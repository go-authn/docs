---
title: "totp — 코드는 한 번만, 그리고 백만 번의 추측은 안 됨"
linkTitle: "totp"
weight: 20
description: "go-authn/totp는 RFC 6238 일회용 코드를 검사하고, 이미 사용된 코드를 거부하며, 비밀 값마다 추측을 제한하고, 그 결과를 mfa 인증 요소로 제공합니다."
tags: [라이브러리, totp, 인증 요소]
---

**이 여섯 자리 코드가 맞는가 — 그리고 전에 사용된 적이 있는가?** 시간 기반 일회용
비밀번호(RFC 6238), 서버가 기억해야 하는 것 — 이미 사용된 코드와 틀린 코드 — 을
기억하는 `Verifier`, 그리고 [mfa]({{< relref "/libraries/mfa.md" >}}) 정책이 요청할 수
있는 인증 요소.

```sh
go get github.com/go-authn/totp@v0.4.2
```

유일한 의존성은 `go-authn/mfa`입니다.

기본값은 모든 휴대전화가 가정하는 것입니다. 여섯 자리, 30초마다, HMAC-SHA1, 양쪽으로 한
단계의 허용 오차. `Options`로 `Digits`, `Period`, `Algorithm`(`SHA1`, `SHA256`,
`SHA512`), `Window`를 바꿉니다.

## 예제 {#example}

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

정책에서는 코드가 비밀번호를 검사하는 것 옆에서 `Possession` 종류의 인증 요소가
됩니다.

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

전화로 소리 내어 읽어 준 코드는 더 이상 소유가 아닙니다. 그 분류가 `DistinctKinds`가
의존하는 것입니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**이미 수락된 코드.** RFC 6238 §5.2: 검증자는 이미 성공한 OTP의 두 번째 시도를 받아들여서는
안 됩니다(MUST NOT). 상태가 없는 `totp.Verify`는 호출 사이에 아무것도 보유하지 않으므로
그럴 수 없습니다. 그래서 서버는 `*Verifier`를 사용하며, 이것은 마지막으로 수락한 단계
**까지의** 모든 단계를 `ErrUsed`로 거부합니다. 30초 전의 코드도 기본 윈도 안에 있기
때문입니다.

**`Verifier`가 없는 `Factor`.** nil `*Verifier`를 가진 `totp.Factor`는 Verifier가
없다고 말하며 모든 코드를 거부합니다. 사용 불가로 보고되지 않으므로 정책이 다른
인증 요소로 통과하여 실수를 숨길 수 없습니다.

**비밀 값별 추측.** `Verifier`는 틀린 코드를 이름별이 아니라 **자격 증명**별로 — SHA-256
형태로만 보유한 비밀 값 — 집계합니다. 이름은 호출자가 넘기는 임의의 문자열이며, v0.3.0
이전에는 `dora`, `Dora`, `DORA`가 하나의 비밀 값에 대한 세 개의 카운터였기 때문입니다.

| 필드 | 기본값 | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | `ErrThrottled` 전까지의 연속 틀린 코드. 그동안 보낸 코드는 보지 않으므로 올바른 코드조차 통과하지 못함 |
| `Pause` | `DefaultPause` = 15분 | 그것이 지속되는 시간 |
| `Lockout` | `DefaultLockout` = 100 | `ErrLockedOut` 전까지의, 얼마나 퍼져 있든 연속 틀린 코드. `Forget`만이 이를 풂 (NIST SP 800-63B §5.2.2) |

틀린 코드만 집계됩니다. 재생, 길이가 틀린 코드, 거부된 파라미터는 중지를 앞당기지
않습니다. 검사 전체가 하나의 락 아래에서 이루어지므로, 같은 순간에 보낸 추측도 하나씩
집계됩니다. `ErrLockedOut`은 `ErrThrottled`를 감싸므로, `errors.Is(err,
totp.ErrThrottled)`는 두 거부 모두에서 true이고 `errors.Is(err, totp.ErrLockedOut)`는
잠금에서만 true입니다.

**맞을 수 없는 파라미터:**

- 128비트 미만의 비밀 값(`MinSecret` = 16바이트, RFC 4226 R6), `Generate`, `At`,
  `Verify`, `Verifier.Verify`에서. `ParseSecret`은 여전히 이를 읽습니다. 파서이기
  때문입니다
- 정수 초가 아니거나 1초 미만인 주기
- 6자리 미만 또는 10자리 초과(RFC 4226 §5.3)
- `MaxWindow` = 양쪽으로 10단계보다 넓은 윈도. `0`은 기본값인 한 단계를 뜻하고,
  `NoWindow`는 현재 단계만 받아들입니다

윈도의 모든 단계는 일찍 멈추지 않고 시도되며, 비교는 상수 시간입니다. `ErrWrongCode`는
"틀림"과 "너무 오래됨"에 같은 오류입니다.

{{< callout type="warning" >}}
**비밀 값이 곧 자격 증명입니다**

그것을 가진 사람은 앞으로의 모든 코드를 만들어 냅니다. 여기의 어떤 오류 메시지도
코드나 비밀 값을 인용하지 않으며, 인증기가 QR 코드에서 읽는 `otpauth://` 문자열인
`URI`는 구조상 비밀 값을 담고 있습니다. 등록하는 사람을 위한 것이며 다른 누구를 위한
것도 아닙니다.
{{< /callout >}}

`Verifier`의 기억은 이 프로세스의 것입니다. 로드 밸런서 뒤의 서버 두 대는 각각 자신의
재생을 거부하고 자신의 추측을 집계합니다. 하나의 답이 필요한 배포 환경은 같은
인터페이스 뒤에 공유 저장소를 둡니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

- **pyotp**, Python 구현: 16바이트부터의 비밀 값 길이, 6~10자리, 네 가지 주기, 세
  알고리즘 전체에 걸친 무작위 사례 200개(`differential_test.go`). Linux 테스트 레인,
  레이스 감지기, 커버리지 레인이 이를 설치하며, 거기서는 `TOTP_REQUIRE_JUDGE`가 pyotp가
  없으면 건너뛰는 대신 실패하게 합니다.
- **RFC 6238 부록 B**, 여섯 시각과 세 알고리즘 전체, 그리고 **RFC 4226 부록 D**,
  카운터 0에서 9.
- 알고리즘마다 1000단계에 걸친 모든 자릿수를, 임의 정밀도로 다시 계산한 RFC 4226 §5.3과
  대조.

커버리지 레인은 95% 미만이면 실패하며(공표된 기준은 100%), 테스트는 여덟 개
아키텍처에서 실행됩니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/totp@v0.4.2](https://pkg.go.dev/github.com/go-authn/totp@v0.4.2)
