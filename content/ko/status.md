---
title: "상태"
weight: 60
description: "이 문서가 설명하는 릴리스, 각 릴리스에서 추가된 것, 그리고 아직 구현되지 않은 것."
tags: [상태, 릴리스]
---

이 문서는 문서 버전 **0.5**이며 다음을 설명합니다.

| 프로그램 | 릴리스 | 모듈 |
|---|---|---|
| authnd | **v0.12.4** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.4** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.6** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

라이브러리의 버전은 [해당 페이지]({{< relref "/libraries/_index.md" >}})에
있습니다. ldap은 빌드되지 않는 스키마를 위한 타입이 있는 `BuildError`, HCL2
스키마, `ldapschema` 변환기를 갖춘 **v0.10.2**이고,
directory는 선언된 오브젝트 클래스를 갖춘 **v0.15.0**입니다. authnd
v0.12.4은 ldap v0.10.2과 directory v0.15.0을 내장합니다.
위 프로그램 중 어느 것이든 새 마이너 버전이 나오면 새 문서 버전이 됩니다. 따라서
독자가 `/docs/0.5/`에서 찾는 페이지는 설치한 것을 계속 설명하며, 이전 릴리스의
페이지는 `/docs/0.1/`, `/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/`에 남아 있습니다.

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
| kdc v0.4.3 | 의존성만: 최소 요구 버전으로 go-authn/directory v0.12.0 |
| keyfactor v0.4.2 | 의존성만: 최소 요구 버전으로 go-authn/fido v0.6.2와 golang.org/x/crypto v0.58.0 |
| krb5 v0.3.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
| krl v0.6.1 | 의존성만: golang.org/x/crypto v0.58.0, Go 1.27.2로 테스트함 |
| ldap v0.8.0 | [`schema` 패키지]({{< relref "/libraries/ldap.md#the-schema" >}})와 `Server.Schema`: `cn=Subschema`(RFC 4512 §4.2), `Validate`, RFC 4517 매칭 규칙, `uidNumber`와 `gidNumber`는 정수로 정렬됨, 페이지 검색이 요청된 속성만 유지함 |
| ldap v0.9.0 | [HCL2 스키마]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): `schema/hclschema` 패키지와 OpenLDAP `.schema`, cn=config LDIF, HCL2 사이를 변환하는 `ldapschema` 명령(`to-hcl`, `to-schema`, `check`), 리더는 slapd처럼 파일을 읽음, DIT 콘텐츠와 구조 규칙, 이름 형식, `include`, `X-SUBST`는 지원되지 않음 |
| ldap v0.10.0 | `Build`가 거부하는 정의에 대한 [타입이 있는 `*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}), `errors.As`로 확인: `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos`(정의가 시작되는 file:line:column, 접힌 또는 base64 LDIF와 HCL도 포함), 다른 정의를 위한 `Ref`, `RefOID`, `RefPos`. 읽은 모든 정의가 `Pos`를 가짐. 메시지의 "object classes" |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}})가 이어짐 줄 수에 선형이 됨(이전에는 제곱 시간이어서 4 MiB 파일에 약 3분이 걸렸음). 첫 줄을 읽으려고 파일 전체를 복사하고 나누지도 않음. `schema.Format`은 2000바이트가 넘는 줄(slapd와 `Read`는 거부함)을 접음. 엄격한 파서가 약 2.6배 빠름(`cosine.schema`에서 할당 498회가 147회, 부하 상태에서 측정) |
| ldap v0.10.2 | 내장 스키마(`schema.Standard()`)의 RFC 2307 정의 13개의 DESC 가 한 줄로 바뀌었습니다. RFC 쪽 나눔의 들여쓰기가 들어 있었고, 리더는 slapd 처럼 따옴표 안에서 이를 유지하므로 서버가 게시한 서브스키마에 연속된 공백이 있었습니다. 이제 테스트가 내장된 모든 DESC 를 이 점에서 검사하고, 같은 OID 가 정의된 곳에서는 OpenLDAP 의 `core`, `cosine`, `inetorgperson`, `nis` 스키마와 비교합니다 |
| oidc v0.4.1 | Go 1.27.2로 테스트함, 코드도 `go.mod`도 바뀌지 않음 |
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
