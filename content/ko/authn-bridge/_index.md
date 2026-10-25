---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "SAML 페더레이션 앞에 놓인 OpenID Connect 공급자: 사람들은 자신의 기관에서 로그인하고, 애플리케이션은 토큰, SSH 인증서, X.509 클라이언트 인증서를 받습니다."
tags: [authn-bridge, oidc, saml]
---

**사람들은 RENATER의 Fédération Éducation-Recherche 또는 eduGAIN을 통해 자신의
대학에서 로그인하고, 애플리케이션은 OpenID Connect 토큰을 받습니다.** 같은 로그인으로
SSH 키를 인증받거나, NFS over TLS용 X.509 클라이언트 인증서를 발급받거나, SMB와 S3용
애플리케이션 비밀번호를 설정하거나, WireGuard 키를 등록할 수도 있습니다. 공급자는
자신이 발급한 것을 폐기할 수 있고, 폐기한 것의 서명된 목록을 게시합니다. 이미
전달된 액세스 토큰은 만료될 때까지 유효합니다. 순수 Go, `CGO_ENABLED=0`, 바이너리
하나입니다. 이 문서는 v0.23.3을 설명합니다.

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

v0.20.0 이전에는 명령이 `bridge`였습니다. 이는 사실상 모든 Linux 시스템에 설치된
iproute2의 `/sbin/bridge`이기도 하며, `PATH`에서 먼저 오는 쪽이 이겼습니다. 모듈
경로는 여전히 `github.com/go-authn/bridge`입니다.

## 브리지가 필요한 이유 {#why-a-bridge}

연구 페더레이션은 SAML을 사용합니다. 구성원은 기관마다 하나씩, 수백 개의 신원
공급자이며, 페더레이션이 게시하는 서명된 메타데이터 문서에 나열됩니다. 오늘날
작성되는 애플리케이션은 OpenID Connect를 원하고 하나의 공급자를 신뢰합니다.
authn-bridge가 그 하나의 공급자입니다. 한쪽에는 페더레이션에 한 번 등록된 SAML
서비스 공급자가 있고, 다른 쪽에는 OpenID 공급자가 있습니다.

게이트웨이는 그 뒤의 모든 애플리케이션에 대해 모두가 누구인지를 결정하므로,
이 프로그램의 대부분은 거부입니다. 페더레이션이 서명하지 않은 메타데이터, 다른
기관의 도메인에 속한 사람을 지명하는 어서션, IdP에게 권한이 없는 그룹, 그리고 이
중 어느 것이든 통과시킬 구성을 거부합니다. 안전하게 서비스할 수 없는 구성은
시작하지 않습니다.

## 시작할 때 출력하는 내용 {#what-it-prints-at-startup}

```
$ authn-bridge --config etc/bridge-admin.hcl
authn-bridge v0.23.3: http://127.0.0.1:28473 on 127.0.0.1:28473
metrics on 127.0.0.1:28475
admin API on unix:///tmp/authn/run/admin.sock
```

루프백의 테스트 공급자입니다(`http://` 발급자는 루프백 호스트에서만 받아들여집니다).
수신을 시작하기 **전에** 페더레이션의 메타데이터를 가져옵니다. 기관 하나도 지명할
수 없는 공급자는 아무도 로그인할 수 없는 공급자이므로, 메타데이터가 없으면 시작하지
않고 종료합니다.

## 다음에 볼 곳 {#where-to-go-next}

| | |
|---|---|
| [설치하기]({{< relref "/authn-bridge/install.md" >}}) | 사용자, 디렉터리, systemd 유닛, 키 |
| [구성]({{< relref "/authn-bridge/configuration.md" >}}) | 모든 블록, `check`, 시작 시 거부되는 것 |
| [페더레이션 측]({{< relref "/authn-bridge/federation.md" >}}) | 메타데이터, 서명자의 지문, 스코프, IdP가 어서션할 수 있는 것 |
| [토큰]({{< relref "/authn-bridge/tokens.md" >}}) | ID 토큰, 액세스 토큰, 디바이스 그랜트, 애플리케이션 비밀번호, WireGuard 키 |
| [리소스 지표]({{< relref "/authn-bridge/resources.md" >}}) | 클라이언트의 리소스 서버 중 한 번에 하나를 위한 토큰 (RFC 8707) |
| [인증서]({{< relref "/authn-bridge/certificates.md" >}}) | SSH 인증서, EuroHPC 프로필, NFS용 X.509 클라이언트 인증서 |
| [폐기]({{< relref "/authn-bridge/revocation.md" >}}) | 서명된 KRL과 CRL, 그리고 Shared Signals 송신기 |
| [관리 API]({{< relref "/authn-bridge/admin.md" >}}) | 사람이나 기관 비활성화, 상태 점검과 메트릭 |

서명하는 목록은 일반 `sshd`나 TLS 서버를 위해
[authn-revokd]({{< relref "/authn-revokd/_index.md" >}})가 읽고, 스스로 확인하는
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)도
읽습니다.

## 하지 않는 것 {#what-it-is-not}

- **하나의 프로세스.** `state` 블록이 있으면 리프레시 토큰과 `/userinfo`에서
  인정되는 액세스 토큰이 재시작 후에도 유지됩니다. 진행 중인 로그인, 코드, 디바이스
  그랜트는 유지되지 않습니다. 상태는 즉시 기록되고 시작할 때 읽으므로, 하나의
  데이터베이스를 쓰는 인스턴스 두 개는 서로가 기록한 것을 각각 놓치게 됩니다.
- 동적 클라이언트 등록도, 프런트 채널 또는 백 채널 로그아웃도 없습니다.
- 추가할 사용자나 그룹이 없습니다. 사람들은 그들의 기관이 보증하기 때문에
  존재하며, 그들의 그룹은 기관이 어서션하는 것입니다.

## 라이선스 {#licence}

BSD-3-Clause.
