---
title: "pkcs12 — der Schlüssel und die Zertifikate in einem hochgeladenen .p12"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12 liest PKCS#12-Dateien (.p12 / .pfx, RFC 7292) in reinem Go, gebaut für nicht vertrauenswürdige Uploads: jede Ressourcengrenze ist eine Option, die sich nicht abschalten lässt, und OpenSSL ist der Maßstab."
tags: [bibliotheken, zertifikate, schlüssel]
---

**Welchen privaten Schlüssel und welche Zertifikate enthält diese Datei, die uns jemand geschickt hat?**
PKCS#12 ([RFC 7292](https://www.rfc-editor.org/rfc/rfc7292)) ist der
`.p12`-/`.pfx`-Container, in den ein Exporteur einen Schlüssel, sein Zertifikat
und den Rest der Kette schreibt. `golang.org/x/crypto/pkcs12` ist veraltet und
auf SHA-1 und 3DES/RC2 eingefroren, es weist also zurück, was OpenSSL 3 und 4
und aktuelles Windows standardmäßig schreiben (PBES2, AES, SHA-2-MACs). Dieses
Modul liest sie, ohne Abhängigkeit außer der Standardbibliothek, und ist für
**nicht vertrauenswürdige Uploads** gebaut.

```sh
go get github.com/go-authn/pkcs12@v0.1.0
```

Es **dekodiert nur**: einen Encoder gibt es nicht. Ob der Kette zu trauen ist,
entscheidet `Verify` von `crypto/x509`, eine eigene Entscheidung.

## Beispiel {#example}

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

`Decode(data, password, *Options) (*Bundle, error)` nimmt `nil` für die
Standardwerte. Das `Bundle` enthält den Schlüssel, das Zertifikat, dessen
öffentliche Hälfte er ist, und die übrigen in Dateireihenfolge.

## Optionen und ihre Standardwerte {#options-and-their-defaults}

Ein Feld mit Null bedeutet den Standardwert, und **kein Feld kann eine Grenze
abschalten**.

| Feld | Standard | Bedeutung |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | Iterationen einer einzelnen Schlüsselableitung |
| `MaxWork` | 5 000 000 | Iterationen x Ausgabeblöcke über die ganze Datei |
| `MaxDepth` | 16 | BER-Verschachtelung und Verschachtelung konstruierter String-Teile |
| `MaxBags` | 1024 | SafeBags der Datei |
| `MaxAuthSafes` | 32 | ContentInfos des AuthenticatedSafe |
| `MaxCertSize` | 32 KiB | DER eines Zertifikats |
| `MaxCertBytes` | 512 KiB | DER aller Zertifikate zusammen |
| `MaxRSABits` | 8192 | RSA-Modulus |
| `AllowNoMAC` | `false` | eine Datei ohne Integritäts-MAC lesen (`openssl pkcs12 -nomac`); sonst `ErrNoMAC` |
| `NoPassword` | `false` | die Datei wurde ganz ohne Passwort exportiert, im Unterschied zum leeren Passwort `""` |

Die beiden Booleans sind die zwei Mehrdeutigkeiten des Formats. Mit
`AllowNoMAC` authentifiziert nichts den Inhalt, und ein falsches Passwort fällt
erst durch eine fehlgeschlagene Entschlüsselung auf. Das **leere** Passwort
(`""`) und das **fehlende** Passwort (`NoPassword`) leiten verschiedene
Schlüssel ab, und beide funktionieren: Bei `""` und `NoPassword` gleich false
versucht `Decode` zuerst das leere, dann das fehlende, weil Exporteure sich
nicht einig sind, was sie geschrieben haben; bei `NoPassword` gleich true wird
nur das fehlende versucht, und das Passwortargument muss `""` sein.

## Was es liest {#what-it-reads}

| Schicht | unterstützt |
|---|---|
| Verschlüsselung | PBES2 ([RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)) mit PBKDF2 über HMAC-SHA-1/224/256/384/512 und AES-128/192/256-CBC |
| alte Verschlüsselung | `pbeWithSHAAnd3-KeyTripleDES-CBC`, `pbeWithSHAAnd2-KeyTripleDES-CBC`, `pbeWithSHAAnd40BitRC2-CBC` und die 128-Bit-Variante; RC2 ist im Modul implementiert |
| Integrität | HMAC-MAC mit SHA-1/224/256/384/512 (KDF aus Anhang B der RFC 7292) und **PBMAC1** ([RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)) |
| Passwörter | BMPString nach Anhang B.1, Zeichen außerhalb der BMP als Surrogatpaare |
| Kodierung | BER, einschließlich unbestimmter Längen und konstruierter OCTET STRINGs, wie Windows und Java sie schreiben |
| Bags | verschleierte und einfache Schlüssel-Bags, Zertifikat-Bags; CRL-, Secret- und Safe-Contents-Bags werden übersprungen |

**Als `ErrUnsupported` abgelehnt:** Integritäts- und Datenschutzmodi mit
öffentlichem Schlüssel (`signedData`, `envelopedData`), RC4, scrypt, PBES1
außer den PKCS#12-eigenen, SHA-1 in PBMAC1 und BER (statt DER) in einem
Zertifikat oder einem PKCS#8-Schlüssel.

## Fehler {#errors}

| Fehler | bedeutet |
|---|---|
| `ErrMalformed` | keine PKCS#12-Datei, die dieses Paket lesen kann |
| `ErrUnsupported` | lesbar, aber mit etwas, das hier nicht implementiert ist |
| `ErrLimit` | eine Grenze aus `Options` würde überschritten; vor der Arbeit abgelehnt |
| `ErrIncorrectPassword` | ein falsches Passwort und eine manipulierte Datei, bewusst dieselbe Antwort |
| `ErrNoMAC` | kein MAC, und `AllowNoMAC` ist nicht gesetzt |
| `ErrNoPrivateKey` | kein privater Schlüssel in der Datei |
| `ErrMultipleKeys` | mehr als ein privater Schlüssel in der Datei |
| `ErrNoCertificate` | kein Zertifikat passt zum privaten Schlüssel |
| `ErrPassword` | ein unbrauchbares Passwort |

Jede Ablehnung umhüllt genau einen davon, und das Fuzz-Ziel hält das als
Invariante.

## Die Sicherheitsgrenzen {#the-security-bounds}

Jede obige Grenze wird **vor der Arbeit** geprüft, und jedes Längenfeld wird
gegen die tatsächlich vorhandenen Bytes geprüft, bevor etwas alloziert wird.
Salze über 512 Bytes und Passwörter über 1024 Zeichen werden abgelehnt.

Das MAC wird **in konstanter Zeit, bevor irgendetwas entschlüsselt wird**,
geprüft.

`crypto/x509` alloziert bis zum 43- bis 52-Fachen der Größe eines Zertifikats,
wenn es aus Tausenden winziger Namen besteht, und `crypto/rsa` validiert einen
Schlüssel durch Arithmetik auf den Zahlen, die er angibt, sodass Faktoren, die
weit länger als der Modulus sind, überlinear CPU kosten. Beides lässt sich von
außen nicht beheben, also wird zuerst begrenzt, was dorthin gelangt:
Zertifikate durch `MaxCertSize` und `MaxCertBytes`, und jeder PKCS#8-Schlüssel
(höchstens 32 KiB) wird mit `encoding/asn1` gelesen und typisiert abgelehnt,
wenn sein Modulus `MaxRSABits` überschreitet, ein Faktor oder Exponent länger
ist, als der Modulus erlaubt, eine Zahl nicht positiv ist oder er mehr als zwei
Primzahlen hat (`ErrUnsupported`).

**Speicher pro Anfrage.** Mit den Standardoptionen lässt eine feindliche Datei
ein `Decode` etwa 25 MB allozieren (gemeinsam gemessen: schlimmste Zertifikate
und größter akzeptierter Schlüssel, 8192 Bit, 25,1 MB, davon etwa 20 MB bis zur
Rückkehr lebendig) bei einer Datei von 530 KB. Ein Dienst, der Uploads
dekodiert, sollte die gleichzeitigen Dekodierungen begrenzen, etwa mit einem
Semaphor, und `MaxCertBytes` senken, wenn er nur kurze Ketten erwartet.

## Einschränkungen {#limitations}

- **RSA-Schlüssel ohne CRT-Werte werden abgelehnt** (`ErrUnsupported`). Ein
  Schlüssel ohne `Dp`, `Dq` und `Qinv` wird abgelehnt, bevor `crypto/x509` ihn
  sieht. RFC 8017 verlangt sie, und jeder Exporteur schreibt sie (OpenSSL,
  Windows, Javas keytool), aber `crypto/x509` leitet fehlende mit
  Großzahlarithmetik ab: 16,4 MB und 21 744 Allokationen bei 8192 Bit, gegen
  0,36 MB und 618 mit ihnen.
- **[go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2), offen,
  LOW.** Unter `GODEBUG=x509rsacrt=0` verwirft `crypto/x509` ungültige
  CRT-Werte und berechnet sie neu, und die Vorprüfung prüft nur, dass sie
  *vorhanden* sind: Ein 8192-Bit-Schlüssel mit falschen CRT-Werten passiert sie,
  und mit den schlimmsten Zertifikaten erreicht die Dekodierung 39,4 MB
  (Verhältnis 74,7), außerhalb der Grenze, die die Tests behaupten. Das
  verlangt, dass der Betreiber es einschaltet, und die `go.mod` des Moduls
  nennt eine Go-Version, für die diese Einstellung nicht der Standard ist; mit
  Standardeinstellungen wird dieselbe Eingabe als `ErrMalformed` abgelehnt.
- Es dekodiert nur und beurteilt die Kette nicht.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**OpenSSL ist der Maßstab.** 23 von OpenSSL 4.1 geschriebene Dateien
(AES/PBES2, `-legacy` 3DES und RC2, `-nomac`, mehrere Zertifikate, RSA, EC und
Ed25519, PBMAC1) liegen den Tests bei, mit einem Manifest dessen, was OpenSSL
selbst über jede sagt.

**Verstärkung.** `TestAmplification` begrenzt allozierte Bytes über
Eingabebytes bei vielen winzigen Bags, vielen Zertifikaten, tiefer
unbestimmter Verschachtelung, langen OCTET-STRING-Ketten und angegebenen
Längen von 4 GiB und stellt sicher, dass die Ablehnungen vor dem Aufruf von
`crypto/x509` geschehen. Das Modul wird außerdem gefuzzt (Korpus eingecheckt),
hat 100 % Blockabdeckung und läuft mit `-race` und `govulncheck`.

**`software.sslmate.com/src/go-pkcs12`**, in einem getrennten Modul `oracle/`:
Von den 23 Dateien, die beide versuchen können, lesen beide 18 mit
byte-identischem Blatt, identischer Kettenreihenfolge und Schlüssel. Nur dieses
Paket liest die anderen 5 (RC2-128, ein SHA-384-MAC, kein MAC und zwei
Passwörter mit Zeichen außerhalb der BMP); keine liest das andere, die dieses
ablehnt.

Es passt zu [cms]({{< relref "/libraries/cms.md" >}}): hier ein `.p12`
dekodieren, dort signieren.
