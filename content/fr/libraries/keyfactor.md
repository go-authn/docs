---
title: "keyfactor — la clé enregistrée, touchée"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor fait d'une clé de sécurité un facteur mfa, en vérifiant la réponse contre l'enregistrement plutôt qu'en faisant confiance à n'importe quel périphérique qui parle CTAP."
tags: [bibliothèques, fido, mfa, facteurs]
---

**Est-ce la clé enregistrée qui a répondu, et une personne l'a-t-elle touchée ?**
`keyfactor` est la seule pièce entre [fido]({{< relref "/libraries/fido.md" >}}),
qui parle CTAP et ne connaît aucune politique, et
[mfa]({{< relref "/libraries/mfa.md" >}}), qui décide combien de preuves
suffisent et ne connaît aucun périphérique. Aucun des deux n'importe l'autre ; celui-ci importe les deux.

```sh
go get github.com/go-authn/keyfactor@v0.4.1
```

En v0.4.1, son `go.mod` requiert au moins `go-authn/fido` v0.6.0 et
`go-authn/mfa` v0.5.0 : des minimums, si bien qu'un programme qui requiert fido v0.6.2, la
version que décrivent ces pages, est compilé avec la v0.6.2.

La plateforme fournit un `Opener` — comment une clé est trouvée sur ce système — et
ne garde que cela. Tout le reste est identique partout où il y a CTAP : l'assertion,
les vérifications, le refus de dépenser la dernière tentative de PIN de quelqu'un.

## Exemple {#example}

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

Le refus vient avant que l'`Opener` soit appelé. Avec la clé publique de
l'enregistrement, le même facteur ouvre la clé, lui demande une assertion sur un
défi aléatoire tout frais, et vérifie la réponse.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

**Qu'un périphérique réponde, ce n'est pas que la clé réponde.** Une carte USB programmable
parle CTAP aussi bien qu'une clé de sécurité, donc la réponse est vérifiée contre
l'enregistrement :

| refusé | message |
|---|---|
| avant que quoi que ce soit soit ouvert : pas d'`Opener`, pas de `RPID`, pas de `PublicKey`, ou une clé qui n'est pas sur P-256 | `keyfactor: no opener; …`, `… needs a relying party id …`, `… no public key for the credential; …`, `… is not on P-256 …` |
| une empreinte de partie utilisatrice (relying party) qui n'est pas le SHA-256 de `RPID` | `… answered for another relying party` |
| un identifiant autre que `CredentialID`, quand le périphérique en nomme un | `… answered with a credential other than the one asked for` |
| une signature sur les données d'authentificateur et le défi que `PublicKey` n'a pas faite | `… answered with a signature the credential's key did not make` |
| pas de drapeau `UP` | `… answered without anyone touching it` |
| pas de drapeau `UV` quand un `PIN` a été donné | `… was asked to establish who holds it and did not` |

**La dernière tentative de PIN n'est pas dépensée sur une supposition.** `PINRetries` est interrogé en premier ;
une clé qui n'acceptera plus de PIN tant qu'elle n'aura pas été débranchée est refusée, tout comme
une clé à laquelle il reste **une tentative ou moins**. Selon CTAP, trois mauvais PIN de suite
bloquent le PIN d'une clé jusqu'à ce qu'elle soit débranchée, et un compteur de tentatives qui
atteint zéro le bloque définitivement : seule une réinitialisation lève ce blocage, en effaçant
tous les identifiants qu'elle contient.

Quand la clé elle-même refuse un PIN, l'erreur est celle de fido, et depuis fido
v0.6.2 elle nomme le bon des deux cas :
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`
quand le débranchement lève le blocage, et
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`
quand seule une réinitialisation le lève. Avant fido v0.6.2, les deux phrases
étaient inversées.

**Un PIN n'est pas un second facteur.** Le type reste `mfa.Possession` : un PIN
saisi dans la clé protège la clé, et n'identifie personne auprès de cette machine.

**Un port vide n'est pas un refus.** Un `Opener` qui ne trouve rien enveloppe son
erreur avec `keyfactor.Unavailable`, qui la marque `mfa.ErrUnavailable`, et une
politique compte *n'a pas pu être interrogé* à part de *a dit non*.

{{< callout type="warning" >}}
**Ce qu'il ne peut pas protéger : l'empreinte du PIN parvient à n'importe quel périphérique qui répond**

CTAP fait remettre par la plateforme `LEFT(SHA-256(PIN), 16)` à la clé, chiffré sous un
secret convenu avec le périphérique lui-même, avant que quoi que ce soit soit signé. Un périphérique
contrefait est refusé comme facteur, mais il a reçu cette empreinte, et un PIN court
tombe sous une recherche hors ligne. C'est le protocole. Utilisez un PIN long, et ne le
tapez pas dans une clé dont la provenance est inconnue.
{{< /callout >}}

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

Les tests imitent **l'authentificateur**, pas le transport, construit à partir du
découpage exporté par go-authn/fido lui-même : une poignée de main CTAPHID, une assertion CTAP2,
et un échange ClientPIN. La moitié PIN joue le côté authentificateur du
protocole deux de façon indépendante — ses propres ECDH, HKDF et AES-CBC, écrits d'après la
spécification (`fakepin_test.go`) — si bien qu'une dérivation qui différerait d'un octet
ferait échouer l'échange. `forged_test.go` est le périphérique qui ne détient aucun
identifiant. La couverture est maintenue à 100 %, et les tests s'exécutent sur huit
architectures.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.1](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.1)
