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

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid and cn
bob    the configuration file  an NT hash  uid and cn
dora   a sqlite database       a password  uid and cn
eli    a sqlite database       an NT hash  uid and cn

GROUP      MEMBERS
engineers  dora and eli
staff      alice, bob and dora

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
| `PUBLISHED AS` | the attributes the entry carries: always `uid` and `cn`; `sambaNTPassword` when `publish_nt_hash` is on and the person has one or a password it can be derived from; `sshPublicKey` when there are keys |

The lines after the tables say what a person needs to know before relying on
the configuration:

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

That last one is published as it stands — `memberUid` is a string, and a
front for one system legitimately carries names another one owns — but it is
said, because the other reading is a typo. Here the database's
`team_members` table has a row for `zoe`, who is nobody here:

```
GROUP      MEMBERS
engineers  dora, eli and zoe
staff      alice, bob and dora
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(A `group` *block* naming a stranger is refused outright; see
[people]({{< relref "/authnd/people.md#written-in-the-configuration" >}}).)

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
