---
title: "oidc — verificar un token bearer"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc verifica un token de OpenID Connect y lo convierte en una identidad: descubrimiento, el conjunto de claves, una lista de algoritmos permitidos y los rechazos que importan. Sin dependencias."
tags: [libraries, oidc, tokens]
---

**¿Quién dice este token bearer que está preguntando, y hay que creerlo?** El
descubrimiento, el conjunto de claves y las comprobaciones que debe hacer un servidor
de recursos, en Go puro, **sin dependencias** fuera de la biblioteca estándar.

```sh
go get github.com/go-authn/oidc@v0.4.0
```

Aquí no hay flujo de inicio de sesión: ni redirección, ni intercambio de código, ni
secreto de cliente, ni cookies. Esta es la mitad del **servidor de recursos**: algo
llega con un token, y esto dice quién es.

## Ejemplo {#example}

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/go-authn/oidc"
)

func main() {
	// Discovery happens here, at startup: an issuer that does not answer is
	// a server that cannot authenticate anybody.
	v, err := oidc.New(context.Background(), oidc.Config{
		Issuer:   "https://login.example.org",
		Audience: "fileshare",
		Type:     "at+jwt", // a resource server takes access tokens, not ID tokens
	})
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		tok, err := v.Verify(r.Context(), raw)
		if err != nil {
			log.Print(err) // which check refused it: for this log only
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		fmt.Fprintln(w, tok.Subject(), tok.Username(), tok.Groups())
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

Un `Verifier` se puede usar de forma concurrente y guarda el conjunto de claves: cree
uno al arrancar y consérvelo. El error de `Verify` dice qué comprobación rechazó el
token, para el registro del servidor; el cliente recibe un único rechazo, sea cual sea
la comprobación.

Tres configuraciones que `New` rechaza antes de descargar nada:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/oidc"
)

func main() {
	ctx := context.Background()
	for _, cfg := range []oidc.Config{
		{Issuer: "http://login.example.org", Audience: "fileshare"},
		{Issuer: "https://login.example.org"},
		{Audience: "fileshare"},
	} {
		_, err := oidc.New(ctx, cfg)
		fmt.Println(err)
	}
}
```

```
oidc: http://login.example.org is not https: the key set decides every signature, and over cleartext so does anybody on the way
oidc: no audience: a token minted for another service is a valid token, and a verifier that does not check accepts every one the issuer ever signed
oidc: no issuer: a verifier without one accepts tokens from anybody
```

El resto de `Config` es opcional: `JWKSURL` omite el descubrimiento; `UsernameClaim`
y `GroupsClaim` (por defecto `groups`) nombran los claims; `ClockSkew` y `MinRefresh`
valen por defecto un minuto; `Client` es el cliente HTTP, para un proxy, una CA
privada o un tiempo de espera. Un `Token` lee `Subject`, `Issuer`, `Audience`,
`Email`, `EmailVerified`, `Username`, `Groups`, `Expiry`, `NotBefore` e `IssuedAt`;
`Claim(name, &v)` decodifica cualquier otro claim, y `Has(name)` dice si está
presente.

## Lo que acepta {#what-it-accepts}

Diez algoritmos de firma, como **lista de permitidos**: `RS256` `RS384` `RS512`,
`PS256` `PS384` `PS512`, `ES256` `ES384` `ES512`, y `EdDSA` (Ed25519). Un token cuyo
`alg` no es uno de estos se rechaza antes de descargar ninguna clave. `alg: none` y la
familia HMAC se rechazan por no estar en la lista, y la clave debe ser de la clase del
algoritmo: un token que declara `RS256` se comprueba con una clave RSA o se rechaza.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

| | por qué |
|---|---|
| `alg: none` | un token que dice que no está firmado es un objeto JSON que alguien tecleó |
| HMAC frente a una clave pública | `HS256` usa un secreto compartido, y la clave del emisor es pública: cualquiera podría acuñar un token |
| un emisor que simplemente **empieza por** el correcto | `iss` se compara entero: `https://login.example.org.evil.test` empieza por la cadena correcta |
| una **audiencia** ausente o errónea | un token acuñado para otro servicio es válido; no va dirigido a este |
| un token **sin caducidad** | es una contraseña que alguien puede copiar una vez |
| un emisor, un conjunto de claves o una redirección **por HTTP sin cifrar**, salvo hacia loopback | el conjunto de claves decide cada firma |
| una clave RSA de menos de 2048 bits, o con `n` o `e` que no están en su forma más corta; un punto EC que no está en su curva | las firmas de una clave corta se pueden falsificar; antes de la v0.2.2, un módulo de 1024 bits rellenado con bytes a cero pasaba por 2048 bits |
| una clave publicada con un `use` distinto de `sig` | un conjunto de claves contiene legítimamente también claves de cifrado |
| con `Type` fijado, un token de otro `typ`; sin fijarlo, un `typ` distinto de `JWT` o `at+jwt` (un token sin cabecera `typ` pasa) | RFC 9068 §4: un servidor de recursos comprueba `typ: at+jwt`, o toma un token de ID por un token de acceso siempre que las audiencias coincidan |
| una parte que no está en base64url canónico | un token se verifica como una sola cadena |

En ECDSA, `s` y `n − s` verifican ambos, como permite el algoritmo. Así que una lista
de denegación o una caché contra repeticiones se indexa por `jti` o `sub`, nunca por
el token tal como se envió.

**Las claves rotan, y una clave desconocida no es una forma de acribillar al emisor.**
Una firma que nada de lo que se tiene puede verificar vale una nueva descarga del
conjunto de claves por `MinRefresh`, tanto si el `kid` es nuevo como si el mismo `kid`
lleva una clave nueva. Los tokens que necesitan el conjunto de claves mientras hay una
descarga en curso la esperan, y una descarga que falla cuenta igualmente.

**Qué nombre da `Username()`.** Por defecto `preferred_username`, después `email`
**solo cuando `email_verified` es verdadero**, después `sub`. Un email no verificado
es una cadena que tecleó la persona (OIDC Core §5.1). Un `UsernameClaim` configurado
se lee tal como se nombra, sin alternativa.

## Contra qué se comprueba {#what-it-is-checked-against}

**pyjwt** firma todos los tokens del conjunto de pruebas, de modo que el verificador
nunca lo juzga un firmante salido de las mismas manos. El token de confusión HMAC se
falsifica a mano, porque pyjwt se niega a producirlo. `testdata/fixed.json` —tokens
que pyjwt firmó una vez con una clave fija— permite a las vías de arquitectura,
s390x incluida, verificar firmas reales con el reloj fijado. La vía de pruebas de
Linux, el detector de carreras y la vía de cobertura instalan pyjwt y fijan
`OIDC_REQUIRE_JUDGE`, así que un pyjwt ausente hace fallar en lugar de omitir. Aceptar
HMAC, comparar el emisor por prefijo y omitir la comprobación de audiencia se probaron
cada uno a propósito, y cada uno pone una prueba en rojo. El umbral de la vía de
cobertura es del 90 %.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/oidc@v0.4.0](https://pkg.go.dev/github.com/go-authn/oidc@v0.4.0)
