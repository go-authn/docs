---
title: "kdcd — a Kerberos KDC daemon for one realm"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd is a program built on the kdc library: AS and TGS over UDP and TCP, one HCL file, every secret a file, and an optional mutual-TLS listener that mints a TGT for a person with no password."
tags: [libraries, kerberos, directory, kdcd]
---

**How is the [kdc]({{< relref "/libraries/kdc.md" >}}) library run as a service?**
`kdcd` is a Kerberos KDC daemon for one realm, built on the library
[go-authn/kdc](https://github.com/go-authn/kdc). It answers AS and TGS requests
over UDP and TCP and, optionally, **mints a TGT** for a person who proved
themselves elsewhere (a passkey login at
[go-authn/bridge](https://github.com/go-authn/bridge)), over mutual TLS. The
library holds the protocol; this program holds the sockets, the configuration,
and the rules for the secrets.

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

Install (the binary is `kdcd`: MIT's KDC is `krb5kdc`, Heimdal's is `kdc`):

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

Pure Go, `CGO_ENABLED=0`; releases carry a `SHA256SUMS` manifest and a build
provenance attestation per binary. As a service: `packaging/systemd/` (unit and
sysusers file; see [Running it](#running-it)).

## What the directory must hold {#what-the-directory-must-hold}

A KDC decrypts the client's pre-authentication with that person's long-term key,
so an **AS-REQ** can only be served for a person whose source holds a
**password**: a `user` block with `password_file`, or a `users "sql"` block that
returns one. A source that can only *verify* one (a bind against somebody
else's LDAP, a hash) cannot serve an AS-REQ, however well it answers "is this
the password". That is a property of Kerberos, explained in the
[library's documentation](https://github.com/go-authn/kdc#readme) and on
the [kdc page]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}}).

A passkey-era realm needs none of that. A person with **no password** (a
`user "alice" {}` block, or a row of any `users` block) is in the directory, has
no key, and is refused an AS-REQ with `KDC_ERR_NULL_KEY`. They get a TGT only
through the **mint listener**, from a caller that authenticated them. `kdcd`
adds no password path of its own: no flag, no environment variable, no inline
value; `password_file` exists because the library's AS path needs it.

## Configuration {#configuration}

One HCL file. Nothing in it is a secret; every secret is a file.

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: any number of these, in any mix.
user "alice" {}                           # a person with no password: mint only
user "bob" { password_file = "/etc/kdcd/bob.pw" }

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"
  users    = "select login, password from staff"
}
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/kdcd/bind.pw"
}
```

The `users` blocks are [go-authn/directory/hcldir](https://github.com/go-authn/directory)'s,
unchanged. A source that can only verify a password, such as a bind against an
LDAP server, gives mint callers a directory to check a principal against and
cannot serve an AS-REQ.

`kdcd check --config FILE` reads and builds everything the daemon would, opens
the directory, listens on nothing, and prints what it serves: the realm,
addresses, the keytab's principals (name, kvno, etype; never a key), how many
people the directory holds, the mint callers. Exit status 0 and a last line
`ok`, or the first refusal.

### What it refuses to start with {#what-it-refuses-to-start-with}

| Refused | Why |
| --- | --- |
| a keytab, mint key, password file, DSN or bind password that **group or others can read or write**, or that belongs to a uid other than root or the daemon's | a copy another account can read forges tickets for every person of the realm |
| a secret written inline (`password = "..."` is not an argument) | secrets live in files, never in the configuration, a backup of it, or a log |
| a configuration file that group or others can write | whoever writes it chooses the mint callers |
| a keytab with no `krbtgt/REALM` key, or lacking a listed service, **in aes256-cts-hmac-sha1-96** (the one type the library issues) | it would start and fail at the first `kinit` |
| a wildcard or a host name in `listen` (an IP literal is required), and **any** wildcard for `mint` | the KDC and the mint listener are on the interfaces somebody chose |
| a `mint` block with no callers, no certificate, or an expired one | the library reads no callers as "minting off"; this says so instead of silently minting nothing |
| `ldap://` to another machine without `start_tls` | every password would cross the network as typed |

Secret files are opened **once** and the open file is checked (regular file,
mode, owner), so a check cannot be about one file and the read about another
(the model is go-fileshare's `readKeytab`). `dsn_file` and `bind_password_file`
are read by `hcldir` by name, after being checked the same way.

## The mint trust model {#the-mint-trust-model}

`POST https://<mint address>/mint` with `{"principal": "alice", "lifetime_seconds": 36000}`
returns a KRB-CRED (RFC 4120 5.8) holding a TGT for `alice`, for the caller to
hand to the person's machine ([go-authn/kinit](https://github.com/go-authn/kinit)
loads it into a Windows logon session). What bounds it:

- **The caller is the TLS client certificate**, verified against `client_ca_file`
  by the listener (TLS 1.3, `RequireAndVerifyClientCert`): a connection with no
  certificate, or one the CA did not sign, fails the handshake before any HTTP
  is read. A verified certificate is then matched, by a **URI subjectAltName**,
  against `callers`, exactly; a certificate that verifies but is not listed is
  `403`. Nothing in a header or a body names the caller.
- **Whoever is on `callers` can obtain a TGT for any principal in the directory**
  (never a service, never a name the directory lacks), without that person's key.
  The caller's own authentication of the person is what the realm trusts, so a
  caller is as trusted as the KDC's keytab is. List one per identity provider,
  give each its own certificate, and keep `client_ca_file` a CA that signs
  nothing else.
- The ticket is `INITIAL | PRE-AUTHENT`, never renewable, forwardable or
  proxiable; its lifetime is the least of the request, `lifetime` and ten hours.
- The session key is made from `crypto/rand`, leaves the process once, in the
  reply, and is never logged. The reply is `Cache-Control: no-store`. The
  KRB-CRED carries the key in the clear, so **the TLS channel is the
  encryption**: put the listener on an internal interface.
- Only `/mint` is served, with timeouts and a header limit. Every mint, and
  every refusal, is logged with the caller's URI and the principal asked for.

The full threat model is that of the library's pull request,
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38), with the
[minting section](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)
and the [audit notes](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)
of the library's README; none of it is repeated or weakened here.
[go-authn/bridge](https://github.com/go-authn/bridge)'s `kerberos` block is the
caller's side: its `kdc_url` is `https://<mint address>/mint`, its `ca_file`
signs `cert_file` above, and its client certificate's URI name is a `callers`
entry.

## Running it {#running-it}

`packaging/systemd/kdcd.service` runs it as the system user of
`packaging/sysusers.d/kdcd.conf`, with the hardening of
[authn-bridge](https://github.com/go-authn/bridge)'s unit. Port 88 is
privileged, so the unit grants exactly `CAP_NET_BIND_SERVICE` and nothing else.

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

Secrets belong to `kdcd` (or to root) at mode 0600; 0640 with group `kdcd` is
refused on purpose. A change to the configuration is `systemctl restart kdcd`
(the daemon does not reload; a client retries a refused connection).

On Windows the mode bits mean nothing and are not checked: put the files where
only the account that runs the service can read them.

## Not here {#not-here}

Cross-realm, PKINIT, FAST, renewable or postdated tickets, a kadmin protocol,
and any encryption type but aes256-cts-hmac-sha1-96 are the library's own
limits ([go-authn/kdc](https://github.com/go-authn/kdc#readme)). `kdcd` has no
reload and no metrics endpoint yet.

## Reference {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd), v0.1.0.
