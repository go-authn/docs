---
title: "check, antes de reiniciar algo a través de lo cual inician sesión las personas"
linkTitle: "check"
weight: 30
description: "Qué abre authnd check, qué imprime sobre una configuración antes de servirla, cómo leerlo, y el único fallo que no puede ver."
tags: [authnd, check, configuration]
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

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid and cn
bob    the configuration file  an NT hash  uid and cn
dora   a sqlite database       a password  uid and cn
eli    a sqlite database       an NT hash  uid and cn

GROUP      MEMBERS
engineers  dora and eli
staff      alice, bob and dora

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
| `PUBLISHED AS` | los atributos que lleva la entrada: siempre `uid` y `cn`; `sambaNTPassword` cuando `publish_nt_hash` está activado y la persona tiene uno o una contraseña de la que puede derivarse; `sshPublicKey` cuando hay claves |

Las líneas que siguen a las tablas dicen lo que hay que saber antes de confiar en
la configuración:

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

Este último se publica tal cual —`memberUid` es una cadena, y una fachada de un
sistema lleva legítimamente nombres que pertenecen a otro—, pero se dice, porque la
otra lectura es una errata. Aquí la tabla `team_members` de la base de datos tiene una
fila para `zoe`, que aquí no es nadie:

```
GROUP      MEMBERS
engineers  dora, eli and zoe
staff      alice, bob and dora
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
