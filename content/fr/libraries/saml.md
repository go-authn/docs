---
title: "saml — un fournisseur de service devant une fédération"
linkTitle: "saml"
weight: 100
description: "go-authn/saml est un fournisseur de service SAML 2.0 pour une fédération de recherche comme RENATER ou eduGAIN : métadonnées signées, l'AuthnRequest, et une assertion lue après chaque vérification."
tags: [bibliothèques, saml, fédération]
---

**Qu'a dit le fournisseur d'identité de cette personne à son sujet ?** Un
fournisseur de service SAML 2.0 pour une fédération d'identités comme la
Fédération Éducation-Recherche de RENATER ou eduGAIN : il lit les métadonnées
signées de la fédération, envoie les personnes vers le fournisseur d'identité
de leur propre établissement, et relit ce que ce fournisseur affirme.

```sh
go get github.com/go-authn/saml@v0.4.0
```

C'est la moitié d'[authn-bridge]({{< relref "/authn-bridge/_index.md" >}})
tournée vers la fédération, et utilisable seule par tout ce qui veut être
un SP SAML. Pas ici : un IdP, le Single Logout, le binding artifact, les
AuthnRequests signées, les requêtes d'attributs, SAML 1.1.

| | |
|---|---|
| `Federation` | récupère les métadonnées, les vérifie contre un certificat **épinglé**, et les maintient à jour avec `Run` |
| `ParseMetadata` | la même vérification, pour un document déjà en main |
| `DiscoveryURL`, `Chosen` | envoient la personne vers un service de découverte, et relisent l'IdP qu'elle a choisi |
| `SP.Request` | l'AuthnRequest, en HTTP-Redirect, et le `Pending` à conserver |
| `SP.Accept` | le `SAMLResponse` posté à l'ACS, lu dans une `Assertion` |
| `Assertion.Subject` | `subject-id`, puis `pairwise-id`, puis `eduPersonPrincipalName`, puis `eduPersonTargetedID`, puis un NameID persistant — jamais l'adresse mail |
| `SP.Metadata` | les métadonnées propres du SP, à enregistrer auprès de la fédération |

## Exemple {#example}

La découverte et la requête, avec un IdP décrit à la main :

```go
package main

import (
	"fmt"
	"net/url"

	"github.com/go-authn/saml"
)

func main() {
	// One IdP, as a federation's metadata would describe it.
	idp := &saml.IdP{
		EntityID: "https://idp.univ-example.fr/idp/shibboleth",
		SSO:      "https://idp.univ-example.fr/idp/profile/SAML2/Redirect/SSO",
		Scopes:   []string{"univ-example.fr"},
	}
	md := &saml.Metadata{IdPs: map[string]*saml.IdP{idp.EntityID: idp}}

	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Federation: md,
	}

	// Send the person to the discovery service, then read back what it chose.
	d, _ := saml.DiscoveryURL("https://discovery.renater.fr/renater", sp.EntityID, "https://app.example.org/saml/chosen")
	fmt.Println(d)

	_, err := saml.Chosen(url.Values{"entityID": {"https://idp.attacker.example/idp"}}, md)
	fmt.Println(err)
	chosen, _ := saml.Chosen(url.Values{"entityID": {idp.EntityID}}, md)

	// The AuthnRequest, over HTTP-Redirect. Keep p, keyed by the RelayState,
	// and hand it to sp.Accept at the ACS.
	to, p, err := sp.Request(chosen, "s1", saml.Options{AuthnContext: []string{"https://refeds.org/profile/mfa"}})
	if err != nil {
		panic(err)
	}
	u, _ := url.Parse(to)
	fmt.Println(u.Host, u.Query().Has("SAMLRequest"), u.Query().Get("RelayState"), p.IdP, p.AuthnContext)

	// RelayState is limited to 80 bytes, and refused beyond that.
	_, _, err = sp.Request(chosen, string(make([]byte, 81)), saml.Options{})
	fmt.Println(err)
}
```

```
https://discovery.renater.fr/renater?entityID=https%3A%2F%2Fapp.example.org%2Fsaml&return=https%3A%2F%2Fapp.example.org%2Fsaml%2Fchosen&returnIDParam=entityID
the chosen identity provider is not in the federation
idp.univ-example.fr true s1 https://idp.univ-example.fr/idp/shibboleth [https://refeds.org/profile/mfa]
RelayState is limited to 80 bytes
```

Dans un service, les métadonnées viennent de la fédération et la réponse arrive
à l'ACS :

```go
package main

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"log"
	"net/http"
	"os"

	"github.com/go-authn/saml"
)

func main() {
	ctx := context.Background()

	// The federation's metadata signing certificate, downloaded ONCE and
	// checked against the fingerprint the federation publishes.
	fed := &saml.Federation{
		URL:  "https://pub.federation.renater.fr/metadata/fer/idps.xml",
		Cert: readCert("/etc/app/metadata-signature-2026.pem"),
	}
	if err := fed.Refresh(ctx); err != nil {
		log.Fatal(err)
	}
	go fed.Run(ctx, func(err error) { log.Print(err) })

	pair, err := tls.LoadX509KeyPair("/etc/app/saml.crt", "/etc/app/saml.key")
	if err != nil {
		log.Fatal(err)
	}
	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Key:        pair.PrivateKey.(*rsa.PrivateKey), // assertions arrive encrypted to it
		Cert:       pair.Leaf,
		Federation: fed,
	}

	http.HandleFunc("/saml/acs", func(w http.ResponseWriter, r *http.Request) {
		p := pendingFor(r.PostFormValue("RelayState")) // what Request returned, from the session
		a, err := sp.Accept(r.PostFormValue("SAMLResponse"), p)
		if err != nil {
			log.Print(err) // for the log, not for the browser
			http.Error(w, "refused", http.StatusForbidden)
			return
		}
		id, from := a.Subject()
		log.Printf("%s (%s) from %s", id, from, a.IdP.EntityID)
	})
	log.Fatal(http.ListenAndServeTLS(":443", "/etc/app/tls.crt", "/etc/app/tls.key", nil))
}

func readCert(path string) *x509.Certificate {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		log.Fatal("no PEM block in ", path)
	}
	c, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		log.Fatal(err)
	}
	return c
}

// pendingFor is the caller's session store.
func pendingFor(relayState string) saml.Pending { return saml.Pending{} }
```

## Ce qu'elle refuse, et pourquoi {#what-it-refuses-and-why}

**Métadonnées :**

| | pourquoi |
|---|---|
| non signées par le certificat **épinglé** | le certificat est un paramètre, jamais récupéré avec les métadonnées : une clé qui arrive par le même canal que le document ne se porte garante de rien |
| au-delà de leur `validUntil`, ou sans `validUntil` | un document signé qui n'expire jamais est une compromission de clé qui ne finit jamais. Un rafraîchissement échoué conserve la dernière bonne copie, jusqu'à ce que cette copie expire |
| valides pour plus de 28 jours à partir de maintenant | `Federation.MaxValidity` change la borne ; une valeur négative la supprime |
| plus anciennes que la copie en usage | un retour en arrière : signé valablement, et portant peut-être une clé révoquée depuis |
| récupérées en `http://` depuis autre chose que la boucle locale | la signature détecterait une modification, mais pas un chemin qui retient le nouveau document |

Le certificat d'un IdP dans les métadonnées est digne de confiance parce que la
signature de la fédération le nomme ; ses dates ne sont pas examinées, puisque
les certificats d'IdP sont souvent autosignés et expirés.

**Les réponses** sont vérifiées à `Accept`. Chaque refus ci-dessous est renvoyé à
l'appelant sous forme d'erreur, destinée au journal du serveur :

| | pourquoi |
|---|---|
| rien de signé, ou signé avec SHA-1 | saml-profiles 4.1.4.5 : en POST, l'assertion doit être signée. Un IdP Shibboleth signe la Response par défaut ; l'une ou l'autre est acceptée |
| plus d'une assertion | c'est ainsi qu'une assertion signée et une non signée arrivent ensemble et que la mauvaise est lue (CVE-2022-41912) |
| tout ce que la signature ne couvrait pas | ce n'est jamais lu : seul l'est l'élément reconstruit à partir des octets que la signature a condensés |
| un identifiant à portée hors des `Scopes` de l'IdP | écarté : sinon n'importe quel IdP pourrait affirmer `alice@another-university.fr` |
| un chiffré AES-CBC qu'aucune signature vérifiée ne couvre | pas même déchiffré : CBC non authentifié est un oracle de remplissage. Le transport de clé RSA PKCS#1 v1.5 n'est pas accepté du tout ; AES-GCM et RSA-OAEP le sont |
| une autre audience, un autre ACS ou une autre requête ; une réponse non sollicitée ; une requête vieille de plus d'une heure | saml-profiles 4.1.4.3 |
| une assertion déjà utilisée | une assertion porteuse appartient à qui la détient |
| une condition qu'elle ne comprend pas | saml-core 2.5.1 : l'assertion est alors Indeterminate |
| un mot de passe renvoyé quand la MFA était demandée (`Options.AuthnContext`) | un IdP peut ignorer la demande |
| avec `ForceAuthn`, un `AuthnInstant` antérieur à la requête | l'IdP a réutilisé une session alors qu'on lui demandait de ne pas le faire |

{{< callout type="warning" >}}
**Le cache anti-rejeu par défaut est la mémoire d'un seul processus**

`SP.Replay` vaut par défaut `NewMemoryReplay()`. Plusieurs instances derrière un
répartiteur de charge accepteraient chacune la même assertion une fois, et un
redémarrage le vide. Implémentez `Replay` sur un stockage partagé ; son `Use` doit être atomique.
{{< /callout >}}

## Contre quoi elle est vérifiée {#what-it-is-checked-against}

- **Les métadonnées de RENATER elles-mêmes**, telles que RENATER les a signées
  le 2026-09-29, dans `testdata/fer-idps.xml.gz`, avec leur certificat vérifié
  contre l'empreinte SHA-256 que RENATER publie. Les 343 IdP sont tous lus ;
  réécrire l'hôte d'un `Location` est refusé. Les voies d'architecture, s390x
  comprise, vérifient aussi cette signature.
- **xmlsec1** signe et chiffre chaque réponse de la suite, à partir de gabarits :
  GCM et CBC, RSA-OAEP avec SHA-1 et avec SHA-256, Response signée,
  assertion signée, les deux. La voie de test Linux, le détecteur de concurrence et
  la voie de couverture l'installent et positionnent `SAML_REQUIRE_JUDGE`.
- **L'IdP de crewjam/saml** écrit des réponses complètes aux AuthnRequests de ce
  SP dans une tâche de CI séparée (`interop/crewjam`, un module à part, absent du
  module publié) : RSA-SHA256 avec AES-128-CBC et la Response signée est accepté ;
  son RSA-SHA1 par défaut est refusé ; la même assertion CBC dont la signature de
  la Response a été retirée est refusée avant déchiffrement.

Le plancher de la voie de couverture est de 92 %.

## Référence {#reference}

[pkg.go.dev/github.com/go-authn/saml@v0.4.0](https://pkg.go.dev/github.com/go-authn/saml@v0.4.0)
