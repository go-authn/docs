---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "sshd가 AuthorizedPrincipalsCommand로 실행할 때 sshcert-authorize가 검사하는 것, 거부하는 것, 그리고 도메인 권한 부여가 없는 인증서도 거부하는 이유."
tags: [sshcert, ssh, sshd, eurohpc]
---

`sshd`는 인증서 로그인마다 어떤 principal이 그 계정에 로그인할 수 있는지 이 명령에
묻습니다. 인증서의 도메인 권한 부여가 이 호스트를 지정할 때만 계정의 principal을
응답하고, 그렇지 않으면 아무것도 응답하지 않으며 `sshd`는 인증서를 거부합니다.
GÉANT의 `ssh-cert-authorize`와 같은 인수, 플래그, 출력, 로그 형식을 사용하며,
무엇을 거부하는지가 다릅니다.

## sshd가 호출하는 방법 {#how-sshd-calls-it}

```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/efp-ssh-ca.pub
AuthorizedPrincipalsCommand /usr/local/bin/sshcert-authorize %u %k
AuthorizedPrincipalsCommandUser nobody
```

```sh
install -o root -g root -m 0755 sshcert-authorize /usr/local/bin/
echo login.example.org > /etc/ssh/cert-allowed-domain.conf
```

그리고 각 로컬 계정마다, 그 계정에 로그인할 수 있는 principal을 한 줄에 하나씩
`/etc/ssh/auth_principals/<account>`에 둡니다. sshd는 root가 소유하고 다른 누구도
쓸 수 없는 경로의 명령만 실행합니다.

`%u`는 로그인하려는 계정입니다. `%k`는 base64 형태의 인증서이며,
`ssh-...-cert-v01@openssh.com BASE64` 한 줄 전체도 읽고, 인수가 없으면 인증서를
표준 입력에서 읽습니다. 세 번째 인수가 주어지면(sshd의 `%t`) 인증서의 타입이어야
하며, 그렇지 않으면 인증서가 거부됩니다.

| 종료 | 출력 | sshd |
|---|---|---|
| `0` | 계정의 principal, 한 줄에 하나 | 인증서의 principal 중 하나가 그 안에 있으면 인증서를 받아들임 |
| `1` | 없음 | 거부함 |
| `2` | 없음 | 거부함: 인수가 잘못됨 |

{{< callout type="info" >}}
**서명, CA, 유효 기간은 검사하지 않습니다**

이 명령의 어떤 것도 인증서의 서명이나 유효 기간을 검증하지 않습니다.
`TrustedUserCAKeys`를 통해 CA를 신뢰하는 sshd가 그 일을 합니다. 이 명령은 한 가지
질문, 즉 인증서가 이 호스트와 이 계정을 위한 것인지만 판단합니다.
{{< /callout >}}

## 거부하는 것 {#what-it-refuses}

검사하는 순서대로:

1. 비어 있거나, `.`, `..`이거나, `/`, `\` 또는 NUL을 포함하는 계정 이름
2. 구성된 도메인이 없는 호스트, 또는 유효한 호스트 이름이 아닌 것
3. 구문 분석되지 않는 인증서, 일반 키, 또는 호스트 인증서
4. 인증서의 타입이 아닌 `%t`
5. `--krl`이 있을 때, 목록이 폐기한 인증서, 또는 목록을 읽을 수 없거나 만료된 경우
   **모든** 인증서
6. 존재하지만 형식이 잘못된 도메인 권한 부여, **플래그와 상관없이**
7. `--allow-no-grant`가 아닌 한, **도메인 권한 부여가 아예 없는 경우**
8. 어떤 패턴도 호스트의 이름 중 어느 것과도 일치하지 않는 권한 부여
9. principal 파일이 없거나 비어 있는 계정

호스트의 이름은 `--domain`, 또는 `--domain-env`가 지정하는 변수, 또는
`--domain-file`의 줄입니다(빈 줄과 `#` 주석은 무시하며, 여러 줄은 여러 이름이고
그중 어느 것이든 일치할 수 있습니다).

테스트 CA가 서명한 인증서에 대해, 계정 `alice`의 principal 파일에
`a1b2c3@univ-example.example`이 나열되어 있고 호스트 이름이
`login.hpc.example.org`인 경우입니다.

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

마지막 줄이 sshd가 읽는 응답이고, 그 앞의 줄은 로그이며 여기서는 표준 오류입니다.
다른 호스트에 대해 권한이 부여된 인증서:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

권한 부여가 없는 인증서:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

principal 파일이 없는 계정, 그리고 일반 키:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

이들은 모두 `1`로 종료했고 표준 출력에는 아무것도 출력하지 않았습니다.

## 권한 부여가 없는 인증서를 거부하는 이유 {#why-a-certificate-with-no-grant-is-refused}

GÉANT의 `ssh-cert-authorize`는 도메인 권한 부여가 없는 인증서("might be valid for
non-domain-based auth")와, 구문 분석할 수 없거나 비어 있는 권한 부여를 가진 인증서를
통과시킵니다. 그러면 `TrustedUserCAKeys`에서 **두 개의** CA(페더레이션의 CA와
직원용 자체 CA, 또는 테스트 CA)를 신뢰하는 사이트는 두 번째 CA의 인증서를 모든
호스트에서, principal 파일에 있는 어떤 principal로든 도메인 검사 없이 들여보내게
됩니다. 도메인 필터는 어디에서 사용할 수 있는지 말하지 않는 인증서를 거부해야만
필터가 됩니다.

GÉANT의 동작을 정말 원하는 사이트는 그렇게 선언하며, 명령은 적용할 때마다
기록합니다.

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

그렇더라도 존재하지만 형식이 잘못된 권한 부여는 거부됩니다.

## `--krl` {#krl}

`RevokedKeys`는 명령이 실행되기 전에 모든 키와 인증서에 대해 수행되는 sshd 자신의
검사이며 CA 키도 폐기합니다. 이를 우선하십시오. `--krl FILE`은 명령 안에서
OpenSSH KRL을 검사하며, sshd가 하지 않는 것을 더합니다. 목록이 만료되면
(`expires@go-authn.github.io` 확장이며 sshd는 이를 무시합니다) **모든** 인증서를
거부하고, 목록을 읽을 수 없을 때도 모든 인증서를 거부합니다. 만료가 없는 목록은
만료 없이 사용합니다.

세 번의 실행입니다. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})가 기록하는
KRL로, 먼저 현재 목록, 그다음 발급자의 목록이
[만료되었을 때]({{< relref "/authn-revokd/lapse.md" >}}) 기록하는 실패 시 차단 목록,
마지막으로 존재하지 않는 파일을 지정한 `--krl`입니다.

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

두 번째 실행이 거부되는 것은 실패 시 차단 목록이 인증서의 **CA 키**를 폐기하기
때문입니다. 검사는 인증서 자신의 키, 일련번호와 키 ID, 그리고 서명한 키를
포함합니다. 세 번째가 거부되는 것은 목록을 읽을 수 없기 때문입니다. 목록이 없다고
해서 폐기된 것이 없다는 뜻으로 받아들이지 않습니다.

## 플래그 {#flags}

```
$ sshcert-authorize -help
usage: sshcert-authorize [flags] USER [CERTIFICATE [KEYTYPE]]

An sshd AuthorizedPrincipalsCommand (%u %k) that refuses a certificate whose
ssh-domain-grant@core.aai.geant.org extension does not grant this host, or that has none.

  -allow-no-grant
    	let in a certificate with no domain grant (GÉANT's behaviour); a malformed grant is still refused
  -debug
    	log details
  -domain string
    	the host's domain (overrides --domain-env and --domain-file)
  -domain-env string
    	environment variable holding the host's domain
  -domain-file string
    	file holding the host's domain, one name per line (default "/etc/ssh/cert-allowed-domain.conf")
  -extension string
    	name of the domain-grant extension (default "ssh-domain-grant@core.aai.geant.org")
  -krl string
    	refuse certificates this OpenSSH KRL revokes, and every certificate once it has expired or cannot be read
  -principals-dir string
    	directory of principals files, one per user (default "/etc/ssh/auth_principals")
  -syslog
    	log to syslog, facility AUTH (--syslog=false: to stderr) (default true)
  -version
    	print the version and exit
```

**로그**는 기본적으로 syslog, facility AUTH로 가는 `key=value` 줄입니다
(`action=cert_processed`, `action=denied`, `action=authorized`, 그리고 `serial`과
`ca_fingerprint`). sshd는 명령의 표준 오류를 버리므로 운영 환경에서는 syslog를 켜
두십시오. `--debug`는 모든 것을 표준 오류에도 기록합니다. 계정 이름처럼 클라이언트에서
오는 값은 공백, `=`, 따옴표, 제어 문자를 포함하면 따옴표로 묶이므로 로그 필드를
위조할 수 없습니다.

**`-version`**은 릴리스 바이너리와 `go install`로 빌드한 바이너리 모두에서 모듈
버전을 출력합니다.

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

v0.1.5 이전에는 `go install`로 빌드한 바이너리가 `sshcert-authorize dev`를
출력했습니다.
