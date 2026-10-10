---
title: "totp — a code, once, and not a million guesses"
linkTitle: "totp"
weight: 20
description: "go-authn/totp checks RFC 6238 one-time codes, refuses a code already used, limits guessing per secret, and offers the result as an mfa factor."
tags: [libraries, totp, factors]
---

**Is this six-digit code right — and has it been used before?** Time-based
one-time passwords (RFC 6238); a `Verifier` that remembers what a server has
to, the codes already used and the wrong ones; and a factor that an
[mfa]({{< relref "/libraries/mfa.md" >}}) policy can ask for.

```sh
go get github.com/go-authn/totp@v0.4.1
```

Its one dependency is `go-authn/mfa`.

The defaults are what every phone assumes: six digits, every 30 seconds,
HMAC-SHA1, one step of tolerance either side. `Options` changes `Digits`,
`Period`, `Algorithm` (`SHA1`, `SHA256`, `SHA512`) and `Window`.

## Example

```go
package main

import (
	"fmt"
	"time"

	"github.com/go-authn/totp"
)

func main() {
	secret, err := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	if err != nil {
		panic(err)
	}
	now := time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)
	o := totp.Options{Now: func() time.Time { return now }}

	code, _ := totp.At(secret, now, o) // what the phone shows
	fmt.Println(code)

	v := &totp.Verifier{Options: o}
	fmt.Println(v.Verify("dora", secret, []byte(code))) // accepted
	fmt.Println(v.Verify("dora", secret, []byte(code))) // the same code again
	fmt.Println(v.Verify("Dora", secret, []byte(code))) // another spelling, same secret

	// A secret shorter than 128 bits makes no code.
	short, _ := totp.ParseSecret("JBSWY3DPEHPK3PXP")
	_, err = totp.At(short, now, o)
	fmt.Println(err)
}
```

```
395621
<nil>
totp: that code has already been used
totp: that code has already been used
totp: a secret of 80 bits; RFC 4226 requires at least 128
```

In a policy, the code becomes a factor of kind `Possession`, next to whatever
checks the password:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/mfa"
	"github.com/go-authn/totp"
)

// knows stands in for whatever checks the password.
type knows struct{}

func (knows) Name() string                 { return "your password" }
func (knows) Kind() mfa.Kind               { return mfa.Knowledge }
func (knows) Verify(context.Context) error { return nil }

func main() {
	ctx := context.Background()
	secret, _ := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	verifier := &totp.Verifier{} // one per server, kept: it remembers used codes
	code := []byte("123456")     // what the person typed

	_, err := mfa.Verify(ctx, mfa.Policy{Count: 2, DistinctKinds: true},
		knows{},
		totp.Factor("dora", secret, code, verifier),
	)
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
```

A code read aloud over the telephone is possession no longer; the
classification is what `DistinctKinds` relies on.

## What it refuses, and why

**A code already accepted.** RFC 6238 §5.2: the verifier MUST NOT accept a
second attempt of an OTP that already succeeded. The stateless `totp.Verify`
cannot — it holds nothing between calls — so a server uses a `*Verifier`, which
refuses with `ErrUsed` every step **up to and including** the last one it
accepted: a code from thirty seconds ago is still inside the default window.

**A `Factor` without a `Verifier`.** `totp.Factor` with a nil `*Verifier`
refuses every code, saying a Verifier is missing. It is not reported as
unavailable, so a policy cannot pass on the other factors and hide the mistake.

**Guessing, per secret.** A `Verifier` counts wrong codes per **credential** —
the secret, held only as its SHA-256 — not per name, because the name is
whatever string the caller passes, and before v0.3.0 `dora`, `Dora` and `DORA`
were three counters for one secret.

| field | default | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | wrong codes in a row before `ErrThrottled`; the code sent meanwhile is not looked at, so not even the right one passes |
| `Pause` | `DefaultPause` = 15 minutes | how long that lasts |
| `Lockout` | `DefaultLockout` = 100 | wrong codes in a row, however spread out, before `ErrLockedOut`, which only `Forget` lifts (NIST SP 800-63B §5.2.2) |

Only a wrong code counts; a replay, a code of the wrong length or a refused
parameter does not bring a pause nearer. The whole check is made under one
lock, so guesses sent at the same moment are counted one by one.
`ErrLockedOut` wraps `ErrThrottled`, so `errors.Is(err, totp.ErrThrottled)` is
true for both refusals, and `errors.Is(err, totp.ErrLockedOut)` only for the
lockout.

**Parameters that cannot be right:**

- a secret under 128 bits (`MinSecret` = 16 bytes, RFC 4226 R6), in
  `Generate`, `At`, `Verify` and `Verifier.Verify`. `ParseSecret` still reads
  one: it is a parser;
- a period that is not a whole number of seconds, or under one second;
- fewer than 6 or more than 10 digits (RFC 4226 §5.3);
- a window wider than `MaxWindow` = 10 steps either side. `0` means the
  default of one step; `NoWindow` accepts only the current step.

Every step in the window is tried without stopping early, and the comparison is
constant-time. `ErrWrongCode` is the same error for "wrong" and "too old".

{{< callout type="warning" >}}
**The secret is the credential**

Whoever holds it produces every future code. No error message here quotes a
code or a secret, and `URI` — the `otpauth://` string an authenticator reads
from a QR code — carries the secret by construction: it is for the person
enrolling, and nobody else.
{{< /callout >}}

The `Verifier`'s memory is this process's. Two servers behind a load balancer
each refuse their own replays and count their own guesses; a deployment that
needs one answer puts a shared store behind the same interface.

## What it is checked against

- **pyotp**, a Python implementation: 200 random cases across secret lengths
  from 16 bytes, 6 to 10 digits, four periods and all three algorithms
  (`differential_test.go`). The Linux test lane, the race detector and the
  coverage lane install it, and there `TOTP_REQUIRE_JUDGE` turns a missing
  pyotp into a failure rather than a skip.
- **RFC 6238 Appendix B**, all six times and all three algorithms, and
  **RFC 4226 Appendix D**, counters 0 to 9.
- Every digit count over 1000 steps per algorithm, against RFC 4226 §5.3
  recomputed in arbitrary precision.

The coverage lane fails below 95% (its stated standard is 100%), and the
tests run on eight architectures.

## Reference

[pkg.go.dev/github.com/go-authn/totp@v0.4.1](https://pkg.go.dev/github.com/go-authn/totp@v0.4.1)
