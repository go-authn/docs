---
title: "saml — un proveedor de servicio ante una federación"
linkTitle: "saml"
weight: 100
description: "go-authn/saml es un proveedor de servicio SAML 2.0 para una federación de investigación como RENATER o eduGAIN: metadatos firmados, la AuthnRequest, y una aserción que se lee tras todas las comprobaciones."
tags: [bibliotecas, saml, federación]
---

**¿Qué ha dicho de esta persona su proveedor de identidad?** Un proveedor de
servicio SAML 2.0 para una federación de identidad como la Fédération
Éducation-Recherche de RENATER o eduGAIN: lee los metadatos firmados de la
federación, envía a las personas al proveedor de identidad de su propia
institución, y lee lo que ese proveedor responde.

```sh
go get github.com/go-authn/saml@v0.4.0
```

Es la mitad de [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) que da a
la federación, y puede usarla por sí sola cualquier cosa que quiera ser un SP
SAML. No incluye: un IdP, Single Logout, el binding de artefactos, AuthnRequests
firmadas, consultas de atributos, SAML 1.1.

| | |
|---|---|
| `Federation` | obtiene los metadatos, los verifica contra un certificado **fijado**, y los mantiene al día con `Run` |
| `ParseMetadata` | la misma verificación, para un documento que ya se tiene |
| `DiscoveryURL`, `Chosen` | envían a la persona a un servicio de descubrimiento, y leen el IdP que eligió |
| `SP.Request` | la AuthnRequest, por HTTP-Redirect, y el `Pending` que hay que conservar |
| `SP.Accept` | la `SAMLResponse` enviada por POST al ACS, leída en una `Assertion` |
| `Assertion.Subject` | `subject-id`, después `pairwise-id`, después `eduPersonPrincipalName`, después `eduPersonTargetedID`, después un NameID persistente — nunca el correo |
| `SP.Metadata` | los metadatos propios del SP, para registrarlos en la federación |

## Ejemplo {#example}

El descubrimiento y la solicitud, con un IdP descrito a mano:

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
		EntityID: "https://idp.univ-example.example/idp/shibboleth",
		SSO:      "https://idp.univ-example.example/idp/profile/SAML2/Redirect/SSO",
		Scopes:   []string{"univ-example.example"},
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
idp.univ-example.example true s1 https://idp.univ-example.example/idp/shibboleth [https://refeds.org/profile/mfa]
RelayState is limited to 80 bytes
```

En un servicio, los metadatos proceden de la federación y la respuesta llega al
ACS:

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

## Qué rechaza, y por qué {#what-it-refuses-and-why}

**Metadatos:**

| | por qué |
|---|---|
| no firmados por el certificado **fijado** | el certificado es un parámetro, nunca se obtiene junto con los metadatos: una clave que llega por el mismo canal que el documento no avala nada |
| pasado su `validUntil`, o sin él | un documento firmado que nunca caduca es un compromiso de clave que nunca termina. Una actualización fallida conserva la última copia válida, hasta que esa copia caduca |
| válidos durante más de 28 días a partir de ahora | `Federation.MaxValidity` cambia el límite; un valor negativo lo elimina |
| más antiguos que la copia en uso | una vuelta atrás: firmados válidamente, y quizá con una clave revocada desde entonces |
| obtenidos por `http://` desde cualquier sitio que no sea loopback | la firma detectaría un cambio, pero no un camino que retiene el documento nuevo |

El certificado de un IdP en los metadatos es de confianza porque la firma de la
federación lo nombra; sus fechas no se miran, ya que los certificados de IdP
suelen ser autofirmados y estar caducados.

**Las respuestas** se comprueban en `Accept`. Cada rechazo de abajo se devuelve a
quien llama como un error, destinado al registro del servidor:

| | por qué |
|---|---|
| nada firmado, o firmado con SHA-1 | saml-profiles 4.1.4.5: por POST la aserción debe estar firmada. Un IdP Shibboleth firma la Response por defecto; se acepta cualquiera de las dos |
| más de una aserción | así llegan juntas una firmada y otra sin firmar y se lee la que no es (CVE-2022-41912) |
| cualquier cosa fuera de lo que cubrió la firma | nunca se lee: solo se lee el elemento reconstruido a partir de los bytes que resumió la firma |
| un identificador con ámbito fuera de los `Scopes` del IdP | se descarta: de lo contrario cualquier IdP podría afirmar `alice@another-university.example` |
| texto cifrado AES-CBC que no cubre ninguna firma verificada | ni siquiera se descifra: CBC sin autenticar es un oráculo de relleno. El transporte de clave RSA PKCS#1 v1.5 no se acepta en absoluto; AES-GCM y RSA-OAEP sí |
| otra audiencia, otro ACS u otra solicitud; una respuesta no solicitada; una solicitud de más de una hora | saml-profiles 4.1.4.3 |
| una aserción ya usada | una aserción bearer es de quien la tenga |
| una condición que no entiende | saml-core 2.5.1: la aserción es entonces Indeterminate |
| una contraseña devuelta cuando se pidió MFA (`Options.AuthnContext`) | un IdP puede ignorar la solicitud |
| con `ForceAuthn`, un `AuthnInstant` anterior a la solicitud | el IdP reutilizó una sesión que se le pidió no reutilizar |

{{< callout type="warning" >}}
**La caché de reproducción por defecto es la memoria de un solo proceso**

`SP.Replay` es por defecto `NewMemoryReplay()`. Varias instancias detrás de un
balanceador de carga aceptarían cada una la misma aserción una vez, y un reinicio
la vacía. Implemente `Replay` sobre un almacenamiento compartido; su `Use` debe
ser atómico.
{{< /callout >}}

## Contra qué se comprueba {#what-it-is-checked-against}

- **Los propios metadatos de RENATER**, tal como RENATER los firmó el 2026-09-29,
  en `testdata/fer-idps.xml.gz`, con su certificado comprobado contra la huella
  SHA-256 que publica RENATER. Se leen los 343 IdP; reescribir el host de un
  `Location` se rechaza. Las vías de arquitectura, s390x incluida, verifican
  también esa firma.
- **xmlsec1** firma y cifra todas las respuestas del conjunto de pruebas, a partir
  de plantillas: GCM y CBC, RSA-OAEP con SHA-1 y con SHA-256, Response firmada,
  aserción firmada, ambas. La vía de pruebas de Linux, el detector de carreras y la
  vía de cobertura lo instalan y fijan `SAML_REQUIRE_JUDGE`.
- **El IdP de crewjam/saml** escribe respuestas completas a las AuthnRequests de
  este SP en un trabajo de CI aparte (`interop/crewjam`, un módulo propio, fuera
  del módulo publicado): se acepta RSA-SHA256 con AES-128-CBC y la Response
  firmada; su RSA-SHA1 por defecto se rechaza; la misma aserción CBC sin la firma
  de la Response se rechaza antes de descifrarla.

El umbral de la vía de cobertura es el 92 %.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/saml@v0.4.0](https://pkg.go.dev/github.com/go-authn/saml@v0.4.0)
