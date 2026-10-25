---
title: "totp — コードは一度だけ、百万回の推測は許さない"
linkTitle: "totp"
weight: 20
description: "go-authn/totp は RFC 6238 のワンタイムコードを確認し、すでに使われたコードを拒否し、シークレットごとに推測を制限し、その結果を mfa の要素として提供する。"
tags: [ライブラリ, totp, 要素]
---

**この六桁のコードは正しいか。そして以前に使われたことはないか。** 時間ベースのワンタイム
パスワード (RFC 6238)。サーバーが覚えておくべきこと、つまり使用済みのコードと間違ったコードを
覚えている `Verifier`。そして [mfa]({{< relref "/libraries/mfa.md" >}}) ポリシーが求められる要素です。

```sh
go get github.com/go-authn/totp@v0.4.2
```

唯一の依存関係は `go-authn/mfa` です。

既定値は、すべての電話が前提とするものです。六桁、30 秒ごと、HMAC-SHA1、前後それぞれ一ステップの
許容。`Options` は `Digits`、`Period`、`Algorithm` (`SHA1`、`SHA256`、`SHA512`)、`Window` を変更
します。

## 例 {#example}

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

ポリシーの中では、コードは種類 `Possession` の要素になり、パスワードを確認するものの隣に並びます。

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

電話で読み上げられたコードは、もはや所持ではありません。`DistinctKinds` が頼りにするのは、この
分類です。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**すでに受け入れられたコード。** RFC 6238 §5.2: 検証者は、すでに成功した OTP の二度目の試行を受け入れて
はならない (MUST NOT)。ステートレスな `totp.Verify` は、呼び出しの間に何も保持しないのでそれができ
ません。そのためサーバーは `*Verifier` を使い、これは最後に受け入れたステップ**まで**のすべての
ステップを `ErrUsed` で拒否します。30 秒前のコードは、既定のウィンドウの内側にまだあるからです。

**`Verifier` のない `Factor`。** nil の `*Verifier` を持つ `totp.Factor` は、Verifier がないと述べて、
すべてのコードを拒否します。利用不可としては報告されないので、ポリシーが他の要素で通って間違いを
隠すことはありません。

**推測、シークレットごと。** `Verifier` は間違ったコードを、名前ごとではなく**認証情報**ごと、つまり
SHA-256 としてのみ保持されるシークレットごとに数えます。名前は呼び出し側が渡す任意の文字列であり、
v0.3.0 より前は、`dora`、`Dora`、`DORA` が一つのシークレットに対する三つのカウンターだったからです。

| フィールド | 既定値 | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | `ErrThrottled` までの連続した間違ったコードの数。その間に送られたコードは見られないので、正しいものすら通らない |
| `Pause` | `DefaultPause` = 15 分 | それが続く時間 |
| `Lockout` | `DefaultLockout` = 100 | どれだけ間隔が空いても、`ErrLockedOut` までの連続した間違ったコードの数。これを解除できるのは `Forget` だけ (NIST SP 800-63B §5.2.2) |

間違ったコードだけが数えられます。リプレイ、長さの違うコード、拒否されたパラメーターは、一時停止を
近づけません。チェック全体が一つのロックの下で行われるので、同時に送られた推測は一つずつ数えられます。
`ErrLockedOut` は `ErrThrottled` をラップするので、`errors.Is(err, totp.ErrThrottled)` は両方の拒否で
true、`errors.Is(err, totp.ErrLockedOut)` はロックアウトでのみ true です。

**正しいはずのないパラメーター:**

- 128 ビット未満のシークレット (`MinSecret` = 16 バイト、RFC 4226 R6)。`Generate`、`At`、`Verify`、
  `Verifier.Verify` で。`ParseSecret` は読みます。パーサーだからです
- 整数秒でない、または一秒未満の周期
- 6 桁未満または 10 桁を超える桁数 (RFC 4226 §5.3)
- `MaxWindow` = 前後それぞれ 10 ステップより広いウィンドウ。`0` は既定の一ステップを意味し、
  `NoWindow` は現在のステップだけを受け入れます

ウィンドウ内のすべてのステップは、途中で止まらずに試され、比較は一定時間です。`ErrWrongCode` は
「間違い」と「古すぎる」で同じエラーです。

{{< callout type="warning" >}}
**シークレットが認証情報である**

それを持つ者は、将来のすべてのコードを生成します。ここのどのエラーメッセージも、コードやシークレットを
引用しません。そして `URI` — 認証アプリが QR コードから読む `otpauth://` 文字列 — は、構造上
シークレットを運びます。それは登録する本人のためのもので、他の誰のためでもありません。
{{< /callout >}}

`Verifier` の記憶は、このプロセスのものです。ロードバランサーの背後の二つのサーバーは、それぞれ
自分のリプレイを拒否し、自分の推測を数えます。一つの答えが必要なデプロイは、同じインターフェースの
背後に共有ストアを置きます。

## 何に対して検証されているか {#what-it-is-checked-against}

- **pyotp**、Python 実装: 16 バイトからのシークレット長、6 から 10 桁、四つの周期、三つのアルゴリズムすべて
  にまたがる 200 のランダムなケース (`differential_test.go`)。Linux のテストレーン、レース検出器、
  カバレッジレーンがそれをインストールし、そこでは `TOTP_REQUIRE_JUDGE` が、pyotp がないことを
  スキップではなく失敗にします。
- **RFC 6238 付録 B**、六つの時刻と三つのアルゴリズムすべて、および **RFC 4226 付録 D**、カウンター
  0 から 9。
- アルゴリズムごとに 1000 ステップにわたるすべての桁数を、任意精度で再計算した RFC 4226 §5.3 に
  対して。

カバレッジレーンは 95% を下回ると失敗し (宣言された基準は 100%)、テストは八つのアーキテクチャで実行
されます。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/totp@v0.4.2](https://pkg.go.dev/github.com/go-authn/totp@v0.4.2)
