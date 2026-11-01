---
title: "krb5 — accepting a Kerberos ticket"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5 is the acceptor half of Kerberos: a keytab, an AP-REQ verified, the AP-REP that mutual authentication needs, and messages signed and sealed under the session key."
tags: [libraries, kerberos]
---

**Is this Kerberos ticket good for this service?** The **acceptor** half of
Kerberos, and only that half: it holds a keytab, verifies the AP-REQ a client
presents, answers with the AP-REP that proves the service is genuine, and then
signs, verifies, seals and opens messages under the key that exchange
established.

```sh
go get github.com/go-authn/krb5@v0.3.3
```

v0.3.3 changes no API and no code: it raises the indirect dependencies
golang.org/x/net to v0.62.0, golang.org/x/crypto to v0.58.0 and
github.com/hashicorp/go-uuid to v1.0.4. `govulncheck` listed 46 findings in
modules it requires and does not call; it lists 1 now, GO-2026-5932
(`golang.org/x/crypto/openpgp`), which has no fixed version and which nothing in
go-authn imports. The findings that are reachable from the code were 0 before and
are 0 after.

It never talks to a KDC and never issues a ticket, so whose tickets it accepts
is somebody else's decision. The issuing half is
[kdc]({{< relref "/libraries/kdc.md" >}}), and this module does not depend on
it — see [why they are separate]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}}).
Ticket decryption is [gokrb5](https://github.com/jcmturner/gokrb5)'s.

## Why it exists

gokrb5 is a client library. It verifies an AP-REQ and cannot build the AP-REP
that answers one. Every GSS-API client asks for mutual authentication — MIT's
own `gss-client` sets `GSS_C_MUTUAL_FLAG` with no way to turn it off — so a
service that cannot produce an AP-REP completes no context at all. Building it
is most of what this module adds.

## Example

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

It needs `github.com/jcmturner/gokrb5/v8` for `keytab.New`, which `krb5.New`
takes; `krb5.Load` reads a keytab from a path instead.

After `Accept`, a `*Context` says who: `Principal()` (`alice@EXAMPLE.ORG`), or
`User()` and `Realm()` apart. Mapping a principal to a local account is the
caller's policy: `alice@EXAMPLE.ORG` and `alice@PARTNER.ORG` both answer to
"alice". `Expires()` is when the ticket behind it ends, past which a server
holding a long-lived connection should stop honouring it. `MIC`/`VerifyMIC`
and `Wrap`/`Unwrap` sign; `Seal`/`Unseal` add confidentiality (`sec=krb5p`).
A `Context` is not safe for concurrent use; an `Acceptor` is.

## What it refuses, and why

**A ticket this service will not accept** — wrong service, wrong key,
expired, replayed, a clock beyond `ClockSkew` (five minutes by default, MIT's
too) — is `ErrRejected`. Bytes that are not a GSS-API krb5 token are
`ErrNotAToken`, and a token that is not an AP-REQ is `ErrNotAPReq`. The errors
are deliberately coarse: a client learns that its ticket was refused, never
which check refused it. An error means no context, and the returned token is
empty.

**A principal the acceptor does not answer for.** With
`krb5.Principal("nfs/files.example.org")`, a keytab holding several services
answers for that one only.

**A message whose signature does not match** is `ErrBadMIC`, whichever of the
length, the header, the sequence or the checksum disagreed. The acceptor signs
with key usage 23 and verifies with 25, so a token this server produced cannot
be replayed back at it as though the client had signed it.

**A sealed token given to `Unwrap`** is `ErrSealed`, distinct from a bad
signature: a caller reading an integrity-only token must not be handed
ciphertext that reads like a message. **An unsealed token given to `Unseal`**
is `ErrNotSealed`: a protocol that promised confidentiality is not handed
something that crossed the wire in the clear.

It asserts no acceptor subkey: the context key is the subkey the initiator put
in its authenticator, or the ticket's session key when it sent none
(RFC 4121 §4.3).

{{< callout type="warning" >}}
**A keytab is a secret at rest**

Its path may come from a configuration file or from `KRB5_KTNAME`; the key
inside it must never be logged, printed, or carried in an environment
variable.
{{< /callout >}}

## What it is checked against

**A real MIT KDC and MIT's own `gss-client`**, against this package standing
in for `gss-server`. `test/kdc.sh` builds a throwaway realm on loopback,
unprivileged; the CI gets MIT Kerberos through pkgx (Ubuntu's packages do not
ship `gss-client`). The Linux test lane, the race detector and the coverage
lane set `KRB5_REQUIRE_JUDGE=1`, so a missing fixture fails. A further step
runs `TestMITClientAgainstThisAcceptor` and fails unless the log says
*authenticated as alice@* — a green lane whose judge silently stopped running
is not accepted. `TestMITClientSealed` does the same with confidentiality on.

The macOS, Windows and cross-architecture lanes have no realm, and there the
judge skips. The coverage lane's floor is 90%.

## Reference

[pkg.go.dev/github.com/go-authn/krb5@v0.3.3](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.3)
