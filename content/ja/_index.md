---
title: "go-authn"
linkTitle: "ホーム"
type: docs
cascade:
  type: docs
description: "純粋な Go による認証: 本人がその場にいることを証明する要素、その人が誰であるかを示すディレクトリ、Kerberos の両側、そして SAML フェデレーションの手前に置く OpenID Connect プロバイダー。"
---

**二つの問いがあり、同じものではありません。** *この人は今ここにいるか。* は
*この人は誰で、何がその人を証明するか。* とは別の問いです。go-authn は両方に答えます。
在席を証明する要素、パスワード欄ではなく各人を**証明するもの**を保持するディレクトリ、
Kerberos の両側、そして SAML フェデレーションの手前に置く OpenID Connect プロバイダーです。
純粋な Go、`CGO_ENABLED=0`。
これらのページは、[ステータスのページ]({{< relref "/status.md" >}})に挙げたリリースを説明しています。

## 四つのプログラム {#four-programs}

| | 概要 | これらのページが説明するバージョン |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | 別の場所で管理されている人々、つまりファイル、SQL データベース、別のディレクトリにいる人々のための LDAP サーバーと、任意で Kerberos レルム | v0.12.0 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | SAML フェデレーション (RENATER、eduGAIN) の手前に置く OpenID Connect プロバイダー。SSH 証明書の発行と、それを失効させるリストへの署名も行う | v0.23.3 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | それらのリストを取得し、サーバーが読む前に一つずつ検証し、期限が切れたものがあればフェイルクローズする | v0.6.5 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`。証明書のドメイン許可がこのホストを指しているかどうかを sshd が問い合わせる | v0.1.7 |

いずれも Linux、macOS、Windows 向け (amd64 と arm64) の単一の静的バイナリで、
`SHA256SUMS` とビルドの来歴を付けて公開されています。
[ダウンロードの検証]({{< relref "/security/verifying-releases.md" >}})。

```sh
go install github.com/go-authn/authnd@v0.12.0
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.5
```

コマンド名が `authn-*` (と `authnd`) なのは、他のものも動いているマシンに
インストールされるためです。`/usr/bin` に素の `bridge` や `revokd` を置くと、
他の誰かが必要とするかもしれない名前を奪ってしまいます。

## その下にあるライブラリ {#and-the-libraries-under-them}

プログラムは薄い層です。実際の処理は
[十四のモジュール]({{< relref "/libraries/_index.md" >}})にあり、問いごとに一つずつ分かれています。
そのため、Kerberos チケットを*受け入れる*だけのサービスは KDC をリンクせず、
ワンタイムコードを検証するだけのサービスはディレクトリをリンクしません。

## ディレクトリが人を証明するものを保持する理由 {#why-the-directory-carries-what-proves-somebody}

SMB には NT ハッシュが必要です。S3 にはパスワードそのものが必要です。SigV4 がそこから
HMAC を計算するためです。Kerberos レルムにはパスワードから導出した鍵が必要で、
NT ハッシュはその鍵ではありません。これらのうち一つしか持たない ID は、
本人が何を入力しても、あるプロトコルには対応でき、別のプロトコルには決して対応できません。
そこで go-authn のディレクトリは**各人が何を証明できるか**を記録し、
`authnd check` は、何かを再起動する前に、誰に Kerberos チケットを発行でき、
誰には決して発行できないかを表示します。

```
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

これは authnd v0.11.0 自身の出力です。[全体はこちら]({{< relref "/authnd/check.md" >}})。

## 他者のツールによる検証 {#judged-by-other-peoples-tools}

プロトコルの一つの解釈から作ったフィクスチャは、その解釈を確認することしかできません。
そのためサーバーは、自分たちが書いていないクライアントによって読まれます。
OpenLDAP 純正の `ldapsearch` が authnd にバインドし、MIT 純正の `kinit` がそのレルムから
チケットを受け取り、OpenSSH が authn-bridge の発行する証明書と KRL を読み込みます。
