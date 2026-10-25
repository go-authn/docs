---
title: "go-authn"
linkTitle: "홈"
type: docs
cascade:
  type: docs
description: "순수 Go로 만든 인증: 누군가가 지금 있다는 것을 증명하는 인증 요소, 그 사람이 누구인지 알려 주는 디렉터리, Kerberos의 양쪽 절반, 그리고 SAML 페더레이션 앞에 놓인 OpenID Connect 공급자."
---

**두 가지 질문이 있으며, 서로 같지 않습니다.** *이 사람이 지금 여기 있는가?*는
*이 사람은 누구이며, 무엇이 그를 증명하는가?*와 다릅니다. go-authn은 둘 모두에
답합니다. 존재를 증명하는 인증 요소, 각 사람에 대해 비밀번호 필드가 아니라
그를 **증명하는 것**을 담는 디렉터리, Kerberos의 양쪽 절반, 그리고 SAML
페더레이션 앞에 놓인 OpenID Connect 공급자입니다. 순수 Go이며
`CGO_ENABLED=0`입니다. 이 문서는 [상태 페이지]({{< relref "/status.md" >}})에
나열된 릴리스를 설명합니다.

## 네 가지 프로그램 {#four-programs}

| | 무엇인가 | 이 문서가 설명하는 버전 |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | 다른 곳(파일, SQL 데이터베이스, 다른 디렉터리)에 있는 사람들을 위한 LDAP 서버이며, 선택적으로 Kerberos 렐름도 제공합니다 | v0.12.1 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | SAML 페더레이션(RENATER, eduGAIN) 앞에 놓인 OpenID Connect 공급자로, SSH 인증서를 발급하고 이를 폐기하는 목록에 서명하기도 합니다 | v0.23.3 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | 그 목록을 가져와 서버가 읽기 전에 각각 검증하고, 목록이 만료되면 실패 시 차단(fail closed)합니다 | v0.6.5 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`로, 인증서의 도메인 권한 부여가 이 호스트를 지정하는지 sshd가 묻는 대상입니다 | v0.1.7 |

각각은 Linux, macOS, Windows의 amd64와 arm64용 정적 바이너리 하나이며,
`SHA256SUMS`와 빌드 출처 증명(provenance)과 함께 배포됩니다:
[다운로드 검증하기]({{< relref "/security/verifying-releases.md" >}}).

```sh
go install github.com/go-authn/authnd@v0.12.1
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.5
```

명령 이름이 `authn-*`(그리고 `authnd`)인 것은 다른 것들도 실행되는 머신에
설치되기 때문입니다. `/usr/bin`에 단순한 `bridge`나 `revokd`가 있으면
다른 사람이 필요로 할 수 있는 이름을 차지하게 됩니다.

## 그 아래의 라이브러리 {#and-the-libraries-under-them}

프로그램은 얇습니다. 프로그램이 하는 일은
[열네 개의 모듈]({{< relref "/libraries/_index.md" >}})에 들어 있으며, 모듈마다
질문 하나씩을 맡습니다. 그래서 Kerberos 티켓을 *받기만* 하는 서비스는 KDC를
링크하지 않고, 일회용 코드만 확인하는 서비스는 디렉터리를 링크하지 않습니다.

## 디렉터리가 사람을 증명하는 것을 담는 이유 {#why-the-directory-carries-what-proves-somebody}

SMB는 NT 해시가 필요하고, S3는 SigV4가 비밀번호로 HMAC을 계산하므로 비밀번호
자체가 필요하며, Kerberos 렐름은 비밀번호에서 파생된 키가 필요한데 NT 해시는
그 키가 아닙니다. 이 중 하나만 가진 신원은 그 사람이 무엇을 입력하든 어떤
프로토콜은 처리할 수 있고 어떤 프로토콜은 영원히 처리할 수 없습니다. 그래서
go-authn의 디렉터리는 **각 사람이 증명할 수 있는 것**을 기록하며,
`authnd check`는 무엇이든 다시 시작하기 전에 누구에게 Kerberos 티켓을 발급할 수
있고 누구에게는 결코 발급할 수 없는지 출력합니다.

```
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

이것은 authnd v0.11.0 자체의 출력입니다: [전체 출력]({{< relref "/authnd/check.md" >}}).

## 다른 사람들의 도구로 판단하기 {#judged-by-other-peoples-tools}

프로토콜의 한 가지 해석으로 만든 픽스처는 그 해석만 확인할 수 있습니다. 그래서
서버는 자신이 작성하지 않은 클라이언트가 읽습니다. OpenLDAP의 `ldapsearch`가
authnd에 바인드하고, MIT의 `kinit`이 그 렐름에서 티켓을 받으며, OpenSSH가
authn-bridge가 발급한 인증서와 KRL을 읽습니다.
