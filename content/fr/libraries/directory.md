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
go get github.com/go-authn/directory@v0.14.0
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

## Attributs {#attributes}

Depuis la v0.13.0, une `Identity` peut porter des **attributs** : ce qu'une
source dit de quelqu'un sans rien prouver — un `uidNumber`, un répertoire
personnel, une adresse de messagerie. Ils sont tenus à l'écart des
identifiants à dessein : un identifiant décide de qui peut se connecter, un
attribut est *publié* à tous ceux qui ont le droit de chercher. Un serveur
comme [authnd]({{< relref "/authnd/entries.md" >}}) en fait les attributs
d'une entrée LDAP, et son schéma décide de ce qu'est l'entrée.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	a, err := directory.NewAttributes(
		directory.Attribute{Name: "uidNumber", Values: []string{"1000"}},
		directory.Attribute{Name: "mail", Values: []string{"dora@example.org"}},
		directory.Attribute{Name: "MAIL", Values: []string{"d.explorer@example.org", "dora@example.org"}},
	)
	fmt.Println(err)
	dora := directory.NewIdentity("dora", directory.WithPassword("hunter2"), directory.WithAttributes(a))
	fmt.Println(dora.Attributes().Names(), dora.Attributes().Get("UIDNUMBER"), dora.Attributes().Get("mail"))

	// What is published cannot hold a secret, nor what a server derives or answers itself.
	for _, name := range []string{"userPassword", "sambaNTPassword", "radiusHash", "cn", "memberUid", "2.5.4.35"} {
		_, err := directory.NewAttributes(directory.Attribute{Name: name, Values: []string{"x"}})
		fmt.Println(errors.Is(err, directory.ErrAttributeName), err)
	}
}
```

```
<nil>
[uidNumber mail] [1000] [dora@example.org d.explorer@example.org]
true directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "sambaNTPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "radiusHash" looks like it holds a secret (its name contains "hash"), and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "cn" is derived by the server from the name it publishes the entry under
true directory: not an attribute this package carries: "memberUid" is membership, which Members answers: a second answer would disagree with it
true directory: not an attribute this package carries: "2.5.4.35" is an OID: name it by its descriptor, so that what is refused by name stays refused
```

Les noms sont des descriptions d'attributs de la RFC 4512, comparées sans
tenir compte de la casse ni de l'ordre des options, si bien que `mail` et
`MAIL` sont un seul attribut, écrit de la première façon dont il a été donné ;
une répétition exacte d'une valeur est gardée une fois. Les valeurs sont des
chaînes et ne sont pas interprétées : `"1000"` est un `uidNumber` parce que le
schéma d'un serveur le dit. Une valeur vide, ou aucune valeur, est refusée.

| refusé | pourquoi |
|---|---|
| 56 secrets nommés — `userPassword`, `authPassword`, `userPKCS12`, `sambaNTPassword`, `sambaLMPassword`, `unicodePwd`, `krbPrincipalKey`, `krb5Key`, `ipaNTHash`, `ipatokenOTPkey`, `oathSecret`, `olcRootPW`, … | relevés dans la RFC 4519, la RFC 3112, la RFC 2798 et les schémas de Samba, d'Active Directory, de Kerberos MIT et Heimdal, de FreeIPA, de 389-ds et d'OpenLDAP |
| tout nom contenant `password`, `passwd`, `pwd`, `secret`, `credential`, `hash` ou `privatekey` | une liste ne connaît que les schémas que quelqu'un a lus ; le seul nom standard que cela attraperait, `secretary` (RFC 4524), est autorisé |
| `sshPublicKey` | il a son propre chemin, `WithPublicKeys`, pour que `Can(PublicKeys)` reste vrai |
| `uid`, `userid`, `cn`, `commonName`, `objectClass` | un serveur les dérive du nom sous lequel il publie l'entrée |
| `member`, `uniqueMember`, `memberUid`, `memberOf` | l'appartenance est ce à quoi répond `Members`, et une seconde réponse serait en désaccord |
| `createTimestamp`, `modifyTimestamp`, `creatorsName`, `modifiersName`, `structuralObjectClass`, `governingStructureRule`, `subschemaSubentry`, `entryDN`, `entryUUID` | un serveur les maintient ; une configuration ne pourrait que les contrefaire |
| un nom sous forme numérique | les refus se font par nom, et `2.5.4.35` *est* `userPassword` |

`ReservedAttributes()` renvoie la liste entière, 75 noms avec leurs raisons ;
`CheckAttributeName` applique la règle seule, si bien qu'une configuration
peut être refusée avant que quoi que ce soit ne soit lu.

D'où ils viennent :

- **`hcldir`** : `attributes = { … }` dans les blocs `user` et `group`, une
  chaîne ou une liste de chaînes par nom ; un nombre est refusé avec la
  correction dans le message (*write it as a string, "1000"*), et `null` omet
  l'attribut.
- **`sqldir`** : deux requêtes facultatives, `users_attributes` et
  `groups_attributes` (`Queries.PeopleAttributes`, `GroupAttributes`), lues
  **par alias de colonne** : la première colonne est le nom, chaque autre
  colonne un attribut nommé par son alias. Une colonne dont l'alias n'est pas
  une description d'attribut, ou nomme un identifiant, est refusée avec son
  numéro de colonne avant qu'une ligne ne soit lue. `NULL` et `''` valent
  absence, et plusieurs lignes pour un même nom ajoutent des valeurs. Un
  groupe nommé seulement là existe, sans personne dedans.
  ⛔ PostgreSQL met en minuscules un alias sans guillemets (`as uidNumber`
  revient `uidnumber`) : le même attribut, écrit à la façon de la base.
  Mettez-le entre guillemets, `as "uidNumber"`, là où la graphie compte.
- **`ldapdir`** : `Config.Attributes` et `GroupAttributes` (`attributes` et
  `group_attributes` dans un bloc `users "ldap"`) nomment ce qu'il faut
  copier depuis l'entrée de chaque personne et celle de chaque groupe,
  appariés selon l'équivalence de la RFC 4512 et gardés dans la graphie
  configurée. En plus de la liste ci-dessus, il refuse le `totp_attribute` et
  les attributs de nommage et de membres du groupe. Un sous-type que
  l'annuaire renvoie en plus (`description;lang-fr` pour `description`) n'est
  pas copié : demandez-le par son nom.

Les attributs d'un groupe viennent de `Set.GroupAttributes`, par
l'interface facultative `GroupAttributer` : **la première source qui donne un
attribut le possède**, si bien qu'un `gidNumber` dans un fichier local
l'emporte sur celui de l'annuaire tandis qu'une `description` que seul
l'annuaire a passe, et une source en panne est une erreur même quand une
autre a répondu. Les attributs d'une personne viennent avec la personne,
depuis la source qui possède le nom.

## Les valeurs par défaut de ldapdir {#ldapdir-defaults}

| réglage (`users "ldap"` / `ldapdir.Config`) | défaut depuis la v0.14.0 | jusqu'à la v0.13.0 |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`, `ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | le même |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | le même |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`, `ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | le même |
| `group_member_attribute` / `MemberAttribute` | aucun : `memberUid` (des noms) **et** `member` (des DN) ; s'il est défini, c'est le seul attribut lu | `memberUid` |

Les trois classes sont les classes standard qui portent un `uid` :
`posixAccount` (RFC 2307), `account` (RFC 4524 §3.1) et `uidObject` (RFC 4519
§3.14). go-authn/authnd, depuis la v0.11.0, publie une personne sans les
attributs POSIX comme un `account` ou un `inetOrgPerson`, met `uidObject` sur
chaque personne, et publie un groupe sans `gidNumber` comme un
`groupOfNames`. Avec les anciennes valeurs par défaut, ces personnes et ces
groupes n'étaient pas lus du tout.

{{< callout type="warning" >}}
**La v0.14.0 élargit ce que donne l'annuaire d'un établissement**

Un annuaire qui contient des entrées `account` ou `uidObject` qui ne sont pas
des posixAccounts — comptes de service, hôtes nommés par uid, personnes
importées d'ailleurs — les donne désormais à tout programme qui a gardé la
valeur par défaut, et chacune peut alors être vérifiée contre l'annuaire par
une liaison. Ses groupes `groupOfNames` deviennent des groupes, et une règle
`@group` qui en nomme un accorde désormais ce qu'elle dit. Un simple
`inetOrgPerson` sans aucune des trois classes n'est toujours pas lu. Pour
garder exactement l'ancien ensemble :

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**Un DN `member` n'ajoute aucune personne.** Il ne correspond à quelqu'un que
lorsqu'il est, selon distinguishedNameMatch (RFC 4517 §4.2.15), le DN d'une
entrée qu'a renvoyée la recherche des personnes. Un DN en dehors de ces
entrées, ou qui ne nomme personne, ne correspond à personne, de même que
`uid=alice,ou=elsewhere,…` quand alice a été importée depuis `ou=people`.
Jusqu'à la v0.13.0, un DN de l'attribut de membres était réduit à la valeur
de son premier RDN, à qui qu'il appartienne, si bien que
`uid=alice,ou=elsewhere,…`, `cn=alice,…` et `uid=zed,…` devenaient des
membres nommés alice, alice et zed.

`ldaptest`, l'annuaire de test, applique désormais la base et le filtre à
chaque recherche, donne à chaque personne un `objectClass`
(`Person.ObjectClasses`, par défaut `top`, `account`, `posixAccount`) et a
des groupes `groupOfNames` (`GroupsOfNames`), si bien qu'un test des filtres
d'un client peut échouer.

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
- **Un attribut qui est un secret, ou auquel un serveur répond lui-même** —
  [la liste ci-dessus]({{< relref "/libraries/directory.md#attributes" >}}) — où qu'il soit configuré : dans un bloc,
  comme alias SQL, ou dans la liste de ldapdir à copier.

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
- **`sqldir` contre une vraie base de données SQLite**, à travers un vrai pilote. Les
  requêtes d'attributs ont aussi été lancées une fois à la main contre
  PostgreSQL 18.6 par pgx, pas en CI : un alias sans guillemets est revenu en
  minuscules et a quand même été trouvé, un alias entre guillemets a gardé sa
  casse, et un alias nommant `userPassword` a été refusé.
- **Les filtres de ldapdir** contre `ldaptest`, qui les applique depuis la
  v0.14.0 : le filtre de personnes par défaut laisse de côté un simple
  `inetOrgPerson` (`TestTheDefaultUserFilter`), et le filtre de groupes
  n'ajoute aucune identité (`TestTheGroupFilterAddsNoIdentity`).
- **MD4** contre les vecteurs de test de la RFC 1320.

La voie de couverture échoue sous 85 % (sa norme déclarée est 100 %), et les
compilations `nosql` et `noldap` sont vérifiées en CI.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
