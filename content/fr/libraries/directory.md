---
title: "directory — qui est quelqu'un, et ce qui le prouve"
linkTitle: "directory"
weight: 50
description: "go-authn/directory : un seul modèle d'une personne et des identifiants qu'une source détient pour elle, sur une liste en mémoire, une base de données SQL, un serveur LDAP ou une configuration HCL."
tags: [bibliothèques, annuaire, ldap, sql]
---

**Qui est quelqu'un, et qu'est-ce qui peut le prouver ?** Un seul modèle sur une liste
tenue en mémoire, une base de données SQL, un serveur LDAP, ou des blocs `user` et `group` dans un
fichier de configuration — et ce qui compte, c'est la seconde moitié de la question.

```sh
go get github.com/go-authn/directory@v0.12.0
```

## Ce qui prouve quelqu'un n'est pas une seule chose {#what-proves-somebody-is-not-one-thing}

C'est un fait des protocoles. NTLMv2 (SMB) est un défi-réponse : le client
n'envoie jamais le mot de passe, donc le serveur doit détenir le mot de passe ou
`MD4(UTF16LE(password))` — l'empreinte NT — et **une liaison LDAP ne peut pas
authentifier une session SMB**. Un KDC doit *déchiffrer* avec la clé de la personne, donc
seule une source qui détient le mot de passe peut adosser un royaume. SSH a besoin d'une clé publique.
Un second facteur a besoin du secret derrière les six chiffres.

Une `Identity` dit donc quels `Credential` sa source a fournis — `Password`,
`NTHash`, `Verifier` (une comparaison d'empreintes ou une liaison), `PublicKeys`,
`TOTPSecret` — et `Identity.Can` permet à un serveur de dire *vous pouvez utiliser WebDAV et pas
SMB* avant que quelqu'un se heurte à un refus au montage. Chaque protocole a sa propre
méthode :

| | répond à | à partir de |
|---|---|---|
| `Verify(password)` | tout ce à quoi on remet le mot de passe | le vérificateur de la source d'abord (ce peut être une liaison LDAP), sinon le mot de passe détenu, comparé en temps constant sur des condensés SHA-256 pour que même la longueur ne fuie pas |
| `NTKey()` | NTLMv2 | l'empreinte publiée, ou dérivée du mot de passe ; `ErrNoCredential` sans l'un ni l'autre |
| `Derive(f)`, `KerberosKey(f)` | un KDC, AWS SigV4 — tout ce qui doit *posséder* le secret | le mot de passe seulement ; la dérivation est la fonction de l'appelant |
| `Keys()` | SSH | des lignes `authorized_keys` |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | une colonne, ou un attribut LDAP que l'appelant nomme |

## Les sources {#the-sources}

| paquet | lit | importe |
|---|---|---|
| `directory` | une liste `Static`, et un `Set` de sources dans l'ordre | la bibliothèque standard seulement |
| `directory/sqldir` | n'importe quel `*sql.DB`, avec **vos** requêtes | aucun pilote : le programme en choisit un |
| `directory/ldapdir` | un serveur LDAP | `go-ldap/ldap/v3` |
| `directory/hcldir` | un bloc `users` nommant une base de données ou un serveur LDAP, et des blocs `user`/`group` contenant des personnes | `x/crypto/ssh`, `hashicorp/hcl/v2`, `zclconf/go-cty` |
| `directory/ldaptest` | un serveur LDAP contre lequel tester | `glauth/ldap` |

Dans un `Set`, la **première** source qui connaît un nom en est propriétaire, si bien qu'un compte
de service écrit localement n'a pas besoin d'être mis dans LDAP. L'appartenance aux groupes est
l'**union** de toutes les sources. Les sources sont lues au démarrage d'un serveur ; une vérification
de mot de passe peut atteindre la source à chaque fois, parce qu'une liaison ne peut pas être mise en cache
sans détenir le secret.

`hcldir` ne décode pas le HCL : l'appelant décode le bloc et le lui remet.
Il n'importe HCL que pour écrire, pour `SetPassword`. Les étiquettes de compilation `nosql` et
`noldap` retirent entièrement un type de source de `hcldir`.

## Exemple {#example}

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	local := &directory.Static{
		Name: "the configuration file",
		People: []*directory.Identity{
			directory.NewIdentity("dora", directory.WithPassword("hunter2")),
			directory.NewIdentity("eli", directory.WithVerifier(func(pw string) error {
				return directory.ErrWrongPassword // a bind against somebody else's LDAP, say
			})),
			directory.NewIdentity("svc-backup", directory.WithPublicKeys("ssh-ed25519 AAAA...elided... backup")),
		},
		Groups: map[string][]string{"staff": {"dora", "eli"}, "nobody": {}},
	}
	people := directory.NewSet(local) // more sources after it: sqldir, ldapdir...

	ids, _ := people.Identities()
	for _, id := range ids {
		fmt.Println(id.Name(), "password:", id.Can(directory.Password), "verifier:", id.Can(directory.Verifier),
			"keys:", id.Can(directory.PublicKeys), "from", id.Where())
	}

	// NTLMv2 needs MD4(UTF16LE(password)): dora's can be derived, eli's cannot.
	for _, id := range ids[:2] {
		_, err := id.NTKey()
		fmt.Println(id.Name(), "SMB:", err == nil, errors.Is(err, directory.ErrNoCredential))
	}

	// An empty group is an empty answer; a group nobody has is an error.
	fmt.Println(people.Members("nobody"))
	fmt.Println(people.Members("admins"))

	// @group is expanded; an empty group, or one nobody has, is refused.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	_, err := directory.Expand([]string{"@nobody"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
	_, err = directory.Expand([]string{"@admins"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[] <nil>
[] directory: no such group: "admins", in the configuration file
[dora eli svc-backup] <nil>
[] directory: the group has no members: "nobody": nobody would be allowed
directory: the group has no members: "nobody": nobody would be allowed true false
directory: no such group: "admins", in the configuration file false true
```

Un mot de passe détenu répond aussi à `Can(Verifier)` : il peut être comparé.

{{< callout type="info" >}}
**Un groupe vide est un groupe : `Members` y répond, `Expand` le refuse**

Depuis la v0.12.0, `Set.Members` renvoie une liste vide et aucune erreur pour
un groupe qu'une source possède mais où il n'y a personne, si bien qu'un
serveur qui liste les groupes peut le publier. `Expand` le refuse toujours,
avec `ErrEmptyGroup`, qui n'est pas `ErrNoSuchGroup` : un groupe que personne
n'a est une faute de frappe ou un groupe supprimé, un groupe vide est un groupe
à remplir. Un appelant qui tolère un groupe n'accordant rien teste les deux.
En v0.11.x, `Set.Members` renvoyait `ErrNoSuchGroup` pour un groupe vide, et
`Expand` de `@nobody` à travers le `Set` affichait
`[] directory: no such group: "nobody"`.
{{< /callout >}}

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

- **Un groupe où il n'y a personne**, et **un groupe qu'aucune source n'a**,
  quand `Expand` transforme `@groupe` en personnes — des erreurs, pas des
  listes vides : une configuration qui n'accorde rien à personne se lit
  exactement comme une qui fonctionne. Le premier est `ErrEmptyGroup`, le
  second `ErrNoSuchGroup`, et `errors.Is` les distingue. `Set.Members` répond à
  un groupe vide par une liste vide ; un groupe qu'aucune source n'a y est
  aussi `ErrNoSuchGroup`. Une source *en panne* est signalée à part d'une
  source à qui le groupe manque, et l'emporte sur une réponse vide.
- **Un annuaire LDAP atteint en clair.** Une liaison simple transporte le
  mot de passe lui-même (RFC 4513), donc `ldapdir.New` et un bloc `users "ldap"`
  refusent `ldap://` vers une autre machine sauf si `StartTLS` est positionné. `ldaps://`,
  `ldapi://` et `ldap://` vers une adresse de bouclage sont acceptés. Il n'y a aucun
  interrupteur pour désactiver cela.
- **Un mot de passe vide lors d'une liaison LDAP.** En LDAP, c'est une *liaison non
  authentifiée*, à laquelle la plupart des annuaires répondent par un succès ; `ldapdir` répond
  `ErrWrongPassword` sans se connecter.
- **Tout autre échec de liaison pris pour un mauvais mot de passe.** Seul le résultat LDAP 49,
  *invalidCredentials*, est `ErrWrongPassword`. Une connexion coupée pendant la
  liaison, un annuaire qui répond occupé (51) ou indisponible (52), est renvoyé comme
  `ldapdir: the directory did not answer the bind: …`, en enveloppant l'erreur LDAP.
  Le mot de passe est refusé dans les deux cas ; ce qui change, c'est que le journal d'un serveur
  ne dit plus *wrong password* à quelqu'un qui l'a tapé correctement. Avant la v0.11.2,
  tout échec de liaison était `ErrWrongPassword`.
- **Des identifiants dans une URL LDAP** — une URL est affichée ; `BindDN` et
  `BindPassword` sont des champs.
- **Une empreinte NT qui ne fait pas 16 octets** (`ParseNTHash`), plutôt que de la compléter
  en une empreinte qui fait échouer chaque connexion comme un mauvais mot de passe.
- **`Derive` ou `KerberosKey` pour une identité sans le mot de passe.** Le
  oui d'un vérificateur n'est pas une clé.

{{< callout type="warning" >}}
**L'empreinte NT et le secret TOTP sont des identifiants, pas des empreintes d'identifiant**

Quiconque détient `sambaNTPassword` s'authentifie comme cette personne exactement comme
avec le mot de passe ; quiconque détient un secret TOTP produit tous les codes
à venir. L'erreur de `WithVerifier` va au serveur, jamais au client.
{{< /callout >}}

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

- **Le `ldapsearch` d'OpenLDAP** lit l'annuaire de `ldaptest` — les entrées, le
  `sambaNTPassword` de la seule personne qui en a un, le groupe — et est refusé
  avec *Invalid credentials (49)* pour un mauvais mot de passe. Les voies Linux de la CI
  installent `ldap-utils` ; là où `ldapsearch` est absent, le test est sauté, car
  rien dans la CI de ce module ne transforme ce saut en échec.
- **`ldapdir` contre `glauth/ldap`**, un serveur LDAP indépendant, pas une imitation ;
  le jeu d'essai autorise la liaison non authentifiée, donc le test échoue si `ldapdir`
  cesse de la refuser en premier.
- **`sqldir` contre une vraie base de données SQLite**, à travers un vrai pilote.
- **MD4** contre les vecteurs de test de la RFC 1320.

La voie de couverture échoue sous 85 % (sa norme déclarée est 100 %), et les
compilations `nosql` et `noldap` sont vérifiées en CI.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.12.0](https://pkg.go.dev/github.com/go-authn/directory@v0.12.0)
