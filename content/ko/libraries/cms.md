---
title: "cms — CMS SignedData 서명"
linkTitle: "cms"
weight: 115
description: "go-authn/cms는 PDF, UEFI, S/MIME 서명을 담는 컨테이너인 CMS SignedData(RFC 5652)를 읽고 검증하고 서명하며, OpenSSL로 판정된다."
tags: [라이브러리, 서명, 인증서]
---

**이 서명이 이 바이트들에 대해 성립하는가, 그리고 어떤 인증서가 만들었는가?**
CMS SignedData([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652))는 PDF 서명,
UEFI 인증 변수, S/MIME 메시지가 쓰이는 컨테이너입니다. 표준 라이브러리는
인증서를 읽고 서명을 검증하지만, CMS는 없습니다.

```sh
go get github.com/go-authn/cms@v0.2.0
```

v0.2.0은 **읽고, 검증하고, 서명합니다**.

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

## 서명 생성 {#signing}

`cms.Sign`은 모든 `crypto.Signer`(파일, 카드 또는 HSM에 있는 RSA, ECDSA,
Ed25519 키)로 **서명자 한 명**의 DER ContentInfo를 씁니다. 결과를 돌려주기 전에
인증서로 서명을 검증하므로, 잘못된 서명을 돌려주는 서명기는 거부되며 결과로
나가지 않습니다.

```go
package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/go-authn/cms"
)

func main() {
	// A key and a self-signed certificate, for the example. In practice the
	// key may live on a card or in an HSM: any crypto.Signer will do.
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "signer"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		panic(err)
	}
	cert, err := x509.ParseCertificate(certDER)
	if err != nil {
		panic(err)
	}

	content := []byte("the bytes to sign")
	der, err := cms.Sign(content, cms.SignOptions{
		Signer:      key,
		Certificate: cert,
		Hash:        crypto.SHA256,
		Detached:    true, // as a PDF signature: the content is not inside
		SigningTime: time.Now(),
	})
	switch {
	case errors.Is(err, cms.ErrSigner):
		panic(fmt.Sprint("the key or the device failed: ", err))
	case errors.Is(err, cms.ErrOptions):
		panic(fmt.Sprint("the request is wrong: ", err))
	case err != nil: // cms.ErrUnsupported
		panic(err)
	}

	// Sign checked its own signature; Verify is the reader's side.
	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content)
	if err != nil {
		panic(err)
	}
	fmt.Println("signed by", signers[0].Subject.CommonName)

	content[0] ^= 1
	_, err = sd.Verify(content)
	fmt.Println("altered content:", errors.Is(err, cms.ErrInvalid))
}
```

`SignOptions`에는 `Chain`(포함할 중간 인증서), `PSS`(RSASSA-PSS),
`SigningCertificateV2`(RFC 5035, CAdES와 PAdES 기본 프로파일이 요구하는 것),
`ContentType`, `NoSignedAttrs`, `Rand`도 있습니다. 다이제스트는 기본이 SHA-256이고
SHA-384나 SHA-512도 쓸 수 있으며, Ed25519는 항상 SHA-512입니다. SHA-1은
거부됩니다.

`Sign`에는 고유한 오류가 세 가지 있습니다. `ErrOptions`(요청이 잘못됨),
`ErrSigner`(키나 장치가 실패했거나 인증서로 검증되지 않는 서명을 돌려줌),
`ErrUnsupported`(쓰지 않는 알고리즘)입니다. **서명 속성이 없는** Ed25519도
거부됩니다. RFC 8419는 허용하지만, 이 패키지가 쓰는 형태를 OpenSSL은 검증하지
않기 때문입니다.

OpenSSL의 `cms -verify`와 이 패키지의 `Verify`는 물어본 모든 조합에서
일치합니다. **58개 조합, 203개 판정**이며, RSA PKCS #1 v1.5, RSA-PSS, ECDSA P-256과
SHA-256, SHA-384, SHA-512, 그리고 Ed25519와 SHA-512를 첨부·분리, 서명 속성
유무로 시험했습니다. `Verify`는 아직 signing-certificate-v2를 검증하지 않습니다.
서명자의 인증서를 그 속성에 묶는 일은 호출자의 몫입니다.

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
- 네 가지 비 DER 형식의 서명 속성: 원시(primitive) `[0]` 태그(유효한 서명과
  1비트 차이), SEQUENCE가 아닌 속성, SET이 아닌 값, 속성 안의 남는 바이트.
  SET의 순서는 확인하지 않음
- **16개를 넘는 서명자**, **16 MiB를 넘는 입력**. 크기 한도는 작업량 한도가
  아니므로 서명자 수에 상한을 둠: 콘텐츠는 다이제스트 알고리즘마다 한 번
  해시되지만, 서명 속성이 없는 Ed25519 서명자는 검증할 때마다 전체를 해시함

**아직 아닌 것:** BER의 부정 길이는 추측하지 않고 거부합니다. 서명 생성은
서명자 한 명이며 부서명과 타임스탬프 토큰이 없습니다. `Verify`는
signing-certificate-v2를 검증하지 않고, 체인 검증도 의도적으로 하지 않습니다.

## 무엇에 대해 검증되는가 {#what-it-is-checked-against}

**OpenSSL의 `cms` 명령.** OpenSSL 4.1.0이 만든 11개의 서명이 RSA, RSA-PSS,
ECDSA, Ed25519를 첨부·분리된 콘텐츠와 두 가지 서명자 식별자 형식으로
다룹니다. `openssl cms -verify`와 이 패키지는 각각과 그 변조된 변형 모두에서
같은 판정을 내립니다: 34개 중 34개.

두 가지 점에서 이 패키지는 OpenSSL 4.1.0보다 **엄격합니다**. OpenSSL은 원시
서명 속성 태그와 SHA-256 위의 Ed25519를 받아들입니다.
