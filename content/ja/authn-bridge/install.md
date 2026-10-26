---
title: "authn-bridge のインストール"
linkTitle: "インストール"
weight: 10
description: "静的ユーザー、三つのディレクトリ、堅牢化した systemd ユニット: リリースバイナリから稼働するサービスまでの authn-bridge。"
tags: [authn-bridge, インストール, systemd]
---

リポジトリには、ユニットとそれが動作するユーザーが含まれています。
`packaging/systemd/authn-bridge.service` と
`packaging/sysusers.d/authn-bridge.conf` です。以下は、特に断りがない限りすべて root で実行します。

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | バイナリ |
| `/etc/authn-bridge/*.hcl` | 設定。名前順に読み込まれる。`root:authn-bridge`、`0750`、ファイルは `0640` |
| `/var/lib/authn-bridge/` | 鍵、サブジェクトソルト、SQLite の状態、発行済み証明書、無効化リスト。`authn-bridge`、`0700` |
| `/run/authn-bridge/` | 設定が求める場合の管理ソケット |

## バイナリ {#the-binary}

リリースには、Linux、macOS、Windows の amd64 と arm64 向けの `authn-bridge-<os>-<arch>`、
`SHA256SUMS` マニフェスト、バイナリごとのビルド来歴証明が含まれます。
[ダウンロードの検証]({{< relref "/security/verifying-releases.md" >}})に両方の確認方法が
あります。あるいはビルドすると、バージョンがバイナリに記録されます。

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.4
go: github.com/go-authn/bridge@v0.23.4 requires go >= 1.27.3; switching to go1.27.3
$ authn-bridge --version
authn-bridge version v0.23.4
```

パスが重要です。v0.20.0 からプログラムは `internal/app` に、コマンドは `cmd/authn-bridge` に
あるので、`go install github.com/go-authn/bridge@...` では何もビルドされません。

## ユーザーと、動的ユーザーではない理由 {#the-user-and-why-it-is-not-a-dynamic-one}

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

ユニットは `DynamicUser=` ではなく `User=authn-bridge` を指定しています。署名鍵、サブジェクト
ソルト、SAML 鍵、認証局は、最初の起動の**前に**作られ、何年も使われ、再インストールや
バックアップからの復元をまたいで同じ所有者を保たなければなりません。動的ユーザーは、
サービスの起動時に UID を得ます。

## 鍵 {#the-keys}

`keygen` はサービスのユーザーとして実行し、書き込むものを自分で所有するようにしてください。
すでにあるファイルの上書きは拒否されます。

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPnW/W/MeVAMgt4fciWbbiJ/BS4vXURfwoc7K5cET1Ma go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

サーバーではパスは `/var/lib/authn-bridge` 以下になり、コマンドは
`runuser -u authn-bridge -- authn-bridge keygen ...` です。

| フラグ | 書き込むもの | 用途 |
|---|---|---|
| `--key` | RSA 3072 鍵 | ID トークン (RS256)。`/jwks` で公開される |
| `--salt` | ランダムな 32 バイト | すべての `sub`。その下の HMAC である |
| `--access-token-key` | P-256 鍵 | 代わりに ES256 で署名されるアクセストークン。ずっと短い |
| `--ssh-ca` | OpenSSH 形式の Ed25519 鍵 | [SSH 証明書]({{< relref "/authn-bridge/certificates.md" >}})と KRL の署名 |
| `--x509-ca DIR` | `DIR/ca.key` (P-256) と `DIR/ca.crt`。有効期間十年、パス長 0 | NFS クライアント証明書と CRL |

{{< callout type="warning" >}}
**ソルトをバックアップし、決して変更しないこと**

新しいソルトは、すべての人に新しい `sub` を与え、すべてのリライングパーティーが新しい人を
見ることになります。アンインストール時に削除した場合も同じです。
{{< /callout >}}

SAML の鍵と証明書は `openssl` で作ります。これらはフェデレーションが登録し、すべての IdP が
暗号化の宛先とするものです。鍵は RSA でなければなりません (IdP は RSA-OAEP でそれに対して
暗号化します)。これは TLS 証明書ではなく、TLS 証明書とともに変わることもありません。

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

フェデレーションのメタデータ署名証明書はフェデレーションから入手し、その SHA-256
フィンガープリントも同様です。フィンガープリントはフェデレーションのウェブページから取り、
証明書と同じダウンロードからは決して取らないでください。
[フェデレーション側]({{< relref "/authn-bridge/federation.md" >}})を参照してください。

## ユニット {#the-unit}

許可するものを簡潔に:

- `Type=exec`、`Restart=on-failure`、`RestartSec=5s`、`TimeoutStopSec=20s`。
  プロバイダーは `SIGTERM` から十秒以内にリスナーを停止します。
- `StateDirectory=`、`RuntimeDirectory=` (どちらも `0700`)、`ConfigurationDirectory=`
  (`0750`)、`UMask=0077`。`ProtectSystem=strict` により、それ以外はすべて読み取り専用です。
- ケーパビリティなし (`CapabilityBoundingSet=` と `AmbientCapabilities=` は空)、
  `NoNewPrivileges=`、`PrivateUsers=`、`PrivateTmp=`、`PrivateDevices=`、`PrivateIPC=`、
  `ProtectHome=`、カーネル、クロック、ホスト名、コントロールグループの保護。
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`: リスナー、メタデータ、ACME CA、
  データベースには TCP、管理 API にはソケット。
- `SystemCallFilter=@system-service` から `@privileged @resources` を除いたもので、強制終了
  ではなく `EPERM` で拒否されます。

メタデータはプロバイダーが待ち受けを始める前に取得されるので、`network-online.target` を
待ちます。

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

ジャーナルの最初の行は、[概要]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}})に
示したものです。

### 変更には再起動が必要 {#changes-need-a-restart}

設定は一度だけ読み込まれます。ユニットには `ExecReload=` がないので、`systemctl
reload` は、できるふりをせずに拒否されます。`SIGHUP` (logrotate や習慣による) は捕捉され、
ログに記録され、無視されます。Go の既定のままだとプロセスを終了させ、systemd はそれを
`Restart=on-failure` が再起動しない正常終了と数えてしまいます。

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

TLS 証明書ファイルは例外です。変更されると再読み込みされます。

### ポート 443 {#port-443}

既定のリスナーは TLS リバースプロキシの背後にある `127.0.0.1:8080` で、ケーパビリティは不要
です。プロバイダー自身がポート 443 で TLS を提供する場合 (`cert_file` または `acme`)、
`CAP_NET_BIND_SERVICE` が必要で、プライベートなユーザー名前空間から出なければなりません。
その内部で保持されたケーパビリティは、ホストのネットワークには適用されないためです。

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## アップグレードと、元に戻すこと {#upgrading-and-going-back}

まず `/var/lib/authn-bridge` をバックアップしてください。鍵とソルトが入っていて、作り直せません。
動作するバイナリを保管し、新しいものをインストールして、再起動します。

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

元に戻すには、`authn-bridge.previous` で同じことをします。新しいリリースには新しいユニットが
付属している場合があります。あなたのものと比較し、インストールして、再起動の前に
`systemctl daemon-reload` を実行してください。

### `bridge` からの移行 {#coming-from-bridge}

設定は変わりません。コマンドとリリースアセットの名前だけが変わりました。`bridge` を実行する
すべてのユニット、スクリプト、cron ジョブ、`bearer_token_command` を変更してください。ログの
行とエラーのプレフィックスは `authn-bridge` となるので、`bridge v0.` に一致していたアラートは
`authn-bridge v0.` に一致させる必要があります。メトリクス名 (`bridge_*`)、`bridge_state`
テーブル、ユーザー側のキャッシュ (ユーザーの設定ディレクトリ内の `go-authn-bridge`、Linux では
`~/.config`) は変わらないので、`authn-bridge token` は `bridge` がキャッシュしたログインを
再利用します。
