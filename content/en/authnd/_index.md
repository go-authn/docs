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
v0.10.1, which differs from v0.10.0 only by the KDC it embeds (go-authn/kdc
v0.4.2); what is verified and what is not is on the [status]({{< relref "/status.md" >}}) page.

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

People are published as `uid=<name>,ou=people,<base_dn>` (`posixAccount`),
groups as `cn=<name>,ou=groups,<base_dn>` (`posixGroup`, with `memberUid`).
Every entry carries `uid` and `cn`; `sambaNTPassword` and `sshPublicKey` are
added when the person has them and, for the first, when
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) says so.

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
vendorName: go-authn/authnd
vendorVersion: v0.10.0
```

`1.3.6.1.4.1.4203.1.11.1` is the RFC 3062 password modify operation.
`supportedSASLMechanisms: OAUTHBEARER` appears only with an
[`oidc` block]({{< relref "/authnd/tokens.md" >}}).

## Where to go next

| | |
|---|---|
| [Installing it]({{< relref "/authnd/install.md" >}}) | the release binary, the `authnd` account, the systemd unit, upgrades |
| [Where the people come from]({{< relref "/authnd/people.md" >}}) | `user` and `group` blocks, a SQL database, another LDAP directory |
| [`check`]({{< relref "/authnd/check.md" >}}) | read the configuration back before restarting |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` or StartTLS, and `publish_nt_hash` |
| [Changing a password]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, and why the old password is always asked for |
| [A Kerberos realm]({{< relref "/authnd/kerberos.md" >}}) | the keytab, and who can be issued a ticket |
| [A second factor]({{< relref "/authnd/mfa.md" >}}) | a one-time code on the end of the password |
| [A token at the bind]({{< relref "/authnd/tokens.md" >}}) | OIDC over SASL `OAUTHBEARER` |
| [Running it]({{< relref "/authnd/operations.md" >}}) | signals, restarts, what it logs, how to tell it is up |

{{< callout type="info" >}}
**About the transcripts**

Every block of output on these pages was printed by the v0.10.0 release binary
(`authnd-darwin-arm64`) -- v0.10.1 printed the same `check`, byte for byte, on the two
configurations compared -- and by the OpenLDAP and Heimdal clients that ship with
macOS, run on 127.0.0.1 on unprivileged ports, in a scratch directory under
`/tmp`. That
is why the configurations behind them name files by relative paths such as
`etc/authnd/passwords/alice.pw`, and why the password files have names like
`alice.pwin`. The `/etc/authnd` paths in the examples are what an installed
server uses.
{{< /callout >}}
