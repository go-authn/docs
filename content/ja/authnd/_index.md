---
title: "authnd、別の場所にいる人々のための LDAP サーバー"
linkTitle: "authnd"
weight: 10
description: "設定ファイル、SQL データベース、または別のディレクトリに保持された人々を対象とする LDAP ディレクトリと、任意の Kerberos レルム。"
tags: [authnd, ldap]
---

**組織の人々はすでにデータベース、ファイル、または別のディレクトリにいます。
その人々を認証したいものは LDAP を話します。** authnd はその窓口です。
[go-authn/directory]({{< relref "/libraries/_index.md" >}}) のソースに対してバインドと検索を行うので、
データベースが保持しているものを、ディレクトリに問い合わせる方法を知っているものなら何でも読めます。
純粋な Go、`CGO_ENABLED=0`、単一のバイナリ。これらのページは v0.12.3 を説明しています。
そのエントリは標準スキーマに従い、`cn=Subschema` で公開するスキーマに適合します。
サイトはこのスキーマを自前のもの
([SUPANN、eduPerson]({{< relref "/authnd/schemas.md" >}})) で拡張できます。
その下には go-authn/ldap v0.10.1 と go-authn/directory v0.15.0 があります。
何が検証済みで何が未検証かは、[ステータス]({{< relref "/status.md" >}})のページにあります。

{{< callout type="warning" >}}
**v0.11.x からのアップグレード**

- ⛔ **セキュリティ: v0.11.1 ではなく v0.12.0 を使ってください。** v0.11.1 のリリースバイナリは
  Go 1.27.2 でビルドされており、その crypto/x509 は GO-2026-6809 が挙げる侵害された
  中間証明書を信頼から外しません。authnd は証明書を検証します。v0.12.0 は Go 1.27.3 で
  ビルドされ、その `go` ディレクティブは 1.27.3 なので、`go install` は修正済みの
  ツールチェーンへ自動的に切り替わります。
- 新しいキーを使わない設定は、v0.11.1 が公開していたものをそのまま公開します。
  クラスは宣言されるもので推論されないため、`object_classes` がなければ何も変わりません。
- 新規で、すべて任意: [`schema_files` と `schema` ブロック]({{< relref "/authnd/schemas.md" >}})は
  サイトの定義を提供されるスキーマに追加し、`object_classes` と `group_object_classes` は
  ソースの人々とグループが持つ補助クラスを宣言します。すでにある定義を再定義する定義は、
  slapd が拒否するのと同様に、一語一句同じであっても拒否されます。
- `check` と起動時のログは、どのファイルとブロックが読み込まれたか、各ソースが何を宣言するか、
  MUST が足りないために人から外されたクラスはどれか、二つのソースの意見が食い違うグループは
  どれかを知らせます。

再起動の前に、
[インストール]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}})にあるとおり、
新しいバイナリで `authnd check` を実行してください。
{{< /callout >}}

{{< callout type="warning" >}}
**v0.10.x からのアップグレード**

- `publish_nt_hash = true` には [`samba` ブロック]({{< relref "/authnd/tls.md#the-samba-block" >}})が必要になりました。
  なければ authnd は起動しません。
- `uidNumber`、`gidNumber`、`homeDirectory` のない人はもはや `posixAccount` ではなく、
  `gidNumber` のないグループはもはや `posixGroup` ではありません。そのため、これらのクラスで
  絞り込むコンシューマーに見えるエントリが減ります。
  [エントリ]({{< relref "/authnd/entries.md" >}})を参照してください。
- `users "ldap"` ブロックは、既定でその先のディレクトリをより広く読むようになりました。
  [人々]({{< relref "/authnd/people.md#in-another-ldap-directory" >}})を参照してください。

新しいバイナリでの `authnd check` は、再起動の前にこの三つすべてを知らせます。
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## 最小の設定 {#the-smallest-configuration}

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

人々は `uid=<name>,ou=people,<base_dn>`、グループは `cn=<name>,ou=groups,<base_dn>` として
公開されます。各エントリが*何であるか*は、ソースが与えたものから決まります。人は
`account` になり、`sn` があれば `inetOrgPerson` になり、`uidNumber`、`gidNumber`、
`homeDirectory` がそろっている場合にのみ `posixAccount` になります。すべての人は
`uidObject` です。グループは、`gidNumber` があれば (`memberUid` を持つ) `posixGroup`、
なければ (`member` DN を持つ) `groupOfNames` になり、さらに空であれば
`organizationalRole` になります。人が鍵を持っていれば `sshPublicKey` が追加され、
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) が指示し、
かつ SID を与えられる場合は `sambaNTPassword` が追加されます。すべてのエントリは、
公開される前に `cn=Subschema` で公開されるスキーマに照らして検証されます。
[エントリとスキーマ]({{< relref "/authnd/entries.md" >}})を参照してください。
v0.10.2 までは、持っているものにかかわらず、すべての人が `posixAccount`、
すべてのグループが `posixGroup` でした。

`--config` (`-c`) はファイルまたはディレクトリを受け取り、複数回指定できます。ディレクトリは
その中のすべての `.hcl` ファイルを意味し、名前順に読み込まれて一つの設定にマージされます。
`base_dn` がない設定、または誰もいない設定では起動しません。

## 誰がバインドでき、誰が読めるか {#who-may-bind-and-who-may-read}

LDAP サーバーは人々を証明するよう求められるので、その拒否こそが設計です。
以下は v0.12.3 のリリースバイナリが OpenLDAP 純正のクライアントに返した応答です。

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| リクエスト | 応答 | 理由 |
|---|---|---|
| 空の名前、空のパスワード (RFC 4513 §5.1.1、匿名) | 成功 | 「私は誰でもない」と言っており、それは事実です。クライアントは何かを探索する前にこれを送ります |
| **名前**があり、パスワードが空 (§5.1.2、未認証) | `unwillingToPerform` | 誰かの名前を挙げながら何も証明していません。§5.1.2 はまさにこのコードを求めています。`invalidCredentials` では、パスワードが間違っていたと本人に伝えてしまいます |
| 間違ったパスワード、またはここにいない人の名前 | `invalidCredentials` | この二つは区別されません |
| `reader` 以外による検索 | `insufficientAccessRights` | バインドは自分が誰であるかを証明するだけです。全員を読むことは、別に許可されるべきことです |
| `add`、`delete`、`modifyDN` | `unwillingToPerform` | ハンドラーが接続されていません。唯一の書き込みは[本人自身のパスワード]({{< relref "/authnd/passwords.md" >}})です |

`reader` は、バインド DN と `password` または `password_file` を持つサービスアカウントです。
どちらも持たない reader は起動時に拒否されます (*何も証明しない reader は、手間が増えただけの
匿名検索です*)。reader が一つもなければ、何も検索できず、`check` がそのことを知らせます。

ルート DSE は、探索に必要なため、匿名のクライアントにも応答されます。

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.12.3
```

`1.3.6.1.4.1.4203.1.11.1` は RFC 3062 のパスワード変更操作です。
`subschemaSubentry` は[スキーマ]({{< relref "/authnd/entries.md#the-schema-it-serves" >}})を指しており、
これも匿名のクライアントに応答されます。
`supportedSASLMechanisms: OAUTHBEARER` は、[`oidc` ブロック]({{< relref "/authnd/tokens.md" >}})がある場合にのみ表示されます。

## 次に読むもの {#where-to-go-next}

| | |
|---|---|
| [インストール]({{< relref "/authnd/install.md" >}}) | リリースバイナリ、`authnd` アカウント、systemd ユニット、アップグレード |
| [人々の出どころ]({{< relref "/authnd/people.md" >}}) | `user` と `group` ブロック、SQL データベース、別の LDAP ディレクトリ |
| [エントリとスキーマ]({{< relref "/authnd/entries.md" >}}) | 各人とグループが何として公開されるか、`cn=Subschema`、属性、破棄または保留されるもの |
| [サイトスキーマ]({{< relref "/authnd/schemas.md" >}}) | `schema_files`、`schema` ブロック、`object_classes`: SUPANN、eduPerson、またはサイト独自の属性 |
| [`check`]({{< relref "/authnd/check.md" >}}) | 再起動する前に設定を読み戻す |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` または StartTLS、そして `publish_nt_hash` |
| [パスワードの変更]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`、`ldapmodify`、そして古いパスワードを常に求める理由 |
| [Kerberos レルム]({{< relref "/authnd/kerberos.md" >}}) | キータブ、そしてチケットを発行できる人 |
| [第二要素]({{< relref "/authnd/mfa.md" >}}) | パスワードの末尾に付けるワンタイムコード |
| [バインド時のトークン]({{< relref "/authnd/tokens.md" >}}) | SASL `OAUTHBEARER` 上の OIDC |
| [運用]({{< relref "/authnd/operations.md" >}}) | シグナル、再起動、ログの内容、稼働しているかの確認方法 |

{{< callout type="info" >}}
**トランスクリプトについて**

これらのページに示したコマンドはすべて、2026-10-26 に公開済みのリリースバイナリで再実行したもので、手で書き直したものではありません。`authnd` v0.12.3 (`authnd-darwin-arm64`、`relverify` で `SHA256SUMS` とその証明 (attestation) を照合済み、`go version -m`: `go1.27.3`、`mod github.com/go-authn/authnd v0.12.3`、`vcs.modified=false`)、`authn-bridge` v0.23.4、`authn-revokd` v0.6.6、`sshcert-authorize` v0.1.9、`ldapschema` v0.10.1 です。コマンドが出力したものが、そのままここに載っています。例外は 2 つのトランスクリプトで、それぞれ載っている場所にその旨を書いてあります。[トークンのページ]({{< relref "/authnd/tokens.md" >}})の `oidctool` クライアントは、これらのページのために書いたテスト用クライアントでどのリリースにも含まれず、そのトランスクリプトと添えたサーバー側の行は v0.10.0 のリリースバイナリが出力したものです。もう 1 つは[フェデレーションのページ]({{< relref "/authn-bridge/federation.md" >}})にある RENATER の期限切れメタデータで、このファイルはもう公開されていません。すべて macOS に付属する OpenLDAP と Heimdal のクライアントで、127.0.0.1 の特権のないポートを使い、作業用ディレクトリで実行しました。そのため、これらの背後にある設定は `etc/authnd/passwords/alice.pw` のような相対パスでファイルを指定し、パスワードファイルには `alice.pwin` のような名前が付いています。例にある `/etc/authnd` のパスは、インストール済みのサーバーが使うものです。
{{< /callout >}}
