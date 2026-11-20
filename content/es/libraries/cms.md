---
title: "cms — firmas en CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms lee y verifica CMS SignedData (RFC 5652), el contenedor de las firmas PDF, UEFI y S/MIME, juzgado por OpenSSL."
tags: [bibliotecas, firmas, certificados]
---

**¿Se sostiene esta firma sobre estos bytes, y qué certificado la hizo?**
CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)) es el
contenedor en el que se escriben una firma PDF, una variable autenticada UEFI y
un mensaje S/MIME. La biblioteca estándar lee certificados y verifica firmas,
pero no tiene CMS.

```sh
go get github.com/go-authn/cms@v0.1.0
```

La v0.1.0 **lee y verifica**. La firma llegará en la próxima versión.

## Ejemplo {#example}

```go
package main

import (
	"crypto/x509"
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/cms"
)

func main() {
	// A detached signature and the bytes it signed. For a PDF these are the
	// signature dictionary's /Contents and the file's /ByteRange.
	der, err := os.ReadFile("signature.der")
	if err != nil {
		panic(err)
	}
	content, err := os.ReadFile("signed-bytes")
	if err != nil {
		panic(err)
	}

	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content) // nil instead, when the content is attached
	switch {
	case errors.Is(err, cms.ErrInvalid):
		fmt.Println("the signature does not hold:", err)
		return
	case errors.Is(err, cms.ErrUnsupported):
		fmt.Println("a signature this package cannot check:", err)
		return
	case err != nil: // cms.ErrMalformed
		fmt.Println("not a signature:", err)
		return
	}

	// The signature holds. Whether to TRUST who made it is a second question,
	// with inputs of its own: the roots you accept.
	roots := x509.NewCertPool() // fill with the roots you trust
	for _, c := range signers {
		_, err := c.Verify(x509.VerifyOptions{Roots: roots, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageAny}})
		fmt.Println(c.Subject, "chain:", err)
	}
}
```

`Verify` responde si la firma se sostiene. La **confianza** — la cadena del
certificado, su validez, su revocación — es una decisión aparte, que la
RFC 5652 §5.6 sitúa fuera de CMS: `crypto/x509` para la cadena, y la
verificación de CRL de
[go-authn/revocation](https://github.com/go-authn/revocation) para lo que se ha
retirado.

## Tres errores, porque quien llama necesita tres respuestas {#three-errors-because-a-caller-needs-three-answers}

| error | significa |
|---|---|
| `ErrMalformed` | no es un SignedData que este paquete sepa leer |
| `ErrUnsupported` | una firma que usa algo no implementado aquí |
| `ErrInvalid` | legible y admitida, y la firma no se sostiene |

Cada rechazo envuelve exactamente uno de ellos, y las pruebas de fuzzing lo
mantienen como invariante.

## Qué rechaza {#what-it-refuses}

Según el código, cada uno con una prueba que comprueba su mensaje:

- un firmante cuyo certificado no está en el contenedor;
- atributos firmados sin exactamente un `content-type` y exactamente un
  `message-digest`, cada uno con un único valor;
- un tipo de contenido firmado que no es el del contenido;
- un resumen que no coincide con el contenido — **recalculado aquí**, nunca
  tomado del firmante;
- un algoritmo de firma cuyo propio hash no es el del resumen;
- SHA-1, rechazado por su nombre;
- Ed25519 sobre algo distinto de SHA-512 (RFC 8419);
- atributos firmados en cuatro formas no DER: una etiqueta `[0]` primitiva (a
  un bit de una firma válida), un atributo que no es una SEQUENCE, valores que
  no son un SET, y bytes sobrantes dentro de un atributo. El orden del SET no se
  comprueba;
- más de **16 firmantes**, y más de **16 MiB**. Un límite de tamaño no es un
  límite de trabajo, de ahí el tope de firmantes: el contenido se resume una
  vez por algoritmo de resumen, pero un firmante Ed25519 sin atributos firmados
  lo sigue resumiendo entero en cada comprobación.

**Todavía no:** las longitudes indefinidas BER se rechazan en lugar de
adivinarse; no hay firma; no hay validación de cadena, a propósito.

## Contra qué se comprueba {#what-it-is-checked-against}

**El comando `cms` de OpenSSL.** Once firmas hechas por OpenSSL 4.1.0 cubren
RSA, RSA-PSS, ECDSA y Ed25519, con contenido adjunto y separado y las dos formas
de identificador de firmante. `openssl cms -verify` y este paquete dan el mismo
veredicto sobre cada una y sobre sus variantes manipuladas: 34 de 34.

En dos puntos el paquete es **más estricto** que OpenSSL 4.1.0, que acepta una
etiqueta primitiva de atributos firmados y Ed25519 sobre SHA-256.
