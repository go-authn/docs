---
title: "ldap — the bytes of an LDAP server"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap is the LDAP protocol as a server library: the wire, the filter, the operations and their limits, with handlers that decide what is answered."
tags: [libraries, ldap, directory]
---

**What are the bytes of an LDAP server?** A library, not a daemon: the wire,
the filter, the operations. [authnd]({{< relref "/authnd/_index.md" >}}) is the
server that runs it and owns the configuration, the directory sources and the
bind policy; this owns the bytes.

```sh
go get github.com/go-authn/ldap@v0.10.2
```

Written from RFC 4511 (the protocol), 4512 (the root DSE and the schema),
4513 (authentication), 4514 and 4515 (DN and filter string forms), 4517 and
4518 (syntaxes, matching rules, string preparation), 4526, 2696 (paged
results), 3672 (subentries), 3673, 4527 (read entry controls), 4532 (whoami)
and 3045.

A `Server` is a set of handlers, each an optional field: `Bind`, `SASL`,
`Search`, `Compare`, `Extended`, `Add`, `Modify`, `Delete`, `ModifyDN`,
`Abandon`. A nil one means *this server does not do that*, and the operation
is answered `unwillingToPerform` — not `insufficientAccessRights`, which would
start an argument about permissions that do not exist. The root DSE is
answered by the server itself, and publishes exactly what it honours.

## Example

A server with one person who can bind and a search that writes what the
filter matches:

```go
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"log/slog"
	"os"

	"github.com/go-authn/ldap"
)

var people = []*ldap.Entry{
	{DN: "uid=dora,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "dora")}},
	{DN: "uid=svc-web-prod,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-prod")}},
	{DN: "uid=svc-web-stage,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-stage")}},
}

// binder checks one password. A real one asks a directory: see go-authn/directory.
type binder struct{}

func (binder) Bind(_ context.Context, _ ldap.Session, req *ldap.BindRequest) (ldap.Result, error) {
	if req.Name == "" && len(req.Simple) == 0 {
		return ldap.Result{Code: ldap.Success}, nil // anonymous: the connection stays unbound
	}
	// A name with an empty password is an UNAUTHENTICATED bind (RFC 4513
	// 5.1.2). This package hands it to the handler, and the handler refuses it:
	// the comparison below does, since the password is never empty.
	ok := ldap.EqualDN(req.Name, "uid=dora,ou=people,dc=example,dc=org") &&
		subtle.ConstantTimeCompare(req.Simple, []byte("hunter2")) == 1
	if !ok {
		return ldap.Refuse(ldap.InvalidCredentials, "invalid credentials"), nil
	}
	return ldap.Result{Code: ldap.Success}, nil
}

// searcher writes each entry in scope that the filter matches, as it finds it.
type searcher struct{}

func (searcher) Search(_ context.Context, s ldap.Session, req *ldap.SearchRequest, w ldap.EntryWriter) (ldap.Result, error) {
	if s.BoundDN() == "" {
		return ldap.Refuse(ldap.InsufficientAccessRights, "bind first"), nil
	}
	for _, e := range people {
		if ldap.InScope(e.DN, req.BaseObject, req.Scope) && req.Filter.Matches(e) {
			if err := w.Entry(e); err != nil {
				return ldap.Result{}, err // the client went away, or a limit was reached
			}
		}
	}
	return ldap.Result{Code: ldap.Success}, nil
}

func main() {
	srv := &ldap.Server{
		Bind:           binder{},
		Search:         searcher{},
		NamingContexts: []string{"dc=example,dc=org"},
		Log:            slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// On anything but loopback: TLSConfig, and RequireTLS so that a
		// client that never asks for StartTLS is refused rather than
		// sending its password in the clear.
	}
	log.Fatal(srv.ListenAndServe("127.0.0.1:3389"))
}
```

Asked by OpenLDAP's `ldapsearch` (2.4.28, as macOS ships it), with dora's
password in a file:

```
$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw \
    -b ou=people,dc=example,dc=org '(uid=svc-*-prod)' uid
dn: uid=svc-web-prod,ou=people,dc=example,dc=org
uid: svc-web-prod

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -b ou=people,dc=example,dc=org '(uid=*)' uid
Insufficient access (50)
Additional information: bind first

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -s base -b '' namingContexts supportedLDAPVersion supportedExtension
dn:
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3

$ printf 'dn: uid=dora,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: uid\nuid: x\n' |
    ldapmodify -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw
ldap_modify: Server is unwilling to perform (53)
	additional info: this server does not modify entries
modifying entry "uid=dora,ou=people,dc=example,dc=org"
```

`(uid=svc-*-prod)` returns `svc-web-prod` and not `svc-web-stage`. The library
this one replaces evaluated that filter as `(uid=svc-*)` and returned
`svc-web-stage` as well; that defect is why this library was written. The
root DSE does not list StartTLS, because no `TLSConfig` was given.

## What it refuses, and why

**A filter means one thing.** It is parsed or decoded once into a tree, and
`String`, `EncodeFilter` and `Matches` all read that tree. An attribute that is
not an RFC 4512 §2.5 attribute description, or a matching rule that is not an
OID, is refused by both `ParseFilter` and `DecodeFilter`: before v0.6.1, printed
back, a "present" filter on the attribute `!x` read as a NOT.

**Plaintext, when it was promised otherwise.** StartTLS is asked for by the
*client*, so a server that merely offers it has promised nothing.
`RequireTLS` refuses every operation on a connection that is not protected,
with `confidentialityRequired`.

**A bind that failed keeps nothing.** RFC 4511 §4.2.1: the connection is made
anonymous when the bind request is *received*, and stays so unless the bind
succeeds — so a re-bind with a wrong password does not keep the previous
person's rights. A simple bind with no `Bind` handler is answered
`authMethodNotSupported`, and LDAPv2 is refused as a protocol error.

{{< callout type="warning" >}}
**The handler decides what an empty password means**

An unauthenticated bind — a name with an empty password, RFC 4513 §5.1.2 — is
passed to the `Bind` handler like any other simple bind, and a handler that
returns `Success` for it binds the connection as that name. Refuse it in the
handler, as the example does. [directory]({{< relref "/libraries/directory.md" >}})'s
`ldapdir` refuses it on the client side.
{{< /callout >}}

**A critical control it does not honour.** ManageDsaIT (RFC 3296), password
modify (RFC 3062) and cancel (RFC 3909) are named as constants because a
client may send them, not because they are answered: nothing here follows
aliases or referrals, so a critical ManageDsaIT is refused with
`unavailableCriticalExtension`.

**What an unauthenticated peer can hold:**

| | default | |
|---|---|---|
| `MaxMessageSize` | 4 MiB | a five-byte header claiming four gigabytes is refused before anything is reserved |
| `MaxMessageElements` | 16384 | BER elements counted before decoding: before v0.5.0, 4 MiB of empty strings held 373 MiB before any bind |
| `IdleTimeout` | 5 minutes | the whole message must arrive in time, not its first byte; negative means never |
| `MaxPending`, `MaxPendingAuth` | 100, 1000 | operations one connection may have in flight before it has bound (`MaxPending`) and after (`MaxPendingAuth`), as slapd's `conn_max_pending` and `conn_max_pending_auth`; a connection that goes over is sent a notice of disconnection and closed |
| `MaxPagedSearches` | 4 | paged searches open per connection, each a goroutine parked on its next entry |

Filter nesting is bounded as well: a stack overflow in Go kills the process.
Nothing logs an assertion *value* — a filter carries what somebody typed — only
the filter's shape.

**A paged search answers what was asked.** Until v0.8.0 the page reader sent
each entry as the handler wrote it: a paged search for `cn` alone came back
with every attribute, operational ones included, and `typesOnly` was
ignored, while the same search unpaged kept to the selection. `ldapsearch
-E pr=N` is how a client pages, so the same question got two answers. From
v0.8.0 both apply the selection, which `ldapsearch` itself checks in CI.

Without a schema — `Server.Schema` nil, the default — every comparison is
case-insensitive on the value: the safer of the two for reading, since it
never hides an entry an exact comparison would have found.

## The schema {#the-schema}

From v0.8.0, package `schema` is the directory schema of RFC 4512 §4, and
`Server.Schema` makes a server use it. Nil keeps a server exactly as it was.

- `schema.Standard()` embeds the definitions of RFC 4512, 4517, 4519, 4524,
  4523, 2798, 2307, 3672 and 3045, plus openssh-lpk's `ldapPublicKey` and
  `sshPublicKey` and the two OpenLDAP definitions they need, copied from the
  RFC text; each file in `schema/defs` names its source and section.
  `schema.Build(append(schema.StandardFiles(), mine)...)` adds a
  deployment's own, and refuses one whose SUP, rules, syntaxes, MUST or MAY
  do not resolve.
- `(*ldap.Entry).Validate(s)` checks one structural chain with every
  superclass listed, every MUST, nothing outside MUST and MAY, SINGLE-VALUE,
  known types, values of their syntax, and the RDN's values in the entry —
  and names **every** problem, as a `*schema.ValidationError`.
- With a schema, the root DSE carries `subschemaSubentry: cn=Subschema`, and
  a base search of `cn=Subschema` (`ldap.SubschemaDN`) is answered by the
  library, like the root DSE (RFC 4512 §4.2). The definitions come only when
  asked for by name or with `+`. It is behind the `RequireTLS` gate.
- Filters are evaluated with the schema's matching rules (RFC 4517 §4.2,
  with RFC 4518 string preparation) in RFC 4511's three-valued logic: an
  unknown attribute, a type with no rule for the match asked, or an invalid
  assertion value is **Undefined**, never an error. The server re-checks
  every entry a handler sends and drops those the filter does not make
  TRUE; a handler filters with `req.Matches(e)`, which uses the same schema.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap"
	"github.com/go-authn/ldap/schema"
)

func main() {
	s := schema.Standard() // RFC 4512, 4517, 4519, 4524, 2798, 2307, ... and openssh-lpk

	// An account with posixAccount, and no homeDirectory.
	eli := &ldap.Entry{DN: "uid=eli,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "top", "account", "posixAccount"),
		ldap.StringAttribute("uid", "eli"),
		ldap.StringAttribute("cn", "eli"),
		ldap.StringAttribute("uidNumber", "1001"),
		ldap.StringAttribute("gidNumber", "1001"),
		ldap.StringAttribute("mail", "eli@example.org"),
	}}
	var v *schema.ValidationError
	if errors.As(eli.Validate(s), &v) {
		for _, p := range v.Problems {
			fmt.Println("-", p)
		}
	}

	// uidNumber orders as an integer: 1001 >= 999, which as strings it is not.
	for _, f := range []string{"(uidNumber>=999)", "(uid>=a)"} {
		filter, _ := ldap.ParseFilter(f)
		fmt.Println(f, ldap.Evaluate(filter, eli, s))
	}
}
```

```
- mail is not allowed by any of the entry's object classes
- homeDirectory is required by posixAccount and is missing
(uidNumber>=999) TRUE
(uid>=a) Undefined
```

`mail` belongs to `inetOrgPerson`, not to `account`. `uid` has no ORDERING
rule, so a range on it is Undefined.

{{< callout type="info" >}}
**One departure from RFC 2307: `uidNumber` and `gidNumber` order as integers**

RFC 2307 gives `uidNumber` and `gidNumber` an EQUALITY rule and no ORDERING
rule, which would make every range filter on them Undefined — including the
one SSSD builds from `ldap_min_id` and `ldap_max_id`. slapd defines both
types itself with `ORDERING integerOrderingMatch`
(`servers/slapd/schema_prep.c`; its `nis.schema` comments them out as
"builtin"), and so does draft-howard-rfc2307bis-02 §2.1, so the embedded
definitions follow them. That, and allowing auxiliary classes without DIT
content rules (RFC 4512 §2.4.3 strictly forbids them; every server in use
allows them), are said rather than discovered.
{{< /callout >}}

Not there, deliberately: DIT content rules, DIT structure rules and name
forms; changing the schema over LDAP; RFC 4523's certificate matching rules
and `directoryStringFirstComponentMatch`, which are defined and not
implemented, so assertions using them are Undefined; collective attributes;
options other than `lang-` and `binary`.

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}) serves
this schema and holds every entry it publishes to it.

## Reading a large schema file {#reading-large-files}

Up to v0.10.0, `schema.Read` took time quadratic in the number of continuation lines of the file it read: a 4 MiB file of short continuation lines took about three minutes, and 1 MiB allocated 139.6 GB. A program that reads a schema file it does not control, as authnd does for its `schema_files` at startup, could be stalled by one. From v0.10.1 the time is linear (`TestManyContinuationLinesJoinInLinearTime`), and `Read` no longer copies and splits the whole file to look at its first line.

`schema.Format` wrote lines longer than 2000 bytes, which slapd and `Read` refuse; it now folds them. The strict parser is about 2.6 times faster, with 147 allocations instead of 498 on `cosine.schema`. Against libldap (macOS SDK, `ldap_str2attributetype` and `ldap_str2objectclass` with `LDAP_SCHEMA_ALLOW_ALL`) on the 54 definitions of OpenLDAP's `cosine.schema`, measured on 2026-10-26 on an Apple M4 Max at load 6.5 to 7.6 (`-cpu 1 -count 10`, benchstat): go-authn/ldap 25.65 µs ± 32 %, libldap 35.62 µs ± 2 %, about 0.72 times libldap's time. The Go side makes 147 allocations (20.6 KiB) per run; `-benchmem` cannot see libldap's C allocations, so there is no figure for them. To reproduce, run `go test -bench . -benchmem -cpu 1 -count 10` in `bench/libldap` of go-authn/ldap (it needs cgo and libldap). authnd has these fixes from v0.12.3.

From v0.10.2, the 13 DESC values of RFC 2307 in `schema.Standard()` are on one line. Up to v0.10.1 they were wrapped like the RFC's page and, because a continuation line keeps its indentation after the first character (slapd's `fp_getline`, which `Read` follows), a server that published them sent `DESC 'An integer uniquely identifying a user in an         administrative domain'`. authnd has the fix from v0.12.4.

## A schema that does not build {#build-error}

From v0.10.0, a definition `schema.Build` or `schema.BuildFrom` refuses is a
`*schema.BuildError`, found with `errors.As`. A program reports a refusal from
its fields, never by matching the message. Build stops at the first
definition it refuses, so there is one.

- `Kind` is one of every check Build makes: `UnknownReference`,
  `DuplicateOID`, `DuplicateName`, `SuperiorCycle`, `KindViolation`,
  `UsageMismatch`, `CollectiveMismatch` and `UsageViolation`.
- `Element` (syntax, matching rule, attribute type or object class), `OID` and
  `Name` (its first NAME) are the refused definition's, and `Pos` is where it
  starts: `file:line:column`, the line of the `.schema` keyword or of the LDIF
  `attributeTypes:` line, also when that line is folded or base64, and the
  block's own position for HCL. A definition built in code has none.
- `Field` is the term at fault (`SUP`, `EQUALITY`, `SYNTAX`, `MUST`, `NAME`
  ...), and `Ref` what the error refers to: the undefined name or OID, or the
  other definition, with its `RefOID` and `RefPos`. For a duplicate it is the
  first definition, and the message says where it is.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap/schema"
)

// An object class whose superclass is defined nowhere.
const site = `# site.schema
objectclass ( 1.3.6.1.4.1.99999.1.1 NAME 'siteMember'
	SUP top AUXILIARY )
objectclass ( 1.3.6.1.4.1.99999.1.2 NAME 'siteGuest'
	SUP nobody AUXILIARY )
`

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "site.schema", Data: []byte(site)})
	_, err := schema.Build(files...)

	var be *schema.BuildError
	if !errors.As(err, &be) {
		fmt.Println("not a BuildError:", err)
		return
	}
	fmt.Println("error:  ", be)
	fmt.Println("Kind:   ", be.Kind)
	fmt.Println("Element:", be.Element)
	fmt.Println("OID:    ", be.OID)
	fmt.Println("Name:   ", be.Name)
	fmt.Println("Field:  ", be.Field)
	fmt.Println("Ref:    ", be.Ref)
	fmt.Println("Pos:    ", be.Pos)
	fmt.Println("RefPos: ", be.RefPos.IsValid())
	fmt.Println("is UnknownReference:", be.Kind == schema.UnknownReference)
}
```

```
error:   site.schema:4:1: schema: the object class siteGuest has the superclass nobody, which is not defined
Kind:    unknown reference
Element: object class
OID:     1.3.6.1.4.1.99999.1.2
Name:    siteGuest
Field:   SUP
Ref:     nobody
Pos:     site.schema:4:1
RefPos:  false
is UnknownReference: true
```

Run from an empty module with `github.com/go-authn/ldap` v0.10.1. The first
class is fine; the second starts on line 4, and nothing else is at fault, so
`RefPos` is empty. Every definition `schema.Read` returns carries a `Pos` too,
and the Position's `String` leaves the column out when it is not known.

## Schemas in HCL2, and the converter {#hcl2-and-the-converter}

From v0.9.0, a schema can be written in HCL2 as well as in the files slapd
reads. Package `schema/hclschema` decodes HCL2 into the same
`*schema.Definitions` that `schema.Read` returns, and encodes them back
(`hclschema.Decode`, `hclschema.Encode`); `schema` itself keeps no HCL
dependency. One block is one definition, and its type says which:
`object_identifier`, `ldap_syntax`, `matching_rule`, `attribute_type` or
`object_class`. The label is the first NAME. The attributes are the terms of
RFC 4512 §4.1 in lower case with underscores (`desc`, `sup`, `equality`,
`single_value`, `kind`, `must`, `may`, and so on), and the `{len}` of a
syntax is `syntax_len`.

**Literal values only.** A value is a quoted string, a number, a boolean or a
list of those. A variable, a function, an operator or a `${...}` template is
refused before anything is evaluated, so reading a schema never runs it.
Each field is checked by the strict RFC 4512 parser, and the errors that need
a position come with the file, line and column.

The command `ldapschema` converts between the formats:

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.10.2
```

- `ldapschema to-hcl [--macros] FILE...` reads OpenLDAP `.schema` files,
  cn=config LDIF and subschema LDIF, and writes HCL2.
- `ldapschema to-schema [--macros] FILE...` reads HCL2 and writes an OpenLDAP
  `.schema` file.
- `ldapschema check FILE...` builds the definitions on top of
  `schema.Standard()` and reports.

Output goes to stdout. The exit status is 0 when the command worked, 1 when a
file or a definition is refused, and 2 on a usage error.

**The readers read files as slapd does**, because published schemas are
written for slapd: terms in any order, slapd's line continuation in a
`.schema` file and RFC 2849 folding in LDIF, base64 values, the `{N}` prefix
of cn=config, and `objectidentifier` macros resolved in file order. The
exported `Parse*` functions, and what a server publishes, stay strict RFC
4512.

An example, run from an empty directory with `ldapschema` v0.10.1. The
schema is invented for this page: 1.3.6.1.4.1.99999 is a private-use example
arc, not an allocation to anyone. One macro, one attribute type, one
auxiliary class:

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1 NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1 NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top AUXILIARY
	MAY siteBadge )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

attribute_type "siteBadge" {
  oid          = "1.3.6.1.4.1.99999.1.1"
  desc         = "the badge number"
  equality     = "caseIgnoreMatch"
  syntax       = "1.3.6.1.4.1.1466.115.121.1.15"
  syntax_len   = 32
  single_value = true
}

object_class "sitePerson" {
  oid  = "1.3.6.1.4.1.99999.2.1"
  desc = "a person with a badge"
  sup  = ["top"]
  kind = "auxiliary"
  may  = ["siteBadge"]
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( 1.3.6.1.4.1.99999.1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( 1.3.6.1.4.1.99999.2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 1 attribute types, 1 object classes
build: ok, 2 definitions added to schema.Standard()
```

Numeric OIDs are the default on output, because that is what a client sees in
the subschema; `--macros` keeps the macro names. `check` also reports the
definitions `schema.Standard()` already has, and every reference that nothing
defines, where `Build` stops at the first.

**`check` can exit 1 on a file that slapd loads.** OpenLDAP's `core.schema`
refers to four things that slapd builds in and that `schema.Standard()` does
not define: the syntaxes 1.3.6.1.4.1.1466.115.121.1.42 and
1.3.6.1.4.1.1466.115.121.1.43, and the matching rules `protocolInformationMatch`
and `presentationAddressMatch`. `ldapschema check core.schema` lists them as
`missing:` and exits 1. Read that as "not defined here", not as a defect of
the file.

**What it does not support:** DIT content rules, DIT structure rules and name
forms; `include` directives, since a `.schema` file is read as definitions and
is not run as a slapd configuration; and `X-SUBST` on `ldapsyntax`.

**Published schemas convert.** The release was measured on OpenLDAP's
`core`, `cosine`, `inetorgperson` and `nis`, on SUPANN 2021 from RENATER, on
eduPerson from REFEDS and on Samba's schema: for each, `.schema` to HCL and
back, and LDIF against `.schema`, give equal definitions. Only OpenLDAP's
files are in the repository. SUPANN and eduPerson are not reproduced here;
read them at their authors' pages:
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)
and [eduPerson](https://github.com/REFEDS/eduperson).

## What it is checked against

**OpenLDAP's `ldapsearch`**, in CI, and required where it is installed: the
Linux test lane, the race detector and the coverage lane set
`LDAP_REQUIRE_JUDGE=1`, so a missing client fails rather than skips. Windows
has none and skips those tests. `ldaptest`, this module's own wire client, is
deliberately not the judge: it asks only what `ldapsearch` cannot, about one
connection's state — two binds on one socket, a SASL bind with an arbitrary
mechanism, StartTLS followed by more LDAP.

`FuzzMessage` runs every message a client may send through the frame, the
decoders and the filter round trip. The coverage floor is 99.7%, with the three
unreached lines named in the workflow.

## Reference

[pkg.go.dev/github.com/go-authn/ldap@v0.10.2](https://pkg.go.dev/github.com/go-authn/ldap@v0.10.2)
