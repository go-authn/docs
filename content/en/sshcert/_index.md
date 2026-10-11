---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "The GÉANT / EuroHPC domain-grant extension of SSH user certificates, and sshcert-authorize, the fail-closed command sshd asks whether a certificate is meant for this host."
tags: [sshcert, ssh, eurohpc]
---

**A certificate from a federation's CA is not, by itself, permission for every
host that trusts that CA.** The EuroHPC Federation Platform's SSH CA writes the
hosts a certificate is meant for into an extension,
`ssh-domain-grant@core.aai.geant.org`, and `sshd` ignores it. go-authn/sshcert
reads and writes that extension, and its command, `sshcert-authorize`, is what
`sshd` runs to enforce it. Pure Go, `CGO_ENABLED=0`. These pages describe
v0.1.6.

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.6
$ sshcert-authorize -version
sshcert-authorize v0.1.6
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | the `AuthorizedPrincipalsCommand`: what it checks, what it refuses, and how sshd calls it |

## The extension

Its data is a compact JSON array of host patterns, `["login.example.org"]`. A
`*` matches **one or more** characters within a single label, and names compare
without case:

| pattern | matches | does not match |
|---|---|---|
| `login.example.org` | `login.example.org`, `LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`, `a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

The reading is strict: only what the encoder writes is accepted. No
whitespace, nothing after `]`, no JSON escapes, no duplicates, at most 64
patterns, each made of letters, digits, hyphens and `*`, in labels of 1 to 63
bytes, at most 253 bytes, and **no `*` in the rightmost label**. `null`, objects,
numbers and nested arrays are refused. `[]` is accepted, and grants no host.

A grant that is present and malformed is never reported as absent. That
difference is the whole point of the command.

## Who uses it

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})**
  writes the extension for a client's `ssh_domain_grants`, after checking each
  pattern with this package's `ValidatePattern`.
- **go-fileshare**'s SFTP server reads it with `ssh_domains`, and refuses a
  certificate with no grant unless `ssh_accept_ungranted` is set.
- **sshcert-authorize** is the same check for a plain `sshd`.

## Licence

BSD-3-Clause.
