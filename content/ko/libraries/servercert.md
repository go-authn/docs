---
title: "servercert — 데몬의 TLS 인증서는 어디서 오는가"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert는 바뀌면 다시 읽는 파일의 TLS 서버 인증서를, 또는 External Account Binding을 포함해 autocert를 통한 ACME CA의 인증서를 제공합니다."
tags: [라이브러리, tls, acme, 인증서]
---

**데몬의 TLS 서버 인증서는 어디서 오는가?** 디스크의 인증서와 키로, 바뀌면 다시
읽습니다. 또는 [`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert)를 통한
ACME CA로, External Account Binding을 포함합니다.

```sh
go get github.com/go-authn/servercert@v0.5.2
```

`Config`는 정확히 하나의 소스 — `CertFile`과 `KeyFile`, 또는 `ACME` — 를 지정하며,
`New`는 `TLSConfig()`가 이를 제공하는 `*Source`를 반환합니다. `MinVersion`은 TLS
1.2입니다.

## 예제 {#example}

파일로:

```go
package main

import (
	"log"
	"net/http"

	"github.com/go-authn/servercert"
)

func main() {
	src, err := servercert.New(servercert.Config{
		CertFile: "/etc/fileshare/tls/fullchain.pem",
		KeyFile:  "/etc/fileshare/tls/privkey.pem",
		OnError:  func(err error) { log.Print(err) }, // a renewal that did not load
	})
	if err != nil {
		log.Fatal(err) // unreadable, unparsable, or a key that is not the certificate's
	}
	srv := &http.Server{Addr: ":443", TLSConfig: src.TLSConfig()}
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
```

`Config.Check`는 동작할 수 없는 구성을 거부하며 아무것도 건드리지 않습니다. 파일을
읽지도, 디렉터리를 만들지도 않습니다.

```go
package main

import (
	"fmt"

	"github.com/go-authn/servercert"
)

func main() {
	// Check touches nothing: no file is read, no directory created.
	for _, c := range []servercert.Config{
		{ACME: &servercert.ACME{Domains: []string{"*.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"192.0.2.10"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "acme"}},
		{CertFile: "/etc/fileshare/tls/fullchain.pem"},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme",
			DirectoryURL: "http://acme.example.org/directory"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
	} {
		fmt.Println(c.Check())
	}
}
```

```
servercert: ACME domain "*.example.org" is a wildcard; that needs dns-01, which autocert does not do
servercert: ACME domain "192.0.2.10" is an IP address; autocert issues only for DNS names
servercert: ACME.CacheDir "acme" is not an absolute path
servercert: CertFile and KeyFile go together; one of them is empty
servercert: ACME.DirectoryURL "http://acme.example.org/directory" is not an https URL (RFC 8555 §6.1)
<nil>
```

마지막은 Let's Encrypt 운영 환경입니다: `DirectoryURL`이 비어 있습니다.

## 파일 {#files}

`New`는 쌍을 읽고, 읽을 수 없거나, 구문 분석되지 않거나, 키가 인증서의 것이 아닌
쌍에 대해 **지금** 실패합니다. 그 후에는 핸드셰이크 중에 최대 10초에 한 번 파일을 다시
읽으며, 바뀐 쌍은 락을 잡지 않고 구문 분석하여 교체합니다. 로드되지 **않는** 바뀐 쌍 —
키보다 먼저 기록된 인증서, 잘린 파일 — 은 `OnError`에 한 번 보고되고 마지막으로 정상인
쌍이 계속 사용되므로, 두 파일을 차례로 기록하는 갱신 작업이 서버를 내리는 일은
없습니다.

## ACME {#acme}

autocert는 두 가지 챌린지 타입에만 응답합니다. `tls-alpn-01`(RFC 8737, 443 포트, ALPN
`acme-tls/1`)과, `HTTPChallenge`가 있을 때 `http-01`(RFC 8555 §8.3, 80 포트,
`Source.HTTPHandler`가 제공)입니다. `dns-01`은 없으므로 와일드카드도 IP 주소
인증서도 없습니다.

인증서는 SNI가 `Domains` 중 하나를 지정하는 첫 핸드셰이크에서, 또는 어떤 클라이언트보다
먼저 `Source.Prefetch`로 받으며, 만료 전에 autocert가 갱신합니다. IP 주소로 연결하는
클라이언트는 SNI를 보내지 않으며 첫 번째 도메인의 인증서를 받습니다.

{{< callout type="warning" >}}
**`NextProtos`는 교체하지 말고 추가하십시오**

ACME에서는 `TLSConfig().NextProtos`가 `acme-tls/1`을 담고 있으며, 이것이 없으면 CA의
tls-alpn-01 검증이 실패합니다. 그리고 추가해야 합니다. ALPN 프로토콜을 알리는 Go TLS
서버는 제안이 하나도 겹치지 않는 클라이언트를 거부하므로, NFS-over-TLS 서버는 `sunrpc`를
추가합니다(RFC 9289). `net/http`는 `http/1.1`과 `h2`를 스스로 추가합니다.
{{< /callout >}}

**챌린지가 필요 없는 CA.** autocert는 새 주문이 이미 `ready`이면 즉시 반환하며, 이는
도메인이 사전 검증된 CA가 응답하는 방식입니다. Enterprise Admin 계정에 대한, HARICA가
제공하는 GÉANT TCS가 그렇습니다. 인터넷에서 80 포트에도 443 포트에도 도달할 수 없는 내부
서버도 공개적으로 신뢰되는 인증서를 받을 수 있습니다. EAB HMAC 키는 비밀 값이므로 구성은
키가 아니라 그것을 담은 **파일**(`EABHMACKeyFile`)을 지정합니다.

`x/crypto/acme`의 결함 하나는 우회합니다
([golang/go#77704](https://github.com/golang/go/issues/77704)). CA가 아직 처리 중인
주문을 확정한 뒤, 클라이언트는 finalize 응답의 `Location` 헤더 URL을 폴링하는데 RFC 8555는
거기에 그것을 두지 않습니다. servercert는 이전 newOrder 응답에서 얻은 주문의 URL로 그
헤더를 추가하는 트랜스포트를 ACME 클라이언트에 줍니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

`Check`는 거부합니다. 소스가 없거나 둘 다 있는 경우, 파일 쌍의 절반, 도메인이나 캐시
디렉터리가 없는 ACME, 상대 경로, EAB의 절반, IP 주소이거나 와일드카드이거나 레이블이
하나이거나 점으로 끝나거나 유효한 호스트 이름이 아닌 도메인, https가 아닌 디렉터리
URL(RFC 8555 §6.1).

`New`는 또한 개인 키를 담고 있는 캐시 디렉터리가 심볼릭 링크이거나, 그룹이나 다른
사용자가 접근할 수 있거나, 프로세스의 유효 사용자가 아닌 사용자가 소유하거나, 쓸 수
없으면 거부합니다. 없으면 `0700`으로 만들고 이후에 검사합니다. 그 위의 모든 디렉터리는
sshd의 `StrictModes`가 `authorized_keys`로 가는 경로에 요구하는 것처럼 root나 유효
사용자만 바꿀 수 있어야 하며, 그 위의 심볼릭 링크는 root가 소유하지 않으면 거부됩니다.
Windows에서는 모드와 소유자를 검사하지 않습니다. ACL이 둘 다 결정하며 제한하는 것은
사용자의 몫입니다. 경로의 어디든 심볼릭 링크가 있으면 거부됩니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**pebble**, Let's Encrypt의 테스트 CA를 `ca`, `db`, `va`, `wfe` 패키지로 프로세스
안에서 DNS 스텁과 함께 실행하여, `crypto/tls`가 pebble의 루트에 대해 검증하는 실제
인증서를 발급합니다. tls-alpn-01, `HTTPHandler`를 통한 http-01과 `HTTPChallenge`를 끈
대조군, EAB 필수/없음/틀림/맞음, 챌린지 포트가 열려 있지 않은 상태에서 발급된 사전 검증
도메인과 그 대조군. 한 테스트는 golang/go#77704 우회 없이 같은 발급을 실행하여 실패해야
함을 요구합니다. 커버리지 하한은 100%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/servercert@v0.5.2](https://pkg.go.dev/github.com/go-authn/servercert@v0.5.2)
