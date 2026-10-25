---
title: "mfa — 足够的因素，以及是哪些"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa 判定是否有足够多、足够多种类的因素作出了应答，并说明是哪些——不涉及设备，也不涉及密码学。"
tags: [库, mfa, 认证因素]
---

**是否有足够多、足够多种类的因素作出了应答——是哪些？** 这里没有任何内容
会接触设备，也没有密码学：`Factor` 是任何可以被询问
*此人此刻是否在场？* 的东西，而本包判定这些应答加起来意味着什么。

```sh
go get github.com/go-authn/mfa@v0.5.0
```

它不导入标准库之外的任何内容。

## 同类的两个就是一个因素 {#two-of-the-same-thing-is-one-factor}

口令和恢复码都是人员*知道*的东西：学到其中一个的人
通常也能从同一个地方学到另一个。因此因素
会说明它证明什么——`Knowledge`、`Possession` 或 `Inherence`——而表示通常所理解的
*双因素* 含义的策略是
`Policy{Count: 2, DistinctKinds: true}`。单独的 `Policy{Count: 2}` 也
可以使用，供有意需要同一种类的两把密钥的调用方使用；它是
不同的请求，写法也不同。

`Kind()` 为 `Unknown` 的因素计入已满足的数量，但绝不
计入种类：无法证明它与任何东西不同。

## 示例 {#example}

```go
package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/go-authn/mfa"
)

// factor is the smallest mfa.Factor: a name, a kind, and an answer.
type factor struct {
	name string
	kind mfa.Kind
	err  error
}

func (f factor) Name() string                 { return f.name }
func (f factor) Kind() mfa.Kind               { return f.kind }
func (f factor) Verify(context.Context) error { return f.err }

func main() {
	ctx := context.Background()
	twoFactor := mfa.Policy{Count: 2, DistinctKinds: true}

	// Two things the person knows are one kind of proof.
	_, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"a recovery code", mfa.Knowledge, nil},
	)
	fmt.Println(err)

	// A key that is not plugged in has not refused anybody.
	r, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"your security key", mfa.Possession, mfa.Unavailable(errors.New("no key attached"))},
	)
	fmt.Println(err)
	fmt.Println(r.Answers[1].Unavailable())

	// The zero Policy is refused, not guessed at.
	_, err = mfa.Verify(ctx, mfa.Policy{}, factor{"your passphrase", mfa.Knowledge, nil})
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) answered but only 1 kind(s) among them (knowledge); two of the same kind are not two factors
mfa: 2 factor(s) needed, 1 answered: your security key (possession): not available
true
mfa: a policy that requires 0 factors accepts anyone
```

真正的因素位于别处：[totp]({{< relref "/libraries/totp.md" >}})
对应来自手机的代码，[keyfactor]({{< relref "/libraries/keyfactor.md" >}})
对应安全密钥。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

`Verify` 在询问任何人之前就会拒绝：

| | 原因 |
|---|---|
| `Count` 小于一的 `Policy` | *a policy that requires 0 factors accepts anyone*。没有默认策略：多少证明才足够，取决于保护该对象的人 |
| 提供的因素少于 `Count` | 无论它们如何作答，策略都无法满足 |
| `Kind()` 在枚举之外的因素 | 若被算作不同的种类，则 `Kind(42)` 与口令放在一起就会算作双因素 |
| **同一个因素出现两次** | 在 v0.3.0 之前，同一个口令传入两次就能满足 `Count: 2`，而在 v0.4.0 之前，任何持有函数的因素也是如此。“相同”指类型相同且持有的值相同，包括函数：函数运行同样的代码时就是同一个函数 |

并且在询问时它把三件事分开：

- **无法被询问不是拒绝。** 返回
  `ErrUnavailable` 的因素——由保留原因的 `mfa.Unavailable(err)` 包装——会
  如此报告（`Answer.Unavailable()`），并且即使使用 `StopOnFirstFailure`，
  也绝不会结束一次尝试。
- **默认询问每个因素**，因此可以在一次尝试中告知某人*你的密钥
  应答了，你的指纹没有*。需要提前停止时可使用
  `StopOnFirstFailure`。
- **未被问及的因素在 `Result.Answers` 中没有条目**：把它报告为
  失败，会让人白白去追查不存在的问题。

无论策略是否满足，都会返回 `Result`，同时错误会
用人可以据以行动的措辞指明缺少什么。

## 它对照什么检查 {#what-it-is-checked-against}

没有外部评判者：本模块不持有任何可能与之不一致的协议。其 CI
要求在 Linux、macOS 和 Windows 上达到**100% 的语句覆盖率**，运行竞态
检测器，并在 amd64、arm64、riscv64、loong64、ppc64le、s390x、
386 和 arm 上运行测试。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
