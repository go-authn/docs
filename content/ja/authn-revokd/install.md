---
title: "authn-revokd のインストール"
linkTitle: "インストール"
weight: 10
description: "堅牢化した systemd サービスとして、またはタイマーでのワンショットとしての authn-revokd と、sshd や TLS サーバーをその書き込み先に接続する方法。"
tags: [authn-revokd, インストール, systemd]
---

リポジトリは `packaging/` に三つのユニットとアカウントを含んでいます。
`authn-revokd.service` (デーモン)、`authn-revokd-once.service` と
`authn-revokd-once.timer` (代替手段)、そして `sysusers.d/authn-revokd.conf` です。

| パス | 内容 | 所有者、モード |
|---|---|---|
| `/usr/local/bin/authn-revokd` | バイナリ | root、`0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | `authn-revokd` システムアカウント | root、`0644` |
| `/etc/systemd/system/authn-revokd.service` | デーモン | root、`0644` |
| `/etc/authn-revokd/revokd.hcl` | 設定。`-config` の既定値 | root、`0644` |
| `/etc/authn-revokd/ca/` | リストが署名されていなければならない CA の鍵と証明書 | root、`0755`。中のファイルは `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`、唯一の書き込み可能な場所 | authn-revokd、`0755` |
| `/var/lib/authn-revokd/state/` | `state_dir`: 検証済みのコピー | authn-revokd、`0700` |
| `/var/lib/authn-revokd/sshd.krl` | 出力: `sshd` が読むもの | authn-revokd、`0644` |

**出力は `/var/lib/authn-revokd` に書き込み、サーバーをそこに向けてください。** 出力は最終的な
名前の隣に書き込まれてからリネームで上書きされるので、その*ディレクトリ*が書き込み可能で
なければなりません。`/etc/ssh` を書き込み可能にすると、`authn-revokd` アカウントが `sshd_config` を
置き換えられるようになってしまいます。出力は `0644` で、`UMask=0077` にもかかわらず明示的に
chmod されるので、独自のユーザーで動く `sshd` と TLS サーバーが読めます。状態は `0700` のままです。

## バイナリ、アカウント、ユニット {#the-binary-the-account-the-unit}

リリースには、Linux、macOS、Windows の amd64 と arm64 向けの `authn-revokd-<os>-<arch>` が、
`SHA256SUMS` とビルド来歴とともに含まれます
([ダウンロードの検証]({{< relref "/security/verifying-releases.md" >}}))。あるいは
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.5` です。

アカウントとユニットはリリースタグの `packaging/` ディレクトリにあり、バイナリと同じバージョン
です。そのタグのチェックアウトから、または v0.6.5 の場合は
<https://github.com/go-authn/revocation/tree/v0.6.5/packaging> から、そのディレクトリを
バイナリの隣にコピーしてください。

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

アカウントは静的で、`DynamicUser=` ではありません。authn-revokd は、自身の uid か root 以外が
所有する状態ディレクトリを拒否し、状態は再起動とアップグレードをまたいで次のリストの順序を
決め続けなければなりません。動的ユーザーでは、ファイルは `/var/lib/private` の下に置かれ、
root の `0700` になり、独自のユーザーで動く TLS サーバーが CRL を読めなくなります。

## デーモン {#the-daemon}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

そしてその周囲に: `User=authn-revokd`、ケーパビリティなし、`NoNewPrivileges=`、
`ProtectSystem=strict` と、唯一の書き込み可能な場所である `StateDirectory=authn-revokd`
(`0755`)、`PrivateUsers=`、`PrivateTmp=`、`PrivateDevices=`、`PrivateIPC=`、
`AF_INET AF_INET6 AF_UNIX` のみ、`@system-service` のシステムコールから
`@privileged @resources` を除いたもの。

**`Restart=always` なのは、sshd が KRL の有効期限を無視するためです。** リストが失効したとき、
ファイルは*このプロセス*によってフェイルクローズされます。停止している間、sshd は最後に書き込まれた
ファイルを読み続け、その間に発行された失効は届きません。ユニットを監視するか、ミラーが有効なら
`/healthz` を監視してください。

**`systemctl reload` は今すぐ同期します。** `SIGHUP` を送り、エージェントは次の `refresh` を待たずに
すべてのソースを取得します。

```
hangup: syncing now
```

設定は再読み込みされません。設定は起動時に一度だけ読み込まれるので、`revokd.hcl` を変更した後は
`systemctl restart authn-revokd` です。(v0.6.0 より前は、捕捉されない `SIGHUP` がプロセスを
終了させ、systemd はそれを正常終了と数えていました。)

### sshd を接続する前に有効にする {#enable-it-before-wiring-sshd}

{{< callout type="warning" >}}
**`RevokedKeys` が存在しないファイルを指していると、sshd はすべての証明書を拒否する**

そのため、まず authn-revokd を起動し、出力ができるまで待ってください。
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl` が、すべてのソースが現在のものである間、
コメント `authn-revokd sshd` を出力します。
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

その後、`/etc/ssh/sshd_config` に:

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

そして `sshd -t && systemctl reload ssh`。sshd は認証のたびに `RevokedKeys` を読むので、
authn-revokd がファイルを書き換えたときにリロードは不要です。アトミックなリネームで十分です。

### TLS サーバーの CRL {#a-tls-servers-crl}

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

TLS サーバーは設定を読み込むときに CRL を読むので、ファイルが変わったらリロードしなければ
なりません。`on_change` コマンドは `authn-revokd` アカウントとして実行され、`systemctl reload nginx`
はできません。代わりに systemd にファイルを root として監視させてください。出力に対する
`PathChanged=` を持つパスユニットが、`systemctl reload nginx` を実行する `oneshot` を起動します。

## または: タイマーでの `-once` {#or--once-on-a-timer}

`authn-revokd -once` は一度同期して終了し、リストが現在のものでない、または取得できなかった場合は
`1` で終了します ([`-once` が報告するもの]({{< relref "/authn-revokd/verification.md#what--once-reports" >}}))。
出力はどちらの場合も書き込まれ、リストが失効すると sshd 向けにフェイルクローズされます。

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

ワンショットはデーモンのアカウントと堅牢化を持ちます。`TimeoutStartSec=5min` は、あるソースで
ハングした同期が次のティックより長生きするのを防ぎ、`RandomizedDelaySec=10s` は、一緒に起動した
複数台が足並みをそろえて発行者をポーリングするのを防ぎます。

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**両方を有効にしないでください。** ユニットは競合するので、一方を起動するともう一方が停止します。
デーモンのほうが優れた選択です。失効したリストを次の `refresh` でフェイルクローズしますが、
タイマーは次のティックを待ちます。そしてミラーとして提供できるのはデーモンだけです。`listen` は
`-once` では無視されます。発火を止めたタイマーは、停止したデーモンと同じなので、
`systemctl status authn-revokd-once` を監視してください。

## アップグレードと、元に戻すこと {#upgrading-and-going-back}

新しいバイナリを古いものの隣にインストールし、入れ替えて、再起動します。状態は引き継がれます。
検証済みのコピーが次のリストの順序を決め続けるので、アップグレードでも古いバイナリへの
ロールバックでも、古いリストが入り込むことはありません。

## アンインストール {#uninstalling}

まず、サーバーの設定から `RevokedKeys` と `ssl_crl` を削除し、リロードしてください。
ファイルがなくなると、sshd はすべての証明書を拒否します。
