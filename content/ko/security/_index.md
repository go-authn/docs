---
title: "보안"
linkTitle: "보안"
weight: 55
description: "프로그램이 거부하는 것, 폐기가 공급자에서 모든 서버로 전달되는 방식, 그리고 정품 바이너리를 다른 것과 구별하는 방법."
tags: [보안]
---

go-authn은 사람을 증명하도록 요청받으므로, 거부가 예외가 아니라 곧 설계입니다. 이
절은 프로그램 경계를 넘나드는 거부를 모아 둔 것이며, 각 프로그램 자체의 페이지가
그 프로그램이 스스로 거부하는 것을 설명합니다.

## 가장 중요한 거부 {#the-refusals-that-matter-most}

| | 거부되는 것 | 이유 |
|---|---|---|
| authnd | 선언된 `reader`가 아닌 누군가의 검색 | 바인드는 누군가가 누구인지를 증명할 뿐이며, 모든 사람을 나열할 권한이 아닙니다 |
| authnd | 소스에 비밀번호가 없는 사람에 대한 Kerberos 티켓 | KDC에는 비밀번호에서 파생된 키가 필요하며, NT 해시나 비밀번호 확인으로는 이를 만들 수 없습니다 ([이유]({{< relref "/authnd/kerberos.md" >}})) |
| authnd | `mfa` 블록 옆의 `kerberos` 블록 | kinit은 비밀번호만 담으므로, 렐름이 `mfa` 블록이 두 요소가 필요하다고 한 사람들에게 하나의 요소만으로 티켓을 발급하게 됩니다 |
| authn-bridge | 아무도 서명하지 않은 어서션, 기관 자체의 범위 밖에서 온 식별자 | 페더레이션의 모든 구성원이 신뢰되므로 각자는 자기 사람들로 제한되어야 합니다. 그렇지 않으면 어느 한 기관이 누구든 지명할 수 있습니다 |
| authn-revokd | 서명되지 않았거나, 만료되었거나, 보유한 것보다 오래된 목록 | 중간의 미러는 목록을 지연시킬 수는 있어도 위조하거나 되돌릴 수는 없습니다 |
| authn-revokd | 만료된 목록을 신뢰하는 것 | CA 자체를 폐기하는 목록을 기록하므로, sshd는 오래된 목록을 신뢰하는 대신 거부합니다 |
| sshcert-authorize | 도메인 권한 부여가 이 호스트를 지정하지 않는 인증서 | 페더레이션 CA의 인증서는 그것만으로 그 CA를 신뢰하는 모든 호스트에 대한 권한이 아닙니다 |

## 폐기, 처음부터 끝까지 {#a-revocation-end-to-end}

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}})가 KRL(SSH 인증서용)과
   CRL(X.509 클라이언트 인증서용)에 서명하고 날짜를 기입하여 게시합니다.
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})가 각 목록을 가져와
   서명과 날짜를 검증하고, 보유한 목록보다 오래된 것은 (재시작을 거쳐서도) 거부하며,
   그런 다음에야 서버가 읽는 곳에 기록합니다.
3. sshd(`RevokedKeys`), go-fileshare, 그 밖의 모든 것은 이미 검증된 파일을
   읽습니다.

공급자의 Shared Signals 송신기를 통한 CAEP `session-revoked` 이벤트는 어떤 목록도
지명할 수 없는 것, 즉 특정 시점 이전에 사람에게 발급된 모든 것을 무효로 합니다.
go-fileshare의 문서가 수신 측을 설명합니다:
[폐기 목록](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
[공유 시그널](https://go-fileshare.github.io/docs/latest/security/shared-signals/).

## 릴리스 {#releases}

모든 바이너리는 릴리스 워크플로가 태그된 커밋에서 빌드하며 세 가지 방법으로 확인할
수 있습니다: [다운로드 검증하기]({{< relref "/security/verifying-releases.md" >}}).
