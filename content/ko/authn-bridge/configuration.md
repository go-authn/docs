---
title: "구성"
linkTitle: "구성"
weight: 20
description: "authn-bridge의 HCL 구성이 어떻게 배치되는지, check가 무엇을 출력하는지, 그리고 누군가 로그인하기 전에 무엇이 거부되는지."
tags: [authn-bridge, 구성]
---

HCL 파일 하나, 또는 그것들의 디렉터리입니다. `--config /etc/authn-bridge`는 그곳의
모든 `*.hcl`을 이름 순으로 읽어 병합하며, `--config`는 여러 번 지정할 수 있습니다.
구성은 시작할 때 읽고 다시는 읽지 않습니다.

```hcl
issuer            = "https://login.example.org"       # https; compared whole by every relying party
listen            = "127.0.0.1:8080"                  # the default: plain HTTP behind a TLS proxy
signing_key_file  = "/var/lib/authn-bridge/oidc.key"  # authn-bridge keygen --key
subject_salt_file = "/var/lib/authn-bridge/salt"      # authn-bridge keygen --salt; never change it
disabled_file     = "/var/lib/authn-bridge/disabled.json"
certificates_file = "/var/lib/authn-bridge/certificates.json"

saml {
  key_file             = "/var/lib/authn-bridge/saml.key"
  cert_file            = "/var/lib/authn-bridge/saml.crt"
  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"
}

state {
  driver   = "sqlite"                                 # or postgres, mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}

client "my-app" {
  secret_file   = "/etc/authn-bridge/my-app.secret"   # absent: a public client
  redirect_uris = ["https://app.example.org/callback"]
}
```

필수인 것은 `issuer`, `signing_key_file`, `subject_salt_file`, 위의 다섯 키를 가진
`saml` 블록, 그리고 `client` 최소 하나입니다. 나머지는 모두 기본값이 있거나 꺼져
있습니다.

## 재시작 전의 `check` {#check-before-a-restart}

`check`는 서버와 같은 방식으로 구성을 읽고, 지정된 모든 키를 로드하며, **페더레이션의
메타데이터를 가져온** 다음, 무엇이 서비스될지 알려 줍니다.

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-11-02T11:21:58Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*Usable here*는 `saml { idps }`가 나열하지 않는 IdP와
[관리 API]({{< relref "/authn-bridge/admin.md" >}})가 비활성화한 IdP를 제외합니다.
위의 기관을 비활성화하면 같은 명령이 `federation    1 IdPs, 0 usable here`를
출력합니다. 페더레이션이 나열하지 않는 `idps` 항목은 서버가 그것으로 시작하더라도
여기서는 거부됩니다.

```
federation    1 IdPs, 0 usable here, valid until 2026-11-02T11:30:52Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata`는 페더레이션에 등록할 SAML 메타데이터를 출력합니다.
[페더레이션 측]({{< relref "/authn-bridge/federation.md" >}})을 참조하십시오.

## 최상위 {#the-top-level}

| 키 | 기본값 | |
|---|---|---|
| `issuer` | | 공급자의 이름이자 모든 URL의 기반. `https`, 또는 테스트용으로 루프백 호스트의 `http`. 쿼리와 프래그먼트 없음, 끝의 `/`는 제거됨 |
| `listen` | `127.0.0.1:8080` | 공개 리스너 |
| `cert_file`, `key_file` | | 이 파일들로 TLS를 서비스하며, 바뀌면 다시 읽음. 함께 지정하거나 아예 지정하지 않음 |
| `acme` | | 대신 ACME CA의 인증서로 TLS를 서비스(아래). `cert_file`과는 함께 쓸 수 없음 |
| `signing_key_file` | | RSA, ID 토큰에 서명(RS256). P-256 키는 거부됨 |
| `access_token_key_file` | 서명 키 | 액세스 토큰에 ES256으로 서명하는 P-256 키. 서명 키와 같으면 거부됨 |
| `retired_signing_key_files` | | 이전에 서명한 키: 여전히 `/jwks`에 게시되지만 서명에는 사용하지 않음 |
| `subject_salt_file` | | 최소 32바이트 |
| `code_lifetime` | `1m` | 최대 10분 (RFC 6749 4.1.2) |
| `token_lifetime` | `1h` | 액세스 토큰 |
| `id_token_lifetime` | `5m` | ID 토큰 |
| `trusted_proxies` | | `X-Forwarded-For`를 신뢰하는 주소 또는 접두사 |
| `requests_per_minute` | `120` | 한 주소가 1분 동안 시작할 수 있는 로그인, 디바이스 그랜트, ACS 게시. `0`이면 제한 없음 |
| `disabled_file` | | 비활성화된 사람과 기관을 보관하는 곳. 없으면 비활성화가 거부됨 |
| `certificates_file` | | 발급된 모든 인증서와 WireGuard 키. `ssh_ca`, `x509_ca`, `wireguard`와 함께 필수 |

블록:

| 블록 | 페이지 |
|---|---|
| `saml`, `claims` | [페더레이션 측]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | 아래, 그리고 [토큰]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | 아래 |
| `ssh_ca`, `x509_ca` | [인증서]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`, `wireguard` | [토큰]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [폐기]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`, `metrics` | [관리 API]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | 아래 |

## 클라이언트 {#a-client}

| 키 | 기본값 | |
|---|---|---|
| `secret_file` | | 클라이언트 시크릿, 최소 16자. 없으면 **공개** 클라이언트 |
| `redirect_uris` | | 정확히 비교하되, 루프백 URI는 포트가 바뀔 수 있음 (RFC 8252). `http`는 루프백에서만 |
| `audience` | 클라이언트 ID | 액세스 토큰이 수신자로 하는 대상. 여러 개이면 그중 하나를 위한 토큰을 요청할 수 있음 ([RFC 8707]({{< relref "/authn-bridge/resources.md" >}})) |
| `subject` | `public` | 또는 `pairwise`: 이 클라이언트에 대해 다른 `sub` (OIDC Core 8.1) |
| `name` | 클라이언트 ID | 디바이스 확인 페이지에 표시됨 |
| `device` | `false` | 디바이스 그랜트 (RFC 8628). 이런 클라이언트에는 리디렉션 URI가 필요 없음 |
| `refresh_lifetime` | 꺼짐 | 리프레시 토큰, 그리고 **로그인** 후 얼마 뒤에 끝나는지 |
| `pkce` | `required` | 또는 `or_nonce`, 기밀 클라이언트에만: PKCE 대신 `nonce` |
| `id_token_claims` | `false` | 내준 클레임을 ID 토큰에도 복사 (opkssh에 필요) |
| `access_token_groups` | `true` | `false`이면 액세스 토큰에서 그 사람의 그룹을 뺌. ssh에 붙여 넣는 토큰용 ([토큰]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})). `ssh_certificates` 또는 `x509_certificates`와는 함께 쓸 수 없음 |
| `ssh_certificates`, `ssh_*` | | [SSH 인증서]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [NFS 클라이언트 인증서]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | 그 사람의 [애플리케이션 비밀번호]({{< relref "/authn-bridge/tokens.md#application-passwords" >}})를 설정할 수 있음 |
| `wireguard_keys`, `wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`, `ssf_subject_format` | | [Shared Signals 수신기]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

리디렉션 URI가 없는 클라이언트는 디바이스 클라이언트, SSF 수신기 또는 WireGuard
게이트웨이여야 하며, 그렇지 않으면 할 수 있는 일이 없습니다.

## `state`: 재시작해도 잊으면 안 되는 것 {#state-what-a-restart-must-not-forget}

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

리프레시 토큰 계열, 리프레시 토큰과 폐기된 토큰, `/userinfo`와 인증서에서 인정되는
액세스 토큰, 이미 수락된 SAML 어서션과 이미 응답한 로그인, SSF 스트림과 아직 전달되지
않은 이벤트는 하나의 테이블 `bridge_state`(없으면 생성)에 즉시 기록되고 시작할 때
읽습니다. 리프레시 토큰은 그 자체가 아니라 SHA-256으로 보관됩니다. 이 블록이 없으면
메모리에 있고, 재시작하면 모두 로그아웃됩니다.

진행 중인 로그인은 여기에 없습니다. 자체 쿠키에 담겨 이동하며, 주체 솔트에서 파생한
키로 AES-256-GCM으로 봉인되므로 브라우저가 읽거나 바꿀 수 없습니다.

## `acme` {#acme}

```hcl
acme {
  accept_terms_of_service = true                     # the operator's agreement; no default
  cache_dir               = "/var/lib/authn-bridge/acme"
  email                   = "noc@example.org"
  # directory_url         = "..."                    # Let's Encrypt by default
  # eab_key_id            = "..."                    # External Account Binding (GÉANT TCS / HARICA)
  # eab_hmac_key_file     = "/etc/authn-bridge/harica-eab.key"
  # http_listen           = ":80"                    # http-01, and a redirect to https
  # directory_ca_file     = "..."                    # a private ACME CA's own TLS
}
```

인증서는 발급자의 호스트용입니다. `cache_dir`은 개인 키를 담으며, 공급자는 다른
사용자가 접근하거나 가리키는 곳을 바꿀 수 있는 디렉터리에서는 시작하기를 거부합니다.

## 시작할 때 거부되는 것 {#what-is-refused-at-startup}

다음은 각각 그것을 요청한 구성에 대해 `authn-bridge check`가 출력한 것입니다.
서버도 같은 구성을 거부합니다. 각각 구성과 그것이 지정하는 파일에서 읽습니다.
`check`가 더하는 유일한 거부는 페더레이션이 나열하지 않는 `idps` 항목이며,
[위](#check-before-a-restart)에 있습니다. 서버는 수신하기 전에 같은 메타데이터를
가져오지만 `idps`를 거기에 맞추어 확인하지는 않습니다.

**유출되는 발급자, 리디렉션, 시크릿:**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**어느 기관이든 주장할 수 있는 이름:**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**발급되었는데 되돌릴 수 없는 것:**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: more than a week, and a certificate lives that long on every server its revocation has not reached
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**접근할 수 없어야 하는 리스너:**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**같은 것을 두 번 말하는 구성:**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

SSH 프로필 자체의 거부는
[인증서]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}})에,
페더레이션의 거부는
[페더레이션 측]({{< relref "/authn-bridge/federation.md#what-is-refused" >}})에 있습니다.
