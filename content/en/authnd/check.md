---
title: "check, before you restart something people log in through"
linkTitle: "check"
weight: 30
description: "What authnd check opens, what it prints about a configuration before it is served, how to read it, and the one failure it cannot see."
tags: [authnd, check, configuration]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check` reads the configuration exactly as the server does, **opens
everything the server opens before it listens** — the files, the database,
the directory behind this one, the identity provider's discovery document,
the TLS certificate and key, the keytab — and prints what would be published
and to whom, **without listening**. It prints where every credential comes
from and never what is in it. It exits 0 and ends with *this configuration
can be served*, or exits 1 with the one sentence that stops the server.

## A configuration that can be served

Two `user` blocks, a reader, and a SQLite database, in a directory of two
files (`authnd.hcl` and `people.hcl`):

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## Reading it

The first line is the scheme, the address and the base: `ldap://`,
`ldaps://`, or `ldap+starttls://` — see [TLS]({{< relref "/authnd/tls.md" >}}).


| column | |
|---|---|
| `FROM` | the source that owns the name: *the configuration file*, *a sqlite database* (or postgres, mysql), or the url of a directory behind this one |
| `CAN PROVE` | *a password* (held, so it can be compared and keys derived from it), *a password check* (another directory answers yes or no), *an NT hash*, *N keys*, *a one-time-code secret*, or *nothing* |
| `PUBLISHED AS` | the entry's object classes, without `top`, as [the shapes]({{< relref "/authnd/entries.md#the-shapes" >}}) give them — or *NOT PUBLISHED (see below)* for an entry that fails the schema |
| `WITH` | the attributes the entry carries, read off the entry a search returns: `uid`; `cn` wherever a class allows it; what the sources gave, less what was dropped; `sshPublicKey` when there are keys; `sambaSID` and `sambaNTPassword` when [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) is on and the person has an NT key and a SID |

The group table has a `PUBLISHED AS` column too: `posixGroup`,
`groupOfNames` or `organizationalRole`. Up to v0.10.2, `PUBLISHED AS` was
the list of attributes, *uid and cn* for nearly everybody, and there was no
`WITH` column.

The lines after the tables say what a person needs to know before relying on
the configuration. First, about [the entries]({{< relref "/authnd/entries.md" >}}):

- **who is not a `posixAccount`**, and which of `uidNumber`, `gidNumber`
  and `homeDirectory` they lack;
- **which groups have no `gidNumber`**, and what they are published as
  instead;
- **every attribute dropped** because no class of its entry allows it, and
  which classes would;
- **every entry not published**, with each problem the schema check found;
- **who has an NT key and no `sambaSID`**, and so no `sambaNTPassword`.

From v0.12.0, between the first line and the tables, what a
[site schema]({{< relref "/authnd/schemas.md" >}}) added, and what the
sources declare:

- **the schema files and `schema` blocks loaded**, and what each adds:
  `schema: etc/authnd/example.schema adds 3 object identifier macros, 2
  attribute types and 2 object classes`;
- **the classes each source declares**: `users "sql" declares exampleStaff and
  exampleLockerHolder for its people`, with the position of the declaration;
- **every class left off a person or group**, because it lacks a MUST of a
  class its source declares: `ben is published without exampleStaff, which its
  source declares: ben has no exampleEmployeeId, which exampleStaff
  requires`, and, after the attributes' lines, those it took with it;
- **a group for which two sources declare different classes**: the first
  source's list is published and the second's ignored.

A file that does not build, a redefinition, and a declared class that is
undefined, STRUCTURAL or one authnd derives stop `check` and the server
alike, with the file or configuration position.

Then, about binds and searches:

- **what a bind carries**: *a password*, or, with an [`mfa` block]({{< relref "/authnd/mfa.md" >}}),
  *a password with a 6-digit code after it*; with an [`oidc` block]({{< relref "/authnd/tokens.md" >}}),
  where tokens come from and over what;
- **who cannot bind with a password at all**: people known only by an NT
  hash — see [people]({{< relref "/authnd/people.md#written-in-the-configuration" >}});
- **who may search**: the readers, or *no reader is declared: nothing may
  search, and binds are not affected*;
- **whether `sambaNTPassword` is published**, and over what — see
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}});
- with a [`kerberos` block]({{< relref "/authnd/kerberos.md" >}}), the realm and
  **who can and who cannot be issued a ticket**, with the reason;
- with an `mfa` block, **who has no second factor**, and so cannot bind with
  a password; with an `oidc` block beside it the line adds that a token whose
  `amr` names two kinds still can;
- a **group that names somebody no source has**.

That last one is published as it stands — a front for one system
legitimately carries names another one owns — but it is said, because the
other reading is a typo. In a `posixGroup` the stranger is a `memberUid`; in
a `groupOfNames` it is a `member` DN that names no entry here,
`member: uid=zoe,ou=people,dc=example,dc=org` here, which go-authn/directory's
`ldapdir` from v0.14.0 maps to nobody. Here the database's `team_members`
table has a row for `zoe`, who is nobody here:

```
GROUP      MEMBERS              PUBLISHED AS
engineers  dora, eli and zoe    groupOfNames
staff      alice, bob and dora  groupOfNames
[...]
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(A `group` *block* naming a stranger is refused outright; see
[people]({{< relref "/authnd/people.md#written-in-the-configuration" >}}).)

From v0.15.0 the second line of the output is `limits:`: the connection limits,
the operation deadline and the startup deadline authnd will run with, defaults
included. The transcripts on this page were printed by earlier releases and do
not show it. A real one is in
[limits and deadlines]({{< relref "/authnd/operations.md#limits" >}}).

## What it refuses

Each of these stops `check` and the server alike, with exit status 1. They
are on the pages where they belong; a few, as printed:

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## The certificate, the keytab, and the one thing it cannot see

A certificate that does not load and a keytab without `krbtgt/REALM` are
refused by `check`, in the words the server would use:

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

What `check` cannot know without listening is **whether the ports are
free**. A second server on the same Kerberos address passes `check` and is
refused at start:

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## Run it as the service account

```sh
sudo -u authnd authnd check /etc/authnd
```

so that a file only root can read fails here, not at the restart. Run it
with the **new** binary before an upgrade; see [install]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}).
