---
title: "When a list lapses"
linkTitle: "When a list lapses"
weight: 40
description: "What authn-revokd writes for sshd when it holds no current list from a CA: a KRL that revokes the CA key itself, so that every certificate of that CA is refused."
tags: [authn-revokd, revocation, fail closed, sshd]
---

A revocation check that lets everything through when the list cannot be had is
the one an attacker who can block the list defeats. So when authn-revokd holds
no current list from a source, what that source's list protects is
**refused**, until a current list arrives again.

| output | while a source has no current list |
|---|---|
| a KRL, for `sshd` | authn-revokd writes a KRL that **revokes the source's CA key** |
| a CRL, for a TLS server | the expired CRL is left in place; OpenSSL refuses an expired CRL by itself |

## For sshd: revoking the CA itself

`sshd` has no notion of a list's expiry: it would go on reading the last file
written for ever. But it checks the **CA key** of every certificate against
`RevokedKeys`. So, in place of the list it cannot vouch for, authn-revokd
puts the CA's own key into the output, and every certificate that CA signed is
refused, and nothing else.

Here the issuer is stopped, and the KRL source has `max_age = "30s"`, so the
copy held lapses within a minute instead of an hour. The CRL source has no
`max_age`, and its copy is still current:

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-26T12:27:10Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4 # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh` is `not current`, and its output is failed closed; `bridge-x509`
is only `not fetched`, and its CRL is left as it was
([what `-once` reports]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
`SHA256:AnDb/...` is the bridge's SSH CA. A certificate it signed is now
revoked as far as anything reading the file is concerned. The commands above
ran in the `revokd` directory, where `out/` is; this one runs beside it, in the
directory that holds the test certificates, as on
[sshcert-authorize's page]({{< relref "/sshcert/authorize.md#krl" >}}), so the
same file is `../revokd/out/sshd.krl`:

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

The comment says `FAIL CLOSED` and names the source, so a person reading
`ssh-keygen -Q -l` sees why. The file's date is 1970 when every source has
lapsed. The output is written **as soon as a sync notices**, which for the daemon
is its next `refresh` and for the timer its next tick. When a current list
arrives again, the next sync writes it in place of the CA's key, and the CA's
certificates are accepted again.

The same happens **before the first list**: a source never fetched has nothing
current, and its CA is revoked from the first write. A new installation refuses
the CA's certificates until its first list verifies, rather than accepting them
unchecked.

### Each CA for itself

In an output that merges several sources, only the lapsed source's CA is
revoked. The others keep their lists. A list that cannot be merged (past the
serial ranges go-authn/krl keeps) fails closed for its own CA only, and
`/healthz` names it. Only if the lists merge alone but not together is every CA
of the output revoked, and the comment says so
(`FAIL CLOSED, the output could not be rendered`). Keeping the old file instead
would let a later lapse go unseen.

## For a TLS server: the CRL itself

A CRL already says when it stops being current, and OpenSSL refuses one past
its `nextUpdate` ("CRL has expired"). So authn-revokd leaves the last verified
CRL in place, and the TLS server fails closed by itself. That is also why
`max_age` is refused on a source that feeds a CRL output: a server that loaded
the CRL keeps it until its `nextUpdate`, whatever authn-revokd writes.

## Readers that check the expiry themselves

The merged KRL carries an expiry, the first of its current inputs'. A reader
that checks it, such as go-fileshare's `ssh_krl_file` or
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}}),
sees authn-revokd stop as it would see the issuer stop.

{{< callout type="warning" >}}
**This only works while authn-revokd runs**

The file is failed closed by authn-revokd. While it is stopped, sshd keeps
reading the last file written, current or not. Hence `Restart=always` on
the daemon, and monitoring the unit, or the timer, or `/healthz`.
{{< /callout >}}
