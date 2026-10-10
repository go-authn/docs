---
title: "mfa – genug Faktoren, und welche"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa entscheidet, ob genug Faktoren geantwortet haben, von genug verschiedenen Arten, und sagt, welche – ohne Gerät und ohne Kryptografie."
tags: [libraries, mfa, factors]
---

**Haben genug Faktoren geantwortet, von genug Arten – und welche?** Nichts hier
erreicht ein Gerät, und es gibt keine Kryptografie: Ein `Factor` ist alles, was man
fragen kann: *Ist diese Person hier, jetzt?*, und dieses Paket entscheidet, was die Antworten
zusammen ergeben.

```sh
go get github.com/go-authn/mfa@v0.5.0
```

Es importiert nichts außerhalb der Standardbibliothek.

## Zweimal dasselbe ist ein Faktor {#two-of-the-same-thing-is-one-factor}

Eine Passphrase und ein Wiederherstellungscode sind beides Dinge, die die Person *weiß*: Wer
das eine erfahren hat, hat meist auch das andere an derselben Stelle erfahren. Daher
sagt ein Faktor, was er beweist – `Knowledge`, `Possession` oder `Inherence` –, und die
Richtlinie, die das bedeutet, was man unter *zwei Faktoren* normalerweise versteht, ist
`Policy{Count: 2, DistinctKinds: true}`. `Policy{Count: 2}` allein wird ebenfalls
angeboten, für einen Aufrufer, der absichtlich zwei Schlüssel derselben Art will; das ist eine
andere Anforderung und wird anders geschrieben.

Ein Faktor, dessen `Kind()` `Unknown` ist, zählt zur Zahl der erfüllten Faktoren, nie
zu den Arten: Es lässt sich nicht zeigen, dass er sich von irgendetwas unterscheidet.

## Beispiel {#example}

```go
package main

import (
	"context"
	"errors"
	"fmt"

	"github.com/go-authn/mfa"
)

// factor is the smallest mfa.Factor: a name, a kind, and an answer.
type factor struct {
	name string
	kind mfa.Kind
	err  error
}

func (f factor) Name() string                 { return f.name }
func (f factor) Kind() mfa.Kind               { return f.kind }
func (f factor) Verify(context.Context) error { return f.err }

func main() {
	ctx := context.Background()
	twoFactor := mfa.Policy{Count: 2, DistinctKinds: true}

	// Two things the person knows are one kind of proof.
	_, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"a recovery code", mfa.Knowledge, nil},
	)
	fmt.Println(err)

	// A key that is not plugged in has not refused anybody.
	r, err := mfa.Verify(ctx, twoFactor,
		factor{"your passphrase", mfa.Knowledge, nil},
		factor{"your security key", mfa.Possession, mfa.Unavailable(errors.New("no key attached"))},
	)
	fmt.Println(err)
	fmt.Println(r.Answers[1].Unavailable())

	// The zero Policy is refused, not guessed at.
	_, err = mfa.Verify(ctx, mfa.Policy{}, factor{"your passphrase", mfa.Knowledge, nil})
	fmt.Println(err)
}
```

```
mfa: 2 factor(s) answered but only 1 kind(s) among them (knowledge); two of the same kind are not two factors
mfa: 2 factor(s) needed, 1 answered: your security key (possession): not available
true
mfa: a policy that requires 0 factors accepts anyone
```

Die echten Faktoren liegen anderswo: [totp]({{< relref "/libraries/totp.md" >}})
für einen Code von einem Telefon, [keyfactor]({{< relref "/libraries/keyfactor.md" >}})
für einen Sicherheitsschlüssel.

## Was es ablehnt und warum {#what-it-refuses-and-why}

`Verify` lehnt ab, bevor es irgendjemanden fragt:

| | warum |
|---|---|
| eine `Policy`, deren `Count` unter eins liegt | *a policy that requires 0 factors accepts anyone*. Es gibt keine Standardrichtlinie: Wie viel Nachweis genügt, entscheidet, wer die Sache schützt |
| weniger angebotene Faktoren als `Count` | die Richtlinie kann nicht erfüllt werden, was auch immer sie antworten |
| ein Faktor, dessen `Kind()` außerhalb der Aufzählung liegt | als eigene Art gezählt, ginge `Kind(42)` neben einer Passphrase als zwei Faktoren durch |
| **derselbe Faktor zweimal** | eine Passphrase, zweimal übergeben, erfüllte `Count: 2`. „Derselbe“ heißt: derselbe Typ mit denselben Werten, Funktionen eingeschlossen; eine Funktion ist dieselbe Funktion, wenn sie denselben Code ausführt |

Und während es fragt, hält es drei Dinge auseinander:

- **Nicht fragen zu können ist keine Ablehnung.** Ein Faktor, der
  `ErrUnavailable` zurückgibt – verpackt durch `mfa.Unavailable(err)`, das den
  Grund behält –, wird als solcher gemeldet (`Answer.Unavailable()`) und beendet nie einen
  Versuch, auch nicht mit `StopOnFirstFailure`.
- **Standardmäßig wird jeder Faktor gefragt**, sodass einer Person in einem Versuch gesagt werden kann:
  *Ihr Schlüssel hat geantwortet, Ihr Fingerabdruck nicht*. `StopOnFirstFailure` ist
  da, wenn ein frühes Abbrechen gewünscht ist.
- **Ein nicht erreichter Faktor hat keinen Eintrag** in `Result.Answers`: Ihn als
  fehlgeschlagen zu melden, würde jemanden einem Nichts hinterherschicken.

Das `Result` wird zurückgegeben, ob die Richtlinie erfüllt wurde oder nicht, und der Fehler
benennt, was fehlte, in Worten, nach denen eine Person handeln kann.

## Wogegen es geprüft wird {#what-it-is-checked-against}

Kein externer Prüfer: Das Modul enthält kein Protokoll, dem es widersprechen könnte. Seine CI
verlangt **100 % Anweisungsabdeckung** unter Linux, macOS und Windows, führt den Race
Detector aus und führt die Tests auf amd64, arm64, riscv64, loong64, ppc64le, s390x,
386 und arm aus.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
