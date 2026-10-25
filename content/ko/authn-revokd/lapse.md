---
title: "목록이 만료될 때"
linkTitle: "목록이 만료될 때"
weight: 40
description: "CA의 현재 목록이 없을 때 authn-revokd가 sshd를 위해 기록하는 것: 그 CA의 모든 인증서가 거부되도록 CA 키 자체를 폐기하는 KRL."
tags: [authn-revokd, 폐기, 실패 시 차단, sshd]
---

목록을 구할 수 없을 때 모든 것을 통과시키는 폐기 검사는, 목록을 막을 수 있는 공격자에게
무력화되는 검사입니다. 그래서 authn-revokd가 소스의 현재 목록을 보유하지 않을 때는,
그 소스의 목록이 보호하는 것을 현재 목록이 다시 도착할 때까지 **거부**합니다.

| 출력 | 소스에 현재 목록이 없는 동안 |
|---|---|
| `sshd`를 위한 KRL | authn-revokd가 **소스의 CA 키를 폐기하는** KRL을 기록 |
| TLS 서버를 위한 CRL | 만료된 CRL을 그대로 둠. OpenSSL이 만료된 CRL을 스스로 거부 |

## sshd를 위해: CA 자체를 폐기하기 {#for-sshd-revoking-the-ca-itself}

`sshd`에는 목록의 만료라는 개념이 없어서 마지막으로 기록된 파일을 영원히 읽을
것입니다. 하지만 모든 인증서의 **CA 키**는 `RevokedKeys`와 대조합니다. 그래서
보증할 수 없는 목록 대신 authn-revokd는 CA 자신의 키를 출력에 넣으며, 그 CA가
서명한 모든 인증서가 거부되고 다른 것은 거부되지 않습니다.

여기서는 발급자가 멈춰 있고 KRL 소스에 `max_age = "30s"`가 있어서, 보유한 사본이
한 시간이 아니라 1분 안에 만료됩니다. CRL 소스에는 `max_age`가 없으며 사본은 아직
현재입니다.

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-11T10:50:24Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh`는 `not current`이며 그 출력은 실패 시 차단 상태입니다. `bridge-x509`는
`not fetched`일 뿐이며 그 CRL은 그대로 남습니다
([`-once`가 보고하는 것]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
`SHA256:Fpa/...`는 bridge의 SSH CA입니다. 그것이 서명한 인증서는 이제 파일을 읽는
모든 것에게 폐기된 것입니다. 위의 명령은 `out/`이 있는 `revokd` 디렉터리에서
실행했고, 이것은 그 옆의 테스트 인증서가 있는 디렉터리에서
[sshcert-authorize 페이지]({{< relref "/sshcert/authorize.md#krl" >}})처럼 실행하므로
같은 파일이 `../revokd/out/sshd.krl`입니다.

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

주석에 `FAIL CLOSED`와 소스 이름이 있으므로 `ssh-keygen -Q -l`을 읽는 사람은 이유를
알 수 있습니다. 모든 소스가 만료되면 파일의 날짜는 1970년입니다. 출력은 동기화가
이를 **알아차리는 즉시** 기록되며, 데몬에서는 다음 `refresh`, 타이머에서는 다음
틱입니다. 현재 목록이 다시 도착하면 다음 동기화가 CA의 키 대신 그것을 기록하고, CA의
인증서는 다시 받아들여집니다.

**첫 번째 목록 전에도** 같습니다. 한 번도 가져오지 않은 소스는 현재인 것이 없으며,
그 CA는 첫 기록부터 폐기됩니다. 새 설치는 CA의 인증서를 확인 없이 받아들이지 않고
첫 목록이 검증될 때까지 거부합니다.

### 각 CA는 각자 {#each-ca-for-itself}

여러 소스를 병합하는 출력에서는 만료된 소스의 CA만 폐기됩니다. 나머지는 자신의 목록을
유지합니다. 병합할 수 없는 목록(go-authn/krl이 유지하는 일련번호 범위를 넘는 경우)은
자신의 CA에 한해서만 실패 시 차단되며 `/healthz`가 이를 지명합니다. 목록이 단독으로는
병합되지만 함께는 병합되지 않는 경우에만 출력의 모든 CA가 폐기되며, 주석이 이를
밝힙니다(`FAIL CLOSED, the output could not be rendered`). 이전 파일을 대신
유지하면 이후의 만료가 눈에 띄지 않게 됩니다.

## TLS 서버를 위해: CRL 자체 {#for-a-tls-server-the-crl-itself}

CRL은 이미 자신이 언제 유효하지 않게 되는지 밝히며, OpenSSL은 `nextUpdate`가 지난
것을 거부합니다("CRL has expired"). 그래서 authn-revokd는 마지막으로 검증된 CRL을
그대로 두고, TLS 서버가 스스로 실패 시 차단합니다. CRL 출력에 공급하는 소스에서
`max_age`가 거부되는 이유이기도 합니다. CRL을 로드한 서버는 authn-revokd가 무엇을
기록하든 `nextUpdate`까지 그것을 유지합니다.

## 만료를 스스로 확인하는 읽는 쪽 {#readers-that-check-the-expiry-themselves}

병합된 KRL은 현재 입력 중 가장 먼저 만료되는 것의 만료를 담습니다. go-fileshare의
`ssh_krl_file`이나
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}})처럼 이를
확인하는 읽는 쪽은 발급자가 멈춘 것을 알게 되는 것과 같이 authn-revokd가 멈춘 것을
알게 됩니다.

{{< callout type="warning" >}}
**authn-revokd가 실행 중일 때만 동작합니다**

파일을 실패 시 차단 상태로 만드는 것은 authn-revokd입니다. 멈춰 있는 동안 sshd는
현재이든 아니든 마지막으로 기록된 파일을 계속 읽습니다. 그래서 데몬에
`Restart=always`가 있고, 유닛이나 타이머, 또는 `/healthz`를 모니터링해야 합니다.
{{< /callout >}}
