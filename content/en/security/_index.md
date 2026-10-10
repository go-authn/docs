---
title: "Security"
linkTitle: "Security"
weight: 55
description: "What the programs refuse, how a revocation travels from the provider to every server, and how to tell a genuine binary from anything else."
tags: [security]
---

go-authn is asked to prove people, so its refusals are the design rather than
the exceptions. This section gathers the ones that cross program boundaries;
each program's own pages say what it refuses on its own.

## The refusals that matter most

| | what is refused | why |
|---|---|---|
| authnd | a search by anyone but a declared `reader` | a bind proves who somebody is; it is not permission to list everybody |
| authnd | a Kerberos ticket for a person whose source holds no password | a KDC needs a key derived from the password; an NT hash or a password check cannot produce one ([why]({{< relref "/authnd/kerberos.md" >}})) |
| authnd | a `kerberos` block beside an `mfa` block | a kinit carries the password and nothing else, so the realm would issue tickets on one factor to people the `mfa` block says need two |
| authn-bridge | an assertion nobody signed, an identifier from outside the institution's own scope | every member of a federation is trusted, so each must be held to its own people: otherwise any one institution could name anybody |
| authn-revokd | a list that is unsigned, expired, or older than the one it holds | a mirror in between may delay a list, never forge it or roll it back |
| authn-revokd | trusting a list that has lapsed | it writes one that revokes the CA itself, so sshd refuses rather than trusting a stale list |
| sshcert-authorize | a certificate whose domain grant does not name this host | a certificate from a federation CA is not, by itself, permission for every host that trusts that CA |

## A revocation, end to end

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) signs and dates a
   KRL (for SSH certificates) and a CRL (for X.509 client certificates), and
   publishes them.
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) fetches each list,
   verifies its signature and dates, refuses one older than the list it holds
   (across a restart too), and only then writes it where the server reads it.
3. sshd (`RevokedKeys`), go-fileshare and anything else read a file that has
   already been verified.

A CAEP `session-revoked` event, through the provider's Shared Signals
transmitter, voids what no list can name: everything issued to a person before
a given moment. go-fileshare's documentation describes the receiving side:
[revocation lists](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
[shared signals](https://go-fileshare.github.io/docs/latest/security/shared-signals/).

## Releases

Every binary is built by the release workflow from a tagged commit and can be
checked three ways: [verifying a download]({{< relref "/security/verifying-releases.md" >}}).
