---
title: "wireguard — ¿de quién es esta clave, y puede conectarse?"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard define estrictamente una clave pública de WireGuard y transporta la lista, firmada por el proveedor, de las claves registradas que un gateway convierte en peers."
tags: [bibliotecas, wireguard, tokens]
---

**¿Puede conectarse esta clave de WireGuard, y de quién es?** WireGuard autentica
a un peer por su clave pública estática y por nada más: ni certificados, ni
caducidad, ni revocación. Así que la pregunta se responde fuera del protocolo, y
se vuelve a responder cada vez que cambia la respuesta. Un proveedor —
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) — la responde; este
módulo es aquello en lo que se ponen de acuerdo el proveedor y un gateway.

```sh
go get github.com/go-authn/wireguard@v0.1.1
```

Su única dependencia es [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0, que
verifica la lista.

Hace dos cosas: `ParseKey` dice qué es una clave pública, y `Source.Fetch`
obtiene la `List` firmada del proveedor con las claves que registraron las
personas, cada una un `Peer` con su `Key`, `Subject`, `Username`, `Device` y el
fin de su concesión.

{{< callout type="info" >}}
**Por aquí solo pasan claves públicas**

Una clave privada se genera en el dispositivo y nunca sale de él; nada en este
paquete tiene sitio para una.
{{< /callout >}}

## Ejemplo {#example}

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

Un gateway conserva un `Source` y obtiene la lista:

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource` lee la configuración del proveedor al arrancar. `Fetch` obtiene un
token para el propio gateway (`client_credentials`, scope `wireguard_peers`),
obtiene la lista de `/wireguard/peers` bajo el emisor, y la verifica con
go-authn/oidc: la firma contra el conjunto de claves del proveedor, el emisor, la
audiencia (el `ClientID` de este gateway), la caducidad, y el `typ`
`wireguard-peers+jwt` (`ListType`) — de modo que ni un token de acceso ni un token
de ID pueden hacerse pasar por una lista, ni una lista por un token.

## Qué rechaza, y por qué {#what-it-refuses-and-why}

**Una clave** (`ParseKey`):

- cualquier otra escritura de los mismos bytes. La decodificación es estricta y el
  texto debe volver a imprimirse exactamente como llegó, así que un almacén
  indexado por el texto no puede guardar una misma clave dos veces bajo dos
  nombres;
- un punto de orden bajo, la clave toda a ceros entre ellos. Todo intercambio con
  uno da el mismo secreto compartido sea cual sea la clave del otro lado
  (RFC 7748 §6.1), así que no autentica a nadie. `crypto/ecdh` lo decide
  calculando un intercambio, así que las variantes con el bit superior también se
  rechazan.

**Una lista** (`Fetch`):

| | por qué |
|---|---|
| una lista con una `version` inferior a una que este `Source` ya ha aceptado | una lista antigua también está firmada, y puede incluir una clave retirada desde entonces |
| una clave que aparece dos veces | conservara la que conservara un gateway, el tráfico de la otra persona llegaría bajo el nombre equivocado |
| un peer sin subject | no pertenece a nadie |
| una clave que no lo es | véase más arriba |
| un emisor o un endpoint de token en claro, salvo loopback | el secreto del gateway y la lista cruzarían un enlace que cualquiera puede leer |
| un `SourceConfig` sin `ClientID` ni `ClientSecret` | un gateway lee la lista como un cliente propio |

Una lista lleva `exp`: un gateway que no puede obtener una más reciente para
entonces se queda sin lista, en lugar de con una obsoleta. `Peer.Subject` es el
`sub` de la persona tal como lo ve el cliente que registró la clave, público o
pairwise — el valor que un gateway encuentra también en los tokens de acceso de
esa persona.

## Contra qué se comprueba {#what-it-is-checked-against}

**El propio `wg(8)`**, de wireguard-tools, genera las claves que `ParseKey` debe
aceptar. Se instala en la vía de pruebas de Linux, el detector de carreras y la
vía de cobertura, que fijan `WIREGUARD_REQUIRE_JUDGE=1` para que la ausencia de
`wg` falle en lugar de omitirse. La prueba de orden bajo comprueba los siete
puntos que enumera libsodium, cada uno con y sin el bit superior. El umbral de
cobertura es el 100 %.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.1](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.1)
