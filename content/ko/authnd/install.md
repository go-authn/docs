---
title: "authnd 설치하기"
linkTitle: "설치"
weight: 10
description: "릴리스 바이너리와 그 검증 방법, authnd 계정, systemd 유닛과 그것이 부여하는 권한, 그리고 업그레이드, 롤백, 제거."
tags: [authnd, 설치, systemd]
---

저장소에는 systemd 호스트에 필요한 두 파일이 있습니다.
`packaging/sysusers.d/authnd.conf`(계정)와 `packaging/systemd/authnd.service`(유닛)입니다.
이 페이지는 두 파일과 그 주변 단계를 설명합니다. go-pkgx의 버전 관리되는 서비스가
나중에 이 일을 대신하도록 되어 있지만, 아직 존재하지 않습니다.

## 릴리스 바이너리 {#the-release-binary}

각 태그는 amd64와 arm64의 linux, darwin, windows용 `authnd-<os>-<arch>`
(windows는 `.exe`)를 `CGO_ENABLED=0`으로 빌드하여 게시하며, `SHA256SUMS`
매니페스트와 모든 바이너리에 대한 빌드 출처 증명(attestation)도 함께 게시합니다.

```sh
version=v0.12.4
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

둘 중 하나라도 실패하면 중단하십시오. 릴리스 워크플로는 게시하는 태그를 정확히
보고하지 않는 바이너리의 게시를 거부하므로, 버전은 비교할 수 있는 값입니다.

```
$ authnd --version
authnd version v0.12.4
```

### 원하는 것만 빌드하기 {#building-only-what-you-want}

서버는 항상 포함되며, 두 개의 빌드 태그로 사람들이 올 수 있는 곳을 뺄 수 있습니다.
`-tags nosql`은 세 가지 데이터베이스 드라이버(pgx를 통한 PostgreSQL,
MySQL/MariaDB, modernc.org/sqlite를 통한 SQLite)와 `users "sql"` 블록을 뺍니다.
`-tags noldap`은 LDAP 클라이언트와 `users "ldap"` 블록을 뺍니다. 바이너리를
빌드할 때 뺀 블록을 지정한 구성에는 블록이 존재하지 않는다는 말 대신
*this binary was built without SQL support (-tags nosql)*라고 알려 줍니다.
릴리스 바이너리는 태그 없이 빌드됩니다.

## 계정 {#the-account}

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

sysusers.d의 정적 계정이며, `DynamicUser=`가 **아닙니다**. authnd가 읽는
파일 — 비밀번호 파일, DSN, keytab, TLS 키 — 은 `authnd` 그룹에 미리 부여된
비밀 값이고, [비밀번호 변경]({{< relref "/authnd/passwords.md" >}})은 그
파일들에 다시 기록합니다. 동적 uid는 서비스가 시작되기 전에는 존재하지 않으며,
그 uid가 기록한 파일은 나중에 다른 사람을 가리키게 될 번호에 속하게 됩니다.

두 파일은 바이너리와 같은 버전인 릴리스 태그의 `packaging/` 디렉터리에서
가져옵니다. 태그의 체크아웃에서, 또는 v0.12.4의 경우
<https://github.com/go-authn/authnd/tree/v0.12.4/packaging>에서 그 디렉터리를
바이너리 옆에 복사하십시오.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## 유닛이 부여하는 것과 그 이유 {#what-the-unit-grants-and-why}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

유닛의 나머지는 일반적인 강화 설정입니다(`ProtectHome`, `PrivateTmp`,
`PrivateDevices`, `ProtectProc=invisible`, 커널과 cgroup 보호,
`MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`,
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`). 의도적으로 **뺀** 것이
세 가지 있습니다.

| | |
|---|---|
| `ExecReload=` | authnd에는 다시 불러오기가 없습니다. 구성, 인증서, keytab을 한 번만 읽습니다. [운영하기]({{< relref "/authnd/operations.md" >}})를 참조하십시오 |
| `PrivateUsers=` | 사용자 네임스페이스 안에서는 `CAP_NET_BIND_SERVICE`가 호스트의 네트워크에 더 이상 적용되지 않아 389에 대한 바인드가 거부됩니다 |
| `ProcSubset=pid` | Go가 `net/core/somaxconn`을 읽는 `/proc/sys`를 숨겨서, 모든 리스너의 백로그가 Go의 대체값인 128로 떨어집니다 |

`IPAddressAllow=`/`IPAddressDeny=`도 설정하지 않았습니다. 어떤 네트워크가
디렉터리에 질의할 수 있는지는 사이트가 드롭인으로 정할 일입니다.

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

하나뿐인 capability는 특권 포트를 위한 것입니다. LDAP 389, LDAPS 636, 그리고
UDP와 TCP의 Kerberos 88입니다. 같은 머신의 PostgreSQL이나 MariaDB는 소켓을 통해
접근하며, 읽기 전용 파일 시스템에서도 허용됩니다. 상태 디렉터리
`/var/lib/authnd`는 SQLite 데이터베이스를 위한 것이며, authnd는 자체 상태를
유지하지 않습니다. 두 번째 인증 요소의 잠금 횟수는 메모리에 있고 재시작할 때마다
초기화됩니다.

## 구성 디렉터리 {#the-configuration-directory}

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

그 안의 모든 파일은 `root:authnd`, 모드 `0640`입니다. 비밀 값은 인라인이 아니라
`*_file` 키로 지정하는 파일에 둡니다. 파일에는 권한이 있지만, 누군가 붙여 넣은
구성에는 없기 때문입니다. `ProtectSystem=strict`에서는 서비스가 `/etc` 아래에 쓸
수 없는데, 구성에는 맞지만 사람들이 직접 바꾸는 비밀번호에는 맞지 않습니다.
비밀번호에는 별도의 디렉터리를 주십시오.

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

파일이 아니라 그 디렉터리여야 하는 이유는
[비밀번호 변경]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}})에
설명되어 있습니다.

| 키 | 기본값 | |
|---|---|---|
| `base_dn` | — (필수) | 트리의 루트, 예: `dc=example,dc=org`. `=`가 없는 값은 거부됩니다 |
| `listen` | `127.0.0.1:3893` | 주소 하나. 기본값은 루프백입니다. 시작하는 순간 모든 인터페이스에 나타나는 디렉터리는 누군가 의도적으로 내려야 하는 결정입니다. LDAP과 LDAPS가 모두 필요한 사이트는 인스턴스 두 개를 실행합니다 |
| `reader "<dn>"` | 없음 | 검색할 수 있는 서비스 계정. [누가 읽을 수 있는가]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})를 참조 |
| `cert_file`, `key_file`, `starttls`, `publish_nt_hash`, `samba` | 꺼짐 | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`, `group`, `users` | — | [사람들]({{< relref "/authnd/people.md" >}}). `user` 또는 `users` 블록이 최소 하나 필요 |
| `kerberos` | 없음 | [렐름]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | 없음 | [두 번째 인증 요소]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | 없음 | [바인드 시의 토큰]({{< relref "/authnd/tokens.md" >}}) |

구성의 상대 경로는 구성 파일이 아니라 프로세스가 실행되는 디렉터리를 기준으로
해석됩니다. 유닛은 `/`에서 실행되므로 경로는 절대 경로로 쓰십시오.

매번 시작하기 전에:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check`는 [자체 페이지]({{< relref "/authnd/check.md" >}})에 설명되어 있으며,
`authnd`로 실행하면 그 계정이 모든 파일을 읽을 수 있다는 것도 함께 증명됩니다.

## 업그레이드, 롤백, 제거 {#upgrade-roll-back-remove}

새 바이너리가 이전 바이너리를 대체하기 **전에** 새 바이너리로 구성을 점검하고,
이전 바이너리는 보관하십시오. 새 바이너리를 먼저 이전 바이너리 옆에 설치합니다.
그러면 실행 가능해지고 `authnd` 계정이 실행할 수 있는 위치에 놓입니다.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

새 태그의 `packaging/`을 설치된 것과 비교하십시오(v0.12.0의 것은 v0.11.1의
것과 같고 바뀌지 않았습니다). 롤백은 `authnd.previous`에서 같은 방식으로
설치하고 재시작하는 것입니다.

v0.10.x에서 v0.11.0으로 올릴 때는 위의 `check`가 중요한 단계입니다.
`publish_nt_hash = true`이면서 [`samba` 블록]({{< relref "/authnd/tls.md#the-samba-block" >}})이
없는 구성은 재시작 때가 아니라 거기서 거부되며, 표 뒤의 줄들이 누가 더 이상
`posixAccount`가 아니고 어떤 그룹이 더 이상 `posixGroup`이 아닌지 알려 줍니다
([엔트리]({{< relref "/authnd/entries.md" >}})).

⛔ v0.11.1에서 v0.12.0으로 올릴 때는 다른 무엇을 하든 업그레이드하십시오.
v0.11.1의 릴리스 바이너리는 Go 1.27.2로 빌드되어 GO-2026-6809(crypto/x509)의
영향을 받지만, Go 1.27.3으로 빌드된 v0.12.0은 그렇지 않습니다. 구성은 바꿀 필요가
없습니다. 사이트 고유의 스키마를 제공하려면 [사이트 스키마]({{< relref "/authnd/schemas.md" >}})를
참조하고, 파일은 절대 경로로 지정하십시오. systemd 유닛의 작업 디렉터리는 `/`이기
때문입니다.

제거하려면:

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`, `/var/lib/authnd`, `authnd` 계정은 그대로 남습니다. 앞의 둘에는
사람들의 자격 증명이 들어 있고, 재사용되는 uid는 다른 사람의 파일을 부여받을 수
있기 때문입니다. 직접 의도를 갖고 제거하십시오.
