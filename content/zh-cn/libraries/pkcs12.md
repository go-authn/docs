---
title: "pkcs12 — 上传的 .p12 里的密钥和证书"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12 用纯 Go 读取 PKCS#12（.p12 / .pfx，RFC 7292）文件，为不可信的上传而建：每一项资源上限都是无法关闭的选项，并由 OpenSSL 判定。"
tags: [库, 证书, 密钥]
---

**别人发来的这个文件里，有哪个私钥和哪些证书？**
PKCS#12（[RFC 7292](https://www.rfc-editor.org/rfc/rfc7292)）是导出工具写入密钥、
其证书和链上其余证书的 `.p12` / `.pfx` 容器。`golang.org/x/crypto/pkcs12` 已被弃用，
并停留在 SHA-1 和 3DES/RC2 上，因此会拒绝 OpenSSL 3 和 4 以及当前 Windows 默认写出的
内容（PBES2、AES、SHA-2 MAC）。本模块读取这些内容，除标准库外没有任何依赖，为
**不可信的上传**而建。

```sh
go get github.com/go-authn/pkcs12@v0.1.0
```

它**只解码**：没有编码器。是否信任这条链，是 `crypto/x509` 的 `Verify` 负责的另一个
决定。

## 示例 {#example}

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/pkcs12"
)

func main() {
	data, err := os.ReadFile("upload.p12")
	if err != nil {
		panic(err)
	}

	b, err := pkcs12.Decode(data, "the password", nil)
	switch {
	case errors.Is(err, pkcs12.ErrIncorrectPassword):
		fmt.Println("ask again:", err)
		return
	case err != nil: // hostile, unsupported, too costly...
		fmt.Println("refused:", err)
		return
	}

	// b.PrivateKey   *rsa.PrivateKey, *ecdsa.PrivateKey, ed25519.PrivateKey or *ecdh.PrivateKey
	// b.Certificate  the certificate holding the key's public half
	// b.CACerts      every other certificate, in file order
	fmt.Println("certificate for", b.Certificate.Subject, "and", len(b.CACerts), "more")
}
```

`Decode(data, password, *Options) (*Bundle, error)` 传入 `nil` 即使用默认值。
`Bundle` 包含密钥、持有其公钥一半的证书，以及按文件顺序排列的其余证书。

## 选项及其默认值 {#options-and-their-defaults}

字段为零表示使用默认值，而且**没有任何字段能关闭上限**。

| 字段 | 默认值 | 含义 |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | 任一次密钥派生的迭代次数 |
| `MaxWork` | 5 000 000 | 整个文件的迭代次数 x 输出块数 |
| `MaxDepth` | 16 | BER 嵌套和构造字符串分片的嵌套 |
| `MaxBags` | 1024 | 文件中的 SafeBag |
| `MaxAuthSafes` | 32 | AuthenticatedSafe 中的 ContentInfo |
| `MaxCertSize` | 32 KiB | 单个证书的 DER |
| `MaxCertBytes` | 512 KiB | 所有证书合计的 DER |
| `MaxRSABits` | 8192 | RSA 模数 |
| `AllowNoMAC` | `false` | 读取没有完整性 MAC 的文件（`openssl pkcs12 -nomac`）；否则为 `ErrNoMAC` |
| `NoPassword` | `false` | 文件导出时完全没有口令，区别于空口令 `""` |

这两个布尔值对应格式的两处歧义。使用 `AllowNoMAC` 时，没有任何东西认证内容，
错误的口令只能通过解密失败发现。**空**口令（`""`）和**缺失**口令（`NoPassword`）
派生出不同的密钥，两者都可用：口令为 `""` 且 `NoPassword` 为 false 时，`Decode`
先试空口令，再试缺失口令，因为各导出工具对自己写的是哪一种意见不一；`NoPassword`
为 true 时只试缺失口令，且口令参数必须是 `""`。

## 它读取什么 {#what-it-reads}

| 层 | 支持 |
|---|---|
| 加密 | PBES2（[RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)），基于 HMAC-SHA-1/224/256/384/512 的 PBKDF2 和 AES-128/192/256-CBC |
| 旧式加密 | `pbeWithSHAAnd3-KeyTripleDES-CBC`、`pbeWithSHAAnd2-KeyTripleDES-CBC`、`pbeWithSHAAnd40BitRC2-CBC` 及 128 位变体；RC2 在模块内实现 |
| 完整性 | 使用 SHA-1/224/256/384/512 的 HMAC MAC（RFC 7292 附录 B 的 KDF）和 **PBMAC1**（[RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)） |
| 口令 | 按附录 B.1 的 BMPString，BMP 之外的字符用代理对 |
| 编码 | BER，包括 Windows 和 Java 写出的不定长和构造的 OCTET STRING |
| 包（bag） | 加密的和明文的密钥包、证书包；CRL、秘密和安全内容包被跳过 |

**以 `ErrUnsupported` 拒绝：** 公钥的完整性和隐私模式（`signedData`、
`envelopedData`）、RC4、scrypt、PKCS#12 自带之外的 PBES1、PBMAC1 内的 SHA-1，
以及证书或 PKCS#8 密钥内的 BER（而非 DER）。

## 错误 {#errors}

| 错误 | 含义 |
|---|---|
| `ErrMalformed` | 不是本包能读取的 PKCS#12 文件 |
| `ErrUnsupported` | 可读，但使用了此处未实现的东西 |
| `ErrLimit` | 将超出 `Options` 的某项上限；在工作之前被拒绝 |
| `ErrIncorrectPassword` | 错误的口令和被篡改的文件，按设计是同一个答案 |
| `ErrNoMAC` | 没有 MAC，且未设置 `AllowNoMAC` |
| `ErrNoPrivateKey` | 文件中没有私钥 |
| `ErrMultipleKeys` | 文件中有多个私钥 |
| `ErrNoCertificate` | 没有证书与私钥匹配 |
| `ErrPassword` | 无法使用的口令 |

每次拒绝恰好包装其中一个，模糊测试目标把这一点当作不变量。

## 安全上限 {#the-security-bounds}

上面每一项上限都在**工作之前**检查，每个长度字段都先与实际存在的字节核对，然后才
分配任何内存。超过 512 字节的盐和超过 1024 个字符的口令会被拒绝。

MAC 在**解密任何内容之前、以恒定时间**验证。

当证书由成千上万个很小的名称构成时，`crypto/x509` 会分配其大小的 43 到 52 倍；
`crypto/rsa` 通过对密钥声明的数做算术来验证密钥，所以远长于模数的因子会消耗超线性
的 CPU。两者都无法从外部修复，因此先限制到达它们的内容：证书由 `MaxCertSize` 和
`MaxCertBytes` 限制，每个 PKCS#8 密钥（最大 32 KiB）用 `encoding/asn1` 读取，当其
模数超过 `MaxRSABits`、某个因子或指数比模数允许的更长、某个数不是正数，或是多素数
时，以带类型的错误拒绝（`ErrUnsupported`）。

**每个请求的内存。** 使用默认选项时，一个恶意文件会让一次 `Decode` 分配约 25 MB
（联合测量：最坏的证书和接受的最大密钥，8192 位，25.1 MB，其中约 20 MB 一直存活到
返回），文件为 530 KB。解码上传文件的服务应限制同时进行的解码数，例如用信号量，
并在只预期短链时降低 `MaxCertBytes`。

## 局限 {#limitations}

- **没有 CRT 值的 RSA 密钥会被拒绝**（`ErrUnsupported`）。缺少 `Dp`、`Dq` 和
  `Qinv` 的密钥在 `crypto/x509` 看到之前就被拒绝。RFC 8017 要求这些值，所有导出
  工具（OpenSSL、Windows、Java 的 keytool）也都会写入，但 `crypto/x509` 用大数运算
  派生缺失的值：8192 位时为 16.4 MB 和 21 744 次分配，有这些值时为 0.36 MB 和 618 次。
- **[go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2)，未关闭，
  LOW。** 在 `GODEBUG=x509rsacrt=0` 下，`crypto/x509` 会丢弃无效的 CRT 值并重新计算，
  而预检只检查它们是否*存在*：CRT 值错误的 8192 位密钥会通过预检，配合最坏的证书，
  解码达到 39.4 MB（比率 74.7），超出测试所断言的上限。这需要运营者主动开启，且
  模块的 `go.mod` 声明的 Go 版本中该设置并非默认；在默认设置下，同样的输入会以
  `ErrMalformed` 被拒绝。
- 它只解码，不判断这条链。

## 它与什么对照检验 {#what-it-is-checked-against}

**OpenSSL 是裁判。** 测试中有 23 个由 OpenSSL 4.1 写出的文件（AES/PBES2、`-legacy`
的 3DES 和 RC2、`-nomac`、多个证书、RSA、EC 和 Ed25519、PBMAC1），并附有一份清单，
记录 OpenSSL 自己对每个文件内容的说法。

**放大。** `TestAmplification` 针对大量很小的包、大量证书、深层不定长嵌套、很长的
OCTET STRING 链和 4 GiB 的长度声明，限制已分配字节相对输入字节的比例，并断言拒绝
发生在调用 `crypto/x509` 之前。模块还做了模糊测试（语料已提交），块覆盖率 100 %，
并在 `-race` 和 `govulncheck` 下运行。

**`software.sslmate.com/src/go-pkcs12`**，位于独立的 `oracle/` 模块中：在两者都能
尝试的 23 个文件中，两者都读取 18 个，叶证书、链顺序和密钥逐字节相同。其余 5 个
（RC2-128、SHA-384 MAC、无 MAC，以及两个含 BMP 之外字符的口令）只有本包能读取；
没有哪个是对方能读而本包拒绝的。

它与 [cms]({{< relref "/libraries/cms.md" >}}) 搭配：在这里解码 `.p12`，在那里签名。
