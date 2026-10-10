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
ldaps on 127.0.0.1:3636, serving 2 people from the configuration file

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
objectClass: person
objectClass: posixAccount
uid: bob
cn: bob
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
password. So it is published only when asked for:

```hcl
publish_nt_hash = true
```

and asking for it is refused unless the listener has TLS, or is loopback
(`127.0.0.0/8`, `::1`, `localhost`) and so on no network at all:

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

With it, `check` names the attribute per person and says what protects it:

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid, cn and sambaNTPassword
bob    the configuration file  an NT hash  uid, cn and sambaNTPassword

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2

this configuration can be served
```

and, for the StartTLS listener, *sambaNTPassword is published over TLS, once
StartTLS has been asked for*. alice has no NT hash written down; theirs is
derived from the password they have. bob's hash is published for an SMB
server to use, and `check` says, too, that bob cannot bind to authnd itself.

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
