---
title: "Site schemas, and the classes a source declares"
linkTitle: "Site schemas"
weight: 27
description: "Serve SUPANN, eduPerson or a site's own attributes: schema_files and the schema block add definitions, object_classes declares which auxiliary classes a source's people and groups carry, and check says what was left off. From v0.13.0, DIT content rules, name forms and DIT structure rules are enforced."
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

## DIT content rules, name forms and DIT structure rules {#rules}

From v0.13.0, `schema_files` and the `schema { }` block also accept the three
kinds of definition that RFC 4512 §4.1.6 and §4.1.7 add to classes and
attributes, and authnd **enforces** them (go-authn/ldap v0.11.0 reads, builds
and checks them; [the library page]({{< relref "/libraries/ldap.md#rules" >}})
says how):

| definition | RFC 4512 | what it says | what authnd does with it |
|---|---|---|---|
| DIT content rule | §4.1.6 | for one structural class: which auxiliary classes (`AUX`) may be added, which attributes are required (`MUST`), allowed (`MAY`) or precluded (`NOT`) | **shapes each entry** (data) |
| name form | §4.1.7.2 | which attribute names (the RDN) an entry of a structural class | **holds the tree** (configuration) |
| DIT structure rule | §4.1.7.1 | where a name form may be placed: under the entry governed by the rule its `SUP` names | **holds the tree** (configuration) |

They are published at `cn=Subschema` (`dITContentRules`, `nameForms`,
`dITStructureRules`) **only when there are some**. With none, nothing on this
page applies, and nothing changes from v0.12.4.

{{< callout type="info" >}}
**Same example arc**

`rules.schema` below is, like `example.schema` above, written for this page,
under `1.3.6.1.4.1.99999`. Use your own arc. The OIDs of the content rule and
of `inetOrgPerson` are the same by definition: a content rule is named after
the structural class it is for.
{{< /callout >}}

### A schema with one of each, and its HCL {#rules-example}

In OpenLDAP's `.schema` form. `ditcontentrule` is slapd.conf(5)'s directive;
`nameform` and `ditstructurerule` are go-authn/ldap's, since slapd has none
([below](#rules-slapd)). authnd also checks the tree it publishes
(suffix, `ou=people`, `ou=groups`, accounts, people and groups under them), so
the file holds five name forms and five structure rules, not one of each:

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

The same definitions in HCL, as `ldapschema` v0.11.0 writes them
(`ldapschema to-hcl rules.schema`). Each block is one definition, labelled with
its first NAME; a structure rule has an `id`, the `form` it places and the
`sup` rules it goes under:

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

That is what goes inside a `schema { }` block, unchanged; the `.schema` file is
what `schema_files` takes. `ldapschema to-schema rules.hcl` turns it back into a
`.schema` file with the same definitions, and `ldapschema check` builds it on
top of the standard schema:

```
$ ldapschema check etc/authnd/rules.schema
read: 0 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 5 name forms, 5 DIT structure rules
build: ok, 11 definitions added to schema.Standard()
```

### What a content rule does to an entry {#content-rules}

The configuration is two people and two groups, with the rules loaded from
`schema_files`. **dave** has an `sn` (so he is an `inetOrgPerson`), a telephone
number, a description and an SSH public key; **erin** has an `sn` and nothing
else; **staff** has a `gidNumber`; **team** has none:

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

The rule applies to the entry's **structural class**, and what it does is said,
at startup and by `check`, entry by entry:

| the rule says | the entry | said as |
|---|---|---|
| `AUX` does not list an auxiliary class, whether declared or one authnd derives (`posixAccount`, `ldapPublicKey`, `sambaSamAccount`, `uidObject`) | the class is **left off**, with the attributes only it allowed (and the `sshPublicKey`, `sambaSID` and `sambaNTPassword` authnd would add for it); a declared class whose superclass is left off goes with it | `<name> is published without <class>: the DIT content rule <rule> does not allow it (not in its AUX)` |
| `NOT` names an attribute | the attribute is **dropped**, whoever gave it | `<name> is published without <attribute>: the DIT content rule <rule> precludes it (NOT)` |
| `MUST` names an attribute the entry lacks | the entry is **left out**: the rule applies to the entry as a whole, and no class can be left off to make it valid | `<name> is NOT published: … <attribute> is required by the DIT content rule <rule> and is missing (RFC 4512 4.1.6)` |

Without a content rule for its structural class, an entry's auxiliary classes
are allowed, as slapd allows them ([below](#rules-slapd)).

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

The server starts, and its log carries the same three kinds of line, with DNs:

```
$ authnd --config etc/authnd/authnd.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules
uid=erin,ou=people,dc=example,dc=org is NOT published: it fails the schema: telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
cn=team,ou=groups,dc=example,dc=org is NOT published: it fails the schema: no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)
uid=dave,ou=people,dc=example,dc=org is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
uid=dave,ou=people,dc=example,dc=org is published without description: the DIT content rule examplePersonRule precludes it (NOT)
```

What OpenLDAP's `ldapsearch` reads at `cn=Subschema`, the three attributes the
rules are published in:

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

And the tree, asked for what the rules touch. First the same configuration
**without** `schema_files` (the witness: every difference below is the rules'
doing), then with them:

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

dave has lost `ldapPublicKey` and with it his `sshPublicKey` (not in `AUX`),
and his `description` (`NOT`). erin is gone (`MUST telephoneNumber`), and so is
**team**: it has no `gidNumber`, so it is a `groupOfNames`, and no structure
rule places a `groupOfNames` under `ou=groups`. That last one is the tree's
rule applied to data, which the next section explains.

### What the structure rules do to the tree {#structure-rules}

With **at least one active** DIT structure rule, authnd walks the tree it will
publish, at startup and in `check`:

- the **suffix** (`base_dn`), given the class its RDN names: `dc` a
  `domain`, `o` an `organization`, `ou` an `organizationalUnit`, `c` a
  `country`, `l` a `locality`. A suffix named by any other attribute is
  refused;
- `ou=people` and `ou=groups`, as `organizationalUnit`s;
- the RDN attribute authnd names its people by (`uid`) and its groups by (`cn`).

A container no rule places, a suffix of a kind no rule has a name form for, a
name form that refuses `uid` or `cn`, or a container under which nothing authnd
publishes could be placed, **refuses startup, and `check`**: every refusal at
once, naming the DN, the rule or name form and the clause, and never echoing a
secret. A person or group whose structural class depends on its data (an `sn`,
a `gidNumber`) and has no rule under its container is **left out and said**
instead, as team was above: the server starts. With no active structure rule,
nothing changes.

A schema whose only structure rule for people, `peopleByCN`, places a name form
that wants `cn` (`accountByCN`: `OC account MUST cn`):

```
$ authnd check cases/bad.hcl
authnd: DIT structure rules: authnd names its people uid=<name>,ou=people,dc=example,dc=org, and an account named so is refused: the RDN (uid) is allowed by the name form of no DIT structure rule that places account under an entry governed by the rule 2: accountByCN needs cn
```

authnd names its people `uid=<name>`: the rules have to allow it. And a
schema whose rule for `organizationalUnit` has no `SUP`, so that an
`organizationalUnit` can only be at the root, leaves both `ou=people` and
`ou=groups` without a place, and says both at once:

```
$ authnd check cases/root.hcl
authnd: DIT structure rules: ou=people,dc=example,dc=org, where authnd publishes its people, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
DIT structure rules: ou=groups,dc=example,dc=org, where authnd publishes its groups, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
```

Both exit with status 1. The files behind them (`cases/bad.schema` and
`cases/root.schema`) hold the same five name forms and only the structure rules
that make the point.

### Where authnd and slapd differ {#rules-slapd}

go-authn/ldap reads the OpenLDAP files, and some of the rules are OpenLDAP's.
These are the differences, said rather than discovered:

- **slapd implements content rules only.** It has no directive for name forms
  or structure rules. `Format` writes `nameform` and `ditstructurerule`
  keywords, which are this library's, and slapd refuses them: keep those in the
  HCL, or in a file only authnd reads. `ditcontentrule` is slapd's.
- **An `OBSOLETE` rule is inactive** (RFC 4512 §4.1.6), as is its name form
  or structure rule. slapd refuses the entry instead.
- **Without a content rule, auxiliary classes are allowed.** That is slapd's
  behaviour (its `SLAP_DISALLOW_AUX_WO_CR` flag is set by no `disallow`
  keyword), and authnd's. RFC 4512 §2.4.3 says otherwise; the library offers it
  as `ValidateOptions{StrictAuxiliary: true}`, and authnd does not set it.
- **libldap cannot read a structure rule's `SUP`.** A structure rule with a
  `SUP` is read here and not by libldap, so libldap's refusal of such a file
  is not a verdict on the file.
- A file that **redefines** a rule is refused, even word for word, like every
  other definition ([above](#redefinition)).

### What it costs {#rules-cost}

Measured on 2026-10-26 with `BenchmarkPublish10k` (go-authn/authnd,
`rules_bench_test.go`): publishing 10,000 people makes **416 allocations per
entry** with the rules of `testdata/rules.schema` and **265** without. This
includes dropping a precluded description and validating again. The times,
192 ms against 118 ms, were measured at a load of 8 to 14 and are not a ratio to
trust; only the allocation counts are.

### Upgrading {#rules-upgrade}

Nothing changes for a schema without rules: v0.12.4 refused all three kinds, so a
configuration that started on it holds none. There is one exception. A
`schema { }` string that is **not valid UTF-8** (an overlong encoding HCL lets
through) started on v0.12.4 and is refused now, because it could not be
published as it was written.

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

The section on [DIT content rules, name forms and DIT structure rules](#rules) was run on 2026-10-26 with the v0.13.0 release binary (`authnd-darwin-arm64`, checked by `relverify` against `SHA256SUMS` and its attestation; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.13.0`; `authnd --version`: `authnd version v0.13.0`), OpenLDAP's `ldapsearch` and `ldapschema` built from the go-authn/ldap v0.11.0 tag (`go install`, go1.27.1; it has no release binary). Every output there was printed by those programs, in a scratch directory, on 127.0.0.1; the files behind the transcripts are shown or described beside them.
{{< /callout >}}
