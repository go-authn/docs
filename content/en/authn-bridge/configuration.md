---
title: "The configuration"
linkTitle: "Configuration"
weight: 20
description: "How authn-bridge's HCL configuration is laid out, what check prints, and what is refused before anybody can log in."
tags: [authn-bridge, configuration]
---

One HCL file, or a directory of them: `--config /etc/authn-bridge` reads every
`*.hcl` there in name order and merges them, and `--config` may be given more
than once. The configuration is read at start and never again.

```hcl
issuer            = "https://login.example.org"       # https; compared whole by every relying party
listen            = "127.0.0.1:8080"                  # the default: plain HTTP behind a TLS proxy
signing_key_file  = "/var/lib/authn-bridge/oidc.key"  # authn-bridge keygen --key
subject_salt_file = "/var/lib/authn-bridge/salt"      # authn-bridge keygen --salt; never change it
disabled_file     = "/var/lib/authn-bridge/disabled.json"
certificates_file = "/var/lib/authn-bridge/certificates.json"

saml {
  key_file             = "/var/lib/authn-bridge/saml.key"
  cert_file            = "/var/lib/authn-bridge/saml.crt"
  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"
}

state {
  driver   = "sqlite"                                 # or postgres, mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}

client "my-app" {
  secret_file   = "/etc/authn-bridge/my-app.secret"   # absent: a public client
  redirect_uris = ["https://app.example.org/callback"]
}
```

What is required is `issuer`, `signing_key_file`, `subject_salt_file`, a `saml`
block with the five keys above, and at least one `client`. Everything else has a
default or is off.

## `check`, before a restart

`check` reads the configuration the way the server does, loads every key it
names, **fetches the federation's metadata**, and says what would be served:

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-17T19:16:33Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*Usable here* leaves out an IdP that `saml { idps }` does not list, and one the
[admin API]({{< relref "/authn-bridge/admin.md" >}}) has disabled: with the
institution above disabled, the same command prints
`federation    1 IdPs, 0 usable here`. An `idps` entry the federation does
not list is refused here, though the server would start with it:

```
federation    1 IdPs, 0 usable here, valid until 2026-10-17T19:16:33Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata` prints the SAML metadata to register with the
federation. See [the federation side]({{< relref "/authn-bridge/federation.md" >}}).

## The top level

| key | default | |
|---|---|---|
| `issuer` | | the provider's name and the base of every URL. `https`, or `http` on a loopback host for testing; no query, no fragment; a trailing `/` is dropped |
| `listen` | `127.0.0.1:8080` | the public listener |
| `cert_file`, `key_file` | | serve TLS from these files, re-read when they change; together or not at all |
| `acme` | | serve TLS with a certificate from an ACME CA instead (below); not with `cert_file` |
| `signing_key_file` | | RSA, signs ID tokens (RS256); a P-256 key here is refused |
| `access_token_key_file` | the signing key | a P-256 key that signs access tokens ES256; refused if it is the signing key |
| `retired_signing_key_files` | | keys that signed before: still published at `/jwks`, never used to sign |
| `subject_salt_file` | | at least 32 bytes |
| `code_lifetime` | `1m` | at most ten minutes (RFC 6749 4.1.2) |
| `token_lifetime` | `1h` | access tokens |
| `id_token_lifetime` | `5m` | ID tokens |
| `trusted_proxies` | | addresses or prefixes whose `X-Forwarded-For` is believed |
| `requests_per_minute` | `120` | logins, device grants and ACS posts an address may start a minute; `0` turns the limit off |
| `disabled_file` | | where disabled people and institutions are kept; without it, disabling is refused |
| `certificates_file` | | every certificate and WireGuard key issued; required with `ssh_ca`, `x509_ca` or `wireguard` |

The blocks:

| block | page |
|---|---|
| `saml`, `claims` | [the federation side]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | below, and [tokens]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | below |
| `ssh_ca`, `x509_ca` | [certificates]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`, `wireguard` | [tokens]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [revocation]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`, `metrics` | [the admin API]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | below |

## A client

| key | default | |
|---|---|---|
| `secret_file` | | the client secret, at least 16 characters; absent, a **public** client |
| `redirect_uris` | | compared exactly, except that a loopback URI may change port (RFC 8252); `http` only on loopback |
| `audience` | the client ID | what its access tokens are addressed to |
| `subject` | `public` | or `pairwise`: a different `sub` for this client (OIDC Core 8.1) |
| `name` | the client ID | shown on the device confirmation page |
| `device` | `false` | the device grant (RFC 8628); such a client needs no redirect URI |
| `refresh_lifetime` | off | refresh tokens, and how long after the **login** they end |
| `pkce` | `required` | or `or_nonce`, for a confidential client only: a `nonce` instead of PKCE |
| `id_token_claims` | `false` | copy the released claims into the ID token as well (opkssh needs it) |
| `ssh_certificates`, `ssh_*` | | [SSH certificates]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [NFS client certificates]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | may set the person's [application password]({{< relref "/authn-bridge/tokens.md#application-passwords" >}}) |
| `wireguard_keys`, `wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`, `ssf_subject_format` | | a [Shared Signals receiver]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

A client with no redirect URI must be a device client, an SSF receiver or a
WireGuard gateway, or there is nothing it could do.

## `state`: what a restart must not forget

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

Refresh token families, the refresh tokens and the retired ones, the access
tokens honoured at `/userinfo` and for certificates, the SAML assertions already
accepted and the logins already answered, the SSF streams and their undelivered
events: written through to one table, `bridge_state` (created if missing), and
read at start. A refresh token is kept as its SHA-256, never as itself.
Without the block they live in memory, and a restart logs everybody out.

A login in progress is not in it. It travels in its own cookie, sealed with
AES-256-GCM under a key derived from the subject salt, so the browser can
neither read nor change it.

## `acme`

```hcl
acme {
  accept_terms_of_service = true                     # the operator's agreement; no default
  cache_dir               = "/var/lib/authn-bridge/acme"
  email                   = "noc@example.org"
  # directory_url         = "..."                    # Let's Encrypt by default
  # eab_key_id            = "..."                    # External Account Binding (GÉANT TCS / HARICA)
  # eab_hmac_key_file     = "/etc/authn-bridge/harica-eab.key"
  # http_listen           = ":80"                    # http-01, and a redirect to https
  # directory_ca_file     = "..."                    # a private ACME CA's own TLS
}
```

The certificate is for the issuer's host. `cache_dir` holds private keys, and
the provider refuses to start on one another user could reach or re-point.

## What is refused at startup

Each of these is the output of `authn-bridge check` on a configuration that
asked for it. The server refuses the same configurations.

**An issuer, a redirect, a secret that leak:**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**A name any institution could claim:**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**Something issued that could never be taken back:**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: a certificate nobody can revoke, for more than a week
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**A listener that should not be reachable:**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**A configuration that says one thing twice:**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

The SSH profile's own refusals are on [certificates]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}}),
and the federation's on [the federation side]({{< relref "/authn-bridge/federation.md#what-is-refused" >}}).
