---
title: "Tokens, passwords and keys"
linkTitle: "Tokens"
weight: 40
description: "What an application gets from authn-bridge: ID tokens and access tokens, the device grant, application passwords for SMB and S3, and WireGuard keys."
tags: [authn-bridge, oidc, tokens, wireguard]
---

Every credential here starts with the same login at the person's institution.
What differs is who the credential is for, and how it is taken back. The
certificates are on [their own page]({{< relref "/authn-bridge/certificates.md" >}}).

## What the provider publishes

```
$ curl -s http://127.0.0.1:28473/.well-known/openid-configuration | jq .
{
  "authorization_endpoint": "http://127.0.0.1:28473/authorize",
  "authorization_response_iss_parameter_supported": true,
  "claims_parameter_supported": false,
  "claims_supported": [
    "sub",
    "iss",
    "aud",
    "exp",
    "iat",
    "auth_time",
    "nonce",
    "acr",
    "name",
    "given_name",
    "family_name",
    "preferred_username",
    "email",
    "groups",
    "eduperson_principal_name",
    "eduperson_scoped_affiliation",
    "eduperson_entitlement",
    "entitlements",
    "eduperson_assurance",
    "eduperson_orcid",
    "schac_home_organization",
    "voperson_id"
  ],
  "code_challenge_methods_supported": [
    "S256"
  ],
  "device_authorization_endpoint": "http://127.0.0.1:28473/device_authorization",
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ],
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "request_parameter_supported": false,
  "request_uri_parameter_supported": false,
  "response_modes_supported": [
    "query"
  ],
  "response_types_supported": [
    "code"
  ],
  "scopes_supported": [
    "openid",
    "profile",
    "email",
    "eduperson",
    "groups"
  ],
  "subject_types_supported": [
    "public",
    "pairwise"
  ],
  "token_endpoint": "http://127.0.0.1:28473/token",
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "none"
  ],
  "userinfo_endpoint": "http://127.0.0.1:28473/userinfo"
}
```

The authorization code flow, with **PKCE S256 required for every client**. A
request with no `code_challenge_method` is refused rather than read as S256,
since RFC 7636 makes `plain` the default. A confidential client configured
`pkce = "or_nonce"` may send an OpenID `nonce` instead.

## The ID token

For the client, and about the login, not the person: RS256, `aud` the client
ID, `sub`, `auth_time`, `at_hash`, the `nonce` when the request had one, and
`acr` when the IdP said which authentication context it used. Lifetime
`id_token_lifetime`, five minutes by default.

**Nothing about the person is in it.** The claims the scopes release are at
`/userinfo`, as OIDC Core 5.4 says when an access token is issued, and one
always is. A client whose ID token is itself the credential, such as opkssh,
sets `id_token_claims = true` to have them copied in. An ID token is only
issued for a request with the `openid` scope.

| scope | releases |
|---|---|
| `profile` | `name`, `given_name`, `family_name`, `preferred_username` |
| `email` | `email` (never `email_verified`) |
| `eduperson` | `eduperson_principal_name`, `eduperson_scoped_affiliation`, `eduperson_entitlement` and `entitlements`, `eduperson_assurance`, `eduperson_orcid`, `schac_home_organization`, `voperson_id` (the SAML `subject-id`, lower-cased) |
| `groups` | `groups` |

## The access token

For the resource servers in the client's `audience`, as RFC 9068 describes:
signed with `signing_key_file` (RS256) or `access_token_key_file` (ES256),
`typ: at+jwt`, valid `token_lifetime` (an hour by default). It carries what a
resource server needs to decide without asking anybody: `preferred_username`,
`groups`, `idp` (the entity ID of the IdP that vouched), `scope`, `client_id`,
and `session_end` when the IdP said when its session ends.

A client whose `audience` names several resource servers can ask for a token
addressed to one of them, with RFC 8707's `resource`: see
[several resource servers]({{< relref "/authn-bridge/resources.md" >}}).

### What it leaves out, and why {#what-it-leaves-out}

**No `auth_time` and no `acr`**, although RFC 9068 allows both. They stay in
the ID token, where OIDC Core puts them. Nothing reads them from an access
token: not this provider, which looks a token up by its `jti`, and not
go-fileshare. An access token, however, is also pasted as an SSH
keyboard-interactive answer (ssh-oidc's mccli, checked by motley-cue at
`/userinfo`), and OpenSSH reads 1023 characters of one; an IdP's `acr` alone,
`urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport`, is about
90 of them. Before v0.22.0 the access token carried both.

The length of an ES256 access token (`access_token_key_file`) for a long eppn
and three AARC entitlements, measured by authn-bridge's `TestES256AccessTokens`
with an issuer of a real length, against the `shibmd:Scope` lengths of
RENATER's metadata (743 scopes):

| scope length | | characters |
|---|---|---|
| 13 | median | 885 |
| 22 | 95th percentile | 945 |
| 29 | 99th percentile | 992 |
| 44 | the longest | **1092: over** |

Before v0.22.0 the same token was 1014 / 1074 / 1121 / 1221 characters: over
from the 95th percentile on. What still does not fit is the longest scopes
and, above all, many groups: every entitlement adds its whole URN, and nothing
bounds how many an IdP sends. An RS256 access token, signed with a 3072-bit
key, is about 1150 characters before any group, so a token meant for SSH is
signed ES256. Past 1023 characters, mccli asks motley-cue for a one-time
password instead, which motley-cue allows by default; a token pasted into plain
`ssh` has to fit.

A token holding one of the provider's own scopes (`ssh`, `nfs`,
`app_password`, `wireguard`, `wireguard_peers`) is addressed to **the provider
alone**: its `aud` is the issuer, and those endpoints refuse any other. A token
a resource server received cannot be replayed here:

```
$ curl -s -X POST http://127.0.0.1:28473/ssh/certificate -d x -D - -o -
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Www-Authenticate: Bearer error="invalid_token"
X-Content-Type-Options: nosniff
Date: Sun, 11 Oct 2026 09:48:07 GMT
Content-Length: 23

the token is not valid
```

An access token already handed out is a signed statement a resource server
checks on its own. What [`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})
ends is everything that comes back here with it; the resource server learns
from [Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}).

## Without a browser: the device grant

A WebDAV client, a script, a terminal has no browser to send to a university. A
client with `device = true` asks for a code (RFC 8628), and the person logs in
on any other device:

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone` prints
an access token, logging in the first time and refreshing after that; it is
golang.org/x/oauth2's device client, not one written here.

| | |
|---|---|
| user codes | eight letters from `BCDFGHJKLMNPQRSTVWXZ` (no vowels, no digits), valid ten minutes; ten **wrong** codes per host in that time (an IPv4 address, an IPv6 /64), and ten times as many for the /24 or /48 around it |
| polling | every five seconds; polling faster earns `slow_down` |
| waiting devices | at most 20,000; past that the oldest is pushed out rather than everybody refused |
| refresh tokens | rotated at every use, inside a family whose end is fixed at the login by `refresh_lifetime`; a retired one used again revokes the family and the access tokens it bought |

## Application passwords

NTLMv2 and SigV4 prove a secret the server must already hold, so no token will
do for SMB or S3. A client with `app_passwords = true` lets a token with the
`app_password` scope set one, generated and shown once:
`authn-bridge app-password --issuer ... --client files` (`--remove` deletes it).

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

The table is created if missing: `login, password, nt_hash, expires, idp`.
Only what the protocols need is stored: the NT hash for SMB, the password itself
only when `store` asks for it. go-fileshare reads it with a `users "sql"` block;
name the columns in its query, never `*`.

Disabling a person removes their password; disabling an institution removes its
people's. A removed password stops working in go-fileshare when it next reads
its directory.

## WireGuard keys

WireGuard authenticates a peer by its public key and nothing else: no
certificate, no expiry, no revocation. So the provider keeps the answer to
*whose is this key, and may it still connect?* The device's VPN client
registers the public key, for a lease; the private key never leaves the device;
a gateway reads the live keys as a list signed for it alone.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"   # keys are recorded beside the certificates

wireguard {
  lifetime = "24h"              # the default: how long a key is listed; registering again renews it
  max_keys = 10                 # the default: devices per person
}

client "vpn" {                  # what people log in with
  device         = true
  wireguard_keys = true
}

client "vpn-gw" {               # the gateway's own client
  secret_file     = "/etc/authn-bridge/vpn-gw.secret"
  wireguard_peers = ["vpn"]     # the clients whose keys it reads
  ssf_receiver    = true        # optional: told at once when somebody is disabled
}
```

| | |
|---|---|
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`, with a token of the `wireguard` scope; answers the lease's end |
| `DELETE /wireguard/key` | `{"public_key": "..."}`: the owner takes a key back |
| `GET /wireguard/peers` | for the gateway's own `client_credentials` token, scope `wireguard_peers`: a signed JWT of type `wireguard-peers+jwt`, addressed to that gateway, valid five minutes |

A key somebody else holds, a key that was taken back, and one key too many are
refused with `409`. A gateway client must be confidential, and must name clients
that have `wireguard_keys`. The format of the list, and the gateway's side, are
go-authn/wireguard's.

## OpenPubkey and opkssh

opkssh turns an ID token into SSH logins with no CA at all, and the token it
makes (a PK Token) outlives the ID token inside it. The provider returns the
`nonce` verbatim in the code flow and in the device flow, signs RS256, and keeps
a retired key **published** for as long as `retired_signing_key_files` names
it, so that a PK Token signed before a rotation still verifies:

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

Give opkssh a client of its own with `id_token_claims = true`: it matches people
on the PK Token's claims, and its ID token travels to every server it logs into.
