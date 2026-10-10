---
title: "A second factor, over a protocol with one field"
linkTitle: "Second factor"
weight: 70
description: "The mfa block: a one-time code on the end of the password, how it is split and checked, what is counted against whom, and who cannot bind under it."
tags: [authnd, mfa, totp]
---

LDAP's simple bind carries a name and a password and nothing else — no place
for a code, no round trip to ask for one, and a client that speaks LDAP will
not learn one. So the code goes on the **end** of the password, which is
what appliances that do this do, and what people already know how to type:

```
password:  hunter2314159
           ^^^^^^^ ^^^^^^
           password  the six digits on their phone
```

```hcl
mfa {
  factors        = 2
  distinct_kinds = true     # two things they KNOW are not two factors
  # digits = 6, period = 30 (seconds) and window = 1 are the defaults
}

user "tess" {
  password_file = "/etc/authnd/passwords/tess.pw"
  totp_secret   = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"   # ⛔ this IS the second factor
}
```

| key | default | |
|---|---|---|
| `factors` | 2 | 1 is refused (*a password and nothing else: remove the block, or ask for 2*); above 2 is refused, since a bind carries a password and a code and no third thing |
| `distinct_kinds` | `false` | the factors must be of different kinds — what "two-factor" is normally taken to mean |
| `digits` | 6 | 6 to 10 (RFC 4226) |
| `period` | 30 | seconds one code lasts |
| `window` | 1 | steps either side of now that are accepted, for clocks that differ. Each step is a step of somebody else's guessing time: set it on purpose |
| `readers` | `false` | whether [readers]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) carry a code too. A service account has no phone; one that does gets a `totp_secret` in its `reader` block |

The secret can equally come from a database column (the fifth) or an LDAP
attribute (`totp_attribute`); see [people]({{< relref "/authnd/people.md" >}}).
A `totp_secret` in a `user` or `reader` block under 128 bits (RFC 4226 R6)
stops the server, naming the person, rather than failing every one of their
logins later:

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## Who cannot bind under it

```
$ authnd check mfa
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
alice has no second factor here, and cannot bind while one is required
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

That is the question to ask before turning the block on.

## What the binds look like

The same configuration served, tess's code computed from her secret at the
moment of the bind:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.only
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
dn:uid=tess,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.badcode
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.code
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin
dn:cn=reader,dc=example,dc=org
```

`tess.only` is her password with no code; `tess.both` her password and the
current code, sent twice; `tess.badcode` her password and `000000`;
`alice.code` alice's password and six digits. The client is told one thing —
*invalid credentials* — whichever half was wrong: which one is a fact about
the account, and telling somebody who has proved nothing narrows their next
guess. The server's own output says which:

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## What follows from the one field

- **The split is by length.** The last `digits` characters are the code. A
  password ending in digits is fine — that is why tess's password alone was
  read as a wrong password followed by a code. A field *no longer* than a
  code is refused rather than guessed at, because a short password cannot be
  told apart from one.
- **Both halves are always checked.** Returning early on a wrong password
  would say, in the time taken, which half was wrong.
- **A code is used once.** It is valid for a whole step, so a server that
  accepts one twice accepts a replay; every step up to the last accepted one
  is refused, not merely the same one.
- **Guessing is limited per name**, with go-authn/totp's defaults: after five
  wrong codes in a row a person is refused for fifteen minutes, the right
  code included, and after a hundred they are locked out until authnd
  restarts. The counts are kept in memory, per process.
- **Only a code behind the right password is counted**: otherwise anybody who
  knew a name could freeze its owner with five binds. Behind a wrong password
  the code is still computed, against nothing that remembers — the first
  line of the output above, *not looked at*.
- **A reader is counted under its DN as the configuration spells it**, so
  `CN=Reader` gets no fresh budget of its own.
- **Nobody enrolled is not a wrong code.** A person with no secret has
  answered nothing rather than answered wrongly, and the server's output
  says *nobody enrolled an authenticator for this person*.

## Not with a realm

A `kerberos` block and an `mfa` block in one configuration are refused: a
`kinit` proves the password and nothing else, and this KDC has no
second-factor pre-authentication. See
[the realm]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}}).

## Tokens, under the same policy

A token at the bind, with an [`oidc` block]({{< relref "/authnd/tokens.md" >}}),
is counted by what its issuer says it checked — the `amr` claim. A token with
no `amr` is one factor, and this policy refuses it.
