---
title: "go-authn"
linkTitle: "Home"
type: docs
cascade:
  type: docs
description: "Authentication in pure Go: the factors that prove somebody is present, a directory that says who they are, both halves of Kerberos, and an OpenID Connect provider in front of a SAML federation."
---

**Two questions, and they are not the same.** *Is this person here, now?* is
not *who is this person, and what would prove them?* go-authn answers both:
the factors that prove presence, a directory that carries what **proves** each
person rather than a password field, both halves of Kerberos, and an OpenID
Connect provider in front of a SAML federation. Pure Go, `CGO_ENABLED=0`.
These pages describe the releases listed on the [status page]({{< relref "/status.md" >}}).

## Four programs

| | what it is | these pages describe |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | an LDAP server, and optionally a Kerberos realm, for people who live somewhere else: a file, a SQL database, another directory | v0.10.1 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | an OpenID Connect provider in front of a SAML federation (RENATER, eduGAIN), which also issues SSH certificates and signs the lists that revoke them | v0.22.0 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | fetches those lists, verifies each before any server reads it, and fails closed when one lapses | v0.6.3 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`, which sshd asks whether a certificate's domain grant names this host | v0.1.6 |

Each is one static binary for Linux, macOS and Windows on amd64 and arm64,
published with `SHA256SUMS` and build provenance:
[verifying a download]({{< relref "/security/verifying-releases.md" >}}).

```sh
go install github.com/go-authn/authnd@v0.10.1
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.22.0
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.3
```

The commands are named `authn-*` (and `authnd`) because they are installed on
machines that run other things: a bare `bridge` or `revokd` in `/usr/bin` would
take a name somebody else may need.

## And the libraries under them

The programs are thin. What they do lives in
[thirteen modules]({{< relref "/libraries/_index.md" >}}), one question each, so
that a service which only *accepts* Kerberos tickets never links a KDC, and one
that only checks a one-time code never links a directory.

## Why the directory carries what proves somebody

SMB needs an NT hash; S3 needs the password itself, because SigV4 computes an
HMAC from it; a Kerberos realm needs a key derived from the password, and an NT
hash is not that key. An identity holding only one of those can serve some
protocols and never others, whatever the person types. So go-authn's directory
records **what each person can prove**, and `authnd check` prints, before
anything is restarted, who could be issued a Kerberos ticket and who never
could:

```
realm EXAMPLE.ORG on 127.0.0.1:88 (udp and tcp), keytab krb5.keytab
  can be issued a ticket: alice
  CANNOT, whatever they type: bob
  a KDC must decrypt the pre-authentication with the person's key
  bob: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

That is authnd v0.10.1's own output: [the whole of it]({{< relref "/authnd/check.md" >}}).

## Judged by other people's tools

A fixture built from one reading of a protocol can only confirm that reading.
So the servers are read by clients they did not write: OpenLDAP's own
`ldapsearch` binds to authnd, MIT's own `kinit` takes tickets from its realm,
and OpenSSH reads the certificates and KRLs authn-bridge issues.
