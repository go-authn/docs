---
title: "scim — provisioning people and groups from an identity provider"
linkTitle: "scim"
weight: 140
description: "go-authn/scim is a SCIM 2.0 service provider (RFC 7643, RFC 7644): Users and Groups over a Backend you write, with Entra ID and Okta payloads tested. Standard library only."
tags: [libraries, scim, provisioning]
---

**Who has the identity provider just created, changed or deleted?**
An identity provider (Entra ID, Okta, Keycloak, …) creates, updates and deletes
people and groups in your application over HTTP; this package is that HTTP
endpoint, for Users and Groups (RFC 7643, RFC 7644), over a `Backend` you
write. Pure Go, `CGO_ENABLED=0`, standard library only.

```sh
go get github.com/go-authn/scim@v0.2.0
```

## Example

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

The Server assigns ids, timestamps and versions, validates input and applies
PATCH; the `Backend` keeps what it is given and enforces what only it can see:
`ErrConflict` for a taken `userName` (409 `uniqueness`), `InvalidValue` for a
member that does not exist (400 `invalidValue`), `ErrPrecondition` when the
stored version is not the one that was read. `NewMemory()` is the reference
implementation.

It serves `/Users` and `/Groups` (list with `filter`, `startIndex`, `count`,
`attributes`, `excludedAttributes`; create; get, `PUT`, `PATCH` and `DELETE` by
id with `ETag` and `If-Match`), `/Users/.search` and `/Groups/.search`, and the
discovery endpoints `/ServiceProviderConfig`, `/ResourceTypes` and `/Schemas`.
Filters cover the whole grammar of RFC 7644 §3.4.2.2; PATCH is atomic: an
operation that fails leaves the resource as it was.

## What it refuses, and why

Everything here comes from outside, so the limits are part of the API:

| | |
|---|---|
| a body over `MaxBodyBytes` (1 MiB), a PATCH with more than `MaxOperations` (100), or one that grows the resource past the body limit | 413 |
| a group with more than `MaxMembers` (10 000) | 400 `invalidValue` |
| a filter over 4 KiB, nested deeper than 32, with an unknown operator, or `gt` on a boolean | 400 `invalidFilter` |
| writes to `id`, `meta`, `schemas` or a user's `groups` | 400 `mutability` |
| a resource without its core schema, a `userName` that is empty, over 256 bytes or has control characters, two primary emails | 400 |
| a missing or wrong bearer token (`BearerAuth`, constant time; an empty token admits nobody) | 401 |
| any Backend error that is not one of the sentinels | 500 with a body that says nothing; the error goes to `ErrorLog` |

**Not supported**: bulk operations, sorting, password changes, `/Me`
(announced as such in `/ServiceProviderConfig`).

## What v0.2.0 changed {#v020}

From an audit, a fuzzing and chaos pass and a performance pass. What a caller can
see:

- **`Server.ReadTimeout`**, new, default 30 s: a request body that takes longer
  to arrive is cut off with a 400. It replaces the `http.Server`'s own
  `ReadTimeout` for the request; a negative value leaves the `http.Server`'s
  alone.
- **`ConditionalDeleter`**, a new optional interface a `Backend` may implement
  (`DeleteUserIf`, `DeleteGroupIf`), which `Memory` does. `DELETE` with
  `If-Match` used to check the version and delete in two steps, so a write
  landing between them was deleted unseen.
- **A lost race is redone.** A `PATCH` or `PUT` without `If-Match` that lost a
  race with another writer was answered 412 although the client asked for no
  precondition; it is now redone on the newer version, at most 32 times. With
  `If-Match` the answer is still 412. Of 24 concurrent PATCHes without
  `If-Match`, 9 failed with 412 before and none now.
- Removing a member, or any element, through a filter that matches nothing
  succeeds; it was a 400 `noTarget` (RFC 7644 §3.5.2.2).
- A PATCH without a path applies its keys in sorted order; it used the map's
  order, so `name` and `name.givenName` in one object gave a different resource
  from run to run.
- `BearerAuth` accepts the scheme name in any case (`bearer <token>`, RFC 7235
  §2.1).
- `startIndex` and `count` are clamped whatever the size of an `int`: a value
  beyond it was a 400 on 32-bit targets and a clamped page on 64-bit ones.
- A `Filter.Equality()` hands a `Backend` the decoded string. It is data: pass it
  to the database as a parameter, and never splice it into a query.

Bulk operations, sorting and password changes remain unsupported.

**Allocations** of one list request over 10,000 users and 200 groups on
`Memory`, exact, from `go test -bench`, Apple M4 Max:

| list request | before | after |
|---|---|---|
| a page of 100 | 789,417 allocations, 47.7 MB | 14,952 allocations, 6.0 MB |
| `userName eq` | 797,979 allocations, 47.7 MB | 90 allocations, 12.6 KB |
| a filter that scans every user (`name.givenName eq` and `emails[...]`) | 818,847 allocations, 48 MB | 361,098 allocations, 29.7 MB |

Wall-clock was not measured: the load was 65, and the rule is under 9. The noisy
single runs (about 1.7 s to 0.06 s for the scanning filter) are not a result.
`FuzzPatchPath`, `FuzzPatchThenDecode`, `FuzzFilter` and `FuzzServer` ran 45 s
each with 16 workers, 1.3 to 2.4 million executions, and found no failure.

## What it is checked against

**What identity providers really send**, tested with their payloads: Entra
ID's `"Replace"`, its string booleans (`"active": "False"`), its member removal
by value list, its filtered add that creates an email; Okta's replace without a
path that repeats the `id`. The filter, PATCH and the whole handler are fuzzed
(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), and the coverage lane's floor is 92%.

## Reference

[pkg.go.dev/github.com/go-authn/scim@v0.2.0](https://pkg.go.dev/github.com/go-authn/scim@v0.2.0)
