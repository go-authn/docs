---
title: "oidc — verifying a bearer token"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc verifies an OpenID Connect token into an identity: discovery, the key set, an algorithm allowlist, and the refusals that matter. No dependencies."
tags: [libraries, oidc, tokens]
---

**Who does this bearer token say is asking, and should it be believed?**
Discovery, the key set, and the checks a resource server must make — in pure
Go, with **no dependencies** outside the standard library.

```sh
go get github.com/go-authn/oidc@v0.4.1
```

There is no login flow here: no redirect, no code exchange, no client secret,
no cookies. This is the **resource-server** half — something arrives with a
token, and this says who that is.

## Example

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/go-authn/oidc"
)

func main() {
	// Discovery happens here, at startup: an issuer that does not answer is
	// a server that cannot authenticate anybody.
	v, err := oidc.New(context.Background(), oidc.Config{
		Issuer:   "https://login.example.org",
		Audience: "fileshare",
		Type:     "at+jwt", // a resource server takes access tokens, not ID tokens
	})
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		tok, err := v.Verify(r.Context(), raw)
		if err != nil {
			log.Print(err) // which check refused it: for this log only
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		fmt.Fprintln(w, tok.Subject(), tok.Username(), tok.Groups())
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

A `Verifier` is safe for concurrent use and holds the key set: build one at
startup and keep it. `Verify`'s error says which check refused the token, for
the server's log; the client gets one refusal whatever the check.

Three configurations `New` refuses before anything is fetched:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/oidc"
)

func main() {
	ctx := context.Background()
	for _, cfg := range []oidc.Config{
		{Issuer: "http://login.example.org", Audience: "fileshare"},
		{Issuer: "https://login.example.org"},
		{Audience: "fileshare"},
	} {
		_, err := oidc.New(ctx, cfg)
		fmt.Println(err)
	}
}
```

```
oidc: http://login.example.org is not https: the key set decides every signature, and over cleartext so does anybody on the way
oidc: no audience: a token minted for another service is a valid token, and a verifier that does not check accepts every one the issuer ever signed
oidc: no issuer: a verifier without one accepts tokens from anybody
```

The rest of `Config` is optional: `JWKSURL` skips discovery; `UsernameClaim`
and `GroupsClaim` (default `groups`) name the claims; `ClockSkew` and
`MinRefresh` default to one minute; `Client` is the HTTP client, for a proxy,
a private CA or a timeout. A `Token` reads `Subject`, `Issuer`, `Audience`,
`Email`, `EmailVerified`, `Username`, `Groups`, `Expiry`, `NotBefore` and
`IssuedAt`; `Claim(name, &v)` decodes any other claim, and `Has(name)` says
whether it is there.

## What it accepts

Ten signature algorithms, as an **allowlist**: `RS256` `RS384` `RS512`,
`PS256` `PS384` `PS512`, `ES256` `ES384` `ES512`, and `EdDSA` (Ed25519). A
token whose `alg` is not one of these is refused before any key is fetched.
`alg: none` and the HMAC family are refused by not being on the list, and the
key must be of the algorithm's kind: a token claiming `RS256` is checked with
an RSA key or refused.

## What it refuses, and why

| | why |
|---|---|
| `alg: none` | a token that says it is unsigned is a JSON object somebody typed |
| HMAC against a public key | `HS256` takes a shared secret, and the issuer's key is public: anybody could mint a token |
| an issuer that merely **starts with** the right one | `iss` is compared whole: `https://login.example.org.evil.test` starts with the right string |
| a missing or wrong **audience** | a token minted for another service is valid; it is not addressed to this one |
| a token with **no expiry** | it is a password somebody can copy once |
| an issuer, a key set, or a redirect **over cleartext HTTP**, except to loopback | the key set decides every signature |
| an RSA key under 2048 bits, or with `n` or `e` not in shortest form; an EC point not on its curve | signatures under a short key can be forged; before v0.2.2, a 1024-bit modulus padded with zero bytes passed as 2048 bits |
| a key published with `use` other than `sig` | a key set legitimately holds encryption keys too |
| with `Type` set, a token of another `typ`; with it unset, a `typ` other than `JWT` or `at+jwt` (a token with no `typ` header passes) | RFC 9068 §4: a resource server checks `typ: at+jwt`, or it takes an ID token for an access token whenever the audiences agree |
| a part that is not canonical base64url | a token verifies as one string |

ECDSA's `s` and `n − s` both verify, as the algorithm allows. So a denylist or
a replay cache keys on `jti` or `sub`, never on the token as sent.

**Keys rotate, and an unknown key is not a way to hammer the issuer.** A
signature nothing held can verify is worth one refetch of the key set per
`MinRefresh`, whether the `kid` is new or the same `kid` carries a new key.
Tokens that need the key set while a fetch is under way wait for it, and a
fetch that fails still counts.

**Which name `Username()` gives.** By default `preferred_username`, then
`email` **only when `email_verified` is true**, then `sub`. An unverified email
is a string the person typed (OIDC Core §5.1). A configured `UsernameClaim` is
read as named, with no fallback.

## What it is checked against

**pyjwt** signs every token in the test suite, so the verifier is never judged
by a signer from the same hands. The HMAC-confusion token is forged by hand,
because pyjwt refuses to produce it. `testdata/fixed.json` — tokens pyjwt
signed once with a fixed key — lets the architecture lanes, s390x included,
verify real signatures with the clock fixed. The Linux test lane, the race
detector and the coverage lane install pyjwt and set `OIDC_REQUIRE_JUDGE`, so a
missing pyjwt fails rather than skips. Accepting HMAC, comparing the issuer by
prefix and skipping the audience check were each tried on purpose, and each
turns a test red. The coverage lane's floor is 90%.

## Reference

[pkg.go.dev/github.com/go-authn/oidc@v0.4.1](https://pkg.go.dev/github.com/go-authn/oidc@v0.4.1)
