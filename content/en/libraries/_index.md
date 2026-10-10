---
title: "The libraries, one question each"
linkTitle: "Libraries"
weight: 50
description: "The thirteen go-authn Go modules: the question each one answers, the version these pages describe, and why they are separate modules."
tags: [libraries]
---

Programs such as [authnd]({{< relref "/authnd/_index.md" >}}) and
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) are built from
modules that are published, versioned and tested on their own. Each answers
**one** question, and a program imports the ones whose questions it asks.

All of them are pure Go and build with `CGO_ENABLED=0`.

| module | the question it answers | these pages describe | import path |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | did enough factors answer, of enough kinds, and which ones? | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | is this six-digit code right, and has it been used before? | v0.4.1 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | how is a security key spoken to, over 64-byte reports? | v0.6.1 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | did *the registered* key answer, and did a person touch it? | v0.4.1 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | who is somebody, and what can prove them? | v0.11.1 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | what are the bytes of an LDAP server? | v0.7.1 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | is this Kerberos ticket good for this service? | v0.3.0 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | how does a realm issue tickets from a directory? | v0.4.2 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | who does this bearer token say is asking, and should it be believed? | v0.4.0 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | what did a federation's identity provider say about this person? | v0.4.0 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | is this SSH certificate or key revoked, as sshd would answer? | v0.6.0 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | where does a daemon's TLS server certificate come from? | v0.5.1 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | may this WireGuard key connect, and whose is it? | v0.1.0 | `github.com/go-authn/wireguard` |

## How they group

**Factors** — whether a person is present.
[mfa]({{< relref "/libraries/mfa.md" >}}) decides how much proof is enough and
knows about no device. [totp]({{< relref "/libraries/totp.md" >}}) is one
factor: a code from a phone. [fido]({{< relref "/libraries/fido.md" >}}) speaks
CTAP to a security key and knows about no policy;
[keyfactor]({{< relref "/libraries/keyfactor.md" >}}) is the one piece that
imports both, and turns a key into a factor.

**The directory, and its protocol.**
[directory]({{< relref "/libraries/directory.md" >}}) is the model: a person,
and which credentials a source holds for them — a password, an NT hash, a
verifier, SSH keys, a one-time-code secret.
[ldap]({{< relref "/libraries/ldap.md" >}}) is the LDAP wire protocol, as a
server; what it answers is the handler's business.

**Kerberos, in two halves.** [krb5]({{< relref "/libraries/krb5.md" >}})
*accepts* tickets: a keytab, an AP-REQ in, an AP-REP out.
[kdc]({{< relref "/libraries/kdc.md" >}}) *issues* them, from a directory that
holds passwords.

**Federation and tokens.** [saml]({{< relref "/libraries/saml.md" >}}) is a
SAML 2.0 service provider in front of a federation such as RENATER or eduGAIN.
[oidc]({{< relref "/libraries/oidc.md" >}}) verifies the OpenID Connect tokens
a provider signs — the resource-server half, with no login flow.

**Revocation and certificates.** [krl]({{< relref "/libraries/krl.md" >}})
reads, writes and checks OpenSSH key revocation lists.
[servercert]({{< relref "/libraries/servercert.md" >}}) gives a daemon its TLS
certificate, from files or from ACME.

**[wireguard]({{< relref "/libraries/wireguard.md" >}})** carries the signed
list of WireGuard public keys people have registered with a provider, which a
gateway turns into peers.

## Why they are separate modules

**A service that only accepts tickets never links a KDC.** An NFS server
verifies the tickets a client presents; it has a keytab and nothing else to do
with a realm. If accepting and issuing were one module, every such server
would carry a ticket-issuing code path, and the directory a KDC reads people
from, that it never runs.

This is measured, not intended. In a scratch module that imports only
`github.com/go-authn/krb5@v0.3.0`:

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.0
```

The same command for a module that imports `github.com/go-authn/kdc@v0.4.2`
lists `github.com/go-authn/directory` and `github.com/go-authn/kdc`: issuing
needs the people, accepting does not.

The same rule holds elsewhere. `mfa` imports nothing outside the standard
library, and `fido` does not import `mfa`: a program that only wants to make a
key blink does not carry a policy package. `totp` depends on `mfa` only, and
`oidc` has no dependency at all. `directory` keeps its LDAP, SQL and HCL
sources in subpackages: the core package imports nothing outside the standard
library, and `sqldir` takes an `*sql.DB`, so the database driver is the
program's choice.

## Every page has the same parts

The question; the `go get` line for the version described; a minimal example
that compiles against that version; what the module refuses, from its code;
and what it is checked against — the implementation that is not this one,
named in its CI or its tests. Where a README and the code disagree, the page
follows the code.
