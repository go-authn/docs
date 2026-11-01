---
title: "사람들이 로그인하는 시스템을 다시 시작하기 전의 check"
linkTitle: "check"
weight: 30
description: "authnd check가 무엇을 열어 보는지, 서비스하기 전에 구성에 대해 무엇을 출력하는지, 어떻게 읽는지, 그리고 볼 수 없는 한 가지 실패."
tags: [authnd, 점검, 구성]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check`는 서버와 정확히 같은 방식으로 구성을 읽고, **서버가 수신을 시작하기 전에
여는 모든 것** — 파일, 데이터베이스, 이 디렉터리 뒤의 디렉터리, 신원 공급자의
디스커버리 문서, TLS 인증서와 키, keytab — 을 열어 본 다음, **수신하지 않고**
무엇이 누구에게 게시될지를 출력합니다. 모든 자격 증명이 어디에서 오는지는
출력하지만 그 내용은 절대 출력하지 않습니다. 0으로 종료하며 *this configuration
can be served*로 끝나거나, 서버를 멈추게 하는 한 문장과 함께 1로 종료합니다.

## 서비스할 수 있는 구성 {#a-configuration-that-can-be-served}

두 개의 `user` 블록, reader 하나, SQLite 데이터베이스가 두 파일(`authnd.hcl`과
`people.hcl`)이 든 디렉터리에 있는 경우입니다.

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## 읽는 방법 {#reading-it}

첫 줄은 스킴, 주소, 베이스입니다. `ldap://`, `ldaps://`, `ldap+starttls://` 중
하나이며, [TLS]({{< relref "/authnd/tls.md" >}})를 참조하십시오.

| 열 | |
|---|---|
| `FROM` | 그 이름을 소유한 소스: *the configuration file*, *a sqlite database*(또는 postgres, mysql), 또는 이 디렉터리 뒤에 있는 디렉터리의 url |
| `CAN PROVE` | *a password*(보유하고 있으므로 비교할 수 있고 거기서 키를 파생할 수 있음), *a password check*(다른 디렉터리가 예/아니오로 응답함), *an NT hash*, *N keys*, *a one-time-code secret*, 또는 *nothing* |
| `PUBLISHED AS` | `top`을 제외한 엔트리의 객체 클래스로, [형태]({{< relref "/authnd/entries.md#the-shapes" >}})가 정하는 대로입니다. 스키마를 통과하지 못하는 엔트리는 *NOT PUBLISHED (see below)* |
| `WITH` | 엔트리가 가진 속성으로, 검색이 반환하는 엔트리에서 읽은 것입니다. `uid`, 클래스가 허용하는 곳에서는 `cn`, 소스가 제공한 것에서 제외된 것을 뺀 나머지, 키가 있으면 `sshPublicKey`, [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})가 켜져 있고 그 사람에게 NT 키와 SID가 있으면 `sambaSID`와 `sambaNTPassword` |

그룹 표에도 `PUBLISHED AS` 열이 있습니다. `posixGroup`, `groupOfNames`,
`organizationalRole` 중 하나입니다. v0.10.2까지는 `PUBLISHED AS`가 속성 목록이었고
(거의 모든 사람에게 *uid and cn*), `WITH` 열은 없었습니다.

표 뒤의 줄들은 구성에 의존하기 전에 알아야 할 것을 알려 줍니다. 먼저
[엔트리]({{< relref "/authnd/entries.md" >}})에 관한 것입니다.

- **누가 `posixAccount`가 아닌지**, 그리고 `uidNumber`, `gidNumber`,
  `homeDirectory` 중 무엇이 없는지
- **어떤 그룹에 `gidNumber`가 없는지**, 그리고 대신 무엇으로 게시되는지
- 엔트리의 어떤 클래스도 허용하지 않아서 **제외된 모든 속성**, 그리고 어떤 클래스라면
  허용하는지
- 스키마 검사에서 발견된 모든 문제와 함께, **게시되지 않은 모든 엔트리**
- **NT 키는 있고 `sambaSID`가 없는 사람**, 그래서 `sambaNTPassword`도 없는 사람

v0.12.0부터는 첫 줄과 표 사이에, [사이트 스키마]({{< relref "/authnd/schemas.md" >}})가
추가한 것과 소스가 선언하는 것이 나옵니다.

- **불러온 스키마 파일과 `schema` 블록**, 그리고 각각이 추가하는 것:
  `schema: etc/authnd/example.schema adds 3 object identifier macros, 2
  attribute types and 2 object classes`
- **각 소스가 선언하는 클래스**: `users "sql" declares exampleStaff and
  exampleLockerHolder for its people`, 그리고 선언의 위치
- **사람이나 그룹에서 빠진 모든 클래스**: 소스가 선언하는 클래스의 MUST가 없기
  때문입니다. `ben is published without exampleStaff, which its source declares: ben
  has no exampleEmployeeId, which exampleStaff requires`, 그리고 속성 줄들 뒤에는
  그 클래스와 함께 빠진 속성들
- **두 소스가 서로 다른 클래스를 선언하는 그룹**: 첫 번째 소스의 목록이 게시되고
  두 번째 소스의 목록은 무시됩니다.

빌드되지 않는 파일, 재정의, 그리고 정의되지 않았거나 STRUCTURAL이거나 authnd가
스스로 도출하는 선언 클래스는 `check`와 서버를 똑같이 멈추게 하며, 파일 또는
구성의 위치를 알려 줍니다.

그다음은 바인드와 검색에 관한 것입니다.

- **바인드가 담는 것**: *a password*, 또는 [`mfa` 블록]({{< relref "/authnd/mfa.md" >}})이
  있으면 *a password with a 6-digit code after it*, [`oidc` 블록]({{< relref "/authnd/tokens.md" >}})이
  있으면 토큰이 어디에서 오며 무엇을 통해 오는지
- **비밀번호로는 아예 바인드할 수 없는 사람**: NT 해시로만 알려진 사람 —
  [사람들]({{< relref "/authnd/people.md#written-in-the-configuration" >}})을 참조하십시오
- **누가 검색할 수 있는가**: reader, 또는 *no reader is declared: nothing may
  search, and binds are not affected*
- **`sambaNTPassword`가 게시되는지**, 그리고 무엇을 통해서인지 —
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})를 참조하십시오
- [`kerberos` 블록]({{< relref "/authnd/kerberos.md" >}})이 있으면 렐름과
  **누가 티켓을 발급받을 수 있고 누가 받을 수 없는지**를 이유와 함께
- `mfa` 블록이 있으면 **누가 두 번째 인증 요소가 없는지**, 그래서 비밀번호로
  바인드할 수 없는지. 옆에 `oidc` 블록이 있으면 `amr`이 두 종류를 지정하는
  토큰으로는 여전히 가능하다는 내용이 이 줄에 추가됨
- **어떤 소스에도 없는 사람을 지정하는 그룹**

마지막 항목은 있는 그대로 게시됩니다. 한 시스템의 앞단이 다른 시스템이 소유한
이름을 담는 것은 정당할 수 있기 때문입니다. 하지만 이를 알려 주는 것은, 달리
읽으면 오타이기 때문입니다. `posixGroup`에서는 낯선 사람이 `memberUid`이고,
`groupOfNames`에서는 여기에 있는 어떤 엔트리도 지정하지 않는 `member` DN
(여기서는 `member: uid=zoe,ou=people,dc=example,dc=org`)이며, go-authn/directory의
`ldapdir`은 v0.14.0부터 이를 아무에게도 매핑하지 않습니다. 여기서는 데이터베이스의
`team_members` 테이블에 여기에는 없는 사람인 `zoe`의 행이 있습니다.

```
GROUP      MEMBERS              PUBLISHED AS
engineers  dora, eli and zoe    groupOfNames
staff      alice, bob and dora  groupOfNames
[...]
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(낯선 사람을 지정하는 `group` *블록*은 즉시 거부됩니다.
[사람들]({{< relref "/authnd/people.md#written-in-the-configuration" >}})을 참조하십시오.)

v0.15.0부터 출력의 두 번째 줄은 `limits:`입니다. authnd가 적용할 연결 제한, 작업 기한, 시작 기한이 기본값을 포함해
출력됩니다. 이 페이지의 트랜스크립트는 이전 릴리스가 출력한 것이어서 이 줄이 보이지 않습니다. 실제 예는
[제한과 기한]({{< relref "/authnd/operations.md#limits" >}})에 있습니다.

## 거부하는 것 {#what-it-refuses}

다음은 각각 `check`와 서버를 똑같이 종료 상태 1로 멈추게 합니다. 각각 해당하는
페이지에 설명되어 있으며, 몇 가지를 출력된 그대로 보이면 다음과 같습니다.

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## 인증서, keytab, 그리고 볼 수 없는 한 가지 {#the-certificate-the-keytab-and-the-one-thing-it-cannot-see}

로드되지 않는 인증서와 `krbtgt/REALM`이 없는 keytab은 서버가 쓸 문구 그대로
`check`가 거부합니다.

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

수신하지 않고서는 `check`가 알 수 없는 것은 **포트가 비어 있는지**입니다. 같은
Kerberos 주소를 쓰는 두 번째 서버는 `check`를 통과하지만 시작할 때 거부됩니다.

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## 서비스 계정으로 실행하기 {#run-it-as-the-service-account}

```sh
sudo -u authnd authnd check /etc/authnd
```

이렇게 하면 root만 읽을 수 있는 파일의 문제가 재시작 때가 아니라 여기서
드러납니다. 업그레이드하기 전에 **새** 바이너리로 실행하십시오.
[설치]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}})를 참조하십시오.
