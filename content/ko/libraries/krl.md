---
title: "krl — OpenSSH 키 폐기 목록"
linkTitle: "krl"
weight: 110
description: "go-authn/krl은 sshd가 읽는 대로 OpenSSH KRL을 구문 분석하고, 만들고, 병합하고, 검사하며, 만료 확장을 갖추고 ssh-keygen으로 판정합니다."
tags: [라이브러리, 폐기, ssh]
---

**sshd가 답하는 대로, 이 SSH 인증서나 키는 폐기되었는가?** OpenSSH의
`PROTOCOL.krl`의 바이너리 형식이며, `sshd`가 `RevokedKeys`로 로드하고
`ssh-keygen -k`가 기록하는 목록입니다. `golang.org/x/crypto/ssh`는 이를 지원하지
않습니다.

```sh
go get github.com/go-authn/krl@v0.6.1
```

`IsRevoked`는 OpenSSH `krl.c`의 `ssh_krl_check_key`를 따릅니다. 인증서는 일련번호나
키 ID가 서명한 CA 아래에서 또는 모든 CA 아래에서 폐기되었거나, CA 키가 폐기되었거나,
자신의 키가 블롭이나 SHA-1 또는 SHA-256 지문으로 폐기되었을 때 폐기된 것입니다. 일련번호
0 — CA가 아무것도 지정하지 않을 때 기록하는 값 — 은 일련번호로는 절대 폐기되지
않습니다.

## 예제 {#example}

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

같은 목록과 인증서를 파일로 기록하면 OpenSSH 10.3p1의 `ssh-keygen -Q -f list.krl`이
같은 세 가지 답을 줍니다: `REVOKED`, `ok`, `REVOKED`.

## 만료: `expires@go-authn.github.io` {#expiry-expiresgo-authngithubio}

KRL에는 생성 날짜와 버전이 있지만 언제 유효하지 않게 되는지는 나와 있지 않으므로,
오래된 사본을 새 것과 구별할 수 없습니다. `Builder.SetExpires`는 그 시각을
`ExtensionExpires`라는 확장 섹션에 **critical이 아닌** 상태로 기록하므로, `sshd`와
`ssh-keygen`은 목록을 로드하고 이를 무시합니다. `Parse`는 이를 `KRL.Expires`로
읽습니다.

{{< callout type="warning" >}}
**서명 없음**

OpenSSH는 KRL 서명 섹션을 쓰는 방법을 공개한 적이 없고 이제는 검증하지도 않습니다.
`Parse`는 이를 건너뛰고 `Signed`를 설정하는데, 이는 진본 여부에 대해 아무것도 말하지
않습니다. `Builder`는 서명을 절대 쓰지 않습니다. 목록의 무결성, 따라서 그 만료의
무결성은 전송 구간 — 인증된 서버의 HTTPS — 또는 호출자가 검사하는 분리된 SSHSIG
서명에서 오며, 이 패키지는 후자를 하지 않습니다.
{{< /callout >}}

## 병합: sshd를 위한 하나의 파일 {#merging-one-file-for-sshd}

`sshd`는 OpenSSH 10.3까지 `RevokedKeys` 파일 하나만 읽었으므로, 여러 CA를 신뢰하는
서버에는 그 목록들이 하나로 필요합니다. `Builder.Merge`는 구문 분석한 목록의 모든
폐기를 추가합니다. `Builder.MergeCA(k, ca, others...)`는 `k`의 `ca` 섹션, `ca`로
범위가 다시 정해진 모든 CA 섹션, 명시적 키와 지문을 유지하고, 다른 CA의 섹션과
`others` 중 하나를 지정하는 키나 지문은 개수를 세면서 제외합니다.
`MergeOptions{DropKeys: true}`와 함께 `MergeCAWith`를 쓰면 `ca` 자신의 것을 제외한
모든 명시적 키도 제외하며, 모든 CA의 사용자를 신뢰하지 않는 목록을 위한 것입니다.
폐기된 사용자 키는 `sshd`가 누가 서명했든 인증서 자신의 키를 검사하므로 병합된 파일의
모든 CA 아래에서 그 사용자를 막아 버립니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

`Parse`는 `ssh-keygen`과 `sshd`가 거부하는 것을 거부합니다. 잘못된 매직 또는 형식
버전, 잘리거나 뒤에 붙은 데이터, 알 수 없는 섹션 또는 인증서 하위 섹션, critical로
표시된 알 수 없는 확장, OpenSSH가 구문 분석할 수 없는 CA 키, 일련번호 0, 뒤집힌 일련번호
범위, OpenSSH가 읽는 것보다 큰 비트맵 또는 2^64−1을 넘어 감기는 비트맵. 형식이 잘못되었거나
반복된 만료도 거부합니다. 없는 것으로 읽으면 만료되도록 만든 목록이 절대 만료되지 않는
목록이 되기 때문입니다.

`Builder`는 — 첫 번째 잘못된 요청을 반환하는 `Marshal`에서 — 일련번호 0, 낮은 쪽이 0이거나
높은 쪽보다 큰 범위, NUL을 포함하는 키 ID 또는 주석, CA 키가 와야 할 곳에 주어진
인증서, 생성 날짜보다 이른 만료를 거부합니다.

**의도적인 차이 하나.** 가까이 있는 희소한 일련번호가 많으면 `ssh-keygen -k`는 자신의
읽기 쪽이 받아들이는 것보다 넓은 비트맵을 기록한 다음 자신의 파일을 거부합니다(*bignum
is too large*). `Parse`도 `sshd`처럼 그 파일을 거부합니다. `Builder`는 비트맵이 그만큼
넓어지기 전에 새 섹션을 시작하므로, 기록하는 것은 항상 읽을 수 있습니다.

Parse는 OpenSSH처럼 목록이 폐기하는 것에 비례하여 할당합니다. KRL은 엄청나게 큰 것을
보내지 않는다고 신뢰되는 출처에서 와야 합니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**OpenSSH의 `ssh-keygen`**, Linux와 macOS 레인에서, `KRL_REQUIRE_SSHKEYGEN=1`이
없는 경우를 실패로 만듭니다(Windows는 순수 Go 테스트만 실행).

- 모든 일련번호 인코딩, 키 ID, CA 셋과 "any CA", 명시적 키, 폐기된 CA 키를 가진
  `ssh-keygen -k`가 기록한 KRL: `IsRevoked`가 인증서 250개에 대해 `ssh-keygen -Q`처럼
  응답하며, 같은 폐기를 받은 `Builder`는 **같은 바이트**를 기록합니다
- 둘 다 기록한 무작위 일련번호 집합 40개: 바이트 단위로 동일하며 인증서 약 9000개에
  대한 답도 같습니다
- 모든 절단과 약 1400개의 단일 바이트 손상: `Parse`는 `ssh-keygen`이 거부하는 것을
  정확히 거부합니다
- 만료 확장은 `ssh-keygen`에 로드되고, 같은 섹션을 critical로 표시하면 거부됩니다
- 병합된 목록은 소스 중 하나가 폐기하는 것을 정확히 폐기합니다

`ssh-keygen`이 기록한 KRL로 시드한 `FuzzParse`와 `FuzzBuilder`가 CI에서 실행됩니다.
커버리지 하한은 100%이며 `ssh-keygen`이 있는 Linux 레인에서 측정합니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/krl@v0.6.1](https://pkg.go.dev/github.com/go-authn/krl@v0.6.1)
