---
title: "mfa — assez de facteurs, et lesquels"
linkTitle: "mfa"
weight: 10
description: "go-authn/mfa décide si assez de facteurs ont répondu, de suffisamment de sortes différentes, et dit lesquels — sans périphérique et sans cryptographie."
tags: [libraries, mfa, factors]
---

**Assez de facteurs ont-ils répondu, de suffisamment de sortes — et lesquels ?** Rien ici
n'atteint un périphérique, et il n'y a pas de cryptographie : un `Factor` est tout ce à quoi
l'on peut demander *cette personne est-elle là, maintenant ?*, et ce paquet décide de ce que
les réponses donnent au total.

```sh
go get github.com/go-authn/mfa@v0.5.0
```

Il n'importe rien en dehors de la bibliothèque standard.

## Deux fois la même chose font un seul facteur {#two-of-the-same-thing-is-one-factor}

Une phrase de passe et un code de secours sont tous deux des choses que la personne *sait* : quiconque
a appris l'un a en général appris l'autre au même endroit. Un facteur
dit donc ce qu'il prouve — `Knowledge`, `Possession` ou `Inherence` — et la
politique qui signifie ce que l'on entend normalement par *deux facteurs* est
`Policy{Count: 2, DistinctKinds: true}`. `Policy{Count: 2}` seule est aussi
proposée, pour un appelant qui veut délibérément deux clés de la même sorte ; c'est une
demande différente et elle s'écrit différemment.

Un facteur dont le `Kind()` est `Unknown` compte pour le nombre atteint, jamais
pour les sortes : on ne peut pas montrer qu'il diffère de quoi que ce soit.

## Exemple {#example}

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

Les vrais facteurs sont ailleurs : [totp]({{< relref "/libraries/totp.md" >}})
pour un code venant d'un téléphone, [keyfactor]({{< relref "/libraries/keyfactor.md" >}})
pour une clé de sécurité.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

`Verify` refuse avant de demander quoi que ce soit à qui que ce soit :

| | pourquoi |
|---|---|
| une `Policy` dont le `Count` est inférieur à un | *a policy that requires 0 factors accepts anyone*. Il n'y a pas de politique par défaut : la quantité de preuve suffisante appartient à qui protège la chose |
| moins de facteurs proposés que `Count` | la politique ne peut pas être satisfaite, quoi qu'ils répondent |
| un facteur dont le `Kind()` est hors de l'énumération | compté comme une sorte distincte, `Kind(42)` à côté d'une phrase de passe passerait pour deux facteurs |
| **le même facteur deux fois** | une phrase de passe passée deux fois satisfaisait `Count: 2`. « Le même » signifie le même type contenant les mêmes valeurs, fonctions comprises : une fonction est la même fonction quand elle exécute le même code |

Et il tient trois choses à part pendant qu'il demande :

- **Ne pas avoir pu être interrogé n'est pas un refus.** Un facteur qui renvoie
  `ErrUnavailable` — enveloppé par `mfa.Unavailable(err)`, qui garde la
  raison — est signalé comme tel (`Answer.Unavailable()`), et ne met jamais fin à une
  tentative, même avec `StopOnFirstFailure`.
- **Chaque facteur est interrogé par défaut**, si bien qu'on peut dire à une personne *votre clé
  a répondu, votre empreinte digitale non* en une seule tentative. `StopOnFirstFailure` est
  là quand on veut s'arrêter tôt.
- **Un facteur non atteint n'a pas d'entrée** dans `Result.Answers` : le signaler comme
  échoué enverrait quelqu'un à la recherche de rien.

Le `Result` est renvoyé que la politique ait été satisfaite ou non, avec l'erreur
nommant ce qui manquait en des termes sur lesquels une personne peut agir.

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

Pas de juge externe : le module ne contient aucun protocole avec lequel être en désaccord. Sa CI
exige **100 % de couverture des instructions** sur Linux, macOS et Windows, exécute le détecteur
de concurrence, et exécute les tests sur amd64, arm64, riscv64, loong64, ppc64le, s390x,
386 et arm.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/mfa@v0.5.0](https://pkg.go.dev/github.com/go-authn/mfa@v0.5.0)
