---
title: "목록 검증 방법"
linkTitle: "검증"
weight: 30
description: "authn-revokd가 목록을 보관하기 전에 확인하는 것: 서명, 날짜, 그리고 보유한 목록보다 오래되지 않았다는 것(재시작을 거쳐서도)."
tags: [authn-revokd, 폐기, 보안]
---

검증되지 않는 목록은 절대 기록되거나 제공되거나 사용되지 않습니다. 마지막으로 성공한
사본이 남습니다. 어떤 이유로든 실패한 가져오기는 그것을 아무것도 폐기하지 않는 빈
응답으로 대체하지 않습니다.

## 서명 {#the-signature}

**KRL**은 서명 `<url>.sig`와 함께 가져옵니다. 파일 전체에 대한 armored SSHSIG이며,
`ssh_ca`로 구성된 **SSH CA 키**가 `krl@go-authn.github.io` 네임스페이스에서 만든
것입니다. 네임스페이스는 서명이 다른 용도로 오인되는 것을 막습니다. 서명자는
SHA-512로 해시하며 SHA-256도 받아들입니다. PROTOCOL.sshsig가 금지하는 SHA-1 형식의
RSA 서명은 거부됩니다.

KRL 자체는 `sshd`가 구문 분석하는 방식대로 구문 분석되어야 하며, OpenSSH가 검증하지
않는 OpenSSH 자체의 서명 섹션을 담고 있어서는 안 됩니다.

다른 키로 서명된 목록은 거부됩니다.

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:6iM7YPhdfXxQEj/PUf7CYbqBuSiVTVMx2VADj63cAg4: public key does not match
bridge-x509: version 1793014030593, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
output sshd: wrote /tmp/authn/revokd/out/other.krl
output tls: wrote /tmp/authn/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

여기서 `ssh_ca`는 bridge의 목록에 서명하지 않은 키를 지정했고, 오류가 그 키를
지명합니다. 검증되지 않는 서명은 두 요청 사이에 다시 발급된 목록일 수도 있으므로,
보고하기 전에 둘 다 한 번 더 가져옵니다. 이것은 그 소스의 첫 가져오기였으므로
보관할 정상 사본이 없었고, 출력은 즉시
[실패 시 차단 목록]({{< relref "/authn-revokd/lapse.md" >}})입니다. (v0.6.2 이전에는
같은 실패가 위 메시지 앞에 "the list changed between it and its signature"를
붙였는데, 마치 목록이 다시 발급된 것처럼 보였습니다.)

서명은 `If-Match: <the list's ETag>`로 가져옵니다. 두 요청 사이에 다시 발급된
목록은 `412`로 응답하며 둘 다 다시 가져옵니다.

**CRL**은 `x509_ca`로 구성된 CA 인증서와 대조합니다. 먼저 원시 바이트의 서명을,
나머지를 구문 분석하기 **전에** 확인하므로, 누가 서명했든 큰 CRL은 구문 분석이
아니라 서명 검사의 비용만 듭니다. 그다음 발급자가 그 인증서의 subject여야 하고,
CRL Number와 `thisUpdate`보다 뒤의 `nextUpdate`가 있어야 하며, 델타 CRL이어서는
안 되고, CRL Number와 Authority Key Identifier 이외의 critical 확장이나 critical
항목 확장을 담고 있어서도 안 됩니다.

KRL은 `expires@go-authn.github.io` 확장에 **언제 만료되는지도 밝혀야** 합니다. 그렇지
않은 것은 오래된 것과 구별할 수 없습니다.

본문의 크기는 제한됩니다. KRL은 32 MiB, 그 서명은 64 KiB, CRL은 64 MiB입니다.

## 날짜 {#the-dates}

목록은 다음일 때 현재입니다.

- 지금이 만료 전일 때(KRL의 확장, CRL의 `nextUpdate`)
- 5분 넘게 미래에 발급되지 않았을 때: 시계가 그보다 많이 앞서 있는 발급자는 나이를 알
  수 없는 목록을 기록합니다
- `max_age`가 있으면, 그보다 오래 전에 발급되지 않았을 때

현재가 아닌 목록은 가져올 때 거부됩니다. `304 Not Modified`는 새 소식이 아닙니다.
보유한 사본이 그동안 만료되었을 수 있으며, 매 동기화마다 다시 판단합니다.

## 보유한 목록보다 오래되지 않음 {#never-older-than-the-list-held}

목록의 위치는 **버전**(KRL의 `krl_version`, CRL Number), 그다음 **발급 시각**(KRL의
생성 날짜, CRL의 `thisUpdate`)입니다. 목록은 더 높은 버전이거나, 같은 버전이 더 나중에
발급되었을 때(같은 폐기를 새 만료와 함께 다시 발급)만 보유한 것을 대체할 수 있습니다.
그 밖의 것은 롤백입니다. 여전히 서명되어 있고 만료되지 않았지만 더 새 목록이 폐기한
것을 되돌릴 재생되거나 복원된 오래된 목록입니다.

### 재시작을 거쳐서도 {#across-restarts-too}

보유한 목록은 `state_dir`에 소스당 파일 하나로 보관되며, 목록과 서명이 함께 들어
있고, 디렉터리를 동기화한 단일 이름 변경으로 기록됩니다. 시작할 때 각 사본을
**다시 검증**하며(만료되었든 아니든 다음에 올 것의 순서를 정합니다), 더 이상 검증되지
않는 사본은 다음 것의 순서를 정하는 데조차 신뢰하지 않고 로그에 그렇게 기록합니다.

여기서는 재시작 후, 소스가 이전 bridge 프로세스가 19초 전에 제공한, 여전히 서명되어
있고 만료되지 않은 목록을 가리킵니다.

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
bridge-x509: version 1793014030593, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/authn/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-26T11:26:49Z, the copy held at 2026-10-26T11:27:10Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-26T12:27:10Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261026T122710
# Comment: authn-revokd sshd
```

첫 번째 실행은 출력을 기록하지 않았습니다. 파일이 이미 그 목록을 담고 있었기
때문입니다. 더 오래된 목록은 거부되고 출력은 더 새 것을 유지합니다. 이를 거부한
프로세스는 더 새 목록을 본 적이 없었으며, `state_dir`에서 읽어 온 것입니다.

상태가 롤백을 감지할 수 있게 하는 것이므로, 디렉터리는 sshd의 StrictModes 규칙을
따릅니다([구성]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}})).
두 번의 쓰기 사이의 충돌이 검증되지 않는 쌍을 남겨 롤백 방지 장치까지 함께 잃게 할 수
없습니다. 목록과 서명은 하나의 파일입니다.

## `-once`가 보고하는 것 {#what--once-reports}

`-once`는 소스에 현재 목록이 없거나, **마지막 가져오기가 실패했거나**, 출력을 기록할
수 없으면 `1`로 종료하며, 마지막 줄이 앞의 두 가지 중 어느 쪽인지 알려 줍니다.

| 마지막 줄 | 소스 | 그 출력 |
|---|---|---|
| `not current: <source>` | 현재 목록이 없음: 한 번도 가져오지 못했거나, 만료되었거나, `max_age`를 넘김 | sshd에 대해 실패 시 차단 |
| `not fetched: <source> (the list held is current until <T>)` | 가져오기가 실패했지만 보유한 사본은 아직 현재 | `T`까지 그 사본에서 변경 없이 기록 |

여기서는 보유한 두 목록이 아직 현재인 동안 발급자가 멈춰 있습니다.

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-26T12:27:10Z), bridge-x509 (the list held is current until 2026-10-26T12:27:10Z)
```

그 실행은 `sshd.krl`을 그대로 두었습니다. 보유한 목록이 만료되면 같은 소스는
`not current`로 보고되며, [목록이 만료될 때]({{< relref "/authn-revokd/lapse.md" >}})처럼
두 종류가 한 줄을 공유할 수 있습니다. v0.6.2 이전에는 두 경우 모두 `not current`로
보고되었는데, 가져오기만 실패했는데도 목록이 만료되었다고 말하는 것이었습니다. 종료
상태는 그때도 `1`이었습니다.

미러의 `/healthz`는 대신 보유한 사본으로 판단하며, 발급자가 내려가 있고 사본이 아직
현재인 동안 `ok`로 응답했습니다.
