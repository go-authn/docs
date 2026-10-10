---
title: "De dónde proceden las personas"
linkTitle: "Personas"
weight: 20
description: "Bloques user y group, una base de datos SQL, otro directorio LDAP: cómo se escribe cada uno, en qué orden se consultan y qué permite hacer cada uno a una persona."
tags: [authnd, configuration, sql, ldap]
---

Un bloque `user` es el directorio entero de un sitio pequeño, o las cuentas de
servicio que uno grande mantiene fuera de su base de datos. Un sitio cuyas personas
ya están en una base de datos o en LDAP no debería copiarlas a un segundo lugar que
se quede desfasado, así que un bloque `users` las lee donde están. El bloque `users`
es el `hcldir` de go-authn/directory, el mismo que lee
[go-fileshare](https://github.com/go-fileshare/fileshare): un mismo directorio se
describe igual para ambos.

## Escritas en la configuración {#written-in-the-configuration}

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| campo | qué es |
|---|---|
| `password` | la contraseña, en línea |
| `password_file` | lo mismo, leído de un archivo (sin los espacios en blanco del principio y del final) |
| `nt_hash` | `MD4(UTF16LE(password))`, 32 caracteres hexadecimales, para un sitio que guarda eso y no la contraseña |
| `totp_secret` | un secreto de código de un solo uso en base32, de al menos 128 bits; consulte [un segundo factor]({{< relref "/authnd/mfa.md" >}}) |
| `authorized_keys` | líneas de `authorized_keys`, publicadas como `sshPublicKey` |
| `authorized_keys_file` | lo mismo, a partir de un archivo |

Se rechaza al arrancar, nombrando a la persona:

- `password` y `password_file` juntos: indique cuál;
- `password` y `nt_hash` juntos: el hash se deriva de la contraseña, así que los
  dos pueden no coincidir;
- `authorized_keys` y `authorized_keys_file` juntos;
- un `nt_hash` que no tiene 32 caracteres hexadecimales, una línea de
  `authorized_keys` que no se puede analizar, un `totp_secret` de menos de 128 bits;
- el mismo `user` o `group` dos veces, y un `group` sin miembros.

Un miembro de grupo que ningún origen conoce también se rechaza, lo que detecta una
errata antes de que, sin decir nada, no conceda nada:

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**Un `nt_hash` solo no puede hacer un bind**

Una persona escrita solo con `nt_hash` se publica, puede entregarse a un servidor
SMB mediante `sambaNTPassword`, y **no puede hacer un bind con el propio authnd**:
un bind simple de LDAP envía la contraseña, y un hash NT no es aquí una forma de
comprobarla. bob, más abajo, solo tiene un hash NT, y el hash es el de la contraseña
enviada:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check` lo dice, después de las tablas:

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```
{{< /callout >}}

## En una base de datos SQL {#in-a-sql-database}

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**Las consultas las escribe usted**, porque las personas de un sitio ya tienen la
forma de ese sitio. Las columnas de la consulta `users` se leen **por posición**: un
nombre y, después, cualquiera de una contraseña, un hash NT, claves SSH (una por
línea) y un secreto de código de un solo uso, en ese orden, hasta cinco columnas. Un
NULL es una credencial que esa persona no tiene. Una columna de contraseña se compara
tal como está guardada: authnd no tiene ningún ajuste para una columna con hash. La
consulta `groups` devuelve un nombre de grupo y un miembro, una fila por pertenencia.

`driver` acepta `postgres` (o `postgresql`, `pgx`), `mysql` (o `mariadb`) y `sqlite`
(o `sqlite3`). La base de datos se contacta al arrancar, antes de que nada escuche,
así que una que no responde detiene el servidor allí donde alguien está mirando:

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

PostgreSQL en la misma máquina, a través de su socket y de la autenticación peer,
no necesita ninguna contraseña en el DSN: `host=/run/postgresql dbname=authnd user=authnd`.
SQLite en el directorio de estado: `file:/var/lib/authnd/people.db`.

Una clave que pertenece a la otra clase de bloque se rechaza en lugar de ignorarse:

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## En otro directorio LDAP {#in-another-ldap-directory}

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url` y `base_dn` son obligatorios. Dónde están las personas y los grupos, y qué
atributos los nombran:

| clave | por defecto |
|---|---|
| `user_filter` | `(objectClass=posixAccount)` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(objectClass=posixGroup)` |
| `group_attribute` | `cn` |
| `group_member_attribute` | `memberUid` |
| `totp_attribute` | ninguno: no hay ningún atributo estándar, y uno adivinado no leería nada aparentando haber buscado |
| `start_tls` | `false` |

`sambaNTPassword` y `sshPublicKey` se leen con esos nombres. Dos cosas se rechazan
antes de abrir nada:

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

`ldap://` hacia una dirección de loopback y `ldapi://` se aceptan: no hay nadie en
medio.

Un directorio detrás de este **comprueba** las contraseñas haciendo un bind contra
él; no las entrega. Aquí un authnd hace de fachada de otro, bajo una base distinta:

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS
alice       ldap://127.0.0.1:3893   a password check  uid and cn
bob         ldap://127.0.0.1:3893   a password check  uid and cn
dora        ldap://127.0.0.1:3893   a password check  uid and cn
eli         ldap://127.0.0.1:3893   a password check  uid and cn
svc-backup  the configuration file  a password        uid and cn

GROUP      MEMBERS
engineers  dora and eli
staff      alice, bob and dora

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

*A password check* basta para un bind, y nunca basta para un
[ticket Kerberos]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})
ni para SMB.

## El orden, y la única excepción {#order-and-the-one-exception}

Los orígenes se consultan **en el orden en que están escritos**, y el primero que
conoce un nombre se queda con él. Los bloques `user` siempre van primero, de modo que
una cuenta de servicio escrita localmente no la anula alguien con el mismo nombre en
la base de datos. **La pertenencia a grupos es la unión** de todos los orígenes:
un grupo que nombran a la vez un bloque `group` y la consulta `groups` de una base de
datos tiene los miembros de ambos.

{{< callout type="warning" >}}
**Dos nombres que solo difieren en mayúsculas y minúsculas se rechazan**

Un uid se compara sin distinguir mayúsculas de minúsculas (RFC 4519 §2.39), y lo
mismo ocurre con cada DN, así que `Dora` en el archivo y `dora` en una base de datos
son un solo nombre para LDAP y dos personas para todo lo que compara bytes: un cambio
de contraseña de una acabaría en la otra. Una configuración así no arranca:

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## Se leen una vez {#read-once}

Cada origen se lee **una vez, al arrancar**. Una persona añadida a la base de datos,
o una pertenencia modificada en el directorio que hay detrás de este, se sirve tras
un reinicio, no antes. Eso incluye una columna de contraseña en una base de datos: se
lee con el resto de la fila. Un directorio detrás de este solo se diferencia en que
un bind se comprueba haciendo un bind contra él, así que la contraseña que funciona
es la cambiada *allí*. La otra excepción es una contraseña que una persona cambia a
través del propio authnd, que se [aplica al instante]({{< relref "/authnd/passwords.md" >}}).
No hay recarga; consulte [ejecutarlo]({{< relref "/authnd/operations.md" >}}).
