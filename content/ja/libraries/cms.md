---
title: "cms — CMS SignedData による署名"
linkTitle: "cms"
weight: 115
description: "go-authn/cms は CMS SignedData (RFC 5652) を読み取り、検証し、署名する。PDF、UEFI、S/MIME の署名を収めるコンテナで、OpenSSL により検証される。"
tags: [ライブラリ, 署名, 証明書]
---

**この署名はこのバイト列に対して成り立つか、そしてどの証明書が作ったか。**
CMS SignedData（[RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)）は、PDF 署名、
UEFI の認証付き変数、S/MIME メッセージが書かれるコンテナです。標準ライブラリは
証明書を読み、署名を検証しますが、CMS は持っていません。

```sh
go get github.com/go-authn/cms@v0.2.1
```

v0.2.1 以降、`Verify` は、署名対象のコンテンツ自体が、content-type 属性と message-digest 属性の
両方を持つ DER の `SET OF Attribute` である、属性なしの署名を拒否します。署名属性付きで作られた署名は
その DER を対象とします (RFC 5652 §5.4)。鍵なしで、その属性をコンテンツとする署名属性なしの
SignedData に詰め替えると、検証に通り、コンテンツとして署名されたことのない内容について署名者を
名指ししていました。

v0.2.0 は**読み取り、検証、署名の作成**を行います。

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

## 署名の作成 {#signing}

`cms.Sign` は、任意の `crypto.Signer`（ファイル上、カード上、HSM 内のいずれかに
ある RSA、ECDSA、Ed25519 の鍵）から、**署名者 1 人**の DER ContentInfo を書き出します。
返す前に証明書でその署名を検証するため、誤った署名を返す署名器は拒否され、
出力されることはありません。

```go
package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/go-authn/cms"
)

func main() {
	// A key and a self-signed certificate, for the example. In practice the
	// key may live on a card or in an HSM: any crypto.Signer will do.
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "signer"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		panic(err)
	}
	cert, err := x509.ParseCertificate(certDER)
	if err != nil {
		panic(err)
	}

	content := []byte("the bytes to sign")
	der, err := cms.Sign(content, cms.SignOptions{
		Signer:      key,
		Certificate: cert,
		Hash:        crypto.SHA256,
		Detached:    true, // as a PDF signature: the content is not inside
		SigningTime: time.Now(),
	})
	switch {
	case errors.Is(err, cms.ErrSigner):
		panic(fmt.Sprint("the key or the device failed: ", err))
	case errors.Is(err, cms.ErrOptions):
		panic(fmt.Sprint("the request is wrong: ", err))
	case err != nil: // cms.ErrUnsupported
		panic(err)
	}

	// Sign checked its own signature; Verify is the reader's side.
	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content)
	if err != nil {
		panic(err)
	}
	fmt.Println("signed by", signers[0].Subject.CommonName)

	content[0] ^= 1
	_, err = sd.Verify(content)
	fmt.Println("altered content:", errors.Is(err, cms.ErrInvalid))
}
```

`SignOptions` には他に `Chain`（埋め込む中間証明書）、`PSS`（RSASSA-PSS）、
`SigningCertificateV2`（RFC 5035。CAdES と PAdES のベースラインが要求するもの）、
`ContentType`、`NoSignedAttrs`、`Rand` があります。ダイジェストは既定で SHA-256、
ほかに SHA-384 と SHA-512 を選べ、Ed25519 は常に SHA-512 です。SHA-1 は拒否されます。

`Sign` には独自のエラーが 3 つあります。`ErrOptions`（要求が誤っている）、
`ErrSigner`（鍵またはデバイスが失敗した、あるいは証明書で検証できない署名を
返した）、`ErrUnsupported`（書き出さないアルゴリズム）です。**署名付き属性なし**の
Ed25519 も拒否されます。RFC 8419 は認めていますが、このパッケージが書き出す形を
OpenSSL は検証しないためです。

OpenSSL の `cms -verify` とこのパッケージの `Verify` は、試したすべての組み合わせで
一致します。**58 の組み合わせ、203 の判定**で、RSA PKCS #1 v1.5、RSA-PSS、
ECDSA P-256 と SHA-256、SHA-384、SHA-512、および Ed25519 と SHA-512 を、添付・分離の
両方、署名付き属性の有無の両方で試しています。`Verify` はまだ
signing-certificate-v2 を検証しません。署名者の証明書をその属性に結び付けるのは
呼び出し側の役目です。

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
- 4 つの非 DER 形式の署名付き属性：プリミティブな `[0]` タグ（有効な署名から
  1 ビットしか違わない）、SEQUENCE ではない属性、SET ではない値、属性内の余分な
  バイト。SET の順序は確認しない
- **16 を超える署名者**、**16 MiB を超える入力**。サイズの上限は作業量の上限では
  ないため、署名者数に上限を設けている。コンテンツのハッシュはダイジェスト
  アルゴリズムごとに 1 回だが、署名付き属性のない Ed25519 署名者は検証のたびに
  全体をハッシュする

**まだ対応していないもの：** BER の不定長は推測せずに拒否します。署名の作成は
署名者 1 人で、副署名もタイムスタンプトークンもありません。`Verify` は
signing-certificate-v2 を検証せず、チェーン検証も意図的に行いません。

## 何に対して検証されるか {#what-it-is-checked-against}

**OpenSSL の `cms` コマンド。** OpenSSL 4.1.0 が作成した 11 個の署名が、RSA、
RSA-PSS、ECDSA、Ed25519 を、添付・分離の両方のコンテンツと 2 種類の署名者識別子で
カバーしています。`openssl cms -verify` とこのパッケージは、それぞれの署名と
改ざんされた変種のすべてで同じ判定を下します：34 中 34。

2 つの点で、このパッケージは OpenSSL 4.1.0 より**厳格**です。OpenSSL は
プリミティブな署名付き属性タグと、SHA-256 上の Ed25519 を受け入れます。
