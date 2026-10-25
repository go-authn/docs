---
title: "keyfactor — 已注册的密钥，被触摸过"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor 把安全密钥变成 mfa 因素，依据注册信息验证应答，而不是信任任何讲 CTAP 的设备。"
tags: [库, fido, mfa, 认证因素]
---

**已注册的那把密钥是否作出了应答，是否有人触摸过它？**
`keyfactor` 位于 [fido]({{< relref "/libraries/fido.md" >}})
与 [mfa]({{< relref "/libraries/mfa.md" >}}) 之间，前者讲 CTAP 而不了解任何策略，
后者决定多少证明才足够而不了解任何设备。两者互不导入；本模块同时导入两者。

```sh
go get github.com/go-authn/keyfactor@v0.4.2
```

在 v0.4.2，其 `go.mod` 至少要求 `go-authn/fido` v0.6.2 和
`go-authn/mfa` v0.5.0，即这些页面所描述的版本。

平台提供 `Opener`——如何在此系统上找到密钥——而且只提供这个。
其他一切在任何使用 CTAP 的地方都相同：断言、
检查、以及拒绝耗费某人最后一次 PIN 尝试机会。

## 示例 {#example}

```go
package main

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"

	"github.com/go-authn/fido"
	"github.com/go-authn/keyfactor"
	"github.com/go-authn/mfa"
)

func main() {
	// The platform supplies the Opener: how a key is found on this system.
	// This one finds nothing, and says so the way a policy understands.
	open := func(context.Context) (fido.Transport, error) {
		return nil, keyfactor.Unavailable(errors.New("no security key is plugged in"))
	}

	// From the registration: the credential ID and its public key, which
	// fido.AuthData.PublicKey returns from the attestation.
	var pub *ecdsa.PublicKey // nil here, to show the refusal

	f := keyfactor.New(open, keyfactor.Options{
		RPID:         "example.test",
		CredentialID: []byte{0x01, 0x02},
		PublicKey:    pub,
	})
	fmt.Println(f.Name(), f.Kind())

	_, err := mfa.Verify(context.Background(), mfa.Policy{Count: 1}, f)
	fmt.Println(err)
}
```

```
your security key possession
mfa: 1 factor(s) needed, 0 answered: your security key (possession): keyfactor: no public key for the credential; without one any device that answers would pass, so pass the one from the registration
```

拒绝发生在调用 `Opener` 之前。有了注册时的
公钥，同一个因素会打开密钥，要求它对
新的随机质询作出断言，并检查应答。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**设备作出应答并不等于密钥作出应答。** 可编程的 USB 板
和安全密钥一样会讲 CTAP，因此应答要对照
注册信息检查：

| 被拒绝的 | 信息 |
|---|---|
| 在打开任何内容之前：没有 `Opener`、没有 `RPID`、没有 `PublicKey`，或密钥不在 P-256 上 | `keyfactor: no opener; …`、`… needs a relying party id …`、`… no public key for the credential; …`、`… is not on P-256 …` |
| 依赖方哈希不是 `RPID` 的 SHA-256 | `… answered for another relying party` |
| 设备指名的凭据不是 `CredentialID` | `… answered with a credential other than the one asked for` |
| 对认证器数据和质询的签名并非 `PublicKey` 所生成 | `… answered with a signature the credential's key did not make` |
| 没有 `UP` 标志 | `… answered without anyone touching it` |
| 给出了 `PIN` 却没有 `UV` 标志 | `… was asked to establish who holds it and did not` |

**最后一次 PIN 尝试机会不会耗费在猜测上。** 首先会询问 `PINRetries`；
在被拔出之前不再接受任何 PIN 的密钥会被拒绝，剩余尝试次数
**为一次或更少**的密钥也是如此。在 CTAP 下，连续三个错误的 PIN
会阻塞密钥的 PIN，直到它被拔出，而重试计数器降到零
则永久阻塞：只有重置才能解除，会擦除其上的所有凭据。

当密钥本身拒绝 PIN 时，错误来自 fido，并且自 fido v0.6.2 起，
它会指明两种情形中正确的那一种：
当拔出可以解除阻塞时是
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`，
只有重置才能解除时是
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`。
在 fido v0.6.2 之前，这两句话是颠倒的。

**PIN 不是第二因素。** 种类仍是 `mfa.Possession`：输入密钥的 PIN
保护的是密钥，并不向这台机器识别任何人。

**空端口不是拒绝。** 找不到任何设备的 `Opener` 会用 `keyfactor.Unavailable`
包装其错误，将其标记为 `mfa.ErrUnavailable`，而策略会把*无法询问*
与*回答否*分开计数。

{{< callout type="warning" >}}
**它无法保护的：PIN 的哈希会到达任何作出应答的设备**

CTAP 让平台在签名之前，把 `LEFT(SHA-256(PIN), 16)` 交给密钥，并用
与设备本身协商的秘密加密。伪造的
设备会被拒绝作为因素，但它已经收到了该哈希，而较短的 PIN
经不起离线搜索。这就是协议。请使用较长的 PIN，并且不要
把 PIN 输入来源不明的密钥。
{{< /callout >}}

## 它对照什么检查 {#what-it-is-checked-against}

测试模拟的是**认证器**，而不是传输，它由
go-authn/fido 自己导出的帧格式构建：CTAPHID 握手、CTAP2 断言，
以及 ClientPIN 交换。PIN 部分独立地扮演认证器一方的协议二——
自己的 ECDH、HKDF 和 AES-CBC，依据规范编写
（`fakepin_test.go`）——因此相差一个字节的派生
都会使交换失败。`forged_test.go` 是不持有任何凭据的设备。覆盖率保持
100%，测试在八种架构上运行。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2)
