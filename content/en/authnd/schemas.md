---
title: "Site schemas, and the classes a source declares"
linkTitle: "Site schemas"
weight: 27
description: "Serve SUPANN, eduPerson or a site's own attributes: schema_files and the schema block add definitions, object_classes declares which auxiliary classes a source's people and groups carry, and check says what was left off."
tags: [authnd, ldap, schema, configuration]
---

**A SUPANN or eduPerson attribute is dropped unless a class of its entry
allows it.** authnd publishes only what the schema it serves permits (see
[the entries]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})),
and the standard schema knows nothing of `supannEtablissement` or
`eduPersonAffiliation`. From v0.12.0 a site says three things, in this order:

1. **which definitions to add**: `schema_files`, the files its slapd already
   loads, and a `schema { }` block for what is only local;
2. **which auxiliary classes its people and groups carry**: `object_classes`;
3. nothing else. A class is **declared, never inferred**: an attribute
   appearing in a database does not change what an entry is published as.

{{< callout type="info" >}}
**The example on this page is an example**

`example.schema` below was written for this page. Its OIDs are under
`1.3.6.1.4.1.99999`, an arc nobody is assigned: use your own, and never copy
these. For SUPANN, see [the end of the page](#supann).
{{< /callout >}}

## An example: a schema, a database, a configuration {#an-example}

A schema in OpenLDAP's `.schema` form: one class a source can declare
(`exampleStaff`, AUXILIARY, with a MUST), and one it cannot
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

A SQLite database of three people, with `sn`, a badge and a staff number
(`sqlite3 var/people.db < people.sql`):

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

And the configuration:

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

Without the `object_classes` line, `check` says what the standard schema
alone does with the same people: the attributes are dropped, and each line
names the class that would have kept it.

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

`schema_files` is a list of OpenLDAP `.schema` files or cn=config LDIF files.
They are loaded **as published**, in order, on top of the standard schema (and
Samba's three definitions, with the [`samba` block]({{< relref "/authnd/tls.md#the-samba-block" >}})), by
go-authn/ldap's [slapd-compatible readers]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}):
any order of terms, slapd and RFC 2849 continuations, base64, `{N}` length
prefixes, and `objectidentifier` macros, which one file may define and the next
use, as across slapd's `include`. Nothing is converted beforehand, so the file
a site's slapd loads is the file authnd loads. The definitions are served at
`cn=Subschema`.

- A relative path is relative to the working directory, as every other path
  in the configuration is. Use absolute paths in a service: the working
  directory of a systemd unit is `/`.
- Each file must be a regular file of at most 4 MiB, and is read once, at
  startup.
- The files decide what every entry may hold. They are not secrets, but keep
  them with the rest of the configuration: `root:authnd`, mode `0640`, in a
  directory only root writes ([install]({{< relref "/authnd/install.md" >}})).
- A file that does not build refuses startup, and `check`, with the file, the
  line and the column where the definition starts, and the kind of refusal at
  the end of the message: an unknown superclass, attribute, matching rule or
  syntax (`unknown reference`), a structural class derived from an auxiliary
  one (`kind violation`), an OID or a name defined twice (`duplicate OID`,
  `duplicate name`). Since v0.12.1 the place and the kind come from
  go-authn/ldap's typed
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}), not
  from reading its message. A definition read from a file starts at column 1,
  also when its text is folded over several lines. A duplicate says where its
  first definition is, and a redefinition says which standard file, or which
  line of an earlier file, holds the original. Two examples:

  `cases/unknown.schema` has a MAY that is defined nowhere:

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema` gives one OID to two attribute types:

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

### A redefinition is refused, even an identical one {#redefinition}

A file may not define what is already there: the standard schema's
definitions, Samba's, or an earlier file's. It is refused **even word for
word**, which is slapd's own rule: a schema file's definitions go through
`parse_at` and `parse_oc`, and slapd answers an OID or a name already indexed
with *Duplicate attributeType* (same OID and names) or *Inconsistent duplicate
attributeType* (`servers/slapd/at.c`, `oc.c`). Only slapd's own hard-coded
schema is allowed the first. A file slapd refuses is a file authnd refuses.

The other reading would have to pick a winner, and that is a silent change to
what every client is told a standard attribute is; refusing names the line
instead. The refusal says whether the text was the same. A file that
redefines `cn` (2.5.4.3) with a definition of its own:

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## The `schema { }` block {#the-schema-block}

For definitions that are only local, a `schema` block holds them in
HCL2, in [hclschema's shape]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}):
`attribute_type`, `object_class`, `object_identifier`, `matching_rule` and
`ldap_syntax`. It is read **after** the files, so it may use their
definitions, and there may be several.

Values must be **literals**: no variables, no functions, no `${...}` or
`%{...}`. The block is decoded by the same decoder that reads an `.hcl`
schema file, with the same bounds, and every error names the configuration's
own line and column. A block that is not in HCL's native syntax is refused.

## `object_classes` {#object-classes}

A definition in the schema allows an attribute; it does not put the class on
anybody. A source **declares** the auxiliary classes its people and groups
are published with:

| where | key | what it declares |
|---|---|---|
| `users` block, any kind | `object_classes` | the classes of every person the block gives |
| `users` block, any kind | `group_object_classes` | the classes of every group |
| `user` block | `object_classes` | the classes of that person |
| `group` block | `object_classes` | the classes of that group |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

These keys are go-authn/directory's, from v0.15.0
([library]({{< relref "/libraries/directory.md#object-classes" >}})). Names
are compared ignoring case, and kept once, in the order written.

What authnd does with a declared class:

- **It is published with its superclasses**, after the classes authnd derives
  (RFC 4512 §3.3: all the superclasses of the named classes are implicitly
  added). The attributes the class allows are kept instead of dropped.
- **It is never inferred.** A person whose source declares nothing keeps
  losing the attributes no class of theirs allows, whatever the database holds.
- **A person missing a MUST of a declared class is published without that
  class.** Its attributes are dropped like any attribute no class allows, and
  both are reported. That is the rule authnd follows everywhere: the person
  stays published, the problem is said, nothing is changed silently.
  Withholding the person would take them out of every search for one missing
  attribute; publishing the class without its MUST would serve an entry that
  fails the schema served.
- **Two sources may declare different classes for one group.** The first
  source that declares classes for a group decides, whole, and a later list is
  ignored: neither merged nor an error. `check` says so.

Here ann has everything, cat has no locker (a MAY), and ben has no
`exampleEmployeeId`, a MUST of `exampleStaff`:

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

The startup log carries the same lines, with DNs:

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

And what OpenLDAP's `ldapsearch` reads back, with the reader's password in a
file. ann carries both auxiliary classes, and every attribute they allow; ben
carries only `exampleLockerHolder`, and his badge is gone with
`exampleStaff`; cat carries both, with her staff number:

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

## What is refused, and why {#what-is-refused}

A declared class is checked at startup, and by `check`, against the schema
served. It must be:

- **defined**, by the standard schema, a file or a block;
- **AUXILIARY** (RFC 4512 §4.1.1). An entry has exactly one structural chain
  (§2.4.2), which authnd chooses from what the person has; a declaration
  cannot add a second one;
- **not one authnd derives itself**: `account`, `inetOrgPerson` and its
  superclasses, `posixAccount`, `posixGroup`, `ldapPublicKey`, `uidObject`,
  `sambaSamAccount`, `groupOfNames` and `organizationalRole`, under any of
  their names. Those follow from what a person or group has, and a
  declaration cannot overrule `check`.

Otherwise startup is refused, naming the block, its position and the class.
`exampleUnit` is STRUCTURAL:

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory checks the **spelling** before that: a class is a
descriptor, never an OID, a space, a quote or a parenthesis.

Refused too, and for the same reason of keeping the schema honest:

| refused | why |
|---|---|
| a file that redefines a definition, even word for word | slapd's rule: [above](#redefinition) |
| a file that is not a regular file, or is over 4 MiB | a FIFO would block startup, `/dev/zero` would never end |
| a `schema` block with a variable, a function or `${...}` | literal values only, as in an `.hcl` schema file |
| an undefined class in `object_classes` | a promise nothing can check |
| a STRUCTURAL class, or one authnd derives | the list above |

## What `check` prints {#what-check-prints}

Four kinds of lines, on top of [the usual ones]({{< relref "/authnd/check.md" >}}); the startup log carries the same:

- **`schema: <file> adds …`** and **`schema: the schema block at <file>:<line>:<column> adds …`**:
  what each file and each block added, counted as object identifier
  macros, attribute types and object classes;
- **`<file>:<line>:<column>: users "sql" declares … for its people`** (a
  `user` or `group` block says `user "ann" declares … for this person` and
  `group "staff" declares … for this group`): what each source declares;
- **`<name> is published without <class>, which its source declares: …`**,
  naming the MUST the person lacks;
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`**:
  two sources disagreeing about a group, which would otherwise be silent.

Attributes dropped for want of a class are the lines `is published without
<attribute>: no class of the entry allows it; <classes> would` that
[the entries]({{< relref "/authnd/entries.md" >}}) already describe: with a
declaration they name the class you have not declared.

## SUPANN, as the real example {#supann}

SUPANN is the attribute set of French higher education and research
(`supannPerson`, `supannEtablissement`, `supannEntite`…), with eduPerson
beside it. RENATER publishes the technical schema, with the others, on its
documentation page:

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**Download the file from there.** It is not reproduced on this site: it
states no licence, so this page does not copy it, and a copy here would go
stale when RENATER revises it. Then:

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

Run `authnd check` and read the `schema:` lines first: a file that slapd
loads loads here, and one that redefines a standard definition is refused
with its line. Then read the *published without* lines: a person lacking a
MUST of `supannPerson` or `eduPerson` is published without the class, and
`check` names the MUST. Quote an alias where its spelling matters
(PostgreSQL lower-cases an unquoted one; see
[the entries]({{< relref "/authnd/entries.md#in-a-sql-database" >}})).

{{< callout type="info" >}}
**About the transcripts**

Every command on this page was run again on 2026-10-26 with the v0.12.3 release binary (`authnd-darwin-arm64`, checked against `SHA256SUMS`; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`) and OpenLDAP's `ldapsearch`, on 127.0.0.1, in a scratch directory, with the files shown. The paths are relative for that reason; a service uses absolute ones. The schema is an example written for this page.
{{< /callout >}}
