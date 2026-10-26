---
title: "The entries authnd publishes, and the schema it serves"
linkTitle: "Entries and schema"
weight: 25
description: "What each person and group is published as, the schema served at cn=Subschema that every entry passes, how to add attributes in a file or a SQL query, and what is dropped or withheld."
tags: [authnd, ldap, schema, sql]
---

**Every entry authnd publishes passes the schema it serves.** From v0.11.0
each person and group is a standard-schema entry, built from what its source
gave, and checked with go-authn/ldap's `schema.Validate` against the schema a
client can read at `cn=Subschema` before it is ever returned by a search. A
client that reads the schema and believes it — an LDAP browser, a
synchronisation tool, a directory replicating this one — is shown what it was
told. Up to v0.10.2 every person was `top, person, posixAccount` with none of
the attributes those classes require, and `sambaNTPassword` sat on an entry
with no class that allows it.

{{< callout type="warning" >}}
**A consumer filtering on `posixAccount` or `posixGroup` sees fewer entries**

A person without `uidNumber`, `gidNumber` and `homeDirectory` is no longer a
`posixAccount`, and a group without a `gidNumber` is no longer a
`posixGroup`. A program that searches `(objectClass=posixAccount)` or
`(objectClass=posixGroup)` no longer finds them. That includes
go-authn/directory's `ldapdir` up to v0.13.0, and so go-fileshare until it
requires directory v0.14.0, whose defaults also read `account`, `uidObject`
and `groupOfNames` ([directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})).
Give people and groups those attributes, or point the consumer at
`(objectClass=uidObject)`, which every person carries.
{{< /callout >}}

## The shapes {#the-shapes}

Every superclass is listed, as RFC 4512 §3.3 asks.

| a person with… | `objectClass` | `cn` |
|---|---|---|
| no `sn` | `top`, `account` (RFC 4524 §3.1) | only when another class allows it |
| `sn` | `top`, `person`, `organizationalPerson`, `inetOrgPerson` (RFC 4519, RFC 2798) | yes |
| … and `uidNumber`, `gidNumber`, `homeDirectory`, all three | `+ posixAccount` (RFC 2307) | yes |
| … and SSH keys | `+ ldapPublicKey` (openssh-lpk), with `sshPublicKey` | |
| … and a published NT hash with a `sambaSID` | `+ sambaSamAccount` (Samba), with `sambaSID` and `sambaNTPassword`: see [the `samba` block]({{< relref "/authnd/tls.md#the-samba-block" >}}) | allowed |
| … always | `+ uidObject` (RFC 4519 §3.14), so `(objectClass=uidObject)` finds everybody | |

| a group with… | `objectClass` | members |
|---|---|---|
| a `gidNumber` | `top`, `posixGroup` (RFC 2307) | `memberUid`, names |
| no `gidNumber`, somebody in it | `top`, `groupOfNames` (RFC 4519 §3.5) | `member`, the DNs this server publishes |
| no `gidNumber`, nobody in it | `top`, `organizationalRole` (RFC 4519 §3.10) | none |
| a `gidNumber`, nobody in it | `top`, `posixGroup` | none: an attribute has at least one value |

`uid` is the person's name, and so is `cn` wherever a class allows it. An
`account` alone does not allow `cn` (its MAY is `description`, `seeAlso`,
`l`, `o`, `ou` and `host`), so a person without `sn` and without the POSIX
trio carries `uid` and no `cn`.

Why these choices, from authnd's own reasons:

- **`posixGroup` follows RFC 2307, not draft-howard-rfc2307bis-02.** The
  draft makes `posixGroup` AUXILIARY and expired unpublished; an AUXILIARY
  `posixGroup` would need a structural class beside it, `groupOfNames`, whose
  `member` an empty group cannot give.
- **`organizationalRole` for an empty group without a `gidNumber`.**
  `groupOfNames` and `groupOfUniqueNames` both require a member, and the ways
  of inventing one are false: `member: ""` names the root DSE, and the
  group's own DN makes it a member of itself. `organizationalRole` is the one
  standard structural class whose only MUST is `cn`, and it takes
  `description`, `ou` and `seeAlso` as `groupOfNames` does.
- **Auxiliary classes without DIT content rules.** RFC 4512 §2.4.3 forbids
  auxiliary classes on an entry whose structural class has no DIT content
  rule. Every directory server in use allows them, and so does `Validate`.

## Adding attributes {#adding-attributes}

What a source says about somebody that proves nothing — a `uidNumber`, a
home directory, a mail address — is an **attribute**, published as given.
They are go-authn/directory's [attributes]({{< relref "/libraries/directory.md#attributes" >}}),
from v0.13.0, and they are kept apart from credentials: a name that holds a
secret, or one the server derives itself, is refused before anything is
read.

### In a `user` or `group` block {#in-a-user-or-group-block}

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

A value is a string or a list of strings; `null` leaves the attribute out.
A number is refused, because an LDAP value is a string and authnd does not
choose how a number is spelled:

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

Refused the same way, whatever their case: any name holding a secret
(`userPassword`, `sambaNTPassword`, `unicodePwd`, `krbPrincipalKey` and the
rest of go-authn/directory's list, or any name containing `password`,
`passwd`, `pwd`, `secret`, `credential`, `hash` or `privatekey`);
`sshPublicKey`, which has `authorized_keys`; `uid`, `cn` and `objectClass`,
which the server derives; `member`, `memberUid` and the other membership
attributes, which `members` answers; the operational attributes a server
maintains; and a name in numeric form (`2.5.4.35` is `userPassword`).

### In a SQL database {#in-a-sql-database}

Two optional queries of a `users "sql"` block read attributes **by column
alias**. The first column is the person's or the group's name; every other
column is an attribute named by its alias:

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

- The positional `users` and `groups` queries are unchanged, and a sixth
  positional column is still refused: attributes come by name, in their own
  query.
- A column whose alias is not an attribute description (an unaliased
  expression such as `count(*)`), or names a credential, is refused with its
  column number before a row is read.
- `NULL` and `''` are absent. A name may come back on several rows, and the
  values of all of them are kept, so a join to a table of addresses gives a
  person several.
- A group named only in `groups_attributes` **exists**, with nobody in it:
  that is how a person's own primary group is written.

{{< callout type="warning" >}}
**The case of an alias is the database's**

PostgreSQL folds an unquoted alias to lower case: `as uidNumber` comes back
as `uidnumber`. Attribute names are case-insensitive, so it is the same
attribute and the entry is the same entry to every LDAP client, but the
spelling authnd prints is the database's. Quote the alias where the spelling
matters: `gid as "gidNumber"`. SQLite keeps an alias as written.
{{< /callout >}}

### From another LDAP directory {#from-another-ldap-directory}

A `users "ldap"` block copies the attributes it is told to, from each
person's entry and each group's: `attributes = ["mail", "uidNumber",
"homeDirectory"]` and `group_attributes = ["gidNumber"]`. See
[people]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

## A configuration, and what it publishes {#a-configuration-and-what-it-publishes}

The SQL block above, with a reader, over a SQLite database of five people and
four groups, as the v0.11.0 release binary checks it:

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

`PUBLISHED AS` is each entry's object classes, without `top`, and `WITH` its
attributes, read off the entries a search returns. hal has a `uidNumber`, a
`gidNumber` and a `mail` and no `homeDirectory` or `sn`: hal is an `account`,
which allows none of the three, so they are dropped and the rest is
published. The server says the same at startup (and `stopping` when it was
stopped):

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

Read back by OpenLDAP's `ldapsearch`, with the reader's password in a file:

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

`alumni` is named only in `groups_attributes`, so it exists with nobody in
it; without a `gidNumber` it is an `organizationalRole`. `nobody-yet` has a
`gidNumber` and nobody, so it is a `posixGroup` without `memberUid`.

Which class finds whom:

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

## What is dropped, and what is withheld {#what-is-dropped-and-what-is-withheld}

| given | the entry | why |
|---|---|---|
| `uidNumber`, `gidNumber`, no `homeDirectory`, no `sn` | `account, uidObject`, without the two | *no class of the entry allows it; posixAccount would* |
| `mail`, no `sn` | `account, uidObject`, without it | *no class of the entry allows it; inetOrgPerson would* |
| a type the schema does not define | the rest | *the schema served here does not define it* |
| `mail` on a group without a `gidNumber` | `groupOfNames`, without it | |
| two `homeDirectory` values with the POSIX trio | **withheld**: SINGLE-VALUE, nothing to drop | |
| a `gidNumber` that is not an integer | **withheld**: not of its syntax | |

**Only what a source gave is dropped**, and which attribute is not allowed
is `Validate`'s answer, not a second reading of the schema. The entry is
validated again after dropping. An entry that still fails is **withheld**:
it is absent from every search, the startup log names it, and `check` lists
it with every problem `Validate` found. An attribute authnd derives itself
(`uid`, `cn`, `objectClass`, `sshPublicKey`, `sambaSID`, `sambaNTPassword`)
that the schema refused would be a defect in authnd, and withholds the entry
rather than publish it without.

alice's `gidNumber` is a word here:

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

Served, alice can still bind and is in no search, and the server says why
at startup:

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

What is withheld is the entry a search returns, not the identity.

## The schema it serves {#the-schema-it-serves}

The root DSE names it (`subschemaSubentry: cn=Subschema`, on
[the root DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})),
and a base search of `cn=Subschema` returns it (RFC 4512 §4.2): the
standard definitions go-authn/ldap embeds — RFC 4512, 4517, 4519, 4523,
4524, 2798, 2307, 3672 and 3045, and openssh-lpk — plus Samba's
`sambaSamAccount`, `sambaSID` and `sambaNTPassword` when there is a
[`samba` block]({{< relref "/authnd/tls.md#the-samba-block" >}}). The
definitions are published only when asked for by name or with `+`. Trimmed
where marked:

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
attributeTypes: ( 1.3.6.1.1.1.1.0 NAME 'uidNumber' DESC 'An integer uniquely identifying a user in an         administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
attributeTypes: ( 1.3.6.1.1.1.1.1 NAME 'gidNumber' DESC 'An integer uniquely identifying a group in an         administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
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

The whole entry was 327 lines: 49 syntaxes, 40 matching rules, 36 matching
rule uses, 143 attribute types and 52 object classes. Unlike a search under
the base, the subschema entry, like the root DSE, is answered to an
anonymous client: the same query without `-D` and `-y` returned it.

**Filters use the schema's matching rules**, so `(uidNumber>=1000)`
compares integers. `uidNumber` and `gidNumber` have `ORDERING
integerOrderingMatch`, which RFC 2307 does not give them; slapd and
draft-howard-rfc2307bis-02 do, and so does go-authn/ldap
([its one departure]({{< relref "/libraries/ldap.md#the-schema" >}})).
As strings, `1000` sorts before `999`:

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

hal is not there: hal's `uidNumber` was dropped. A range on an attribute
with no ORDERING rule, such as `uid`, is Undefined and matches nothing.
