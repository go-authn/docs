---
title: "keyfactor — the registered key, touched"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor turns a security key into an mfa factor, verifying the answer against the registration rather than trusting whatever device speaks CTAP."
tags: [libraries, fido, mfa, factors]
---

**Did the key that was registered answer, and did a person touch it?**
`keyfactor` is the one piece between [fido]({{< relref "/libraries/fido.md" >}}),
which speaks CTAP and knows about no policy, and
[mfa]({{< relref "/libraries/mfa.md" >}}), which decides how much proof is
enough and knows about no device. Neither imports the other; this imports both.

```sh
go get github.com/go-authn/keyfactor@v0.4.2
```

At v0.4.2 its `go.mod` requires at least `go-authn/fido` v0.6.2 and
`go-authn/mfa` v0.5.0, the versions these pages describe.

The platform supplies an `Opener` — how a key is found on this system — and
keeps only that. Everything else is the same wherever CTAP is: the assertion,
the checks, the refusal to spend somebody's last PIN attempt.

## Example

```go
package main

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"

	"github.com/go-authn/fido"
	"github.com/go-authn/keyfactor"
	"github.com/go-authn/mfa"
)

func main() {
	// The platform supplies the Opener: how a key is found on this system.
	// This one finds nothing, and says so the way a policy understands.
	open := func(context.Context) (fido.Transport, error) {
		return nil, keyfactor.Unavailable(errors.New("no security key is plugged in"))
	}

	// From the registration: the credential ID and its public key, which
	// fido.AuthData.PublicKey returns from the attestation.
	var pub *ecdsa.PublicKey // nil here, to show the refusal

	f := keyfactor.New(open, keyfactor.Options{
		RPID:         "example.test",
		CredentialID: []byte{0x01, 0x02},
		PublicKey:    pub,
	})
	fmt.Println(f.Name(), f.Kind())

	_, err := mfa.Verify(context.Background(), mfa.Policy{Count: 1}, f)
	fmt.Println(err)
}
```

```
your security key possession
mfa: 1 factor(s) needed, 0 answered: your security key (possession): keyfactor: no public key for the credential; without one any device that answers would pass, so pass the one from the registration
```

The refusal comes before the `Opener` is called. With the registration's
public key, the same factor opens the key, asks it for an assertion over a
fresh random challenge, and checks the answer.

## What it refuses, and why

**A device answering is not the key answering.** A programmable USB board
speaks CTAP as well as a security key does, so the answer is checked against
the registration:

| refused | message |
|---|---|
| before anything is opened: no `Opener`, no `RPID`, no `PublicKey`, or a key not on P-256 | `keyfactor: no opener; …`, `… needs a relying party id …`, `… no public key for the credential; …`, `… is not on P-256 …` |
| a relying-party hash that is not SHA-256 of `RPID` | `… answered for another relying party` |
| a credential other than `CredentialID`, when the device names one | `… answered with a credential other than the one asked for` |
| a signature over the authenticator data and the challenge that `PublicKey` did not make | `… answered with a signature the credential's key did not make` |
| no `UP` flag | `… answered without anyone touching it` |
| no `UV` flag when a `PIN` was given | `… was asked to establish who holds it and did not` |

**The last PIN attempt is not spent on a guess.** `PINRetries` is asked first;
a key that will take no more PINs until it is unplugged is refused, and so is
one with **one attempt or fewer** left. Under CTAP, three wrong PINs in a row
block a key's PIN until it is unplugged, and a retry counter that reaches zero
blocks it for good: only a reset lifts that, erasing every credential on it.

When the key itself refuses a PIN, the error is fido's, and from fido v0.6.2
it names the right one of the two:
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`
when unplugging lifts the block, and
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`
when only a reset does. Before fido v0.6.2 the two sentences were swapped.

**A PIN is not a second factor.** The kind stays `mfa.Possession`: a PIN
entered into the key protects the key, and identifies nobody to this machine.

**An empty port is not a refusal.** An `Opener` that finds nothing wraps its
error with `keyfactor.Unavailable`, which marks it `mfa.ErrUnavailable`, and a
policy counts *could not be asked* apart from *said no*.

{{< callout type="warning" >}}
**What it cannot protect: the PIN's hash reaches whatever device answers**

CTAP has the platform hand the key `LEFT(SHA-256(PIN), 16)`, encrypted under a
secret agreed with the device itself, before anything is signed. A forged
device is refused as a factor, but it has received that hash, and a short PIN
falls to an offline search. That is the protocol. Use a long PIN, and do not
type one into a key whose provenance is unknown.
{{< /callout >}}

## What it is checked against

The tests fake **the authenticator**, not the transport, built from
go-authn/fido's own exported framing: a CTAPHID handshake, a CTAP2 assertion,
and a ClientPIN exchange. The PIN half plays the authenticator's side of
protocol two independently — its own ECDH, HKDF and AES-CBC, written from the
specification (`fakepin_test.go`) — so a derivation that differed by a byte
would fail the exchange. `forged_test.go` is the device that holds no
credential. Coverage is held at 100%, and the tests run on eight
architectures.

## Reference

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2)
