---
title: "토큰, 비밀번호, 키"
linkTitle: "토큰"
weight: 40
description: "애플리케이션이 authn-bridge에서 받는 것: ID 토큰과 액세스 토큰, 디바이스 그랜트, SMB와 S3용 애플리케이션 비밀번호, 그리고 WireGuard 키."
tags: [authn-bridge, oidc, 토큰, wireguard]
---

여기의 모든 자격 증명은 사람의 기관에서 하는 같은 로그인으로 시작합니다. 다른 점은
자격 증명이 누구를 위한 것인지, 그리고 어떻게 회수되는지입니다. 인증서는
[별도 페이지]({{< relref "/authn-bridge/certificates.md" >}})에 있습니다.

## 공급자가 게시하는 것 {#what-the-provider-publishes}

```
$ curl -s http://127.0.0.1:28473/.well-known/openid-configuration | jq .
{
  "authorization_endpoint": "http://127.0.0.1:28473/authorize",
  "authorization_response_iss_parameter_supported": true,
  "claims_parameter_supported": false,
  "claims_supported": [
    "sub",
    "iss",
    "aud",
    "exp",
    "iat",
    "auth_time",
    "nonce",
    "acr",
    "name",
    "given_name",
    "family_name",
    "preferred_username",
    "email",
    "groups",
    "eduperson_principal_name",
    "eduperson_scoped_affiliation",
    "eduperson_entitlement",
    "entitlements",
    "eduperson_assurance",
    "eduperson_orcid",
    "schac_home_organization",
    "voperson_id"
  ],
  "code_challenge_methods_supported": [
    "S256"
  ],
  "device_authorization_endpoint": "http://127.0.0.1:28473/device_authorization",
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ],
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "request_parameter_supported": false,
  "request_uri_parameter_supported": false,
  "response_modes_supported": [
    "query"
  ],
  "response_types_supported": [
    "code"
  ],
  "scopes_supported": [
    "openid",
    "profile",
    "email",
    "eduperson",
    "groups"
  ],
  "subject_types_supported": [
    "public",
    "pairwise"
  ],
  "token_endpoint": "http://127.0.0.1:28473/token",
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "none"
  ],
  "userinfo_endpoint": "http://127.0.0.1:28473/userinfo"
}
```

인가 코드 흐름이며, **모든 클라이언트에 PKCE S256이 필수**입니다.
`code_challenge_method`가 없는 요청은 S256으로 읽지 않고 거부됩니다. RFC 7636이
`plain`을 기본값으로 정하기 때문입니다. `pkce = "or_nonce"`로 구성된 기밀 클라이언트는
대신 OpenID `nonce`를 보낼 수 있습니다.

## ID 토큰 {#the-id-token}

클라이언트를 위한 것이며, 사람이 아니라 로그인에 관한 것입니다. RS256, `aud`는
클라이언트 ID, `sub`, `auth_time`, `at_hash`, 요청에 있었다면 `nonce`, IdP가 사용한
인증 컨텍스트를 알려 주었다면 `acr`. 수명은 `id_token_lifetime`이며 기본값은
5분입니다.

**사람에 관한 것은 아무것도 들어 있지 않습니다.** 스코프가 내주는 클레임은
`/userinfo`에 있으며, 이는 액세스 토큰이 발급될 때에 대해 OIDC Core 5.4가 말하는
바와 같고, 액세스 토큰은 항상 발급됩니다. opkssh처럼 ID 토큰 자체가 자격 증명인
클라이언트는 `id_token_claims = true`로 클레임을 복사해 넣게 합니다. ID 토큰은
`openid` 스코프가 있는 요청에 대해서만 발급됩니다.

| 스코프 | 내주는 것 |
|---|---|
| `profile` | `name`, `given_name`, `family_name`, `preferred_username` |
| `email` | `email` (`email_verified`는 절대 아님) |
| `eduperson` | `eduperson_principal_name`, `eduperson_scoped_affiliation`, `eduperson_entitlement`와 `entitlements`, `eduperson_assurance`, `eduperson_orcid`, `schac_home_organization`, `voperson_id` (SAML `subject-id`를 소문자로 한 것) |
| `groups` | `groups` |

## 액세스 토큰 {#the-access-token}

RFC 9068이 설명하는 대로 클라이언트의 `audience`에 있는 리소스 서버를 위한 것입니다.
`signing_key_file`(RS256) 또는 `access_token_key_file`(ES256)로 서명되고,
`typ: at+jwt`이며, `token_lifetime`(기본값 한 시간) 동안 유효합니다. 리소스 서버가
아무에게도 묻지 않고 판단하는 데 필요한 것을 담고 있습니다. `preferred_username`,
`groups`, `idp`(보증한 IdP의 엔티티 ID), `scope`, `client_id`, 그리고 IdP가 세션이
끝나는 때를 알려 주었다면 `session_end`.
그룹은 클라이언트별로 뺄 수 있습니다: [아래](#what-it-leaves-out).

`audience`가 여러 리소스 서버를 지정하는 클라이언트는 RFC 8707의 `resource`로 그중
하나를 수신자로 하는 토큰을 요청할 수 있습니다:
[여러 리소스 서버]({{< relref "/authn-bridge/resources.md" >}})를 참조하십시오.

### 무엇을 빼는가, 그리고 이유 {#what-it-leaves-out}

RFC 9068이 둘 다 허용하지만 **`auth_time`과 `acr`은 없습니다.** 둘은 OIDC Core가
두는 ID 토큰에 남아 있습니다. 액세스 토큰에서 이를 읽는 것은 없습니다. `jti`로
토큰을 찾는 이 공급자도, go-fileshare도 읽지 않습니다. 그런데 액세스 토큰은 SSH
keyboard-interactive 응답으로도 붙여 넣어지며(ssh-oidc의 mccli, motley-cue가
`/userinfo`에서 확인), OpenSSH는 그중 1023자를 읽습니다. IdP의 `acr`
`urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport`만으로도 약
90자입니다. v0.22.0 이전에는 액세스 토큰이 둘 다 담고 있었습니다.

긴 eppn과 AARC 권한 세 개를 가진 ES256 액세스 토큰(`access_token_key_file`)의 길이를,
실제 길이의 발급자를 사용하여 RENATER 메타데이터의 `shibmd:Scope` 길이(스코프
743개)에 대해 authn-bridge의 `TestES256AccessTokens`로 측정한 결과입니다.

| 스코프 길이 | | 문자 수 |
|---|---|---|
| 13 | 중앙값 | 885 |
| 22 | 95번째 백분위수 | 945 |
| 29 | 99번째 백분위수 | 992 |
| 44 | 가장 긴 것 | **1092: 초과** |

v0.22.0 이전에는 같은 토큰이 1014 / 1074 / 1121 / 1221자였습니다. 95번째
백분위수부터 초과였습니다. 여전히 맞지 않는 것은 가장 긴 스코프와, 무엇보다 많은
그룹입니다. 모든 권한이 URN 전체를 추가하고, IdP가 몇 개를 보내는지는 제한이
없습니다. 3072비트 키로 서명한 RS256 액세스 토큰은 그룹이 하나도 없어도 약 1150자이므로,
SSH용 토큰은 ES256으로 서명합니다. 1023자를 넘으면 mccli는 대신 motley-cue에 일회용
비밀번호를 요청하며 motley-cue는 기본적으로 이를 허용합니다. 일반 `ssh`에 붙여 넣는
토큰은 맞아야 합니다.

**요청하는 클라이언트에는 그룹 없음** (v0.23.0). 모든 그룹이 URN 전체를 추가하고
IdP가 몇 개를 보내는지 제한이 없으므로, 어떤 키나 서명 알고리즘으로도 그룹을 담은
토큰이 확실히 맞는다고 할 수 없습니다. `access_token_groups = false`인 클라이언트는
사람의 `groups`가 없는 액세스 토큰을 받습니다.

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
}
```

이는 ssh-oidc를 위한 것입니다. oidc-agent가 토큰을 받고, mccli가 이를
keyboard-interactive 응답으로 붙여 넣고, motley-cue가 `/userinfo`에서 이를 확인하며
그곳에서 그룹을 읽습니다. authn-bridge의 `TestAccessTokenWithoutGroups`로 측정한
결과, 그룹 50개에 속한 사람의 ES256 토큰은 가장 긴 RENATER 스코프(44)와 실제 길이의
발급자로 732자입니다.

테스트 페더레이션에 대해, 그룹 세 개에 속한 사람이 디바이스 그랜트로 그 클라이언트를
통해 로그인합니다.

```
$ authn-bridge token --issuer http://127.0.0.1:28473 --client oidc-agent --scope "openid eduperson groups" --cache var/tokens.json > at
To log in, open http://127.0.0.1:28473/device
and enter the code ZNBP-NMXM
(or open http://127.0.0.1:28473/device?user_code=ZNBP-NMXM)
$ tr -d '\n' < at | wc -c
     625
```

토큰은 사람과 그 IdP를 지명하며 그룹은 없습니다.

```
$ cut -d. -f2 at | tr "_-" "/+" | jq -R "@base64d | fromjson"
{
  "aud": "ssh",
  "client_id": "oidc-agent",
  "exp": 1793017858,
  "iat": 1793014258,
  "idp": "https://idp.univ-example.example/idp/shibboleth",
  "iss": "http://127.0.0.1:28473",
  "jti": "T1qu1-IjIqirgQedQ6hkQCUfeM0OFANOESdXKc3yrJA",
  "preferred_username": "alice@univ-example.example",
  "scope": "openid eduperson groups",
  "sub": "UmCstEtvM1rTavlxDxNPVw-jCNFAZhdRXU405Uz985o"
}
```

`/userinfo`는 여전히 `groups`(스코프 `groups`)와 `eduperson_entitlement`(스코프
`eduperson`)로 그룹을 제공합니다.

```
$ { printf 'Authorization: Bearer '; cat at; } > auth.hdr
$ curl -s -H @auth.hdr http://127.0.0.1:28473/userinfo | jq .
{
  "eduperson_entitlement": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "eduperson_principal_name": "alice@univ-example.example",
  "entitlements": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "groups": [
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example"
  ],
  "sub": "UmCstEtvM1rTavlxDxNPVw-jCNFAZhdRXU405Uz985o",
  "voperson_id": "a1b2c3@univ-example.example"
}
```

**기본값은 `true`로 유지됩니다.** go-fileshare처럼 토큰만으로 판단하는 리소스 서버는
토큰에 그룹이 있어야 합니다. `/userinfo`를 읽는 서버로 토큰이 가는 클라이언트에 한해서만
그룹을 빼십시오.

**인증서와는 거부됩니다.** SSH와 X.509 인증서는 사람의 그룹을 액세스 토큰에서
가져오므로, `access_token_groups = false`와 `ssh_certificates` 또는
`x509_certificates`를 가진 클라이언트는 그룹이 없는 인증서를 발급하게 되고, 그룹으로
권한을 부여하는 서버는 그 이유를 알려 주는 곳이 아무 데도 없이 그 사람을 거부하게
됩니다. `check`는 시작할 때의 서버처럼 이 조합을 거부합니다.

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
  ssh_certificates    = true
}
```

```
$ authn-bridge check --config etc/bridge.hcl
authn-bridge: client "oidc-agent": access_token_groups = false with ssh_certificates or x509_certificates: the certificates take the groups from the access token, and would carry none -- use one client for the certificates and another for tokens pasted into ssh
$ echo $?
1
```

인증서에는 클라이언트 하나를, ssh에 붙여 넣는 토큰에는 다른 클라이언트를 주십시오.

공급자 자체의 스코프(`ssh`, `nfs`, `app_password`, `wireguard`, `wireguard_peers`) 중
하나를 가진 토큰은 **공급자만을** 수신자로 합니다. `aud`가 발급자이며, 해당
엔드포인트는 다른 것을 거부합니다. 리소스 서버가 받은 토큰은 여기서 재생할 수
없습니다.

```
$ curl -s -X POST http://127.0.0.1:28473/ssh/certificate -d x -D - -o -
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Www-Authenticate: Bearer error="invalid_token"
X-Content-Type-Options: nosniff
Date: Mon, 26 Oct 2026 11:36:20 GMT
Content-Length: 23

the token is not valid
```

이미 전달된 액세스 토큰은 리소스 서버가 스스로 확인하는 서명된 진술입니다.
[`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})이 끝내는 것은 그 토큰과
함께 여기로 되돌아오는 모든 것이며, 리소스 서버는
[Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}})로 알게 됩니다.

## 브라우저 없이: 디바이스 그랜트 {#without-a-browser-the-device-grant}

WebDAV 클라이언트, 스크립트, 터미널에는 대학으로 보낼 브라우저가 없습니다.
`device = true`인 클라이언트는 코드를 요청하고(RFC 8628), 사람은 다른 아무 장치에서나
로그인합니다.

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone`은 액세스
토큰을 출력하며, 처음에는 로그인하고 이후에는 갱신합니다. 이는 여기서 작성한 것이
아니라 golang.org/x/oauth2의 디바이스 클라이언트입니다.

| | |
|---|---|
| 사용자 코드 | `BCDFGHJKLMNPQRSTVWXZ`의 문자 여덟 개(모음 없음, 숫자 없음), 10분간 유효. 그 시간 동안 호스트당(IPv4 주소, IPv6 /64) **잘못된** 코드 열 개, 그리고 그 주위의 /24 또는 /48에는 열 배 |
| 폴링 | 5초마다. 더 빨리 폴링하면 `slow_down` |
| 대기 중인 디바이스 | 최대 20,000개. 그 이상이면 모두를 거부하지 않고 가장 오래된 것을 밀어냄 |
| 리프레시 토큰 | 사용할 때마다 교체되며, 끝이 `refresh_lifetime`으로 로그인 시점에 고정된 계열 안에 있음. 폐기된 토큰을 다시 사용하면 계열과 그것으로 얻은 액세스 토큰이 폐기됨 |

## 애플리케이션 비밀번호 {#application-passwords}

NTLMv2와 SigV4는 서버가 이미 가지고 있어야 하는 비밀 값을 증명하므로, SMB나 S3에는
어떤 토큰도 소용이 없습니다. `app_passwords = true`인 클라이언트는 `app_password`
스코프가 있는 토큰으로 비밀번호를 설정할 수 있게 하며, 비밀번호는 생성되어 한 번만
표시됩니다. `authn-bridge app-password --issuer ... --client files`(`--remove`는
삭제).

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

테이블은 없으면 생성됩니다: `login, password, nt_hash, expires, idp`. 프로토콜에
필요한 것만 저장됩니다. SMB를 위한 NT 해시, 그리고 `store`가 요청할 때에 한해서만
비밀번호 자체. go-fileshare는 `users "sql"` 블록으로 이를 읽습니다. 쿼리에서 열
이름을 지정하고, `*`는 절대 쓰지 마십시오.

사람을 비활성화하면 그 사람의 비밀번호가 제거되고, 기관을 비활성화하면 그 기관 사람들의
비밀번호가 제거됩니다. 제거된 비밀번호는 go-fileshare가 다음에 디렉터리를 읽을 때
동작하지 않게 됩니다.

## WireGuard 키 {#wireguard-keys}

WireGuard는 피어를 공개 키로만 인증합니다. 인증서도, 만료도, 폐기도 없습니다. 그래서
공급자가 *이 키는 누구의 것이며, 아직 연결해도 되는가?*라는 질문의 답을 보관합니다.
디바이스의 VPN 클라이언트가 공개 키를 일정 기간(lease) 동안 등록하고, 개인 키는
디바이스를 떠나지 않으며, 게이트웨이는 유효한 키를 그 게이트웨이만을 위해 서명된
목록으로 읽습니다.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"   # keys are recorded beside the certificates

wireguard {
  lifetime = "24h"              # the default: how long a key is listed; registering again renews it
  max_keys = 10                 # the default: devices per person
}

client "vpn" {                  # what people log in with
  device         = true
  wireguard_keys = true
}

client "vpn-gw" {               # the gateway's own client
  secret_file     = "/etc/authn-bridge/vpn-gw.secret"
  wireguard_peers = ["vpn"]     # the clients whose keys it reads
  ssf_receiver    = true        # optional: told at once when somebody is disabled
}
```

| | |
|---|---|
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`, `wireguard` 스코프의 토큰과 함께. lease의 끝을 응답 |
| `DELETE /wireguard/key` | `{"public_key": "..."}`: 소유자가 키를 회수 |
| `GET /wireguard/peers` | 게이트웨이 자신의 `client_credentials` 토큰, 스코프 `wireguard_peers`로: 그 게이트웨이를 수신자로 하는 `wireguard-peers+jwt` 타입의 서명된 JWT, 5분간 유효 |

다른 사람이 가진 키, 회수된 키, 그리고 하나 초과한 키는 `409`로 거부됩니다. 게이트웨이
클라이언트는 기밀 클라이언트여야 하며 `wireguard_keys`가 있는 클라이언트를 지정해야
합니다. 목록의 형식과 게이트웨이 측은 go-authn/wireguard의 것입니다.

## OpenPubkey와 opkssh {#openpubkey-and-opkssh}

opkssh는 CA 없이 ID 토큰을 SSH 로그인으로 바꾸며, 만들어 내는 토큰(PK Token)은 그
안의 ID 토큰보다 오래 지속됩니다. 공급자는 코드 흐름과 디바이스 흐름에서 `nonce`를
그대로 반환하고, RS256으로 서명하며, `retired_signing_key_files`가 지정하는 동안
폐기된 키를 **게시된 채로** 유지하여 교체 이전에 서명된 PK Token이 계속 검증되게
합니다.

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

opkssh에는 `id_token_claims = true`인 자체 클라이언트를 주십시오. opkssh는 PK Token의
클레임으로 사람을 일치시키며, 그 ID 토큰은 로그인하는 모든 서버에 전달됩니다.
