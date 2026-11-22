---
title: "pkcs12 — the key and certificates inside a .p12 upload"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12 reads PKCS#12 (.p12 / .pfx, RFC 7292) files in pure Go, built for untrusted uploads: every resource bound is an option that cannot be switched off, and OpenSSL is the judge."
tags: [libraries, certificates, keys]
---

**What private key and certificates are inside this file somebody sent us?**
PKCS#12 ([RFC 7292](https://www.rfc-editor.org/rfc/rfc7292)) is the `.p12` /
`.pfx` container an exporter writes a key, its certificate and the rest of the
chain into. `golang.org/x/crypto/pkcs12` is deprecated and frozen on SHA-1 and
3DES/RC2, so it rejects what OpenSSL 3 and 4 and current Windows write by
default (PBES2, AES, SHA-2 MACs). This module reads those, with no dependency
beyond the standard library, and is built for **untrusted uploads**.

```sh
go get github.com/go-authn/pkcs12@v0.1.0
```

It **decodes only**: there is no encoder. Whether to trust the chain is
`crypto/x509`'s `Verify`, a separate decision.

## Example {#example}

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/pkcs12"
)

func main() {
	data, err := os.ReadFile("upload.p12")
	if err != nil {
		panic(err)
	}

	b, err := pkcs12.Decode(data, "the password", nil)
	switch {
	case errors.Is(err, pkcs12.ErrIncorrectPassword):
		fmt.Println("ask again:", err)
		return
	case err != nil: // hostile, unsupported, too costly...
		fmt.Println("refused:", err)
		return
	}

	// b.PrivateKey   *rsa.PrivateKey, *ecdsa.PrivateKey, ed25519.PrivateKey or *ecdh.PrivateKey
	// b.Certificate  the certificate holding the key's public half
	// b.CACerts      every other certificate, in file order
	fmt.Println("certificate for", b.Certificate.Subject, "and", len(b.CACerts), "more")
}
```

`Decode(data, password, *Options) (*Bundle, error)` takes `nil` for the
defaults. The `Bundle` holds the key, the certificate whose public half it is,
and the others in file order.

## Options and their defaults {#options-and-their-defaults}

A zero field means the default, and **no field can switch a bound off**.

| field | default | meaning |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | iterations of any one key derivation |
| `MaxWork` | 5 000 000 | iterations x output blocks over the whole file |
| `MaxDepth` | 16 | BER nesting and constructed-string chunk nesting |
| `MaxBags` | 1024 | SafeBags in the file |
| `MaxAuthSafes` | 32 | ContentInfos in the AuthenticatedSafe |
| `MaxCertSize` | 32 KiB | DER of one certificate |
| `MaxCertBytes` | 512 KiB | DER of all certificates together |
| `MaxRSABits` | 8192 | RSA modulus |
| `AllowNoMAC` | `false` | read a file with no integrity MAC (`openssl pkcs12 -nomac`); otherwise it is `ErrNoMAC` |
| `NoPassword` | `false` | the file was exported with no password at all, as opposed to the empty password `""` |

The two booleans are the format's two ambiguities. With `AllowNoMAC`, nothing
authenticates the content, and a wrong password is only noticed by a failed
decryption. The **empty** password (`""`) and the **absent** password
(`NoPassword`) derive different keys and both work: with `""` and `NoPassword`
false, `Decode` tries the empty one first and then the absent one, because
exporters disagree about which they wrote; with `NoPassword` true only the
absent one is tried, and the password argument must be `""`.

## What it reads {#what-it-reads}

| layer | supported |
|---|---|
| encryption | PBES2 ([RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)) with PBKDF2 over HMAC-SHA-1/224/256/384/512 and AES-128/192/256-CBC |
| legacy encryption | `pbeWithSHAAnd3-KeyTripleDES-CBC`, `pbeWithSHAAnd2-KeyTripleDES-CBC`, `pbeWithSHAAnd40BitRC2-CBC` and the 128-bit variant; RC2 is implemented in the module |
| integrity | HMAC MAC with SHA-1/224/256/384/512 (RFC 7292 Appendix B KDF), and **PBMAC1** ([RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)) |
| passwords | BMPString per Appendix B.1, non-BMP characters as surrogate pairs |
| encoding | BER, including indefinite lengths and constructed OCTET STRINGs, which Windows and Java write |
| bags | shrouded and plain key bags, certificate bags; CRL, secret and safe-contents bags are skipped |

**Refused as `ErrUnsupported`:** public-key integrity and privacy modes
(`signedData`, `envelopedData`), RC4, scrypt, PBES1 other than the PKCS#12
ones, SHA-1 inside PBMAC1, and BER (rather than DER) inside a certificate or a
PKCS#8 key.

## Errors {#errors}

| error | means |
|---|---|
| `ErrMalformed` | not a PKCS#12 file this package can read |
| `ErrUnsupported` | readable, using something not implemented here |
| `ErrLimit` | a bound of `Options` would be exceeded; refused before the work |
| `ErrIncorrectPassword` | a wrong password and a tampered file, the same answer by design |
| `ErrNoMAC` | no MAC, and `AllowNoMAC` is not set |
| `ErrNoPrivateKey` | no private key in the file |
| `ErrMultipleKeys` | more than one private key in the file |
| `ErrNoCertificate` | no certificate matches the private key |
| `ErrPassword` | a password that cannot be used |

Every refusal wraps exactly one of them, and the fuzz target holds that as an
invariant.

## The security bounds {#the-security-bounds}

Every bound above is checked **before the work**, and every length field is
checked against the bytes actually present before anything is allocated. Salts
over 512 bytes and passwords over 1024 characters are refused.

The MAC is verified, **in constant time, before anything is decrypted**.

`crypto/x509` allocates up to 43 to 52 times a certificate's size when it is
made of thousands of tiny names, and `crypto/rsa` validates a key by arithmetic
on the numbers it declares, so factors far longer than the modulus cost
superlinear CPU. Neither can be fixed from outside, so what reaches them is
bounded first: certificates by `MaxCertSize` and `MaxCertBytes`, and every
PKCS#8 key (32 KiB at most) is read with `encoding/asn1` and refused, typed,
when its modulus exceeds `MaxRSABits`, a factor or exponent is longer than the
modulus allows, a number is not positive, or it is multi-prime
(`ErrUnsupported`).

**Memory per request.** With the default options, a hostile file makes one
`Decode` allocate about 25 MB (measured jointly: worst certificates and the
largest accepted key, 8192 bits, 25.1 MB, of which about 20 MB stay live until
it returns) for a file of 530 KB. A service decoding uploads should cap the
decodes in flight, for instance with a semaphore, and lower `MaxCertBytes` if
it expects only short chains.

## Limitations {#limitations}

- **RSA keys without CRT values are refused** (`ErrUnsupported`). A key lacking
  `Dp`, `Dq` and `Qinv` is refused before `crypto/x509` sees it. RFC 8017
  requires them and every exporter writes them (OpenSSL, Windows, Java
  keytool), but `crypto/x509` derives missing ones with big-number arithmetic:
  16.4 MB and 21 744 allocations at 8192 bits, against 0.36 MB and 618 with
  them.
- **[go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2), open,
  LOW.** Under `GODEBUG=x509rsacrt=0`, `crypto/x509` drops invalid CRT values
  and computes them again, and the preflight checks only that they are
  *present*: an 8192-bit key with wrong CRT values then passes it, and with the
  worst certificates the decode reaches 39.4 MB (ratio 74.7), outside the bound
  the tests assert. It needs the operator to opt in, and the module's `go.mod`
  declares a Go version for which that setting is not the default; with
  default settings the same input is refused as `ErrMalformed`.
- It decodes only, and does not judge the chain.

## What it is checked against {#what-it-is-checked-against}

**OpenSSL is the judge.** 23 files written by OpenSSL 4.1 (AES/PBES2,
`-legacy` 3DES and RC2, `-nomac`, several certificates, RSA, EC and Ed25519,
PBMAC1) are in the tests, with a manifest of what OpenSSL itself says each
holds.

**Amplification.** `TestAmplification` bounds allocated bytes over input bytes
on many tiny bags, many certificates, deep indefinite nesting, long OCTET
STRING chains and 4 GiB length claims, and asserts that the refusals happen
before `crypto/x509` is called. The module is also fuzzed (corpus committed),
holds 100 % block coverage and is run with `-race` and `govulncheck`.

**`software.sslmate.com/src/go-pkcs12`**, in a separate `oracle/` module: on
the 23 files both can attempt, both read 18 with byte-identical leaf, chain
order and key. Only this package reads the other 5 (RC2-128, a SHA-384 MAC, no
MAC, and two passwords with characters outside the BMP); there is none the
other reads and this one refuses.

It pairs with [cms]({{< relref "/libraries/cms.md" >}}): decode a `.p12` here,
sign there.
