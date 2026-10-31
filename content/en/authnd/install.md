---
title: "Installing authnd"
linkTitle: "Install"
weight: 10
description: "The release binary and how to check it, the authnd account, the systemd unit and what it grants, and upgrading, rolling back and removing it."
tags: [authnd, install, systemd]
---

The repository carries the two files a systemd host needs:
`packaging/sysusers.d/authnd.conf` (the account) and
`packaging/systemd/authnd.service` (the unit). This page explains both and
the steps around them. go-pkgx's versioned services are meant to do this for
you later; they do not exist yet.

## The release binary

Each tag publishes `authnd-<os>-<arch>` for linux, darwin and windows on amd64
and arm64 (`.exe` on windows), built with `CGO_ENABLED=0`, a `SHA256SUMS`
manifest, and a build provenance attestation for every binary.

```sh
version=v0.13.0
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

Stop if either check fails. The release workflow refuses to publish a binary
that does not report exactly the tag it is published under, so the version is
something to compare:

```
$ authnd --version
authnd version v0.13.0
```

### Building only what you want

The server is always there; two build tags leave out where people can come
from. `-tags nosql` drops the three database drivers (PostgreSQL through pgx,
MySQL/MariaDB, SQLite through modernc.org/sqlite) and the `users "sql"` block;
`-tags noldap` drops the LDAP client and the `users "ldap"` block. A
configuration naming a block the binary was built without is told so —
*this binary was built without SQL support (-tags nosql)* — rather than that
the block does not exist. The release binaries are built without tags.

## The account

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

A static account from sysusers.d, **not** `DynamicUser=`. The files authnd
reads — password files, a DSN, a keytab, a TLS key — are secrets given to the
`authnd` group ahead of time, and a [password change]({{< relref "/authnd/passwords.md" >}})
writes back into them. A dynamic uid does not exist until the service starts,
and a file it wrote would belong to a number that later means somebody else.

The two files come from the `packaging/` directory of the release tag, the
same version as the binary: copy that directory beside the binary, from a
checkout of the tag or, for v0.13.0, from
<https://github.com/go-authn/authnd/tree/v0.13.0/packaging>.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## What the unit grants, and why

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

The rest of the unit is the usual hardening (`ProtectHome`, `PrivateTmp`,
`PrivateDevices`, `ProtectProc=invisible`, the kernel and cgroup protections,
`MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`,
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`). Three things it
**leaves out** are deliberate:

| | |
|---|---|
| `ExecReload=` | authnd has no reload. It reads its configuration, certificate and keytab once; see [running it]({{< relref "/authnd/operations.md" >}}) |
| `PrivateUsers=` | inside a user namespace `CAP_NET_BIND_SERVICE` no longer applies to the host's network, and the bind to 389 is refused |
| `ProcSubset=pid` | it hides `/proc/sys`, where Go reads `net/core/somaxconn`, and every listener's backlog falls to Go's fallback of 128 |

`IPAddressAllow=`/`IPAddressDeny=` are not set either: which networks may ask
a directory is the site's to say, in a drop-in:

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

The one capability is for the privileged ports: LDAP 389, LDAPS 636, and
Kerberos 88 over UDP and TCP. A PostgreSQL or MariaDB on the same machine is
reached through its socket, which a read-only file system allows. The state
directory, `/var/lib/authnd`, is there for a SQLite database; authnd keeps no
state of its own — the second-factor lockout counts live in memory and are
reset at every restart.

## The configuration directory

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

Every file inside it `root:authnd`, mode `0640`. Secrets go in files named by
`*_file` keys rather than inline: a file has permissions, and a configuration
someone pastes does not. With `ProtectSystem=strict` the service cannot write
under `/etc`, which is right for the configuration and wrong for the
passwords people change themselves — give those a directory of their own:

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

Why that directory and not the file is explained in
[changing a password]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}}).

| key | default | |
|---|---|---|
| `base_dn` | — (required) | the root of the tree, e.g. `dc=example,dc=org`; a value with no `=` is refused |
| `listen` | `127.0.0.1:3893` | one address. Loopback by default: a directory that appears on every interface the moment it starts is a decision somebody should make on purpose. A site that needs LDAP and LDAPS runs two instances |
| `reader "<dn>"` | none | a service account that may search; see [who may read]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) |
| `refresh` | `60s` | how often every source is read again; `0` turns it off; see [running it]({{< relref "/authnd/operations.md" >}}) |
| `max_age` | unset | refuse stale data (`unavailable`) once the served data is older; see [running it]({{< relref "/authnd/operations.md" >}}) |
| `cert_file`, `key_file`, `starttls`, `publish_nt_hash`, `samba` | off | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`, `group`, `users` | — | [the people]({{< relref "/authnd/people.md" >}}); at least one `user` or `users` block |
| `kerberos` | none | [a realm]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | none | [a second factor]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | none | [a token at the bind]({{< relref "/authnd/tokens.md" >}}) |

A relative path in the configuration is resolved against the directory the
process runs in, not the configuration file's; the unit runs from `/`, so
write paths absolute.

Before every start:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check` is described on [its own page]({{< relref "/authnd/check.md" >}});
running it as `authnd` also proves the account can read every file.

## Upgrade, roll back, remove

Check the configuration with the **new** binary before it replaces the old
one, and keep the old one. The new binary is installed beside the old one
first: that makes it executable, and puts it where the `authnd` account can
run it.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

Compare `packaging/` at the new tag with what is installed (v0.12.0's is
v0.11.1's, unchanged). Rolling back is the same install from
`authnd.previous`, and a restart.

From v0.10.x to v0.11.0 the `check` above is the step that matters: a
configuration with `publish_nt_hash = true` and no
[`samba` block]({{< relref "/authnd/tls.md#the-samba-block" >}}) is refused
there rather than at the restart, and the lines after its tables say who is
no longer a `posixAccount` and which groups are no longer `posixGroup`s
([the entries]({{< relref "/authnd/entries.md" >}})).

⛔ From v0.11.1 to v0.12.0, upgrade whatever else you do: v0.11.1's release
binaries were built with Go 1.27.2 and are affected by GO-2026-6809
(crypto/x509), which v0.12.0, built with Go 1.27.3, is not. The configuration
needs no change; to serve a site's own schema, see
[site schemas]({{< relref "/authnd/schemas.md" >}}), and name the files by
absolute paths, since a systemd unit's working directory is `/`.

To remove it:

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`, `/var/lib/authnd` and the `authnd` account are left in place:
the first two hold people's credentials, and a uid that is reused can be
given somebody else's files. Remove them deliberately.
