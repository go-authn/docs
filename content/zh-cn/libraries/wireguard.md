---
title: "wireguard — 这把密钥是谁的，它是否可以连接？"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard 严格定义 WireGuard 公钥，并携带由提供方签名的已注册密钥列表，网关会将其转换为对端。"
tags: [库, wireguard, 令牌]
---

**这把 WireGuard 密钥是否可以连接，它是谁的？** WireGuard 仅凭
对端的静态公钥来认证对端，别无其他：没有证书，没有过期，
没有吊销。因此这个问题要在协议之外回答，并且每当
答案改变时都要重新回答。提供方——
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}})——回答它；本
模块是提供方与网关达成一致的内容。

```sh
go get github.com/go-authn/wireguard@v0.1.1
```

它唯一的依赖是 [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0，
用于验证列表。

它做两件事：`ParseKey` 说明什么是公钥，而 `Source.Fetch`
获取提供方对人员已注册密钥的签名 `List`，每个密钥是一个 `Peer`，
带有其 `Key`、`Subject`、`Username`、`Device` 以及租期结束时间。

{{< callout type="info" >}}
**这里只经手公钥**

私钥在设备上生成，从不离开设备；本包中没有任何
位置容纳私钥。
{{< /callout >}}

## 示例 {#example}

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

网关保留一个 `Source` 并获取列表：

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource` 在启动时读取提供方的配置。`Fetch` 为网关自己获取
令牌（`client_credentials`，scope `wireguard_peers`），
从签发方之下的 `/wireguard/peers` 获取列表，并用 go-authn/oidc 验证它：
对照提供方密钥集的签名、签发方、
audience（本网关的 `ClientID`）、过期时间，以及 `typ`
`wireguard-peers+jwt`（`ListType`）——因此访问令牌和 ID
令牌都不能冒充列表，列表也不能冒充令牌。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**密钥**（`ParseKey`）：

- 同一字节的任何其他写法。解码是严格的，文本
  必须能原样打印回来，因此以文本为键的存储不会把
  一把密钥以两个名称存两次；
- 低阶点，其中包括全零密钥。与它进行的每次交换
  无论对方的密钥是什么，都得到相同的共享秘密（RFC 7748 §6.1），
  因此它不认证任何人。`crypto/ecdh` 通过计算
  一次交换来判定，所以最高位变体也会被拒绝。

**列表**（`Fetch`）：

| | 原因 |
|---|---|
| `version` 低于此 `Source` 已接受的版本的列表 | 旧列表同样有签名，并且可能列出此后已被收回的密钥 |
| 列出两次的密钥 | 无论网关保留哪一个，另一个人的流量都会以错误的名称到达 |
| 没有 subject 的对端 | 它不属于任何人 |
| 不是密钥的密钥 | 见上文 |
| 明文的签发方或令牌端点，环回地址除外 | 网关的密钥和列表会穿过任何人都能读取的链路 |
| 没有 `ClientID` 和 `ClientSecret` 的 `SourceConfig` | 网关是以自己的客户端身份读取列表的 |

列表带有 `exp`：到那时仍无法获取较新列表的网关，没有
列表，而不是持有过时的列表。`Peer.Subject` 是注册该密钥的客户端所看到的
人员的 `sub`，公开的或成对的——也就是网关在该人员的
访问令牌中同样会看到的值。

## 它对照什么检查 {#what-it-is-checked-against}

**`wg(8)` 本身**，来自 wireguard-tools，生成 `ParseKey` 必须
接受的密钥。它安装在 Linux 测试通道、竞态检测器和
覆盖率通道中，这些通道设置 `WIREGUARD_REQUIRE_JUDGE=1`，因此缺少 `wg` 会失败
而不是跳过。低阶测试检查 libsodium 列出的七个点，
每个都分别带有和不带最高位。覆盖率下限是 100%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.1](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.1)
