---
title: "keyfactor – der registrierte Schlüssel, berührt"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor macht aus einem Sicherheitsschlüssel einen mfa-Faktor und prüft die Antwort gegen die Registrierung, statt jedem Gerät zu vertrauen, das CTAP spricht."
tags: [bibliotheken, fido, mfa, faktoren]
---

**Hat der Schlüssel geantwortet, der registriert wurde, und hat eine Person ihn berührt?**
`keyfactor` ist das eine Stück zwischen [fido]({{< relref "/libraries/fido.md" >}}),
das CTAP spricht und keine Richtlinie kennt, und
[mfa]({{< relref "/libraries/mfa.md" >}}), das entscheidet, wie viel Nachweis
genug ist, und kein Gerät kennt. Keines importiert das andere; dieses importiert beide.

```sh
go get github.com/go-authn/keyfactor@v0.4.1
```

In v0.4.1 verlangt sein `go.mod` mindestens `go-authn/fido` v0.6.0 und
`go-authn/mfa` v0.5.0: Mindestversionen, sodass ein Programm, das fido v0.6.1 verlangt, die
Version, die diese Seiten beschreiben, mit v0.6.1 gebaut wird.

Die Plattform liefert einen `Opener` – wie ein Schlüssel auf diesem System gefunden wird – und
behält nur diesen. Alles andere ist überall gleich, wo es CTAP gibt: die Assertion,
die Prüfungen, die Weigerung, den letzten PIN-Versuch einer Person zu verbrauchen.

## Beispiel {#example}

```go
package main

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"

	"github.com/go-authn/fido"
	"github.com/go-authn/keyfactor"
	"github.com/go-authn/mfa"
)

func main() {
	// The platform supplies the Opener: how a key is found on this system.
	// This one finds nothing, and says so the way a policy understands.
	open := func(context.Context) (fido.Transport, error) {
		return nil, keyfactor.Unavailable(errors.New("no security key is plugged in"))
	}

	// From the registration: the credential ID and its public key, which
	// fido.AuthData.PublicKey returns from the attestation.
	var pub *ecdsa.PublicKey // nil here, to show the refusal

	f := keyfactor.New(open, keyfactor.Options{
		RPID:         "example.test",
		CredentialID: []byte{0x01, 0x02},
		PublicKey:    pub,
	})
	fmt.Println(f.Name(), f.Kind())

	_, err := mfa.Verify(context.Background(), mfa.Policy{Count: 1}, f)
	fmt.Println(err)
}
```

```
your security key possession
mfa: 1 factor(s) needed, 0 answered: your security key (possession): keyfactor: no public key for the credential; without one any device that answers would pass, so pass the one from the registration
```

Die Ablehnung kommt, bevor der `Opener` aufgerufen wird. Mit dem öffentlichen Schlüssel
aus der Registrierung öffnet derselbe Faktor den Schlüssel, fordert von ihm eine Assertion über eine
frische zufällige Challenge an und prüft die Antwort.

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Dass ein Gerät antwortet, heißt nicht, dass der Schlüssel antwortet.** Eine programmierbare USB-Platine
spricht CTAP ebenso gut wie ein Sicherheitsschlüssel, daher wird die Antwort gegen
die Registrierung geprüft:

| abgelehnt | Meldung |
|---|---|
| bevor irgendetwas geöffnet wird: kein `Opener`, keine `RPID`, kein `PublicKey` oder ein Schlüssel nicht auf P-256 | `keyfactor: no opener; …`, `… needs a relying party id …`, `… no public key for the credential; …`, `… is not on P-256 …` |
| ein Relying-Party-Hash, der nicht SHA-256 von `RPID` ist | `… answered for another relying party` |
| ein anderes Credential als `CredentialID`, wenn das Gerät eines nennt | `… answered with a credential other than the one asked for` |
| eine Signatur über die Authenticator-Daten und die Challenge, die nicht von `PublicKey` stammt | `… answered with a signature the credential's key did not make` |
| kein `UP`-Flag | `… answered without anyone touching it` |
| kein `UV`-Flag, wenn eine `PIN` angegeben wurde | `… was asked to establish who holds it and did not` |

**Der letzte PIN-Versuch wird nicht auf einen Rateversuch verschwendet.** Zuerst wird `PINRetries` abgefragt;
ein Schlüssel, der bis zum Abziehen keine PINs mehr annimmt, wird abgelehnt, ebenso
einer, dem **ein Versuch oder weniger** bleibt. Nach CTAP sperren drei falsche PINs hintereinander
die PIN eines Schlüssels, bis er abgezogen wird, und ein Versuchszähler, der null erreicht, sperrt
sie endgültig: Nur ein Reset hebt das auf und löscht dabei jedes Credential auf ihm.

**Eine PIN ist kein zweiter Faktor.** Die Art bleibt `mfa.Possession`: Eine in den Schlüssel
eingegebene PIN schützt den Schlüssel und identifiziert gegenüber dieser Maschine niemanden.

**Ein leerer Port ist keine Ablehnung.** Ein `Opener`, der nichts findet, umhüllt seinen
Fehler mit `keyfactor.Unavailable`, was ihn als `mfa.ErrUnavailable` kennzeichnet, und eine
Richtlinie zählt *konnte nicht gefragt werden* getrennt von *hat Nein gesagt*.

{{< callout type="warning" >}}
**Was es nicht schützen kann: Der Hash der PIN erreicht jedes Gerät, das antwortet**

CTAP lässt die Plattform dem Schlüssel `LEFT(SHA-256(PIN), 16)` übergeben, verschlüsselt mit einem
mit dem Gerät selbst vereinbarten Geheimnis, bevor irgendetwas signiert wird. Ein gefälschtes
Gerät wird als Faktor abgelehnt, hat diesen Hash aber erhalten, und eine kurze PIN
fällt einer Offline-Suche zum Opfer. So ist das Protokoll. Verwenden Sie eine lange PIN, und geben Sie
keine in einen Schlüssel ein, dessen Herkunft unbekannt ist.
{{< /callout >}}

## Wogegen es geprüft wird {#what-it-is-checked-against}

Die Tests fälschen **den Authenticator**, nicht den Transport, gebaut aus
dem eigenen exportierten Framing von go-authn/fido: ein CTAPHID-Handshake, eine CTAP2-Assertion
und ein ClientPIN-Austausch. Die PIN-Hälfte spielt die Seite des Authenticators von
Protokoll zwei unabhängig – mit eigenem ECDH, HKDF und AES-CBC, nach der
Spezifikation geschrieben (`fakepin_test.go`) –, sodass eine Ableitung, die um ein Byte abweicht,
den Austausch scheitern ließe. `forged_test.go` ist das Gerät, das kein
Credential hält. Die Coverage wird bei 100 % gehalten, und die Tests laufen auf acht
Architekturen.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.1](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.1)
