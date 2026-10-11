---
title: "krb5 – ein Kerberos-Ticket annehmen"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5 ist die annehmende Hälfte von Kerberos: eine Keytab, ein geprüfter AP-REQ, der AP-REP, den gegenseitige Authentifizierung braucht, und Nachrichten, die mit dem Sitzungsschlüssel signiert und versiegelt werden."
tags: [bibliotheken, kerberos]
---

**Taugt dieses Kerberos-Ticket für diesen Dienst?** Die **annehmende** Hälfte von
Kerberos (Acceptor), und nur diese Hälfte: Sie hält eine Keytab, prüft den AP-REQ, den ein Client
vorlegt, antwortet mit dem AP-REP, der beweist, dass der Dienst echt ist, und
signiert, prüft, versiegelt und öffnet dann Nachrichten mit dem Schlüssel, den dieser Austausch
festgelegt hat.

```sh
go get github.com/go-authn/krb5@v0.3.0
```

Es spricht nie mit einem KDC und stellt nie ein Ticket aus, daher entscheidet jemand anderes,
wessen Tickets es annimmt. Die ausstellende Hälfte ist
[kdc]({{< relref "/libraries/kdc.md" >}}), und dieses Modul hängt nicht davon
ab – siehe [warum sie getrennt sind]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}}).
Die Entschlüsselung der Tickets übernimmt [gokrb5](https://github.com/jcmturner/gokrb5).

## Warum es existiert {#why-it-exists}

gokrb5 ist eine Client-Bibliothek. Sie prüft einen AP-REQ und kann den AP-REP nicht bauen,
der darauf antwortet. Jeder GSS-API-Client verlangt gegenseitige Authentifizierung – MITs
eigener `gss-client` setzt `GSS_C_MUTUAL_FLAG`, ohne dass es sich abschalten ließe –, daher
bringt ein Dienst, der keinen AP-REP erzeugen kann, überhaupt keinen Kontext zustande. Ihn zu bauen,
ist der größte Teil dessen, was dieses Modul hinzufügt.

## Beispiel {#example}

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

Es braucht `github.com/jcmturner/gokrb5/v8` für `keytab.New`, das `krb5.New`
entgegennimmt; `krb5.Load` liest stattdessen eine Keytab aus einem Pfad.

Nach `Accept` sagt ein `*Context`, wer: `Principal()` (`alice@EXAMPLE.ORG`) oder
`User()` und `Realm()` getrennt. Einen Principal auf ein lokales Konto abzubilden, ist die
Richtlinie des Aufrufers: `alice@EXAMPLE.ORG` und `alice@PARTNER.ORG` antworten beide auf
„alice“. `Expires()` ist der Zeitpunkt, zu dem das zugrunde liegende Ticket endet; danach sollte ein Server,
der eine langlebige Verbindung hält, es nicht mehr anerkennen. `MIC`/`VerifyMIC`
und `Wrap`/`Unwrap` signieren; `Seal`/`Unseal` fügen Vertraulichkeit hinzu (`sec=krb5p`).
Ein `Context` ist nicht sicher für nebenläufige Nutzung; ein `Acceptor` schon.

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Ein Ticket, das dieser Dienst nicht annimmt** – falscher Dienst, falscher Schlüssel,
abgelaufen, wiederholt eingespielt, eine Uhr jenseits von `ClockSkew` (standardmäßig fünf Minuten, wie bei
MIT) –, ist `ErrRejected`. Bytes, die kein GSS-API-krb5-Token sind, sind
`ErrNotAToken`, und ein Token, das kein AP-REQ ist, ist `ErrNotAPReq`. Die Fehler
sind absichtlich grob: Ein Client erfährt, dass sein Ticket abgelehnt wurde, nie,
welche Prüfung es abgelehnt hat. Ein Fehler bedeutet keinen Kontext, und das zurückgegebene Token ist
leer.

**Ein Principal, für den der Acceptor nicht antwortet.** Mit
`krb5.Principal("nfs/files.example.org")` antwortet eine Keytab, die mehrere Dienste hält,
nur für diesen einen.

**Eine Nachricht, deren Signatur nicht passt**, ist `ErrBadMIC`, ganz gleich, ob die
Länge, der Header, die Sequenz oder die Prüfsumme abwich. Der Acceptor signiert
mit Key Usage 23 und prüft mit 25, sodass ein Token, das dieser Server erzeugt hat, ihm nicht
zurückgespielt werden kann, als hätte der Client es signiert.

**Ein versiegeltes Token, an `Unwrap` übergeben**, ist `ErrSealed`, verschieden von einer schlechten
Signatur: Einem Aufrufer, der ein nur integritätsgeschütztes Token liest, darf kein
Chiffretext übergeben werden, der sich wie eine Nachricht liest. **Ein unversiegeltes Token, an `Unseal` übergeben**,
ist `ErrNotSealed`: Einem Protokoll, das Vertraulichkeit versprochen hat, wird nichts übergeben,
was die Leitung im Klartext durchquert hat.

Es setzt keinen eigenen Subkey des Acceptors: Der Kontextschlüssel ist der Subkey, den der Initiator
in seinen Authenticator gelegt hat, oder der Sitzungsschlüssel des Tickets, wenn er keinen gesendet hat
(RFC 4121 §4.3).

{{< callout type="warning" >}}
**Eine Keytab ist ein ruhendes Geheimnis**

Ihr Pfad kann aus einer Konfigurationsdatei oder aus `KRB5_KTNAME` kommen; der Schlüssel
darin darf nie geloggt, ausgegeben oder in einer Umgebungsvariablen
transportiert werden.
{{< /callout >}}

## Wogegen es geprüft wird {#what-it-is-checked-against}

**Ein echter MIT-KDC und MITs eigener `gss-client`**, gegen dieses Paket, das
an die Stelle von `gss-server` tritt. `test/kdc.sh` baut einen Wegwerf-Realm auf Loopback,
ohne Privilegien; die CI bezieht MIT Kerberos über pkgx (die Pakete von Ubuntu liefern
`gss-client` nicht mit). Die Linux-Test-Lane, der Race-Detector und die Coverage-Lane
setzen `KRB5_REQUIRE_JUDGE=1`, sodass eine fehlende Fixture zum Fehlschlag führt. Ein weiterer Schritt
führt `TestMITClientAgainstThisAcceptor` aus und schlägt fehl, sofern das Log nicht
„authenticated as alice@“ sagt – eine grüne Lane, deren Prüfstein stillschweigend nicht mehr läuft,
wird nicht akzeptiert. `TestMITClientSealed` tut dasselbe mit eingeschalteter Vertraulichkeit.

Die Lanes für macOS, Windows und andere Architekturen haben keinen Realm, und dort wird der
Prüfstein übersprungen. Die Untergrenze der Coverage-Lane liegt bei 90 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/krb5@v0.3.0](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.0)
