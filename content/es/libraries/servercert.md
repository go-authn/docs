---
title: "servercert — de dónde procede el certificado TLS de un demonio"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert sirve un certificado TLS de servidor a partir de archivos que se releen cuando cambian, o de una CA ACME mediante autocert, vinculación de cuenta externa incluida."
tags: [bibliotecas, tls, acme, certificados]
---

**¿De dónde procede el certificado TLS de servidor de un demonio?** De un
certificado y una clave en disco, que se releen cuando cambian, o de una CA ACME
mediante [`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert),
vinculación de cuenta externa (External Account Binding) incluida.

```sh
go get github.com/go-authn/servercert@v0.7.0
```

Una `Config` indica exactamente un origen — `CertFile` y `KeyFile`, o `ACME` — y
`New` devuelve un `*Source` cuyo `TLSConfig()` lo sirve, con `MinVersion` TLS 1.2.

## Ejemplo {#example}

A partir de archivos:

```go
package main

import (
	"log"
	"net/http"

	"github.com/go-authn/servercert"
)

func main() {
	src, err := servercert.New(servercert.Config{
		CertFile: "/etc/fileshare/tls/fullchain.pem",
		KeyFile:  "/etc/fileshare/tls/privkey.pem",
		OnError:  func(err error) { log.Print(err) }, // a renewal that did not load
	})
	if err != nil {
		log.Fatal(err) // unreadable, unparsable, or a key that is not the certificate's
	}
	srv := &http.Server{Addr: ":443", TLSConfig: src.TLSConfig()}
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
```

`Config.Check` rechaza una configuración que no puede funcionar, y no toca nada —
no se lee ningún archivo ni se crea ningún directorio:

```go
package main

import (
	"fmt"

	"github.com/go-authn/servercert"
)

func main() {
	// Check touches nothing: no file is read, no directory created.
	for _, c := range []servercert.Config{
		{ACME: &servercert.ACME{Domains: []string{"*.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"192.0.2.10"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "acme"}},
		{CertFile: "/etc/fileshare/tls/fullchain.pem"},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme",
			DirectoryURL: "http://acme.example.org/directory"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
	} {
		fmt.Println(c.Check())
	}
}
```

```
servercert: ACME domain "*.example.org" is a wildcard; that needs dns-01, which autocert does not do
servercert: ACME domain "192.0.2.10" is an IP address; autocert issues only for DNS names
servercert: ACME.CacheDir "acme" is not an absolute path
servercert: CertFile and KeyFile go together; one of them is empty
servercert: ACME.DirectoryURL "http://acme.example.org/directory" is not an https URL (RFC 8555 §6.1)
<nil>
```

La última es Let's Encrypt en producción: `DirectoryURL` vacío.

## Archivos {#files}

`New` lee el par y falla **en ese momento** si no se puede leer, no se puede
analizar, o su clave no es la del certificado. Después, como mucho una vez cada
10 segundos y durante un handshake, se vuelven a leer los archivos; un par
cambiado se analiza sin mantener ningún bloqueo y se sustituye. Un par cambiado
que **no** se carga — el certificado escrito antes que su clave, un archivo
truncado — se notifica una vez a `OnError`, y el último par válido sigue en
servicio, así que una tarea de renovación que escribe los dos archivos uno tras
otro nunca deja caído el servidor.

## ACME {#acme}

autocert responde a dos tipos de desafío y a ningún otro: `tls-alpn-01` (RFC 8737,
puerto 443, ALPN `acme-tls/1`) y, con `HTTPChallenge`, `http-01` (RFC 8555
§8.3, puerto 80, servido por `Source.HTTPHandler`). Sin `ACME.DNS` no hay `dns-01`,
y por tanto no hay comodines; nunca se emite un certificado para una dirección IP.

### dns-01: un servidor que la CA no puede alcanzar (desde v0.7.0)

`ACME.DNS` demuestra el control de los nombres con un registro TXT en
`_acme-challenge.<nombre>` (RFC 8555 §8.4). El servidor no necesita ningún puerto
de entrada y puede estar en una dirección privada de la red local; `Domains`
puede contener un comodín (`*.escuela.example`, que no cubre `escuela.example`:
indique ambos). La emisión pasa directamente por `x/crypto/acme` (autocert no
tiene dns-01): un certificado para todos los nombres, guardado con 0600 en
`CacheDir` y renovado en segundo plano, sirviendo el anterior mientras tanto.
`DNS` excluye `HTTPChallenge`.

```go
DNS: &servercert.DNS{
    CredentialsFile: "/etc/relay/dns-update.conf", // 0600, del usuario
    Provider: func(b []byte) (servercert.DNSSolver, error) { return rfc2136.New(b) },
    Resolver: "192.0.2.53:53", // opcional: esperar a que el TXT sea visible ahí
}
```

Un proveedor son dos métodos, `Present(ctx, name, value)` y
`CleanUp(ctx, name, value)`, cada uno sobre un valor TXT (un comodín y su nombre
base comparten un nombre de registro). El archivo de credenciales se lee bajo las
comprobaciones de `EABHMACKeyFile` y se entrega a `Provider`; nunca como
argumento, variable de entorno ni URL. El módulo
`github.com/go-authn/servercert/rfc2136` (v0.1.0) es el proveedor para un
servidor de nombres que acepta actualizaciones dinámicas RFC 2136 firmadas con
TSIG (RFC 8945): `server`, `zone`, `key`, `algorithm` (hmac-sha256, -384 o -512)
y `secret` en un solo archivo.

Los certificados se obtienen en el primer handshake cuyo SNI nombra uno de los
`Domains`, o antes de cualquier cliente mediante `Source.Prefetch`, y autocert
los renueva antes de que caduquen. Un cliente que se conecta por dirección IP no
envía SNI y recibe el certificado del primer dominio.

{{< callout type="warning" >}}
**Añada a `NextProtos`, nunca lo sustituya**

Con ACME, `TLSConfig().NextProtos` contiene `acme-tls/1`, sin el cual la
validación tls-alpn-01 de la CA falla. Y hay que añadir: un servidor TLS de Go
que anuncia protocolos ALPN rechaza a un cliente cuya oferta no comparte
ninguno, así que un servidor NFS sobre TLS añade `sunrpc` (RFC 9289). `net/http`
añade `http/1.1` y `h2` por sí mismo.
{{< /callout >}}

**Una CA que no necesita desafío.** autocert vuelve de inmediato cuando un pedido
nuevo ya está `ready`, que es lo que responde una CA con dominios prevalidados:
GÉANT TCS, servida por HARICA, para una cuenta Enterprise Admin. Un servidor
interno al que no se llega desde Internet ni por el puerto 80 ni por el 443 puede
obtener aun así un certificado de confianza pública. La clave HMAC de EAB es un
secreto, así que la configuración nombra un **archivo** que la contiene
(`EABHMACKeyFile`), nunca la clave.

Se sortea un defecto de `x/crypto/acme` ([golang/go#77704](https://github.com/golang/go/issues/77704)):
tras finalizar un pedido que la CA todavía está procesando, el cliente consulta
la URL de la cabecera `Location` de la respuesta de finalización, que el RFC 8555
no pone ahí. servercert da al cliente ACME un transporte que añade esa cabecera,
con la URL del pedido tomada de la respuesta newOrder recibida antes.

## Qué rechaza, y por qué {#what-it-refuses-and-why}

`Check` rechaza: ningún origen o ambos; medio par de archivos; ACME sin dominios
o sin directorio de caché; una ruta relativa; media EAB; un dominio que es una
dirección IP, un comodín, una sola etiqueta, termina en punto, o no es un nombre
de host válido; una URL de directorio que no es https (RFC 8555 §6.1).

`New` rechaza además un directorio de caché — contiene claves privadas — que es
un enlace simbólico, es accesible por el grupo o por otros, pertenece a un usuario
distinto del efectivo del proceso, o no se puede escribir; uno inexistente se crea
con `0700` y se comprueba después. Todos los directorios por encima de él deben
poder ser modificados solo por root o por el usuario efectivo, como exige
`StrictModes` de sshd a la ruta de `authorized_keys`, y un enlace simbólico por
encima de él se rechaza salvo que pertenezca a root. En Windows no se comprueban
ni el modo ni el propietario — las ACL deciden ambos, y restringirlas le
corresponde a usted — y se rechaza un enlace simbólico en cualquier punto de la
ruta.

`New` (y cada recarga) rechaza también un **archivo secreto** que el grupo u otros puedan leer o escribir: la `KeyFile` TLS y la `EABHMACKeyFile` ACME (desde v0.6.0), como OpenSSH rechaza una clave privada, con `chmod 600 it`. El modo se lee del archivo abierto, no de su nombre. Una clave de reemplazo escrita como legible no se toma: el certificado actual sigue sirviéndose y se llama a `OnError`. No se comprueba en Windows, donde deciden las ACL. **Actualización:** `chmod 600` (o `0400`) en ambos archivos antes de desplegar.

## Contra qué se comprueba {#what-it-is-checked-against}

**pebble**, la CA de pruebas de Let's Encrypt, ejecutada en el propio proceso a
partir de sus paquetes `ca`, `db`, `va` y `wfe` con un DNS simulado, que emite
certificados reales que `crypto/tls` verifica contra la raíz de pebble:
tls-alpn-01; http-01 mediante `HTTPHandler` y su control con `HTTPChallenge`
desactivado; EAB exigida, ausente, incorrecta y luego correcta; un dominio
prevalidado emitido sin ningún puerto de desafío abierto, y su control. Una prueba
ejecuta la misma emisión sin el arreglo de golang/go#77704 y exige que falle. El
umbral de cobertura es el 100 %.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/servercert@v0.7.0](https://pkg.go.dev/github.com/go-authn/servercert@v0.7.0)
