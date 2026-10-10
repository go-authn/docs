---
title: "fido: hablar con una llave de seguridad"
linkTitle: "fido"
weight: 30
description: "go-authn/fido habla CTAPHID y CTAP2 con una llave de seguridad sobre cualquier transporte de 64 bytes: handshake, registro, aserción y PIN, en Go puro."
tags: [libraries, fido, factors]
---

**¿Cómo se habla con una llave de seguridad?** El protocolo FIDO de cliente a
autenticador —el entramado CTAPHID, el handshake del canal, y los comandos CTAP2 que
registran una credencial, piden una firma e intercambian un PIN por un token— en Go
puro, en cualquier sistema operativo.

```sh
go get github.com/go-authn/fido@v0.6.1
```

Nada aquí depende de la plataforma. Un `Transport` lleva informes de 64 bytes hacia
un autenticador y desde él, y dice cómo se llama el dispositivo; de dónde proceden
esos informes —IOKit en macOS, hidraw en Linux, WebHID en un navegador— es asunto del
paquete de otro. Todo lo que está por encima está aquí:

| | |
|---|---|
| `Open(ctx, t)` | el handshake `INIT` en el canal de difusión; devuelve un `*Key` con su propio canal. El `Key` es dueño de `t`: `Close` lo cierra, y también un `Open` fallido |
| `Key.Ping`, `Key.Wink` | una ida y vuelta, y un parpadeo: la forma más barata de preguntar *¿cuál de estas llaves es esta?* |
| `Key.GetInfo` | versiones, extensiones, AAGUID, opciones, protocolos de PIN |
| `Key.MakeCredential`, `Key.GetAssertion` | registrar, y firmar; `ParseAuthData` lee los datos del autenticador, y `AuthData.PublicKey` convierte una clave COSE P-256 en un `*ecdsa.PublicKey` |
| `Key.PINRetries`, `Key.KeyAgreement`, `Key.PINToken` | `authenticatorClientPIN`, los dos protocolos de autenticación PIN/UV |
| `Split`, `NewReassembler`, `ParseInit`, `Key.CBOR` | el entramado, exportado para quien maneje una llave de otro modo |

`AuthData.PublicKey` es una conversión, no una verificación: qué algoritmos cuentan y
qué hacer con un contador de firmas que ha retrocedido corresponde al llamante.
[keyfactor]({{< relref "/libraries/keyfactor.md" >}}) es uno de esos llamantes.

## Ejemplo {#example}

Solo el entramado, sin llave: un mensaje cortado en informes, y vuelto a montar.

```go
package main

import (
	"bytes"
	"fmt"

	"github.com/go-authn/fido"
)

func main() {
	// A 200-byte ping, cut into the 64-byte reports a key reads...
	payload := bytes.Repeat([]byte{0xA5}, 200)
	reports, err := fido.Split(0x01020304, fido.CmdPing, payload)
	if err != nil {
		panic(err)
	}
	fmt.Println(len(reports), "reports of", len(reports[0]), "bytes")

	// ...and put back together, as a reply would be.
	r := fido.NewReassembler(0x01020304)
	for _, rep := range reports {
		msg, done, err := r.Feed(rep)
		if err != nil {
			panic(err)
		}
		if done {
			fmt.Println(bytes.Equal(msg.Data, payload), msg.Cmd == fido.CmdPing)
		}
	}

	// A report for another channel is an error, not something to drop.
	other, _ := fido.Split(0x0A0B0C0D, fido.CmdPing, []byte("hi"))
	_, _, err = fido.NewReassembler(0x01020304).Feed(other[0])
	fmt.Println(err)

	// The framing's real limit, not the length field's.
	fmt.Println(fido.MaxMessage)
}
```

```
4 reports of 64 bytes
true true
fido: the report belongs to another channel
7609
```

Con una llave, `fido.Open(ctx, transport)` hace el handshake y el `*Key` que devuelve
lleva todos los comandos posteriores.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

**No se confía en que una llave responda a lo que se le preguntó.** Una respuesta que
lleva un comando distinto del enviado se rechaza (CTAP 2.1 §11.2.9 da a cada respuesta
su propio comando, y libfido2 también lo comprueba). Una respuesta `INIT` cuyo nonce no
es el enviado se rechaza: es el handshake de otro programa en la misma llave. Un token
PIN que no tiene la longitud de su protocolo —16 o 32 bytes con el protocolo uno,
exactamente 32 con el protocolo dos— se rechaza.

**Un keepalive no es una respuesta.** Una llave que espera un dedo envía
`CTAPHID_KEEPALIVE` aproximadamente cada cien milisegundos; se omite, y el único límite
a lo que puede tardar un toque es el contexto.

**Un mensaje más largo de lo que el entramado puede transportar.** Dos bytes de
longitud permitirían 65535, pero 57 bytes en el paquete de inicialización más 128
continuaciones de 59 dan 7609 (`MaxMessage`); más allá, un número de secuencia llegaría
a `0x80` y una llave lo leería como un mensaje nuevo. `Split` devuelve `ErrTooLong`.

**Informes que no cuadran**: uno para otro canal (`ErrWrongChannel`: dos programas en
una llave), continuaciones desordenadas (`ErrOutOfOrder`), un informe más corto que un
paquete (`ErrShortPacket`), una respuesta `INIT` más corta que sus 17 bytes
(`ErrTruncated`).

**Un comando que la llave no dijo admitir.** `Wink` no se envía a una llave sin
`CapWink`, ni `GetInfo` a una sin `CapCBOR`: la llave respondería `CTAPHID_ERROR`, y el
llamante tendría que distinguir ese rechazo de una avería.

**Un PIN vacío**, y cualquier cosa que no sea P-256 en `AuthData.PublicKey`:
rechazados por su nombre en lugar de decodificados a medias.

{{< callout type="warning" >}}
**Un PIN incorrecto cuesta un reintento**

CTAP da a un autenticador un contador de reintentos de PIN, ocho como máximo, y cada
PIN incorrecto gasta uno. Tres PIN incorrectos seguidos bloquean el PIN hasta que la
llave se desconecta y se vuelve a conectar. Un contador que llega a cero lo bloquea
para siempre: solo un reinicio lo levanta, y un reinicio borra todas las credenciales
de la llave. Consulte `Key.PINRetries` antes de pedírselo a nadie: dice cuántos
reintentos quedan y si la llave espera a que la desconecten.
{{< /callout >}}

## Contra qué se comprueba {#what-it-is-checked-against}

La CI no tiene ninguna llave de seguridad, así que las pruebas usan un transporte
falso que vuelve a montar lo que se le envía —una llave que rechaza, se atasca, sigue
diciendo que está ocupada, o comparte su canal con otro programa—, con la cobertura
mantenida al 100%. Dos bancos de pruebas proceden de fuera de este código:

- `testdata/yubikey-fido-5.7.4-getinfo.hex`, la respuesta `GetInfo` **capturada de una
  YubiKey FIDO 5.7.4**, decodificada por `ctap2_test.go`;
- `testdata/webauthn-reference-authdata.b64`, una muestra de las pruebas de
  **go-webauthn/webauthn**, que comprueba el analizador de datos del autenticador y
  `AuthData.PublicKey`.

La tabla de códigos de estado sigue el `err.h` de libfido2. El README del módulo
registra un registro y una aserción ejecutados contra una YubiKey real, con la firma
verificada contra la clave pública que entregó; esa ejecución no forma parte de la CI.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/fido@v0.6.1](https://pkg.go.dev/github.com/go-authn/fido@v0.6.1)
