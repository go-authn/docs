---
title: "fido — parler à une clé de sécurité"
linkTitle: "fido"
weight: 30
description: "go-authn/fido parle CTAPHID et CTAP2 à une clé de sécurité sur n'importe quel transport de 64 octets : poignée de main, enregistrement, assertion et PIN, en pur Go."
tags: [libraries, fido, factors]
---

**Comment parle-t-on à une clé de sécurité ?** Le protocole client-authentificateur
de FIDO — le découpage CTAPHID, la poignée de main du canal, et les commandes CTAP2 qui
enregistrent un identifiant, demandent une signature et échangent un PIN contre un jeton — en
pur Go, sur n'importe quel système d'exploitation.

```sh
go get github.com/go-authn/fido@v0.6.1
```

Rien ici n'est propre à une plateforme. Un `Transport` achemine des rapports de 64 octets vers
un authentificateur et depuis lui, et dit comment le périphérique s'appelle ; d'où viennent ces rapports
— IOKit sur macOS, hidraw sur Linux, WebHID dans un navigateur — relève du paquet de
quelqu'un d'autre. Tout ce qui est au-dessus est ici :

| | |
|---|---|
| `Open(ctx, t)` | la poignée de main `INIT` sur le canal de diffusion ; renvoie une `*Key` avec son propre canal. La `Key` possède `t` : `Close` le ferme, et un `Open` qui échoue aussi |
| `Key.Ping`, `Key.Wink` | un aller-retour, et un clignotement — la façon la moins coûteuse de demander *laquelle de ces clés est celle-ci ?* |
| `Key.GetInfo` | versions, extensions, AAGUID, options, protocoles de PIN |
| `Key.MakeCredential`, `Key.GetAssertion` | enregistrer, et signer ; `ParseAuthData` lit les données d'authentificateur, et `AuthData.PublicKey` transforme une clé COSE P-256 en `*ecdsa.PublicKey` |
| `Key.PINRetries`, `Key.KeyAgreement`, `Key.PINToken` | `authenticatorClientPIN`, les deux protocoles d'authentification PIN/UV |
| `Split`, `NewReassembler`, `ParseInit`, `Key.CBOR` | le découpage, exporté pour quiconque pilote une clé autrement |

`AuthData.PublicKey` est une conversion, pas une vérification : quels algorithmes
comptent et que faire d'un compteur de signatures qui a reculé appartiennent à
l'appelant. [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) est un tel
appelant.

## Exemple {#example}

Le découpage seul, sans clé : un message coupé en rapports, puis
reconstitué.

```go
package main

import (
	"bytes"
	"fmt"

	"github.com/go-authn/fido"
)

func main() {
	// A 200-byte ping, cut into the 64-byte reports a key reads...
	payload := bytes.Repeat([]byte{0xA5}, 200)
	reports, err := fido.Split(0x01020304, fido.CmdPing, payload)
	if err != nil {
		panic(err)
	}
	fmt.Println(len(reports), "reports of", len(reports[0]), "bytes")

	// ...and put back together, as a reply would be.
	r := fido.NewReassembler(0x01020304)
	for _, rep := range reports {
		msg, done, err := r.Feed(rep)
		if err != nil {
			panic(err)
		}
		if done {
			fmt.Println(bytes.Equal(msg.Data, payload), msg.Cmd == fido.CmdPing)
		}
	}

	// A report for another channel is an error, not something to drop.
	other, _ := fido.Split(0x0A0B0C0D, fido.CmdPing, []byte("hi"))
	_, _, err = fido.NewReassembler(0x01020304).Feed(other[0])
	fmt.Println(err)

	// The framing's real limit, not the length field's.
	fmt.Println(fido.MaxMessage)
}
```

```
4 reports of 64 bytes
true true
fido: the report belongs to another channel
7609
```

Avec une clé, `fido.Open(ctx, transport)` fait la poignée de main, et la `*Key` qu'il
renvoie porte toutes les commandes suivantes.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

**On ne fait pas confiance à une clé pour répondre à ce qu'on lui a demandé.** Une réponse qui porte
une commande différente de celle envoyée est refusée (CTAP 2.1 §11.2.9 donne à chaque
réponse sa propre commande, et libfido2 le vérifie aussi). Une réponse `INIT` dont le
nonce n'est pas celui envoyé est refusée : c'est la poignée de main d'un autre programme sur la
même clé. Un jeton PIN qui n'a pas la longueur de son protocole — 16 ou 32 octets sous le
protocole un, exactement 32 sous le protocole deux — est refusé.

**Un keepalive n'est pas une réponse.** Une clé qui attend un doigt envoie
`CTAPHID_KEEPALIVE` environ toutes les cent millisecondes ; il est ignoré, et la
seule borne sur la durée que peut prendre un toucher est le contexte.

**Un message plus long que ce que le découpage peut porter.** Deux octets de longueur permettraient
65535, mais 57 octets dans le paquet d'initialisation plus 128 continuations de 59
font 7609 (`MaxMessage`) ; au-delà, un numéro de séquence atteindrait `0x80` et une
clé le lirait comme un nouveau message. `Split` renvoie `ErrTooLong`.

**Des rapports qui ne concordent pas** : un pour un autre canal (`ErrWrongChannel` —
deux programmes sur une même clé), des continuations dans le désordre (`ErrOutOfOrder`), un
rapport plus court qu'un paquet (`ErrShortPacket`), une réponse `INIT` plus courte que
ses 17 octets (`ErrTruncated`).

**Une commande que la clé n'a pas dit prendre en charge.** `Wink` n'est pas envoyé à une clé
sans `CapWink`, ni `GetInfo` à une clé sans `CapCBOR` : la clé répondrait
`CTAPHID_ERROR`, et l'appelant devrait distinguer ce refus d'une panne.

**Un PIN vide**, et tout ce qui n'est pas P-256 dans `AuthData.PublicKey` — refusés
nommément plutôt qu'à moitié décodés.

{{< callout type="warning" >}}
**Un mauvais PIN coûte une tentative**

Un authentificateur qui les a toutes épuisées se verrouille jusqu'à ce qu'on le débranche, puis
définitivement. Interrogez `Key.PINRetries` avant de solliciter qui que ce soit.
{{< /callout >}}

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

La CI n'a pas de clé de sécurité, donc les tests utilisent un faux transport qui reconstitue
ce qu'on lui envoie — une clé qui refuse, se bloque, répète qu'elle est occupée, ou partage
son canal avec un autre programme — avec une couverture maintenue à 100 %. Deux jeux d'essai
viennent de l'extérieur de ce code :

- `testdata/yubikey-fido-5.7.4-getinfo.hex`, la réponse `GetInfo` **capturée
  sur une YubiKey FIDO 5.7.4**, décodée par `ctap2_test.go` ;
- `testdata/webauthn-reference-authdata.b64`, un échantillon tiré des tests de
  **go-webauthn/webauthn**, qui vérifie l'analyseur des données d'authentificateur et
  `AuthData.PublicKey`.

La table des codes d'état suit le `err.h` de libfido2. Le README du module consigne
un enregistrement et une assertion exécutés sur une vraie YubiKey, avec la signature
vérifiée contre la clé publique qu'elle a fournie ; cette exécution ne fait pas partie de la CI.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/fido@v0.6.1](https://pkg.go.dev/github.com/go-authn/fido@v0.6.1)
