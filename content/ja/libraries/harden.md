---
title: "harden — 共有される二つのセキュリティプリミティブ"
linkTitle: "harden"
weight: 36
description: "go-authn/harden は、go-authn の各リポジトリがそれぞれコピーしていたセキュリティプリミティブ、https かループバックかのリダイレクト規則、原子的に書かれる非公開ファイル、そしてコアダンプ対策付きのメモリロックをまとめたものです。"
tags: [ライブラリ, harden, セキュリティ]
---

**go-authn の各リポジトリは何をコピーしていたのか?** 二つの小さな規則です。今は、標準ライブラリ
以外に依存しない一つのモジュールにあります。

```sh
go get github.com/go-authn/harden@v0.3.0
```

## `redirect` {#redirect}

トークン、鍵セット、署名付きアサーションがリンクをまたぐ前に適用される規則です。**URL は https
であるか、このマシンを指していなければなりません。**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| 関数 | |
|---|---|
| `CheckRedirect(req, via) error` | `http.Client` のポリシー: 10 回のリダイレクトで止まり、https でもループバックでもない先を拒否します (別のホストへの https から http へのリダイレクトが、これが存在する理由のケースです)。独自のポリシーはこの後に連ねてください |
| `HTTPSOrLoopback(rawURL) error` | `https://host.example/...`、またはループバックのホストへの `http://` なら nil。ホストなし、ほかのスキーム、平文は拒否します。エラーはスキームとホストを示し、URL 全体は決して示しません |
| `Loopback(host) bool` | `host` は `url.URL.Hostname()` が返すとおりのもの |

`Loopback` が受け入れるのは、ループバックである IP リテラル (127.0.0.0/8、`::1`、IPv4 マップの
`::ffff:127.0.0.1`)、そして `localhost` と `.localhost` 配下の任意の名前 (RFC 6761 section 6.3)
です。大文字小文字は問わず、末尾のドットの有無も問いません。前方一致は決して行わないので、
`127.evil.example` は拒否され、`0x7f.1`、`127.1`、`2130706433`、IPv6 ゾーン、角括弧付きの
`[::1]` (角括弧は URL の構文であり、ホストの一部ではありません) も同様です。

`Loopback` と `HTTPSOrLoopback` は、RFC の二つ目の読み方に対してファズされており、コーパスは
コミットされています。

これを適用しているのは、[oidc]({{< relref "/libraries/oidc.md" >}}) (v0.8.1)、
[saml]({{< relref "/libraries/saml.md" >}}) (v0.7.3)、
[wireguard]({{< relref "/libraries/wireguard.md" >}})、rp (v0.5.1)、awscred (v0.3.1) です。

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write` は、データをモード 0600 で `path` に置きます。同じディレクトリに一時ファイルを作り、
`fsync` し、`rename` します。そのため:

- 読み手が見るのは古いファイルか新しいファイルのどちらかで、半分だけ書かれたものを見ることは
  ありません。
- `path` に置かれたシンボリックリンクは**辿られずに置き換えられ** (指していたものには手を
  触れません)、モードが緩いファイルはそのモードを保ちません。
- Unix では、シンボリックリンクであるディレクトリ、他人が所有するディレクトリ、グループまたは
  その他に書き込み可能なディレクトリは、何かを書く前に拒否されます。

ディレクトリは作りません。Windows には読めるモードがありません。v0.2.0 以降、ファイルは
`CreateFile` が設定する、現在のアカウントだけを一つのエントリとする保護されたアクセスリスト
(kinit v0.3.2 のリスト) で作られるので、フォルダーのエントリは決して継承されません。モジュールは
`golang.org/x/sys` を必要としますが、使うのは Windows のビルドだけです。

これが書いているのは、kinit の `--cred-file` (v0.3.3)、wireguard の `FloorFile` (v0.2.1)、
`authn-revokd` の状態ファイル (revocation v0.7.2)、
[secretsource]({{< relref "/libraries/secretsource.md" >}}) の KeePassXC 関連付けファイル
(v0.8.1) です。

## フロア {#floors}

go-authn/wireguard と go-authn/revocation はどちらも再起動をまたいで順序のフロアを保ちますが、
フロアは共有していません。wireguard はバージョンと発行時刻だけを自前の小さなファイルに保ち、
revocation は署名済みの一覧全体を保ち、それを検証してフロアを再計算します。共通なのはファイルの
書き込みだけで、それが `privfile` です。

## `memlock` {#memlock}

v0.3.0 から (theca から移設): 鍵素材をスワップ、コアファイル、デバッガから遠ざけます。

```go
import "github.com/go-authn/harden/memlock"

region, err := memlock.Lock(unsafe.Pointer(&key[0]), uintptr(len(key)))
if err != nil { ... } // 拒否された: 報告するか、中止する
defer region.Release()
```

| 関数 | |
|---|---|
| `Lock(p, n) (*Region, error)` | 範囲のページを `mlock` (Linux、macOS、BSD 系) または `VirtualLock` (Windows) でロックします。**拒否はエラーです**。何もロックされたままにならず、判断は呼び出し側に委ねられます。二つの領域が共有するページは、両方が解放されるまでロックされたままです |
| `(*Locker).LockBestEffort(p, n, report)` | 同じですが、拒否のたびに `report` へ渡し、残りは構わずロックします。名前のとおり、ロックなしで動いても許される場所でだけ使ってください |
| `(*Region).Release()` | ロックを解除します。nil でも、二度呼んでも安全です |
| `DisableDumps() error` | `RLIMIT_CORE` を 0 に、Linux では `PR_SET_DUMPABLE` も 0 にします。macOS に限り `PT_DENY_ATTACH` も呼びます |

それ以外のプラットフォームは `*UnsupportedError` (`errors.ErrUnsupported`
に一致) を受け取り、黙って成功することはありません。

**保証すること**: 範囲のページが `Lock` から `Release` までメモリ上でロックされるか、
さもなければエラーが返ること。**保証しないこと**: コピーが存在しないこと。Go の
ガベージコレクタは、ヒープオブジェクトをロックされる前にコピーすることがあります。
そのため、動かないメモリをロックし、秘密は一か所にだけ置いてください。システムの
上限は引き続き適用されます (`RLIMIT_MEMLOCK`、Windows ではワーキングセットの大きさ)。
Windows には `PR_SET_DUMPABLE` や `PT_DENY_ATTACH` に相当するものがなく、同じユーザーの
デバッガや管理者はプロセスを読めます。

## リファレンス {#reference}

このページの正本は
[github.com/go-authn/harden](https://github.com/go-authn/harden) の README です。BSD 3-Clause。
