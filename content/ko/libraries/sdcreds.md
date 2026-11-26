---
title: "sdcreds — systemd 없이 쓰는 systemd 자격 증명"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds는 systemd 자격 증명 형식(systemd-creds encrypt 및 decrypt)을 Go에서 읽고 쓰며, 명령줄과 감독되는 서비스에 $CREDENTIALS_DIRECTORY를 제공하는 s6 도우미를 갖추고 있습니다."
tags: [libraries, sdcreds, secrets, s6]
---

**systemd 유닛이 `LoadCredentialEncrypted=`로 받는 자격 증명이 서비스에 필요한데
systemd가 없다면?** `sdcreds`는
[systemd 자격 증명](https://systemd.io/CREDENTIALS/) 형식
(`systemd-creds encrypt` / `decrypt`)을 Go에서 읽고 쓰며, 명령줄과 s6가 감독하는
서비스에 동일한 `$CREDENTIALS_DIRECTORY`를 제공하는 도우미를 갖추고 있습니다.

지원하는 키는 **null**, **host**(`/var/lib/systemd/credential.secret`),
**host-scoped**(`--uid` / `--user`)입니다. TPM2 및 공개 키 자격 증명은 인식된 뒤
`*UnsupportedModeError`로 거부되며, 추측하는 일은 없습니다.

## 설치 {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

이 페이지가 설명하는 버전은 v0.3.0입니다.

## 명령줄 {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

Go에서의 동일한 동작:

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run`은 무엇이든 마운트하기 **전에** `--source`의 모든 파일을 복호화하고,
서비스별 `tmpfs`(`nodev,noexec,nosuid,nosymfollow,noswap`, 모드 0700, 크기와 inode
수 제한. 커널에 해당 옵션이 없으면 `ramfs`)를 마운트하며, 평문을 서비스 사용자
소유의 0400으로 기록하고, 읽기 전용으로 다시 마운트하고, `CREDENTIALS_DIRECTORY`를
설정한 다음, 권한을 내려놓는(`no_new_privs`, 빈 capability 집합) 자식
프로세스에서 서비스를 시작하고 그 종료를 기다립니다.

- `s6-run`은 여전히 s6가 감독하는 프로세스입니다. `TERM`, `INT`, `HUP`, `QUIT`,
  `USR1`, `USR2`, `ALRM`, `CONT`를 서비스로 전달하고, 서비스의 상태로
  종료하며(시그널로 종료된 경우 128에 시그널 번호를 더한 값), 받은 디스크립터를
  넘겨주고, `s6-run`이 죽으면 서비스도 종료됩니다.
- 자격 증명은 서비스가 끝날 때, 그리고 프로그램을 실행할 수 없어 `s6-run`이
  실패하기 전에 제거됩니다.
- 마운트는 기본적으로 비공개 네임스페이스에 있으며(`--unshare=false`로 끌 수
  있음) 서비스와 함께 사라집니다.
- null 키로 봉인된 자격 증명은 `--allow-null`을 지정하지 않으면 거부되고, 이름이
  없는 것은 항상 거부됩니다.
- `sdcreds s6-finish --service=web`은 지연 언마운트하고 디렉터리를 제거하며,
  멱등입니다. `--unshare=false`에서는 `s6-run`에 `SIGKILL`을 보내면 `s6-finish`가
  실행될 때까지 마운트가 남습니다. 서비스의 finish 스크립트에 넣으십시오.
- 서비스당 최대 1024개의 자격 증명과 16 MiB. Linux 전용이며, 다른 환경에서는
  명령이 `ErrUnsupported`를 보고합니다.

`--secret`과 `--machine-id-file`로 지정한 키 파일은 root 소유여야 하고 그룹이나
다른 사용자가 쓸 수 없어야 하며, `/`까지의 모든 상위 디렉터리도 마찬가지입니다.
키 파일은 마지막 링크를 따라가지 않고 한 번만 열리며, 키는 자격 증명 처리를
마치는 즉시 `s6-run`의 메모리에서 지워집니다. 서비스의 신원을 취하는 것은 자식
프로세스뿐이며, `s6-run`과 그 모든 스레드는 root로 남습니다.

### 케이퍼빌리티 유지: `--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

이 플래그는 반복할 수 있고 쉼표로 구분할 수 있으며(`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`
또는 하나씩 각각), **기본값이 없습니다**. 지정하지 않으면 서비스는 모든 케이퍼빌리티
집합이 비어 있는 상태로 실행됩니다.

이것은 케이퍼빌리티 7개로 이루어진 **허용 목록**이며, 어느 것도 root와 동등하지 않고
자격 증명 tmpfs를 읽거나 쓰거나 `s6-run`에 시그널을 보낼 수 없습니다:
`CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`, `CAP_NET_RAW`, `CAP_NET_BROADCAST`,
`CAP_IPC_LOCK`, `CAP_WAKE_ALARM`, `CAP_BLOCK_SUSPEND`. 그 밖의 케이퍼빌리티나
케이퍼빌리티가 아닌 이름은 허용 목록을 알려 주는 오류가 되며, 키를 읽거나 무엇이든
마운트하기 전에 보고됩니다.

서비스는 bounding, permitted, inheritable, effective, ambient 집합에 유지한
케이퍼빌리티만 정확히 가집니다. `no_new_privs`는 계속 켜져 있고, securebits는 0x3
(`SECBIT_NOROOT` 설정 및 잠금)입니다. `s6-run` 자체의 권한은 바뀌지 않습니다.

`CAP_NET_ADMIN`은 서비스가 실행되는 네트워크 네임스페이스에 작용합니다. 서비스를 자체
네트워크 네임스페이스에서 시작하지 않으면 그것은 호스트의 것입니다(`--unshare`는
비공개 마운트 네임스페이스만 제공합니다). 거기서는 인터페이스, 라우트, 방화벽을 바꿀 수
있습니다. 중요하다면 그런 서비스를 자체 네트워크 네임스페이스에서 실행하십시오.

## `sdcreds run`: OpenBSD와 Linux {#run}

```sh
sdcreds run --service=web --user=svc --source=/etc/creds [--class=daemon] -- /usr/local/bin/web
```

`run`은 `--source`의 봉인된 파일을 복호화하고, `--user` 소유의 읽기 전용 파일로
`$CREDENTIALS_DIRECTORY` 아래에서 프로그램에 보이게 하며, 그 사용자로 프로그램을 실행하고,
끝나면 파일을 지웁니다. Linux에서는 같은 플래그의 `s6-run`입니다. `--check`는 모든 거부를
실행하되 아무것도 복호화하지 않습니다(rc.d의 `rc_pre`에서 사용). 거부는 상태 2로 끝나며 호스트
키를 읽기 전에 일어납니다. OpenBSD에서는 서비스를 위해 마운트되는 메모리 파일 시스템(MFS)에
파일이 놓이고, 끝날 때 0으로 채워집니다.

- **마운트 네임스페이스가 없습니다.** 프로그램이 실행되는 동안 자격 증명은 그 디렉터리에 닿을 수
  있는 모든 프로세스에 보이며, root는 언제나 읽을 수 있습니다.
- **호스트 키**는 `/etc/sdcreds/host.key`이며 소유자는 root, 모드는 0600입니다. 다른 모드나 소유자는
  거부됩니다. `sdcreds setup --path /etc/sdcreds/host.key`로 만든 뒤 `chmod 600` 하십시오. 머신 ID는
  `sysctl hw.uuid`입니다. `--secret`과 `--machine-id-file`은 둘 다 대체하며, 같은 소유자·모드 검사를
  거칩니다.
- **`--user`는 절대 root가 아닙니다**: uid 0, gid 0, 보조 그룹 0은 `run`과 라이브러리(`s6.Run`,
  `delivery`) 모두에서 거부되며, 이를 허용하는 플래그는 없습니다. 프로그램은 사용자가 실행할 수 있는
  절대 경로이면서 정규화된 경로여야 합니다.
- **sdcreds를 죽이면 프로그램도 죽고** 언마운트됩니다. `SIGKILL`이라도 마찬가지입니다. 도우미
  프로세스가 서비스 잠금을 쥐고 sdcreds를 지켜보다가, 어떤 식으로 끝나든 서비스 사용자가 실행하는
  모든 것을 (실제 uid 기준으로, 따라서 `setsid`를 호출한 프로그램도 빠져나가지 못합니다) 죽이고 나서
  언마운트합니다. 죽일지는 root가 결정합니다. 도우미는 찾은 모든 프로세스를 멈추고, 프로세스 표가
  더 변하지 않을 때까지 다시 읽은 뒤 `SIGKILL`을 보내고, 사용자의 프로세스가 없어질 때까지 반복합니다.
  유효 uid만 서비스 사용자의 것인 프로세스는 "사용 중"으로 세어져 시작이 거부되지만 죽이지는 않습니다.
  20초의 예산을 넘겨 살아남는 프로세스가 있어도 도우미는 언마운트하고(비밀은 사라집니다), 실패를
  보고하고 0이 아닌 상태로 끝납니다. 사용자는 한 번에 하나의 전달에만 속하며(`/var/run/sdcreds`의
  `.uid-<N>.lock`), 이미 다른 프로세스가 있는 사용자는 `run`이 거부합니다. 서비스에 전용 사용자를
  주십시오. sdcreds와 도우미가 모두 죽으면 `sdcreds sweep [--base DIR] [--service S]`(또는 서비스의
  다음 시작)가 남은 것을 지웁니다. 프로그램이 끝난 뒤 해제에 실패하면 sdcreds는 상태 70(프로그램이
  이미 실패였다면 프로그램의 상태)으로 끝나며 이유를 stderr에 씁니다.
- **스왑은 암호화되어 있어야 합니다.** `sysctl vm.swapencrypt.enable`이 0이거나, 읽을 수 없거나,
  존재하지 않으면 `run`은 시작을 거부합니다. 이를 무시하는 플래그는 없습니다. 라이브러리에서
  `s6.Config`는 `ReadSource`(명령은 신뢰 경로를 검사하는 리더를 줍니다)가 필요하며, 없으면 `s6.Run`이
  거부합니다.
- **내장 파일 시스템 이미지는 고정되어 있습니다**: 각 `delivery/images/ffs-<N>MiB.gz`의 sha256이
  도우미가 압축을 풀기 전에 검사됩니다.
- **`--class`**는 먼저 `/etc/login.conf.d/<class>`에서, 다음으로 `/etc/login.conf`에서 찾으며
  `login.conf.db`는 참조하지 않습니다. 클래스의 자원 한도는 프로그램에 적용되며 원래 가질 값을 낮추기만
  합니다. 읽거나 구문 분석할 수 없는 클래스는 거부됩니다. 우선순위와 umask는 적용되지 않으며
  프로그램의 umask는 077입니다.
- **프로그램의 환경은 허용 목록입니다**: `PATH`(고정 기본값), `CREDENTIALS_DIRECTORY`, `LANG`, `TZ`,
  `TERM`, `LC_*`. 2보다 큰 디스크립터는 실행 전에 닫힙니다.
- **메모리.** 평문은 짧은 시간 동안 sdcreds 프로세스의 메모리에 있습니다. OpenBSD에서는 Go
  프로세스에서 `mlockall`을 쓸 수 없으므로(8.0에서 측정) 보호는 `vm.swapencrypt.enable`(시작 시
  검사), 코어 덤프 비활성화, `kern.nosuidcoredump`입니다. 관리자가 만든 크래시 덤프에는 여전히 평문이
  있을 수 있습니다.
- `--keep-cap`은 Linux 전용입니다.

저장소의 `docs/openbsd/authn_bridge`는 go-authn/bridge를 이 방식으로 실행하는 rc.d 스크립트입니다.
전달은 라이브러리(패키지 `delivery`)이기도 합니다.

## 상호 운용성 {#interop}

두 방향 모두 `v262.2` 태그에서 빌드한 실제 `systemd-creds` **262.2**(배포판
패키지 아님)를 대상으로 테스트합니다.

- `testdata/systemd-v262.2`에는 systemd-creds가 작성한 44개의 자격 증명(null,
  host, host-scoped. 이름 있음과 없음. not-after 없음, 과거, 미래. 0 B, 1 B,
  64 KiB 페이로드. 변조된 변형 다섯 개)이 들어 있고, `manifest.json`에는 272번의
  복호화 시도(올바른 이름과 틀린 이름, not-after 이전과 이후, `--uid` 유무) 각각에
  대해 systemd-creds 자신이 답한 내용이 기록되어 있습니다. 라이브러리는 모든
  경우에 같은 종류의 오류를 포함해 같은 답을 냅니다.
- IV를 고정하면 `Encrypt`는 systemd의 바이트를 그대로 재현합니다.
- 컨테이너에서 `systemd-creds decrypt`는 `Encrypt`가 쓴 것을 열며, 명령줄도 두
  방향 모두에서 같은 왕복 시험을 통과합니다.

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

`SDCREDS_REQUIRE_SYSTEMD=1`이 없으면 바이너리가 필요한 테스트는 건너뜁니다.
CI는 이를 설정하므로 바이너리가 없으면 그곳에서는 실패입니다. 1 MiB 경계는
라이브러리 테스트만 다루며, 상호 운용 벡터는 다루지 않습니다.

## systemd와의 차이점 {#deviations}

- 머신 ID가 일치하지 않는 호스트 시크릿은 **거부**됩니다(`ErrHostKeyMachine`).
  systemd는 이를 삭제합니다.
- `--with-key=auto`는 `host`를 뜻합니다. 여기에는 TPM2가 없습니다.
- null 키로 봉인된 자격 증명에는 기밀성이 없습니다. `sdcreds decrypt`는
  `--allow-null`을 지정하지 않으면 모든 머신에서 이를 거부합니다(systemd는 대신
  TPM2와 SecureBoot 상태를 확인합니다. 그 라이브러리 정책인 `SystemNullPolicy`는
  CLI에서 사용되지 않습니다).
- `SDCREDS_MACHINE_ID_FILE`(`encrypt`, `decrypt`, `setup`)은 다른 머신 ID 파일을
  가리킵니다. `s6-run`은 이것과 `SYSTEMD_CREDENTIAL_SECRET`을 무시하며, 키는 기본
  파일 또는 `--secret`과 `--machine-id-file`에서 가져옵니다.
- 가변 IV 크기는 systemd처럼 읽을 때 허용되며, 이 라이브러리는 항상 12바이트를
  기록합니다.
- 시크릿은 마지막 심볼릭 링크를 따라가지 않고 열리며, systemd가 요구하듯 링크가
  하나이고 모드가 `0400`인 일반 파일이어야 합니다.

## 안전성 {#safety}

모든 길이는 사용하기 전, 무엇이든 할당하기 전에, 그 경계의 양쪽에서 검사됩니다.
자격 증명은 1 MiB(systemd와 동일), 호스트 시크릿은 16 MiB로 제한됩니다. 파서는
코퍼스를 커밋한 상태로 CI에서 퍼징하며, `govulncheck`도 CI에서 실행됩니다.
README에는 아직 성능 표가 없습니다. 측정은 미뤄졌으며, 결과가 아니라 열려 있는
항목입니다.

## 참고 {#reference}

[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds)의 README가 이
페이지의 기준 자료입니다. 모듈의 `LICENSE`를 참조하십시오.
