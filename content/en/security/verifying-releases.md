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
binary. The examples below use authnd v0.9.6; the other programs work the same
way with their own repository and name.

```sh
gh release download v0.9.6 --repo go-authn/authnd
```

## 1. The checksum

```sh
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```
authnd-linux-amd64: OK
```

This proves the file is the one the release lists, and nothing more: whoever
could replace a binary on the release page could replace `SHA256SUMS` beside
it.

## 2. The provenance

```sh
gh attestation verify authnd-linux-amd64 --repo go-authn/authnd
echo $?
```

The attestation is signed by GitHub for the workflow run that built the file,
so it names the repository and the workflow, not a key somebody holds.

{{< callout type="warning" >}}
**Read the exit status, not the output.** Without a terminal, some versions of
`gh` print nothing at all when the verification succeeds: measured with gh
2.65.0, a genuine binary gave exit status 0 and an empty output. A binary with
one byte appended gave exit status 1 and
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`,
because no attestation exists for its digest. Silence is not the failure; a
non-zero status is.
{{< /callout >}}

## 3. What the binary says about itself

```sh
go version -m authnd-linux-amd64
```

```
	path	github.com/go-authn/authnd
	mod	github.com/go-authn/authnd	v0.9.6
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=82da8e7ec3dff61e4e883a1bd03600aa550af48a
	build	vcs.modified=false
```

(lines shortened to the ones that matter). The `mod` line must be the tag
exactly, and `vcs.modified` must be `false`: a build from a tree with
uncommitted changes says `true`, and its version reads `v0.9.6+dirty`. The
release workflow refuses to publish unless **every one** of the six binaries
passes both checks, and unless the program prints the tag as the last word of
its version line:

```
$ authnd --version
authnd version v0.9.6
$ authn-bridge --version
authn-bridge version v0.20.0
$ authn-revokd -version
authn-revokd v0.6.1
```

authnd and authn-bridge take `--version`; authn-revokd takes `-version`, Go's
standard flag syntax. From v0.6.1 it prints on standard output, like the other
two, so `v=$(authn-revokd -version)` captures it.

## Which releases have binaries

Binaries, sums and attestations are published from authnd v0.9.2, authn-bridge
v0.19.3, authn-revokd v0.5.0 and sshcert v0.1.2. The first release of each
built its binaries inside the checkout and reported `+dirty`; that was fixed in
the next one, and the per-binary check came after that. Earlier tags are
source-only: build them with `go install …@<tag>`, which records the version
in the same way.
