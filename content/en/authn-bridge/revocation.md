---
title: "What it revokes, and how servers hear of it"
linkTitle: "Revocation"
weight: 60
description: "The signed, dated KRL and CRL authn-bridge publishes for the certificates it revoked, and the Shared Signals transmitter that reaches what no list can name."
tags: [authn-bridge, revocation, krl, crl, shared signals]
---

Disabling a person or an institution ([the admin API]({{< relref "/authn-bridge/admin.md" >}}))
ends everything that comes back to the provider: refresh tokens, `/userinfo`,
new certificates, application passwords. What it has already handed out is
checked elsewhere, against keys, and three mechanisms reach it:

| credential | taken back by |
|---|---|
| an SSH certificate this CA signed | the **KRL**, `GET /ssh/krl`, with its signature at `/ssh/krl.sig` |
| an X.509 client certificate | the **CRL**, `GET /x509/crl` |
| an access token, an opkssh certificate, anything a server verifies alone | a **Shared Signals** `session-revoked` event |

Revocation is permanent. Enabling a person again does not bring their
certificates back; they get new ones. A list a revocation could be taken out of
is a list somebody who reaches the admin API could edit.

## The lists

Both are issued as go-authn/revocation's protocol says, so that they can travel
through anything (a mirror, plain HTTP, a file) and still be checked by whoever
reads them:

| | KRL | CRL |
|---|---|---|
| format | OpenSSH `PROTOCOL.krl`, written by go-authn/krl: what `sshd`'s `RevokedKeys` and `ssh-keygen -Q` read | DER, RFC 5280 |
| signed | a detached SSHSIG by the SSH CA key, namespace `krl@go-authn.github.io` | by the CA that signs the certificates |
| current until | its `expires@go-authn.github.io` extension (which sshd ignores) | its `nextUpdate` |
| ordered by | its `krl_version`, then its generation date | its CRL Number, then `thisUpdate` |

Each list says it stops being current **an hour** after it is issued. A list is
kept and served unchanged until it is half way to that, or until something is
revoked; the next request then gets a new issue. An issue is never dated before
the one it replaces, even if the clock steps back, since a reader refuses an
earlier issue of the same version as a rollback. The CRL Number rises at every
issue.

The KRL from a test provider with nothing revoked:

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "db5b4e920d2da3911da51a8f70db8c4f"
Date: Sun, 11 Oct 2026 09:48:14 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261011T114814
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**The ETag is the content's.** A reader polls with `If-None-Match`, and gets
`304` while the issue it holds is still the one served; since the content
changes at least every half hour, a polling reader never keeps a copy past its
expiry:

```
$ curl -s -o /dev/null -H 'If-None-Match: "db5b4e920d2da3911da51a8f70db8c4f"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**The signature is fetched with `If-Match`** on the list's ETag. A list
issued again in between answers `412`, rather than a signature that does not
match it:

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "db5b4e920d2da3911da51a8f70db8c4f"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen` checks the signature, and refuses it in any other namespace:

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
```

where `allowed` is the line
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>`.

The CRL, issued fifteen seconds later:

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 11 09:48:29 2026 GMT
    Next Update: Oct 11 10:48:29 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            2A:90:7A:50:FF:65:52:BA:70:4E:E1:F8:70:EE:7A:FC:B1:8B:FE:4E
        X509v3 CRL Number: 
            1791712109993
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:37:90:14:6f:c1:f2:ea:98:29:04:61:88:a8:17:
        88:e3:f6:84:9d:46:a7:fc:2b:ac:81:26:47:9d:ac:84:23:38:
        02:20:0a:a6:93:cb:7d:2d:81:e4:59:d4:0d:a0:fd:f4:6e:75:
        c9:0d:53:e7:92:49:ac:a1:31:a8:90:09:91:d1:87:b6
```

A certificate stays in its list until it expires: an expired certificate is
refused everywhere without being listed.

### Who reads them

- A plain `sshd`, or nginx and other TLS servers:
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) fetches the lists,
  keeps only those that verify, writes them where the servers read them, and
  fails closed for sshd when a list lapses.
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
  fetches and verifies them itself, and refuses the provider's certificates
  while it holds no current list.

## Shared Signals

An access token or an opkssh certificate is checked where it is used, and no
list can name it. So the provider is an OpenID Shared Signals transmitter: on
`DisablePerson`, `RevokePerson` and `DisableIdP` it queues a CAEP
**`session-revoked`** event (everything issued to this subject before the
event's time is void) for every receiver that asked.

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **Poll delivery only** (RFC 8936): the receiver asks; nothing here dials out.
- A receiver authenticates with an access token from the **client
  credentials** grant, for an `ssf_receiver` client with a secret, scope `ssf`.
  It sees its own streams only, ten at most.
- Events are SETs (RFC 8417) signed with the ID token key, with no `exp` and no
  `sub`. The subject is the **account**, `acct:<username>`, by default: a `sub`
  may be pairwise, one per client. A receiver configured
  `ssf_subject_format = "iss_sub"` gets instead the issuer and the public `sub`.
- An institution disabled is one event per person the provider has a trace of
  there, and one whose subject is the **tenant**, the institution's entity ID,
  with its scopes, which covers the people the provider has forgotten.
- Streams and undelivered events are kept in the `state` database until
  acknowledged or `event_retention` passes. An event a receiver reports in
  error is handed out again, up to ten times.

The SSF block is refused without a `state` block:

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
