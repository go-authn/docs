---
title: "keyfactor: la llave registrada, tocada"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor convierte una llave de seguridad en un factor mfa, verificando la respuesta contra el registro en lugar de confiar en cualquier dispositivo que hable CTAP."
tags: [libraries, fido, mfa, factors]
---

**¿Respondió la llave que se registró, y la tocó una persona?** `keyfactor` es la
única pieza entre [fido]({{< relref "/libraries/fido.md" >}}), que habla CTAP y no
sabe nada de ninguna política, y [mfa]({{< relref "/libraries/mfa.md" >}}), que decide
cuánta prueba basta y no sabe nada de ningún dispositivo. Ninguno importa al otro;
este importa a los dos.

```sh
go get github.com/go-authn/keyfactor@v0.4.1
```

En la v0.4.1 su `go.mod` requiere como mínimo `go-authn/fido` v0.6.0 y
`go-authn/mfa` v0.5.0: son mínimos, así que un programa que requiere fido v0.6.1, la
versión que describen estas páginas, se compila con la v0.6.1.

La plataforma aporta un `Opener` —cómo se encuentra una llave en este sistema— y solo
conserva eso. Todo lo demás es igual allí donde haya CTAP: la aserción, las
comprobaciones, la negativa a gastar el último intento de PIN de alguien.

## Ejemplo {#example}

```go
package main

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"

	"github.com/go-authn/fido"
	"github.com/go-authn/keyfactor"
	"github.com/go-authn/mfa"
)

func main() {
	// The platform supplies the Opener: how a key is found on this system.
	// This one finds nothing, and says so the way a policy understands.
	open := func(context.Context) (fido.Transport, error) {
		return nil, keyfactor.Unavailable(errors.New("no security key is plugged in"))
	}

	// From the registration: the credential ID and its public key, which
	// fido.AuthData.PublicKey returns from the attestation.
	var pub *ecdsa.PublicKey // nil here, to show the refusal

	f := keyfactor.New(open, keyfactor.Options{
		RPID:         "example.test",
		CredentialID: []byte{0x01, 0x02},
		PublicKey:    pub,
	})
	fmt.Println(f.Name(), f.Kind())

	_, err := mfa.Verify(context.Background(), mfa.Policy{Count: 1}, f)
	fmt.Println(err)
}
```

```
your security key possession
mfa: 1 factor(s) needed, 0 answered: your security key (possession): keyfactor: no public key for the credential; without one any device that answers would pass, so pass the one from the registration
```

El rechazo llega antes de llamar al `Opener`. Con la clave pública del registro, el
mismo factor abre la llave, le pide una aserción sobre un desafío aleatorio nuevo, y
comprueba la respuesta.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

**Que responda un dispositivo no es que responda la llave.** Una placa USB
programable habla CTAP tan bien como una llave de seguridad, así que la respuesta se
comprueba contra el registro:

| se rechaza | mensaje |
|---|---|
| antes de abrir nada: sin `Opener`, sin `RPID`, sin `PublicKey`, o una clave que no está en P-256 | `keyfactor: no opener; …`, `… needs a relying party id …`, `… no public key for the credential; …`, `… is not on P-256 …` |
| un hash de la parte que confía que no es el SHA-256 de `RPID` | `… answered for another relying party` |
| una credencial distinta de `CredentialID`, cuando el dispositivo nombra una | `… answered with a credential other than the one asked for` |
| una firma sobre los datos del autenticador y el desafío que no hizo `PublicKey` | `… answered with a signature the credential's key did not make` |
| sin indicador `UP` | `… answered without anyone touching it` |
| sin indicador `UV` cuando se dio un `PIN` | `… was asked to establish who holds it and did not` |

**El último intento de PIN no se gasta en una suposición.** Primero se consulta
`PINRetries`; una llave que no aceptará más PIN hasta que se desconecte se rechaza, y
también una a la que le queda **un intento o menos**. Según CTAP, tres PIN incorrectos
seguidos bloquean el PIN de una llave hasta que se desconecta, y un contador de
reintentos que llega a cero lo bloquea para siempre: solo un reinicio lo levanta, y
borra todas sus credenciales.

**Un PIN no es un segundo factor.** El tipo sigue siendo `mfa.Possession`: un PIN
introducido en la llave protege la llave, y no identifica a nadie ante esta máquina.

**Un puerto vacío no es un rechazo.** Un `Opener` que no encuentra nada envuelve su
error con `keyfactor.Unavailable`, que lo marca como `mfa.ErrUnavailable`, y una
política cuenta *no se pudo preguntar* aparte de *dijo que no*.

{{< callout type="warning" >}}
**Lo que no puede proteger: el hash del PIN llega a cualquier dispositivo que responda**

CTAP hace que la plataforma entregue a la llave `LEFT(SHA-256(PIN), 16)`, cifrado con
un secreto acordado con el propio dispositivo, antes de firmar nada. Un dispositivo
falsificado se rechaza como factor, pero ha recibido ese hash, y un PIN corto cae ante
una búsqueda sin conexión. Así es el protocolo. Use un PIN largo, y no lo escriba en
una llave de procedencia desconocida.
{{< /callout >}}

## Contra qué se comprueba {#what-it-is-checked-against}

Las pruebas imitan **el autenticador**, no el transporte, construido con el entramado
exportado del propio go-authn/fido: un handshake CTAPHID, una aserción CTAP2 y un
intercambio ClientPIN. La mitad PIN juega el lado del autenticador del protocolo dos de
forma independiente —su propio ECDH, HKDF y AES-CBC, escritos a partir de la
especificación (`fakepin_test.go`)—, así que una derivación que difiriera en un byte
haría fallar el intercambio. `forged_test.go` es el dispositivo que no guarda ninguna
credencial. La cobertura se mantiene al 100%, y las pruebas se ejecutan en ocho
arquitecturas.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.1](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.1)
