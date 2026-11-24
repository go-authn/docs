---
title: "sdcreds — systemd credentials, without systemd"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds reads and writes the systemd credential format (systemd-creds encrypt and decrypt) from Go, with a command line and an s6 helper that gives a supervised service its $CREDENTIALS_DIRECTORY."
tags: [libraries, sdcreds, secrets, s6]
---

**What if a service needs the credentials a systemd unit gets from
`LoadCredentialEncrypted=`, and there is no systemd?** `sdcreds` reads and
writes the [systemd credential](https://systemd.io/CREDENTIALS/) format
(`systemd-creds encrypt` / `decrypt`) from Go, with a command line and a helper
that gives an s6-supervised service the same `$CREDENTIALS_DIRECTORY`.

Supported keys: **null**, **host** (`/var/lib/systemd/credential.secret`) and
**host-scoped** (`--uid` / `--user`). TPM2 and public-key credentials are
recognised and refused with `*UnsupportedModeError`; nothing is guessed.

## Install {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

The version these pages describe is v0.2.0.

## Command line {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

The same from Go:

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run` decrypts every file of `--source` **before** mounting anything, mounts
a per-service `tmpfs` (`nodev,noexec,nosuid,nosymfollow,noswap`, mode 0700, size
and inode count bounded; `ramfs` if the kernel lacks those options), writes the
plaintext 0400 owned by the service user, remounts it read-only, sets
`CREDENTIALS_DIRECTORY`, then starts the service in a child that drops
privileges (`no_new_privs`, an empty capability set) and waits for it.

- `s6-run` is still the process that s6 supervises: it forwards `TERM`, `INT`,
  `HUP`, `QUIT`, `USR1`, `USR2`, `ALRM` and `CONT` to the service, exits with its
  status (128 plus the signal number if a signal killed it), hands on the
  descriptors it was given, and the service is killed if `s6-run` dies.
- The credentials are taken away when the service ends, and before `s6-run`
  fails if the program cannot be executed.
- The mount lives in a private namespace by default (`--unshare=false` turns
  that off), so it disappears with the service.
- A credential sealed with the null key is refused unless `--allow-null` is
  given, and one that carries no name is always refused.
- `sdcreds s6-finish --service=web` unmounts lazily and removes the directory;
  it is idempotent. With `--unshare=false`, a `SIGKILL` of `s6-run` leaves the
  mount in place until `s6-finish` runs: put it in the finish script of the
  service.
- At most 1024 credentials and 16 MiB per service. Linux only; elsewhere the
  commands report `ErrUnsupported`.

The key files named by `--secret` and `--machine-id-file` must be root-owned and
not writable by group or others, and so must every directory above them up to
`/`. The key file is opened once, without following a final link, and the key
is wiped from the memory of `s6-run` when it is done with the credentials. Only
the child takes the identity of the service; `s6-run` and all its threads stay
root.

### Keeping a capability: `--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

The flag is repeatable and comma-separated (`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`
or one flag each) and has **no default**: without it the service runs with every
capability set empty.

It is an **allowlist** of seven capabilities, none of them root-equivalent or
able to read or write the credential tmpfs or to signal `s6-run`:
`CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`, `CAP_NET_RAW`, `CAP_NET_BROADCAST`,
`CAP_IPC_LOCK`, `CAP_WAKE_ALARM` and `CAP_BLOCK_SUSPEND`. Any other capability,
or a name that is not a capability, is an error that names the allowlist,
reported before the key is read or anything is mounted.

The service has, in its bounding, permitted, inheritable, effective and ambient
sets, exactly the kept capabilities and nothing else. `no_new_privs` stays on,
and the securebits are 0x3 (`SECBIT_NOROOT` set and locked). `s6-run`'s own
privileges are unchanged.

`CAP_NET_ADMIN` acts on the network namespace the service runs in, which is the
host's unless the service is started in a network namespace of its own
(`--unshare` only gives it a private mount namespace): there it can change
interfaces, routes and the firewall. Run such a service in its own network
namespace when that matters.

## Interoperability {#interop}

Both directions are tested against the real `systemd-creds` **262.2**, built
from the `v262.2` tag (no distribution package).

- `testdata/systemd-v262.2` holds 44 credentials written by systemd-creds (null,
  host and host-scoped; with and without a name; no, past and future not-after;
  0 B, 1 B and 64 KiB payloads; five tampered variants), and `manifest.json`
  records what systemd-creds itself answered for each of 272 decryption attempts
  (right and wrong name, before and after not-after, with and without `--uid`).
  The library gives the same answer, with the same class of error, for every
  one.
- With a fixed IV, `Encrypt` reproduces systemd's bytes exactly.
- In the container, `systemd-creds decrypt` opens what `Encrypt` wrote, and the
  command line passes the same round trip in both directions.

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

Without `SDCREDS_REQUIRE_SYSTEMD=1` the tests that need the binary are skipped;
CI sets it, so an absent binary is a failure there. The 1 MiB boundary is
covered by the library tests only, not by interop vectors.

## Deviations from systemd {#deviations}

- A host secret whose machine id does not match is **refused**
  (`ErrHostKeyMachine`); systemd removes it.
- `--with-key=auto` means `host`: there is no TPM2 here.
- A credential sealed with the null key has no secrecy: `sdcreds decrypt`
  refuses it on every machine unless `--allow-null` is given (systemd instead
  consults the TPM2 and SecureBoot state; that library policy,
  `SystemNullPolicy`, is not used by the CLI).
- `SDCREDS_MACHINE_ID_FILE` (`encrypt`, `decrypt`, `setup`) points at another
  machine id file. `s6-run` ignores it and `SYSTEMD_CREDENTIAL_SECRET`: its key
  comes from the default files, or from `--secret` and `--machine-id-file`.
- A variable IV size is accepted when reading, as in systemd; this library
  always writes 12 bytes.
- The secret is opened without following a final symlink, and must be a regular
  file with one link and mode `0400`, as systemd requires.

## Safety {#safety}

Every length is checked before it is used, before anything is allocated, and on
both sides of its bound; credentials are limited to 1 MiB (as systemd) and the
host secret to 16 MiB. The parsers are fuzzed in CI with the corpus committed,
and `govulncheck` runs in CI. The README has no performance table yet: the
measurement is deferred, an open item and not a result.

## Reference {#reference}

The README at
[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) is the source
of truth for this page. See the module's `LICENSE`.
