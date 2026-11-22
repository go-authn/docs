---
title: "secretsource — 참조에서 비밀 가져오기"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource는 PIN, 비밀번호, 복구 코드를 참조(파일, macOS 키체인, Secret Service, KeePassXC)에서 가져와 평문 파일이 디스크에 남지 않게 합니다."
tags: [라이브러리, secretsource, 비밀]
---

**파일에 남겨 두면 안 되는 PIN은 어디에서 가져오는가?** **참조**는 비밀이 있는
곳을 가리키고, `secretsource.Open`이 그것을 가져옵니다. 참조에는 비밀이 들어
있지 않으므로 플래그, 스크립트, 셸 기록에 있어도 됩니다.

```sh
go get github.com/go-authn/secretsource@v0.8.1
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 참조 | 읽는 대상 |
|---|---|
| `file:PATH` | 소유자만 읽을 수 있는 일반 파일(Unix: 모드 0600 이하; Windows, v0.7.0부터: 소유자, SYSTEM, Administrators 그룹 외에는 누구에게도 읽기나 쓰기 권한을 주지 않는 액세스 목록); 끝의 줄바꿈 하나는 제거됩니다; 비어 있거나 줄 끝만 든 파일은 `ErrEmpty`로 거부되며(v0.6.0부터), FIFO는 일반 파일이 아니라며 거부됩니다 |
| `keychain:SERVICE/ACCOUNT` | macOS 키체인의 일반 암호 항목 |
| `secretservice:SERVICE/ACCOUNT` | 속성 `service=SERVICE`, `account=ACCOUNT`를 가진 freedesktop Secret Service 항목 (GNOME Keyring, KWallet, KeePassXC의 Secret Service 연동) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | 그 속성을 모두 가진 단 하나의 Secret Service 항목; 여러 개가 일치하면 거부됩니다 |
| `keepassxc:URL` | **URL 필드**가 그 URL인 KeePassXC 항목(`https://NAME.invalid/...`는 결코 해석되지 않는 좋은 선택); 같은 URL의 항목이 둘이면 모호하다고 거부됩니다 |
| `systemd-creds:NAME` | (Linux, v0.8.0부터) systemd 자격 증명을 바이트 그대로 반환합니다. `file:`과 달리 끝의 줄바꿈을 제거하지 않습니다. 먼저 `$CREDENTIALS_DIRECTORY`의 `NAME` 파일(`LoadCredential=`, `LoadCredentialEncrypted=`, `SetCredentialEncrypted=`가 배치), 없으면 `/etc`, `/run`, `/usr/lib`의 `credstore.encrypted`에 있는 `NAME` 또는 `NAME.cred`를 `systemd-creds decrypt`로 복호화합니다. 다른 시스템에서는 `ErrUnavailable`로 거부됩니다 |

`keepassxc:by-uuid/...`와 `keepassxc:by-path/...`는 **거부됩니다**: KeePassXC
2.8.0은 조회가 URL이 없는 항목을 찾으면 비정상 종료합니다.

**명령을 실행하는 스킴은 없습니다**: 플래그가 프로세스를 시작할 수 있어서는 안
되기 때문입니다. 스킴이 없는 참조는 경로로 추측되지 않고 거부됩니다(경로는
`file:`로 씁니다). 4096바이트보다 긴 비밀이나 관리자나 `file:`이 돌려준 빈 비밀은
거부되며(`ErrEmpty`), 호출은 컨텍스트(기한이 없으면 2분)와 함께 끝납니다. 관리자가 잠금
해제를 기다리고 있어도 마찬가지입니다.

## systemd 자격 증명 {#systemd-creds}

문법은 정확히 `systemd-creds:NAME`입니다. 소문자 스킴, 콜론, 그리고
`LoadCredential=`, `LoadCredentialEncrypted=`, `systemd-creds encrypt --name=`에
준 자격 증명 이름이 옵니다. 예: `systemd-creds:smtp`. `NAME`은 1~255바이트의
단순한 파일 이름이며, `/`가 없고(경로가 아님), `.`나 `..`가 아니며, 제어 문자가
없고, `.cred` 접미사도 붙이지 않습니다(접미사는 파일의 것이며, `smtp`는 `smtp`
또는 `smtp.cred`를 찾습니다).

- `$CREDENTIALS_DIRECTORY`의 파일은 `O_NOFOLLOW`로 열리며, root 또는 호출자가
  소유하고 "기타" 사용자에게 접근 권한이 없는 일반 파일이어야 합니다(그룹 비트는
  허용됩니다. systemd는 `User=` 서비스에 ACL이 있는 root 소유 0440 파일을
  줍니다). 디렉터리도 마찬가지입니다. 심볼릭 링크나 너무 느슨한 모드는
  거부됩니다.
- 그렇지 않으면 `systemd-creds decrypt --name=NAME PATH -`를 직접 실행합니다.
  셸 없이, 빈 환경으로, 비밀은 표준 출력에서만 읽고, 최대 4096바이트이며,
  컨텍스트로 끝납니다. root가 아닌 호출자는 먼저 `--user`(systemd 256 이상)를
  시도합니다.
- 다듬기 없음: 끝의 줄바꿈, NUL 바이트, UTF-8이 아닌 바이트가 그대로
  유지되므로 비밀번호는 `printf %s`로 봉인하십시오.
- systemd 257(Debian 13)에서 `--with-key=host`로 측정했으며, TPM2 키로는 측정하지
  않았습니다. 복호화에 실패하면 `ErrUnavailable`을 반환하고 자격 증명을 다시
  봉인해야 할 수 있다고 알려 줍니다.
- PCR 바인딩: `--tpm2-pcrs=`의 기본값은 없음입니다. `--tpm2-pcrs=7`만 쓰면
  펌웨어나 shim 업데이트, vTPM 마이그레이션 후 모든 자격 증명이 잠길 수
  있습니다. `--with-key=host+tpm2`, 서명된 PCR 정책(`--tpm2-public-key`, PCR 11)
  또는 `systemd-pcrlock`을 쓰고, 다시 봉인할 수 있도록 비밀의 사본을 보관하십시오.

## KeePassXC {#keepassxc}

KeePassXC는 브라우저 통합 프로토콜로 연결합니다(macOS와 Linux; Windows는 아직
구현되지 않았습니다). v0.6.0부터 Unix에서는 소켓이 심볼릭 링크이거나 그 디렉터리가 다른
사용자 소유이거나 그룹이나 다른 사용자가 쓸 수 있으면 소켓을 거부하고, 다이얼 뒤에 연결된
피어의 uid를 확인하며, 레거시 `$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer`
심볼릭 링크는 더 이상 따라가지 않습니다(`app/org.keepassxc.KeePassXC/` 아래의 실제 소켓은
따라갑니다).

v0.6.1부터 연결 파일(macOS 키체인도 Secret Service도 없을 때 쓰는 대체 저장소)은 같은
디렉터리의 새 임시 파일에 쓴 뒤 최종 이름으로 이름을 바꾸므로, 그 이름에 남아 있던
심볼릭 링크는 따라가지 않고 교체되며, 더 느슨한 모드의 파일은 0600이 됩니다. Unix에서는
소켓의 디렉터리처럼 디렉터리를 먼저 검사합니다. 이 사용자 소유여야 하고, 그룹이나 다른
사용자가 쓸 수 없어야 하며, 심볼릭 링크가 아니어야 합니다. 그렇지 않으면 아무것도 쓰지
않습니다.

v0.8.1부터 그 쓰기는 [`harden/privfile`]({{< relref "/libraries/harden.md#privfile" >}})
v0.2.0이 합니다. Windows에서는 이제 파일이 go-authn/kinit v0.3.2처럼 소유자 전용
보호된 접근 목록을 받으며, 디렉터리는 쓰기 전은 물론 쓰는 순간에도 다시 검사됩니다.

1. KeePassXC에서 *Settings > Browser Integration*을 켭니다.
2. 데이터베이스마다 한 번 이 컴퓨터를 연결하고 KeePassXC에서 승인합니다:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. 항목을 만들고 **URL 필드**에 `https://fido.invalid/yubikey-5c`를 채웁니다
   (다른 항목이 쓰지 않는 아무 URL; 참조가 곧 그 URL입니다). 비밀을 출력하지
   않고 참조를 확인합니다:
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

항목을 처음 읽을 때 KeePassXC의 접근 대화 상자가 나타납니다.

`fido --pin-from`([fido]({{< relref "/libraries/fido.md" >}}) 참고)과
`theca --pin-from`, `--password-from`, `--recovery-from`이 사용합니다.

## 비밀 저장하기: `secretsource store` {#store}

항목을 손으로 만들 필요가 없습니다. `secretsource store REF [--group G]
[--login L] [--replace] [--generate N]`은 `keychain:`,
`secretservice:SERVICE/ACCOUNT`, `secretservice:KEY=VALUE`, `keepassxc:URL`에
비밀을 기록합니다:

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

비밀은 에코 없이 두 번 입력하거나, 표준 입력이 터미널이 아니면 거기서 읽습니다.
인자나 환경 변수에서는 절대 가져오지 않습니다. `--generate N`은 N개의 영문자와
숫자를 만들고 비밀 내용은 아무것도 출력하지 않습니다. 이미 있는 항목은
`--replace`가 없으면 거부됩니다(KeePassXC에서는 URL로 찾은 그 항목을 갱신합니다).
`file:`은 거부됩니다.

`keepassxc:`에서는 브라우저 프로토콜의 `set-login`을 쓰므로 항목은 항상 다시 찾을
수 있는 URL을 가지며, 중복은 URL로 찾습니다. 로그인 기본값은 URL의 호스트
(`--login`)이고, 그룹은 `--group`이 루트 아래 이름을 지정하지 않는 한
`KeePassXC-Browser Passwords`이며, `--title`은 KeePassXC 2.8.0이 무시하므로
거부됩니다. KeePassXC는 자체 대화 상자를 표시합니다.

## 참조 문서 {#reference}

이 페이지의 기준은
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource)의
README입니다.
