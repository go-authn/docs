---
title: "wireguard — à qui est cette clé, et peut-elle se connecter ?"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard définit strictement une clé publique WireGuard et transporte la liste, signée par le fournisseur, des clés enregistrées qu'une passerelle transforme en pairs."
tags: [bibliothèques, wireguard, jetons]
---

**Cette clé WireGuard peut-elle se connecter, et à qui est-elle ?** WireGuard authentifie un
pair par sa clé publique statique et par rien d'autre : pas de certificats, pas d'expiration,
pas de révocation. La question trouve donc sa réponse hors du protocole, et une nouvelle réponse
chaque fois que la réponse change. Un fournisseur —
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) — y répond ; ce
module est ce sur quoi le fournisseur et une passerelle s'accordent.

```sh
go get github.com/go-authn/wireguard@v0.1.0
```

Sa seule dépendance est [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0,
qui vérifie la liste.

Il fait deux choses : `ParseKey` dit ce qu'est une clé publique, et `Source.Fetch`
obtient la `List` signée du fournisseur, avec les clés que les personnes ont enregistrées, chacune un `Peer`
avec sa `Key`, son `Subject`, son `Username`, son `Device` et la fin de son bail.

{{< callout type="info" >}}
**Seules des clés publiques passent par ici**

Une clé privée est générée sur l'appareil et ne le quitte jamais ; rien dans ce
paquet n'a de place pour une clé privée.
{{< /callout >}}

## Exemple {#example}

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

Une passerelle garde une seule `Source` et récupère la liste :

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource` lit la configuration du fournisseur au démarrage. `Fetch` obtient un
jeton pour la passerelle elle-même (`client_credentials`, portée `wireguard_peers`),
récupère la liste à `/wireguard/peers` sous l'émetteur, et la vérifie
avec go-authn/oidc : la signature contre le jeu de clés du fournisseur, l'émetteur,
l'audience (le `ClientID` de cette passerelle), l'expiration, et le `typ`
`wireguard-peers+jwt` (`ListType`) — si bien que ni un jeton d'accès ni un jeton
d'identité (ID token) ne peuvent passer pour une liste, ni une liste pour un jeton.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

**Une clé** (`ParseKey`) :

- toute autre graphie des mêmes octets. Le décodage est strict et le texte
  doit se réimprimer exactement tel qu'il est arrivé : un stockage indexé sur le texte ne peut donc pas
  contenir une même clé deux fois sous deux noms ;
- un point d'ordre faible, la clé entièrement nulle parmi eux. Tout échange avec l'un d'eux
  donne le même secret partagé quelle que soit la clé de l'autre côté (RFC 7748 §6.1) :
  il n'authentifie donc personne. `crypto/ecdh` en décide en calculant un
  échange, si bien que les variantes au bit de poids fort sont refusées aussi.

**Une liste** (`Fetch`) :

| | pourquoi |
|---|---|
| une liste dont la `version` est inférieure à celle d'une liste que cette `Source` a déjà prise | une ancienne liste est signée elle aussi, et peut lister une clé reprise depuis |
| une clé listée deux fois | quelle que soit celle qu'une passerelle garderait, le trafic de l'autre personne arriverait sous le mauvais nom |
| un pair sans sujet | il n'appartient à personne |
| une clé qui n'en est pas une | voir ci-dessus |
| un émetteur ou un point de terminaison de jeton en clair, sauf en boucle locale | le secret de la passerelle et la liste traverseraient un lien que n'importe qui peut lire |
| une `SourceConfig` sans `ClientID` ni `ClientSecret` | une passerelle lit la liste en tant que client à part entière |

Une liste porte `exp` : une passerelle qui ne peut pas en récupérer une plus récente d'ici là n'a plus
de liste, plutôt qu'une liste périmée. `Peer.Subject` est le `sub` de la personne tel que le
client qui a enregistré la clé le voit, public ou pairwise — la valeur qu'une
passerelle trouve aussi dans les jetons d'accès de cette personne.

## Contre quoi il est vérifié {#what-it-is-checked-against}

**`wg(8)` lui-même**, de wireguard-tools, fabrique les clés que `ParseKey` doit
accepter. Il est installé dans la voie de test Linux, le détecteur de concurrence et la
voie de couverture, qui positionnent `WIREGUARD_REQUIRE_JUDGE=1` pour qu'un `wg` absent échoue
plutôt que d'être sauté. Le test d'ordre faible vérifie les sept points que liste libsodium,
chacun avec et sans le bit de poids fort. Le plancher de couverture est de 100 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.0](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.0)
