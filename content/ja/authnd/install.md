---
title: "authnd のインストール"
linkTitle: "インストール"
weight: 10
description: "リリースバイナリとその検証方法、authnd アカウント、systemd ユニットとそれが許可するもの、そしてアップグレード、ロールバック、削除。"
tags: [authnd, インストール, systemd]
---

リポジトリには、systemd ホストが必要とする二つのファイルが含まれています。
`packaging/sysusers.d/authnd.conf` (アカウント) と
`packaging/systemd/authnd.service` (ユニット) です。このページは、その両方と周辺の手順を
説明します。go-pkgx のバージョン付きサービスが将来これを代行する予定ですが、まだ存在しません。

## リリースバイナリ {#the-release-binary}

各タグは、linux、darwin、windows の amd64 と arm64 向けに `authnd-<os>-<arch>`
(windows では `.exe`) を、`CGO_ENABLED=0` でビルドして公開します。`SHA256SUMS` マニフェストと、
すべてのバイナリのビルド来歴証明も付きます。

```sh
version=v0.13.0
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

どちらかの検証に失敗したら、そこで止めてください。リリースワークフローは、公開するタグと
正確に同じバージョンを報告しないバイナリの公開を拒否するので、バージョンは比較の材料になります。

```
$ authnd --version
authnd version v0.13.0
```

### 必要なものだけをビルドする {#building-only-what-you-want}

サーバーは常に含まれます。二つのビルドタグで、人々の出どころを省けます。`-tags nosql` は
三つのデータベースドライバー (pgx 経由の PostgreSQL、MySQL/MariaDB、modernc.org/sqlite 経由の
SQLite) と `users "sql"` ブロックを除きます。`-tags noldap` は LDAP クライアントと
`users "ldap"` ブロックを除きます。バイナリがビルドされた際に含まれていなかったブロックを
指名した設定には、ブロックが存在しないとは告げず、*this binary was built without SQL support
(-tags nosql)* のように告げます。リリースバイナリはタグなしでビルドされています。

## アカウント {#the-account}

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

sysusers.d による静的アカウントで、`DynamicUser=` では**ありません**。authnd が読むファイル、
つまりパスワードファイル、DSN、キータブ、TLS 鍵は、あらかじめ `authnd` グループに与えられた
シークレットであり、[パスワードの変更]({{< relref "/authnd/passwords.md" >}})はそこに書き戻します。
動的な uid はサービスが起動するまで存在せず、それが書いたファイルは、後に別の誰かを意味する
番号のものになってしまいます。

二つのファイルはリリースタグの `packaging/` ディレクトリにあり、バイナリと同じバージョンです。
そのタグのチェックアウトから、または v0.13.0 の場合は
<https://github.com/go-authn/authnd/tree/v0.13.0/packaging> から、
そのディレクトリをバイナリの隣にコピーしてください。

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## ユニットが許可するものとその理由 {#what-the-unit-grants-and-why}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

ユニットの残りは通常の堅牢化です (`ProtectHome`、`PrivateTmp`、`PrivateDevices`、
`ProtectProc=invisible`、カーネルと cgroup の保護、`MemoryDenyWriteExecute`、
`SystemCallFilter=@system-service`、`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`)。
**含めていない**三つのものは意図的です。

| | |
|---|---|
| `ExecReload=` | authnd にはリロードがありません。設定、証明書、キータブを一度だけ読み込みます。[運用]({{< relref "/authnd/operations.md" >}})を参照 |
| `PrivateUsers=` | ユーザー名前空間の内部では、`CAP_NET_BIND_SERVICE` はホストのネットワークに適用されなくなり、389 へのバインドが拒否されます |
| `ProcSubset=pid` | Go が `net/core/somaxconn` を読む `/proc/sys` を隠してしまい、すべてのリスナーのバックログが Go のフォールバックである 128 に下がります |

`IPAddressAllow=`/`IPAddressDeny=` も設定されていません。どのネットワークがディレクトリに
問い合わせてよいかは、ドロップインで、サイトが決めることです。

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

唯一のケーパビリティは特権ポートのためのものです。LDAP 389、LDAPS 636、そして UDP と TCP の
Kerberos 88 です。同じマシン上の PostgreSQL や MariaDB は、読み取り専用のファイルシステムでも
許されるソケット経由で到達されます。状態ディレクトリ `/var/lib/authnd` は SQLite データベース
のためのものです。authnd 自身は状態を持ちません。第二要素のロックアウトのカウントはメモリ上に
あり、再起動のたびにリセットされます。

## 設定ディレクトリ {#the-configuration-directory}

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

内部のすべてのファイルは `root:authnd`、モード `0640` にします。シークレットはインラインではなく、
`*_file` キーで指名したファイルに入れます。ファイルにはパーミッションがありますが、
誰かが貼り付けた設定にはありません。`ProtectSystem=strict` の下では、サービスは `/etc` 以下に
書き込めません。それは設定にとっては正しく、人々が自分で変更するパスワードにとっては誤りです。
パスワード用には専用のディレクトリを与えてください。

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

ファイルではなくそのディレクトリを使う理由は、
[パスワードの変更]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}})
で説明しています。

| キー | 既定値 | |
|---|---|---|
| `base_dn` | — (必須) | ツリーのルート。例: `dc=example,dc=org`。`=` を含まない値は拒否されます |
| `listen` | `127.0.0.1:3893` | 一つのアドレス。既定ではループバックです。起動した途端にすべてのインターフェースに現れるディレクトリは、誰かが意図して決めるべきことです。LDAP と LDAPS の両方が必要なサイトは、二つのインスタンスを動かします |
| `reader "<dn>"` | なし | 検索できるサービスアカウント。[誰が読めるか]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})を参照 |
| `refresh` | `60s` | すべてのソースを読み直す間隔。`0` で無効。[運用]({{< relref "/authnd/operations.md" >}})を参照 |
| `max_age` | 未設定 | 提供中のデータがこれより古くなったら、古いデータを拒否 (`unavailable`)。[運用]({{< relref "/authnd/operations.md" >}})を参照 |
| `cert_file`、`key_file`、`starttls`、`publish_nt_hash`、`samba` | オフ | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`、`group`、`users` | — | [人々]({{< relref "/authnd/people.md" >}})。`user` または `users` ブロックが少なくとも一つ必要 |
| `kerberos` | なし | [レルム]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | なし | [第二要素]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | なし | [バインド時のトークン]({{< relref "/authnd/tokens.md" >}}) |

設定内の相対パスは、設定ファイルのあるディレクトリではなく、プロセスが動いているディレクトリを
基準に解決されます。ユニットは `/` から実行されるので、パスは絶対パスで書いてください。

起動のたびに、事前に実行します。

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check` は[専用ページ]({{< relref "/authnd/check.md" >}})で説明しています。
`authnd` として実行すると、そのアカウントがすべてのファイルを読めることも確認できます。

## アップグレード、ロールバック、削除 {#upgrade-roll-back-remove}

古いバイナリを置き換える前に、**新しい**バイナリで設定を check し、古いほうは保管してください。
新しいバイナリは、まず古いものの隣にインストールします。そうすれば実行可能になり、
`authnd` アカウントが実行できる場所に置かれます。

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

新しいタグの `packaging/` を、インストール済みのものと比較してください (v0.12.0 のものは
v0.11.1 のものと同じで、変更はありません)。ロールバックは、`authnd.previous` から同じように
インストールして再起動するだけです。

v0.10.x から v0.11.0 への場合、上記の `check` が重要な手順です。`publish_nt_hash = true` で
[`samba` ブロック]({{< relref "/authnd/tls.md#the-samba-block" >}})がない設定は、再起動時では
なくそこで拒否され、表の後の行が、もはや `posixAccount` でなくなる人と、もはや `posixGroup` で
なくなるグループを知らせます
([エントリ]({{< relref "/authnd/entries.md" >}}))。

⛔ v0.11.1 から v0.12.0 への場合は、他に何をするにせよアップグレードしてください。v0.11.1 の
リリースバイナリは Go 1.27.2 でビルドされており、GO-2026-6809 (crypto/x509) の影響を受けますが、
Go 1.27.3 でビルドされた v0.12.0 は受けません。設定の変更は不要です。サイト独自のスキーマを
提供するには、[サイトスキーマ]({{< relref "/authnd/schemas.md" >}})を参照し、
systemd ユニットの作業ディレクトリは `/` なので、ファイルは絶対パスで指定してください。

削除するには:

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`、`/var/lib/authnd`、`authnd` アカウントはそのまま残ります。前の二つには人々の
認証情報が入っており、再利用された uid には他人のファイルが渡されかねないためです。
削除は意図して行ってください。
