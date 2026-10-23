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
go get github.com/go-authn/scim@v0.1.0
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

## What it is checked against

**What identity providers really send**, tested with their payloads: Entra
ID's `"Replace"`, its string booleans (`"active": "False"`), its member removal
by value list, its filtered add that creates an email; Okta's replace without a
path that repeats the `id`. The filter, PATCH and the whole handler are fuzzed
(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), and the coverage lane's floor is 92%.

## Reference

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
