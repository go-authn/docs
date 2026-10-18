---
title: "krb5: aceptar un ticket Kerberos"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5 es la mitad aceptante de Kerberos: una keytab, un AP-REQ verificado, el AP-REP que necesita la autenticación mutua, y mensajes firmados y sellados con la clave de sesión."
tags: [bibliotecas, kerberos]
---

**¿Es válido este ticket Kerberos para este servicio?** La mitad **aceptante** de
Kerberos, y solo esa mitad: guarda una keytab, verifica el AP-REQ que presenta un
cliente, responde con el AP-REP que prueba que el servicio es auténtico, y después
firma, verifica, sella y abre mensajes con la clave que estableció ese intercambio.

```sh
go get github.com/go-authn/krb5@v0.3.1
```

Nunca habla con un KDC y nunca emite un ticket, así que de quién acepta tickets es una
decisión de otro. La mitad emisora es [kdc]({{< relref "/libraries/kdc.md" >}}), y
este módulo no depende de ella; consulte
[por qué están separados]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}}).
El descifrado de tickets es el de [gokrb5](https://github.com/jcmturner/gokrb5).

## Por qué existe {#why-it-exists}

gokrb5 es una biblioteca cliente. Verifica un AP-REQ y no sabe construir el AP-REP que
lo responde. Todo cliente GSS-API pide autenticación mutua —el propio `gss-client` de
MIT fija `GSS_C_MUTUAL_FLAG` sin forma de desactivarlo—, así que un servicio que no
puede producir un AP-REP no completa ningún contexto. Construirlo es la mayor parte de
lo que añade este módulo.

## Ejemplo {#example}

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

Necesita `github.com/jcmturner/gokrb5/v8` para `keytab.New`, que recibe `krb5.New`;
`krb5.Load` lee en cambio una keytab desde una ruta.

Después de `Accept`, un `*Context` dice quién: `Principal()` (`alice@EXAMPLE.ORG`), o
`User()` y `Realm()` por separado. Asociar un principal a una cuenta local es la
política del llamante: `alice@EXAMPLE.ORG` y `alice@PARTNER.ORG` responden ambos a
«alice». `Expires()` es cuándo termina el ticket que hay detrás, momento a partir del
cual un servidor que mantiene una conexión de larga duración debería dejar de
respetarlo. `MIC`/`VerifyMIC` y `Wrap`/`Unwrap` firman; `Seal`/`Unseal` añaden
confidencialidad (`sec=krb5p`). Un `Context` no es seguro para uso concurrente; un
`Acceptor` sí.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

**Un ticket que este servicio no acepta** —servicio equivocado, clave equivocada,
caducado, reproducido, un reloj más allá de `ClockSkew` (cinco minutos por defecto,
también en MIT)— es `ErrRejected`. Los bytes que no son un token GSS-API krb5 son
`ErrNotAToken`, y un token que no es un AP-REQ es `ErrNotAPReq`. Los errores son
deliberadamente gruesos: un cliente sabe que su ticket se rechazó, nunca qué
comprobación lo rechazó. Un error significa que no hay contexto, y el token devuelto
está vacío.

**Un principal por el que el aceptante no responde.** Con
`krb5.Principal("nfs/files.example.org")`, una keytab que guarda varios servicios solo
responde por ese.

**Un mensaje cuya firma no coincide** es `ErrBadMIC`, sea la longitud, la cabecera, la
secuencia o la suma de comprobación lo que no cuadrara. El aceptante firma con el uso
de clave 23 y verifica con el 25, así que un token que produjo este servidor no puede
reproducirse contra él como si lo hubiera firmado el cliente.

**Un token sellado entregado a `Unwrap`** es `ErrSealed`, distinto de una firma
incorrecta: a un llamante que lee un token solo de integridad no se le debe entregar
un texto cifrado que se lea como un mensaje. **Un token sin sellar entregado a
`Unseal`** es `ErrNotSealed`: a un protocolo que prometió confidencialidad no se le
entrega algo que cruzó la red sin cifrar.

No afirma ninguna subclave del aceptante: la clave del contexto es la subclave que el
iniciador puso en su autenticador, o la clave de sesión del ticket cuando no envió
ninguna (RFC 4121 §4.3).

{{< callout type="warning" >}}
**Una keytab es un secreto en reposo**

Su ruta puede proceder de un archivo de configuración o de `KRB5_KTNAME`; la clave que
contiene nunca debe registrarse, imprimirse ni transportarse en una variable de
entorno.
{{< /callout >}}

## Contra qué se comprueba {#what-it-is-checked-against}

**Un KDC de MIT real y el propio `gss-client` de MIT**, contra este paquete haciendo
las veces de `gss-server`. `test/kdc.sh` construye un reino desechable en loopback, sin
privilegios; la CI obtiene MIT Kerberos mediante pkgx (los paquetes de Ubuntu no
incluyen `gss-client`). La línea de pruebas Linux, el detector de carreras y la línea
de cobertura fijan `KRB5_REQUIRE_JUDGE=1`, de modo que un banco de pruebas ausente
falla. Un paso adicional ejecuta `TestMITClientAgainstThisAcceptor` y falla salvo que
el registro diga *authenticated as alice@*: no se acepta una línea en verde cuyo juez
dejó de ejecutarse en silencio. `TestMITClientSealed` hace lo mismo con la
confidencialidad activada.

Las líneas de macOS, Windows y de otras arquitecturas no tienen reino, y allí el juez
se omite. El mínimo de la línea de cobertura es el 90%.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/krb5@v0.3.1](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.1)
