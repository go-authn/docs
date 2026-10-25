---
title: "같은 사람들을 위한 Kerberos 렐름"
linkTitle: "Kerberos 렐름"
weight: 60
description: "kerberos 블록, 티켓에 서명하는 데 쓰는 keytab, 누가 티켓을 발급받을 수 있고 어떤 사람은 왜 영원히 받을 수 없는지, 그리고 왜 mfa 블록과 함께 둘 수 없는지."
tags: [authnd, kerberos, kdc]
---

```hcl
kerberos {
  realm    = "EXAMPLE.ORG"               # required, upper case
  keytab   = "/etc/authnd/krb5.keytab"   # required; must hold krbtgt/EXAMPLE.ORG
  listen   = "127.0.0.1:88"              # the default; UDP and TCP both
  lifetime = "10h"                       # the default, MIT's
}
```

`kerberos` 블록은 authnd를 디렉터리일 뿐 아니라 KDC로도 만들어 줍니다.
[go-authn/kdc]({{< relref "/libraries/_index.md" >}})를 통해, 같은 사람들이
조회만 되는 것이 아니라 티켓도 발급받습니다. UDP와 TCP로 같은 주소에서 응답하고,
암호화된 타임스탬프 사전 인증을 요구하며, `aes256-cts-hmac-sha1-96` 티켓만
발급합니다. `lifetime`은 Go duration(`"10h"`, `"90m"`)입니다. 디렉터리와 렐름은
동등합니다. 둘 중 하나가 멈추면 프로세스도 멈춥니다. KDC가 죽은 뒤에도 LDAP에
계속 응답하는 서버는 Kerberos를 쓰지 않는 모든 쪽에는 정상으로 보일 것이기
때문입니다.

시작 시 거부되는 경우:

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

이름이 없는 렐름, keytab이 없는 경우, 구문 분석되지 않는 주소, Go가 읽지 못하는
`lifetime`, 그리고 `mfa` 블록 옆의 `kerberos` 블록(아래)도 마찬가지입니다.

## keytab {#the-keytab}

keytab에는 authnd가 자신의 티켓에 서명하는 키 — `krbtgt/REALM@REALM` — 와, 티켓을
발급하는 서비스마다 하나씩의 키가 들어 있습니다. 그 서비스들이 읽는 것도 같은
파일입니다. krbtgt의 비밀번호는 다시는 입력하지 않으므로 무작위로 만드십시오.
MIT의 `ktutil`로 하는 방법입니다(Debian과 Ubuntu에서는 `krb5-user` 패키지이며,
이 방법은 `docs/install.md`가 제시하는 것이고 이 문서를 위해 실행해 보지는
않았습니다).

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

서비스의 키도 같은 방법으로 추가하고(`-p nfs/files.example.org@EXAMPLE.ORG`),
그 서비스에는 자신의 keytab에 같은 키를 넣어 주십시오. macOS에서는 Heimdal의
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96`이
비밀번호 없이 무작위 키를 기록합니다. 어느 쪽이든 시작하기 전에 keytab을 다시
읽어 보십시오(MIT는 `klist -k`, Heimdal은 `ktutil -k <file> list`).

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

`krbtgt/REALM`이 없는 keytab은 `check`와 시작 시에 거부됩니다.
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}})를
참조하십시오. keytab은 시작할 때 한 번만 읽으므로, 교체하려면 다시 시작해야 합니다.

## 누가 티켓을 발급받을 수 있는가 {#who-can-be-issued-a-ticket}

KDC는 클라이언트의 사전 인증을 그 사람의 장기 키로 **복호화**해야 하므로,
비밀번호를 확인할 방법뿐 아니라 그 사람의 **비밀번호**가 필요합니다. `check`는
누가 가능하고 누가 불가능한지를 이유와 함께 알려 줍니다.

```
$ authnd check realm
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP  MEMBERS        PUBLISHED AS
staff  alice and bob  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

| 소스가 가진 것 | 티켓 |
|---|---|
| 비밀번호(`password`, `password_file`, SQL 비밀번호 열) | 예 |
| NT 해시만 | **아니요**: 이것은 RC4-HMAC 키이며, 이 렐름은 AES만 발급합니다 |
| 비밀번호 확인만(이 디렉터리 뒤에 있는 `users "ldap"` 디렉터리) | **아니요**: 비밀번호를 검증하기만 하는 소스는 어떤 키도 만들어 낼 수 없습니다 |

이 디렉터리 뒤에 다른 디렉터리가 있는 경우, 렐름 부분의 마지막 줄은
*alice, bob, dora and eli: the source only verifies a password, so it cannot
produce any key*라고 나옵니다. 이는 구성의 문제가 아니라 구조적인 문제이며,
올바른 비밀번호가 틀렸다고 `kinit`이 말하는 사람에게서 알게 되는 것보다
`check`에서 먼저 발견하는 편이 낫습니다.

## kinit으로 접속하기 {#kinit-against-it}

이 KDC를 지정하는 `krb5.conf`입니다. ⛔ MIT Kerberos에서는 중괄호를 각각 별도의
줄에 써야 합니다. 한 줄로 쓴 렐름은 파서가 조용히 무시합니다.

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

같은 구성을 실행하고 macOS의 Heimdal `kinit`으로 요청한 결과입니다
(`--password-file`은 파일에서 비밀번호를 읽습니다).

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 18 16:10:19 2026  Oct 19 02:10:19 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

티켓은 기본값인 10시간 동안 유지됩니다. bob은 자신의 NT 해시를 계산한 원래
비밀번호를 입력했지만 여전히 거부됩니다. 렐름에 그 사람의 키가 없기 때문입니다.
KDC는 거부한 내용을 Kerberos 오류 코드와 함께 자신의 출력에 기록합니다.

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required*는 `kinit`의 정상적인 첫 번째 왕복입니다. 클라이언트가
사전 인증 없이 요청하면 사전 인증이 필요하다는 응답을 받고, 이어서 사전 인증을
붙여 다시 요청합니다. alice의 성공한 `kinit`은 그 줄만 남깁니다.

{{< callout type="info" >}}
**렐름은 어떤 이름이 존재하는지 알려 주지만, 디렉터리는 알려 주지 않습니다**

아무도 쓰지 않는 이름에 대한 LDAP 바인드는 잘못된 비밀번호와 똑같이
`invalidCredentials`로 응답합니다. KDC는 Kerberos KDC가 하는 대로 *no such
principal in this realm*(`KDC_ERR_C_PRINCIPAL_UNKNOWN`, 코드 6)으로 응답합니다.
다른 사람이 접근할 수 있는 주소에 `kerberos` 블록을 두면, 이름 목록은 어느 KDC에서와
마찬가지로 추측할 수 있게 됩니다. `listen`의 기본값은 루프백입니다.
{{< /callout >}}

## LDAP으로 변경한 비밀번호 {#a-password-changed-over-ldap}

KDC는 디렉터리가 제공하는 것과 같은 사람들을 읽으므로,
[LDAP으로 변경한 비밀번호]({{< relref "/authnd/passwords.md" >}})는 즉시 렐름에
반영됩니다. 이전 비밀번호는 바인드에서 동작하지 않게 되는 순간 `kinit`에서도
동작하지 않습니다.

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## `mfa` 블록과 함께 둘 수 없음 {#not-beside-an-mfa-block}

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

RFC 4120의 암호화된 타임스탬프 사전 인증은 비밀번호만으로 키가 만들어집니다.
두 번째 인증 요소에는 FAST(RFC 6113) 안에서의 OTP 사전 인증(RFC 6560)이
필요하며, 이 KDC는 이를 구현하지 않습니다. 여기에 렐름이 있으면
[`mfa` 블록]({{< relref "/authnd/mfa.md" >}})이 두 요소가 필요하다고 지정한
사람들에게 하나의 요소만으로 티켓을 내주게 되고, 티켓은 바인드가 여는 모든 것을
엽니다. 그래서 선택은 차단하는 쪽으로 정해졌습니다. 둘 중 하나만 쓰십시오.

## 포트 {#ports}

88은 특권 포트입니다. 패키지로 제공되는 유닛에서는 `CAP_NET_BIND_SERVICE`가 이를
허용합니다. 일반 사용자로 실행하는 서버는 위에서처럼 높은 번호의 포트와 그
포트를 지정하는 `krb5.conf`가 필요합니다.
