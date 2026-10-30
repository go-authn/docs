---
title: "Status"
weight: 60
description: "Which releases these pages describe, what each release added, and what is not implemented yet."
tags: [status, releases]
---

These pages are documentation version **0.6**, and describe:

| program | release | module |
|---|---|---|
| authnd | **v0.13.3** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.4** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.6** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

The libraries' versions are on [their own page]({{< relref "/libraries/_index.md" >}});
ldap is **v0.11.3**, with DIT content rules, name forms and DIT structure
rules read, enforced and published, a typed `BuildError` for a schema that does
not build, schemas in HCL2 and the `ldapschema` converter, and
directory **v0.15.0**, with declared object classes. authnd
v0.13.3 embeds ldap v0.11.3 and directory v0.15.0.
A new minor version of any program above is a new documentation version, so
the pages a reader finds under `/docs/0.6/` keep describing what they
installed; those of the previous releases stay under `/docs/0.1/`,
`/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/` and `/docs/0.5/`.

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

{{< callout type="warning" >}}
**Security: take authn-bridge v0.23.3 and authn-revokd v0.6.5**

Under Go 1.27.2, `govulncheck` reports GO-2026-6809 in both programs: `crypto/x509`'s `Certificate.Verify` did not reject known compromised intermediate certificates. It is fixed in Go 1.26.10 and 1.27.3. **Release binaries built with an older Go are affected.** v0.23.3 and v0.6.5 are built with Go 1.27.3 and their `go` directive is 1.27.3, so `go install` switches to the fixed toolchain by itself; their release binaries report `go1.27.3` in `go version -m`. sshcert is not affected and has no new release.
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
| v0.12.1 | a schema file or block that does not build is refused at the position go-authn/ldap v0.10.0's `BuildError` carries, with a column (`site.schema:6:` becomes `site.schema:6:1:`); the message ends with the kind of refusal, and a duplicate says where its first definition is |
| v0.12.2 | release binaries are linked with `-ldflags="-w"` instead of `-s -w`: the symbol table is kept, so `govulncheck -mode binary` is precise instead of reporting vulnerabilities in code that is not linked; about 9 % larger (18.8 MB to 20.5 MB on darwin/arm64) |
| v0.12.3 | go-authn/ldap v0.10.1: `schema_files` are read in linear time. ⛔ Up to v0.12.2, a large schema file of short continuation lines (4 MiB: about three minutes) stalled startup: a denial of service by a file you do not control |
| v0.12.4 | go-authn/ldap v0.10.2: the DESC values of 13 RFC 2307 definitions in `cn=Subschema` (`uidNumber`, `gidNumber`, `ipHostNumber`, `ipNetworkNumber`, `ipNetmaskNumber`, `macAddress` and the classes `ipService`, `ipProtocol`, `oncRpc`, `ipHost`, `ipNetwork`, `ieee802Device`, `bootableDevice`) no longer carry the indentation of the RFC's page layout: `DESC 'An integer uniquely identifying a user in an administrative domain'`, not `... in an         administrative domain'` |
| v0.13.0 | [DIT content rules, name forms and DIT structure rules]({{< relref "/authnd/schemas.md#rules" >}}) (go-authn/ldap v0.11.0): `schema_files` and the `schema { }` block accept the three kinds, and authnd enforces them. A content rule shapes each entry: an auxiliary class its `AUX` does not list is left off (with the attributes only it allowed), a `NOT` attribute is dropped, an entry missing a `MUST` is left out; each is logged and reported by `check`. With an active structure rule, the tree (suffix, `ou=people`, `ou=groups`, the `uid` or `cn` RDN) is checked at startup and by `check`, and a violation **refuses to start**, all refusals at once, never echoing a secret; an entry no rule places is left out. ⛔ A `schema { }` string that is not valid UTF-8 is now refused. Publishing 10,000 people makes 416 allocations per entry with the rules against 265 without (times measured under load, not reliable) |
| v0.13.1 | Performance only, with go-authn/ldap v0.11.1: publishing 10,000 people (`BenchmarkPublish10k`, `-cpu 1`) makes 364 allocations per entry with the rules and 239 without, against 416 and 265 at v0.13.0, and 102.5 MiB per run with the rules against 147.5. Times were measured at a load of 10 to 16 and are not reliable |
| v0.13.2 | Performance only, with go-authn/ldap v0.11.2: `Validate` makes 12 allocations instead of 76 for a ten attribute entry; publishing 10,000 people (`BenchmarkPublish10k`, `-cpu 1`) makes 128 allocations per entry with the rules and 85 without, against 364 and 239 at v0.13.1, and 54.8 MiB per run with the rules against 102.5. Times (load 8 to 11): about 90 ms against 158 ms with the rules |
| v0.13.3 | Performance only, with go-authn/ldap v0.11.3: an entry `unmet` has just validated is not validated again by `validated` when it has not changed; publishing 10,000 people (`BenchmarkPublish10k`, `-cpu 1`) makes 97 allocations per entry with the rules and 69 without, against 128 and 85 at v0.13.2 (-24 % and -19 %); about 66 ms and 36 ms (load 4.8) |

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
| v0.23.2 | security: go-authn/oidc v0.4.2, which refuses an `nbf` outside the int64 range (a token that was not yet valid was accepted) and an RSA key with `e = 0` (it was parsed); go-authn/wireguard v0.1.2 |
| v0.23.3 | built with Go 1.27.3, for GO-2026-6809 (`crypto/x509`: `Certificate.Verify` did not reject known compromised intermediate certificates); the `go` directive is 1.27.3; no change in behaviour |
| v0.23.4 | release binaries are linked with `-w` instead of `-s -w`, so the symbol table is kept for a precise `govulncheck -mode binary`; no change in behaviour |

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
| v0.6.5 | built with Go 1.27.3, for GO-2026-6809 (`crypto/x509`: `Certificate.Verify` did not reject known compromised intermediate certificates); the `go` directive is 1.27.3; no change in behaviour |
| v0.6.6 | release binaries are linked with `-w` instead of `-s -w`, so the symbol table is kept for a precise `govulncheck -mode binary`; no change in behaviour |

### sshcert

| | |
|---|---|
| v0.1.0 | the domain-grant extension, and a fail-closed `sshcert-authorize` |
| v0.1.2 | release binaries, `SHA256SUMS` and build provenance on every tag |
| v0.1.4 | the release checks every binary's build information |
| v0.1.5 | `-version` prints the module version of a `go install` build, not `dev` |
| v0.1.6 | placeholder domains in RFC 2606 names, in the documentation; no change in behaviour |
| v0.1.7 | dependencies only: golang.org/x/crypto v0.58.0 |
| v0.1.8 | release binaries are linked with `-w` instead of `-s -w`, so the symbol table is kept for a precise `govulncheck -mode binary`; no change in behaviour |
| v0.1.9 | built with Go 1.27.3; no change in behaviour |

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
| ldap v0.9.0 | [schemas in HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): package `schema/hclschema` and the `ldapschema` command (`to-hcl`, `to-schema`, `check`) between OpenLDAP `.schema`, cn=config LDIF and HCL2; the readers read files as slapd does; DIT content and structure rules, name forms, `include` and `X-SUBST` are not supported (v0.11.0 supports the rules) |
| ldap v0.10.0 | [a typed `*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}) for a definition `Build` refuses, matched with `errors.As`: `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos` (file:line:column where the definition starts, also for folded or base64 LDIF and HCL), and `Ref`, `RefOID` and `RefPos` for the other definition; every definition read carries a `Pos`; "object classes" in a message |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) is linear in the number of continuation lines (it was quadratic: a 4 MiB file took about three minutes) and no longer copies and splits the whole file to read its first line; `schema.Format` folds lines over 2000 bytes, which slapd and `Read` refuse; the strict parser is about 2.6 times faster (147 allocations instead of 498 on `cosine.schema`, measured under load) |
| ldap v0.10.2 | the DESC of 13 RFC 2307 definitions in the embedded schema (`schema.Standard()`) is on one line: it carried the indentation of the RFC's page layout, which the reader keeps inside quotes as slapd does, so the subschema a server published had runs of spaces in it; a test now checks every embedded DESC for that and, where the same OID is defined, against OpenLDAP's `core`, `cosine`, `inetorgperson` and `nis` schemas |
| ldap v0.11.0 | [DIT content rules, name forms and DIT structure rules]({{< relref "/libraries/ldap.md#rules" >}}) (RFC 4512 §4.1.6, §4.1.7) read from `.schema` and LDIF, written by `Format`, carried through HCL (`dit_content_rule`, `name_form`, `dit_structure_rule`) and `ldapschema`, checked by `Build`, enforced by `Validate` (content rules: AUX, MUST, MAY, NOT; name forms: the RDN; structure rules: `GoverningStructureRule`) and published at `cn=Subschema` only when present; `ValidateOptions{StrictAuxiliary}` gives RFC 4512 §2.4.3. ⛔ slapd implements content rules only, so `Format` writes `nameform` and `ditstructurerule` keywords it refuses; an `OBSOLETE` rule is inactive where slapd refuses the entry; libldap cannot read a structure rule's `SUP`. `hclschema.Decode` refuses a string that is not UTF-8 |
| ldap v0.11.1 | Performance only, no change of result: a string of printable ASCII is prepared for the string matching rules (RFC 4518) with at most one allocation, none when nothing changes, and the DN parser makes 6 allocations instead of 11 for a four-RDN DN. The results are those of v0.11.0, checked against its code on every string of one or two bytes below 0x80 and by a differential fuzzer |
| ldap v0.11.2 | Performance only, no change of result: `Validate` allocates 12 times for a ten attribute entry instead of 76 (lookups without a lower-case copy, descriptions not split and re-joined, in-place sets instead of maps). The results are those of v0.11.1, checked against a copy of its `Validate` on random entries under the standard schema and a rules schema, and by a differential fuzzer |
| ldap v0.11.3 | Performance only, no change of result: `GoverningStructureRule` allocates 5 times instead of 12 for an account (it reads only the RDN's types), and the DN parser 3 times instead of 6 for a four-RDN DN. The results are those of v0.11.2, checked against a copy of its `GoverningStructureRule` on random entries and every superior rule, and by a differential fuzzer |
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
