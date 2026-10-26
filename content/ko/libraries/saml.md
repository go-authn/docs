---
title: "saml — 페더레이션 앞의 서비스 공급자"
linkTitle: "saml"
weight: 100
description: "go-authn/saml은 RENATER나 eduGAIN 같은 연구 페더레이션을 위한 SAML 2.0 서비스 공급자입니다: 서명된 메타데이터, AuthnRequest, 그리고 모든 검사 후에 읽는 어서션."
tags: [라이브러리, saml, 페더레이션]
---

**이 사람의 신원 공급자는 그에 대해 무엇을 말했는가?** RENATER의 Fédération
Éducation-Recherche나 eduGAIN 같은 신원 페더레이션을 위한 SAML 2.0 서비스 공급자입니다.
페더레이션의 서명된 메타데이터를 읽고, 사람들을 자신의 기관의 신원 공급자로 보내고,
그 공급자가 말하는 것을 읽어 옵니다.

```sh
go get github.com/go-authn/saml@v0.5.0
```

이것은 [authn-bridge]({{< relref "/authn-bridge/_index.md" >}})의 페더레이션을 마주하는
절반이며, SAML SP가 되고 싶은 무엇이든 단독으로 사용할 수 있습니다. 여기에 없는 것:
IdP, 단일 로그아웃, 아티팩트 바인딩, 서명된 AuthnRequest, 속성 쿼리, SAML 1.1.

| | |
|---|---|
| `Federation` | 메타데이터를 가져와 **고정된** 인증서에 대해 검증하고, `Run`으로 최신 상태를 유지 |
| `ParseMetadata` | 이미 가진 문서에 대한 같은 검증 |
| `DiscoveryURL`, `Chosen` | 사람을 디스커버리 서비스로 보내고, 그가 선택한 IdP를 읽어 옴 |
| `SP.Request` | HTTP-Redirect로 보내는 AuthnRequest, 그리고 보관할 `Pending` |
| `SP.Accept` | ACS에 게시된 `SAMLResponse`를 `Assertion`으로 읽음 |
| `Assertion.Subject` | `subject-id`, 그다음 `pairwise-id`, 그다음 `eduPersonPrincipalName`, 그다음 `eduPersonTargetedID`, 그다음 영구 NameID — 메일은 절대 아님 |
| `SP.Metadata` | 페더레이션에 등록할 SP 자신의 메타데이터 |

## 예제 {#example}

디스커버리와 요청, 직접 기술한 IdP 하나로:

```go
package main

import (
	"fmt"
	"net/url"

	"github.com/go-authn/saml"
)

func main() {
	// One IdP, as a federation's metadata would describe it.
	idp := &saml.IdP{
		EntityID: "https://idp.univ-example.example/idp/shibboleth",
		SSO:      "https://idp.univ-example.example/idp/profile/SAML2/Redirect/SSO",
		Scopes:   []string{"univ-example.example"},
	}
	md := &saml.Metadata{IdPs: map[string]*saml.IdP{idp.EntityID: idp}}

	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Federation: md,
	}

	// Send the person to the discovery service, then read back what it chose.
	d, _ := saml.DiscoveryURL("https://discovery.renater.fr/renater", sp.EntityID, "https://app.example.org/saml/chosen")
	fmt.Println(d)

	_, err := saml.Chosen(url.Values{"entityID": {"https://idp.attacker.example/idp"}}, md)
	fmt.Println(err)
	chosen, _ := saml.Chosen(url.Values{"entityID": {idp.EntityID}}, md)

	// The AuthnRequest, over HTTP-Redirect. Keep p, keyed by the RelayState,
	// and hand it to sp.Accept at the ACS.
	to, p, err := sp.Request(chosen, "s1", saml.Options{AuthnContext: []string{"https://refeds.org/profile/mfa"}})
	if err != nil {
		panic(err)
	}
	u, _ := url.Parse(to)
	fmt.Println(u.Host, u.Query().Has("SAMLRequest"), u.Query().Get("RelayState"), p.IdP, p.AuthnContext)

	// RelayState is limited to 80 bytes, and refused beyond that.
	_, _, err = sp.Request(chosen, string(make([]byte, 81)), saml.Options{})
	fmt.Println(err)
}
```

```
https://discovery.renater.fr/renater?entityID=https%3A%2F%2Fapp.example.org%2Fsaml&return=https%3A%2F%2Fapp.example.org%2Fsaml%2Fchosen&returnIDParam=entityID
the chosen identity provider is not in the federation
idp.univ-example.example true s1 https://idp.univ-example.example/idp/shibboleth [https://refeds.org/profile/mfa]
RelayState is limited to 80 bytes
```

서비스에서는 메타데이터가 페더레이션에서 오고 응답이 ACS에 도착합니다.

```go
package main

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"log"
	"net/http"
	"os"

	"github.com/go-authn/saml"
)

func main() {
	ctx := context.Background()

	// The federation's metadata signing certificate, downloaded ONCE and
	// checked against the fingerprint the federation publishes.
	fed := &saml.Federation{
		URL:  "https://pub.federation.renater.fr/metadata/fer/idps.xml",
		Cert: readCert("/etc/app/metadata-signature-2026.pem"),
	}
	if err := fed.Refresh(ctx); err != nil {
		log.Fatal(err)
	}
	go fed.Run(ctx, func(err error) { log.Print(err) })

	pair, err := tls.LoadX509KeyPair("/etc/app/saml.crt", "/etc/app/saml.key")
	if err != nil {
		log.Fatal(err)
	}
	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Key:        pair.PrivateKey.(*rsa.PrivateKey), // assertions arrive encrypted to it
		Cert:       pair.Leaf,
		Federation: fed,
	}

	http.HandleFunc("/saml/acs", func(w http.ResponseWriter, r *http.Request) {
		p := pendingFor(r.PostFormValue("RelayState")) // what Request returned, from the session
		a, err := sp.Accept(r.PostFormValue("SAMLResponse"), p)
		if err != nil {
			log.Print(err) // for the log, not for the browser
			http.Error(w, "refused", http.StatusForbidden)
			return
		}
		id, from := a.Subject()
		log.Printf("%s (%s) from %s", id, from, a.IdP.EntityID)
	})
	log.Fatal(http.ListenAndServeTLS(":443", "/etc/app/tls.crt", "/etc/app/tls.key", nil))
}

func readCert(path string) *x509.Certificate {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		log.Fatal("no PEM block in ", path)
	}
	c, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		log.Fatal(err)
	}
	return c
}

// pendingFor is the caller's session store.
func pendingFor(relayState string) saml.Pending { return saml.Pending{} }
```

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**메타데이터:**

| | 이유 |
|---|---|
| **고정된** 인증서로 서명되지 않음 | 인증서는 파라미터이며 메타데이터와 함께 가져오지 않습니다. 보증하는 문서와 같은 경로로 도착한 키는 아무것도 보증하지 못합니다 |
| `validUntil`이 지났거나 없음 | 만료되지 않는 서명된 문서는 끝나지 않는 키 유출입니다. 실패한 갱신은 그 사본이 만료될 때까지 마지막으로 성공한 사본을 유지합니다 |
| 지금부터 28일을 넘게 유효함 | `Federation.MaxValidity`가 한계를 바꾸며, 음수 값은 한계를 없앱니다 |
| 사용 중인 사본보다 오래됨 | 롤백: 유효하게 서명되었고 그 사이 폐기된 키를 담고 있을 수 있음 |
| 루프백이 아닌 곳에서 `http://`로 가져옴 | 서명이 변경은 잡아내겠지만, 새 문서를 붙잡아 두는 경로는 잡아내지 못합니다 |

메타데이터에 있는 IdP의 인증서는 페더레이션의 서명이 그것을 지명하기 때문에 신뢰됩니다.
IdP 인증서는 자체 서명되었고 만료된 경우가 많으므로 그 날짜는 보지 않습니다.

**응답**은 `Accept`에서 검사합니다. 아래의 각 거부는 서버의 로그를 위해 호출자에게 오류로
반환됩니다.

| | 이유 |
|---|---|
| 아무것도 서명되지 않음, 또는 SHA-1로 서명됨 | saml-profiles 4.1.4.5: POST에서는 어서션이 서명되어야 합니다. Shibboleth IdP는 기본적으로 Response에 서명하며 어느 쪽이든 받아들입니다 |
| 어서션이 둘 이상 | 서명된 것과 서명되지 않은 것이 함께 도착해 잘못된 것을 읽게 되는 방식(CVE-2022-41912) |
| 서명이 덮지 않은 모든 것 | 절대 읽지 않습니다. 서명이 다이제스트한 바이트로 다시 만든 요소만 읽습니다 |
| IdP의 `Scopes` 밖의 스코프 식별자 | 버려짐: 그렇지 않으면 어느 IdP든 `alice@another-university.example`을 어서션할 수 있습니다 |
| 검증된 서명이 덮지 않는 AES-CBC 암호문 | 복호화조차 하지 않습니다. 인증되지 않은 CBC는 패딩 오라클입니다. RSA PKCS#1 v1.5 키 전송은 아예 받아들이지 않으며, AES-GCM과 RSA-OAEP는 받아들입니다 |
| 다른 audience, ACS 또는 요청, 요청하지 않은 응답, 한 시간이 넘은 요청 | saml-profiles 4.1.4.3 |
| 이미 사용된 어서션 | 베어러 어서션은 그것을 가진 사람이 곧 주인입니다 |
| 이해하지 못하는 조건 | saml-core 2.5.1: 그러면 어서션은 Indeterminate입니다 |
| MFA를 요청했는데 반환된 비밀번호 (`Options.AuthnContext`) | IdP는 요청을 무시할 수 있습니다 |
| `ForceAuthn`일 때 요청 이전의 `AuthnInstant` | IdP가 재사용하지 말라고 요청받은 세션을 재사용했습니다 |

{{< callout type="warning" >}}
**기본 재생 캐시는 한 프로세스의 메모리입니다**

`SP.Replay`의 기본값은 `NewMemoryReplay()`입니다. 로드 밸런서 뒤의 여러 인스턴스는
각각 같은 어서션을 한 번씩 받아들일 것이며, 재시작하면 비워집니다. 공유 저장소 위에
`Replay`를 구현하십시오. `Use`는 원자적이어야 합니다.
{{< /callout >}}

## 이 패키지 위에 만든 프로그램 테스트하기: `samltest` {#samltest}

`github.com/go-authn/saml/samltest`(v0.5.0부터)는 이 패키지 위에 만든 프로그램, 예를 들어
페더레이션 앞의 OpenID 공급자(go-authn/bridge)나 그 뒤에 있는 것(go-llmflow/bench)을
테스트하기 위한 페더레이션과 IdP입니다. 순수 Go이며 **사용하는 데 xmlsec1이 필요 없습니다**.

```go
fed, _ := samltest.NewParty("federation")
key, _ := samltest.NewParty("idp")
idp := &samltest.IdP{EntityID: "https://idp.univ-ex.example/idp/shibboleth",
	Scope: "univ-ex.example", SSO: srv.URL + "/SSO", Signer: key}
md, _ := (&samltest.Federation{Signer: fed, IdPs: []*samltest.IdP{idp}}).Metadata(24 * time.Hour)
// serve md; pin fed.Fingerprint() in the program's configuration
srv.Config.Handler = idp.Handler(spEntityID, acsURL, spCert, func(user, pw string) ([]samltest.Attribute, bool) {
	return []samltest.Attribute{{Name: samltest.EPPN, Values: []string{user + "@univ-ex.example"}},
		{Name: samltest.Entitlement, Values: []string{"grp-alpha"}}}, pw == "secret"
})
```

- **메타데이터**: 페더레이션의 키로 서명한 `EntitiesDescriptor`이며, 각 IdP의 스코프,
  표시 이름, 서명 인증서, HTTP-Redirect SSO 위치를 담습니다.
- **응답**: `IdP.Response`는 요청 ID, 오디언스, ACS, 속성이 담긴 `Assertion`을 받습니다.
  Response는 RSA-SHA256, 배타적 c14n, enveloped 방식으로 Issuer 뒤에 서명됩니다.
  어서션은 SP의 인증서로 AES-128-GCM과 RSA-OAEP MGF1-SHA1(Shibboleth IdP v5의 기본값)으로
  암호화되며, `EncryptTo`가 nil이면 평문 상태로 어서션 자체가 서명됩니다.
- **로그인**: `IdP.Handler`는 AuthnRequest에 대해 사용자 이름과 비밀번호 폼을 보여 주고,
  `SAMLResponse`와 `RelayState`를 ACS로 보내는 폼으로 응답합니다. 테스트의 HTTP 클라이언트는
  브라우저의 스크립트처럼 이를 제출합니다.

출력은 그것을 작성하지 않은 쪽이 판정합니다. **xmlsec1**이 메타데이터와 두 종류의
Response를 검증하고 어서션을 복호화하며(xmlsec1이 없으면 이 테스트는 그 사실을 밝히고
건너뛰고, `SAML_REQUIRE_JUDGE=1`이면 실패합니다), 이 패키지의 **SP**는 이를 수락하고, 변조되었거나
재생되었거나 페더레이션이 나열하지 않은 키로 서명된 것은 거부합니다. 키는 호출마다
생성되므로 여기 있는 어떤 것도 프로덕션용이 아닙니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

- **RENATER 자체의 메타데이터**를 RENATER가 2026-09-29에 서명한 그대로
  `testdata/fer-idps.xml.gz`에 두고, 그 인증서를 RENATER가 공개하는 SHA-256 지문과
  대조합니다. IdP 343개를 모두 읽으며, `Location` 하나의 호스트를 다시 쓰면 거부됩니다.
  s390x를 포함한 아키텍처 레인도 그 서명을 검증합니다.
- **xmlsec1**이 스위트의 모든 응답에 템플릿으로 서명하고 암호화합니다. GCM과 CBC,
  SHA-1과 SHA-256의 RSA-OAEP, Response 서명, 어서션 서명, 둘 다. Linux 테스트 레인,
  레이스 감지기, 커버리지 레인은 이를 설치하고 `SAML_REQUIRE_JUDGE`를 설정합니다.
- **crewjam/saml의 IdP**가 별도의 CI 작업(`interop/crewjam`, 게시된 모듈에 없는
  독립 모듈)에서 이 SP의 AuthnRequest에 대한 전체 응답을 작성합니다. Response가
  서명된 AES-128-CBC의 RSA-SHA256은 받아들여지고, 기본값인 RSA-SHA1은 거부되며,
  Response 서명을 제거한 같은 CBC 어서션은 복호화 전에 거부됩니다.

커버리지 레인의 하한은 92%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/saml@v0.4.1](https://pkg.go.dev/github.com/go-authn/saml@v0.4.1)
