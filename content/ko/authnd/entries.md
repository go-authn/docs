---
title: "authnd가 게시하는 엔트리와 제공하는 스키마"
linkTitle: "엔트리와 스키마"
weight: 25
description: "각 사람과 그룹이 무엇으로 게시되는지, 모든 엔트리가 통과하는 cn=Subschema의 스키마, 파일이나 SQL 쿼리로 속성을 추가하는 방법, 그리고 제외되거나 보류되는 것."
tags: [authnd, ldap, 스키마, sql]
---

**authnd가 게시하는 모든 엔트리는 자신이 제공하는 스키마를 통과합니다.** v0.11.0부터
각 사람과 그룹은 소스가 제공한 것으로 만들어지는 표준 스키마 엔트리이며,
검색으로 반환되기 전에 go-authn/ldap의 `schema.Validate`로 클라이언트가
`cn=Subschema`에서 읽을 수 있는 스키마에 맞게 검사됩니다. 스키마를 읽고 믿는
클라이언트 — LDAP 브라우저, 동기화 도구, 이 디렉터리를 복제하는 디렉터리 — 는
들은 대로의 내용을 보게 됩니다. v0.10.2까지는 모든 사람이 `top, person,
posixAccount`였고 그 클래스가 요구하는 속성은 하나도 없었으며,
`sambaNTPassword`는 그것을 허용하는 클래스가 없는 엔트리에 붙어 있었습니다.

{{< callout type="warning" >}}
**`posixAccount`나 `posixGroup`으로 필터링하는 소비자는 더 적은 엔트리를 봅니다**

`uidNumber`, `gidNumber`, `homeDirectory`가 없는 사람은 더 이상
`posixAccount`가 아니고, `gidNumber`가 없는 그룹은 더 이상 `posixGroup`이
아닙니다. `(objectClass=posixAccount)`나 `(objectClass=posixGroup)`을 검색하는
프로그램은 더 이상 이들을 찾지 못합니다. 여기에는 v0.13.0까지의 go-authn/directory
`ldapdir`이 포함되며, 따라서 `account`, `uidObject`, `groupOfNames`도 읽는 기본값을
가진 directory v0.14.0을 요구하기 전까지의 go-fileshare도 포함됩니다
([directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})).
사람과 그룹에 해당 속성을 부여하거나, 모든 사람이 가지고 있는
`(objectClass=uidObject)`를 소비자가 사용하도록 지정하십시오.
{{< /callout >}}

## 형태 {#the-shapes}

RFC 4512 §3.3이 요구하는 대로 모든 상위 클래스가 나열됩니다.

| 이런 사람은… | `objectClass` | `cn` |
|---|---|---|
| `sn`이 없음 | `top`, `account` (RFC 4524 §3.1) | 다른 클래스가 허용할 때만 |
| `sn`이 있음 | `top`, `person`, `organizationalPerson`, `inetOrgPerson` (RFC 4519, RFC 2798) | 예 |
| … 그리고 `uidNumber`, `gidNumber`, `homeDirectory` 세 가지 모두 | `+ posixAccount` (RFC 2307) | 예 |
| … 그리고 SSH 키 | `+ ldapPublicKey` (openssh-lpk), `sshPublicKey` 포함 | |
| … 그리고 `sambaSID`가 있는 게시된 NT 해시 | `+ sambaSamAccount` (Samba), `sambaSID`와 `sambaNTPassword` 포함: [`samba` 블록]({{< relref "/authnd/tls.md#the-samba-block" >}})을 참조 | 허용됨 |
| … 항상 | `+ uidObject` (RFC 4519 §3.14), 그래서 `(objectClass=uidObject)`가 모든 사람을 찾음 | |

| 이런 그룹은… | `objectClass` | 구성원 |
|---|---|---|
| `gidNumber`가 있음 | `top`, `posixGroup` (RFC 2307) | `memberUid`, 이름 |
| `gidNumber`가 없고 구성원이 있음 | `top`, `groupOfNames` (RFC 4519 §3.5) | `member`, 이 서버가 게시하는 DN |
| `gidNumber`가 없고 구성원도 없음 | `top`, `organizationalRole` (RFC 4519 §3.10) | 없음 |
| `gidNumber`가 있고 구성원이 없음 | `top`, `posixGroup` | 없음: 속성에는 값이 최소 하나 있어야 함 |

`uid`는 사람의 이름이며, 클래스가 허용하는 곳에서는 `cn`도 그렇습니다.
`account`만으로는 `cn`이 허용되지 않으므로(MAY는 `description`, `seeAlso`, `l`,
`o`, `ou`, `host`), `sn`도 POSIX 세 가지도 없는 사람은 `uid`만 있고 `cn`은
없습니다.

authnd 자체의 이유로 본 이 선택들의 근거는 다음과 같습니다.

- **`posixGroup`은 draft-howard-rfc2307bis-02가 아니라 RFC 2307을 따릅니다.**
  초안은 `posixGroup`을 AUXILIARY로 만들었고 게시되지 않은 채 만료되었습니다.
  AUXILIARY `posixGroup`에는 옆에 구조 클래스인 `groupOfNames`가 필요한데, 빈
  그룹은 그 `member`를 줄 수 없습니다.
- **`gidNumber`가 없는 빈 그룹에는 `organizationalRole`.**
  `groupOfNames`와 `groupOfUniqueNames`는 둘 다 구성원을 요구하며, 구성원을
  지어내는 방법은 모두 거짓입니다. `member: ""`는 루트 DSE를 가리키고, 그룹 자신의
  DN을 쓰면 그룹이 자기 자신의 구성원이 됩니다. `organizationalRole`은 유일한
  MUST가 `cn`인 표준 구조 클래스이며, `groupOfNames`처럼 `description`, `ou`,
  `seeAlso`를 받습니다.
- **DIT 콘텐츠 규칙 없는 보조 클래스.** RFC 4512 §2.4.3은 구조 클래스에 DIT 콘텐츠
  규칙이 없는 엔트리에 보조 클래스를 두는 것을 금지합니다. 사용 중인 모든 디렉터리
  서버가 이를 허용하며 `Validate`도 마찬가지입니다.

## 속성 추가하기 {#adding-attributes}

소스가 누군가에 대해 말하는 것 중 아무것도 증명하지 않는 것 — `uidNumber`, 홈
디렉터리, 메일 주소 — 은 **속성**이며, 주어진 대로 게시됩니다. 이것들은
v0.13.0부터의 go-authn/directory [속성]({{< relref "/libraries/directory.md#attributes" >}})이고
자격 증명과 분리되어 있습니다. 비밀 값을 담는 이름이나 서버가 직접 파생하는
이름은 아무것도 읽기 전에 거부됩니다.

### `user` 또는 `group` 블록에서 {#in-a-user-or-group-block}

```hcl
user "dora" {
  password_file   = "/etc/authnd/passwords/dora.pw"
  authorized_keys = ["ssh-ed25519 AAAA… dora@laptop"]
  attributes = {
    sn            = "Explorer"          # inetOrgPerson
    uidNumber     = "1000"              # the three: posixAccount
    gidNumber     = "1000"
    homeDirectory = "/home/dora"
    mail          = ["dora@example.org", "d.explorer@example.org"]
  }
}

group "engineers" {
  members    = ["dora", "eli"]
  attributes = { gidNumber = "2000" }   # a posixGroup; without it, a groupOfNames
}
```

값은 문자열이거나 문자열 목록이며, `null`은 그 속성을 생략합니다. 숫자는
거부됩니다. LDAP 값은 문자열이고 authnd는 숫자를 어떻게 표기할지 선택하지
않기 때문입니다.

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

대소문자와 상관없이 같은 방식으로 거부되는 것: 비밀 값을 담는 모든 이름
(`userPassword`, `sambaNTPassword`, `unicodePwd`, `krbPrincipalKey`와 go-authn/directory
목록의 나머지, 또는 `password`, `passwd`, `pwd`, `secret`, `credential`, `hash`,
`privatekey`를 포함하는 모든 이름), `authorized_keys`가 따로 있는 `sshPublicKey`,
서버가 파생하는 `uid`, `cn`, `objectClass`, `members`가 대신 답하는 `member`,
`memberUid` 및 기타 구성원 속성, 서버가 유지하는 운영 속성, 그리고 숫자 형식의
이름(`2.5.4.35`는 `userPassword`입니다).

### SQL 데이터베이스에서 {#in-a-sql-database}

`users "sql"` 블록의 선택적 쿼리 두 개는 **열 별칭으로** 속성을 읽습니다. 첫
번째 열은 사람 또는 그룹의 이름이고, 나머지 모든 열은 별칭이 이름이 되는
속성입니다.

```hcl
users "sql" {
  driver   = "sqlite"
  dsn_file = "/etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

- 위치 기반 `users`와 `groups` 쿼리는 그대로이며, 여섯 번째 위치 열은 여전히
  거부됩니다. 속성은 이름으로, 자신만의 쿼리에서 가져옵니다.
- 별칭이 속성 설명이 아닌 열(`count(*)`처럼 별칭 없는 표현식)이나 자격 증명을
  지정하는 열은 행을 읽기 전에 열 번호와 함께 거부됩니다.
- `NULL`과 `''`는 없는 것으로 취급합니다. 하나의 이름이 여러 행에 나올 수 있으며
  모든 행의 값이 유지되므로, 주소 테이블을 조인하면 한 사람이 여러 개를 갖게
  됩니다.
- `groups_attributes`에서만 지정된 그룹은 구성원이 없는 채로 **존재합니다**.
  사람 자신의 기본 그룹은 이렇게 기록합니다.

{{< callout type="warning" >}}
**별칭의 대소문자는 데이터베이스가 정합니다**

PostgreSQL은 따옴표 없는 별칭을 소문자로 접습니다. `as uidNumber`는
`uidnumber`로 돌아옵니다. 속성 이름은 대소문자를 구분하지 않으므로 같은 속성이고
모든 LDAP 클라이언트에게 같은 엔트리이지만, authnd가 출력하는 표기는 데이터베이스의
것입니다. 표기가 중요한 곳에서는 별칭에 따옴표를 쓰십시오: `gid as "gidNumber"`.
SQLite는 별칭을 쓴 그대로 유지합니다.
{{< /callout >}}

### 다른 LDAP 디렉터리에서 {#from-another-ldap-directory}

`users "ldap"` 블록은 지시받은 속성을 각 사람의 엔트리와 각 그룹의 엔트리에서
복사합니다: `attributes = ["mail", "uidNumber", "homeDirectory"]`와
`group_attributes = ["gidNumber"]`. [사람들]({{< relref "/authnd/people.md#in-another-ldap-directory" >}})을
참조하십시오.

## 구성과 그것이 게시하는 것 {#a-configuration-and-what-it-publishes}

위의 SQL 블록에 reader를 더하고, 다섯 사람과 네 그룹이 든 SQLite 데이터베이스를
v0.11.0 릴리스 바이너리로 검사한 결과입니다.

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER  FROM               CAN PROVE             PUBLISHED AS                                                                         WITH
dora  a sqlite database  a password and 1 key  person, organizationalPerson, inetOrgPerson, posixAccount, ldapPublicKey, uidObject  uid, cn, sn, uidNumber, gidNumber, homeDirectory, mail and sshPublicKey
eli   a sqlite database  a password            account, posixAccount, uidObject                                                     uid, cn, uidNumber, gidNumber and homeDirectory
fay   a sqlite database  a password            person, organizationalPerson, inetOrgPerson, uidObject                               uid, cn, sn and mail
gus   a sqlite database  a password            account, uidObject                                                                   uid
hal   a sqlite database  a password            account, uidObject                                                                   uid

GROUP       MEMBERS       PUBLISHED AS
alumni      nobody        organizationalRole
engineers   dora and eli  posixGroup
nobody-yet  nobody        posixGroup
readers     fay and gus   groupOfNames

fay has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
gus has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
hal has no homeDirectory: not a posixAccount, published as account, uidObject
hal is published without uidNumber: no class of the entry allows it; posixAccount would
hal is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
hal is published without mail: no class of the entry allows it; inetOrgPerson would
group alumni has no gidNumber and nobody in it: not a posixGroup, published as an organizationalRole (a groupOfNames needs a member)
group readers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

`PUBLISHED AS`는 `top`을 제외한 각 엔트리의 객체 클래스이고, `WITH`는 검색이
반환하는 엔트리에서 읽은 속성입니다. hal은 `uidNumber`, `gidNumber`, `mail`이
있고 `homeDirectory`와 `sn`이 없습니다. hal은 `account`이며 `account`는 세 가지
모두 허용하지 않으므로, 그 속성들은 제외되고 나머지가 게시됩니다. 서버도 시작할 때
같은 내용을 알려 줍니다(그리고 멈추면 `stopping`).

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

reader의 비밀번호를 파일에 넣고 OpenLDAP의 `ldapsearch`로 되읽은 결과입니다.

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(|(uid=dora)(uid=eli)(uid=gus)(uid=hal))'
dn: uid=dora,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: ldapPublicKey
objectClass: uidObject
uid: dora
cn: dora
sn: Explorer
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/dora
mail: dora@example.org
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTfVR7FqXWE/0VEcjrUhK+Fz/MLqlwGPIxalr6onRMn dora@laptop

dn: uid=eli,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: uidObject
uid: eli
cn: eli
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/eli

dn: uid=gus,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: gus

dn: uid=hal,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: hal

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=groups,dc=example,dc=org '(objectClass=*)'
dn: cn=alumni,ou=groups,dc=example,dc=org
objectClass: top
objectClass: organizationalRole
cn: alumni
description: people who were here

dn: cn=engineers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: engineers
gidNumber: 2000
memberUid: dora
memberUid: eli

dn: cn=nobody-yet,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: nobody-yet
gidNumber: 2001

dn: cn=readers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
cn: readers
description: people who read
member: uid=fay,ou=people,dc=example,dc=org
member: uid=gus,ou=people,dc=example,dc=org
```

`alumni`는 `groups_attributes`에만 지정되어 있으므로 구성원 없이 존재하며,
`gidNumber`가 없으므로 `organizationalRole`입니다. `nobody-yet`은 `gidNumber`가
있고 구성원이 없으므로 `memberUid`가 없는 `posixGroup`입니다.

어떤 클래스가 누구를 찾는지:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=uidObject)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org

dn: uid=fay,ou=people,dc=example,dc=org

dn: uid=gus,ou=people,dc=example,dc=org

dn: uid=hal,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=posixAccount)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org
```

## 무엇이 제외되고 무엇이 보류되는가 {#what-is-dropped-and-what-is-withheld}

| 주어진 것 | 엔트리 | 이유 |
|---|---|---|
| `uidNumber`, `gidNumber`, `homeDirectory` 없음, `sn` 없음 | `account, uidObject`, 두 속성 제외 | *no class of the entry allows it; posixAccount would* |
| `mail`, `sn` 없음 | `account, uidObject`, `mail` 제외 | *no class of the entry allows it; inetOrgPerson would* |
| 스키마가 정의하지 않는 타입 | 나머지 | *the schema served here does not define it* |
| `gidNumber` 없는 그룹의 `mail` | `groupOfNames`, `mail` 제외 | |
| POSIX 세 가지와 함께 `homeDirectory` 값 두 개 | **보류**: SINGLE-VALUE이므로 제외할 것이 없음 | |
| 정수가 아닌 `gidNumber` | **보류**: 구문에 맞지 않음 | |

**소스가 제공한 것만 제외되며**, 어떤 속성이 허용되지 않는지는 스키마를 다시
읽은 결과가 아니라 `Validate`의 답입니다. 제외한 뒤 엔트리를 다시 검증합니다. 그래도
실패하는 엔트리는 **보류됩니다**. 모든 검색에서 사라지고, 시작 로그가 이를 지정하며,
`check`는 `Validate`가 찾은 모든 문제와 함께 이를 나열합니다. authnd가 직접 파생하는
속성(`uid`, `cn`, `objectClass`, `sshPublicKey`, `sambaSID`, `sambaNTPassword`)을
스키마가 거부한다면 이는 authnd의 결함이며, 그 속성 없이 게시하지 않고 엔트리를
보류합니다.

여기서 alice의 `gidNumber`는 단어입니다.

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes = {
    uidNumber     = "1000"
    gidNumber     = "staff"
    homeDirectory = "/home/alice"
  }
}

user "bob" { password_file = "etc/authnd/bob.pw" }
```

```
$ authnd check cases/withheld.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS               WITH
alice  the configuration file  a password  NOT PUBLISHED (see below)  uid, cn, gidNumber, homeDirectory and uidNumber
bob    the configuration file  a password  account, uidObject         uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
alice is NOT published: as account, posixAccount, uidObject it fails the schema:
  - the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

서비스를 시작하면 alice는 여전히 바인드할 수 있지만 어떤 검색에도 나타나지
않으며, 서버는 시작할 때 그 이유를 알려 줍니다.

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

보류되는 것은 검색이 반환하는 엔트리이지 신원이 아닙니다.

## 제공하는 스키마 {#the-schema-it-serves}

루트 DSE가 이를 지정하며([루트 DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})의
`subschemaSubentry: cn=Subschema`), `cn=Subschema`의 베이스 검색이 이를
반환합니다(RFC 4512 §4.2). go-authn/ldap이 내장한 표준 정의 — RFC 4512, 4517,
4519, 4523, 4524, 2798, 2307, 3672, 3045와 openssh-lpk — 에,
[`samba` 블록]({{< relref "/authnd/tls.md#the-samba-block" >}})이 있으면 Samba의
`sambaSamAccount`, `sambaSID`, `sambaNTPassword`가 더해집니다. 정의는 이름으로
요청하거나 `+`로 요청할 때만 게시됩니다. 표시한 곳은 줄였습니다.

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -s base -b cn=Subschema '+' '*'
dn: cn=Subschema
objectClass: top
objectClass: subentry
objectClass: subschema
cn: Subschema
subtreeSpecification: {}
ldapSyntaxes: ( 1.3.6.1.4.1.1466.115.121.1.3 DESC 'Attribute Type Description' )
[...]
matchingRules: ( 2.5.13.15 NAME 'integerOrderingMatch' SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 )
[...]
attributeTypes: ( 1.3.6.1.1.1.1.0 NAME 'uidNumber' DESC 'An integer uniquely identifying a user in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
attributeTypes: ( 1.3.6.1.1.1.1.1 NAME 'gidNumber' DESC 'An integer uniquely identifying a group in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
[...]
objectClasses: ( 2.5.6.9 NAME 'groupOfNames' SUP top STRUCTURAL MUST ( member $ cn ) MAY ( businessCategory $ seeAlso $ owner $ ou $ o $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.3.1 NAME 'uidObject' SUP top AUXILIARY MUST uid )
objectClasses: ( 0.9.2342.19200300.100.4.5 NAME 'account' SUP top STRUCTURAL MUST uid MAY ( description $ seeAlso $ l $ o $ ou $ host ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.0 NAME 'posixAccount' DESC 'Abstraction of an account with POSIX attributes' SUP top AUXILIARY MUST ( cn $ uid $ uidNumber $ gidNumber $ homeDirectory ) MAY ( userPassword $ loginShell $ gecos $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.2 NAME 'posixGroup' DESC 'Abstraction of a group of accounts' SUP top STRUCTURAL MUST ( cn $ gidNumber ) MAY ( userPassword $ memberUid $ description ) )
[...]
```

전체 엔트리는 327줄이었습니다. 구문 49개, 매칭 규칙 40개, 매칭 규칙 사용 36개,
속성 타입 143개, 객체 클래스 52개입니다. 베이스 아래의 검색과 달리, 서브스키마
엔트리는 루트 DSE처럼 익명 클라이언트에게도 응답합니다. `-D`와 `-y` 없이 같은
쿼리를 보내도 반환되었습니다.

**필터는 스키마의 매칭 규칙을 사용하므로** `(uidNumber>=1000)`은 정수를
비교합니다. `uidNumber`와 `gidNumber`에는 `ORDERING integerOrderingMatch`가
있는데, RFC 2307은 이를 주지 않습니다. slapd와 draft-howard-rfc2307bis-02는
주며, go-authn/ldap도 줍니다([유일한 차이점]({{< relref "/libraries/ldap.md#the-schema" >}})).
문자열로 비교하면 `1000`이 `999`보다 앞에 정렬됩니다.

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=1000)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=999)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001
```

hal은 나오지 않습니다. hal의 `uidNumber`가 제외되었기 때문입니다. `uid`처럼
ORDERING 규칙이 없는 속성에 대한 범위 비교는 Undefined이며 아무것도 일치하지
않습니다.
