---
title: "운영하기: 시그널, 재시작, 그리고 출력하는 내용"
linkTitle: "운영"
weight: 80
description: "authnd가 한 번만 읽는 것, SIGHUP이 다시 불러오지 않는 이유, 멈추는 방식, 출력에 기록하는 내용, 그리고 가동 중인지 확인하는 방법."
tags: [authnd, 운영, 시그널, systemd]
---

## 모든 것을 한 번만 읽습니다 {#it-reads-everything-once}

구성 파일과 keytab은 **시작할 때** 읽습니다.
이들을 다시 불러오는 기능은 없으며, 패키지로 제공되는 유닛에는 `ExecReload=`가 없습니다.
둘 중 무엇이든 바꾼 뒤에는:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

TLS 인증서는 v0.15.0부터 예외입니다. authnd가 `cert_file`과 `key_file`을 다시 살펴보므로
갱신에 재시작이 필요 없습니다. [인증서 갱신]({{< relref "/authnd/tls.md#renewal" >}})을 참조하십시오.

소스(아래 참조)를 제외하면, 실행 중에 적용되는 유일한 것은
[사람이 authnd를 통해 바꾸는 비밀번호]({{< relref "/authnd/passwords.md" >}})이며,
이때 `user` 블록만 다시 읽고 다른 것은 읽지 않습니다.

소스는 "한 번만 읽음"의 예외입니다. 사람과 그룹은 `refresh`마다(기본 60초이며
`refresh = "0"`이면 끔) 서비스 경로 밖에서 만든 새 스냅숏으로 다시 읽어 원자적으로
교체하므로, 삭제된 사람이나 그룹 구성원은 재시작 없이 한 주기 안에 사라집니다.
(v0.13.4는 한 번만 읽었고 그룹을 바꾸려면 재시작이 필요했습니다.) 실패한 새로 고침은
마지막 정상 데이터를 유지하며, 실패가 이어지는 동안 소스 이름과 함께 한 번만 로그에
남습니다. 권한 회수가 중요한 곳에서는 `max_age`(예: `"10m"`)를 설정하십시오. 데이터가
그보다 오래되면 검색, 사람의 바인드, 비밀번호 변경은 오래된 데이터 대신
`unavailable`(52)로 응답합니다. 시작할 때 읽을 수 없는 소스, 예를 들어 실행되지
않는 그룹 쿼리나 여러 데이터베이스 중 하나가 내려간 경우는 소스와 그룹의 이름을 밝히며
시작과 `check`를 거부합니다. LDAP 메시지 하나에 담기에 너무 큰 항목(약 3 MiB이며, 10 MB짜리
속성 값 하나면 도달합니다)은 게시되지 않고, 스키마에 맞지 않는 항목과 마찬가지로 시작할 때와
`check`에서 알려 줍니다.

## 시그널 {#signals}

| 시그널 | 일어나는 일 |
|---|---|
| `SIGTERM`, `SIGINT` | `stopping`을 출력하고, 리스너와 **수립된 모든 연결**을 닫고, 렐름을 멈추고, 소스를 닫은 뒤, 서버가 실제로 끝나면 0으로 종료합니다 |
| `SIGHUP` | 잡아서 기록하며, authnd는 **계속 실행됩니다**. TLS 인증서는 즉시 다시 읽습니다(v0.15.0). 구성과 keytab은 다시 불러오지 않습니다 |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 1 person from the configuration file
hangup: authnd does not reload its configuration or keytab; restart it to apply those (the TLS certificate is read again)
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

v0.15.0 바이너리의 한 번의 실행입니다. `kill -HUP`, 비밀번호 변경 시도 두 번(첫 번째는 거부, 두
번째는 수락), 그리고 `kill -TERM`. `SIGHUP` 뒤에도 프로세스는 그대로 있었습니다.

예전에는 `SIGHUP`이 authnd를 **종료시켰습니다**. 아무도 처리하지 않는 시그널에
대한 Go의 기본 동작이었고, systemd는 `SIGHUP`에 의한 종료를 정상 종료로 간주하므로
`Restart=on-failure`가 다시 시작하지 않았습니다. `kill -HUP` 한 번이나 logrotate의
`postrotate` 한 번으로 디렉터리가 영구히 내려갔습니다. 이제는 이 습관이 해롭지
않도록 시그널을 잡으며, 그 줄이 대신 무엇을 해야 하는지 알려 줍니다.

리스너만이 아니라 수립된 연결도 닫는 것은 의도적입니다. 수신을 멈추고 열린
연결에는 계속 응답하는 서버는 멈춘 것처럼 보이지만 멈추지 않은 것이며, 그것이
바로 적용되지 않는 재시작입니다.

## 출력하는 내용 {#what-it-writes}

모든 것은 표준 출력으로 가며, systemd에서는 저널입니다
(`journalctl -u authnd`).

- 시작할 때, 어디에서 수신하고 누구에게 서비스하는지 — `ldap on …`, `ldaps on …`
  또는 `ldap+starttls on …`, 그리고 `kerberos` 블록이 있으면
  `realm EXAMPLE.ORG on … (udp and tcp)`
- `mfa` 블록에서 거부된 모든 바인드, 거부된 모든 토큰, 거부되었거나 완료된 모든
  비밀번호 변경을 **이유와 함께** — 클라이언트는 이를 절대 듣지 못합니다.
  [두 번째 인증 요소]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})와
  [토큰]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}})을 참조하십시오
- KDC가 거부하는 모든 요청을 `kerberos:` 접두사와 Kerberos 오류 코드와 함께.
  [렐름]({{< relref "/authnd/kerberos.md#kinit-against-it" >}})을 참조하십시오
- LDAP 라이브러리 자체의 로그, `slog` 텍스트 형식, info 수준

`mfa` 블록이 없는 단순 바인드에서의 단순한 잘못된 비밀번호는
`invalidCredentials`로 응답하며 authnd 자체는 기록하지 않습니다.

## 제한과 기한 {#limits}

v0.15.0부터 authnd는 클라이언트, 느린 소스, 폭주가 자신에게 붙잡아 둘 수 있는 것에 상한을 둡니다.
구성의 최상위에 두는 선택 키 네 개입니다.

| 키 | 기본값 | 의미 |
|---|---|---|
| `max_connections` | `4096` (이전에는 무제한) | 동시에 열려 있는 연결의 최대 수. `0`은 무제한 |
| `max_connections_per_ip` | 없음 | 한 주소에서의 최대 수. `max_connections`를 넘을 수 없음 |
| `operation_timeout` | `30s` (이전에는 없음) | LDAP 작업 하나가 걸릴 수 있는 최대 시간. `"0"`은 없음, 그 외에는 `100ms` 이상 |
| `startup_timeout` | `60s` | 모든 소스를 열고 처음 읽는 데 걸릴 수 있는 최대 시간. `"0"`은 없음 |

상한을 넘은 연결은 연결 해제 통지(notice of disconnection)로 `busy`(51)를 받고 닫히며, 대기열에 들어가지
않습니다(RFC 4511 4.4.1). `operation_timeout` 시점에도 실행 중인 작업은 `timeLimitExceeded`(3)로 응답받습니다.
**핸들러가 막혀서 기한을 무시하더라도 마찬가지입니다**. 늦게 나온 결과는 버려집니다. 시작할 때 소스가 응답하지
않으면 authnd는 `startup_timeout` 뒤에 시작을 거부하며, 오류는 단계와 소스를 밝힙니다. 음수나 읽을 수 없는
기간은 시작할 때와 `check`에서 거부됩니다. v0.14의 동작을 원하면 `max_connections = 0`과
`operation_timeout = "0"`을 설정하십시오.

`check`는 앞으로 적용할 제한을 출력합니다. 아무도 모르는 채 기본값으로 운영하지 않도록 하기 위해서입니다.

```
$ authnd check etc2/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org
limits: 200 connections, 20 per address; an operation may take 10s; startup may take no limit

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid

GROUP  MEMBERS  PUBLISHED AS
staff  alice    groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

이 구성은 `max_connections = 200`, `max_connections_per_ip = 20`, `operation_timeout = "10s"`,
`startup_timeout = "0"`을 지정합니다. 이 네 키가 없으면 해당 줄은 `limits: 4096 connections, no limit per
address; an operation may take 30s; startup may take 1m0s`이며, 같은 바이너리가 이것도 출력했습니다.

### 장애는 틀린 비밀번호가 아닙니다 {#outage}

사람을 다른 디렉터리(`ldap` 소스)에 대해 확인하는데 그 디렉터리에 물어볼 수 없을 때, 즉 연결이 거부되거나
재설정되거나, `busy`, `unavailable`, `other`로 응답하거나, `operation_timeout` 안에 응답하지 않을 때, authnd는
LDAP `unavailable`(52)로 응답하며 `invalidCredentials`(49)로는 **절대** 응답하지 않습니다. 단순 바인드, 비밀번호
변경의 이전 비밀번호, `mfa` 바인드의 비밀번호 요소에 모두 해당합니다. v0.15.0 이전에는 이것이 틀린 비밀번호로
보고되었으므로, 디렉터리가 내려가 있는 동안 로그인 양식이 사용자에게 비밀번호가 틀렸다고 알렸습니다. 틀린
비밀번호는 여전히 49입니다. 원인은 클라이언트에게 알려지는 내용이 아니라 로그에 남으며, 장애는 실패한 추측으로
세지 않습니다.

## 시작하지 않는 경우 {#when-it-does-not-start}

거부는 표준 오류에 `authnd:` 접두사가 붙은 한 줄과 종료 상태 1로 나타납니다.
유닛에서는 `Restart=on-failure`가 5초마다 다시 시도하며 그때마다 그 줄이 저널에
남습니다. `check`가 거부하는 것은 모두 여기서도 거부되며, 서버만 발견하는 한 가지는
수신할 수 없는 주소입니다 —
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}})를
참조하십시오. LDAP 리스너, 인증서, 렐름은 모두 첫 줄을 출력하기 전에 열리므로,
시작할 수 없는 서버는 거부 메시지만 출력합니다. 여기서는 두 번째 인스턴스가 첫
번째 인스턴스의 Kerberos 포트와 부딪힙니다.

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

`ldap on …` 줄과 그 뒤의 `realm … on …` 줄은 양쪽 절반이 모두 수신 중이라는
뜻입니다.

## 가동 중인지 확인하기 {#telling-that-it-is-up}

상태 점검 엔드포인트도 메트릭도 없습니다. 있는 것은 다음과 같습니다.

- **프로세스와 그 종료 상태** — systemd에서는 `systemctl is-active authnd`.
  LDAP 리스너나 렐름이 스스로 멈추면 프로세스 전체가 그 오류와 함께 끝나므로,
  살아 있는 프로세스는 양쪽 절반이 모두 응답하는 프로세스입니다
- **루트 DSE**: 익명 클라이언트에게 응답하며 어떤 버전과 이야기하고 있는지
  알려 줍니다.

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.13.0
```

[StartTLS 리스너]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}})에서는
이 쿼리에 `-ZZ`가 필요합니다. 더 많은 것을 증명하는 프로브 — 소스가 여전히
응답한다는 것 — 는 그 용도로 따로 둔 사람이나 reader로 바인드하는 것이며,
`users "ldap"` 블록이 있으면 그 바인드는 이 디렉터리 뒤의 디렉터리에 도달합니다.

## 무엇이 어디에 있고, 재시작하면 무엇을 잃는가 {#what-lives-where-and-what-a-restart-loses}

| | |
|---|---|
| 구성, 비밀번호, DSN, 인증서, keytab | 구성이 지정하는 파일. 아무것도 복사되지 않습니다 |
| SQLite 데이터베이스 | DSN이 가리키는 곳. 유닛에서는 `/var/lib/authnd` |
| 두 번째 인증 요소의 횟수와 잠금 | 메모리에만 있음: **재시작하면 잊어버립니다**. 틀린 코드 백 번으로 잠긴 사람도 포함 |
| 사용된 일회용 코드 | 메모리에만 있음 |
