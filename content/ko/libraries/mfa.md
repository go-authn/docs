---
title: "mfa — 충분한 인증 요소, 그리고 어느 것들인가"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa는 충분한 수의 인증 요소가, 충분히 다른 종류로 답했는지를 판단하고 어느 것들이 답했는지 알려 줍니다 — 장치도 암호도 없이."
tags: [라이브러리, mfa, 인증 요소]
---

**충분한 인증 요소가 충분한 종류에서 답했는가 — 그리고 어느 것들인가?** 여기서는
장치에 접근하는 것이 없고 암호도 없습니다. `Factor`는 *이 사람이 지금 여기 있는가?*라고
물을 수 있는 무엇이든 되며, 이 패키지는 답이 합쳐서 무엇이 되는지를 판단합니다.

```sh
go get github.com/go-authn/mfa@v0.5.0
```

표준 라이브러리 밖의 것은 가져오지 않습니다.

## 같은 것 둘은 인증 요소 하나입니다 {#two-of-the-same-thing-is-one-factor}

암호문과 복구 코드는 둘 다 사람이 *아는* 것입니다. 하나를 알게 된 사람은 보통 같은
곳에서 다른 하나도 알게 됩니다. 그래서 인증 요소는 자신이 무엇을 증명하는지 —
`Knowledge`, `Possession`, `Inherence` — 밝히며, 보통 *2단계 인증*이라는 말이 뜻하는
정책은 `Policy{Count: 2, DistinctKinds: true}`입니다. `Policy{Count: 2}`만 쓰는 것도
제공되는데, 같은 종류의 키 두 개를 일부러 원하는 호출자를 위한 것이며 다른 요청이므로
다르게 표기됩니다.

`Kind()`가 `Unknown`인 인증 요소는 충족된 수에는 집계되지만 종류에는 절대 집계되지
않습니다. 무엇과 다르다는 것을 보일 수 없기 때문입니다.

## 예제 {#example}

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

실제 인증 요소는 다른 곳에 있습니다. 휴대전화의 코드는
[totp]({{< relref "/libraries/totp.md" >}}), 보안 키는
[keyfactor]({{< relref "/libraries/keyfactor.md" >}}).

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

`Verify`는 누구에게 묻기 전에 거부합니다.

| | 이유 |
|---|---|
| `Count`가 1 미만인 `Policy` | *a policy that requires 0 factors accepts anyone*. 기본 정책은 없습니다. 증명이 얼마나 필요한지는 그것을 보호하는 쪽에 속합니다 |
| `Count`보다 적게 제공된 인증 요소 | 정책은 그들이 무엇이라고 답하든 충족될 수 없습니다 |
| `Kind()`가 열거형 밖인 인증 요소 | 별개의 종류로 집계됩니다. 암호문 옆의 `Kind(42)`는 2단계 인증으로 통과하게 됩니다 |
| **같은 인증 요소를 두 번** | v0.3.0 이전에는 같은 암호문을 두 번 건네면 `Count: 2`를 충족했고, v0.4.0 이전에는 함수를 가진 인증 요소도 그랬습니다. "같다"는 것은 같은 값을 가진 같은 타입이며, 함수도 포함합니다. 함수는 같은 코드를 실행하면 같은 함수입니다 |

그리고 묻는 동안 세 가지를 구별합니다.

- **물어볼 수 없었던 것은 거부가 아닙니다.** `ErrUnavailable`을 반환하는 인증 요소 —
  이유를 유지하는 `mfa.Unavailable(err)`로 감쌈 — 는 그렇게 보고되며
  (`Answer.Unavailable()`), `StopOnFirstFailure`가 있어도 시도를 끝내지 않습니다.
- **기본적으로 모든 인증 요소에게 묻습니다.** 그래서 한 번의 시도에서 *키는 답했고
  지문은 답하지 않았습니다*라고 사람에게 알려 줄 수 있습니다. 일찍 멈추고 싶을 때를
  위해 `StopOnFirstFailure`가 있습니다.
- **도달하지 못한 인증 요소는 `Result.Answers`에 항목이 없습니다.** 실패했다고 보고하면
  아무것도 아닌 것을 찾아다니게 됩니다.

`Result`는 정책이 충족되었는지와 상관없이 반환되며, 오류는 사람이 조치할 수 있는
말로 무엇이 빠졌는지를 지명합니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

외부 판정자는 없습니다. 이 모듈에는 어긋날 프로토콜이 없습니다. CI는 Linux, macOS,
Windows에서 **100% 구문 커버리지**를 요구하고, 레이스 감지기를 실행하며, amd64, arm64,
riscv64, loong64, ppc64le, s390x, 386, arm에서 테스트를 실행합니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
