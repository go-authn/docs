---
title: "kdcd — 하나의 렐름을 위한 Kerberos KDC 데몬"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd는 kdc 라이브러리 위에 만든 프로그램입니다: UDP와 TCP의 AS 및 TGS, 하나의 HCL 파일, 모든 비밀은 파일, 그리고 비밀번호가 없는 사람에게 TGT를 발급하는 선택적 상호 TLS 리스너."
tags: [라이브러리, kerberos, 디렉터리, kdcd]
---

**[kdc]({{< relref "/libraries/kdc.md" >}}) 라이브러리는 어떻게 서비스로 실행되는가?**
`kdcd`는 라이브러리 [go-authn/kdc](https://github.com/go-authn/kdc) 위에 만든, 하나의
렐름을 위한 Kerberos KDC 데몬입니다. UDP와 TCP로 AS 및 TGS 요청에 응답하고, 선택적으로
다른 곳에서 본인임을 증명한 사람([go-authn/bridge](https://github.com/go-authn/bridge)의
패스키 로그인)을 위해 상호 TLS로 **TGT를 발급(mint)** 합니다. 프로토콜은 라이브러리가
가지고, 이 프로그램은 소켓과 설정, 그리고 비밀에 관한 규칙을 가집니다.

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

설치(바이너리는 `kdcd`입니다: MIT의 KDC는 `krb5kdc`, Heimdal의 KDC는 `kdc`):

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

순수 Go, `CGO_ENABLED=0`; 릴리스에는 바이너리마다 `SHA256SUMS` 매니페스트와 빌드 출처
증명이 붙습니다. 서비스로: `packaging/systemd/`(유닛과 sysusers 파일. [실행하기](#running-it) 참조).

## 비밀번호 없음 {#no-passwords}

**`kdcd`에는 비밀번호 경로가 없으며, 켤 수도 없습니다**(v0.2.0에서 제거됨. v0.1.0에는
`password_file`이 있었습니다). 여기서 사람은 장기 키가 없으므로, 사람에 대한 **AS-REQ**는
클라이언트가 무엇을 보내든 설계상 `KDC_ERR_NULL_KEY`로 응답됩니다. 사람은 패스키로 그를
인증한 호출자(go-authn/bridge)로부터 **mint 리스너**를 통해서만 TGT를 얻습니다.

- 디렉터리는 **누가 존재하는지, 그리고 그들의 그룹**을 말합니다. 소스가 가진 것 중 이름
  외에는 KDC에 닿지 않습니다. 모든 ID는 라이브러리가 보기 전에 이름만으로 다시 구성되므로
  (`nameOnly`), 소스가 실제로 공개한 비밀번호조차 키를 도출하지 않습니다. 아래의 로드 시
  거부는 이유를 알려 주기 위한 것이며, 유일한 방어가 아닙니다.
- 서비스와 `krbtgt/REALM`은 키를 keytab에 보관합니다: **무작위 키**이며, 비밀번호에서
  도출되지 않습니다(예를 들어 keytab 도구로 `/dev/urandom`의 32바이트를 사용해 생성하십시오).
- `password_file`, 비밀번호 또는 NT 해시 열을 지정하는 `users` 쿼리나 속성,
  `bind_password_file`, `bind_dn`(단순 바인드는 비밀번호입니다), 비밀번호를 담은 DSN:
  로드 시 제거 사실과 버전을 밝히며 거부됩니다.
- `ldap` 소스는 **익명으로** 읽힙니다. 클라이언트 인증서나 SASL EXTERNAL에 의한 서비스
  바인드는 `go-authn/directory`의 `hcldir.Block`에 그에 필요한 필드가 없어 아직 사용할 수
  없습니다. 그것이 생길 때까지 `bind_dn`은 거부됩니다.

라이브러리 쪽 설명은 [kdc 페이지]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}})에 있습니다.

## 설정 {#configuration}

하나의 HCL 파일. 그 안에는 비밀이 없으며, 모든 비밀은 파일입니다.

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: who exists. Any number of these, in any mix.
user "alice@poc.test" {}                  # a name; a TGT only through mint

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"              # no password in it: a client certificate or a socket
  users    = "select login as name from staff"
}
users "ldap" {                            # read anonymously
  url      = "ldaps://ldap.example.org"
  base_dn  = "ou=people,dc=example,dc=org"
}
```

`users` 블록은 [go-authn/directory/hcldir](https://github.com/go-authn/directory)의 것입니다.
kdcd는 그중 비밀번호를 담은 부분을 거부합니다(위 참조).

`kdcd check --config FILE`은 데몬이 구성할 모든 것을 읽어 구성하고, 디렉터리를 열고,
어디에서도 listen하지 않은 채, 제공할 내용을 출력합니다: 렐름, 주소, keytab의 프린시펄
(이름, kvno, etype. 키는 절대 출력하지 않음), 디렉터리가 보유한 사람 수, mint 호출자.
종료 상태 0과 마지막 줄 `ok`, 또는 첫 번째 거부입니다.

### 시작을 거부하는 경우 {#what-it-refuses-to-start-with}

| 거부되는 것 | 이유 |
| --- | --- |
| **그룹이나 다른 사용자가 읽거나 쓸 수 있는**, 또는 root나 데몬이 아닌 uid가 소유한 keytab, mint 키, DSN 파일 | 다른 계정이 읽을 수 있는 사본은 렐름의 모든 사람에 대한 티켓을 위조한다 |
| **모든 비밀번호 경로**: `password_file`(비어 있어도), `bind_password_file`, `bind_dn`, `password`, `passwd`, `nt_hash`, `userPassword`... 를 지정하는 `users`/`groups` 쿼리나 속성, 비밀번호를 담은 DSN | v0.2.0에서 제거됨: 여기서는 누구도 키가 없다. 메시지가 그렇게 알려 준다. 쿼리와 DSN 검사는 최선의 노력이며, 놓친 것은 `nameOnly`가 막는다 |
| 인라인으로 쓴 비밀(`password = "..."`는 인수가 아님) | 비밀은 파일에 있으며, 설정이나 그 백업, 로그에는 절대 두지 않는다 |
| 그룹이나 다른 사용자가 쓸 수 있는 설정 파일 | 그것을 쓰는 사람이 mint 호출자를 정한다 |
| `krbtgt/REALM` 키가 없거나 나열된 서비스가 빠진 keytab. **aes256-cts-hmac-sha1-96으로**(라이브러리가 발급하는 유일한 타입) | 시작은 되지만 첫 `kinit`에서 실패한다 |
| `listen`의 와일드카드나 호스트 이름(IP 리터럴 필요), 그리고 `mint`의 **모든** 와일드카드 | KDC와 mint 리스너는 누군가 고른 인터페이스 위에 있다 |
| 호출자가 없거나, 인증서가 없거나, 만료된 인증서를 가진 `mint` 블록 | 라이브러리는 호출자 없음을 "mint 꺼짐"으로 읽는다. 이는 조용히 아무것도 발급하지 않는 대신 그렇게 알려 준다 |
| `start_tls` 없이 다른 머신으로의 `ldap://` | 모든 비밀번호가 입력된 그대로 네트워크를 건넌다 |

비밀 파일은 **한 번만** 열리고, 열린 파일을 검사합니다(일반 파일, 모드, 소유자). 따라서
검사는 한 파일에 대해, 읽기는 다른 파일에 대해 이루어질 수 없습니다(모델은 go-fileshare의
`readKeytab`). `dsn_file`은 같은 방식으로 검사한 뒤 `hcldir`가
이름으로 읽습니다.

## mint의 신뢰 모델 {#the-mint-trust-model}

`POST https://<mint address>/mint`에 `{"principal": "alice", "lifetime_seconds": 36000}`을
보내면 `alice`의 TGT를 담은 KRB-CRED(RFC 4120 5.8)가 반환되며, 호출자는 이를 그 사람의
머신에 전달합니다([go-authn/kinit](https://github.com/go-authn/kinit)이 Windows 로그온
세션에 로드합니다). 이를 제한하는 것:

- **호출자는 TLS 클라이언트 인증서**이며, 리스너가 `client_ca_file`에 대해 검증합니다
  (TLS 1.3, `RequireAndVerifyClientCert`). 인증서가 없거나 CA가 서명하지 않은 연결은
  HTTP를 읽기 전에 핸드셰이크에서 실패합니다. 검증된 인증서는 이어서 **URI
  subjectAltName**으로 `callers`와 정확히 대조됩니다. 검증은 되지만 나열되지 않은
  인증서는 `403`입니다. 헤더나 본문의 어떤 것도 호출자를 지정하지 않습니다.
- **`callers`에 있는 자는 디렉터리의 어떤 프린시펄에 대해서도 TGT를 얻을 수 있습니다**
  (서비스는 절대 불가, 디렉터리에 없는 이름도 불가). 그 사람의 키 없이도 가능합니다.
  렐름이 신뢰하는 것은 호출자의 그 사람에 대한 인증이므로, 호출자는 KDC의 keytab만큼
  신뢰받습니다. ID 제공자마다 하나씩 나열하고, 각각에 전용 인증서를 주며,
  `client_ca_file`은 다른 어떤 것도 서명하지 않는 CA로 유지하십시오.
- 티켓은 `INITIAL | PRE-AUTHENT`이며, 갱신 가능·전달 가능·대리 가능하지 않습니다.
  수명은 요청, `lifetime`, 열 시간 중 가장 작은 값입니다.
- 세션 키는 `crypto/rand`로 만들어지고, 응답에서 한 번 프로세스를 떠나며, 절대 로그에
  남지 않습니다. 응답은 `Cache-Control: no-store`입니다. KRB-CRED는 키를 평문으로
  싣고 있으므로 **TLS 채널이 곧 암호화**입니다: 리스너를 내부 인터페이스에 두십시오.
- 제공되는 것은 `/mint`뿐이며, 타임아웃과 헤더 한도가 있습니다. 모든 mint와 모든 거부는
  호출자의 URI와 요청된 프린시펄과 함께 로그에 기록됩니다.

전체 위협 모델은 라이브러리의 풀 리퀘스트
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38)의 것이며, 라이브러리 README의
[발급 절](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)과
[감사 노트](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)가
함께 있습니다. 여기서는 그 어느 것도 반복하거나 약화하지 않습니다.
[go-authn/bridge](https://github.com/go-authn/bridge)의 `kerberos` 블록이 호출자 쪽입니다:
그 `kdc_url`은 `https://<mint address>/mint`이고, 그 `ca_file`이 위의 `cert_file`에
서명하며, 그 클라이언트 인증서의 URI 이름이 `callers`의 항목입니다.

## 실행하기 {#running-it}

`packaging/systemd/kdcd.service`는 `packaging/sysusers.d/kdcd.conf`의 시스템 사용자로,
[authn-bridge](https://github.com/go-authn/bridge)의 유닛과 같은 강화 설정으로 실행합니다.
포트 88은 특권 포트이므로, 유닛은 정확히 `CAP_NET_BIND_SERVICE`만 부여하고 다른 것은
부여하지 않습니다.

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

비밀은 `kdcd`(또는 root) 소유에 모드 0600이어야 하며, 그룹 `kdcd`의 0640은 의도적으로
거부됩니다. 설정 변경은 `systemctl restart kdcd`입니다(데몬은 다시 읽지 않으며,
클라이언트는 거부된 연결을 재시도합니다).

Windows에서는 모드 비트가 의미가 없고 검사되지 않습니다: 서비스를 실행하는 계정만
읽을 수 있는 곳에 파일을 두십시오.

## 여기에 없는 것 {#not-here}

크로스 렐름, PKINIT, FAST, 갱신 가능하거나 사후 날짜의 티켓, kadmin 프로토콜,
aes256-cts-hmac-sha1-96 이외의 모든 암호화 타입은 라이브러리 자체의 한계입니다
([go-authn/kdc](https://github.com/go-authn/kdc#readme)). `kdcd`에는 아직 다시 읽기도
메트릭 엔드포인트도 없습니다.

## 참조 {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd), v0.2.0.
