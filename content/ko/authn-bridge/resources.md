---
title: "여러 리소스 서버: 한 번에 하나를 위한 토큰"
linkTitle: "리소스 지표"
weight: 45
description: "authn-bridge의 RFC 8707 리소스 지표: audience가 여러 리소스 서버를 지정하는 클라이언트가 그중 하나를 수신자로 하는 액세스 토큰을 요청합니다."
tags: [authn-bridge, oidc, 토큰, rfc8707]
---

`audience`가 여러 리소스 서버를 지정하는 클라이언트, 예를 들어 여러 파일 서버 앞의
포털은 그 **모두**를 수신자로 하는 액세스 토큰을 받습니다. 그러면 그 서버 중
어느 하나가 받은 토큰을 다른 서버들에 제시할 수 있습니다. RFC 8707 §3은 이것이
audience를 제한해야 하는 이유라고 말합니다. v0.21.0부터 클라이언트는 RFC 8707의
`resource` 파라미터로 그중 **하나**를 수신자로 하는 토큰을 요청할 수 있습니다.
이 페이지는 v0.23.3을 설명하며, v0.22.0이 달랐던 점은 [끝](#departures)에 있습니다.

`resource`가 없으면 아무것도 바뀌지 않습니다. 액세스 토큰은
[토큰 페이지]({{< relref "/authn-bridge/tokens.md#the-access-token" >}})가 설명하는 대로
클라이언트의 전체 `audience`를 대상으로 합니다.

## 클라이언트 {#the-client}

켤 것은 없습니다. 클라이언트의 `audience`에 있는 모든 URI를 요청할 수 있습니다.
아래 예제는 리프레시 토큰이 있는 기밀 클라이언트와 같은 audience를 가진 디바이스
클라이언트를 사용합니다.

```hcl
client "portal" {
  secret_file      = "etc/portal.secret"
  redirect_uris    = ["http://127.0.0.1:9/portal"]
  audience         = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
  refresh_lifetime = "8h"
}

client "files-cli" {
  device   = true
  audience = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
}
```

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-18T15:48:27Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
client        files-cli (public, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
```

`check`는 audience를 나열할 뿐 그 이상은 말하지 않습니다. 특히 어떤 항목을 요청할 수
있는지는 알려 주지 않습니다. **프래그먼트가 없는 절대 URI**만 요청할 수 있습니다.
`fileshare` 같은 논리 이름이나 `#`이 있는 URI는 `audience`에서 받아들여지고 리소스를
지정하지 않으면 여전히 토큰에 들어가지만, 그것을 지정하는 `resource`는 거부됩니다.

## 한 서버를 위한 토큰 {#a-token-for-one-server}

사람은 평소처럼 로그인합니다(여기서는 테스트 페더레이션에 대해, 인가 요청이 리소스를
지정하지 않은 채로). 그런 다음 클라이언트가 코드를 교환할 때 서버 하나를 지정합니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

`aud`는 보낸 그대로의 요청한 값이며 그 밖의 것은 없습니다.
[go-authn/oidc]({{< relref "/libraries/oidc.md" >}})처럼 audience를 확인하는 서버는
이 토큰을 파리에서는 받아들이고 리옹에서는 거부합니다.

## 다음 갱신 때의 다른 서버 {#another-server-at-the-next-refresh}

리프레시 토큰은 그랜트 전체를 유지하므로(RFC 8707 §2.2), 다음 갱신 때 다른 서버를
요청할 수 있습니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

`scope`는 두 서버에 같습니다. 공급자는 리소스별로 이를 줄이지 않습니다.

## 클라이언트가 가질 수 없는 서버 {#a-server-the-client-may-not-have}

클라이언트의 `audience`에 없는 리소스는 `invalid_target`으로 거부됩니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-nantes.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-nantes.example.org/\" is not one this client may ask a token for"
}
400
```

**거부된 갱신은 리프레시 토큰을 소모하지 않습니다.** 요청은 토큰이 소모되기 전에
검사되므로 같은 리프레시 토큰이 여전히 동작합니다. 리소스를 지정하지 않고 요청하면
클라이언트의 전체 audience를 위한 토큰을 줍니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
```

값은 URI로 정규화되지 않고 문자열로서 `audience` 항목과 비교됩니다. 끝의 `/`가 없는
같은 서버는 다른 리소스입니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org \
    -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-paris.example.org\" is not one this client may ask a token for"
}
400
```

## 인가 요청에서 그랜트의 범위 제한하기 {#bounding-the-grant-at-the-authorization-request}

`resource`는 인가 요청과 함께 보낼 수도 있습니다. 그러면 그랜트의 범위가 제한됩니다.
코드와 그 뒤의 리프레시 토큰은 그 서버를 위한 것이며, 이후의 토큰 요청은 그것을 다시
지정할 수는 있어도 다른 서버를 지정할 수는 없습니다. 인가 요청에
`resource=https://fs-paris.example.org/`가 담긴 로그인 후:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-lyon.example.org/\" was not part of the authorization"
}
400
```

인가 요청은 **여러 개의** `resource` 값을 담을 수 있습니다. 거기서 반복할 수 있는
유일한 파라미터입니다. 각각이 검사되고, 두 번 주어진 값은 한 번으로 집계되며,
그랜트는 지정된 서버들을 위한 것입니다. 인가 요청에
`resource=https://fs-paris.example.org/`와 `resource=https://fs-lyon.example.org/`가
담긴 로그인 후에는 코드가 둘 모두를 위한 토큰을 주고, 각 갱신은 둘 중 어느 쪽이든
요청할 수 있습니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

`state` 블록이 있으면 그랜트의 리소스가 리프레시 토큰과 함께 저장되므로, 재시작해도
그랜트가 넓어지지 않습니다.

클라이언트가 가질 수 없는 리소스는 인가 엔드포인트에서도 클라이언트의 리디렉션 URI로
되돌려 보내는 오류로 거부됩니다. 올바른 값들 사이에 그런 값이 하나만 있어도 요청
전체가 거부됩니다.

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**토큰 엔드포인트에서는 요청당 리소스 하나.** 토큰은 한 서버를 위한 것이거나,
그랜트의 서버들을 위한 것이거나, 전체 `audience`를 위한 것이며, 토큰 요청이 선택한
목록을 위한 것은 절대 아닙니다. 거기서 두 번째 `resource`는 다른 반복된 파라미터처럼
거부됩니다.

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_request",
  "error_description": "resource appears more than once"
}
400
```

## 규칙 {#the-rules}

| | |
|---|---|
| **어디서** | `resource`는 인가 엔드포인트에서, 그리고 토큰 엔드포인트에서 `authorization_code`와 `refresh_token` 그랜트와 함께 받습니다 |
| **몇 개** | 인가 엔드포인트에서는 여러 개: 각각이 검사되며 거부되는 것이 하나라도 있으면 요청이 거부됩니다. 토큰 엔드포인트에서는 하나: 두 번째는 `invalid_request`입니다 |
| **무엇을 지정할 수 있는가** | 프래그먼트가 없고, 한 글자도 다르지 않게 클라이언트 `audience`의 항목인 절대 URI |
| **토큰의 `aud`** | 토큰 엔드포인트에서 지정한 리소스. 없으면 인가 요청이 지정한 리소스를 주어진 순서대로. 둘 다 없으면 클라이언트의 전체 `audience` |
| **갱신** | 인가 요청이 지정한 리소스 중 하나를, 지정한 것이 없으면 클라이언트 `audience`의 아무 URI나 지정할 수 있습니다. 새 리프레시 토큰은 그랜트 전체를 유지합니다 |
| **거부** | `invalid_target`: 인가 엔드포인트에서는 리디렉션 URI로 되돌려 보내고, 토큰 엔드포인트에서는 `400` 오류로 반환합니다. 거부된 갱신은 리프레시 토큰을 소모하지 않습니다 |
| **다른 그랜트** | `client_credentials`와 함께, 디바이스 인가 요청에서, 또는 디바이스 토큰을 폴링할 때의 `resource`는 무시되지 않고 `invalid_target`으로 거부됩니다. 한 서버를 위한 토큰을 요청한 클라이언트가 다른 서버를 위한 토큰을 받아서는 안 됩니다. 디바이스 토큰은 항상 전체 `audience`를 위한 것입니다 |
| **공급자 자체의 스코프** | `ssh`, `nfs`, `app_password`, `wireguard`, `wireguard_peers`가 있는 토큰은 공급자만을 위한 것이며, 발급자 자신만 지정할 수 있습니다 |

토큰 엔드포인트와 디바이스 인가 요청에서의 다른 그랜트의 거부:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=client_credentials \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

```
$ curl -s http://127.0.0.1:28473/device_authorization -d client_id=files-cli \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

## RFC 8707과 다른 점 {#departures}

| RFC 8707 | authn-bridge v0.23.3 |
|---|---|
| §2: "Multiple `resource` parameters MAY be used" | 인가 엔드포인트에서는 쓰인 대로. 토큰 엔드포인트에서는 하나: 두 번째 `resource`는 `invalid_request`이며, §3이 이를 허용합니다("an authorization server may be unwilling or unable to fulfill a token request with multiple resources") |
| §2.2: 파라미터는 "for all grant types"에 적용됨 | `authorization_code`와 `refresh_token`에만. `client_credentials`나 디바이스 그랜트에서는 디바이스 인가 요청에서도 폴링할 때도 `invalid_target`으로 거부됩니다 |
| §2: 값은 "SHOULD NOT include a query component" | 검사하지 않음. 검사하는 것은 값이 절대 URI이고, 프래그먼트가 없고, 클라이언트의 `audience`에 있다는 것 |
| §2: 서버는 "may map from that value to a more general URI or abstract identifier" | 매핑 없음: `aud`는 요청한 값이며, `audience`와 문자열로 비교됨 |
| §2.2: "the authorization server should downscope the scope value" (리소스별로) | 하지 않음: `scope`는 어느 서버를 지정하든 그랜트의 것 |
| §2.1: `resource`가 없는 요청은 "by using a predefined default resource value"로 처리될 수 있음 | 기본값은 클라이언트의 전체 `audience` |
| §2.2: 갱신은 "to those [resources] that were originally granted"로 제한될 수 있고, 리프레시 토큰은 "is bound to the full original grant" | 쓰인 대로 |

**v0.22.1 이전에는** v0.22.0이 인가 엔드포인트에서 반복된 `resource`를 다른 모든 반복된
파라미터처럼 오류 페이지로 거부했으므로, 그랜트가 두 서버를 지정할 수 없었습니다.
또한 디바이스 인가 요청은 `resource`를 읽지 않았으므로, 한 서버를 요청한 디바이스가
전체 `audience`를 위한 토큰을 받았습니다.
