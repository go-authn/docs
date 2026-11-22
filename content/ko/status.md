---
title: "상태"
weight: 60
description: "이 문서가 설명하는 릴리스, 각 릴리스에서 추가된 것, 그리고 아직 구현되지 않은 것."
tags: [상태, 릴리스]
---

이 문서는 문서 버전 **0.11**이며 다음을 설명합니다.

| 프로그램 | 릴리스 | 모듈 |
|---|---|---|
| authnd | **v0.18.6** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.12** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.7.0** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

라이브러리의 버전은 [해당 페이지]({{< relref "/libraries/_index.md" >}})에
있습니다. ldap은 DIT 콘텐츠 규칙, 이름 형식, DIT 구조 규칙의 읽기, 적용, 게시와
빌드되지 않는 스키마를 위한 타입이 있는 `BuildError`, HCL2
스키마, `ldapschema` 변환기를 갖춘 **v0.12.3**이고,
directory는 선언된 오브젝트 클래스, 모든 SQL 쿼리의 기한, 그리고 실패한 소스를
보고하는 `GroupNames`를 갖춘 **v0.21.0**입니다. authnd
v0.18.6는 ldap v0.12.3과 directory v0.20.0을 내장합니다.
위 프로그램 중 어느 것이든 새 마이너 버전이 나오면 새 문서 버전이 됩니다. 따라서
독자가 `/docs/0.11/`에서 찾는 페이지는 설치한 것을 계속 설명하며, 이전 릴리스의
페이지는 `/docs/0.1/`, `/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/`, `/docs/0.5/`, `/docs/0.6/`, `/docs/0.7/`, `/docs/0.8/`, `/docs/0.9/`, `/docs/0.10/`에 남아 있습니다.

{{< callout type="warning" >}}
**authnd를 v0.16.x에서 업그레이드: `max_age`의 기본값은 10분입니다**

제공되는 데이터에는 나이 제한이 없어서, 소스에서 제거된 사람이 그 소스를 읽을 수 없게 된 뒤에도 장애가 이어지는 동안 계속 bind할 수 있었습니다. v0.17.0부터 `max_age`는 10분이며(`refresh` 주기의 10배 이상, `refresh = "0"`이면 기본값 없음), 그 시간이 지나면 검색, 사람의 bind, 비밀번호 변경은 `unavailable`(52)로 응답합니다. `max_age`를 허용할 수 있는 값으로 설정하거나, 제한이 없어도 되면 `"0"`으로 설정하십시오. [업그레이드 안내]({{< relref "/authnd/_index.md" >}})와 [오래된 데이터를 거부하는 방식]({{< relref "/authnd/operations.md#it-reads-everything-once" >}})을 참조하십시오.
{{< /callout >}}

{{< callout type="warning" >}}
**authnd를 v0.15.x에서 업그레이드: `oidc { domains }`가 필수입니다**

`oidc` 블록이 있는 설정은 `domains` 없이는 시작되지 않으며, 토큰의 이름은 허용된 도메인의 정확히 하나의
`local@scope`여야 합니다. 연합 프록시 뒤에서는 어느 기관의 alice든 로컬 alice로 바인드되었습니다.
`domains`를 추가하고 `username_claim = "eduperson_principal_name"`을 설정하며, 디렉터리 이름이 로컬 부분만이면
`local_domain`을 추가하십시오. [업그레이드 노트]({{< relref "/authnd/_index.md" >}})와
[이름에는 범위가 있어야 합니다]({{< relref "/authnd/tokens.md#scoped-name" >}})를 보십시오.
{{< /callout >}}

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
| v0.15.1 | Kerberos. go-authn/kdc v0.5.0 사용: 바이트 단위로 같은 재전송은 이전 응답을 받고(MIT의 lookaside), 디렉터리 장애는 올바른 비밀번호여도 `KDC_ERR_SVC_UNAVAILABLE`이며 `KDC_ERR_PREAUTH_FAILED`가 아니므로 잠금에 계산되지 않습니다. golang.org/x/net v0.62.0. 설정 변경 없음 |
| v0.16.0 | ⛔ 보안. go-authn/oidc v0.6.1과 go-authn/directory v0.18.0 사용. **`oidc` 블록이 있는 배포에는 호환되지 않는 변경**: [`domains`가 필수]({{< relref "/authnd/tokens.md#scoped-name" >}})이며 없으면 서버가 시작되지 않습니다. 토큰의 이름은 허용된 도메인의 정확히 하나의 `local@scope`여야 하며(범위 없는 이름, 다른 기관의 이름, `@`가 둘인 이름은 거부), 선택 사항인 `local_domain`(`domains` 중 하나)은 그 범위의 사람을 로컬 부분만의 디렉터리 이름에 대응시키고 다른 범위는 `local@scope` 전체로 조회됩니다. 연합 프록시 뒤에서는 어느 기관의 alice든 로컬 alice로 바인드되었습니다. 한 소스의 두 엔트리가 같은 uid를 가지면 조용히 하나를 고르는 대신 시작할 때와 새로 고칠 때 오류가 됩니다. [업그레이드 노트]({{< relref "/authnd/_index.md" >}}) |
| v0.16.1 | `kerberos { listen = "host:0" }`는 UDP와 TCP에 하나의 포트를 받습니다(이전에는 두 개였고, `krb5.conf`는 하나만 지정할 수 있습니다). 시작 줄은 그 포트를 표시합니다. 테스트는 포트를 골라 해제한 뒤 지정하는 방식을 그만두었습니다. 이 방식은 러너에서 `address already in use`로 실패했습니다 |
| v0.16.2 | ⛔ 보안. [렐름은 스냅숏을 읽습니다]({{< relref "/authnd/kerberos.md#where-the-realm-reads-people" >}}). 소스는 읽지 않습니다: 모든 AS-REQ와 TGS-REQ(UDP의 인증되지 않은 AS-REQ 포함)가 각 SQL 소스의 전체 사용자 쿼리와 각 `ldap` 업스트림의 하위 트리 검색을 실행했습니다. `max_age`는 이제 Kerberos에도 적용됩니다(넘으면 `KDC_ERR_SVC_UNAVAILABLE`). 데이터베이스에서 삭제된 사람은 LDAP 바인드처럼 `refresh` 한 주기 안에 티켓을 받지 못합니다. go-authn/kdc v0.6.0 사용 |
| v0.17.0 | ⛔ 보안, 두 번째 점검, go-authn/ldap v0.12.1 사용. **호환되지 않는 변경: [`max_age`에 이제 기본값이 있습니다]({{< relref "/authnd/operations.md#it-reads-everything-once" >}})**. 10분(`refresh` 주기의 10배 이상, `refresh = "0"`이면 기본값 없음)이며 이전에는 무제한이었습니다. 소스에서 제거된 사람이 그 소스를 읽을 수 없게 된 뒤에도 장애가 이어지는 동안 계속 bind할 수 있었습니다. 그 시간이 지나면 검색, 사람의 bind, 비밀번호 변경은 `unavailable`(52)로 응답하며, `max_age = "0"`은 받아들여지고 의도적인 제한 없음을 뜻합니다. [토큰의 이름은 ASCII 대소문자 접기로만 비교됩니다]({{< relref "/authnd/tokens.md#scoped-name" >}}): 켈빈 기호(U+212A)를 쓴 `Kate@univ-a.example`는 더 이상 `kate`로 bind되지 않습니다. 업스트림에 대해 [소스마다 미완료 확인은 최대 64개]({{< relref "/authnd/operations.md#outage" >}})이며 65번째는 즉시 `unavailable`로 응답합니다(응답하지 않는 업스트림에 대한 bind 400건에서 유지되던 goroutine은 1620개에서 257개로 줄었습니다). [업그레이드 안내]({{< relref "/authnd/_index.md" >}}) |
| v0.18.0 | [업스트림에 대한 비밀번호 확인은 제한되는 데 그치지 않고 취소됩니다]({{< relref "/authnd/operations.md#outage" >}}): bind와 비밀번호 요소는 `Identity.VerifyContext`(go-authn/directory v0.19.0)를 사용하며, bind의 예산이 끝나면 업스트림 연결을 닫으므로 아무것도 계속 실행되지 않습니다. 응답하지 않는 업스트림에 대한 bind 400건에서 붙들린 goroutine: 1620개(v0.16.2), 257개(v0.17.0, 상한), 4개(v0.18.0). 취소할 수 없는 소스를 위해 소스마다 확인 64개라는 상한은 그대로입니다. 이름 접기는 go-authn/oidc v0.7.0에서 가져옵니다. 설정 변경은 없습니다 |
| v0.18.1 | [시작 타임아웃이 열고 있던 SQL 소스를 밝힙니다]({{< relref "/authnd/operations.md#limits" >}}): `opening sql pgx (dsn_file …) did not answer`. 이전에는 모든 SQL 블록이 `opening sql`이었습니다. 드라이버와 DSN을 담은 파일을 밝히며, DSN은 결코 밝히지 않습니다. 테스트: 일회용 클러스터의 실제 PostgreSQL에 대한 카오스 테스트(새로 고치는 중 서버 중지, 쿼리 도중 연결 재설정, 결코 응답하지 않는 리스너, 장애 중의 Kerberos 렐름). 서버 바이너리가 없으면 건너뛰며, `AUTHND_REQUIRE_PG=1`이면 실패로 처리합니다. 설정 변경은 없습니다 |
| v0.18.2 | [멈춘 SQL 읽기가 더 이상 새로 고침을 얼리지 않습니다]({{< relref "/authnd/people.md" >}}): 연결을 받아들이고 응답을 멈춘 데이터베이스가 있으면 새로 고침이 쿼리에서 막혔고, 이후의 모든 틱은 건너뛰어졌으며, `max_age`가 지나면 재시작할 때까지 모든 것이 `unavailable`로 응답했습니다. `users "sql"` 블록에 이제 `query_timeout`이 있으며 기본값은 `refresh`의 4분의 3입니다(go-authn/directory v0.20.0). **동작 변경:** 기한보다 느린 쿼리 하나는 실패합니다. 더 느린 쿼리에는 `query_timeout`을 설정하세요 |
| v0.18.3 | [반환은 정지를 뜻합니다]({{< relref "/authnd/operations.md" >}}): 종료가 반환되는 시점에 LDAP 리스너와 Kerberos 소켓 둘은 닫혀 있고 서버는 끝나 있으므로 재시작이 즉시 바인드할 수 있습니다. 서버가 Kerberos 라이브러리에 닿기 전에 종료가 도착하면, 이전에는 렐름의 UDP와 TCP 소켓이 열린 채로 반환되었습니다. 설정 변경은 없습니다 |
| v0.18.4 | LDAP 업스트림에 대한 리프레시의 할당이 이전의 4분의 1이 되었습니다(go-authn/ldap v0.12.2). 게시된 엔트리의 스키마 검사가 `member` 값의 모든 쌍을 비교하며 매번 두 DN을 파싱했습니다. 10,000명과 DN 50개짜리 그룹 2,000개의 리프레시를 같은 프로세스의 LDAP 업스트림에 대해 실행하면(`BenchmarkRefreshLDAP10k2k`, 정확한 횟수) 이전에는 할당 3,760만 회와 2.43 GB, 이후에는 995만 회와 651 MB입니다. 설정 변경은 없습니다 |
| v0.18.5 | 응답하지 않는 업스트림에 대한 bind는 부하가 높은 호스트에서도 `timeLimitExceeded`(3)가 아니라 `unavailable`(52)로 응답합니다. bind의 예산은 라이브러리의 `operation_timeout` 기한보다 그 10분의 1(최소 250 ms, 최대 절반)만큼 일찍 끝납니다. 이전에는 10분의 1뿐이었고(`"300ms"`에서 30 ms) 부하가 높은 호스트가 그것을 다 써 버렸습니다. 설정 변경은 없습니다 |
| v0.18.6 | go-authn/ldap v0.12.3: 같은 리프레시가 할당 835만 회와 573 MB입니다(v0.18.4에서는 995만 회와 651 MB). 남은 것은 주로 클라이언트의 LDAP 와이어 라이브러리와 같은 프로세스의 테스트 서버입니다. 설정 변경은 없습니다 |
| v0.18.7 | 보안: [익명의 느린 bind가 한 소스의 모든 bind를 `unavailable`로 응답하게 만들 수 없게 되었습니다]({{< relref "/authnd/operations.md#outage" >}}). 소스당 확인 64개의 상한은 시작된 순간부터 모든 확인을 세었으므로, 인증되지 않은 연결 64개가 느린 틀린 비밀번호 bind를 하면 정당한 bind가 굶었습니다. 이제는 bind의 예산을 넘겨 아직 실행 중인 확인만 세며, 이것이 원래 제한하려던 것(응답하지 않는 업스트림)입니다. 예산 안의 확인은 `max_connections`가 제한합니다. `max_connections_per_ip`의 기본값은 그대로입니다(제한 없음). 클라이언트가 직접 연결하는 곳에 지정하세요 |
| v0.19.0 | [대소문자나 중요하지 않은 공백만 다른 이름은 소스 사이에서 한 사람입니다]({{< relref "/authnd/people.md#order-and-the-one-exception" >}}). go-authn/directory v0.26.0, go-authn/ldap v0.15.0과 함께입니다. `Set`은 이름을 uid의 LDAP 동등 규칙(`caseIgnoreMatch`)으로 비교하며, `ldapdir`가 한 소스 안에서는 이미 그렇게 했습니다. 첫 소스가 그 사람을 소유하고, 나중의 표기는 제외되며, 그 사람은 소유한 소스의 표기를 유지합니다. **authnd는 이제 소스 사이에 대소문자만 다른 이름이 있어도 시작하며, 그것을 기록합니다.** 시작할 때와, 목록이 바뀐 새로 고침 때 `directory: names shadowed by a spelling an earlier source owns`가 가려진 각 표기와 그 소스, 소유자를 알려 줍니다. 동등 키가 없는 이름(UTF-8이 아니거나, 비었거나, 공백뿐인 이름)은 바이트로 비교되는 대신 시작과 새로 고침을 실패시킵니다. **업그레이드:** 가려진 표기가 있는지 로그를 읽으세요 |

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
| v0.23.7 | 보안: `saml { idps }`에서 빠진 IdP에서 온 리프레시 토큰, 애플리케이션 비밀번호, SSH 인증서 요청은 `DisableIdP`처럼 다음에 사용될 때 `institution not configured`로 거부됩니다([관리 API]({{< relref "/authn-bridge/admin.md" >}})). IdP를 다시 넣으면 다시 동작합니다 |
| v0.23.8 | 보안: [사람은 그 사람 자신으로서 비활성화됩니다]({{< relref "/authn-bridge/admin.md" >}}). 사용자 이름(비활성화 목록, 인증서 프린시펄, subject-id)은 go-authn/oidc v0.7.0의 `ASCIILower`로 ASCII 문자만 접어 비교하므로, `kate`와 켈빈 기호(U+212A)를 쓴 표기는 두 사람이며 비활성화 항목도 인증서 프린시펄도 둘이 됩니다 |
| v0.23.9 | 보안, go-authn/saml v0.6.0과 함께: [`schac_home_organization`이 발급되는]({{< relref "/authn-bridge/tokens.md" >}}) 것은 토큰과 userinfo에서 어서션하는 IdP의 `shibmd:Scope` 값 중 하나(정확히 일치, 대소문자 구분)일 때뿐입니다. 한 기관의 IdP가 다른 기관의 값을 말할 수 있었고, 이 클레임으로 거르는 서비스(게이트웨이의 `accept`)는 그 기관으로 받아들였습니다. **업그레이드:** 메타데이터가 도메인의 Scope를 게시하지 않는 IdP는 더 이상 클레임이 발급되지 않습니다 |
| v0.23.10 | 보안: [지금에 시계 오차 3분을 더한 것보다 늦은 `AuthnInstant`]({{< relref "/authn-bridge/federation.md" >}})가 `max_age`에서 새로운 인증으로 계산되었습니다(경과 시간이 음수가 되었습니다). 이제 경과 시간을 알 수 없는 것으로 보며(OIDC Core 3.1.2.1), 오래된 것과 마찬가지로 그 사람은 `ForceAuthn`과 함께 IdP로 다시 보내집니다. 오차 범위 안에서는 아무것도 바뀌지 않습니다 |
| v0.23.11 | [데이터베이스가 영구적으로 거부하는 상태 행 하나가 더 이상 이후의 모든 플러시를 멈추지 않습니다]({{< relref "/authn-bridge/configuration.md#state-what-a-restart-must-not-forget" >}}). 폐기도 포함됩니다. 삭제는 항상 흘러가며, 영구적으로 거부된 행(PostgreSQL SQLSTATE 클래스 22와 23, MySQL 1048, 1062, 1264, 1265, 1292, 1366, 1406, 1452, SQLite constraint, mismatch, too big)은 한 번 로그에 기록되고, 새 `bridge_state_rows_rejected_total{kind}`에 계산되며 포기됩니다. 메모리에서는 동작하고 재시작을 넘어 남지 않습니다 |
| v0.23.12 | 어떤 분류기도 모르는 오류로 거부된 상태 행은, 그 행이 계속 실패하는 동안 데이터베이스가 다른 것을 받아 준 플러시가 최소 30초에 걸쳐 다섯 번 있으면 포기됩니다. 아무것도 성공하지 못한 플러시, 즉 데이터베이스가 없는 경우는 어떤 행에도 불리하게 계산되지 않으므로 **장애는 아무것도 포기하게 하지 않습니다**. 동작은 더 이상 드라이버 오류 클래스의 목록에 의존하지 않습니다 |
| v0.31.0 | 보안: [페더레이션된 사람과 로컬 계정이 더 이상 하나의 프린시펄이 될 수 없습니다]({{< relref "/authn-bridge/federation.md" >}}). `local { scope }`가 페더레이션 IdP의 스코프와 같으면, 로컬 `alice`와 페더레이션 `alice@<scope>`는 같은 Kerberos 프린시펄, 같은 `eduperson_principal_name`, 따라서 같은 SSH 프린시펄이었습니다. 사용자 이름이나 eppn이 로컬 스코프에 있는 페더레이션 로그인은 이제 발급 시점에 거부되고(`access_denied`), 메타데이터의 스코프는 갱신할 때마다 바뀌기 때문입니다. 그래도 존재하는 페더레이션 토큰은 Kerberos 티켓을 받지 못하며, 사용 가능한 IdP의 스코프가 로컬 스코프이면 `authn-bridge check`가 실패합니다. **업그레이드:** `check`가 이 충돌을 보고하면 `local` 블록에 다른 스코프를 지정하세요(로컬 계정의 프린시펄과 eppn이 함께 바뀝니다). v0.23.12와 v0.31.0 사이의 릴리스는 이 페이지가 아니라 [CHANGELOG](https://github.com/go-authn/bridge/blob/v0.31.0/CHANGELOG.md)에 설명되어 있습니다 |
| v0.31.1 | 보안: bridge가 의존하는 directory v0.24.0, saml v0.7.1, webauthn v0.1.1의 수정 사항을 가져옵니다. bridge의 설정과 동작은 바뀌지 않습니다. **업그레이드:** v0.31.1로 업데이트하세요. 설정 변경은 필요하지 않습니다 |
| v0.31.2 | 보안, 감사 후속: **제거된 패스키의 토큰으로 더 이상 Kerberos 티켓을 얻을 수 없고, SSH 인증서의 사람을 계속 유효하게 둘 수도 없습니다.** 액세스 토큰은 발급 때 쓴 패스키를 기록하며(상태 필드 `credential`, 선택 사항입니다. 이전에 저장된 토큰은 계정에만 묶입니다), KDC에 묻기 전, 묻고 난 뒤, SSH 인증서를 철회할 때 그 패스키에 묶입니다. 갱신 승인이 이미 그랬던 것과 같습니다. Kerberos 티켓 수명은 호스트가 아니라 공급자의 시계를 씁니다. 방향 제어 문자와 보이지 않는 문자(U+202E, U+200B 등. ZWJ와 ZWNJ는 허용)가 든 표시 이름은 거부됩니다. 등록을 마칠 때 패스키가 열 개를 넘을 수 없습니다(409) |
| v0.31.3 | 의존성, 감사의 두 번째 라운드: go-authn/directory v0.26.0(`Set`의 이름은 소스 사이에서 LDAP 동등 키로, 대소문자 구분 없이 비교됩니다. ldap v0.15.0은 간접 요구 사항으로 들어옵니다), oidc v0.8.0, webauthn v0.2.0, saml v0.7.2, revocation v0.7.1, servercert v0.7.1, wireguard v0.2.0. bridge 자체의 사용과 전체 테스트 스위트는 바뀌지 않습니다 |
| v0.32.0 | [`mail` 블록]({{< relref "/authn-bridge/configuration.md#mail" >}}): 패스키 삭제를 요청하거나 취소하면 계정 자신의 주소(요청이 아니라 로컬 계정 파일에서 가져옴)로 대역 외 평문 이메일을 보내므로, 키 하나를 가진 도둑이 그 키로 소유자의 삭제를 몰래 취소할 수 없습니다. TLS만 사용하며(암시적, 또는 필수 STARTTLS) 인증서를 검증합니다. `username`과 `password_file`은 필수입니다(서비스 사용자 소유, 그룹·다른 사용자 비트 없음, 한 번 열기인 파일). AUTH(PLAIN, 없으면 LOGIN)는 TLS가 성립한 뒤에만 하며, 평문으로는 127.0.0.1에도 하지 않습니다. 본문에 링크가 없고, 헤더의 CR/LF는 거부됩니다. 계정당 `window`(기본 10m)마다 메일 하나이며, 그 사이의 이벤트는 요약 하나로 합쳐집니다. [알림을 보낼 수 없는 삭제 요청은 보류된 채로 남습니다]({{< relref "/authn-bridge/admin.md#passkey-removal-notices" >}})(5회 시도 후 큰 `GAVE UP` 로그, 재시작하면 재개). 취소는 메일이 실패해도 적용되며, 실패는 로그에 남고 계정 페이지에 표시됩니다. 주소가 없는 계정도 삭제는 됩니다. 로그와 페이지가 아무도 알림을 받지 못했다고 알려 줍니다. `mail` 블록이 없으면 아무것도 바뀌지 않습니다. 새 레코드 필드 `notice_pending` |

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
| v0.6.8 | 보안: [검증할 수 없는 상태 사본은 순서의 하한선으로 자리를 유지합니다]({{< relref "/authn-revokd/verification.md#across-restarts-too" >}}). 손상되었거나 다른 CA 키로 기록된 상태 파일은 사본이 없는 것으로 취급되었으므로, 재생된 오래된 목록이 서명되어 있고 만료되지 않았다면 받아들여졌고 더 새 목록이 폐기한 것을 되돌렸습니다. 그 버전과 발급 시각은 이제 검증되지 않은 채 하한선으로 유지됩니다. 그보다 낮은 목록은 그 뒤를 잇는, 검증되는 목록을 보유할 때까지 롤백으로 거부되며, 그 내용은 절대 쓰이지 않습니다. CA가 교체되어 그 목록이 더 낮은 버전에서 다시 시작하면, 로그가 지울 파일 `<source>.state`를 알려 줍니다 |
| v0.7.0 | **명령은 cobra입니다.** 이 플릿의 다른 명령처럼 `--config`/`-c`, `--once`/`-o`, `--version`/`-v`, `--help`/`-h`, `--config=PATH`를 받으며, `--help`는 표준 출력에 출력합니다. [이전 릴리스의 단일 대시 철자]({{< relref "/authn-revokd/_index.md" >}})(`-config`, `-once`, `-version`, `-help`)도 여전히 받아들여지며, 플래그마다 표준 오류에 폐기 예정 안내가 한 줄 나오고, 이후 릴리스에서 제거됩니다. 종료 상태는 바뀌지 않습니다. `packaging/`의 유닛과 설치 가이드는 새 철자를 쓰며, 배포된 유닛은 바꿀 필요가 없습니다. **업그레이드:** 예전 철자가 사라지기 전에 유닛과 스크립트를 `--config`와 `--once`로 옮기십시오 |

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
| awscred v0.2.0 | 리디렉션은 https나 루프백으로 제한됩니다. 토큰 또는 STS 엔드포인트의 307이 서명된 클라이언트 어서션이나 웹 ID 토큰을 일반 http 호스트로 다시 POST하곤 했습니다(호출자 자신의 `CheckRedirect`는 여전히 실행됩니다). **동작 변경:** Unix에서 캐시 파일은 이 사용자의 일반 파일이고, 그룹이나 다른 사용자가 쓸 수 없으며, 이 사용자 소유이고 그룹이나 다른 사용자가 쓸 수 없는 디렉터리에 있을 때만 신뢰됩니다(/tmp 같은 스티키 디렉터리는 허용). 그 밖의 것은 무시되고 자격 증명을 새로 가져오며, 그런 디렉터리에는 아무것도 쓰지 않습니다. Windows는 그대로입니다. **업그레이드:** 모드가 느슨한 공유 `--cache-dir`은 이제 `chmod 700`이 필요합니다 |
| awscred v0.3.0 | `--duration` / `Config.Duration`을 검증합니다. 이전에는 `int(Duration.Seconds())`로 보냈기 때문에 500ms는 `DurationSeconds=0`이 되었고 STS의 범위(900~43200초)를 벗어난 값도 그대로 전송되었습니다. **동작 변경:** 0(서버의 기본값)이 아니거나 15분~12시간을 정수 초로 나타낸 값이 아닌 기간은 어떤 요청보다 먼저 거부되며, 음수도 마찬가지입니다(이전에는 무시되었습니다). `LoadKey`는 키를 한 번만 열고 모드와 바이트를 그 디스크립터에서 가져오며, 최대 1 MiB까지만 읽습니다. **업그레이드:** 0을 넘기거나 15분~12시간의 기간을 넘기세요 |
| awscred v0.3.1 | https나 루프백 규칙과 리디렉션 한도는 oidc, rp, saml, wireguard와 공유하는 [`harden/redirect`]({{< relref "/libraries/harden.md" >}})에서 옵니다. 이제 루프백에는 `*.localhost`도 포함되며, 대소문자와 끝의 점은 가리지 않습니다. IPv6 존은 거부되고, 오류는 URL 전체(비밀이 들어 있을 수 있음)가 아니라 스킴과 호스트를 알려 줍니다. 호출자 자신의 `CheckRedirect`가 설정된 경우에도 이제 10회 리디렉션 한도가 적용되며, 그 `CheckRedirect`는 그 뒤에 여전히 실행됩니다 |
| cms v0.2.1 | [`Verify`]({{< relref "/libraries/cms.md" >}})는 서명된 콘텐츠 자체가 콘텐츠 타입과 메시지 다이제스트 속성을 모두 담은 DER `SET OF Attribute`인 속성 없는 서명을 거부합니다. 서명된 속성이 있는 서명은 그 DER을 덮습니다(RFC 5652 §5.4). 키 없이 그 속성을 콘텐츠로 하는 서명된 속성 없는 SignedData로 다시 포장하면 검증을 통과하고, 콘텐츠로서는 서명된 적 없는 내용에 대해 서명자를 지명했습니다 |
| cms v0.2.2 | 보안: [`Verify`]({{< relref "/libraries/cms.md" >}})는 signing-time 속성이 둘 있거나, 값이 없거나 여럿인 signing-time 속성이 있는 서명 속성을 거부합니다(RFC 5652 §11.3). `Signer.SignedAttrs`를 읽을 때 첫 번째를 취하는 쪽과 마지막을 취하는 쪽이 메시지가 서명된 시점에 대해 서로 다르게 판단하곤 했습니다 |
| directory v0.13.0 | [속성]({{< relref "/libraries/directory.md#attributes" >}}): 누군가를 설명하되 아무것도 증명하지 않는 것(자격 증명 제외), 속성이 될 수 없는 이름 포함, `user`와 `group` 블록의 `attributes`, `users_attributes`와 `groups_attributes` 쿼리, ldapdir의 `attributes`와 `group_attributes` |
| directory v0.14.0 | ⛔ ldapdir의 [기본값]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})이 `account`와 `uidObject` 사람 및 `groupOfNames` 그룹을 읽으므로 기관의 디렉터리가 제공하는 범위가 넓어짐, `member` DN은 소스가 가져온 사람에게만 매핑됨 |
| directory v0.15.0 | [오브젝트 클래스]({{< relref "/libraries/directory.md#object-classes" >}}), 선언되며 추론되지 않음: `users` 블록의 `object_classes`와 `group_object_classes`, `user`와 `group` 블록의 `object_classes`, sqldir의 `WithObjectClasses`와 ldapdir의 `Config.ObjectClasses`, 그룹의 클래스는 이를 선언하는 첫 번째 소스가 결정함, `sqldir.ClosesDB` |
| directory v0.16.0 | [각 그룹을 한 번만 읽음]({{< relref "/libraries/directory.md" >}}): `GroupReader`와 `Set.Frozen`. 새로 고침이 그룹 수와 멤버십 행의 곱에 따라 늘지 않습니다 |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}}), `AsUnavailable`과 `TransportFailure` 포함: ldapdir는 busy(51), unavailable(52), other(80), timeLimitExceeded(3), 끊기거나 거부된 연결, 연결이나 TLS 실패에 대해 `Verify`와 모든 읽기에서 이를 반환합니다. `ErrWrongPassword`와 동시에 참인 일은 없으며 `invalidCredentials`(49)는 후자로 남습니다. `ldaptest.Server.FailBindsWith(code)`. 멤버 DN은 훑는 대신 한 번의 조회로 사람에 대응되며 결과는 같습니다. DN 50개씩의 2,000개 그룹과 10,000명에서 `ReadGroups`는 50.6 MB·2.20 M 객체 대신 13.1 MB·0.38 M을 할당하고, DN 조회는 0회, 전체 새로 고침은 9.72 M 대신 7.17 M회(정확. 시간은 측정하지 않음, 부하 65~105) |
| directory v0.18.0 | [한 소스의 두 엔트리가 가진 같은 이름은 `ErrAmbiguous`]({{< relref "/libraries/directory.md" >}}): ldapdir는 uid를 대소문자 구분 없이 비교해 두 DN을 밝히고, `Set.Identities`는 한 소스가 두 번 나열하는 이름을 거부합니다. 소스 사이에서는 첫 소스가 계속 그 이름을 가집니다. `ldaptest.Person.UID`. 이런 중복이 있는 디렉터리는 고칠 때까지 로드되지 않습니다 |
| directory v0.19.0 | [비밀번호 확인을 취소할 수 있습니다]({{< relref "/libraries/directory.md" >}}): `directory.WithContextVerifier`와 `Identity.VerifyContext(ctx, password)`. `ldapdir` ID에서는 컨텍스트가 끝나면 업스트림 연결을 닫고 `ErrUnavailable`로 응답합니다(go-ldap에는 컨텍스트도 기본 타임아웃도 없어서, 연결을 받아들이고 응답하지 않는 업스트림에 대한 bind는 영원히 기다렸습니다). 확인의 연결 수립도 컨텍스트의 기한에 끝납니다. `Verify`와 `WithVerifier`는 그대로입니다. **업그레이드:** 확인에 제한을 두는 서버는 `VerifyContext`를 호출해야 합니다 |
| directory v0.20.0 | [모든 쿼리에 기한이 있습니다]({{< relref "/libraries/directory.md" >}}): `sqldir.WithQueryTimeout(d)`, 기본값은 `sqldir.DefaultQueryTimeout`(30초), `0`은 제한 없음. 행을 읽는 것까지 포함하며 기한에 드라이버가 연결을 끊습니다(이전에는 응답을 멈춘 데이터베이스가 읽기를 영원히 막았습니다). `hcldir.Block.QueryTimeout`(`sql` 블록의 `query_timeout`)이 여기에 닿으며 네트워크 없이 검사되고 `ldap` 블록에서는 거부됩니다. `Source` 인터페이스는 바뀌지 않습니다. **업그레이드:** 30초보다 느린 쿼리는 이제 실패합니다. 더 느린 쿼리에는 `WithQueryTimeout`을 지정하세요 |
| directory v0.21.0 | [`Set.GroupNames`는 실패한 소스를 보고합니다]({{< relref "/libraries/directory.md" >}}): 답한 소스의 이름과 실패한 각 소스에 대한 `"<describe>: <err>"`의 `errors.Join`을 반환합니다(`errors.Is`는 여전히 `ErrUnavailable`과 일치). 이전에는 다른 소스가 답하면 오류가 버려졌습니다. **동작 변경:** `err != nil`만 검사하던 호출자는 이제 부분 목록을 보던 자리에서 오류를 보며, 이름도 함께 돌아옵니다. 이름을 사용하고 오류를 기록하십시오 |
| directory v0.24.0 | 보안, go-authn/ldap v0.14.0과 함께, [ldapdir]({{< relref "/libraries/directory.md" >}}): `caseIgnoreMatch`가 같다고 보는 두 uid는 한 이름이므로, "alice"와 "alice "(끝의 공백), "al ice"와 "al  ice", 전각 "ａlice", "ſam"과 "sam", 소프트 하이픈이 든 이름은 `ErrAmbiguous`이며 `Identities`는 더 이상 둘 다 반환하지 않습니다(키는 표준 스키마가 정의한 속성의 동등 키이고 RFC 4518 준비를 따르며, 표준 스키마가 모르는 `UserAttribute`는 소문자 변환을 유지). 인증서는 URL의 호스트에 대해 검증됩니다(`tls.Config.ServerName`, 복사되며 바뀌지 않고 명시한 값이 여전히 우선하며), StartTLS도 함께 고쳐집니다. `Set.Identities`는 여전히 이름을 바이트 단위로 비교하며, 소스 사이에서는 그 이름을 아는 첫 소스가 가집니다. **업그레이드:** 이런 쌍이 있는 디렉터리는 항목 하나를 고칠 때까지 로드되지 않습니다 |
| directory v0.26.0 | **호환성 깨짐, 보안:** [`Set`은 이름을 하나의 동치 관계로 비교합니다]({{< relref "/libraries/directory.md" >}}). uid의 LDAP 동등 규칙(`caseIgnoreMatch`, RFC 4518 준비)이며, 소스 내부의 중복 검사, 소스 사이, `Members`, `Expand`에 모두 적용됩니다. 대소문자나 중요하지 않은 공백만 다른 이름은 한 사람입니다. **그 이름을 아는 첫 소스가 소유하고**, 나중의 표기는 가려져 제외되며(오류가 아닙니다), ID는 소유한 소스의 표기를 유지합니다. **`Set.Shadowed()`는** `Identities` 뒤에, 앞선 소스의 사람에게 가려진 나중의 표기를 각각 나열합니다(`Shadow{Name, Source, Owner, By}`). 두 소스에 같은 표기가 있는 것은 문서화된 재정의이며 나열되지 않습니다. 키가 없는 이름(UTF-8이 아니거나, 비었거나, 공백뿐인 이름)은 `ErrBadName`으로 거부됩니다. 이전에는 소스 사이에서 이름을 바이트 단위로 비교했습니다. **업그레이드:** 대소문자나 중요하지 않은 공백만 다른 이름의 두 사람이 소스에 있는 서버는 이제 나중 사람을 잃습니다. `Shadowed`를 읽으세요 |
| fido v0.6.4 | [권한이 있는 `PINToken`]({{< relref "/libraries/fido.md" >}})은 CTAP 2.1(§6.5.5)이 번호를 매기는 대로 `permissions`를 키 0x09로, `rpId`를 0x0A로 보냅니다. 이전에는 0x07과 0x08을 썼고, YubiKey 5는 `CTAP2_ERR_MISSING_PARAMETER`(0x14)로 응답했습니다 |
| fido cmd/fido v0.7.2 | 보안(낮음): 키가 제공하는 텍스트가 더 이상 터미널에 그대로 닿지 않습니다. 지문 템플릿 이름(`fingerprint list`), 키 이름(`name show`), USB 제품 또는 시리얼 문자열(`list`, 키 선택), 버전이나 옵션 이름(`info`), 그리고 이를 인용하는 오류 텍스트는 하나의 함수를 거치며, 이 함수는 제어 문자, ESC, CR, 양방향 문자와 그 밖의 서식 문자, 줄 구분자, 잘못된 UTF-8을 이스케이프로 씁니다. 출력 가능한 텍스트는 그대로입니다 |
| fido v0.14.0 | 보안: [`PINRetries`와 `UVRetries`]({{< relref "/libraries/fido.md" >}})는 음수 횟수를 거부합니다(CTAP 2.1 6.5.5.2와 6.5.5.3은 부호 없는 수로 정의합니다). `{PIN: -1}`은 `== 0` "차단됨" 검사를 "차단되지 않음"으로 통과하곤 했습니다. `CheckNewPIN`은 키가 제공한 최소값을 부호 없는 수로 비교하므로, 어떤 PIN도 충족할 수 없는 최소값(63 초과)은 사라지지 않고 모든 PIN을 거부합니다. 음수를 답하는 키는 이제 오류를 냅니다 |
| fido v0.15.0 | [`PINTokenBytes`, `SetPINBytes`, `ChangePINBytes`, `CheckNewPINBytes`]({{< relref "/libraries/fido.md" >}})는 PIN을 지울 수 있는 `[]byte`로 받습니다. 제자리에서 읽고 어디에도 보관하지 않으며, 도중에 만든 모든 복사본(다이제스트, 채워진 블록)은 지워집니다. 전송되는 요청은 `string` 형식과 동일합니다. `PINToken`, `SetPIN`, `ChangePIN`은 더 이상 권장되지 않으며 지우는 복사본을 거쳐 위임합니다. `NameTokens`는 PIN을 보관하므로 계속 `string`을 받습니다 |
| fido cmd/fido v0.7.3 | `pin set`, `pin change` 및 토큰이 필요한 모든 명령에서 읽은 PIN은 지울 수 없는 `string`으로 변환되는 대신 `[]byte`로 키에 전달되고([`PINTokenBytes`, `SetPINBytes`, `ChangePINBytes`]({{< relref "/libraries/fido.md" >}}), fido v0.15.0) 명령이 끝나면 지워집니다 |
| harden v0.1.0 | 첫 릴리스, 새 라이브러리: go-authn 저장소들이 각자 복사해 두었던 [보안 기본 요소 두 가지]({{< relref "/libraries/harden.md" >}})를 표준 라이브러리 외에는 의존성이 없는 하나의 모듈에 담았습니다. `redirect`: `CheckRedirect`, `HTTPSOrLoopback`, `Loopback`(oidc에서 가져왔으며, rp, awscred, saml, wireguard의 사본과 비교함). `privfile`: `Write`, 대상과 같은 디렉터리의 0600 임시 파일을 sync한 뒤 그 위로 이름을 바꾸며, 소유자만 쓸 수 있는 디렉터리에서만 동작합니다 |
| harden v0.2.0 | Windows의 `privfile.Write`는 임시 파일을 현재 계정에 대한 허용 항목 하나(`FILE_ALL_ACCESS`)만 든 보호된 접근 목록으로 만들며, 이는 생성 시 `CreateFile`이 지정하고 kinit v0.3.2와 같습니다. 이름을 바꿔도 유지됩니다. 이전에는 파일이 폴더의 접근 목록을 상속했습니다. 모듈은 이제 `golang.org/x/sys`를 요구합니다(Windows 빌드만 사용) |
| kdc v0.4.3 | 의존성만: 최소 요구 버전으로 go-authn/directory v0.12.0 |
| kdc v0.4.5 | 보안 감사, 퍼징, 카오스 실행([거부하는 것]({{< relref "/libraries/kdc.md" >}})): 다른 렐름에 대한 요청은 `KDC_ERR_WRONG_REALM`, 읽을 수 없는 디렉터리는 `KDC_ERR_SVC_UNAVAILABLE`로 응답하며(이전에는 `KDC_ERR_C_PRINCIPAL_UNKNOWN`), 시작이 `MaxSkew` 안의 미래인 TGT는 받아들이고, 디코더 패닉은 프로세스를 크래시시키는 대신 요청 하나를 버립니다(잘못된 AS-REQ나 TGS-REQ 하나로 크래시할 수 있었습니다). 프린시펄 이름은 로그에서 따옴표로 묶입니다. golang.org/x/net v0.62.0, go-authn/directory v0.16.1 |
| kdc v0.5.0 | MIT KDC의 [lookaside]({{< relref "/libraries/kdc.md" >}}): 바이트 단위로 이미 본 요청은 이전 응답을 받음(2분 동안, 합계 10 MiB 미만). `KRB-ERROR`는 저장하지 않음. MIT가 TGS에서 끄는 인증자 재전송 캐시는 일부러 두지 않음. 테스트는 읽을 수 없는 디렉터리가 AS(올바른 비밀번호로)와 TGS에서 `KDC_ERR_SVC_UNAVAILABLE`이 됨을 고정함. 요청당 할당 2회 증가 |
| kdc v0.6.0 | [`Finder`]({{< relref "/libraries/kdc.md#finder" >}}): 이름 색인을 가진 소스는 순회하지 않고 질의함. 10,000명일 때 순회가 AS-REQ CPU의 절반이었고, `Finder`가 있으면 조회는 프로파일 임계값 아래로 내려감. 이름이 프린시펄과 다른 응답은 알 수 없는 프린시펄로 처리함(프린시펄은 대소문자를 구분함) |
| kdc v0.7.0 | Windows 클라이언트의 TGS-REQ를 받아들임: 그 RSA-MD5 authenticator 체크섬은 MIT도 받아들임. 티켓과 응답 부분은 플래그와 starttime을 가짐 |
| kdc v0.8.0 | [`Mint`]({{< relref "/libraries/kdc.md" >}}): 키가 없는 사람의 TGT를, 상호 인증된 TLS를 통해 허용 목록의 호출자가 요청하고 KRB-CRED로 돌려받음(기본값은 꺼짐). TGS는 authenticator가 티켓과 다른 클라이언트를 지정하면 `KRB_AP_ERR_BADMATCH`로 응답함 |
| kdc v0.8.1 | additional-tickets 필드가 `[11] SEQUENCE`가 아닌 요청은 gokrb5가 디코딩하기 전에 버려짐(v8.4.4는 패닉했음). recover는 남아 있고, 퍼즈 테스트는 요청이 그곳에 도달하면 이제 실패함 |
| kdc v0.10.0 | 보안: [소스 주소당 최대 16개의 TCP 연결]({{< relref "/libraries/kdc.md" >}})(IPv6는 /64당)만 동시에 처리합니다. 전역 한도 256만 있을 때는 한 호스트가 유휴 연결 256개를 붙들어 다른 모두를 30초 동안 굶겼습니다. `Config.Services`와 README는 더 이상 서비스가 KDC와 같은 keytab을 읽는다고 말하지 않습니다. 그 파일에는 krbtgt 키와 모든 서비스의 키가 들어 있으며, 서비스는 자기 키만 든 keytab을 받습니다. **동작 변경:** 한 주소에서 동시 연결이 16개를 넘게 필요한 클라이언트는 16번째 이후로는 처리되지 않습니다 |
| kdcd v0.3.1 | 보안: [설정 파일의 소유자를 검사합니다]({{< relref "/libraries/kdcd.md" >}}). keytab과 비밀 파일은 이미 그랬습니다(root 또는 데몬이 실행되는 계정). 이전에는 모드만 검사했는데, 파일의 소유자는 검사 뒤에 다시 쓰기 가능하게 만들 수 있습니다. `dsn_file`은 더 이상 이름으로 두 번 읽지 않습니다(검사한 뒤 디렉터리 라이브러리가 다시 엽니다). 라이브러리에는 검사한 파일의 `/dev/fd/N`이 주어집니다(Windows는 이름을 유지). go-authn/kdc v0.10.0을 받으며, 소스 주소당 TCP 연결 16개 제한이 따라옵니다 |
| keyfactor v0.4.2 | 의존성만: 최소 요구 버전으로 go-authn/fido v0.6.2와 golang.org/x/crypto v0.58.0 |
| kinit v0.3.1 | 보안: `--cred-file`은 새 파일(`os.CreateTemp`, 0600)에 쓴 뒤 그 경로 위로 이름을 바꿉니다. 이전에는 `os.WriteFile`을 썼는데, 이는 기존 파일에 쓰면서 그 모드를 유지하고(0644 파일이 이후의 chmod 전까지 티켓을 담았습니다) 심볼릭 링크를 따라갑니다(티켓이 링크의 대상에 저장되었습니다). Windows에서 0600 모드는 읽기 전용 속성일 뿐이므로 `--cred-file`과 `keygen --out`은 폴더의 권한을 따릅니다. 계정만 열 수 있는 폴더를 쓰세요(코드에서 고치지 않았습니다) |
| kinit v0.3.2 | 수정: Windows에서 `--cred-file`과 `keygen --out` 개인 키는 현재 계정의 SID에 대한 허용 항목(`FILE_ALL_ACCESS`) 하나만 든 보호된 접근 목록으로 만들어지므로, 더 이상 폴더의 접근 목록을 받지 않습니다. 이 목록은 `CREATE_NEW`와 함께 `CreateFile`에 전달되므로 파일은 잠깐이라도 다른 누구에게도 읽히지 않으며, 이름을 바꾸기 전에 쓰는 임시 파일도 같은 방식으로 만듭니다. SYSTEM과 Administrators에는 항목이 없습니다. POSIX는 그대로입니다(0600, `O_EXCL`, `os.CreateTemp`) |
| kinit v0.3.3 | `--cred-file`은 [`harden/privfile`]({{< relref "/libraries/harden.md" >}}) v0.2.0이 씁니다(임시 파일, sync, 이름 바꾸기 코드와 Windows의 소유자 전용 접근 목록이 이 모듈에서 그쪽으로 옮겨졌으며, `keygen --out`은 자체 배타적 생성을 유지합니다). **동작 변경:** 심볼릭 링크이거나, 다른 사용자 소유이거나, 그룹이나 다른 사용자가 쓸 수 있는 디렉터리(예를 들어 `/tmp` 자체)는 이제 `--cred-file`에 거부됩니다. 그곳에서는 티켓이 바꿔치기될 수 있기 때문입니다 |
| krb5 v0.3.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| krb5 v0.3.3 | 의존성만: golang.org/x/net v0.62.0, golang.org/x/crypto v0.58.0, go-uuid v1.0.4로 요구하지만 호출되지 않는 모듈에서 `govulncheck` 결과 46건 중 45건이 해소됩니다. GO-2026-5932(`x/crypto/openpgp`)는 수정이 없고 어떤 go-authn 모듈도 가져오지 않습니다. API 변경 없음 |
| krb5 v0.4.1 | 보안, [`Principal` 옵션]({{< relref "/libraries/krb5.md" >}})으로 만든 acceptor 대상: `Accept`는 평문 서비스 이름이 설정된 프린시펄과 다른 티켓을 gokrb5가 보기 전에 거부합니다(평문 서비스 이름이 빈 티켓은 `Accept`가 gokrb5 안에서 패닉하게 했고, 평문 이름을 다시 쓰면 gokrb5의 재전송 캐시가 무력화되었습니다). gokrb5의 패닉은 복구하여 거부로 응답합니다. `Principal`이 없는 acceptor는 그대로입니다 |
| krb5 v0.5.0 | **호환성 깨짐, 보안:** [재생 캐시가 이 패키지 자체의 것입니다]({{< relref "/libraries/krb5.md" >}}). acceptor마다 있으며 gokrb5의 프로세스 전역 캐시를 대체합니다. 그 캐시는 영역 없이 클라이언트 이름으로 키를 만들었고(alice@A와 alice@B가 같은 마이크로초에 충돌했습니다), 확인과 추가를 따로 잠근 두 단계로 했으며(한 AP-REQ의 동시 사본 24개 중 2개가 수락되었습니다), 인증자마다 항목을 하나씩 한없이 보관했습니다. 새 캐시는 하나의 임계 구역에서 결정하고, 영역, 클라이언트, 서비스, 시각으로 키를 만들며, 한도가 있고(전체와 클라이언트당, 가득 차면 거부) 시계 오차의 두 배가 지나면 잊습니다. 새 옵션 `ReplayCacheSize(n)`, 기본값 65536. 티켓 발급 티켓(평문 sname `krbtgt/...`)은 서비스 티켓으로 거부됩니다. KDC와 공유하는 keytab에는 krbtgt 키가 들어 있기 때문입니다. 수락되던 동작이 이제 거부됩니다 |
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
| ldap v0.12.1 | [bind는 진행 중인 페이지 검색을 중단합니다]({{< relref "/libraries/ldap.md" >}})(RFC 4511 4.2.1): 한 사람이 시작한 검색은 연결이 익명이거나 다른 사람의 것이 된 뒤에는 결과를 계속 전달하지 않습니다 |
| ldap v0.12.2 | `Validate`의 중복 값 검사는 모든 쌍을 비교하는 대신 키로 같은 값을 찾습니다. `member` DN 50개짜리 `groupOfNames`는 14,907회·959 KB 대신 1,065회·68 KB의 할당을 합니다(정확한 값). 결과는 무작위 목록으로 비교한 쌍별 검사와 같습니다 |
| ldap v0.12.3 | 단순한 DN(`type=value` RDN, 출력 가능한 ASCII, 이스케이프 없음)은 바이트에서 직접 17회 대신 1회의 할당으로 키를 얻고, 그 밖의 DN은 전체 파싱을 거칩니다. 50개짜리 그룹당 265회의 할당. 키는 전체 파싱의 것과 같으며 차분 테스트와 퍼저(3,900만 회 실행)로 보장합니다 |
| ldap v0.14.0 | 보안, [클라이언트]({{< relref "/libraries/ldap.md" >}}): **`StartTLS`가 URL의 호스트를 검증합니다**. 이전에는 `RemoteAddr`의 피어 IP 주소에 대해 인증서를 검증했습니다(`ldaps://`는 맞았습니다). `Dial`은 URL의 호스트를 유지하고 `StartTLS`가 그것을 지명하며, 명시한 `tls.Config.ServerName`이 여전히 우선하고, `NewClientConn`으로 만든 `ClientConn`은 URL이 없으므로 피어 주소를 계속 검증합니다. **TLS 핸드셰이크에 한도가 있습니다**: 최대 다이얼러의 타임아웃(기본 30초)까지 걸리며 `DialOptions.Timeout`을 넘지 않습니다(`ldaps://`와 `StartTLS` 모두). **검색 참조를 셉니다**: 연속 참조와 중간 응답이 그 검색의 `ClientLimits.MaxEntries`에 계산됩니다. 추가: `schema.Schema.EqualityKey`, 속성 타입의 두 값이 `Equal`이 참일 때에 한해 같은 키를 갖는 값당 하나의 키이므로, 맵으로 한 번에 중복을 찾을 수 있습니다 |
| ldap v0.15.0 | 보안: [서버는 이름은 있고 비밀번호가 빈 단순 bind에]({{< relref "/libraries/ldap.md" >}}) 스스로 unwillingToPerform으로 응답하며 `Binder`에게 묻지 않습니다(RFC 4513 5.1.2: 인증되지 않은 메커니즘이며, 그 이름은 인가에 쓰면 안 됩니다). 이전에는 Success로 답하는 `Binder`가 연결을 그 이름으로 bind했습니다. 익명 bind(이름도 비밀번호도 없음)와 비밀번호가 있는 bind는 그대로입니다. **업그레이드:** 인증되지 않은 bind를 `Binder`가 받아 주는 데 의존하던 배포는 그것을 멈춰야 합니다 |
| oidc v0.4.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| oidc v0.6.1 | [`ScopedName`]({{< relref "/libraries/oidc.md#scoped-names" >}})은 `@`가 둘 이상인 이름을 거부합니다(`ErrBadName`) |
| oidc v0.7.0 | [`ASCIILower`와 `EqualASCIIFold`]({{< relref "/libraries/oidc.md#scoped-names" >}}): 이름을 위한 ASCII 전용의 유일한 접기입니다. `strings.ToLower`와 `strings.EqualFold`는 유니코드를 접어서 켈빈 기호 U+212A를 "k"와 같게 보기 때문입니다 |
| oidc v0.8.0 | **호환성 깨짐, 보안:** [ES256, ES384, ES512는 각각 P-256, P-384, P-521의 키로만 검증합니다]({{< relref "/libraries/oidc.md" >}})(RFC 7518 §3.4. ES256은 서명 길이가 그 곡선의 길이이면 P-384나 P-521 키로도 검증하곤 했습니다). JWK의 `alg`를 존중하므로(RFC 7517 §4.4) RS256용으로 게시된 키는 더 이상 RS512나 PS256 토큰을 검증하지 않습니다(`alg`가 없는 키는 그대로). `PeekIssuer`는 클레임 `iss`를 정확히 읽습니다(`encoding/json`은 대소문자를 접으므로 페이로드 `{"ISS": ...}`가 다른 발급자의 검증기로 보내지곤 했습니다). **업그레이드:** `alg`에 맞지 않는 곡선의 키로 서명하거나 잘못된 `alg`를 게시하는 발급자는 이제 거부됩니다 |
| oidc v0.8.1 | https나 루프백 규칙과 리디렉션 정책은 rp, awscred, saml, wireguard와 공유하는 [`harden/redirect`]({{< relref "/libraries/harden.md" >}})에서 옵니다. 이전보다 엄격합니다. 호스트가 없는 `https:///x` URL은 거부되고, `LOCALHOST`와 `localhost.`는 루프백이며, IPv6 존은 루프백이 아닙니다. 오류는 URL 전체(비밀이 들어 있을 수 있음)가 아니라 스킴과 호스트를 알려 줍니다. 빈 레이블이 있는 `.localhost`는 더 이상 루프백이 아닙니다 |
| revocation v0.7.1 | 보안: `VerifyCRL`은 발급자가 critical로 표시했든 아니든 issuingDistributionPoint 확장이 있는 CRL을 거부합니다. RFC 5280 5.2.5: 이 확장은 CRL의 범위를 정하며(파티션, 사용자 인증서만 등), 이를 지원하지 않는 리더는 목록에 없는 인증서를 알 수 없음으로 취급해야 합니다. critical이 아닌 확장은 완전한 목록으로 읽혔습니다 |
| revocation v0.7.2 | `authn-revokd`는 상태 파일을 [`harden/privfile`]({{< relref "/libraries/harden.md" >}})로 씁니다(같은 0600 임시 파일, sync, 이름 바꾸기이며, 이제 wireguard, kinit, secretsource와 공유). 또한 심볼릭 링크이거나, 다른 사용자 소유이거나, 그룹이나 다른 사용자가 쓸 수 있는 상태 디렉터리를 시작할 때만이 아니라 쓰는 순간에도 거부합니다. 게시되는 목록은 의도적으로 0644로 남습니다 |
| rp v0.4.1 | `Discover`는 리디렉션 뒤에 평문으로 온 문서를 거부합니다. `go` 지시문은 1.27.4입니다(GO-2026-6859). 야간 워크플로가 모든 타깃을 퍼징합니다 |
| rp v0.5.0 | 보안: 루프백 흐름에서 `open`은 루프백 리스너의 일회용 링크를 받으며, 이 링크가 인증 URL로 한 번 리디렉션하므로 state, nonce, PKCE 챌린지가 더 이상 `open` / `xdg-open`의 인수에 들어 있지 않습니다. 인수는 로컬 사용자라면 누구나 읽을 수 있습니다. `VerifyID`는 이 클라이언트의 것이 아닌 `azp` 클레임을, 대상이 하나일 때도 여럿일 때도 거부합니다(OIDC Core §3.1.3.7). HTTP 클라이언트가 없는 직접 만든 `Provider`는 패닉하는 대신 `http.DefaultClient`를 씁니다. `Error.Error()`는 공급자의 `error`와 `error_description`에서 제어 문자를 지우고 각각 256 룬에서 자릅니다. **업그레이드:** `open` 함수가 받은 URL을 검사하는 호출자는 이제 일회용 링크를 보게 됩니다 |
| rp v0.5.1 | https나 루프백 규칙은 oidc, awscred, saml, wireguard와 공유하는 [`harden/redirect`]({{< relref "/libraries/harden.md" >}})에서 옵니다. 이제 루프백에는 `*.localhost`도 포함되며, 대소문자와 끝의 점은 가리지 않습니다. IPv6 존은 거부되고, 오류는 URL 전체(비밀이 들어 있을 수 있음)가 아니라 스킴과 호스트를 알려 줍니다. 토큰 엔드포인트에서 모든 리디렉션을 거부하는 것은 그대로입니다 |
| saml v0.6.0 | [`schacHomeOrganization`은 IdP의 `shibmd:Scope` 값으로 제한되며]({{< relref "/libraries/saml.md" >}}) (정확히 일치, 대소문자 구분) 그렇지 않으면 버려집니다. `eduPersonPrincipalName`, `subject-id`, `pairwise-id`, 스코프 소속이 이미 그랬던 것과 같습니다(SWITCH와 SAFIRE의 속성 페이지가 신뢰 당사자에게 요구합니다). **업그레이드:** 메타데이터가 도메인의 Scope를 게시하지 않는 IdP의 속성은 더 이상 읽히지 않습니다 |
| saml v0.6.1 | [퍼즈 타깃 네 개와 적대적 입력 테스트]({{< relref "/libraries/saml.md#fuzzing" >}}): `FuzzAccept`, `FuzzParseMetadata`, `FuzzDecrypt`, `FuzzLimits`. 코퍼스는 커밋되어 `go test`가 다시 실행하며, 각각 110만에서 510만 번 실행했으나 충돌, 멈춤, 속성 위반이 없었습니다. billion-laughs 폭탄, 외부 엔티티, 80,000단계와 1,048,576단계의 중첩, 형제 60,000개, 너무 큰 `CipherValue`와 응답은 많아야 4~8 MiB를 할당하고 거부됩니다. `fuzz` 작업이 CI에서 각 타깃을 30초씩 실행합니다. 동작 변경 없음 |
| saml v0.7.0 | [`samltest`]({{< relref "/libraries/saml.md#samltest" >}})가 IdP가 보낼 수 있는 것을 더 많이 쓰게 되어, 프로그램의 테스트가 이 응답을 만들 때 xmlsec1이 필요 없어짐: `Assertion.Status`(최상위 코드가 Success가 아니면 어서션이 없음, 예: 거부된 패시브 로그인), `NameID` 문자열 대신 NameID의 형식과 한정자를 담는 `Assertion.Subject`, `Now`와 따로인 `Assertion.AuthnInstant`, `Attribute.NameIDs`(eduPersonTargetedID). 영값은 v0.6.1이 쓰던 것을 씀 |
| saml v0.7.1 | 보안: [`Federation`]({{< relref "/libraries/saml.md" >}})이 `127.`로 시작하는 모든 DNS 이름(`127.evil.example`)을 루프백으로 취급했고, 그 때문에 평문 http로 메타데이터를 가져오고 https에서 http로의 리디렉션을 그런 호스트로 따라갔습니다. 이제 루프백은 `localhost`이거나 루프백인 IP 리터럴(`127.0.0.0/8`, `::1`)입니다 |
| saml v0.7.2 | 보안: [서명 알고리즘 허용 목록]({{< relref "/libraries/saml.md" >}})은 Response나 Assertion의 직접 자식 `ds:Signature`만 보았는데, 검증기는 문서 순서에서 그 요소를 참조하는 첫 서명을 깊이에 상관없이 취합니다. `<Extensions>` 아래에 중첩된 SHA-1 서명이 허용된 미끼 서명 옆에서 통과했습니다. 검증 대상 요소를 참조하면서 그 직접 자식이 아닌 서명은 이제 거부됩니다(Response 안의 Assertion에 있는 서명은 영향이 없고, Response와 그 Assertion이 모두 RSA-SHA256으로 서명된 경우는 계속 수락됩니다). Response의 재생 캐시 항목은 이제 첫 bearer 확인의 `NotOnOrAfter`가 아니라 시계 오차를 포함해 그 Response가 수락될 수 있는 동안 유지됩니다. 더 늦은 기한이 있으면 항목이 밀려난 뒤 같은 Response가 다시 전달될 수 있었습니다. 규격을 따르는 IdP는 영향이 없습니다 |
| saml v0.7.3 | `Federation`의 루프백 규칙과 리디렉션 정책은 oidc, rp, awscred, wireguard와 공유하는 [`harden/redirect`]({{< relref "/libraries/harden.md" >}})에서 옵니다. 이제 루프백에는 `*.localhost`도 포함되며, 대소문자와 끝의 점은 가리지 않습니다. `::1%eth0` 같은 IPv6 존은 더 이상 루프백이 아니며, 리디렉션 오류는 스킴과 호스트만 알려 줍니다 |
| scim v0.2.0 | [감사, 퍼징, 카오스, 성능 실행]({{< relref "/libraries/scim.md#v020" >}}): `Server.ReadTimeout`(30초), 선택 인터페이스 `ConditionalDeleter`, `If-Match` 없는 PATCH나 PUT은 진 경합에서 412 대신 최대 32번 다시 수행, 아무것도 일치하지 않는 필터로의 제거는 성공, 경로 없는 PATCH의 키는 정렬된 순서로 적용, `BearerAuth`는 스킴을 대소문자 구분 없이 받아들임, `startIndex`와 `count`는 워드 크기와 상관없이 상한으로 잘림. 사용자 10,000명에 대한 목록 요청: 100개 페이지는 789,417회에서 14,952회로, `userName eq`는 797,979회에서 90회로, 전체 훑기는 818,847회에서 361,098회로(정확. 시간은 측정하지 않음, 부하 65) |
| scim v0.2.1 | [RFC 7232 §3.2에 따른 `If-None-Match`]({{< relref "/libraries/scim.md#v021" >}}): 엔티티 태그 목록, `*`, 약한 비교, 그리고 304가 `ETag`를 담음. `Memory`는 색인으로 `userName` 고유성을 확인함(사용자 N명을 불러오는 데 `EqualFold` 호출이 O(N^2) 대신 O(N)). 어떤 색인도 답하지 못하는 목록 필터는 그것이 지명하는 최상위 속성에서 일치를 검사함: 사용자 10,000명에서 요청당 할당 361,095회가 162,695회로, 사용자당 36.1회가 16.3회로(정확) |
| scim v0.3.0 | 보안: [`userName` 유사 문자열은 하나의 이름입니다]({{< relref "/libraries/scim.md#v030" >}}). `"alice "`, `" alice"`, U+200B, U+202E 또는 소프트 하이픈이 든 이름, 전각 `ａlice`는 모두 `alice` 옆에 생성되었는데(201), 고유성이 `strings.EqualFold`뿐이었고 제어 문자(Cc)만 거부되었기 때문입니다. `userName`은 이제 서식 문자(Cf)를 어디서든, 공백을 양 끝에서 거부하며(400 `invalidValue`), `Memory`는 고유성(생성, 이름 변경, `userName eq` 좁히기)을 NFKC와 대소문자 접기로 비교하므로 호환 변형과 조합형·분해형 표기는 하나의 이름입니다(409). **업그레이드:** 앞이나 뒤에 공백이 있거나, 폭 없는 연결자나 비연결자 또는 다른 Cf 문자(일부 페르시아어와 인도 계통 이름이 사용함)가 든 `userName`을 보내는 클라이언트는 이제 400을 받습니다. 그런 이름으로 이미 저장된 사용자는 읽을 수 있지만 이름을 정리하지 않으면 다시 저장할 수 없습니다. 사용자 정의 `Backend`는 고유성 검사에 같은 NFKC와 접기를 적용해야 하며, 모듈은 이제 `golang.org/x/text`(unicode/norm)에 의존합니다 |
| scim v0.4.0 | 보안: [`attributes`와 `excludedAttributes`에 한도가 있습니다]({{< relref "/libraries/scim.md" >}}). 경로가 64개를 넘으면 거부되며(400 `invalidValue`), 목록, `POST /.search`, 단일 리소스 모두에 적용됩니다. 속성 하나를 수만 번 지명한 1 MiB 본문은 요청마다 한 페이지 분량의 파싱 비용을 냈습니다. **업그레이드:** 경로를 64개보다 많이 보낸 클라이언트는 400을 받습니다 |
| secretsource v0.6.0 | 보안 감사: [파일이 빈 `file:` 참조]({{< relref "/libraries/secretsource.md" >}})(또는 줄 끝만 든 파일)는 빈 비밀을 반환하는 대신 다른 모든 백엔드처럼 `ErrEmpty`로 실패합니다(잘린 비밀번호 파일이 빈 PIN이 되곤 했습니다). FIFO의 `file:`은 더 이상 컨텍스트를 넘어 막히지 않습니다(`O_NONBLOCK`으로 열고 일반 파일이 아니라며 거부). Unix의 `keepassxc:`는 소켓이 심볼릭 링크이거나 그 디렉터리가 다른 사용자 소유이거나 그룹이나 다른 사용자가 쓸 수 있으면 거부되고, 연결된 피어의 uid를 다이얼 뒤에 확인하며(macOS와 Linux), 레거시 `$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` 심볼릭 링크는 더 이상 따라가지 않습니다(`app/org.keepassxc.KeePassXC/` 아래의 실제 소켓은 따라갑니다). **업그레이드:** 빈 파일이 "비밀 없음"을 뜻한다고 의존하던 호출자는 `ErrEmpty`를 처리해야 합니다 |
| secretsource v0.6.1 | 보안: `keepassxc:`의 연결 파일(macOS 키체인도 Secret Service도 없을 때 쓰는 대체 저장소)은 같은 디렉터리의 새 임시 파일에 쓴 뒤 최종 이름으로 이름을 바꾸므로, 그 이름에 남아 있던 심볼릭 링크는 따라가지 않고 교체되며, 더 느슨한 모드의 파일은 0600이 됩니다. Unix에서는 소켓의 디렉터리처럼 디렉터리를 먼저 검사합니다. 이 사용자 소유여야 하고, 그룹이나 다른 사용자가 쓸 수 없어야 하며, 심볼릭 링크가 아니어야 합니다. 그렇지 않으면 아무것도 쓰지 않습니다. API 변경은 없습니다. **업그레이드:** v0.6.1로 업데이트하세요. 연결 디렉터리가 비공개가 아니면 키를 더 이상 그곳에 쓰지 않습니다 |
| secretsource v0.7.0 | [`file:`이 Windows에서 동작합니다]({{< relref "/libraries/secretsource.md" >}}): 지금까지 Windows에서는 Go 런타임이 꾸며 낸 모드 0666을 보고하기 때문에 항상 거부되었습니다. 대신 열린 파일의 액세스 목록을 읽어, 소유자, SYSTEM, Administrators 그룹 외의 누군가에게 읽기, 쓰기, 추가, 삭제, 소유권 권한을 주는 항목이 있거나, 목록이 null이거나, 항목을 읽을 수 없으면 거부합니다. 거부 항목은 무시되며, 이는 거부를 늘릴 수만 있습니다. Unix는 달라지지 않습니다 |
| secretsource v0.8.0 | 새 스킴 [`systemd-creds:NAME`]({{< relref "/libraries/secretsource.md#systemd-creds" >}})(Linux): systemd 자격 증명을 `$CREDENTIALS_DIRECTORY/NAME`에서 읽고, 없으면 `credstore.encrypted` 디렉터리에서 `systemd-creds decrypt`로 복호화하므로 비밀을 평문으로 디스크에 쓸 필요가 전혀 없습니다. 바이너리 안전: `file:`과 달리 바이트가 저장된 그대로 돌아오며 끝의 줄바꿈을 지우지 않습니다. 복호화에 실패하면 자격 증명을 다시 봉인해야 할 수 있다고 알려 줍니다. `NAME`은 검증되며(`/`, `.`, `..`, NUL, 제어 문자 없음, 최대 255바이트) 퍼징됩니다. TPM2 키가 아니라 `--with-key=host`를 쓴 systemd 257에서 측정했습니다 |
| secretsource v0.8.1 | KeePassXC 연결 파일은 [`harden/privfile`]({{< relref "/libraries/harden.md" >}}) v0.2.0이 씁니다(임시 파일, sync, 이름 바꾸기가 그쪽으로 옮겨짐). Windows에서는 이제 파일이 kinit v0.3.2처럼 소유자 전용 보호된 접근 목록을 받으며, 디렉터리는 쓰기 전은 물론 쓰는 순간에도 다시 검사됩니다 |
| servercert v0.5.2 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| servercert v0.6.0 | [TLS `KeyFile`과 ACME `EABHMACKeyFile`은 거부됩니다]({{< relref "/libraries/servercert.md" >}}). 그룹이나 다른 사용자가 읽거나 쓸 수 있는 경우이며, `New` 시점과 매번 다시 불러올 때 확인합니다(읽을 수 있는 교체 키는 `OnError`로 보고되고 사용되지 않으며, 현재 인증서가 계속 제공됩니다). Windows에서는 확인하지 않습니다. **업그레이드:** 두 파일 모두 `chmod 600` |
| servercert v0.7.1 | 보안: [dns-01은 주문하지 않은 이름에 대한 승인을 거부합니다]({{< relref "/libraries/servercert.md" >}}). TXT 레코드 이름은 CA 승인의 식별자로 만들어졌고 주문한 도메인과 비교된 적이 없어서(RFC 8555 7.1.4), CA가 고른 이름이 DNS 솔버에 도달했습니다. `present`는 이제 게시하기 전에, dns 식별자가 아니거나 (값, 와일드카드) 쌍이 주문한 이름이 아닌 승인을 거부합니다. `go` 지시어는 1.27.4(GO-2026-6859)입니다 |
| totp v0.4.2 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| totp v0.4.4 | `Verifier`가 매 시도 전에 유휴 이름을 정리합니다. go-authn/mfa v0.5.1, `go` 지시문은 1.27.4입니다(GO-2026-6859) |
| webauthn v0.1.1 | `VerifyAssertion`은 두 카운터 중 하나라도 0이 아니면 signCount 0을 거부합니다 |
| webauthn v0.2.0 | **호환성 깨짐, 보안:** 등록은 위수가 작은 점인 Ed25519 공개 키(위수가 8을 나누는 여덟 점)를 거부합니다. 그런 ID는 어떤 메시지에 대해서도 R = identity, S = 0을 검증하므로 그런 키 뒤에는 비밀이 없습니다. `coseKey.verify`는 검증기가 없는 키 유형에서 닫힌 채로 실패합니다(`ErrKey`). 그런 키를 등록했던 자격 증명은 영향을 받습니다 |
| wireguard v0.1.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| wireguard v0.1.4 | 소스의 토큰 요청과 목록 요청은 Basic 시크릿이나 Bearer 토큰을 싣고 있으므로 더 이상 리디렉션을 따르지 않습니다. 리디렉션은 오류입니다([거부하는 것]({{< relref "/libraries/wireguard.md" >}})) |
| wireguard v0.2.0 | 보안: [`SourceConfig.FloorFile`]({{< relref "/libraries/wireguard.md" >}})은 가장 최신 목록의 위치(버전과 발급 시각)를 재시작 사이에도 유지합니다. 이전에는 하한이 메모리에만 있어서, 재시작한 게이트웨이가 여전히 서명되었고 만료되지 않은 재생된 이전 목록을 첫 목록으로 받아들였습니다. 하한과 버전이 같지만 더 일찍 발급된 목록도 거부됩니다. 새로 추가: `Floor`, `ParseFloor`, `(*Source).Floor`, `ErrFloorNotKept`(파일을 쓸 수 없을 때 올바른 목록과 함께 반환). `FloorFile`이 없으면 같은 버전 검사 외에는 아무것도 바뀌지 않습니다 |
| wireguard v0.2.1 | `FloorFile`은 [`harden/privfile`]({{< relref "/libraries/harden.md" >}})이 씁니다. 모드는 0600이며(이전에는 명시적 모드가 없었음), 심볼릭 링크이거나, 다른 사용자 소유이거나, 그룹이나 다른 사용자가 쓸 수 있는 상태 디렉터리는 거부됩니다(그러면 하한이 유지되지 않으며 `ErrFloorNotKept`). **업그레이드:** 그룹이 쓸 수 있는 상태 디렉터리를 쓰는 배포는 권한을 좁혀야 합니다 |

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
