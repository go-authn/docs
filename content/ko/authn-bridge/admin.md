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
