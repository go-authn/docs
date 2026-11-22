---
title: "secretsource — a secret from a reference"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource resolves a PIN, a password or a recovery code from a reference (a file, the macOS Keychain, a Secret Service, KeePassXC, a systemd credential) so that no plaintext file has to stay on disk."
tags: [libraries, secretsource, secrets]
---

**Where does a PIN come from, when it must not sit in a file?** A **reference**
names where a secret lives; `secretsource.Open` fetches it. The reference holds
no secret, so it may sit in a flag, a script or a shell history.

```sh
go get github.com/go-authn/secretsource@v0.8.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Reference | Reads |
|---|---|
| `file:PATH` | a regular file readable by its owner alone (Unix: mode 0600 or stricter; Windows, since v0.7.0: an access list that grants no read or write right to anyone but the owner, SYSTEM and the Administrators group); one trailing newline is stripped; a file that is empty, or holds only a line ending, is refused with `ErrEmpty` (since v0.6.0), and a FIFO is refused as not a regular file |
| `keychain:SERVICE/ACCOUNT` | a macOS Keychain generic-password item |
| `secretservice:SERVICE/ACCOUNT` | a freedesktop Secret Service item with attributes `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, KeePassXC's Secret Service integration) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | the one Secret Service item carrying all those attributes; several matches are refused |
| `keepassxc:URL` | the KeePassXC entry whose **URL field** is that URL (`https://NAME.invalid/...` is a good, never-resolving choice); two entries with the same URL are refused as ambiguous |
| `systemd-creds:NAME` | (Linux, since v0.8.0) a systemd credential, returned byte for byte: no trailing-newline stripping, unlike `file:`. First the file `NAME` in `$CREDENTIALS_DIRECTORY` (placed by `LoadCredential=`, `LoadCredentialEncrypted=`, `SetCredentialEncrypted=`); else `NAME` or `NAME.cred` in `/etc`, `/run`, `/usr/lib` `credstore.encrypted`, decrypted by `systemd-creds decrypt`. Refused with `ErrUnavailable` on other systems |

`keepassxc:by-uuid/...` and `keepassxc:by-path/...` are **refused**: KeePassXC
2.8.0 crashes when a lookup finds an entry with no URL.

**No scheme runs a command**: a flag must never be able to start a process. A
reference with no scheme is refused, not guessed to be a path (`file:` is how a
path is written). A secret longer than 4096 bytes, or an empty one from a
manager or a `file:`, is refused (`ErrEmpty`), and a call ends with its context (2 minutes when it has no
deadline) even while the manager waits for you to unlock it.

## systemd credentials {#systemd-creds}

Grammar, exactly: `systemd-creds:NAME`, the scheme in lower case, a colon, then
the credential name as given to `LoadCredential=`, `LoadCredentialEncrypted=` or
`systemd-creds encrypt --name=`, for example `systemd-creds:smtp`. `NAME` is a
plain file name of 1 to 255 bytes: no `/` (so no path), not `.` or `..`, no
control character, and no `.cred` suffix (the suffix belongs to the file; `smtp`
finds `smtp` or `smtp.cred`).

- The file in `$CREDENTIALS_DIRECTORY` is opened with `O_NOFOLLOW`, must be a
  regular file owned by root or the caller, with no access for "other" (group
  bits are accepted: systemd gives a `User=` service a root-owned 0440 file with
  an ACL); the directory likewise. A symlink or a loose mode is refused.
- Otherwise `systemd-creds decrypt --name=NAME PATH -` is run directly: no shell,
  an empty environment, the secret read from standard output only, at most 4096
  bytes, ended with the context. A non-root caller tries `--user` (systemd 256 or
  later) first.
- No trimming: a trailing newline, NUL bytes and non-UTF-8 bytes are kept, so
  seal a password with `printf %s`.
- Measured on systemd 257 (Debian 13) with `--with-key=host`; not measured with a
  TPM2 key. A failed decryption returns `ErrUnavailable` and says the credential
  may need re-sealing.
- PCR binding: `--tpm2-pcrs=` defaults to none. A bare `--tpm2-pcrs=7` can lock
  every credential after a firmware or shim update or a vTPM migration. Prefer
  `--with-key=host+tpm2`, a signed PCR policy (`--tpm2-public-key`, PCR 11), or
  `systemd-pcrlock`, and keep a copy of the secret to re-seal from.

## KeePassXC

KeePassXC is reached through its browser-integration protocol, on macOS and
Linux; Windows is not implemented yet. Since v0.6.0, on Unix, the socket is
refused when it is a symbolic link or when its directory is owned by another user
or writable by group or others, and the uid of the connected peer is checked after
the dial; the legacy `$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer`
symlink is no longer followed (the real socket under `app/org.keepassxc.KeePassXC/`
is).

Since v0.6.1, the association file (the fallback store, used when neither the
macOS Keychain nor a Secret Service is there) is written to a new temporary file in
the same directory and renamed onto the final name, so a symbolic link left at that
name is replaced, not followed, and a file of looser mode comes out 0600. On Unix the
directory is checked first, as the socket's is: owned by this user, not writable by
group or others, not a symbolic link; otherwise nothing is written.

1. In KeePassXC, enable *Settings > Browser Integration*.
2. Associate this machine once per database, and approve it in KeePassXC:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Create the entry and **fill its URL field** with
   `https://fido.invalid/yubikey-5c` (any URL no other entry uses: the
   reference is that URL). Check the reference without printing the secret:
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

The first read of an entry shows KeePassXC's access dialog.

Used by `fido --pin-from` (see [fido]({{< relref "/libraries/fido.md" >}})) and
by `theca --pin-from`, `--password-from` and `--recovery-from`.

## Storing a secret: `secretsource store` {#store}

No entry has to be made by hand. `secretsource store REF [--group G]
[--login L] [--replace] [--generate N]` writes the secret for `keychain:`,
`secretservice:SERVICE/ACCOUNT`, `secretservice:KEY=VALUE` and `keepassxc:URL`:

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

The secret is typed twice with echo off, or read from standard input when that
is not a terminal; it is never taken from an argument or the environment.
`--generate N` draws N letters and digits and prints nothing secret. An
existing entry is refused unless `--replace` (for KeePassXC that updates that
entry, found by its URL). `file:` is refused.

For `keepassxc:` it uses the browser protocol's `set-login`, so the entry always
carries the URL that finds it again, and a duplicate is looked up by URL. The
login defaults to the URL's host (`--login`), the group is `KeePassXC-Browser
Passwords` unless `--group` names one below the root, and `--title` is refused
because KeePassXC 2.8.0 ignores it. KeePassXC shows its own dialogs.

## Reference {#reference}

The README at
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) is
the source of truth for this page.
