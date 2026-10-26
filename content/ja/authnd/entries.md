---
title: "authnd が公開するエントリと、提供するスキーマ"
linkTitle: "エントリとスキーマ"
weight: 25
description: "各人とグループが何として公開されるか、すべてのエントリが適合する cn=Subschema のスキーマ、ファイルまたは SQL クエリで属性を追加する方法、そして破棄または保留されるもの。"
tags: [authnd, ldap, スキーマ, sql]
---

**authnd が公開するすべてのエントリは、自身が提供するスキーマに適合します。** v0.11.0 からは、
各人とグループが標準スキーマのエントリとなり、ソースが与えたものから組み立てられ、
検索で返される前に、クライアントが `cn=Subschema` で読めるスキーマに照らして
go-authn/ldap の `schema.Validate` で検証されます。スキーマを読んでそれを信じるクライアント、
つまり LDAP ブラウザー、同期ツール、このディレクトリをレプリケートするディレクトリには、
告げられたとおりのものが見えます。v0.10.2 までは、すべての人が `top, person, posixAccount` で、
それらのクラスが必須とする属性は一つもなく、`sambaNTPassword` はそれを許すクラスのない
エントリに載っていました。

{{< callout type="warning" >}}
**`posixAccount` や `posixGroup` で絞り込むコンシューマーには、見えるエントリが減ります**

`uidNumber`、`gidNumber`、`homeDirectory` のない人はもはや `posixAccount` ではなく、
`gidNumber` のないグループはもはや `posixGroup` ではありません。
`(objectClass=posixAccount)` や `(objectClass=posixGroup)` を検索するプログラムは、
それらを見つけられなくなります。これには v0.13.0 までの go-authn/directory の `ldapdir` が含まれ、
したがって directory v0.14.0 を要求するまでの go-fileshare も含まれます。v0.14.0 の既定値は
`account`、`uidObject`、`groupOfNames` も読みます
([directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}}))。
人とグループにそれらの属性を与えるか、コンシューマーを `(objectClass=uidObject)` に向けてください。
すべての人がそれを持っています。
{{< /callout >}}

## 各形態 {#the-shapes}

RFC 4512 §3.3 が求めるとおり、すべてのスーパークラスを列挙しています。

| 次を持つ人… | `objectClass` | `cn` |
|---|---|---|
| `sn` なし | `top`, `account` (RFC 4524 §3.1) | 別のクラスが許す場合のみ |
| `sn` あり | `top`, `person`, `organizationalPerson`, `inetOrgPerson` (RFC 4519, RFC 2798) | あり |
| … さらに `uidNumber`、`gidNumber`、`homeDirectory` の三つすべて | `+ posixAccount` (RFC 2307) | あり |
| … さらに SSH 鍵 | `+ ldapPublicKey` (openssh-lpk)、`sshPublicKey` を伴う | |
| … さらに `sambaSID` を伴う公開された NT ハッシュ | `+ sambaSamAccount` (Samba)、`sambaSID` と `sambaNTPassword` を伴う: [`samba` ブロック]({{< relref "/authnd/tls.md#the-samba-block" >}})を参照 | 許可 |
| … 常に | `+ uidObject` (RFC 4519 §3.14)。そのため `(objectClass=uidObject)` で全員が見つかる | |

| 次を持つグループ… | `objectClass` | メンバー |
|---|---|---|
| `gidNumber` あり | `top`, `posixGroup` (RFC 2307) | `memberUid`、名前 |
| `gidNumber` なし、メンバーあり | `top`, `groupOfNames` (RFC 4519 §3.5) | `member`、このサーバーが公開する DN |
| `gidNumber` なし、メンバーなし | `top`, `organizationalRole` (RFC 4519 §3.10) | なし |
| `gidNumber` あり、メンバーなし | `top`, `posixGroup` | なし: 属性には少なくとも一つの値が必要 |

`uid` は人の名前で、クラスが許す場合は `cn` も同じです。`account` 単独では `cn` を許さない
(その MAY は `description`、`seeAlso`、`l`、`o`、`ou`、`host`) ため、`sn` がなく POSIX の三つ組も
ない人は、`uid` を持ち `cn` を持ちません。

これらの選択の理由を、authnd 自身の言葉で示します。

- **`posixGroup` は RFC 2307 に従い、draft-howard-rfc2307bis-02 には従いません。**
  このドラフトは `posixGroup` を AUXILIARY にしており、未公開のまま失効しました。AUXILIARY の
  `posixGroup` には構造クラスが必要で、それは `groupOfNames` ですが、空のグループは
  その `member` を与えられません。
- **`gidNumber` のない空のグループには `organizationalRole`。**
  `groupOfNames` と `groupOfUniqueNames` はどちらもメンバーを必須とし、メンバーをでっち上げる
  方法はどれも偽りです。`member: ""` はルート DSE を指し、グループ自身の DN を入れると
  自分自身のメンバーになってしまいます。`organizationalRole` は、唯一の MUST が `cn` である
  標準の構造クラスで、`groupOfNames` と同様に `description`、`ou`、`seeAlso` を受け付けます。
- **DIT コンテンツルールのない補助クラス。** RFC 4512 §2.4.3 は、構造クラスに DIT コンテンツ
  ルールがないエントリに補助クラスを付けることを禁じています。実用されているディレクトリ
  サーバーはすべてそれを許しており、`Validate` も同様です
  (`ValidateOptions{StrictAuxiliary: true}` が厳格な読み方で、authnd はそれを設定しません)。
  構造クラスにコンテンツルールが**ある**場合は、v0.13.0 からそれに従わされます。
  [ルール]({{< relref "/authnd/schemas.md#rules" >}})を参照してください。

## 属性の追加 {#adding-attributes}

ソースが誰かについて述べるもので、何も証明しないもの、たとえば `uidNumber`、ホームディレクトリ、
メールアドレスは**属性**であり、与えられたとおりに公開されます。これは go-authn/directory の
[属性]({{< relref "/libraries/directory.md#attributes" >}})で、v0.13.0 からあり、認証情報とは
切り離されています。シークレットを保持する名前や、サーバー自身が導出する名前は、
何かが読まれる前に拒否されます。

### `user` または `group` ブロックで {#in-a-user-or-group-block}

```hcl
user "dora" {
  password_file   = "/etc/authnd/passwords/dora.pw"
  authorized_keys = ["ssh-ed25519 AAAA… dora@laptop"]
  attributes = {
    sn            = "Explorer"          # inetOrgPerson
    uidNumber     = "1000"              # the three: posixAccount
    gidNumber     = "1000"
    homeDirectory = "/home/dora"
    mail          = ["dora@example.org", "d.explorer@example.org"]
  }
}

group "engineers" {
  members    = ["dora", "eli"]
  attributes = { gidNumber = "2000" }   # a posixGroup; without it, a groupOfNames
}
```

値は文字列または文字列のリストです。`null` はその属性を省きます。数値は拒否されます。
LDAP の値は文字列であり、authnd は数値の綴り方を決めないためです。

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

大文字小文字にかかわらず、同様に拒否されるもの: シークレットを保持するあらゆる名前
(`userPassword`、`sambaNTPassword`、`unicodePwd`、`krbPrincipalKey`、および go-authn/directory の
リストの残り、または `password`、`passwd`、`pwd`、`secret`、`credential`、`hash`、`privatekey`
を含む名前)、`authorized_keys` がある `sshPublicKey`、サーバーが導出する `uid`、`cn`、
`objectClass`、`members` が担う `member`、`memberUid` とその他のメンバーシップ属性、
サーバーが維持する操作属性、そして数値形式の名前 (`2.5.4.35` は `userPassword`) です。

### SQL データベースで {#in-a-sql-database}

`users "sql"` ブロックの二つの任意のクエリは、属性を**列のエイリアスで**読みます。
最初の列は人またはグループの名前で、それ以外のすべての列は、そのエイリアスで名付けられた
属性です。

```hcl
users "sql" {
  driver   = "sqlite"
  dsn_file = "/etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

- 位置で指定する `users` と `groups` のクエリは変わらず、六番目の位置の列は引き続き
  拒否されます。属性は名前で、専用のクエリで渡されます。
- エイリアスが属性記述でない列 (`count(*)` のようなエイリアスのない式) や、認証情報を名指しする
  列は、行が読まれる前に、列番号付きで拒否されます。
- `NULL` と `''` は存在しないものとして扱います。一つの名前が複数の行に現れることがあり、
  そのすべての値が保持されます。そのため、アドレスのテーブルへの結合は、人に複数の値を与えます。
- `groups_attributes` にだけ名前のあるグループは、メンバーがいなくても**存在します**。
  人自身のプライマリグループはそのように書きます。

{{< callout type="warning" >}}
**エイリアスの大文字小文字はデータベース次第です**

PostgreSQL は引用符のないエイリアスを小文字に畳み込みます。`as uidNumber` は `uidnumber` として
返ります。属性名は大文字小文字を区別しないので、同じ属性であり、どの LDAP クライアントにとっても
同じエントリですが、authnd が表示する綴りはデータベースのものです。綴りが重要な場合は
エイリアスを引用符で囲んでください: `gid as "gidNumber"`。SQLite はエイリアスを書かれたとおりに保ちます。
{{< /callout >}}

### 別の LDAP ディレクトリから {#from-another-ldap-directory}

`users "ldap"` ブロックは、指示された属性を、各人のエントリと各グループのエントリからコピーします。
`attributes = ["mail", "uidNumber",
"homeDirectory"]` と `group_attributes = ["gidNumber"]` のように指定します。
[人々]({{< relref "/authnd/people.md#in-another-ldap-directory" >}})を参照してください。

## 設定と、それが公開するもの {#a-configuration-and-what-it-publishes}

上の SQL ブロックに reader を加え、五人と四つのグループを持つ SQLite データベースに対して、
v0.11.0 のリリースバイナリが check した結果です。

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER  FROM               CAN PROVE             PUBLISHED AS                                                                         WITH
dora  a sqlite database  a password and 1 key  person, organizationalPerson, inetOrgPerson, posixAccount, ldapPublicKey, uidObject  uid, cn, sn, uidNumber, gidNumber, homeDirectory, mail and sshPublicKey
eli   a sqlite database  a password            account, posixAccount, uidObject                                                     uid, cn, uidNumber, gidNumber and homeDirectory
fay   a sqlite database  a password            person, organizationalPerson, inetOrgPerson, uidObject                               uid, cn, sn and mail
gus   a sqlite database  a password            account, uidObject                                                                   uid
hal   a sqlite database  a password            account, uidObject                                                                   uid

GROUP       MEMBERS       PUBLISHED AS
alumni      nobody        organizationalRole
engineers   dora and eli  posixGroup
nobody-yet  nobody        posixGroup
readers     fay and gus   groupOfNames

fay has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
gus has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
hal has no homeDirectory: not a posixAccount, published as account, uidObject
hal is published without uidNumber: no class of the entry allows it; posixAccount would
hal is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
hal is published without mail: no class of the entry allows it; inetOrgPerson would
group alumni has no gidNumber and nobody in it: not a posixGroup, published as an organizationalRole (a groupOfNames needs a member)
group readers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

`PUBLISHED AS` は `top` を除いた各エントリのオブジェクトクラスで、`WITH` は検索が返すエントリから
読み取った属性です。hal は `uidNumber`、`gidNumber`、`mail` を持ち、`homeDirectory` と `sn` は
持ちません。hal は `account` であり、この三つのどれも許さないので、それらは破棄され、残りが公開されます。
サーバーも起動時に同じことを述べます (停止されたときは `stopping` と出ます)。

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

reader のパスワードをファイルに入れて、OpenLDAP の `ldapsearch` で読み戻します。

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(|(uid=dora)(uid=eli)(uid=gus)(uid=hal))'
dn: uid=dora,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: ldapPublicKey
objectClass: uidObject
uid: dora
cn: dora
sn: Explorer
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/dora
mail: dora@example.org
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTfVR7FqXWE/0VEcjrUhK+Fz/MLqlwGPIxalr6onRMn dora@laptop

dn: uid=eli,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: uidObject
uid: eli
cn: eli
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/eli

dn: uid=gus,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: gus

dn: uid=hal,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: hal

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=groups,dc=example,dc=org '(objectClass=*)'
dn: cn=alumni,ou=groups,dc=example,dc=org
objectClass: top
objectClass: organizationalRole
cn: alumni
description: people who were here

dn: cn=engineers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: engineers
gidNumber: 2000
memberUid: dora
memberUid: eli

dn: cn=nobody-yet,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: nobody-yet
gidNumber: 2001

dn: cn=readers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
cn: readers
description: people who read
member: uid=fay,ou=people,dc=example,dc=org
member: uid=gus,ou=people,dc=example,dc=org
```

`alumni` は `groups_attributes` にだけ名前があるため、メンバーなしで存在します。`gidNumber` が
ないので `organizationalRole` です。`nobody-yet` は `gidNumber` があり、メンバーがいないので、
`memberUid` のない `posixGroup` です。

どのクラスが誰を見つけるか:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=uidObject)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org

dn: uid=fay,ou=people,dc=example,dc=org

dn: uid=gus,ou=people,dc=example,dc=org

dn: uid=hal,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=posixAccount)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org
```

## 何が破棄され、何が保留されるか {#what-is-dropped-and-what-is-withheld}

| 与えられたもの | エントリ | 理由 |
|---|---|---|
| `uidNumber`、`gidNumber`、`homeDirectory` なし、`sn` なし | `account, uidObject`、この二つなし | *no class of the entry allows it; posixAccount would* |
| `mail`、`sn` なし | `account, uidObject`、`mail` なし | *no class of the entry allows it; inetOrgPerson would* |
| スキーマが定義していない型 | 残りの部分 | *the schema served here does not define it* |
| `gidNumber` のないグループへの `mail` | `groupOfNames`、`mail` なし | |
| POSIX の三つ組と共に二つの `homeDirectory` 値 | **保留**: SINGLE-VALUE であり、破棄できるものがない | |
| 整数でない `gidNumber` | **保留**: その構文に適合しない | |

**破棄されるのはソースが与えたものだけ**で、どの属性が許されないかは `Validate` の答えであり、
スキーマの二度目の解釈ではありません。エントリは破棄の後にもう一度検証されます。それでも
適合しないエントリは**保留**されます。どの検索にも現れず、起動ログがその名前を挙げ、
`check` が `Validate` の見つけたすべての問題とともに一覧します。authnd 自身が導出する属性
(`uid`、`cn`、`objectClass`、`sshPublicKey`、`sambaSID`、`sambaNTPassword`) がスキーマに
拒否された場合は authnd の欠陥であり、その属性なしで公開するのではなく、エントリを保留します。

ここでは alice の `gidNumber` が単語になっています。

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes = {
    uidNumber     = "1000"
    gidNumber     = "staff"
    homeDirectory = "/home/alice"
  }
}

user "bob" { password_file = "etc/authnd/bob.pw" }
```

```
$ authnd check cases/withheld.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS               WITH
alice  the configuration file  a password  NOT PUBLISHED (see below)  uid, cn, gidNumber, homeDirectory and uidNumber
bob    the configuration file  a password  account, uidObject         uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
alice is NOT published: as account, posixAccount, uidObject it fails the schema:
  - the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

提供された場合、alice は引き続きバインドできますが、どの検索にも現れず、サーバーは起動時にその
理由を述べます。

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

保留されるのは検索が返すエントリであって、ID ではありません。

## 提供するスキーマ {#the-schema-it-serves}

ルート DSE がそれを指し (`subschemaSubentry: cn=Subschema`、
[ルート DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})上)、
`cn=Subschema` のベース検索がそれを返します (RFC 4512 §4.2)。go-authn/ldap が組み込む標準の
定義、つまり RFC 4512、4517、4519、4523、4524、2798、2307、3672、3045 と openssh-lpk に加え、
[`samba` ブロック]({{< relref "/authnd/tls.md#the-samba-block" >}})がある場合は Samba の
`sambaSamAccount`、`sambaSID`、`sambaNTPassword` です。定義は、名前を指定するか `+` を
付けて要求した場合にのみ公開されます。印のある箇所は省略しています。

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -s base -b cn=Subschema '+' '*'
dn: cn=Subschema
objectClass: top
objectClass: subentry
objectClass: subschema
cn: Subschema
subtreeSpecification: {}
ldapSyntaxes: ( 1.3.6.1.4.1.1466.115.121.1.3 DESC 'Attribute Type Description' )
[...]
matchingRules: ( 2.5.13.15 NAME 'integerOrderingMatch' SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 )
[...]
attributeTypes: ( 1.3.6.1.1.1.1.0 NAME 'uidNumber' DESC 'An integer uniquely identifying a user in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
attributeTypes: ( 1.3.6.1.1.1.1.1 NAME 'gidNumber' DESC 'An integer uniquely identifying a group in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
[...]
objectClasses: ( 2.5.6.9 NAME 'groupOfNames' SUP top STRUCTURAL MUST ( member $ cn ) MAY ( businessCategory $ seeAlso $ owner $ ou $ o $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.3.1 NAME 'uidObject' SUP top AUXILIARY MUST uid )
objectClasses: ( 0.9.2342.19200300.100.4.5 NAME 'account' SUP top STRUCTURAL MUST uid MAY ( description $ seeAlso $ l $ o $ ou $ host ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.0 NAME 'posixAccount' DESC 'Abstraction of an account with POSIX attributes' SUP top AUXILIARY MUST ( cn $ uid $ uidNumber $ gidNumber $ homeDirectory ) MAY ( userPassword $ loginShell $ gecos $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.2 NAME 'posixGroup' DESC 'Abstraction of a group of accounts' SUP top STRUCTURAL MUST ( cn $ gidNumber ) MAY ( userPassword $ memberUid $ description ) )
[...]
```

エントリ全体は 327 行で、49 の構文、40 のマッチングルール、36 のマッチングルール使用、
143 の属性型、52 のオブジェクトクラスでした。ベース以下の検索と違い、サブスキーマエントリは
ルート DSE と同様に匿名のクライアントにも応答されます。`-D` と `-y` を付けない同じクエリが
それを返しました。

**フィルターはスキーマのマッチングルールを使う**ので、`(uidNumber>=1000)` は整数として比較します。
`uidNumber` と `gidNumber` には `ORDERING
integerOrderingMatch` があり、RFC 2307 はこれを与えていません。slapd と
draft-howard-rfc2307bis-02 は与えており、go-authn/ldap も同様です
([唯一の逸脱]({{< relref "/libraries/ldap.md#the-schema" >}}))。
文字列として扱うと、`1000` は `999` より前に並びます。

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=1000)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=999)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001
```

hal はいません。hal の `uidNumber` は破棄されたためです。`uid` のように ORDERING ルールのない
属性への範囲指定は Undefined となり、何にも一致しません。
