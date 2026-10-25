---
title: "Status"
weight: 60
description: "Which releases these pages describe, what each release added, and what is not implemented yet."
tags: [status, releases]
---

These pages are documentation version **0.5**, and describe:

| program | release | module |
|---|---|---|
| authnd | **v0.12.0** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.1** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.4** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.7** | `github.com/go-authn/sshcert` |

The libraries' versions are on [their own page]({{< relref "/libraries/_index.md" >}});
ldap is **v0.9.0**, with schemas in HCL2 and the `ldapschema` converter, and
directory **v0.15.0**, with declared object classes. authnd
v0.12.0 embeds ldap v0.9.0 and directory v0.15.0.
A new minor version of any program above is a new documentation version, so
the pages a reader finds under `/docs/0.5/` keep describing what they
installed; those of the previous releases stay under `/docs/0.1/`,
`/docs/0.2/`, `/docs/0.3/` and `/docs/0.4/`.

{{< callout type="warning" >}}
**Security: use authnd v0.12.0, not v0.11.1**

authnd verifies certificates (`x509.Certificate.Verify`, reached from `main`
per `govulncheck`), and Go 1.27.2's crypto/x509 did not distrust the
compromised intermediate certificates that GO-2026-6809 names. **v0.11.1's
release binaries were built with Go 1.27.2 and are affected.** v0.12.0 is
built with Go 1.27.3 and its `go` directive is 1.27.3, so `go install`
switches to the fixed toolchain by itself; `govulncheck` under 1.27.3 reports
no vulnerabilities. Its release binary reports `go1.27.3` in
`go version -m`. See [the upgrade note]({{< relref "/authnd/_index.md" >}}).
{{< /callout >}}

## What each release added

Each line is the change a release was cut for. Releases that only updated
dependencies are left out, except those this documentation version describes.

### authnd

| | |
|---|---|
| v0.1.0 | an LDAP server for people who are somewhere else: a file, a SQL database, another directory |
| v0.2.0 | a second factor, over a protocol with one field |
| v0.5.0 | password changes that touch exactly one identity; a reload with no race; the KDC sees changes |
| v0.6.0 | the security fixes of oidc, directory, ldap, totp and mfa |
| v0.7.0 | the old password is required to change one; secrets are compared as fixed-length digests |
| v0.8.2 | a code counts only behind the right password; a reader is keyed by its configured DN |
| v0.9.0 | built and tested with Go 1.27.1, pinned rather than `stable` |
| v0.9.2 | release binaries, `SHA256SUMS` and build provenance on every tag |
| v0.9.3 | binaries built outside the checkout; each must report the tag exactly |
| v0.9.4 | a `SIGHUP` no longer ends authnd: it is logged, and nothing is reloaded |
| v0.9.5 | the release checks **every** binary's build information, not one |
| v0.9.6 | `check` says why each person cannot be issued a ticket |
| v0.10.0 | `check` opens the certificate and the keytab, as the server does; it names who cannot bind with a password, and who a token still admits; the listening line comes after the realm opens |
| v0.10.1 | go-authn/kdc v0.4.2: a `till` of 19700101000000Z gets the longest ticket, not one expired in 1970 |
| v0.10.2 | go-authn/directory v0.12.0: an empty group is published as a `posixGroup` without `memberUid` |
| v0.11.0 | [standard-schema entries]({{< relref "/authnd/entries.md" >}}), each held to the schema served at `cn=Subschema`; `attributes`, `users_attributes` and `groups_attributes`; `(uidNumber>=1000)` compares integers. ⛔ `publish_nt_hash` needs a [`samba` block]({{< relref "/authnd/tls.md#the-samba-block" >}}), and a consumer filtering on `posixAccount` or `posixGroup` sees fewer entries |
| v0.11.1 | the startup line names only the sources somebody is served from: with no `user` block it no longer names the configuration file |
| v0.12.0 | [site schemas]({{< relref "/authnd/schemas.md" >}}): `schema_files` (OpenLDAP `.schema` and cn=config LDIF, as published; a redefinition is refused, even identical, as slapd does) and a `schema { }` block; auxiliary classes declared per source with `object_classes`, validated at startup and published with their superclasses; `check` reports the files, the declarations, the classes left off a person for a missing MUST, and groups two sources disagree on. ⛔ Built with Go 1.27.3: v0.11.1's binaries (Go 1.27.2) are affected by GO-2026-6809 |

### authn-bridge

| | |
|---|---|
| v0.1.0 | an OpenID Connect provider in front of a SAML federation |
| v0.2.0 | the device grant, SSH certificates, application passwords, OpenPubkey |
| v0.3.0 | an admin API (`bridge.admin.v1`), and `/healthz`, `/readyz`, `/metrics` |
| v0.4.0 | ES256 access tokens |
| v0.5.0 | TLS through go-authn/servercert, shared with go-fileshare |
| v0.6.0 | certificates that can be revoked: an SSH KRL, and X.509 for NFS with a CRL |
| v0.7.0 | state that survives a restart: refresh tokens and honoured access tokens |
| v0.8.0 | a Shared Signals transmitter: CAEP `session-revoked` |
| v0.9.0 | the fixes of an adversarial review of v0.8.1 |
| v0.10.0 | revocation lists to be checked anywhere: a signed KRL, an expiry, an ETag of the content |
| v0.10.2 | a CRL number for every issue; never an issue dated before the last |
| v0.11.0 | groups held to their identity provider; disabling by identity; a bridge-only audience |
| v0.12.0 | a login in progress lives in its sealed cookie, not in memory |
| v0.13.0 | a confidential client may protect its code with the nonce (RFC 9700 2.1.1) |
| v0.16.0 | `max_age` asks for a new authentication only when the last is too old |
| v0.16.3 | a second review: every spelling revoked, disabling by `sub`, no replay across restarts |
| v0.17.0 | WireGuard keys, registered by people and listed for a gateway |
| v0.18.0 | an ID token without the person's claims; go-authn/saml v0.4.0 |
| v0.19.0 | the EuroHPC SSH CA profile, opt-in per client |
| v0.19.3 | release binaries, `SHA256SUMS` and build provenance on every tag |
| v0.20.0 | the command is `authn-bridge`; a hardened systemd unit and an install guide |
| v0.20.1 | comments and a refusal message that were no longer true; the README lists everything `RevokePerson` revokes |
| v0.21.0 | [RFC 8707 resource indicators]({{< relref "/authn-bridge/resources.md" >}}): a client whose `audience` names several resource servers can ask for a token addressed to one. Tagged an hour before v0.20.1, which has them too, and without v0.20.1's corrections |
| v0.21.1 | golang.org/x/net v0.60.0, for its HTTP/2 advisories, and Go 1.27.2; v0.20.1's corrections again; placeholder domains in RFC 2606 names |
| v0.22.0 | the access token no longer carries `auth_time` or `acr` (the ID token still does), so that an ES256 token fits OpenSSH's 1023 characters up to the 99th percentile of RENATER's scopes |
| v0.22.1 | `resource` may be repeated at the authorization endpoint, for a grant bounded to several servers; refused at `device_authorization` rather than ignored ([resource indicators]({{< relref "/authn-bridge/resources.md" >}})) |
| v0.23.0 | `access_token_groups = false`: a client whose tokens are pasted into ssh carries no groups ([tokens]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})) |
| v0.23.1 | dependencies only: go-jose/v4 v4.1.6, golang.org/x/crypto v0.58.0, golang.org/x/net v0.61.0; go-authn/directory v0.12.0, revocation v0.6.3, saml v0.4.1, servercert v0.5.1, sshcert v0.1.6 |

### authn-revokd

| | |
|---|---|
| v0.1.0 | signed, expiring revocation lists: the protocol, the library, and revokd (agent and mirror) |
| v0.2.0 | the fixes of an adversarial review |
| v0.2.1 | each CA's list merged with its own key revocations; a CRL's signature checked before it is parsed |
| v0.3.0 | key revocations scoped; failing closed per CA; the state directory's owner checked |
| v0.5.0 | release binaries, `SHA256SUMS` and build provenance on every tag |
| v0.6.0 | the command is `authn-revokd`; systemd units and an install guide; `SIGHUP` syncs at once |
| v0.6.1 | `-version` prints on standard output |
| v0.6.2 | `-once` tells a failed fetch apart from a lapsed list; a list signed by another key is no longer called a race; `-help` exits 0 |
| v0.6.3 | placeholder domains in RFC 2606 names, in the examples and the documentation; no change in behaviour |
| v0.6.4 | dependencies only: golang.org/x/crypto v0.58.0 |

### sshcert

| | |
|---|---|
| v0.1.0 | the domain-grant extension, and a fail-closed `sshcert-authorize` |
| v0.1.2 | release binaries, `SHA256SUMS` and build provenance on every tag |
| v0.1.4 | the release checks every binary's build information |
| v0.1.5 | `-version` prints the module version of a `go install` build, not `dev` |
| v0.1.6 | placeholder domains in RFC 2606 names, in the documentation; no change in behaviour |
| v0.1.7 | dependencies only: golang.org/x/crypto v0.58.0 |

### The libraries

The library releases this documentation version was made for; each
library's page says what earlier ones changed.

| | |
|---|---|
| directory v0.13.0 | [attributes]({{< relref "/libraries/directory.md#attributes" >}}): what describes somebody and proves nothing, apart from credentials, with the names that can never be one; `attributes` in `user` and `group` blocks, `users_attributes` and `groups_attributes` queries, ldapdir's `attributes` and `group_attributes` |
| directory v0.14.0 | ⛔ ldapdir's [defaults]({{< relref "/libraries/directory.md#ldapdir-defaults" >}}) read `account` and `uidObject` people and `groupOfNames` groups, which widens what an institution's directory gives; a `member` DN maps only to a person the source imported |
| directory v0.15.0 | [object classes]({{< relref "/libraries/directory.md#object-classes" >}}), declared and never inferred: `object_classes` and `group_object_classes` in `users` blocks, `object_classes` in `user` and `group` blocks, `WithObjectClasses` for sqldir and `Config.ObjectClasses` for ldapdir; the first source that declares a group's classes decides; `sqldir.ClosesDB` |
| kdc v0.4.3 | dependencies only: go-authn/directory v0.12.0 as its minimum |
| keyfactor v0.4.2 | dependencies only: go-authn/fido v0.6.2 and golang.org/x/crypto v0.58.0 as its minimums |
| krb5 v0.3.1 | tested with Go 1.27.2; neither the code nor `go.mod` changed |
| krl v0.6.1 | dependencies only: golang.org/x/crypto v0.58.0; tested with Go 1.27.2 |
| ldap v0.8.0 | [package `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) and `Server.Schema`: `cn=Subschema` (RFC 4512 §4.2), `Validate`, RFC 4517 matching rules; `uidNumber` and `gidNumber` order as integers; a paged search keeps to the requested attributes |
| ldap v0.9.0 | [schemas in HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): package `schema/hclschema` and the `ldapschema` command (`to-hcl`, `to-schema`, `check`) between OpenLDAP `.schema`, cn=config LDIF and HCL2; the readers read files as slapd does; DIT content and structure rules, name forms, `include` and `X-SUBST` are not supported |
| oidc v0.4.1 | tested with Go 1.27.2; neither the code nor `go.mod` changed |
| servercert v0.5.2 | tested with Go 1.27.2; neither the code nor `go.mod` changed |
| totp v0.4.2 | tested with Go 1.27.2; neither the code nor `go.mod` changed |
| wireguard v0.1.1 | tested with Go 1.27.2; neither the code nor `go.mod` changed |

## Not implemented yet

- **Writes through LDAP**, beyond a person changing their own password. authnd
  answers a modify of one's own `userPassword` and the RFC 3062 password modify
  operation (what `ldappasswd` sends), both only with the current password, and
  nothing else: add, delete and modifyDN exist in go-authn/ldap and are
  deliberately not wired (`server.go`). The library carries a modify as an
  ordered list (RFC 4511 4.6) and answers the read entry controls (RFC 4527), so
  the shape is there; what is missing is the policy of who may write what.
- **A second factor inside Kerberos**: OTP pre-authentication (RFC 6560) in
  FAST (RFC 6113). Until it exists, a `kerberos` block and an `mfa` block
  cannot both be configured.
- **RC4-HMAC**: the realm issues aes256-cts-hmac-sha1-96 only, so a person
  known only by an NT hash cannot be issued a ticket. This is a choice (RC4 is
  deprecated by RFC 8429), not a gap waiting to be filled.
