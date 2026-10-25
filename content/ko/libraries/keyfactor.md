---
title: "keyfactor — 등록된 키, 터치됨"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor는 보안 키를 mfa 인증 요소로 바꾸며, CTAP를 사용하는 어떤 장치든 신뢰하는 대신 등록 정보에 대해 응답을 검증합니다."
tags: [라이브러리, fido, mfa, 인증 요소]
---

**등록된 키가 답했는가, 그리고 사람이 그것을 만졌는가?** `keyfactor`는 CTAP로
통신하며 어떤 정책도 알지 못하는 [fido]({{< relref "/libraries/fido.md" >}})와, 얼마나
많은 증명이 충분한지를 결정하며 어떤 장치도 알지 못하는 [mfa]({{< relref "/libraries/mfa.md" >}})
사이의 유일한 부분입니다. 둘은 서로를 가져오지 않으며, 이 모듈이 둘을 모두 가져옵니다.

```sh
go get github.com/go-authn/keyfactor@v0.4.2
```

v0.4.2의 `go.mod`는 최소 `go-authn/fido` v0.6.2와 `go-authn/mfa` v0.5.0, 즉 이
문서가 설명하는 버전을 요구합니다.

플랫폼은 `Opener` — 이 시스템에서 키를 찾는 방법 — 를 제공하며 그것만 담당합니다.
그 밖의 모든 것은 CTAP가 있는 곳 어디서나 같습니다. 어서션, 검사, 누군가의 마지막 PIN
시도를 소모하기를 거부하는 것.

## 예제 {#example}

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

거부는 `Opener`가 호출되기 전에 일어납니다. 등록 정보의 공개 키가 있으면, 같은
인증 요소가 키를 열고, 새로운 무작위 챌린지에 대한 어서션을 요청하고, 응답을
검사합니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**장치가 응답한다고 해서 키가 응답하는 것은 아닙니다.** 프로그래밍 가능한 USB 보드도
보안 키만큼 잘 CTAP로 통신하므로, 응답은 등록 정보와 대조하여 검사합니다.

| 거부되는 것 | 메시지 |
|---|---|
| 아무것도 열기 전에: `Opener` 없음, `RPID` 없음, `PublicKey` 없음, 또는 P-256이 아닌 키 | `keyfactor: no opener; …`, `… needs a relying party id …`, `… no public key for the credential; …`, `… is not on P-256 …` |
| `RPID`의 SHA-256이 아닌 신뢰 당사자 해시 | `… answered for another relying party` |
| 장치가 지명하는 경우, `CredentialID`가 아닌 자격 증명 | `… answered with a credential other than the one asked for` |
| `PublicKey`가 만들지 않은, 인증기 데이터와 챌린지에 대한 서명 | `… answered with a signature the credential's key did not make` |
| `UP` 플래그 없음 | `… answered without anyone touching it` |
| `PIN`이 주어졌는데 `UV` 플래그 없음 | `… was asked to establish who holds it and did not` |

**마지막 PIN 시도를 추측에 쓰지 않습니다.** `PINRetries`를 먼저 묻습니다. 뽑기 전에는
더 이상 PIN을 받지 않는 키는 거부되고, **시도가 한 번 이하** 남은 키도 거부됩니다.
CTAP에서는 연속 세 번 잘못된 PIN이 키를 뽑을 때까지 PIN을 막으며, 재시도 카운터가 0에
도달하면 영구히 막혀 초기화만이 이를 풀고 모든 자격 증명을 지웁니다.

키 자체가 PIN을 거부하면 오류는 fido의 것이며, fido v0.6.2부터 둘 중 맞는 쪽을
지명합니다. 뽑으면 풀리는 경우에는
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`,
초기화만이 푸는 경우에는
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`.
fido v0.6.2 이전에는 두 문장이 바뀌어 있었습니다.

**PIN은 두 번째 인증 요소가 아닙니다.** 종류는 `mfa.Possession`으로 유지됩니다. 키에
입력한 PIN은 키를 보호하며, 이 머신에 누구도 식별해 주지 않습니다.

**빈 포트는 거부가 아닙니다.** 아무것도 찾지 못하는 `Opener`는 오류를
`keyfactor.Unavailable`로 감싸며, 이는 `mfa.ErrUnavailable`로 표시하고 정책은 *물어볼
수 없었음*과 *아니라고 했음*을 구별하여 집계합니다.

{{< callout type="warning" >}}
**보호할 수 없는 것: PIN의 해시는 응답하는 모든 장치에 도달합니다**

CTAP는 무엇이든 서명하기 전에, 플랫폼이 장치 자체와 합의한 비밀 값으로 암호화하여
`LEFT(SHA-256(PIN), 16)`을 키에 건네게 합니다. 위조된 장치는 인증 요소로서
거부되지만, 그 해시를 이미 받았으며 짧은 PIN은 오프라인 탐색에 무너집니다. 이것이
프로토콜입니다. 긴 PIN을 사용하고, 출처를 알 수 없는 키에는 PIN을 입력하지 마십시오.
{{< /callout >}}

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

테스트는 전송이 아니라 **인증기**를 흉내 내며, go-authn/fido 자체의 공개된 프레이밍으로
만듭니다. CTAPHID 핸드셰이크, CTAP2 어서션, ClientPIN 교환입니다. PIN 쪽은 프로토콜 2의
인증기 측을 독립적으로 연기합니다. 자체 ECDH, HKDF, AES-CBC를 사양에서 직접 작성한
것(`fakepin_test.go`)이므로, 한 바이트라도 다른 파생은 교환에 실패합니다.
`forged_test.go`는 자격 증명을 갖지 않은 장치입니다. 커버리지는 100%로 유지되며,
테스트는 여덟 개 아키텍처에서 실행됩니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2)
