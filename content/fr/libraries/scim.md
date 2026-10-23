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
go get github.com/go-authn/scim@v0.1.0
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

## Contre quoi il est vérifié {#what-it-is-checked-against}

**Ce que les fournisseurs d'identité envoient réellement**, testé avec leurs
charges utiles : le `"Replace"` d'Entra ID, ses booléens en chaîne
(`"active": "False"`), son retrait de membres par liste de valeurs, son ajout
filtré qui crée un courriel ; le remplacement sans chemin d'Okta qui répète
l'`id`. Le filtre, PATCH et tout le gestionnaire sont soumis au fuzzing
(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), et le plancher de la voie de
couverture est de 92 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
