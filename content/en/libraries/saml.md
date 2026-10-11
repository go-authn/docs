---
title: "saml — a service provider in front of a federation"
linkTitle: "saml"
weight: 100
description: "go-authn/saml is a SAML 2.0 service provider for a research federation such as RENATER or eduGAIN: signed metadata, the AuthnRequest, and an assertion read after every check."
tags: [libraries, saml, federation]
---

**What did this person's identity provider say about them?** A SAML 2.0
service provider for an identity federation such as RENATER's Fédération
Éducation-Recherche or eduGAIN: it reads the federation's signed metadata,
sends people to their own institution's identity provider, and reads back what
that provider says.

```sh
go get github.com/go-authn/saml@v0.4.1
```

It is the half of [authn-bridge]({{< relref "/authn-bridge/_index.md" >}})
that faces the federation, and usable on its own by anything that wants to be
a SAML SP. Not here: an IdP, Single Logout, the artifact binding, signed
AuthnRequests, attribute queries, SAML 1.1.

| | |
|---|---|
| `Federation` | fetches the metadata, verifies it against a **pinned** certificate, and keeps it fresh with `Run` |
| `ParseMetadata` | the same verification, for a document already in hand |
| `DiscoveryURL`, `Chosen` | send the person to a discovery service, and read back the IdP it chose |
| `SP.Request` | the AuthnRequest, over HTTP-Redirect, and the `Pending` to keep |
| `SP.Accept` | the `SAMLResponse` posted to the ACS, read into an `Assertion` |
| `Assertion.Subject` | `subject-id`, then `pairwise-id`, then `eduPersonPrincipalName`, then `eduPersonTargetedID`, then a persistent NameID — never mail |
| `SP.Metadata` | the SP's own metadata, to register with the federation |

## Example

Discovery and the request, with one IdP described by hand:

```go
package main

import (
	"fmt"
	"net/url"

	"github.com/go-authn/saml"
)

func main() {
	// One IdP, as a federation's metadata would describe it.
	idp := &saml.IdP{
		EntityID: "https://idp.univ-example.example/idp/shibboleth",
		SSO:      "https://idp.univ-example.example/idp/profile/SAML2/Redirect/SSO",
		Scopes:   []string{"univ-example.example"},
	}
	md := &saml.Metadata{IdPs: map[string]*saml.IdP{idp.EntityID: idp}}

	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Federation: md,
	}

	// Send the person to the discovery service, then read back what it chose.
	d, _ := saml.DiscoveryURL("https://discovery.renater.fr/renater", sp.EntityID, "https://app.example.org/saml/chosen")
	fmt.Println(d)

	_, err := saml.Chosen(url.Values{"entityID": {"https://idp.attacker.example/idp"}}, md)
	fmt.Println(err)
	chosen, _ := saml.Chosen(url.Values{"entityID": {idp.EntityID}}, md)

	// The AuthnRequest, over HTTP-Redirect. Keep p, keyed by the RelayState,
	// and hand it to sp.Accept at the ACS.
	to, p, err := sp.Request(chosen, "s1", saml.Options{AuthnContext: []string{"https://refeds.org/profile/mfa"}})
	if err != nil {
		panic(err)
	}
	u, _ := url.Parse(to)
	fmt.Println(u.Host, u.Query().Has("SAMLRequest"), u.Query().Get("RelayState"), p.IdP, p.AuthnContext)

	// RelayState is limited to 80 bytes, and refused beyond that.
	_, _, err = sp.Request(chosen, string(make([]byte, 81)), saml.Options{})
	fmt.Println(err)
}
```

```
https://discovery.renater.fr/renater?entityID=https%3A%2F%2Fapp.example.org%2Fsaml&return=https%3A%2F%2Fapp.example.org%2Fsaml%2Fchosen&returnIDParam=entityID
the chosen identity provider is not in the federation
idp.univ-example.example true s1 https://idp.univ-example.example/idp/shibboleth [https://refeds.org/profile/mfa]
RelayState is limited to 80 bytes
```

In a service, the metadata comes from the federation and the response arrives
at the ACS:

```go
package main

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"log"
	"net/http"
	"os"

	"github.com/go-authn/saml"
)

func main() {
	ctx := context.Background()

	// The federation's metadata signing certificate, downloaded ONCE and
	// checked against the fingerprint the federation publishes.
	fed := &saml.Federation{
		URL:  "https://pub.federation.renater.fr/metadata/fer/idps.xml",
		Cert: readCert("/etc/app/metadata-signature-2026.pem"),
	}
	if err := fed.Refresh(ctx); err != nil {
		log.Fatal(err)
	}
	go fed.Run(ctx, func(err error) { log.Print(err) })

	pair, err := tls.LoadX509KeyPair("/etc/app/saml.crt", "/etc/app/saml.key")
	if err != nil {
		log.Fatal(err)
	}
	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Key:        pair.PrivateKey.(*rsa.PrivateKey), // assertions arrive encrypted to it
		Cert:       pair.Leaf,
		Federation: fed,
	}

	http.HandleFunc("/saml/acs", func(w http.ResponseWriter, r *http.Request) {
		p := pendingFor(r.PostFormValue("RelayState")) // what Request returned, from the session
		a, err := sp.Accept(r.PostFormValue("SAMLResponse"), p)
		if err != nil {
			log.Print(err) // for the log, not for the browser
			http.Error(w, "refused", http.StatusForbidden)
			return
		}
		id, from := a.Subject()
		log.Printf("%s (%s) from %s", id, from, a.IdP.EntityID)
	})
	log.Fatal(http.ListenAndServeTLS(":443", "/etc/app/tls.crt", "/etc/app/tls.key", nil))
}

func readCert(path string) *x509.Certificate {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		log.Fatal("no PEM block in ", path)
	}
	c, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		log.Fatal(err)
	}
	return c
}

// pendingFor is the caller's session store.
func pendingFor(relayState string) saml.Pending { return saml.Pending{} }
```

## What it refuses, and why

**Metadata:**

| | why |
|---|---|
| not signed by the **pinned** certificate | the certificate is a parameter, never fetched alongside the metadata: a key that arrives over the same channel as the document vouches for nothing |
| past its `validUntil`, or with none | a signed document that never expires is a key compromise that never ends. A failed refresh keeps the last good copy, until that copy expires |
| valid for more than 28 days from now | `Federation.MaxValidity` changes the bound; a negative value removes it |
| older than the copy in use | a rollback: validly signed, and possibly carrying a key since revoked |
| fetched over `http://` from anywhere but loopback | the signature would catch a change, but not a path that holds back the new document |

An IdP's certificate in metadata is trusted because the federation's signature
names it; its dates are not looked at, since IdP certificates are often
self-signed and expired.

**Responses** are checked at `Accept`. Each refusal below is returned to the
caller as an error, for the server's log:

| | why |
|---|---|
| nothing signed, or signed with SHA-1 | saml-profiles 4.1.4.5: over POST the assertion must be signed. A Shibboleth IdP signs the Response by default; either is accepted |
| more than one assertion | how a signed one and an unsigned one arrive together and the wrong one is read (CVE-2022-41912) |
| anything outside what the signature covered | it is never read: only the element rebuilt from the bytes the signature digested is |
| a scoped identifier outside the IdP's `Scopes` | dropped: otherwise any IdP could assert `alice@another-university.example` |
| AES-CBC ciphertext no verified signature covers | not even decrypted: unauthenticated CBC is a padding oracle. RSA PKCS#1 v1.5 key transport is not accepted at all; AES-GCM and RSA-OAEP are |
| another audience, ACS or request; an unsolicited response; a request more than an hour old | saml-profiles 4.1.4.3 |
| an assertion already used | a bearer assertion is whoever holds it |
| a condition it does not understand | saml-core 2.5.1: the assertion is then Indeterminate |
| a password returned when MFA was asked for (`Options.AuthnContext`) | an IdP may ignore the request |
| with `ForceAuthn`, an `AuthnInstant` from before the request | the IdP reused a session it was asked not to |

{{< callout type="warning" >}}
**The default replay cache is one process's memory**

`SP.Replay` defaults to `NewMemoryReplay()`. Several instances behind a load
balancer would each accept the same assertion once, and a restart empties
it. Implement `Replay` over shared storage; its `Use` must be atomic.
{{< /callout >}}

## What it is checked against

- **RENATER's own metadata**, as RENATER signed it on 2026-09-29, in
  `testdata/fer-idps.xml.gz`, with its certificate checked against the
  SHA-256 fingerprint RENATER publishes. All 343 IdPs are read; rewriting the
  host of one `Location` is refused. The architecture lanes, s390x included,
  verify that signature too.
- **xmlsec1** signs and encrypts every response in the suite, from templates:
  GCM and CBC, RSA-OAEP with SHA-1 and with SHA-256, Response signed,
  assertion signed, both. The Linux test lane, the race detector and the
  coverage lane install it and set `SAML_REQUIRE_JUDGE`.
- **crewjam/saml's IdP** writes whole responses to this SP's AuthnRequests in a
  separate CI job (`interop/crewjam`, a module of its own, not in the published
  module): RSA-SHA256 with AES-128-CBC and the Response signed is accepted; its
  default RSA-SHA1 is refused; the same CBC assertion with the Response
  signature removed is refused before decryption.

The coverage lane's floor is 92%.

## Reference

[pkg.go.dev/github.com/go-authn/saml@v0.4.1](https://pkg.go.dev/github.com/go-authn/saml@v0.4.1)
