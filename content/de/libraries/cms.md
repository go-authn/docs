---
title: "cms — Signaturen in CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms liest und prüft CMS SignedData (RFC 5652), den Container hinter PDF-, UEFI- und S/MIME-Signaturen, beurteilt von OpenSSL."
tags: [Bibliotheken, Signaturen, Zertifikate]
---

**Hält diese Signatur über diesen Bytes, und welches Zertifikat hat sie
erstellt?** CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652))
ist der Container, in dem eine PDF-Signatur, eine authentifizierte
UEFI-Variable und eine S/MIME-Nachricht geschrieben werden. Die
Standardbibliothek liest Zertifikate und prüft Signaturen, kennt aber kein CMS.

```sh
go get github.com/go-authn/cms@v0.1.0
```

v0.1.0 **liest und prüft**. Das Signieren folgt im nächsten Release.

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

**Noch nicht:** BER mit unbestimmter Länge wird abgelehnt statt geraten; kein
Signieren; keine Kettenprüfung, mit Absicht.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**Den `cms`-Befehl von OpenSSL.** Elf von OpenSSL 4.1.0 erzeugte Signaturen
decken RSA, RSA-PSS, ECDSA und Ed25519 ab, mit angehängtem und abgetrenntem
Inhalt und beiden Formen der Unterzeichner-Kennung. `openssl cms -verify` und
dieses Paket kommen bei jeder und bei ihren manipulierten Varianten zum selben
Urteil: 34 von 34.

In zwei Punkten ist das Paket **strenger** als OpenSSL 4.1.0, das ein
primitives Tag für signierte Attribute und Ed25519 über SHA-256 akzeptiert.
