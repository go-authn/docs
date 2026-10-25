---
title: "다운로드 검증하기"
linkTitle: "다운로드 검증하기"
weight: 10
description: "각 릴리스가 게시하는 것, 그리고 릴리스 워크플로가 빌드한 바이너리를 다른 것과 구별하는 세 가지 검사."
tags: [보안, 릴리스]
---

authnd, authn-bridge, authn-revokd, sshcert의 각 릴리스는 정적 바이너리 여섯 개
(`CGO_ENABLED=0`: amd64와 arm64의 linux, darwin, windows), `SHA256SUMS` 파일, 그리고
모든 바이너리에 대한 빌드 출처 증명(attestation)을 게시합니다. 아래 예제는
authn-bridge v0.23.1을 사용하며, 다른 프로그램도 각자의 저장소와 이름으로 같은
방식으로 동작합니다.

```sh
gh release download v0.23.1 --repo go-authn/bridge
```

## 1. 체크섬 {#1-the-checksum}

```sh
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```
authn-bridge-darwin-amd64: OK
authn-bridge-darwin-arm64: OK
authn-bridge-linux-amd64: OK
authn-bridge-linux-arm64: OK
authn-bridge-windows-amd64.exe: OK
authn-bridge-windows-arm64.exe: OK
```

이는 파일이 릴리스가 나열한 것과 같다는 것만 증명하며, 그 이상은 아닙니다. 릴리스
페이지에서 바이너리를 바꿀 수 있는 사람은 그 옆의 `SHA256SUMS`도 바꿀 수 있습니다.

## 2. 출처 증명 {#2-the-provenance}

```sh
gh attestation verify authn-bridge-linux-amd64 --repo go-authn/bridge
echo $?
```

증명은 파일을 빌드한 워크플로 실행에 대해 GitHub이 서명하므로, 누군가 가진 키가
아니라 저장소와 워크플로를 지정합니다.

{{< callout type="warning" >}}
**출력이 아니라 종료 상태를 읽으십시오.** 터미널이 없으면 일부 버전의 `gh`는
검증에 성공했을 때 아무것도 출력하지 않습니다. authnd에서 gh 2.65.0으로 측정한
결과, 정품 바이너리는 종료 상태 0과 빈 출력을 냈습니다. 한 바이트를 덧붙인
바이너리는 종료 상태 1과
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`를
냈는데, 그 다이제스트에 대한 증명이 존재하지 않기 때문입니다. 침묵은 실패가
아니며, 0이 아닌 상태가 실패입니다.
{{< /callout >}}

## 3. 바이너리가 스스로 말하는 것 {#3-what-the-binary-says-about-itself}

```sh
go version -m authn-bridge-linux-amd64
```

```
	path	github.com/go-authn/bridge/cmd/authn-bridge
	mod	github.com/go-authn/bridge	v0.23.1	
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=9a51e5e9839f879d44c09b8b4e71f823e72ee0aa
	build	vcs.modified=false
```

(중요한 줄만 남겨 줄였습니다.) `mod` 줄은 태그와 정확히 같아야 하고
`vcs.modified`는 `false`여야 합니다. 커밋되지 않은 변경이 있는 트리에서 빌드하면
`true`라고 나오고 버전은 `v0.23.1+dirty`로 표시됩니다. 릴리스 워크플로는 여섯
바이너리 **모두**가 두 검사를 통과하지 않으면, 그리고 프로그램이 버전 줄의 마지막
단어로 태그를 출력하지 않으면 게시를 거부합니다.

```
$ authnd --version
authnd version v0.11.1
$ authn-bridge --version
authn-bridge version v0.23.1
$ authn-revokd -version
authn-revokd v0.6.4
```

authnd와 authn-bridge는 `--version`을 받고, authn-revokd는 Go의 표준 플래그
문법인 `-version`을 받습니다. v0.6.1부터는 다른 둘처럼 표준 출력에 출력하므로
`v=$(authn-revokd -version)`으로 가져올 수 있습니다.

## 바이너리가 있는 릴리스 {#which-releases-have-binaries}

바이너리, 합계, 증명은 authnd v0.9.2, authn-bridge v0.19.3, authn-revokd v0.5.0,
sshcert v0.1.2부터 게시됩니다. 각각의 첫 릴리스는 체크아웃 안에서 바이너리를
빌드하여 `+dirty`로 보고했으며, 이는 다음 릴리스에서 고쳐졌고 바이너리별 검사는 그
뒤에 추가되었습니다. 그보다 이전 태그는 소스만 있습니다. `go install …@<tag>`로
빌드하십시오. 그러면 `go version -m`이 읽는 빌드 정보에 태그가 기록됩니다.
프로그램이 출력하는 것이 항상 그것은 아닙니다. sshcert-authorize는 v0.1.5까지
`go install` 빌드에서 `dev`를 출력했고, revokd는 v0.5.0 이전에는 `-version`이
없습니다.
