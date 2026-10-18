---
title: "A Kerberos realm for the same people"
linkTitle: "Kerberos realm"
weight: 60
description: "The kerberos block, the keytab it signs tickets with, who can be issued a ticket and why some people never can, and why it cannot sit beside an mfa block."
tags: [authnd, kerberos, kdc]
---

```hcl
kerberos {
  realm    = "EXAMPLE.ORG"               # required, upper case
  keytab   = "/etc/authnd/krb5.keytab"   # required; must hold krbtgt/EXAMPLE.ORG
  listen   = "127.0.0.1:88"              # the default; UDP and TCP both
  lifetime = "10h"                       # the default, MIT's
}
```

A `kerberos` block makes authnd a KDC as well as a directory, through
[go-authn/kdc]({{< relref "/libraries/_index.md" >}}): the same people are
issued tickets instead of only being looked up. It answers on UDP and TCP at
the same address, requires encrypted-timestamp pre-authentication, and issues
`aes256-cts-hmac-sha1-96` tickets only. `lifetime` is a Go duration
(`"10h"`, `"90m"`). The directory and the realm are equals: if either stops,
the process stops, because a server that kept answering LDAP after its KDC
died would look healthy to everything that does not speak Kerberos.

Refused at startup:

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

and likewise a realm with no name, no keytab, an address that does not parse,
a `lifetime` Go cannot read, and a `kerberos` block beside an `mfa` block
(below).

## The keytab

The keytab holds the key authnd signs its own tickets with —
`krbtgt/REALM@REALM` — and one key per service it issues tickets to. It is
the same file those services read. The krbtgt
password is never typed again, so make it random. With MIT's `ktutil`
(package `krb5-user` on Debian and Ubuntu; this recipe is the one
`docs/install.md` gives, and was not run for these pages):

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

Add a service's key the same way (`-p nfs/files.example.org@EXAMPLE.ORG`), and
give that service the same key in its own keytab. On macOS, Heimdal's
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96`
writes a random key without a password at all. Either way, read the keytab
back before starting (`klist -k` with MIT, `ktutil -k <file> list` with
Heimdal):

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

A keytab without `krbtgt/REALM` is refused by `check` and at start; see
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
The keytab is read once, at start: replacing it takes a restart.

## Who can be issued a ticket

A KDC must **decrypt** the client's pre-authentication with that person's
long-term key, so it needs the person's **password**, not only a way to
check one. `check` says who can and who cannot, with the reason:

```
$ authnd check realm
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP  MEMBERS        PUBLISHED AS
staff  alice and bob  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

| the source has | a ticket |
|---|---|
| a password (`password`, `password_file`, a SQL password column) | yes |
| only an NT hash | **no**: it is the RC4-HMAC key, and this realm issues AES only |
| only a password check (a `users "ldap"` directory behind this one) | **no**: a source that only verifies a password cannot produce any key |

For a directory behind this one, the last line of the realm part reads
*alice, bob, dora and eli: the source only verifies a password, so it cannot
produce any key*. That is structural rather than a matter of configuration,
and finding it in `check` beats finding it from somebody whose `kinit` says
their correct password is wrong.

## kinit against it

A `krb5.conf` that names this KDC. ⛔ For MIT Kerberos the braces go on their
own lines: its parser silently ignores a realm written on one line.

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

The same configuration served, and asked by macOS's Heimdal `kinit`
(`--password-file` reads the password from a file):

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 18 16:10:19 2026  Oct 19 02:10:19 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

The ticket lasts the default ten hours. bob typed the password their NT hash
was computed from, and is still refused: the realm has no key for them. The
KDC writes what it refused, with the Kerberos error code, to its output:

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required* is the normal first round of a `kinit`: the
client asks without pre-authentication and is told it is required, then asks
again with it. alice's successful `kinit` leaves only that line.

{{< callout type="info" >}}
**The realm says which names exist; the directory does not**

An LDAP bind for a name nobody has is answered `invalidCredentials`, the
same as a wrong password. The KDC answers *no such principal in this realm*
(`KDC_ERR_C_PRINCIPAL_UNKNOWN`, code 6), as Kerberos KDCs do. With a
`kerberos` block on an address others can reach, the list of names is
therefore as guessable as it is from any KDC; `listen` defaults to
loopback.
{{< /callout >}}

## A password changed over LDAP

The KDC reads the same people the directory serves, so a
[password changed over LDAP]({{< relref "/authnd/passwords.md" >}}) reaches the
realm at once — the old one stops working for `kinit` the moment it stops
working for a bind:

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## Not beside an `mfa` block

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

RFC 4120's encrypted-timestamp pre-authentication is keyed by the password
alone. A second factor needs OTP pre-authentication (RFC 6560) inside FAST
(RFC 6113), which this KDC does not implement. A realm here would hand out
tickets on one factor to the people the [`mfa` block]({{< relref "/authnd/mfa.md" >}})
says need two, and a ticket opens everything a bind does — so the choice is
made closed: one or the other.

## Ports

88 is privileged. Under the packaged unit, `CAP_NET_BIND_SERVICE` covers it;
a server run as an ordinary user wants a high port, as above, and a
`krb5.conf` that names it.
