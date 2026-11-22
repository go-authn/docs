---
title: "pkcs12 — 업로드된 .p12 안의 키와 인증서"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12는 PKCS#12(.p12 / .pfx, RFC 7292) 파일을 순수 Go로 읽는다. 신뢰할 수 없는 업로드를 위해 만들어졌고, 모든 자원 한도는 끌 수 없는 옵션이며, OpenSSL이 판정한다."
tags: [라이브러리, 인증서, 키]
---

**누군가 보낸 이 파일 안에는 어떤 개인 키와 어떤 인증서가 들어 있는가?**
PKCS#12([RFC 7292](https://www.rfc-editor.org/rfc/rfc7292))는 내보내기 도구가 키,
그 인증서, 나머지 체인을 써 넣는 `.p12` / `.pfx` 컨테이너입니다.
`golang.org/x/crypto/pkcs12`는 더 이상 쓰이지 않으며 SHA-1과 3DES/RC2에 멈춰
있어서, OpenSSL 3과 4 및 최신 Windows가 기본으로 쓰는 것(PBES2, AES, SHA-2 MAC)을
거부합니다. 이 모듈은 표준 라이브러리 외에 의존성 없이 그것들을 읽으며,
**신뢰할 수 없는 업로드**를 위해 만들어졌습니다.

```sh
go get github.com/go-authn/pkcs12@v0.1.0
```

**디코딩만** 합니다. 인코더는 없습니다. 체인을 신뢰할지는 `crypto/x509`의
`Verify`가 맡는 별개의 결정입니다.

## 예제 {#example}

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/pkcs12"
)

func main() {
	data, err := os.ReadFile("upload.p12")
	if err != nil {
		panic(err)
	}

	b, err := pkcs12.Decode(data, "the password", nil)
	switch {
	case errors.Is(err, pkcs12.ErrIncorrectPassword):
		fmt.Println("ask again:", err)
		return
	case err != nil: // hostile, unsupported, too costly...
		fmt.Println("refused:", err)
		return
	}

	// b.PrivateKey   *rsa.PrivateKey, *ecdsa.PrivateKey, ed25519.PrivateKey or *ecdh.PrivateKey
	// b.Certificate  the certificate holding the key's public half
	// b.CACerts      every other certificate, in file order
	fmt.Println("certificate for", b.Certificate.Subject, "and", len(b.CACerts), "more")
}
```

`Decode(data, password, *Options) (*Bundle, error)`는 기본값을 쓰려면 `nil`을
받습니다. `Bundle`에는 키, 그 공개 쪽을 가진 인증서, 나머지 인증서가 파일 순서대로
들어 있습니다.

## 옵션과 기본값 {#options-and-their-defaults}

0인 필드는 기본값을 뜻하며, **어떤 필드도 한도를 끌 수 없습니다**.

| 필드 | 기본값 | 의미 |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | 키 유도 1회의 반복 횟수 |
| `MaxWork` | 5 000 000 | 파일 전체의 반복 횟수 x 출력 블록 수 |
| `MaxDepth` | 16 | BER 중첩과 구성된 문자열 조각의 중첩 |
| `MaxBags` | 1024 | 파일 안의 SafeBag |
| `MaxAuthSafes` | 32 | AuthenticatedSafe의 ContentInfo |
| `MaxCertSize` | 32 KiB | 인증서 하나의 DER |
| `MaxCertBytes` | 512 KiB | 모든 인증서를 합친 DER |
| `MaxRSABits` | 8192 | RSA 모듈러스 |
| `AllowNoMAC` | `false` | 무결성 MAC이 없는 파일(`openssl pkcs12 -nomac`)을 읽음. 아니면 `ErrNoMAC` |
| `NoPassword` | `false` | 파일이 비밀번호 없이 내보내졌음. 빈 비밀번호 `""`와는 다름 |

두 불리언은 이 형식의 두 가지 모호함입니다. `AllowNoMAC`을 쓰면 내용을 인증하는
것이 없어지고, 틀린 비밀번호는 복호화 실패로만 알 수 있습니다. **빈** 비밀번호
(`""`)와 **없는** 비밀번호(`NoPassword`)는 서로 다른 키를 유도하며 둘 다 동작합니다.
`""`이고 `NoPassword`가 false이면 `Decode`는 빈 것을 먼저, 없는 것을 그다음에
시도합니다. 내보내기 도구마다 무엇을 썼는지가 다르기 때문입니다. `NoPassword`가
true이면 없는 것만 시도하며, 비밀번호 인자는 `""`여야 합니다.

## 읽을 수 있는 것 {#what-it-reads}

| 계층 | 지원 |
|---|---|
| 암호화 | PBES2([RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)), HMAC-SHA-1/224/256/384/512 위의 PBKDF2와 AES-128/192/256-CBC |
| 구형 암호화 | `pbeWithSHAAnd3-KeyTripleDES-CBC`, `pbeWithSHAAnd2-KeyTripleDES-CBC`, `pbeWithSHAAnd40BitRC2-CBC`와 128비트 변형. RC2는 모듈 안에서 구현 |
| 무결성 | SHA-1/224/256/384/512 HMAC MAC(RFC 7292 부록 B의 KDF)과 **PBMAC1**([RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)) |
| 비밀번호 | 부록 B.1에 따른 BMPString, BMP 밖의 문자는 서로게이트 쌍 |
| 인코딩 | BER. Windows와 Java가 쓰는 부정 길이와 구성된 OCTET STRING 포함 |
| 백 | 암호화된 키 백과 평문 키 백, 인증서 백. CRL, 시크릿, 세이프 콘텐츠 백은 건너뜀 |

**`ErrUnsupported`로 거부되는 것:** 공개 키 기반 무결성 및 프라이버시 모드
(`signedData`, `envelopedData`), RC4, scrypt, PKCS#12 고유의 것 외의 PBES1,
PBMAC1 안의 SHA-1, 인증서나 PKCS#8 키 안의 BER(DER이 아닌 것).

## 오류 {#errors}

| 오류 | 의미 |
|---|---|
| `ErrMalformed` | 이 패키지가 읽을 수 있는 PKCS#12 파일이 아님 |
| `ErrUnsupported` | 읽을 수 있지만 여기서 구현하지 않은 것을 사용함 |
| `ErrLimit` | `Options`의 한도를 넘게 됨. 작업 전에 거부됨 |
| `ErrIncorrectPassword` | 틀린 비밀번호와 변조된 파일. 설계상 같은 답 |
| `ErrNoMAC` | MAC이 없고 `AllowNoMAC`이 설정되지 않음 |
| `ErrNoPrivateKey` | 파일에 개인 키가 없음 |
| `ErrMultipleKeys` | 파일에 개인 키가 둘 이상 있음 |
| `ErrNoCertificate` | 개인 키에 맞는 인증서가 없음 |
| `ErrPassword` | 사용할 수 없는 비밀번호 |

모든 거부는 이 중 정확히 하나를 감싸며, 퍼즈 대상은 이를 불변 조건으로 유지합니다.

## 보안 한도 {#the-security-bounds}

위의 모든 한도는 **작업 전에** 검사되고, 모든 길이 필드는 무언가를 할당하기 전에
실제로 존재하는 바이트와 대조됩니다. 512바이트를 넘는 솔트와 1024자를 넘는
비밀번호는 거부됩니다.

MAC은 **무엇이든 복호화하기 전에, 상수 시간으로** 검증됩니다.

`crypto/x509`는 수천 개의 작은 이름으로 이루어진 인증서에서는 그 크기의 43배에서
52배까지 할당하고, `crypto/rsa`는 키가 선언한 수에 대한 산술로 키를 검증하므로
모듈러스보다 훨씬 긴 인수는 초선형 CPU를 소모합니다. 둘 다 밖에서는 고칠 수 없으므로
그곳에 닿는 것을 먼저 제한합니다. 인증서는 `MaxCertSize`와 `MaxCertBytes`로,
모든 PKCS#8 키(최대 32 KiB)는 `encoding/asn1`로 읽고, 모듈러스가 `MaxRSABits`를
넘거나, 인수나 지수가 모듈러스가 허용하는 것보다 길거나, 수가 양수가 아니거나,
다중 소수인 경우 유형이 있는 오류로 거부합니다(`ErrUnsupported`).

**요청당 메모리.** 기본 옵션에서 악의적인 파일은 `Decode` 한 번에 약 25 MB를
할당하게 합니다(함께 측정: 최악의 인증서와 받아들이는 가장 큰 키, 8192비트에서
25.1 MB, 그중 약 20 MB는 반환될 때까지 살아 있음). 파일은 530 KB입니다. 업로드를
디코딩하는 서비스는 예를 들어 세마포어로 진행 중인 디코딩 수를 제한하고, 짧은
체인만 기대한다면 `MaxCertBytes`를 낮춰야 합니다.

## 제한 사항 {#limitations}

- **CRT 값이 없는 RSA 키는 거부됩니다**(`ErrUnsupported`). `Dp`, `Dq`, `Qinv`가
  없는 키는 `crypto/x509`가 보기 전에 거부됩니다. RFC 8017은 이를 요구하고 모든
  내보내기 도구(OpenSSL, Windows, Java의 keytool)가 쓰지만, `crypto/x509`는 빠진
  값을 큰 수 연산으로 유도합니다. 8192비트에서 16.4 MB와 21 744번의 할당, 값이
  있으면 0.36 MB와 618번입니다.
- **[go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2), 열림, LOW.**
  `GODEBUG=x509rsacrt=0`에서는 `crypto/x509`가 잘못된 CRT 값을 버리고 다시 계산하며,
  사전 검사는 그 값이 *존재하는지*만 확인합니다. CRT 값이 틀린 8192비트 키는 이를
  통과하고, 최악의 인증서와 함께라면 디코딩이 39.4 MB(비율 74.7)에 이르러 테스트가
  단언하는 한도를 벗어납니다. 운영자가 켜야 하며, 모듈의 `go.mod`는 그 설정이
  기본값이 아닌 Go 버전을 선언합니다. 기본 설정에서는 같은 입력이 `ErrMalformed`로
  거부됩니다.
- 디코딩만 하며 체인을 판단하지 않습니다.

## 무엇과 대조되는가 {#what-it-is-checked-against}

**OpenSSL이 판정합니다.** OpenSSL 4.1이 쓴 23개 파일(AES/PBES2, `-legacy`의 3DES와
RC2, `-nomac`, 여러 인증서, RSA, EC와 Ed25519, PBMAC1)이 테스트에 있으며, 각 파일에
무엇이 들었는지 OpenSSL 자신이 말하는 것을 기록한 매니페스트가 있습니다.

**증폭.** `TestAmplification`은 많은 작은 백, 많은 인증서, 깊은 부정 길이 중첩, 긴
OCTET STRING 연쇄, 4 GiB 길이 주장에 대해 할당된 바이트를 입력 바이트에 대해
제한하고, 거부가 `crypto/x509` 호출 전에 일어남을 단언합니다. 모듈은 퍼징도
하고(코퍼스 커밋됨), 블록 커버리지 100 %이며, `-race`와 `govulncheck`로 실행됩니다.

**`software.sslmate.com/src/go-pkcs12`**는 별도의 `oracle/` 모듈에 있습니다. 둘 다
시도할 수 있는 23개 파일 중 둘 다 18개를 읽고, 리프, 체인 순서, 키가 바이트 단위로
같습니다. 나머지 5개(RC2-128, SHA-384 MAC, MAC 없음, BMP 밖의 문자를 가진 두
비밀번호)는 이 패키지만 읽습니다. 상대는 읽는데 이쪽이 거부하는 것은 없습니다.

[cms]({{< relref "/libraries/cms.md" >}})와 함께 씁니다. 여기서 `.p12`를 디코딩하고,
거기서 서명합니다.
