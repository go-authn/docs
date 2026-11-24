---
title: "pkcs12 — la clave y los certificados de un .p12 subido"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12 lee archivos PKCS#12 (.p12 / .pfx, RFC 7292) en Go puro, pensado para cargas no confiables: cada límite de recursos es una opción que no se puede desactivar, y OpenSSL es el juez."
tags: [bibliotecas, certificados, claves]
---

**¿Qué clave privada y qué certificados contiene este archivo que nos enviaron?**
PKCS#12 ([RFC 7292](https://www.rfc-editor.org/rfc/rfc7292)) es el contenedor
`.p12` / `.pfx` en el que un exportador escribe una clave, su certificado y el
resto de la cadena. `golang.org/x/crypto/pkcs12` está obsoleto y congelado en
SHA-1 y 3DES/RC2, así que rechaza lo que OpenSSL 3 y 4 y Windows escriben hoy
por defecto (PBES2, AES, MAC SHA-2). Este módulo los lee, sin más dependencia
que la biblioteca estándar, y está pensado para **cargas no confiables**.

```sh
go get github.com/go-authn/pkcs12@v0.1.1
```

**Solo decodifica**: no hay codificador. Decidir si se confía en la cadena es el
`Verify` de `crypto/x509`, una decisión aparte.

## Ejemplo {#example}

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/pkcs12"
)

func main() {
	data, err := os.ReadFile("upload.p12")
	if err != nil {
		panic(err)
	}

	b, err := pkcs12.Decode(data, "the password", nil)
	switch {
	case errors.Is(err, pkcs12.ErrIncorrectPassword):
		fmt.Println("ask again:", err)
		return
	case err != nil: // hostile, unsupported, too costly...
		fmt.Println("refused:", err)
		return
	}

	// b.PrivateKey   *rsa.PrivateKey, *ecdsa.PrivateKey, ed25519.PrivateKey or *ecdh.PrivateKey
	// b.Certificate  the certificate holding the key's public half
	// b.CACerts      every other certificate, in file order
	fmt.Println("certificate for", b.Certificate.Subject, "and", len(b.CACerts), "more")
}
```

`Decode(data, password, *Options) (*Bundle, error)` acepta `nil` para los
valores por defecto. El `Bundle` contiene la clave, el certificado cuya mitad
pública es, y los demás en el orden del archivo.

## Opciones y valores por defecto {#options-and-their-defaults}

Un campo en cero toma el valor por defecto, y **ningún campo puede desactivar
un límite**.

| campo | por defecto | significado |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | iteraciones de una derivación de clave |
| `MaxWork` | 5 000 000 | iteraciones x bloques de salida en todo el archivo |
| `MaxDepth` | 16 | anidamiento BER y de fragmentos de cadena construida |
| `MaxBags` | 1024 | SafeBags del archivo |
| `MaxAuthSafes` | 32 | ContentInfos del AuthenticatedSafe |
| `MaxCertSize` | 32 KiB | DER de un certificado |
| `MaxCertBytes` | 512 KiB | DER de todos los certificados juntos |
| `MaxRSABits` | 8192 | módulo RSA |
| `AllowNoMAC` | `false` | leer un archivo sin MAC de integridad (`openssl pkcs12 -nomac`); si no, es `ErrNoMAC` |
| `NoPassword` | `false` | el archivo se exportó sin contraseña alguna, a diferencia de la contraseña vacía `""` |

Los dos booleanos son las dos ambigüedades del formato. Con `AllowNoMAC`, nada
autentica el contenido, y una contraseña errónea solo se nota por un descifrado
fallido. La contraseña **vacía** (`""`) y la contraseña **ausente**
(`NoPassword`) derivan claves distintas y ambas funcionan: con `""` y
`NoPassword` en false, `Decode` prueba primero la vacía y luego la ausente,
porque los exportadores no coinciden en cuál escribieron; con `NoPassword` en
true solo se prueba la ausente, y el argumento de contraseña debe ser `""`.

## Qué lee {#what-it-reads}

| capa | admitido |
|---|---|
| cifrado | PBES2 ([RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)) con PBKDF2 sobre HMAC-SHA-1/224/256/384/512 y AES-128/192/256-CBC |
| cifrado heredado | `pbeWithSHAAnd3-KeyTripleDES-CBC`, `pbeWithSHAAnd2-KeyTripleDES-CBC`, `pbeWithSHAAnd40BitRC2-CBC` y la variante de 128 bits; RC2 está implementado en el módulo |
| integridad | MAC HMAC con SHA-1/224/256/384/512 (KDF del apéndice B de la RFC 7292), y **PBMAC1** ([RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)) |
| contraseñas | BMPString según el apéndice B.1, caracteres fuera de BMP como pares sustitutos |
| codificación | BER, incluidas longitudes indefinidas y OCTET STRING construidos, que escriben Windows y Java |
| bolsas | bolsas de claves cifradas y en claro, bolsas de certificados; las bolsas de CRL, de secretos y de contenido seguro se omiten |

**Rechazados como `ErrUnsupported`:** los modos de integridad y privacidad de
clave pública (`signedData`, `envelopedData`), RC4, scrypt, PBES1 que no sea
el de PKCS#12, SHA-1 dentro de PBMAC1, y BER (en vez de DER) dentro de un
certificado o de una clave PKCS#8.

## Errores {#errors}

| error | significa |
|---|---|
| `ErrMalformed` | no es un archivo PKCS#12 que este paquete pueda leer |
| `ErrUnsupported` | legible, pero usa algo no implementado aquí |
| `ErrLimit` | se superaría un límite de `Options`; rechazado antes del trabajo |
| `ErrIncorrectPassword` | una contraseña errónea y un archivo manipulado, la misma respuesta por diseño |
| `ErrNoMAC` | sin MAC, y `AllowNoMAC` no está activado |
| `ErrNoPrivateKey` | ninguna clave privada en el archivo |
| `ErrMultipleKeys` | más de una clave privada en el archivo |
| `ErrNoCertificate` | ningún certificado corresponde a la clave privada |
| `ErrPassword` | una contraseña inutilizable |

Todo rechazo envuelve exactamente uno de ellos, y el objetivo de fuzzing lo
mantiene como invariante.

## Los límites de seguridad {#the-security-bounds}

Cada límite anterior se comprueba **antes del trabajo**, y cada campo de
longitud se compara con los bytes realmente presentes antes de reservar nada.
Se rechazan las sales de más de 512 bytes y las contraseñas de más de 1024
caracteres.

El MAC se verifica **en tiempo constante, antes de descifrar nada**.

`crypto/x509` reserva hasta 43 a 52 veces el tamaño de un certificado cuando
está hecho de miles de nombres diminutos, y `crypto/rsa` valida una clave con
aritmética sobre los números que declara, de modo que factores mucho más largos
que el módulo cuestan CPU superlineal. Ninguno de los dos se puede arreglar
desde fuera, así que lo que les llega se acota antes: los certificados con
`MaxCertSize` y `MaxCertBytes`, y toda clave PKCS#8 (32 KiB como máximo) se lee
con `encoding/asn1` y se rechaza, tipada, cuando su módulo supera `MaxRSABits`,
un factor o exponente es más largo de lo que el módulo permite, un número no es
positivo, o es multiprimo (`ErrUnsupported`).

**Memoria por petición.** Con las opciones por defecto, un archivo hostil hace
que un `Decode` reserve unos 25 MB (medido conjuntamente: peores certificados y
mayor clave aceptada, 8192 bits, 25,1 MB, de los cuales unos 20 MB siguen vivos
hasta que retorna) para un archivo de 530 KB. Un servicio que decodifica cargas
debe limitar las decodificaciones en curso, por ejemplo con un semáforo, y bajar
`MaxCertBytes` si solo espera cadenas cortas.

## Limitaciones {#limitations}

- **Las claves RSA sin valores CRT se rechazan** (`ErrUnsupported`). Una clave
  sin `Dp`, `Dq` y `Qinv` se rechaza antes de que `crypto/x509` la vea. La
  RFC 8017 los exige y todo exportador los escribe (OpenSSL, Windows, el
  keytool de Java), pero `crypto/x509` deriva los que faltan con aritmética de
  enteros grandes: 16,4 MB y 21 744 reservas a 8192 bits, frente a 0,36 MB y 618
  con ellos.
- **Los valores CRT de RSA se verifican, diga lo que diga `GODEBUG`**
  ([go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2), corregido
  en v0.1.1). Antes de que `crypto/x509` vea la clave se comprueban
  `Dp = D mod (P-1)`, `Dq = D mod (Q-1)` y `Qinv × Q = 1 mod P`, después de los
  límites de tamaño; una discrepancia se rechaza como `ErrMalformed`. Bajo
  `GODEBUG=x509rsacrt=0` la biblioteca estándar descarta los valores CRT
  erróneos y los recalcula, lo que llevó la decodificación con los peores
  certificados a 39,4 MB (razón 74,7), fuera del límite que afirman las
  pruebas. La comprobación no depende del ajuste.
- Solo decodifica, y no juzga la cadena.

## Contra qué se comprueba {#what-it-is-checked-against}

**OpenSSL es el juez.** 23 archivos escritos por OpenSSL 4.1 (AES/PBES2,
3DES y RC2 con `-legacy`, `-nomac`, varios certificados, RSA, EC y Ed25519,
PBMAC1) están en las pruebas, con un manifiesto de lo que el propio OpenSSL
dice que contiene cada uno.

**Amplificación.** `TestAmplification` acota los bytes reservados sobre los
bytes de entrada con muchas bolsas diminutas, muchos certificados, anidamiento
indefinido profundo, cadenas largas de OCTET STRING y longitudes declaradas de
4 GiB, y afirma que los rechazos ocurren antes de llamar a `crypto/x509`. El
módulo también se fuzzea (corpus versionado), tiene 100 % de cobertura de
bloques y se ejecuta con `-race` y `govulncheck`.

**`software.sslmate.com/src/go-pkcs12`**, en un módulo `oracle/` aparte: de los
23 archivos que ambos pueden intentar, ambos leen 18 con hoja, orden de cadena
y clave idénticos byte a byte. Solo este paquete lee los otros 5 (RC2-128, un
MAC SHA-384, sin MAC, y dos contraseñas con caracteres fuera de BMP); no hay
ninguno que el otro lea y este rechace.

Se combina con [cms]({{< relref "/libraries/cms.md" >}}): decodificar un `.p12`
aquí, firmar allí.
