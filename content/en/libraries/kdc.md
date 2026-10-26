---
title: "kdc — issuing Kerberos tickets from a directory"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc is the issuing half of Kerberos: AS and TGS over UDP and TCP, pre-authentication required, one encryption type, people from a go-authn directory."
tags: [libraries, kerberos, directory]
---

**How does a realm issue tickets from a directory?** AS-REQ and TGS-REQ, over
UDP and TCP, with encrypted-timestamp pre-authentication required, for the
people a [directory]({{< relref "/libraries/directory.md" >}}) knows and the
services a keytab holds. It runs under
[authnd]({{< relref "/authnd/_index.md" >}}).

```sh
go get github.com/go-authn/kdc@v0.4.3
```

At v0.4.3 its `go.mod` requires at least `go-authn/directory` v0.12.0 and
gokrb5 v8.4.4: minimums, so a program that requires directory v0.14.0, the
version these pages describe, builds with v0.15.0, as authnd v0.12.3 does. The
accepting half is [krb5]({{< relref "/libraries/krb5.md" >}}), and a service
that only verifies tickets needs this module not at all.

Not implemented: cross-realm referrals, PKINIT, FAST, renewable or postdated
tickets, and any kadmin protocol. Keys come from the directory and from a
keytab, and change where they live.

## Only a source holding the password can back a realm

A KDC must **decrypt** the client's pre-authentication with that person's
long-term key, so a `directory.Verifier` — a bind against somebody else's
LDAP, a hash comparison — cannot serve, however well it answers *is this the
right password*. A person whose source holds no password is answered
`KDC_ERR_NULL_KEY` (*null key*), never the code a wrong password gets, so it
reads as a configuration to fix rather than a password to retype.

## Example

A realm in memory, on loopback:

```go
package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/go-authn/directory"
	"github.com/go-authn/kdc"
	"github.com/jcmturner/gokrb5/v8/iana/etypeID"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

func main() {
	// People: a source that holds PASSWORDS. A verifier cannot back a realm.
	people := &directory.Static{Name: "the configuration file", People: []*directory.Identity{
		directory.NewIdentity("alice", directory.WithPassword("correct horse battery staple")),
	}}

	// Services: the realm's own krbtgt key, and one per service.
	kt := keytab.New()
	for _, p := range []string{"krbtgt/EXAMPLE.ORG", "nfs/files.example.org"} {
		if err := kt.AddEntry(p, "EXAMPLE.ORG", rand.Text(), time.Now(), 1, etypeID.AES256_CTS_HMAC_SHA1_96); err != nil {
			log.Fatal(err)
		}
	}

	// A keytab without krbtgt/REALM is refused before anything listens.
	_, err := kdc.New(kdc.Config{Realm: "OTHER.ORG", People: people, Services: kt})
	fmt.Println(err)

	srv, err := kdc.New(kdc.Config{
		Realm:    "EXAMPLE.ORG",
		People:   people,
		Services: kt,
		Logf:     log.Printf, // why each request was refused; never a key
	})
	if err != nil {
		log.Fatal(err)
	}
	pc, err := net.ListenPacket("udp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	go srv.ServeTCP(ln)
	fmt.Println("EXAMPLE.ORG answers on", pc.LocalAddr())
	log.Fatal(srv.ServeUDP(pc))
}
```

With a `krb5.conf` naming `kdc = tcp/127.0.0.1:18088` for `EXAMPLE.ORG`, the
Heimdal `kinit` that macOS ships (1.5.1) gets a ticket-granting ticket, with
`KRB5_CONFIG=krb5.conf` and `KRB5CCNAME=FILE:cc`:

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  nfs/files.example.org@EXAMPLE.ORG
```

The ten hours are `Config.Lifetime`'s default, and the service ticket ends with
the ticket-granting ticket it was bought with. The KDC said why it refused each
request, in its own log:

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

The first refusal of each exchange is the protocol working: the `KRB-ERROR`
that demands pre-authentication carries an `ETYPE-INFO2` hint naming the
etype and the salt, and the client tries again with a timestamp.

{{< callout type="info" >}}
**Before v0.4.2, a `till` of 19700101000000Z got a ticket that had already expired**

RFC 4120 §5.4.1: a `till` of 19700101000000Z asks for the maximum end time
the KDC's policy permits. Heimdal's `kgetcred` sends exactly that. v0.4.1
tested only for Go's zero time, so it took the Unix epoch for a real end and
issued a service ticket that `klist` showed as `>>>Expired<<<`; MIT's `kvno`,
the CI's judge, sends a real `till` and never met the case. v0.4.2 issues the
longest ticket allowed, as above, and answers a `till` that has already passed
with `KDC_ERR_NEVER_VALID` instead of a ticket expired on arrival
([go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19)).
{{< /callout >}}

## What it refuses, and why

**At configuration** (`New`): no realm (`ErrNoRealm`), no directory
(`ErrNoPeople`), no keytab (`ErrNoServices`), or a keytab without
`krbtgt/REALM@REALM` (`ErrNoTGTKey`) — rather than starting and failing at the
first `kinit`, where the error reaches a person who cannot fix it.

**At the AS:** a request without pre-authentication is answered with the
demand for it, and the person's key is not derived until there is a timestamp
to check, so a spoofed UDP packet naming a real principal costs no key
derivation. A wrong password, a timestamp under another etype and one from an
hour ago are all answered `KDC_ERR_PREAUTH_FAILED`, the code a wrong password
gets; the error text names the reason, and so does `Logf`. A service asking for a TGT of its own is refused: services
authenticate from a keytab.

**One encryption type.** Tickets and keys are `aes256-cts-hmac-sha1-96`
(etype 18) only. A request whose etype list lacks 18 is answered
`KDC_ERR_ETYPE_NOSUPP` before anybody is looked up. With `Logf` set, the log
records both etypes, so an operator can tell a mismatched cipher from a
mistyped password.

**At the TGS** (RFC 4120 §3.3.2), a ticket is issued only when:

- the ticket presented is a TGT of this realm, decrypted under the
  `krbtgt/REALM` key the KDC names — not under the key of whatever service the
  ticket claims (`KRB_AP_ERR_NOT_US`);
- the authenticator decrypts under its session key, within `MaxSkew`;
- its checksum is over this request's body, as the bytes arrived, keyed with
  the session key (`KRB_AP_ERR_INAPP_CKSUM` when missing or unkeyed,
  `KRB_AP_ERR_MODIFIED` when wrong);
- the TGT is not past its end (`KRB_AP_ERR_TKT_EXPIRED`), not before its start
  and not flagged invalid (`KRB_AP_ERR_TKT_NYV`), with no skew allowed: this
  KDC's clock wrote those times;
- the client is of this realm and still in the directory
  (`KDC_ERR_C_PRINCIPAL_UNKNOWN`).

**Lifetimes.** `Config.Lifetime` caps a ticket, ten hours when zero; a client
asking for less gets less, and a ticket bought with a TGT ends no later than
that TGT, so asking for `krbtgt` again cannot stretch a credential.

**What an unauthenticated peer can hold:** a TCP message, its length included,
must arrive within 30 seconds; at most 256 TCP connections are served at once,
and at most 64 datagrams are answered at once — one more is dropped, and the
client resends or falls back to TCP.

## What it is checked against

**MIT's own `kinit` and `kvno`**, through pkgx, against a realm built in Go —
no MIT KDC is involved, only the client is borrowed.
`TestMITClientGetsATGTAndAServiceTicket` gets a TGT and a service ticket and
checks the key version `kvno` reports. The Linux test lane, the race detector
and the coverage lane set `KDC_REQUIRE_JUDGE=1`, and a further step fails
unless the log says *were served by this realm*. The tests also pin the
refusals a real client never triggers: a timestamp under the wrong key, one
from an hour ago, a three-byte cipher, a service asked for straight from an
AS-REQ, a forged service ticket at the TGS, and a realm backed by a verifier.
The coverage lane's floor is 80%.

## Reference

[pkg.go.dev/github.com/go-authn/kdc@v0.4.3](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.3)
