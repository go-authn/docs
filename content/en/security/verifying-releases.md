---
title: "Verifying a download"
linkTitle: "Verifying a download"
weight: 10
description: "What each release publishes, and the three checks that tell a binary built by the release workflow from anything else."
tags: [security, releases]
---

Each release of authnd, authn-bridge, authn-revokd and sshcert publishes six
static binaries (`CGO_ENABLED=0`: linux, darwin and windows, on amd64 and
arm64), a `SHA256SUMS` file, and a build-provenance attestation for every
binary. The examples below use authn-bridge v0.20.1; the other programs work
the same way with their own repository and name.

```sh
gh release download v0.20.1 --repo go-authn/bridge
```

## 1. The checksum

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

This proves the file is the one the release lists, and nothing more: whoever
could replace a binary on the release page could replace `SHA256SUMS` beside
it.

## 2. The provenance

```sh
gh attestation verify authn-bridge-linux-amd64 --repo go-authn/bridge
echo $?
```

The attestation is signed by GitHub for the workflow run that built the file,
so it names the repository and the workflow, not a key somebody holds.

{{< callout type="warning" >}}
**Read the exit status, not the output.** Without a terminal, some versions of
`gh` print nothing at all when the verification succeeds: measured with gh
2.65.0 on authnd, a genuine binary gave exit status 0 and an empty output. A binary with
one byte appended gave exit status 1 and
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`,
because no attestation exists for its digest. Silence is not the failure; a
non-zero status is.
{{< /callout >}}

## 3. What the binary says about itself

```sh
go version -m authn-bridge-linux-amd64
```

```
	path	github.com/go-authn/bridge/cmd/authn-bridge
	mod	github.com/go-authn/bridge	v0.20.1	
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=d30d3b52b644c7db74c431c2a07b8d1aaeb1c0ff
	build	vcs.modified=false
```

(lines shortened to the ones that matter). The `mod` line must be the tag
exactly, and `vcs.modified` must be `false`: a build from a tree with
uncommitted changes says `true`, and its version reads `v0.20.1+dirty`. The
release workflow refuses to publish unless **every one** of the six binaries
passes both checks, and unless the program prints the tag as the last word of
its version line:

```
$ authnd --version
authnd version v0.10.1
$ authn-bridge --version
authn-bridge version v0.20.1
$ authn-revokd -version
authn-revokd v0.6.2
```

authnd and authn-bridge take `--version`; authn-revokd takes `-version`, Go's
standard flag syntax. From v0.6.1 it prints on standard output, like the other
two, so `v=$(authn-revokd -version)` captures it.

## Which releases have binaries

Binaries, sums and attestations are published from authnd v0.9.2, authn-bridge
v0.19.3, authn-revokd v0.5.0 and sshcert v0.1.2. The first release of each
built its binaries inside the checkout and reported `+dirty`; that was fixed in
the next one, and the per-binary check came after that. Earlier tags are
source-only: build them with `go install …@<tag>`, which records the tag in
the build information that `go version -m` reads. What the program prints is
not always that: sshcert-authorize printed `dev` for a `go install` build until
v0.1.5, and revokd has no `-version` before v0.5.0.
