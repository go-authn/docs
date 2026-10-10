---
title: "mfa — enough factors, and which ones"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa decides whether enough factors answered, of enough different kinds, and says which ones did — with no device and no cryptography."
tags: [libraries, mfa, factors]
---

**Did enough factors answer, of enough kinds — and which ones?** Nothing here
reaches a device, and there is no cryptography: a `Factor` is anything that can
be asked *is this person here, now?*, and this package decides what the answers
add up to.

```sh
go get github.com/go-authn/mfa@v0.5.0
```

It imports nothing outside the standard library.

## Two of the same thing is one factor

A passphrase and a recovery code are both things the person *knows*: whoever
learned one has usually learned the other from the same place. So a factor
says what it proves — `Knowledge`, `Possession` or `Inherence` — and the
policy that means what *two-factor* is normally taken to mean is
`Policy{Count: 2, DistinctKinds: true}`. `Policy{Count: 2}` alone is also
offered, for a caller who wants two keys of the same kind on purpose; it is a
different request and is spelled differently.

A factor whose `Kind()` is `Unknown` counts towards the number satisfied, never
towards the kinds: it cannot be shown to differ from anything.

## Example

```go
package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/go-authn/mfa"
)

// factor is the smallest mfa.Factor: a name, a kind, and an answer.
type factor struct {
	name string
	kind mfa.Kind
	err  error
}

func (f factor) Name() string                 { return f.name }
func (f factor) Kind() mfa.Kind               { return f.kind }
func (f factor) Verify(context.Context) error { return f.err }

func main() {
	ctx := context.Background()
	twoFactor := mfa.Policy{Count: 2, DistinctKinds: true}

	// Two things the person knows are one kind of proof.
	_, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"a recovery code", mfa.Knowledge, nil},
	)
	fmt.Println(err)

	// A key that is not plugged in has not refused anybody.
	r, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"your security key", mfa.Possession, mfa.Unavailable(errors.New("no key attached"))},
	)
	fmt.Println(err)
	fmt.Println(r.Answers[1].Unavailable())

	// The zero Policy is refused, not guessed at.
	_, err = mfa.Verify(ctx, mfa.Policy{}, factor{"your passphrase", mfa.Knowledge, nil})
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) answered but only 1 kind(s) among them (knowledge); two of the same kind are not two factors
mfa: 2 factor(s) needed, 1 answered: your security key (possession): not available
true
mfa: a policy that requires 0 factors accepts anyone
```

The real factors live elsewhere: [totp]({{< relref "/libraries/totp.md" >}})
for a code from a phone, [keyfactor]({{< relref "/libraries/keyfactor.md" >}})
for a security key.

## What it refuses, and why

`Verify` refuses before it asks anybody:

| | why |
|---|---|
| a `Policy` whose `Count` is below one | *a policy that requires 0 factors accepts anyone*. There is no default policy: how much proof is enough belongs to whoever protects the thing |
| fewer factors offered than `Count` | the policy cannot be met, whatever they answer |
| a factor whose `Kind()` is outside the enumeration | counted as a distinct kind, `Kind(42)` beside a passphrase would pass as two-factor |
| **the same factor twice** | one passphrase passed twice satisfied `Count: 2`. "The same" is the same type holding the same values, functions included: a function is the same function when it runs the same code |

And it keeps three things apart while it asks:

- **Could not be asked is not a refusal.** A factor that returns
  `ErrUnavailable` — wrapped by `mfa.Unavailable(err)`, which keeps the
  reason — is reported as such (`Answer.Unavailable()`), and never ends an
  attempt even with `StopOnFirstFailure`.
- **Every factor is asked by default**, so a person can be told *your key
  answered, your fingerprint did not* in one attempt. `StopOnFirstFailure` is
  there when stopping early is wanted.
- **A factor not reached has no entry** in `Result.Answers`: reporting it as
  failed would send somebody after nothing.

The `Result` is returned whether or not the policy was met, with the error
naming what was missing in words a person can act on.

## What it is checked against

No external judge: the module holds no protocol to disagree with. Its CI
requires **100% statement coverage** on Linux, macOS and Windows, runs the race
detector, and runs the tests on amd64, arm64, riscv64, loong64, ppc64le, s390x,
386 and arm.

## Reference

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
