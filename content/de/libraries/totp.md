---
title: "totp – ein Code, einmal, und nicht eine Million Rateversuche"
linkTitle: "totp"
weight: 20
description: "go-authn/totp prüft Einmalcodes nach RFC 6238, lehnt einen bereits verwendeten Code ab, begrenzt das Raten pro Geheimnis und bietet das Ergebnis als mfa-Faktor an."
tags: [libraries, totp, factors]
---

**Ist dieser sechsstellige Code richtig – und wurde er schon einmal verwendet?** Zeitbasierte
Einmalpasswörter (RFC 6238), ein `Verifier`, der sich merkt, was ein Server sich merken muss,
und der [mfa]({{< relref "/libraries/mfa.md" >}})-Faktor, den eine Richtlinie verlangt.

```sh
go get github.com/go-authn/totp@v0.4.1
```

Seine einzige Abhängigkeit ist `go-authn/mfa`.

Die Standardwerte sind das, wovon jedes Telefon ausgeht: sechs Ziffern, alle 30 Sekunden,
HMAC-SHA1, ein Schritt Toleranz in jede Richtung. `Options` ändert `Digits`,
`Period`, `Algorithm` (`SHA1`, `SHA256`, `SHA512`) und `Window`.

## Beispiel {#example}

```go
package main

import (
	"fmt"
	"time"

	"github.com/go-authn/totp"
)

func main() {
	secret, err := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	if err != nil {
		panic(err)
	}
	now := time.Date(2026, 10, 10, 12, 0, 0, 0, time.UTC)
	o := totp.Options{Now: func() time.Time { return now }}

	code, _ := totp.At(secret, now, o) // what the phone shows
	fmt.Println(code)

	v := &totp.Verifier{Options: o}
	fmt.Println(v.Verify("dora", secret, []byte(code))) // accepted
	fmt.Println(v.Verify("dora", secret, []byte(code))) // the same code again
	fmt.Println(v.Verify("Dora", secret, []byte(code))) // another spelling, same secret

	// A secret shorter than 128 bits makes no code.
	short, _ := totp.ParseSecret("JBSWY3DPEHPK3PXP")
	_, err = totp.At(short, now, o)
	fmt.Println(err)
}
```

```
395621
<nil>
totp: that code has already been used
totp: that code has already been used
totp: a secret of 80 bits; RFC 4226 requires at least 128
```

In einer Richtlinie wird der Code zu einem Faktor der Art `Possession`, neben dem, was
das Passwort prüft:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/mfa"
	"github.com/go-authn/totp"
)

// knows stands in for whatever checks the password.
type knows struct{}

func (knows) Name() string                 { return "your password" }
func (knows) Kind() mfa.Kind               { return mfa.Knowledge }
func (knows) Verify(context.Context) error { return nil }

func main() {
	ctx := context.Background()
	secret, _ := totp.ParseSecret("JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP")
	verifier := &totp.Verifier{} // one per server, kept: it remembers used codes
	code := []byte("123456")     // what the person typed

	_, err := mfa.Verify(ctx, mfa.Policy{Count: 2, DistinctKinds: true},
		knows{},
		totp.Factor("dora", secret, code, verifier),
	)
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
```

Ein am Telefon vorgelesener Code ist kein Besitz mehr; die
Einordnung ist das, worauf sich `DistinctKinds` verlässt.

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Einen bereits akzeptierten Code.** RFC 6238 §5.2: Der Verifier MUST NOT einen
zweiten Versuch mit einem OTP akzeptieren, das bereits erfolgreich war. Das zustandslose `totp.Verify`
kann das nicht – es hält zwischen den Aufrufen nichts fest –, daher verwendet ein Server einen `*Verifier`, der
mit `ErrUsed` jeden Schritt **bis einschließlich** des letzten ablehnt, den er
akzeptiert hat: Ein Code von vor dreißig Sekunden liegt noch innerhalb des Standardfensters.

**Einen `Factor` ohne `Verifier`.** `totp.Factor` mit einem nil-`*Verifier`
lehnt jeden Code ab und meldet, dass ein Verifier fehlt. Das wird nicht als
nicht verfügbar gemeldet, sodass eine Richtlinie nicht mit den anderen Faktoren durchkommen und den Fehler verbergen kann.

**Raten, pro Geheimnis.** Ein `Verifier` zählt falsche Codes pro **Zugangsnachweis** –
dem Geheimnis, nur als sein SHA-256 gehalten –, nicht pro Name, denn der Name ist
irgendeine Zeichenkette, die der Aufrufer übergibt, und `dora`, `Dora` und `DORA` waren einst
drei Zähler für ein Geheimnis.

| Feld | Standard | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | falsche Codes in Folge vor `ErrThrottled`; der zwischenzeitlich gesendete Code wird nicht angesehen, also kommt nicht einmal der richtige durch |
| `Pause` | `DefaultPause` = 15 Minuten | wie lange das dauert |
| `Lockout` | `DefaultLockout` = 100 | falsche Codes in Folge, wie weit auch immer verteilt, vor `ErrLockedOut`, das nur `Forget` aufhebt (NIST SP 800-63B §5.2.2) |

Nur ein falscher Code zählt; eine Wiederholung, ein Code der falschen Länge oder ein abgelehnter
Parameter bringt eine Pause nicht näher. Die gesamte Prüfung erfolgt unter einer
Sperre, sodass gleichzeitig gesendete Rateversuche einzeln gezählt werden.
`errors.Is(err, totp.ErrThrottled)` ist für beide Ablehnungen wahr.

**Parameter, die nicht richtig sein können:**

- ein Geheimnis unter 128 Bit (`MinSecret` = 16 Bytes, RFC 4226 R6), in
  `Generate`, `At`, `Verify` und `Verifier.Verify`. `ParseSecret` liest ein solches
  trotzdem: Es ist ein Parser;
- eine Periode, die keine ganze Zahl von Sekunden ist oder unter einer Sekunde liegt;
- weniger als 6 oder mehr als 10 Ziffern (RFC 4226 §5.3);
- ein Fenster, das breiter ist als `MaxWindow` = 10 Schritte in jede Richtung. `0` bedeutet den
  Standard von einem Schritt; `NoWindow` akzeptiert nur den aktuellen Schritt.

Jeder Schritt im Fenster wird ohne vorzeitigen Abbruch ausprobiert, und der Vergleich erfolgt
in konstanter Zeit. `ErrWrongCode` ist derselbe Fehler für „falsch“ und „zu alt“.

{{< callout type="warning" >}}
**Das Geheimnis ist der Zugangsnachweis**

Wer es besitzt, erzeugt jeden künftigen Code. Keine Fehlermeldung hier zitiert einen
Code oder ein Geheimnis, und `URI` – die `otpauth://`-Zeichenkette, die eine Authenticator-App
aus einem QR-Code liest – trägt das Geheimnis konstruktionsbedingt: Sie ist für die Person
bestimmt, die sich registriert, und für niemanden sonst.
{{< /callout >}}

Der Speicher des `Verifier` ist der dieses Prozesses. Zwei Server hinter einem Load Balancer
lehnen jeweils ihre eigenen Wiederholungen ab und zählen ihre eigenen Rateversuche; eine Installation, die
eine einzige Antwort braucht, setzt einen gemeinsamen Speicher hinter dieselbe Schnittstelle.

## Wogegen es geprüft wird {#what-it-is-checked-against}

- **pyotp**, eine Python-Implementierung: 200 zufällige Fälle über Geheimnislängen
  ab 16 Bytes, 6 bis 10 Ziffern, vier Perioden und alle drei Algorithmen
  (`differential_test.go`). Die Linux-Test-Lane, der Race Detector und die
  Coverage-Lane installieren es, und dort macht `TOTP_REQUIRE_JUDGE` aus einem fehlenden
  pyotp einen Fehlschlag statt eines Überspringens.
- **RFC 6238 Anhang B**, alle sechs Zeitpunkte und alle drei Algorithmen, und
  **RFC 4226 Anhang D**, Zähler 0 bis 9.
- Jede Ziffernanzahl über 1000 Schritte pro Algorithmus, gegen RFC 4226 §5.3,
  in beliebiger Genauigkeit nachgerechnet.

Die Coverage-Lane schlägt unter 95 % fehl (ihr erklärter Standard ist 100 %), und die
Tests laufen auf acht Architekturen.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/totp@v0.4.1](https://pkg.go.dev/github.com/go-authn/totp@v0.4.1)
