---
title: "cms — signatures in CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms reads, verifies and signs CMS SignedData (RFC 5652), the container behind PDF, UEFI and S/MIME signatures, judged by OpenSSL."
tags: [libraries, signatures, certificates]
---

**Does this signature hold over these bytes, and which certificate made it?**
CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)) is the
container a PDF signature, a UEFI authenticated variable and an S/MIME message
are written in. The standard library reads certificates and checks signatures,
but has no CMS.

```sh
go get github.com/go-authn/cms@v0.2.0
```

v0.2.0 **reads, verifies and signs**.

## Example

```go
package main

import (
	"crypto/x509"
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/cms"
)

func main() {
	// A detached signature and the bytes it signed. For a PDF these are the
	// signature dictionary's /Contents and the file's /ByteRange.
	der, err := os.ReadFile("signature.der")
	if err != nil {
		panic(err)
	}
	content, err := os.ReadFile("signed-bytes")
	if err != nil {
		panic(err)
	}

	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content) // nil instead, when the content is attached
	switch {
	case errors.Is(err, cms.ErrInvalid):
		fmt.Println("the signature does not hold:", err)
		return
	case errors.Is(err, cms.ErrUnsupported):
		fmt.Println("a signature this package cannot check:", err)
		return
	case err != nil: // cms.ErrMalformed
		fmt.Println("not a signature:", err)
		return
	}

	// The signature holds. Whether to TRUST who made it is a second question,
	// with inputs of its own: the roots you accept.
	roots := x509.NewCertPool() // fill with the roots you trust
	for _, c := range signers {
		_, err := c.Verify(x509.VerifyOptions{Roots: roots, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}})
		fmt.Println(c.Subject, "chain:", err)
	}
}
```

`Verify` answers whether the signature holds. **Trust** — the certificate's
chain, its validity, its revocation — is a separate decision, which RFC 5652
§5.6 places outside CMS: `crypto/x509` for the chain, and
[go-authn/revocation](https://github.com/go-authn/revocation)'s CRL
verification for what has been taken back.

## Signing

`cms.Sign` writes one DER ContentInfo with **one signer**, from any
`crypto.Signer`: an RSA, ECDSA or Ed25519 key, held in a file, on a card or in
an HSM. Before it returns, it verifies the signature under the certificate, so a
signer that hands back a wrong signature is refused, never emitted.

```go
package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/go-authn/cms"
)

func main() {
	// A key and a self-signed certificate, for the example. In practice the
	// key may live on a card or in an HSM: any crypto.Signer will do.
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "signer"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		panic(err)
	}
	cert, err := x509.ParseCertificate(certDER)
	if err != nil {
		panic(err)
	}

	content := []byte("the bytes to sign")
	der, err := cms.Sign(content, cms.SignOptions{
		Signer:      key,
		Certificate: cert,
		Hash:        crypto.SHA256,
		Detached:    true, // as a PDF signature: the content is not inside
		SigningTime: time.Now(),
	})
	switch {
	case errors.Is(err, cms.ErrSigner):
		panic(fmt.Sprint("the key or the device failed: ", err))
	case errors.Is(err, cms.ErrOptions):
		panic(fmt.Sprint("the request is wrong: ", err))
	case err != nil: // cms.ErrUnsupported
		panic(err)
	}

	// Sign checked its own signature; Verify is the reader's side.
	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content)
	if err != nil {
		panic(err)
	}
	fmt.Println("signed by", signers[0].Subject.CommonName)

	content[0] ^= 1
	_, err = sd.Verify(content)
	fmt.Println("altered content:", errors.Is(err, cms.ErrInvalid))
}
```

`SignOptions` also takes `Chain` (intermediates to embed), `PSS` (RSASSA-PSS),
`SigningCertificateV2` (RFC 5035, what CAdES and PAdES baseline require),
`ContentType`, `NoSignedAttrs` and `Rand`. The digest is SHA-256 by default, or
SHA-384 or SHA-512; Ed25519 always uses SHA-512. SHA-1 is refused.

`Sign` has three errors of its own: `ErrOptions` (the request is wrong),
`ErrSigner` (the key or device failed, or returned a signature that does not
verify under the certificate) and `ErrUnsupported` (an algorithm it does not
write). Ed25519 **without signed attributes** is refused too: RFC 8419 allows
it, but OpenSSL does not verify what this package would write.

OpenSSL's `cms -verify` and this package's `Verify` agree on every combination
it was asked about: **58 combinations, 203 verdicts**, over RSA PKCS #1 v1.5,
RSA-PSS and ECDSA P-256 with SHA-256, SHA-384 and SHA-512, and Ed25519 with
SHA-512, attached and detached, with and without signed attributes. `Verify`
does not yet check signing-certificate-v2: pinning the signer's certificate to
that attribute is the caller's.

## Three errors, because a caller needs three answers

| error | means |
|---|---|
| `ErrMalformed` | not a SignedData this package can read |
| `ErrUnsupported` | a signature, using something not implemented here |
| `ErrInvalid` | readable and supported, and the signature does not hold |

Every refusal wraps exactly one of them, and the fuzz tests hold that as an
invariant.

## What it refuses

From the code, each with a test that asserts its message:

- a signer whose certificate is not in the container;
- signed attributes without exactly one `content-type` and exactly one
  `message-digest`, each with a single value;
- a signed content type that is not the content's;
- a digest that does not match the content — **recomputed here**, never taken
  from the signer;
- a signature algorithm whose own hash is not the digest's;
- SHA-1, refused by name;
- Ed25519 over anything but SHA-512 (RFC 8419);
- signed attributes in four non-DER shapes: a primitive `[0]` tag (one bit
  away from a valid signature), an attribute that is not a SEQUENCE, values
  that are not a SET, and bytes trailing inside an attribute. The order of the
  SET is not checked;
- more than **16 signers**, and more than **16 MiB**. A size bound is not a
  work bound, which is why the signers are capped: the content is hashed once
  per digest algorithm, but an Ed25519 signer without signed attributes still
  hashes all of it on every check.

**Not yet:** BER indefinite lengths are refused rather than guessed at;
signing is one signer, with no counter-signatures and no timestamp token;
`Verify` does not check signing-certificate-v2; no chain validation, on
purpose.

## What it is checked against

**OpenSSL's `cms` command.** Eleven signatures made by OpenSSL 4.1.0 cover RSA,
RSA-PSS, ECDSA and Ed25519, with attached and detached content and both
signer-identifier forms. `openssl cms -verify` and this package give the same
verdict on every one and on its tampered variants: 34 of 34.

On two points the package is **stricter** than OpenSSL 4.1.0, which accepts a
primitive signed-attributes tag and Ed25519 over SHA-256.
