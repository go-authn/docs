---
title: "fido — 보안 키와 통신하기"
linkTitle: "fido"
weight: 30
description: "go-authn/fido는 모든 64바이트 전송 위에서 보안 키와 CTAPHID 및 CTAP2로 통신합니다: 핸드셰이크, 등록, 어서션, PIN을 순수 Go로."
tags: [라이브러리, fido, 인증 요소]
---

**보안 키와 어떻게 통신하는가?** FIDO 클라이언트-인증기 프로토콜 — CTAPHID
프레이밍, 채널 핸드셰이크, 그리고 자격 증명을 등록하고, 서명을 요청하고, PIN을
토큰으로 교환하는 CTAP2 명령 — 을 어떤 운영 체제에서든 순수 Go로 제공합니다.

```sh
go get github.com/go-authn/fido@v0.6.2
```

여기에는 플랫폼에 종속된 것이 없습니다. `Transport`는 64바이트 리포트를 인증기 하나와
주고받고 장치의 이름을 알려 줍니다. 그 리포트가 어디서 오는지 — macOS의 IOKit,
Linux의 hidraw, 브라우저의 WebHID — 는 다른 패키지의 몫입니다. 그 위의 모든 것은
여기에 있습니다.

| | |
|---|---|
| `Open(ctx, t)` | 브로드캐스트 채널의 `INIT` 핸드셰이크. 자신의 채널을 가진 `*Key`를 반환. `Key`가 `t`를 소유합니다. `Close`가 이를 닫으며 실패한 `Open`도 닫습니다 |
| `Key.Ping`, `Key.Wink` | 왕복, 그리고 깜박임 — *이 키들 중 어느 것이 이 키인가?*라고 묻는 가장 저렴한 방법 |
| `Key.GetInfo` | 버전, 확장, AAGUID, 옵션, PIN 프로토콜 |
| `Key.MakeCredential`, `Key.GetAssertion` | 등록, 그리고 서명. `ParseAuthData`가 인증기 데이터를 읽고, `AuthData.PublicKey`가 P-256 COSE 키를 `*ecdsa.PublicKey`로 바꿈 |
| `Key.PINRetries`, `Key.KeyAgreement`, `Key.PINToken` | `authenticatorClientPIN`, 두 PIN/UV 인증 프로토콜 모두 |
| `Split`, `NewReassembler`, `ParseInit`, `Key.CBOR` | 프레이밍. 다른 방식으로 키를 구동하는 사람을 위해 공개됨 |

`AuthData.PublicKey`는 검증이 아니라 변환입니다. 어떤 알고리즘을 인정할지, 거꾸로 간
서명 카운터를 어떻게 할지는 호출자의 몫입니다.
[keyfactor]({{< relref "/libraries/keyfactor.md" >}})가 그런 호출자 중 하나입니다.

## 예제 {#example}

키 없이 프레이밍만: 메시지를 리포트로 자르고 다시 합칩니다.

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

키가 있으면 `fido.Open(ctx, transport)`가 핸드셰이크를 수행하고, 반환된 `*Key`가 이후의
모든 명령을 담당합니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**키는 질문받은 것에 대해 답한다고 신뢰되지 않습니다.** 보낸 것과 다른 명령을 담은
응답은 거부됩니다(CTAP 2.1 §11.2.9는 각 응답에 자신의 명령을 부여하며, libfido2도
이를 확인합니다). nonce가 보낸 것이 아닌 `INIT` 응답은 거부됩니다. 같은 키에서의
다른 프로그램의 핸드셰이크이기 때문입니다. 프로토콜의 길이가 아닌 PIN 토큰 —
프로토콜 1에서는 16 또는 32바이트, 프로토콜 2에서는 정확히 32바이트 — 은
거부됩니다.

**keepalive는 응답이 아닙니다.** 손가락을 기다리는 키는 약 100밀리초마다
`CTAPHID_KEEPALIVE`를 보내며, 이는 건너뜁니다. 터치에 걸릴 수 있는 시간의 유일한
한계는 컨텍스트입니다.

**프레이밍이 전달할 수 있는 것보다 긴 메시지.** 길이 바이트 두 개로는 65535까지
가능하지만, 초기화 패킷의 57바이트에 59바이트짜리 연속 패킷 128개를 더하면
7609(`MaxMessage`)입니다. 그보다 크면 시퀀스 번호가 `0x80`에 도달해 키가 이를 새
메시지로 읽게 됩니다. `Split`은 `ErrTooLong`을 반환합니다.

**맞지 않는 리포트**: 다른 채널의 것(`ErrWrongChannel` — 한 키에 프로그램 두 개),
순서가 어긋난 연속 패킷(`ErrOutOfOrder`), 패킷보다 짧은 리포트(`ErrShortPacket`), 17바이트보다
짧은 `INIT` 응답(`ErrTruncated`).

**키가 지원한다고 말하지 않은 명령.** `CapWink`가 없는 키에는 `Wink`를, `CapCBOR`가
없는 키에는 `GetInfo`를 보내지 않습니다. 키는 `CTAPHID_ERROR`로 응답할 것이고,
호출자는 그 거부를 장애와 구별해야 하기 때문입니다.

**빈 PIN**, 그리고 `AuthData.PublicKey`에서 P-256이 아닌 모든 것 — 반쯤 디코딩하지
않고 이름을 대며 거부합니다.

{{< callout type="warning" >}}
**잘못된 PIN은 재시도 횟수를 소모합니다**

CTAP는 인증기에 PIN 재시도 카운터를 주며 최대 여덟 번이고, 잘못된 PIN마다 하나가
소모됩니다. 연속 세 번 잘못된 PIN은 키를 뽑았다 다시 꽂을 때까지 PIN을 막습니다.
카운터가 0에 도달하면 영구히 막히며, 초기화만이 이를 풀고 초기화는 키의 모든 자격
증명을 지웁니다. 누군가에게 프롬프트를 띄우기 전에 `Key.PINRetries`를 물으십시오.
남은 재시도 횟수와 키가 뽑히기를 기다리는지 알려 줍니다.

키가 PIN을 거부하면 오류가 둘 중 어느 쪽인지 알려 줍니다.
뽑으면 풀리는 CTAP2_ERR_PIN_AUTH_BLOCKED(`0x34`)는
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`,
초기화만이 푸는 CTAP2_ERR_PIN_BLOCKED(`0x32`)는
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`
라고 나옵니다. v0.6.2 이전에는 두 문장이 바뀌어 있었습니다. 뽑기만 하면 되는 키가
잠겼다고 표시되었고, 그 말을 들은 사람은 키를 초기화하여 그 안의 모든 자격 증명을
잃을 수 있었습니다.
{{< /callout >}}

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

CI에는 보안 키가 없으므로 테스트는 자신이 받은 것을 재조립하는 가짜 전송을 사용합니다.
거부하거나, 멈추거나, 계속 바쁘다고 하거나, 채널을 다른 프로그램과 공유하는 키이며,
커버리지는 100%로 유지됩니다. 이 코드 밖에서 온 픽스처가 둘 있습니다.

- `testdata/yubikey-fido-5.7.4-getinfo.hex`, **YubiKey FIDO 5.7.4에서 캡처한**
  `GetInfo` 응답으로 `ctap2_test.go`가 디코딩합니다.
- `testdata/webauthn-reference-authdata.b64`, **go-webauthn/webauthn**의 테스트에서
  가져온 샘플로 인증기 데이터 파서와 `AuthData.PublicKey`를 검사합니다.

상태 코드 표는 libfido2의 `err.h`를 따릅니다. 모듈의 README에는 실제 YubiKey를 대상으로
수행한 등록과 어서션이 기록되어 있으며, 서명은 키가 내준 공개 키로 검증되었습니다.
그 실행은 CI에 포함되지 않습니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/fido@v0.6.2](https://pkg.go.dev/github.com/go-authn/fido@v0.6.2)
