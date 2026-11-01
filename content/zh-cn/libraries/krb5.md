---
title: "krb5 — 接受 Kerberos 票据"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5 是 Kerberos 的接受方一半：keytab、对 AP-REQ 的验证、双向认证所需的 AP-REP，以及在会话密钥下签名和加密的消息。"
tags: [库, kerberos]
---

**这张 Kerberos 票据对此服务是否有效？** Kerberos 的**接受方**
一半，且仅此一半：它持有 keytab，验证客户端出示的 AP-REQ，
用证明服务真实的 AP-REP 作答，然后在该交换所建立的密钥下
签名、验证、加密和解密消息。

```sh
go get github.com/go-authn/krb5@v0.3.3
```

v0.3.3 不改变 API，也不改变代码：它把间接依赖 golang.org/x/net 提升到 v0.62.0，golang.org/x/crypto 提升到 v0.58.0，
github.com/hashicorp/go-uuid 提升到 v1.0.4。`govulncheck` 过去在它所需要但不调用的模块中列出 46 项发现，现在列出 1 项，
GO-2026-5932（`golang.org/x/crypto/openpgp`），它没有修复版本，且 go-authn 中没有任何东西导入它。从代码可达的发现，
之前是 0，之后也是 0。

它从不与 KDC 通信，也从不签发票据，因此接受谁的票据是
别人的决定。签发的一半是
[kdc]({{< relref "/libraries/kdc.md" >}})，本模块并不依赖它——
参见[为什么它们是独立的]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}})。
票据解密由 [gokrb5](https://github.com/jcmturner/gokrb5) 完成。

## 为什么需要它 {#why-it-exists}

gokrb5 是客户端库。它验证 AP-REQ，却无法构造作答的 AP-REP。
每个 GSS-API 客户端都会要求双向认证——MIT 自己的
`gss-client` 设置 `GSS_C_MUTUAL_FLAG` 而无法关闭——因此无法生成 AP-REP 的服务
根本无法完成任何上下文。构造它几乎就是本模块所增加的全部内容。

## 示例 {#example}

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

它需要 `github.com/jcmturner/gokrb5/v8` 提供 `keytab.New`，即 `krb5.New`
所接受的类型；`krb5.Load` 则改为从路径读取 keytab。

`Accept` 之后，`*Context` 会说明是谁：`Principal()`（`alice@EXAMPLE.ORG`），或
分开的 `User()` 和 `Realm()`。把 principal 映射到本地账户是
调用方的策略：`alice@EXAMPLE.ORG` 和 `alice@PARTNER.ORG` 都对应
“alice”。`Expires()` 是其背后票据的结束时间，过了这个时间，
持有长连接的服务器就应当不再承认它。`MIC`/`VerifyMIC`
和 `Wrap`/`Unwrap` 进行签名；`Seal`/`Unseal` 增加机密性（`sec=krb5p`）。
`Context` 不是并发安全的；`Acceptor` 是。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**此服务不会接受的票据**——服务错误、密钥错误、
已过期、被重放、时钟超出 `ClockSkew`（默认五分钟，与 MIT 相同）——
是 `ErrRejected`。不是 GSS-API krb5 令牌的字节是
`ErrNotAToken`，不是 AP-REQ 的令牌是 `ErrNotAPReq`。这些错误
有意保持粗略：客户端只会得知其票据被拒绝，而绝不会知道
是哪一项检查拒绝了它。出现错误即没有上下文，返回的令牌
为空。

**接受方不负责应答的 principal。** 使用
`krb5.Principal("nfs/files.example.org")` 时，持有多个服务的 keytab
只为那一个服务应答。

**签名不匹配的消息**是 `ErrBadMIC`，无论是长度、头部、序列还是校验和
不一致。接受方用密钥用途 23 签名，用 25 验证，因此此服务器
生成的令牌不能被当作客户端签名的令牌而重放回来。

**交给 `Unwrap` 的已加密令牌**是 `ErrSealed`，不同于签名
错误：读取仅有完整性保护的令牌的调用方，不应被交给
读起来像消息的密文。**交给 `Unseal` 的未加密令牌**
是 `ErrNotSealed`：承诺了机密性的协议，不应被交给
以明文穿过线路的内容。

它不声明接受方子密钥：上下文密钥是发起方放入
其认证符的子密钥，或在发起方没有发送子密钥时是票据的会话密钥
（RFC 4121 §4.3）。

{{< callout type="warning" >}}
**keytab 是静态存储的秘密**

它的路径可以来自配置文件或 `KRB5_KTNAME`；其中的
密钥绝不能被记录、打印，或通过环境变量
传递。
{{< /callout >}}

## 它对照什么检查 {#what-it-is-checked-against}

**真实的 MIT KDC 和 MIT 自己的 `gss-client`**，由本包
充当 `gss-server`。`test/kdc.sh` 在环回地址上构建一次性的域，
无需特权；CI 通过 pkgx 获取 MIT Kerberos（Ubuntu 的软件包
不提供 `gss-client`）。Linux 测试通道、竞态检测器和覆盖率
通道设置 `KRB5_REQUIRE_JUDGE=1`，因此缺少测试夹具就会失败。另有一个步骤
运行 `TestMITClientAgainstThisAcceptor`，并在日志没有写明
*authenticated as alice@* 时失败——评判者悄悄停止运行的绿色通道
是不被接受的。`TestMITClientSealed` 在开启机密性的情况下做同样的事。

macOS、Windows 和跨架构通道没有域，在那里
评判者会跳过。覆盖率通道的下限是 90%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/krb5@v0.3.3](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.3)
