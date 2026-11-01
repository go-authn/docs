---
title: "상태"
weight: 60
description: "이 문서가 설명하는 릴리스, 각 릴리스에서 추가된 것, 그리고 아직 구현되지 않은 것."
tags: [상태, 릴리스]
---

이 문서는 문서 버전 **0.7**이며 다음을 설명합니다.

| 프로그램 | 릴리스 | 모듈 |
|---|---|---|
| authnd | **v0.15.0** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.6** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.7** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

라이브러리의 버전은 [해당 페이지]({{< relref "/libraries/_index.md" >}})에
있습니다. ldap은 DIT 콘텐츠 규칙, 이름 형식, DIT 구조 규칙의 읽기, 적용, 게시와
빌드되지 않는 스키마를 위한 타입이 있는 `BuildError`, HCL2
스키마, `ldapschema` 변환기를 갖춘 **v0.12.0**이고,
directory는 선언된 오브젝트 클래스를 갖춘 **v0.17.0**입니다. authnd
v0.15.0은 ldap v0.12.0과 directory v0.17.0을 내장합니다.
위 프로그램 중 어느 것이든 새 마이너 버전이 나오면 새 문서 버전이 됩니다. 따라서
독자가 `/docs/0.7/`에서 찾는 페이지는 설치한 것을 계속 설명하며, 이전 릴리스의
페이지는 `/docs/0.1/`, `/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/`, `/docs/0.5/`, `/docs/0.6/`에 남아 있습니다.

{{< callout type="warning" >}}
**authnd를 v0.14.x에서 업그레이드: 기본값 두 개가 바뀝니다**

`max_connections`는 `4096`(이전에는 무제한), `operation_timeout`은 `30s`(이전에는 없음)입니다. 상위 디렉터리가
내려가 있으면 `unavailable`(52)로 응답하며 더 이상 `invalidCredentials`(49)가 아닙니다.
`max_connections = 0`과 `operation_timeout = "0"`은 이전 동작을 줍니다.
[제한과 기한]({{< relref "/authnd/operations.md#limits" >}})을 참조하십시오.
{{< /callout >}}

{{< callout type="warning" >}}
**보안: v0.11.1이 아니라 authnd v0.12.0을 사용하십시오**

authnd는 인증서를 검증하며(`x509.Certificate.Verify`, `govulncheck`에 따르면
`main`에서 도달 가능), Go 1.27.2의 crypto/x509는 GO-2026-6809가 지목하는 침해된
중간 인증서들을 신뢰 해제하지 않았습니다. **v0.11.1의 릴리스 바이너리는 Go
1.27.2로 빌드되었으며 영향을 받습니다.** v0.12.0은 Go 1.27.3으로 빌드되었고 `go`
지시문이 1.27.3이므로, `go install`이 수정된 툴체인으로 알아서 전환합니다. Go
1.27.3에서의 `govulncheck`는 취약점이 없다고 보고합니다. 릴리스 바이너리는
`go version -m`에서 `go1.27.3`을 보고합니다.
[업그레이드 안내]({{< relref "/authnd/_index.md" >}})를 참조하십시오.
{{< /callout >}}

{{< callout type="warning" >}}
**보안: authn-bridge v0.23.3과 authn-revokd v0.6.5를 사용하세요**

Go 1.27.2에서 `govulncheck`는 두 프로그램 모두에서 GO-2026-6809를 보고합니다. `crypto/x509`의 `Certificate.Verify`가 알려진 침해된 중간 인증서를 거부하지 않았습니다. Go 1.26.10과 1.27.3에서 수정되었습니다. **더 오래된 Go로 빌드한 릴리스 바이너리는 영향을 받습니다.** v0.23.3과 v0.6.5는 Go 1.27.3으로 빌드되고 `go` 지시어도 1.27.3이므로, `go install`이 스스로 수정된 툴체인으로 전환합니다. 두 릴리스 바이너리는 `go version -m`에서 `go1.27.3`을 보고합니다. sshcert는 영향을 받지 않으며 새 릴리스가 없습니다.
{{< /callout >}}

## 각 릴리스에서 추가된 것 {#what-each-release-added}

각 줄은 해당 릴리스를 만든 이유가 된 변경입니다. 의존성만 갱신한 릴리스는, 이
문서 버전이 설명하는 것을 제외하고 생략했습니다.

### authnd {#authnd}

| | |
|---|---|
| v0.1.0 | 다른 곳(파일, SQL 데이터베이스, 다른 디렉터리)에 있는 사람들을 위한 LDAP 서버 |
| v0.2.0 | 필드가 하나뿐인 프로토콜 위의 두 번째 인증 요소 |
| v0.5.0 | 정확히 하나의 신원만 건드리는 비밀번호 변경, 경쟁 상태 없는 다시 불러오기, KDC가 변경을 인식함 |
| v0.6.0 | oidc, directory, ldap, totp, mfa의 보안 수정 |
| v0.7.0 | 비밀번호를 변경하려면 이전 비밀번호가 필요함, 비밀 값을 고정 길이 다이제스트로 비교함 |
| v0.8.2 | 코드는 올바른 비밀번호 뒤에서만 인정됨, 리더는 구성된 DN으로 키가 지정됨 |
| v0.9.0 | `stable`이 아니라 고정된 Go 1.27.1로 빌드하고 테스트함 |
| v0.9.2 | 모든 태그에 릴리스 바이너리, `SHA256SUMS`, 빌드 출처 증명 |
| v0.9.3 | 체크아웃 밖에서 빌드한 바이너리, 각각이 태그를 정확히 보고해야 함 |
| v0.9.4 | `SIGHUP`이 더 이상 authnd를 종료하지 않음: 기록만 하고 아무것도 다시 불러오지 않음 |
| v0.9.5 | 릴리스가 바이너리 하나가 아니라 **모든** 바이너리의 빌드 정보를 확인함 |
| v0.9.6 | `check`가 각 사람에게 티켓을 발급할 수 없는 이유를 알려 줌 |
| v0.10.0 | `check`가 서버처럼 인증서와 keytab을 열어 봄, 비밀번호로 바인드할 수 없는 사람과 토큰으로 여전히 허용되는 사람을 알려 줌, 수신 대기 줄이 렐름을 연 뒤에 나옴 |
| v0.10.1 | go-authn/kdc v0.4.2: `till`이 19700101000000Z이면 1970년에 만료된 티켓이 아니라 가장 긴 티켓을 받음 |
| v0.10.2 | go-authn/directory v0.12.0: 빈 그룹은 `memberUid` 없는 `posixGroup`으로 게시됨 |
| v0.11.0 | [표준 스키마 엔트리]({{< relref "/authnd/entries.md" >}}), 각각 `cn=Subschema`에서 제공하는 스키마에 맞춰짐, `attributes`, `users_attributes`, `groups_attributes`, `(uidNumber>=1000)`이 정수로 비교함. ⛔ `publish_nt_hash`에는 [`samba` 블록]({{< relref "/authnd/tls.md#the-samba-block" >}})이 필요하며, `posixAccount`나 `posixGroup`으로 필터링하는 소비자는 더 적은 엔트리를 봄 |
| v0.11.1 | 시작 줄이 실제로 사람들을 제공하는 소스만 지정함: `user` 블록이 없으면 더 이상 구성 파일을 지정하지 않음 |
| v0.12.0 | [사이트 스키마]({{< relref "/authnd/schemas.md" >}}): `schema_files`(OpenLDAP `.schema`와 cn=config LDIF를 게시된 그대로, 재정의는 slapd처럼 동일하더라도 거부됨)와 `schema { }` 블록, 소스별로 `object_classes`로 선언하는 보조 클래스(시작 시 검증되고 상위 클래스와 함께 게시됨), `check`가 파일, 선언, MUST가 없어 사람에게서 빠진 클래스, 두 소스가 일치하지 않는 그룹을 보고함. ⛔ Go 1.27.3으로 빌드됨: v0.11.1의 바이너리(Go 1.27.2)는 GO-2026-6809의 영향을 받음 |
| v0.12.1 | 빌드되지 않는 스키마 파일이나 블록은 go-authn/ldap v0.10.0의 `BuildError`가 담고 있는 위치에서 열 번호와 함께 거부됨(`site.schema:6:`이 `site.schema:6:1:`이 됨). 메시지는 거부의 종류로 끝나며, 중복은 첫 번째 정의의 위치를 알려 줌 |
| v0.12.2 | 릴리스 바이너리를 `-s -w` 대신 `-ldflags="-w"`로 링크함. 심볼 테이블이 남으므로 `govulncheck -mode binary`가 링크되지 않은 코드의 취약점을 보고하는 대신 정확해짐. 약 9 % 커짐(darwin/arm64에서 18.8 MB에서 20.5 MB) |
| v0.12.3 | go-authn/ldap v0.10.1: `schema_files`를 선형 시간에 읽음. ⛔ v0.12.2까지는 짧은 이어짐 줄로 된 큰 스키마 파일(4 MiB: 약 3분)이 시작을 멈추게 했음: 통제할 수 없는 파일에 의한 서비스 거부 |
| v0.12.4 | go-authn/ldap v0.10.2: `cn=Subschema` 의 RFC 2307 정의 13개(`uidNumber`, `gidNumber`, `ipHostNumber`, `ipNetworkNumber`, `ipNetmaskNumber`, `macAddress` 와 클래스 `ipService`, `ipProtocol`, `oncRpc`, `ipHost`, `ipNetwork`, `ieee802Device`, `bootableDevice`)의 DESC 값에 더 이상 RFC 쪽 나눔의 들여쓰기가 들어 있지 않습니다. `... in an         administrative domain'` 이 아니라 `DESC 'An integer uniquely identifying a user in an administrative domain'` 입니다 |
| v0.13.0 | [DIT 콘텐츠 규칙, 이름 형식, DIT 구조 규칙]({{< relref "/authnd/schemas.md#rules" >}})(go-authn/ldap v0.11.0): `schema_files`와 `schema { }` 블록이 세 종류를 받아들이고 authnd가 이를 적용합니다. 콘텐츠 규칙은 각 엔트리의 형태를 정합니다. `AUX`에 나열되지 않은 보조 클래스는 (그 클래스만 허용하던 속성과 함께) 빠지고, `NOT` 속성은 제거되며, `MUST`가 빠진 엔트리는 게시에서 제외됩니다. 각각 로그에 남고 `check`가 보고합니다. 활성 구조 규칙이 있으면 트리(접미사, `ou=people`, `ou=groups`, `uid` 또는 `cn` RDN)를 시작 시와 `check`에서 검사하며, 위반은 **시작을 거부**합니다. 거부 사유는 한꺼번에 모두 보고되고 비밀 값은 절대 출력되지 않습니다. 어떤 규칙도 자리를 주지 않는 엔트리는 제외됩니다. ⛔ UTF-8이 아닌 `schema { }` 문자열은 이제 거부됩니다. 10,000명을 게시할 때 엔트리당 할당은 규칙이 있으면 416회, 없으면 265회입니다(시간은 부하 상태에서 측정되어 신뢰할 수 없음) |
| v0.13.1 | 성능만 개선, go-authn/ldap v0.11.1 내장: 10,000명을 게시할 때(`BenchmarkPublish10k`, `-cpu 1`) 엔트리당 할당은 규칙이 있으면 364회, 없으면 239회이며(v0.13.0은 416회와 265회), 한 번 실행에 규칙이 있으면 102.5 MiB를 씁니다(v0.13.0은 147.5 MiB). 시간은 부하 10~16에서 측정되어 신뢰할 수 없음 |
| v0.13.2 | 성능만 개선, go-authn/ldap v0.11.2 내장: 속성 열 개짜리 엔트리에서 `Validate`의 할당이 76회에서 12회로 줄었습니다. 10,000명을 게시할 때(`BenchmarkPublish10k`, `-cpu 1`) 엔트리당 할당은 규칙이 있으면 128회, 없으면 85회이며(v0.13.1은 364회와 239회), 한 번 실행에 규칙이 있으면 54.8 MiB를 씁니다(v0.13.1은 102.5 MiB). 시간(부하 8~11): 규칙이 있을 때 약 158 ms에서 약 90 ms |
| v0.13.3 | 성능만 개선, go-authn/ldap v0.11.3 내장: `unmet`가 방금 검증한 엔트리는 바뀌지 않았다면 `validated`가 다시 검증하지 않습니다. 10,000명을 게시할 때(`BenchmarkPublish10k`, `-cpu 1`) 엔트리당 할당은 규칙이 있으면 97회, 없으면 69회입니다(v0.13.2는 128회와 85회, -24 %와 -19 %). 시간은 규칙이 있을 때 약 66 ms, 없을 때 약 36 ms(부하 4.8) |
| v0.13.4 | 카오스 점검. 그룹은 사람과 마찬가지로 시작할 때 한 번만 읽습니다. SQLite에서 500명과 50명씩 200개 그룹에 대한 검색은 4.13초가 걸렸고(검색할 때마다 그룹을 다시 조회했습니다) 이제 1.2밀리초가 걸리며, 검색 중 실패한 그룹 쿼리가 Success라고 답하는 응답에서 그룹을 조용히 빼는 일도 없어졌습니다. 시작할 때 읽을 수 없는 소스(실행되지 않는 그룹 쿼리, 여러 데이터베이스 중 하나의 중단)는 시작과 `check`를 거부합니다. 약 3 MiB를 넘는 항목(10 MB짜리 속성 값 하나)은 게시되지 않습니다. 게시 내용은 사람 집합마다 한 번만 만듭니다. 테스트로 확인: 모든 바이트 위치에서 자른 스키마 파일, 삭제되거나 손상된 데이터베이스, 악의적인 행, 유휴 연결, 과도한 BER 길이, 20,000단계 중첩 필터 |
| v0.14.0 | 변경: v0.13.4는 그룹을 바꾸면 재시작이 필요해서, 데이터베이스에서 뺀 구성원이 누군가 authnd를 재시작할 때까지 접근 권한을 유지했습니다. v0.14.0은 제때의 권한 회수를 되살립니다. `refresh`(기본 60초, `0`이면 끔)가 사람과 그룹의 모든 소스를 서비스 경로 밖에서 만든 새 스냅숏으로 다시 읽고 통째로 교체합니다. 실패한 새로 고침은 마지막 정상 스냅숏을 유지하며, 실패가 이어지는 동안 소스 이름과 함께 한 번만 로그에 남습니다. `max_age`(기본값은 설정 안 함)를 지정하면 제공 중인 데이터가 그보다 오래된 시점부터 검색, 사람의 bind, 비밀번호 변경이 `unavailable`로 응답합니다. authnd를 통해 쓴 비밀번호도 같은 교체를 거칩니다. 측정: SQLite에서 500명과 50명씩 200개 그룹의 새로 고침은 코어 하나로 약 2초, 검색은 0.5밀리초 (새로 고침 비용은 v0.14.1에서 해결) |
| v0.14.1 | 성능만 개선. 새로 고침 비용이 더 이상 그룹 수 × 구성원 행 수에 따라 늘지 않습니다. directory v0.16.0이 각 소스를 한 번에 일괄로 읽습니다. SQLite에서 500명과 50명씩 200개 그룹의 새로 고침은 1.87초에서 0.155초로, 10,000명과 2,000개 그룹의 새로 고침은 391초(새로 고침 주기의 여섯 배 반)에서 1.6초(60초 주기의 2.7 %)로 줄었습니다. 할당 횟수는 39,959,235에서 3,095,482로, 6,373,736,235에서 31,198,460으로 줄었습니다. 시간은 부하 17~67에서 잰 참고값이고, 할당 횟수는 정확합니다 |
| v0.15.0 | 가용성과 보안. go-authn/ldap v0.12.0과 go-authn/directory v0.17.0 사용. ⛔ **기본값 두 개가 바뀝니다**: `max_connections`는 `4096`(이전에는 무제한), `operation_timeout`은 `30s`(이전에는 없음). 새 선택 항목: `max_connections_per_ip`와 `startup_timeout`(`60s`). [`check`는 제한을 출력합니다]({{< relref "/authnd/operations.md#limits" >}}). 상한을 넘은 연결은 `busy`를 받고 닫히며, 기한을 넘긴 작업은 핸들러가 막혀 있어도 `timeLimitExceeded`로 응답받습니다. 바인드 중 업스트림 장애(단순 바인드, 비밀번호 변경, `mfa`의 비밀번호 요소)는 `unavailable`(52)이며 `invalidCredentials`(49)가 아닙니다. 틀린 비밀번호는 여전히 49입니다. 느린 소스에 대한 시작은 `startup_timeout` 뒤에 실패하고 단계와 소스를 밝힙니다. [TLS 인증서를 다시 읽습니다]({{< relref "/authnd/tls.md#renewal" >}})(`cert_file`이나 `key_file`이 바뀔 때. 5초 뒤 첫 핸드셰이크와 `SIGHUP`). 로드되지 않는 쌍은 제공 중인 인증서를 유지하고 한 번만 기록됩니다. 할당 횟수는 아래 라이브러리에 있습니다. 실제 시간은 측정하지 않음(시작 시 부하 21) |

### authn-bridge {#authn-bridge}

| | |
|---|---|
| v0.1.0 | SAML 페더레이션 앞에 놓인 OpenID Connect 공급자 |
| v0.2.0 | 디바이스 그랜트, SSH 인증서, 애플리케이션 비밀번호, OpenPubkey |
| v0.3.0 | 관리 API(`bridge.admin.v1`)와 `/healthz`, `/readyz`, `/metrics` |
| v0.4.0 | ES256 액세스 토큰 |
| v0.5.0 | go-fileshare와 공유하는 go-authn/servercert를 통한 TLS |
| v0.6.0 | 폐기할 수 있는 인증서: SSH KRL, 그리고 CRL이 있는 NFS용 X.509 |
| v0.7.0 | 재시작 후에도 유지되는 상태: 리프레시 토큰과 인정된 액세스 토큰 |
| v0.8.0 | Shared Signals 송신기: CAEP `session-revoked` |
| v0.9.0 | v0.8.1에 대한 적대적 검토의 수정 사항 |
| v0.10.0 | 어디서든 확인할 수 있는 폐기 목록: 서명된 KRL, 만료, 내용의 ETag |
| v0.10.2 | 발급마다 CRL 번호 부여, 직전 발급보다 이른 날짜의 발급은 절대 없음 |
| v0.11.0 | 그룹이 신원 공급자에 묶임, 신원 단위 비활성화, 브리지 전용 audience |
| v0.12.0 | 진행 중인 로그인이 메모리가 아니라 봉인된 쿠키에 있음 |
| v0.13.0 | 기밀 클라이언트가 nonce로 코드를 보호할 수 있음(RFC 9700 2.1.1) |
| v0.16.0 | `max_age`는 마지막 인증이 너무 오래된 경우에만 새 인증을 요청함 |
| v0.16.3 | 두 번째 검토: 모든 표기가 폐기됨, `sub` 단위 비활성화, 재시작 간 재생 없음 |
| v0.17.0 | 사람들이 등록하고 게이트웨이용으로 나열되는 WireGuard 키 |
| v0.18.0 | 사람의 클레임이 없는 ID 토큰, go-authn/saml v0.4.0 |
| v0.19.0 | EuroHPC SSH CA 프로필, 클라이언트별 선택 적용 |
| v0.19.3 | 모든 태그에 릴리스 바이너리, `SHA256SUMS`, 빌드 출처 증명 |
| v0.20.0 | 명령은 `authn-bridge`, 강화된 systemd 유닛과 설치 가이드 |
| v0.20.1 | 더 이상 사실이 아니던 주석과 거부 메시지, README에 `RevokePerson`이 폐기하는 모든 것을 나열함 |
| v0.21.0 | [RFC 8707 리소스 지표]({{< relref "/authn-bridge/resources.md" >}}): `audience`가 여러 리소스 서버를 지정하는 클라이언트가 그중 하나를 수신자로 하는 토큰을 요청할 수 있음. v0.20.1보다 한 시간 먼저 태그되었으며 v0.20.1에도 포함되어 있지만 v0.20.1의 수정 사항은 없음 |
| v0.21.1 | HTTP/2 권고 사항에 따른 golang.org/x/net v0.60.0과 Go 1.27.2, v0.20.1의 수정 사항 재적용, 자리 표시자 도메인을 RFC 2606 이름으로 변경 |
| v0.22.0 | 액세스 토큰이 더 이상 `auth_time`이나 `acr`을 담지 않음(ID 토큰은 여전히 담음). 그래서 ES256 토큰이 RENATER 스코프의 99번째 백분위수까지 OpenSSH의 1023자에 들어맞음 |
| v0.22.1 | 여러 서버로 제한된 그랜트를 위해 인가 엔드포인트에서 `resource`를 반복할 수 있음, `device_authorization`에서는 무시하지 않고 거부함([리소스 지표]({{< relref "/authn-bridge/resources.md" >}})) |
| v0.23.0 | `access_token_groups = false`: 토큰을 ssh에 붙여 넣는 클라이언트는 그룹을 담지 않음([토큰]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})) |
| v0.23.1 | 의존성만: go-jose/v4 v4.1.6, golang.org/x/crypto v0.58.0, golang.org/x/net v0.61.0, go-authn/directory v0.12.0, revocation v0.6.3, saml v0.4.1, servercert v0.5.1, sshcert v0.1.6 |
| v0.23.2 | 보안: go-authn/oidc v0.4.2는 int64 범위를 벗어난 `nbf`(아직 유효하지 않은 토큰이 받아들여졌음)와 `e = 0`인 RSA 키(파싱되었음)를 거부합니다. go-authn/wireguard v0.1.2 |
| v0.23.3 | Go 1.27.3으로 빌드, GO-2026-6809 대응(`crypto/x509`: `Certificate.Verify`가 알려진 침해된 중간 인증서를 거부하지 않았음). `go` 지시어는 1.27.3. 동작 변경 없음 |
| v0.23.4 | 릴리스 바이너리를 `-s -w` 대신 `-w`로 링크하므로 정확한 `govulncheck -mode binary`를 위해 심볼 테이블이 남음. 동작 변경 없음 |
| v0.23.6 | 감사, 퍼징, 카오스 실행. go-authn/saml v0.5.1 사용. 추가되거나 바뀐 구성 키는 없습니다. [메타데이터를 제때 새로 고칩니다]({{< relref "/authn-bridge/federation.md#refreshing-it" >}}): 남은 `validUntil`의 절반을 넘겨 예약되지 않으며, 유효한 메타데이터가 없으면 1분 뒤에 다시 시도하고 간격을 두 배로 늘려 최대 1시간까지 가므로, 만료 직전의 새로 고침 실패로 공급자가 최대 12시간 IdP 없이 지내는 일이 없습니다. 어설션 재전송 키는 SHA-256으로 저장됩니다. 긴 IdP `entityID` 때문에 PostgreSQL과 MySQL이 쓰기를 거부하여 상태 데이터베이스가 막혔습니다. 시계는 IdP와 3분까지 달라도 되며 한 시간은 400 페이지로 거부됩니다. [테스트되는 것]({{< relref "/authn-bridge/federation.md#tested" >}}): XML 서명 래핑 XSW1~XSW8, CVE-2017-11427, DOCTYPE, 다른 오디언스·수신자·요청·목적지, 퍼저 다섯 개. 로그인당 SHA-256 한 번은 할당이 0~2회 늘어납니다(`BenchmarkReplayUse`: 0회·183 B에서 2회·326 B). 실제 시간은 측정하지 않음, 부하 53~75 |

### authn-revokd {#authn-revokd}

| | |
|---|---|
| v0.1.0 | 서명되고 만료되는 폐기 목록: 프로토콜, 라이브러리, revokd(에이전트와 미러) |
| v0.2.0 | 적대적 검토의 수정 사항 |
| v0.2.1 | 각 CA의 목록이 자체 키 폐기와 병합됨, CRL의 서명을 구문 분석하기 전에 확인함 |
| v0.3.0 | 범위가 지정된 키 폐기, CA별 실패 시 차단, 상태 디렉터리 소유자 확인 |
| v0.5.0 | 모든 태그에 릴리스 바이너리, `SHA256SUMS`, 빌드 출처 증명 |
| v0.6.0 | 명령은 `authn-revokd`, systemd 유닛과 설치 가이드, `SIGHUP`이 즉시 동기화함 |
| v0.6.1 | `-version`이 표준 출력에 출력됨 |
| v0.6.2 | `-once`가 가져오기 실패와 만료된 목록을 구분함, 다른 키로 서명된 목록을 더 이상 경쟁 상태라고 부르지 않음, `-help`가 0으로 종료함 |
| v0.6.3 | 예제와 문서의 자리 표시자 도메인을 RFC 2606 이름으로 변경, 동작 변화 없음 |
| v0.6.4 | 의존성만: golang.org/x/crypto v0.58.0 |
| v0.6.5 | Go 1.27.3으로 빌드, GO-2026-6809 대응(`crypto/x509`: `Certificate.Verify`가 알려진 침해된 중간 인증서를 거부하지 않았음). `go` 지시어는 1.27.3. 동작 변경 없음 |
| v0.6.6 | 릴리스 바이너리를 `-s -w` 대신 `-w`로 링크하므로 정확한 `govulncheck -mode binary`를 위해 심볼 테이블이 남음. 동작 변경 없음 |
| v0.6.7 | 감사, 퍼징, 카오스, 성능 실행([한 번의 동기화가 하는 일]({{< relref "/authn-revokd/configuration.md#sync" >}})). 만료되는 목록은 다음 새로 고침이 아니라 만료되는 때 거부됩니다. 소스는 병렬로 가져옵니다(최대 16개, 각 2분). `on_change`는 1분 뒤에 종료되고 다시 시도됩니다. 에이전트 모르게 바뀐 출력 파일은 다음 동기화에서 다시 쓰입니다. `file://` 소스는 일반 파일이어야 합니다. 오류는 비밀번호, 쿼리, 프래그먼트 없는 URL을 보여 줍니다. `0..2^159` 범위를 벗어난 CRL 번호는 거부됩니다. 미러에는 읽기, 쓰기, 유휴 기한이 있습니다. 오래된 임시 파일은 시작할 때 제거됩니다. 100,000개 항목의 CRL을 다시 조회: 조회당 할당 300,138회와 96,956,946 B가 37회와 4,776,864 B로(정확. 시간은 측정하지 않음, 부하 53~65). govulncheck는 여전히 GO-2026-5932(`golang.org/x/crypto/openpgp`)를 나열하며, 수정된 버전이 없고 호출되지 않습니다 |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | 도메인 권한 부여 확장, 그리고 실패 시 차단하는 `sshcert-authorize` |
| v0.1.2 | 모든 태그에 릴리스 바이너리, `SHA256SUMS`, 빌드 출처 증명 |
| v0.1.4 | 릴리스가 모든 바이너리의 빌드 정보를 확인함 |
| v0.1.5 | `-version`이 `dev`가 아니라 `go install` 빌드의 모듈 버전을 출력함 |
| v0.1.6 | 문서의 자리 표시자 도메인을 RFC 2606 이름으로 변경, 동작 변화 없음 |
| v0.1.7 | 의존성만: golang.org/x/crypto v0.58.0 |
| v0.1.8 | 릴리스 바이너리를 `-s -w` 대신 `-w`로 링크하므로 정확한 `govulncheck -mode binary`를 위해 심볼 테이블이 남음. 동작 변경 없음 |
| v0.1.9 | Go 1.27.3으로 빌드. 동작 변경 없음 |

### 라이브러리 {#the-libraries}

이 문서 버전을 위해 만들어진 라이브러리 릴리스입니다. 이전 릴리스에서 바뀐 것은
각 라이브러리의 페이지에 설명되어 있습니다.

| | |
|---|---|
| directory v0.13.0 | [속성]({{< relref "/libraries/directory.md#attributes" >}}): 누군가를 설명하되 아무것도 증명하지 않는 것(자격 증명 제외), 속성이 될 수 없는 이름 포함, `user`와 `group` 블록의 `attributes`, `users_attributes`와 `groups_attributes` 쿼리, ldapdir의 `attributes`와 `group_attributes` |
| directory v0.14.0 | ⛔ ldapdir의 [기본값]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})이 `account`와 `uidObject` 사람 및 `groupOfNames` 그룹을 읽으므로 기관의 디렉터리가 제공하는 범위가 넓어짐, `member` DN은 소스가 가져온 사람에게만 매핑됨 |
| directory v0.15.0 | [오브젝트 클래스]({{< relref "/libraries/directory.md#object-classes" >}}), 선언되며 추론되지 않음: `users` 블록의 `object_classes`와 `group_object_classes`, `user`와 `group` 블록의 `object_classes`, sqldir의 `WithObjectClasses`와 ldapdir의 `Config.ObjectClasses`, 그룹의 클래스는 이를 선언하는 첫 번째 소스가 결정함, `sqldir.ClosesDB` |
| directory v0.16.0 | [각 그룹을 한 번만 읽음]({{< relref "/libraries/directory.md" >}}): `GroupReader`와 `Set.Frozen`. 새로 고침이 그룹 수와 멤버십 행의 곱에 따라 늘지 않습니다 |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}}), `AsUnavailable`과 `TransportFailure` 포함: ldapdir는 busy(51), unavailable(52), other(80), timeLimitExceeded(3), 끊기거나 거부된 연결, 연결이나 TLS 실패에 대해 `Verify`와 모든 읽기에서 이를 반환합니다. `ErrWrongPassword`와 동시에 참인 일은 없으며 `invalidCredentials`(49)는 후자로 남습니다. `ldaptest.Server.FailBindsWith(code)`. 멤버 DN은 훑는 대신 한 번의 조회로 사람에 대응되며 결과는 같습니다. DN 50개씩의 2,000개 그룹과 10,000명에서 `ReadGroups`는 50.6 MB·2.20 M 객체 대신 13.1 MB·0.38 M을 할당하고, DN 조회는 0회, 전체 새로 고침은 9.72 M 대신 7.17 M회(정확. 시간은 측정하지 않음, 부하 65~105) |
| kdc v0.4.3 | 의존성만: 최소 요구 버전으로 go-authn/directory v0.12.0 |
| kdc v0.4.5 | 보안 감사, 퍼징, 카오스 실행([거부하는 것]({{< relref "/libraries/kdc.md" >}})): 다른 렐름에 대한 요청은 `KDC_ERR_WRONG_REALM`, 읽을 수 없는 디렉터리는 `KDC_ERR_SVC_UNAVAILABLE`로 응답하며(이전에는 `KDC_ERR_C_PRINCIPAL_UNKNOWN`), 시작이 `MaxSkew` 안의 미래인 TGT는 받아들이고, 디코더 패닉은 프로세스를 크래시시키는 대신 요청 하나를 버립니다(잘못된 AS-REQ나 TGS-REQ 하나로 크래시할 수 있었습니다). 프린시펄 이름은 로그에서 따옴표로 묶입니다. golang.org/x/net v0.62.0, go-authn/directory v0.16.1 |
| keyfactor v0.4.2 | 의존성만: 최소 요구 버전으로 go-authn/fido v0.6.2와 golang.org/x/crypto v0.58.0 |
| krb5 v0.3.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| krb5 v0.3.3 | 의존성만: golang.org/x/net v0.62.0, golang.org/x/crypto v0.58.0, go-uuid v1.0.4로 요구하지만 호출되지 않는 모듈에서 `govulncheck` 결과 46건 중 45건이 해소됩니다. GO-2026-5932(`x/crypto/openpgp`)는 수정이 없고 어떤 go-authn 모듈도 가져오지 않습니다. API 변경 없음 |
| krl v0.6.1 | 의존성만: golang.org/x/crypto v0.58.0, Go 1.27.2로 테스트함 |
| ldap v0.8.0 | [`schema` 패키지]({{< relref "/libraries/ldap.md#the-schema" >}})와 `Server.Schema`: `cn=Subschema`(RFC 4512 §4.2), `Validate`, RFC 4517 매칭 규칙, `uidNumber`와 `gidNumber`는 정수로 정렬됨, 페이지 검색이 요청된 속성만 유지함 |
| ldap v0.9.0 | [HCL2 스키마]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): `schema/hclschema` 패키지와 OpenLDAP `.schema`, cn=config LDIF, HCL2 사이를 변환하는 `ldapschema` 명령(`to-hcl`, `to-schema`, `check`), 리더는 slapd처럼 파일을 읽음, DIT 콘텐츠와 구조 규칙, 이름 형식, `include`, `X-SUBST`는 지원되지 않음(v0.11.0은 규칙을 지원함) |
| ldap v0.10.0 | `Build`가 거부하는 정의에 대한 [타입이 있는 `*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}), `errors.As`로 확인: `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos`(정의가 시작되는 file:line:column, 접힌 또는 base64 LDIF와 HCL도 포함), 다른 정의를 위한 `Ref`, `RefOID`, `RefPos`. 읽은 모든 정의가 `Pos`를 가짐. 메시지의 "object classes" |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}})가 이어짐 줄 수에 선형이 됨(이전에는 제곱 시간이어서 4 MiB 파일에 약 3분이 걸렸음). 첫 줄을 읽으려고 파일 전체를 복사하고 나누지도 않음. `schema.Format`은 2000바이트가 넘는 줄(slapd와 `Read`는 거부함)을 접음. 엄격한 파서가 약 2.6배 빠름(`cosine.schema`에서 할당 498회가 147회, 부하 상태에서 측정) |
| ldap v0.10.2 | 내장 스키마(`schema.Standard()`)의 RFC 2307 정의 13개의 DESC 가 한 줄로 바뀌었습니다. RFC 쪽 나눔의 들여쓰기가 들어 있었고, 리더는 slapd 처럼 따옴표 안에서 이를 유지하므로 서버가 게시한 서브스키마에 연속된 공백이 있었습니다. 이제 테스트가 내장된 모든 DESC 를 이 점에서 검사하고, 같은 OID 가 정의된 곳에서는 OpenLDAP 의 `core`, `cosine`, `inetorgperson`, `nis` 스키마와 비교합니다 |
| ldap v0.11.0 | [DIT 콘텐츠 규칙, 이름 형식, DIT 구조 규칙]({{< relref "/libraries/ldap.md#rules" >}})(RFC 4512 §4.1.6, §4.1.7)을 `.schema`와 LDIF에서 읽고, `Format`이 쓰고, HCL(`dit_content_rule`, `name_form`, `dit_structure_rule`)과 `ldapschema`를 거치며, `Build`가 검사하고, `Validate`가 적용하며(콘텐츠 규칙: AUX, MUST, MAY, NOT, 이름 형식: RDN, 구조 규칙: `GoverningStructureRule`), 있을 때만 `cn=Subschema`에 게시됨. `ValidateOptions{StrictAuxiliary}`는 RFC 4512 §2.4.3을 따름. ⛔ slapd는 콘텐츠 규칙만 구현하므로 `Format`이 쓰는 `nameform`과 `ditstructurerule` 키워드를 slapd는 거부하며, `OBSOLETE` 규칙은 비활성이지만 slapd는 엔트리를 거부하고, libldap은 구조 규칙의 `SUP`을 읽지 못함. `hclschema.Decode`는 UTF-8이 아닌 문자열을 거부함 |
| ldap v0.11.1 | 성능만 개선, 결과는 그대로: 인쇄 가능한 ASCII 문자열은 문자열 비교 규칙(RFC 4518)을 위해 최대 한 번의 할당으로 준비되고 아무것도 바뀌지 않으면 할당이 없으며, DN 파서는 RDN이 네 개인 DN에서 할당을 11회에서 6회로 줄임. 결과는 v0.11.0과 같고, 0x80 미만의 1바이트·2바이트 문자열 전부에 대해 v0.11.0 코드와 대조했으며 차분 퍼저로도 확인함 |
| ldap v0.11.2 | 성능만 개선, 결과는 그대로: 속성 열 개짜리 엔트리에서 `Validate`의 할당이 76회에서 12회로 줄어듦(소문자 복사본 없는 조회, 나누었다 다시 합치지 않는 설명, 맵 대신 제자리 집합). 결과는 v0.11.1과 같고, 표준 스키마와 규칙 스키마에서 무작위 엔트리로 v0.11.1의 `Validate` 사본과 대조했으며 차분 퍼저로도 확인함 |
| ldap v0.11.3 | 성능만 개선, 결과는 그대로: `GoverningStructureRule`의 할당이 계정 하나에서 12회에서 5회로 줄어듦(RDN의 타입만 읽음), DN 파서는 RDN이 네 개인 DN에서 6회에서 3회로 줄어듦. 결과는 v0.11.2와 같고, 무작위 엔트리와 모든 상위 규칙에서 v0.11.2의 `GoverningStructureRule` 사본과 대조했으며 차분 퍼저로도 확인함 |
| ldap v0.12.0 | [서버의 자원 한도]({{< relref "/libraries/ldap.md" >}}): `Server.MaxConnections`와 `Server.MaxConnectionsPerIP`(기본 0, 제한 없음. 상한을 넘은 연결은 `busy`(51) 연결 해제 통지, RFC 4511 4.4.1을 받고 닫힙니다). `Server.Timeout`은 서버가 강제하며, 핸들러가 막혀서 컨텍스트를 무시하더라도 기한에 모든 작업에 `timeLimitExceeded`(3)로 응답합니다(늦은 결과는 버려지고, 고루틴은 돌아올 때까지 `MaxPending`과 `MaxPendingAuth`에 계산됩니다). 클라이언트의 검색 `timeLimit`은 핸들러의 컨텍스트에 적용됩니다. 핸들러의 `DeadlineExceeded`는 그 작업 자신의 컨텍스트가 만료되었을 때만 코드 3이 됩니다. 작업당 할당(정확): `Timeout` 없이는 전후 모두 3, 있으면 이전 10, 지금 16 |
| oidc v0.4.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| scim v0.2.0 | [감사, 퍼징, 카오스, 성능 실행]({{< relref "/libraries/scim.md#v020" >}}): `Server.ReadTimeout`(30초), 선택 인터페이스 `ConditionalDeleter`, `If-Match` 없는 PATCH나 PUT은 진 경합에서 412 대신 최대 32번 다시 수행, 아무것도 일치하지 않는 필터로의 제거는 성공, 경로 없는 PATCH의 키는 정렬된 순서로 적용, `BearerAuth`는 스킴을 대소문자 구분 없이 받아들임, `startIndex`와 `count`는 워드 크기와 상관없이 상한으로 잘림. 사용자 10,000명에 대한 목록 요청: 100개 페이지는 789,417회에서 14,952회로, `userName eq`는 797,979회에서 90회로, 전체 훑기는 818,847회에서 361,098회로(정확. 시간은 측정하지 않음, 부하 65) |
| servercert v0.5.2 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| totp v0.4.2 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| wireguard v0.1.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |

## 아직 구현되지 않은 것 {#not-implemented-yet}

- **LDAP을 통한 쓰기**, 사람이 자신의 비밀번호를 바꾸는 경우는 제외합니다. authnd는
  자기 자신의 `userPassword`에 대한 modify와 RFC 3062 비밀번호 변경 작업
  (`ldappasswd`가 보내는 것)에만 응답하며, 둘 다 현재 비밀번호가 있어야 합니다.
  그 밖에는 아무것도 하지 않습니다. add, delete, modifyDN은 go-authn/ldap에
  존재하지만 의도적으로 연결하지 않았습니다(`server.go`). 라이브러리는 modify를
  순서 있는 목록으로 다루고(RFC 4511 4.6) 읽기 엔트리 컨트롤(RFC 4527)에
  응답하므로 형태는 갖추어져 있습니다. 부족한 것은 누가 무엇을 쓸 수 있는가라는
  정책입니다.
- **Kerberos 안의 두 번째 인증 요소**: FAST(RFC 6113) 안에서의 OTP 사전 인증
  (RFC 6560). 이것이 생기기 전까지는 `kerberos` 블록과 `mfa` 블록을 함께
  구성할 수 없습니다.
- **RC4-HMAC**: 렐름은 aes256-cts-hmac-sha1-96만 발급하므로 NT 해시로만 알려진
  사람에게는 티켓을 발급할 수 없습니다. 이것은 채워지기를 기다리는 빈틈이 아니라
  선택입니다(RC4는 RFC 8429에서 사용 중단되었습니다).
