---
title: "krl — OpenSSH key revocation lists"
linkTitle: "krl"
weight: 110
description: "go-authn/krl parses, builds, merges and checks OpenSSH KRLs as sshd reads them, with an expiry extension, judged by ssh-keygen."
tags: [libraries, revocation, ssh]
---

**Is this SSH certificate or key revoked — as sshd would answer?** The binary
format of OpenSSH's `PROTOCOL.krl`, the list `sshd` loads through
`RevokedKeys` and `ssh-keygen -k` writes. `golang.org/x/crypto/ssh` has no
support for it.

```sh
go get github.com/go-authn/krl@v0.6.1
```

`IsRevoked` follows `ssh_krl_check_key` in OpenSSH's `krl.c`: a certificate
is revoked when its serial or key ID is revoked under the CA that signed it or
under any CA, when its CA key is revoked, or when its own key is revoked by
blob or by SHA-1 or SHA-256 fingerprint. Serial 0 — what a CA writes when it
names none — is never revoked by serial.

## Example

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

The same list and certificates, written to files, get the same three answers
from OpenSSH 10.3p1's `ssh-keygen -Q -f list.krl`: `REVOKED`, `ok`,
`REVOKED`.

## Expiry: `expires@go-authn.github.io`

A KRL has a generation date and a version, and nothing says when it stops
being current, so a stale copy cannot be told from a fresh one.
`Builder.SetExpires` writes that time in an extension section named
`ExtensionExpires`, **not critical**, so `sshd` and `ssh-keygen` load the list
and ignore it; `Parse` reads it into `KRL.Expires`.

{{< callout type="warning" >}}
**No signatures**

OpenSSH never exposed a way to write the KRL signature section and no longer
verifies it. `Parse` skips one and sets `Signed`, which says nothing about
authenticity; `Builder` never writes one. The list's integrity, and so its
expiry's, comes from its transport — HTTPS from an authenticated server — or
from a detached SSHSIG signature checked by the caller, which this package
does not do.
{{< /callout >}}

## Merging: one file for sshd

`sshd` read a single `RevokedKeys` file until OpenSSH 10.3, so a server
trusting several CAs needs their lists in one. `Builder.Merge` adds every
revocation of a parsed list. `Builder.MergeCA(k, ca, others...)` keeps `k`'s
section for `ca`, its any-CA sections re-scoped to `ca`, and its explicit keys
and fingerprints, and leaves out — counting them — sections for another CA and
keys or fingerprints that designate one of `others`. `MergeCAWith` with
`MergeOptions{DropKeys: true}` also leaves out every explicit key except
`ca`'s own, for a list not trusted with every CA's users: a revoked user key
locks that user out under every CA of the merged file, because `sshd` checks a
certificate's own key whoever signed it.

## What it refuses, and why

`Parse` refuses what `ssh-keygen` and `sshd` refuse: a bad magic or format
version, truncated or trailing data, an unknown section or certificate
subsection, an unknown extension marked critical, a CA key OpenSSH cannot
parse, serial 0, an inverted serial range, a bitmap larger than OpenSSH reads
or one that wraps past 2^64−1. It also refuses a malformed or repeated expiry:
read as absent, it would turn a list meant to lapse into one that never does.

`Builder` refuses — at `Marshal`, which returns the first invalid request —
serial 0, a range whose low end is 0 or above its high end, a key ID or
comment containing a NUL, a certificate given where a CA key is expected, and
an expiry before the generation date.

**One deliberate difference.** For many sparse serials close together,
`ssh-keygen -k` writes a bitmap wider than its own reader accepts and then
refuses its own file (*bignum is too large*). `Parse` refuses that file too,
as `sshd` would; `Builder` starts a new section before a bitmap gets that
wide, so what it writes is always readable.

Parse allocates in proportion to what the list revokes, as OpenSSH does: a KRL
should come from a source trusted not to send an enormous one.

## What it is checked against

**OpenSSH's `ssh-keygen`**, on the Linux and macOS lanes, where
`KRL_REQUIRE_SSHKEYGEN=1` makes a missing one a failure (Windows runs the
pure-Go tests only):

- a KRL written by `ssh-keygen -k` with every serial encoding, key IDs, three
  CAs plus "any CA", explicit keys and a revoked CA key: `IsRevoked` answers
  like `ssh-keygen -Q` for 250 certificates, and `Builder` given the same
  revocations writes **the same bytes**;
- 40 random serial sets written by both: byte-identical, and the same answers
  for about 9000 certificates;
- every truncation and about 1400 single-byte corruptions: `Parse` refuses
  exactly what `ssh-keygen` refuses;
- the expiry extension loads in `ssh-keygen`, and the same section marked
  critical is refused;
- merged lists revoke exactly what one of their sources revokes.

`FuzzParse`, seeded with KRLs `ssh-keygen` wrote, and `FuzzBuilder` run in CI.
The coverage floor is 100%, measured on the Linux lane where `ssh-keygen` is
present.

## Reference

[pkg.go.dev/github.com/go-authn/krl@v0.6.1](https://pkg.go.dev/github.com/go-authn/krl@v0.6.1)
