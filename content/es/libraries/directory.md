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
go get github.com/go-authn/directory@v0.11.2
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

	// @group is expanded; an empty group, or one nobody has, is an error.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	fmt.Println(directory.Expand([]string{"@nobody"}, people))
	fmt.Println(directory.Expand([]string{"@admins"}, people))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[dora eli svc-backup] <nil>
[] directory: group "nobody" has no members: nobody would be allowed
[] directory: no such group: "nobody"
[] directory: no such group: "admins", in the configuration file
```

Una contraseña guardada también responde a `Can(Verifier)`: se puede comparar.

{{< callout type="info" >}}
**Un grupo vacío, consultado a través de un `Set`, se notifica como inexistente**

`Expand` rechaza un grupo vacío con *has no members*, como muestra la antepenúltima
línea para el propio `Static`. A través de un `Set`, `Set.Members` devuelve
`ErrNoSuchGroup` para un grupo que un origen tiene pero en el que no hay nadie
(`source.go:138`), así que el mensaje nombra la causa equivocada. El grupo se rechaza
en ambos casos.
{{< /callout >}}

## Lo que rechaza, y por qué {#what-it-refuses-and-why}

- **Un grupo en el que no hay nadie**, y **un grupo que ningún origen tiene**: errores,
  no listas vacías: una configuración que no concede nada a nadie se lee exactamente
  igual que una que funciona. Un origen que está *averiado* se notifica aparte de uno
  al que le falta el grupo.
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
- **MD4** contra los vectores de prueba del RFC 1320.

La línea de cobertura falla por debajo del 85% (su norma declarada es el 100%), y las
compilaciones `nosql` y `noldap` se comprueban en la CI.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.11.2](https://pkg.go.dev/github.com/go-authn/directory@v0.11.2)
