---
title: "Where the people come from"
linkTitle: "People"
weight: 20
description: "user and group blocks, a SQL database, another LDAP directory: how each is written, the order they are asked in, and what each lets a person do."
tags: [authnd, configuration, sql, ldap]
---

A `user` block is the whole directory for a small site, or the service
accounts a big one keeps out of its database. A site whose people are already
in a database or in LDAP should not copy them into a second place that goes
stale, so a `users` block reads them where they are. The `users` block is
go-authn/directory's `hcldir`, the same one
[go-fileshare](https://github.com/go-fileshare/fileshare) reads: one
directory is described the same way to both.

## Written in the configuration

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| field | what it is |
|---|---|
| `password` | the password, inline |
| `password_file` | the same, read from a file (surrounding white space removed) |
| `nt_hash` | `MD4(UTF16LE(password))`, 32 hex characters — for a site that holds that and not the password |
| `totp_secret` | a base32 one-time-code secret, at least 128 bits; see [a second factor]({{< relref "/authnd/mfa.md" >}}) |
| `authorized_keys` | `authorized_keys` lines, published as `sshPublicKey` |
| `authorized_keys_file` | the same, from a file |
| `attributes` | from v0.11.0, what describes the person and proves nothing — `sn`, `uidNumber`, `gidNumber`, `homeDirectory`, `mail`… — as a map of strings or lists of strings; a `group` block takes it too. They decide what the entry is published as: see [the entries]({{< relref "/authnd/entries.md#adding-attributes" >}}) |
| `object_classes` | from v0.12.0, the auxiliary classes this person (or, in a `group` block, this group) is published with, such as `["siteMember"]`: declared, never inferred, and defined in a [site schema]({{< relref "/authnd/schemas.md#object-classes" >}}) |

Refused at startup, naming the person:

- `password` and `password_file` together — say which one;
- `password` and `nt_hash` together — the hash is derived from the password,
  so two of them can disagree;
- `authorized_keys` and `authorized_keys_file` together;
- an `nt_hash` that is not 32 hex characters, an `authorized_keys` line that
  does not parse, a `totp_secret` under 128 bits;
- the same `user` or `group` twice, and a `group` with no members.

A group member that no source knows is refused too, which is what catches a
typo before it silently grants nothing:

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**An `nt_hash` alone cannot bind**

A person written with only `nt_hash` is published, can be handed to an SMB
server through `sambaNTPassword`, and **cannot bind to authnd itself**: an
LDAP simple bind sends the password, and an NT hash is not a way to check
one here. bob below has only an NT hash, and the hash is that of the
password sent:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check` says so, after the tables:

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```

**Why it is refused, by design.** An NT hash is `MD4(UTF16LE(password))`,
unsalted and fast (MS-NLMP §3.3.1, NTOWFv1). Accepting it to check LDAP binds
would widen what a leaked hash opens, from SMB to every application that binds
through authnd. Kerberos refuses these people for a related reason: the NT hash
is the RC4-HMAC key (RFC 4757 §2), and the realm issues AES only. This is a
deliberate decision, not a missing feature, and there is no option to change it.

**What to do instead.** When migrating from a directory that holds only NT
hashes (Samba, an exported AD), give each person a real password or a password
check in their source: a password reset, or a `users "ldap"` source whose
upstream directory checks the password itself. Do not keep the NT hash as the
only credential.
{{< /callout >}}

## In a SQL database

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**The queries are yours**, because a site's people are already in that
site's shape. The `users` query's columns are read **by position**: a name,
then any of a password, an NT hash, SSH keys (one per line) and a
one-time-code secret, in that order — up to five columns. A NULL is a
credential that person does not have. A password column is compared as it is
stored: authnd has no setting for a hashed column. The `groups` query returns
a group name and a member, one row per membership.

Two more queries, optional, read attributes **by column alias** rather than
by position: `users_attributes` (a name, then one column per attribute) and
`groups_attributes` (a group, then the same). An unquoted alias is lower-cased
by PostgreSQL. See [the entries]({{< relref "/authnd/entries.md#in-a-sql-database" >}}).

**The classes of what a `users` block gives** are declared beside its queries
(from v0.12.0, the same two keys in a `users "ldap"` block):

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]   # every person this block gives
  group_object_classes = ["supannGroupe"]                # every group
}
```

Each must be an AUXILIARY class that the schema served defines (the standard
schema, or [`schema_files` and a `schema` block]({{< relref "/authnd/schemas.md" >}})),
and not one authnd derives itself. A person missing a MUST of a declared class
is published without it, and `check` says so.

`driver` accepts `postgres` (or `postgresql`, `pgx`), `mysql` (or `mariadb`)
and `sqlite` (or `sqlite3`). The database is reached at startup, before
anything listens, so one that is not answering stops the server where
somebody is watching:

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

PostgreSQL on the same machine through its socket and peer authentication
needs no password in the DSN: `host=/run/postgresql dbname=authnd user=authnd`.
SQLite in the state directory: `file:/var/lib/authnd/people.db`.

A key that belongs to the other kind of block is refused rather than ignored:

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## In another LDAP directory

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url` and `base_dn` are required. Where the people and groups are, and which
attributes name them:

| key | default |
|---|---|
| `user_filter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))` |
| `group_attribute` | `cn` |
| `group_member_attribute` | none: `memberUid` (names) **and** `member` (DNs); set, it is the one attribute read |
| `totp_attribute` | none: there is no standard attribute, and a guess would read nothing while looking like it had looked |
| `attributes`, `group_attributes` | none: the attributes to copy from each person's entry and each group's, such as `["mail", "uidNumber", "homeDirectory"]` and `["gidNumber"]` ([the entries]({{< relref "/authnd/entries.md#adding-attributes" >}})) |
| `object_classes`, `group_object_classes` | none: from v0.12.0, the auxiliary classes every person and every group read from this directory is published with ([site schemas]({{< relref "/authnd/schemas.md#object-classes" >}})); the classes the upstream entries carry are never copied |
| `start_tls` | `false` |

A `member` DN counts only when it is the DN of an entry the people search
returned: a DN outside them, or naming nobody, maps to nobody, and the name
is never read out of the DN. `sambaNTPassword` and `sshPublicKey` are read
under those names.

{{< callout type="warning" >}}
**From v0.11.0 the defaults read more of an institution's directory**

The block is go-authn/directory's, and directory v0.14.0, which authnd
v0.11.0 embeds, widened its defaults: up to v0.10.2, `user_filter` was
`(objectClass=posixAccount)`, `group_filter` `(objectClass=posixGroup)` and
`group_member_attribute` `memberUid`. A directory holding `account` or
`uidObject` entries that are not posixAccounts — service accounts, hosts
named by uid, people imported from elsewhere — now gives them to authnd, and
each can be checked by a bind; its `groupOfNames` groups become groups here.
To keep exactly the old set, write the old values:

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

Two things are refused before anything is opened:

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

`ldap://` to a loopback address and `ldapi://` are accepted: nobody is on
the way.

A directory behind this one **checks** passwords by binding to it; it does
not hand them over. Here one authnd fronts another, under a different base;
the one behind is the [`check`]({{< relref "/authnd/check.md#a-configuration-that-can-be-served" >}})
example, served on 3893:

```hcl
listen  = "127.0.0.1:3894"
base_dn = "dc=example,dc=net"

users "ldap" {
  url                = "ldap://127.0.0.1:3893"
  base_dn            = "ou=people,dc=example,dc=org"
  group_base_dn      = "ou=groups,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "etc/authnd/reader.pw"
}

user "svc-backup" { password_file = "etc/authnd/svc-backup.pw" }
```

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS        WITH
alice       ldap://127.0.0.1:3893   a password check  account, uidObject  uid
bob         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
dora        ldap://127.0.0.1:3893   a password check  account, uidObject  uid
eli         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
svc-backup  the configuration file  a password        account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
svc-backup has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Every person the directory behind publishes is an `account` and every group
a `groupOfNames`, since none has POSIX attributes: the defaults read them,
and the groups' `member` DNs map to the people imported. With the defaults
up to v0.10.2, `(objectClass=posixAccount)` would have matched none of them.

*A password check* is enough for a bind, and is never enough for a
[Kerberos ticket]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})
or for SMB.

## Order, and the one exception

Sources are asked **in the order they are written**, and the first one that
knows a name owns it. The `user` blocks always come first, so a service
account written down locally is not overridden by somebody with the same name
in the database. **Group membership is the union** of every source: a group
that a `group` block and a database's `groups` query both name has the
members of both.

{{< callout type="warning" >}}
**Two names that differ only by case are refused**

A uid is compared ignoring case (RFC 4519 §2.39), and so is every DN, so
`Dora` in the file and `dora` in a database are one name to LDAP and two
people to anything that compares bytes — a password change by one would land
on the other. Such a configuration does not start:

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## Read at start, then every refresh {#read-once}

Every source is read **at startup and again every `refresh`**. A person added
to or removed from the database, or a membership changed in the directory
behind this one, is served within one period, with no restart. That includes a
password column in a database: it is read with the row. A directory behind this
one is different only in that a bind is checked by binding to it, so a password
changed *there* is the one that works. A password a person changes through
authnd itself is [applied at once]({{< relref "/authnd/passwords.md" >}}).
A refresh that fails keeps the last good data, and `max_age` says when to stop
serving it; see [running it]({{< relref "/authnd/operations.md" >}}). The
configuration files and the keytab still need a restart; the certificate does
not, from v0.15.0.
