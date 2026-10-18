---
title: "krl — listes de révocation de clés OpenSSH"
linkTitle: "krl"
weight: 110
description: "go-authn/krl analyse, construit, fusionne et vérifie les KRL OpenSSH comme sshd les lit, avec une extension d'expiration, jugée par ssh-keygen."
tags: [bibliothèques, révocation, ssh]
---

**Ce certificat ou cette clé SSH est-il révoqué — comme sshd répondrait ?** Le format
binaire du `PROTOCOL.krl` d'OpenSSH, la liste que `sshd` charge par
`RevokedKeys` et qu'écrit `ssh-keygen -k`. `golang.org/x/crypto/ssh` ne le
prend pas en charge.

```sh
go get github.com/go-authn/krl@v0.6.1
```

`IsRevoked` suit `ssh_krl_check_key` dans le `krl.c` d'OpenSSH : un certificat
est révoqué quand son numéro de série ou son identifiant de clé est révoqué sous l'AC qui l'a signé ou
sous n'importe quelle AC, quand la clé de son AC est révoquée, ou quand sa propre clé est révoquée par
blob ou par empreinte SHA-1 ou SHA-256. Le numéro de série 0 — ce qu'écrit une AC quand elle
n'en indique aucun — n'est jamais révoqué par numéro de série.

## Exemple {#example}

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

La même liste et les mêmes certificats, écrits dans des fichiers, obtiennent les trois mêmes réponses
de `ssh-keygen -Q -f list.krl` d'OpenSSH 10.3p1 : `REVOKED`, `ok`,
`REVOKED`.

## Expiration : `expires@go-authn.github.io` {#expiry-expiresgo-authngithubio}

Une KRL a une date de génération et une version, et rien ne dit quand elle cesse
d'être en vigueur : une copie périmée ne peut donc pas être distinguée d'une copie à jour.
`Builder.SetExpires` écrit cette date dans une section d'extension nommée
`ExtensionExpires`, **non critique** : `sshd` et `ssh-keygen` chargent donc la liste
et l'ignorent ; `Parse` la lit dans `KRL.Expires`.

{{< callout type="warning" >}}
**Pas de signatures**

OpenSSH n'a jamais exposé de moyen d'écrire la section de signature d'une KRL et ne la
vérifie plus. `Parse` en saute une et positionne `Signed`, qui ne dit rien de
l'authenticité ; `Builder` n'en écrit jamais. L'intégrité de la liste, et donc celle de son
expiration, vient de son transport — HTTPS depuis un serveur authentifié — ou
d'une signature SSHSIG détachée vérifiée par l'appelant, ce que ce paquet
ne fait pas.
{{< /callout >}}

## Fusion : un seul fichier pour sshd {#merging-one-file-for-sshd}

`sshd` lisait un seul fichier `RevokedKeys` jusqu'à OpenSSH 10.3 : un serveur
qui fait confiance à plusieurs AC a donc besoin de leurs listes en une seule. `Builder.Merge` ajoute chaque
révocation d'une liste analysée. `Builder.MergeCA(k, ca, others...)` garde la
section de `k` pour `ca`, ses sections « toute AC » restreintes à `ca`, et ses clés
et empreintes explicites, et laisse de côté — en les comptant — les sections d'une autre AC et
les clés ou empreintes qui désignent l'une des `others`. `MergeCAWith` avec
`MergeOptions{DropKeys: true}` laisse aussi de côté toute clé explicite sauf
celle de `ca` elle-même, pour une liste à qui l'on ne confie pas les utilisateurs de toutes les AC : une clé d'utilisateur révoquée
exclut cet utilisateur sous toutes les AC du fichier fusionné, parce que `sshd` vérifie la
propre clé d'un certificat quel qu'en soit le signataire.

## Ce qu'il refuse, et pourquoi {#what-it-refuses-and-why}

`Parse` refuse ce que `ssh-keygen` et `sshd` refusent : un nombre magique ou une version de format
incorrects, des données tronquées ou en excédent, une section ou une sous-section de certificat
inconnue, une extension inconnue marquée critique, une clé d'AC qu'OpenSSH ne sait pas
analyser, le numéro de série 0, un intervalle de numéros de série inversé, un bitmap plus grand que ce qu'OpenSSH lit
ou qui dépasse 2^64−1. Il refuse aussi une expiration malformée ou répétée :
lue comme absente, elle transformerait une liste censée expirer en une liste qui n'expire jamais.

`Builder` refuse — au `Marshal`, qui renvoie la première demande invalide —
le numéro de série 0, un intervalle dont la borne basse vaut 0 ou dépasse sa borne haute, un identifiant de clé ou un
commentaire contenant un NUL, un certificat donné là où une clé d'AC est attendue, et
une expiration antérieure à la date de génération.

**Une différence délibérée.** Pour de nombreux numéros de série épars et proches,
`ssh-keygen -k` écrit un bitmap plus large que ce qu'accepte son propre lecteur, puis
refuse son propre fichier (*bignum is too large*). `Parse` refuse aussi ce fichier,
comme le ferait `sshd` ; `Builder` commence une nouvelle section avant qu'un bitmap n'atteigne cette
largeur, si bien que ce qu'il écrit est toujours lisible.

Parse alloue en proportion de ce que la liste révoque, comme OpenSSH : une KRL
doit venir d'une source à qui l'on fait confiance pour ne pas en envoyer une énorme.

## Ce contre quoi il est vérifié {#what-it-is-checked-against}

**Le `ssh-keygen` d'OpenSSH**, sur les voies Linux et macOS, où
`KRL_REQUIRE_SSHKEYGEN=1` fait de son absence un échec (Windows n'exécute que
les tests en Go pur) :

- une KRL écrite par `ssh-keygen -k` avec tous les encodages de numéros de série, des identifiants de clé, trois
  AC plus « toute AC », des clés explicites et une clé d'AC révoquée : `IsRevoked` répond
  comme `ssh-keygen -Q` pour 250 certificats, et `Builder`, à qui l'on donne les mêmes
  révocations, écrit **les mêmes octets** ;
- 40 ensembles aléatoires de numéros de série écrits par les deux : identiques à l'octet près, et les mêmes réponses
  pour environ 9000 certificats ;
- toutes les troncatures et environ 1400 corruptions d'un seul octet : `Parse` refuse
  exactement ce que `ssh-keygen` refuse ;
- l'extension d'expiration se charge dans `ssh-keygen`, et la même section marquée
  critique est refusée ;
- les listes fusionnées révoquent exactement ce que révoque l'une de leurs sources.

`FuzzParse`, amorcé avec des KRL écrites par `ssh-keygen`, et `FuzzBuilder` s'exécutent en CI.
Le plancher de couverture est de 100 %, mesuré sur la voie Linux où `ssh-keygen` est
présent.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/krl@v0.6.1](https://pkg.go.dev/github.com/go-authn/krl@v0.6.1)
