---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "SAML フェデレーションの手前に置く OpenID Connect プロバイダー: 人々は自分の所属機関でログインし、アプリケーションはトークン、SSH 証明書、X.509 クライアント証明書を受け取る。"
tags: [authn-bridge, oidc, saml]
---

**人々は自分の大学で、RENATER の Fédération Éducation-Recherche または eduGAIN を通じて
ログインし、アプリケーションは OpenID Connect トークンを受け取ります。**
同じログインで、SSH 鍵に証明書を発行したり、NFS over TLS 用の X.509 クライアント証明書を
発行したり、SMB と S3 用のアプリケーションパスワードを設定したり、WireGuard 鍵を登録したり
することもできます。プロバイダーは自分が発行したものを失効でき、失効させたものの署名付き
リストを公開します。すでに渡されたアクセストークンは、期限が切れるまで有効なままです。
純粋な Go、`CGO_ENABLED=0`、単一のバイナリ。これらのページは v0.23.1 を説明しています。

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.1

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

v0.20.0 より前は、コマンド名は `bridge` でした。これは iproute2 の `/sbin/bridge` でもあり、
ほぼすべての Linux システムにインストールされていて、`PATH` で先に見つかったほうが勝って
いました。モジュールパスは今も `github.com/go-authn/bridge` です。

## なぜブリッジか {#why-a-bridge}

研究フェデレーションは SAML を話します。そのメンバーは、機関ごとに一つ、数百の ID
プロバイダーで、フェデレーションが公開する署名付きメタデータに列挙されています。今日書かれる
アプリケーションは OpenID Connect を求め、一つのプロバイダーを信頼します。authn-bridge はその
一つのプロバイダーです。片側では、フェデレーションに一度登録された SAML サービスプロバイダー、
もう片側では OpenID プロバイダーです。

ゲートウェイは、その背後のすべてのアプリケーションに対して、全員が誰であるかを決めます。
そのため、このプログラムの大半は拒否です。フェデレーションが署名していないメタデータ、
別の機関のドメインの誰かを名指しするアサーション、IdP に権限のないグループ、そしてこれらの
いずれかを通してしまう設定を拒否します。安全に提供できない設定では起動しません。

## 起動時に出力されるもの {#what-it-prints-at-startup}

```
$ authn-bridge --config etc/bridge-admin.hcl
authn-bridge v0.23.0: http://127.0.0.1:28473 on 127.0.0.1:28473
metrics on 127.0.0.1:28475
admin API on unix:///tmp/authn/run/admin.sock
```

これはループバック上のテスト用プロバイダーです (`http://` の発行者はループバックホストでのみ
受け入れられます)。待ち受けを始める**前に**、フェデレーションのメタデータを取得します。
機関を一つも挙げられないプロバイダーは、誰もそこを通ってログインできないので、メタデータが
なければ起動せずに終了します。

## 次に読むもの {#where-to-go-next}

| | |
|---|---|
| [インストール]({{< relref "/authn-bridge/install.md" >}}) | ユーザー、ディレクトリ、systemd ユニット、鍵 |
| [設定]({{< relref "/authn-bridge/configuration.md" >}}) | すべてのブロック、`check`、起動時に拒否されるもの |
| [フェデレーション側]({{< relref "/authn-bridge/federation.md" >}}) | メタデータ、その署名者のフィンガープリント、スコープ、IdP が主張してよいこと |
| [トークン]({{< relref "/authn-bridge/tokens.md" >}}) | ID トークン、アクセストークン、デバイスグラント、アプリケーションパスワード、WireGuard 鍵 |
| [リソースインジケーター]({{< relref "/authn-bridge/resources.md" >}}) | クライアントのリソースサーバーのうち、一度に一つ宛てのトークン (RFC 8707) |
| [証明書]({{< relref "/authn-bridge/certificates.md" >}}) | SSH 証明書、EuroHPC プロファイル、NFS 向け X.509 クライアント証明書 |
| [失効]({{< relref "/authn-bridge/revocation.md" >}}) | 署名付き KRL と CRL、そして Shared Signals トランスミッター |
| [管理 API]({{< relref "/authn-bridge/admin.md" >}}) | 人や機関の無効化、ヘルスとメトリクス |

署名するリストは、通常の `sshd` や TLS サーバー向けに
[authn-revokd]({{< relref "/authn-revokd/_index.md" >}})が読み、
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)は
自身でそれを確認します。

## 何ではないか {#what-it-is-not}

- **単一のプロセス。** `state` ブロックがあれば、リフレッシュトークンと `/userinfo` で承認される
  アクセストークンは再起動後も残ります。進行中のログイン、コード、デバイスグラントは残りません。
  状態は書き込みと同時に保存され、起動時に読み込まれるので、一つのデータベースに二つの
  インスタンスがあると、それぞれが相手の書いたものを見落とします。
- 動的クライアント登録はなく、フロントチャネルやバックチャネルのログアウトもありません。
- 追加するユーザーやグループはありません。人々は所属機関が保証するから存在し、そのグループは
  機関が主張するものです。

## ライセンス {#licence}

BSD-3-Clause。
