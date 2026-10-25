---
title: "ユーザーがログインに使うものを再起動する前の check"
linkTitle: "check"
weight: 30
description: "authnd check が何を開き、設定が提供される前に何を表示するか、その読み方、そして check には見えない唯一の失敗。"
tags: [authnd, チェック, 設定]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check` は設定をサーバーとまったく同じように読み込み、**待ち受けを始める前にサーバーが
開くものをすべて開き**ます。ファイル、データベース、この背後にあるディレクトリ、ID プロバイダーの
ディスカバリードキュメント、TLS 証明書と鍵、キータブです。そして、何が誰に向けて公開されるかを、
**待ち受けることなく**表示します。すべての認証情報について出どころは表示しますが、
中身は決して表示しません。終了コード 0 で、*this configuration can be served* で終わるか、
終了コード 1 で、サーバーを止める一文を出力します。

## 提供できる設定 {#a-configuration-that-can-be-served}

二つの `user` ブロック、一つの reader、一つの SQLite データベースを、二つのファイル
(`authnd.hcl` と `people.hcl`) を含むディレクトリで構成した例です。

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## 読み方 {#reading-it}

最初の行は、スキーム、アドレス、ベースです。`ldap://`、`ldaps://`、`ldap+starttls://` の
いずれかで、[TLS]({{< relref "/authnd/tls.md" >}})を参照してください。

| 列 | |
|---|---|
| `FROM` | その名前を所有するソース: *the configuration file*、*a sqlite database* (または postgres、mysql)、またはこの背後にあるディレクトリの URL |
| `CAN PROVE` | *a password* (保持しているので比較でき、そこから鍵を導出できる)、*a password check* (別のディレクトリが可否を答える)、*an NT hash*、*N keys*、*a one-time-code secret*、または *nothing* |
| `PUBLISHED AS` | `top` を除いたエントリのオブジェクトクラス。[各形態]({{< relref "/authnd/entries.md#the-shapes" >}})が示すとおりです。スキーマに適合しないエントリの場合は *NOT PUBLISHED (see below)* |
| `WITH` | エントリが持つ属性。検索が返すエントリから読み取ったもの: `uid`、クラスが許す場合の `cn`、ソースが与えたもの (破棄されたものを除く)、鍵がある場合の `sshPublicKey`、[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) が有効で、その人が NT 鍵と SID を持つ場合の `sambaSID` と `sambaNTPassword` |

グループの表にも `PUBLISHED AS` 列があり、`posixGroup`、`groupOfNames`、`organizationalRole` の
いずれかです。v0.10.2 までは、`PUBLISHED AS` は属性のリストで、ほぼ全員が *uid and cn* であり、
`WITH` 列はありませんでした。

表の後の行は、設定に頼る前に知っておくべきことを伝えます。まず、
[エントリ]({{< relref "/authnd/entries.md" >}})について。

- **`posixAccount` ではない人**と、`uidNumber`、`gidNumber`、`homeDirectory` のうち
  足りないもの
- **`gidNumber` のないグループ**と、代わりに何として公開されるか
- **破棄されたすべての属性**。そのエントリのどのクラスもそれを許さないためで、どのクラスなら
  許すか
- **公開されないすべてのエントリ**と、スキーマ検証で見つかったそれぞれの問題
- **NT 鍵を持つが `sambaSID` がない人**。したがって `sambaNTPassword` もない

次に、バインドと検索について。

- **バインドが運ぶもの**: *a password*、[`mfa` ブロック]({{< relref "/authnd/mfa.md" >}})がある場合は
  *a password with a 6-digit code after it*、[`oidc` ブロック]({{< relref "/authnd/tokens.md" >}})がある場合は
  トークンの出どころとその経路
- **パスワードではまったくバインドできない人**: NT ハッシュしか知られていない人。
  [人々]({{< relref "/authnd/people.md#written-in-the-configuration" >}})を参照
- **検索できる人**: reader、または *no reader is declared: nothing may
  search, and binds are not affected*
- **`sambaNTPassword` が公開されるかどうか**と、その経路。
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})を参照
- [`kerberos` ブロック]({{< relref "/authnd/kerberos.md" >}})がある場合は、レルムと
  **チケットを発行できる人とできない人**、その理由
- `mfa` ブロックがある場合は、**第二要素のない人**、したがってパスワードでバインドできない人。
  横に `oidc` ブロックがある場合、その行には、`amr` が二種類を示すトークンならそれでも通る
  という注記が加わります
- **どのソースにもいない人を名指しするグループ**

最後のものはそのまま公開されます。ある一つのシステムの窓口が、別のシステムが所有する名前を
正当に持つことがあるためです。ただし知らされます。もう一つの解釈は誤字だからです。
`posixGroup` では、その見知らぬ人は `memberUid` です。`groupOfNames` では、ここにあるどの
エントリも指さない `member` DN で、ここでは `member: uid=zoe,ou=people,dc=example,dc=org` が
それにあたり、go-authn/directory の `ldapdir` は v0.14.0 からこれを誰にも対応付けません。
ここではデータベースの `team_members` テーブルに `zoe` の行があり、`zoe` はここでは誰でもありません。

```
GROUP      MEMBERS              PUBLISHED AS
engineers  dora, eli and zoe    groupOfNames
staff      alice, bob and dora  groupOfNames
[...]
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(見知らぬ人を名指しする `group` *ブロック*は、完全に拒否されます。
[人々]({{< relref "/authnd/people.md#written-in-the-configuration" >}})を参照してください。)

## 拒否されるもの {#what-it-refuses}

以下のいずれも、`check` とサーバーの両方を、終了ステータス 1 で止めます。それぞれ
関連するページで説明しています。いくつかを出力のまま示します。

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## 証明書、キータブ、そして check に見えない唯一のこと {#the-certificate-the-keytab-and-the-one-thing-it-cannot-see}

読み込めない証明書と、`krbtgt/REALM` のないキータブは、サーバーが使うのと同じ言葉で
`check` に拒否されます。

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

待ち受けなしには `check` が知り得ないのは、**ポートが空いているかどうか**です。同じ Kerberos
アドレスで動く二つ目のサーバーは `check` を通り、起動時に拒否されます。

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## サービスアカウントとして実行する {#run-it-as-the-service-account}

```sh
sudo -u authnd authnd check /etc/authnd
```

root しか読めないファイルが、再起動時ではなくここで失敗するようにするためです。
アップグレードの前に、**新しい**バイナリで実行してください。
[インストール]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}})を参照してください。
