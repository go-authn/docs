---
title: "krb5 — Kerberos 티켓 받아들이기"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5는 Kerberos의 수락 측 절반입니다: keytab, 검증된 AP-REQ, 상호 인증에 필요한 AP-REP, 그리고 세션 키로 서명하고 봉인한 메시지."
tags: [라이브러리, kerberos]
---

**이 Kerberos 티켓이 이 서비스에 유효한가?** Kerberos의 **수락자** 쪽 절반이며, 그
절반만입니다. keytab을 보유하고, 클라이언트가 제시하는 AP-REQ를 검증하고, 서비스가
진짜임을 증명하는 AP-REP로 응답한 다음, 그 교환이 수립한 키로 메시지에 서명하고,
검증하고, 봉인하고, 엽니다.

```sh
go get github.com/go-authn/krb5@v0.3.3
```

v0.3.3은 API도 코드도 바꾸지 않습니다. 간접 의존성 golang.org/x/net을 v0.62.0, golang.org/x/crypto를 v0.58.0,
github.com/hashicorp/go-uuid를 v1.0.4로 올립니다. `govulncheck`는 요구하지만 호출하지 않는 모듈에서 46건을 보고했으나
지금은 1건, GO-2026-5932(`golang.org/x/crypto/openpgp`)뿐입니다. 이것은 수정된 버전이 없고 go-authn의 어느 것도
가져오지 않습니다. 코드에서 도달 가능한 결과는 전후 모두 0입니다.

KDC와 통신하지 않으며 티켓을 발급하지 않으므로, 누구의 티켓을 받아들일지는 다른 쪽의
결정입니다. 발급 측 절반은 [kdc]({{< relref "/libraries/kdc.md" >}})이며 이 모듈은
그것에 의존하지 않습니다 — [별도 모듈인 이유]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}})를
참조하십시오. 티켓 복호화는 [gokrb5](https://github.com/jcmturner/gokrb5)의 것입니다.

## 존재하는 이유 {#why-it-exists}

gokrb5는 클라이언트 라이브러리입니다. AP-REQ를 검증하지만 그에 답하는 AP-REP를 만들
수 없습니다. 모든 GSS-API 클라이언트는 상호 인증을 요청합니다 — MIT 자체의
`gss-client`는 끌 방법 없이 `GSS_C_MUTUAL_FLAG`를 설정합니다 — 그래서 AP-REP를
만들 수 없는 서비스는 컨텍스트를 하나도 완성하지 못합니다. 이를 만드는 것이 이
모듈이 더하는 것의 대부분입니다.

## 예제 {#example}

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

`krb5.New`가 받는 `keytab.New`를 위해 `github.com/jcmturner/gokrb5/v8`이 필요하며,
`krb5.Load`는 대신 경로에서 keytab을 읽습니다.

`Accept` 후에 `*Context`가 누구인지 알려 줍니다. `Principal()`(`alice@EXAMPLE.ORG`),
또는 `User()`와 `Realm()`을 따로. principal을 로컬 계정에 매핑하는 것은 호출자의
정책입니다. `alice@EXAMPLE.ORG`와 `alice@PARTNER.ORG`는 모두 "alice"에 응답합니다.
`Expires()`는 그 뒤의 티켓이 끝나는 시각이며, 오래 지속되는 연결을 가진 서버는 그
이후에는 이를 인정하지 않아야 합니다. `MIC`/`VerifyMIC`와 `Wrap`/`Unwrap`은 서명하고,
`Seal`/`Unseal`은 기밀성을 더합니다(`sec=krb5p`). `Context`는 동시 사용에 안전하지
않으며, `Acceptor`는 안전합니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**이 서비스가 받아들이지 않을 티켓** — 잘못된 서비스, 잘못된 키, 만료, 재생, `ClockSkew`
(기본값 5분, MIT도 같음)를 넘는 시계 — 은 `ErrRejected`입니다. GSS-API krb5 토큰이
아닌 바이트는 `ErrNotAToken`이고, AP-REQ가 아닌 토큰은 `ErrNotAPReq`입니다. 오류는
의도적으로 거칠게 나뉩니다. 클라이언트는 자신의 티켓이 거부되었다는 것만 알 뿐 어떤
검사가 거부했는지는 알지 못합니다. 오류는 컨텍스트가 없다는 뜻이며 반환된 토큰은
비어 있습니다.

**수락자가 대신 답하지 않는 principal.** `krb5.Principal("nfs/files.example.org")`가
있으면 서비스 여러 개를 가진 keytab도 그 하나에 대해서만 응답합니다.

**서명이 맞지 않는 메시지**는 길이, 헤더, 시퀀스, 체크섬 중 무엇이 어긋났든
`ErrBadMIC`입니다. 수락자는 키 용도 23으로 서명하고 25로 검증하므로, 이 서버가 만든
토큰을 클라이언트가 서명한 것처럼 되돌려 재생할 수 없습니다.

**`Unwrap`에 주어진 봉인된 토큰**은 `ErrSealed`이며 잘못된 서명과 구별됩니다.
무결성만 있는 토큰을 읽는 호출자에게 메시지처럼 읽히는 암호문을 건네서는 안
됩니다. **`Unseal`에 주어진 봉인되지 않은 토큰**은 `ErrNotSealed`입니다. 기밀성을
약속한 프로토콜에 평문으로 전송 구간을 지난 것을 건네지 않습니다.

수락자 서브키는 주장하지 않습니다. 컨텍스트 키는 개시자가 authenticator에 넣은
서브키이거나, 보내지 않았다면 티켓의 세션 키입니다(RFC 4121 §4.3).

{{< callout type="warning" >}}
**keytab은 저장된 상태의 비밀 값입니다**

경로는 구성 파일이나 `KRB5_KTNAME`에서 올 수 있습니다. 그 안의 키는 절대 로그에 남기거나,
출력하거나, 환경 변수로 전달해서는 안 됩니다.
{{< /callout >}}

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**실제 MIT KDC와 MIT 자체의 `gss-client`**를, `gss-server`를 대신하는 이 패키지에 대해
실행합니다. `test/kdc.sh`는 루프백에서 권한 없이 일회용 렐름을 만들며, CI는 pkgx로 MIT
Kerberos를 가져옵니다(Ubuntu의 패키지는 `gss-client`를 제공하지 않습니다). Linux 테스트
레인, 레이스 감지기, 커버리지 레인은 `KRB5_REQUIRE_JUDGE=1`을 설정하므로 픽스처가 없으면
실패합니다. 추가 단계가 `TestMITClientAgainstThisAcceptor`를 실행하며 로그에
*authenticated as alice@*가 없으면 실패합니다. 판정자가 조용히 실행을 멈춘 초록색
레인은 받아들이지 않습니다. `TestMITClientSealed`는 기밀성을 켜고 같은 일을 합니다.

macOS, Windows, 크로스 아키텍처 레인에는 렐름이 없으며, 거기서는 판정자가 건너뜁니다.
커버리지 레인의 하한은 90%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/krb5@v0.3.3](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.3)
