---
title: "harden — 공유하는 보안 기본 요소 두 가지"
linkTitle: "harden"
weight: 36
description: "go-authn/harden은 go-authn 저장소들이 각자 복사해 두었던 보안 기본 요소, 즉 https나 루프백 리디렉션 규칙, 원자적으로 쓰는 개인 파일, 코어 덤프 방어를 갖춘 메모리 잠금을 담고 있습니다."
tags: [라이브러리, harden, 보안]
---

**go-authn 저장소마다 복사해 두었던 것은 무엇인가?** 작은 규칙 두 가지이며, 이제
표준 라이브러리 외에는 의존성이 없는 하나의 모듈에 있습니다.

```sh
go get github.com/go-authn/harden@v0.3.0
```

## `redirect` {#redirect}

토큰, 키 집합, 서명된 어서션이 링크를 건너기 전에 적용하는 규칙입니다. **URL은 https이거나,
이 컴퓨터를 가리켜야 합니다.**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| 함수 | |
|---|---|
| `CheckRedirect(req, via) error` | `http.Client` 정책입니다. 리디렉션 10회 뒤에 멈추고, https도 루프백도 아닌 대상은 거부합니다(다른 호스트로 https에서 http로 가는 경우가 이 함수가 존재하는 이유입니다). 자신의 정책은 이것 뒤에 이어 붙이세요 |
| `HTTPSOrLoopback(rawURL) error` | `https://host.example/...`이거나 루프백 호스트의 `http://`이면 nil입니다. 호스트가 없는 URL, 다른 스킴, 평문은 거부합니다. 오류는 URL 전체가 아니라 스킴과 호스트를 알려 줍니다 |
| `Loopback(host) bool` | `host`는 `url.URL.Hostname()`이 돌려주는 그대로입니다 |

`Loopback`은 루프백인 IP 리터럴(127.0.0.0/8, `::1`, IPv4 매핑된 `::ffff:127.0.0.1`)과
`localhost` 또는 `.localhost` 아래의 모든 이름(RFC 6761 6.3절)을, 대소문자와 끝의 점
유무에 관계없이 받아들입니다. 접두사로는 절대 일치하지 않으므로 `127.evil.example`은
거부되며, `0x7f.1`, `127.1`, `2130706433`, IPv6 존, 대괄호가 붙은 `[::1]`도 마찬가지입니다
(대괄호는 URL 문법이며 호스트의 일부가 아닙니다).

`Loopback`과 `HTTPSOrLoopback`은 RFC를 다시 읽어 구현한 것과 대조해 퍼징되며, 코퍼스는
커밋되어 있습니다.

[oidc]({{< relref "/libraries/oidc.md" >}})(v0.8.1),
[saml]({{< relref "/libraries/saml.md" >}})(v0.7.3),
[wireguard]({{< relref "/libraries/wireguard.md" >}}), rp(v0.5.1), awscred(v0.3.1)가
이것을 적용합니다.

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write`는 데이터를 모드 0600으로 `path`에 둡니다. 같은 디렉터리의 임시 파일에 쓰고,
`fsync`한 뒤, `rename`합니다. 따라서:

- 읽는 쪽은 옛 파일이나 새 파일을 보며, 절반만 쓰인 파일은 결코 보지 않습니다.
- `path`에 남아 있던 심볼릭 링크는 **따라가지 않고 교체되며**(가리키던 것은 그대로입니다),
  더 느슨한 모드의 파일은 그 모드를 유지하지 않습니다.
- Unix에서는 심볼릭 링크이거나, 다른 사람 소유이거나, 그룹이나 다른 사용자가 쓸 수 있는
  디렉터리는 아무것도 쓰기 전에 거부됩니다.

디렉터리는 만들지 않습니다. Windows에는 읽을 모드가 없습니다. v0.2.0부터 파일은 항목이
하나, 즉 현재 계정뿐인 보호된 접근 목록으로 만들어지며(kinit v0.3.2의 목록), 이는
`CreateFile`이 지정하므로 폴더의 항목을 상속하는 일이 없습니다. 모듈은
`golang.org/x/sys`를 요구하며, Windows 빌드만 사용합니다.

kinit의 `--cred-file`(v0.3.3), wireguard의 `FloorFile`(v0.2.1), `authn-revokd`의 상태
파일(revocation v0.7.2), [secretsource]({{< relref "/libraries/secretsource.md" >}})의
KeePassXC 연결 파일(v0.8.1)을 쓰는 것이 이것입니다.

## 하한 {#floors}

go-authn/wireguard와 go-authn/revocation은 둘 다 재시작해도 순서 하한을 유지하지만,
하한을 공유하지는 않습니다. wireguard는 버전과 발행 시각만 자기 작은 파일에 두고,
revocation은 서명된 목록 전체를 두었다가 그것을 검증해 하한을 다시 계산합니다. 공통인
것은 파일 쓰기뿐이며, 그것이 `privfile`입니다.

## `memlock` {#memlock}

v0.3.0부터 (theca에서 옮겨 옴): 키 자료를 스왑, 코어 파일, 디버거로부터 지킵니다.

```go
import "github.com/go-authn/harden/memlock"

region, err := memlock.Lock(unsafe.Pointer(&key[0]), uintptr(len(key)))
if err != nil { ... } // 거부됨: 알리거나 중단
defer region.Release()
```

| 함수 | |
|---|---|
| `Lock(p, n) (*Region, error)` | 범위의 페이지를 `mlock`(Linux, macOS, BSD 계열) 또는 `VirtualLock`(Windows)으로 잠급니다. **거부는 오류입니다**. 잠긴 채로 남는 것은 없고, 결정은 호출자가 합니다. 두 영역이 공유하는 페이지는 둘 다 해제될 때까지 잠겨 있습니다 |
| `(*Locker).LockBestEffort(p, n, report)` | 같지만, 거부될 때마다 `report`에 넘기고 나머지는 어쨌든 잠급니다. 이름 그대로, 잠금 없이 실행해도 괜찮은 곳에서만 쓰십시오 |
| `(*Region).Release()` | 잠금을 풉니다. nil이어도, 두 번 호출해도 안전합니다 |
| `DisableDumps() error` | `RLIMIT_CORE`를 0으로, Linux에서는 `PR_SET_DUMPABLE`도 0으로 합니다. macOS에서만 `PT_DENY_ATTACH`도 호출합니다 |

그 밖의 플랫폼은 `*UnsupportedError`(`errors.ErrUnsupported`와 일치)를 받으며,
조용히 성공하는 일은 없습니다.

**보장하는 것**: 범위의 페이지가 `Lock`부터 `Release`까지 메모리에 잠겨 있거나,
그렇지 않으면 오류를 받는다는 것. **보장하지 않는 것**: 복사본이 없다는 것. Go의
가비지 컬렉터는 힙 객체를 잠그기 전에 복사할 수 있으므로, 움직이지 않는 메모리를
잠그고 비밀은 한 곳에만 두십시오. 시스템 한도는 여전히 적용됩니다(`RLIMIT_MEMLOCK`,
Windows에서는 워킹 셋 크기). Windows에는 `PR_SET_DUMPABLE`이나 `PT_DENY_ATTACH`에
해당하는 것이 없어, 같은 사용자의 디버거나 관리자는 프로세스를 읽을 수 있습니다.

## 참고 {#reference}

이 페이지의 근거 자료는 [github.com/go-authn/harden](https://github.com/go-authn/harden)의
README입니다. BSD 3-Clause.
