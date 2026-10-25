---
title: "사람들은 어디에서 오는가"
linkTitle: "사람들"
weight: 20
description: "user와 group 블록, SQL 데이터베이스, 다른 LDAP 디렉터리: 각각을 쓰는 방법, 조회되는 순서, 그리고 각각이 사람에게 허용하는 것."
tags: [authnd, 구성, sql, ldap]
---

`user` 블록은 작은 사이트에게는 디렉터리 전체이고, 큰 사이트에게는 데이터베이스에
넣지 않고 따로 관리하는 서비스 계정입니다. 사람들이 이미 데이터베이스나 LDAP에
있는 사이트는 그들을 낡아 가는 두 번째 장소에 복사해서는 안 되므로, `users`
블록이 사람들이 있는 곳에서 그대로 읽습니다. `users` 블록은 go-authn/directory의
`hcldir`로, [go-fileshare](https://github.com/go-fileshare/fileshare)가 읽는 것과
같습니다. 하나의 디렉터리가 둘 모두에게 같은 방식으로 기술됩니다.

## 구성에 직접 쓰기 {#written-in-the-configuration}

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| 필드 | 설명 |
|---|---|
| `password` | 인라인 비밀번호 |
| `password_file` | 같은 것을 파일에서 읽음(앞뒤 공백 제거) |
| `nt_hash` | `MD4(UTF16LE(password))`, 16진수 32자 — 비밀번호는 없고 이것을 보유한 사이트를 위한 것 |
| `totp_secret` | base32 일회용 코드 비밀 값, 최소 128비트. [두 번째 인증 요소]({{< relref "/authnd/mfa.md" >}})를 참조 |
| `authorized_keys` | `authorized_keys` 줄, `sshPublicKey`로 게시됨 |
| `authorized_keys_file` | 같은 것을 파일에서 |
| `attributes` | v0.11.0부터, 사람을 설명하되 아무것도 증명하지 않는 것 — `sn`, `uidNumber`, `gidNumber`, `homeDirectory`, `mail`… — 을 문자열 또는 문자열 목록의 맵으로. `group` 블록도 받습니다. 이것들이 엔트리가 무엇으로 게시되는지를 결정합니다. [엔트리]({{< relref "/authnd/entries.md#adding-attributes" >}})를 참조 |

시작 시 거부되며 해당 사람의 이름을 지정합니다.

- `password`와 `password_file`이 함께 있는 경우 — 어느 쪽인지 지정하십시오
- `password`와 `nt_hash`가 함께 있는 경우 — 해시는 비밀번호에서 파생되므로 둘이
  서로 다를 수 있습니다
- `authorized_keys`와 `authorized_keys_file`이 함께 있는 경우
- 16진수 32자가 아닌 `nt_hash`, 구문 분석되지 않는 `authorized_keys` 줄, 128비트
  미만의 `totp_secret`
- 같은 `user` 또는 `group`이 두 번 나오는 경우, 그리고 구성원이 없는 `group`

어떤 소스도 모르는 그룹 구성원도 거부되며, 이것이 오타를 아무것도 조용히 부여하지
않게 되기 전에 잡아 줍니다.

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**`nt_hash`만으로는 바인드할 수 없습니다**

`nt_hash`만으로 작성된 사람은 게시되고, `sambaNTPassword`를 통해 SMB 서버에 전달될
수 있지만, **authnd 자체에는 바인드할 수 없습니다**. LDAP 단순 바인드는
비밀번호를 보내는데, NT 해시는 여기서 비밀번호를 확인하는 방법이 아니기
때문입니다. 아래의 bob은 NT 해시만 있고, 해시는 보낸 비밀번호의 것입니다.

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check`는 표 뒤에 이를 알려 줍니다.

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```

**설계상 거부되는 이유.** NT 해시는 `MD4(UTF16LE(password))`이며, 솔트가 없고
빠릅니다(MS-NLMP §3.3.1, NTOWFv1). LDAP 바인드를 확인하는 데 이를 받아들이면
유출된 해시가 열 수 있는 범위가 SMB에서 authnd를 통해 바인드하는 모든
애플리케이션으로 넓어집니다. Kerberos도 관련된 이유로 이런 사람들을 거부합니다.
NT 해시는 RC4-HMAC 키(RFC 4757 §2)이고 렐름은 AES만 발급하기 때문입니다. 이것은
누락된 기능이 아니라 의도적인 결정이며, 이를 바꾸는 옵션은 없습니다.

**대신 할 일.** NT 해시만 보유한 디렉터리(Samba, 내보낸 AD)에서 마이그레이션할 때는
각 사람에게 실제 비밀번호나 소스 안의 비밀번호 확인 수단을 주십시오. 비밀번호
재설정, 또는 상위 디렉터리가 직접 비밀번호를 확인하는 `users "ldap"` 소스가
방법입니다. NT 해시를 유일한 자격 증명으로 유지하지 마십시오.
{{< /callout >}}

## SQL 데이터베이스에서 {#in-a-sql-database}

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**쿼리는 직접 작성합니다.** 사이트의 사람들은 이미 그 사이트의 형태로 들어 있기
때문입니다. `users` 쿼리의 열은 **위치로** 읽습니다. 이름, 그다음에 비밀번호, NT
해시, SSH 키(한 줄에 하나), 일회용 코드 비밀 값 중 원하는 것이 이 순서로 오며,
최대 다섯 열입니다. NULL은 그 사람이 갖지 않은 자격 증명입니다. 비밀번호 열은
저장된 그대로 비교됩니다. authnd에는 해시된 열을 위한 설정이 없습니다. `groups`
쿼리는 그룹 이름과 구성원을, 소속 하나당 한 행으로 반환합니다.

선택 사항인 쿼리 두 개는 위치가 아니라 **열 별칭으로** 속성을 읽습니다.
`users_attributes`(이름, 그다음 속성당 한 열)와 `groups_attributes`(그룹, 그다음
같은 것)입니다. 따옴표 없는 별칭은 PostgreSQL이 소문자로 바꿉니다.
[엔트리]({{< relref "/authnd/entries.md#in-a-sql-database" >}})를 참조하십시오.

`driver`는 `postgres`(또는 `postgresql`, `pgx`), `mysql`(또는 `mariadb`),
`sqlite`(또는 `sqlite3`)를 받습니다. 데이터베이스는 아무것도 수신하기 전에 시작할
때 접속하므로, 응답하지 않는 데이터베이스는 누군가 지켜보고 있는 시점에 서버를
멈춥니다.

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

같은 머신의 PostgreSQL에 소켓과 peer 인증으로 접속하면 DSN에 비밀번호가 필요
없습니다: `host=/run/postgresql dbname=authnd user=authnd`. 상태 디렉터리의
SQLite는: `file:/var/lib/authnd/people.db`.

다른 종류의 블록에 속하는 키는 무시되지 않고 거부됩니다.

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## 다른 LDAP 디렉터리에서 {#in-another-ldap-directory}

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url`과 `base_dn`은 필수입니다. 사람과 그룹이 어디에 있고 어떤 속성이 그들의
이름인지는 다음과 같습니다.

| 키 | 기본값 |
|---|---|
| `user_filter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))` |
| `group_attribute` | `cn` |
| `group_member_attribute` | 없음: `memberUid`(이름) **그리고** `member`(DN). 설정하면 그 속성 하나만 읽음 |
| `totp_attribute` | 없음: 표준 속성이 없으며, 추측하면 읽은 것처럼 보이면서 아무것도 읽지 않게 됨 |
| `attributes`, `group_attributes` | 없음: 각 사람의 엔트리와 각 그룹의 엔트리에서 복사할 속성, 예를 들어 `["mail", "uidNumber", "homeDirectory"]`와 `["gidNumber"]` ([엔트리]({{< relref "/authnd/entries.md#adding-attributes" >}})) |
| `start_tls` | `false` |

`member` DN은 사람 검색이 반환한 엔트리의 DN일 때만 인정됩니다. 그 밖의 DN이나
아무도 지정하지 않는 DN은 아무에게도 매핑되지 않으며, 이름은 DN에서 읽어내지
않습니다. `sambaNTPassword`와 `sshPublicKey`는 그 이름으로 읽습니다.

{{< callout type="warning" >}}
**v0.11.0부터 기본값이 기관의 디렉터리를 더 많이 읽습니다**

이 블록은 go-authn/directory의 것이며, authnd v0.11.0이 내장한 directory v0.14.0이
기본값을 넓혔습니다. v0.10.2까지 `user_filter`는 `(objectClass=posixAccount)`,
`group_filter`는 `(objectClass=posixGroup)`, `group_member_attribute`는
`memberUid`였습니다. posixAccount가 아닌 `account`나 `uidObject` 엔트리 — 서비스
계정, uid로 이름 붙은 호스트, 다른 곳에서 가져온 사람 — 를 담은 디렉터리는 이제
그것들을 authnd에 제공하며, 각각은 바인드로 확인할 수 있고, `groupOfNames` 그룹은
여기서 그룹이 됩니다. 이전의 집합을 정확히 유지하려면 이전 값을 쓰십시오.

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

두 가지는 아무것도 열기 전에 거부됩니다.

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

루프백 주소로의 `ldap://`와 `ldapi://`는 받아들여집니다. 중간에 아무도 없기
때문입니다.

이 디렉터리 뒤의 디렉터리는 비밀번호를 건네주지 않고, 그 디렉터리에 바인드하여
비밀번호를 **확인합니다**. 여기서는 한 authnd가 다른 authnd를 다른 베이스 아래에서
앞에서 받아 줍니다. 뒤쪽의 것은 3893에서 서비스되는
[`check`]({{< relref "/authnd/check.md#a-configuration-that-can-be-served" >}}) 예제입니다.

```hcl
listen  = "127.0.0.1:3894"
base_dn = "dc=example,dc=net"

users "ldap" {
  url                = "ldap://127.0.0.1:3893"
  base_dn            = "ou=people,dc=example,dc=org"
  group_base_dn      = "ou=groups,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "etc/authnd/reader.pw"
}

user "svc-backup" { password_file = "etc/authnd/svc-backup.pw" }
```

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS        WITH
alice       ldap://127.0.0.1:3893   a password check  account, uidObject  uid
bob         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
dora        ldap://127.0.0.1:3893   a password check  account, uidObject  uid
eli         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
svc-backup  the configuration file  a password        account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
svc-backup has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

뒤쪽 디렉터리가 게시하는 모든 사람은 `account`이고 모든 그룹은 `groupOfNames`
입니다. POSIX 속성을 가진 것이 없기 때문입니다. 기본값이 이들을 읽고, 그룹의
`member` DN은 가져온 사람들에게 매핑됩니다. v0.10.2까지의 기본값으로는
`(objectClass=posixAccount)`가 이들 중 아무것도 일치시키지 못했을 것입니다.

*비밀번호 확인*은 바인드에는 충분하지만, [Kerberos 티켓]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})이나
SMB에는 결코 충분하지 않습니다.

## 순서, 그리고 하나의 예외 {#order-and-the-one-exception}

소스는 **쓰인 순서대로** 조회되며, 이름을 아는 첫 번째 소스가 그 이름을 소유합니다.
`user` 블록이 항상 먼저 오므로, 로컬에 적어 둔 서비스 계정이 데이터베이스의 같은
이름을 가진 누군가에게 덮어쓰이지 않습니다. **그룹 구성원은 합집합입니다.** `group`
블록과 데이터베이스의 `groups` 쿼리가 모두 지정하는 그룹은 양쪽의 구성원을
가집니다.

{{< callout type="warning" >}}
**대소문자만 다른 두 이름은 거부됩니다**

uid는 대소문자를 무시하고 비교하며(RFC 4519 §2.39) 모든 DN도 마찬가지이므로,
파일의 `Dora`와 데이터베이스의 `dora`는 LDAP에게는 하나의 이름이고 바이트를
비교하는 모든 것에게는 두 사람입니다. 한쪽의 비밀번호 변경이 다른 쪽에 적용될 수
있습니다. 이런 구성은 시작하지 않습니다.

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## 한 번만 읽음 {#read-once}

모든 소스는 **시작할 때 한 번** 읽습니다. 데이터베이스에 추가된 사람이나 이 디렉터리
뒤의 디렉터리에서 바뀐 구성원은 재시작 후에 서비스되며, 그 전에는 서비스되지
않습니다. 데이터베이스의 비밀번호 열도 마찬가지입니다. 행의 나머지와 함께 읽습니다.
뒤쪽 디렉터리가 다른 점은, 바인드를 그 디렉터리에 바인드하여 확인하므로 *그곳에서*
바뀐 비밀번호가 동작하는 것이라는 점뿐입니다. 또 하나의 예외는 사람이 authnd
자체를 통해 바꾸는 비밀번호이며, 이는 [즉시 적용됩니다]({{< relref "/authnd/passwords.md" >}}).
다시 불러오기는 없습니다. [운영하기]({{< relref "/authnd/operations.md" >}})를
참조하십시오.
