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

이 페이지가 설명하는 버전은 v0.1.0입니다.

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
