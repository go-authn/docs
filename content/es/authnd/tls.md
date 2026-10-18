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
ACME: los dos archivos los escribe otra cosa —
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}}), certbot, la CA propia
de un sitio—, y authnd se **reinicia** tras cada renovación, porque el
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
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

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
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
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
conocer nunca la contraseña. Por eso solo se publica cuando se pide y, desde la
v0.11.0, con el dominio al que pertenecen los SID de las personas:

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

Pedirlo se rechaza salvo que la escucha tenga TLS, o sea de loopback
(`127.0.0.0/8`, `::1`, `localhost`) y, por tanto, no esté en ninguna red:

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### El bloque `samba` {#the-samba-block}

`sambaNTPassword` pertenece a `sambaSamAccount` de Samba, cuyo MUST es `uid` y
`sambaSID`, y ninguna otra clase lo permite. Cada entrada que publica authnd
supera [el esquema que sirve]({{< relref "/authnd/entries.md" >}}), así que el
atributo solo se publica en un `sambaSamAccount`, y eso necesita un SID:

| clave | |
|---|---|
| `domain_sid` | obligatorio: el SID de dominio del servidor SMB, `S-1-5-21-…`, tal como lo imprime `net getlocalsid` |
| `algorithmic_rid_base` | opcional, `1000` por defecto, el de Samba. Un número impar, o uno por debajo de 1000, se rechaza: Samba usaría otro sin decir nada |

El `sambaSID` de una persona es su propio atributo `sambaSID` cuando un origen
le da uno ([atributos]({{< relref "/authnd/entries.md#adding-attributes" >}})).
Si no, es `domain_sid-RID`, con RID = 2 × `uidNumber` +
`algorithmic_rid_base`: la correspondencia algorítmica de Samba (smb.conf(5),
*algorithmic rid base*). Una persona con una clave NT y sin ninguno de los dos
se publica **sin** `sambaNTPassword`, y `check` y el registro de arranque dicen
quién. Las definiciones de Samba se añaden al esquema servido en
`cn=Subschema` solo cuando el bloque está presente; se escribieron a partir de
los OID, nombres y sintaxis que publica Samba, no se copiaron de su
`samba.schema` bajo GPL-3.0.

{{< callout type="error" >}}
**Incompatible con las configuraciones de la v0.10.x: `publish_nt_hash` sin un bloque `samba` no arranca**

La v0.10.x servía `publish_nt_hash = true` solo. Desde la v0.11.0 esa
configuración se rechaza al arrancar y en `check`, con lo que hay que añadir:

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

Ejecute `check` con el nuevo binario antes de actualizar. El rechazo es
deliberado: la entrada de la v0.10.x no puede superar el esquema, y las dos
alternativas silenciosas —descartar el atributo, lo que quita SMB a todo el
mundo, o descartar la entrada, lo que quita a la persona— ocurrirían ambas sin
nada en la consola.
{{< /callout >}}

Un bloque `samba` sin `publish_nt_hash` también se rechaza, ya que no
publicaría nada:

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### Lo que dice `check` {#what-check-says}

Tres personas en una escucha `ldaps://`: alice tiene una contraseña y el trío
POSIX, así que su SID se deriva (2 × 1000 + 1000); bob solo tiene un hash NT y
un `sambaSID` propio; carol tiene una contraseña y ninguno de los dos.

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

y, para la escucha StartTLS, *sambaNTPassword is published over TLS, once StartTLS
has been asked for*. alice no tiene ningún hash NT escrito; el suyo se deriva de su
contraseña. El hash de bob se publica para que lo use un servidor SMB, y `check`
dice también que bob no puede hacer un bind con el propio authnd. La entrada de
carol se publica sin el atributo, y un servidor SMB no puede servir a carol
hasta que un origen le dé un `uidNumber` o un `sambaSID`.

Lo que recibe un reader, por la escucha StartTLS de las mismas personas:

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

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
