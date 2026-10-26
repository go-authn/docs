---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "SSH 사용자 인증서의 GÉANT / EuroHPC 도메인 권한 부여 확장, 그리고 인증서가 이 호스트를 위한 것인지 sshd가 묻는 실패 시 차단 명령인 sshcert-authorize."
tags: [sshcert, ssh, eurohpc]
---

**페더레이션 CA의 인증서는 그것만으로 그 CA를 신뢰하는 모든 호스트에 대한 권한이
아닙니다.** EuroHPC Federation Platform의 SSH CA는 인증서가 대상으로 하는 호스트를
확장 `ssh-domain-grant@core.aai.geant.org`에 기록하는데, `sshd`는 이를 무시합니다.
go-authn/sshcert는 그 확장을 읽고 쓰며, 이 패키지의 명령 `sshcert-authorize`가
`sshd`가 이를 강제하기 위해 실행하는 것입니다. 순수 Go, `CGO_ENABLED=0`입니다. 이
문서는 v0.1.9을 설명합니다.

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | `AuthorizedPrincipalsCommand`: 무엇을 검사하는지, 무엇을 거부하는지, sshd가 어떻게 호출하는지 |

## 확장 {#the-extension}

데이터는 호스트 패턴의 간결한 JSON 배열이며, `["login.example.org"]` 같은
형태입니다. `*`는 하나의 레이블 안에서 **하나 이상의** 문자와 일치하며, 이름은
대소문자를 구분하지 않고 비교합니다.

| 패턴 | 일치 | 불일치 |
|---|---|---|
| `login.example.org` | `login.example.org`, `LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`, `a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

읽기는 엄격합니다. 인코더가 쓰는 것만 받아들입니다. 공백 없음, `]` 뒤에 아무것도
없음, JSON 이스케이프 없음, 중복 없음, 패턴은 최대 64개이며 각각 문자, 숫자,
하이픈, `*`로 이루어지고, 레이블은 1에서 63바이트, 전체 최대 253바이트, 그리고
**가장 오른쪽 레이블에는 `*`가 없어야** 합니다. `null`, 객체, 숫자, 중첩 배열은
거부됩니다. `[]`는 받아들여지며 어떤 호스트도 허용하지 않습니다.

존재하지만 형식이 잘못된 권한 부여는 절대 없는 것으로 보고되지 않습니다. 그
차이가 이 명령의 핵심입니다.

## 누가 사용하는가 {#who-uses-it}

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})**는
  클라이언트의 `ssh_domain_grants`에 대해, 이 패키지의 `ValidatePattern`으로 각
  패턴을 검사한 뒤 확장을 기록합니다.
- **go-fileshare**의 SFTP 서버는 `ssh_domains`로 이를 읽고, `ssh_accept_ungranted`가
  설정되지 않은 한 권한 부여가 없는 인증서를 거부합니다.
- **sshcert-authorize**는 일반 `sshd`를 위한 같은 검사입니다.

## 라이선스 {#licence}

BSD-3-Clause.
