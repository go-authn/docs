---
title: "fido — 与安全密钥通信"
linkTitle: "fido"
weight: 30
description: "go-authn/fido 通过任何 64 字节传输与安全密钥进行 CTAPHID 和 CTAP2 通信：握手、注册、断言和 PIN，纯 Go 实现。"
tags: [库, fido, 认证因素]
---

**如何与安全密钥通信？** FIDO 客户端到认证器协议
——CTAPHID 帧格式、通道握手，以及注册凭据、
请求签名并用 PIN 换取令牌的 CTAP2 命令——纯 Go 实现，
适用于任何操作系统。

```sh
go get github.com/go-authn/fido@v0.6.2
```

这里没有任何平台相关的内容。`Transport` 在一个认证器之间
双向传送 64 字节报告，并说明设备的名称；这些报告
从哪里来——macOS 上的 IOKit、Linux 上的 hidraw、浏览器中的 WebHID——
是别人的包的事。在它之上的一切都在这里：

| | |
|---|---|
| `Open(ctx, t)` | 在广播通道上进行 `INIT` 握手；返回带有自己通道的 `*Key`。`Key` 拥有 `t`：`Close` 会关闭它，失败的 `Open` 也会 |
| `Key.Ping`、`Key.Wink` | 一次往返和一次闪烁——询问*这些密钥中哪个是这一把？*的最便宜方式 |
| `Key.GetInfo` | 版本、扩展、AAGUID、选项、PIN 协议 |
| `Key.MakeCredential`、`Key.GetAssertion` | 注册和签名；`ParseAuthData` 读取认证器数据，而 `AuthData.PublicKey` 把 P-256 COSE 密钥转换为 `*ecdsa.PublicKey` |
| `Key.PINRetries`、`Key.KeyAgreement`、`Key.PINToken` | `authenticatorClientPIN`，两种 PIN/UV 认证协议 |
| `Split`、`NewReassembler`、`ParseInit`、`Key.CBOR` | 帧格式，导出供以其他方式驱动密钥的人使用 |

`AuthData.PublicKey` 是转换而不是验证：哪些算法
算数，以及对倒退的签名计数器怎么办，属于调用方的事。
[keyfactor]({{< relref "/libraries/keyfactor.md" >}})就是这样的一个
调用方。

## 示例 {#example}

仅帧格式，没有密钥：一条消息被切分为报告，再被
重新拼合。

```go
package main

import (
	"bytes"
	"fmt"

	"github.com/go-authn/fido"
)

func main() {
	// A 200-byte ping, cut into the 64-byte reports a key reads...
	payload := bytes.Repeat([]byte{0xA5}, 200)
	reports, err := fido.Split(0x01020304, fido.CmdPing, payload)
	if err != nil {
		panic(err)
	}
	fmt.Println(len(reports), "reports of", len(reports[0]), "bytes")

	// ...and put back together, as a reply would be.
	r := fido.NewReassembler(0x01020304)
	for _, rep := range reports {
		msg, done, err := r.Feed(rep)
		if err != nil {
			panic(err)
		}
		if done {
			fmt.Println(bytes.Equal(msg.Data, payload), msg.Cmd == fido.CmdPing)
		}
	}

	// A report for another channel is an error, not something to drop.
	other, _ := fido.Split(0x0A0B0C0D, fido.CmdPing, []byte("hi"))
	_, _, err = fido.NewReassembler(0x01020304).Feed(other[0])
	fmt.Println(err)

	// The framing's real limit, not the length field's.
	fmt.Println(fido.MaxMessage)
}
```

```
4 reports of 64 bytes
true true
fido: the report belongs to another channel
7609
```

有密钥时，`fido.Open(ctx, transport)` 完成握手，它
返回的 `*Key` 承载之后的每个命令。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**不信任密钥会如实回答所问的问题。** 携带的命令与所发送命令
不同的应答会被拒绝（CTAP 2.1 §11.2.9 为每个
响应指定了自己的命令，libfido2 也会检查）。nonce 不是所发送 nonce 的
`INIT` 应答会被拒绝：那是同一把密钥上另一个程序的握手。长度不符合其协议的
PIN 令牌——协议一下为 16 或 32 字节，协议二下恰好为 32——会被拒绝。

**保活不是应答。** 等待手指触摸的密钥大约每一百毫秒发送一次
`CTAPHID_KEEPALIVE`；它会被跳过，而触摸可以花多长时间，
唯一的限制是上下文。

**比帧格式所能承载的更长的消息。** 两个长度字节本可以允许
65535，但初始化数据包中的 57 个字节加上 128 个各 59 字节的后续数据包
是 7609（`MaxMessage`）；超过它，序列号会达到 `0x80`，而密钥
会把它读作新消息。`Split` 返回 `ErrTooLong`。

**对不上的报告**：属于另一个通道的报告（`ErrWrongChannel`——
同一把密钥上有两个程序）、乱序的后续数据包（`ErrOutOfOrder`）、
短于一个数据包的报告（`ErrShortPacket`）、短于其 17 字节的 `INIT` 应答
（`ErrTruncated`）。

**密钥没有声明支持的命令。** 不会向没有 `CapWink` 的密钥发送 `Wink`，
也不会向没有 `CapCBOR` 的密钥发送 `GetInfo`：密钥会答复
`CTAPHID_ERROR`，而调用方就得把这种拒绝与故障区分开。

**空 PIN**，以及 `AuthData.PublicKey` 中 P-256 之外的任何类型——按名称
拒绝，而不是只解码一半。

{{< callout type="warning" >}}
**错误的 PIN 会消耗一次重试机会**

CTAP 给认证器设有 PIN 重试计数器，最多八次，每个
错误的 PIN 消耗一次。连续三个错误的 PIN 会阻塞 PIN，直到密钥被
拔出再插入。计数器降到零则永久阻塞：
只有重置才能解除，而重置会擦除密钥上的所有凭据。在提示任何人之前
请先询问 `Key.PINRetries`：它会说明还剩多少次重试，
以及密钥是否在等待被拔出。

当密钥拒绝 PIN 时，错误信息会说明是两种情形中的哪一种。
CTAP2_ERR_PIN_AUTH_BLOCKED（`0x34`），拔出即可解除，其信息为
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`；
CTAP2_ERR_PIN_BLOCKED（`0x32`），只有重置才能解除，其信息为
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`。
在 v0.6.2 之前，这两句话是颠倒的：只需拔出的密钥
被说成已被锁定，而被如此告知的人可能会重置它，
从而丢失密钥上的所有凭据。
{{< /callout >}}

## 它对照什么检查 {#what-it-is-checked-against}

CI 中没有安全密钥，因此测试使用一个会重新拼合所收内容的
假传输——一把拒绝、停滞、不断说自己忙碌，或与另一个程序共用
通道的密钥——覆盖率保持 100%。有两个测试夹具
来自此代码之外：

- `testdata/yubikey-fido-5.7.4-getinfo.hex`，**从 YubiKey FIDO 5.7.4
  捕获**的 `GetInfo` 应答，由 `ctap2_test.go` 解码；
- `testdata/webauthn-reference-authdata.b64`，取自
  **go-webauthn/webauthn** 测试的样本，用于检查认证器数据解析器和
  `AuthData.PublicKey`。

状态码表遵循 libfido2 的 `err.h`。该模块的 README 记录了
针对真实 YubiKey 运行的一次注册和一次断言，并用其交出的公钥验证了签名；
该运行不属于 CI。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/fido@v0.6.2](https://pkg.go.dev/github.com/go-authn/fido@v0.6.2)
