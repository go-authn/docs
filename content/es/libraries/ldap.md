---
title: "ldap — los bytes de un servidor LDAP"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap es el protocolo LDAP como biblioteca de servidor: el formato en la red, el filtro, las operaciones y sus límites, con handlers que deciden qué se responde."
tags: [bibliotecas, ldap, directorio]
---

**¿Cuáles son los bytes de un servidor LDAP?** Una biblioteca, no un demonio: el
formato en la red, el filtro, las operaciones. [authnd]({{< relref "/authnd/_index.md" >}})
es el servidor que la ejecuta y que es dueño de la configuración, de los orígenes del
directorio y de la política de bind; esta es dueña de los bytes.

```sh
go get github.com/go-authn/ldap@v0.8.0
```

Escrita a partir de los RFC 4511 (el protocolo), 4512 (el root DSE), 4513
(autenticación), 4514 y 4515 (formas en cadena de los DN y de los filtros), 4526,
2696 (resultados paginados), 3673, 4527 (controles de lectura de entrada), 4532
(whoami) y 3045.

Un `Server` es un conjunto de handlers, cada uno un campo opcional: `Bind`, `SASL`,
`Search`, `Compare`, `Extended`, `Add`, `Modify`, `Delete`, `ModifyDN`, `Abandon`.
Uno nil significa *este servidor no hace eso*, y la operación se responde con
`unwillingToPerform`, no con `insufficientAccessRights`, que abriría una discusión
sobre permisos que no existen. El root DSE lo responde el propio servidor, y publica
exactamente lo que respeta.

## Ejemplo {#example}

Un servidor con una persona que puede hacer un bind y una búsqueda que escribe lo que
coincide con el filtro:

```go
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"log/slog"
	"os"

	"github.com/go-authn/ldap"
)

var people = []*ldap.Entry{
	{DN: "uid=dora,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "dora")}},
	{DN: "uid=svc-web-prod,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-prod")}},
	{DN: "uid=svc-web-stage,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-stage")}},
}

// binder checks one password. A real one asks a directory: see go-authn/directory.
type binder struct{}

func (binder) Bind(_ context.Context, _ ldap.Session, req *ldap.BindRequest) (ldap.Result, error) {
	if req.Name == "" && len(req.Simple) == 0 {
		return ldap.Result{Code: ldap.Success}, nil // anonymous: the connection stays unbound
	}
	// A name with an empty password is an UNAUTHENTICATED bind (RFC 4513
	// 5.1.2). This package hands it to the handler, and the handler refuses it:
	// the comparison below does, since the password is never empty.
	ok := ldap.EqualDN(req.Name, "uid=dora,ou=people,dc=example,dc=org") &&
		subtle.ConstantTimeCompare(req.Simple, []byte("hunter2")) == 1
	if !ok {
		return ldap.Refuse(ldap.InvalidCredentials, "invalid credentials"), nil
	}
	return ldap.Result{Code: ldap.Success}, nil
}

// searcher writes each entry in scope that the filter matches, as it finds it.
type searcher struct{}

func (searcher) Search(_ context.Context, s ldap.Session, req *ldap.SearchRequest, w ldap.EntryWriter) (ldap.Result, error) {
	if s.BoundDN() == "" {
		return ldap.Refuse(ldap.InsufficientAccessRights, "bind first"), nil
	}
	for _, e := range people {
		if ldap.InScope(e.DN, req.BaseObject, req.Scope) && req.Filter.Matches(e) {
			if err := w.Entry(e); err != nil {
				return ldap.Result{}, err // the client went away, or a limit was reached
			}
		}
	}
	return ldap.Result{Code: ldap.Success}, nil
}

func main() {
	srv := &ldap.Server{
		Bind:           binder{},
		Search:         searcher{},
		NamingContexts: []string{"dc=example,dc=org"},
		Log:            slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// On anything but loopback: TLSConfig, and RequireTLS so that a
		// client that never asks for StartTLS is refused rather than
		// sending its password in the clear.
	}
	log.Fatal(srv.ListenAndServe("127.0.0.1:3389"))
}
```

Consultado con el `ldapsearch` de OpenLDAP (2.4.28, el que trae macOS), con la
contraseña de dora en un archivo:

```
$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw \
    -b ou=people,dc=example,dc=org '(uid=svc-*-prod)' uid
dn: uid=svc-web-prod,ou=people,dc=example,dc=org
uid: svc-web-prod

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -b ou=people,dc=example,dc=org '(uid=*)' uid
Insufficient access (50)
Additional information: bind first

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -s base -b '' namingContexts supportedLDAPVersion supportedExtension
dn:
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3

$ printf 'dn: uid=dora,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: uid\nuid: x\n' |
    ldapmodify -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw
ldap_modify: Server is unwilling to perform (53)
	additional info: this server does not modify entries
modifying entry "uid=dora,ou=people,dc=example,dc=org"
```

`(uid=svc-*-prod)` devuelve `svc-web-prod` y no `svc-web-stage`. La biblioteca a la
que esta sustituye evaluaba ese filtro como `(uid=svc-*)` y devolvía también
`svc-web-stage`; ese defecto es la razón por la que se escribió esta biblioteca. El
root DSE no anuncia StartTLS, porque no se indicó ningún `TLSConfig`.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

**Un filtro significa una sola cosa.** Se analiza o se decodifica una sola vez en un
árbol, y `String`, `EncodeFilter` y `Matches` leen todos ese árbol. Un atributo que
no es una descripción de atributo según el RFC 4512 §2.5, o una regla de coincidencia
que no es un OID, lo rechazan tanto `ParseFilter` como `DecodeFilter`: antes de la
v0.6.1, al volver a imprimirlo, un filtro «present» sobre el atributo `!x` se leía
como un NOT.

**Texto en claro, cuando se había prometido lo contrario.** StartTLS lo pide el
*cliente*, así que un servidor que solo lo ofrece no ha prometido nada.
`RequireTLS` rechaza cada operación en una conexión que no está protegida, con
`confidentialityRequired`.

**Un bind fallido no conserva nada.** RFC 4511 §4.2.1: la conexión se vuelve anónima
cuando se *recibe* la petición de bind, y sigue así salvo que el bind tenga éxito; así
que un nuevo bind con una contraseña errónea no conserva los derechos de la persona
anterior. Un bind simple sin handler `Bind` se responde con `authMethodNotSupported`,
y LDAPv2 se rechaza como error de protocolo.

{{< callout type="warning" >}}
**El handler decide qué significa una contraseña vacía**

Un bind no autenticado —un nombre con una contraseña vacía, RFC 4513 §5.1.2— se pasa
al handler `Bind` como cualquier otro bind simple, y un handler que devuelve
`Success` para él vincula la conexión a ese nombre. Recháselo en el handler, como
hace el ejemplo. El `ldapdir` de [directory]({{< relref "/libraries/directory.md" >}})
lo rechaza del lado del cliente.
{{< /callout >}}

**Un control crítico que no respeta.** ManageDsaIT (RFC 3296), password modify
(RFC 3062) y cancel (RFC 3909) se nombran como constantes porque un cliente puede
enviarlos, no porque se respondan: aquí nada sigue alias ni referencias, así que un
ManageDsaIT crítico se rechaza con `unavailableCriticalExtension`.

**Lo que puede retener un interlocutor no autenticado:**

| | por defecto | |
|---|---|---|
| `MaxMessageSize` | 4 MiB | una cabecera de cinco bytes que anuncia cuatro gigabytes se rechaza antes de reservar nada |
| `MaxMessageElements` | 16384 | elementos BER contados antes de decodificar: antes de la v0.5.0, 4 MiB de cadenas vacías retenían 373 MiB antes de cualquier bind |
| `IdleTimeout` | 5 minutos | el mensaje entero debe llegar a tiempo, no su primer byte; un valor negativo significa nunca |
| `MaxPending`, `MaxPendingAuth` | 100, 1000 | operaciones que una conexión puede tener en curso antes de su bind (`MaxPending`) y después (`MaxPendingAuth`), como `conn_max_pending` y `conn_max_pending_auth` de slapd; una conexión que se pasa recibe un aviso de desconexión y se cierra |
| `MaxPagedSearches` | 4 | búsquedas paginadas abiertas por conexión, cada una una goroutine detenida a la espera de su siguiente entrada |

El anidamiento de los filtros también está acotado: un desbordamiento de pila en Go
mata el proceso. Nada registra el *valor* de una aserción —un filtro lleva lo que
alguien tecleó—, solo la forma del filtro.

No hay esquema, así que cada comparación ignora mayúsculas y minúsculas en el valor.

## Contra qué se comprueba {#what-it-is-checked-against}

**El `ldapsearch` de OpenLDAP**, en la CI, y obligatorio donde está instalado: la vía
de pruebas de Linux, el detector de carreras y la vía de cobertura fijan
`LDAP_REQUIRE_JUDGE=1`, así que un cliente ausente hace fallar en lugar de omitir.
Windows no lo tiene y omite esas pruebas. `ldaptest`, el cliente de red propio de este
módulo, deliberadamente no es el juez: solo pregunta lo que `ldapsearch` no puede,
sobre el estado de una conexión: dos binds en un mismo socket, un bind SASL con un
mecanismo arbitrario, StartTLS seguido de más LDAP.

`FuzzMessage` hace pasar cada mensaje que puede enviar un cliente por la trama, los
decodificadores y la ida y vuelta del filtro. El umbral de cobertura es del 99,7 %,
con las tres líneas no alcanzadas nombradas en el workflow.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/ldap@v0.8.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.8.0)
