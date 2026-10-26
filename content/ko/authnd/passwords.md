---
title: "사람이 자신의 비밀번호를 변경하기"
linkTitle: "비밀번호 변경"
weight: 50
description: "authnd가 받아들이는 유일한 쓰기: 사람 자신의 비밀번호. RFC 3062 또는 RFC 4511 modify를 통해, 항상 이전 비밀번호와 함께, 그 사람을 선언한 파일에 다시 기록됩니다."
tags: [authnd, 비밀번호, ldappasswd]
---

사람은 RFC 3062 비밀번호 변경 작업(`ldappasswd`가 보내는 것) 또는 RFC 4511
modify를 통해 **자기 자신의** 비밀번호를 변경할 수 있으며, 다른 사람의 것은
변경할 수 없습니다. 두 경우 모두 **연결이 무엇으로 바인드했든 현재 비밀번호를 새
비밀번호와 함께 보내야 합니다.** [OAUTHBEARER 토큰]({{< relref "/authnd/tokens.md" >}})으로
바인드된 세션은 수명이 짧고 인증 요소가 하나일 수도 있는데, 그렇지 않으면 이를
`kinit`에서도 동작하는 영구 비밀번호로 바꿀 수 있기 때문입니다.

이는 `pwdSafeModify`를 설정한 OpenLDAP ppolicy의 동작이며, `ppolicy.c`가 반환하는
결과 코드를 그대로 사용합니다. RFC 3062 §3이 이를 허용합니다. "If oldPasswd is
not present, the server MAY use other policy to determine whether or not to
change the password."

## `ldappasswd`로 {#with-ldappasswd}

`-t`는 이전 비밀번호가 든 파일이고 `-T`는 새 비밀번호가 든 파일입니다. `-A`와
`-S`는 대신 프롬프트로 묻습니다.

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -T alice.new
Result: Insufficient access (50)
Additional info: a password change must send the old password with the new one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t wrong.pwin -T alice.new
Result: Server is unwilling to perform (53)
Additional info: the old password sent is not the current one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.new
dn:uid=alice,ou=people,dc=example,dc=org
```

이전 비밀번호는 즉시 동작하지 않게 되며, 바인드에서도, 그리고
[렐름]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}})이 있으면
`kinit`에서도 마찬가지입니다. 서버는 출력에 이를 기록합니다.

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd는 비밀번호를 생성하지 않습니다. 새 비밀번호가 없는 요청은
`unwillingToPerform`으로 거부됩니다(*this server does not generate passwords:
send the one you want*). 서버가 만들어 낸 비밀번호는 연결을 통해 다시 보내야
하는데, 그것이 반드시 도달하는 곳은 터미널의 스크롤백입니다.

## `ldapmodify`로 {#with-ldapmodify}

변경은 **이전 값의 삭제 다음에 새 값의 추가를, 한 요청 안에서** 하는 것입니다.
RFC 4511 §4.6은 modify의 변경을 순서대로 원자적으로 적용하므로, 삭제하는 값이
보유한 값이 아니면 삭제가 — 그리고 요청 전체가 — 실패합니다.

```
dn: uid=alice,ou=people,dc=example,dc=org
changetype: modify
delete: userPassword
userPassword: alice-test-pw
-
add: userPassword
userPassword: alice-new-pw
-
```

단순한 `replace`는 아무것도 증명하지 못하며, `userPassword` 이외의 것은 이 서버가
바꾸지 않습니다.

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f replace.ldif
ldap_modify: Insufficient access (50)
	additional info: a password change must send the old password with the new one
modifying entry "uid=alice,ou=people,dc=example,dc=org"

$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f other.ldif
ldap_modify: Server is unwilling to perform (53)
	additional info: this server changes userPassword and nothing else, not cn
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

비밀번호 **그리고** 다른 것을 요청하는 modify는 통째로 거부됩니다. modify는
원자적이고, 절반만 수행하면 아무도 요청하지 않은 일에 대해 성공을 보고하게
되기 때문입니다.

## 누가 무엇을 변경할 수 있는가 {#who-can-change-what}

| 요청 | 응답 |
|---|---|
| 이전 비밀번호가 없음, 또는 단순한 `replace: userPassword` | `insufficientAccessRights` |
| 현재 비밀번호가 아닌 이전 비밀번호 | `unwillingToPerform` |
| 다른 사람의 엔트리 | `insufficientAccessRights`, *a password may be changed only by the person it belongs to* |
| 익명 연결 | `insufficientAccessRights`, *an anonymous connection has not said who it is* |
| 비밀번호가 아예 없는 사람 — 토큰으로만 바인드했을 수 있음 | `unwillingToPerform`: 베어러 토큰은 비밀번호가 아니며 첫 번째 비밀번호를 설정하지 않습니다. 관리자가 구성에서 설정합니다 |
| `users` 블록에서 서비스되는 사람 | `unwillingToPerform`: authnd는 그 소스를 읽기만 하고 쓰지 않습니다 |
| 파일에 쓸 수 없음 | `other`(80), *the password could not be written*. 이유는 서버의 출력에 있습니다 |

끝에서 두 번째의 경우로, SQLite 데이터베이스에서 오는 dora에 대해 릴리스
바이너리가 낸 결과입니다.

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

사람은 DN이 아니라 **신원으로** 일치시킵니다. 세션 자신의 이름이 대상의 이름과
바이트 단위로 정확히 같아야 하므로, `uid=Backup`으로 바인드된 세션은 두 DN이
같다고 비교되더라도 `backup`의 비밀번호를 바꿀 수 없습니다. 이것과
[대소문자만 다른 이름의 거부]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})는
서로 의존하지 않는 두 가지 통제입니다.

## 새 비밀번호가 기록되는 곳 {#where-the-new-password-is-written}

**그 사람을 선언한 파일**에 다시 기록되며, 다른 곳에는 기록되지 않습니다.

- `password_file`이 있는 `user` 블록은 **그 파일**을 다시 씁니다. 프로세스가
  할 수 있는 범위에서 소유자와 그룹을 유지하고, 모드는 최대 0600으로 좁히며 절대
  넓히지 않습니다
- `password`가 인라인인 `user` 블록은 구성 파일을 새 값으로 다시 쓰며, 주석, 순서,
  모드는 유지합니다
- `nt_hash`만 있는 `user` 블록에는 비밀번호를 부여하지 않습니다. 그것은 그 사람을
  증명하는 것을 바꾸는 일이며, 구성의 변경이기 때문입니다

모든 쓰기는 **같은 디렉터리의** 임시 파일에 한 다음 이름을 바꾸는 방식이므로,
디스크가 가득 차거나 충돌이 나도 빈 파일이 아니라 이전 비밀번호가 남습니다.
그러려면 디렉터리에 대한 쓰기 권한이 필요합니다. 패키지로 제공되는 유닛에서는
`ProtectSystem=strict`가 이를 빼앗으며, 변경은 다음과 같이 거부됩니다.

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

이유는 서버의 출력에 있습니다.

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-1822988247: permission denied
```

그러므로 비밀번호는 서비스가 쓸 수 있는 별도의 디렉터리에 두고, 구성은 서비스에
읽기 전용으로 두십시오 —
[`ReadWritePaths=` 드롭인]({{< relref "/authnd/install.md#the-configuration-directory" >}}).
비밀번호가 인라인으로 기록된 사람이 있으면 `/etc/authnd` 자체를 쓰기 가능하게
해야 하는데, 그러면 서비스가 자신의 구성을 다시 쓸 수도 있게 됩니다.

쓰기에 성공하면 구성 파일을 **`user` 블록에 한해서만** 다시 읽습니다. 디스크에서
기다리고 있는 관련 없는 편집이, 누군가 비밀번호를 바꿨다는 이유로 중간에
적용되지 않습니다. 나머지는 모두 여전히 재시작을 기다립니다. 다만 파일은 통째로
읽으므로, 그중 하나가 더 이상 로드되지 않으면 비밀번호는 기록되고 클라이언트는
*the password was written but this server did not reload it*라고 듣게 됩니다 —
실행 중인 서버는 재시작할 때까지 이전 비밀번호를 유지합니다.
