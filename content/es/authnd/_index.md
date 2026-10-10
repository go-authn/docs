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
Go puro, `CGO_ENABLED=0`, un solo binario. Estas páginas describen la v0.10.1, que
solo se diferencia de la v0.10.0 por el KDC que incorpora (go-authn/kdc v0.4.2);
lo que está verificado y lo que no figura en la página de [estado]({{< relref "/status.md" >}}).

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

Las personas se publican como `uid=<name>,ou=people,<base_dn>` (`posixAccount`),
y los grupos como `cn=<name>,ou=groups,<base_dn>` (`posixGroup`, con `memberUid`).
Cada entrada lleva `uid` y `cn`; `sambaNTPassword` y `sshPublicKey` se añaden
cuando la persona los tiene y, para el primero, cuando
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) lo indica.

`--config` (`-c`) admite un archivo o un directorio y puede repetirse; un directorio
equivale a todos los archivos `.hcl` que contiene, leídos por orden de nombre y
fusionados en una sola configuración. Una configuración sin `base_dn`, o sin nadie
dentro, no arranca.

## Quién puede hacer un bind, y quién puede leer {#who-may-bind-and-who-may-read}

A un servidor LDAP se le pide que pruebe quiénes son las personas, así que sus
rechazos son el diseño. Estas son las respuestas del binario de la versión v0.10.0
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
vendorName: go-authn/authnd
vendorVersion: v0.10.0
```

`1.3.6.1.4.1.4203.1.11.1` es la operación de modificación de contraseña del RFC 3062.
`supportedSASLMechanisms: OAUTHBEARER` solo aparece con un
[bloque `oidc`]({{< relref "/authnd/tokens.md" >}}).

## Por dónde seguir {#where-to-go-next}

| | |
|---|---|
| [Instalarlo]({{< relref "/authnd/install.md" >}}) | el binario de la versión, la cuenta `authnd`, la unidad systemd, las actualizaciones |
| [De dónde proceden las personas]({{< relref "/authnd/people.md" >}}) | bloques `user` y `group`, una base de datos SQL, otro directorio LDAP |
| [`check`]({{< relref "/authnd/check.md" >}}) | releer la configuración antes de reiniciar |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` o StartTLS, y `publish_nt_hash` |
| [Cambiar una contraseña]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, y por qué siempre se pide la contraseña anterior |
| [Un reino Kerberos]({{< relref "/authnd/kerberos.md" >}}) | la keytab, y a quién se le puede emitir un ticket |
| [Un segundo factor]({{< relref "/authnd/mfa.md" >}}) | un código de un solo uso al final de la contraseña |
| [Un token en el bind]({{< relref "/authnd/tokens.md" >}}) | OIDC sobre SASL `OAUTHBEARER` |
| [Ejecutarlo]({{< relref "/authnd/operations.md" >}}) | señales, reinicios, lo que registra, cómo saber que está en marcha |

{{< callout type="info" >}}
**Sobre las transcripciones**

Cada bloque de salida de estas páginas lo imprimió el binario de la versión v0.10.0
(`authnd-darwin-arm64`) —la v0.10.1 imprimió el mismo `check`, byte a byte, con las dos
configuraciones comparadas, y la línea `--version` de la página de instalación es la de la
v0.10.1—, junto con los clientes OpenLDAP y Heimdal que incluye
macOS, ejecutados en 127.0.0.1 en puertos sin privilegios, en un directorio temporal
bajo `/tmp`. Por eso las configuraciones que hay detrás nombran los archivos con rutas
relativas como `etc/authnd/passwords/alice.pw`, y por eso los archivos de contraseña
tienen nombres como `alice.pwin`. Las rutas `/etc/authnd` de los ejemplos son las que
usa un servidor instalado.
{{< /callout >}}
