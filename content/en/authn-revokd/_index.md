---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "An agent that fetches signed KRLs and CRLs, keeps only the lists that verify, writes them where sshd and TLS servers read them, and fails closed when one lapses."
tags: [authn-revokd, revocation, krl, crl]
---

**OpenSSH has no way to distribute a KRL, and nothing in a KRL says it is
stale.** `sshd` reads a file that stopped updating months ago as the current
list. authn-revokd closes both gaps for the lists
[authn-bridge]({{< relref "/authn-bridge/revocation.md" >}}) publishes: it
fetches each list, keeps it only if it verifies, writes it where `sshd` or a TLS
server reads it, and, when a list lapses, writes one that **revokes the CA
itself**. Pure Go, `CGO_ENABLED=0`, one binary. These pages describe v0.7.0.

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.7.0
go: downloading github.com/go-authn/revocation v0.7.0
$ authn-revokd --version
authn-revokd v0.7.0
$ authn-revokd --help
authn-revokd fetches revocation lists, keeps only those that verify, writes
them where sshd and TLS servers read them (failing closed for sshd when a list
lapses) and, with listen, serves the verified copies as a mirror. SIGHUP syncs now.

The single-dash spellings -config, -once, -version and -help of earlier
releases are still accepted, with a deprecation warning on stderr.

Usage:
  authn-revokd [flags]

Flags:
  -c, --config string   the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -h, --help            help for authn-revokd
  -o, --once            sync once and exit: 1 when a list is not current, or could not be fetched
  -v, --version         version for authn-revokd
```

The command is cobra since v0.7.0: POSIX flags `--config`/`-c`, `--once`/`-o`,
`--version`/`-v`, `--help`/`-h`, and `--config=PATH`. `--help` prints to
standard output and exits 0 (before v0.6.2 the old `-help` exited 2). The
single-dash spellings of earlier releases (`-config`, `-once`, `-version`,
`-help`, with `=` or a separate value) are still accepted, with one
deprecation line per flag on standard error, and will be removed in a later
release; the exit statuses are unchanged (0; 1 for a failure or a list not
current under `--once`; 2 for a usage error or an unreadable configuration),
so a unit deployed with `-once` needs no change.

Before v0.6.0 the command was `revokd`, and read `/etc/revokd.hcl` by default.
Nothing reads that file any more; when it is there and the new default is not,
the error names both paths.

## What it does, in one run

Against a stand-in issuer on loopback (a small program serving a KRL and a CRL
signed by test keys, with the same endpoints as authn-bridge), with a KRL source
and a CRL source:

```
$ authn-revokd --config revokd.hcl --once
bridge-ssh: version 0, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
bridge-x509: version 1794481424000, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261112T120344
# Comment: authn-revokd sshd
```

A second run with nothing new prints nothing and exits 0: an output is
rewritten only when its content changes.

## Why the transport does not matter

Every list authenticates itself: a KRL by a detached SSHSIG signature by the
CA's own key, a CRL by its CA's signature. Every list says when it stops being
current. So a list may come over HTTPS, plain HTTP inside a cluster, a mirror,
or a file. The transport decides how fast a change arrives, never whether a
forged or stale list is taken.

| | KRL | CRL |
|---|---|---|
| authentic | SSHSIG by the SSH CA key, namespace `krl@go-authn.github.io` | signed by its CA |
| current | `expires@go-authn.github.io`, which sshd ignores | `nextUpdate` |
| never backwards | `krl_version`, then generation date | CRL Number, then `thisUpdate` |
| fail closed | authn-revokd writes a KRL that revokes the CA key | OpenSSL refuses an expired CRL by itself |

## Where to go next

| | |
|---|---|
| [Installing it]({{< relref "/authn-revokd/install.md" >}}) | the daemon, or `--once` on a timer; wiring sshd and nginx |
| [The configuration]({{< relref "/authn-revokd/configuration.md" >}}) | sources, outputs, the mirror, and what is refused |
| [How a list is verified]({{< relref "/authn-revokd/verification.md" >}}) | signature, dates, and never older than the list held, across restarts |
| [When a list lapses]({{< relref "/authn-revokd/lapse.md" >}}) | the KRL that revokes the CA itself |

## What it does not do

A revocation reaches a server no faster than authn-revokd polls (`refresh`),
plus the issuer's delay in issuing again. While the issuer is down, its
certificates are refused from the list's expiry on. Whoever holds a CA's key can
sign any list, as they can sign any certificate.

## Licence

BSD-3-Clause.
