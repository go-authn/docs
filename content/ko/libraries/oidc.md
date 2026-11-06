---
title: "oidc — 베어러 토큰 검증하기"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc는 OpenID Connect 토큰을 신원으로 검증합니다: 디스커버리, 키 집합, 알고리즘 허용 목록, 그리고 중요한 거부. 의존성 없음."
tags: [라이브러리, oidc, 토큰]
---

**이 베어러 토큰은 누가 요청한다고 말하며, 믿어야 하는가?** 디스커버리, 키 집합,
그리고 리소스 서버가 해야 하는 검사를 순수 Go로, 표준 라이브러리 밖의 **의존성
없이** 제공합니다.

```sh
go get github.com/go-authn/oidc@v0.6.0
```

여기에는 로그인 흐름이 없습니다. 리디렉션도, 코드 교환도, 클라이언트 시크릿도,
쿠키도 없습니다. 이것은 **리소스 서버** 쪽 절반입니다. 토큰을 가진 무언가가 도착하면
이것이 그것이 누구인지 알려 줍니다.

## 예제 {#example}

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/go-authn/oidc"
)

func main() {
	// Discovery happens here, at startup: an issuer that does not answer is
	// a server that cannot authenticate anybody.
	v, err := oidc.New(context.Background(), oidc.Config{
		Issuer:   "https://login.example.org",
		Audience: "fileshare",
		Type:     "at+jwt", // a resource server takes access tokens, not ID tokens
	})
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		tok, err := v.Verify(r.Context(), raw)
		if err != nil {
			log.Print(err) // which check refused it: for this log only
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		fmt.Fprintln(w, tok.Subject(), tok.Username(), tok.Groups())
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

`Verifier`는 동시 사용에 안전하며 키 집합을 보유합니다. 시작할 때 하나를 만들어 계속
쓰십시오. `Verify`의 오류는 서버의 로그를 위해 어떤 검사가 토큰을 거부했는지 알려
주며, 클라이언트는 어떤 검사였든 하나의 거부만 받습니다.

`New`가 아무것도 가져오기 전에 거부하는 세 가지 구성:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/oidc"
)

func main() {
	ctx := context.Background()
	for _, cfg := range []oidc.Config{
		{Issuer: "http://login.example.org", Audience: "fileshare"},
		{Issuer: "https://login.example.org"},
		{Audience: "fileshare"},
	} {
		_, err := oidc.New(ctx, cfg)
		fmt.Println(err)
	}
}
```

```
oidc: http://login.example.org is not https: the key set decides every signature, and over cleartext so does anybody on the way
oidc: no audience: a token minted for another service is a valid token, and a verifier that does not check accepts every one the issuer ever signed
oidc: no issuer: a verifier without one accepts tokens from anybody
```

`Config`의 나머지는 선택 사항입니다. `JWKSURL`은 디스커버리를 건너뜁니다.
`UsernameClaim`과 `GroupsClaim`(기본값 `groups`)은 클레임을 지정합니다. `ClockSkew`와
`MinRefresh`의 기본값은 1분입니다. `Client`는 프록시, 사설 CA, 타임아웃을 위한 HTTP
클라이언트입니다. `Token`은 `Subject`, `Issuer`, `Audience`, `Email`, `EmailVerified`,
`Username`, `Groups`, `Expiry`, `NotBefore`, `IssuedAt`을 읽습니다. `Claim(name, &v)`는
다른 클레임을 디코딩하고, `Has(name)`은 그것이 있는지 알려 줍니다.

## 받아들이는 것 {#what-it-accepts}

서명 알고리즘 열 가지를 **허용 목록**으로 받아들입니다. `RS256` `RS384` `RS512`,
`PS256` `PS384` `PS512`, `ES256` `ES384` `ES512`, 그리고 `EdDSA`(Ed25519). `alg`가
이 중 하나가 아닌 토큰은 어떤 키를 가져오기 전에 거부됩니다. `alg: none`과 HMAC
계열은 목록에 없으므로 거부되며, 키는 알고리즘의 종류여야 합니다. `RS256`을 주장하는
토큰은 RSA 키로 검사하거나 거부됩니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

| | 이유 |
|---|---|
| `alg: none` | 서명되지 않았다고 말하는 토큰은 누군가 입력한 JSON 객체입니다 |
| 공개 키에 대한 HMAC | `HS256`은 공유 비밀 값을 받는데 발급자의 키는 공개되어 있습니다. 누구나 토큰을 만들 수 있게 됩니다 |
| 올바른 발급자로 **시작하기만** 하는 발급자 | `iss`는 통째로 비교합니다. `https://login.example.org.evil.test`는 올바른 문자열로 시작합니다 |
| 없거나 잘못된 **audience** | 다른 서비스를 위해 만들어진 토큰은 유효합니다. 이 서비스를 수신자로 하지 않을 뿐입니다 |
| **만료가 없는** 토큰 | 누군가 한 번 복사할 수 있는 비밀번호입니다 |
| **평문 HTTP** 위의 발급자, 키 집합, 리디렉션 (루프백 제외) | 키 집합이 모든 서명을 결정합니다 |
| 2048비트 미만의 RSA 키, `n`이나 `e`가 최단 형식이 아닌 것, 곡선 위에 없는 EC 점 | 짧은 키의 서명은 위조될 수 있습니다. v0.2.2 이전에는 0 바이트로 채운 1024비트 모듈러스가 2048비트로 통과했습니다 |
| `sig`가 아닌 `use`로 게시된 키 | 키 집합은 정당하게 암호화 키도 담고 있습니다 |
| `Type`이 설정되었으면 다른 `typ`의 토큰, 설정되지 않았으면 `JWT`나 `at+jwt`가 아닌 `typ` (`typ` 헤더가 없는 토큰은 통과) | RFC 9068 §4: 리소스 서버는 `typ: at+jwt`를 검사해야 하며, 그렇지 않으면 audience가 일치할 때마다 ID 토큰을 액세스 토큰으로 받아들입니다 |
| 표준 base64url이 아닌 부분 | 토큰이 하나의 문자열로 검증됩니다 |

ECDSA의 `s`와 `n − s`는 알고리즘이 허용하는 대로 둘 다 검증됩니다. 그래서 거부 목록이나
재생 캐시는 전송된 토큰이 아니라 `jti`나 `sub`를 키로 삼습니다.

**키는 교체되며, 알 수 없는 키가 발급자를 두드리는 방법이 되어서는 안 됩니다.** 가진
것으로 검증할 수 없는 서명은 `kid`가 새 것이든 같은 `kid`가 새 키를 담고 있든,
`MinRefresh`마다 키 집합을 한 번 다시 가져올 가치가 있습니다. 가져오는 중에 키 집합이
필요한 토큰은 그것을 기다리며, 실패한 가져오기도 집계됩니다.

**`Username()`이 주는 이름.** 기본적으로 `preferred_username`, 그다음 **`email_verified`가
true일 때만** `email`, 그다음 `sub`입니다. 확인되지 않은 이메일은 사람이 입력한
문자열입니다(OIDC Core §5.1). 구성된 `UsernameClaim`은 폴백 없이 지정된 그대로
읽습니다.

## 여러 발급자, 그리고 일부 기관만 허용 {#several-issuers-and-only-some-institutions}

**v0.5.0** 부터 `oidc.NewSet(v1, v2, …)` 는 여러 발급자의 토큰을 검증합니다. 검증기마다 고유한 audience 와 키 집합을 가집니다. 토큰은 **검증되지 않은** `iss` 로 그 발급자에 정확히 설정된 검증기로 전달되어 거기서 검증됩니다(그 발급자의 키로 서명, `iss` 재확인, audience, 시각). `iss` 를 읽는 것은 키 집합을 고르는 데 그치며, 위조된 토큰은 이어지는 검증에서 실패합니다. 알 수 없는 `iss` 는 `ErrUnknownIssuer` 이며 네트워크 접근이 없습니다. 다른 발급자의 키 집합을 시도하는 일은 없고, 한 발급자에 두 검증기를 두면 거부되며, `MaxTokenSize`(16 KiB)를 넘는 토큰은 디코딩 전에 거부됩니다.

연합 프록시(MyAccessID 를 통한 eduGAIN, eduTEAMS, Renater, Keycloak 브로커) 뒤에서는 `oidc.Accept{Claim, Values}` 와 `oidc.Check(accepts, token)` 가 클레임에 제공 대상 기관의 값이 하나도 없는 토큰을 거부합니다. 모든 accept 가 충족되어야 하며, 다중 값 클레임은 값 하나만 일치하면 됩니다. 없거나 문자열(또는 문자열 목록)이 아닌 클레임은 아무것도 포함하지 않습니다. 대소문자 규칙은 클레임의 스키마를 따릅니다. `schac_home_organization`(SCHAC 1.6.0, 도메인 이름, `caseIgnoreMatch`), `eduperson_scoped_affiliation`, `voperson_external_affiliation` 은 대소문자를 구분하지 않고, 나머지 클레임은 정확히 비교합니다. ASCII 문자만 접습니다(켈빈 기호 U+212A 는 `k` 가 아닙니다). 클레임은 검증되는 토큰에 있어야 합니다. MyAccessID 는 `schac_home_organization` 을 userinfo 로만 제공합니다. 로그인 쪽(제공자의 `rp.Set`, 제공자에 묶인 state, `iss` 의 RFC 9207 검사)은 [go-authn/rp](https://github.com/go-authn/rp) v0.4.0 에 있습니다. v0.4.0 부터는 로그인을 끝낼 수도 있습니다. `Client.Revoke(ctx, refreshToken, rp.RefreshTokenHint)` 는 제공자의 `revocation_endpoint`(RFC 7009)에 리프레시 토큰의 폐기를 요청하여, 로그아웃한 세션의 토큰 사본이 아무 가치도 없게 합니다. 이 엔드포인트가 없는 제공자는 `rp.ErrNoRevocation` 을 돌려줍니다.

## 범위가 있는 이름, 그리고 그 범위가 누구의 것인지 {#scoped-names}

계정은 기관에 상대적입니다. 연합 프록시 뒤에서는 하나의 발급자가 여러 기관의 사람을 보증합니다. `oidc.ScopedName(name, allowed, defaultScope)` 은 이 발급자가 주장할 수 있는 범위인지 Shibboleth 가 scope 를 검사하듯 **확인한 뒤** 이름을 ASCII 소문자 `local@scope` 로 돌려줍니다(eduPersonPrincipalName 은 eduPerson 스키마에서 `caseIgnoreMatch` 이며 단일 값입니다). 다른 범위는 `ErrScopeNotAllowed`, 범위도 기본값도 없는 이름은 `ErrNoScope` 입니다. `@` 가 없는 이름은 `defaultScope`(범위 이름보다 계정이 먼저 있던 기관)를 받으며, 이것도 허용되어야 합니다. `Token.ScopedUsername` 은 토큰의 사용자 이름에 이를 적용합니다. `UsernameClaim` 을 `eduperson_principal_name` 또는 `voperson_id` 로 설정하십시오. 이름에는 `@`가 정확히 하나 있어야 합니다. 둘 이상 있는 이름은 `ErrBadName`이며(v0.6.1부터), 로컬 부분에 `@`를 넣어 범위를 고를 수 없습니다. 범위는 그 뒤의 부분입니다.

**이름에 쓰는 접기는 하나뿐입니다**(v0.7.0부터). ASCII 문자만 접으며, 이 이름을 비교하거나 저장하는 서비스도 같은 방식으로 접어야 합니다. `oidc.ASCIILower(name)`와 `oidc.EqualASCIIFold(a, b)`가 그 유일한 접기입니다. `strings.ToLower`와 `strings.EqualFold`는 유니코드를 접어서 켈빈 기호 U+212A를 "k"와 같게 봅니다. `Kate`(켈빈 기호)와 `kate`는 발급자에게는 두 계정이지만 유니코드를 접는 소비자에게는 하나입니다.

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**pyjwt**가 테스트 스위트의 모든 토큰에 서명하므로, 검증자는 같은 손에서 나온 서명자에게
판정받지 않습니다. HMAC 혼동 토큰은 pyjwt가 만들기를 거부하므로 손으로 위조합니다.
`testdata/fixed.json` — pyjwt가 고정된 키로 한 번 서명한 토큰 — 은 s390x를 포함한
아키텍처 레인이 시계를 고정하고 실제 서명을 검증할 수 있게 합니다. Linux 테스트 레인,
레이스 감지기, 커버리지 레인은 pyjwt를 설치하고 `OIDC_REQUIRE_JUDGE`를 설정하므로 pyjwt가
없으면 건너뛰지 않고 실패합니다. HMAC 허용, 발급자의 접두사 비교, audience 검사 생략을
각각 일부러 시도했고 각각 테스트를 빨갛게 만듭니다. 커버리지 레인의 하한은 90%입니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/oidc@v0.6.0](https://pkg.go.dev/github.com/go-authn/oidc@v0.6.0)
