---
title: "ldap — les octets d'un serveur LDAP"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap est le protocole LDAP sous forme de bibliothèque serveur : le réseau, le filtre, les opérations et leurs limites, avec des gestionnaires qui décident de ce qui est répondu."
tags: [bibliothèques, ldap, annuaire]
---

**Quels sont les octets d'un serveur LDAP ?** Une bibliothèque, pas un démon : le réseau,
le filtre, les opérations. [authnd]({{< relref "/authnd/_index.md" >}}) est le
serveur qui l'exécute et qui détient la configuration, les sources d'annuaire et la
politique de liaison ; celle-ci détient les octets.

```sh
go get github.com/go-authn/ldap@v0.10.1
```

Écrite d'après les RFC 4511 (le protocole), 4512 (le root DSE et le schéma),
4513 (l'authentification), 4514 et 4515 (formes textuelles des DN et des
filtres), 4517 et 4518 (syntaxes, règles de correspondance, préparation des
chaînes), 4526, 2696 (résultats paginés), 3672 (sous-entrées), 3673, 4527
(contrôles de lecture d'entrée), 4532 (whoami) et 3045.

Un `Server` est un ensemble de gestionnaires, chacun un champ facultatif : `Bind`, `SASL`,
`Search`, `Compare`, `Extended`, `Add`, `Modify`, `Delete`, `ModifyDN`,
`Abandon`. Un gestionnaire nil signifie *ce serveur ne fait pas cela*, et l'opération
reçoit la réponse `unwillingToPerform` — pas `insufficientAccessRights`, qui ouvrirait
une discussion sur des permissions qui n'existent pas. Le root DSE reçoit sa réponse
du serveur lui-même, et publie exactement ce qu'il honore.

## Exemple {#example}

Un serveur avec une personne qui peut se lier et une recherche qui écrit ce que
le filtre sélectionne :

```go
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"log/slog"
	"os"

	"github.com/go-authn/ldap"
)

var people = []*ldap.Entry{
	{DN: "uid=dora,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "dora")}},
	{DN: "uid=svc-web-prod,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-prod")}},
	{DN: "uid=svc-web-stage,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-stage")}},
}

// binder checks one password. A real one asks a directory: see go-authn/directory.
type binder struct{}

func (binder) Bind(_ context.Context, _ ldap.Session, req *ldap.BindRequest) (ldap.Result, error) {
	if req.Name == "" && len(req.Simple) == 0 {
		return ldap.Result{Code: ldap.Success}, nil // anonymous: the connection stays unbound
	}
	// A name with an empty password is an UNAUTHENTICATED bind (RFC 4513
	// 5.1.2). This package hands it to the handler, and the handler refuses it:
	// the comparison below does, since the password is never empty.
	ok := ldap.EqualDN(req.Name, "uid=dora,ou=people,dc=example,dc=org") &&
		subtle.ConstantTimeCompare(req.Simple, []byte("hunter2")) == 1
	if !ok {
		return ldap.Refuse(ldap.InvalidCredentials, "invalid credentials"), nil
	}
	return ldap.Result{Code: ldap.Success}, nil
}

// searcher writes each entry in scope that the filter matches, as it finds it.
type searcher struct{}

func (searcher) Search(_ context.Context, s ldap.Session, req *ldap.SearchRequest, w ldap.EntryWriter) (ldap.Result, error) {
	if s.BoundDN() == "" {
		return ldap.Refuse(ldap.InsufficientAccessRights, "bind first"), nil
	}
	for _, e := range people {
		if ldap.InScope(e.DN, req.BaseObject, req.Scope) && req.Filter.Matches(e) {
			if err := w.Entry(e); err != nil {
				return ldap.Result{}, err // the client went away, or a limit was reached
			}
		}
	}
	return ldap.Result{Code: ldap.Success}, nil
}

func main() {
	srv := &ldap.Server{
		Bind:           binder{},
		Search:         searcher{},
		NamingContexts: []string{"dc=example,dc=org"},
		Log:            slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// On anything but loopback: TLSConfig, and RequireTLS so that a
		// client that never asks for StartTLS is refused rather than
		// sending its password in the clear.
	}
	log.Fatal(srv.ListenAndServe("127.0.0.1:3389"))
}
```

Interrogé par le `ldapsearch` d'OpenLDAP (2.4.28, tel que macOS le fournit), avec le
mot de passe de dora dans un fichier :

```
$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw \
    -b ou=people,dc=example,dc=org '(uid=svc-*-prod)' uid
dn: uid=svc-web-prod,ou=people,dc=example,dc=org
uid: svc-web-prod

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -b ou=people,dc=example,dc=org '(uid=*)' uid
Insufficient access (50)
Additional information: bind first

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -s base -b '' namingContexts supportedLDAPVersion supportedExtension
dn:
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3

$ printf 'dn: uid=dora,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: uid\nuid: x\n' |
    ldapmodify -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw
ldap_modify: Server is unwilling to perform (53)
	additional info: this server does not modify entries
modifying entry "uid=dora,ou=people,dc=example,dc=org"
```

`(uid=svc-*-prod)` renvoie `svc-web-prod` et pas `svc-web-stage`. La bibliothèque
que celle-ci remplace évaluait ce filtre comme `(uid=svc-*)` et renvoyait aussi
`svc-web-stage` ; c'est à cause de ce défaut que cette bibliothèque a été écrite. Le
root DSE ne mentionne pas StartTLS, parce qu'aucun `TLSConfig` n'a été donné.

## Ce qu'elle refuse, et pourquoi {#what-it-refuses-and-why}

**Un filtre veut dire une seule chose.** Il est analysé ou décodé une seule fois en un arbre, et
`String`, `EncodeFilter` et `Matches` lisent tous cet arbre. Un attribut qui n'est
pas une description d'attribut au sens de la RFC 4512 §2.5, ou une règle de correspondance qui n'est pas un
OID, est refusé à la fois par `ParseFilter` et par `DecodeFilter` : avant la v0.6.1, réimprimé, un
filtre « présent » sur l'attribut `!x` se lisait comme un NOT.

**Du texte en clair, alors qu'autre chose était promis.** StartTLS est demandé par le
*client* : un serveur qui se contente de le proposer n'a donc rien promis.
`RequireTLS` refuse toute opération sur une connexion qui n'est pas protégée,
avec `confidentialityRequired`.

**Une liaison qui a échoué ne garde rien.** RFC 4511 §4.2.1 : la connexion est rendue
anonyme quand la requête de liaison est *reçue*, et le reste à moins que la liaison
ne réussisse — une nouvelle liaison avec un mauvais mot de passe ne garde donc pas les droits de la
personne précédente. Une liaison simple sans gestionnaire `Bind` reçoit la réponse
`authMethodNotSupported`, et LDAPv2 est refusé comme erreur de protocole.

{{< callout type="warning" >}}
**Le gestionnaire décide de ce que signifie un mot de passe vide**

Une liaison non authentifiée — un nom avec un mot de passe vide, RFC 4513 §5.1.2 — est
transmise au gestionnaire `Bind` comme n'importe quelle autre liaison simple, et un gestionnaire qui
renvoie `Success` pour elle lie la connexion sous ce nom. Refusez-la dans le
gestionnaire, comme le fait l'exemple. Le `ldapdir` de
[directory]({{< relref "/libraries/directory.md" >}}) la refuse côté client.
{{< /callout >}}

**Un contrôle critique qu'elle n'honore pas.** ManageDsaIT (RFC 3296), la modification de
mot de passe (RFC 3062) et l'annulation (RFC 3909) sont nommés en constantes parce qu'un
client peut les envoyer, pas parce qu'on y répond : rien ici ne suit
les alias ni les renvois (referrals), si bien qu'un ManageDsaIT critique est refusé avec
`unavailableCriticalExtension`.

**Ce qu'un pair non authentifié peut retenir :**

| | par défaut | |
|---|---|---|
| `MaxMessageSize` | 4 Mio | un en-tête de cinq octets annonçant quatre gigaoctets est refusé avant que quoi que ce soit ne soit réservé |
| `MaxMessageElements` | 16384 | éléments BER comptés avant décodage : avant la v0.5.0, 4 Mio de chaînes vides retenaient 373 Mio avant toute liaison |
| `IdleTimeout` | 5 minutes | le message entier doit arriver à temps, pas son premier octet ; une valeur négative signifie jamais |
| `MaxPending`, `MaxPendingAuth` | 100, 1000 | opérations qu'une connexion peut avoir en cours avant sa liaison (`MaxPending`) et après (`MaxPendingAuth`), comme les `conn_max_pending` et `conn_max_pending_auth` de slapd ; une connexion qui dépasse reçoit un avis de déconnexion et est fermée |
| `MaxPagedSearches` | 4 | recherches paginées ouvertes par connexion, chacune une goroutine en attente de son entrée suivante |

La profondeur d'imbrication des filtres est bornée elle aussi : un débordement de pile en Go tue le processus.
Rien ne journalise la *valeur* d'une assertion — un filtre porte ce que quelqu'un a tapé — seulement
la forme du filtre.

**Une recherche paginée répond à ce qui a été demandé.** Jusqu'à la v0.8.0, le
lecteur de pages envoyait chaque entrée telle que le gestionnaire l'avait
écrite : une recherche paginée de `cn` seul revenait avec tous les attributs,
opérationnels compris, et `typesOnly` était ignoré, alors que la même
recherche non paginée s'en tenait à la sélection. `ldapsearch -E pr=N` est la
façon dont un client pagine, si bien que la même question recevait deux
réponses. Depuis la v0.8.0, les deux appliquent la sélection, ce que
`ldapsearch` lui-même vérifie en CI.

Sans schéma — `Server.Schema` nil, la valeur par défaut — toute comparaison
est insensible à la casse sur la valeur : la plus sûre des deux pour la
lecture, puisqu'elle ne cache jamais une entrée qu'une comparaison exacte
aurait trouvée.

## Le schéma {#the-schema}

Depuis la v0.8.0, le paquet `schema` est le schéma d'annuaire de la RFC 4512
§4, et `Server.Schema` fait qu'un serveur l'utilise. Nil laisse un serveur
exactement tel qu'il était.

- `schema.Standard()` embarque les définitions des RFC 4512, 4517, 4519,
  4524, 4523, 2798, 2307, 3672 et 3045, plus `ldapPublicKey` et
  `sshPublicKey` d'openssh-lpk et les deux définitions OpenLDAP dont ils ont
  besoin, copiées du texte des RFC ; chaque fichier de `schema/defs` nomme sa
  source et sa section. `schema.Build(append(schema.StandardFiles(), mine)...)`
  ajoute celles d'un déploiement, et refuse celle dont le SUP, les règles,
  les syntaxes, le MUST ou le MAY ne se résolvent pas.
- `(*ldap.Entry).Validate(s)` vérifie une chaîne structurelle avec chaque
  superclasse listée, chaque MUST, rien en dehors de MUST et MAY,
  SINGLE-VALUE, des types connus, des valeurs de leur syntaxe, et les valeurs
  du RDN dans l'entrée — et nomme **chaque** problème, sous forme d'un
  `*schema.ValidationError`.
- Avec un schéma, le root DSE porte `subschemaSubentry: cn=Subschema`, et une
  recherche de base sur `cn=Subschema` (`ldap.SubschemaDN`) reçoit sa réponse
  de la bibliothèque, comme le root DSE (RFC 4512 §4.2). Les définitions ne
  viennent que lorsqu'on les demande par leur nom ou avec `+`. Elle est
  derrière la barrière `RequireTLS`.
- Les filtres sont évalués avec les règles de correspondance du schéma (RFC
  4517 §4.2, avec la préparation des chaînes de la RFC 4518) dans la logique
  à trois valeurs de la RFC 4511 : un attribut inconnu, un type sans règle
  pour la correspondance demandée, ou une valeur d'assertion invalide est
  **Undefined**, jamais une erreur. Le serveur revérifie chaque entrée
  qu'envoie un gestionnaire et écarte celles que le filtre ne rend pas TRUE ;
  un gestionnaire filtre avec `req.Matches(e)`, qui utilise le même schéma.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap"
	"github.com/go-authn/ldap/schema"
)

func main() {
	s := schema.Standard() // RFC 4512, 4517, 4519, 4524, 2798, 2307, ... and openssh-lpk

	// An account with posixAccount, and no homeDirectory.
	eli := &ldap.Entry{DN: "uid=eli,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "top", "account", "posixAccount"),
		ldap.StringAttribute("uid", "eli"),
		ldap.StringAttribute("cn", "eli"),
		ldap.StringAttribute("uidNumber", "1001"),
		ldap.StringAttribute("gidNumber", "1001"),
		ldap.StringAttribute("mail", "eli@example.org"),
	}}
	var v *schema.ValidationError
	if errors.As(eli.Validate(s), &v) {
		for _, p := range v.Problems {
			fmt.Println("-", p)
		}
	}

	// uidNumber orders as an integer: 1001 >= 999, which as strings it is not.
	for _, f := range []string{"(uidNumber>=999)", "(uid>=a)"} {
		filter, _ := ldap.ParseFilter(f)
		fmt.Println(f, ldap.Evaluate(filter, eli, s))
	}
}
```

```
- mail is not allowed by any of the entry's object classes
- homeDirectory is required by posixAccount and is missing
(uidNumber>=999) TRUE
(uid>=a) Undefined
```

`mail` appartient à `inetOrgPerson`, pas à `account`. `uid` n'a pas de règle
ORDERING, donc une plage sur lui est Undefined.

{{< callout type="info" >}}
**Un écart par rapport à la RFC 2307 : `uidNumber` et `gidNumber` s'ordonnent comme des entiers**

La RFC 2307 donne à `uidNumber` et `gidNumber` une règle EQUALITY et aucune
règle ORDERING, ce qui rendrait Undefined tout filtre de plage sur eux — y
compris celui que SSSD construit à partir de `ldap_min_id` et `ldap_max_id`.
slapd définit lui-même les deux types avec `ORDERING integerOrderingMatch`
(`servers/slapd/schema_prep.c` ; son `nis.schema` les met en commentaire
comme « builtin »), et draft-howard-rfc2307bis-02 §2.1 aussi, donc les
définitions embarquées les suivent. Cela, et le fait d'autoriser des classes
auxiliaires sans règles de contenu DIT (la RFC 4512 §2.4.3 les interdit
strictement ; tous les serveurs en usage les autorisent), est dit plutôt que
découvert.
{{< /callout >}}

Absents, délibérément : les règles de contenu DIT, les règles de structure
DIT et les formes de noms ; la modification du schéma par LDAP ; les règles
de correspondance de certificats de la RFC 4523 et
`directoryStringFirstComponentMatch`, qui sont définies et non implémentées,
si bien que les assertions qui les utilisent sont Undefined ; les attributs
collectifs ; les options autres que `lang-` et `binary`.

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}) sert ce
schéma et y soumet chaque entrée qu'il publie.

## Lire un gros fichier de schéma {#reading-large-files}

Jusqu'à v0.10.0, `schema.Read` prenait un temps quadratique en nombre de lignes de continuation du fichier lu : un fichier de 4 Mio de courtes lignes de continuation prenait environ trois minutes, et 1 Mio allouait 139,6 Go. Un programme qui lit un fichier de schéma qu'il ne maîtrise pas, comme authnd pour ses `schema_files` au démarrage, pouvait être bloqué par un tel fichier. Depuis v0.10.1 le temps est linéaire (`TestManyContinuationLinesJoinInLinearTime`), et `Read` ne copie ni ne découpe plus tout le fichier pour regarder sa première ligne.

`schema.Format` écrivait des lignes de plus de 2000 octets, que slapd et `Read` refusent ; il les replie désormais. L'analyseur strict est environ 2,6 fois plus rapide, avec 147 allocations au lieu de 498 sur `cosine.schema`. Face à libldap (SDK macOS, `ldap_str2attributetype` et `ldap_str2objectclass` avec `LDAP_SCHEMA_ALLOW_ALL`), sur les 54 définitions du `cosine.schema` d'OpenLDAP, mesuré le 2026-10-26 sur un Apple M4 Max à une charge de 6,5 à 7,6 (`-cpu 1 -count 10`, benchstat) : go-authn/ldap 25,65 µs ± 32 %, libldap 35,62 µs ± 2 %, soit environ 0,72 fois le temps de libldap. Côté Go : 147 allocations (20,6 Kio) par exécution ; `-benchmem` ne voit pas les allocations C de libldap, il n'y a donc pas de chiffre pour elles. Pour reproduire, lancez `go test -bench . -benchmem -cpu 1 -count 10` dans `bench/libldap` de go-authn/ldap (cgo et libldap sont nécessaires). authnd a ces correctifs depuis v0.12.3.

## Un schéma qui ne se construit pas {#build-error}

Depuis la v0.10.0, une définition que `schema.Build` ou `schema.BuildFrom`
refuse est une `*schema.BuildError`, que l'on retrouve avec `errors.As`. Un
programme rapporte un refus à partir de ses champs, jamais en comparant le
message. Build s'arrête à la première définition qu'il refuse : il n'y en a donc
qu'une.

- `Kind` est l'un des contrôles que fait Build : `UnknownReference`,
  `DuplicateOID`, `DuplicateName`, `SuperiorCycle`, `KindViolation`,
  `UsageMismatch`, `CollectiveMismatch` et `UsageViolation`.
- `Element` (syntaxe, règle de correspondance, type d'attribut ou classe
  d'objet), `OID` et `Name` (son premier NAME) sont ceux de la définition
  refusée, et `Pos` est l'endroit où elle commence : `fichier:ligne:colonne`, la
  ligne du mot-clé du `.schema` ou de la ligne LDIF `attributeTypes:`, y compris
  quand cette ligne est repliée ou en base64, et la position du bloc lui-même
  pour le HCL. Une définition construite en code n'en a pas.
- `Field` est le terme fautif (`SUP`, `EQUALITY`, `SYNTAX`, `MUST`, `NAME`
  ...), et `Ref` ce à quoi l'erreur renvoie : le nom ou l'OID non défini, ou
  l'autre définition, avec ses `RefOID` et `RefPos`. Pour un doublon, c'est la
  première définition, et le message dit où elle se trouve.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap/schema"
)

// An object class whose superclass is defined nowhere.
const site = `# site.schema
objectclass ( 1.3.6.1.4.1.99999.1.1 NAME 'siteMember'
	SUP top AUXILIARY )
objectclass ( 1.3.6.1.4.1.99999.1.2 NAME 'siteGuest'
	SUP nobody AUXILIARY )
`

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "site.schema", Data: []byte(site)})
	_, err := schema.Build(files...)

	var be *schema.BuildError
	if !errors.As(err, &be) {
		fmt.Println("not a BuildError:", err)
		return
	}
	fmt.Println("error:  ", be)
	fmt.Println("Kind:   ", be.Kind)
	fmt.Println("Element:", be.Element)
	fmt.Println("OID:    ", be.OID)
	fmt.Println("Name:   ", be.Name)
	fmt.Println("Field:  ", be.Field)
	fmt.Println("Ref:    ", be.Ref)
	fmt.Println("Pos:    ", be.Pos)
	fmt.Println("RefPos: ", be.RefPos.IsValid())
	fmt.Println("is UnknownReference:", be.Kind == schema.UnknownReference)
}
```

```
error:   site.schema:4:1: schema: the object class siteGuest has the superclass nobody, which is not defined
Kind:    unknown reference
Element: object class
OID:     1.3.6.1.4.1.99999.1.2
Name:    siteGuest
Field:   SUP
Ref:     nobody
Pos:     site.schema:4:1
RefPos:  false
is UnknownReference: true
```

Lancé depuis un module vide avec `github.com/go-authn/ldap` v0.10.0. La première
classe est correcte ; la seconde commence à la ligne 4, et rien d'autre n'est
fautif, donc `RefPos` est vide. Chaque définition que renvoie `schema.Read`
porte aussi un `Pos`, et le `String` de la Position omet la colonne quand elle
n'est pas connue.

## Les schémas en HCL2, et le convertisseur {#hcl2-and-the-converter}

Depuis la v0.9.0, un schéma peut s'écrire en HCL2 aussi bien que dans les
fichiers que lit slapd. Le paquet `schema/hclschema` décode le HCL2 vers les
mêmes `*schema.Definitions` que renvoie `schema.Read`, et les ré-encode
(`hclschema.Decode`, `hclschema.Encode`) ; `schema` lui-même n'a aucune
dépendance à HCL. Un bloc est une définition, et son type dit laquelle :
`object_identifier`, `ldap_syntax`, `matching_rule`, `attribute_type` ou
`object_class`. L'étiquette est le premier NAME. Les attributs sont les termes
de la RFC 4512 §4.1, en minuscules avec des tirets bas (`desc`, `sup`,
`equality`, `single_value`, `kind`, `must`, `may`, etc.), et le `{len}` d'une
syntaxe est `syntax_len`.

**Des valeurs littérales, seulement.** Une valeur est une chaîne entre
guillemets, un nombre, un booléen ou une liste de ceux-ci. Une variable, une
fonction, un opérateur ou un gabarit `${...}` est refusé avant toute
évaluation : lire un schéma ne l'exécute donc jamais. Chaque champ est vérifié
par l'analyseur strict de la RFC 4512, et les erreurs qui demandent une
position arrivent avec le fichier, la ligne et la colonne.

La commande `ldapschema` convertit d'un format à l'autre :

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.9.0
```

- `ldapschema to-hcl [--macros] FILE...` lit des fichiers `.schema` d'OpenLDAP,
  du LDIF cn=config et du LDIF de sous-schéma, et écrit du HCL2.
- `ldapschema to-schema [--macros] FILE...` lit du HCL2 et écrit un fichier
  `.schema` d'OpenLDAP.
- `ldapschema check FILE...` construit les définitions par-dessus
  `schema.Standard()` et rend compte.

La sortie va sur stdout. Le code de sortie est 0 quand la commande a réussi, 1
quand un fichier ou une définition est refusé, et 2 pour une erreur d'usage.

**Les lecteurs lisent les fichiers comme slapd**, parce que les schémas publiés
sont écrits pour slapd : termes dans n'importe quel ordre, continuation de
ligne de slapd dans un fichier `.schema` et pliage de la RFC 2849 en LDIF,
valeurs en base64, préfixe `{N}` de cn=config, et macros `objectidentifier`
résolues dans l'ordre des fichiers. Les fonctions `Parse*` exportées, et ce
qu'un serveur publie, restent strictement RFC 4512.

Un exemple, lancé depuis un répertoire vide avec `ldapschema` v0.9.0. Le
schéma est inventé pour cette page : 1.3.6.1.4.1.99999 est un arc d'exemple à
usage privé, attribué à personne. Une macro, un type d'attribut, une classe
auxiliaire :

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1 NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1 NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top AUXILIARY
	MAY siteBadge )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

attribute_type "siteBadge" {
  oid          = "1.3.6.1.4.1.99999.1.1"
  desc         = "the badge number"
  equality     = "caseIgnoreMatch"
  syntax       = "1.3.6.1.4.1.1466.115.121.1.15"
  syntax_len   = 32
  single_value = true
}

object_class "sitePerson" {
  oid  = "1.3.6.1.4.1.99999.2.1"
  desc = "a person with a badge"
  sup  = ["top"]
  kind = "auxiliary"
  may  = ["siteBadge"]
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( 1.3.6.1.4.1.99999.1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( 1.3.6.1.4.1.99999.2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 1 attribute types, 1 object classes
build: ok, 2 definitions added to schema.Standard()
```

Les OID numériques sont la sortie par défaut, parce que c'est ce qu'un client
voit dans le sous-schéma ; `--macros` garde les noms de macros. `check`
signale aussi les définitions que `schema.Standard()` possède déjà, et chaque
référence que rien ne définit, là où `Build` s'arrête à la première.

**`check` peut sortir avec le code 1 sur un fichier que slapd charge.** Le
`core.schema` d'OpenLDAP renvoie à quatre choses que slapd intègre et que
`schema.Standard()` ne définit pas : les syntaxes 1.3.6.1.4.1.1466.115.121.1.42
et 1.3.6.1.4.1.1466.115.121.1.43, et les règles de correspondance
`protocolInformationMatch` et `presentationAddressMatch`. `ldapschema check
core.schema` les liste sous `missing:` et sort avec le code 1. Il faut le lire
comme « non défini ici », pas comme un défaut du fichier.

**Ce qui n'est pas géré :** les règles de contenu DIT, les règles de structure
DIT et les formes de noms ; les directives `include`, puisqu'un fichier
`.schema` est lu comme des définitions et n'est pas exécuté comme une
configuration de slapd ; et `X-SUBST` sur `ldapsyntax`.

**Les schémas publiés se convertissent.** La version a été mesurée sur les
fichiers `core`, `cosine`, `inetorgperson` et `nis` d'OpenLDAP, sur SUPANN 2021
de RENATER, sur eduPerson de REFEDS et sur le schéma de Samba : pour chacun,
`.schema` vers HCL et retour, et LDIF contre `.schema`, donnent des
définitions égales. Seuls les fichiers d'OpenLDAP sont dans le dépôt. SUPANN et
eduPerson ne sont pas reproduits ici ; lisez-les sur les pages de leurs
auteurs :
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)
et [eduPerson](https://github.com/REFEDS/eduperson).

## Ce contre quoi elle est vérifiée {#what-it-is-checked-against}

**Le `ldapsearch` d'OpenLDAP**, en CI, et exigé là où il est installé : la
voie de test Linux, le détecteur de concurrence et la voie de couverture positionnent
`LDAP_REQUIRE_JUDGE=1`, si bien qu'un client absent fait échouer au lieu de sauter. Windows
n'en a pas et saute ces tests. `ldaptest`, le client réseau propre à ce module, n'est
délibérément pas le juge : il ne demande que ce que `ldapsearch` ne peut pas demander, sur l'état
d'une connexion — deux liaisons sur une même socket, une liaison SASL avec un mécanisme
arbitraire, StartTLS suivi de davantage de LDAP.

`FuzzMessage` fait passer chaque message qu'un client peut envoyer par la trame, les
décodeurs et l'aller-retour du filtre. Le plancher de couverture est de 99,7 %, avec les trois
lignes non atteintes nommées dans le workflow.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/ldap@v0.10.1](https://pkg.go.dev/github.com/go-authn/ldap@v0.10.1)
