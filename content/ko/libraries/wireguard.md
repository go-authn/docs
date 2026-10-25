---
title: "wireguard — 이 키는 누구의 것이며, 연결해도 되는가?"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard는 WireGuard 공개 키를 엄격하게 정의하고, 게이트웨이가 피어로 바꾸는, 공급자가 서명한 등록된 키의 목록을 전달합니다."
tags: [라이브러리, wireguard, 토큰]
---

**이 WireGuard 키가 연결해도 되는가, 그리고 누구의 것인가?** WireGuard는 피어를 정적
공개 키로만 인증하며 다른 것은 없습니다. 인증서도, 만료도, 폐기도 없습니다. 그래서
질문은 프로토콜 밖에서 답해지며, 답이 바뀔 때마다 다시 답해집니다. 공급자 —
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) — 가 답하고, 이 모듈은 공급자와
게이트웨이가 합의하는 것입니다.

```sh
go get github.com/go-authn/wireguard@v0.1.1
```

유일한 의존성은 목록을 검증하는 [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0입니다.

두 가지를 합니다. `ParseKey`는 공개 키가 무엇인지 알려 주고, `Source.Fetch`는 사람들이
등록한 키의 공급자 서명 `List`를 가져옵니다. 각각이 `Key`, `Subject`, `Username`,
`Device`, lease의 끝을 가진 `Peer`입니다.

{{< callout type="info" >}}
**여기를 지나가는 것은 공개 키뿐입니다**

개인 키는 장치에서 생성되어 장치를 떠나지 않습니다. 이 패키지에는 개인 키를 위한 자리가
없습니다.
{{< /callout >}}

## 예제 {#example}

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

게이트웨이는 `Source` 하나를 유지하며 목록을 가져옵니다.

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource`는 시작할 때 공급자의 구성을 읽습니다. `Fetch`는 게이트웨이 자신을 위한
토큰(`client_credentials`, 스코프 `wireguard_peers`)을 받고, 발급자 아래
`/wireguard/peers`에서 목록을 가져오며, go-authn/oidc로 검증합니다. 공급자의 키 집합에
대한 서명, 발급자, audience(이 게이트웨이의 `ClientID`), 만료, 그리고 `typ`
`wireguard-peers+jwt`(`ListType`) — 그러므로 액세스 토큰이나 ID 토큰이 목록으로,
목록이 토큰으로 통할 수 없습니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**키**(`ParseKey`):

- 같은 바이트의 다른 모든 표기. 디코딩은 엄격하며 텍스트가 들어온 그대로 다시 출력되어야
  하므로, 텍스트를 키로 삼는 저장소가 하나의 키를 두 이름으로 두 번 보유할 수 없습니다
- 저위수 점, 그중 전부 0인 키. 이런 키와의 모든 교환은 상대 측 키가 무엇이든 같은 공유
  비밀 값을 주므로(RFC 7748 §6.1) 아무도 인증하지 못합니다. `crypto/ecdh`는 교환을
  계산해서 이를 판단하므로 최상위 비트 변형도 거부됩니다

**목록**(`Fetch`):

| | 이유 |
|---|---|
| 이 `Source`가 받은 것보다 낮은 `version`의 목록 | 오래된 목록도 서명되어 있으며 그 사이 회수된 키를 나열할 수 있습니다 |
| 두 번 나열된 키 | 게이트웨이가 어느 쪽을 유지하든 다른 사람의 트래픽이 잘못된 이름으로 도착하게 됩니다 |
| 주체가 없는 피어 | 아무에게도 속하지 않습니다 |
| 키가 아닌 키 | 위를 참조하십시오 |
| 평문의 발급자 또는 토큰 엔드포인트 (루프백 제외) | 게이트웨이의 비밀 값과 목록이 누구나 읽을 수 있는 링크를 지나게 됩니다 |
| `ClientID`와 `ClientSecret`이 없는 `SourceConfig` | 게이트웨이는 목록을 자신의 클라이언트로서 읽습니다 |

목록은 `exp`를 담습니다. 그 시점까지 더 새 목록을 가져오지 못한 게이트웨이는 오래된
목록이 아니라 목록이 없는 상태가 됩니다. `Peer.Subject`는 키를 등록한 클라이언트가
보는 그대로의 사람의 `sub`, 즉 public 또는 pairwise이며, 게이트웨이가 그 사람의 액세스
토큰에서도 찾는 값입니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

wireguard-tools의 **`wg(8)`** 자체가 `ParseKey`가 받아들여야 하는 키를 만듭니다. Linux
테스트 레인, 레이스 감지기, 커버리지 레인에 설치되며, 이들은 `WIREGUARD_REQUIRE_JUDGE=1`을
설정하므로 `wg`가 없으면 건너뛰는 대신 실패합니다. 저위수 테스트는 libsodium이 나열하는
일곱 점을 각각 최상위 비트가 있을 때와 없을 때 검사합니다. 커버리지 하한은 100%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.1](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.1)
