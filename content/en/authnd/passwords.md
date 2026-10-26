---
title: "A person changing their own password"
linkTitle: "Changing a password"
weight: 50
description: "The one write authnd accepts: a person's own password, over RFC 3062 or an RFC 4511 modify, always with the old password, written back to the file that declares them."
tags: [authnd, passwords, ldappasswd]
---

A person may change **their own** password, and nobody else's, through the
RFC 3062 password modify operation (what `ldappasswd` sends) or an RFC 4511
modify. In both, **the current password must be sent with the new one,
whatever the connection bound with**. A session bound with an
[OAUTHBEARER token]({{< relref "/authnd/tokens.md" >}}) — short-lived, and
possibly one factor — could otherwise turn it into a permanent password that
also works for `kinit`.

This is OpenLDAP's ppolicy behaviour with `pwdSafeModify` set, with the
result codes its `ppolicy.c` returns. RFC 3062 §3 allows it: "If oldPasswd is
not present, the server MAY use other policy to determine whether or not to
change the password."

## With `ldappasswd`

`-t` is a file holding the old password, `-T` one holding the new; `-A` and
`-S` prompt for them instead.

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -T alice.new
Result: Insufficient access (50)
Additional info: a password change must send the old password with the new one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t wrong.pwin -T alice.new
Result: Server is unwilling to perform (53)
Additional info: the old password sent is not the current one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.new
dn:uid=alice,ou=people,dc=example,dc=org
```

The old password stops working at once, for a bind and — with a
[realm]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}}) —
for `kinit`. The server says so in its output:

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd does not generate a password: a request without a new one is refused
with `unwillingToPerform` (*this server does not generate passwords: send the
one you want*). A password it invented would have to be sent back over the
connection, and the one place it is certain to end up is a terminal's
scrollback.

## With `ldapmodify`

The change is a **delete of the old value followed by an add of the new
one, in one request**. RFC 4511 §4.6 applies a modify's changes in order and
atomically, so the delete — and the whole request with it — fails unless the
value deleted is the one held:

```
dn: uid=alice,ou=people,dc=example,dc=org
changetype: modify
delete: userPassword
userPassword: alice-test-pw
-
add: userPassword
userPassword: alice-new-pw
-
```

A bare `replace` proves nothing, and anything but `userPassword` is not
something this server changes:

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f replace.ldif
ldap_modify: Insufficient access (50)
	additional info: a password change must send the old password with the new one
modifying entry "uid=alice,ou=people,dc=example,dc=org"

$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f other.ldif
ldap_modify: Server is unwilling to perform (53)
	additional info: this server changes userPassword and nothing else, not cn
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

A modify that asks for a password **and** something else is refused whole:
a modify is atomic, and honouring half of it would report success for
something nobody asked for.

## Who can change what

| request | answer |
|---|---|
| no old password, or a bare `replace: userPassword` | `insufficientAccessRights` |
| an old password that is not the current one | `unwillingToPerform` |
| somebody else's entry | `insufficientAccessRights`, *a password may be changed only by the person it belongs to* |
| an anonymous connection | `insufficientAccessRights`, *an anonymous connection has not said who it is* |
| somebody with no password at all — they can only have bound with a token | `unwillingToPerform`: a bearer token is not a password, and does not set the first one. An administrator sets it in the configuration |
| somebody served from a `users` block | `unwillingToPerform`: authnd reads those sources and does not write them |
| the file cannot be written | `other` (80), *the password could not be written*; the reason is in the server's output |

The second-to-last, from the release binary, for dora, who comes from a
SQLite database:

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

The person is matched **by identity, not by DN**: the session's own name must
be exactly the target's, byte for byte, so a session bound as `uid=Backup`
cannot change `backup`'s password even though the two DNs compare equal. That
and the [refusal of names that differ only by case]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})
are two controls that do not depend on each other.

## Where the new password is written

Back into **the file that declares the person**, and nowhere else:

- a `user` block with `password_file` has **that file** rewritten, keeping
  its owner and group where the process may, and its mode narrowed to at
  most 0600 — never widened;
- a `user` block with `password` inline has the configuration file rewritten
  with the new value, keeping its comments, order and mode;
- a `user` block with only an `nt_hash` is not given a password: that would
  change what can prove them, which is a change to the configuration.

Every write goes to a temporary file **in the same directory**, then a
rename — so a full disk or a crash leaves the old password, not an empty
file. That needs write access to the directory. Under the packaged unit,
`ProtectSystem=strict` takes it away, and a change is refused like this:

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

with the reason in the server's output:

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-1822988247: permission denied
```

So keep the passwords in a directory of their own, writable by the service,
and the configuration read-only to it — the
[`ReadWritePaths=` drop-in]({{< relref "/authnd/install.md#the-configuration-directory" >}}).
A person whose password is written inline would need `/etc/authnd` itself
writable, which would also let the service rewrite its own configuration.

After a successful write, the configuration files are read again **for the
`user` blocks only**: an unrelated edit waiting on disk does not take effect
halfway because somebody changed a password. Everything else still waits for
a restart. The files are still read whole, though, so if one of them no
longer loads, the password is written and the client is told *the password
was written but this server did not reload it* — the running server keeps
the old one until it is restarted.
