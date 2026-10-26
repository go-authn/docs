---
title: "Esquemas de un sitio, y las clases que declara un origen"
linkTitle: "Esquemas de un sitio"
weight: 27
description: "Sirva SUPANN, eduPerson o los atributos propios de un sitio: schema_files y el bloque schema añaden definiciones, object_classes declara qué clases auxiliares llevan las personas y los grupos de un origen, y check dice qué se omitió."
tags: [authnd, ldap, esquema, configuración]
---

**Un atributo SUPANN o eduPerson se descarta salvo que lo permita una clase de
su entrada.** authnd publica solo lo que permite el esquema que sirve (consulte
[las entradas]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})),
y el esquema estándar no sabe nada de `supannEtablissement` ni de
`eduPersonAffiliation`. Desde la v0.12.0 un sitio dice tres cosas, en este orden:

1. **qué definiciones añadir**: `schema_files`, los archivos que su slapd ya
   carga, y un bloque `schema { }` para lo que es solo local;
2. **qué clases auxiliares llevan sus personas y sus grupos**: `object_classes`;
3. nada más. Una clase se **declara, nunca se deduce**: que aparezca un atributo
   en una base de datos no cambia como qué se publica una entrada.

{{< callout type="info" >}}
**El ejemplo de esta página es un ejemplo**

`example.schema`, más abajo, se escribió para esta página. Sus OID cuelgan de
`1.3.6.1.4.1.99999`, un arco que no está asignado a nadie: use los suyos, y no
copie nunca estos. Para SUPANN, consulte [el final de la página](#supann).
{{< /callout >}}

## Un ejemplo: un esquema, una base de datos, una configuración {#an-example}

Un esquema en la forma `.schema` de OpenLDAP: una clase que un origen puede
declarar (`exampleStaff`, AUXILIARY, con un MUST), y una que no puede
(`exampleUnit`, STRUCTURAL).

```
objectidentifier exampleRoot  1.3.6.1.4.1.99999
objectidentifier exampleAttr  exampleRoot:1
objectidentifier exampleClass exampleRoot:2

attributetype ( exampleAttr:1 NAME 'exampleBadge'
	DESC 'the number on a badge'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

attributetype ( exampleAttr:2 NAME 'exampleEmployeeId'
	DESC 'a staff number'
	EQUALITY caseExactMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

# AUXILIARY: it can be declared. exampleStaff has a MUST.
objectclass ( exampleClass:1 NAME 'exampleStaff' SUP top AUXILIARY
	DESC 'somebody employed: has a staff number'
	MUST exampleEmployeeId
	MAY exampleBadge )

# STRUCTURAL: it cannot be declared (an entry has one structural chain).
objectclass ( exampleClass:2 NAME 'exampleUnit' SUP top STRUCTURAL
	MUST cn )
```

Una base de datos SQLite con tres personas, con `sn`, una insignia y un número
de empleado (`sqlite3 var/people.db < people.sql`):

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

Y la configuración:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

# Files first, then the blocks: a definition may use anything before it.
schema_files = ["etc/authnd/example.schema"]

schema {
  attribute_type "exampleLocker" {
    oid    = "1.3.6.1.4.1.99999.1.3"
    syntax = "1.3.6.1.4.1.1466.115.121.1.15"
  }
  object_class "exampleLockerHolder" {
    oid  = "1.3.6.1.4.1.99999.2.3"
    kind = "auxiliary"
    may  = ["exampleLocker"]
  }
}

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret from staff"
  users_attributes = "select login, sn, badge as exampleBadge, empid as exampleEmployeeId, locker as exampleLocker from person_attrs"
  object_classes   = ["exampleStaff", "exampleLockerHolder"]   # declared, never inferred
}
```

Sin la línea `object_classes`, `check` dice qué hace el esquema estándar por sí
solo con las mismas personas: los atributos se descartan, y cada línea nombra
la clase que lo habría conservado.

```
$ authnd check cases/nodecl.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes

USER  FROM               CAN PROVE   PUBLISHED AS                                            WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ann is published without exampleBadge: no class of the entry allows it; exampleStaff would
ann is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
cat is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## `schema_files` {#schema-files}

`schema_files` es una lista de archivos `.schema` de OpenLDAP o de archivos LDIF
de cn=config. Se cargan **tal como se publican**, por orden, sobre el esquema
estándar (y las tres definiciones de Samba, con el [bloque `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}})), con los
[lectores compatibles con slapd]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})
de go-authn/ldap: términos en cualquier orden, continuaciones de slapd y del
RFC 2849, base64, prefijos de longitud `{N}` y macros `objectidentifier`, que un
archivo puede definir y el siguiente usar, como a través del `include` de slapd.
No se convierte nada de antemano, de modo que el archivo que carga el slapd de
un sitio es el archivo que carga authnd. Las definiciones se sirven en
`cn=Subschema`.

- Una ruta relativa es relativa al directorio de trabajo, como todas las demás
  rutas de la configuración. Use rutas absolutas en un servicio: el directorio
  de trabajo de una unidad systemd es `/`.
- Cada archivo debe ser un archivo regular de como máximo 4 MiB, y se lee una
  sola vez, al arrancar.
- Los archivos deciden qué puede contener cada entrada. No son secretos, pero
  guárdelos con el resto de la configuración: `root:authnd`, modo `0640`, en un
  directorio donde solo escribe root ([instalación]({{< relref "/authnd/install.md" >}})).
- Un archivo que no se construye rechaza el arranque, y `check`, con el
  archivo, la línea y la columna donde empieza la definición, y el tipo de
  rechazo al final del mensaje: una superclase, un atributo, una regla de
  comparación o una sintaxis desconocidos (`unknown reference`), una clase
  estructural derivada de una auxiliar (`kind violation`), un OID o un nombre
  definidos dos veces (`duplicate OID`, `duplicate name`). Desde la v0.12.1 el
  lugar y el tipo vienen del
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}})
  tipado de go-authn/ldap, no de la lectura de su mensaje. Una definición leída
  de un archivo empieza en la columna 1, también cuando su texto está plegado en
  varias líneas. Un duplicado dice dónde está su primera definición, y una
  redefinición dice qué archivo estándar, o qué línea de un archivo anterior,
  contiene el original. Dos ejemplos:

  `cases/unknown.schema` tiene un MAY que no está definido en ninguna parte:

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema` da un mismo OID a dos tipos de atributo:

  ```
  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleA'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )

  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleB'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )
  ```

  ```
  $ authnd check cases/twice.hcl
  authnd: schema_files: cases/twice.schema:4:1: the attribute type 1.3.6.1.4.1.99999.1.9 is defined twice (first defined at cases/twice.schema:1:1) (duplicate OID)
  ```

### Una redefinición se rechaza, incluso una idéntica {#redefinition}

Un archivo no puede definir lo que ya existe: las definiciones del esquema
estándar, las de Samba o las de un archivo anterior. Se rechaza **incluso
palabra por palabra**, que es la regla del propio slapd: las definiciones de un
archivo de esquema pasan por `parse_at` y `parse_oc`, y slapd responde a un OID
o a un nombre ya indexados con *Duplicate attributeType* (mismo OID y mismos
nombres) o *Inconsistent duplicate attributeType* (`servers/slapd/at.c`,
`oc.c`). Solo el esquema fijo del propio slapd tiene permitido lo primero. Un
archivo que slapd rechaza es un archivo que authnd rechaza.

La otra lectura tendría que elegir un ganador, y eso es un cambio silencioso en
lo que se le dice a cada cliente que es un atributo estándar; rechazar nombra
en cambio la línea. El rechazo dice si el texto era el mismo. Un archivo que
redefine `cn` (2.5.4.3) con una definición propia:

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## El bloque `schema { }` {#the-schema-block}

Para las definiciones que son solo locales, un bloque `schema` las contiene en
HCL2, con la [forma de hclschema]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}):
`attribute_type`, `object_class`, `object_identifier`, `matching_rule` y
`ldap_syntax`. Se lee **después** de los archivos, así que puede usar sus
definiciones, y puede haber varios.

Los valores deben ser **literales**: ni variables, ni funciones, ni `${...}` ni
`%{...}`. El bloque lo decodifica el mismo decodificador que lee un archivo de
esquema `.hcl`, con los mismos límites, y cada error nombra la línea y la
columna de la propia configuración. Un bloque que no está en la sintaxis nativa
de HCL se rechaza.

## `object_classes` {#object-classes}

Una definición en el esquema permite un atributo; no pone la clase a nadie. Un
origen **declara** las clases auxiliares con las que se publican sus personas y
sus grupos:

| dónde | clave | qué declara |
|---|---|---|
| bloque `users`, de cualquier tipo | `object_classes` | las clases de cada persona que da el bloque |
| bloque `users`, de cualquier tipo | `group_object_classes` | las clases de cada grupo |
| bloque `user` | `object_classes` | las clases de esa persona |
| bloque `group` | `object_classes` | las clases de ese grupo |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

Estas claves son las de go-authn/directory, desde la v0.15.0
([biblioteca]({{< relref "/libraries/directory.md#object-classes" >}})). Los
nombres se comparan sin distinguir mayúsculas y se conservan una sola vez, en
el orden escrito.

Lo que authnd hace con una clase declarada:

- **Se publica con sus superclases**, después de las clases que deduce authnd
  (RFC 4512 §3.3: todas las superclases de las clases nombradas se añaden
  implícitamente). Los atributos que la clase permite se conservan en lugar de
  descartarse.
- **Nunca se deduce.** Una persona cuyo origen no declara nada sigue perdiendo
  los atributos que ninguna clase suya permite, tenga lo que tenga la base de
  datos.
- **Una persona a la que le falta un MUST de una clase declarada se publica sin
  esa clase.** Sus atributos se descartan como cualquier atributo que ninguna
  clase permite, y ambas cosas se informan. Esa es la regla que authnd sigue en
  todas partes: la persona sigue publicada, el problema se dice, nada se cambia
  en silencio. Retener a la persona la sacaría de toda búsqueda por un solo
  atributo que falta; publicar la clase sin su MUST serviría una entrada que no
  supera el esquema servido.
- **Dos orígenes pueden declarar clases distintas para un mismo grupo.** El
  primer origen que declara clases para un grupo decide, entero, y una lista
  posterior se ignora: ni se fusiona ni es un error. `check` lo dice.

Aquí ann lo tiene todo, cat no tiene taquilla (un MAY), y ben no tiene
`exampleEmployeeId`, un MUST de `exampleStaff`:

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people

USER  FROM               CAN PROVE   PUBLISHED AS                                                                               WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn, exampleBadge, exampleEmployeeId and exampleLocker
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder                uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn and exampleEmployeeId

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder
ben is published without exampleStaff, which its source declares: ben has no exampleEmployeeId, which exampleStaff requires
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

El registro de arranque lleva las mismas líneas, con DN:

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 3 people from a sqlite database
schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people
uid=ben,ou=people,dc=example,dc=org is published without exampleStaff, which its source declares: uid=ben,ou=people,dc=example,dc=org has no exampleEmployeeId, which exampleStaff requires
uid=ben,ou=people,dc=example,dc=org is published without exampleBadge: no class of the entry allows it; exampleStaff would

stopping
```

Y lo que relee el `ldapsearch` de OpenLDAP, con la contraseña del lector en un
archivo. ann lleva las dos clases auxiliares y todos los atributos que
permiten; ben lleva solo `exampleLockerHolder`, y su insignia se fue con
`exampleStaff`; cat lleva las dos, con su número de empleado:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(uid=*)'
dn: uid=ann,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: ann
cn: ann
sn: Archer
exampleBadge: B-0001
exampleEmployeeId: E-1001
exampleLocker: L-12

dn: uid=ben,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleLockerHolder
uid: ben
cn: ben
sn: Brook

dn: uid=cat,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: cat
cn: cat
sn: Cole
exampleEmployeeId: E-1003

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(objectClass=exampleStaff)' 1.1
dn: uid=ann,ou=people,dc=example,dc=org

dn: uid=cat,ou=people,dc=example,dc=org
```

## Qué se rechaza, y por qué {#what-is-refused}

Una clase declarada se comprueba al arrancar, y con `check`, contra el esquema
servido. Debe ser:

- **definida**, por el esquema estándar, un archivo o un bloque;
- **AUXILIARY** (RFC 4512 §4.1.1). Una entrada tiene exactamente una cadena
  estructural (§2.4.2), que authnd elige a partir de lo que tiene la persona;
  una declaración no puede añadir una segunda;
- **no una que authnd deduce por sí mismo**: `account`, `inetOrgPerson` y sus
  superclases, `posixAccount`, `posixGroup`, `ldapPublicKey`, `uidObject`,
  `sambaSamAccount`, `groupOfNames` y `organizationalRole`, con cualquiera de
  sus nombres. Esas se siguen de lo que tiene una persona o un grupo, y una
  declaración no puede desautorizar a `check`.

En caso contrario se rechaza el arranque, nombrando el bloque, su posición y la
clase. `exampleUnit` es STRUCTURAL:

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory comprueba antes la **grafía**: una clase es un descriptor,
nunca un OID, un espacio, unas comillas ni un paréntesis.

También se rechaza, y por la misma razón de mantener honesto el esquema:

| se rechaza | por qué |
|---|---|
| un archivo que redefine una definición, incluso palabra por palabra | la regla de slapd: [arriba](#redefinition) |
| un archivo que no es un archivo regular, o que pasa de 4 MiB | un FIFO bloquearía el arranque, `/dev/zero` no acabaría nunca |
| un bloque `schema` con una variable, una función o `${...}` | solo valores literales, como en un archivo de esquema `.hcl` |
| una clase sin definir en `object_classes` | una promesa que nada puede comprobar |
| una clase STRUCTURAL, o una que authnd deduce | la lista de arriba |

## Qué imprime `check` {#what-check-prints}

Cuatro tipos de líneas, además de [las habituales]({{< relref "/authnd/check.md" >}}); el registro de arranque lleva las mismas:

- **`schema: <file> adds …`** y **`schema: the schema block at <file>:<line>:<column> adds …`**:
  lo que añadió cada archivo y cada bloque, contado como macros de
  identificador de objeto, tipos de atributo y clases de objeto;
- **`<file>:<line>:<column>: users "sql" declares … for its people`** (un
  bloque `user` o `group` dice `user "ann" declares … for this person` y
  `group "staff" declares … for this group`): lo que declara cada origen;
- **`<name> is published without <class>, which its source declares: …`**,
  que nombra el MUST que le falta a la persona;
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`**:
  dos orígenes que discrepan sobre un grupo, algo que de otro modo sería
  silencioso.

Los atributos descartados por falta de una clase son las líneas `is published
without <attribute>: no class of the entry allows it; <classes> would` que
[las entradas]({{< relref "/authnd/entries.md" >}}) ya describen: con una
declaración nombran la clase que usted no ha declarado.

## SUPANN, como ejemplo real {#supann}

SUPANN es el conjunto de atributos de la enseñanza superior y la investigación
francesas (`supannPerson`, `supannEtablissement`, `supannEntite`…), con eduPerson
a su lado. RENATER publica el esquema técnico, con los demás, en su página de
documentación:

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**Descargue el archivo desde allí.** No se reproduce en este sitio: no declara
ninguna licencia, así que esta página no lo copia, y una copia aquí quedaría
obsoleta cuando RENATER lo revisara. Después:

```sh
sudo install -o root -g authnd -m 0640 supann.schema eduperson.ldif /etc/authnd/
```

```hcl
schema_files = ["/etc/authnd/supann.schema", "/etc/authnd/eduperson.ldif"]

users "sql" {
  # ...
  users_attributes     = "select login, sn, etab as \"supannEtablissement\" from staff"
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}
```

Ejecute `authnd check` y lea primero las líneas `schema:`: un archivo que slapd
carga se carga aquí, y uno que redefine una definición estándar se rechaza con
su línea. Después lea las líneas *published without*: una persona a la que le
falta un MUST de `supannPerson` o de `eduPerson` se publica sin la clase, y
`check` nombra el MUST. Ponga entre comillas un alias allí donde importe su
grafía (PostgreSQL pasa a minúsculas uno sin comillas; consulte
[las entradas]({{< relref "/authnd/entries.md#in-a-sql-database" >}})).

{{< callout type="info" >}}
**Sobre las transcripciones**

Cada comando de esta página se volvió a ejecutar el 26 de octubre de 2026 con el binario de la versión v0.12.3 (`authnd-darwin-arm64`, comprobado con `SHA256SUMS`; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`) y el `ldapsearch` de OpenLDAP, en 127.0.0.1, en un directorio temporal, con los archivos mostrados. Las rutas son relativas por esa razón; un servicio usa rutas absolutas. El esquema es un ejemplo escrito para esta página.
{{< /callout >}}
