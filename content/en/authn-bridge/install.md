---
title: "Installing authn-bridge"
linkTitle: "Install"
weight: 10
description: "A static user, three directories and a hardened systemd unit: authn-bridge from a release binary to a running service."
tags: [authn-bridge, install, systemd]
---

The repository ships the unit and the user it runs as:
`packaging/systemd/authn-bridge.service` and
`packaging/sysusers.d/authn-bridge.conf`. Everything below runs as root unless
it says otherwise.

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | the binary |
| `/etc/authn-bridge/*.hcl` | the configuration, read in name order; `root:authn-bridge`, `0750`, files `0640` |
| `/var/lib/authn-bridge/` | keys, the subject salt, the SQLite state, the certificates issued, the disabled list; `authn-bridge`, `0700` |
| `/run/authn-bridge/` | the admin socket, when the configuration asks for one |

## The binary

A release carries `authn-bridge-<os>-<arch>` for Linux, macOS and Windows on
amd64 and arm64, a `SHA256SUMS` manifest and a build provenance attestation per
binary; [verifying a download]({{< relref "/security/verifying-releases.md" >}})
says how to check both. Or build it, which records the version in the binary:

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3
$ authn-bridge --version
authn-bridge version v0.23.3
```

The path matters: from v0.20.0 the program lives in `internal/app` and the
command in `cmd/authn-bridge`, so `go install github.com/go-authn/bridge@...`
builds nothing.

## The user, and why it is not a dynamic one

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

The unit names `User=authn-bridge`, not `DynamicUser=`. The signing key, the
subject salt, the SAML key and the certificate authorities are made **before**
the first start, live for years, and must keep one owner across reinstalls and
restores from backup. A dynamic user gets its UID when the service starts.

## The keys

Run `keygen` as the service's user, so that it owns what it writes. It refuses
to overwrite a file that is already there:

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

On a server the paths are under `/var/lib/authn-bridge`, and the command is
`runuser -u authn-bridge -- authn-bridge keygen ...`.

| flag | writes | for |
|---|---|---|
| `--key` | an RSA 3072 key | ID tokens (RS256), published at `/jwks` |
| `--salt` | 32 random bytes | every `sub`, which is an HMAC under it |
| `--access-token-key` | a P-256 key | access tokens signed ES256 instead, much shorter |
| `--ssh-ca` | an Ed25519 key in OpenSSH format | the [SSH certificates]({{< relref "/authn-bridge/certificates.md" >}}) and the KRL's signature |
| `--x509-ca DIR` | `DIR/ca.key` (P-256) and `DIR/ca.crt`, valid ten years, path length 0 | NFS client certificates and the CRL |

{{< callout type="warning" >}}
**Back up the salt, and never change it**

A new salt gives every person a new `sub`, and every relying party then
sees a new person. The same goes for deleting it on uninstall.
{{< /callout >}}

The SAML key and certificate are made with `openssl`: they are what the
federation registers and what every IdP encrypts to. The key must be RSA (IdPs
encrypt to it with RSA-OAEP). It is not the TLS certificate, and does not change
with it.

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

The federation's metadata signing certificate comes from the federation, and so
does its SHA-256 fingerprint: take the fingerprint from the federation's web
page, never from the same download as the certificate. See
[the federation side]({{< relref "/authn-bridge/federation.md" >}}).

## The unit

What it grants, in short:

- `Type=exec`, `Restart=on-failure`, `RestartSec=5s`, `TimeoutStopSec=20s`.
  The provider shuts its listener down within ten seconds of `SIGTERM`.
- `StateDirectory=`, `RuntimeDirectory=` (both `0700`) and
  `ConfigurationDirectory=` (`0750`), `UMask=0077`. With
  `ProtectSystem=strict`, everything else is read-only.
- No capability (`CapabilityBoundingSet=` and `AmbientCapabilities=` empty),
  `NoNewPrivileges=`, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
  `PrivateIPC=`, `ProtectHome=`, the kernel, clock, hostname and control
  groups protected.
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`: TCP for the listener,
  the metadata, an ACME CA and a database; a socket for the admin API.
- `SystemCallFilter=@system-service`, minus `@privileged @resources`, refused
  with `EPERM` rather than a kill.

It waits for `network-online.target`, because the metadata is fetched before
the provider listens.

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

The first line in the journal is the one shown on
[the overview]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}}).

### Changes need a restart

The configuration is read once. The unit has no `ExecReload=`, so `systemctl
reload` is refused rather than pretending. A `SIGHUP` (from logrotate, or habit)
is caught, logged and ignored. Left to Go's default it would kill the process,
and systemd would count that as a clean exit that `Restart=on-failure` does not
restart:

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

TLS certificate files are the exception: they are re-read when they change.

### Port 443

The default listener is `127.0.0.1:8080`, behind a TLS reverse proxy, and
needs no capability. To serve TLS itself on port 443 (`cert_file` or `acme`),
the provider needs `CAP_NET_BIND_SERVICE` and must leave the private user
namespace, since a capability held inside it does not apply to the host's
network:

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## Upgrading, and going back

Back up `/var/lib/authn-bridge` first: it holds the keys and the salt, which
cannot be made again. Keep the binary that works, install the new one, restart:

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

Going back is the same with `authn-bridge.previous`. A newer release may ship a
newer unit: compare it with yours, install it and `systemctl daemon-reload`
before the restart.

### Coming from `bridge`

The configuration is unchanged; only the command and the release assets were
renamed. Change every unit, script, cron job and `bearer_token_command` that
runs `bridge`. The log line and the error prefix now say `authn-bridge`, so an
alert that matched `bridge v0.` must match `authn-bridge v0.`. Metric names
(`bridge_*`), the `bridge_state` table and the user-side cache
(`go-authn-bridge` in the user's configuration directory, `~/.config` on
Linux) are unchanged, so `authn-bridge token` reuses the logins `bridge`
cached.
