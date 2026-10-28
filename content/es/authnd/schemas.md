---
title: "Esquemas de un sitio, y las clases que declara un origen"
linkTitle: "Esquemas de un sitio"
weight: 27
description: "Sirva SUPANN, eduPerson o los atributos propios de un sitio: schema_files y el bloque schema añaden definiciones, object_classes declara qué clases auxiliares llevan las personas y los grupos de un origen, y check dice qué se omitió. Desde la v0.13.0 se aplican las reglas de contenido DIT, las formas de nombre y las reglas de estructura DIT."
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

## Reglas de contenido DIT, formas de nombre y reglas de estructura DIT {#rules}

Desde la v0.13.0, `schema_files` y el bloque `schema { }` aceptan también los
tres tipos de definición que los RFC 4512 §4.1.6 y §4.1.7 añaden a las clases y
a los atributos, y authnd los **aplica** (go-authn/ldap v0.11.0 los lee, los
construye y los comprueba; [la página de la biblioteca]({{< relref "/libraries/ldap.md#rules" >}})
explica cómo):

| definición | RFC 4512 | qué dice | qué hace authnd con ella |
|---|---|---|---|
| regla de contenido DIT | §4.1.6 | para una clase estructural: qué clases auxiliares (`AUX`) se pueden añadir, qué atributos son obligatorios (`MUST`), permitidos (`MAY`) o excluidos (`NOT`) | **da forma a cada entrada** (datos) |
| forma de nombre | §4.1.7.2 | qué atributos nombran (el RDN) una entrada de una clase estructural | **sostiene el árbol** (configuración) |
| regla de estructura DIT | §4.1.7.1 | dónde se puede ubicar una forma de nombre: bajo la entrada gobernada por la regla que nombra su `SUP` | **sostiene el árbol** (configuración) |

Se publican en `cn=Subschema` (`dITContentRules`, `nameForms`,
`dITStructureRules`) **solo cuando las hay**. Sin ninguna, nada de esta página
se aplica, y nada cambia respecto a la v0.12.4.

{{< callout type="info" >}}
**El mismo arco de ejemplo**

`rules.schema`, más abajo, está escrito para esta página, como el
`example.schema` de arriba, bajo `1.3.6.1.4.1.99999`. Use su propio arco. Los OID
de la regla de contenido y de `inetOrgPerson` son los mismos por definición:
una regla de contenido se llama como la clase estructural a la que corresponde.
{{< /callout >}}

### Un esquema con una de cada, y su HCL {#rules-example}

En la forma `.schema` de OpenLDAP. `ditcontentrule` es la directiva de
slapd.conf(5); `nameform` y `ditstructurerule` son de go-authn/ldap, porque
slapd no tiene ninguna ([más abajo](#rules-slapd)). authnd comprueba además el
árbol que publica (el sufijo, `ou=people`, `ou=groups`, y las cuentas, personas
y grupos bajo ellos), así que el archivo contiene cinco formas de nombre y cinco
reglas de estructura, no una de cada:

```
# Rules for the tree authnd publishes. 1.3.6.1.4.1.99999 is an example arc:
# nobody is assigned it, use your own.

# A content rule belongs to a structural class and takes that class's OID.
# inetOrgPerson (2.16.840.1.113730.3.2.2): posixAccount and uidObject may be
# added, ldapPublicKey may not; telephoneNumber is required; description is
# precluded.
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule'
	AUX ( posixAccount $ uidObject )
	MUST telephoneNumber
	NOT description )

# A name form says which attribute names an entry of a structural class.
nameform ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameform ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameform ( 1.3.6.1.4.1.99999.9.3 NAME 'exampleAccountForm' OC account MUST uid )
nameform ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )
nameform ( 1.3.6.1.4.1.99999.9.5 NAME 'examplePosixGroupForm' OC posixGroup MUST cn )

# A structure rule gives a name form a place: the rule ID is a number, SUP
# names the rule of the parent entry.
ditstructurerule ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
ditstructurerule ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
ditstructurerule ( 3 NAME 'exampleAccounts' FORM exampleAccountForm SUP 2 )
ditstructurerule ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
ditstructurerule ( 5 NAME 'examplePosixGroups' FORM examplePosixGroupForm SUP 2 )
```

Las mismas definiciones en HCL, tal como las escribe `ldapschema` v0.11.0
(`ldapschema to-hcl rules.schema`). Cada bloque es una definición, etiquetada con
su primer NAME; una regla de estructura tiene un `id`, el `form` que ubica y las
reglas `sup` bajo las que va:

```hcl
dit_content_rule "examplePersonRule" {
  oid  = "2.16.840.1.113730.3.2.2"
  aux  = ["posixAccount", "uidObject"]
  must = ["telephoneNumber"]
  not  = ["description"]
}

name_form "exampleDomainForm" {
  oid  = "1.3.6.1.4.1.99999.9.1"
  oc   = "domain"
  must = ["dc"]
}

name_form "exampleUnitForm" {
  oid  = "1.3.6.1.4.1.99999.9.2"
  oc   = "organizationalUnit"
  must = ["ou"]
}

name_form "exampleAccountForm" {
  oid  = "1.3.6.1.4.1.99999.9.3"
  oc   = "account"
  must = ["uid"]
}

name_form "examplePersonForm" {
  oid  = "1.3.6.1.4.1.99999.9.4"
  oc   = "inetOrgPerson"
  must = ["uid"]
}

name_form "examplePosixGroupForm" {
  oid  = "1.3.6.1.4.1.99999.9.5"
  oc   = "posixGroup"
  must = ["cn"]
}

dit_structure_rule "exampleSuffix" {
  id   = 1
  form = "exampleDomainForm"
}

dit_structure_rule "exampleUnit" {
  id   = 2
  form = "exampleUnitForm"
  sup  = [1]
}

dit_structure_rule "exampleAccounts" {
  id   = 3
  form = "exampleAccountForm"
  sup  = [2]
}

dit_structure_rule "examplePersons" {
  id   = 4
  form = "examplePersonForm"
  sup  = [2]
}

dit_structure_rule "examplePosixGroups" {
  id   = 5
  form = "examplePosixGroupForm"
  sup  = [2]
}
```

Eso es lo que va dentro de un bloque `schema { }`, sin cambios; el archivo
`.schema` es lo que toma `schema_files`. `ldapschema to-schema rules.hcl` lo
convierte de nuevo en un archivo `.schema` con las mismas definiciones, y
`ldapschema check` lo construye sobre el esquema estándar:

```
$ ldapschema check etc/authnd/rules.schema
read: 0 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 5 name forms, 5 DIT structure rules
build: ok, 11 definitions added to schema.Standard()
```

### Lo que una regla de contenido hace a una entrada {#content-rules}

La configuración son dos personas y dos grupos, con las reglas cargadas desde
`schema_files`. **dave** tiene un `sn` (así que es un `inetOrgPerson`), un número
de teléfono, una descripción y una clave pública SSH; **erin** tiene un `sn` y
nada más; **staff** tiene un `gidNumber`; **team** no tiene ninguno:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

schema_files = ["etc/authnd/rules.schema"]

user "dave" {
  password        = "dave-password"
  authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl dave@example.org"]
  attributes = {
    sn              = "Dumont"
    telephoneNumber = "+33 1 23 45 67 89"
    description     = "on call"
  }
}

user "erin" {
  password   = "erin-password"
  attributes = { sn = "Evans" }
}

group "staff" {
  members    = ["dave"]
  attributes = { gidNumber = "100" }
}

group "team" { members = ["dave"] }
```

La regla se aplica a la **clase estructural** de la entrada, y lo que hace se
dice, al arrancar y con `check`, entrada por entrada:

| la regla dice | la entrada | se dice como |
|---|---|---|
| `AUX` no enumera una clase auxiliar, declarada o derivada por authnd (`posixAccount`, `ldapPublicKey`, `sambaSamAccount`, `uidObject`) | la clase **se deja fuera**, con los atributos que solo ella permitía (y el `sshPublicKey`, el `sambaSID` y el `sambaNTPassword` que authnd añadiría por ella); una clase declarada cuya superclase se deja fuera se va con ella | `<name> is published without <class>: the DIT content rule <rule> does not allow it (not in its AUX)` |
| `NOT` nombra un atributo | el atributo **se descarta**, lo haya dado quien lo haya dado | `<name> is published without <attribute>: the DIT content rule <rule> precludes it (NOT)` |
| `MUST` nombra un atributo que la entrada no tiene | la entrada **se deja fuera**: la regla se aplica a la entrada entera, y ninguna clase se puede dejar fuera para hacerla válida | `<name> is NOT published: … <attribute> is required by the DIT content rule <rule> and is missing (RFC 4512 4.1.6)` |

Sin una regla de contenido para su clase estructural, las clases auxiliares de
una entrada se permiten, como las permite slapd ([más abajo](#rules-slapd)).

```
$ authnd check etc/authnd/authnd.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules

USER  FROM                    CAN PROVE             PUBLISHED AS                                            WITH
dave  the configuration file  a password and 1 key  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn, sn and telephoneNumber
erin  the configuration file  a password            NOT PUBLISHED (see below)                               uid, cn and sn

GROUP  MEMBERS  PUBLISHED AS
staff  dave     posixGroup
team   dave     NOT PUBLISHED (see below)

dave has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
dave is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
dave is published without description: the DIT content rule examplePersonRule precludes it (NOT)
erin has no uidNumber, gidNumber or homeDirectory: not a posixAccount, and as person, organizationalPerson, inetOrgPerson, uidObject the entry fails the schema (below)
erin is NOT published: as person, organizationalPerson, inetOrgPerson, uidObject it fails the schema:
  - telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
group team is NOT published: as groupOfNames it fails the schema:
  - no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

El servidor arranca, y su log lleva los mismos tres tipos de línea, con DN:

```
$ authnd --config etc/authnd/authnd.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules
uid=erin,ou=people,dc=example,dc=org is NOT published: it fails the schema: telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
cn=team,ou=groups,dc=example,dc=org is NOT published: it fails the schema: no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)
uid=dave,ou=people,dc=example,dc=org is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
uid=dave,ou=people,dc=example,dc=org is published without description: the DIT content rule examplePersonRule precludes it (NOT)
```

Lo que lee el `ldapsearch` de OpenLDAP en `cn=Subschema`, los tres atributos en
los que se publican las reglas:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b cn=Subschema -s base '(objectClass=subschema)' dITContentRules nameForms dITStructureRules
dn: cn=Subschema
dITContentRules: ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule' AUX ( posixAccount $ uidObject ) MUST telephoneNumber NOT description )
nameForms: ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameForms: ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameForms: ( 1.3.6.1.4.1.99999.9.3 NAME 'exampleAccountForm' OC account MUST uid )
nameForms: ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )
nameForms: ( 1.3.6.1.4.1.99999.9.5 NAME 'examplePosixGroupForm' OC posixGroup MUST cn )
dITStructureRules: ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
dITStructureRules: ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
dITStructureRules: ( 3 NAME 'exampleAccounts' FORM exampleAccountForm SUP 2 )
dITStructureRules: ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
dITStructureRules: ( 5 NAME 'examplePosixGroups' FORM examplePosixGroupForm SUP 2 )
```

Y el árbol, consultado por lo que las reglas tocan. Primero la misma
configuración **sin** `schema_files` (el testigo: toda diferencia de abajo es
obra de las reglas), y luego con ellos:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(|(uid=*)(cn=*))' dn objectClass description sshPublicKey
dn: uid=dave,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: ldapPublicKey
objectClass: uidObject
description: on call
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl dave@example.org

dn: uid=erin,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject

dn: cn=staff,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup

dn: cn=team,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
```

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(|(uid=*)(cn=*))' dn objectClass description sshPublicKey
dn: uid=dave,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject

dn: cn=staff,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
```

dave ha perdido `ldapPublicKey` y con ella su `sshPublicKey` (no está en
`AUX`), y su `description` (`NOT`). erin ha desaparecido (`MUST telephoneNumber`),
y también **team**: no tiene `gidNumber`, así que es un `groupOfNames`, y
ninguna regla de estructura ubica un `groupOfNames` bajo `ou=groups`. Esa
última es la regla del árbol aplicada a los datos, que explica la sección
siguiente.

### Lo que las reglas de estructura hacen al árbol {#structure-rules}

Con **al menos una** regla de estructura DIT activa, authnd recorre el árbol que
va a publicar, al arrancar y en `check`:

- el **sufijo** (`base_dn`), con la clase que nombra su RDN: `dc` un
  `domain`, `o` una `organization`, `ou` una `organizationalUnit`, `c` un
  `country`, `l` una `locality`. Un sufijo nombrado por cualquier otro atributo
  se rechaza;
- `ou=people` y `ou=groups`, como `organizationalUnit`;
- el atributo RDN con el que authnd nombra a sus personas (`uid`) y a sus grupos
  (`cn`).

Un contenedor que ninguna regla ubica, un sufijo de un tipo para el que ninguna
regla tiene forma de nombre, una forma de nombre que rechaza `uid` o `cn`, o un
contenedor bajo el que no se podría ubicar nada de lo que authnd publica,
**impide el arranque, y `check`**: todos los rechazos a la vez, nombrando el DN,
la regla o la forma de nombre y la cláusula, y sin repetir nunca un secreto. Una
persona o un grupo cuya clase estructural depende de sus datos (un `sn`, un
`gidNumber`) y no tiene regla bajo su contenedor se **deja fuera y se dice**, en
cambio, como team más arriba: el servidor arranca. Sin ninguna regla de
estructura activa, nada cambia.

Un esquema cuya única regla de estructura para las personas, `peopleByCN`, ubica
una forma de nombre que quiere `cn` (`accountByCN`: `OC account MUST cn`):

```
$ authnd check cases/bad.hcl
authnd: DIT structure rules: authnd names its people uid=<name>,ou=people,dc=example,dc=org, and an account named so is refused: the RDN (uid) is allowed by the name form of no DIT structure rule that places account under an entry governed by the rule 2: accountByCN needs cn
```

authnd nombra a sus personas `uid=<name>`: las reglas tienen que permitirlo. Y
un esquema cuya regla para `organizationalUnit` no tiene `SUP`, de modo que una
`organizationalUnit` solo puede estar en la raíz, deja sin lugar tanto
`ou=people` como `ou=groups`, y dice ambos a la vez:

```
$ authnd check cases/root.hcl
authnd: DIT structure rules: ou=people,dc=example,dc=org, where authnd publishes its people, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
DIT structure rules: ou=groups,dc=example,dc=org, where authnd publishes its groups, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
```

Ambos salen con código 1. Los archivos que hay detrás (`cases/bad.schema` y
`cases/root.schema`) contienen las mismas cinco formas de nombre y solo las
reglas de estructura que sirven a la demostración.

### Dónde difieren authnd y slapd {#rules-slapd}

go-authn/ldap lee los archivos de OpenLDAP, y algunas de las reglas son las de
OpenLDAP. Estas son las diferencias, dichas en lugar de descubiertas:

- **slapd solo implementa reglas de contenido.** No tiene ninguna directiva para
  formas de nombre ni reglas de estructura. `Format` escribe las palabras clave
  `nameform` y `ditstructurerule`, que son de esta biblioteca, y slapd las
  rechaza: manténgalas en el HCL, o en un archivo que solo lea authnd.
  `ditcontentrule` es de slapd.
- **Una regla `OBSOLETE` está inactiva** (RFC 4512 §4.1.6), igual que su forma de
  nombre o su regla de estructura. slapd rechaza la entrada en su lugar.
- **Sin regla de contenido, las clases auxiliares se permiten.** Es el
  comportamiento de slapd (ninguna palabra clave `disallow` activa su indicador
  `SLAP_DISALLOW_AUX_WO_CR`), y el de authnd. El RFC 4512 §2.4.3 dice otra cosa;
  la biblioteca lo ofrece como `ValidateOptions{StrictAuxiliary: true}`, y
  authnd no lo activa.
- **libldap no puede leer el `SUP` de una regla de estructura.** Una regla de
  estructura con `SUP` se lee aquí y no con libldap, así que el rechazo de
  libldap a un archivo así no es un veredicto sobre el archivo.
- Un archivo que **redefine** una regla se rechaza, incluso palabra por palabra,
  como toda otra definición ([arriba](#redefinition)).

### Lo que cuesta {#rules-cost}

Medido el 2026-10-28 con `BenchmarkPublish10k` (go-authn/authnd,
`rules_bench_test.go`, `-cpu 1`) en authnd v0.13.1, que incorpora go-authn/ldap
v0.11.1: publicar 10 000 personas hace **364 asignaciones por entrada** con las
reglas de `testdata/rules.schema` y **239** sin ellas (v0.13.0: 416 y 265), y
una ejecución ocupa 102,5 MiB con las reglas y 65,4 MiB sin ellas (v0.13.0:
147,5 y 88,0). Esto incluye descartar una descripción excluida y validar de
nuevo. Los tiempos, unos 157 ms frente a 100 ms (v0.13.0: 194 ms frente a
123 ms), se midieron con una carga de 10 a 16 y no son una proporción fiable;
solo lo son los recuentos de asignaciones.

### Actualizar {#rules-upgrade}

No cambia nada para un esquema sin reglas: la v0.12.4 rechazaba los tres tipos,
así que una configuración que arrancó con ella no tiene ninguno. Hay una
excepción. Una cadena `schema { }` que **no es UTF-8 válido** (una codificación
superlarga que HCL deja pasar) arrancaba con la v0.12.4 y ahora se rechaza,
porque no se podría publicar tal como se escribió.

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

La sección sobre [reglas de contenido DIT, formas de nombre y reglas de estructura DIT](#rules) se ejecutó el 26 de octubre de 2026 con el binario de la versión v0.13.0 (`authnd-darwin-arm64`, comprobado por `relverify` contra `SHA256SUMS` y su atestación; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.13.0`; `authnd --version`: `authnd version v0.13.0`), el `ldapsearch` de OpenLDAP y `ldapschema` compilado desde la etiqueta v0.11.0 de go-authn/ldap (`go install`, go1.27.1; no tiene binario publicado). Toda salida de allí la imprimieron esos programas, en un directorio temporal, en 127.0.0.1; los archivos que hay detrás de las transcripciones se muestran o se describen a su lado.
{{< /callout >}}
