---
title: "directory — 누군가가 누구이며, 무엇이 그를 증명하는가"
linkTitle: "directory"
weight: 50
description: "go-authn/directory: 메모리의 목록, SQL 데이터베이스, LDAP 서버 또는 HCL 구성 위에서, 사람과 소스가 그 사람에 대해 보유한 자격 증명의 하나의 모델."
tags: [라이브러리, 디렉터리, ldap, sql]
---

**누군가는 누구이며, 무엇이 그를 증명할 수 있는가?** 메모리에 보관한 목록, SQL
데이터베이스, LDAP 서버, 또는 구성 파일의 `user`와 `group` 블록 위에 놓인 하나의
모델이며, 요점은 질문의 후반부에 있습니다.

```sh
go get github.com/go-authn/directory@v0.14.0
```

## 사람을 증명하는 것은 하나가 아닙니다 {#what-proves-somebody-is-not-one-thing}

이는 프로토콜에 관한 사실입니다. NTLMv2(SMB)는 챌린지-응답입니다. 클라이언트는
비밀번호를 보내지 않으므로, 서버가 비밀번호나 `MD4(UTF16LE(password))` — NT 해시 —
를 가지고 있어야 하며 **LDAP 바인드로는 SMB 세션을 인증할 수 없습니다.** KDC는
그 사람의 키로 *복호화*해야 하므로 비밀번호를 보유한 소스만이 렐름을 뒷받침할 수
있습니다. SSH에는 공개 키가 필요합니다. 두 번째 인증 요소에는 여섯 자리 뒤의 비밀
값이 필요합니다.

그래서 `Identity`는 소스가 어떤 `Credential`을 제공했는지 — `Password`, `NTHash`,
`Verifier`(해시 비교 또는 바인드), `PublicKeys`, `TOTPSecret` — 알려 주며,
`Identity.Can`으로 서버는 누군가 마운트에서 거부를 만나기 전에 *WebDAV는 되지만 SMB는
안 됩니다*라고 말할 수 있습니다. 프로토콜마다 자신의 메서드가 있습니다.

| | 답하는 대상 | 출처 |
|---|---|---|
| `Verify(password)` | 비밀번호를 건네받은 모든 것 | 먼저 소스의 검증자(LDAP 바인드일 수 있음), 없으면 보유한 비밀번호를 SHA-256 다이제스트에 대해 상수 시간으로 비교하므로 길이조차 새지 않음 |
| `NTKey()` | NTLMv2 | 게시된 해시, 또는 비밀번호에서 파생. 둘 다 없으면 `ErrNoCredential` |
| `Derive(f)`, `KerberosKey(f)` | KDC, AWS SigV4 — 비밀 값을 *소유해야* 하는 모든 것 | 비밀번호만. 파생은 호출자의 함수 |
| `Keys()` | SSH | `authorized_keys` 줄 |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | 열, 또는 호출자가 지정하는 LDAP 속성 |

## 소스 {#the-sources}

| 패키지 | 읽는 대상 | import |
|---|---|---|
| `directory` | `Static` 목록, 그리고 순서가 있는 소스의 `Set` | 표준 라이브러리만 |
| `directory/sqldir` | 임의의 `*sql.DB`, **당신의** 쿼리로 | 드라이버 없음: 프로그램이 선택 |
| `directory/ldapdir` | LDAP 서버 | `go-ldap/ldap/v3` |
| `directory/hcldir` | 데이터베이스나 LDAP 서버를 지정하는 `users` 블록, 그리고 사람을 담은 `user`/`group` 블록 | `x/crypto/ssh`, `hashicorp/hcl/v2`, `zclconf/go-cty` |
| `directory/ldaptest` | 대조해 테스트할 LDAP 서버 | `glauth/ldap` |

`Set`에서는 이름을 아는 **첫 번째** 소스가 그 이름을 소유하므로, 로컬에 적어 둔 서비스
계정을 LDAP에 넣을 필요가 없습니다. 그룹 구성원은 모든 소스의 **합집합**입니다.
소스는 서버가 시작할 때 읽습니다. 비밀번호 확인은 매번 소스에 도달할 수 있는데,
바인드는 비밀 값을 보유하지 않고서는 캐시할 수 없기 때문입니다.

`hcldir`은 HCL을 디코딩하지 않습니다. 호출자가 블록을 디코딩해서 건넵니다. HCL은
`SetPassword`를 위해 쓸 때만 import합니다. 빌드 태그 `nosql`과 `noldap`은 한 종류를
`hcldir`에서 완전히 뺍니다.

## 예제 {#example}

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	local := &directory.Static{
		Name: "the configuration file",
		People: []*directory.Identity{
			directory.NewIdentity("dora", directory.WithPassword("hunter2")),
			directory.NewIdentity("eli", directory.WithVerifier(func(pw string) error {
				return directory.ErrWrongPassword // a bind against somebody else's LDAP, say
			})),
			directory.NewIdentity("svc-backup", directory.WithPublicKeys("ssh-ed25519 AAAA...elided... backup")),
		},
		Groups: map[string][]string{"staff": {"dora", "eli"}, "nobody": {}},
	}
	people := directory.NewSet(local) // more sources after it: sqldir, ldapdir...

	ids, _ := people.Identities()
	for _, id := range ids {
		fmt.Println(id.Name(), "password:", id.Can(directory.Password), "verifier:", id.Can(directory.Verifier),
			"keys:", id.Can(directory.PublicKeys), "from", id.Where())
	}

	// NTLMv2 needs MD4(UTF16LE(password)): dora's can be derived, eli's cannot.
	for _, id := range ids[:2] {
		_, err := id.NTKey()
		fmt.Println(id.Name(), "SMB:", err == nil, errors.Is(err, directory.ErrNoCredential))
	}

	// An empty group is an empty answer; a group nobody has is an error.
	fmt.Println(people.Members("nobody"))
	fmt.Println(people.Members("admins"))

	// @group is expanded; an empty group, or one nobody has, is refused.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	_, err := directory.Expand([]string{"@nobody"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
	_, err = directory.Expand([]string{"@admins"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[] <nil>
[] directory: no such group: "admins", in the configuration file
[dora eli svc-backup] <nil>
[] directory: the group has no members: "nobody": nobody would be allowed
directory: the group has no members: "nobody": nobody would be allowed true false
directory: no such group: "admins", in the configuration file false true
```

보유한 비밀번호는 `Can(Verifier)`에도 응답합니다. 비교할 수 있기 때문입니다.

{{< callout type="info" >}}
**빈 그룹도 그룹입니다: `Members`는 응답하고, `Expand`는 거부합니다**

v0.12.0부터 `Set.Members`는 소스에 있지만 구성원이 없는 그룹에 대해 오류 없이 빈
목록을 반환하므로, 그룹을 나열하는 서버가 그것을 게시할 수 있습니다. `Expand`는 여전히
`ErrEmptyGroup`으로 거부하며, 이는 `ErrNoSuchGroup`이 아닙니다. 아무도 가지지 않은
그룹은 오타이거나 삭제된 그룹이고, 빈 그룹은 채워야 할 그룹입니다. 아무것도 허용하지
않는 그룹을 용인하는 호출자는 둘 다 검사합니다. v0.11.x에서는 `Set.Members`가 빈
그룹에 대해 `ErrNoSuchGroup`을 반환했고, `Set`을 통한 `@nobody`의 `Expand`는
`[] directory: no such group: "nobody"`를 출력했습니다.
{{< /callout >}}

## 속성 {#attributes}

v0.13.0부터 `Identity`는 **속성**을 담을 수 있습니다. 소스가 누군가에 대해 말하는 것
중 아무것도 증명하지 않는 것 — `uidNumber`, 홈 디렉터리, 메일 주소 — 입니다. 이는
의도적으로 자격 증명과 분리되어 있습니다. 자격 증명은 누가 로그인할 수 있는지를
결정하고, 속성은 검색이 허용된 모든 사람에게 *게시됩니다.*
[authnd]({{< relref "/authnd/entries.md" >}}) 같은 서버는 이를 LDAP 엔트리의 속성으로
바꾸며, 그 스키마가 엔트리가 무엇인지를 결정합니다.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	a, err := directory.NewAttributes(
		directory.Attribute{Name: "uidNumber", Values: []string{"1000"}},
		directory.Attribute{Name: "mail", Values: []string{"dora@example.org"}},
		directory.Attribute{Name: "MAIL", Values: []string{"d.explorer@example.org", "dora@example.org"}},
	)
	fmt.Println(err)
	dora := directory.NewIdentity("dora", directory.WithPassword("hunter2"), directory.WithAttributes(a))
	fmt.Println(dora.Attributes().Names(), dora.Attributes().Get("UIDNUMBER"), dora.Attributes().Get("mail"))

	// What is published cannot hold a secret, nor what a server derives or answers itself.
	for _, name := range []string{"userPassword", "sambaNTPassword", "radiusHash", "cn", "memberUid", "2.5.4.35"} {
		_, err := directory.NewAttributes(directory.Attribute{Name: name, Values: []string{"x"}})
		fmt.Println(errors.Is(err, directory.ErrAttributeName), err)
	}
}
```

```
<nil>
[uidNumber mail] [1000] [dora@example.org d.explorer@example.org]
true directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "sambaNTPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "radiusHash" looks like it holds a secret (its name contains "hash"), and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "cn" is derived by the server from the name it publishes the entry under
true directory: not an attribute this package carries: "memberUid" is membership, which Members answers: a second answer would disagree with it
true directory: not an attribute this package carries: "2.5.4.35" is an OID: name it by its descriptor, so that what is refused by name stays refused
```

이름은 RFC 4512 속성 설명이며 대소문자와 옵션의 순서를 무시하고 비교하므로, `mail`과
`MAIL`은 처음 주어진 표기를 따르는 하나의 속성입니다. 값이 정확히 반복되면 한 번만
유지됩니다. 값은 문자열이며 해석되지 않습니다. `"1000"`이 `uidNumber`인 것은 서버의
스키마가 그렇게 말하기 때문입니다. 빈 값, 또는 값이 없는 것은 거부됩니다.

| 거부되는 것 | 이유 |
|---|---|
| 이름이 있는 비밀 값 56개 — `userPassword`, `authPassword`, `userPKCS12`, `sambaNTPassword`, `sambaLMPassword`, `unicodePwd`, `krbPrincipalKey`, `krb5Key`, `ipaNTHash`, `ipatokenOTPkey`, `oathSecret`, `olcRootPW`, … | RFC 4519, RFC 3112, RFC 2798과 Samba, Active Directory, MIT 및 Heimdal Kerberos, FreeIPA, 389-ds, OpenLDAP 스키마에서 가져옴 |
| `password`, `passwd`, `pwd`, `secret`, `credential`, `hash`, `privatekey`를 포함하는 모든 이름 | 목록은 누군가 읽은 스키마만 알 수 있습니다. 이것이 잡게 될 유일한 표준 이름인 `secretary`(RFC 4524)는 허용됩니다 |
| `sshPublicKey` | 자체 경로 `WithPublicKeys`가 있어서 `Can(PublicKeys)`가 계속 true |
| `uid`, `userid`, `cn`, `commonName`, `objectClass` | 서버가 엔트리를 게시하는 이름에서 파생함 |
| `member`, `uniqueMember`, `memberUid`, `memberOf` | 구성원은 `Members`가 답하는 것이며, 두 번째 답은 어긋나게 됨 |
| `createTimestamp`, `modifyTimestamp`, `creatorsName`, `modifiersName`, `structuralObjectClass`, `governingStructureRule`, `subschemaSubentry`, `entryDN`, `entryUUID` | 서버가 유지하는 것이며, 구성은 위조만 할 수 있음 |
| 숫자 형식의 이름 | 거부는 이름으로 하는데, `2.5.4.35`는 `userPassword`임 |

`ReservedAttributes()`는 이유와 함께 75개 이름의 전체 목록을 반환하며,
`CheckAttributeName`은 규칙만 적용하므로 아무것도 읽기 전에 구성을 거부할 수
있습니다.

출처:

- **`hcldir`**: `user`와 `group` 블록의 `attributes = { … }`, 이름마다 문자열 또는
  문자열 목록. 숫자는 메시지에 해결 방법과 함께 거부되며(*write it as a string,
  "1000"*), `null`은 속성을 생략합니다.
- **`sqldir`**: 선택적 쿼리 두 개 `users_attributes`와 `groups_attributes`
  (`Queries.PeopleAttributes`, `GroupAttributes`)가 **열 별칭으로** 읽습니다. 첫 번째
  열은 이름이고 나머지 모든 열은 별칭이 이름이 되는 속성입니다. 별칭이 속성 설명이
  아니거나 자격 증명을 지정하는 열은 행을 읽기 전에 열 번호와 함께 거부됩니다.
  `NULL`과 `''`는 없는 것이고, 한 이름의 여러 행은 값을 더합니다. 거기에서만 지정된
  그룹은 구성원 없이 존재합니다.
  ⛔ PostgreSQL은 따옴표 없는 별칭을 소문자로 바꿉니다(`as uidNumber`는
  `uidnumber`로 돌아옵니다). 데이터베이스 방식으로 표기된 같은 속성입니다. 표기가
  중요한 곳에서는 `as "uidNumber"`처럼 따옴표를 쓰십시오.
- **`ldapdir`**: `Config.Attributes`와 `GroupAttributes`(`users "ldap"` 블록의
  `attributes`와 `group_attributes`)가 각 사람의 엔트리와 각 그룹의 엔트리에서
  무엇을 복사할지 지정하며, RFC 4512 동등성으로 일치시키고 구성된 표기로
  유지합니다. 위의 목록에 더해 `totp_attribute`와 그룹의 이름 및 구성원 속성도
  거부합니다. 디렉터리가 추가로 반환하는 하위 타입(`description`에 대한
  `description;lang-fr`)은 복사하지 않습니다. 이름으로 요청하십시오.

그룹의 속성은 선택적 `GroupAttributer`를 통해 `Set.GroupAttributes`에서 오며,
**속성을 처음 제공하는 소스가 그것을 소유합니다.** 그래서 로컬 파일의 `gidNumber`는
디렉터리의 것을 덮어쓰지만 디렉터리에만 있는 `description`은 그대로 전달되고, 다른
소스가 답했더라도 고장 난 소스는 오류입니다. 사람의 속성은 그 이름을 소유한 소스에서
사람과 함께 옵니다.

## ldapdir의 기본값 {#ldapdir-defaults}

| 설정 (`users "ldap"` / `ldapdir.Config`) | v0.14.0부터의 기본값 | v0.13.0까지 |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`, `ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | 동일 |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | 동일 |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`, `ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | 동일 |
| `group_member_attribute` / `MemberAttribute` | 없음: `memberUid`(이름) **그리고** `member`(DN). 설정하면 그 속성 하나만 읽음 | `memberUid` |

세 클래스는 `uid`를 가지는 표준 클래스입니다. `posixAccount`(RFC 2307), `account`(RFC
4524 §3.1), `uidObject`(RFC 4519 §3.14). go-authn/authnd v0.11.0부터는 POSIX 속성이
없는 사람을 `account` 또는 `inetOrgPerson`으로 게시하고, 모든 사람에게 `uidObject`를
붙이며, `gidNumber`가 없는 그룹을 `groupOfNames`로 게시합니다. 이전 기본값에서는
그런 사람과 그룹을 전혀 읽지 않았습니다.

{{< callout type="warning" >}}
**v0.14.0은 기관의 디렉터리가 제공하는 범위를 넓힙니다**

posixAccount가 아닌 `account`나 `uidObject` 엔트리 — 서비스 계정, uid로 이름 붙은
호스트, 다른 곳에서 가져온 사람 — 를 담은 디렉터리는 이제 기본값을 유지한 모든
프로그램에 그것들을 제공하며, 각각은 바인드로 디렉터리와 대조해 확인할 수 있습니다.
`groupOfNames` 그룹은 그룹이 되고, 그중 하나를 지정하는 `@group` 규칙은 이제 말한
대로 권한을 부여합니다. 세 클래스 중 어느 것도 없는 일반 `inetOrgPerson`은 여전히
읽지 않습니다. 이전의 집합을 정확히 유지하려면:

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**`member` DN은 사람을 추가하지 않습니다.** distinguishedNameMatch(RFC 4517
§4.2.15)에 의해 사람 검색이 반환한 엔트리의 DN일 때만 누군가에게 매핑됩니다. 그
엔트리들 밖의 DN이나 아무도 지정하지 않는 DN은 아무에게도 매핑되지 않으며,
alice를 `ou=people`에서 가져왔다면 `uid=alice,ou=elsewhere,…`도 마찬가지입니다.
v0.13.0까지는 member 속성의 DN이 누구의 것이든 첫 RDN의 값으로 줄어들어,
`uid=alice,ou=elsewhere,…`, `cn=alice,…`, `uid=zed,…`가 alice, alice, zed라는 이름의
구성원이 되었습니다.

테스트 디렉터리인 `ldaptest`는 이제 모든 검색에 베이스와 필터를 적용하고, 각 사람에게
`objectClass`를 부여하며(`Person.ObjectClasses`, 기본값은 `top`, `account`,
`posixAccount`) `groupOfNames` 그룹(`GroupsOfNames`)을 갖습니다. 그래서 클라이언트의
필터에 대한 테스트가 실패할 수 있습니다.

## 거부하는 것과 그 이유 {#what-it-refuses-and-why}

- **구성원이 없는 그룹**, 그리고 **어떤 소스에도 없는 그룹**을 `Expand`가 `@group`을
  사람으로 바꿀 때 — 빈 목록이 아니라 오류입니다. 아무에게도 아무것도 허용하지 않는
  구성은 제대로 동작하는 구성과 똑같이 읽히기 때문입니다. 첫 번째는 `ErrEmptyGroup`,
  두 번째는 `ErrNoSuchGroup`이며 `errors.Is`로 구별합니다. `Set.Members`는 빈 그룹에
  빈 목록으로 답하고, 어떤 소스에도 없는 그룹은 거기서도 `ErrNoSuchGroup`입니다.
  *고장 난* 소스는 그룹이 없는 소스와 별도로 보고되며 빈 응답보다 우선합니다.
- **평문으로 접근하는 LDAP 디렉터리.** 단순 바인드는 비밀번호 자체를 전달하므로(RFC
  4513), `ldapdir.New`와 `users "ldap"` 블록은 `StartTLS`가 설정되지 않은 다른 머신으로의
  `ldap://`를 거부합니다. `ldaps://`, `ldapi://`, 루프백 주소로의 `ldap://`는
  받아들여집니다. 이를 끄는 스위치는 없습니다.
- **LDAP 바인드의 빈 비밀번호.** LDAP에서는 *비인증 바인드*이며 대부분의 디렉터리가
  성공으로 응답합니다. `ldapdir`은 연결하지 않고 `ErrWrongPassword`로 응답합니다.
- **잘못된 비밀번호로 오인되는 다른 모든 실패한 바인드.** LDAP 결과 49,
  *invalidCredentials*만 `ErrWrongPassword`입니다. 바인드 도중 끊어진 연결, 바쁨(51)
  또는 사용 불가(52)로 응답하는 디렉터리는
  `ldapdir: the directory did not answer the bind: …`로 반환되며 LDAP 오류를 감쌉니다.
  비밀번호는 어느 쪽이든 거부됩니다. 달라지는 것은 서버의 로그가 올바르게 입력한
  사람에게 *wrong password*라고 말하지 않는다는 점입니다. v0.11.2 이전에는 실패한 모든
  바인드가 `ErrWrongPassword`였습니다.
- **LDAP URL 안의 자격 증명** — URL은 출력됩니다. `BindDN`과 `BindPassword`는
  필드입니다.
- **16바이트가 아닌 NT 해시**(`ParseNTHash`). 모든 로그인을 잘못된 비밀번호로
  실패시키는 해시로 채워 넣지 않습니다.
- **비밀번호가 없는 신원에 대한 `Derive` 또는 `KerberosKey`.** 검증자의 yes는 키가
  아닙니다.
- **비밀 값이거나 서버가 스스로 답하는 속성** —
  [위의 목록]({{< relref "/libraries/directory.md#attributes" >}}) — 블록에서든, SQL 별칭으로든,
  ldapdir의 복사 목록에서든 어디에 구성되어 있더라도.

{{< callout type="warning" >}}
**NT 해시와 TOTP 비밀 값은 자격 증명이며, 자격 증명의 해시가 아닙니다**

`sambaNTPassword`를 가진 사람은 비밀번호를 가진 것과 똑같이 그 사람으로 인증됩니다.
TOTP 비밀 값을 가진 사람은 앞으로의 모든 코드를 만들어 냅니다. `WithVerifier`의
오류는 서버에 전달되며 클라이언트에는 절대 전달되지 않습니다.
{{< /callout >}}

## 무엇과 대조해 검사하는가 {#what-it-is-checked-against}

- **OpenLDAP의 `ldapsearch`**가 `ldaptest`의 디렉터리 — 엔트리, 가진 한 사람의
  `sambaNTPassword`, 그룹 — 를 읽으며, 잘못된 비밀번호에는 *Invalid credentials
  (49)*로 거부됩니다. CI의 Linux 레인은 `ldap-utils`를 설치합니다. `ldapsearch`가 없으면
  테스트는 건너뛰며, 이 모듈의 CI에서 그 건너뛰기를 실패로 바꾸는 것은 없습니다.
- **`glauth/ldap`에 대한 `ldapdir`**: 가짜가 아닌 독립적인 LDAP 서버이며, 픽스처가
  비인증 바인드를 허용하므로 `ldapdir`이 먼저 그것을 거부하지 않게 되면 테스트가
  실패합니다.
- **실제 SQLite 데이터베이스에 대한 `sqldir`**, 실제 드라이버를 통해. 속성 쿼리는
  CI가 아니라 PostgreSQL 18.6에 pgx로 한 번 직접 실행했습니다. 따옴표 없는 별칭은
  소문자로 돌아왔지만 그래도 발견되었고, 따옴표 있는 별칭은 대소문자를 유지했으며,
  `userPassword`를 지정하는 별칭은 거부되었습니다.
- **`ldaptest`에 대한 ldapdir의 필터**, v0.14.0부터 이를 적용합니다. 기본 사용자
  필터는 일반 `inetOrgPerson`을 제외하고(`TestTheDefaultUserFilter`), 그룹 필터는
  신원을 추가하지 않습니다(`TestTheGroupFilterAddsNoIdentity`).
- **RFC 1320의 테스트 벡터에 대한 MD4**.

커버리지 레인은 85% 미만이면 실패하며(공표된 기준은 100%), `nosql`과 `noldap` 빌드는
CI에서 검사합니다.

## 참고 {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
