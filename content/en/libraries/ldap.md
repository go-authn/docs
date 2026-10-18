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
go get github.com/go-authn/ldap@v0.8.0
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

[pkg.go.dev/github.com/go-authn/ldap@v0.8.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.8.0)
