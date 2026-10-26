---
title: "Several resource servers: a token for one at a time"
linkTitle: "Resource indicators"
weight: 45
description: "RFC 8707 resource indicators in authn-bridge: a client whose audience names several resource servers asks for an access token addressed to one of them."
tags: [authn-bridge, oidc, tokens, rfc8707]
---

A client whose `audience` names several resource servers, such as a portal in
front of several file servers, gets access tokens addressed to **all** of them.
Any one of those servers can then take a token it received and present it to the
others: RFC 8707 §3 says this is why an audience should be restricted. Since
v0.21.0 the client can ask, with RFC 8707's `resource` parameter, for a token
addressed to **one** of them. This page describes v0.23.4; what v0.22.0 did
differently is [at the end](#departures).

Without `resource`, nothing changes: the access token is for the client's whole
`audience`, as [the tokens page]({{< relref "/authn-bridge/tokens.md#the-access-token" >}})
describes.

## The client

Nothing needs turning on. Every URI in the client's `audience` can be asked for.
The examples below use a confidential client with refresh tokens, and a device
client with the same audience:

```hcl
client "portal" {
  secret_file      = "etc/portal.secret"
  redirect_uris    = ["http://127.0.0.1:9/portal"]
  audience         = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
  refresh_lifetime = "8h"
}

client "files-cli" {
  device   = true
  audience = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
}
```

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-11-02T11:30:50Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
client        files-cli (public, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
```

`check` lists the audience and says nothing more about it. In particular, it does
not say which entries can be asked for: only an **absolute URI without a
fragment** can be. A logical name such as `fileshare`, or a URI with a `#`, is
accepted in `audience` and still goes into the token when no resource is named,
but a `resource` naming it is refused.

## A token for one server

The person logs in as usual (here, against a test federation, with the
authorization request naming no resource). The client then names one server
when it exchanges the code:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

The `aud` is the value asked for, exactly as it was sent, and nothing else. A
server that checks its audience, as [go-authn/oidc]({{< relref "/libraries/oidc.md" >}})
does, accepts this token at Paris and refuses it at Lyon.

## Another server, at the next refresh

The refresh token keeps the whole grant (RFC 8707 §2.2), so the next refresh can
ask for another server:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

The `scope` is the same for both servers: the provider does not reduce it per
resource.

## A server the client may not have

A resource that is not in the client's `audience` is refused with
`invalid_target`:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-nantes.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-nantes.example.org/\" is not one this client may ask a token for"
}
400
```

**A refused refresh does not spend the refresh token.** The request is checked
before the token is used up, so the same refresh token still works. Asked for no
resource, it gives a token for the client's whole audience:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
```

The value is compared with the `audience` entries as a string, not normalised as
a URI. The same server without its final `/` is a different resource:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org \
    -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-paris.example.org\" is not one this client may ask a token for"
}
400
```

## Bounding the grant at the authorization request

`resource` can also be sent with the authorization request. It then bounds the
grant: the code, and the refresh tokens that follow, are for that server, and a
later token request can name it again but never another one. After a login whose
authorization request carried `resource=https://fs-paris.example.org/`:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-lyon.example.org/\" was not part of the authorization"
}
400
```

The authorization request may carry **several** `resource` values: it is the one
parameter that may be repeated there. Each is checked, a value given twice counts
once, and the grant is for the servers named. After a login whose authorization
request carried `resource=https://fs-paris.example.org/` and
`resource=https://fs-lyon.example.org/`, the code gives a token for both, and
each refresh can ask for either:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

With a `state` block, the grant's resources are stored with the refresh token,
so a restart does not widen it.

A resource the client may not have is refused at the authorization endpoint too,
as an error sent back to the client's redirect URI. One such value among good
ones refuses the whole request:

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**At the token endpoint, one resource per request.** A token is for one server,
for the grant's servers, or for the whole `audience`; it is never for a list the
token request chooses. A second `resource` there is refused like any repeated
parameter:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_request",
  "error_description": "resource appears more than once"
}
400
```

## The rules

| | |
|---|---|
| **where** | `resource` is taken by the authorization endpoint, and by the token endpoint with the `authorization_code` and `refresh_token` grants |
| **how many** | at the authorization endpoint, several: each is checked, and one that is refused refuses the request. At the token endpoint, one: a second is `invalid_request` |
| **what may be named** | an absolute URI without a fragment that is, character for character, an entry of the client's `audience` |
| **the token's `aud`** | the resource named at the token endpoint; if none, the resources the authorization request named, in the order given; if neither, the client's whole `audience` |
| **a refresh** | may name one of the resources the authorization request named or, if it named none, any URI of the client's `audience`. The new refresh token keeps the whole grant |
| **refused** | `invalid_target`, sent back to the redirect URI at the authorization endpoint and returned as a `400` error by the token endpoint. A refused refresh does not spend the refresh token |
| **other grants** | `resource` with `client_credentials`, at the device authorization request or when polling for a device token is refused with `invalid_target`, not ignored: a client that asked for a token for one server must not receive one for another. A device token is always for the whole `audience` |
| **the provider's own scopes** | a token with `ssh`, `nfs`, `app_password`, `wireguard` or `wireguard_peers` is for the provider alone, and only the issuer itself may be named |

The refusal of other grants, at the token endpoint and at the device
authorization request:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=client_credentials \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

```
$ curl -s http://127.0.0.1:28473/device_authorization -d client_id=files-cli \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

## Where this departs from RFC 8707 {#departures}

| RFC 8707 | authn-bridge v0.23.4 |
|---|---|
| §2: "Multiple `resource` parameters MAY be used" | at the authorization endpoint, as written. At the token endpoint, one: a second `resource` is `invalid_request`, which §3 allows ("an authorization server may be unwilling or unable to fulfill a token request with multiple resources") |
| §2.2: the parameter applies "for all grant types" | only `authorization_code` and `refresh_token`. With `client_credentials` or the device grant it is refused with `invalid_target`, at the device authorization request as when polling |
| §2: the value "SHOULD NOT include a query component" | not checked. What is checked is that the value is absolute, has no fragment, and is in the client's `audience` |
| §2: the server "may map from that value to a more general URI or abstract identifier" | no mapping: `aud` is the value asked for, compared with `audience` as a string |
| §2.2: "the authorization server should downscope the scope value" for each resource | not done: the `scope` is the grant's, whichever server is named |
| §2.1: a request without `resource` MAY be processed "by using a predefined default resource value" | the default is the client's whole `audience` |
| §2.2: a refresh may be limited "to those [resources] that were originally granted", and the refresh token "is bound to the full original grant" | as written |

**Before v0.22.1**, v0.22.0 refused a repeated `resource` at the authorization
endpoint with an error page, as it refuses any other repeated parameter, so a
grant could not name two servers; and its device authorization request did not
read `resource`, so a device that asked for one server got a token for the whole
`audience`.
