---
title: "cms — Signaturen in CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms liest, prüft und signiert CMS SignedData (RFC 5652), den Container hinter PDF-, UEFI- und S/MIME-Signaturen, beurteilt von OpenSSL."
tags: [Bibliotheken, Signaturen, Zertifikate]
---

**Hält diese Signatur über diesen Bytes, und welches Zertifikat hat sie
erstellt?** CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652))
ist der Container, in dem eine PDF-Signatur, eine authentifizierte
UEFI-Variable und eine S/MIME-Nachricht geschrieben werden. Die
Standardbibliothek liest Zertifikate und prüft Signaturen, kennt aber kein CMS.

```sh
go get github.com/go-authn/cms@v0.2.1
```

Seit v0.2.1 lehnt `Verify` eine Signatur ohne Attribute ab, deren signierter Inhalt
selbst ein DER-`SET OF Attribute` ist, das sowohl ein Content-Type- als auch ein
Message-Digest-Attribut trägt. Eine Signatur mit signierten Attributen deckt deren DER
ab (RFC 5652 §5.4); ohne den Schlüssel als SignedData ohne signierte Attribute neu
verpackt, dessen Inhalt diese Attribute sind, wurde sie verifiziert und nannte den
Unterzeichner für einen Inhalt, der nie als Inhalt signiert wurde.

v0.2.0 **liest, prüft und signiert**.

## Beispiel {#example}

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

`Verify` beantwortet, ob die Signatur hält. **Vertrauen** — die Kette des
Zertifikats, seine Gültigkeit, sein Widerruf — ist eine eigene Entscheidung,
die RFC 5652 §5.6 außerhalb von CMS ansiedelt: `crypto/x509` für die Kette und
die CRL-Prüfung von
[go-authn/revocation](https://github.com/go-authn/revocation) für das, was
zurückgezogen wurde.

## Signieren {#signing}

`cms.Sign` schreibt ein DER-ContentInfo mit **einem Unterzeichner**, aus jedem
`crypto.Signer`: einem RSA-, ECDSA- oder Ed25519-Schlüssel, in einer Datei, auf
einer Karte oder in einem HSM. Bevor es zurückkehrt, prüft es die Signatur unter
dem Zertifikat; ein Signierer, der eine falsche Signatur liefert, wird
abgelehnt und nie ausgegeben.

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

`SignOptions` kennt außerdem `Chain` (einzubettende Zwischenzertifikate), `PSS`
(RSASSA-PSS), `SigningCertificateV2` (RFC 5035, was die Basisprofile von CAdES
und PAdES verlangen), `ContentType`, `NoSignedAttrs` und `Rand`. Der Hashwert
ist standardmäßig SHA-256, wahlweise SHA-384 oder SHA-512; Ed25519 verwendet
immer SHA-512. SHA-1 wird abgelehnt.

`Sign` hat drei eigene Fehler: `ErrOptions` (die Anfrage ist falsch),
`ErrSigner` (der Schlüssel oder das Gerät ist ausgefallen oder lieferte eine
Signatur, die unter dem Zertifikat nicht prüfbar ist) und `ErrUnsupported` (ein
Algorithmus, den es nicht schreibt). Auch Ed25519 **ohne signierte Attribute**
wird abgelehnt: RFC 8419 erlaubt es, aber OpenSSL prüft nicht, was dieses Paket
schreiben würde.

`cms -verify` von OpenSSL und das `Verify` dieses Pakets stimmen bei jeder
gefragten Kombination überein: **58 Kombinationen, 203 Urteile**, über RSA
PKCS #1 v1.5, RSA-PSS und ECDSA P-256 mit SHA-256, SHA-384 und SHA-512 sowie
Ed25519 mit SHA-512, angehängt und abgetrennt, mit und ohne signierte
Attribute. `Verify` prüft signing-certificate-v2 noch nicht: Das Zertifikat des
Unterzeichners an dieses Attribut zu binden, ist Sache des Aufrufers.

## Drei Fehler, weil ein Aufrufer drei Antworten braucht {#three-errors-because-a-caller-needs-three-answers}

| Fehler | bedeutet |
|---|---|
| `ErrMalformed` | kein SignedData, das dieses Paket lesen kann |
| `ErrUnsupported` | eine Signatur, die etwas verwendet, das hier nicht implementiert ist |
| `ErrInvalid` | lesbar und unterstützt, und die Signatur hält nicht |

Jede Ablehnung umhüllt genau einen davon, und die Fuzz-Tests halten das als
Invariante fest.

## Was es ablehnt {#what-it-refuses}

Aus dem Code, jeweils mit einem Test, der die Meldung prüft:

- einen Unterzeichner, dessen Zertifikat nicht im Container liegt;
- signierte Attribute ohne genau ein `content-type` und genau ein
  `message-digest`, jeweils mit einem einzigen Wert;
- einen signierten Inhaltstyp, der nicht der des Inhalts ist;
- einen Hashwert, der nicht zum Inhalt passt — **hier neu berechnet**, nie vom
  Unterzeichner übernommen;
- einen Signaturalgorithmus, dessen eigener Hash nicht der des Hashwerts ist;
- SHA-1, ausdrücklich abgelehnt;
- Ed25519 über etwas anderes als SHA-512 (RFC 8419);
- signierte Attribute in vier Nicht-DER-Formen: ein primitives `[0]`-Tag (ein
  Bit von einer gültigen Signatur entfernt), ein Attribut, das keine SEQUENCE
  ist, Werte, die kein SET sind, und überzählige Bytes in einem Attribut. Die
  Reihenfolge des SET wird nicht geprüft;
- mehr als **16 Unterzeichner** und mehr als **16 MiB**. Eine Größengrenze ist
  keine Arbeitsgrenze, daher die Obergrenze für Unterzeichner: Der Inhalt wird
  einmal pro Hashalgorithmus gehasht, aber ein Ed25519-Unterzeichner ohne
  signierte Attribute hasht ihn bei jeder Prüfung noch vollständig.

**Noch nicht:** BER mit unbestimmter Länge wird abgelehnt statt geraten; das
Signieren hat einen Unterzeichner, ohne Gegensignaturen und ohne
Zeitstempel-Token; `Verify` prüft signing-certificate-v2 nicht; keine
Kettenprüfung, mit Absicht.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**Den `cms`-Befehl von OpenSSL.** Elf von OpenSSL 4.1.0 erzeugte Signaturen
decken RSA, RSA-PSS, ECDSA und Ed25519 ab, mit angehängtem und abgetrenntem
Inhalt und beiden Formen der Unterzeichner-Kennung. `openssl cms -verify` und
dieses Paket kommen bei jeder und bei ihren manipulierten Varianten zum selben
Urteil: 34 von 34.

In zwei Punkten ist das Paket **strenger** als OpenSSL 4.1.0, das ein
primitives Tag für signierte Attribute und Ed25519 über SHA-256 akzeptiert.
