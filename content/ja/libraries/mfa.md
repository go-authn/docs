---
title: "mfa — 十分な要素、そしてどれか"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa は、十分な数の、十分に異なる種類の要素が答えたかを判断し、どれが答えたかを述べる。デバイスも暗号も関与しない。"
tags: [ライブラリ, mfa, 要素]
---

**十分な数の要素が、十分な種類で答えたか。そしてどれか。** ここにはデバイスに届くものも暗号もありません。
`Factor` は *この人は今ここにいるか*と尋ねられるものなら何でもよく、このパッケージは答えの合計が
何になるかを判断します。

```sh
go get github.com/go-authn/mfa@v0.5.0
```

標準ライブラリ以外は何もインポートしません。

## 同じものが二つあっても一つの要素 {#two-of-the-same-thing-is-one-factor}

パスフレーズとリカバリーコードは、どちらも人が*知っている*ものです。一方を知った者は、たいてい
同じ場所からもう一方も知っています。そのため要素は何を証明するかを述べます。`Knowledge`、
`Possession`、`Inherence` です。そして通常「二要素」が意味するものを表すポリシーは
`Policy{Count: 2, DistinctKinds: true}` です。`Policy{Count: 2}` だけのものも用意されており、同じ種類の
鍵を意図的に二つ求める呼び出し側向けです。それは別のリクエストであり、綴りも異なります。

`Kind()` が `Unknown` の要素は、満たされた数には数えられますが、種類には数えられません。何かと
異なることを示せないからです。

## 例 {#example}

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

実際の要素は別の場所にあります。電話のコードには [totp]({{< relref "/libraries/totp.md" >}})、
セキュリティキーには [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) です。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

`Verify` は、誰かに尋ねる前に拒否します。

| | 理由 |
|---|---|
| `Count` が 1 未満の `Policy` | *a policy that requires 0 factors accepts anyone*。既定のポリシーはありません。どれだけの証明で十分かは、そのものを守る者が決めることです |
| `Count` より少ない要素しか与えられない | 何が答えても、ポリシーを満たせない |
| 列挙の外の `Kind()` を持つ要素 | 別個の種類として数えられ、パスフレーズの隣の `Kind(42)` が二要素として通ってしまう |
| **同じ要素が二度** | v0.3.0 より前は、同じパスフレーズを二度渡すと `Count: 2` を満たし、v0.4.0 より前は関数を保持する要素でも同様だった。「同じ」とは、同じ値を保持する同じ型で、関数も含む。関数は同じコードを実行するなら同じ関数である |

そして尋ねている間、三つのことを区別して保ちます。

- **尋ねられなかったことは拒否ではありません。** `ErrUnavailable` を返す要素 — 理由を保つ
  `mfa.Unavailable(err)` でラップされたもの — はそのように報告され (`Answer.Unavailable()`)、
  `StopOnFirstFailure` があっても試行を終わらせることはありません。
- **既定ではすべての要素に尋ねる**ので、*鍵は答えたが、指紋は答えなかった*と一回の試行で人に
  伝えられます。早く止めたいときのために `StopOnFirstFailure` があります。
- **到達しなかった要素は `Result.Answers` に項目を持ちません。** 失敗として報告すると、存在しない
  ものを探しに行かせてしまうからです。

`Result` は、ポリシーが満たされたかどうかにかかわらず返され、エラーは足りなかったものを、人が
対処できる言葉で述べます。

## 何に対して検証されているか {#what-it-is-checked-against}

外部の審判はありません。このモジュールには、食い違い得るプロトコルがないからです。その CI は
Linux、macOS、Windows で**文の 100% のカバレッジ**を要求し、レース検出器を実行し、amd64、arm64、
riscv64、loong64、ppc64le、s390x、386、arm でテストを実行します。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
