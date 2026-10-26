---
title: "authn-revokd 설치하기"
linkTitle: "설치"
weight: 10
description: "강화된 systemd 서비스로서, 또는 타이머의 일회성 실행으로서의 authn-revokd, 그리고 sshd와 TLS 서버를 그것이 기록하는 것에 연결하는 방법."
tags: [authn-revokd, 설치, systemd]
---

저장소는 `packaging/`에 유닛 세 개와 계정 하나를 제공합니다.
`authn-revokd.service`(데몬), `authn-revokd-once.service`와
`authn-revokd-once.timer`(대안), 그리고 `sysusers.d/authn-revokd.conf`입니다.

| 경로 | 설명 | 소유자, 모드 |
|---|---|---|
| `/usr/local/bin/authn-revokd` | 바이너리 | root, `0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | `authn-revokd` 시스템 계정 | root, `0644` |
| `/etc/systemd/system/authn-revokd.service` | 데몬 | root, `0644` |
| `/etc/authn-revokd/revokd.hcl` | 구성, 기본 `-config` | root, `0644` |
| `/etc/authn-revokd/ca/` | 목록이 서명되어야 하는 CA 키와 인증서 | root, `0755`, 그 안의 파일은 `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`, 유일하게 쓸 수 있는 곳 | authn-revokd, `0755` |
| `/var/lib/authn-revokd/state/` | `state_dir`: 검증된 사본 | authn-revokd, `0700` |
| `/var/lib/authn-revokd/sshd.krl` | 출력: `sshd`가 읽는 것 | authn-revokd, `0644` |

**출력을 `/var/lib/authn-revokd`에 기록하고, 서버가 그곳을 가리키게 하십시오.**
출력은 최종 이름 옆에 기록된 뒤 이름이 바뀌어 덮어쓰므로, 그 *디렉터리*에 쓸 수
있어야 합니다. `/etc/ssh`를 쓰기 가능하게 하면 `authn-revokd` 계정이 `sshd_config`를
바꿀 수 있게 됩니다. 출력은 `0644`이며 `UMask=0077`에도 불구하고 명시적으로 chmod하여,
자신의 사용자로 실행되는 `sshd`와 TLS 서버가 읽을 수 있게 합니다. 상태는 `0700`으로
유지됩니다.

## 바이너리, 계정, 유닛 {#the-binary-the-account-the-unit}

릴리스에는 amd64와 arm64의 Linux, macOS, Windows용 `authn-revokd-<os>-<arch>`가
`SHA256SUMS`와 빌드 출처 증명과 함께 들어 있습니다
([다운로드 검증하기]({{< relref "/security/verifying-releases.md" >}})). 또는
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.6`.

계정과 유닛은 바이너리와 같은 버전인 릴리스 태그의 `packaging/` 디렉터리에서
가져옵니다. 태그의 체크아웃에서, 또는 v0.6.6의 경우
<https://github.com/go-authn/revocation/tree/v0.6.6/packaging>에서 그 디렉터리를
바이너리 옆에 복사하십시오.

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

계정은 `DynamicUser=`가 아니라 정적 계정입니다. authn-revokd는 자신의 uid나 root가
아닌 사람이 소유한 상태 디렉터리를 거부하며, 상태는 재시작과 업그레이드를 거쳐서도
다음 목록의 순서를 계속 정해야 합니다. 동적 사용자라면 파일이 root 소유 `0700`인
`/var/lib/private` 아래에 있게 되어, 자신의 사용자로 실행되는 TLS 서버가 CRL을 읽을
수 없습니다.

## 데몬 {#the-daemon}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

그리고 그 주위에: `User=authn-revokd`, capability 전혀 없음, `NoNewPrivileges=`,
`ProtectSystem=strict`에 `StateDirectory=authn-revokd`(`0755`)가 유일하게 쓸 수 있는
곳, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`, `PrivateIPC=`,
`AF_INET AF_INET6 AF_UNIX`만, `@system-service` 시스템 콜에서
`@privileged @resources`를 뺀 것.

**sshd는 KRL의 만료를 무시하므로 `Restart=always`입니다.** 목록이 만료되면 파일은
*이 프로세스가* 실패 시 차단 상태로 만듭니다. 프로세스가 멈춰 있는 동안 sshd는 마지막으로
기록된 파일을 계속 읽고, 그동안 발급된 폐기는 도착하지 않습니다. 유닛을 모니터링하거나,
미러가 켜져 있으면 `/healthz`를 모니터링하십시오.

**`systemctl reload`는 지금 동기화합니다.** `SIGHUP`을 보내며, 에이전트는 다음
`refresh`를 기다리지 않고 모든 소스를 즉시 가져옵니다.

```
hangup: syncing now
```

구성은 시작할 때 한 번만 읽으므로 다시 읽지 않습니다. `revokd.hcl`을 바꾼 뒤에는
`systemctl restart authn-revokd`를 하십시오. (v0.6.0 이전에는 처리되지 않은
`SIGHUP`이 프로세스를 죽였고, systemd는 이를 정상 종료로 간주합니다.)

### sshd를 연결하기 전에 켜십시오 {#enable-it-before-wiring-sshd}

{{< callout type="warning" >}}
**`RevokedKeys`가 존재하지 않는 파일을 지정하면 sshd는 모든 인증서를 거부합니다**

그러므로 authn-revokd를 먼저 시작하고 출력이 생길 때까지 기다리십시오.
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl`은 모든 소스가 현재인 동안
주석 `authn-revokd sshd`를 출력합니다.
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

그다음 `/etc/ssh/sshd_config`에:

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

그리고 `sshd -t && systemctl reload ssh`. sshd는 인증할 때마다 `RevokedKeys`를 읽으므로
authn-revokd가 파일을 다시 기록해도 다시 불러올 필요가 없습니다. 원자적 이름 변경이면
충분합니다.

### TLS 서버의 CRL {#a-tls-servers-crl}

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

TLS 서버는 구성을 로드할 때 CRL을 읽으므로, 파일이 바뀌면 다시 불러와야 합니다.
`on_change` 명령은 `authn-revokd` 계정으로 실행되는데 이 계정은 `systemctl reload
nginx`를 할 수 없습니다. 대신 systemd가 root로 파일을 지켜보게 하십시오. 출력에 대한
경로 유닛(`PathChanged=`)이 `systemctl reload nginx`를 실행하는 `oneshot`을
시작하게 합니다.

## 또는: 타이머의 `-once` {#or--once-on-a-timer}

`authn-revokd -once`는 한 번 동기화하고 종료하며, 목록이 현재가 아니거나 가져올 수
없으면 `1`입니다
([`-once`가 보고하는 것]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
출력은 어느 쪽이든 기록되며, 목록이 만료되면 sshd에 대해 실패 시 차단 상태가 됩니다.

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

일회성 실행은 데몬의 계정과 강화 설정을 갖습니다. `TimeoutStartSec=5min`은 소스에서
멈춘 동기화가 다음 틱보다 오래 살아남지 않게 하고, `RandomizedDelaySec=10s`는
함께 시작한 서버 군이 같은 박자로 발급자를 폴링하지 않게 합니다.

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**둘을 함께 켜지 마십시오.** 유닛이 충돌하므로 하나를 시작하면 다른 하나가 멈춥니다.
데몬이 더 나은 선택으로 남습니다. 만료된 목록을 타이머가 다음 틱을 기다리는 동안 데몬은
다음 `refresh`에서 실패 시 차단 처리하며, 미러로 동작하는 것도 데몬뿐입니다.
`listen`은 `-once`에서 무시됩니다. 발사를 멈춘 타이머는 멈춘 데몬과 같으므로
`systemctl status authn-revokd-once`를 모니터링하십시오.

## 업그레이드와 되돌리기 {#upgrading-and-going-back}

새 바이너리를 이전 것 옆에 설치하고, 교체하고, 재시작합니다. 상태는 이어집니다.
검증된 사본이 다음 목록의 순서를 계속 정하므로, 업그레이드도 이전 바이너리로의
롤백도 오래된 목록이 들어오게 하지 않습니다.

## 제거하기 {#uninstalling}

서버의 구성에서 `RevokedKeys`와 `ssl_crl`을 **먼저** 제거하고 서버를 다시
불러오십시오. 파일이 사라지면 sshd는 모든 인증서를 거부합니다.
