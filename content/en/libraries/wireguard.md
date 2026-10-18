---
title: "wireguard — whose key is this, and may it connect?"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard defines a WireGuard public key strictly and carries the provider-signed list of registered keys that a gateway turns into peers."
tags: [libraries, wireguard, tokens]
---

**May this WireGuard key connect, and whose is it?** WireGuard authenticates a
peer by its static public key and by nothing else: no certificates, no expiry,
no revocation. So the question is answered outside the protocol, and answered
again whenever the answer changes. A provider —
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) — answers it; this
module is what the provider and a gateway agree on.

```sh
go get github.com/go-authn/wireguard@v0.1.1
```

Its one dependency is [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0,
which verifies the list.

It does two things: `ParseKey` says what a public key is, and `Source.Fetch`
gets the provider's signed `List` of the keys people registered, each a `Peer`
with its `Key`, `Subject`, `Username`, `Device` and the end of its lease.

{{< callout type="info" >}}
**Only public keys pass through here**

A private key is generated on the device and never leaves it; nothing in this
package has a place for one.
{{< /callout >}}

## Example

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

A gateway keeps one `Source` and fetches the list:

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource` reads the provider's configuration at startup. `Fetch` gets a
token for the gateway itself (`client_credentials`, scope `wireguard_peers`),
fetches the list from `/wireguard/peers` under the issuer, and verifies it
with go-authn/oidc: the signature against the provider's key set, the issuer,
the audience (this gateway's `ClientID`), the expiry, and the `typ`
`wireguard-peers+jwt` (`ListType`) — so neither an access token nor an ID
token can pass for a list, nor a list for a token.

## What it refuses, and why

**A key** (`ParseKey`):

- any other spelling of the same bytes. The decoding is strict and the text
  must print back exactly as it came, so a store keyed on the text cannot hold
  one key twice under two names;
- a point of low order, the all-zero key among them. Every exchange with one
  gives the same shared secret whatever the other side's key (RFC 7748 §6.1),
  so it authenticates nobody. `crypto/ecdh` decides it by computing an
  exchange, so the top-bit variants are refused too.

**A list** (`Fetch`):

| | why |
|---|---|
| a list with a lower `version` than one this `Source` has taken | an old list is signed too, and may list a key taken back since |
| a key listed twice | whichever a gateway kept, the other person's traffic would arrive under the wrong name |
| a peer with no subject | it belongs to nobody |
| a key that is not one | see above |
| an issuer or token endpoint in the clear, except loopback | the gateway's secret and the list would cross a link anybody can read |
| a `SourceConfig` without `ClientID` and `ClientSecret` | a gateway reads the list as a client of its own |

A list carries `exp`: a gateway that cannot fetch a newer one by then has no
list, rather than a stale one. `Peer.Subject` is the person's `sub` as the
client that registered the key sees it, public or pairwise — the value a
gateway also finds in that person's access tokens.

## What it is checked against

**`wg(8)` itself**, from wireguard-tools, makes the keys `ParseKey` must
accept. It is installed in the Linux test lane, the race detector and the
coverage lane, which set `WIREGUARD_REQUIRE_JUDGE=1` so a missing `wg` fails
rather than skips. The low-order test checks the seven points libsodium lists,
each with and without the top bit. The coverage floor is 100%.

## Reference

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.1](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.1)
