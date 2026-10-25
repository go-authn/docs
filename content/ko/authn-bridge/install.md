---
title: "authn-bridge 설치하기"
linkTitle: "설치"
weight: 10
description: "정적 사용자, 디렉터리 세 개, 강화된 systemd 유닛: 릴리스 바이너리에서 실행 중인 서비스까지의 authn-bridge."
tags: [authn-bridge, 설치, systemd]
---

저장소에는 유닛과 그것이 실행되는 사용자가 들어 있습니다.
`packaging/systemd/authn-bridge.service`와
`packaging/sysusers.d/authn-bridge.conf`입니다. 아래의 모든 것은 별도 언급이 없으면
root로 실행합니다.

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | 바이너리 |
| `/etc/authn-bridge/*.hcl` | 구성, 이름 순으로 읽음. `root:authn-bridge`, `0750`, 파일은 `0640` |
| `/var/lib/authn-bridge/` | 키, 주체 솔트, SQLite 상태, 발급된 인증서, 비활성화 목록. `authn-bridge`, `0700` |
| `/run/authn-bridge/` | 구성이 요청하면 관리 소켓 |

## 바이너리 {#the-binary}

릴리스에는 amd64와 arm64의 Linux, macOS, Windows용 `authn-bridge-<os>-<arch>`,
`SHA256SUMS` 매니페스트, 바이너리별 빌드 출처 증명이 들어 있습니다.
[다운로드 검증하기]({{< relref "/security/verifying-releases.md" >}})가 둘을 확인하는
방법을 설명합니다. 또는 직접 빌드하면 바이너리에 버전이 기록됩니다.

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.1
$ authn-bridge --version
authn-bridge version v0.23.1
```

경로가 중요합니다. v0.20.0부터 프로그램은 `internal/app`에, 명령은
`cmd/authn-bridge`에 있으므로 `go install github.com/go-authn/bridge@...`는
아무것도 빌드하지 않습니다.

## 사용자, 그리고 동적 사용자가 아닌 이유 {#the-user-and-why-it-is-not-a-dynamic-one}

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

유닛은 `DynamicUser=`가 아니라 `User=authn-bridge`를 지정합니다. 서명 키, 주체 솔트,
SAML 키, 인증 기관은 첫 시작 **전에** 만들어지고, 수년간 유지되며, 재설치와 백업
복원을 거쳐도 하나의 소유자를 유지해야 합니다. 동적 사용자는 서비스가 시작될 때
UID를 받습니다.

## 키 {#the-keys}

`keygen`은 서비스의 사용자로 실행하여, 자신이 기록하는 것을 소유하게 하십시오.
이미 있는 파일을 덮어쓰기는 거부합니다.

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

서버에서는 경로가 `/var/lib/authn-bridge` 아래이고, 명령은
`runuser -u authn-bridge -- authn-bridge keygen ...`입니다.

| 플래그 | 기록하는 것 | 용도 |
|---|---|---|
| `--key` | RSA 3072 키 | ID 토큰(RS256), `/jwks`에 게시됨 |
| `--salt` | 무작위 32바이트 | 모든 `sub`, 이는 그 솔트 아래의 HMAC |
| `--access-token-key` | P-256 키 | 대신 ES256으로 서명하는 액세스 토큰, 훨씬 짧음 |
| `--ssh-ca` | OpenSSH 형식의 Ed25519 키 | [SSH 인증서]({{< relref "/authn-bridge/certificates.md" >}})와 KRL의 서명 |
| `--x509-ca DIR` | `DIR/ca.key`(P-256)와 `DIR/ca.crt`, 10년 유효, 경로 길이 0 | NFS 클라이언트 인증서와 CRL |

{{< callout type="warning" >}}
**솔트를 백업하고, 절대 바꾸지 마십시오**

새 솔트는 모든 사람에게 새 `sub`를 주며, 그러면 모든 신뢰 당사자가 새로운 사람을
보게 됩니다. 제거할 때 삭제하는 경우도 마찬가지입니다.
{{< /callout >}}

SAML 키와 인증서는 `openssl`로 만듭니다. 이것들은 페더레이션이 등록하는 것이고
모든 IdP가 암호화하는 대상입니다. 키는 RSA여야 합니다(IdP는 RSA-OAEP로 암호화합니다).
TLS 인증서가 아니며, TLS 인증서와 함께 바뀌지도 않습니다.

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

페더레이션의 메타데이터 서명 인증서는 페더레이션에서 가져오며, SHA-256 지문도
마찬가지입니다. 지문은 인증서와 같은 다운로드가 아니라 페더레이션의 웹 페이지에서
가져오십시오. [페더레이션 측]({{< relref "/authn-bridge/federation.md" >}})을
참조하십시오.

## 유닛 {#the-unit}

부여하는 것을 요약하면:

- `Type=exec`, `Restart=on-failure`, `RestartSec=5s`, `TimeoutStopSec=20s`.
  공급자는 `SIGTERM` 후 10초 이내에 리스너를 종료합니다.
- `StateDirectory=`, `RuntimeDirectory=`(둘 다 `0700`)와
  `ConfigurationDirectory=`(`0750`), `UMask=0077`. `ProtectSystem=strict`로 그 밖의
  모든 것은 읽기 전용입니다.
- capability 없음(`CapabilityBoundingSet=`와 `AmbientCapabilities=`가 비어 있음),
  `NoNewPrivileges=`, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
  `PrivateIPC=`, `ProtectHome=`, 커널, 시계, 호스트 이름, 컨트롤 그룹 보호.
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`: 리스너, 메타데이터, ACME CA,
  데이터베이스를 위한 TCP, 관리 API를 위한 소켓.
- `SystemCallFilter=@system-service`에서 `@privileged @resources`를 뺀 것이며,
  프로세스를 죽이지 않고 `EPERM`으로 거부합니다.

메타데이터를 공급자가 수신하기 전에 가져오므로 `network-online.target`을 기다립니다.

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

저널의 첫 줄은 [개요]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}})에
나온 것입니다.

### 변경하려면 재시작이 필요합니다 {#changes-need-a-restart}

구성은 한 번만 읽습니다. 유닛에는 `ExecReload=`가 없으므로 `systemctl reload`는
하는 척하지 않고 거부됩니다. `SIGHUP`(logrotate나 습관에서 오는)은 잡아서 기록하고
무시합니다. Go의 기본 동작에 맡기면 프로세스를 죽일 것이고, systemd는 이를
`Restart=on-failure`가 재시작하지 않는 정상 종료로 간주할 것입니다.

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

TLS 인증서 파일은 예외입니다. 바뀌면 다시 읽습니다.

### 443 포트 {#port-443}

기본 리스너는 TLS 리버스 프록시 뒤의 `127.0.0.1:8080`이며 capability가 필요 없습니다.
443 포트에서 직접 TLS를 서비스하려면(`cert_file` 또는 `acme`) 공급자에게
`CAP_NET_BIND_SERVICE`가 필요하고 비공개 사용자 네임스페이스를 벗어나야 합니다.
그 안에서 가진 capability는 호스트의 네트워크에 적용되지 않기 때문입니다.

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## 업그레이드와 되돌리기 {#upgrading-and-going-back}

먼저 `/var/lib/authn-bridge`를 백업하십시오. 다시 만들 수 없는 키와 솔트가 들어
있습니다. 동작하는 바이너리를 보관하고, 새 바이너리를 설치한 뒤, 재시작합니다.

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

되돌리는 것은 `authn-bridge.previous`로 같은 일을 하는 것입니다. 새 릴리스는 더 새
유닛을 제공할 수 있습니다. 재시작하기 전에 자신의 유닛과 비교하고, 설치하고,
`systemctl daemon-reload`를 하십시오.

### `bridge`에서 옮겨 오는 경우 {#coming-from-bridge}

구성은 그대로이며, 명령과 릴리스 자산의 이름만 바뀌었습니다. `bridge`를 실행하는
모든 유닛, 스크립트, cron 작업, `bearer_token_command`를 바꾸십시오. 로그 줄과 오류
접두사는 이제 `authn-bridge`라고 하므로, `bridge v0.`와 일치하던 경보는
`authn-bridge v0.`와 일치해야 합니다. 메트릭 이름(`bridge_*`), `bridge_state`
테이블, 사용자 측 캐시(사용자의 구성 디렉터리 안의 `go-authn-bridge`, Linux에서는
`~/.config`)는 그대로이므로, `authn-bridge token`은 `bridge`가 캐시한 로그인을
재사용합니다.
