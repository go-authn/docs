---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "An OpenID Connect provider in front of a SAML federation: people log in at their own institution, and applications get tokens, SSH certificates and X.509 client certificates."
tags: [authn-bridge, oidc, saml]
---

**People log in at their own university, through RENATER's Fédération
Éducation-Recherche or eduGAIN, and applications get an OpenID Connect token.**
The same login can also have an SSH key certified, an X.509 client certificate
issued for NFS over TLS, an application password set for SMB and S3, or a
WireGuard key registered. The provider can revoke what it issued, and it
publishes signed lists of what it has revoked; an access token already handed
out stays valid until it expires. Pure Go, `CGO_ENABLED=0`, one
binary. These pages describe v0.23.6.

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.6

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

Before v0.20.0 the command was `bridge`. That is also iproute2's
`/sbin/bridge`, installed on practically every Linux system, and whichever came
first on `PATH` won. The module path is still `github.com/go-authn/bridge`.

## Why a bridge

A research federation speaks SAML. Its members are hundreds of identity
providers, one per institution, listed in a signed metadata document the
federation publishes. Applications written today want OpenID Connect, and trust one
provider. authn-bridge is that one provider: a SAML service provider on one
side, registered once with the federation, and an OpenID provider on the other.

A gateway decides who everybody is for every application behind it, so most
of this program is refusals. It refuses metadata the federation did not sign, an
assertion that names somebody from another institution's domain, groups an IdP
has no authority over, and a configuration that would let any of these through.
A configuration that cannot be served safely does not start.

## What it prints at startup

```
$ authn-bridge --config etc/bridge-admin.hcl
admin API on unix:///tmp/authn/run/admin.sock
metrics on 127.0.0.1:28475
authn-bridge v0.23.4: http://127.0.0.1:28473 on 127.0.0.1:28473
```

This is a test provider on loopback (an `http://` issuer is accepted only on a
loopback host). It fetches the federation's metadata **before** it listens. A
provider that cannot name a single institution is one nobody can log in through,
so without the metadata it exits rather than starts.

## Where to go next

| | |
|---|---|
| [Installing it]({{< relref "/authn-bridge/install.md" >}}) | the user, the directories, the systemd unit, the keys |
| [The configuration]({{< relref "/authn-bridge/configuration.md" >}}) | every block, `check`, and what is refused at startup |
| [The federation side]({{< relref "/authn-bridge/federation.md" >}}) | metadata, its signer's fingerprint, scopes, and what an IdP may assert |
| [Tokens]({{< relref "/authn-bridge/tokens.md" >}}) | ID tokens, access tokens, the device grant, application passwords, WireGuard keys |
| [Resource indicators]({{< relref "/authn-bridge/resources.md" >}}) | a token for one of a client's resource servers at a time (RFC 8707) |
| [Certificates]({{< relref "/authn-bridge/certificates.md" >}}) | SSH certificates, the EuroHPC profile, X.509 client certificates for NFS |
| [Revocation]({{< relref "/authn-bridge/revocation.md" >}}) | the signed KRL and CRL, and the Shared Signals transmitter |
| [The admin API]({{< relref "/authn-bridge/admin.md" >}}) | disabling a person or an institution, health and metrics |

The lists it signs are read by [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
for a plain `sshd` or a TLS server, and by
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
which checks them itself.

## What it is not

- **One process.** With a `state` block, refresh tokens and the access tokens
  honoured at `/userinfo` survive a restart. Logins in progress, codes and
  device grants do not. The state is written through and read at start, so
  two instances on one database would each miss what the other wrote.
- No dynamic client registration, and no front- or back-channel logout.
- No users or groups to add. People exist because their institution vouches
  for them, and their groups are what it asserts.

## Licence

BSD-3-Clause.
