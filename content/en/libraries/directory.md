---
title: "directory — who somebody is, and what proves them"
linkTitle: "directory"
weight: 50
description: "go-authn/directory: one model of a person and the credentials a source holds for them, over a list in memory, a SQL database, an LDAP server or HCL configuration."
tags: [libraries, directory, ldap, sql]
---

**Who is somebody, and what can prove them?** One model over a list held in
memory, a SQL database, an LDAP server, or `user` and `group` blocks in a
configuration file — and the point of it is the second half of the question.

```sh
go get github.com/go-authn/directory@v0.15.0
```

## What proves somebody is not one thing

It is a fact about protocols. NTLMv2 (SMB) is a challenge-response: the client
never sends the password, so the server must hold the password or
`MD4(UTF16LE(password))` — the NT hash — and **an LDAP bind cannot
authenticate an SMB session**. A KDC must *decrypt* with the person's key, so
only a source holding the password can back a realm. SSH needs a public key.
A second factor needs the secret behind the six digits.

So an `Identity` says which `Credential`s its source gave — `Password`,
`NTHash`, `Verifier` (a hash comparison or a bind), `PublicKeys`,
`TOTPSecret` — and `Identity.Can` lets a server say *you can use WebDAV and not
SMB* before somebody meets a refusal at a mount. Each protocol has its own
method:

| | answers | from |
|---|---|---|
| `Verify(password)` | anything handed the password | the source's verifier first (it may be an LDAP bind), else the held password, compared in constant time on SHA-256 digests so not even the length leaks |
| `NTKey()` | NTLMv2 | the published hash, or derived from the password; `ErrNoCredential` with neither |
| `Derive(f)`, `KerberosKey(f)` | a KDC, AWS SigV4 — anything that must *possess* the secret | the password only; the derivation is the caller's function |
| `Keys()` | SSH | `authorized_keys` lines |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | a column, or an LDAP attribute the caller names |

## The sources

| package | reads | imports |
|---|---|---|
| `directory` | a `Static` list, and a `Set` of sources in order | the standard library only |
| `directory/sqldir` | any `*sql.DB`, with **your** queries | no driver: the program picks one |
| `directory/ldapdir` | an LDAP server | `go-ldap/ldap/v3` |
| `directory/hcldir` | a `users` block naming a database or an LDAP server, and `user`/`group` blocks holding people | `x/crypto/ssh`, `hashicorp/hcl/v2`, `zclconf/go-cty` |
| `directory/ldaptest` | an LDAP server to test against | `glauth/ldap` |

In a `Set`, the **first** source that knows a name owns it, so a service
account written down locally need not be put in LDAP. Group membership is the
**union** of every source. Sources are read when a server starts; a password
check may reach the source every time, because a bind cannot be cached
without holding the secret.

`hcldir` does not decode HCL: the caller decodes the block and hands it over.
It imports HCL only to write, for `SetPassword`. The build tags `nosql` and
`noldap` leave a kind out of `hcldir` entirely.

## Example

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	local := &directory.Static{
		Name: "the configuration file",
		People: []*directory.Identity{
			directory.NewIdentity("dora", directory.WithPassword("hunter2")),
			directory.NewIdentity("eli", directory.WithVerifier(func(pw string) error {
				return directory.ErrWrongPassword // a bind against somebody else's LDAP, say
			})),
			directory.NewIdentity("svc-backup", directory.WithPublicKeys("ssh-ed25519 AAAA...elided... backup")),
		},
		Groups: map[string][]string{"staff": {"dora", "eli"}, "nobody": {}},
	}
	people := directory.NewSet(local) // more sources after it: sqldir, ldapdir...

	ids, _ := people.Identities()
	for _, id := range ids {
		fmt.Println(id.Name(), "password:", id.Can(directory.Password), "verifier:", id.Can(directory.Verifier),
			"keys:", id.Can(directory.PublicKeys), "from", id.Where())
	}

	// NTLMv2 needs MD4(UTF16LE(password)): dora's can be derived, eli's cannot.
	for _, id := range ids[:2] {
		_, err := id.NTKey()
		fmt.Println(id.Name(), "SMB:", err == nil, errors.Is(err, directory.ErrNoCredential))
	}

	// An empty group is an empty answer; a group nobody has is an error.
	fmt.Println(people.Members("nobody"))
	fmt.Println(people.Members("admins"))

	// @group is expanded; an empty group, or one nobody has, is refused.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	_, err := directory.Expand([]string{"@nobody"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
	_, err = directory.Expand([]string{"@admins"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[] <nil>
[] directory: no such group: "admins", in the configuration file
[dora eli svc-backup] <nil>
[] directory: the group has no members: "nobody": nobody would be allowed
directory: the group has no members: "nobody": nobody would be allowed true false
directory: no such group: "admins", in the configuration file false true
```

A held password also answers `Can(Verifier)`: it can be compared.

{{< callout type="info" >}}
**An empty group is a group: `Members` answers it, `Expand` refuses it**

From v0.12.0, `Set.Members` returns an empty list and no error for a group a
source has with nobody in it, so a server that lists groups can publish it.
`Expand` still refuses it, with `ErrEmptyGroup`, which is not
`ErrNoSuchGroup`: a group nobody has is a typo or a deleted group, an empty
one is a group to fill. A caller that tolerates a group granting nothing tests
for both. In v0.11.x, `Set.Members` returned `ErrNoSuchGroup` for an empty
group, and `Expand` of `@nobody` through the `Set` printed
`[] directory: no such group: "nobody"`.
{{< /callout >}}

## Attributes {#attributes}

From v0.13.0 an `Identity` can carry **attributes**: what a source says
about somebody that proves nothing — a `uidNumber`, a home directory, a mail
address. They are kept apart from credentials on purpose: a credential
decides who may log in, an attribute is *published* to everybody allowed to
search. A server such as [authnd]({{< relref "/authnd/entries.md" >}}) turns
them into the attributes of an LDAP entry, and its schema decides what the
entry is.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	a, err := directory.NewAttributes(
		directory.Attribute{Name: "uidNumber", Values: []string{"1000"}},
		directory.Attribute{Name: "mail", Values: []string{"dora@example.org"}},
		directory.Attribute{Name: "MAIL", Values: []string{"d.explorer@example.org", "dora@example.org"}},
	)
	fmt.Println(err)
	dora := directory.NewIdentity("dora", directory.WithPassword("hunter2"), directory.WithAttributes(a))
	fmt.Println(dora.Attributes().Names(), dora.Attributes().Get("UIDNUMBER"), dora.Attributes().Get("mail"))

	// What is published cannot hold a secret, nor what a server derives or answers itself.
	for _, name := range []string{"userPassword", "sambaNTPassword", "radiusHash", "cn", "memberUid", "2.5.4.35"} {
		_, err := directory.NewAttributes(directory.Attribute{Name: name, Values: []string{"x"}})
		fmt.Println(errors.Is(err, directory.ErrAttributeName), err)
	}
}
```

```
<nil>
[uidNumber mail] [1000] [dora@example.org d.explorer@example.org]
true directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "sambaNTPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "radiusHash" looks like it holds a secret (its name contains "hash"), and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "cn" is derived by the server from the name it publishes the entry under
true directory: not an attribute this package carries: "memberUid" is membership, which Members answers: a second answer would disagree with it
true directory: not an attribute this package carries: "2.5.4.35" is an OID: name it by its descriptor, so that what is refused by name stays refused
```

Names are RFC 4512 attribute descriptions, compared ignoring case and the
order of options, so `mail` and `MAIL` are one attribute, spelled the first
way it was given; an exact repeat of a value is kept once. Values are
strings and are not interpreted: `"1000"` is a `uidNumber` because a
server's schema says so. An empty value, or none, is refused.

| refused | why |
|---|---|
| 56 named secrets — `userPassword`, `authPassword`, `userPKCS12`, `sambaNTPassword`, `sambaLMPassword`, `unicodePwd`, `krbPrincipalKey`, `krb5Key`, `ipaNTHash`, `ipatokenOTPkey`, `oathSecret`, `olcRootPW`, … | read off RFC 4519, RFC 3112, RFC 2798 and the Samba, Active Directory, MIT and Heimdal Kerberos, FreeIPA, 389-ds and OpenLDAP schemas |
| any name containing `password`, `passwd`, `pwd`, `secret`, `credential`, `hash` or `privatekey` | a list only knows the schemas somebody read; the one standard name this would catch, `secretary` (RFC 4524), is allowed |
| `sshPublicKey` | it has its own path, `WithPublicKeys`, so that `Can(PublicKeys)` stays true |
| `uid`, `userid`, `cn`, `commonName`, `objectClass` | a server derives them from the name it publishes the entry under |
| `member`, `uniqueMember`, `memberUid`, `memberOf` | membership is what `Members` answers, and a second answer would disagree |
| `createTimestamp`, `modifyTimestamp`, `creatorsName`, `modifiersName`, `structuralObjectClass`, `governingStructureRule`, `subschemaSubentry`, `entryDN`, `entryUUID` | a server maintains them; a configuration could only forge them |
| a name in numeric form | refusals are by name, and `2.5.4.35` *is* `userPassword` |

`ReservedAttributes()` returns the whole list, 75 names with their reasons;
`CheckAttributeName` applies the rule alone, so a configuration can be
refused before anything is read.

Where they come from:

- **`hcldir`**: `attributes = { … }` in `user` and `group` blocks, a string
  or a list of strings per name; a number is refused with the fix in the
  message (*write it as a string, "1000"*), and `null` leaves the attribute
  out.
- **`sqldir`**: two optional queries, `users_attributes` and
  `groups_attributes` (`Queries.PeopleAttributes`, `GroupAttributes`), read
  **by column alias**: the first column is the name, every other column an
  attribute named by its alias. A column whose alias is not an attribute
  description, or names a credential, is refused with its column number
  before a row is read. `NULL` and `''` are absent, and several rows for one
  name add values. A group named only there exists, with nobody in it.
  ⛔ PostgreSQL lower-cases an unquoted alias (`as uidNumber` comes back
  `uidnumber`): the same attribute, spelled the database's way. Quote it,
  `as "uidNumber"`, where the spelling matters.
- **`ldapdir`**: `Config.Attributes` and `GroupAttributes` (`attributes`
  and `group_attributes` in a `users "ldap"` block) name what to copy from
  each person's entry and each group's, matched by RFC 4512 equivalence and
  kept in the configured spelling. Besides the list above, it refuses the
  `totp_attribute` and the group's naming and member attributes. A subtype
  the directory returns besides (`description;lang-fr` for `description`) is
  not copied: ask for it by name.

A group's attributes come from `Set.GroupAttributes`, through the optional
`GroupAttributer`: **the first source to give an attribute owns it**, so a
`gidNumber` in a local file overrides the directory's while a `description`
only the directory has comes through, and a broken source is an error even
when another answered. A person's attributes come with the person, from the
source that owns the name.

## Object classes {#object-classes}

From v0.15.0 a source can **declare** the auxiliary object classes its people
and groups carry, so that a server such as
[authnd]({{< relref "/authnd/schemas.md" >}}) can publish a site schema
(SUPANN, eduPerson). A class promises the shape of every entry (RFC 4512
§4.1.1), so it is never inferred from the attributes present, and never read
from the data: no database column, no upstream `objectClass` value. An
attribute appearing in a database cannot change a published class.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	c, err := directory.NewObjectClasses("supannPerson", "eduPerson", "EDUPERSON")
	fmt.Println(c.Names(), err)
	ann := directory.NewIdentity("ann", directory.WithPassword("hunter2"), directory.WithObjectClasses(c))
	fmt.Println(ann.ObjectClasses())
	fmt.Println(directory.NewIdentity("bob").ObjectClasses())

	// A class is a name, never a number or a filter.
	for _, name := range []string{"edu Person", "1.3.6.1.4.1.5923.1.1.2", "x)(objectClass=*"} {
		_, err := directory.NewObjectClasses("eduPerson", name)
		fmt.Println(errors.Is(err, directory.ErrObjectClassName), err)
	}
}
```

```
[supannPerson eduPerson] <nil>
[supannPerson eduPerson]
[]
true directory: not an object class name: "edu Person" is not a descriptor: a letter, then letters, digits and hyphens (RFC 4512 §1.4)
true directory: not an object class name: "1.3.6.1.4.1.5923.1.1.2" is an OID: name the class by its descriptor, so that what is refused by name stays refused
true directory: not an object class name: "x)(objectClass=*" is not a descriptor: a letter, then letters, digits and hyphens (RFC 4512 §1.4)
```

Names are kept in the order written, once each, ignoring case (`EDUPERSON`
repeats `eduPerson`). This package checks the **spelling** only, an RFC 4512
descriptor: numeric OIDs, spaces, quotes and parentheses are refused, and the
refusal is fuzzed. Whether a class is defined, AUXILIARY and not one the
server derives is the server's to check against the schema it serves.

Where they come from:

- **`hcldir`**: `object_classes` and `group_object_classes` in a `users`
  block of either kind, and `object_classes` in a `user` and a `group` block.
  An error carries the position in the configuration.
- **`sqldir`**: `WithObjectClasses` and `WithGroupObjectClasses`.
- **`ldapdir`**: `Config.ObjectClasses` and `Config.GroupObjectClasses`.

`Identity.ObjectClasses()` returns a copy of a person's list. A group's come
from `Set.GroupObjectClasses`, through the optional `GroupObjectClasser`,
beside `GroupAttributer`. **The first source that has the group and declares
classes decides, whole**: a source declaring nothing does not decide, and a
later source's different list is ignored, neither merged nor an error. (authnd
says so in `check`.)

`sqldir.ClosesDB()` hands a database to its source, and `(*sqldir.Source).Close`
closes it; `hcldir.Open` now returns the `*sqldir.Source` itself.

## ldapdir's defaults {#ldapdir-defaults}

| setting (`users "ldap"` / `ldapdir.Config`) | default from v0.14.0 | up to v0.13.0 |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`, `ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | the same |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | the same |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`, `ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | the same |
| `group_member_attribute` / `MemberAttribute` | none: `memberUid` (names) **and** `member` (DNs); set, it is the one attribute read | `memberUid` |

The three classes are the standard ones that carry a `uid`: `posixAccount`
(RFC 2307), `account` (RFC 4524 §3.1) and `uidObject` (RFC 4519 §3.14).
go-authn/authnd from v0.11.0 publishes a person without the POSIX attributes
as an `account` or an `inetOrgPerson`, puts `uidObject` on every person, and
publishes a group without a `gidNumber` as a `groupOfNames`. Under the old
defaults such people and groups were not read at all.

{{< callout type="warning" >}}
**v0.14.0 widens what an institution's directory gives**

A directory holding `account` or `uidObject` entries that are not
posixAccounts — service accounts, hosts named by uid, people imported from
elsewhere — now gives them to every program that kept the default, and each
of them can then be checked against the directory by a bind. Its
`groupOfNames` groups become groups, and an `@group` rule naming one now
grants what it says. A plain `inetOrgPerson` with none of the three classes
is still not read. To keep exactly the old set:

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**A `member` DN adds no person.** It maps to somebody only when it is, by
distinguishedNameMatch (RFC 4517 §4.2.15), the DN of an entry the people
search returned. A DN outside those entries, or naming nobody, maps to
nobody, and so does `uid=alice,ou=elsewhere,…` when alice was imported from
`ou=people`. Up to v0.13.0 a DN in the member attribute was reduced to the
value of its first RDN, whoever's it was, so `uid=alice,ou=elsewhere,…`,
`cn=alice,…` and `uid=zed,…` became members named alice, alice and zed.

`ldaptest`, the test directory, now applies base and filter to every search,
gives each person an `objectClass` (`Person.ObjectClasses`, by default
`top`, `account`, `posixAccount`) and has `groupOfNames` groups
(`GroupsOfNames`), so a test of a client's filters can fail.

## What it refuses, and why

- **A group with nobody in it**, and **a group no source has**, when `Expand`
  turns `@group` into people — errors, not empty lists: a configuration that
  grants nothing to nobody reads exactly like one that works. The first is
  `ErrEmptyGroup`, the second `ErrNoSuchGroup`, and `errors.Is` tells them
  apart. `Set.Members` answers an empty group with an empty list; a group no
  source has is `ErrNoSuchGroup` there too. A source that is *broken* is
  reported apart from one that lacks the group, and wins over an empty answer.
- **An LDAP directory reached in the clear.** A simple bind carries the
  password itself (RFC 4513), so `ldapdir.New` and a `users "ldap"` block
  refuse `ldap://` to another machine unless `StartTLS` is set. `ldaps://`,
  `ldapi://` and `ldap://` to a loopback address are accepted. There is no
  switch to turn this off.
- **An empty password at an LDAP bind.** In LDAP it is an *unauthenticated
  bind*, which most directories answer with success; `ldapdir` answers
  `ErrWrongPassword` without dialling.
- **Any other failed bind taken for a wrong password.** Only LDAP result 49,
  *invalidCredentials*, is `ErrWrongPassword`. A connection dropped during the
  bind, a directory answering busy (51) or unavailable (52), is returned as
  `ldapdir: the directory did not answer the bind: …`, wrapping the LDAP error.
  The password is refused either way; what changes is that a server's log no
  longer says *wrong password* to somebody who typed it right. Before v0.11.2
  every failed bind was `ErrWrongPassword`.
- **Credentials in an LDAP URL** — a URL is printed; `BindDN` and
  `BindPassword` are fields.
- **An NT hash that is not 16 bytes** (`ParseNTHash`), rather than padding it
  into a hash that fails every login as a wrong password.
- **`Derive` or `KerberosKey` for an identity without the password.** A
  verifier's yes is not a key.
- **An attribute that is a secret, or that a server answers itself** —
  [the list above]({{< relref "/libraries/directory.md#attributes" >}}) — wherever it is configured: in a block, as
  a SQL alias, or in ldapdir's list to copy.

{{< callout type="warning" >}}
**The NT hash and the TOTP secret are credentials, not hashes of one**

Whoever holds `sambaNTPassword` authenticates as that person exactly as if
they held the password; whoever holds a TOTP secret produces every future
code. `WithVerifier`'s error goes to the server, never to the client.
{{< /callout >}}

## What it is checked against

- **OpenLDAP's `ldapsearch`** reads `ldaptest`'s directory — the entries, the
  `sambaNTPassword` of the one person who has it, the group — and is refused
  with *Invalid credentials (49)* for a wrong password. The CI's Linux lanes
  install `ldap-utils`; where `ldapsearch` is absent the test skips, as
  nothing in this module's CI turns that skip into a failure.
- **`ldapdir` against `glauth/ldap`**, an independent LDAP server, not a fake;
  the fixture allows the unauthenticated bind, so the test fails if `ldapdir`
  stops refusing it first.
- **`sqldir` against a real SQLite database** through a real driver. The
  attributes queries were also run once by hand against PostgreSQL 18.6
  through pgx, not in CI: an unquoted alias came back lower-cased and was
  found anyway, a quoted one kept its case, and an alias naming
  `userPassword` was refused.
- **ldapdir's filters** against `ldaptest`, which from v0.14.0 applies them:
  the default user filter leaves out a plain `inetOrgPerson`
  (`TestTheDefaultUserFilter`), and the group filter adds no identity
  (`TestTheGroupFilterAddsNoIdentity`).
- **MD4** against RFC 1320's test vectors.

The coverage lane fails below 85% (its stated standard is 100%), and the
`nosql` and `noldap` builds are checked in CI.

## Reference

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
