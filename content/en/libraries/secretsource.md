---
title: "secretsource — a secret from a reference"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource resolves a PIN, a password or a recovery code from a reference (a file, the macOS Keychain, a Secret Service, KeePassXC) so that no plaintext file has to stay on disk."
tags: [libraries, secretsource, secrets]
---

**Where does a PIN come from, when it must not sit in a file?** A **reference**
names where a secret lives; `secretsource.Open` fetches it. The reference holds
no secret, so it may sit in a flag, a script or a shell history.

```sh
go get github.com/go-authn/secretsource@v0.2.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:by-path/Keys/Yubikey PIN")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Reference | Reads |
|---|---|
| `file:PATH` | a regular file readable by its owner alone (mode 0600 or stricter); one trailing newline is stripped |
| `keychain:SERVICE/ACCOUNT` | a macOS Keychain generic-password item |
| `secretservice:SERVICE/ACCOUNT` | a freedesktop Secret Service item with attributes `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, KeePassXC's Secret Service integration) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | the one Secret Service item carrying all those attributes; several matches are refused |
| `keepassxc:by-uuid/HEX` | the KeePassXC entry with that UUID (32 hex digits) |
| `keepassxc:by-path/Group/Title` | the entry at that path (the root group's name is left out); a title shared by two groups is refused as ambiguous, use `by-uuid/` |
| `keepassxc:URL` | the entry whose URL field matches |

**No scheme runs a command**: a flag must never be able to start a process. A
reference with no scheme is refused, not guessed to be a path (`file:` is how a
path is written). A secret longer than 4096 bytes, or an empty one from a
manager, is refused, and a call ends with its context (2 minutes when it has no
deadline) even while the manager waits for you to unlock it.

## KeePassXC

KeePassXC is reached through its browser-integration protocol, on macOS and
Linux; Windows is not implemented yet.

1. In KeePassXC, enable *Settings > Browser Integration*.
2. Associate this machine once per database, and approve it in KeePassXC:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Check a reference without printing the secret:
   ```sh
   secretsource check 'keepassxc:by-path/Yubikey PIN'
   ```

The first read of an entry shows KeePassXC's access dialog.

Used by `fido --pin-from` (see [fido]({{< relref "/libraries/fido.md" >}})) and
by `theca --pin-from`, `--password-from` and `--recovery-from`.

## Reference

The README at
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) is
the source of truth for this page.
