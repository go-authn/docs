---
title: "kdc: emitir tickets Kerberos a partir de un directorio"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc es la mitad emisora de Kerberos: AS y TGS por UDP y TCP, preautenticación obligatoria, un solo tipo de cifrado, personas de un directorio go-authn."
tags: [bibliotecas, kerberos, directorio]
---

**¿Cómo emite un reino tickets a partir de un directorio?** AS-REQ y TGS-REQ, por UDP
y TCP, con preautenticación por marca de tiempo cifrada obligatoria, para las personas
que conoce un [directorio]({{< relref "/libraries/directory.md" >}}) y los servicios que
guarda una keytab. Se ejecuta bajo [authnd]({{< relref "/authnd/_index.md" >}}).

```sh
go get github.com/go-authn/kdc@v0.4.3
```

En la v0.4.3 su `go.mod` requiere como mínimo `go-authn/directory` v0.12.0 y
gokrb5 v8.4.4: son mínimos, así que un programa que requiere directory v0.14.0, la
versión que describen estas páginas, se compila con la v0.15.0, como hace authnd
v0.12.3. La mitad que
acepta es [krb5]({{< relref "/libraries/krb5.md" >}}), y un servicio que solo
verifica tickets no necesita este módulo en absoluto.

No implementado: referencias entre reinos, PKINIT, FAST, tickets renovables o
posfechados, y cualquier protocolo kadmin. Las claves proceden del directorio y de una
keytab, y se cambian allí donde viven.

## Solo un origen que guarda la contraseña puede respaldar un reino {#only-a-source-holding-the-password-can-back-a-realm}

Un KDC debe **descifrar** la preautenticación del cliente con la clave de larga
duración de esa persona, así que un `directory.Verifier` —un bind contra el LDAP de
otro, una comparación de hash— no sirve, por bien que responda *¿es esta la contraseña
correcta?*. A una persona cuyo origen no guarda ninguna contraseña se le responde
`KDC_ERR_NULL_KEY` (*null key*), nunca el código que recibe una contraseña incorrecta,
de modo que se lee como una configuración que corregir y no como una contraseña que
volver a escribir.

## Ejemplo {#example}

Un reino en memoria, en loopback:

```go
package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/go-authn/directory"
	"github.com/go-authn/kdc"
	"github.com/jcmturner/gokrb5/v8/iana/etypeID"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

func main() {
	// People: a source that holds PASSWORDS. A verifier cannot back a realm.
	people := &directory.Static{Name: "the configuration file", People: []*directory.Identity{
		directory.NewIdentity("alice", directory.WithPassword("correct horse battery staple")),
	}}

	// Services: the realm's own krbtgt key, and one per service.
	kt := keytab.New()
	for _, p := range []string{"krbtgt/EXAMPLE.ORG", "nfs/files.example.org"} {
		if err := kt.AddEntry(p, "EXAMPLE.ORG", rand.Text(), time.Now(), 1, etypeID.AES256_CTS_HMAC_SHA1_96); err != nil {
			log.Fatal(err)
		}
	}

	// A keytab without krbtgt/REALM is refused before anything listens.
	_, err := kdc.New(kdc.Config{Realm: "OTHER.ORG", People: people, Services: kt})
	fmt.Println(err)

	srv, err := kdc.New(kdc.Config{
		Realm:    "EXAMPLE.ORG",
		People:   people,
		Services: kt,
		Logf:     log.Printf, // why each request was refused; never a key
	})
	if err != nil {
		log.Fatal(err)
	}
	pc, err := net.ListenPacket("udp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	go srv.ServeTCP(ln)
	fmt.Println("EXAMPLE.ORG answers on", pc.LocalAddr())
	log.Fatal(srv.ServeUDP(pc))
}
```

Con un `krb5.conf` que nombra `kdc = tcp/127.0.0.1:18088` para `EXAMPLE.ORG`, el
`kinit` de Heimdal que incluye macOS (1.5.1) obtiene un ticket de concesión de tickets,
con `KRB5_CONFIG=krb5.conf` y `KRB5CCNAME=FILE:cc`:

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  nfs/files.example.org@EXAMPLE.ORG
```

Las diez horas son el valor por defecto de `Config.Lifetime`, y el ticket de servicio
termina con el ticket de concesión de tickets con el que se obtuvo. El KDC dijo por qué
rechazó cada petición, en su propio registro:

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

El primer rechazo de cada intercambio es el protocolo funcionando: el `KRB-ERROR` que
exige la preautenticación lleva una indicación `ETYPE-INFO2` que nombra el etype y la
sal, y el cliente lo vuelve a intentar con una marca de tiempo.

{{< callout type="info" >}}
**Antes de la v0.4.2, un `till` de 19700101000000Z obtenía un ticket ya caducado**

RFC 4120 §5.4.1: un `till` de 19700101000000Z pide la hora de fin máxima que permite
la política del KDC. El `kgetcred` de Heimdal envía exactamente eso. La v0.4.1 solo
comprobaba el tiempo cero de Go, así que tomaba la época Unix por un fin real y emitía
un ticket de servicio que `klist` mostraba como `>>>Expired<<<`; el `kvno` de MIT, el
juez de la CI, envía un `till` real y nunca se encontró con el caso. La v0.4.2 emite el
ticket más largo permitido, como arriba, y responde a un `till` ya pasado con
`KDC_ERR_NEVER_VALID` en lugar de con un ticket caducado al llegar
([go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19)).
{{< /callout >}}

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

**En la configuración** (`New`): sin reino (`ErrNoRealm`), sin directorio
(`ErrNoPeople`), sin keytab (`ErrNoServices`), o una keytab sin `krbtgt/REALM@REALM`
(`ErrNoTGTKey`), en lugar de arrancar y fallar en el primer `kinit`, donde el error
llega a una persona que no puede corregirlo.

**En el AS:** a una petición sin preautenticación se le responde exigiéndola, y la
clave de la persona no se deriva hasta que hay una marca de tiempo que comprobar, así
que un paquete UDP falsificado que nombra un principal real no cuesta ninguna
derivación de clave. Una contraseña incorrecta, una marca de tiempo con otro etype y
una de hace una hora se responden todas con `KDC_ERR_PREAUTH_FAILED`, el código que
recibe una contraseña incorrecta; el texto del error nombra el motivo, y `Logf`
también. Un servicio que pide un TGT propio se rechaza: los servicios se autentican a
partir de una keytab.

**Un solo tipo de cifrado.** Los tickets y las claves son únicamente
`aes256-cts-hmac-sha1-96` (etype 18). A una petición cuya lista de etypes no incluye el
18 se le responde `KDC_ERR_ETYPE_NOSUPP` antes de buscar a nadie. Con `Logf` fijado, el
registro anota ambos etypes, de modo que un operador puede distinguir un cifrado
incompatible de una contraseña mal escrita.

**En el TGS** (RFC 4120 §3.3.2), solo se emite un ticket cuando:

- el ticket presentado es un TGT de este reino, descifrado con la clave
  `krbtgt/REALM` que nombra el KDC, y no con la clave del servicio que diga el ticket
  (`KRB_AP_ERR_NOT_US`);
- el autenticador se descifra con su clave de sesión, dentro de `MaxSkew`;
- su suma de comprobación cubre el cuerpo de esta petición, tal como llegaron los
  bytes, con la clave de sesión (`KRB_AP_ERR_INAPP_CKSUM` cuando falta o no lleva
  clave, `KRB_AP_ERR_MODIFIED` cuando es incorrecta);
- el TGT no ha pasado su fin (`KRB_AP_ERR_TKT_EXPIRED`), no es anterior a su inicio
  ni está marcado como inválido (`KRB_AP_ERR_TKT_NYV`), sin ningún desfase permitido:
  esas horas las escribió el reloj de este KDC;
- el cliente es de este reino y sigue en el directorio
  (`KDC_ERR_C_PRINCIPAL_UNKNOWN`).

**Duraciones.** `Config.Lifetime` limita un ticket, diez horas cuando vale cero; un
cliente que pide menos obtiene menos, y un ticket obtenido con un TGT no termina más
tarde que ese TGT, así que volver a pedir `krbtgt` no puede alargar una credencial.

**Lo que puede retener un interlocutor no autenticado:** un mensaje TCP, incluida su
longitud, debe llegar en 30 segundos; se sirven como máximo 256 conexiones TCP a la vez,
y se responden como máximo 64 datagramas a la vez: uno más se descarta, y el cliente lo
reenvía o recurre a TCP.

## Contra qué se comprueba {#what-it-is-checked-against}

**Los propios `kinit` y `kvno` de MIT**, mediante pkgx, contra un reino construido en
Go: no interviene ningún KDC de MIT, solo se toma prestado el cliente.
`TestMITClientGetsATGTAndAServiceTicket` obtiene un TGT y un ticket de servicio y
comprueba la versión de clave que informa `kvno`. La línea de pruebas Linux, el
detector de carreras y la línea de cobertura fijan `KDC_REQUIRE_JUDGE=1`, y un paso
adicional falla salvo que el registro diga *were served by this realm*. Las pruebas
también fijan los rechazos que un cliente real nunca provoca: una marca de tiempo con
la clave equivocada, una de hace una hora, un cifrado de tres bytes, un servicio pedido
directamente en un AS-REQ, un ticket de servicio falsificado en el TGS, y un reino
respaldado por un verificador. El mínimo de la línea de cobertura es el 80%.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/kdc@v0.4.3](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.3)
