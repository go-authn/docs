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
go get github.com/go-authn/ldap@v0.8.0
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

[pkg.go.dev/github.com/go-authn/ldap@v0.8.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.8.0)
