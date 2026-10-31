---
title: "人々の出どころ"
linkTitle: "人々"
weight: 20
description: "user と group ブロック、SQL データベース、別の LDAP ディレクトリ: それぞれの書き方、問い合わせの順序、そして各々が人に許すこと。"
tags: [authnd, 設定, sql, ldap]
---

`user` ブロックは、小規模なサイトにとってはディレクトリのすべてであり、大規模なサイトにとっては
データベースの外に置いておくサービスアカウントです。人々がすでにデータベースや LDAP にいる
サイトは、陳腐化する二つ目の場所にそれをコピーすべきではないので、`users` ブロックは
人々をそのある場所で読みます。`users` ブロックは go-authn/directory の `hcldir` で、
[go-fileshare](https://github.com/go-fileshare/fileshare) が読むものと同じです。
一つのディレクトリが、両方に対して同じように記述されます。

## 設定に書く {#written-in-the-configuration}

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| フィールド | 内容 |
|---|---|
| `password` | インラインのパスワード |
| `password_file` | 同じものをファイルから読む (前後の空白は除去) |
| `nt_hash` | `MD4(UTF16LE(password))`、16 進 32 文字。パスワードではなくそれを保持しているサイト向け |
| `totp_secret` | base32 のワンタイムコードのシークレット、128 ビット以上。[第二要素]({{< relref "/authnd/mfa.md" >}})を参照 |
| `authorized_keys` | `authorized_keys` の行。`sshPublicKey` として公開される |
| `authorized_keys_file` | 同じものをファイルから |
| `attributes` | v0.11.0 から。人を説明するだけで何も証明しないもの — `sn`、`uidNumber`、`gidNumber`、`homeDirectory`、`mail`… — を、文字列または文字列のリストのマップとして指定する。`group` ブロックも受け付ける。エントリが何として公開されるかを決める。[エントリ]({{< relref "/authnd/entries.md#adding-attributes" >}})を参照 |
| `object_classes` | v0.12.0 から。この人 (`group` ブロックでは、このグループ) が公開される際の補助クラス。たとえば `["siteMember"]`。宣言されるもので推論されず、[サイトスキーマ]({{< relref "/authnd/schemas.md#object-classes" >}})で定義される |

起動時に、その人の名前を挙げて拒否されるもの:

- `password` と `password_file` の併用 — どちらかを指定してください
- `password` と `nt_hash` の併用 — ハッシュはパスワードから導出されるので、二つあると
  食い違いかねません
- `authorized_keys` と `authorized_keys_file` の併用
- 16 進 32 文字でない `nt_hash`、解析できない `authorized_keys` の行、128 ビット未満の `totp_secret`
- 同じ `user` または `group` の重複、メンバーのいない `group`

どのソースも知らないグループメンバーも拒否されます。これにより、何も付与しないまま黙って
通ってしまう誤字が捕まります。

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**`nt_hash` だけではバインドできない**

`nt_hash` のみで書かれた人は、公開され、`sambaNTPassword` を通じて SMB サーバーに渡すことが
できますが、**authnd 自身にはバインドできません**。LDAP の単純バインドはパスワードを送り、
NT ハッシュはここではそれを検証する手段ではないからです。以下の bob は NT ハッシュしか
持たず、そのハッシュは送られたパスワードのものです。

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check` は表の後でそのことを告げます。

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```

**設計上、拒否される理由。** NT ハッシュは `MD4(UTF16LE(password))` で、ソルトがなく高速です
(MS-NLMP §3.3.1、NTOWFv1)。LDAP バインドの検証にそれを受け入れると、漏えいしたハッシュが開く
範囲が、SMB から authnd を通じてバインドするすべてのアプリケーションに広がってしまいます。
Kerberos がこれらの人々を拒否するのは関連した理由からです。NT ハッシュは RC4-HMAC 鍵
(RFC 4757 §2) であり、レルムは AES のみを発行します。これは欠けている機能ではなく意図的な
決定であり、変更するオプションはありません。

**代わりにすべきこと。** NT ハッシュしか保持していないディレクトリ (Samba、エクスポートした AD)
から移行する場合は、各人のソースに本物のパスワードか、パスワードの検証手段を与えてください。
パスワードのリセット、またはパスワードを自ら検証する上流ディレクトリを指す `users "ldap"`
ソースです。NT ハッシュを唯一の認証情報として残さないでください。
{{< /callout >}}

## SQL データベースで {#in-a-sql-database}

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**クエリはあなたのものです。** サイトの人々はすでにそのサイトの形でそこにあるからです。
`users` クエリの列は**位置で**読まれます。名前、続いてパスワード、NT ハッシュ、SSH 鍵
(一行に一つ)、ワンタイムコードのシークレットのいずれか、この順序で、最大五列です。
NULL は、その人が持たない認証情報です。パスワード列は保存されたとおりに比較されます。
authnd にはハッシュ化された列のための設定はありません。`groups` クエリは、グループ名とメンバーを
所属ごとに一行で返します。

さらに二つの任意のクエリが、属性を位置ではなく**列のエイリアスで**読みます。
`users_attributes` (名前、続いて属性ごとに一列) と `groups_attributes` (グループ、続いて同様)
です。引用符のないエイリアスは PostgreSQL によって小文字にされます。
[エントリ]({{< relref "/authnd/entries.md#in-a-sql-database" >}})を参照してください。

**`users` ブロックが与えるもののクラス**は、そのクエリの横で宣言します
(v0.12.0 から、`users "ldap"` ブロックでも同じ二つのキーが使えます)。

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]   # every person this block gives
  group_object_classes = ["supannGroupe"]                # every group
}
```

それぞれは、提供されるスキーマ (標準スキーマ、または
[`schema_files` と `schema` ブロック]({{< relref "/authnd/schemas.md" >}}))が定義する
AUXILIARY クラスでなければならず、authnd が自ら導出するクラスであってはなりません。
宣言されたクラスの MUST が足りない人は、そのクラスなしで公開され、`check` がそれを知らせます。

`driver` は `postgres` (または `postgresql`、`pgx`)、`mysql` (または `mariadb`)、
`sqlite` (または `sqlite3`) を受け付けます。データベースには、何かが待ち受けを始める前の
起動時に接続するので、応答しないデータベースがあれば、誰かが見ている場でサーバーが止まります。

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

同じマシン上の PostgreSQL にソケットとピア認証で接続する場合、DSN にパスワードは不要です。
`host=/run/postgresql dbname=authnd user=authnd`。状態ディレクトリ内の SQLite は
`file:/var/lib/authnd/people.db` です。

もう一方の種類のブロックに属するキーは、無視されずに拒否されます。

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## 別の LDAP ディレクトリで {#in-another-ldap-directory}

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url` と `base_dn` は必須です。人々とグループの場所と、それらを名付ける属性は次のとおりです。

| キー | 既定値 |
|---|---|
| `user_filter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))` |
| `group_attribute` | `cn` |
| `group_member_attribute` | なし: `memberUid` (名前)**と** `member` (DN)。設定すると、それが読まれる唯一の属性になる |
| `totp_attribute` | なし: 標準の属性がなく、推測では何も読まないのに読んだように見えてしまう |
| `attributes`、`group_attributes` | なし: 各人のエントリと各グループのエントリからコピーする属性。`["mail", "uidNumber", "homeDirectory"]` と `["gidNumber"]` など ([エントリ]({{< relref "/authnd/entries.md#adding-attributes" >}})) |
| `object_classes`、`group_object_classes` | なし: v0.12.0 から、このディレクトリから読まれるすべての人とすべてのグループが公開される際の補助クラス ([サイトスキーマ]({{< relref "/authnd/schemas.md#object-classes" >}}))。上流のエントリが持つクラスはコピーされない |
| `start_tls` | `false` |

`member` DN が数えられるのは、人々の検索が返したエントリの DN である場合だけです。それらの外の
DN や誰も指さない DN は誰にも対応付けられず、名前が DN から読み取られることは決してありません。
`sambaNTPassword` と `sshPublicKey` は、その名前のまま読まれます。

{{< callout type="warning" >}}
**v0.11.0 から、既定値は組織のディレクトリをより広く読む**

このブロックは go-authn/directory のもので、authnd v0.11.0 が組み込む directory v0.14.0 は既定値を
広げました。v0.10.2 までは、`user_filter` は `(objectClass=posixAccount)`、`group_filter` は
`(objectClass=posixGroup)`、`group_member_attribute` は `memberUid` でした。posixAccount ではない
`account` や `uidObject` のエントリ — サービスアカウント、uid で名付けられたホスト、他から
取り込まれた人々 — を持つディレクトリは、それらを authnd に渡すようになり、そのそれぞれを
バインドで検証できます。`groupOfNames` のグループは、ここでのグループになります。
以前とまったく同じ集合を保つには、以前の値を書いてください。

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

何かが開かれる前に、二つのことが拒否されます。

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

ループバックアドレスへの `ldap://` と `ldapi://` は受け入れられます。途中に誰もいないからです。

この背後にあるディレクトリは、パスワードをそこへのバインドによって**検証**します。パスワードを
引き渡すことはありません。ここでは、一つの authnd が別のベースの下で別の authnd の窓口に
なっています。背後にあるのは、3893 で提供される
[`check`]({{< relref "/authnd/check.md#a-configuration-that-can-be-served" >}})の例です。

```hcl
listen  = "127.0.0.1:3894"
base_dn = "dc=example,dc=net"

users "ldap" {
  url                = "ldap://127.0.0.1:3893"
  base_dn            = "ou=people,dc=example,dc=org"
  group_base_dn      = "ou=groups,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "etc/authnd/reader.pw"
}

user "svc-backup" { password_file = "etc/authnd/svc-backup.pw" }
```

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS        WITH
alice       ldap://127.0.0.1:3893   a password check  account, uidObject  uid
bob         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
dora        ldap://127.0.0.1:3893   a password check  account, uidObject  uid
eli         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
svc-backup  the configuration file  a password        account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
svc-backup has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

背後のディレクトリが公開するすべての人は `account`、すべてのグループは `groupOfNames` です。
どれも POSIX 属性を持たないためで、既定値がそれらを読み、グループの `member` DN は取り込まれた
人々に対応付けられます。v0.10.2 までの既定値では、`(objectClass=posixAccount)` はそれらの
どれにも一致しなかったでしょう。

*A password check* はバインドには十分ですが、
[Kerberos チケット]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})や SMB には
決して十分ではありません。

## 順序と、唯一の例外 {#order-and-the-one-exception}

ソースは**書かれた順序で**問い合わせられ、ある名前を最初に知っているものがそれを所有します。
`user` ブロックは常に最初に来るので、ローカルに書かれたサービスアカウントが、データベースに
ある同名の誰かに上書きされることはありません。**グループのメンバーシップはすべてのソースの
和集合**です。`group` ブロックとデータベースの `groups` クエリの両方が名指しするグループは、
両方のメンバーを持ちます。

{{< callout type="warning" >}}
**大文字小文字だけが異なる二つの名前は拒否される**

uid は大文字小文字を無視して比較され (RFC 4519 §2.39)、すべての DN も同様です。そのため
ファイルの `Dora` とデータベースの `dora` は、LDAP にとっては一つの名前で、バイトを比較する
ものにとっては二人の人です。一方によるパスワード変更が他方に及んでしまいます。そのような
設定は起動しません。

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## 起動時に読み込み、以後は更新のたびに読み直す {#read-once}

すべてのソースは**起動時に読み込まれ、その後も `refresh` ごとに読み直されます**。データベースに
追加または削除された人や、この背後にあるディレクトリで変更されたメンバーシップは、再起動なしで
1 周期以内に反映されます。これにはデータベースのパスワード列も含まれ、行と共に読み込まれます。
この背後にあるディレクトリが違うのは、バインドがそこへのバインドによって検証される点だけで、
そのため*そこで*変更されたパスワードが有効になります。人が authnd 自体を通じて
変更したパスワードは、[直ちに反映されます]({{< relref "/authnd/passwords.md" >}})。
失敗した更新は最後に正常だったデータを保ち、いつ提供をやめるかは `max_age` で決まります。
[運用]({{< relref "/authnd/operations.md" >}})を参照してください。設定ファイル、証明書、
keytab は今も再起動が必要です。
