---
title: "TLS: ldaps:// or StartTLS, and not both at once"
linkTitle: "TLS"
weight: 40
description: "Serving LDAP over TLS from a certificate in files, the choice between ldaps:// and StartTLS, and why sambaNTPassword is published only over one."
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file` and `key_file` together turn TLS on; one without the other is
refused (*one without the other serves nothing*). TLS 1.2 is the minimum.
authnd has no ACME client: the two files are written by something else —
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}}), certbot, a
site's own CA — and authnd is **restarted** after each renewal,
because the certificate is read once, when the listener opens.

## Two ways, one listener each

| | `starttls` | the listener | `check` says |
|---|---|---|---|
| **ldaps://** | not set | the TLS handshake happens before a byte of LDAP is spoken | `ldaps://…` |
| **StartTLS** | `starttls = true` | plaintext, upgraded when the client asks (RFC 4511 §4.14) | `ldap+starttls://…` |

It is one or the other and has to be: a listener cannot both require a
handshake and wait to see whether one is asked for. Which one a site wants is
about its **clients**: `ldaps://` on 636 is what most of them are configured
for, and StartTLS is what a client pointed at 389 with "use TLS" ticked will
ask for. A site that needs both runs two instances, each with its own
`--config`. `starttls = true` without a certificate is refused:

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps://

The server, a CA-signed certificate for `127.0.0.1`, and the chain verified
by a client that is not this program:

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS, which refuses until it is asked for

StartTLS is requested by the **client**, so merely offering it promises
nothing: a client that never asks would bind in the clear. A listener with
`starttls = true` therefore refuses every bind and every search until the
connection has been upgraded, with `confidentialityRequired`:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

(`-ZZ` is "StartTLS, and fail if it fails". `LDAPTLS_REQCERT=never` is there
because the `ldapsearch` macOS ships trusts the system store and could not be
told to trust this test CA; the chain was checked separately with
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error`,
which answered `Verify return code: 0 (ok)`.)

That refusal is what makes `cert_file` a guarantee rather than an offer — and
it is what `publish_nt_hash` relies on. It includes the anonymous bind
`ldapsearch -x` sends before reading the root DSE, so on a StartTLS listener
that discovery query, too, needs `-ZZ`.

## `publish_nt_hash`

`sambaNTPassword` is what lets a Samba or another SMB server authenticate
people through this directory, and it is **not** a password hash in the
sense a login form means: whoever holds `MD4(UTF16LE(password))`
authenticates as that person over NTLMv2 without ever learning the
password. So it is published only when asked for, and, from v0.11.0, with
the domain the people's SIDs belong to:

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

Asking for it is refused unless the listener has TLS, or is loopback
(`127.0.0.0/8`, `::1`, `localhost`) and so on no network at all:

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### The `samba` block {#the-samba-block}

`sambaNTPassword` belongs to Samba's `sambaSamAccount`, whose MUST is `uid`
and `sambaSID`, and no other class allows it. Every entry authnd publishes
passes [the schema it serves]({{< relref "/authnd/entries.md" >}}), so the
attribute is published only on a `sambaSamAccount`, and that needs a SID:

| key | |
|---|---|
| `domain_sid` | required: the SMB server's domain SID, `S-1-5-21-…`, as `net getlocalsid` prints it |
| `algorithmic_rid_base` | optional, `1000` by default, Samba's. An odd number, or one below 1000, is refused: Samba would silently use another one |

A person's `sambaSID` is their own `sambaSID` attribute when a source gives
one ([attributes]({{< relref "/authnd/entries.md#adding-attributes" >}})).
Otherwise it is `domain_sid-RID`, with RID = 2 × `uidNumber` +
`algorithmic_rid_base`: Samba's algorithmic mapping (smb.conf(5),
*algorithmic rid base*). A person with an NT key and neither is published
**without** `sambaNTPassword`, and `check` and the startup log say who. The
Samba definitions are added to the schema served at `cn=Subschema` only when
the block is there; they were written from Samba's published OIDs, names and
syntaxes, not copied from its GPL-3.0 `samba.schema`.

{{< callout type="error" >}}
**Breaking for v0.10.x configurations: `publish_nt_hash` without a `samba` block does not start**

v0.10.x served `publish_nt_hash = true` alone. From v0.11.0 that
configuration is refused at startup and by `check`, with what to add:

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

Run `check` with the new binary before upgrading. Refusing is deliberate:
the v0.10.x entry cannot pass the schema, and the two quiet alternatives —
dropping the attribute, which takes SMB away from everybody, or dropping the
entry, which takes the person away — would both happen with nothing on the
console.
{{< /callout >}}

A `samba` block without `publish_nt_hash` is refused too, since it would
publish nothing:

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### What `check` says {#what-check-says}

Three people on an `ldaps://` listener: alice has a password and the POSIX
trio, so their SID is derived (2 × 1000 + 1000); bob has only an NT hash and
a `sambaSID` of their own; carol has a password and neither.

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

and, for the StartTLS listener, *sambaNTPassword is published over TLS, once
StartTLS has been asked for*. alice has no NT hash written down; theirs is
derived from the password they have. bob's hash is published for an SMB
server to use, and `check` says, too, that bob cannot bind to authnd itself.
carol's entry is published without the attribute, and an SMB server cannot
serve carol until a source gives them a `uidNumber` or a `sambaSID`.

What a reader is given, over the StartTLS listener of the same people:

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

Only a [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})
can search, so only a reader ever sees the attribute. Who may read it is
therefore the same question as who holds a reader's password.

{{< callout type="warning" >}}
**NTLMv2 needs the password or its MD4, and nothing else will do**

A file server asking authnd about somebody can serve them over SMB only if
the *source* held enough for that: a password, or the hash. A person who
comes from a directory that only checks passwords — *a password check* in
`check` — can never be given a `sambaNTPassword`, whatever authnd does in
between. Without `publish_nt_hash`, nobody can: `check` then says
*sambaNTPassword is not published, so nothing here can authenticate an SMB
session*.
{{< /callout >}}

## Tokens need it too

An [`oidc` block]({{< relref "/authnd/tokens.md" >}}) refuses a token over a
connection that is not encrypted, unless `allow_plaintext = true` says that
TLS is terminated in front of this process.
