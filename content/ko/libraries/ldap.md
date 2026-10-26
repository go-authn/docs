---
title: "ldap — LDAP 서버의 바이트"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap은 서버 라이브러리로서의 LDAP 프로토콜입니다: 와이어, 필터, 작업과 그 한계, 그리고 무엇에 응답할지 결정하는 핸들러."
tags: [라이브러리, ldap, 디렉터리]
---

**LDAP 서버의 바이트는 무엇인가?** 데몬이 아니라 라이브러리입니다. 와이어, 필터,
작업. [authnd]({{< relref "/authnd/_index.md" >}})는 이를 실행하고 구성, 디렉터리 소스,
바인드 정책을 소유하는 서버이며, 이 라이브러리는 바이트를 소유합니다.

```sh
go get github.com/go-authn/ldap@v0.11.0
```

RFC 4511(프로토콜), 4512(루트 DSE와 스키마), 4513(인증), 4514와 4515(DN과 필터 문자열
형식), 4517과 4518(구문, 매칭 규칙, 문자열 준비), 4526, 2696(페이지 결과), 3672
(서브엔트리), 3673, 4527(읽기 엔트리 컨트롤), 4532(whoami), 3045로부터 작성되었습니다.

`Server`는 핸들러의 집합이며 각각이 선택적 필드입니다. `Bind`, `SASL`, `Search`,
`Compare`, `Extended`, `Add`, `Modify`, `Delete`, `ModifyDN`, `Abandon`. nil인 것은
*이 서버는 그것을 하지 않음*을 뜻하며, 그 작업은 `unwillingToPerform`으로 응답합니다.
존재하지 않는 권한에 대한 논쟁을 시작하게 할 `insufficientAccessRights`가 아닙니다.
루트 DSE는 서버 자신이 응답하며, 서버가 인정하는 것을 정확히 게시합니다.

## 예제 {#example}

바인드할 수 있는 사람 한 명과, 필터와 일치하는 것을 기록하는 검색이 있는 서버:

```go
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"log/slog"
	"os"

	"github.com/go-authn/ldap"
)

var people = []*ldap.Entry{
	{DN: "uid=dora,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "dora")}},
	{DN: "uid=svc-web-prod,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-prod")}},
	{DN: "uid=svc-web-stage,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-stage")}},
}

// binder checks one password. A real one asks a directory: see go-authn/directory.
type binder struct{}

func (binder) Bind(_ context.Context, _ ldap.Session, req *ldap.BindRequest) (ldap.Result, error) {
	if req.Name == "" && len(req.Simple) == 0 {
		return ldap.Result{Code: ldap.Success}, nil // anonymous: the connection stays unbound
	}
	// A name with an empty password is an UNAUTHENTICATED bind (RFC 4513
	// 5.1.2). This package hands it to the handler, and the handler refuses it:
	// the comparison below does, since the password is never empty.
	ok := ldap.EqualDN(req.Name, "uid=dora,ou=people,dc=example,dc=org") &&
		subtle.ConstantTimeCompare(req.Simple, []byte("hunter2")) == 1
	if !ok {
		return ldap.Refuse(ldap.InvalidCredentials, "invalid credentials"), nil
	}
	return ldap.Result{Code: ldap.Success}, nil
}

// searcher writes each entry in scope that the filter matches, as it finds it.
type searcher struct{}

func (searcher) Search(_ context.Context, s ldap.Session, req *ldap.SearchRequest, w ldap.EntryWriter) (ldap.Result, error) {
	if s.BoundDN() == "" {
		return ldap.Refuse(ldap.InsufficientAccessRights, "bind first"), nil
	}
	for _, e := range people {
		if ldap.InScope(e.DN, req.BaseObject, req.Scope) && req.Filter.Matches(e) {
			if err := w.Entry(e); err != nil {
				return ldap.Result{}, err // the client went away, or a limit was reached
			}
		}
	}
	return ldap.Result{Code: ldap.Success}, nil
}

func main() {
	srv := &ldap.Server{
		Bind:           binder{},
		Search:         searcher{},
		NamingContexts: []string{"dc=example,dc=org"},
		Log:            slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// On anything but loopback: TLSConfig, and RequireTLS so that a
		// client that never asks for StartTLS is refused rather than
		// sending its password in the clear.
	}
	log.Fatal(srv.ListenAndServe("127.0.0.1:3389"))
}
```

dora의 비밀번호를 파일에 넣고 OpenLDAP의 `ldapsearch`(macOS가 제공하는 2.4.28)로
요청한 결과입니다.

```
$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw \
    -b ou=people,dc=example,dc=org '(uid=svc-*-prod)' uid
dn: uid=svc-web-prod,ou=people,dc=example,dc=org
uid: svc-web-prod

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -b ou=people,dc=example,dc=org '(uid=*)' uid
Insufficient access (50)
Additional information: bind first

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -s base -b '' namingContexts supportedLDAPVersion supportedExtension
dn:
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3

$ printf 'dn: uid=dora,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: uid\nuid: x\n' |
    ldapmodify -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw
ldap_modify: Server is unwilling to perform (53)
	additional info: this server does not modify entries
modifying entry "uid=dora,ou=people,dc=example,dc=org"
```

`(uid=svc-*-prod)`는 `svc-web-prod`를 반환하며 `svc-web-stage`는 반환하지 않습니다.
이 라이브러리가 대체하는 라이브러리는 그 필터를 `(uid=svc-*)`로 평가하여
`svc-web-stage`도 반환했으며, 그 결함이 이 라이브러리가 작성된 이유입니다. `TLSConfig`가
주어지지 않았으므로 루트 DSE는 StartTLS를 나열하지 않습니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

**필터는 한 가지 의미만 갖습니다.** 한 번 트리로 구문 분석 또는 디코딩되며, `String`,
`EncodeFilter`, `Matches`가 모두 그 트리를 읽습니다. RFC 4512 §2.5 속성 설명이 아닌
속성이나 OID가 아닌 매칭 규칙은 `ParseFilter`와 `DecodeFilter` 모두 거부합니다.
v0.6.1 이전에는 속성 `!x`에 대한 "present" 필터가 다시 출력되면 NOT으로 읽혔습니다.

**다르게 약속했는데 평문인 경우.** StartTLS는 *클라이언트*가 요청하는 것이므로, 단지
제공하기만 하는 서버는 아무것도 약속한 것이 아닙니다. `RequireTLS`는 보호되지 않은
연결의 모든 작업을 `confidentialityRequired`로 거부합니다.

**실패한 바인드는 아무것도 남기지 않습니다.** RFC 4511 §4.2.1: 연결은 바인드 요청을
*받을 때* 익명이 되며, 바인드가 성공하지 않으면 그대로입니다. 그래서 잘못된
비밀번호로 다시 바인드해도 이전 사람의 권한을 유지하지 않습니다. `Bind` 핸들러가
없는 단순 바인드는 `authMethodNotSupported`로 응답하며, LDAPv2는 프로토콜 오류로
거부됩니다.

{{< callout type="warning" >}}
**빈 비밀번호가 무엇을 뜻하는지는 핸들러가 결정합니다**

비인증 바인드 — 빈 비밀번호가 있는 이름, RFC 4513 §5.1.2 — 는 다른 단순 바인드처럼
`Bind` 핸들러에 전달되며, 그것에 `Success`를 반환하는 핸들러는 연결을 그 이름으로
바인드합니다. 예제처럼 핸들러에서 거부하십시오. [directory]({{< relref "/libraries/directory.md" >}})의
`ldapdir`은 클라이언트 측에서 이를 거부합니다.
{{< /callout >}}

**인정하지 않는 critical 컨트롤.** ManageDsaIT(RFC 3296), 비밀번호 변경(RFC 3062),
취소(RFC 3909)는 클라이언트가 보낼 수 있기 때문에 상수로 명명되어 있을 뿐 응답하는 것은
아닙니다. 여기서는 별칭이나 리퍼럴을 따르는 것이 없으므로 critical ManageDsaIT는
`unavailableCriticalExtension`으로 거부됩니다.

**인증되지 않은 피어가 붙들 수 있는 것:**

| | 기본값 | |
|---|---|---|
| `MaxMessageSize` | 4 MiB | 4기가바이트라고 주장하는 5바이트 헤더는 아무것도 예약하기 전에 거부됨 |
| `MaxMessageElements` | 16384 | 디코딩 전에 세는 BER 요소: v0.5.0 이전에는 빈 문자열 4 MiB가 바인드 전에 373 MiB를 붙들었음 |
| `IdleTimeout` | 5분 | 첫 바이트가 아니라 메시지 전체가 제때 도착해야 함. 음수는 제한 없음 |
| `MaxPending`, `MaxPendingAuth` | 100, 1000 | 연결 하나가 바인드 전(`MaxPending`)과 후(`MaxPendingAuth`)에 진행 중으로 둘 수 있는 작업, slapd의 `conn_max_pending`과 `conn_max_pending_auth`처럼. 넘는 연결에는 연결 해제 통지를 보내고 닫음 |
| `MaxPagedSearches` | 4 | 연결당 열려 있는 페이지 검색, 각각 다음 엔트리를 기다리며 멈춘 고루틴 |

필터 중첩도 제한됩니다. Go의 스택 오버플로는 프로세스를 죽입니다. 어떤 것도 어서션
*값*을 기록하지 않습니다. 필터는 누군가 입력한 것을 담고 있으므로 필터의 형태만
기록합니다.

**페이지 검색은 요청된 것에 응답합니다.** v0.8.0까지는 페이지 리더가 핸들러가 쓴 대로
각 엔트리를 보냈습니다. `cn`만 요청한 페이지 검색이 운영 속성을 포함한 모든 속성과 함께
돌아왔고 `typesOnly`는 무시되었지만, 같은 검색을 페이지 없이 하면 선택을 지켰습니다.
`ldapsearch -E pr=N`이 클라이언트가 페이징하는 방법이므로 같은 질문이 두 가지 답을
받았습니다. v0.8.0부터 둘 다 선택을 적용하며, `ldapsearch` 자체가 CI에서 이를
검사합니다.

스키마가 없으면 — `Server.Schema`가 nil인 기본값 — 모든 비교는 값에 대해 대소문자를
구분하지 않습니다. 읽기에는 둘 중 더 안전한 쪽으로, 정확한 비교가 찾았을 엔트리를
숨기는 일이 없기 때문입니다.

## 스키마 {#the-schema}

v0.8.0부터 `schema` 패키지는 RFC 4512 §4의 디렉터리 스키마이며, `Server.Schema`가
서버가 이를 사용하게 합니다. nil이면 서버는 이전과 정확히 같습니다.

- `schema.Standard()`는 RFC 4512, 4517, 4519, 4524, 4523, 2798, 2307, 3672, 3045의
  정의와, openssh-lpk의 `ldapPublicKey`와 `sshPublicKey` 및 이들이 필요로 하는 두
  OpenLDAP 정의를 RFC 본문에서 복사하여 내장합니다. `schema/defs`의 각 파일은 출처와
  절을 밝힙니다. `schema.Build(append(schema.StandardFiles(), mine)...)`는 배포 환경
  자신의 것을 추가하며, SUP, 규칙, 구문, MUST 또는 MAY가 해석되지 않는 정의는
  거부합니다.
- `(*ldap.Entry).Validate(s)`는 모든 상위 클래스가 나열된 구조 체인 하나, 모든 MUST,
  MUST와 MAY 밖의 것이 없는지, SINGLE-VALUE, 알려진 타입, 구문에 맞는 값, 그리고
  엔트리 안의 RDN 값을 검사하며, **모든** 문제를 `*schema.ValidationError`로 알려
  줍니다.
- 스키마가 있으면 루트 DSE에 `subschemaSubentry: cn=Subschema`가 실리며,
  `cn=Subschema`(`ldap.SubschemaDN`)의 베이스 검색은 루트 DSE처럼 라이브러리가
  응답합니다(RFC 4512 §4.2). 정의는 이름으로 요청하거나 `+`로 요청할 때만 나옵니다.
  `RequireTLS` 게이트 뒤에 있습니다.
- 필터는 스키마의 매칭 규칙(RFC 4517 §4.2, RFC 4518 문자열 준비 포함)으로 RFC 4511의
  3값 논리에서 평가됩니다. 알 수 없는 속성, 요청한 매칭에 대한 규칙이 없는 타입,
  유효하지 않은 어서션 값은 오류가 아니라 **Undefined**입니다. 서버는 핸들러가 보내는
  모든 엔트리를 다시 검사하고 필터가 TRUE로 만들지 않는 것을 버립니다. 핸들러는
  같은 스키마를 사용하는 `req.Matches(e)`로 필터링합니다.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap"
	"github.com/go-authn/ldap/schema"
)

func main() {
	s := schema.Standard() // RFC 4512, 4517, 4519, 4524, 2798, 2307, ... and openssh-lpk

	// An account with posixAccount, and no homeDirectory.
	eli := &ldap.Entry{DN: "uid=eli,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "top", "account", "posixAccount"),
		ldap.StringAttribute("uid", "eli"),
		ldap.StringAttribute("cn", "eli"),
		ldap.StringAttribute("uidNumber", "1001"),
		ldap.StringAttribute("gidNumber", "1001"),
		ldap.StringAttribute("mail", "eli@example.org"),
	}}
	var v *schema.ValidationError
	if errors.As(eli.Validate(s), &v) {
		for _, p := range v.Problems {
			fmt.Println("-", p)
		}
	}

	// uidNumber orders as an integer: 1001 >= 999, which as strings it is not.
	for _, f := range []string{"(uidNumber>=999)", "(uid>=a)"} {
		filter, _ := ldap.ParseFilter(f)
		fmt.Println(f, ldap.Evaluate(filter, eli, s))
	}
}
```

```
- mail is not allowed by any of the entry's object classes
- homeDirectory is required by posixAccount and is missing
(uidNumber>=999) TRUE
(uid>=a) Undefined
```

`mail`은 `account`가 아니라 `inetOrgPerson`에 속합니다. `uid`에는 ORDERING 규칙이
없으므로 그에 대한 범위는 Undefined입니다.

{{< callout type="info" >}}
**RFC 2307과의 한 가지 차이: `uidNumber`와 `gidNumber`는 정수로 정렬됩니다**

RFC 2307은 `uidNumber`와 `gidNumber`에 EQUALITY 규칙을 주고 ORDERING 규칙은 주지
않으므로, SSSD가 `ldap_min_id`와 `ldap_max_id`로 만드는 것을 포함해 이들에 대한 모든
범위 필터가 Undefined가 됩니다. slapd는 두 타입을 `ORDERING integerOrderingMatch`로
직접 정의하며(`servers/slapd/schema_prep.c`, 그 `nis.schema`는 이를 "builtin"으로
주석 처리), draft-howard-rfc2307bis-02 §2.1도 그러하므로 내장 정의는 이들을 따릅니다.
이것과, DIT 콘텐츠 규칙 없이 보조 클래스를 허용하는 것(RFC 4512 §2.4.3은 엄밀히
금지하지만 사용 중인 모든 서버가 허용함)은 발견되는 것이 아니라 명시된 것입니다.
{{< /callout >}}

DIT 콘텐츠 규칙, 이름 형식, DIT 구조 규칙은 [v0.11.0부터 있습니다](#rules).
의도적으로 없는 것: LDAP으로 스키마 변경,
RFC 4523의 인증서 매칭 규칙과 `directoryStringFirstComponentMatch`(정의는 되어 있으나
구현되지 않았으므로 이를 쓰는 어서션은 Undefined), 컬렉티브 속성, `lang-`과 `binary`
이외의 옵션.

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}})는 이 스키마를
제공하며 게시하는 모든 엔트리를 여기에 맞춥니다.

## 큰 스키마 파일 읽기 {#reading-large-files}

v0.10.0까지 `schema.Read`는 읽는 파일의 이어짐 줄 수에 대해 제곱 시간이 걸렸습니다. 짧은 이어짐 줄로 된 4 MiB 파일에 약 3분이 걸렸고, 1 MiB에서 139.6 GB를 할당했습니다. authnd가 시작할 때 `schema_files`로 하듯이, 통제하지 않는 스키마 파일을 읽는 프로그램은 그런 파일 하나에 멈출 수 있었습니다. v0.10.1부터 시간은 선형이며(`TestManyContinuationLinesJoinInLinearTime`), `Read`는 첫 줄을 확인하려고 파일 전체를 복사하고 나누지 않습니다.

`schema.Format`은 2000바이트가 넘는 줄을 썼는데, slapd와 `Read`는 이를 거부합니다. 이제는 줄을 접어서 씁니다. 엄격한 파서는 약 2.6배 빠르고, `cosine.schema`에서 할당이 498회에서 147회로 줄었습니다. libldap(macOS SDK, `LDAP_SCHEMA_ALLOW_ALL`을 쓴 `ldap_str2attributetype`과 `ldap_str2objectclass`)과의 비교는 OpenLDAP `cosine.schema`의 정의 54개로, 2026-10-26에 Apple M4 Max에서 부하 6.5~7.6일 때 측정했습니다(`-cpu 1 -count 10`, benchstat). go-authn/ldap은 25.65 µs ± 32 %, libldap은 35.62 µs ± 2 %로, libldap 시간의 약 0.72배입니다. Go 쪽은 실행마다 할당 147회(20.6 KiB)입니다. `-benchmem`은 libldap의 C 할당을 볼 수 없으므로 그 수치는 없습니다. 재현하려면 go-authn/ldap의 `bench/libldap`에서 `go test -bench . -benchmem -cpu 1 -count 10`을 실행하세요(cgo와 libldap 필요). authnd는 v0.12.3부터 이 수정을 갖고 있습니다.

v0.10.2 부터 `schema.Standard()` 의 RFC 2307 DESC 값 13개는 한 줄입니다. v0.10.1 까지는 RFC 쪽처럼 줄이 나뉘어 있었고, 이어지는 줄은 첫 문자 뒤의 들여쓰기를 유지하므로(`Read` 가 따르는 slapd 의 `fp_getline`) 이를 게시한 서버는 `DESC 'An integer uniquely identifying a user in an         administrative domain'` 을 보냈습니다. authnd 는 v0.12.4 부터 수정되었습니다.

## 빌드되지 않는 스키마 {#build-error}

v0.10.0부터 `schema.Build` 또는 `schema.BuildFrom`이 거부하는 정의는
`*schema.BuildError`이며 `errors.As`로 찾습니다. 프로그램은 거부 사실을 메시지를
비교해서가 아니라 필드로 보고합니다. Build는 처음 거부하는 정의에서 멈추므로
거부되는 정의는 하나입니다.

- `Kind`는 Build가 수행하는 모든 검사 중 하나입니다. `UnknownReference`,
  `DuplicateOID`, `DuplicateName`, `SuperiorCycle`, `KindViolation`,
  `UsageMismatch`, `CollectiveMismatch`, `UsageViolation`입니다.
- `Element`(구문, 매칭 규칙, 속성 타입 또는 오브젝트 클래스), `OID`, `Name`(첫
  번째 NAME)은 거부된 정의의 것이고, `Pos`는 그 정의가 시작되는 위치입니다.
  `file:line:column`이며, `.schema` 키워드가 있는 줄 또는 LDIF의 `attributeTypes:`
  줄이고 그 줄이 접히거나 base64여도 마찬가지이며, HCL에서는 블록 자체의
  위치입니다. 코드로 만든 정의에는 위치가 없습니다.
- `Field`는 문제가 되는 항(`SUP`, `EQUALITY`, `SYNTAX`, `MUST`, `NAME` ...)이고,
  `Ref`는 오류가 가리키는 대상입니다. 정의되지 않은 이름이나 OID, 또는 `RefOID`와
  `RefPos`를 가진 다른 정의입니다. 중복의 경우에는 첫 번째 정의이며, 메시지가 그
  위치를 알려 줍니다.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap/schema"
)

// An object class whose superclass is defined nowhere.
const site = `# site.schema
objectclass ( 1.3.6.1.4.1.99999.1.1 NAME 'siteMember'
	SUP top AUXILIARY )
objectclass ( 1.3.6.1.4.1.99999.1.2 NAME 'siteGuest'
	SUP nobody AUXILIARY )
`

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "site.schema", Data: []byte(site)})
	_, err := schema.Build(files...)

	var be *schema.BuildError
	if !errors.As(err, &be) {
		fmt.Println("not a BuildError:", err)
		return
	}
	fmt.Println("error:  ", be)
	fmt.Println("Kind:   ", be.Kind)
	fmt.Println("Element:", be.Element)
	fmt.Println("OID:    ", be.OID)
	fmt.Println("Name:   ", be.Name)
	fmt.Println("Field:  ", be.Field)
	fmt.Println("Ref:    ", be.Ref)
	fmt.Println("Pos:    ", be.Pos)
	fmt.Println("RefPos: ", be.RefPos.IsValid())
	fmt.Println("is UnknownReference:", be.Kind == schema.UnknownReference)
}
```

```
error:   site.schema:4:1: schema: the object class siteGuest has the superclass nobody, which is not defined
Kind:    unknown reference
Element: object class
OID:     1.3.6.1.4.1.99999.1.2
Name:    siteGuest
Field:   SUP
Ref:     nobody
Pos:     site.schema:4:1
RefPos:  false
is UnknownReference: true
```

`github.com/go-authn/ldap` v0.10.1으로 빈 모듈에서 실행한 예제입니다. 첫 번째
클래스는 문제가 없고, 두 번째는 4번째 줄에서 시작하며 다른 곳에는 잘못이 없으므로
`RefPos`는 비어 있습니다. `schema.Read`가 반환하는 모든 정의에도 `Pos`가 있으며,
Position의 `String`은 열을 알 수 없을 때 열을 생략합니다.

## DIT 콘텐츠 규칙, 이름 형식, DIT 구조 규칙 {#rules}

v0.11.0부터, RFC 4512 §4.1.6(DIT 콘텐츠 규칙)과 §4.1.7(이름 형식, DIT 구조 규칙)이
정의하는 세 종류의 정의를 이 패키지가 읽고, 빌드하고, 적용하고, 게시합니다. 그
전에는 이 정의들을 거부했습니다.

- **타입.** `schema.DITContentRule`, `schema.NameForm`, `schema.DITStructureRule`과
  엄격한 RFC 4512 파서 `ParseDITContentRule`, `ParseNameForm`,
  `ParseDITStructureRule`(`FuzzDefinition`으로 퍼징함), 그리고 프린터가 있습니다.
  `schema.MaxRuleID`는 규칙 ID를 모든 플랫폼에서 2^31-1로 제한합니다.
  `Definitions.DITContentRules`, `NameForms`, `DITStructureRules`가 `Read`가 반환하는
  것을 담습니다.
- **읽기와 쓰기.** `schema.Read`는 `.schema` 파일(slapd.conf(5)의 지시어인
  `ditcontentrule`, 그리고 slapd에는 없는 이 패키지의 `nameform`과
  `ditstructurerule`)과 LDIF(`olcDitContentRules`, `dITContentRules`, `nameForms`,
  `dITStructureRules`)에서 이를 읽으며, libldap이 읽는 것처럼 항목은 어떤 순서든
  됩니다. `Format`은 이를 다시 씁니다. v0.11.0 이전에는 이 속성들을 거부했습니다.
- **빌드.** `Build`가 이들을 연결합니다. 모든 클래스, 타입, 이름 형식, 상위 규칙이
  정의되어 있어야 하고, 콘텐츠 규칙은 구조 클래스에 대한 것이며 그 `AUX`는 보조
  클래스여야 하고, 이름 형식은 구조 클래스를 지정해야 하며, 규칙 ID와 이름은
  유일해야 합니다. 새 `BuildErrorKind`가 둘, `DuplicateMember`와
  `PrecludedRequired`, 새 `Element`가 셋, `ElementDITContentRule`,
  `ElementNameForm`, `ElementDITStructureRule` 있습니다. `Schema`에는
  `DITContentRules`, `NameForms`, `DITStructureRules`, `DITContentRule(name)`,
  `DITContentRuleOf(class)`, `NameForm(name)`, `DITStructureRule(id)`가 있습니다.
- **적용.** `Validate`는 엔트리의 구조 클래스에 대한 활성 콘텐츠 규칙(`AUX`, `MUST`,
  `MAY`, `NOT`)과 활성 이름 형식을 적용하며, 새 `ProblemKind`로
  `AuxiliaryNotAllowed`, `Precluded`, `NameFormViolation`, `NoStructureRule`이 있습니다.
  엔트리가 트리의 어디에 놓일 수 있는지는 그 상위 엔트리가 있어야 알 수 있으므로
  `Schema.GoverningStructureRule(entry, superior)`가 맡습니다. 상위 엔트리의 규칙 아래에서
  엔트리를 다스리는 구조 규칙을 반환하며, 상위가 nil이면 서브트리의 루트에서의
  규칙을 반환합니다. 활성 구조 규칙이 없으면 nil을 반환하고 오류는 없습니다.
  규칙이 없는 스키마에서 `Validate`는 이전과 같은 결과를 줍니다.
- **게시.** 스키마에 있을 때 `cn=Subschema`가 `dITContentRules`, `nameForms`,
  `dITStructureRules`를 게시합니다.
- **그 밖에.** 구문 1.3.6.1.4.1.1466.115.121.1.16, .17, .35를 검사합니다.
  `hclschema`에는 `dit_content_rule`, `name_form`, `dit_structure_rule` 블록이 있고,
  `ldapschema`가 이를 변환하고 검사합니다([아래](#hcl2-and-the-converter) 참조).
  `bench/libldap`은 세 파서를 libldap의 파서와 비교합니다.

예제 OID 아크 1.3.6.1.4.1.99999 아래의 작동 예입니다. `inetOrgPerson`에 대한 콘텐츠
규칙(`posixAccount`와 `uidObject`를 추가할 수 있고, 전화번호는 필수이며, 설명은
금지), 접미사와 `ou=` 컨테이너와 사람의 이름 형식, 그리고 이를 배치하는 구조
규칙입니다.

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/ldap/schema"
)

const rules = `# rules.schema
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule'
	AUX ( posixAccount $ uidObject )
	MUST telephoneNumber
	NOT description )

nameform ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameform ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameform ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )

ditstructurerule ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
ditstructurerule ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
ditstructurerule ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
`

func attr(name string, values ...string) schema.Attribute {
	a := schema.Attribute{Description: name}
	for _, v := range values {
		a.Values = append(a.Values, []byte(v))
	}
	return a
}

func report(title string, err error) {
	fmt.Println(title)
	var v *schema.ValidationError
	if errors.As(err, &v) {
		for _, p := range v.Problems {
			fmt.Println("  -", p)
		}
		return
	}
	fmt.Println("  ", err)
}

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "rules.schema", Data: []byte(rules)})
	s, err := schema.Build(files...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// erin: an inetOrgPerson with a public key, a description, and no telephone number.
	erin := schema.Entry{DN: "uid=erin,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson", "ldapPublicKey"),
		attr("uid", "erin"), attr("cn", "erin"), attr("sn", "Evans"),
		attr("description", "on call"),
		attr("sshPublicKey", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl erin@example.org"),
	}}
	report("erin:", s.Validate(erin))

	// fay: named by cn, which the name form of inetOrgPerson does not allow.
	fay := schema.Entry{DN: "cn=fay,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson"),
		attr("uid", "fay"), attr("cn", "fay"), attr("sn", "Fox"),
		attr("telephoneNumber", "+33 1 23 45 67 89"),
	}}
	report("fay:", s.Validate(fay))

	// The rule that governs each entry is the superior of the next.
	suffix := schema.Entry{DN: "dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "domain"), attr("dc", "example"),
	}}
	people := schema.Entry{DN: "ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "organizationalUnit"), attr("ou", "people"),
	}}
	root, err := s.GoverningStructureRule(suffix, nil)
	fmt.Println("suffix:", root.Names[0], err)
	ou, err := s.GoverningStructureRule(people, root)
	fmt.Println("ou=people:", ou.Names[0], err)
	gina := schema.Entry{DN: "uid=gina,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson"),
		attr("uid", "gina"), attr("cn", "gina"), attr("sn", "Gray"),
		attr("telephoneNumber", "+33 1 23 45 67 89"),
	}}
	r, err := s.GoverningStructureRule(gina, ou)
	fmt.Println("uid=gina:", r.Names[0], err)
	_, err = s.GoverningStructureRule(gina, root)
	report("uid=gina directly under the suffix:", err)

	// hal: an account with posixAccount, and no content rule for account.
	hal := schema.Entry{DN: "uid=hal,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "account", "posixAccount"),
		attr("uid", "hal"), attr("cn", "hal"), attr("uidNumber", "1001"), attr("gidNumber", "100"),
		attr("homeDirectory", "/home/hal"),
	}}
	report("hal, as slapd allows it:", s.Validate(hal))
	report("hal, with StrictAuxiliary:", s.ValidateWith(hal, schema.ValidateOptions{StrictAuxiliary: true}))
}
```

```
erin:
  - the auxiliary class ldapPublicKey is not in the AUX of the DIT content rule examplePersonRule (RFC 4512 4.1.6)
  - description is precluded by the DIT content rule examplePersonRule (RFC 4512 4.1.6)
  - telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
fay:
  - the RDN (cn) is allowed by no name form of inetOrgPerson: examplePersonForm needs uid
suffix: exampleSuffix <nil>
ou=people: exampleUnit <nil>
uid=gina: examplePersons <nil>
uid=gina directly under the suffix:
  - no DIT structure rule allows inetOrgPerson under an entry governed by the rule exampleSuffix (X.501 13.7.5)
hal, as slapd allows it:
   <nil>
hal, with StrictAuxiliary:
  - the auxiliary class posixAccount is allowed by no DIT content rule: account has none (RFC 4512 2.4.3)
```

`github.com/go-authn/ldap` v0.11.0(go1.27.1)으로 빈 모듈에서 실행했습니다.
`Validate`는 이전처럼 **모든** 문제를 말합니다. erin은 콘텐츠 규칙을 세 가지로
동시에 어깁니다.

**slapd와 다른 점**은 발견하게 두지 않고 밝혀 둡니다.

- slapd는 콘텐츠 규칙만 구현합니다. 이름 형식이나 구조 규칙을 위한 지시어가 없으므로
  `Format`은 slapd가 거부하는 `nameform`과 `ditstructurerule` 키워드를 씁니다.
  `ditcontentrule`은 slapd의 것입니다.
- `OBSOLETE` 규칙은 비활성입니다(RFC 4512 §4.1.6). 아무것도 다스리지 않습니다.
  slapd는 대신 엔트리를 거부합니다.
- 콘텐츠 규칙이 없으면 보조 클래스가 허용됩니다. 이것이 slapd의 동작입니다.
  `SLAP_DISALLOW_AUX_WO_CR` 플래그는 어떤 `disallow` 키워드로도 설정되지 않습니다.
  `ValidateOptions{StrictAuxiliary: true}`는 위의 `hal`이 보여 주듯 RFC 4512
  §2.4.3을 따릅니다.
- libldap은 구조 규칙의 `SUP`을 읽지 못합니다.

`hclschema.Decode`는 이제 UTF-8이 아닌 문자열을 거부합니다. 이전에는 받아들였고,
그것이 다른 문자열로 인코딩되었습니다(`FuzzDecode`가 찾아냄).
[authnd]({{< relref "/authnd/schemas.md#rules" >}})는 `schema_files`와 `schema { }`
블록에서 이 정의들을 불러와, 게시하는 트리와 엔트리에 적용합니다.

## HCL2의 스키마와 변환기 {#hcl2-and-the-converter}

v0.9.0부터 스키마는 slapd가 읽는 파일뿐 아니라 HCL2로도 쓸 수 있습니다.
`schema/hclschema` 패키지는 HCL2를 `schema.Read`가 반환하는 것과 같은
`*schema.Definitions`로 디코딩하고 다시 인코딩합니다(`hclschema.Decode`,
`hclschema.Encode`). `schema` 자체는 HCL 의존성을 갖지 않습니다. 블록 하나가 정의
하나이며, 그 타입이 무엇인지 알려 줍니다. `object_identifier`, `ldap_syntax`,
`matching_rule`, `attribute_type`, `object_class`. 레이블은 첫 번째 NAME입니다. 속성은
RFC 4512 §4.1의 항목을 소문자와 밑줄로 쓴 것(`desc`, `sup`, `equality`,
`single_value`, `kind`, `must`, `may` 등)이며, 구문의 `{len}`은 `syntax_len`입니다.

**리터럴 값만.** 값은 따옴표 문자열, 숫자, 불리언 또는 그것들의 목록입니다. 변수, 함수,
연산자, `${...}` 템플릿은 아무것도 평가하기 전에 거부되므로, 스키마를 읽는 것이 그것을
실행하지는 않습니다. 각 필드는 엄격한 RFC 4512 파서가 검사하며, 위치가 필요한 오류에는
파일, 줄, 열이 함께 옵니다.

`ldapschema` 명령이 형식 사이를 변환합니다.

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.11.0
```

- `ldapschema to-hcl [--macros] FILE...`은 OpenLDAP `.schema` 파일, cn=config LDIF,
  서브스키마 LDIF를 읽고 HCL2를 씁니다.
- `ldapschema to-schema [--macros] FILE...`은 HCL2를 읽고 OpenLDAP `.schema` 파일을
  씁니다.
- `ldapschema check FILE...`은 `schema.Standard()` 위에 정의를 빌드하고 보고합니다.

출력은 stdout으로 갑니다. 종료 상태는 명령이 동작하면 0, 파일이나 정의가 거부되면 1,
사용법 오류이면 2입니다.

**읽는 쪽은 slapd처럼 파일을 읽습니다.** 공개된 스키마는 slapd를 위해 작성되기
때문입니다. 순서에 관계없는 항목, `.schema` 파일의 slapd식 줄 이음과 LDIF의 RFC 2849
접기, base64 값, cn=config의 `{N}` 접두사, 파일 순서로 해석되는 `objectidentifier`
매크로. 공개된 `Parse*` 함수와 서버가 게시하는 것은 엄격한 RFC 4512로 유지됩니다.

`ldapschema` v0.10.1으로 빈 디렉터리에서 실행한 예제입니다. 스키마는 이 페이지를 위해
만든 것이며, 1.3.6.1.4.1.99999는 개인 용도의 예제 아크이지 누구에게 할당된 것이
아닙니다. 매크로 하나, 속성 타입 하나, 보조 클래스 하나:

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1 NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1 NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top AUXILIARY
	MAY siteBadge )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

attribute_type "siteBadge" {
  oid          = "1.3.6.1.4.1.99999.1.1"
  desc         = "the badge number"
  equality     = "caseIgnoreMatch"
  syntax       = "1.3.6.1.4.1.1466.115.121.1.15"
  syntax_len   = 32
  single_value = true
}

object_class "sitePerson" {
  oid  = "1.3.6.1.4.1.99999.2.1"
  desc = "a person with a badge"
  sup  = ["top"]
  kind = "auxiliary"
  may  = ["siteBadge"]
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( 1.3.6.1.4.1.99999.1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( 1.3.6.1.4.1.99999.2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 1 attribute types, 1 object classes
build: ok, 2 definitions added to schema.Standard()
```

클라이언트가 서브스키마에서 보는 것이 숫자 OID이므로 출력은 기본적으로 숫자 OID이며,
`--macros`는 매크로 이름을 유지합니다. `check`는 `schema.Standard()`에 이미 있는 정의와
아무것도 정의하지 않는 모든 참조도 보고하며, `Build`는 첫 번째에서 멈춥니다.

**v0.11.0부터 `ldapschema`는 세 종류의 [규칙](#rules)도 변환합니다.** `.schema`
파일의 `ditcontentrule`, `nameform`, `ditstructurerule`과 HCL의 `dit_content_rule`,
`name_form`, `dit_structure_rule` 블록입니다. 구조 규칙은 첫 번째 NAME으로
레이블이 붙고, `id`, 배치하는 `form`, 그 아래에 놓이는 `sup` 규칙(ID)을 가집니다.
`check`는 이들이 만드는 누락된 참조를 모두 보고합니다. `ldapschema` v0.11.0(태그에서
`go install`로 빌드)으로 빈 디렉터리에서 실행한, 각 종류가 하나씩 있는 스키마입니다.

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

# inetOrgPerson: may carry uidObject, must have a telephone number.
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'sitePersonRule'
	AUX uidObject
	MUST telephoneNumber )

nameform ( site:9.1 NAME 'siteDomainForm' OC domain MUST dc )

ditstructurerule ( 1 NAME 'siteSuffix' FORM siteDomainForm )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

dit_content_rule "sitePersonRule" {
  oid  = "2.16.840.1.113730.3.2.2"
  aux  = ["uidObject"]
  must = ["telephoneNumber"]
}

name_form "siteDomainForm" {
  oid  = "1.3.6.1.4.1.99999.9.1"
  oc   = "domain"
  must = ["dc"]
}

dit_structure_rule "siteSuffix" {
  id   = 1
  form = "siteDomainForm"
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

ditcontentrule ( 2.16.840.1.113730.3.2.2
	NAME 'sitePersonRule'
	AUX uidObject
	MUST telephoneNumber )

nameform ( site:9.1
	NAME 'siteDomainForm'
	OC domain
	MUST dc )

ditstructurerule ( 1
	NAME 'siteSuffix'
	FORM siteDomainForm )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 1 name forms, 1 DIT structure rules
build: ok, 3 definitions added to schema.Standard()
```

**`check`는 slapd가 로드하는 파일에서 1로 종료할 수 있습니다.** OpenLDAP의
`core.schema`는 slapd가 내장하고 `schema.Standard()`는 정의하지 않는 네 가지를
참조합니다. 구문 1.3.6.1.4.1.1466.115.121.1.42와 1.3.6.1.4.1.1466.115.121.1.43,
그리고 매칭 규칙 `protocolInformationMatch`와 `presentationAddressMatch`입니다.
`ldapschema check core.schema`는 이를 `missing:`으로 나열하고 1로 종료합니다. 파일의
결함이 아니라 "여기서는 정의되지 않음"으로 읽으십시오.

**지원하지 않는 것:** `include` 지시문:
`.schema` 파일은 정의로 읽히며 slapd 구성으로 실행되지 않기 때문입니다.
`ldapsyntax`의 `X-SUBST`.

**공개된 스키마는 변환됩니다.** 릴리스는 OpenLDAP의 `core`, `cosine`, `inetorgperson`,
`nis`, RENATER의 SUPANN 2021, REFEDS의 eduPerson, Samba의 스키마에서 측정했습니다.
각각에 대해 `.schema`에서 HCL로 갔다 돌아오는 것과, LDIF를 `.schema`와 비교하는 것이
같은 정의를 줍니다. 저장소에는 OpenLDAP의 파일만 있습니다. SUPANN과 eduPerson은 여기에
다시 싣지 않았으니 저자들의 페이지에서 읽으십시오:
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)과
[eduPerson](https://github.com/REFEDS/eduperson).

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

**OpenLDAP의 `ldapsearch`**를 CI에서 사용하며 설치된 곳에서는 필수입니다. Linux 테스트
레인, 레이스 감지기, 커버리지 레인은 `LDAP_REQUIRE_JUDGE=1`을 설정하므로 클라이언트가
없으면 건너뛰는 대신 실패합니다. Windows에는 없으며 그 테스트를 건너뜁니다. 이 모듈
자체의 와이어 클라이언트인 `ldaptest`는 의도적으로 판정자가 아닙니다. `ldapsearch`가
할 수 없는 것, 즉 연결 하나의 상태에 대해서만 묻습니다. 한 소켓에서의 두 번의 바인드,
임의의 메커니즘을 쓰는 SASL 바인드, StartTLS 뒤에 이어지는 LDAP.

`FuzzMessage`는 클라이언트가 보낼 수 있는 모든 메시지를 프레임, 디코더, 필터 왕복에
통과시킵니다. 커버리지 하한은 99.7%이며, 도달하지 않는 세 줄은 워크플로에 이름이
있습니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/ldap](https://pkg.go.dev/github.com/go-authn/ldap)
