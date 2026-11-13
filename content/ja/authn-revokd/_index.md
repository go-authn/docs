---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "署名付きの KRL と CRL を取得し、検証に通ったリストだけを保持し、sshd と TLS サーバーが読む場所に書き込み、リストが失効したらフェイルクローズするエージェント。"
tags: [authn-revokd, 失効, krl, crl]
---

**OpenSSH には KRL を配布する手段がなく、KRL の中にそれが古いと示すものもありません。**
`sshd` は、何か月も前に更新が止まったファイルを、現在のリストとして読みます。authn-revokd は、
[authn-bridge]({{< relref "/authn-bridge/revocation.md" >}}) が公開するリストについて、この二つの
隙間を塞ぎます。各リストを取得し、検証に通った場合にのみ保持し、`sshd` や TLS サーバーが読む
場所に書き込み、リストが失効したときは **CA 自体を失効させる**リストを書き込みます。
純粋な Go、`CGO_ENABLED=0`、単一のバイナリ。これらのページは v0.7.0 を説明しています。

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.7.0
go: downloading github.com/go-authn/revocation v0.7.0
$ authn-revokd --version
authn-revokd v0.7.0
$ authn-revokd --help
authn-revokd fetches revocation lists, keeps only those that verify, writes
them where sshd and TLS servers read them (failing closed for sshd when a list
lapses) and, with listen, serves the verified copies as a mirror. SIGHUP syncs now.

The single-dash spellings -config, -once, -version and -help of earlier
releases are still accepted, with a deprecation warning on stderr.

Usage:
  authn-revokd [flags]

Flags:
  -c, --config string   the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -h, --help            help for authn-revokd
  -o, --once            sync once and exit: 1 when a list is not current, or could not be fetched
  -v, --version         version for authn-revokd
```

コマンドは v0.7.0 から cobra です。POSIX フラグ `--config`/`-c`、`--once`/`-o`、
`--version`/`-v`、`--help`/`-h`、および `--config=PATH`。`--help` は標準出力に出力して 0 で終了します
(v0.6.2 より前は、旧来の `-help` は 2 で終了していました)。以前のリリースのシングルダッシュの
綴り (`-config`、`-once`、`-version`、`-help`。`=` でも別の値でも) は引き続き受け付けられ、
フラグごとに標準エラー出力へ非推奨の行が一行出力されます。後のリリースで削除されます。
終了ステータスは変わりません (0。失敗、または `--once` のときにリストが current でない場合は 1。
使い方の誤り、または読めない設定は 2)。したがって `-once` でデプロイされたユニットは
変更不要です。

v0.6.0 より前は、コマンドは `revokd` で、既定で `/etc/revokd.hcl` を読んでいました。そのファイルは
もう読まれず、そのファイルがあって新しい既定のファイルがない場合、エラーは両方のパスを
示します。

## 一回の実行で何をするか {#what-it-does-in-one-run}

ループバック上の代役の発行者 (テスト用の鍵で署名した KRL と CRL を、authn-bridge と同じエンドポイントで配信する小さなプログラム) に対して、KRL ソースと CRL ソースで:

```
$ authn-revokd --config revokd.hcl --once
bridge-ssh: version 0, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
bridge-x509: version 1794481424000, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261112T120344
# Comment: authn-revokd sshd
```

新しいものが何もない二回目の実行は何も出力せず、0 で終了します。出力は、内容が変わったときに
のみ書き換えられるからです。

## トランスポートが問題にならない理由 {#why-the-transport-does-not-matter}

すべてのリストは自身を認証します。KRL は CA 自身の鍵による分離 SSHSIG 署名で、CRL はその CA の
署名でです。すべてのリストは、有効でなくなる時刻を述べます。そのためリストは、HTTPS、
クラスタ内の平文 HTTP、ミラー、ファイルのいずれで届いても構いません。トランスポートが決めるのは
変更が届く速さであり、偽造されたリストや古いリストが受け入れられるかどうかではありません。

| | KRL | CRL |
|---|---|---|
| 真正性 | SSH CA 鍵による SSHSIG、名前空間 `krl@go-authn.github.io` | その CA による署名 |
| 有効性 | `expires@go-authn.github.io`。sshd は無視する | `nextUpdate` |
| 後戻りしない | `krl_version`、次に生成日時 | CRL Number、次に `thisUpdate` |
| フェイルクローズ | authn-revokd が CA 鍵を失効させる KRL を書き込む | OpenSSL が期限切れの CRL を自ら拒否する |

## 次に読むもの {#where-to-go-next}

| | |
|---|---|
| [インストール]({{< relref "/authn-revokd/install.md" >}}) | デーモン、またはタイマーでの `--once`。sshd と nginx の接続 |
| [設定]({{< relref "/authn-revokd/configuration.md" >}}) | ソース、出力、ミラー、拒否されるもの |
| [リストの検証方法]({{< relref "/authn-revokd/verification.md" >}}) | 署名、日付、そして再起動をまたいで、保持しているリストより古くならないこと |
| [リストが失効したとき]({{< relref "/authn-revokd/lapse.md" >}}) | CA 自体を失効させる KRL |

## しないこと {#what-it-does-not-do}

失効がサーバーに届く速さは、authn-revokd のポーリング (`refresh`) に、発行者が再発行するまでの
遅れを加えたものより速くなりません。発行者が停止している間、その証明書はリストの有効期限から
拒否されます。CA の鍵を持つ者は、証明書に署名できるのと同じように、どのリストにも署名できます。

## ライセンス {#licence}

BSD-3-Clause。
