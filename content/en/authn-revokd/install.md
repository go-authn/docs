---
title: "Installing authn-revokd"
linkTitle: "Install"
weight: 10
description: "authn-revokd as a hardened systemd service, or as a one-shot on a timer, and how to wire sshd and a TLS server to what it writes."
tags: [authn-revokd, install, systemd]
---

The repository ships three units and an account in `packaging/`:
`authn-revokd.service` (the daemon), `authn-revokd-once.service` with
`authn-revokd-once.timer` (the alternative), and
`sysusers.d/authn-revokd.conf`.

| path | what | owner, mode |
|---|---|---|
| `/usr/local/bin/authn-revokd` | the binary | root, `0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | the `authn-revokd` system account | root, `0644` |
| `/etc/systemd/system/authn-revokd.service` | the daemon | root, `0644` |
| `/etc/authn-revokd/revokd.hcl` | the configuration, the default `-config` | root, `0644` |
| `/etc/authn-revokd/ca/` | the CA keys and certificates the lists must be signed by | root, `0755`; the files in it `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`, the only writable place | authn-revokd, `0755` |
| `/var/lib/authn-revokd/state/` | `state_dir`: the verified copies | authn-revokd, `0700` |
| `/var/lib/authn-revokd/sshd.krl` | an output: what `sshd` reads | authn-revokd, `0644` |

**Write the outputs to `/var/lib/authn-revokd`, and point the servers there.**
An output is written beside its final name and renamed over it, so its
*directory* must be writable. Making `/etc/ssh` writable would let the
`authn-revokd` account replace `sshd_config`. Outputs are `0644`, chmod-ed
explicitly despite `UMask=0077`, so that `sshd` and a TLS server running as its
own user can read them; the state stays `0700`.

## The binary, the account, the unit

A release carries `authn-revokd-<os>-<arch>` for Linux, macOS and Windows on
amd64 and arm64, with `SHA256SUMS` and build provenance
([verifying a download]({{< relref "/security/verifying-releases.md" >}})). Or
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.5`.

The account and the unit come from the `packaging/` directory of the release
tag, the same version as the binary: copy that directory beside the binary,
from a checkout of the tag or, for v0.6.5, from
<https://github.com/go-authn/revocation/tree/v0.6.5/packaging>.

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

The account is static, not `DynamicUser=`. authn-revokd refuses a state
directory owned by anyone but its own uid or root, and the state must keep
ordering the next list across restarts and upgrades. With a dynamic user the
files would sit under `/var/lib/private`, `0700` root, and a TLS server running
as its own user could not read the CRL.

## The daemon

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

and around it: `User=authn-revokd`, no capability at all, `NoNewPrivileges=`,
`ProtectSystem=strict` with `StateDirectory=authn-revokd` (`0755`) the one
writable place, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
`PrivateIPC=`, `AF_INET AF_INET6 AF_UNIX` only, `@system-service` system calls
minus `@privileged @resources`.

**`Restart=always`, because sshd ignores the expiry in the KRL.** The file is
failed closed by *this process* when a list lapses. While it is stopped, sshd
keeps reading the last file it wrote, and a revocation issued meanwhile never
arrives. Monitor the unit, or `/healthz` when the mirror is on.

**`systemctl reload` syncs now.** It sends `SIGHUP`, and the agent fetches every
source at once instead of at the next `refresh`:

```
hangup: syncing now
```

It does not re-read the configuration, which is read once, at start: after
changing `revokd.hcl`, `systemctl restart authn-revokd`. (Before v0.6.0 an
uncaught `SIGHUP` killed the process, and systemd counts that as a clean exit.)

### Enable it BEFORE wiring sshd

{{< callout type="warning" >}}
**sshd refuses every certificate when `RevokedKeys` names a file that does not exist**

So start authn-revokd first, and wait until the output is there:
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl` prints its comment,
`authn-revokd sshd` while every source is current.
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

Then, in `/etc/ssh/sshd_config`:

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

and `sshd -t && systemctl reload ssh`. sshd reads `RevokedKeys` at every
authentication, so it needs no reload when authn-revokd rewrites the file: the
atomic rename is enough.

### A TLS server's CRL

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

A TLS server reads its CRL when it loads its configuration, so it must be
reloaded when the file changes. An `on_change` command runs as the
`authn-revokd` account, which cannot `systemctl reload nginx`: let systemd watch
the file instead, as root, with a path unit (`PathChanged=` on the output) that
starts a `oneshot` running `systemctl reload nginx`.

## Or: `-once`, on a timer

`authn-revokd -once` syncs once and exits, `1` when a list is not current or
could not be fetched ([what `-once` reports]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
The outputs are written either way, and failed closed for sshd once a list
lapses.

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

The one-shot has the daemon's account and hardening. `TimeoutStartSec=5min`
keeps a sync that hangs on a source from outliving the next tick, and
`RandomizedDelaySec=10s` keeps a fleet started together from polling its
issuer in step.

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**Never enable both**: the units conflict, so starting one stops the other.
The daemon remains the better choice. It fails a lapsed list closed at its next
`refresh`, where the timer waits for its next tick, and only the daemon serves as
a mirror: `listen` is ignored with `-once`. A timer that stops firing is a daemon
that stopped, so monitor `systemctl status authn-revokd-once`.

## Upgrading, and going back

Install the new binary beside the old, swap, restart. The state carries over:
the verified copies keep ordering the next lists, so neither an upgrade nor a
rollback to an older binary lets an older list in.

## Uninstalling

Remove `RevokedKeys` and `ssl_crl` from the servers' configuration **first**,
and reload them: sshd refuses every certificate once the file is gone.
