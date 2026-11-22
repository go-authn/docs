---
title: "harden — two security primitives, shared"
linkTitle: "harden"
weight: 36
description: "go-authn/harden holds the two security primitives that go-authn repositories had each copied: the https-or-loopback redirect rule, and a private file written atomically."
tags: [libraries, harden, security]
---

**What did every go-authn repository copy?** Two small rules, now in one
module with no dependency but the standard library.

```sh
go get github.com/go-authn/harden@v0.2.0
```

## `redirect` {#redirect}

The rule applied before a token, a key set or a signed assertion crosses a
link: **the URL is https, or it names this machine.**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| Function | |
|---|---|
| `CheckRedirect(req, via) error` | an `http.Client` policy: stops after 10 redirects and refuses a target that is not https and not loopback (https to http on another host is the case it exists for). Chain your own policy after it |
| `HTTPSOrLoopback(rawURL) error` | nil for `https://host.example/...`, or `http://` with a loopback host. Refuses no host, other schemes and cleartext. The error names the scheme and host, never the whole URL |
| `Loopback(host) bool` | `host` as `url.URL.Hostname()` returns it |

`Loopback` accepts an IP literal that is loopback (127.0.0.0/8, `::1`,
IPv4-mapped `::ffff:127.0.0.1`), and `localhost` or any name under
`.localhost` (RFC 6761 section 6.3), in any letter case, with or without the
trailing dot. It never matches a prefix, so `127.evil.example` is refused, as
are `0x7f.1`, `127.1`, `2130706433`, an IPv6 zone and the bracketed `[::1]`
(brackets are URL syntax, not part of a host).

`Loopback` and `HTTPSOrLoopback` are fuzzed against a second reading of the
RFC; the corpus is committed.

It is what [oidc]({{< relref "/libraries/oidc.md" >}}) (v0.8.1),
[saml]({{< relref "/libraries/saml.md" >}}) (v0.7.3),
[wireguard]({{< relref "/libraries/wireguard.md" >}}), rp (v0.5.1) and awscred
(v0.3.1) apply.

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write` puts data at `path` with mode 0600: a temporary file in the same
directory, `fsync`, then `rename`. So:

- a reader sees the old file or the new one, never half of one;
- a symbolic link left at `path` is **replaced, not followed** (what it pointed
  at is untouched), and a file of looser mode does not keep its mode;
- on Unix, a directory that is a symbolic link, belongs to someone else or is
  writable by group or others is refused before anything is written.

It does not create the directory. On Windows there is no mode to read; since
v0.2.0 the file is made with a protected access list holding one entry, the
current account, set by `CreateFile` (kinit v0.3.2's list), so the folder's
entries are never inherited. The module requires `golang.org/x/sys`, used by
Windows builds only.

It is what writes kinit's `--cred-file` (v0.3.3), wireguard's `FloorFile`
(v0.2.1), `authn-revokd`'s state file (revocation v0.7.2) and
[secretsource]({{< relref "/libraries/secretsource.md" >}})'s KeePassXC
association file (v0.8.1).

## Floors

go-authn/wireguard and go-authn/revocation both keep an ordering floor across a
restart, but they do not share a floor: wireguard keeps a bare version and issue
time in a small file of its own, revocation keeps the whole signed list and
recomputes the floor by verifying it. Only the file write is common, and that
is `privfile`.

## Reference {#reference}

The README at
[github.com/go-authn/harden](https://github.com/go-authn/harden) is the source
of truth for this page. BSD 3-Clause.
