---
title: "Running it: signals, restarts and what it says"
linkTitle: "Operations"
weight: 80
description: "What authnd reads once, why SIGHUP does not reload it, how it stops, what it writes to its output, and how to tell that it is up."
tags: [authnd, operations, signals, systemd]
---

## It reads everything once

The configuration files, every source behind them, the TLS certificate and
the keytab are read **at start**. There is no reload, and the packaged unit
has no `ExecReload=`. After changing any of them:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

The one thing applied while it runs is a
[password a person changes through authnd]({{< relref "/authnd/passwords.md" >}}),
which re-reads the `user` blocks and nothing else.

## Signals

| signal | what happens |
|---|---|
| `SIGTERM`, `SIGINT` | it prints `stopping`, closes the listeners **and every established connection**, stops the realm, closes the sources, and exits 0 once the server has really finished |
| `SIGHUP` | it is caught and logged, and authnd **stays up** without reloading anything |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
hangup: authnd does not reload; restart it to apply a changed configuration, certificate or keytab
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

That is one run: a `kill -HUP`, two attempts to change a password (the first
refused, the second accepted), then a `kill -TERM`.
The process was still there after the `SIGHUP`.

A `SIGHUP` used to **kill** authnd — Go's default for a signal nobody handles
— and systemd counts death by `SIGHUP` as a clean exit, so
`Restart=on-failure` did not start it again: one `kill -HUP` or one logrotate
`postrotate` took a directory down for good. It is caught now so that the
habit is harmless, and the line says what to do instead.

Closing established connections, not only the listener, is deliberate: a
server that stopped accepting and left its open connections answering would
look stopped and not be, which is the restart that does not take.

## What it writes

Everything goes to standard output, which under systemd is the journal
(`journalctl -u authnd`):

- at start, where it listens and whom it serves — `ldap on …`, `ldaps on …`
  or `ldap+starttls on …`, then `realm EXAMPLE.ORG on … (udp and tcp)` with a
  `kerberos` block;
- every refused bind under an `mfa` block, every refused token, every
  refused or completed password change, **with the reason** — which the
  client is never told; see [the second factor]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})
  and [tokens]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}});
- every request the KDC refuses, prefixed `kerberos:`, with the Kerberos error
  code; see [the realm]({{< relref "/authnd/kerberos.md#kinit-against-it" >}});
- the LDAP library's own log, in `slog` text form, at level info.

A plain wrong password on a simple bind, with no `mfa` block, is answered
`invalidCredentials` and not logged by authnd itself.

## When it does not start

A refusal is one line on standard error, prefixed `authnd:`, and exit
status 1; under the unit, `Restart=on-failure` then tries again every five
seconds and the line is in the journal each time. Everything `check` refuses
is refused here too, and the one thing only the server finds is an address
it cannot listen on — see
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
The LDAP listener, the certificate and the realm are all opened before the
first line is printed, so a server that cannot start prints only the
refusal. Here a second instance meets the first one's Kerberos port:

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

The `ldap on …` line, and `realm … on …` after it, mean both halves are
listening.

## Telling that it is up

There is no health endpoint and no metrics. What there is:

- **the process and its exit status** — under systemd, `systemctl is-active
  authnd`. If the LDAP listener or the realm stops of its own accord, the
  whole process ends with that error, so a live process is one whose two
  halves both answer;
- **the root DSE**, which answers an anonymous client and says which version
  it is talking to:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.11.0
```

On a [StartTLS listener]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}})
that query needs `-ZZ`. A probe that proves more — that a source still
answers — is a bind as a person or a reader kept for the purpose; with a
`users "ldap"` block, that bind reaches the directory behind this one.

## What lives where, and what a restart loses

| | |
|---|---|
| configuration, passwords, DSN, certificate, keytab | the files the configuration names; nothing is copied |
| a SQLite database | wherever its DSN says; `/var/lib/authnd` under the unit |
| second-factor counts and lockouts | memory only: **a restart forgets them**, including a person locked out after a hundred wrong codes |
| used one-time codes | memory only |
