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
純粋な Go、`CGO_ENABLED=0`、単一のバイナリ。これらのページは v0.6.4 を説明しています。

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.4
$ authn-revokd -version
authn-revokd v0.6.4
$ authn-revokd -help
Usage of authn-revokd:
  -config string
    	the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -once
    	sync once and exit: 1 when a list is not current, or could not be fetched
  -version
    	print the version and exit
```

`-help` は 0 で終了します。v0.6.2 より前は 2 で終了していました。

v0.6.0 より前は、コマンドは `revokd` で、既定で `/etc/revokd.hcl` を読んでいました。そのファイルは
もう読まれず、そのファイルがあって新しい既定のファイルがない場合、エラーは両方のパスを
示します。

## 一回の実行で何をするか {#what-it-does-in-one-run}

ループバック上のテスト用 authn-bridge に対して、KRL ソースと CRL ソースで:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
bridge-x509: version 1791712224691, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261011T115024
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
| [インストール]({{< relref "/authn-revokd/install.md" >}}) | デーモン、またはタイマーでの `-once`。sshd と nginx の接続 |
| [設定]({{< relref "/authn-revokd/configuration.md" >}}) | ソース、出力、ミラー、拒否されるもの |
| [リストの検証方法]({{< relref "/authn-revokd/verification.md" >}}) | 署名、日付、そして再起動をまたいで、保持しているリストより古くならないこと |
| [リストが失効したとき]({{< relref "/authn-revokd/lapse.md" >}}) | CA 自体を失効させる KRL |

## しないこと {#what-it-does-not-do}

失効がサーバーに届く速さは、authn-revokd のポーリング (`refresh`) に、発行者が再発行するまでの
遅れを加えたものより速くなりません。発行者が停止している間、その証明書はリストの有効期限から
拒否されます。CA の鍵を持つ者は、証明書に署名できるのと同じように、どのリストにも署名できます。

## ライセンス {#licence}

BSD-3-Clause。
