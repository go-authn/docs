---
title: "totp — un code, une fois, et pas un million d'essais"
linkTitle: "totp"
weight: 20
description: "go-authn/totp vérifie les codes à usage unique RFC 6238, refuse un code déjà utilisé, limite les essais par secret, et offre le résultat comme facteur mfa."
tags: [libraries, totp, factors]
---

**Ce code à six chiffres est-il juste — et a-t-il déjà servi ?** Des mots de
passe à usage unique fondés sur le temps (RFC 6238) ; un `Verifier` qui retient
ce qu'un serveur doit retenir, les codes déjà utilisés et les codes faux ; et un facteur
qu'une politique [mfa]({{< relref "/libraries/mfa.md" >}}) peut demander.

```sh
go get github.com/go-authn/totp@v0.4.1
```

Sa seule dépendance est `go-authn/mfa`.

Les valeurs par défaut sont celles que tout téléphone suppose : six chiffres, toutes les 30 secondes,
HMAC-SHA1, un pas de tolérance de part et d'autre. `Options` change `Digits`,
`Period`, `Algorithm` (`SHA1`, `SHA256`, `SHA512`) et `Window`.

## Exemple {#example}

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

Dans une politique, le code devient un facteur de type `Possession`, à côté de ce
qui vérifie le mot de passe :

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

Un code lu à voix haute au téléphone n'est plus une possession ; c'est sur
cette classification que s'appuie `DistinctKinds`.

## Ce qu'elle refuse, et pourquoi {#what-it-refuses-and-why}

**Un code déjà accepté.** RFC 6238 §5.2 : le vérificateur MUST NOT accepter une
seconde tentative d'un OTP qui a déjà réussi. Le `totp.Verify` sans état
ne le peut pas — il ne garde rien d'un appel à l'autre — : un serveur utilise donc un `*Verifier`, qui
refuse avec `ErrUsed` chaque pas **jusqu'au dernier qu'il a accepté, inclus** :
un code d'il y a trente secondes est encore dans la fenêtre par défaut.

**Un `Factor` sans `Verifier`.** `totp.Factor` avec un `*Verifier` nil
refuse tous les codes, en disant qu'il manque un Verifier. Ce n'est pas signalé comme
indisponible : une politique ne peut donc pas passer sur les autres facteurs et masquer l'erreur.

**Les essais, par secret.** Un `Verifier` compte les codes faux par **identifiant** —
le secret, conservé uniquement sous forme de son SHA-256 — et non par nom, parce que le nom est
la chaîne quelconque que passe l'appelant, et qu'avant la v0.3.0 `dora`, `Dora` et `DORA` étaient
trois compteurs pour un seul secret.

| champ | défaut | |
|---|---|---|
| `Throttle` | `DefaultThrottle` = 5 | codes faux d'affilée avant `ErrThrottled` ; le code envoyé entre-temps n'est pas examiné, si bien que même le bon ne passe pas |
| `Pause` | `DefaultPause` = 15 minutes | combien de temps cela dure |
| `Lockout` | `DefaultLockout` = 100 | codes faux d'affilée, aussi espacés soient-ils, avant `ErrLockedOut`, que seul `Forget` lève (NIST SP 800-63B §5.2.2) |

Seul un code faux compte ; un rejeu, un code de mauvaise longueur ou un paramètre
refusé ne rapproche pas une pause. Toute la vérification se fait sous un seul
verrou : des essais envoyés au même instant sont donc comptés un par un.
`ErrLockedOut` enveloppe `ErrThrottled` : `errors.Is(err, totp.ErrThrottled)` est donc
vrai pour les deux refus, et `errors.Is(err, totp.ErrLockedOut)` seulement pour le
verrouillage.

**Des paramètres qui ne peuvent pas être justes :**

- un secret de moins de 128 bits (`MinSecret` = 16 octets, RFC 4226 R6), dans
  `Generate`, `At`, `Verify` et `Verifier.Verify`. `ParseSecret` en lit tout de même
  un : c'est un analyseur ;
- une période qui n'est pas un nombre entier de secondes, ou inférieure à une seconde ;
- moins de 6 ou plus de 10 chiffres (RFC 4226 §5.3) ;
- une fenêtre plus large que `MaxWindow` = 10 pas de part et d'autre. `0` signifie la
  valeur par défaut d'un pas ; `NoWindow` n'accepte que le pas courant.

Chaque pas de la fenêtre est essayé sans arrêt anticipé, et la comparaison se fait
en temps constant. `ErrWrongCode` est la même erreur pour « faux » et « trop ancien ».

{{< callout type="warning" >}}
**Le secret est l'identifiant**

Qui le détient produit tous les codes à venir. Aucun message d'erreur ici ne cite
de code ni de secret, et `URI` — la chaîne `otpauth://` qu'un authentificateur lit
dans un QR code — porte le secret par construction : elle est destinée à la personne
qui s'enrôle, et à personne d'autre.
{{< /callout >}}

La mémoire du `Verifier` est celle de ce processus. Deux serveurs derrière un répartiteur de charge
refusent chacun leurs propres rejeux et comptent chacun leurs propres essais ; un déploiement qui
a besoin d'une seule réponse place un stockage partagé derrière la même interface.

## Contre quoi elle est vérifiée {#what-it-is-checked-against}

- **pyotp**, une implémentation en Python : 200 cas aléatoires sur des longueurs de secret
  à partir de 16 octets, de 6 à 10 chiffres, quatre périodes et les trois algorithmes
  (`differential_test.go`). La voie de test Linux, le détecteur de concurrence et la
  voie de couverture l'installent, et là `TOTP_REQUIRE_JUDGE` fait d'un pyotp
  absent un échec plutôt qu'un saut.
- **RFC 6238 Appendix B**, les six instants et les trois algorithmes, et
  **RFC 4226 Appendix D**, compteurs 0 à 9.
- Chaque nombre de chiffres sur 1000 pas par algorithme, contre RFC 4226 §5.3
  recalculé en précision arbitraire.

La voie de couverture échoue en dessous de 95 % (sa norme affichée est 100 %), et les
tests s'exécutent sur huit architectures.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/totp@v0.4.1](https://pkg.go.dev/github.com/go-authn/totp@v0.4.1)
