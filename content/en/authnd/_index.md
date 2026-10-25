---
title: "authnd, an LDAP server for people who are somewhere else"
linkTitle: "authnd"
weight: 10
description: "An LDAP directory, and optionally a Kerberos realm, over people held in a configuration file, a SQL database or another directory."
tags: [authnd, ldap]
---

**A site's people are already in a database, a file or another directory. The
things that want to authenticate them speak LDAP.** authnd is the front: it
binds and searches over [go-authn/directory]({{< relref "/libraries/_index.md" >}})'s
sources, so what a database holds can be read by anything that knows how to
ask a directory. Pure Go, `CGO_ENABLED=0`, one binary. These pages describe
v0.12.0, whose entries follow the standard schemas and pass the schema it
serves at `cn=Subschema`, which a site extends with its own
([SUPANN, eduPerson]({{< relref "/authnd/schemas.md" >}})), with go-authn/ldap v0.9.0 and
go-authn/directory v0.15.0 under it; what is verified and what is not is on
the [status]({{< relref "/status.md" >}}) page.

{{< callout type="warning" >}}
**Upgrading from v0.11.x**

- ⛔ **Security: take v0.12.0, not v0.11.1.** v0.11.1's release binaries were
  built with Go 1.27.2, whose crypto/x509 does not distrust the compromised
  intermediate certificates GO-2026-6809 names, and authnd verifies
  certificates. v0.12.0 is built with Go 1.27.3, and its `go` directive is
  1.27.3, so `go install` switches to the fixed toolchain by itself.
- A configuration that does not use the new keys publishes what v0.11.1
  published: a class is declared, never inferred, so without `object_classes`
  nothing changes.
- New, all optional: [`schema_files` and a `schema` block]({{< relref "/authnd/schemas.md" >}})
  add a site's definitions to the schema served, and `object_classes` and
  `group_object_classes` declare the auxiliary classes a source's people and
  groups carry. A definition that redefines one already there is refused,
  even word for word, as slapd refuses it.
- `check` and the startup log say which files and blocks were loaded, what each
  source declares, which classes were left off a person for lack of a
  MUST, and which groups two sources disagree about.

Run `authnd check` with the new binary before the restart, as
[install]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}) says.
{{< /callout >}}

{{< callout type="warning" >}}
**Upgrading from v0.10.x**

- `publish_nt_hash = true` now needs a [`samba` block]({{< relref "/authnd/tls.md#the-samba-block" >}}),
  or authnd does not start.
- A person without `uidNumber`, `gidNumber` and `homeDirectory` is no longer
  a `posixAccount`, and a group without a `gidNumber` no longer a
  `posixGroup`, so a consumer filtering on those classes sees fewer entries:
  see [the entries]({{< relref "/authnd/entries.md" >}}).
- A `users "ldap"` block reads more of the directory behind it by default:
  see [people]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

`authnd check` with the new binary says all three before the restart.
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## The smallest configuration

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

People are published as `uid=<name>,ou=people,<base_dn>`, groups as
`cn=<name>,ou=groups,<base_dn>`. What each entry *is* follows from what its
source gave: a person is an `account`, or an `inetOrgPerson` when there is
an `sn`, and a `posixAccount` only with `uidNumber`, `gidNumber` and
`homeDirectory`; every person is a `uidObject`. A group is a `posixGroup`
(with `memberUid`) when it has a `gidNumber`, otherwise a `groupOfNames`
(with `member` DNs), or an `organizationalRole` when it is also empty.
`sshPublicKey` is added when the person has keys, and `sambaNTPassword` when
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) says
so and a SID can be given. Every entry passes the schema served at
`cn=Subschema` before it is published: see
[the entries and the schema]({{< relref "/authnd/entries.md" >}}). Up to
v0.10.2 every person was a `posixAccount` and every group a `posixGroup`,
whatever they had.

`--config` (`-c`) takes a file or a directory and may be repeated; a directory
is every `.hcl` file in it, read in name order and merged into one
configuration. A configuration with no `base_dn`, or with nobody in it, does
not start.

## Who may bind, and who may read

An LDAP server is asked to prove people, so its refusals are the design.
These are answers from the v0.10.0 release binary to OpenLDAP's own client:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| request | answer | why |
|---|---|---|
| empty name, empty password (RFC 4513 §5.1.1, anonymous) | success | it says "I am nobody", which is true, and a client sends it before it has discovered anything |
| a **name** and an empty password (§5.1.2, unauthenticated) | `unwillingToPerform` | it names somebody and proves nothing; §5.1.2 asks for exactly this code. `invalidCredentials` would tell a person their password was wrong |
| a wrong password, or a name nobody here has | `invalidCredentials` | the two are not told apart |
| a search by anybody but a `reader` | `insufficientAccessRights` | binding proves who you are; reading everybody is a separate thing to be allowed |
| `add`, `delete`, `modifyDN` | `unwillingToPerform` | no handler is wired for them; the one write is [a person's own password]({{< relref "/authnd/passwords.md" >}}) |

A `reader` is a service account with a bind DN and `password` or
`password_file`; a reader with neither is refused at startup (*a reader that
proves nothing is anonymous search with extra steps*). Without any reader,
nothing may search, and `check` says so.

The root DSE is answered to an anonymous client, as discovery needs:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.12.0
```

`1.3.6.1.4.1.4203.1.11.1` is the RFC 3062 password modify operation.
`subschemaSubentry` names the [schema]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}),
which is answered to an anonymous client as well.
`supportedSASLMechanisms: OAUTHBEARER` appears only with an
[`oidc` block]({{< relref "/authnd/tokens.md" >}}).

## Where to go next

| | |
|---|---|
| [Installing it]({{< relref "/authnd/install.md" >}}) | the release binary, the `authnd` account, the systemd unit, upgrades |
| [Where the people come from]({{< relref "/authnd/people.md" >}}) | `user` and `group` blocks, a SQL database, another LDAP directory |
| [The entries and the schema]({{< relref "/authnd/entries.md" >}}) | what each person and group is published as, `cn=Subschema`, attributes, what is dropped or withheld |
| [Site schemas]({{< relref "/authnd/schemas.md" >}}) | `schema_files`, the `schema` block and `object_classes`: SUPANN, eduPerson or a site's own attributes |
| [`check`]({{< relref "/authnd/check.md" >}}) | read the configuration back before restarting |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` or StartTLS, and `publish_nt_hash` |
| [Changing a password]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, and why the old password is always asked for |
| [A Kerberos realm]({{< relref "/authnd/kerberos.md" >}}) | the keytab, and who can be issued a ticket |
| [A second factor]({{< relref "/authnd/mfa.md" >}}) | a one-time code on the end of the password |
| [A token at the bind]({{< relref "/authnd/tokens.md" >}}) | OIDC over SASL `OAUTHBEARER` |
| [Running it]({{< relref "/authnd/operations.md" >}}) | signals, restarts, what it logs, how to tell it is up |

{{< callout type="info" >}}
**About the transcripts**

The root DSE, the `--version` lines and everything on the
[site schemas]({{< relref "/authnd/schemas.md" >}}) page were printed by the
v0.12.0 release binary (`authnd-darwin-arm64`, checked against `SHA256SUMS`;
`go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.0`,
`vcs.modified=false`). The other startup lines were printed by the v0.11.1
release binary (`mod github.com/go-authn/authnd v0.11.1`,
`vcs.modified=false`), and so was every other command shown in the same
transcript as a startup line; v0.11.1 changed nothing but that line, and
v0.12.0's changelog changes nothing for a configuration that declares no
schema file, block or class, so they were not run again. Every `check` table, the entries read
back with `ldapsearch`, `cn=Subschema` and the `samba` refusals were printed
by the v0.11.0 release binary (`mod github.com/go-authn/authnd v0.11.0`,
`vcs.modified=false`). So were the configuration refusals on these pages,
which v0.11.0 printed byte for byte as v0.10.0 had. The other binds, `kinit`s,
password changes and token exchanges were printed by the v0.10.0 release
binary and were not run again, since neither v0.11.0's nor v0.11.1's release
notes change any of them. All of them were asked by the OpenLDAP and
Heimdal clients that ship with macOS, on 127.0.0.1 on unprivileged ports, in
a scratch directory under `/tmp`. That
is why the configurations behind them name files by relative paths such as
`etc/authnd/passwords/alice.pw`, and why the password files have names like
`alice.pwin`. The `/etc/authnd` paths in the examples are what an installed
server uses.
{{< /callout >}}
