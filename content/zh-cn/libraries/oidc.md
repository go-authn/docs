---
title: "oidc — 验证持有者令牌"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc 把 OpenID Connect 令牌验证为一个身份：发现、密钥集、算法允许列表，以及重要的拒绝情形。没有依赖。"
tags: [库, oidc, 令牌]
---

**这个持有者令牌声称是谁在发出请求，是否应当相信？**
发现、密钥集，以及资源服务器必须进行的检查——纯 Go，
**除标准库之外没有任何依赖**。

```sh
go get github.com/go-authn/oidc@v0.4.1
```

这里没有登录流程：没有重定向，没有授权码交换，没有客户端密钥，
没有 cookie。这是**资源服务器**的一半——有东西带着
令牌到来，而本库说明那是谁。

## 示例 {#example}

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/go-authn/oidc"
)

func main() {
	// Discovery happens here, at startup: an issuer that does not answer is
	// a server that cannot authenticate anybody.
	v, err := oidc.New(context.Background(), oidc.Config{
		Issuer:   "https://login.example.org",
		Audience: "fileshare",
		Type:     "at+jwt", // a resource server takes access tokens, not ID tokens
	})
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		tok, err := v.Verify(r.Context(), raw)
		if err != nil {
			log.Print(err) // which check refused it: for this log only
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		fmt.Fprintln(w, tok.Subject(), tok.Username(), tok.Groups())
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

`Verifier` 对并发使用是安全的，并持有密钥集：在启动时构建一个
并一直保留。`Verify` 的错误会说明是哪项检查拒绝了令牌，供
服务器的日志使用；无论是哪项检查，客户端得到的都是同一种拒绝。

`New` 在获取任何内容之前就会拒绝的三种配置：

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/oidc"
)

func main() {
	ctx := context.Background()
	for _, cfg := range []oidc.Config{
		{Issuer: "http://login.example.org", Audience: "fileshare"},
		{Issuer: "https://login.example.org"},
		{Audience: "fileshare"},
	} {
		_, err := oidc.New(ctx, cfg)
		fmt.Println(err)
	}
}
```

```
oidc: http://login.example.org is not https: the key set decides every signature, and over cleartext so does anybody on the way
oidc: no audience: a token minted for another service is a valid token, and a verifier that does not check accepts every one the issuer ever signed
oidc: no issuer: a verifier without one accepts tokens from anybody
```

`Config` 的其余部分是可选的：`JWKSURL` 跳过发现；`UsernameClaim`
和 `GroupsClaim`（默认 `groups`）指定声明名称；`ClockSkew` 和
`MinRefresh` 默认为一分钟；`Client` 是 HTTP 客户端，用于代理、
私有 CA 或超时设置。`Token` 可读取 `Subject`、`Issuer`、`Audience`、
`Email`、`EmailVerified`、`Username`、`Groups`、`Expiry`、`NotBefore` 和
`IssuedAt`；`Claim(name, &v)` 解码任何其他声明，而 `Has(name)` 说明
它是否存在。

## 它接受什么 {#what-it-accepts}

十种签名算法，作为**允许列表**：`RS256` `RS384` `RS512`、
`PS256` `PS384` `PS512`、`ES256` `ES384` `ES512`，以及 `EdDSA`（Ed25519）。`alg`
不在其中的令牌，会在获取任何密钥之前就被拒绝。
`alg: none` 和 HMAC 系列因不在列表中而被拒绝，并且
密钥必须与算法的种类相符：声称使用 `RS256` 的令牌要用
RSA 密钥检查，否则被拒绝。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

| | 原因 |
|---|---|
| `alg: none` | 声称自己未签名的令牌，只是某人键入的 JSON 对象 |
| 针对公钥的 HMAC | `HS256` 使用共享密钥，而签发方的密钥是公开的：任何人都可以伪造令牌 |
| 仅仅以正确签发方**开头**的签发方 | `iss` 是整体比较的：`https://login.example.org.evil.test` 以正确的字符串开头 |
| 缺失或错误的 **audience** | 为另一个服务生成的令牌是有效的；它并不发往这一个 |
| **没有过期时间**的令牌 | 它是别人可以复制一次的密码 |
| 通过**明文 HTTP** 访问的签发方、密钥集或重定向，环回地址除外 | 密钥集决定每一个签名 |
| 不足 2048 位的 RSA 密钥，或 `n` 或 `e` 不是最短形式的密钥；不在其曲线上的 EC 点 | 短密钥下的签名可以被伪造；在 v0.2.2 之前，用零字节填充的 1024 位模数会被当作 2048 位通过 |
| 以 `sig` 之外的 `use` 发布的密钥 | 密钥集中合理地也包含加密密钥 |
| 设置了 `Type` 时，`typ` 不同的令牌；未设置时，`typ` 不是 `JWT` 或 `at+jwt`（没有 `typ` 头的令牌可通过） | RFC 9068 §4：资源服务器要检查 `typ: at+jwt`，否则只要 audience 一致，就会把 ID 令牌当作访问令牌 |
| 不是规范 base64url 的部分 | 令牌应当作为一个字符串通过验证 |

ECDSA 的 `s` 和 `n − s` 都能通过验证，算法允许这样。因此
拒绝列表或重放缓存应以 `jti` 或 `sub` 为键，绝不以所发送的令牌本身为键。

**密钥会轮换，而未知的密钥不是敲打签发方的手段。** 无法用
所持有的任何密钥验证的签名，每个 `MinRefresh` 值得重新获取一次密钥集，
无论是 `kid` 为新，还是同一个 `kid` 带着新密钥。
在获取过程中需要密钥集的令牌会等待它，而
失败的获取同样计数。

**`Username()` 给出哪个名称。** 默认是 `preferred_username`，然后是
`email`，**仅当 `email_verified` 为 true 时**，然后是 `sub`。未验证的电子邮件
是人员自己键入的字符串（OIDC Core §5.1）。配置了 `UsernameClaim` 时
按所指名的读取，不作回退。

## 它对照什么检查 {#what-it-is-checked-against}

**pyjwt** 为测试套件中的每个令牌签名，因此验证器从不由
出自同一人之手的签名者来评判。HMAC 混淆令牌是手工伪造的，
因为 pyjwt 拒绝生成它。`testdata/fixed.json`——pyjwt 用固定密钥
一次性签名的令牌——使各架构通道（包括 s390x）能够在固定时钟下
验证真实的签名。Linux 测试通道、竞态
检测器和覆盖率通道安装 pyjwt 并设置 `OIDC_REQUIRE_JUDGE`，因此缺少
pyjwt 会失败而不是跳过。接受 HMAC、按前缀比较签发方，以及跳过
audience 检查，都曾被有意尝试过，每一种都会使一个测试变红。覆盖率通道的下限是 90%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/oidc@v0.4.1](https://pkg.go.dev/github.com/go-authn/oidc@v0.4.1)
