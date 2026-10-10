---
title: "oidc — vérifier un jeton porteur"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc vérifie un jeton OpenID Connect pour en tirer une identité : la découverte, le jeu de clés, une liste d'algorithmes autorisés, et les refus qui comptent. Aucune dépendance."
tags: [libraries, oidc, tokens]
---

**Qui ce jeton porteur dit-il être à l'origine de la demande, et faut-il le croire ?**
La découverte, le jeu de clés, et les vérifications qu'un serveur de ressources doit faire — en Go
pur, **sans aucune dépendance** en dehors de la bibliothèque standard.

```sh
go get github.com/go-authn/oidc@v0.4.0
```

Il n'y a pas ici de parcours de connexion : pas de redirection, pas d'échange de code, pas de secret client,
pas de cookies. C'est la moitié **serveur de ressources** — quelque chose arrive avec un
jeton, et ceci dit de qui il s'agit.

## Exemple {#example}

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

Un `Verifier` peut être utilisé en concurrence et détient le jeu de clés : construisez-en un au
démarrage et gardez-le. L'erreur de `Verify` dit quelle vérification a refusé le jeton, pour
le journal du serveur ; le client reçoit un seul et même refus, quelle que soit la vérification.

Trois configurations que `New` refuse avant que quoi que ce soit ne soit récupéré :

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

Le reste de `Config` est facultatif : `JWKSURL` saute la découverte ; `UsernameClaim`
et `GroupsClaim` (par défaut `groups`) nomment les revendications ; `ClockSkew` et
`MinRefresh` valent une minute par défaut ; `Client` est le client HTTP, pour un proxy,
une AC privée ou un délai d'expiration. Un `Token` lit `Subject`, `Issuer`, `Audience`,
`Email`, `EmailVerified`, `Username`, `Groups`, `Expiry`, `NotBefore` et
`IssuedAt` ; `Claim(name, &v)` décode toute autre revendication, et `Has(name)` dit
si elle est présente.

## Ce qu'il accepte {#what-it-accepts}

Dix algorithmes de signature, sous forme de **liste d'autorisation** : `RS256` `RS384` `RS512`,
`PS256` `PS384` `PS512`, `ES256` `ES384` `ES512`, et `EdDSA` (Ed25519). Un
jeton dont l'`alg` n'est pas l'un d'eux est refusé avant que la moindre clé ne soit récupérée.
`alg: none` et la famille HMAC sont refusés du fait de ne pas figurer sur la liste, et la
clé doit être de la sorte qu'exige l'algorithme : un jeton qui se réclame de `RS256` est vérifié avec
une clé RSA ou refusé.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

| | pourquoi |
|---|---|
| `alg: none` | un jeton qui se dit non signé est un objet JSON que quelqu'un a tapé |
| HMAC contre une clé publique | `HS256` prend un secret partagé, et la clé de l'émetteur est publique : n'importe qui pourrait fabriquer un jeton |
| un émetteur qui se contente de **commencer par** le bon | `iss` est comparé en entier : `https://login.example.org.evil.test` commence par la bonne chaîne |
| une **audience** absente ou erronée | un jeton fabriqué pour un autre service est valide ; il n'est pas adressé à celui-ci |
| un jeton **sans expiration** | c'est un mot de passe que quelqu'un peut copier une fois |
| un émetteur, un jeu de clés ou une redirection **en HTTP en clair**, sauf vers le loopback | le jeu de clés décide de chaque signature |
| une clé RSA de moins de 2048 bits, ou dont `n` ou `e` n'est pas sous sa forme la plus courte ; un point EC qui n'est pas sur sa courbe | les signatures d'une clé courte peuvent être contrefaites ; avant la v0.2.2, un module de 1024 bits complété d'octets nuls passait pour 2048 bits |
| une clé publiée avec un `use` autre que `sig` | un jeu de clés contient légitimement aussi des clés de chiffrement |
| avec `Type` défini, un jeton d'un autre `typ` ; sans lui, un `typ` autre que `JWT` ou `at+jwt` (un jeton sans en-tête `typ` passe) | RFC 9068 §4 : un serveur de ressources vérifie `typ: at+jwt`, sinon il prend un jeton d'identité (ID token) pour un jeton d'accès dès que les audiences concordent |
| une partie qui n'est pas en base64url canonique | un jeton se vérifie comme une seule chaîne |

Le `s` et le `n − s` d'ECDSA se vérifient tous les deux, comme l'algorithme le permet. Une liste de refus ou
un cache anti-rejeu se fonde donc sur `jti` ou `sub`, jamais sur le jeton tel qu'il a été envoyé.

**Les clés changent, et une clé inconnue n'est pas un moyen de marteler l'émetteur.** Une
signature que rien de détenu ne peut vérifier vaut une nouvelle récupération du jeu de clés par
`MinRefresh`, que le `kid` soit nouveau ou que le même `kid` porte une nouvelle clé.
Les jetons qui ont besoin du jeu de clés pendant qu'une récupération est en cours l'attendent, et une
récupération qui échoue compte quand même.

**Quel nom donne `Username()`.** Par défaut `preferred_username`, puis
`email` **seulement quand `email_verified` est vrai**, puis `sub`. Une adresse e-mail non vérifiée
est une chaîne que la personne a tapée (OIDC Core §5.1). Une `UsernameClaim` configurée est
lue telle que nommée, sans repli.

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

**pyjwt** signe chaque jeton de la suite de tests, si bien que le vérificateur n'est jamais jugé
par un signataire sorti des mêmes mains. Le jeton de confusion HMAC est forgé à la main,
parce que pyjwt refuse de le produire. `testdata/fixed.json` — des jetons que pyjwt a
signés une fois avec une clé fixe — permet aux voies d'architecture, s390x comprise, de
vérifier de vraies signatures avec l'horloge figée. La voie de test Linux, le détecteur
de concurrence et la voie de couverture installent pyjwt et positionnent `OIDC_REQUIRE_JUDGE`, si bien qu'un
pyjwt absent fait échouer au lieu de sauter. Accepter HMAC, comparer l'émetteur par
préfixe et sauter la vérification de l'audience ont chacun été essayés délibérément, et chacun
fait passer un test au rouge. Le plancher de la voie de couverture est de 90 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/oidc@v0.4.0](https://pkg.go.dev/github.com/go-authn/oidc@v0.4.0)
