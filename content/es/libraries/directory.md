---
title: "directory: quién es alguien, y qué lo prueba"
linkTitle: "directory"
weight: 50
description: "go-authn/directory: un solo modelo de una persona y de las credenciales que un origen guarda para ella, sobre una lista en memoria, una base de datos SQL, un servidor LDAP o una configuración HCL."
tags: [bibliotecas, directorio, ldap, sql]
---

**¿Quién es alguien, y qué puede probarlo?** Un solo modelo sobre una lista guardada
en memoria, una base de datos SQL, un servidor LDAP, o bloques `user` y `group` en un
archivo de configuración; y lo que importa es la segunda mitad de la pregunta.

```sh
go get github.com/go-authn/directory@v0.14.0
```

## Lo que prueba a alguien no es una sola cosa {#what-proves-somebody-is-not-one-thing}

Es un hecho de los protocolos. NTLMv2 (SMB) es un desafío-respuesta: el cliente nunca
envía la contraseña, así que el servidor debe guardar la contraseña o
`MD4(UTF16LE(password))` —el hash NT—, y **un bind LDAP no puede autenticar una sesión
SMB**. Un KDC debe *descifrar* con la clave de la persona, así que solo un origen que
guarda la contraseña puede respaldar un reino. SSH necesita una clave pública. Un
segundo factor necesita el secreto que hay detrás de los seis dígitos.

Así que una `Identity` dice qué `Credential` le dio su origen —`Password`, `NTHash`,
`Verifier` (una comparación de hash o un bind), `PublicKeys`, `TOTPSecret`—, e
`Identity.Can` permite a un servidor decir *puede usar WebDAV y no SMB* antes de que
alguien se encuentre con un rechazo al montar. Cada protocolo tiene su propio método:

| | responde a | a partir de |
|---|---|---|
| `Verify(password)` | cualquier cosa a la que se entregue la contraseña | primero el verificador del origen (puede ser un bind LDAP), si no la contraseña guardada, comparada en tiempo constante sobre resúmenes SHA-256 para que ni siquiera se filtre la longitud |
| `NTKey()` | NTLMv2 | el hash publicado, o derivado de la contraseña; `ErrNoCredential` sin ninguno de los dos |
| `Derive(f)`, `KerberosKey(f)` | un KDC, AWS SigV4: cualquier cosa que deba *poseer* el secreto | solo la contraseña; la derivación es la función del llamante |
| `Keys()` | SSH | líneas `authorized_keys` |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | una columna, o un atributo LDAP que nombra el llamante |

## Los orígenes {#the-sources}

| paquete | lee | importa |
|---|---|---|
| `directory` | una lista `Static`, y un `Set` de orígenes en orden | solo la biblioteca estándar |
| `directory/sqldir` | cualquier `*sql.DB`, con **sus** consultas | ningún controlador: lo elige el programa |
| `directory/ldapdir` | un servidor LDAP | `go-ldap/ldap/v3` |
| `directory/hcldir` | un bloque `users` que nombra una base de datos o un servidor LDAP, y bloques `user`/`group` que contienen personas | `x/crypto/ssh`, `hashicorp/hcl/v2`, `zclconf/go-cty` |
| `directory/ldaptest` | un servidor LDAP contra el que probar | `glauth/ldap` |

En un `Set`, el **primer** origen que conoce un nombre se lo queda, así que una cuenta
de servicio anotada localmente no tiene por qué ponerse en LDAP. La pertenencia a
grupos es la **unión** de todos los orígenes. Los orígenes se leen cuando arranca un
servidor; una comprobación de contraseña puede llegar al origen cada vez, porque un
bind no puede guardarse en caché sin guardar el secreto.

`hcldir` no decodifica HCL: el llamante decodifica el bloque y se lo entrega. Solo
importa HCL para escribir, para `SetPassword`. Las etiquetas de compilación `nosql` y
`noldap` dejan un tipo completamente fuera de `hcldir`.

## Ejemplo {#example}

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	local := &directory.Static{
		Name: "the configuration file",
		People: []*directory.Identity{
			directory.NewIdentity("dora", directory.WithPassword("hunter2")),
			directory.NewIdentity("eli", directory.WithVerifier(func(pw string) error {
				return directory.ErrWrongPassword // a bind against somebody else's LDAP, say
			})),
			directory.NewIdentity("svc-backup", directory.WithPublicKeys("ssh-ed25519 AAAA...elided... backup")),
		},
		Groups: map[string][]string{"staff": {"dora", "eli"}, "nobody": {}},
	}
	people := directory.NewSet(local) // more sources after it: sqldir, ldapdir...

	ids, _ := people.Identities()
	for _, id := range ids {
		fmt.Println(id.Name(), "password:", id.Can(directory.Password), "verifier:", id.Can(directory.Verifier),
			"keys:", id.Can(directory.PublicKeys), "from", id.Where())
	}

	// NTLMv2 needs MD4(UTF16LE(password)): dora's can be derived, eli's cannot.
	for _, id := range ids[:2] {
		_, err := id.NTKey()
		fmt.Println(id.Name(), "SMB:", err == nil, errors.Is(err, directory.ErrNoCredential))
	}

	// An empty group is an empty answer; a group nobody has is an error.
	fmt.Println(people.Members("nobody"))
	fmt.Println(people.Members("admins"))

	// @group is expanded; an empty group, or one nobody has, is refused.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	_, err := directory.Expand([]string{"@nobody"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
	_, err = directory.Expand([]string{"@admins"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[] <nil>
[] directory: no such group: "admins", in the configuration file
[dora eli svc-backup] <nil>
[] directory: the group has no members: "nobody": nobody would be allowed
directory: the group has no members: "nobody": nobody would be allowed true false
directory: no such group: "admins", in the configuration file false true
```

Una contraseña guardada también responde a `Can(Verifier)`: se puede comparar.

{{< callout type="info" >}}
**Un grupo vacío es un grupo: `Members` lo responde, `Expand` lo rechaza**

Desde la v0.12.0, `Set.Members` devuelve una lista vacía y ningún error para
un grupo que un origen tiene pero en el que no hay nadie, así que un servidor
que lista los grupos puede publicarlo. `Expand` lo sigue rechazando, con
`ErrEmptyGroup`, que no es `ErrNoSuchGroup`: un grupo que nadie tiene es una
errata o un grupo borrado; uno vacío es un grupo por llenar. Quien llama y
tolera un grupo que no concede nada comprueba los dos. En la v0.11.x,
`Set.Members` devolvía `ErrNoSuchGroup` para un grupo vacío, y `Expand` de `@nobody`
a través del `Set` imprimía `[] directory: no such group: "nobody"`.
{{< /callout >}}

## Atributos {#attributes}

Desde la v0.13.0, una `Identity` puede llevar **atributos**: lo que un origen
dice de alguien y no prueba nada —un `uidNumber`, un directorio personal, una
dirección de correo—. Se mantienen aparte de las credenciales a propósito: una
credencial decide quién puede iniciar sesión, un atributo se *publica* a todo
el que tiene permitido buscar. Un servidor como
[authnd]({{< relref "/authnd/entries.md" >}}) los convierte en los atributos de
una entrada LDAP, y su esquema decide qué es la entrada.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	a, err := directory.NewAttributes(
		directory.Attribute{Name: "uidNumber", Values: []string{"1000"}},
		directory.Attribute{Name: "mail", Values: []string{"dora@example.org"}},
		directory.Attribute{Name: "MAIL", Values: []string{"d.explorer@example.org", "dora@example.org"}},
	)
	fmt.Println(err)
	dora := directory.NewIdentity("dora", directory.WithPassword("hunter2"), directory.WithAttributes(a))
	fmt.Println(dora.Attributes().Names(), dora.Attributes().Get("UIDNUMBER"), dora.Attributes().Get("mail"))

	// What is published cannot hold a secret, nor what a server derives or answers itself.
	for _, name := range []string{"userPassword", "sambaNTPassword", "radiusHash", "cn", "memberUid", "2.5.4.35"} {
		_, err := directory.NewAttributes(directory.Attribute{Name: name, Values: []string{"x"}})
		fmt.Println(errors.Is(err, directory.ErrAttributeName), err)
	}
}
```

```
<nil>
[uidNumber mail] [1000] [dora@example.org d.explorer@example.org]
true directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "sambaNTPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "radiusHash" looks like it holds a secret (its name contains "hash"), and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "cn" is derived by the server from the name it publishes the entry under
true directory: not an attribute this package carries: "memberUid" is membership, which Members answers: a second answer would disagree with it
true directory: not an attribute this package carries: "2.5.4.35" is an OID: name it by its descriptor, so that what is refused by name stays refused
```

Los nombres son descripciones de atributo del RFC 4512, comparadas sin
distinguir mayúsculas de minúsculas ni el orden de las opciones, así que `mail`
y `MAIL` son un solo atributo, escrito de la primera forma en que se dio; una
repetición exacta de un valor se conserva una sola vez. Los valores son cadenas
y no se interpretan: `"1000"` es un `uidNumber` porque así lo dice el esquema de
un servidor. Un valor vacío, o ninguno, se rechaza.

| se rechaza | por qué |
|---|---|
| 56 secretos con nombre —`userPassword`, `authPassword`, `userPKCS12`, `sambaNTPassword`, `sambaLMPassword`, `unicodePwd`, `krbPrincipalKey`, `krb5Key`, `ipaNTHash`, `ipatokenOTPkey`, `oathSecret`, `olcRootPW`, …— | leídos del RFC 4519, el RFC 3112, el RFC 2798 y los esquemas de Samba, Active Directory, Kerberos de MIT y de Heimdal, FreeIPA, 389-ds y OpenLDAP |
| cualquier nombre que contenga `password`, `passwd`, `pwd`, `secret`, `credential`, `hash` o `privatekey` | una lista solo conoce los esquemas que alguien leyó; el único nombre estándar que esto atraparía, `secretary` (RFC 4524), está permitido |
| `sshPublicKey` | tiene su propio camino, `WithPublicKeys`, para que `Can(PublicKeys)` siga siendo verdadero |
| `uid`, `userid`, `cn`, `commonName`, `objectClass` | un servidor los deriva del nombre bajo el que publica la entrada |
| `member`, `uniqueMember`, `memberUid`, `memberOf` | la pertenencia es lo que responde `Members`, y una segunda respuesta discreparía |
| `createTimestamp`, `modifyTimestamp`, `creatorsName`, `modifiersName`, `structuralObjectClass`, `governingStructureRule`, `subschemaSubentry`, `entryDN`, `entryUUID` | los mantiene un servidor; una configuración solo podría falsificarlos |
| un nombre en forma numérica | los rechazos son por nombre, y `2.5.4.35` *es* `userPassword` |

`ReservedAttributes()` devuelve la lista completa, 75 nombres con sus motivos;
`CheckAttributeName` aplica la regla sola, para que una configuración pueda
rechazarse antes de leer nada.

De dónde vienen:

- **`hcldir`**: `attributes = { … }` en los bloques `user` y `group`, una
  cadena o una lista de cadenas por nombre; un número se rechaza con la
  corrección en el mensaje (*write it as a string, "1000"*), y `null` omite el
  atributo.
- **`sqldir`**: dos consultas opcionales, `users_attributes` y
  `groups_attributes` (`Queries.PeopleAttributes`, `GroupAttributes`), leídas
  **por alias de columna**: la primera columna es el nombre, cada una de las
  demás un atributo nombrado por su alias. Una columna cuyo alias no es una
  descripción de atributo, o nombra una credencial, se rechaza con su número de
  columna antes de leer una sola fila. `NULL` y `''` son ausencia, y varias
  filas para un mismo nombre suman valores. Un grupo nombrado solo ahí existe,
  sin nadie dentro.
  ⛔ PostgreSQL pasa a minúsculas un alias sin comillas (`as uidNumber` vuelve
  como `uidnumber`): el mismo atributo, escrito a la manera de la base de
  datos. Póngalo entre comillas, `as "uidNumber"`, cuando la grafía importe.
- **`ldapdir`**: `Config.Attributes` y `GroupAttributes` (`attributes` y
  `group_attributes` en un bloque `users "ldap"`) nombran lo que se copia de la
  entrada de cada persona y de la de cada grupo, comparado por equivalencia
  del RFC 4512 y conservado con la grafía configurada. Además de la lista de
  arriba, rechaza el `totp_attribute` y los atributos de nombre y de miembro
  del grupo. Un subtipo que el directorio devuelve además
  (`description;lang-fr` para `description`) no se copia: pídalo por su
  nombre.

Los atributos de un grupo vienen de `Set.GroupAttributes`, a través del
`GroupAttributer` opcional: **el primer origen que da un atributo se queda con
él**, así que un `gidNumber` en un archivo local prevalece sobre el del
directorio, mientras que una `description` que solo tiene el directorio pasa, y
un origen averiado es un error aunque otro haya respondido. Los atributos de
una persona llegan con la persona, desde el origen al que pertenece el nombre.

## Los valores por defecto de ldapdir {#ldapdir-defaults}

| ajuste (`users "ldap"` / `ldapdir.Config`) | por defecto desde la v0.14.0 | hasta la v0.13.0 |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`, `ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | el mismo |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | el mismo |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`, `ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | el mismo |
| `group_member_attribute` / `MemberAttribute` | ninguno: `memberUid` (nombres) **y** `member` (DN); si se define, es el único atributo que se lee | `memberUid` |

Las tres clases son las estándar que llevan un `uid`: `posixAccount`
(RFC 2307), `account` (RFC 4524 §3.1) y `uidObject` (RFC 4519 §3.14).
go-authn/authnd desde la v0.11.0 publica a una persona sin los atributos POSIX
como `account` o `inetOrgPerson`, pone `uidObject` en cada persona y publica un
grupo sin `gidNumber` como `groupOfNames`. Con los valores por defecto
anteriores, esas personas y esos grupos no se leían en absoluto.

{{< callout type="warning" >}}
**La v0.14.0 amplía lo que entrega el directorio de una institución**

Un directorio con entradas `account` o `uidObject` que no son posixAccount
—cuentas de servicio, máquinas nombradas por uid, personas importadas de otro
lugar— se las entrega ahora a todo programa que conservó el valor por defecto,
y cada una de ellas puede entonces comprobarse contra el directorio con un
bind. Sus grupos `groupOfNames` pasan a ser grupos, y una regla `@group` que
nombra uno concede ahora lo que dice. Un `inetOrgPerson` simple sin ninguna de
las tres clases sigue sin leerse. Para conservar exactamente el conjunto
anterior:

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**Un DN en `member` no añade ninguna persona.** Corresponde a alguien solo
cuando es, por distinguishedNameMatch (RFC 4517 §4.2.15), el DN de una entrada
que devolvió la búsqueda de personas. Un DN fuera de esas entradas, o que no
nombra a nadie, no corresponde a nadie, y tampoco `uid=alice,ou=elsewhere,…`
cuando alice se importó de `ou=people`. Hasta la v0.13.0, un DN en el atributo
de miembro se reducía al valor de su primer RDN, fuera de quien fuera, así que
`uid=alice,ou=elsewhere,…`, `cn=alice,…` y `uid=zed,…` se convertían en
miembros llamados alice, alice y zed.

`ldaptest`, el directorio de pruebas, aplica ahora la base y el filtro a cada
búsqueda, da a cada persona un `objectClass` (`Person.ObjectClasses`, por
defecto `top`, `account`, `posixAccount`) y tiene grupos `groupOfNames`
(`GroupsOfNames`), para que una prueba de los filtros de un cliente pueda
fallar.

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

- **Un grupo en el que no hay nadie**, y **un grupo que ningún origen tiene**,
  cuando `Expand` convierte `@grupo` en personas: errores, no listas vacías:
  una configuración que no concede nada a nadie se lee exactamente igual que
  una que funciona. El primero es `ErrEmptyGroup`, el segundo
  `ErrNoSuchGroup`, y `errors.Is` los distingue. `Set.Members` responde a un
  grupo vacío con una lista vacía; un grupo que ningún origen tiene también es
  `ErrNoSuchGroup` ahí. Un origen que está *averiado* se notifica aparte de uno
  al que le falta el grupo, y prevalece sobre una respuesta vacía.
- **Un directorio LDAP al que se llega sin cifrar.** Un bind simple lleva la propia
  contraseña (RFC 4513), así que `ldapdir.New` y un bloque `users "ldap"` rechazan
  `ldap://` hacia otra máquina salvo que se fije `StartTLS`. Se aceptan `ldaps://`,
  `ldapi://` y `ldap://` hacia una dirección de loopback. No existe ningún interruptor
  para desactivarlo.
- **Una contraseña vacía en un bind LDAP.** En LDAP es un *bind no autenticado*, que la
  mayoría de los directorios responden con éxito; `ldapdir` responde
  `ErrWrongPassword` sin conectarse.
- **Cualquier otro bind fallido tomado por una contraseña incorrecta.** Solo el
  resultado LDAP 49, *invalidCredentials*, es `ErrWrongPassword`. Una conexión cortada
  durante el bind, o un directorio que responde ocupado (51) o no disponible (52), se
  devuelve como `ldapdir: the directory did not answer the bind: …`, envolviendo el
  error LDAP. La contraseña se rechaza en ambos casos; lo que cambia es que el registro
  de un servidor ya no dice *wrong password* a alguien que la escribió bien. Antes de la
  v0.11.2, cada bind fallido era `ErrWrongPassword`.
- **Credenciales en una URL LDAP**: una URL se imprime; `BindDN` y `BindPassword` son
  campos.
- **Un hash NT que no tiene 16 bytes** (`ParseNTHash`), en lugar de rellenarlo hasta
  formar un hash que hace fallar cada inicio de sesión como contraseña incorrecta.
- **`Derive` o `KerberosKey` para una identidad sin la contraseña.** El sí de un
  verificador no es una clave.
- **Un atributo que es un secreto, o que un servidor responde por sí mismo**
  —[la lista de arriba]({{< relref "/libraries/directory.md#attributes" >}})—,
  dondequiera que se configure: en un bloque, como alias SQL o en la lista de
  ldapdir de lo que se copia.

{{< callout type="warning" >}}
**El hash NT y el secreto TOTP son credenciales, no hashes de una**

Quien tiene `sambaNTPassword` se autentica como esa persona exactamente igual que si
tuviera la contraseña; quien tiene un secreto TOTP produce todos los códigos futuros.
El error de `WithVerifier` va al servidor, nunca al cliente.
{{< /callout >}}

## Contra qué se comprueba {#what-it-is-checked-against}

- **El `ldapsearch` de OpenLDAP** lee el directorio de `ldaptest` —las entradas, el
  `sambaNTPassword` de la única persona que lo tiene, el grupo— y se rechaza con
  *Invalid credentials (49)* para una contraseña incorrecta. Las líneas Linux de la CI
  instalan `ldap-utils`; donde falta `ldapsearch`, la prueba se omite, ya que nada en
  la CI de este módulo convierte esa omisión en un fallo.
- **`ldapdir` contra `glauth/ldap`**, un servidor LDAP independiente, no una
  imitación; el banco de pruebas permite el bind no autenticado, así que la prueba
  falla si `ldapdir` deja de rechazarlo antes.
- **`sqldir` contra una base de datos SQLite real**, mediante un controlador real.
  Las consultas de atributos también se ejecutaron una vez a mano contra
  PostgreSQL 18.6 mediante pgx, no en la CI: un alias sin comillas volvió en
  minúsculas y se encontró de todos modos, uno entre comillas conservó su
  capitalización, y un alias que nombraba `userPassword` se rechazó.
- **Los filtros de ldapdir** contra `ldaptest`, que desde la v0.14.0 los aplica:
  el filtro de usuarios por defecto deja fuera un `inetOrgPerson` simple
  (`TestTheDefaultUserFilter`), y el filtro de grupos no añade ninguna identidad
  (`TestTheGroupFilterAddsNoIdentity`).
- **MD4** contra los vectores de prueba del RFC 1320.

La línea de cobertura falla por debajo del 85% (su norma declarada es el 100%), y las
compilaciones `nosql` y `noldap` se comprueban en la CI.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
