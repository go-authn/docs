---
title: "saml – ein Service Provider vor einer Föderation"
linkTitle: "saml"
weight: 100
description: "go-authn/saml ist ein SAML-2.0-Service-Provider für eine Forschungsföderation wie RENATER oder eduGAIN: signierte Metadaten, der AuthnRequest und eine Assertion, die erst nach jeder Prüfung gelesen wird."
tags: [libraries, saml, federation]
---

**Was hat der Identitätsanbieter dieser Person über sie gesagt?** Ein SAML-2.0-Service-Provider
für eine Identitätsföderation wie RENATERs Fédération
Éducation-Recherche oder eduGAIN: Er liest die signierten Metadaten der Föderation,
schickt Personen zum Identitätsanbieter ihrer eigenen Einrichtung und liest zurück, was
dieser Anbieter sagt.

```sh
go get github.com/go-authn/saml@v0.4.0
```

Er ist die Hälfte von [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}),
die der Föderation zugewandt ist, und für sich allein von allem nutzbar, was
ein SAML-SP sein will. Nicht enthalten: ein IdP, Single Logout, das Artifact-Binding, signierte
AuthnRequests, Attributabfragen, SAML 1.1.

| | |
|---|---|
| `Federation` | ruft die Metadaten ab, prüft sie gegen ein **festgelegtes** Zertifikat und hält sie mit `Run` aktuell |
| `ParseMetadata` | dieselbe Prüfung, für ein bereits vorliegendes Dokument |
| `DiscoveryURL`, `Chosen` | schicken die Person zu einem Discovery-Dienst und lesen den IdP zurück, den er gewählt hat |
| `SP.Request` | der AuthnRequest, über HTTP-Redirect, und das aufzubewahrende `Pending` |
| `SP.Accept` | die an den ACS gesendete `SAMLResponse`, eingelesen in eine `Assertion` |
| `Assertion.Subject` | `subject-id`, dann `pairwise-id`, dann `eduPersonPrincipalName`, dann `eduPersonTargetedID`, dann eine persistente NameID – nie die E-Mail-Adresse |
| `SP.Metadata` | die eigenen Metadaten des SP, zur Registrierung bei der Föderation |

## Beispiel {#example}

Discovery und die Anfrage, mit einem von Hand beschriebenen IdP:

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

In einem Dienst kommen die Metadaten von der Föderation, und die Antwort trifft
am ACS ein:

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

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Metadaten:**

| | warum |
|---|---|
| nicht vom **festgelegten** Zertifikat signiert | das Zertifikat ist ein Parameter und wird nie zusammen mit den Metadaten abgerufen: Ein Schlüssel, der über denselben Kanal ankommt wie das Dokument, bürgt für nichts |
| nach ihrem `validUntil` oder ohne eines | ein signiertes Dokument, das nie abläuft, ist eine Schlüsselkompromittierung, die nie endet. Ein fehlgeschlagenes Auffrischen behält die letzte gute Kopie, bis diese Kopie abläuft |
| ab jetzt länger als 28 Tage gültig | `Federation.MaxValidity` ändert die Grenze; ein negativer Wert hebt sie auf |
| älter als die verwendete Kopie | ein Rollback: gültig signiert und möglicherweise mit einem inzwischen widerrufenen Schlüssel |
| über `http://` abgerufen, von irgendwoher außer Loopback | die Signatur würde eine Änderung bemerken, aber keinen Pfad, der das neue Dokument zurückhält |

Dem Zertifikat eines IdP in den Metadaten wird vertraut, weil die Signatur der Föderation
es benennt; seine Daten werden nicht angesehen, da IdP-Zertifikate oft
selbstsigniert und abgelaufen sind.

**Antworten** werden bei `Accept` geprüft. Jede der folgenden Ablehnungen geht als Fehler an
den Aufrufer, für das Log des Servers:

| | warum |
|---|---|
| nichts signiert oder mit SHA-1 signiert | saml-profiles 4.1.4.5: Über POST muss die Assertion signiert sein. Ein Shibboleth-IdP signiert standardmäßig die Response; beides wird akzeptiert |
| mehr als eine Assertion | so kommen eine signierte und eine unsignierte zusammen an, und die falsche wird gelesen (CVE-2022-41912) |
| alles außerhalb dessen, was die Signatur abgedeckt hat | es wird nie gelesen: gelesen wird nur das Element, das aus den von der Signatur gehashten Bytes neu aufgebaut wird |
| ein bereichsgebundener Bezeichner außerhalb der `Scopes` des IdP | verworfen: Sonst könnte jeder IdP `alice@another-university.fr` behaupten |
| AES-CBC-Chiffretext, den keine geprüfte Signatur abdeckt | nicht einmal entschlüsselt: Nicht authentifiziertes CBC ist ein Padding-Orakel. RSA-PKCS#1-v1.5-Schlüsseltransport wird überhaupt nicht akzeptiert; AES-GCM und RSA-OAEP schon |
| eine andere Audience, ein anderer ACS oder eine andere Anfrage; eine unaufgeforderte Antwort; eine Anfrage, die älter als eine Stunde ist | saml-profiles 4.1.4.3 |
| eine bereits verwendete Assertion | eine Bearer-Assertion ist, wer auch immer sie hält |
| eine Bedingung, die es nicht versteht | saml-core 2.5.1: Die Assertion ist dann Indeterminate |
| ein Passwort, zurückgegeben, als MFA verlangt wurde (`Options.AuthnContext`) | ein IdP kann die Anforderung ignorieren |
| mit `ForceAuthn` ein `AuthnInstant` von vor der Anfrage | der IdP hat eine Sitzung wiederverwendet, obwohl er gebeten wurde, es nicht zu tun |

{{< callout type="warning" >}}
**Der Standard-Replay-Cache ist der Speicher eines einzigen Prozesses**

`SP.Replay` ist standardmäßig `NewMemoryReplay()`. Mehrere Instanzen hinter einem Load
Balancer würden dieselbe Assertion jeweils einmal akzeptieren, und ein Neustart leert
ihn. Implementieren Sie `Replay` über gemeinsamen Speicher; sein `Use` muss atomar sein.
{{< /callout >}}

## Wogegen es geprüft wird {#what-it-is-checked-against}

- **RENATERs eigene Metadaten**, so wie RENATER sie am 2026-09-29 signiert hat, in
  `testdata/fer-idps.xml.gz`, wobei ihr Zertifikat gegen den
  SHA-256-Fingerabdruck geprüft wird, den RENATER veröffentlicht. Alle 343 IdPs werden gelesen; das Umschreiben des
  Hosts einer `Location` wird abgelehnt. Die Architektur-Lanes, s390x eingeschlossen,
  prüfen diese Signatur ebenfalls.
- **xmlsec1** signiert und verschlüsselt jede Antwort in der Suite, aus Vorlagen:
  GCM und CBC, RSA-OAEP mit SHA-1 und mit SHA-256, Response signiert,
  Assertion signiert, beides. Die Linux-Test-Lane, der Race Detector und die
  Coverage-Lane installieren es und setzen `SAML_REQUIRE_JUDGE`.
- **Der IdP von crewjam/saml** schreibt vollständige Antworten auf die AuthnRequests dieses SP in einem
  separaten CI-Job (`interop/crewjam`, ein eigenes Modul, nicht im veröffentlichten
  Modul): RSA-SHA256 mit AES-128-CBC und signierter Response wird akzeptiert; sein
  Standard RSA-SHA1 wird abgelehnt; dieselbe CBC-Assertion, deren Response-Signatur
  entfernt wurde, wird vor der Entschlüsselung abgelehnt.

Die Untergrenze der Coverage-Lane liegt bei 92 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/saml@v0.4.0](https://pkg.go.dev/github.com/go-authn/saml@v0.4.0)
