---
title: "cms — CMS SignedData 서명"
linkTitle: "cms"
weight: 115
description: "go-authn/cms는 PDF, UEFI, S/MIME 서명을 담는 컨테이너인 CMS SignedData(RFC 5652)를 읽고 검증하며, OpenSSL로 판정된다."
tags: [라이브러리, 서명, 인증서]
---

**이 서명이 이 바이트들에 대해 성립하는가, 그리고 어떤 인증서가 만들었는가?**
CMS SignedData([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652))는 PDF 서명,
UEFI 인증 변수, S/MIME 메시지가 쓰이는 컨테이너입니다. 표준 라이브러리는
인증서를 읽고 서명을 검증하지만, CMS는 없습니다.

```sh
go get github.com/go-authn/cms@v0.1.0
```

v0.1.0은 **읽고 검증합니다**. 서명 생성은 다음 릴리스입니다.

## 예제 {#example}

```go
package main

import (
	"crypto/x509"
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/cms"
)

func main() {
	// A detached signature and the bytes it signed. For a PDF these are the
	// signature dictionary's /Contents and the file's /ByteRange.
	der, err := os.ReadFile("signature.der")
	if err != nil {
		panic(err)
	}
	content, err := os.ReadFile("signed-bytes")
	if err != nil {
		panic(err)
	}

	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content) // nil instead, when the content is attached
	switch {
	case errors.Is(err, cms.ErrInvalid):
		fmt.Println("the signature does not hold:", err)
		return
	case errors.Is(err, cms.ErrUnsupported):
		fmt.Println("a signature this package cannot check:", err)
		return
	case err != nil: // cms.ErrMalformed
		fmt.Println("not a signature:", err)
		return
	}

	// The signature holds. Whether to TRUST who made it is a second question,
	// with inputs of its own: the roots you accept.
	roots := x509.NewCertPool() // fill with the roots you trust
	for _, c := range signers {
		_, err := c.Verify(x509.VerifyOptions{Roots: roots, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}})
		fmt.Println(c.Subject, "chain:", err)
	}
}
```

`Verify`는 서명이 성립하는지에 답합니다. **신뢰** — 인증서의 체인, 유효성,
폐기 — 는 별개의 판단이며, RFC 5652 §5.6은 이를 CMS 바깥에 둡니다. 체인에는
`crypto/x509`를, 취소된 것에는
[go-authn/revocation](https://github.com/go-authn/revocation)의 CRL 검증을
사용합니다.

## 세 가지 오류, 호출자에게 세 가지 답이 필요하기 때문에 {#three-errors-because-a-caller-needs-three-answers}

| 오류 | 의미 |
|---|---|
| `ErrMalformed` | 이 패키지가 읽을 수 있는 SignedData가 아님 |
| `ErrUnsupported` | 여기서 구현되지 않은 것을 사용하는 서명 |
| `ErrInvalid` | 읽을 수 있고 지원도 되지만, 서명이 성립하지 않음 |

모든 거부는 이 중 정확히 하나를 감싸며, 퍼징 테스트는 이를 불변 조건으로
유지합니다.

## 거부하는 것 {#what-it-refuses}

코드에 근거하며, 각각 메시지를 확인하는 테스트가 있습니다.

- 인증서가 컨테이너에 없는 서명자
- `content-type`과 `message-digest`가 각각 정확히 하나, 단일 값으로 있지 않은
  서명 속성
- 콘텐츠의 형식과 다른 서명된 콘텐츠 형식
- 콘텐츠와 일치하지 않는 다이제스트 — **여기서 다시 계산**하며, 서명자의 값을
  절대 가져오지 않음
- 자체 해시가 다이제스트의 해시와 다른 서명 알고리즘
- SHA-1, 이름을 들어 거부
- SHA-512가 아닌 것 위의 Ed25519(RFC 8419)
- DER이 아닌 서명 속성 — 유효한 서명과 1비트 차이인 원시(primitive) `[0]`
  태그 포함
- **16개를 넘는 서명자**, **16 MiB를 넘는 입력**. 크기 한도는 작업량 한도가
  아님: 각 서명자는 콘텐츠 전체에 대해 검증됨

**아직 아닌 것:** BER의 부정 길이는 추측하지 않고 거부합니다. 서명 생성이 없고,
체인 검증도 의도적으로 하지 않습니다.

## 무엇에 대해 검증되는가 {#what-it-is-checked-against}

**OpenSSL의 `cms` 명령.** OpenSSL 4.1.0이 만든 11개의 서명이 RSA, RSA-PSS,
ECDSA, Ed25519를 첨부·분리된 콘텐츠와 두 가지 서명자 식별자 형식으로
다룹니다. `openssl cms -verify`와 이 패키지는 각각과 그 변조된 변형 모두에서
같은 판정을 내립니다: 34개 중 34개.

두 가지 점에서 이 패키지는 OpenSSL 4.1.0보다 **엄격합니다**. OpenSSL은 원시
서명 속성 태그와 SHA-256 위의 Ed25519를 받아들입니다.
