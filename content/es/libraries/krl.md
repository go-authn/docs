---
title: "krl — listas de revocación de claves de OpenSSH"
linkTitle: "krl"
weight: 110
description: "go-authn/krl analiza, construye, fusiona y comprueba KRL de OpenSSH tal como las lee sshd, con una extensión de caducidad, y ssh-keygen hace de juez."
tags: [libraries, revocation, ssh]
---

**¿Está revocado este certificado o esta clave SSH, tal como respondería sshd?** El
formato binario del `PROTOCOL.krl` de OpenSSH, la lista que `sshd` carga mediante
`RevokedKeys` y que escribe `ssh-keygen -k`. `golang.org/x/crypto/ssh` no lo
admite.

```sh
go get github.com/go-authn/krl@v0.6.0
```

`IsRevoked` sigue a `ssh_krl_check_key` del `krl.c` de OpenSSH: un certificado está
revocado cuando su número de serie o su key ID está revocado bajo la CA que lo firmó
o bajo cualquier CA, cuando está revocada la clave de su CA, o cuando su propia clave
está revocada por blob o por huella SHA-1 o SHA-256. El número de serie 0 —el que
escribe una CA cuando no indica ninguno— nunca se revoca por número de serie.

## Ejemplo {#example}

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

La misma lista y los mismos certificados, escritos en archivos, obtienen las mismas
tres respuestas del `ssh-keygen -Q -f list.krl` de OpenSSH 10.3p1: `REVOKED`, `ok`,
`REVOKED`.

## Caducidad: `expires@go-authn.github.io` {#expiry-expiresgo-authngithubio}

Una KRL tiene una fecha de generación y una versión, y nada indica cuándo deja de
estar vigente, así que una copia obsoleta no se distingue de una reciente.
`Builder.SetExpires` escribe ese momento en una sección de extensión llamada
`ExtensionExpires`, **no crítica**, de modo que `sshd` y `ssh-keygen` cargan la lista
y la ignoran; `Parse` la lee en `KRL.Expires`.

{{< callout type="warning" >}}
**Sin firmas**

OpenSSH nunca ofreció una forma de escribir la sección de firma de la KRL, y ya no
la verifica. `Parse` se salta una si la hay y fija `Signed`, que no dice nada sobre
la autenticidad; `Builder` nunca escribe ninguna. La integridad de la lista, y por
tanto la de su caducidad, procede de su transporte —HTTPS desde un servidor
autenticado— o de una firma SSHSIG separada que comprueba quien llama, cosa que este
paquete no hace.
{{< /callout >}}

## Fusionar: un solo archivo para sshd {#merging-one-file-for-sshd}

`sshd` leía un único archivo `RevokedKeys` hasta OpenSSH 10.3, así que un servidor
que confía en varias CA necesita sus listas en una sola. `Builder.Merge` añade cada
revocación de una lista analizada. `Builder.MergeCA(k, ca, others...)` conserva la
sección de `k` para `ca`, sus secciones de cualquier CA reasignadas a `ca`, y sus
claves y huellas explícitas, y deja fuera —contándolas— las secciones de otra CA y
las claves o huellas que designan a una de `others`. `MergeCAWith` con
`MergeOptions{DropKeys: true}` deja fuera además todas las claves explícitas salvo
la de la propia `ca`, para una lista a la que no se confían los usuarios de todas las
CA: una clave de usuario revocada impide el acceso a ese usuario bajo todas las CA
del archivo fusionado, porque `sshd` comprueba la propia clave de un certificado sea
quien sea quien lo firmó.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

`Parse` rechaza lo que rechazan `ssh-keygen` y `sshd`: un número mágico o una versión
de formato incorrectos, datos truncados o sobrantes al final, una sección o
subsección de certificado desconocida, una extensión desconocida marcada como
crítica, una clave de CA que OpenSSH no puede analizar, el número de serie 0, un
rango de números de serie invertido, un mapa de bits mayor de lo que lee OpenSSH o
uno que da la vuelta más allá de 2^64−1. También rechaza una caducidad mal formada o
repetida: leída como ausente, convertiría una lista pensada para caducar en una que
nunca caduca.

`Builder` rechaza —en `Marshal`, que devuelve la primera petición no válida— el
número de serie 0, un rango cuyo extremo inferior es 0 o mayor que su extremo
superior, un key ID o un comentario que contiene un NUL, un certificado dado donde
se espera una clave de CA, y una caducidad anterior a la fecha de generación.

**Una diferencia deliberada.** Para muchos números de serie dispersos y próximos
entre sí, `ssh-keygen -k` escribe un mapa de bits más ancho de lo que acepta su
propio lector, y luego rechaza su propio archivo (*bignum is too large*). `Parse`
rechaza también ese archivo, como haría `sshd`; `Builder` empieza una sección nueva
antes de que un mapa de bits llegue a ser tan ancho, de modo que lo que escribe
siempre se puede leer.

Parse reserva memoria en proporción a lo que revoca la lista, como hace OpenSSH: una
KRL debería proceder de un origen en el que se confía para no enviar una enorme.

## Contra qué se comprueba {#what-it-is-checked-against}

**El `ssh-keygen` de OpenSSH**, en las vías de Linux y macOS, donde
`KRL_REQUIRE_SSHKEYGEN=1` convierte su ausencia en un fallo (Windows solo ejecuta las
pruebas en Go puro):

- una KRL escrita por `ssh-keygen -k` con todas las codificaciones de números de
  serie, key IDs, tres CA más «cualquier CA», claves explícitas y una clave de CA
  revocada: `IsRevoked` responde como `ssh-keygen -Q` para 250 certificados, y
  `Builder`, con las mismas revocaciones, escribe **los mismos bytes**;
- 40 conjuntos aleatorios de números de serie escritos por ambos: idénticos byte a
  byte, y las mismas respuestas para unos 9000 certificados;
- cada truncamiento y unas 1400 corrupciones de un solo byte: `Parse` rechaza
  exactamente lo que rechaza `ssh-keygen`;
- la extensión de caducidad se carga en `ssh-keygen`, y la misma sección marcada como
  crítica se rechaza;
- las listas fusionadas revocan exactamente lo que revoca uno de sus orígenes.

`FuzzParse`, sembrado con KRL que escribió `ssh-keygen`, y `FuzzBuilder` se ejecutan
en la CI. El umbral de cobertura es del 100 %, medido en la vía de Linux, donde
`ssh-keygen` está presente.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/krl@v0.6.0](https://pkg.go.dev/github.com/go-authn/krl@v0.6.0)
