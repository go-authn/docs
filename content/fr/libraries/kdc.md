---
title: "kdc — délivrer des tickets Kerberos à partir d'un annuaire"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc est la moitié de Kerberos qui délivre : AS et TGS sur UDP et TCP, pré-authentification exigée, un seul type de chiffrement, des personnes issues d'un annuaire go-authn."
tags: [bibliothèques, kerberos, annuaire]
---

**Comment un royaume délivre-t-il des tickets à partir d'un annuaire ?** AS-REQ et TGS-REQ, sur
UDP et TCP, avec la pré-authentification par horodatage chiffré exigée, pour les
personnes qu'un [annuaire]({{< relref "/libraries/directory.md" >}}) connaît et les
services qu'un keytab détient. Il fonctionne sous
[authnd]({{< relref "/authnd/_index.md" >}}).

```sh
go get github.com/go-authn/kdc@v0.4.2
```

En v0.4.2, son `go.mod` requiert au moins `go-authn/directory` v0.11.1 et
gokrb5 v8.4.4 : des minimums, si bien qu'un programme qui requiert directory v0.14.0, la
version que décrivent ces pages, est compilé avec la v0.14.0, comme authnd v0.11.0. La
moitié qui accepte est [krb5]({{< relref "/libraries/krb5.md" >}}), et un service
qui ne fait que vérifier des tickets n'a nullement besoin de ce module.

Non implémentés : les renvois inter-royaumes, PKINIT, FAST, les tickets renouvelables ou
postdatés, et tout protocole kadmin. Les clés viennent de l'annuaire et d'un
keytab, et se changent là où elles résident.

## Seule une source qui détient le mot de passe peut adosser un royaume {#only-a-source-holding-the-password-can-back-a-realm}

Un KDC doit **déchiffrer** la pré-authentification du client avec la clé à long terme
de cette personne, donc un `directory.Verifier` — une liaison contre le LDAP de quelqu'un
d'autre, une comparaison d'empreintes — ne peut pas servir, si bien qu'il réponde à *est-ce le
bon mot de passe*. Une personne dont la source ne détient aucun mot de passe reçoit
`KDC_ERR_NULL_KEY` (*null key*), jamais le code qu'obtient un mauvais mot de passe, si bien que cela
se lit comme une configuration à corriger plutôt que comme un mot de passe à retaper.

## Exemple {#example}

Un royaume en mémoire, sur l'interface de bouclage :

```go
package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/go-authn/directory"
	"github.com/go-authn/kdc"
	"github.com/jcmturner/gokrb5/v8/iana/etypeID"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

func main() {
	// People: a source that holds PASSWORDS. A verifier cannot back a realm.
	people := &directory.Static{Name: "the configuration file", People: []*directory.Identity{
		directory.NewIdentity("alice", directory.WithPassword("correct horse battery staple")),
	}}

	// Services: the realm's own krbtgt key, and one per service.
	kt := keytab.New()
	for _, p := range []string{"krbtgt/EXAMPLE.ORG", "nfs/files.example.org"} {
		if err := kt.AddEntry(p, "EXAMPLE.ORG", rand.Text(), time.Now(), 1, etypeID.AES256_CTS_HMAC_SHA1_96); err != nil {
			log.Fatal(err)
		}
	}

	// A keytab without krbtgt/REALM is refused before anything listens.
	_, err := kdc.New(kdc.Config{Realm: "OTHER.ORG", People: people, Services: kt})
	fmt.Println(err)

	srv, err := kdc.New(kdc.Config{
		Realm:    "EXAMPLE.ORG",
		People:   people,
		Services: kt,
		Logf:     log.Printf, // why each request was refused; never a key
	})
	if err != nil {
		log.Fatal(err)
	}
	pc, err := net.ListenPacket("udp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	go srv.ServeTCP(ln)
	fmt.Println("EXAMPLE.ORG answers on", pc.LocalAddr())
	log.Fatal(srv.ServeUDP(pc))
}
```

Avec un `krb5.conf` indiquant `kdc = tcp/127.0.0.1:18088` pour `EXAMPLE.ORG`, le
`kinit` de Heimdal que livre macOS (1.5.1) obtient un ticket d'octroi de tickets, avec
`KRB5_CONFIG=krb5.conf` et `KRB5CCNAME=FILE:cc` :

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:54:46 2026  Oct 11 07:54:46 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:54:46 2026  Oct 11 07:54:46 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 10 21:54:47 2026  Oct 11 07:54:46 2026  nfs/files.example.org@EXAMPLE.ORG
```

Les dix heures sont la valeur par défaut de `Config.Lifetime`, et le ticket de service se termine avec
le ticket d'octroi de tickets avec lequel il a été obtenu. Le KDC a dit pourquoi il refusait chaque
requête, dans son propre journal :

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/10 21:54:46 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/10 21:54:47 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

Le premier refus de chaque échange, c'est le protocole qui fonctionne : le `KRB-ERROR`
qui exige la pré-authentification porte un indice `ETYPE-INFO2` nommant
l'etype et le sel, et le client réessaie avec un horodatage.

{{< callout type="info" >}}
**Avant la v0.4.2, un `till` de 19700101000000Z obtenait un ticket déjà expiré**

RFC 4120 §5.4.1 : un `till` de 19700101000000Z demande l'heure de fin maximale
que la politique du KDC autorise. Le `kgetcred` de Heimdal envoie exactement cela. La v0.4.1
ne testait que l'heure zéro de Go, donc elle prenait l'époque Unix pour une vraie fin et
délivrait un ticket de service que `klist` affichait comme `>>>Expired<<<` ; le `kvno` du MIT,
le juge de la CI, envoie un vrai `till` et n'a jamais rencontré le cas. La v0.4.2 délivre le
ticket le plus long autorisé, comme ci-dessus, et répond à un `till` déjà passé
par `KDC_ERR_NEVER_VALID` au lieu d'un ticket expiré à l'arrivée
([go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19)).
{{< /callout >}}

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

**À la configuration** (`New`) : pas de royaume (`ErrNoRealm`), pas d'annuaire
(`ErrNoPeople`), pas de keytab (`ErrNoServices`), ou un keytab sans
`krbtgt/REALM@REALM` (`ErrNoTGTKey`) — plutôt que de démarrer et d'échouer au
premier `kinit`, où l'erreur atteint une personne qui ne peut pas la corriger.

**À l'AS :** une requête sans pré-authentification reçoit en réponse
l'exigence de celle-ci, et la clé de la personne n'est pas dérivée tant qu'il n'y a pas d'horodatage
à vérifier, si bien qu'un paquet UDP usurpé nommant un vrai principal ne coûte aucune
dérivation de clé. Un mauvais mot de passe, un horodatage sous un autre etype et un horodatage d'il y a
une heure reçoivent tous `KDC_ERR_PREAUTH_FAILED`, le code qu'obtient un mauvais mot de passe ;
le texte de l'erreur nomme la raison, et `Logf` aussi. Un service qui demande son propre TGT est refusé : les services
s'authentifient à partir d'un keytab.

**Un seul type de chiffrement.** Les tickets et les clés sont en `aes256-cts-hmac-sha1-96`
(etype 18) uniquement. Une requête dont la liste d'etypes ne contient pas 18 reçoit
`KDC_ERR_ETYPE_NOSUPP` avant que quiconque soit recherché. Avec `Logf` positionné, le journal
consigne les deux etypes, si bien que l'on peut distinguer un chiffrement discordant d'un
mot de passe mal tapé.

**Au TGS** (RFC 4120 §3.3.2), un ticket n'est délivré que lorsque :

- le ticket présenté est un TGT de ce royaume, déchiffré sous la
  clé `krbtgt/REALM` que le KDC nomme — pas sous la clé du service, quel qu'il soit, que le
  ticket revendique (`KRB_AP_ERR_NOT_US`) ;
- l'authentificateur se déchiffre sous sa clé de session, dans la limite de `MaxSkew` ;
- sa somme de contrôle porte sur le corps de cette requête, tel que les octets sont arrivés, avec pour clé
  la clé de session (`KRB_AP_ERR_INAPP_CKSUM` si elle est absente ou sans clé,
  `KRB_AP_ERR_MODIFIED` si elle est fausse) ;
- le TGT n'a pas dépassé sa fin (`KRB_AP_ERR_TKT_EXPIRED`), n'est pas avant son début
  et n'est pas marqué invalide (`KRB_AP_ERR_TKT_NYV`), sans aucune dérive d'horloge tolérée : c'est
  l'horloge de ce KDC qui a écrit ces heures ;
- le client est de ce royaume et toujours dans l'annuaire
  (`KDC_ERR_C_PRINCIPAL_UNKNOWN`).

**Durées de vie.** `Config.Lifetime` plafonne un ticket, dix heures quand elle vaut zéro ; un client
qui demande moins obtient moins, et un ticket obtenu avec un TGT ne se termine pas plus tard que
ce TGT, si bien que redemander `krbtgt` ne peut pas prolonger un identifiant.

**Ce qu'un pair non authentifié peut retenir :** un message TCP, sa longueur comprise,
doit arriver en 30 secondes ; au plus 256 connexions TCP sont servies à la fois,
et au plus 64 datagrammes reçoivent une réponse à la fois — un de plus est abandonné, et le
client renvoie ou se rabat sur TCP.

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

**Les propres `kinit` et `kvno` du MIT**, via pkgx, contre un royaume construit en Go —
aucun KDC du MIT n'intervient, seul le client est emprunté.
`TestMITClientGetsATGTAndAServiceTicket` obtient un TGT et un ticket de service et
vérifie la version de clé que `kvno` rapporte. La voie de test Linux, le détecteur de concurrence
et la voie de couverture positionnent `KDC_REQUIRE_JUDGE=1`, et une étape supplémentaire échoue
à moins que le journal ne dise *were served by this realm*. Les tests épinglent aussi les
refus qu'un vrai client ne déclenche jamais : un horodatage sous la mauvaise clé, un horodatage
d'il y a une heure, un chiffré de trois octets, un service demandé directement par un
AS-REQ, un ticket de service forgé au TGS, et un royaume adossé à un vérificateur.
Le plancher de la voie de couverture est de 80 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/kdc@v0.4.2](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.2)
