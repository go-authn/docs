---
title: "cms — firmas en CMS SignedData"
linkTitle: "cms"
weight: 115
description: "go-authn/cms lee, verifica y firma CMS SignedData (RFC 5652), el contenedor de las firmas PDF, UEFI y S/MIME, juzgado por OpenSSL."
tags: [bibliotecas, firmas, certificados]
---

**¿Se sostiene esta firma sobre estos bytes, y qué certificado la hizo?**
CMS SignedData ([RFC 5652](https://www.rfc-editor.org/rfc/rfc5652)) es el
contenedor en el que se escriben una firma PDF, una variable autenticada UEFI y
un mensaje S/MIME. La biblioteca estándar lee certificados y verifica firmas,
pero no tiene CMS.

```sh
go get github.com/go-authn/cms@v0.2.1
```

Desde la v0.2.1, `Verify` rechaza una firma sin atributos cuyo contenido firmado es
en sí un `SET OF Attribute` DER que lleva a la vez un atributo content-type y un
atributo message-digest. Una firma hecha con atributos firmados cubre su DER (RFC 5652
§5.4); reempaquetada sin la clave como un SignedData sin atributos firmados, cuyo
contenido son esos atributos, se verificaba y nombraba al firmante por un contenido
nunca firmado como contenido.

La v0.2.0 **lee, verifica y firma**.

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

## Firmar {#signing}

`cms.Sign` escribe un ContentInfo DER con **un solo firmante**, a partir de
cualquier `crypto.Signer`: una clave RSA, ECDSA o Ed25519, en un fichero, en una
tarjeta o en un HSM. Antes de devolver el resultado, verifica la firma con el
certificado, de modo que un firmante que devuelve una firma errónea es
rechazado y nunca se emite.

```go
package main

import (
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/go-authn/cms"
)

func main() {
	// A key and a self-signed certificate, for the example. In practice the
	// key may live on a card or in an HSM: any crypto.Signer will do.
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		panic(err)
	}
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject:      pkix.Name{CommonName: "signer"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(time.Hour),
		KeyUsage:     x509.KeyUsageDigitalSignature,
	}
	certDER, err := x509.CreateCertificate(rand.Reader, template, template, key.Public(), key)
	if err != nil {
		panic(err)
	}
	cert, err := x509.ParseCertificate(certDER)
	if err != nil {
		panic(err)
	}

	content := []byte("the bytes to sign")
	der, err := cms.Sign(content, cms.SignOptions{
		Signer:      key,
		Certificate: cert,
		Hash:        crypto.SHA256,
		Detached:    true, // as a PDF signature: the content is not inside
		SigningTime: time.Now(),
	})
	switch {
	case errors.Is(err, cms.ErrSigner):
		panic(fmt.Sprint("the key or the device failed: ", err))
	case errors.Is(err, cms.ErrOptions):
		panic(fmt.Sprint("the request is wrong: ", err))
	case err != nil: // cms.ErrUnsupported
		panic(err)
	}

	// Sign checked its own signature; Verify is the reader's side.
	sd, err := cms.Parse(der)
	if err != nil {
		panic(err)
	}
	signers, err := sd.Verify(content)
	if err != nil {
		panic(err)
	}
	fmt.Println("signed by", signers[0].Subject.CommonName)

	content[0] ^= 1
	_, err = sd.Verify(content)
	fmt.Println("altered content:", errors.Is(err, cms.ErrInvalid))
}
```

`SignOptions` admite además `Chain` (intermedios que incrustar), `PSS`
(RSASSA-PSS), `SigningCertificateV2` (RFC 5035, lo que exigen los perfiles base
de CAdES y PAdES), `ContentType`, `NoSignedAttrs` y `Rand`. El resumen es
SHA-256 por defecto, o SHA-384 o SHA-512; Ed25519 usa siempre SHA-512. SHA-1 se
rechaza.

`Sign` tiene tres errores propios: `ErrOptions` (la petición es errónea),
`ErrSigner` (la clave o el dispositivo falló, o devolvió una firma que no se
verifica con el certificado) y `ErrUnsupported` (un algoritmo que no escribe).
También se rechaza Ed25519 **sin atributos firmados**: la RFC 8419 lo permite,
pero OpenSSL no verifica lo que este paquete escribiría.

`cms -verify` de OpenSSL y el `Verify` de este paquete coinciden en todas las
combinaciones consultadas: **58 combinaciones, 203 veredictos**, con RSA
PKCS #1 v1.5, RSA-PSS y ECDSA P-256 con SHA-256, SHA-384 y SHA-512, y Ed25519
con SHA-512, adjunta y separada, con y sin atributos firmados. `Verify` todavía
no comprueba signing-certificate-v2: vincular el certificado del firmante a ese
atributo corresponde a quien llama.

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
adivinarse; la firma es de un solo firmante, sin contrafirmas ni sello de
tiempo; `Verify` no comprueba signing-certificate-v2; no hay validación de
cadena, a propósito.

## Contra qué se comprueba {#what-it-is-checked-against}

**El comando `cms` de OpenSSL.** Once firmas hechas por OpenSSL 4.1.0 cubren
RSA, RSA-PSS, ECDSA y Ed25519, con contenido adjunto y separado y las dos formas
de identificador de firmante. `openssl cms -verify` y este paquete dan el mismo
veredicto sobre cada una y sobre sus variantes manipuladas: 34 de 34.

En dos puntos el paquete es **más estricto** que OpenSSL 4.1.0, que acepta una
etiqueta primitiva de atributos firmados y Ed25519 sobre SHA-256.
