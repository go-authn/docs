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
go get github.com/go-authn/secretsource@v0.5.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| 참조 | 읽는 대상 |
|---|---|
| `file:PATH` | 소유자만 읽을 수 있는 일반 파일(모드 0600 이하); 끝의 줄바꿈 하나는 제거됩니다 |
| `keychain:SERVICE/ACCOUNT` | macOS 키체인의 일반 암호 항목 |
| `secretservice:SERVICE/ACCOUNT` | 속성 `service=SERVICE`, `account=ACCOUNT`를 가진 freedesktop Secret Service 항목 (GNOME Keyring, KWallet, KeePassXC의 Secret Service 연동) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | 그 속성을 모두 가진 단 하나의 Secret Service 항목; 여러 개가 일치하면 거부됩니다 |
| `keepassxc:URL` | **URL 필드**가 그 URL인 KeePassXC 항목(`https://NAME.invalid/...`는 결코 해석되지 않는 좋은 선택); 같은 URL의 항목이 둘이면 모호하다고 거부됩니다 |

`keepassxc:by-uuid/...`와 `keepassxc:by-path/...`는 **거부됩니다**: KeePassXC
2.8.0은 조회가 URL이 없는 항목을 찾으면 비정상 종료합니다.

**명령을 실행하는 스킴은 없습니다**: 플래그가 프로세스를 시작할 수 있어서는 안
되기 때문입니다. 스킴이 없는 참조는 경로로 추측되지 않고 거부됩니다(경로는
`file:`로 씁니다). 4096바이트보다 긴 비밀이나 관리자가 돌려준 빈 비밀은
거부되며, 호출은 컨텍스트(기한이 없으면 2분)와 함께 끝납니다. 관리자가 잠금
해제를 기다리고 있어도 마찬가지입니다.

## KeePassXC {#keepassxc}

KeePassXC는 브라우저 통합 프로토콜로 연결합니다(macOS와 Linux; Windows는 아직
구현되지 않았습니다).

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
