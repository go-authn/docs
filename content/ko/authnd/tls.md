---
title: "TLS: ldaps:// 또는 StartTLS, 둘을 동시에는 안 됨"
linkTitle: "TLS"
weight: 40
description: "파일에 있는 인증서로 TLS 위에서 LDAP을 서비스하기, ldaps://와 StartTLS 중 선택, 그리고 sambaNTPassword가 둘 중 하나에서만 게시되는 이유."
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file`과 `key_file`이 함께 있어야 TLS가 켜지며, 하나만 있으면 거부됩니다
(*one without the other serves nothing*). TLS 1.2가 최소 버전입니다. authnd에는
ACME 클라이언트가 없습니다. 두 파일은 다른 것이 기록합니다 —
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}}), certbot, 사이트
자체의 CA — 그리고 v0.15.0부터 authnd는 파일이 바뀌면 다시 읽으므로 재시작이 필요 없습니다.
[인증서 갱신](#renewal)을 참조하십시오. v0.14.1까지는 인증서를 리스너를 열 때 한 번만 읽었으므로
갱신할 때마다 authnd를 **재시작**했습니다.

## 두 가지 방식, 각각 리스너 하나 {#two-ways-one-listener-each}

| | `starttls` | 리스너 | `check`의 표시 |
|---|---|---|---|
| **ldaps://** | 설정하지 않음 | LDAP이 한 바이트도 오가기 전에 TLS 핸드셰이크가 이루어짐 | `ldaps://…` |
| **StartTLS** | `starttls = true` | 평문이며, 클라이언트가 요청하면 업그레이드됨 (RFC 4511 §4.14) | `ldap+starttls://…` |

둘 중 하나이며 그래야만 합니다. 리스너는 핸드셰이크를 요구하면서 동시에 핸드셰이크가
요청되는지 기다릴 수는 없습니다. 어느 쪽을 원하는지는 **클라이언트**에 달려
있습니다. 대부분의 클라이언트는 636의 `ldaps://`로 설정되어 있고, 389를 가리키며
"TLS 사용"을 선택한 클라이언트는 StartTLS를 요청합니다. 둘 다 필요한 사이트는
각각 자신의 `--config`로 인스턴스 두 개를 실행합니다. 인증서 없는
`starttls = true`는 거부됩니다.

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps:// {#ldaps}

서버, `127.0.0.1`용 CA 서명 인증서, 그리고 이 프로그램이 아닌 클라이언트가
검증한 체인입니다.

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS는 요청받을 때까지 거부합니다 {#starttls-which-refuses-until-it-is-asked-for}

StartTLS는 **클라이언트**가 요청하는 것이므로 제공하는 것만으로는 아무것도
약속하지 않습니다. 요청하지 않는 클라이언트는 평문으로 바인드할 것입니다. 그래서
`starttls = true`인 리스너는 연결이 업그레이드될 때까지 모든 바인드와 모든 검색을
`confidentialityRequired`로 거부합니다.

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

(`-ZZ`는 "StartTLS를 하고, 실패하면 실패 처리"입니다. `LDAPTLS_REQCERT=never`가
있는 것은 macOS에 포함된 `ldapsearch`가 시스템 저장소를 신뢰하며 이 테스트 CA를
신뢰하도록 지정할 수 없었기 때문입니다. 체인은
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error`로 따로
확인했고, `Verify return code: 0 (ok)`라고 응답했습니다.)

그 거부가 `cert_file`을 제안이 아니라 보장으로 만들며, `publish_nt_hash`가 의존하는
것도 그것입니다. 루트 DSE를 읽기 전에 `ldapsearch -x`가 보내는 익명 바인드도
포함되므로, StartTLS 리스너에서는 그 디스커버리 쿼리에도 `-ZZ`가 필요합니다.

## 인증서 갱신 {#renewal}

v0.15.0부터 갱신된 인증서에는 재시작이 필요 없습니다. authnd는 마지막으로 살펴본 뒤 5초가 지난 첫 TLS
핸드셰이크에서, 그리고 `SIGHUP`(`kill -HUP` 또는 `systemctl kill -s HUP authnd`)으로 즉시, `cert_file`과
`key_file`을 제공 중인 것과 비교합니다. 파일의 식별은 내용의 SHA-256이므로, 새 파일을 옛 파일 위로 이름 변경하는
갱신 도구와 제자리에서 다시 쓰는 도구가 모두 감지되며, 같은 타임스탬프 눈금 안에 쓰인 같은 크기의 쌍이 옛 것으로
오인되지도 않습니다.

로드되지 않는 새 쌍(쓰다 만 것, 인증서와 맞지 않는 키, 깨진 파일)은 아무것도 바꾸지 않습니다. authnd는 가진
인증서를 계속 제공하고, 파일의 그 상태에 대해 실패를 **한 번만** 기록하며, 파일이 다시 바뀌면 다시 시도합니다.
v0.15.0 이전에는 밤에 만료된 인증서가 누군가 authnd를 재시작할 때까지 모든 클라이언트에게 신뢰받지 못했습니다.
구성과 keytab은 여전히 시작할 때만 읽습니다.

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword`는 Samba나 다른 SMB 서버가 이 디렉터리를 통해 사람들을 인증할 수
있게 해 주는 것이며, 로그인 폼이 뜻하는 의미의 비밀번호 해시가 **아닙니다**.
`MD4(UTF16LE(password))`를 가진 사람은 비밀번호를 알지 못한 채로 NTLMv2를 통해 그
사람으로 인증됩니다. 그래서 요청할 때만 게시되고, v0.11.0부터는 사람들의 SID가
속한 도메인과 함께 게시됩니다.

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

리스너에 TLS가 있거나, 루프백(`127.0.0.0/8`, `::1`, `localhost`)이어서 네트워크를
전혀 지나지 않는 경우가 아니면 요청이 거부됩니다.

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### `samba` 블록 {#the-samba-block}

`sambaNTPassword`는 Samba의 `sambaSamAccount`에 속하며, 이 클래스의 MUST는 `uid`와
`sambaSID`이고 다른 클래스는 이를 허용하지 않습니다. authnd가 게시하는 모든 엔트리는
[자신이 제공하는 스키마]({{< relref "/authnd/entries.md" >}})를 통과하므로, 이
속성은 `sambaSamAccount`에서만 게시되고 그러려면 SID가 필요합니다.

| 키 | |
|---|---|
| `domain_sid` | 필수: `net getlocalsid`가 출력하는 SMB 서버의 도메인 SID, `S-1-5-21-…` |
| `algorithmic_rid_base` | 선택, 기본값은 Samba와 같은 `1000`. 홀수이거나 1000 미만이면 거부됩니다. Samba가 조용히 다른 값을 쓰게 되기 때문입니다 |

소스가 제공하는 경우([속성]({{< relref "/authnd/entries.md#adding-attributes" >}}))
사람의 `sambaSID`는 그 사람 자신의 `sambaSID` 속성입니다. 그렇지 않으면
`domain_sid-RID`이며, RID = 2 × `uidNumber` + `algorithmic_rid_base`로 Samba의
알고리즘 매핑입니다(smb.conf(5), *algorithmic rid base*). NT 키는 있고 둘 다 없는
사람은 `sambaNTPassword` **없이** 게시되며, `check`와 시작 로그가 누구인지
알려 줍니다. Samba 정의는 이 블록이 있을 때만 `cn=Subschema`가 제공하는 스키마에
추가됩니다. 이 정의는 Samba가 공개한 OID, 이름, 구문으로 작성한 것이며 GPL-3.0인
`samba.schema`에서 복사한 것이 아닙니다.

{{< callout type="error" >}}
**v0.10.x 구성에는 호환성이 깨짐: `samba` 블록 없는 `publish_nt_hash`는 시작하지 않습니다**

v0.10.x는 `publish_nt_hash = true`만으로 서비스했습니다. v0.11.0부터 그 구성은
시작 시와 `check`에서 거부되며, 무엇을 추가해야 하는지 알려 줍니다.

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

업그레이드하기 전에 새 바이너리로 `check`를 실행하십시오. 거부는 의도적입니다.
v0.10.x의 엔트리는 스키마를 통과할 수 없고, 조용한 두 가지 대안 — 모든 사람에게서
SMB를 빼앗는 속성 제외, 그 사람을 빼앗는 엔트리 제외 — 은 모두 콘솔에 아무 표시도
없이 일어나게 됩니다.
{{< /callout >}}

`publish_nt_hash` 없는 `samba` 블록도 아무것도 게시하지 않으므로 거부됩니다.

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### `check`가 알려 주는 것 {#what-check-says}

`ldaps://` 리스너의 세 사람입니다. alice는 비밀번호와 POSIX 세 가지가 있으므로
SID가 파생됩니다(2 × 1000 + 1000). bob은 NT 해시만 있고 자신의 `sambaSID`가
있으며, carol은 비밀번호가 있고 둘 다 없습니다.

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

StartTLS 리스너의 경우에는 *sambaNTPassword is published over TLS, once StartTLS
has been asked for*라고 나옵니다. alice에게는 NT 해시가 따로 적혀 있지 않으며,
alice의 해시는 가지고 있는 비밀번호에서 파생됩니다. bob의 해시는 SMB 서버가
사용하도록 게시되며, `check`는 bob이 authnd 자체에는 바인드할 수 없다는 것도
알려 줍니다. carol의 엔트리는 그 속성 없이 게시되며, 소스가 `uidNumber`나
`sambaSID`를 줄 때까지 SMB 서버는 carol에게 서비스할 수 없습니다.

같은 사람들의 StartTLS 리스너에서 reader가 받는 것입니다.

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

[reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})만 검색할 수
있으므로 reader만이 이 속성을 보게 됩니다. 따라서 누가 이를 읽을 수 있는가는 누가
reader의 비밀번호를 가지고 있는가와 같은 질문입니다.

{{< callout type="warning" >}}
**NTLMv2에는 비밀번호나 그 MD4가 필요하며, 다른 것으로는 안 됩니다**

authnd에게 누군가에 대해 묻는 파일 서버가 SMB로 그 사람에게 서비스할 수 있으려면
*소스*가 그에 충분한 것 — 비밀번호 또는 해시 — 를 가지고 있어야 합니다. 비밀번호만
확인하는 디렉터리 — `check`의 *a password check* — 에서 오는 사람은 그 사이에서
authnd가 무엇을 하든 `sambaNTPassword`를 받을 수 없습니다. `publish_nt_hash`가
없으면 아무도 받을 수 없으며, 그러면 `check`는 *sambaNTPassword is not published,
so nothing here can authenticate an SMB session*이라고 알려 줍니다.
{{< /callout >}}

## 토큰에도 필요함 {#tokens-need-it-too}

[`oidc` 블록]({{< relref "/authnd/tokens.md" >}})은 암호화되지 않은 연결에서의 토큰을
거부합니다. 단, `allow_plaintext = true`로 TLS가 이 프로세스 앞에서 종단된다고
선언한 경우는 예외입니다.
