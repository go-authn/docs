---
title: "사이트 스키마와 소스가 선언하는 클래스"
linkTitle: "사이트 스키마"
weight: 27
description: "SUPANN, eduPerson 또는 사이트 고유의 속성을 제공합니다. schema_files와 schema 블록은 정의를 추가하고, object_classes는 소스의 사람과 그룹이 갖는 보조 클래스를 선언하며, check는 무엇이 빠졌는지 알려 줍니다."
tags: [authnd, ldap, 스키마, 구성]
---

**SUPANN이나 eduPerson 속성은 엔트리의 어떤 클래스도 허용하지 않으면 제외됩니다.**
authnd는 제공하는 스키마가 허용하는 것만 게시하며
([엔트리]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})를 참조),
표준 스키마는 `supannEtablissement`나 `eduPersonAffiliation`을 알지 못합니다.
v0.12.0부터 사이트는 다음 세 가지를 이 순서로 지정합니다.

1. **추가할 정의**: `schema_files`, 즉 사이트의 slapd가 이미 불러오는 파일과,
   로컬에서만 쓰는 것을 위한 `schema { }` 블록
2. **사람과 그룹이 갖는 보조 클래스**: `object_classes`
3. 그 밖에는 없습니다. 클래스는 **선언되는 것이지 추론되지 않습니다.** 데이터베이스에
   속성이 나타난다고 해서 엔트리가 무엇으로 게시되는지가 바뀌지는 않습니다.

{{< callout type="info" >}}
**이 페이지의 예제는 예제입니다**

아래의 `example.schema`는 이 페이지를 위해 작성되었습니다. OID는 아무에게도 할당되지
않은 `1.3.6.1.4.1.99999` 아래에 있으므로, 여러분 자신의 것을 사용하고 이것을 절대
복사하지 마십시오. SUPANN은 [페이지 끝](#supann)을 참조하십시오.
{{< /callout >}}

## 예제: 스키마, 데이터베이스, 구성 {#an-example}

OpenLDAP의 `.schema` 형식으로 작성한 스키마입니다. 소스가 선언할 수 있는 클래스
하나(`exampleStaff`, AUXILIARY, MUST 있음)와 선언할 수 없는 클래스
하나(`exampleUnit`, STRUCTURAL)가 있습니다.

```
objectidentifier exampleRoot  1.3.6.1.4.1.99999
objectidentifier exampleAttr  exampleRoot:1
objectidentifier exampleClass exampleRoot:2

attributetype ( exampleAttr:1 NAME 'exampleBadge'
	DESC 'the number on a badge'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

attributetype ( exampleAttr:2 NAME 'exampleEmployeeId'
	DESC 'a staff number'
	EQUALITY caseExactMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

# AUXILIARY: it can be declared. exampleStaff has a MUST.
objectclass ( exampleClass:1 NAME 'exampleStaff' SUP top AUXILIARY
	DESC 'somebody employed: has a staff number'
	MUST exampleEmployeeId
	MAY exampleBadge )

# STRUCTURAL: it cannot be declared (an entry has one structural chain).
objectclass ( exampleClass:2 NAME 'exampleUnit' SUP top STRUCTURAL
	MUST cn )
```

`sn`, 배지, 직원 번호를 가진 세 사람의 SQLite 데이터베이스입니다
(`sqlite3 var/people.db < people.sql`).

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

그리고 구성입니다.

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

# Files first, then the blocks: a definition may use anything before it.
schema_files = ["etc/authnd/example.schema"]

schema {
  attribute_type "exampleLocker" {
    oid    = "1.3.6.1.4.1.99999.1.3"
    syntax = "1.3.6.1.4.1.1466.115.121.1.15"
  }
  object_class "exampleLockerHolder" {
    oid  = "1.3.6.1.4.1.99999.2.3"
    kind = "auxiliary"
    may  = ["exampleLocker"]
  }
}

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret from staff"
  users_attributes = "select login, sn, badge as exampleBadge, empid as exampleEmployeeId, locker as exampleLocker from person_attrs"
  object_classes   = ["exampleStaff", "exampleLockerHolder"]   # declared, never inferred
}
```

`object_classes` 줄이 없으면, `check`는 표준 스키마만으로 같은 사람들을 어떻게
처리하는지 알려 줍니다. 속성이 제외되며, 각 줄은 그 속성을 유지했을 클래스를
지정합니다.

```
$ authnd check cases/nodecl.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes

USER  FROM               CAN PROVE   PUBLISHED AS                                            WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ann is published without exampleBadge: no class of the entry allows it; exampleStaff would
ann is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
cat is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## `schema_files` {#schema-files}

`schema_files`는 OpenLDAP `.schema` 파일 또는 cn=config LDIF 파일의 목록입니다.
이 파일들은 표준 스키마(그리고 [`samba` 블록]({{< relref "/authnd/tls.md#the-samba-block" >}})을
쓰는 경우 Samba의 정의 세 개) 위에 **게시된 그대로** 순서대로 로드되며,
go-authn/ldap의 [slapd 호환 리더]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})가
읽습니다. 용어의 순서는 자유이고, slapd와 RFC 2849 연속 줄, base64, `{N}` 길이
접두사, 그리고 한 파일이 정의하고 다음 파일이 사용할 수 있는 `objectidentifier`
매크로(slapd의 `include`를 가로지르는 것과 같습니다)를 지원합니다. 미리 변환하는 것은
없으므로, 사이트의 slapd가 로드하는 파일이 곧 authnd가 로드하는 파일입니다. 정의는
`cn=Subschema`에서 제공됩니다.

- 상대 경로는 구성의 다른 모든 경로와 마찬가지로 작업 디렉터리를 기준으로 합니다.
  서비스에서는 절대 경로를 사용하십시오. systemd 유닛의 작업 디렉터리는 `/`입니다.
- 각 파일은 최대 4 MiB의 일반 파일이어야 하며, 시작 시 한 번 읽습니다.
- 파일은 모든 엔트리가 가질 수 있는 것을 결정합니다. 비밀은 아니지만 나머지 구성과
  함께 보관하십시오. `root:authnd`, 모드 `0640`, root만 쓸 수 있는 디렉터리입니다
  ([설치]({{< relref "/authnd/install.md" >}})).
- 빌드되지 않는 파일은 시작과 `check`를 거부하며, 파일, 정의가 시작되는 줄과
  열, 그리고 메시지 끝에 거부의 종류를 알려 줍니다. 알 수 없는 상위 클래스, 속성,
  매칭 규칙 또는 구문(`unknown reference`), AUXILIARY 클래스에서 파생된 STRUCTURAL
  클래스(`kind violation`), 두 번 정의된 OID 또는 이름(`duplicate OID`,
  `duplicate name`)이 그 예입니다. v0.12.1부터 위치와 종류는 메시지를 읽어서가
  아니라 go-authn/ldap의 타입이 있는
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}})에서 옵니다.
  파일에서 읽은 정의는 여러 줄에 걸쳐 접혀 있어도 1열에서 시작합니다. 중복은 첫
  번째 정의가 어디 있는지 알려 주고, 재정의는 원본이 어느 표준 파일에, 또는 앞선
  파일의 어느 줄에 있는지 알려 줍니다. 두 가지 예입니다.

  `cases/unknown.schema`에는 어디에도 정의되지 않은 MAY가 있습니다.

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema`는 하나의 OID를 두 속성 타입에 부여합니다.

  ```
  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleA'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )

  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleB'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )
  ```

  ```
  $ authnd check cases/twice.hcl
  authnd: schema_files: cases/twice.schema:4:1: the attribute type 1.3.6.1.4.1.99999.1.9 is defined twice (first defined at cases/twice.schema:1:1) (duplicate OID)
  ```

### 재정의는 동일하더라도 거부됩니다 {#redefinition}

파일은 이미 있는 것을 정의할 수 없습니다. 표준 스키마의 정의, Samba의 정의, 앞선
파일의 정의가 그렇습니다. **한 글자도 다르지 않더라도** 거부되며, 이는 slapd 자신의
규칙입니다. 스키마 파일의 정의는 `parse_at`과 `parse_oc`를 거치고, slapd는 이미
색인된 OID나 이름에 대해 *Duplicate attributeType*(OID와 이름이 같은 경우) 또는
*Inconsistent duplicate attributeType*으로 답합니다(`servers/slapd/at.c`, `oc.c`).
앞의 것은 slapd 자신의 하드코딩된 스키마에만 허용됩니다. slapd가 거부하는 파일은
authnd도 거부합니다.

다른 해석이라면 승자를 골라야 하는데, 그것은 모든 클라이언트가 표준 속성에 대해
듣는 내용을 조용히 바꾸는 일입니다. 거부하면 해당 줄을 알려 줄 수 있습니다. 거부
메시지는 텍스트가 같았는지도 알려 줍니다. `cn`(2.5.4.3)을 자체 정의로 재정의하는
파일은 다음과 같습니다.

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## `schema { }` 블록 {#the-schema-block}

로컬에서만 쓰는 정의를 위해, `schema` 블록은 이를 HCL2로
[hclschema의 형태]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})에 맞춰
담습니다. `attribute_type`, `object_class`, `object_identifier`, `matching_rule`,
`ldap_syntax`입니다. 파일 **뒤에** 읽히므로 파일의 정의를 사용할 수 있으며, 여러 개를
둘 수 있습니다.

값은 **리터럴**이어야 합니다. 변수도, 함수도, `${...}`나 `%{...}`도 안 됩니다. 블록은
`.hcl` 스키마 파일을 읽는 것과 같은 디코더로, 같은 한도로 디코딩되며, 모든 오류는
구성 자체의 줄과 열을 알려 줍니다. HCL의 네이티브 구문이 아닌 블록은 거부됩니다.

## `object_classes` {#object-classes}

스키마의 정의는 속성을 허용할 뿐이며, 클래스를 누군가에게 붙이지는 않습니다. 소스는
자신의 사람과 그룹이 함께 게시되는 보조 클래스를 **선언**합니다.

| 위치 | 키 | 선언하는 것 |
|---|---|---|
| `users` 블록, 모든 종류 | `object_classes` | 블록이 제공하는 모든 사람의 클래스 |
| `users` 블록, 모든 종류 | `group_object_classes` | 모든 그룹의 클래스 |
| `user` 블록 | `object_classes` | 그 사람의 클래스 |
| `group` 블록 | `object_classes` | 그 그룹의 클래스 |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

이 키들은 v0.15.0부터의 go-authn/directory의 것입니다
([라이브러리]({{< relref "/libraries/directory.md#object-classes" >}})). 이름은 대소문자를
무시하고 비교되며, 쓴 순서대로 한 번씩만 유지됩니다.

authnd가 선언된 클래스로 하는 일은 다음과 같습니다.

- **상위 클래스와 함께 게시됩니다.** authnd가 도출하는 클래스 뒤에 옵니다(RFC 4512
  §3.3: 지정된 클래스의 모든 상위 클래스가 암묵적으로 추가됨). 클래스가 허용하는
  속성은 제외되지 않고 유지됩니다.
- **결코 추론되지 않습니다.** 소스가 아무것도 선언하지 않는 사람은, 데이터베이스에
  무엇이 있든 자신의 어떤 클래스도 허용하지 않는 속성을 계속 잃습니다.
- **선언된 클래스의 MUST가 없는 사람은 그 클래스 없이 게시됩니다.** 그 속성은 어떤
  클래스도 허용하지 않는 속성처럼 제외되며, 둘 다 보고됩니다. 이것이 authnd가 어디서나
  따르는 규칙입니다. 사람은 계속 게시되고, 문제는 알려지며, 아무것도 조용히 바뀌지
  않습니다. 속성 하나가 없다고 사람을 보류하면 그 사람이 모든 검색에서 빠지게 되고,
  MUST 없이 클래스를 게시하면 제공하는 스키마를 통과하지 못하는 엔트리를 제공하게
  됩니다.
- **두 소스가 한 그룹에 대해 서로 다른 클래스를 선언할 수 있습니다.** 그룹의 클래스를
  처음 선언하는 소스가 전체를 결정하고, 이후의 목록은 병합되지도 오류가 되지도 않고
  무시됩니다. `check`가 이를 알려 줍니다.

여기서 ann은 모든 것을 갖고 있고, cat은 사물함이 없으며(MAY), ben은
`exampleStaff`의 MUST인 `exampleEmployeeId`가 없습니다.

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people

USER  FROM               CAN PROVE   PUBLISHED AS                                                                               WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn, exampleBadge, exampleEmployeeId and exampleLocker
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder                uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn and exampleEmployeeId

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder
ben is published without exampleStaff, which its source declares: ben has no exampleEmployeeId, which exampleStaff requires
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

시작 로그에도 같은 줄이 DN과 함께 나옵니다.

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 3 people from a sqlite database
schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people
uid=ben,ou=people,dc=example,dc=org is published without exampleStaff, which its source declares: uid=ben,ou=people,dc=example,dc=org has no exampleEmployeeId, which exampleStaff requires
uid=ben,ou=people,dc=example,dc=org is published without exampleBadge: no class of the entry allows it; exampleStaff would

stopping
```

그리고 OpenLDAP의 `ldapsearch`가 되읽는 내용입니다. reader의 비밀번호는 파일에
있습니다. ann은 두 보조 클래스와 그것들이 허용하는 모든 속성을 갖습니다. ben은
`exampleLockerHolder`만 갖고, 그의 배지는 `exampleStaff`와 함께 사라졌습니다. cat은
둘 다 갖고 직원 번호도 있습니다.

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(uid=*)'
dn: uid=ann,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: ann
cn: ann
sn: Archer
exampleBadge: B-0001
exampleEmployeeId: E-1001
exampleLocker: L-12

dn: uid=ben,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleLockerHolder
uid: ben
cn: ben
sn: Brook

dn: uid=cat,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: cat
cn: cat
sn: Cole
exampleEmployeeId: E-1003

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(objectClass=exampleStaff)' 1.1
dn: uid=ann,ou=people,dc=example,dc=org

dn: uid=cat,ou=people,dc=example,dc=org
```

## 거부되는 것과 그 이유 {#what-is-refused}

선언된 클래스는 시작 시, 그리고 `check`에서 제공하는 스키마와 대조해 검사됩니다.
다음을 만족해야 합니다.

- 표준 스키마, 파일 또는 블록에 의해 **정의되어** 있을 것
- **AUXILIARY**일 것(RFC 4512 §4.1.1). 엔트리에는 정확히 하나의 구조 체인이 있으며
  (§2.4.2), 이는 사람이 가진 것을 보고 authnd가 고릅니다. 선언으로 두 번째 체인을
  추가할 수는 없습니다.
- **authnd가 스스로 도출하는 클래스가 아닐 것**: `account`, `inetOrgPerson`과 그
  상위 클래스, `posixAccount`, `posixGroup`, `ldapPublicKey`, `uidObject`,
  `sambaSamAccount`, `groupOfNames`, `organizationalRole`이며, 어떤 이름으로 쓰든
  마찬가지입니다. 이것들은 사람이나 그룹이 가진 것으로부터 정해지며, 선언이 `check`를
  뒤집을 수는 없습니다.

그렇지 않으면 시작이 거부되며, 블록과 그 위치와 클래스를 알려 줍니다.
`exampleUnit`은 STRUCTURAL입니다.

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory는 그에 앞서 **철자**를 검사합니다. 클래스는 디스크립터이며, OID도,
공백도, 따옴표도, 괄호도 아닙니다.

스키마의 정직함을 지키려는 같은 이유로 다음도 거부됩니다.

| 거부되는 것 | 이유 |
|---|---|
| 정의를 재정의하는 파일, 한 글자도 다르지 않더라도 | slapd의 규칙: [위](#redefinition) |
| 일반 파일이 아니거나 4 MiB를 넘는 파일 | FIFO는 시작을 막고, `/dev/zero`는 끝나지 않음 |
| 변수, 함수 또는 `${...}`가 있는 `schema` 블록 | `.hcl` 스키마 파일처럼 리터럴 값만 |
| `object_classes`의 정의되지 않은 클래스 | 아무것도 검사할 수 없는 약속 |
| STRUCTURAL 클래스, 또는 authnd가 도출하는 클래스 | 위의 목록 |

## `check`가 출력하는 것 {#what-check-prints}

[평소의 줄]({{< relref "/authnd/check.md" >}}) 위에 네 종류의 줄이 더해지며, 시작 로그에도
같은 줄이 나옵니다.

- **`schema: <file> adds …`**와 **`schema: the schema block at <file>:<line>:<column> adds …`**:
  각 파일과 각 블록이 추가한 것을 오브젝트 식별자 매크로, 속성 타입, 오브젝트 클래스로
  센 것
- **`<file>:<line>:<column>: users "sql" declares … for its people`**(`user` 또는
  `group` 블록은 `user "ann" declares … for this person`, `group "staff" declares …
  for this group`이라고 함): 각 소스가 선언하는 것
- **`<name> is published without <class>, which its source declares: …`**: 그 사람에게
  없는 MUST를 지정함
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`**:
  그룹에 대해 두 소스가 일치하지 않는 경우이며, 그렇지 않으면 조용히 지나갈 것입니다.

클래스가 없어서 제외된 속성은 `is published without
<attribute>: no class of the entry allows it; <classes> would` 줄이며
[엔트리]({{< relref "/authnd/entries.md" >}})가 이미 설명한 것입니다. 선언이 있으면 이
줄은 아직 선언하지 않은 클래스를 알려 줍니다.

## 실제 예제로서의 SUPANN {#supann}

SUPANN은 프랑스 고등 교육 및 연구 기관의 속성 집합(`supannPerson`,
`supannEtablissement`, `supannEntite`…)이며, eduPerson이 곁에 있습니다. RENATER는 다른
것들과 함께 기술 스키마를 문서 페이지에 게시합니다.

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**파일은 거기서 내려받으십시오.** 이 사이트에는 복제하지 않습니다. 라이선스를
명시하고 있지 않으므로 이 페이지는 복사하지 않으며, 여기의 사본은 RENATER가
개정하면 낡아 버립니다. 그다음:

```sh
sudo install -o root -g authnd -m 0640 supann.schema eduperson.ldif /etc/authnd/
```

```hcl
schema_files = ["/etc/authnd/supann.schema", "/etc/authnd/eduperson.ldif"]

users "sql" {
  # ...
  users_attributes     = "select login, sn, etab as \"supannEtablissement\" from staff"
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}
```

`authnd check`를 실행하고 먼저 `schema:` 줄을 읽으십시오. slapd가 로드하는 파일은 여기서도
로드되며, 표준 정의를 재정의하는 파일은 그 줄과 함께 거부됩니다. 그다음 *published
without* 줄을 읽으십시오. `supannPerson`이나 `eduPerson`의 MUST가 없는 사람은 그 클래스 없이
게시되며, `check`가 그 MUST를 알려 줍니다. 철자가 중요한 곳에서는 별칭에 따옴표를 쓰십시오
(PostgreSQL은 따옴표 없는 별칭을 소문자로 바꿉니다.
[엔트리]({{< relref "/authnd/entries.md#in-a-sql-database" >}})를 참조).

{{< callout type="info" >}}
**트랜스크립트에 대하여**

이 페이지의 모든 명령은 2026-10-26에 v0.12.3 릴리스 바이너리(`authnd-darwin-arm64`, `SHA256SUMS`와 대조함; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`)와 OpenLDAP의 `ldapsearch`로, 127.0.0.1에서 임시 디렉터리에 보여 준 파일을 두고 다시 실행한 것입니다. 경로가 상대 경로인 것은 그 때문이며, 서비스에서는 절대 경로를 사용합니다. 스키마는 이 페이지를 위해 작성한 예제입니다.
{{< /callout >}}
