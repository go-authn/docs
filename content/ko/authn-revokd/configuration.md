---
title: "구성"
linkTitle: "구성"
weight: 20
description: "authn-revokd의 revokd.hcl: 목록이 어디서 오는지, 무엇으로 서명되어야 하는지, 어떤 파일에 기록되는지, 그리고 미러."
tags: [authn-revokd, 구성]
---

기본값은 `/etc/authn-revokd/revokd.hcl` 파일 하나입니다(`-config`로 다른 파일을
지정). 시작할 때 한 번 읽습니다.

```hcl
state_dir = "/var/lib/authn-revokd/state"   # the verified copies: what orders the next list
refresh   = "1m"

source "univ-a-ssh" {
  url    = "https://login.univ-a.example/ssh/krl"    # and .../ssh/krl.sig beside it
  ssh_ca = "/etc/authn-revokd/ca/univ-a-ssh.pub"     # what the list must be signed by
}
source "univ-b-ssh" {
  url    = "http://mirror.cluster.local:8080/univ-b-ssh"   # a mirror: plain http is fine
  ssh_ca = "/etc/authn-revokd/ca/univ-b-ssh.pub"
}
source "univ-a-x509" {
  url     = "https://login.univ-a.example/x509/crl"
  x509_ca = "/etc/authn-revokd/ca/univ-a-x509.pem"
}

output "sshd" {                              # sshd_config: RevokedKeys /var/lib/authn-revokd/sshd.krl
  path    = "/var/lib/authn-revokd/sshd.krl"
  sources = ["univ-a-ssh", "univ-b-ssh"]     # merged into one file
}
output "tls" {                               # nginx: ssl_crl /var/lib/authn-revokd/univ-a.crl
  path    = "/var/lib/authn-revokd/univ-a.crl"
  sources = ["univ-a-x509"]
  format  = "pem"
}

# listen = "127.0.0.1:8080"                  # serve the verified lists: a mirror
```

## 키 {#the-keys}

| 키 | 기본값 | |
|---|---|---|
| `state_dir` | | 필수, 절대 경로. 없으면 `0700`으로 생성 |
| `refresh` | `1m` | 모든 소스를 가져오는 주기, 1초 이상. 각 대기는 위아래로 10분의 1씩 달라져서 서버 군이 같은 박자로 움직이지 않음 |
| `listen` | | `host:port`: 검증된 목록을 제공, 즉 미러. `-once`에서는 무시됨 |

**`source "<name>"`**: 목록 하나. 이름은 문자, 숫자, `.`, `_`, `-`이며 점으로 시작하지
않고 최대 64자입니다. 상태 디렉터리의 파일 이름이자 미러의 경로가 됩니다.

| 키 | |
|---|---|
| `url` | `https://`, `http://` 또는 `file://`. KRL의 서명은 같은 URL에 `.sig`를 붙여 가져옴 |
| `ssh_ca` | SSH CA의 공개 키, `authorized_keys` 한 줄: KRL 소스. 인증서는 여기서 거부됨 |
| `x509_ca` | CA의 PEM 인증서: CRL 소스 |
| `max_age` | 자체 만료에 더해, 이보다 오래 전에 발급된 목록도 거부. CRL 출력에 공급하는 소스에서는 거부됨 |
| `revoke_keys` | 다른 소스와 공유하는 출력에서 이 소스의 목록이 **일반 키**를 폐기하도록 허용. KRL 소스에만 |

**`output "<name>"`**: 서버가 읽는 파일 하나.

| 키 | |
|---|---|
| `path` | 절대 경로. 그 옆에 기록한 뒤 이름을 바꿔 덮어씀 |
| `sources` | 하나의 파일로 병합되는 KRL 소스들, 또는 정확히 하나의 CRL 소스 |
| `format` | `der`(기본값) 또는 `pem`. CRL 출력에만 |
| `on_change` | 파일이 바뀐 뒤, 그리고 성공할 때까지 매 동기화마다 실행하는 명령과 인수 |

## 여러 CA를 위한 하나의 KRL {#one-krl-for-several-cas}

OpenSSH 10.3 이전에는 `RevokedKeys`가 파일 하나만 받으므로 출력의 KRL 소스들은
병합되며, **각 목록은 자신의 CA에는 온전한 효과를 유지하고 다른 CA에는 아무 효과도
없습니다.**

- **유지:** 일련번호와 키 ID, CA를 지정하지 않는 섹션(자신의 CA로 한정됨), 그리고 그
  CA의 모든 인증서를 폐기하는 자신의 CA 키.
- **제외하고 기록:** 다른 CA의 섹션, 그리고 다른 CA의 키.
- **일반 사용자 키**는 출력에 소스가 둘 이상이면, 소스에 `revoke_keys = true`가 있지
  않는 한 제외됩니다. KRL은 키를 하나의 CA로 한정할 수 없습니다. sshd는 누가
  서명했든 인증서 자신의 키를 파일과 대조하므로, 한 CA가 지명한 키는 파일의 모든 CA
  아래에서 그 소유자를 막아 버립니다. 소스가 하나인 출력은 이를 유지합니다.

각 목록은 먼저 단독으로 병합됩니다. 병합할 수 없는 목록은 **자신의 CA에 한해서만**
실패 시 차단되며, 병합된 파일은 현재 입력 중 가장 먼저 만료되는 것과 함께 만료되므로
만료를 확인하는 읽는 쪽은 authn-revokd가 멈춘 것을 알게 됩니다.

## 한 번의 동기화가 하는 일 {#sync}

v0.6.7부터, 동기화가 만나는 순서대로:

- **소스는 함께 가져옵니다**. 동시에 최대 16개, 각각 2분 안에(한 번 가져올 때 요청은 최대 네 개). 응답하지 않는
  업스트림 하나가 다른 모든 소스와 그 출력을 더 이상 지연시키지 않습니다.
- **각 출력 파일은 동기화할 때마다 디스크와 비교되고**, 다르면 다시 쓰이며 `on_change`가 실행됩니다. 에이전트가
  모르는 사이에 삭제되거나 잘리거나 교체된 파일은 목록이 다음에 바뀔 때까지 그대로였고, sshd는 `RevokedKeys`를
  읽을 수 없으면 모든 로그인을 거부합니다.
- **`on_change`는 1분 뒤에 종료되며**, 그 출력을 붙잡고 있는 자식 프로세스도 함께 종료되고, 다른 실패와 마찬가지로
  다음 동기화에서 다시 실행됩니다. 에이전트의 잠금을 쥔 채 실행되지 않으므로 `/healthz`와 다음 동기화가 함께
  멈추지 않습니다.
- **만료되는 목록은 만료되는 때 거부됩니다**. 다음 새로 고침까지 기다리지 않습니다. 에이전트는 현재 목록의 첫
  만료(또는 `max_age`)에 깨어나 그때 실패-폐쇄합니다. `refresh = "1h"`에서는 발급자가 멈춘 뒤 최대 한 시간
  동안 마지막 KRL이 디스크에 남아 sshd에는 유효한 것으로 보였습니다.
- **`file://` 소스는 일반 파일이어야 합니다.** FIFO를 가리키는 소스는 에이전트를 `open(2)`에서 영원히 막았습니다.
- **오류 속의 URL은 비밀번호, 쿼리, 프래그먼트 없이 표시됩니다**. 쿼리의 토큰이 로그에도, 미러의 인증 없는
  `/healthz`에도 나타나지 않게 하기 위해서입니다.
- **`0..2^159` 범위를 벗어난 CRL 번호는 거부됩니다**. RFC 5280 5.2.3은 `CRLNumber ::= INTEGER (0..MAX)`를 최대 20
  옥텟으로 정의합니다. `-1`은 퍼저가 찾아낼 때까지 받아들여졌습니다.
- **임시 파일**은 만들기와 이름 바꾸기 사이에 종료된 쓰기의 잔여물이 시작할 때 제거됩니다.

보유한 목록과 동일한 바이트는 다시 검증하거나 파싱하지 않습니다(유효 기간 판정은 계속합니다). 그래서 `ETag`를 보내지
않는 소스를 조회하는 비용이 낮습니다. 100,000개 항목의 CRL(2.1 MB)은 v0.6.6에서 조회 한 번에 할당 300,138회와
96,956,946바이트가 들었고, v0.6.7에서는 할당 37회와 4,776,864바이트가 듭니다(`BenchmarkFetchUnchangedCRL`, 할당은
정확). 시간은 측정하지 않았습니다. 머신 부하가 53에서 65였습니다.

## 미러 {#the-mirror}

`listen`이 있으면 authn-revokd는 자신이 보유한 것을 메모리에서 제공하며, 쓰기가 한창
진행 중일 수 있는 파일에서는 절대 제공하지 않습니다.

| | |
|---|---|
| `GET /<source>` | `ETag`와 함께 목록. `If-None-Match`는 `304`로 응답 |
| `GET /<source>.sig` | KRL의 서명. 다른 ETag에 대한 `If-Match`는 `412`로 응답 |
| `GET /healthz` | `200 ok`, 또는 현재 목록이 없는 각 소스와 실패한 각 출력을 지정하는 `503` |

```
$ curl -s http://127.0.0.1:28474/healthz
ok
$ curl -s -D - -o /dev/null http://127.0.0.1:28474/bridge-ssh
HTTP/1.1 200 OK
Cache-Control: max-age=30
Content-Type: application/octet-stream
Etag: "dfd84d8513eb48d07ed72f2110316858"
Date: Mon, 26 Oct 2026 11:27:10 GMT
Content-Length: 130

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-Match: "stale"' http://127.0.0.1:28474/bridge-ssh.sig
412
```

CRL 소스에는 `.sig`가 없습니다(`404`). 미러는 연쇄할 수 있습니다. 모든 목록이 스스로
검증되므로 미러의 소스가 다른 미러일 수 있습니다. 느린 업스트림이 미러의 응답을
막는 일은 없습니다.

v0.6.7부터 미러 자체의 연결에는 기한이 있습니다. 요청 헤더를 읽는 데 10초, 요청 전체에 30초, 응답을 쓰는 데 2분,
유휴 상태로 1분입니다. 이전에는 목록을 요청하고 읽지 않는 클라이언트가 연결을 영원히 붙잡을 수 있었습니다.

## 시작할 때 거부되는 것 {#what-is-refused-at-start}

다음은 각각 아무것도 가져오기 전에 `2`로 종료합니다.

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

없는 구성도 마찬가지입니다.

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

v0.6.2 이전에는 HCL 파서의 메시지였습니다.
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

CRL 출력도 소스 하나만 받으며(TLS 서버는 발급자당 CRL 하나를 읽습니다), `max_age`가
있는 CRL 소스는 아무것도 이를 강제할 수 없으므로 거부됩니다.

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

CRL을 로드한 TLS 서버는 authn-revokd가 무엇을 기록하든 `nextUpdate`까지 그것을
메모리에 유지합니다.

**상태 디렉터리**는 sshd의 StrictModes 규칙을 따릅니다. 그 안의 파일을 바꾸거나
제거할 수 있는 사람이 다음 목록을 결정하며, 비워진 상태는 재생된 오래된 목록이
들어오게 합니다. 그래서 심볼릭 링크이거나, 그룹이나 다른 사용자가 쓸 수 있거나,
authn-revokd의 사용자나 root가 아닌 사람이 소유하면 안 됩니다. 이들은 `1`로
종료합니다.

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
