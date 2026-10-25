---
title: "TLS: ldaps:// または StartTLS、両方同時ではない"
linkTitle: "TLS"
weight: 40
description: "ファイルにある証明書で LDAP を TLS 経由で提供すること、ldaps:// と StartTLS の選択、そして sambaNTPassword がどちらか一方でのみ公開される理由。"
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file` と `key_file` を併せて指定すると TLS が有効になります。片方だけの指定は
拒否されます (*one without the other serves nothing*)。TLS 1.2 が最低限です。
authnd には ACME クライアントがありません。二つのファイルは別のもの、つまり
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}})、certbot、サイト自身の CA が
書き、証明書はリスナーが開く際に一度だけ読み込まれるので、更新のたびに authnd を
**再起動**します。

## 二つの方法、それぞれ一つのリスナー {#two-ways-one-listener-each}

| | `starttls` | リスナー | `check` の表示 |
|---|---|---|---|
| **ldaps://** | 未設定 | LDAP が一バイトも話される前に TLS ハンドシェイクが行われる | `ldaps://…` |
| **StartTLS** | `starttls = true` | 平文で、クライアントが求めたときにアップグレードされる (RFC 4511 §4.14) | `ldap+starttls://…` |

どちらか一方であり、そうでなければなりません。リスナーは、ハンドシェイクを要求することと、
それが求められるかどうかを待つことを同時にはできないからです。サイトがどちらを望むかは
**クライアント**次第です。`ldaps://` の 636 は、ほとんどのクライアントが設定されている先で、
StartTLS は、389 を指して「TLS を使う」にチェックを入れたクライアントが求めるものです。
両方が必要なサイトは、それぞれ独自の `--config` で二つのインスタンスを動かします。
証明書のない `starttls = true` は拒否されます。

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps:// {#ldaps}

サーバー、`127.0.0.1` 用の CA 署名証明書、そしてこのプログラムではないクライアントによって
検証された証明書チェーンです。

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS は、求められるまで拒否する {#starttls-which-refuses-until-it-is-asked-for}

StartTLS を要求するのは**クライアント**なので、提供するだけでは何も約束できません。一度も
求めないクライアントは、平文でバインドしてしまいます。そのため `starttls = true` のリスナーは、
接続がアップグレードされるまで、すべてのバインドとすべての検索を `confidentialityRequired` で
拒否します。

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

(`-ZZ` は「StartTLS を行い、失敗したら失敗とする」です。`LDAPTLS_REQCERT=never` があるのは、
macOS が同梱する `ldapsearch` がシステムストアを信頼し、このテスト用 CA を信頼するよう
指定できなかったためです。チェーンは別途
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error` で確認し、
`Verify return code: 0 (ok)` が返りました。)

この拒否こそが、`cert_file` を提供ではなく保証にするものであり、`publish_nt_hash` が頼りにして
いるものです。ルート DSE を読む前に `ldapsearch -x` が送る匿名バインドも対象なので、StartTLS
リスナーでは、その探索クエリにも `-ZZ` が必要です。

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword` は、Samba や他の SMB サーバーがこのディレクトリを通じて人々を認証できるように
するものであり、ログインフォームが意味する意味でのパスワードハッシュでは**ありません**。
`MD4(UTF16LE(password))` を持つ者は誰でも、パスワードを知ることなく、NTLMv2 でその人として認証
されます。そのため、求められたときだけ公開され、v0.11.0 からは、人々の SID が属するドメインとともに
公開されます。

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

リスナーに TLS がない限り、あるいはループバック (`127.0.0.0/8`、`::1`、`localhost`) で、
したがってネットワークをまったく通らない場合を除き、これを求めると拒否されます。

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### `samba` ブロック {#the-samba-block}

`sambaNTPassword` は Samba の `sambaSamAccount` に属しており、その MUST は `uid` と `sambaSID`
で、他のクラスはこれを許しません。authnd が公開するすべてのエントリは
[提供するスキーマ]({{< relref "/authnd/entries.md" >}})に適合するので、この属性は
`sambaSamAccount` の上でのみ公開され、それには SID が必要です。

| キー | |
|---|---|
| `domain_sid` | 必須: SMB サーバーのドメイン SID、`S-1-5-21-…`。`net getlocalsid` が出力するもの |
| `algorithmic_rid_base` | 任意、既定値は Samba と同じ `1000`。奇数や 1000 未満の値は拒否されます。Samba が黙って別の値を使うためです |

人の `sambaSID` は、ソースが与える場合はその人自身の `sambaSID` 属性です
([属性]({{< relref "/authnd/entries.md#adding-attributes" >}}))。そうでなければ
`domain_sid-RID` で、RID = 2 × `uidNumber` + `algorithmic_rid_base` です。これは Samba の
アルゴリズムによるマッピングです (smb.conf(5)、*algorithmic rid base*)。NT 鍵を持ちながらどちらも
ない人は、`sambaNTPassword` **なしで**公開され、`check` と起動ログが誰かを告げます。Samba の
定義は、このブロックがある場合にのみ `cn=Subschema` で提供されるスキーマに追加されます。それらは
Samba が公開している OID、名前、構文から書かれたもので、GPL-3.0 の `samba.schema` からコピー
したものではありません。

{{< callout type="error" >}}
**v0.10.x の設定には破壊的変更: `samba` ブロックのない `publish_nt_hash` は起動しない**

v0.10.x は `publish_nt_hash = true` だけで提供していました。v0.11.0 からは、その設定は起動時と
`check` で拒否され、何を追加すべきかが示されます。

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

アップグレードする前に、新しいバイナリで `check` を実行してください。拒否するのは意図的です。
v0.10.x のエントリはスキーマに適合できず、二つの静かな代替案、つまり全員から SMB を奪う属性の
破棄と、その人を奪うエントリの破棄は、どちらもコンソールに何も出さずに起きてしまうからです。
{{< /callout >}}

`publish_nt_hash` のない `samba` ブロックも、何も公開しないので拒否されます。

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### `check` が述べること {#what-check-says}

`ldaps://` リスナー上の三人です。alice はパスワードと POSIX の三つ組を持つので、SID が導出され
ます (2 × 1000 + 1000)。bob は NT ハッシュのみで、自身の `sambaSID` を持ちます。carol は
パスワードを持ち、どちらもありません。

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

StartTLS リスナーの場合は *sambaNTPassword is published over TLS, once
StartTLS has been asked for* となります。alice には NT ハッシュが書かれていません。alice のものは
持っているパスワードから導出されます。bob のハッシュは SMB サーバーが使えるよう公開され、
`check` は、bob が authnd 自身にはバインドできないことも述べます。carol のエントリはこの属性
なしで公開され、ソースが carol に `uidNumber` か `sambaSID` を与えるまで、SMB サーバーは carol に
サービスを提供できません。

同じ人々の StartTLS リスナーで、reader に与えられるもの:

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

検索できるのは [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})
だけなので、この属性を目にするのも reader だけです。したがって、誰がそれを読めるかは、
誰が reader のパスワードを持っているかと同じ問いです。

{{< callout type="warning" >}}
**NTLMv2 にはパスワードまたはその MD4 が必要で、他のものでは代わりにならない**

authnd にある人について尋ねるファイルサーバーが SMB でその人にサービスを提供できるのは、
*ソース*がそのために十分なもの、つまりパスワードかハッシュを保持している場合だけです。
パスワードを検証するだけのディレクトリから来る人 — `check` で *a password check* と表示される人 —
には、間で authnd が何をしても、`sambaNTPassword` を与えることは決してできません。
`publish_nt_hash` がなければ、誰にもできません。その場合 `check` は
*sambaNTPassword is not published, so nothing here can authenticate an SMB
session* と述べます。
{{< /callout >}}

## トークンにも必要 {#tokens-need-it-too}

[`oidc` ブロック]({{< relref "/authnd/tokens.md" >}})は、暗号化されていない接続でのトークンを
拒否します。ただし `allow_plaintext = true` で、このプロセスの手前で TLS が終端されていると
示した場合を除きます。
