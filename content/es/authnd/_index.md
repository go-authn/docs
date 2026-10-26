---
title: "authnd, un servidor LDAP para personas que están en otro lugar"
linkTitle: "authnd"
weight: 10
description: "Un directorio LDAP, y opcionalmente un reino Kerberos, sobre personas guardadas en un archivo de configuración, una base de datos SQL u otro directorio."
tags: [authnd, ldap]
---

**Las personas de un sitio ya están en una base de datos, un archivo u otro
directorio. Lo que quiere autenticarlas habla LDAP.** authnd es la fachada:
hace binds y búsquedas sobre los orígenes de
[go-authn/directory]({{< relref "/libraries/_index.md" >}}), así que lo que guarda
una base de datos puede leerlo cualquier cosa que sepa consultar un directorio.
Go puro, `CGO_ENABLED=0`, un solo binario. Estas páginas describen la v0.12.3,
cuyas entradas siguen los esquemas estándar y superan el esquema que sirve en
`cn=Subschema`, que un sitio amplía con el suyo
([SUPANN, eduPerson]({{< relref "/authnd/schemas.md" >}})), con go-authn/ldap v0.10.1 y
go-authn/directory v0.15.0 por debajo; lo que está verificado y lo que no
figura en la página de [estado]({{< relref "/status.md" >}}).

{{< callout type="warning" >}}
**Actualizar desde la v0.11.x**

- ⛔ **Seguridad: use la v0.12.0, no la v0.11.1.** Los binarios de la versión
  v0.11.1 se compilaron con Go 1.27.2, cuyo crypto/x509 no deja de confiar en
  los certificados intermedios comprometidos que nombra GO-2026-6809, y authnd
  verifica certificados. La v0.12.0 se compila con Go 1.27.3, y su directiva
  `go` es 1.27.3, así que `go install` cambia por sí solo a la cadena de
  herramientas corregida.
- Una configuración que no usa las claves nuevas publica lo mismo que publicaba
  la v0.11.1: una clase se declara, nunca se deduce, así que sin
  `object_classes` nada cambia.
- Novedades, todas opcionales: [`schema_files` y un bloque `schema`]({{< relref "/authnd/schemas.md" >}})
  añaden las definiciones de un sitio al esquema servido, y `object_classes` y
  `group_object_classes` declaran las clases auxiliares que llevan las personas
  y los grupos de un origen. Una definición que redefine otra ya presente se
  rechaza, incluso palabra por palabra, como la rechaza slapd.
- `check` y el registro de arranque dicen qué archivos y bloques se cargaron,
  qué declara cada origen, qué clases se omitieron en una persona por falta de
  un MUST, y sobre qué grupos discrepan dos orígenes.

Ejecute `authnd check` con el nuevo binario antes del reinicio, como dice
[la instalación]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}).
{{< /callout >}}

{{< callout type="warning" >}}
**Actualizar desde la v0.10.x**

- `publish_nt_hash = true` necesita ahora un [bloque `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}),
  o authnd no arranca.
- Una persona sin `uidNumber`, `gidNumber` y `homeDirectory` ya no es un
  `posixAccount`, y un grupo sin `gidNumber` ya no es un `posixGroup`, así
  que un consumidor que filtra por esas clases ve menos entradas: consulte
  [las entradas]({{< relref "/authnd/entries.md" >}}).
- Un bloque `users "ldap"` lee por defecto más del directorio que tiene
  detrás: consulte [personas]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

`authnd check` con el nuevo binario dice las tres cosas antes del reinicio.
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## La configuración más pequeña {#the-smallest-configuration}

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

Las personas se publican como `uid=<name>,ou=people,<base_dn>`, y los grupos
como `cn=<name>,ou=groups,<base_dn>`. Lo que *es* cada entrada se deduce de
lo que dio su origen: una persona es un `account`, o un `inetOrgPerson`
cuando hay un `sn`, y un `posixAccount` solo con `uidNumber`, `gidNumber` y
`homeDirectory`; toda persona es un `uidObject`. Un grupo es un `posixGroup`
(con `memberUid`) cuando tiene un `gidNumber`, si no un `groupOfNames` (con
DN en `member`), o un `organizationalRole` cuando además está vacío.
`sshPublicKey` se añade cuando la persona tiene claves, y `sambaNTPassword`
cuando [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})
lo indica y se puede dar un SID. Cada entrada supera el esquema servido en
`cn=Subschema` antes de publicarse: consulte
[las entradas y el esquema]({{< relref "/authnd/entries.md" >}}). Hasta la
v0.10.2, toda persona era un `posixAccount` y todo grupo un `posixGroup`,
tuvieran lo que tuvieran.

`--config` (`-c`) admite un archivo o un directorio y puede repetirse; un directorio
equivale a todos los archivos `.hcl` que contiene, leídos por orden de nombre y
fusionados en una sola configuración. Una configuración sin `base_dn`, o sin nadie
dentro, no arranca.

## Quién puede hacer un bind, y quién puede leer {#who-may-bind-and-who-may-read}

A un servidor LDAP se le pide que pruebe quiénes son las personas, así que sus
rechazos son el diseño. Estas son las respuestas del binario de la versión v0.12.3
al propio cliente de OpenLDAP:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| petición | respuesta | por qué |
|---|---|---|
| nombre vacío, contraseña vacía (RFC 4513 §5.1.1, anónimo) | éxito | dice «no soy nadie», lo cual es cierto, y un cliente lo envía antes de haber descubierto nada |
| un **nombre** y una contraseña vacía (§5.1.2, no autenticado) | `unwillingToPerform` | nombra a alguien y no prueba nada; §5.1.2 pide exactamente este código. `invalidCredentials` le diría a la persona que su contraseña era incorrecta |
| una contraseña incorrecta, o un nombre que nadie tiene aquí | `invalidCredentials` | los dos casos no se distinguen |
| una búsqueda por cualquiera que no sea un `reader` | `insufficientAccessRights` | el bind prueba quién es usted; leer a todo el mundo es algo distinto que hay que permitir |
| `add`, `delete`, `modifyDN` | `unwillingToPerform` | no hay ningún manejador conectado para ellas; la única escritura es [la contraseña de la propia persona]({{< relref "/authnd/passwords.md" >}}) |

Un `reader` es una cuenta de servicio con un DN de bind y `password` o
`password_file`; un reader sin ninguno de los dos se rechaza al arrancar (*a reader that
proves nothing is anonymous search with extra steps*). Sin ningún
reader, nada puede buscar, y `check` lo dice.

El root DSE se responde a un cliente anónimo, como exige el descubrimiento:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.12.3
```

`1.3.6.1.4.1.4203.1.11.1` es la operación de modificación de contraseña del RFC 3062.
`subschemaSubentry` nombra el [esquema]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}),
que también se responde a un cliente anónimo.
`supportedSASLMechanisms: OAUTHBEARER` solo aparece con un
[bloque `oidc`]({{< relref "/authnd/tokens.md" >}}).

## Por dónde seguir {#where-to-go-next}

| | |
|---|---|
| [Instalarlo]({{< relref "/authnd/install.md" >}}) | el binario de la versión, la cuenta `authnd`, la unidad systemd, las actualizaciones |
| [De dónde proceden las personas]({{< relref "/authnd/people.md" >}}) | bloques `user` y `group`, una base de datos SQL, otro directorio LDAP |
| [Las entradas y el esquema]({{< relref "/authnd/entries.md" >}}) | como qué se publica cada persona y cada grupo, `cn=Subschema`, los atributos, lo que se descarta o se retiene |
| [Esquemas de un sitio]({{< relref "/authnd/schemas.md" >}}) | `schema_files`, el bloque `schema` y `object_classes`: SUPANN, eduPerson o los atributos propios de un sitio |
| [`check`]({{< relref "/authnd/check.md" >}}) | releer la configuración antes de reiniciar |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` o StartTLS, y `publish_nt_hash` |
| [Cambiar una contraseña]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, y por qué siempre se pide la contraseña anterior |
| [Un reino Kerberos]({{< relref "/authnd/kerberos.md" >}}) | la keytab, y a quién se le puede emitir un ticket |
| [Un segundo factor]({{< relref "/authnd/mfa.md" >}}) | un código de un solo uso al final de la contraseña |
| [Un token en el bind]({{< relref "/authnd/tokens.md" >}}) | OIDC sobre SASL `OAUTHBEARER` |
| [Ejecutarlo]({{< relref "/authnd/operations.md" >}}) | señales, reinicios, lo que registra, cómo saber que está en marcha |

{{< callout type="info" >}}
**Sobre las transcripciones**

Cada comando que se muestra en estas páginas se volvió a ejecutar el 26 de octubre de 2026 con los binarios publicados, no se reescribió a mano: `authnd` v0.12.3 (`authnd-darwin-arm64`, comprobado por `relverify` con `SHA256SUMS` y su atestación; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`), `authn-bridge` v0.23.4, `authn-revokd` v0.6.6, `sshcert-authorize` v0.1.9 y `ldapschema` v0.10.1. Lo que los comandos imprimieron es lo que figura aquí. Dos transcripciones son excepciones, y cada una lo dice donde aparece: el cliente `oidctool` de [la página de tokens]({{< relref "/authnd/tokens.md" >}}), un cliente de prueba escrito para estas páginas y que no forma parte de ninguna versión publicada, cuyas transcripciones y líneas del servidor las imprimió el binario de la versión v0.10.0; y los metadatos caducados de RENATER en [la página de la federación]({{< relref "/authn-bridge/federation.md" >}}), un archivo que ya no se publica. Todos los pidieron los clientes OpenLDAP y Heimdal que incluye macOS, en 127.0.0.1 en puertos sin privilegios, en un directorio temporal. Por eso las configuraciones que hay detrás nombran los archivos con rutas relativas como `etc/authnd/passwords/alice.pw`, y por eso los archivos de contraseña tienen nombres como `alice.pwin`. Las rutas `/etc/authnd` de los ejemplos son las que usa un servidor instalado.
{{< /callout >}}
