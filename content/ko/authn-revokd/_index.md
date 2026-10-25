---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "서명된 KRL과 CRL을 가져와 검증되는 목록만 보관하고, sshd와 TLS 서버가 읽는 곳에 기록하며, 목록이 만료되면 실패 시 차단하는 에이전트."
tags: [authn-revokd, 폐기, krl, crl]
---

**OpenSSH에는 KRL을 배포하는 방법이 없고, KRL에는 그것이 오래되었다고 말하는 것이
아무것도 없습니다.** `sshd`는 몇 달 전에 갱신이 멈춘 파일도 현재 목록으로 읽습니다.
authn-revokd는 [authn-bridge]({{< relref "/authn-bridge/revocation.md" >}})가 게시하는
목록에 대해 두 틈을 모두 메웁니다. 각 목록을 가져와 검증되는 경우에만 보관하고,
`sshd`나 TLS 서버가 읽는 곳에 기록하며, 목록이 만료되면 **CA 자체를 폐기하는** 목록을
기록합니다. 순수 Go, `CGO_ENABLED=0`, 바이너리 하나입니다. 이 문서는 v0.6.4를
설명합니다.

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.4
$ authn-revokd -version
authn-revokd v0.6.4
$ authn-revokd -help
Usage of authn-revokd:
  -config string
    	the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -once
    	sync once and exit: 1 when a list is not current, or could not be fetched
  -version
    	print the version and exit
```

`-help`는 0으로 종료합니다. v0.6.2 이전에는 2로 종료했습니다.

v0.6.0 이전에는 명령이 `revokd`였고 기본값으로 `/etc/revokd.hcl`을 읽었습니다. 이제
그 파일을 읽는 것은 없으며, 그 파일은 있는데 새 기본값은 없으면 오류가 두 경로를 모두
지정합니다.

## 한 번의 실행으로 하는 일 {#what-it-does-in-one-run}

루프백의 테스트 authn-bridge에 대해, KRL 소스와 CRL 소스가 있는 경우:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
bridge-x509: version 1791712224691, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261011T115024
# Comment: authn-revokd sshd
```

새로운 것이 없는 두 번째 실행은 아무것도 출력하지 않고 0으로 종료합니다. 출력은
내용이 바뀔 때만 다시 기록됩니다.

## 전송 방식이 중요하지 않은 이유 {#why-the-transport-does-not-matter}

모든 목록은 스스로를 인증합니다. KRL은 CA 자신의 키로 만든 분리된 SSHSIG 서명으로,
CRL은 해당 CA의 서명으로 인증합니다. 모든 목록은 언제 유효하지 않게 되는지를
밝힙니다. 그러므로 목록은 HTTPS, 클러스터 내부의 일반 HTTP, 미러, 파일 중 무엇으로든
올 수 있습니다. 전송 방식은 변경이 얼마나 빨리 도착하는지를 정할 뿐, 위조되었거나
오래된 목록을 받아들일지 여부는 정하지 않습니다.

| | KRL | CRL |
|---|---|---|
| 진본 | SSH CA 키의 SSHSIG, 네임스페이스 `krl@go-authn.github.io` | 해당 CA가 서명 |
| 현재성 | `expires@go-authn.github.io`, sshd는 무시 | `nextUpdate` |
| 역행 없음 | `krl_version`, 그다음 생성 날짜 | CRL Number, 그다음 `thisUpdate` |
| 실패 시 차단 | authn-revokd가 CA 키를 폐기하는 KRL을 기록 | OpenSSL이 만료된 CRL을 스스로 거부 |

## 다음에 볼 곳 {#where-to-go-next}

| | |
|---|---|
| [설치하기]({{< relref "/authn-revokd/install.md" >}}) | 데몬, 또는 타이머의 `-once`, sshd와 nginx 연결하기 |
| [구성]({{< relref "/authn-revokd/configuration.md" >}}) | 소스, 출력, 미러, 거부되는 것 |
| [목록 검증 방법]({{< relref "/authn-revokd/verification.md" >}}) | 서명, 날짜, 보유한 목록보다 오래되지 않음(재시작을 거쳐서도) |
| [목록이 만료될 때]({{< relref "/authn-revokd/lapse.md" >}}) | CA 자체를 폐기하는 KRL |

## 하지 않는 것 {#what-it-does-not-do}

폐기는 authn-revokd가 폴링하는 주기(`refresh`)에 발급자가 다시 발급하기까지의 지연을
더한 것보다 빨리 서버에 도달하지 않습니다. 발급자가 내려가 있는 동안 그 인증서는
목록의 만료 시점부터 거부됩니다. CA의 키를 가진 사람은 인증서에 서명할 수 있는 것처럼
어떤 목록에도 서명할 수 있습니다.

## 라이선스 {#licence}

BSD-3-Clause.
