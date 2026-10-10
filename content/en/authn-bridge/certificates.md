---
title: "Certificates"
linkTitle: "Certificates"
weight: 50
description: "The SSH user certificates authn-bridge signs, their EuroHPC Federation Platform profile, and the X.509 client certificates it issues for NFS over TLS."
tags: [authn-bridge, ssh, x509, eurohpc]
---

A person who logged in can have an SSH public key certified, or an X.509 client
certificate issued, for a few hours. A server that trusts the provider's CA lets
them in with no account file to edit there. Every certificate is **recorded in
`certificates_file` before it is handed out**: one that cannot be recorded is
not issued, since it could never be revoked, and revoked ones are published in
the [KRL and the CRL]({{< relref "/authn-bridge/revocation.md" >}}).

## SSH certificates

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

ssh_ca {
  key_file = "/var/lib/authn-bridge/ssh-ca"   # authn-bridge keygen --ssh-ca; Ed25519
  validity = "12h"                            # the default; a week at most
}

client "sftp" {
  device           = true
  ssh_certificates = true
}
```

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp` logs
in with a code, posts `~/.ssh/id_ed25519.pub` (or `--key`) to
`/ssh/certificate` with a token of the `ssh` scope, and writes
`<key>-cert.pub` beside it, where `ssh` and `sftp` find it.

The CA key must be Ed25519: an RSA CA key signs with SHA-1 unless told
otherwise, which OpenSSH has refused by default since 8.8.

**What the certificate says.**

- **Exactly one principal**, the person's `preferred_username` unless the
  client's profile says another claim. A certificate with no principal is valid
  for *any* user (PROTOCOL.certkeys), so a person with no username gets none. A
  name holding a comma, a space, a quote, a backslash or a control character is
  refused (`403`): `sshd` reads `principals="a,b"` and `AuthorizedPrincipalsFile`
  entries as lists, so one such name is two.
- **Key ID** `<principal> sub=<sub> jti=<token id>`: what `sshd` logs.
- **No `permit-*` extension** by default. SFTP needs none, and a certificate
  that permits no pty, no forwarding and no rc file grants file access and
  nothing else.
- **The person's groups** in the `groups@go-authn.org` extension, one per line,
  when the token carries groups. OpenSSH ignores it; it is signed, so a server
  that authorizes by group can believe it.
- **Valid** from five minutes ago (for clocks that disagree) until `validity`
  from now, or until the IdP's session ends if that is sooner.
- **The key** must be Ed25519, ECDSA P-256/384/521, a security key (`sk-`), or
  RSA of at least 2048 bits. A certificate is refused as a key.

## The EuroHPC SSH CA profile

The EuroHPC Federation Platform's SSH CA (GÉANT / MyAccessID) issues Ed25519
certificates valid one hour, with one principal that names the person across
the federation, and the hosts they are meant for in GÉANT's
`ssh-domain-grant@core.aai.geant.org` extension. A client can have its
certificates issued in that shape. Every key is per client and optional; a
client that sets none gets the certificate above.

```hcl
client "efp" {
  device              = true
  ssh_certificates    = true
  ssh_principal_claim = "voperson_id"               # the default is preferred_username
  ssh_validity        = "1h"                        # never longer than ssh_ca's, nor the IdP's session
  ssh_extensions      = ["permit-pty"]              # none by default
  ssh_domain_grants   = ["login.hpc.example.org"]   # the hosting entity's hosts
  # ssh_source_address = ["192.0.2.0/24"]           # the source-address critical option
}
```

| key | |
|---|---|
| `ssh_principal_claim` | `preferred_username`, `sub`, `voperson_id` or `eduperson_principal_name`. The last two are released by the `eduperson` scope, which the token must hold (`authn-bridge ssh-cert --scope eduperson`); otherwise, or when the IdP released no such attribute, the answer is `403` saying which |
| `ssh_extensions` | among `permit-pty`, `permit-user-rc`, `permit-port-forwarding`, `permit-agent-forwarding`, `permit-X11-forwarding` |
| `ssh_source_address` | addresses or CIDR prefixes, written canonically into `source-address` |
| `ssh_validity` | never longer than `ssh_ca`'s `validity` (equal is accepted), for this client |
| `ssh_domain_grants` | domain patterns, checked by [go-authn/sshcert]({{< relref "/sshcert/_index.md" >}})'s `ValidatePattern` and encoded by its `EncodeDomainGrant` |

### What the profile refuses

Each at startup, from `authn-bridge check`:

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

`no-touch-required` is not offered: it waives the user-presence test of the
person's **own** security key, which is not the provider's to give away for
everybody of a client.

A domain grant is held to the specification's syntax, then to this provider's
own policy: lower case, at least two labels, and a wildcard only under a
registrable domain. What stays fixed to the right of the last wildcard must not
be a public suffix (the Public Suffix List): `*.ac.uk` would grant every
institution under it.

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### Trusting it from a site

`GET /ssh/config` publishes the CA key in the shape EFP publishes its own, so a
site follows EFP's trust instructions with this provider's URL:

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFRUBlwxcGmmqW2lBI9bJyN4LL0/4U0NZwOOwBFPWw9"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd ignores the domain grant. The site filters by it with an
`AuthorizedPrincipalsCommand`: [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}),
which refuses a certificate whose grant does not name the host, and one with no
grant at all. The CA is not in the OpenID discovery document: no OpenID Connect
metadata names an SSH CA.

What remains different from EFP's own CA: with `ssh_principal_claim =
"voperson_id"`, as above, the principal is the `subject-id` the person's
institution released, in lower case, not a MyAccessID identifier; the groups
extension is there when the token carries groups; and **there is a KRL**,
`GET /ssh/krl`, listing the certificates of people disabled here.

## X.509 client certificates, for NFS over TLS

NFS over TLS (RFC 9289) can name the client by its certificate.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

x509_ca {
  key_file  = "/var/lib/authn-bridge/nfs-ca/ca.key"   # authn-bridge keygen --x509-ca /var/lib/authn-bridge/nfs-ca
  cert_file = "/var/lib/authn-bridge/nfs-ca/ca.crt"   # what go-fileshare trusts
  validity  = "12h"                                   # the default; a week at most
}

client "nfs" {
  device            = true
  x509_certificates = true
}
```

`authn-bridge nfs-cert --issuer ... --client nfs` makes a P-256 key on the
person's machine, posts a certificate request to `/x509/cert` with a token of
the `nfs` scope, and writes the certificate and the key. The CA key must be
P-256, and its certificate a CA that signs certificates and CRLs.

**What the certificate says.** The request's subject and extensions are
ignored: what is certified is the token's person, not what they asked for.

- The person, `user@domain`, as **one** subjectAltName `otherName`
  `1.3.6.1.4.1.2238.1.1.1` holding a UTF8String, where FreeBSD's
  `rpc.tlsservd -u` reads it. A username without `@`, or under three bytes, is
  refused.
- Each group as a URI name beside it:
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`.
- The CN is the username; past 64 characters the subject is empty and the
  subjectAltName critical (RFC 5280).
- Client authentication only, and a CRL distribution point:
  `<issuer>/x509/crl`.
- Valid from five minutes ago until `validity`, the IdP's session or the CA's
  own certificate, whichever ends first.
- A P-256 or RSA (2048 bits and more) key, and a request signed by it.

{{< callout type="warning" >}}
**A certificate names the machine, not the user of it**

RFC 9289: the server "cannot utilize the remote TLS peer identity to
authenticate RPC users". Linux sets the client certificate per mount, so
everybody using that mount is the person it names. This is for a machine
one person uses, and `authn-bridge nfs-cert` says so.
{{< /callout >}}

## A certificate request held open across a disabling

The token is checked when the request starts and the body read after, at
whatever pace the client sends it. So a certificate is recorded first, and then
the token and the person are checked again: if the person was disabled, or the
token revoked, in between, the certificate just recorded is revoked and the
answer is `401`. Either the revocation saw the certificate, or the certificate
sees the revocation.
