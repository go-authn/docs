---
title: "TLS: ldaps:// o StartTLS, y no ambos a la vez"
linkTitle: "TLS"
weight: 40
description: "Servir LDAP sobre TLS con un certificado en archivos, la elección entre ldaps:// y StartTLS, y por qué sambaNTPassword solo se publica sobre uno de ellos."
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file` y `key_file` juntos activan TLS; uno sin el otro se rechaza (*one
without the other serves nothing*). TLS 1.2 es el mínimo. authnd no tiene cliente
ACME: lo que escriba los dos archivos —
[go-authn/servercert]({{< relref "/libraries/_index.md" >}}), certbot, la CA propia
de un sitio— los escribe, y authnd se **reinicia** tras cada renovación, porque el
certificado se lee una vez, cuando se abre la escucha.

## Dos formas, una escucha para cada una {#two-ways-one-listener-each}

| | `starttls` | la escucha | `check` dice |
|---|---|---|---|
| **ldaps://** | sin definir | el handshake TLS ocurre antes de que se intercambie un solo byte de LDAP | `ldaps://…` |
| **StartTLS** | `starttls = true` | sin cifrar, se actualiza cuando el cliente lo pide (RFC 4511 §4.14) | `ldap+starttls://…` |

Es una u otra, y tiene que serlo: una escucha no puede a la vez exigir un handshake
y esperar a ver si se le pide uno. Cuál quiere un sitio depende de sus
**clientes**: `ldaps://` en el 636 es para lo que la mayoría están configurados, y
StartTLS es lo que pedirá un cliente apuntado al 389 con «use TLS» marcado. Un sitio
que necesita ambas ejecuta dos instancias, cada una con su propio `--config`.
`starttls = true` sin certificado se rechaza:

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps:// {#ldaps}

El servidor, un certificado firmado por una CA para `127.0.0.1`, y la cadena
verificada por un cliente que no es este programa:

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 2 people from the configuration file

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS, que rechaza hasta que se le pide {#starttls-which-refuses-until-it-is-asked-for}

StartTLS lo solicita el **cliente**, así que el mero hecho de ofrecerlo no promete
nada: un cliente que nunca lo pide haría el bind sin cifrar. Por eso, una escucha
con `starttls = true` rechaza todo bind y toda búsqueda hasta que la conexión se ha
actualizado, con `confidentialityRequired`:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: posixAccount
uid: bob
cn: bob
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

(`-ZZ` es «StartTLS, y fallar si falla». `LDAPTLS_REQCERT=never` está ahí porque el
`ldapsearch` que incluye macOS confía en el almacén del sistema y no había forma de
indicarle que confiara en esta CA de prueba; la cadena se comprobó aparte con
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error`, que
respondió `Verify return code: 0 (ok)`.)

Ese rechazo es lo que convierte `cert_file` en una garantía en lugar de una oferta,
y es en lo que se apoya `publish_nt_hash`. Incluye el bind anónimo que envía
`ldapsearch -x` antes de leer el root DSE, así que en una escucha StartTLS esa
consulta de descubrimiento también necesita `-ZZ`.

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword` es lo que permite a Samba u otro servidor SMB autenticar a las
personas a través de este directorio, y **no** es un hash de contraseña en el
sentido en que lo entiende un formulario de inicio de sesión: quien posee
`MD4(UTF16LE(password))` se autentica como esa persona mediante NTLMv2 sin llegar a
conocer nunca la contraseña. Por eso solo se publica cuando se pide:

```hcl
publish_nt_hash = true
```

y pedirlo se rechaza salvo que la escucha tenga TLS, o sea de loopback
(`127.0.0.0/8`, `::1`, `localhost`) y, por tanto, no esté en ninguna red:

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

Con él, `check` nombra el atributo por persona y dice qué lo protege:

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid, cn and sambaNTPassword
bob    the configuration file  an NT hash  uid, cn and sambaNTPassword

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2

this configuration can be served
```

y, para la escucha StartTLS, *sambaNTPassword is published over TLS, once StartTLS
has been asked for*. alice no tiene ningún hash NT escrito; el suyo se deriva de su
contraseña. El hash de bob se publica para que lo use un servidor SMB, y `check`
dice también que bob no puede hacer un bind con el propio authnd.

Solo un [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})
puede buscar, así que solo un reader ve alguna vez el atributo. Quién puede leerlo
es, por tanto, la misma pregunta que quién tiene la contraseña de un reader.

{{< callout type="warning" >}}
**NTLMv2 necesita la contraseña o su MD4, y ninguna otra cosa sirve**

Un servidor de archivos que consulta a authnd sobre alguien solo puede servirle por
SMB si el *origen* guardaba lo suficiente para ello: una contraseña, o el hash. A una
persona que procede de un directorio que solo comprueba contraseñas —*a password
check* en `check`— nunca se le puede dar un `sambaNTPassword`, haga lo que haga
authnd entre medias. Sin `publish_nt_hash`, a nadie: `check` dice entonces
*sambaNTPassword is not published, so nothing here can authenticate an SMB
session*.
{{< /callout >}}

## Los tokens también lo necesitan {#tokens-need-it-too}

Un [bloque `oidc`]({{< relref "/authnd/tokens.md" >}}) rechaza un token en una
conexión que no está cifrada, salvo que `allow_plaintext = true` indique que TLS se
termina delante de este proceso.
