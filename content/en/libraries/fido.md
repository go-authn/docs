---
title: "fido — speaking to a security key"
linkTitle: "fido"
weight: 30
description: "go-authn/fido speaks CTAPHID and CTAP2 to a security key over any 64-byte transport: handshake, registration, assertion and PIN, in pure Go."
tags: [libraries, fido, factors]
---

**How is a security key spoken to?** The FIDO client-to-authenticator protocol
— the CTAPHID framing, the channel handshake, and the CTAP2 commands that
register a credential, ask for a signature and exchange a PIN for a token — in
pure Go, on any operating system.

```sh
go get github.com/go-authn/fido@v0.6.2
```

Nothing here is platform-specific. A `Transport` moves 64-byte reports to and
from one authenticator and says what the device is called; where those reports
come from — IOKit on macOS, hidraw on Linux, WebHID in a browser — is somebody
else's package. Everything above it is here:

| | |
|---|---|
| `Open(ctx, t)` | the `INIT` handshake on the broadcast channel; returns a `*Key` with its own channel. The `Key` owns `t`: `Close` closes it, and so does a failed `Open` |
| `Key.Ping`, `Key.Wink` | a round trip, and a blink — the cheapest way to ask *which of these keys is this one?* |
| `Key.GetInfo` | versions, extensions, AAGUID, options, PIN protocols |
| `Key.MakeCredential`, `Key.GetAssertion` | register, and sign; `ParseAuthData` reads the authenticator data, and `AuthData.PublicKey` turns a P-256 COSE key into an `*ecdsa.PublicKey` |
| `Key.PINRetries`, `Key.KeyAgreement`, `Key.PINToken` | `authenticatorClientPIN`, both PIN/UV auth protocols |
| `Split`, `NewReassembler`, `ParseInit`, `Key.CBOR` | the framing, exported for whoever drives a key some other way |

`AuthData.PublicKey` is a conversion, not a verification: which algorithms
count and what to do with a sign counter that went backwards belongs to the
caller. [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) is one such
caller.

## Example

The framing alone, with no key: a message cut into reports, and put back
together.

```go
package main

import (
	"bytes"
	"fmt"

	"github.com/go-authn/fido"
)

func main() {
	// A 200-byte ping, cut into the 64-byte reports a key reads...
	payload := bytes.Repeat([]byte{0xA5}, 200)
	reports, err := fido.Split(0x01020304, fido.CmdPing, payload)
	if err != nil {
		panic(err)
	}
	fmt.Println(len(reports), "reports of", len(reports[0]), "bytes")

	// ...and put back together, as a reply would be.
	r := fido.NewReassembler(0x01020304)
	for _, rep := range reports {
		msg, done, err := r.Feed(rep)
		if err != nil {
			panic(err)
		}
		if done {
			fmt.Println(bytes.Equal(msg.Data, payload), msg.Cmd == fido.CmdPing)
		}
	}

	// A report for another channel is an error, not something to drop.
	other, _ := fido.Split(0x0A0B0C0D, fido.CmdPing, []byte("hi"))
	_, _, err = fido.NewReassembler(0x01020304).Feed(other[0])
	fmt.Println(err)

	// The framing's real limit, not the length field's.
	fmt.Println(fido.MaxMessage)
}
```

```
4 reports of 64 bytes
true true
fido: the report belongs to another channel
7609
```

With a key, `fido.Open(ctx, transport)` does the handshake and the `*Key` it
returns carries every later command.

## What it refuses, and why

**A key is not trusted to answer what it was asked.** A reply that carries a
different command from the one sent is refused (CTAP 2.1 §11.2.9 gives each
response its own command, and libfido2 checks it too). An `INIT` reply whose
nonce is not the one sent is refused: it is another program's handshake on the
same key. A PIN token that is not its protocol's length — 16 or 32 bytes under
protocol one, exactly 32 under protocol two — is refused.

**A keepalive is not an answer.** A key waiting for a finger sends
`CTAPHID_KEEPALIVE` about every hundred milliseconds; it is skipped, and the
only bound on how long a touch may take is the context.

**A message longer than the framing can carry.** Two length bytes would allow
65535, but 57 bytes in the initialisation packet plus 128 continuations of 59
is 7609 (`MaxMessage`); past that a sequence number would reach `0x80` and a
key would read it as a new message. `Split` returns `ErrTooLong`.

**Reports that do not add up**: one for another channel (`ErrWrongChannel` —
two programs on one key), continuations out of order (`ErrOutOfOrder`), a
report shorter than a packet (`ErrShortPacket`), an `INIT` reply shorter than
its 17 bytes (`ErrTruncated`).

**A command the key did not say it supports.** `Wink` is not sent to a key
without `CapWink`, nor `GetInfo` to one without `CapCBOR`: the key would answer
`CTAPHID_ERROR`, and the caller would have to tell that refusal from a fault.

**An empty PIN**, and anything but P-256 in `AuthData.PublicKey` — refused by
name rather than half-decoded.

{{< callout type="warning" >}}
**A wrong PIN costs a retry**

CTAP gives an authenticator a counter of PIN retries, eight at most, and each
wrong PIN spends one. Three wrong PINs in a row block the PIN until the key is
unplugged and plugged back in. A counter that reaches zero blocks it for good:
only a reset lifts that, and a reset erases every credential on the key. Ask
`Key.PINRetries` before prompting anybody: it says how many retries are left,
and whether the key is waiting to be unplugged.

When a key refuses a PIN, the error says which of the two it is.
CTAP2_ERR_PIN_AUTH_BLOCKED (`0x34`), which unplugging lifts, reads
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`;
CTAP2_ERR_PIN_BLOCKED (`0x32`), which only a reset lifts, reads
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`.
Before v0.6.2 the two sentences were swapped: a key that only had to be
unplugged was called locked, and somebody told that might reset it and lose
every credential on it.
{{< /callout >}}

## What it is checked against

The CI has no security key, so the tests use a fake transport that reassembles
what it is sent — a key that refuses, stalls, keeps saying it is busy, or shares
its channel with another program — with coverage held at 100%. Two fixtures
come from outside this code:

- `testdata/yubikey-fido-5.7.4-getinfo.hex`, the `GetInfo` reply **captured
  from a YubiKey FIDO 5.7.4**, decoded by `ctap2_test.go`;
- `testdata/webauthn-reference-authdata.b64`, a sample from the tests of
  **go-webauthn/webauthn**, which checks the authenticator-data parser and
  `AuthData.PublicKey`.

The status-code table follows libfido2's `err.h`. The module's README records
a registration and an assertion run against a real YubiKey, with the signature
verified against the public key it handed out; that run is not part of CI.

## Reference

[pkg.go.dev/github.com/go-authn/fido@v0.6.2](https://pkg.go.dev/github.com/go-authn/fido@v0.6.2)
