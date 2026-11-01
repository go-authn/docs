---
title: "kdc — 디렉터리에서 Kerberos 티켓 발급하기"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc는 Kerberos의 발급 쪽 절반입니다: UDP와 TCP의 AS 및 TGS, 필수 사전 인증, 하나의 암호화 타입, go-authn 디렉터리의 사람들."
tags: [라이브러리, kerberos, 디렉터리]
---

**렐름은 디렉터리에서 어떻게 티켓을 발급하는가?** [디렉터리]({{< relref "/libraries/directory.md" >}})가
아는 사람들과 keytab이 보유한 서비스에 대해, UDP와 TCP로 AS-REQ와 TGS-REQ를 처리하며
암호화된 타임스탬프 사전 인증이 필수입니다. [authnd]({{< relref "/authnd/_index.md" >}}) 아래에서
실행됩니다.

```sh
go get github.com/go-authn/kdc@v0.4.5
```

v0.4.5의 `go.mod`는 최소 `go-authn/directory` v0.16.1과 gokrb5 v8.4.4를 요구합니다.
이는 최소 요구 버전이므로, directory v0.16.1을 요구하는 프로그램은
authnd v0.15.0처럼 v0.17.0으로 빌드됩니다. 받아들이는 쪽 절반은
[krb5]({{< relref "/libraries/krb5.md" >}})이며, 티켓을 검증하기만 하는 서비스에는 이
모듈이 전혀 필요하지 않습니다.

구현되지 않은 것: 크로스 렐름 리퍼럴, PKINIT, FAST, 갱신 가능하거나 사후 날짜의
티켓, 그리고 모든 kadmin 프로토콜. 키는 디렉터리와 keytab에서 오며, 그것이 있는 곳에서
바뀝니다.

## 비밀번호를 보유한 소스만이 렐름을 뒷받침할 수 있습니다 {#only-a-source-holding-the-password-can-back-a-realm}

KDC는 클라이언트의 사전 인증을 그 사람의 장기 키로 **복호화**해야 하므로,
`directory.Verifier` — 다른 사람의 LDAP에 대한 바인드, 해시 비교 — 는 *이것이 올바른
비밀번호인가*에 아무리 잘 답하더라도 소용이 없습니다. 소스에 비밀번호가 없는 사람에게는
`KDC_ERR_NULL_KEY`(*null key*)로 응답하며, 잘못된 비밀번호에 주는 코드는 절대 아니므로,
다시 입력할 비밀번호가 아니라 고쳐야 할 구성으로 읽힙니다.

## 예제 {#example}

루프백의 메모리 내 렐름:

```go
package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/go-authn/directory"
	"github.com/go-authn/kdc"
	"github.com/jcmturner/gokrb5/v8/iana/etypeID"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

func main() {
	// People: a source that holds PASSWORDS. A verifier cannot back a realm.
	people := &directory.Static{Name: "the configuration file", People: []*directory.Identity{
		directory.NewIdentity("alice", directory.WithPassword("correct horse battery staple")),
	}}

	// Services: the realm's own krbtgt key, and one per service.
	kt := keytab.New()
	for _, p := range []string{"krbtgt/EXAMPLE.ORG", "nfs/files.example.org"} {
		if err := kt.AddEntry(p, "EXAMPLE.ORG", rand.Text(), time.Now(), 1, etypeID.AES256_CTS_HMAC_SHA1_96); err != nil {
			log.Fatal(err)
		}
	}

	// A keytab without krbtgt/REALM is refused before anything listens.
	_, err := kdc.New(kdc.Config{Realm: "OTHER.ORG", People: people, Services: kt})
	fmt.Println(err)

	srv, err := kdc.New(kdc.Config{
		Realm:    "EXAMPLE.ORG",
		People:   people,
		Services: kt,
		Logf:     log.Printf, // why each request was refused; never a key
	})
	if err != nil {
		log.Fatal(err)
	}
	pc, err := net.ListenPacket("udp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	go srv.ServeTCP(ln)
	fmt.Println("EXAMPLE.ORG answers on", pc.LocalAddr())
	log.Fatal(srv.ServeUDP(pc))
}
```

`EXAMPLE.ORG`에 대해 `kdc = tcp/127.0.0.1:18088`을 지정한 `krb5.conf`가 있으면,
`KRB5_CONFIG=krb5.conf`와 `KRB5CCNAME=FILE:cc`로 macOS가 제공하는 Heimdal `kinit`(1.5.1)이
티켓 발급 티켓을 받습니다.

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  nfs/files.example.org@EXAMPLE.ORG
```

10시간은 `Config.Lifetime`의 기본값이며, 서비스 티켓은 그것을 얻는 데 쓴 티켓 발급
티켓과 함께 끝납니다. KDC는 각 요청을 왜 거부했는지를 자신의 로그에 남겼습니다.

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

각 교환의 첫 번째 거부는 프로토콜이 동작하는 것입니다. 사전 인증을 요구하는
`KRB-ERROR`는 etype과 salt를 지정하는 `ETYPE-INFO2` 힌트를 담고 있고, 클라이언트는
타임스탬프를 붙여 다시 시도합니다.

{{< callout type="info" >}}
**v0.4.2 이전에는 `till`이 19700101000000Z이면 이미 만료된 티켓을 받았습니다**

RFC 4120 §5.4.1: `till`이 19700101000000Z이면 KDC 정책이 허용하는 최대 종료 시각을
요청하는 것입니다. Heimdal의 `kgetcred`가 정확히 이것을 보냅니다. v0.4.1은 Go의 영
시각만 검사했으므로 Unix epoch를 실제 종료 시각으로 받아들여, `klist`에 `>>>Expired<<<`로
표시되는 서비스 티켓을 발급했습니다. CI의 판정자인 MIT의 `kvno`는 실제 `till`을 보내므로
이 경우를 만난 적이 없습니다. v0.4.2는 위와 같이 허용되는 가장 긴 티켓을 발급하고,
이미 지난 `till`에는 도착하자마자 만료된 티켓 대신 `KDC_ERR_NEVER_VALID`로 응답합니다
([go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19)).
{{< /callout >}}

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**구성할 때**(`New`): 렐름 없음(`ErrNoRealm`), 디렉터리 없음(`ErrNoPeople`), keytab
없음(`ErrNoServices`), 또는 `krbtgt/REALM@REALM`이 없는 keytab(`ErrNoTGTKey`) —
시작해 놓고 첫 `kinit`에서 실패하여, 고칠 수 없는 사람에게 오류가 도달하는 것보다
낫습니다.

**AS에서:** 사전 인증이 없는 요청은 그것을 요구하는 응답을 받으며, 확인할 타임스탬프가
있기 전까지는 사람의 키를 파생하지 않으므로, 실제 principal을 지명하는 위조된 UDP
패킷은 키 파생 비용을 발생시키지 않습니다. 잘못된 비밀번호, 다른 etype의 타임스탬프,
한 시간 전의 타임스탬프는 모두 잘못된 비밀번호가 받는 코드인 `KDC_ERR_PREAUTH_FAILED`로
응답합니다. 오류 텍스트가 이유를 지명하고 `Logf`도 그렇습니다. 자신의 TGT를 요청하는
서비스는 거부됩니다. 서비스는 keytab으로 인증합니다.

**하나의 암호화 타입.** 티켓과 키는 `aes256-cts-hmac-sha1-96`(etype 18)뿐입니다.
etype 목록에 18이 없는 요청은 누구를 조회하기 전에 `KDC_ERR_ETYPE_NOSUPP`로
응답합니다. `Logf`가 설정되어 있으면 로그에 양쪽 etype이 기록되므로, 운영자는 암호가
맞지 않는 것과 비밀번호를 잘못 입력한 것을 구별할 수 있습니다.

**TGS에서**(RFC 4120 §3.3.2) 티켓은 다음일 때만 발급됩니다.

- 제시된 티켓이 이 렐름의 TGT이고, 티켓이 주장하는 서비스의 키가 아니라 KDC가 지정한
  `krbtgt/REALM` 키로 복호화될 때(`KRB_AP_ERR_NOT_US`)
- authenticator가 세션 키로 복호화되고 `MaxSkew` 이내일 때
- 체크섬이 도착한 그대로의 이 요청 본문에 대한 것이며 세션 키로 키가 지정되었을 때(없거나
  키가 지정되지 않았으면 `KRB_AP_ERR_INAPP_CKSUM`, 틀리면 `KRB_AP_ERR_MODIFIED`)
- TGT가 끝나지 않았고(`KRB_AP_ERR_TKT_EXPIRED`), 시작 전이 아니며 invalid로 표시되지
  않았을 때(`KRB_AP_ERR_TKT_NYV`), 오차는 허용되지 않음: 그 시각들은 이 KDC의 시계가
  기록했기 때문
- 클라이언트가 이 렐름의 것이고 여전히 디렉터리에 있을 때
  (`KDC_ERR_C_PRINCIPAL_UNKNOWN`)

**v0.4.5부터**, 보안 감사와 퍼징·카오스 실행을 거쳐:

- 다른 렐름에 대한 요청은 처리되지 않고 AS와 TGS 모두에서 `KDC_ERR_WRONG_REALM`으로 응답합니다.
- 읽을 수 없는 디렉터리는 `KDC_ERR_SVC_UNAVAILABLE`로 응답하며, 더 이상 `KDC_ERR_C_PRINCIPAL_UNKNOWN`이 아닙니다.
- 시작이 `MaxSkew` 안의 미래인 TGT는 받아들입니다(시계 단계). 이전에는 TGT의 시작에 허용 오차가 없었습니다.
- **잘못된 AS-REQ나 TGS-REQ 하나로 프로세스가 크래시할 수 있었습니다**. gokrb5 v8.4.4의
  `unmarshalTicketsSequence`가 인증 이전에 패닉합니다. 디코더를 패닉시키는 요청은 이제 버려지고, 패닉과 그 스택이
  기록됩니다.
- 네트워크에서 온 프린시펄 이름은 줄을 위조할 수 없도록 로그에서 따옴표로 묶입니다.
- 의존성은 golang.org/x/net v0.62.0(GO-2026-6866, GO-2026-6860)과 go-authn/directory v0.16.1입니다.
  GO-2026-5932(`golang.org/x/crypto/openpgp`)는 업스트림에 수정이 없고 호출되지 않습니다.

`FuzzHandle`은 두 번의 실행(90초와 150초)에서 약 1,400만 회 실행되었고 빠져나온 패닉은 없었습니다.
`BenchmarkASNoPreauth`, 10,000명 중 마지막 사람, 사전 인증 없이: 요청당 할당 508회, 18,999바이트, 112 µs입니다. 이 경로의
코드는 바뀌지 않았으므로 이전 수치는 없습니다. 시간은 참고용일 뿐입니다. 부하가 65였으므로 MIT의 `krb5kdc`와는
비교하지 않았습니다.

**수명.** `Config.Lifetime`이 티켓의 상한이며 0이면 10시간입니다. 더 적게 요청하는
클라이언트는 더 적게 받고, TGT로 얻은 티켓은 그 TGT보다 늦게 끝나지 않으므로
`krbtgt`를 다시 요청해도 자격 증명을 늘릴 수 없습니다.

**인증되지 않은 피어가 붙들 수 있는 것:** TCP 메시지는 길이를 포함해 30초 이내에
도착해야 하고, 동시에 최대 256개의 TCP 연결이 서비스되며, 동시에 최대 64개의
데이터그램에 응답합니다. 하나가 더 오면 버려지고 클라이언트는 다시 보내거나 TCP로
돌아갑니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**MIT 자체의 `kinit`과 `kvno`**를 pkgx로 가져와, Go로 만든 렐름에 대해 실행합니다.
MIT KDC는 관여하지 않으며 클라이언트만 빌려 옵니다.
`TestMITClientGetsATGTAndAServiceTicket`이 TGT와 서비스 티켓을 받고 `kvno`가 보고하는
키 버전을 검사합니다. Linux 테스트 레인, 레이스 감지기, 커버리지 레인은
`KDC_REQUIRE_JUDGE=1`을 설정하며, 로그에 *were served by this realm*이 없으면 추가
단계가 실패합니다. 테스트는 실제 클라이언트가 유발하지 않는 거부도 고정합니다. 잘못된
키의 타임스탬프, 한 시간 전의 것, 3바이트 암호, AS-REQ에서 직접 요청한 서비스, TGS에서
위조한 서비스 티켓, 검증자가 뒷받침하는 렐름. 커버리지 레인의 하한은 80%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/kdc@v0.4.5](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.5)
