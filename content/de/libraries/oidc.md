---
title: "oidc – ein Bearer-Token prüfen"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc prüft ein OpenID-Connect-Token und macht daraus eine Identität: Discovery, die Schlüsselmenge, eine Allowlist für Algorithmen und die Ablehnungen, auf die es ankommt. Keine Abhängigkeiten."
tags: [libraries, oidc, tokens]
---

**Wer fragt laut diesem Bearer-Token, und sollte man es glauben?**
Discovery, die Schlüsselmenge und die Prüfungen, die ein Resource Server vornehmen muss – in reinem
Go, **ohne Abhängigkeiten** außerhalb der Standardbibliothek.

```sh
go get github.com/go-authn/oidc@v0.4.0
```

Hier gibt es keinen Anmeldeablauf: keine Weiterleitung, keinen Code-Austausch, kein Client-Geheimnis,
keine Cookies. Dies ist die **Resource-Server**-Hälfte – etwas kommt mit einem
Token an, und dies hier sagt, wer das ist.

## Beispiel {#example}

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

Ein `Verifier` ist sicher für nebenläufige Nutzung und hält die Schlüsselmenge: Erzeugen Sie einen beim
Start und behalten Sie ihn. Der Fehler von `Verify` sagt, welche Prüfung das Token abgelehnt hat, für
das Log des Servers; der Client erhält eine einzige Ablehnung, welche Prüfung es auch war.

Drei Konfigurationen, die `New` ablehnt, bevor irgendetwas abgerufen wird:

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

Der Rest von `Config` ist optional: `JWKSURL` überspringt die Discovery; `UsernameClaim`
und `GroupsClaim` (Standard `groups`) benennen die Claims; `ClockSkew` und
`MinRefresh` stehen standardmäßig auf einer Minute; `Client` ist der HTTP-Client, für einen Proxy,
eine private CA oder ein Timeout. Ein `Token` liest `Subject`, `Issuer`, `Audience`,
`Email`, `EmailVerified`, `Username`, `Groups`, `Expiry`, `NotBefore` und
`IssuedAt`; `Claim(name, &v)` dekodiert jeden anderen Claim, und `Has(name)` sagt,
ob er vorhanden ist.

## Was es akzeptiert {#what-it-accepts}

Zehn Signaturalgorithmen, als **Allowlist**: `RS256` `RS384` `RS512`,
`PS256` `PS384` `PS512`, `ES256` `ES384` `ES512` und `EdDSA` (Ed25519). Ein
Token, dessen `alg` keiner davon ist, wird abgelehnt, bevor irgendein Schlüssel abgerufen wird.
`alg: none` und die HMAC-Familie werden abgelehnt, weil sie nicht auf der Liste stehen, und der
Schlüssel muss zur Art des Algorithmus passen: Ein Token, das `RS256` angibt, wird mit
einem RSA-Schlüssel geprüft oder abgelehnt.

## Was es ablehnt und warum {#what-it-refuses-and-why}

| | warum |
|---|---|
| `alg: none` | ein Token, das von sich sagt, es sei unsigniert, ist ein JSON-Objekt, das jemand eingetippt hat |
| HMAC gegen einen öffentlichen Schlüssel | `HS256` verwendet ein gemeinsames Geheimnis, und der Schlüssel des Ausstellers ist öffentlich: Jeder könnte ein Token ausstellen |
| ein Aussteller, der lediglich mit dem richtigen **beginnt** | `iss` wird als Ganzes verglichen: `https://login.example.org.evil.test` beginnt mit der richtigen Zeichenkette |
| eine fehlende oder falsche **Audience** | ein für einen anderen Dienst ausgestelltes Token ist gültig; es ist nicht an diesen adressiert |
| ein Token **ohne Ablauf** | es ist ein Passwort, das jemand einmal kopieren kann |
| ein Aussteller, eine Schlüsselmenge oder eine Weiterleitung **über Klartext-HTTP**, außer zu Loopback | die Schlüsselmenge entscheidet über jede Signatur |
| ein RSA-Schlüssel unter 2048 Bit oder mit `n` oder `e` nicht in kürzester Form; ein EC-Punkt, der nicht auf seiner Kurve liegt | ein kurzer Schlüssel ist eine Signatur, die jemand anderes erzeugen kann; ein aufgefüllter Modulus ging einst als 2048 Bit durch |
| ein Schlüssel, der mit einem anderen `use` als `sig` veröffentlicht ist | eine Schlüsselmenge enthält legitimerweise auch Verschlüsselungsschlüssel |
| bei gesetztem `Type` ein Token mit anderem `typ`; ohne, jedes `typ` außer keinem, `JWT` oder `at+jwt` | RFC 9068 §4: Ein Resource Server prüft `typ: at+jwt`, sonst hält er ein ID-Token für ein Access-Token, sobald die Audiences übereinstimmen |
| ein Teil, der kein kanonisches base64url ist | ein Token wird als eine Zeichenkette geprüft |

Bei ECDSA werden sowohl `s` als auch `n − s` verifiziert, wie es der Algorithmus erlaubt. Daher verwendet eine Denylist oder
ein Replay-Cache `jti` oder `sub` als Schlüssel, nie das Token, wie es gesendet wurde.

**Schlüssel rotieren, und ein unbekannter Schlüssel ist kein Mittel, den Aussteller zu bestürmen.** Eine
Signatur, die nichts Vorhandenes verifizieren kann, ist einen erneuten Abruf der Schlüsselmenge pro
`MinRefresh` wert, ob die `kid` neu ist oder dieselbe `kid` einen neuen Schlüssel trägt.
Tokens, die die Schlüsselmenge brauchen, während ein Abruf läuft, warten darauf, und ein
Abruf, der fehlschlägt, zählt trotzdem.

**Welchen Namen `Username()` liefert.** Standardmäßig `preferred_username`, dann
`email` **nur, wenn `email_verified` true ist**, dann `sub`. Eine nicht verifizierte E-Mail-Adresse
ist eine Zeichenkette, die die Person eingetippt hat (OIDC Core §5.1). Ein konfigurierter `UsernameClaim` wird
so gelesen, wie er benannt ist, ohne Rückfall.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**pyjwt** signiert jedes Token in der Testsuite, sodass der Verifier nie von
einem Signierer aus denselben Händen beurteilt wird. Das HMAC-Verwechslungs-Token wird von Hand gefälscht,
weil pyjwt sich weigert, es zu erzeugen. `testdata/fixed.json` – Tokens, die pyjwt
einmal mit einem festen Schlüssel signiert hat – lässt die Architektur-Lanes, s390x eingeschlossen,
echte Signaturen bei festgehaltener Uhr prüfen. Die Linux-Test-Lane, der Race
Detector und die Coverage-Lane installieren pyjwt und setzen `OIDC_REQUIRE_JUDGE`, sodass ein
fehlendes pyjwt zum Fehlschlag führt, statt übersprungen zu werden. HMAC zu akzeptieren, den Aussteller per
Präfix zu vergleichen und die Audience-Prüfung zu überspringen, wurde jeweils absichtlich ausprobiert, und jedes
färbt einen Test rot. Die Untergrenze der Coverage-Lane liegt bei 90 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/oidc@v0.4.0](https://pkg.go.dev/github.com/go-authn/oidc@v0.4.0)
