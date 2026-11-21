---
title: "cms — CMS SignedData 签名"
linkTitle: "cms"
weight: 115
description: "go-authn/cms 读取、验证并生成 CMS SignedData（RFC 5652），即 PDF、UEFI 和 S/MIME 签名所用的容器，由 OpenSSL 判定。"
tags: [库, 签名, 证书]
---

**这个签名对这些字节是否成立，又是哪个证书做出的？**
CMS SignedData（[RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)）是 PDF
签名、UEFI 认证变量和 S/MIME 消息所写入的容器。标准库能读取证书、验证签名，
但没有 CMS。

```sh
go get github.com/go-authn/cms@v0.2.1
```

自 v0.2.1 起，`Verify` 拒绝没有签名属性的签名，如果其被签名的内容本身是一个同时带有
content-type 和 message-digest 属性的 DER `SET OF Attribute`。带签名属性的签名所覆盖的是
这些属性的 DER（RFC 5652 §5.4）；在没有密钥的情况下把它重新打包成没有签名属性的
SignedData，使其内容就是这些属性，它此前会通过验证，并为从未作为内容被签名的内容指认签名者。

v0.2.0 **读取、验证并生成签名**。

## 示例 {#example}

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

`Verify` 回答签名是否成立。**信任** — 证书的链、有效期、吊销 — 是另一项
判断，RFC 5652 §5.6 将其置于 CMS 之外：链用 `crypto/x509`，已撤回的用
[go-authn/revocation](https://github.com/go-authn/revocation) 的 CRL 验证。

## 生成签名 {#signing}

`cms.Sign` 用任意 `crypto.Signer`（文件、卡或 HSM 中的 RSA、ECDSA 或 Ed25519
密钥）写出一个只有**一个签名者**的 DER ContentInfo。返回之前，它会用证书验证
这个签名，因此返回错误签名的签名器会被拒绝，绝不会被输出。

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

`SignOptions` 还接受 `Chain`（要嵌入的中间证书）、`PSS`（RSASSA-PSS）、
`SigningCertificateV2`（RFC 5035，CAdES 和 PAdES 基线所要求的）、`ContentType`、
`NoSignedAttrs` 和 `Rand`。摘要默认为 SHA-256，也可选 SHA-384 或 SHA-512；
Ed25519 始终使用 SHA-512。SHA-1 会被拒绝。

`Sign` 有三种自己的错误：`ErrOptions`（请求有误）、`ErrSigner`（密钥或设备失败，
或返回了无法用证书验证的签名）和 `ErrUnsupported`（它不写出的算法）。**没有签名
属性**的 Ed25519 同样被拒绝：RFC 8419 允许，但 OpenSSL 不验证本包会写出的形式。

OpenSSL 的 `cms -verify` 与本包的 `Verify` 对所询问的每种组合都一致：
**58 种组合，203 个判定**，涵盖 RSA PKCS #1 v1.5、RSA-PSS 和 ECDSA P-256 搭配
SHA-256、SHA-384、SHA-512，以及 Ed25519 搭配 SHA-512，附加与分离，有与没有签名
属性。`Verify` 目前还不检查 signing-certificate-v2：把签名者的证书与该属性绑定
是调用方的事。

## 三种错误，因为调用方需要三种回答 {#three-errors-because-a-caller-needs-three-answers}

| 错误 | 含义 |
|---|---|
| `ErrMalformed` | 不是本包能读取的 SignedData |
| `ErrUnsupported` | 使用了本包未实现内容的签名 |
| `ErrInvalid` | 可读且受支持，但签名不成立 |

每一次拒绝都恰好包装其中之一，模糊测试将其作为不变量来保持。

## 它拒绝什么 {#what-it-refuses}

依据代码，每一项都有检查其消息的测试：

- 证书不在容器中的签名者；
- 签名属性中没有恰好一个 `content-type` 和恰好一个 `message-digest`、
  且各自只有单一值；
- 与内容类型不符的已签名内容类型；
- 与内容不匹配的摘要 — **在此处重新计算**，绝不采用签名者给出的值；
- 自身哈希与摘要哈希不同的签名算法；
- SHA-1，点名拒绝；
- 基于 SHA-512 以外的 Ed25519（RFC 8419）；
- 四种非 DER 形式的签名属性：原始（primitive）`[0]` 标签（与有效签名只差
  一位）、不是 SEQUENCE 的属性、不是 SET 的值，以及属性内多余的字节。不检查
  SET 的顺序；
- 超过 **16 个签名者**，以及超过 **16 MiB** 的输入。大小上限不是工作量上限，
  因此对签名者数量设了上限：内容按每种摘要算法只哈希一次，但没有签名属性的
  Ed25519 签名者在每次验证时仍会哈希全部内容。

**尚未支持：** BER 不定长被拒绝而非猜测；生成签名只有一个签名者，没有副署，
也没有时间戳令牌；`Verify` 不检查 signing-certificate-v2；有意不做链验证。

## 用什么来检验 {#what-it-is-checked-against}

**OpenSSL 的 `cms` 命令。** 由 OpenSSL 4.1.0 生成的 11 个签名覆盖 RSA、
RSA-PSS、ECDSA 和 Ed25519，包含附加与分离两种内容以及两种签名者标识形式。
`openssl cms -verify` 与本包对每一个签名及其篡改变体都给出相同的判定：34 个中
34 个。

在两点上，本包比 OpenSSL 4.1.0 **更严格**：OpenSSL 接受原始的签名属性标签，
以及基于 SHA-256 的 Ed25519。
