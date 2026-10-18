---
title: "Las entradas que publica authnd, y el esquema que sirve"
linkTitle: "Entradas y esquema"
weight: 25
description: "Como qué se publica cada persona y cada grupo, el esquema servido en cn=Subschema que supera cada entrada, cómo añadir atributos en un archivo o en una consulta SQL, y lo que se descarta o se retiene."
tags: [authnd, ldap, esquema, sql]
---

**Cada entrada que publica authnd supera el esquema que sirve.** Desde la
v0.11.0, cada persona y cada grupo es una entrada de esquema estándar,
construida a partir de lo que dio su origen y comprobada con
`schema.Validate` de go-authn/ldap contra el esquema que un cliente puede leer
en `cn=Subschema`, antes de que una búsqueda la devuelva nunca. Un cliente que
lee el esquema y se lo cree —un navegador LDAP, una herramienta de
sincronización, un directorio que replica este— ve lo que se le dijo. Hasta la
v0.10.2, toda persona era `top, person, posixAccount` sin ninguno de los
atributos que exigen esas clases, y `sambaNTPassword` estaba en una entrada sin
ninguna clase que lo permitiera.

{{< callout type="warning" >}}
**Un consumidor que filtra por `posixAccount` o `posixGroup` ve menos entradas**

Una persona sin `uidNumber`, `gidNumber` y `homeDirectory` ya no es un
`posixAccount`, y un grupo sin `gidNumber` ya no es un `posixGroup`. Un
programa que busca `(objectClass=posixAccount)` o `(objectClass=posixGroup)`
ya no los encuentra. Eso incluye el `ldapdir` de go-authn/directory hasta la
v0.13.0, y por tanto go-fileshare hasta que requiera directory v0.14.0, cuyos
valores por defecto también leen `account`, `uidObject` y `groupOfNames`
([directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})).
Dé esos atributos a las personas y a los grupos, o dirija el consumidor a
`(objectClass=uidObject)`, que lleva toda persona.
{{< /callout >}}

## Las formas {#the-shapes}

Se lista cada superclase, como pide el RFC 4512 §3.3.

| una persona con… | `objectClass` | `cn` |
|---|---|---|
| ningún `sn` | `top`, `account` (RFC 4524 §3.1) | solo cuando otra clase lo permite |
| `sn` | `top`, `person`, `organizationalPerson`, `inetOrgPerson` (RFC 4519, RFC 2798) | sí |
| … y `uidNumber`, `gidNumber`, `homeDirectory`, los tres | `+ posixAccount` (RFC 2307) | sí |
| … y claves SSH | `+ ldapPublicKey` (openssh-lpk), con `sshPublicKey` | |
| … y un hash NT publicado con un `sambaSID` | `+ sambaSamAccount` (Samba), con `sambaSID` y `sambaNTPassword`: consulte [el bloque `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}) | permitido |
| … siempre | `+ uidObject` (RFC 4519 §3.14), así que `(objectClass=uidObject)` encuentra a todo el mundo | |

| un grupo con… | `objectClass` | miembros |
|---|---|---|
| un `gidNumber` | `top`, `posixGroup` (RFC 2307) | `memberUid`, nombres |
| ningún `gidNumber`, alguien dentro | `top`, `groupOfNames` (RFC 4519 §3.5) | `member`, los DN que publica este servidor |
| ningún `gidNumber`, nadie dentro | `top`, `organizationalRole` (RFC 4519 §3.10) | ninguno |
| un `gidNumber`, nadie dentro | `top`, `posixGroup` | ninguno: un atributo tiene al menos un valor |

`uid` es el nombre de la persona, y también lo es `cn` allí donde una clase lo
permite. Un `account` solo no permite `cn` (su MAY es `description`,
`seeAlso`, `l`, `o`, `ou` y `host`), así que una persona sin `sn` y sin el trío
POSIX lleva `uid` y ningún `cn`.

Por qué estas elecciones, según las razones del propio authnd:

- **`posixGroup` sigue el RFC 2307, no draft-howard-rfc2307bis-02.** El
  borrador hace AUXILIARY a `posixGroup` y caducó sin publicarse; un
  `posixGroup` AUXILIARY necesitaría una clase estructural a su lado,
  `groupOfNames`, cuyo `member` no puede dar un grupo vacío.
- **`organizationalRole` para un grupo vacío sin `gidNumber`.**
  `groupOfNames` y `groupOfUniqueNames` exigen ambos un miembro, y las formas
  de inventarse uno son falsas: `member: ""` nombra el root DSE, y el propio
  DN del grupo lo hace miembro de sí mismo. `organizationalRole` es la única
  clase estructural estándar cuyo único MUST es `cn`, y admite `description`,
  `ou` y `seeAlso` como `groupOfNames`.
- **Clases auxiliares sin reglas de contenido DIT.** El RFC 4512 §2.4.3
  prohíbe las clases auxiliares en una entrada cuya clase estructural no tiene
  regla de contenido DIT. Todos los servidores de directorio en uso las
  permiten, y `Validate` también.

## Añadir atributos {#adding-attributes}

Lo que un origen dice de alguien y no prueba nada —un `uidNumber`, un
directorio personal, una dirección de correo— es un **atributo**, publicado tal
como se da. Son los [atributos]({{< relref "/libraries/directory.md#attributes" >}})
de go-authn/directory, desde la v0.13.0, y se mantienen aparte de las
credenciales: un nombre que guarda un secreto, o uno que el servidor deriva por
sí mismo, se rechaza antes de leer nada.

### En un bloque `user` o `group` {#in-a-user-or-group-block}

```hcl
user "dora" {
  password_file   = "/etc/authnd/passwords/dora.pw"
  authorized_keys = ["ssh-ed25519 AAAA… dora@laptop"]
  attributes = {
    sn            = "Explorer"          # inetOrgPerson
    uidNumber     = "1000"              # the three: posixAccount
    gidNumber     = "1000"
    homeDirectory = "/home/dora"
    mail          = ["dora@example.org", "d.explorer@example.org"]
  }
}

group "engineers" {
  members    = ["dora", "eli"]
  attributes = { gidNumber = "2000" }   # a posixGroup; without it, a groupOfNames
}
```

Un valor es una cadena o una lista de cadenas; `null` omite el atributo. Un
número se rechaza, porque un valor LDAP es una cadena y authnd no elige cómo se
escribe un número:

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

Se rechazan igual, sea cual sea su capitalización: cualquier nombre que guarde
un secreto (`userPassword`, `sambaNTPassword`, `unicodePwd`, `krbPrincipalKey`
y el resto de la lista de go-authn/directory, o cualquier nombre que contenga
`password`, `passwd`, `pwd`, `secret`, `credential`, `hash` o `privatekey`);
`sshPublicKey`, que tiene `authorized_keys`; `uid`, `cn` y `objectClass`, que
deriva el servidor; `member`, `memberUid` y los demás atributos de
pertenencia, a los que responde `members`; los atributos operativos que
mantiene un servidor; y un nombre en forma numérica (`2.5.4.35` es
`userPassword`).

### En una base de datos SQL {#in-a-sql-database}

Dos consultas opcionales de un bloque `users "sql"` leen atributos **por alias
de columna**. La primera columna es el nombre de la persona o del grupo; cada
una de las demás columnas es un atributo nombrado por su alias:

```hcl
users "sql" {
  driver   = "sqlite"
  dsn_file = "/etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

- Las consultas posicionales `users` y `groups` no cambian, y una sexta
  columna posicional se sigue rechazando: los atributos llegan por nombre, en
  su propia consulta.
- Una columna cuyo alias no es una descripción de atributo (una expresión sin
  alias como `count(*)`), o nombra una credencial, se rechaza con su número de
  columna antes de leer una sola fila.
- `NULL` y `''` son ausencia. Un nombre puede volver en varias filas, y se
  conservan los valores de todas ellas, así que un join con una tabla de
  direcciones le da varias a una persona.
- Un grupo nombrado solo en `groups_attributes` **existe**, sin nadie dentro:
  así se escribe el grupo principal propio de una persona.

{{< callout type="warning" >}}
**La capitalización de un alias es la de la base de datos**

PostgreSQL pasa a minúsculas un alias sin comillas: `as uidNumber` vuelve como
`uidnumber`. Los nombres de atributo no distinguen mayúsculas de minúsculas,
así que es el mismo atributo y la entrada es la misma entrada para cualquier
cliente LDAP, pero la grafía que imprime authnd es la de la base de datos.
Ponga el alias entre comillas cuando la grafía importe: `gid as "gidNumber"`.
SQLite conserva un alias tal como se escribe.
{{< /callout >}}

### Desde otro directorio LDAP {#from-another-ldap-directory}

Un bloque `users "ldap"` copia los atributos que se le indican, de la entrada
de cada persona y de la de cada grupo: `attributes = ["mail", "uidNumber",
"homeDirectory"]` y `group_attributes = ["gidNumber"]`. Consulte
[personas]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

## Una configuración, y lo que publica {#a-configuration-and-what-it-publishes}

El bloque SQL de arriba, con un reader, sobre una base de datos SQLite de cinco
personas y cuatro grupos, tal como lo comprueba el binario de la versión
v0.11.0:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER  FROM               CAN PROVE             PUBLISHED AS                                                                         WITH
dora  a sqlite database  a password and 1 key  person, organizationalPerson, inetOrgPerson, posixAccount, ldapPublicKey, uidObject  uid, cn, sn, uidNumber, gidNumber, homeDirectory, mail and sshPublicKey
eli   a sqlite database  a password            account, posixAccount, uidObject                                                     uid, cn, uidNumber, gidNumber and homeDirectory
fay   a sqlite database  a password            person, organizationalPerson, inetOrgPerson, uidObject                               uid, cn, sn and mail
gus   a sqlite database  a password            account, uidObject                                                                   uid
hal   a sqlite database  a password            account, uidObject                                                                   uid

GROUP       MEMBERS       PUBLISHED AS
alumni      nobody        organizationalRole
engineers   dora and eli  posixGroup
nobody-yet  nobody        posixGroup
readers     fay and gus   groupOfNames

fay has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
gus has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
hal has no homeDirectory: not a posixAccount, published as account, uidObject
hal is published without uidNumber: no class of the entry allows it; posixAccount would
hal is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
hal is published without mail: no class of the entry allows it; inetOrgPerson would
group alumni has no gidNumber and nobody in it: not a posixGroup, published as an organizationalRole (a groupOfNames needs a member)
group readers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

`PUBLISHED AS` son las clases de objeto de cada entrada, sin `top`, y `WITH`
sus atributos, leídos de las entradas que devuelve una búsqueda. hal tiene un
`uidNumber`, un `gidNumber` y un `mail`, y ningún `homeDirectory` ni `sn`: hal
es un `account`, que no permite ninguno de los tres, así que se descartan y se
publica el resto. El servidor dice lo mismo al arrancar (y `stopping` cuando se
detuvo):

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

Releído con el `ldapsearch` de OpenLDAP, con la contraseña del reader en un
archivo:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(|(uid=dora)(uid=eli)(uid=gus)(uid=hal))'
dn: uid=dora,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: ldapPublicKey
objectClass: uidObject
uid: dora
cn: dora
sn: Explorer
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/dora
mail: dora@example.org
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTfVR7FqXWE/0VEcjrUhK+Fz/MLqlwGPIxalr6onRMn dora@laptop

dn: uid=eli,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: uidObject
uid: eli
cn: eli
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/eli

dn: uid=gus,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: gus

dn: uid=hal,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: hal

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=groups,dc=example,dc=org '(objectClass=*)'
dn: cn=alumni,ou=groups,dc=example,dc=org
objectClass: top
objectClass: organizationalRole
cn: alumni
description: people who were here

dn: cn=engineers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: engineers
gidNumber: 2000
memberUid: dora
memberUid: eli

dn: cn=nobody-yet,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: nobody-yet
gidNumber: 2001

dn: cn=readers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
cn: readers
description: people who read
member: uid=fay,ou=people,dc=example,dc=org
member: uid=gus,ou=people,dc=example,dc=org
```

`alumni` solo se nombra en `groups_attributes`, así que existe sin nadie
dentro; sin `gidNumber` es un `organizationalRole`. `nobody-yet` tiene un
`gidNumber` y a nadie, así que es un `posixGroup` sin `memberUid`.

Qué clase encuentra a quién:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=uidObject)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org

dn: uid=fay,ou=people,dc=example,dc=org

dn: uid=gus,ou=people,dc=example,dc=org

dn: uid=hal,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=posixAccount)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org
```

## Lo que se descarta y lo que se retiene {#what-is-dropped-and-what-is-withheld}

| dado | la entrada | por qué |
|---|---|---|
| `uidNumber`, `gidNumber`, sin `homeDirectory`, sin `sn` | `account, uidObject`, sin los dos | *no class of the entry allows it; posixAccount would* |
| `mail`, sin `sn` | `account, uidObject`, sin él | *no class of the entry allows it; inetOrgPerson would* |
| un tipo que el esquema no define | el resto | *the schema served here does not define it* |
| `mail` en un grupo sin `gidNumber` | `groupOfNames`, sin él | |
| dos valores de `homeDirectory` con el trío POSIX | **retenida**: SINGLE-VALUE, nada que descartar | |
| un `gidNumber` que no es un entero | **retenida**: no es de su sintaxis | |

**Solo se descarta lo que dio un origen**, y qué atributo no está permitido es
la respuesta de `Validate`, no una segunda lectura del esquema. La entrada se
valida de nuevo tras el descarte. Una entrada que sigue fallando se
**retiene**: no aparece en ninguna búsqueda, el registro de arranque la
nombra, y `check` la lista con cada problema que encontró `Validate`. Un
atributo que authnd deriva por sí mismo (`uid`, `cn`, `objectClass`,
`sshPublicKey`, `sambaSID`, `sambaNTPassword`) y que el esquema rechazara sería
un defecto de authnd, y retiene la entrada en lugar de publicarla sin él.

Aquí el `gidNumber` de alice es una palabra:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes = {
    uidNumber     = "1000"
    gidNumber     = "staff"
    homeDirectory = "/home/alice"
  }
}

user "bob" { password_file = "etc/authnd/bob.pw" }
```

```
$ authnd check cases/withheld.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS               WITH
alice  the configuration file  a password  NOT PUBLISHED (see below)  uid, cn, gidNumber, homeDirectory and uidNumber
bob    the configuration file  a password  account, uidObject         uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
alice is NOT published: as account, posixAccount, uidObject it fails the schema:
  - the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Una vez servida, alice sigue pudiendo hacer un bind y no aparece en ninguna
búsqueda, y el servidor dice por qué al arrancar:

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

Lo que se retiene es la entrada que devuelve una búsqueda, no la identidad.

## El esquema que sirve {#the-schema-it-serves}

El root DSE lo nombra (`subschemaSubentry: cn=Subschema`, en
[el root DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})),
y una búsqueda de base sobre `cn=Subschema` lo devuelve (RFC 4512 §4.2): las
definiciones estándar que incorpora go-authn/ldap —RFC 4512, 4517, 4519, 4523,
4524, 2798, 2307, 3672 y 3045, y openssh-lpk—, más `sambaSamAccount`,
`sambaSID` y `sambaNTPassword` de Samba cuando hay un
[bloque `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}). Las
definiciones solo se publican cuando se piden por nombre o con `+`. Recortado
donde se indica:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -s base -b cn=Subschema '+' '*'
dn: cn=Subschema
objectClass: top
objectClass: subentry
objectClass: subschema
cn: Subschema
subtreeSpecification: {}
ldapSyntaxes: ( 1.3.6.1.4.1.1466.115.121.1.3 DESC 'Attribute Type Description' )
[...]
matchingRules: ( 2.5.13.15 NAME 'integerOrderingMatch' SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 )
[...]
attributeTypes: ( 1.3.6.1.1.1.1.0 NAME 'uidNumber' DESC 'An integer uniquely identifying a user in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
attributeTypes: ( 1.3.6.1.1.1.1.1 NAME 'gidNumber' DESC 'An integer uniquely identifying a group in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
[...]
objectClasses: ( 2.5.6.9 NAME 'groupOfNames' SUP top STRUCTURAL MUST ( member $ cn ) MAY ( businessCategory $ seeAlso $ owner $ ou $ o $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.3.1 NAME 'uidObject' SUP top AUXILIARY MUST uid )
objectClasses: ( 0.9.2342.19200300.100.4.5 NAME 'account' SUP top STRUCTURAL MUST uid MAY ( description $ seeAlso $ l $ o $ ou $ host ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.0 NAME 'posixAccount' DESC 'Abstraction of an account with POSIX attributes' SUP top AUXILIARY MUST ( cn $ uid $ uidNumber $ gidNumber $ homeDirectory ) MAY ( userPassword $ loginShell $ gecos $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.2 NAME 'posixGroup' DESC 'Abstraction of a group of accounts' SUP top STRUCTURAL MUST ( cn $ gidNumber ) MAY ( userPassword $ memberUid $ description ) )
[...]
```

La entrada completa tenía 327 líneas: 49 sintaxis, 40 reglas de comparación,
36 usos de reglas de comparación, 143 tipos de atributo y 52 clases de objeto.
A diferencia de una búsqueda bajo la base, la entrada de subesquema, como el
root DSE, se responde a un cliente anónimo: la misma consulta sin `-D` ni `-y`
la devolvió.

**Los filtros usan las reglas de comparación del esquema**, así que
`(uidNumber>=1000)` compara enteros. `uidNumber` y `gidNumber` tienen
`ORDERING integerOrderingMatch`, que el RFC 2307 no les da; slapd y
draft-howard-rfc2307bis-02 sí, y go-authn/ldap también
([su única desviación]({{< relref "/libraries/ldap.md#the-schema" >}})).
Como cadenas, `1000` se ordena antes que `999`:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=1000)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=999)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001
```

hal no está: el `uidNumber` de hal se descartó. Un rango sobre un atributo sin
regla ORDERING, como `uid`, es Undefined y no encuentra nada.
