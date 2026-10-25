---
title: "check, antes de reiniciar algo a través de lo cual inician sesión las personas"
linkTitle: "check"
weight: 30
description: "Qué abre authnd check, qué imprime sobre una configuración antes de servirla, cómo leerlo, y el único fallo que no puede ver."
tags: [authnd, check, configuración]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check` lee la configuración exactamente como lo hace el servidor, **abre todo lo
que el servidor abre antes de escuchar** —los archivos, la base de datos, el
directorio que hay detrás de este, el documento de descubrimiento del proveedor de
identidad, el certificado y la clave TLS, la keytab— e imprime lo que se publicaría
y para quién, **sin escuchar**. Imprime de dónde procede cada credencial y nunca lo
que contiene. Termina con 0 y acaba con *this configuration can be served*, o
termina con 1 con la única frase que detiene el servidor.

## Una configuración que se puede servir {#a-configuration-that-can-be-served}

Dos bloques `user`, un reader y una base de datos SQLite, en un directorio de dos
archivos (`authnd.hcl` y `people.hcl`):

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## Cómo leerlo {#reading-it}

La primera línea es el esquema, la dirección y la base: `ldap://`, `ldaps://` o
`ldap+starttls://`; consulte [TLS]({{< relref "/authnd/tls.md" >}}).

| columna | |
|---|---|
| `FROM` | el origen al que pertenece el nombre: *the configuration file*, *a sqlite database* (o postgres, mysql), o la URL de un directorio que hay detrás de este |
| `CAN PROVE` | *a password* (guardada, de modo que puede compararse y derivarse claves de ella), *a password check* (otro directorio responde sí o no), *an NT hash*, *N keys*, *a one-time-code secret*, o *nothing* |
| `PUBLISHED AS` | las clases de objeto de la entrada, sin `top`, tal como las dan [las formas]({{< relref "/authnd/entries.md#the-shapes" >}}), o *NOT PUBLISHED (see below)* para una entrada que no supera el esquema |
| `WITH` | los atributos que lleva la entrada, leídos de la entrada que devuelve una búsqueda: `uid`; `cn` allí donde una clase lo permite; lo que dieron los orígenes, menos lo descartado; `sshPublicKey` cuando hay claves; `sambaSID` y `sambaNTPassword` cuando [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) está activado y la persona tiene una clave NT y un SID |

La tabla de grupos también tiene una columna `PUBLISHED AS`: `posixGroup`,
`groupOfNames` u `organizationalRole`. Hasta la v0.10.2, `PUBLISHED AS` era la
lista de atributos, *uid and cn* para casi todo el mundo, y no había columna
`WITH`.

Las líneas que siguen a las tablas dicen lo que hay que saber antes de confiar en
la configuración. Primero, sobre [las entradas]({{< relref "/authnd/entries.md" >}}):

- **quién no es un `posixAccount`**, y cuáles de `uidNumber`, `gidNumber` y
  `homeDirectory` le faltan;
- **qué grupos no tienen `gidNumber`**, y como qué se publican en su lugar;
- **cada atributo descartado** porque ninguna clase de su entrada lo
  permite, y qué clases lo permitirían;
- **cada entrada no publicada**, con cada problema que encontró la
  comprobación del esquema;
- **quién tiene una clave NT y ningún `sambaSID`**, y por tanto ningún
  `sambaNTPassword`.

Desde la v0.12.0, entre la primera línea y las tablas, lo que añadió un
[esquema de un sitio]({{< relref "/authnd/schemas.md" >}}) y lo que declaran
los orígenes:

- **los archivos de esquema y los bloques `schema` cargados**, y lo que añade
  cada uno: `schema: etc/authnd/example.schema adds 3 object identifier macros, 2
  attribute types and 2 object classes`;
- **las clases que declara cada origen**: `users "sql" declares exampleStaff and
  exampleLockerHolder for its people`, con la posición de la declaración;
- **cada clase omitida en una persona o un grupo**, porque le falta un MUST de
  una clase que su origen declara: `ben is published without exampleStaff, which its
  source declares: ben has no exampleEmployeeId, which exampleStaff
  requires`, y, tras las líneas de los atributos, las que se llevó consigo;
- **un grupo para el que dos orígenes declaran clases distintas**: se publica
  la lista del primer origen y se ignora la del segundo.

Un archivo que no se construye, una redefinición, y una clase declarada que no
está definida, es STRUCTURAL o la deduce authnd detienen por igual `check` y el
servidor, con la posición del archivo o de la configuración.

Después, sobre binds y búsquedas:

- **qué lleva un bind**: *a password* o, con un [bloque `mfa`]({{< relref "/authnd/mfa.md" >}}),
  *a password with a 6-digit code after it*; con un [bloque `oidc`]({{< relref "/authnd/tokens.md" >}}),
  de dónde proceden los tokens y por qué medio;
- **quién no puede hacer un bind con contraseña en absoluto**: las personas conocidas
  solo por un hash NT; consulte [personas]({{< relref "/authnd/people.md#written-in-the-configuration" >}});
- **quién puede buscar**: los readers, o *no reader is declared: nothing may
  search, and binds are not affected*;
- **si se publica `sambaNTPassword`**, y por qué medio; consulte
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}});
- con un [bloque `kerberos`]({{< relref "/authnd/kerberos.md" >}}), el reino y
  **a quién se le puede y a quién no se le puede emitir un ticket**, con el motivo;
- con un bloque `mfa`, **quién no tiene segundo factor**, y por tanto no puede hacer
  un bind con contraseña; con un bloque `oidc` a su lado, la línea añade que un token
  cuyo `amr` nombra dos tipos sí puede;
- un **grupo que nombra a alguien que ningún origen tiene**.

Este último se publica tal cual —una fachada de un sistema lleva legítimamente
nombres que pertenecen a otro—, pero se dice, porque la otra lectura es una
errata. En un `posixGroup` el desconocido es un `memberUid`; en un
`groupOfNames` es un DN en `member` que no nombra ninguna entrada de aquí,
`member: uid=zoe,ou=people,dc=example,dc=org` en este caso, que el `ldapdir`
de go-authn/directory a partir de la v0.14.0 no asigna a nadie. Aquí la tabla `team_members` de la base de datos tiene una
fila para `zoe`, que aquí no es nadie:

```
GROUP      MEMBERS              PUBLISHED AS
engineers  dora, eli and zoe    groupOfNames
staff      alice, bob and dora  groupOfNames
[...]
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(Un *bloque* `group` que nombra a un desconocido se rechaza directamente; consulte
[personas]({{< relref "/authnd/people.md#written-in-the-configuration" >}}).)

## Lo que rechaza {#what-it-refuses}

Cada uno de estos casos detiene tanto `check` como el servidor, con el código de
salida 1. Están en las páginas a las que pertenecen; algunos, tal como se imprimen:

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## El certificado, la keytab, y lo único que no puede ver {#the-certificate-the-keytab-and-the-one-thing-it-cannot-see}

Un certificado que no se carga y una keytab sin `krbtgt/REALM` los rechaza `check`,
con las mismas palabras que usaría el servidor:

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

Lo que `check` no puede saber sin escuchar es **si los puertos están libres**. Un
segundo servidor en la misma dirección Kerberos pasa `check` y se rechaza al arrancar:

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## Ejecútelo como la cuenta de servicio {#run-it-as-the-service-account}

```sh
sudo -u authnd authnd check /etc/authnd
```

para que un archivo que solo root puede leer falle aquí y no en el reinicio. Ejecútelo
con el binario **nuevo** antes de una actualización; consulte [la instalación]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}).
