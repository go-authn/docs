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
go get github.com/go-authn/ldap@v0.9.0
```

Escrita a partir de los RFC 4511 (el protocolo), 4512 (el root DSE y el
esquema), 4513 (autenticación), 4514 y 4515 (formas en cadena de los DN y de los
filtros), 4517 y 4518 (sintaxis, reglas de comparación, preparación de
cadenas), 4526, 2696 (resultados paginados), 3672 (subentradas), 3673, 4527
(controles de lectura de entrada), 4532 (whoami) y 3045.

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

**Una búsqueda paginada responde a lo que se preguntó.** Hasta la v0.8.0, el
lector de páginas enviaba cada entrada tal como la escribía el handler: una
búsqueda paginada solo de `cn` volvía con todos los atributos, operativos
incluidos, y `typesOnly` se ignoraba, mientras que la misma búsqueda sin
paginar se ceñía a la selección. `ldapsearch -E pr=N` es como pagina un
cliente, así que la misma pregunta recibía dos respuestas. Desde la v0.8.0
ambas aplican la selección, lo que el propio `ldapsearch` comprueba en la CI.

Sin esquema —`Server.Schema` a nil, el valor por defecto—, cada comparación
ignora mayúsculas y minúsculas en el valor: la más segura de las dos para
leer, ya que nunca oculta una entrada que una comparación exacta habría
encontrado.

## El esquema {#the-schema}

Desde la v0.8.0, el paquete `schema` es el esquema de directorio del
RFC 4512 §4, y `Server.Schema` hace que un servidor lo use. Nil deja un
servidor exactamente como estaba.

- `schema.Standard()` incorpora las definiciones de los RFC 4512, 4517, 4519,
  4524, 4523, 2798, 2307, 3672 y 3045, más `ldapPublicKey` y `sshPublicKey` de
  openssh-lpk y las dos definiciones de OpenLDAP que necesitan, copiadas del
  texto de los RFC; cada archivo de `schema/defs` nombra su fuente y su
  sección. `schema.Build(append(schema.StandardFiles(), mine)...)` añade las
  propias de un despliegue, y rechaza una cuyos SUP, reglas, sintaxis, MUST o
  MAY no se resuelven.
- `(*ldap.Entry).Validate(s)` comprueba una sola cadena estructural con cada
  superclase listada, cada MUST, nada fuera de MUST y MAY, SINGLE-VALUE, tipos
  conocidos, valores de su sintaxis y los valores del RDN en la entrada, y
  nombra **cada** problema, como un `*schema.ValidationError`.
- Con un esquema, el root DSE lleva `subschemaSubentry: cn=Subschema`, y una
  búsqueda de base sobre `cn=Subschema` (`ldap.SubschemaDN`) la responde la
  biblioteca, como el root DSE (RFC 4512 §4.2). Las definiciones solo llegan
  cuando se piden por nombre o con `+`. Está detrás de la barrera de
  `RequireTLS`.
- Los filtros se evalúan con las reglas de comparación del esquema
  (RFC 4517 §4.2, con la preparación de cadenas del RFC 4518) en la lógica de
  tres valores del RFC 4511: un atributo desconocido, un tipo sin regla para
  la comparación pedida o un valor de aserción no válido es **Undefined**,
  nunca un error. El servidor vuelve a comprobar cada entrada que envía un
  handler y descarta las que el filtro no hace TRUE; un handler filtra con
  `req.Matches(e)`, que usa el mismo esquema.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap"
	"github.com/go-authn/ldap/schema"
)

func main() {
	s := schema.Standard() // RFC 4512, 4517, 4519, 4524, 2798, 2307, ... and openssh-lpk

	// An account with posixAccount, and no homeDirectory.
	eli := &ldap.Entry{DN: "uid=eli,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "top", "account", "posixAccount"),
		ldap.StringAttribute("uid", "eli"),
		ldap.StringAttribute("cn", "eli"),
		ldap.StringAttribute("uidNumber", "1001"),
		ldap.StringAttribute("gidNumber", "1001"),
		ldap.StringAttribute("mail", "eli@example.org"),
	}}
	var v *schema.ValidationError
	if errors.As(eli.Validate(s), &v) {
		for _, p := range v.Problems {
			fmt.Println("-", p)
		}
	}

	// uidNumber orders as an integer: 1001 >= 999, which as strings it is not.
	for _, f := range []string{"(uidNumber>=999)", "(uid>=a)"} {
		filter, _ := ldap.ParseFilter(f)
		fmt.Println(f, ldap.Evaluate(filter, eli, s))
	}
}
```

```
- mail is not allowed by any of the entry's object classes
- homeDirectory is required by posixAccount and is missing
(uidNumber>=999) TRUE
(uid>=a) Undefined
```

`mail` pertenece a `inetOrgPerson`, no a `account`. `uid` no tiene regla
ORDERING, así que un rango sobre él es Undefined.

{{< callout type="info" >}}
**Una desviación del RFC 2307: `uidNumber` y `gidNumber` se ordenan como enteros**

El RFC 2307 da a `uidNumber` y `gidNumber` una regla EQUALITY y ninguna regla
ORDERING, lo que haría Undefined todo filtro de rango sobre ellos, incluido el
que SSSD construye a partir de `ldap_min_id` y `ldap_max_id`. slapd define él
mismo ambos tipos con `ORDERING integerOrderingMatch`
(`servers/slapd/schema_prep.c`; su `nis.schema` los comenta como
"builtin"), y lo mismo hace draft-howard-rfc2307bis-02 §2.1, así que las
definiciones incorporadas los siguen. Eso, y permitir clases auxiliares sin
reglas de contenido DIT (el RFC 4512 §2.4.3 las prohíbe estrictamente; todos
los servidores en uso las permiten), se dicen en lugar de descubrirse.
{{< /callout >}}

No están, deliberadamente: las reglas de contenido DIT, las reglas de
estructura DIT y las formas de nombre; cambiar el esquema por LDAP; las reglas
de comparación de certificados del RFC 4523 y
`directoryStringFirstComponentMatch`, que están definidas y no implementadas,
así que las aserciones que las usan son Undefined; los atributos colectivos;
las opciones distintas de `lang-` y `binary`.

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}) sirve este
esquema y somete a él cada entrada que publica.

## Esquemas en HCL2, y el conversor {#hcl2-and-the-converter}

Desde la v0.9.0, un esquema puede escribirse en HCL2 además de en los
archivos que lee slapd. El paquete `schema/hclschema` decodifica HCL2 en los
mismos `*schema.Definitions` que devuelve `schema.Read`, y los vuelve a
codificar (`hclschema.Decode`, `hclschema.Encode`); `schema` en sí no depende
de HCL. Un bloque es una definición, y su tipo dice cuál:
`object_identifier`, `ldap_syntax`, `matching_rule`, `attribute_type` u
`object_class`. La etiqueta es el primer NAME. Los atributos son los términos
del RFC 4512 §4.1 en minúsculas y con guiones bajos (`desc`, `sup`,
`equality`, `single_value`, `kind`, `must`, `may`, etcétera), y el `{len}` de
una sintaxis es `syntax_len`.

**Sólo valores literales.** Un valor es una cadena entre comillas, un número,
un booleano o una lista de ellos. Una variable, una función, un operador o una
plantilla `${...}` se rechaza antes de evaluar nada, de modo que leer un
esquema nunca lo ejecuta. Cada campo lo comprueba el analizador estricto del
RFC 4512, y los errores que necesitan una posición llegan con el archivo, la
línea y la columna.

El comando `ldapschema` convierte entre los formatos:

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.9.0
```

- `ldapschema to-hcl [--macros] FILE...` lee archivos `.schema` de OpenLDAP,
  LDIF de cn=config y LDIF del subesquema, y escribe HCL2.
- `ldapschema to-schema [--macros] FILE...` lee HCL2 y escribe un archivo
  `.schema` de OpenLDAP.
- `ldapschema check FILE...` construye las definiciones sobre
  `schema.Standard()` e informa.

La salida va a stdout. El código de salida es 0 cuando el comando funcionó, 1
cuando se rechaza un archivo o una definición, y 2 ante un error de uso.

**Los lectores leen los archivos como slapd**, porque los esquemas publicados
se escriben para slapd: términos en cualquier orden, la continuación de línea
de slapd en un archivo `.schema` y el plegado del RFC 2849 en LDIF, valores en
base64, el prefijo `{N}` de cn=config, y macros `objectidentifier` resueltas
en el orden de los archivos. Las funciones `Parse*` exportadas, y lo que un
servidor publica, siguen siendo estrictamente RFC 4512.

Un ejemplo, ejecutado desde un directorio vacío con `ldapschema` v0.9.0. El
esquema está inventado para esta página: 1.3.6.1.4.1.99999 es un arco de
ejemplo de uso privado, no asignado a nadie. Una macro, un tipo de atributo,
una clase auxiliar:

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1 NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1 NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top AUXILIARY
	MAY siteBadge )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

attribute_type "siteBadge" {
  oid          = "1.3.6.1.4.1.99999.1.1"
  desc         = "the badge number"
  equality     = "caseIgnoreMatch"
  syntax       = "1.3.6.1.4.1.1466.115.121.1.15"
  syntax_len   = 32
  single_value = true
}

object_class "sitePerson" {
  oid  = "1.3.6.1.4.1.99999.2.1"
  desc = "a person with a badge"
  sup  = ["top"]
  kind = "auxiliary"
  may  = ["siteBadge"]
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( 1.3.6.1.4.1.99999.1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( 1.3.6.1.4.1.99999.2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 1 attribute types, 1 object classes
build: ok, 2 definitions added to schema.Standard()
```

Los OID numéricos son la salida por defecto, porque es lo que un cliente ve en
el subesquema; `--macros` conserva los nombres de las macros. `check` informa
también de las definiciones que `schema.Standard()` ya tiene, y de cada
referencia que nada define, donde `Build` se detiene en la primera.

**`check` puede salir con código 1 en un archivo que slapd carga.** El
`core.schema` de OpenLDAP remite a cuatro cosas que slapd incorpora y que
`schema.Standard()` no define: las sintaxis 1.3.6.1.4.1.1466.115.121.1.42 y
1.3.6.1.4.1.1466.115.121.1.43, y las reglas de comparación
`protocolInformationMatch` y `presentationAddressMatch`. `ldapschema check
core.schema` las lista como `missing:` y sale con código 1. Debe leerse como
«no definido aquí», no como un defecto del archivo.

**Lo que no admite:** las reglas de contenido del DIT, las reglas de
estructura del DIT y las formas de nombre; las directivas `include`, porque un
archivo `.schema` se lee como definiciones y no se ejecuta como una
configuración de slapd; y `X-SUBST` en `ldapsyntax`.

**Los esquemas publicados se convierten.** La versión se midió con los archivos
`core`, `cosine`, `inetorgperson` y `nis` de OpenLDAP, con SUPANN 2021 de
RENATER, con eduPerson de REFEDS y con el esquema de Samba: en cada uno,
`.schema` a HCL y vuelta, y LDIF frente a `.schema`, dan definiciones iguales.
Sólo los archivos de OpenLDAP están en el repositorio. SUPANN y eduPerson no se
reproducen aquí; léalos en las páginas de sus autores:
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)
y [eduPerson](https://github.com/REFEDS/eduperson).

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

[pkg.go.dev/github.com/go-authn/ldap@v0.9.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.9.0)
