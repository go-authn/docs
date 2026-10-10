---
title: "A token at the bind, in a field that is not the password"
linkTitle: "Tokens (OIDC)"
weight: 75
description: "The oidc block: an OpenID Connect token carried in a SASL OAUTHBEARER bind, how many factors it counts for, and what is refused."
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}}) verifies a token into an
identity. The obvious way to carry one to an LDAP server is the password
field, and it works once and then stops: the password field is where the
[`mfa` block]({{< relref "/authnd/mfa.md" >}}) takes the code off the end, and
a token cannot be both.

So the token goes where the protocol has a place for it. A **SASL** bind's
credentials are an octet string of the mechanism's own shape, and RFC 7628's
`OAUTHBEARER` shape is a GS2 header followed by key/value pairs, one of which
is `auth=Bearer <token>`:

```
n,,^Aauth=Bearer eyJ…^A^A
```

The password field is left alone. On one listener, at the same time, a
person can type a password with a code on the end and another can send a
token.

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer` and `audience` are required. Without `username_claim`, the name is
`preferred_username`, then `email` when `email_verified` is true, then `sub`.
With the block, the root DSE advertises the mechanism:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

Without it, every SASL bind is answered `authMethodNotSupported` — *not this
way*, which sends a client somewhere different from *wrong password*.

## Discovery happens at startup

The provider's discovery document and keys are read when the server starts,
and by `check`. A provider that cannot be reached stops the server where
somebody is watching, rather than refusing every bind later:

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

An issuer that is not `https` is refused, except on loopback:

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## How many factors is a token?

**Whatever the issuer says it checked, and nothing more.** A token carries
RFC 8176's `amr`, the methods the provider used. That is the only evidence
there is, so it is what the `mfa` policy counts, **by kind**:

| `amr` method | kind |
|---|---|
| `pwd`, `pin`, `kba`, `mca` | knowledge |
| `otp`, `hwk`, `swk`, `sms`, `tel`, `sc`, `pop`, `user`, `wia`, `mfa` | possession |
| `fpt`, `face`, `iris`, `retina`, `vbm`, `geo` | inherence |
| anything else | unknown, which never satisfies `distinct_kinds` |
| no `amr` at all | one factor, possession — the token itself |

Two methods of one kind are one factor. The alternative would be this server
inventing a second factor nobody performed; and a server that believes the
issuer about *who* this is has no separate ground for disbelieving it about
*how* it checked.

With an `mfa` block, `check` says it:

```
$ authnd check sasl
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
or a token from http://127.0.0.1:18481, over SASL OAUTHBEARER over TLS
  a token counts for the factors its amr claim names, so one with no amr is refused by this policy
alice has no second factor here, so a password cannot satisfy this policy; a token whose amr names two kinds still can
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

alice has no `totp_secret`, so a password with a code can never be enough
for them; a token whose `amr` names two kinds can, as the first bind below
shows.

## What the binds look like

The issuer here is a small test provider on loopback, and `oidctool` a test
client written for these pages: it signs a token for the name given, with
the `amr` given, sends it in an `OAUTHBEARER` bind (with an `authzid` when a
fifth argument names one), and prints the bind's result code and the
server's SASL credentials. Against the configuration above, over `ldaps://`:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 0, serverSaslCreds 

$ ./oidctool alice '' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","kba"]' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls tess
bind result 14, serverSaslCreds {"status":"insufficient_scope","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}

$ ./oidctool zed '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 14, serverSaslCreds {"status":"invalid_token","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}
```

0 is success, 49 `invalidCredentials`, 14 `saslBindInProgress`. A
`["pwd","kba"]` token names two methods of one kind, so it counts once. And
to the same configuration without `cert_file` and `key_file`, on a plaintext
listener:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13 is `confidentialityRequired`: a token is not taken over a connection that
is not encrypted.

What the server wrote for the four binds over `ldaps://` that were refused:

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

and for the plaintext one:

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

A successful `OAUTHBEARER` bind leaves the connection bound as
`uid=<name>,ou=people,<base_dn>`, spelled as every other entry is.

## What it refuses

- **A token in the clear.** A bearer token needs no other half: whoever reads
  it off the wire is that person until it expires. `allow_plaintext = true`
  exists for a deployment that terminates TLS in front of this process, and
  `check` then says *a token may cross this socket in the clear*.
- **A request to be somebody else.** The GS2 header may name an `authzid`. A
  token for alice carrying a request to act as tess is refused, not quietly
  treated as either.
- **A token for somebody no source here publishes.** The client is told only
  `invalid_token`; which names exist is not something to hand out one guess
  at a time. The reason is in the server's output.
- **Channel binding.** A GS2 header with `p=` — the client insists on
  channel binding — is refused: this server does not do it, and accepting the
  header while binding nothing would let the client believe the channel was
  checked.
- **A mechanism this server does not speak**, with `authMethodNotSupported`.

A refusal of the token itself is RFC 7628 §3.2.3's: a JSON error carrying
`openid-configuration`, returned as `saslBindInProgress` so the client can
send the `^A` that ends the exchange. A token that verifies but does not
satisfy the `mfa` policy is answered plainly `invalidCredentials`, as the
second and third binds above show.

{{< callout type="info" >}}
**A token does not set a password**

A person who has only ever signed in with a token cannot use that session to
give themselves a first password, and a person who has one must still send
it to change it. See [changing a password]({{< relref "/authnd/passwords.md" >}}).
{{< /callout >}}
