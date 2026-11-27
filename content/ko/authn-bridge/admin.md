---
title: "관리 API, 상태 점검, 메트릭"
linkTitle: "관리 API"
weight: 70
description: "authn-bridge의 gRPC 관리 API로 사람이나 기관을 비활성화하는 방법, 그리고 그 옆의 상태 점검 및 메트릭 엔드포인트."
tags: [authn-bridge, 관리, grpc, 메트릭]
---

둘 다 구성이 요청하지 않으면 꺼져 있으며, 공개 리스너에서는 절대 켜지지 않습니다.

```hcl
admin {
  listen = "unix:///run/authn-bridge/admin.sock"   # mode 0600
  # or over the network, mutual TLS and nothing less (loopback included):
  # listen         = "10.0.0.5:9443"
  # tls_cert_file  = "/etc/authn-bridge/admin.crt"
  # tls_key_file   = "/etc/authn-bridge/admin.key"
  # client_ca_file = "/etc/authn-bridge/operators-ca.crt"
  # reflection     = true                          # for grpcurl; off by default
}

metrics { listen = "127.0.0.1:9101" }              # /healthz /readyz /metrics

disabled_file = "/var/lib/authn-bridge/disabled.json"
```

리스너는 grpc-transports/control의 것이며 go-fileshare와 공유합니다. 소켓은 bind와
chmod 사이에서도 다른 사용자가 접근할 수 없고, 아직 실행 중인 인스턴스에게서
빼앗지도 않습니다. TLS 파일 세 개가 모두 없는 TCP는 루프백을 포함해 거부됩니다.
모든 로컬 사용자가 `127.0.0.1`에 접근할 수 있기 때문입니다.

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

`-tags nogrpc`로 빌드한 바이너리에는 관리 API가 없으며, `admin` 블록이 있는 구성은
그것 없이 시작하지 않고 거부합니다.

## 서비스 {#the-service}

`bridge.admin.v1.AdminService`(`proto/bridge/admin/v1/admin.proto`)와 그 옆의
`grpc.health.v1`이며, 후자는 공급자가 준비된 동안 `SERVING`을 보고합니다.

| | |
|---|---|
| `Status` | 버전, 발급자, 시작 시각, 페더레이션의 메타데이터(IdP, 사용 가능, 유효 기한, 마지막 갱신, 마지막 오류), 메모리에 보유한 것 |
| `RefreshMetadata` | 지금 페더레이션의 메타데이터를 가져오고 결과를 알려 줌 |
| `ListIdPs` | 기관 목록이 보여 주는 대로의 페더레이션 IdP (`query`, `limit`, 기본값 100) |
| `ListClients` | 구성된 신뢰 당사자 |
| `RevokePerson` | 그 사람의 리프레시 토큰 계열, 그것으로 얻은 액세스 토큰, 진행 중인 로그인과 디바이스 그랜트, 애플리케이션 비밀번호를 끝내고, 인증서 저장소가 그 사람에 대해 보유한 모든 것(SSH와 X.509 인증서는 다음 KRL과 CRL로, 그리고 WireGuard 키)을 폐기 |
| `DisablePerson`, `EnablePerson` | 소속 기관이 무엇이라고 하든 로그인과 모든 토큰에서 이 사람을 거부하고, 보유한 것을 폐기함. 선택적으로 `until` 시각까지 |
| `DisableIdP`, `EnableIdP` | 한 기관이 보증하는 모든 사람에 대해 동일하게 함. 메타데이터 갱신으로는 해제되지 않음 |
| `ListDisabled` | 누가 비활성화되었는지, 이유, 누가 했는지, 언제부터 언제까지인지 |

`saml { idps }`에서 IdP를 빼면 `DisableIdP`처럼 그 IdP가 보증하던 것이 끝납니다(v0.23.7부터).
새 로그인은 거부되고, 그 IdP를 거쳐 온 사람의 모든 권한도 다음에 사용될 때
`institution not configured`로 거부됩니다. 리프레시 토큰(재시작을 넘어서도), 애플리케이션 비밀번호,
SSH 인증서 요청이 그 대상입니다. IdP를 다시 넣으면 다시 동작하며, 폐기할 것은 없습니다.

`reflection = true`일 때, 테스트 공급자에 대해:

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.4",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-26T11:22:17.441725Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-02T11:22:16Z",
    "lastRefresh": "2026-10-26T11:22:17.442875Z"
  },
  "counts": {}
}
```

## 비활성화 {#disabling}

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.example",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-26T11:22:17.952680Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-11-27T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-26T11:21:27.038956Z",
    "until": "2026-11-27T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked`는 각 호출이 끝낸 것(리프레시 계열, 액세스 토큰, 로그인, 애플리케이션
비밀번호, 인증서)의 개수이며, 여기서는 살아 있는 것이 없었습니다. 무언가를
바꾸는 모든 호출은 누가 했는지와 함께 기록되며, 소켓에서는 상대방의 `uid=`, TLS에서는
클라이언트 인증서의 `cn=`입니다.

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-11-27T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**사람은 그가 누구인지로 비활성화됩니다.** 사용자 이름은 eppn, uid, mail,
subject-id가 모두 그렇듯 대소문자 구분 없이 비교되므로,
`"Alice@Univ-Example.example"`로 같은 호출을 하면 `alice@univ-example.example`에
대해 설정한 것이 해제됩니다(`{"wasDisabled": true}`). 항목은 그 이름으로 알려진
모든 사람의 안정적인 신원도 기록하므로, IdP가 다른 표기를 보내더라도 그 사람이
다시 들어올 수 없습니다. `@`가 없는 이름은 사용자 이름을 내주지 않는 IdP의 사람을
위해 `sub`로도 일치시킵니다.

항목은 무엇이든 폐기하기 **전에** 기록되므로, 폐기와 경쟁하는 그랜트는 그 항목을
만나게 됩니다.

**이름은 ASCII 문자만 접습니다**(v0.23.8부터). 비활성화 목록, 인증서 프린시펄, subject-id는 사용자 이름을 go-authn/oidc의 `ASCIILower`로 비교하므로 켈빈 기호(U+212A)는 "k"가 아닙니다. `kate`와 켈빈 기호를 쓴 표기는 두 사람이며, 비활성화 항목도 인증서 프린시펄도 둘이 됩니다. 한쪽을 비활성화해도 다른 쪽은 비활성화되지 않습니다.

**비활성화는 `disabled_file`에 보관되며, 없으면 거부됩니다.** 다음 재시작까지만
비활성화된 사람은 다음 배포 때 다시 들어오게 될 것입니다.

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

읽을 수 없는 파일은 같은 이유로 공급자가 시작하지 못하게 합니다. 비활성화된 기관은
`Status`, `ListIdPs`,
[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}})에서
사용 불가로 집계됩니다.

비활성화가 공급자 밖으로 미치는 범위는
[폐기]({{< relref "/authn-bridge/revocation.md" >}})에 있습니다. 인증서는 KRL과
CRL, 토큰은 Shared Signals입니다. 여기서 제거한 애플리케이션 비밀번호는
go-fileshare가 다음에 디렉터리를 읽을 때 동작하지 않게 되며, 즉시 효과가 나게 하려면
`DisablePerson` 뒤에 그 `ReloadDirectory`를 호출하십시오.

{{< callout type="warning" >}}
**`RevokePerson`이 끝낼 수 없는 것**

이미 전달된 액세스 토큰은 리소스 서버가 스스로 확인하는 서명된 진술이며, 그곳에서
만료될 때까지(기본값은 한 시간) 유효합니다. 이미 발급된 SSH 인증서는 서버가 KRL을
읽지 않으면 유효 기간 동안 유지되며, 그래서 둘 다 수명이 짧습니다.
{{< /callout >}}

## 패스키 삭제 알림 {#passkey-removal-notices}

[`mail` 블록]({{< relref "/authn-bridge/configuration.md#mail" >}})이 있으면(v0.32.0부터)
패스키 삭제가 요청되거나 취소될 때 로컬 계정은 자기 주소로 알림을 받으므로, 키 하나를 가진
도둑이 소유자의 삭제를 조용히 취소할 수 없습니다. **로컬 계정에만** 해당하며, 알림은 계정당
`window`(기본 10분)마다 메일 하나입니다. 그 사이에 도착한 이벤트는 요약 하나로 합쳐집니다.
운영자에게 무엇이 보이는지는 이벤트에 따라 다릅니다.

- **알림을 보낼 수 없는 삭제 요청은 보류된 채로 남습니다.** 지연이 끝나도 실행되지 않습니다.
  bridge는 다시 시도하고(5회, 간격이 점점 길어짐) 그다음 `GAVE UP`을 크게 기록합니다.
  재시작하면 재개되며 다음 이벤트도 마찬가지입니다. 그동안 키는 전처럼 계속 동작합니다.
  레코드에는 알림이 전달될 때까지 `notice_pending`이 있습니다.
- **취소는 메일이 실패해도 적용됩니다.** 실패는 기록되며(`mailing <login> failed`) 알림을
  보낼 수 없었다고 알려 주는 계정 페이지에 표시됩니다.
- **쓸 수 있는 주소가 없는 계정**은 막히지 않습니다. `mail` 블록이 없을 때처럼 삭제가
  진행되고, 로그에는 `<login> has no usable mail address ... nobody is told`가 남으며,
  계정 페이지도 그렇게 알려 줍니다.

`mail` 블록이 없으면 아무것도 바뀌지 않습니다.

## 저널과 로컬 계정 {#journal-and-local-accounts}

v0.37.0부터 로그인에 성공할 때마다 저널에 한 줄이 남으며, 어느 줄에도 비밀이
들어 있지 않습니다. 코드, 토큰, 어서션, 메일 주소, 이름, 그룹은 출력되지 않습니다.

```text
login: <username> via <idp entityID> for <client_id> from <address>
login: <login> via <issuer>/local with passkey <8 hex> for <client_id> from <address>
account: <username> confirmed through <idp entityID> from <address>
account: audit: <login> stepup <16 hex> from <address>
token: authorization_code issued to <client_id> for <username>
token: refresh_token issued to <client_id> for <username>
```

처음 두 줄은 인가 엔드포인트에서의 로그인으로, 기관을 통한 것과 로컬 패스키를 쓴
것입니다(`<8 hex>`는 `local: <login> enrolled a passkey (<8 hex>)`가 출력하는
패스키 ID입니다). 다음 두 줄은 계정 페이지 로그인으로, 기관을 통한 것과 패스키를 쓴
것입니다. 마지막 두 줄은 클라이언트에 발급된 토큰입니다.

계정 디렉터리가 `root:authn-bridge` 0750이고 파일이 0640일 때(문서화된 구성)
`authn-bridge local-account …`는 **root**로 실행하십시오. 이 명령은 옆에 임시 파일을
만들어 파일을 교체하므로, `authn-bridge` 사용자로 실행하면
`open /etc/authn-bridge-local/.accounts-NNN: permission denied`로 실패합니다.
파일의 소유자와 모드는 유지됩니다. SSH로 실행할 때는
`ssh host sudo authn-bridge local-account … --name "Two words"`에 따옴표를 한 겹 더
둘러야 합니다(`--name '"Two words"'`). ssh가 인자를 하나의 문자열로 이어 붙이고
원격 셸이 이를 다시 나누기 때문입니다.

## 클라이언트가 받아들이는 계정 {#client-accounts}

v0.38.0부터 `client` 블록은 한 종류의 사람만 받아들이도록 설정할 수 있습니다.

```hcl
client "forgejo" {
  secret_file   = "/etc/authn-bridge/forgejo.secret"
  redirect_uris = ["https://git.example.org/user/oauth2/bridge/callback"]
  accounts      = ["local"]   # "local", "federated", or both (the default)
}
```

`accounts = ["local"]`은 하드웨어 키를 요구하는 서비스를 위한 것으로, SAML
기관 소속 사람은 거부됩니다. 이 규칙은 로그인이 제시되는 곳뿐 아니라 권한이
부여되거나 사용되는 모든 곳에서 지켜집니다. 인가 엔드포인트는 클라이언트가
받아들이는 하나의 경로로만 사람을 보내며(로컬 전용 클라이언트에 대한
`prompt=none`은 `login_required`로 답합니다), 페더레이션 단계, 패스키 단계,
로그인의 끝은 각각 다른 종류의 로그인을 거부합니다. 코드 교환, 갱신, 기기 폴링도
다른 종류의 사람을 거부하므로 제한이 쓰이기 전에 얻은 권한은 제한과 함께
멈춥니다. 응답은 `access_denied`이며, 로그인 중에는 클라이언트의 리디렉션 URI로,
그 뒤에는 토큰 엔드포인트에서 돌려줍니다. `authn-bridge check`는 클라이언트 줄에
제한을 표시하고, `local`에는 `local` 블록이 필요하며,
`bridge_logins_total{result="wrong_account_kind"}`가 거부를 셉니다. 저널에는
이유가 남습니다.

```text
login: <username> via <idp entityID> refused for <client_id>: this client takes local accounts only
token: account kind not accepted by this client: <why> (<username> via <idp> for <client_id>)
```

알려진 한계: 인증서 엔드포인트(SSH, X.509, Kerberos, WireGuard)는 특정
클라이언트에 묶여 있지 않으므로 `accounts`가 적용되지 않습니다.

## 웹에서 초대하는 관리자 {#web-invitations}

v0.39.0부터 관리자는 호스트의 셸 없이 `/account/invite`에서 로컬 계정을 초대할
수 있습니다(로그인 이름, 이메일 주소, 선택 사항인 이름). 초대는 명령줄의 것과
같으며, 링크는 초대받은 사람에게 이메일로만 전달됩니다. 관리자는 `local` 블록에
사용할 수 있는 인증기 모델과 함께 지정합니다.

```hcl
local {
  admins        = ["alice"]
  admin_aaguids = ["9dd8d593-2213-438a-97f8-d6b813d51c27"]
  mds_dir       = "/var/lib/authn-bridge/mds"
  admin_min_certification = "L2"   # 선택 사항
}
```

이 페이지에는 `mail` 블록, 3분 이내의 사용자 검증 어서션, CSRF 토큰이 필요하며,
관리자 한 명당 시간당 10개 계정까지 초대할 수 있습니다. 관리자 패스키의 모델은
보고된 것이 아니라 **증명**되어야 합니다. 등록 시 브라우저에 direct attestation을
요청하고, go-authn/webauthn v0.5.0이 이를 검증하며(`x5c` 체인을 가진 `packed`
구문이고, 그 인증서가 인증기의 AAGUID와 같은 `id-fido-gen-ce-aaguid` 확장을
가져야 함. `self`와 `none`은 검증되지만 모델을 증명하지 않으며, 이 확장이 없는
인증서도 마찬가지), 모델은 go-authn/fido
v0.16.0의 `mds`를 통해 FIDO MDS3 메타데이터와 대조됩니다. 그런 다음에야 bridge가
모델을 기록하며, 페이지는 그 외에는 아무것도 읽지 않습니다. 이후 메타데이터가
폐기 또는 침해로 보고한 모델은 더 이상 페이지를 열지 못합니다. 모델이 증명되지
않은 채 등록된 키로도 로그인은 되지만, 아무것도 열지 못합니다.

**최소 인증 수준.** `admin_min_certification`(선택 사항. `"L1"`, `"L1plus"`,
`"L2"`, `"L2plus"`, `"L3"`, `"L3plus"` 중 하나이며, 다른 값은 설정 오류이고
`admins`가 없으면 거부됩니다)은 관리자 패스키의 모델이 가져야 하는 FIDO 인증
수준의 하한으로, 같은 MDS3 메타데이터에서 읽습니다. 순서는 사양의 것
(MDS 3.1 §3.1.4.1)으로 L1 < L1plus < L2 < L2plus < L3 < L3plus입니다. 수준은
모델의 *현재* 수준, 즉 효력이 있는 가장 최근의 `FIDO_CERTIFIED_Lx` 상태
보고서(§3.1.3)입니다. 그러한 보고서가 없는 모델(예전의 `FIDO_CERTIFIED`는 어느
수준으로도 치지 않습니다)은 어떤 하한도 충족하지 못합니다. 폐기·침해 상태와
마찬가지로 등록할 때**와 페이지를 열 때마다** 확인합니다. 나중에 하한 아래로
강등되거나 폐기된 모델은 로그인은 되지만 관리자 페이지는 더 이상 열지
못합니다. 설정하지 않으면 어떤 수준도 요구하지 않습니다. authn-bridge
v0.41.0(go-authn/fido v0.17.0)부터 사용할 수 있습니다.

메타데이터는 `mds_dir`에 보관됩니다. 선택 사항이며 기본값은
`/var/lib/authn-bridge/mds`이고 절대 경로여야 하며 `admins`가 없으면 거부됩니다.
내려받는 것은 백그라운드 고루틴이며 요청이 아닙니다. 호스트에는 다음이
필요합니다.

- 서비스가 쓸 수 있는 디렉터리(`mds_dir`. 기본값이 아닌 경로는 유닛의
  `ReadWritePaths=`에 있어야 함)
- `mds3.fidoalliance.org`로의 아웃바운드 HTTPS, 그리고 해당 인증서의 CRL 배포
  지점으로의 아웃바운드 일반 HTTP
- 정확한 시계

서비스는 메타데이터 없이 시작해 다시 시도하며, 메타데이터가 들어올 때까지
관리자 키는 증명되지 않고 페이지는 거부합니다.

**관리자의 키를 다시 등록하기.** v0.39.0 이전에 등록된 키에는 검증된 증명이
없습니다. 각 관리자는 기존 키로 로그인하고 `/account`를 열어 키로 확인한 뒤,
허용된 인증기(예: YubiKey Bio)로 패스키를 추가하고 브라우저가 묻는 제조사와
모델 공유를 수락합니다. 응답에 `attested: true`가 표시되어야 하며, 그러면
`/account/invite`가 동작합니다. 그 후 이전 키를 삭제합니다.

## 상태 점검과 메트릭 {#health-and-metrics}

go-net-health/endpoint의 것으로 go-fileshare와 같으며, `metrics` 리스너에 있습니다.
이 리스너는 공개 리스너여서는 안 됩니다(그렇게 만드는 구성은 거부됩니다).

| | |
|---|---|
| `/healthz` | 프로세스가 응답하는 동안 up |
| `/readyz` | 페더레이션의 메타데이터가 로드되어 `validUntil` 이내이고, 상태 데이터베이스에 도달하기를 기다리는 폐기가 없는 동안 ready |
| `/metrics` | Prometheus 텍스트, `bridge_*` 계열 |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.23.4",goversion="go1.27.3",revision="6e0156cb516ace9091d4070c425258febc48f6ee"} 1
bridge_start_time_seconds 1793013737
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793618536
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1793013737
bridge_metadata_refreshes_total{result="failed"} 0
bridge_metadata_refreshes_total{result="ok"} 1
bridge_logins_in_progress 0
bridge_devices_waiting 0
bridge_refresh_families 0
bridge_access_tokens 0
bridge_disabled{kind="idp"} 0
bridge_disabled{kind="person"} 0
bridge_ssh_certificates_total 0
bridge_x509_certificates_total 0
```

결과별 로그인 카운터(`bridge_logins_total`), 그랜트별 토큰 카운터
(`bridge_tokens_issued_total`), 애플리케이션 비밀번호 카운터
(`bridge_app_passwords_total`)는 무언가를 집계한 뒤에야 나타납니다. **어떤 레이블도
사람이나 기관의 이름을 담지 않습니다.** 어느 대학의 사람들이 서비스를 언제
사용하는지는 공급자가 공개할 일이 아닙니다. `bridge_metadata_valid_until_timestamp_seconds`가
알려 주는 시각에 도달하기 전에 경보를 설정하십시오. 그 시각이 지나면 아무도
로그인할 수 없습니다.
