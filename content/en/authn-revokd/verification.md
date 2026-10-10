---
title: "How a list is verified"
linkTitle: "Verification"
weight: 30
description: "What authn-revokd checks before it keeps a list: the signature, the dates, and that it is never older than the list it holds, across restarts too."
tags: [authn-revokd, revocation, security]
---

A list that does not verify is never written, served or used. The last good
copy stays. A fetch that fails, for any reason, never replaces it with an empty
answer, which would revoke nothing.

## The signature

**A KRL** is fetched with its signature, `<url>.sig`: an armored SSHSIG over
the whole file, by the **SSH CA key** configured as `ssh_ca`, in the namespace
`krl@go-authn.github.io`. The namespace keeps the signature from being taken
for anything else. A signer hashes with SHA-512; SHA-256 is accepted too. An RSA
signature in the SHA-1 form, which PROTOCOL.sshsig forbids, is refused.

The KRL itself must parse as `sshd` parses it, and must not carry OpenSSH's own
signature section, which OpenSSH never verifies.

A list signed by any other key is refused:

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:SLbG7N+YZ/TQ6B3I1DQLYo2/6In4OWx5GYkRfKIxpxo: public key does not match
bridge-x509: version 1791665695047, issued 2026-10-10T20:54:55Z, expires 2026-10-10T21:54:55Z
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/other.krl
output tls: wrote /tmp/docs-patch-a2daf7c8/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

Here `ssh_ca` named a key that did not sign bridge's list, and the error names
that key. A signature that does not verify may also be a list issued again
between the two requests, so both are fetched once more before it is reported.
This was the first fetch of that source, so there was no good copy to keep, and
the output is the [fail-closed list]({{< relref "/authn-revokd/lapse.md" >}}) at
once. (Before v0.6.2 the same failure was reported as "the list changed between
it and its signature", ahead of the same words.)

The signature is fetched with `If-Match: <the list's ETag>`. A list issued
again between the two requests answers `412`, and both are fetched again.

**A CRL** is checked against the CA certificate configured as `x509_ca`: its
signature first, on the raw bytes, **before** the rest is parsed, so a large
CRL signed by anybody costs a signature check rather than a parse. Then its
issuer must be that certificate's subject; it must have a CRL Number and a
`nextUpdate` after its `thisUpdate`; and it must not be a delta CRL, nor carry a
critical extension other than the CRL Number and the Authority Key Identifier,
nor a critical entry extension.

A KRL must also **say when it expires**, in the `expires@go-authn.github.io`
extension: one that does not could never be told from a stale one.

Bodies are bounded: a KRL at 32 MiB, its signature at 64 KiB, a CRL at 64 MiB.

## The dates

A list is current when:

- now is before its expiry (the KRL's extension, the CRL's `nextUpdate`);
- it was not issued more than five minutes in the future: an issuer whose clock
  is ahead by more than that writes lists whose age cannot be known;
- with `max_age`, it was issued no longer ago than that.

A list that is not current is refused when fetched. A `304 Not Modified` is no
news: the copy held may have expired since, and it is judged again at every
sync.

## Never older than the list held

A list's position is its **version** (the KRL's `krl_version`, the CRL
Number), then its **issue time** (the KRL's generation date, the CRL's
`thisUpdate`). A list may replace the one held only when it has a higher
version, or the same version issued later: the same revocations, issued again
with a new expiry. Anything else is a rollback: a replayed or restored older
list, still signed and unexpired, that would un-revoke what the newer one
revoked.

### Across restarts too

The list held is kept in `state_dir`, one file per source holding the list and
its signature together, written by a single rename with the directory synced.
At start each copy is **verified again** (expired or not, it orders what comes
next), and a copy that no longer verifies is not trusted, not even to order the
next one, and is said so in the log.

Here a source is pointed, after a restart, at a list an earlier bridge process
served fourteen seconds before, still signed and still unexpired:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-10T20:54:50Z, expires 2026-10-10T21:54:50Z
bridge-x509: version 1791665695047, issued 2026-10-10T20:54:55Z, expires 2026-10-10T21:54:55Z
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/sshd.krl
output tls: wrote /tmp/docs-patch-a2daf7c8/revokd/out/bridge.crl
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/docs-patch-a2daf7c8/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-10T20:54:36Z, the copy held at 2026-10-10T20:54:50Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-10T21:54:50Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261010T225450
# Comment: authn-revokd sshd
```

The older list is refused and the output keeps the newer one. The process that
refused it had never seen the newer list: it read it back from `state_dir`.

Since the state is what makes a rollback detectable, the directory is held to
sshd's StrictModes rule ([the configuration]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}})).
A crash between two writes cannot leave a pair that fails to verify, which
would take the rollback guard with it: the list and its signature are one file.

## What `-once` reports

`-once` exits `1` when a source has no current list, when its **last fetch
failed**, or when an output could not be written, and its last line says which
of the first two it is:

| last line | the source | its outputs |
|---|---|---|
| `not current: <source>` | holds no current list: never fetched, expired, or past `max_age` | failed closed for sshd |
| `not fetched: <source> (the list held is current until <T>)` | its fetch failed, but the copy held is still current | written from that copy, unchanged, until `T` |

Here the issuer is stopped while both lists held are still current:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-10T21:54:50Z), bridge-x509 (the list held is current until 2026-10-10T21:54:55Z)
```

That run left `sshd.krl` as it was. Once a list held lapses, the same source is
reported `not current`, and both kinds can share the line, as on
[when a list lapses]({{< relref "/authn-revokd/lapse.md" >}}). Before v0.6.2
both cases were reported `not current`, which said a list had lapsed when only
its fetch had failed; the exit status was `1` then too.

The mirror's `/healthz` judges by the copy held instead, and answered `ok` while
the issuer was down and the copies still current.
