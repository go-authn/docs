---
title: "ライブラリ、一つにつき一つの問い"
linkTitle: "ライブラリ"
weight: 50
description: "十四の go-authn Go モジュール: それぞれが答える問い、これらのページが説明するバージョン、そして別々のモジュールである理由。"
tags: [ライブラリ]
---

[authnd]({{< relref "/authnd/_index.md" >}}) や [authn-bridge]({{< relref "/authn-bridge/_index.md" >}})
のようなプログラムは、単独で公開、バージョン管理、テストされるモジュールから組み立てられています。
各モジュールは**一つ**の問いに答え、プログラムは自分が問う問いのモジュールをインポートします。

すべて純粋な Go で、`CGO_ENABLED=0` でビルドできます。

| モジュール | 答える問い | これらのページが説明するバージョン | インポートパス |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | 十分な要素が、十分な種類で答えたか。どれが答えたか | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | この六桁のコードは正しいか。以前に使われたことはないか | v0.4.2 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | 64 バイトのレポートで、セキュリティキーとどう話すか | v0.6.2 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | *登録された*鍵が答えたか。人がそれに触れたか | v0.4.2 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | ある人は誰で、何がその人を証明できるか | v0.15.0 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | LDAP サーバーのバイト列とは何か | v0.11.0 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | この Kerberos チケットはこのサービスに有効か | v0.3.1 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | レルムはディレクトリからどうチケットを発行するか | v0.4.3 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | このベアラートークンは誰が尋ねていると述べ、それを信じるべきか | v0.4.1 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | フェデレーションの ID プロバイダーは、この人について何と述べたか | v0.4.1 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | この SSH 証明書または鍵は、sshd が答えるとおりに失効しているか | v0.6.1 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | デーモンの TLS サーバー証明書はどこから来るか | v0.5.2 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | この WireGuard 鍵は接続してよいか。誰のものか | v0.1.1 | `github.com/go-authn/wireguard` |
| [scim]({{< relref "/libraries/scim.md" >}}) | ID プロバイダーが作成、変更、削除したのは誰か | v0.1.0 | `github.com/go-authn/scim` |

## グループ分け {#how-they-group}

**要素** — 人がその場にいるかどうか。
[mfa]({{< relref "/libraries/mfa.md" >}}) はどれだけの証明で十分かを判断し、デバイスについては何も
知りません。[totp]({{< relref "/libraries/totp.md" >}}) は一つの要素、つまり電話のコードです。
[fido]({{< relref "/libraries/fido.md" >}}) はセキュリティキーに CTAP で話しかけ、ポリシーについては
何も知りません。[keyfactor]({{< relref "/libraries/keyfactor.md" >}}) は両方をインポートする唯一の
部品で、鍵を要素に変えます。

**ディレクトリとそのプロトコル。**
[directory]({{< relref "/libraries/directory.md" >}}) はモデルです。人と、ソースがその人について保持
する認証情報、つまりパスワード、NT ハッシュ、検証器、SSH 鍵、ワンタイムコードのシークレット、
そしてそれらとは別に、その人を説明するだけで何も証明しない属性です。
[ldap]({{< relref "/libraries/ldap.md" >}}) は、サーバーとしての LDAP ワイヤープロトコルと、エントリを
検証できるディレクトリスキーマです。スキーマは OpenLDAP のファイルから読むか、HCL2 で書きます。
何に答えるかはハンドラーの仕事です。

**Kerberos の二つの半分。** [krb5]({{< relref "/libraries/krb5.md" >}}) はチケットを*受け入れ*ます。
キータブ、入ってくる AP-REQ、出ていく AP-REP です。[kdc]({{< relref "/libraries/kdc.md" >}}) は、
パスワードを保持するディレクトリからチケットを*発行*します。

**フェデレーションとトークン。** [saml]({{< relref "/libraries/saml.md" >}}) は、RENATER や eduGAIN
のようなフェデレーションの手前に置く SAML 2.0 サービスプロバイダーです。
[oidc]({{< relref "/libraries/oidc.md" >}}) はプロバイダーが署名する OpenID Connect トークンを検証します。
ログインフローのないリソースサーバー側の半分です。
[scim]({{< relref "/libraries/scim.md" >}}) は逆方向です。ID プロバイダーが、アプリケーションの
人々とグループを作成、更新、削除するために呼び出す SCIM 2.0 エンドポイントです。

**失効と証明書。** [krl]({{< relref "/libraries/krl.md" >}}) は OpenSSH の鍵失効リストを読み、書き、
確認します。[servercert]({{< relref "/libraries/servercert.md" >}}) はデーモンに TLS 証明書を、
ファイルまたは ACME から与えます。

**[wireguard]({{< relref "/libraries/wireguard.md" >}})** は、人々がプロバイダーに登録した WireGuard
公開鍵の署名付きリストを運び、ゲートウェイがそれをピアに変えます。

## 別々のモジュールである理由 {#why-they-are-separate-modules}

**チケットを受け入れるだけのサービスは、KDC を決してリンクしません。** NFS サーバーはクライアントが
提示するチケットを検証します。持っているのはキータブで、レルムについて他にすることはありません。
受け入れと発行が一つのモジュールだったら、そのようなサーバーはすべて、決して実行しない
チケット発行のコードパスと、KDC が人々を読むのに使い自分では使わないディレクトリモジュールを
抱えることになります。

これは意図ではなく、測定です。`github.com/go-authn/krb5@v0.3.1` だけをインポートする作業用
モジュールで:

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.1
```

`github.com/go-authn/kdc@v0.4.3` をインポートするモジュールで同じコマンドを実行すると、
`github.com/go-authn/directory` と `github.com/go-authn/kdc` が列挙されます。発行には人々が
必要で、受け入れには必要ありません。

同じ規則が他にも当てはまります。`mfa` は標準ライブラリ以外を何もインポートせず、`fido` は `mfa` を
インポートしません。鍵を点滅させたいだけのプログラムが、ポリシーパッケージを抱えることは
ありません。`totp` が依存するのは `mfa` だけで、`oidc` は依存関係がまったくありません。
`directory` は LDAP、SQL、HCL のソースをサブパッケージに分けています。コアパッケージは標準
ライブラリ以外を何もインポートせず、`sqldir` は `*sql.DB` を受け取るので、データベースドライバーは
プログラムが選びます。

## すべてのページは同じ構成 {#every-page-has-the-same-parts}

問い、説明するバージョンの `go get` の行、そのバージョンに対してコンパイルできる最小限の例、
コードから読み取った、モジュールが拒否するもの、そして何に対して検証されているか、つまり
CI やテストで名指しされている、このモジュールではない実装です。README とコードが食い違う場合、
ページはコードに従います。
