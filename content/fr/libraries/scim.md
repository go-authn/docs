---
title: "scim — provisionner personnes et groupes depuis un fournisseur d'identité"
linkTitle: "scim"
weight: 140
description: "go-authn/scim est un fournisseur de service SCIM 2.0 (RFC 7643, RFC 7644) : Users et Groups au-dessus d'un Backend que vous écrivez, avec les charges utiles d'Entra ID et d'Okta testées. Bibliothèque standard uniquement."
tags: [bibliothèques, scim, provisionnement]
---

**Qui le fournisseur d'identité vient-il de créer, de modifier ou de supprimer ?**
Un fournisseur d'identité (Entra ID, Okta, Keycloak, …) crée, met à jour et
supprime des personnes et des groupes dans votre application par HTTP ; ce
paquet est ce point d'accès HTTP, pour Users et Groups (RFC 7643, RFC 7644),
au-dessus d'un `Backend` que vous écrivez. Go pur, `CGO_ENABLED=0`, bibliothèque
standard uniquement.

```sh
go get github.com/go-authn/scim@v0.2.0
```

## Exemple {#example}

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

Le Server attribue les identifiants, les horodatages et les versions, valide
l'entrée et applique PATCH ; le `Backend` garde ce qu'on lui donne et impose ce
que lui seul peut voir : `ErrConflict` pour un `userName` déjà pris (409
`uniqueness`), `InvalidValue` pour un membre qui n'existe pas (400
`invalidValue`), `ErrPrecondition` quand la version stockée n'est pas celle qui
a été lue. `NewMemory()` est l'implémentation de référence.

Il sert `/Users` et `/Groups` (liste avec `filter`, `startIndex`, `count`,
`attributes`, `excludedAttributes` ; création ; lecture, `PUT`, `PATCH` et
`DELETE` par identifiant avec `ETag` et `If-Match`), `/Users/.search` et
`/Groups/.search`, ainsi que les points de découverte `/ServiceProviderConfig`,
`/ResourceTypes` et `/Schemas`. Les filtres couvrent toute la grammaire de la
RFC 7644 §3.4.2.2 ; PATCH est atomique : une opération qui échoue laisse la
ressource telle qu'elle était.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

Tout ici vient de l'extérieur, donc les limites font partie de l'API :

| | |
|---|---|
| un corps de plus de `MaxBodyBytes` (1 Mio), un PATCH de plus de `MaxOperations` (100), ou un PATCH qui fait dépasser à la ressource la limite du corps | 413 |
| un groupe de plus de `MaxMembers` (10 000) | 400 `invalidValue` |
| un filtre de plus de 4 Kio, imbriqué sur plus de 32 niveaux, avec un opérateur inconnu, ou `gt` sur un booléen | 400 `invalidFilter` |
| une écriture sur `id`, `meta`, `schemas` ou les `groups` d'un utilisateur | 400 `mutability` |
| une ressource sans son schéma de base, un `userName` vide, de plus de 256 octets ou contenant des caractères de contrôle, deux courriels principaux | 400 |
| un jeton porteur absent ou erroné (`BearerAuth`, en temps constant ; un jeton vide n'admet personne) | 401 |
| toute erreur du Backend qui n'est pas l'une des sentinelles | 500 avec un corps qui ne dit rien ; l'erreur va dans `ErrorLog` |

**Non pris en charge** : les opérations en masse (bulk), le tri, les changements
de mot de passe, `/Me` (annoncé comme tel dans `/ServiceProviderConfig`).

## Ce que la v0.2.0 a changé {#v020}

Après un audit, une passe de fuzzing et de chaos et une passe de performance. Ce
qu'un appelant peut voir :

- **`Server.ReadTimeout`**, nouveau, 30 s par défaut : un corps de requête qui met
  plus longtemps à arriver est coupé par une réponse 400. Il remplace le
  `ReadTimeout` propre du `http.Server` pour la requête ; une valeur négative laisse
  celui du `http.Server`.
- **`ConditionalDeleter`**, une nouvelle interface facultative qu'un `Backend` peut
  implémenter (`DeleteUserIf`, `DeleteGroupIf`), ce que fait `Memory`. `DELETE` avec
  `If-Match` vérifiait la version puis supprimait en deux temps, si bien qu'une
  écriture arrivée entre les deux était supprimée sans être vue.
- **Une course perdue est rejouée.** Un `PATCH` ou `PUT` sans `If-Match` qui perdait
  une course contre un autre écrivain recevait 412 alors que le client ne demandait
  aucune précondition ; il est maintenant rejoué sur la version plus récente, 32 fois
  au plus. Avec `If-Match`, la réponse reste 412. Sur 24 PATCH concurrents sans
  `If-Match`, 9 échouaient avec 412 avant et aucun maintenant.
- Retirer un membre, ou tout élément, par un filtre qui ne correspond à rien réussit ;
  c'était un 400 `noTarget` (RFC 7644 §3.5.2.2).
- Un PATCH sans chemin applique ses clés dans l'ordre trié ; il suivait l'ordre de la
  table, si bien que `name` et `name.givenName` dans un même objet donnaient une
  ressource différente d'une exécution à l'autre.
- `BearerAuth` accepte le nom du schéma en toute casse (`bearer <token>`, RFC 7235
  §2.1).
- `startIndex` et `count` sont bornés quelle que soit la taille d'un `int` : une valeur
  au-delà était un 400 sur les cibles 32 bits et une page bornée sur les 64 bits.
- Un `Filter.Equality()` remet à un `Backend` la chaîne décodée. C'est une donnée : la
  passer à la base comme paramètre, et ne jamais la coller dans une requête.

Les opérations en masse, le tri et les changements de mot de passe restent non pris en
charge.

**Allocations** d'une requête de liste sur 10 000 utilisateurs et 200 groupes avec
`Memory`, exactes, issues de `go test -bench`, Apple M4 Max :

| requête de liste | avant | après |
|---|---|---|
| une page de 100 | 789 417 allocations, 47,7 Mo | 14 952 allocations, 6,0 Mo |
| `userName eq` | 797 979 allocations, 47,7 Mo | 90 allocations, 12,6 Ko |
| un filtre qui balaie chaque utilisateur (`name.givenName eq` et `emails[...]`) | 818 847 allocations, 48 Mo | 361 098 allocations, 29,7 Mo |

Le temps réel n'a pas été mesuré : la charge était de 65, et la règle est sous 9. Les
exécutions isolées bruitées (environ 1,7 s à 0,06 s pour le filtre qui balaie) ne
sont pas un résultat. `FuzzPatchPath`, `FuzzPatchThenDecode`, `FuzzFilter` et
`FuzzServer` ont tourné 45 s chacun avec 16 workers, de 1,3 à 2,4 millions
d'exécutions, sans trouver d'échec.

## Contre quoi il est vérifié {#what-it-is-checked-against}

**Ce que les fournisseurs d'identité envoient réellement**, testé avec leurs
charges utiles : le `"Replace"` d'Entra ID, ses booléens en chaîne
(`"active": "False"`), son retrait de membres par liste de valeurs, son ajout
filtré qui crée un courriel ; le remplacement sans chemin d'Okta qui répète
l'`id`. Le filtre, PATCH et tout le gestionnaire sont soumis au fuzzing
(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), et le plancher de la voie de
couverture est de 92 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.2.0](https://pkg.go.dev/github.com/go-authn/scim@v0.2.0)
