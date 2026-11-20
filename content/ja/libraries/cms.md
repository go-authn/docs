---
title: "cms — CMS SignedData による署名"
linkTitle: "cms"
weight: 115
description: "go-authn/cms は CMS SignedData (RFC 5652) を読み取り検証する。PDF、UEFI、S/MIME の署名を収めるコンテナで、OpenSSL により検証される。"
tags: [ライブラリ, 署名, 証明書]
---

**この署名はこのバイト列に対して成り立つか、そしてどの証明書が作ったか。**
CMS SignedData（[RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)）は、PDF 署名、
UEFI の認証付き変数、S/MIME メッセージが書かれるコンテナです。標準ライブラリは
証明書を読み、署名を検証しますが、CMS は持っていません。

```sh
go get github.com/go-authn/cms@v0.1.0
```

v0.1.0 は**読み取りと検証**を行います。署名の作成は次のリリースです。

## 例 {#example}

```go
package main

import (
	"crypto/x509"
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/cms"
)

func main() {
	// A detached signature and the bytes it signed. For a PDF these are the
	// signature dictionary's /Contents and the file's /ByteRange.
	der, err := os.ReadFile("signature.der")
	if err != nil {
		panic(err)
	}
	content, err := os.ReadFile("signed-bytes")
	if err != nil {
		panic(err)
	}

	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content) // nil instead, when the content is attached
	switch {
	case errors.Is(err, cms.ErrInvalid):
		fmt.Println("the signature does not hold:", err)
		return
	case errors.Is(err, cms.ErrUnsupported):
		fmt.Println("a signature this package cannot check:", err)
		return
	case err != nil: // cms.ErrMalformed
		fmt.Println("not a signature:", err)
		return
	}

	// The signature holds. Whether to TRUST who made it is a second question,
	// with inputs of its own: the roots you accept.
	roots := x509.NewCertPool() // fill with the roots you trust
	for _, c := range signers {
		_, err := c.Verify(x509.VerifyOptions{Roots: roots, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}})
		fmt.Println(c.Subject, "chain:", err)
	}
}
```

`Verify` は署名が成り立つかどうかに答えます。**信頼** — 証明書のチェーン、
有効性、失効 — は別の判断で、RFC 5652 §5.6 はこれを CMS の外に置いています。
チェーンには `crypto/x509` を、取り消されたものには
[go-authn/revocation](https://github.com/go-authn/revocation) の CRL 検証を
使います。

## 3 つのエラー。呼び出し側には 3 つの答えが必要だから {#three-errors-because-a-caller-needs-three-answers}

| エラー | 意味 |
|---|---|
| `ErrMalformed` | このパッケージが読める SignedData ではない |
| `ErrUnsupported` | ここで実装されていないものを使う署名 |
| `ErrInvalid` | 読み取れてサポートもされているが、署名が成り立たない |

すべての拒否はこのうちちょうど 1 つを包み、ファジングテストはそれを不変条件として
保持します。

## 拒否するもの {#what-it-refuses}

コードに基づき、それぞれメッセージを確認するテストがあります。

- 証明書がコンテナに含まれていない署名者
- `content-type` と `message-digest` がそれぞれちょうど 1 つ、単一の値で存在しない
  署名付き属性
- コンテンツの型と一致しない署名付きコンテンツ型
- コンテンツと一致しないダイジェスト — **ここで再計算**し、署名者の値は決して
  使わない
- 自身のハッシュがダイジェストのハッシュと異なる署名アルゴリズム
- SHA-1（名指しで拒否）
- SHA-512 以外の上での Ed25519（RFC 8419）
- DER ではない署名付き属性 — 有効な署名から 1 ビットしか違わない、プリミティブな
  `[0]` タグを含む
- **16 を超える署名者**、**16 MiB を超える入力**。サイズの上限は作業量の上限では
  ない。各署名者はコンテンツ全体に対して検証される

**まだ対応していないもの：** BER の不定長は推測せずに拒否します。署名の作成は
なく、チェーン検証も意図的に行いません。

## 何に対して検証されるか {#what-it-is-checked-against}

**OpenSSL の `cms` コマンド。** OpenSSL 4.1.0 が作成した 11 個の署名が、RSA、
RSA-PSS、ECDSA、Ed25519 を、添付・分離の両方のコンテンツと 2 種類の署名者識別子で
カバーしています。`openssl cms -verify` とこのパッケージは、それぞれの署名と
改ざんされた変種のすべてで同じ判定を下します：34 中 34。

2 つの点で、このパッケージは OpenSSL 4.1.0 より**厳格**です。OpenSSL は
プリミティブな署名付き属性タグと、SHA-256 上の Ed25519 を受け入れます。
