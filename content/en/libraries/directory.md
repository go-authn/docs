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
go get github.com/go-authn/directory@v0.12.0
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
- **`sqldir` against a real SQLite database** through a real driver.
- **MD4** against RFC 1320's test vectors.

The coverage lane fails below 85% (its stated standard is 100%), and the
`nosql` and `noldap` builds are checked in CI.

## Reference

[pkg.go.dev/github.com/go-authn/directory@v0.12.0](https://pkg.go.dev/github.com/go-authn/directory@v0.12.0)
