---
title: "필드가 하나뿐인 프로토콜 위의 두 번째 인증 요소"
linkTitle: "두 번째 인증 요소"
weight: 70
description: "mfa 블록: 비밀번호 끝에 붙는 일회용 코드, 그것을 나누고 확인하는 방법, 누구에게 무엇이 집계되는지, 그리고 그 아래에서 누가 바인드할 수 없는지."
tags: [authnd, mfa, totp]
---

LDAP의 단순 바인드는 이름과 비밀번호만 담고 다른 것은 담지 않습니다. 코드를 넣을
자리도, 코드를 요청하는 왕복도 없으며, LDAP을 쓰는 클라이언트는 그것을 새로
배우지도 않습니다. 그래서 코드는 비밀번호의 **끝**에 붙습니다. 이는 이런 일을
하는 어플라이언스가 하는 방식이고 사람들이 이미 입력할 줄 아는 방식입니다.

```
password:  hunter2314159
           ^^^^^^^ ^^^^^^
           password  the six digits on their phone
```

```hcl
mfa {
  factors        = 2
  distinct_kinds = true     # two things they KNOW are not two factors
  # digits = 6, period = 30 (seconds) and window = 1 are the defaults
}

user "tess" {
  password_file = "/etc/authnd/passwords/tess.pw"
  totp_secret   = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"   # ⛔ this IS the second factor
}
```

| 키 | 기본값 | |
|---|---|---|
| `factors` | 2 | 1은 거부됩니다(*a password and nothing else: remove the block, or ask for 2*). 바인드는 비밀번호와 코드를 담을 뿐 세 번째는 담지 않으므로 2를 넘는 값도 거부됩니다 |
| `distinct_kinds` | `false` | 인증 요소가 서로 다른 종류여야 함 — 보통 "2단계 인증"이라는 말이 뜻하는 것 |
| `digits` | 6 | 6에서 10까지 (RFC 4226) |
| `period` | 30 | 코드 하나가 유지되는 초 |
| `window` | 1 | 시계가 다른 경우를 위해 지금의 앞뒤로 허용되는 단계 수. 각 단계는 다른 사람이 추측할 수 있는 시간의 한 단계이므로 의도를 갖고 설정하십시오 |
| `readers` | `false` | [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})도 코드를 담는지 여부. 서비스 계정에는 휴대전화가 없습니다. 있는 계정은 `reader` 블록에 `totp_secret`을 둡니다 |

비밀 값은 데이터베이스 열(다섯 번째)이나 LDAP 속성(`totp_attribute`)에서도 가져올
수 있습니다. [사람들]({{< relref "/authnd/people.md" >}})을 참조하십시오.
`user` 또는 `reader` 블록의 `totp_secret`이 128비트 미만이면(RFC 4226 R6),
나중에 그 사람의 모든 로그인이 실패하게 두는 대신 서버가 그 사람의 이름을 지정하며
멈춥니다.

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## 그 아래에서 누가 바인드할 수 없는가 {#who-cannot-bind-under-it}

```
$ authnd check mfa
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS        WITH
alice  the configuration file  a password                             account, uidObject  uid
tess   the configuration file  a password and a one-time-code secret  account, uidObject  uid

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
tess has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject

a bind carries a password with a 6-digit code after it, of two different kinds
alice has no second factor here, and cannot bind while one is required
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

블록을 켜기 전에 물어야 할 질문이 바로 이것입니다.

## 바인드는 어떻게 보이는가 {#what-the-binds-look-like}

같은 구성을 서비스하고, 바인드 순간에 tess의 비밀 값으로 코드를 계산한 결과입니다.

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.only
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
dn:uid=tess,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.badcode
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.code
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin
dn:cn=reader,dc=example,dc=org
```

`tess.only`는 코드 없는 tess의 비밀번호이고, `tess.both`는 같은 비밀번호에
현재 코드를 붙여 두 번 보낸 것이며, `tess.badcode`는 그 비밀번호와 `000000`이고,
`alice.code`는 alice의 비밀번호와 여섯 자리 숫자입니다. 클라이언트는 어느 쪽이
틀렸든 한 가지만 듣습니다 — *invalid credentials*. 어느 쪽인지는 계정에 관한
사실이며, 아무것도 증명하지 못한 사람에게 그것을 알려 주면 다음 추측이 좁혀집니다.
서버 자체의 출력은 어느 쪽인지 알려 줍니다.

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## 필드가 하나뿐이라서 따라오는 것 {#what-follows-from-the-one-field}

- **나누는 기준은 길이입니다.** 마지막 `digits`개의 문자가 코드입니다. 숫자로 끝나는
  비밀번호도 괜찮습니다 — 그래서 tess의 비밀번호만 보냈을 때 틀린 비밀번호 뒤에
  코드가 붙은 것으로 읽혔습니다. 코드보다 *길지 않은* 필드는 추측하지 않고
  거부합니다. 짧은 비밀번호는 코드와 구별할 수 없기 때문입니다.
- **양쪽 절반을 항상 확인합니다.** 틀린 비밀번호에서 일찍 반환하면 걸린 시간으로
  어느 쪽이 틀렸는지 알려 주는 셈이 됩니다.
- **코드는 한 번만 사용됩니다.** 코드는 한 단계 전체 동안 유효하므로, 같은 코드를
  두 번 받아들이는 서버는 재생 공격을 받아들입니다. 마지막으로 받아들인 단계까지의
  모든 단계가 거부되며, 같은 코드만 거부되는 것이 아닙니다.
- **추측은 이름별로 제한됩니다.** go-authn/totp의 기본값에 따라, 틀린 코드가
  연속 다섯 번이면 올바른 코드를 포함해 15분 동안 거부되고, 백 번이면 authnd를
  다시 시작할 때까지 잠깁니다. 횟수는 프로세스별로 메모리에 보관됩니다.
- **올바른 비밀번호 뒤의 코드만 집계됩니다.** 그렇지 않으면 이름을 아는 누구든
  바인드 다섯 번으로 그 소유자를 동결시킬 수 있습니다. 틀린 비밀번호 뒤에서도
  코드는 계산되지만, 기억하는 것에 대해서는 계산하지 않습니다 — 위 출력의 첫
  줄, *not looked at*.
- **reader는 구성에 쓴 그대로의 DN으로 집계됩니다.** 그래서 `CN=Reader`는 자기만의
  새 횟수를 얻지 못합니다.
- **등록한 사람이 없는 것은 틀린 코드가 아닙니다.** 비밀 값이 없는 사람은 틀리게
  답한 것이 아니라 아무것도 답하지 않은 것이며, 서버의 출력은 *nobody enrolled an
  authenticator for this person*이라고 말합니다.

## 렐름과는 안 됨 {#not-with-a-realm}

하나의 구성에 `kerberos` 블록과 `mfa` 블록이 함께 있으면 거부됩니다. `kinit`은
비밀번호만 증명하고 다른 것은 증명하지 않으며, 이 KDC에는 두 번째 인증 요소
사전 인증이 없습니다. [렐름]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}})을
참조하십시오.

## 같은 정책 아래의 토큰 {#tokens-under-the-same-policy}

[`oidc` 블록]({{< relref "/authnd/tokens.md" >}})이 있을 때 바인드 시의 토큰은 발급자가
무엇을 확인했다고 말하는지 — `amr` 클레임 — 로 집계됩니다. `amr`이 없는 토큰은
인증 요소 하나이며, 이 정책은 그것을 거부합니다.
