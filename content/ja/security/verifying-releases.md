---
title: "ダウンロードの検証"
linkTitle: "ダウンロードの検証"
weight: 10
description: "各リリースが公開するものと、リリースワークフローでビルドされたバイナリをそれ以外と見分ける三つの確認。"
tags: [セキュリティ, リリース]
---

authnd、authn-bridge、authn-revokd、sshcert の各リリースは、六つの静的バイナリ
(`CGO_ENABLED=0`: linux、darwin、windows の amd64 と arm64)、`SHA256SUMS` ファイル、そして
すべてのバイナリのビルド来歴証明を公開します。以下の例は authn-bridge v0.23.3 を使います。
他のプログラムも、それぞれのリポジトリと名前で同じように動作します。

```sh
gh release download v0.23.3 --repo go-authn/bridge
```

## 1. チェックサム {#1-the-checksum}

```sh
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```
authn-bridge-darwin-amd64: OK
authn-bridge-darwin-arm64: OK
authn-bridge-linux-amd64: OK
authn-bridge-linux-arm64: OK
authn-bridge-windows-amd64.exe: OK
authn-bridge-windows-arm64.exe: OK
```

これが証明するのは、ファイルがリリースの列挙するものであるということだけで、それ以上では
ありません。リリースページのバイナリを置き換えられる者は、その隣の `SHA256SUMS` も置き換え
られます。

## 2. 来歴 {#2-the-provenance}

```sh
gh attestation verify authn-bridge-linux-amd64 --repo go-authn/bridge
echo $?
```

来歴証明は、ファイルをビルドしたワークフローの実行に対して GitHub が署名したものなので、
誰かが保持する鍵ではなく、リポジトリとワークフローを名指しします。

{{< callout type="warning" >}}
**出力ではなく終了ステータスを読んでください。** 端末がない場合、一部のバージョンの `gh` は、
検証が成功したときに何も出力しません。authnd で gh 2.65.0 を使って測定したところ、本物のバイナリは
終了ステータス 0 で出力は空でした。1 バイト追加したバイナリは終了ステータス 1 と
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found` を返しました。
そのダイジェストに対する来歴証明が存在しないためです。無音は失敗ではなく、ゼロでない
ステータスが失敗です。
{{< /callout >}}

## 3. バイナリ自身が述べること {#3-what-the-binary-says-about-itself}

```sh
go version -m authn-bridge-linux-amd64
```

```
authn-bridge-linux-amd64: go1.27.3
	path	github.com/go-authn/bridge/cmd/authn-bridge
	mod	github.com/go-authn/bridge	v0.23.3	
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=b04769c43c24f684df9e0b5a0d1cb6997ee90d95
	build	vcs.modified=false
```

(重要な行に短縮しています。最初の行は、そのバイナリをビルドした Go ツールチェーンです)。`mod` 行はタグと正確に一致しなければならず、`vcs.modified` は `false`
でなければなりません。コミットされていない変更のあるツリーからのビルドは `true` となり、そのバージョンは
`v0.23.3+dirty` と表示されます。リリースワークフローは、六つのバイナリ**すべて**が両方の確認に
通らない限り、またプログラムがバージョン行の最後の語としてタグを表示しない限り、公開を
拒否します。

```
$ authnd --version
authnd version v0.12.0
$ authn-bridge --version
authn-bridge version v0.23.3
$ authn-revokd -version
authn-revokd v0.6.5
```

authnd と authn-bridge は `--version` を受け付け、authn-revokd は Go 標準のフラグ構文である
`-version` を受け付けます。v0.6.1 からは、他の二つと同様に標準出力に表示するので、
`v=$(authn-revokd -version)` で取得できます。

## バイナリのあるリリース {#which-releases-have-binaries}

バイナリ、チェックサム、来歴証明は、authnd v0.9.2、authn-bridge v0.19.3、authn-revokd v0.5.0、
sshcert v0.1.2 から公開されています。それぞれの最初のリリースはチェックアウトの内部でバイナリを
ビルドして `+dirty` と報告しており、それは次のリリースで修正され、バイナリごとの確認はその後に
追加されました。それより前のタグはソースのみです。`go install …@<tag>` でビルドしてください。
これはタグを、`go version -m` が読むビルド情報に記録します。プログラムが表示するものは必ずしも
それではありません。sshcert-authorize は v0.1.5 まで `go install` のビルドで `dev` と表示して
おり、revokd には v0.5.0 より前は `-version` がありません。
