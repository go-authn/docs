---
title: "totp — 代码只能用一次，而不是一百万次猜测"
linkTitle: "totp"
weight: 20
description: "go-authn/totp 检查 RFC 6238 一次性代码，拒绝已使用过的代码，按密钥限制猜测，并将结果作为 mfa 因素提供。"
tags: [库, totp, 认证因素]
---

**这个六位数字代码是否正确——以前是否用过？** 基于时间的
一次性密码（RFC 6238）；一个 `Verifier`，它记住服务器
必须记住的内容，即已使用的代码和错误的代码；以及可被
[mfa]({{< relref "/libraries/mfa.md" >}})策略请求的因素。

```sh
go get github.com/go-authn/totp@v0.4.2
```

它唯一的依赖是 `go-authn/mfa`。

默认值是每部手机都假定的：六位数字、每 30 秒一次、
HMAC-SHA1、前后各容忍一步。`Options` 可更改 `Digits`、
`Period`、`Algorithm`（`SHA1`、`SHA256`、`SHA512`）和 `Window`。

## 示例 {#example}

```go
package main

import (
	"fmt"
	"time"

	"github.com/go-authn/totp"
)

func main() {
	secret, err := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	if err != nil {
		panic(err)
	}
	now := time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)
	o := totp.Options{Now: func() time.Time { return now }}

	code, _ := totp.At(secret, now, o) // what the phone shows
	fmt.Println(code)

	v := &totp.Verifier{Options: o}
	fmt.Println(v.Verify("dora", secret, []byte(code))) // accepted
	fmt.Println(v.Verify("dora", secret, []byte(code))) // the same code again
	fmt.Println(v.Verify("Dora", secret, []byte(code))) // another spelling, same secret

	// A secret shorter than 128 bits makes no code.
	short, _ := totp.ParseSecret("JBSWY3DPEHPK3PXP")
	_, err = totp.At(short, now, o)
	fmt.Println(err)
}
```

```
395621
<nil>
totp: that code has already been used
totp: that code has already been used
totp: a secret of 80 bits; RFC 4226 requires at least 128
```

在策略中，代码成为 `Possession` 种类的因素，与
检查密码的因素并列：

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/mfa"
	"github.com/go-authn/totp"
)

// knows stands in for whatever checks the password.
type knows struct{}

func (knows) Name() string                 { return "your password" }
func (knows) Kind() mfa.Kind               { return mfa.Knowledge }
func (knows) Verify(context.Context) error { return nil }

func main() {
	ctx := context.Background()
	secret, _ := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	verifier := &totp.Verifier{} // one per server, kept: it remembers used codes
	code := []byte("123456")     // what the person typed

	_, err := mfa.Verify(ctx, mfa.Policy{Count: 2, DistinctKinds: true},
		knows{},
		totp.Factor("dora", secret, code, verifier),
	)
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
```

通过电话大声读出的代码就不再是持有物；
`DistinctKinds` 所依赖的正是这种分类。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**已经被接受的代码。** RFC 6238 §5.2：验证方不得接受对已成功的 OTP
的第二次尝试。无状态的 `totp.Verify`
做不到——它在两次调用之间不保存任何内容——因此服务器使用 `*Verifier`，它
对**截至并包括**其最后接受的那一步的每一步都以 `ErrUsed` 拒绝：
三十秒之前的代码仍然在默认窗口之内。

**没有 `Verifier` 的 `Factor`。** 带有 nil `*Verifier` 的 `totp.Factor`
会拒绝每个代码，并说明缺少 Verifier。它不会被报告为
不可用，因此策略无法越过其他因素而掩盖这个错误。

**按密钥限制猜测。** `Verifier` 按**凭据**统计错误代码——
即密钥，仅以其 SHA-256 形式保存——而不是按名称，因为名称
是调用方传入的任意字符串，而在 v0.3.0 之前，`dora`、`Dora` 和 `DORA`
是同一个密钥的三个计数器。

| 字段 | 默认值 | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | 在 `ErrThrottled` 之前连续的错误代码数；期间发送的代码不会被查看，因此连正确的代码也不会通过 |
| `Pause` | `DefaultPause` = 15 分钟 | 上述状态持续多久 |
| `Lockout` | `DefaultLockout` = 100 | 在 `ErrLockedOut` 之前连续的错误代码数，无论间隔多久，只有 `Forget` 才能解除（NIST SP 800-63B §5.2.2） |

只有错误的代码才计数；重放、长度错误的代码或被拒绝的
参数不会使暂停更近。整个检查在一把
锁下进行，因此同一时刻发送的猜测会被逐个计数。
`ErrLockedOut` 包装 `ErrThrottled`，因此对两种拒绝，`errors.Is(err, totp.ErrThrottled)` 都为
真，而 `errors.Is(err, totp.ErrLockedOut)` 仅对
锁定为真。

**不可能正确的参数：**

- 不足 128 位的密钥（`MinSecret` = 16 字节，RFC 4226 R6），在
  `Generate`、`At`、`Verify` 和 `Verifier.Verify` 中。`ParseSecret` 仍然会读取
  这样的密钥：它只是解析器；
- 不是整数秒的周期，或小于一秒的周期；
- 少于 6 位或多于 10 位的数字（RFC 4226 §5.3）；
- 比 `MaxWindow` = 前后各 10 步更宽的窗口。`0` 表示
  默认的一步；`NoWindow` 只接受当前这一步。

窗口内的每一步都会被尝试而不提前停止，并且比较是
常量时间的。`ErrWrongCode` 对“错误”和“太旧”是同一个错误。

{{< callout type="warning" >}}
**密钥就是凭据**

持有它的人可以生成之后的每一个代码。这里没有任何错误信息会引用
代码或密钥，而 `URI`——认证器从二维码读取的 `otpauth://` 字符串——
在构造上就携带密钥：它只供登记的人员使用，
不供任何其他人使用。
{{< /callout >}}

`Verifier` 的记忆属于本进程。负载均衡器之后的两个服务器
各自拒绝自己的重放并统计自己的猜测；需要统一答案的部署
应在同一接口后放置共享存储。

## 它对照什么检查 {#what-it-is-checked-against}

- **pyotp**，一个 Python 实现：200 个随机用例，涵盖从 16 字节起的
  各种密钥长度、6 到 10 位数字、四种周期以及全部三种算法
  （`differential_test.go`）。Linux 测试通道、竞态检测器和
  覆盖率通道安装它，并且在那里 `TOTP_REQUIRE_JUDGE` 使缺少
  pyotp 成为失败而不是跳过。
- **RFC 6238 附录 B**，全部六个时间和全部三种算法，以及
  **RFC 4226 附录 D**，计数器 0 到 9。
- 每种位数，每种算法 1000 步，对照以任意精度
  重新计算的 RFC 4226 §5.3。

覆盖率通道在低于 95% 时失败（其声明的标准是 100%），
测试在八种架构上运行。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/totp@v0.4.2](https://pkg.go.dev/github.com/go-authn/totp@v0.4.2)
