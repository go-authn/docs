---
title: "라이브러리, 질문 하나씩"
linkTitle: "라이브러리"
weight: 50
description: "열네 개의 go-authn Go 모듈: 각각이 답하는 질문, 이 문서가 설명하는 버전, 그리고 별도의 모듈인 이유."
tags: [라이브러리]
---

[authnd]({{< relref "/authnd/_index.md" >}})와
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) 같은 프로그램은 각각 독립적으로
게시되고, 버전이 관리되고, 테스트되는 모듈로 만들어집니다. 각 모듈은 **하나의**
질문에 답하며, 프로그램은 자신이 묻는 질문의 모듈을 가져옵니다.

모두 순수 Go이며 `CGO_ENABLED=0`으로 빌드됩니다.

| 모듈 | 답하는 질문 | 이 문서가 설명하는 버전 | import 경로 |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | 충분한 수의 인증 요소가, 충분한 종류에서 답했는가, 그리고 어느 것들인가? | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | 이 여섯 자리 코드가 맞는가, 그리고 전에 사용된 적이 있는가? | v0.4.2 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | 64바이트 리포트로 보안 키와 어떻게 통신하는가? | v0.6.2 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | *등록된* 키가 답했는가, 그리고 사람이 그것을 만졌는가? | v0.4.2 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | 누군가는 누구이며, 무엇이 그를 증명할 수 있는가? | v0.15.0 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | LDAP 서버의 바이트는 무엇인가? | v0.10.0 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | 이 Kerberos 티켓이 이 서비스에 유효한가? | v0.3.1 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | 렐름은 디렉터리에서 어떻게 티켓을 발급하는가? | v0.4.3 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | 이 베어러 토큰은 누가 요청한다고 말하며, 믿어야 하는가? | v0.4.1 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | 페더레이션의 신원 공급자는 이 사람에 대해 무엇을 말했는가? | v0.4.1 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | sshd가 답하는 대로, 이 SSH 인증서나 키는 폐기되었는가? | v0.6.1 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | 데몬의 TLS 서버 인증서는 어디서 오는가? | v0.5.2 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | 이 WireGuard 키가 연결해도 되는가, 그리고 누구의 것인가? | v0.1.1 | `github.com/go-authn/wireguard` |
| [scim]({{< relref "/libraries/scim.md" >}}) | 신원 공급자가 방금 누구를 생성, 변경, 삭제했는가? | v0.1.0 | `github.com/go-authn/scim` |

## 모듈의 묶음 {#how-they-group}

**인증 요소** — 사람이 있는지 여부.
[mfa]({{< relref "/libraries/mfa.md" >}})는 얼마나 많은 증명이 충분한지를 결정하며
어떤 장치도 알지 못합니다. [totp]({{< relref "/libraries/totp.md" >}})는 인증 요소
하나, 휴대전화의 코드입니다. [fido]({{< relref "/libraries/fido.md" >}})는 보안 키와
CTAP로 통신하며 어떤 정책도 알지 못합니다.
[keyfactor]({{< relref "/libraries/keyfactor.md" >}})는 둘을 모두 가져오는 유일한
부분으로, 키를 인증 요소로 바꿉니다.

**디렉터리, 그리고 그 프로토콜.**
[directory]({{< relref "/libraries/directory.md" >}})는 모델입니다. 사람, 그리고 소스가
그 사람에 대해 보유한 자격 증명 — 비밀번호, NT 해시, 검증자, SSH 키, 일회용 코드
비밀 값 — 그리고 그것들과 별도로 그 사람을 설명하되 아무것도 증명하지 않는 속성.
[ldap]({{< relref "/libraries/ldap.md" >}})은 서버로서의 LDAP 와이어 프로토콜과, 엔트리를
대조할 수 있는 디렉터리 스키마(OpenLDAP 파일에서 읽거나 HCL2로 작성)입니다. 무엇에
응답하는지는 핸들러의 몫입니다.

**두 반쪽의 Kerberos.** [krb5]({{< relref "/libraries/krb5.md" >}})는 티켓을 *받아들입니다*.
keytab이 있고, AP-REQ가 들어오고, AP-REP가 나갑니다.
[kdc]({{< relref "/libraries/kdc.md" >}})는 비밀번호를 보유한 디렉터리에서 티켓을
*발급합니다*.

**페더레이션과 토큰.** [saml]({{< relref "/libraries/saml.md" >}})은 RENATER나 eduGAIN
같은 페더레이션 앞의 SAML 2.0 서비스 공급자입니다.
[oidc]({{< relref "/libraries/oidc.md" >}})는 공급자가 서명한 OpenID Connect 토큰을
검증합니다. 로그인 흐름 없이 리소스 서버 쪽 절반입니다.
[scim]({{< relref "/libraries/scim.md" >}})은 반대 방향입니다. 신원 공급자가 애플리케이션의
사람과 그룹을 생성, 갱신, 삭제하려고 호출하는 SCIM 2.0 엔드포인트입니다.

**폐기와 인증서.** [krl]({{< relref "/libraries/krl.md" >}})은 OpenSSH 키 폐기 목록을
읽고, 쓰고, 확인합니다. [servercert]({{< relref "/libraries/servercert.md" >}})는 데몬에
파일이나 ACME에서 가져온 TLS 인증서를 제공합니다.

**[wireguard]({{< relref "/libraries/wireguard.md" >}})**는 사람들이 공급자에 등록한
WireGuard 공개 키의 서명된 목록을 전달하며, 게이트웨이가 이를 피어로 바꿉니다.

## 별도의 모듈인 이유 {#why-they-are-separate-modules}

**티켓을 받아들이기만 하는 서비스는 KDC를 링크하지 않습니다.** NFS 서버는 클라이언트가
제시하는 티켓을 검증하며, keytab이 있을 뿐 렐름과는 다른 관계가 없습니다. 받아들이는 것과
발급하는 것이 하나의 모듈이라면, 그런 모든 서버가 실행하지 않을 티켓 발급 코드 경로와,
KDC가 사람을 읽는 디렉터리 모듈을 함께 갖게 됩니다.

이는 의도가 아니라 측정한 결과입니다. `github.com/go-authn/krb5@v0.3.1`만 가져오는
임시 모듈에서:

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.1
```

`github.com/go-authn/kdc@v0.4.3`을 가져오는 모듈에 같은 명령을 실행하면
`github.com/go-authn/directory`와 `github.com/go-authn/kdc`가 나열됩니다. 발급에는
사람이 필요하고, 받아들이는 데에는 필요하지 않습니다.

같은 규칙이 다른 곳에도 적용됩니다. `mfa`는 표준 라이브러리 밖의 것을 가져오지
않고, `fido`는 `mfa`를 가져오지 않습니다. 키를 깜박이게 하고 싶을 뿐인 프로그램이
정책 패키지를 함께 가져가지 않습니다. `totp`는 `mfa`에만 의존하고, `oidc`는 아무
의존성이 없습니다. `directory`는 LDAP, SQL, HCL 소스를 하위 패키지에 두며, 핵심
패키지는 표준 라이브러리 밖의 것을 가져오지 않고 `sqldir`는 `*sql.DB`를 받으므로
데이터베이스 드라이버는 프로그램이 선택합니다.

## 모든 페이지는 같은 부분으로 이루어집니다 {#every-page-has-the-same-parts}

질문, 설명하는 버전의 `go get` 줄, 그 버전에 대해 컴파일되는 최소 예제, 모듈이 코드에서
거부하는 것, 그리고 무엇과 대조해 검사하는지 — 이 구현이 아닌 구현으로, CI나 테스트에
이름이 있는 것. README와 코드가 다르면 페이지는 코드를 따릅니다.
