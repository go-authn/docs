---
title: "The configuration"
linkTitle: "Configuration"
weight: 20
description: "authn-revokd's revokd.hcl: where the lists come from, what they must be signed by, which files they are written to, and the mirror."
tags: [authn-revokd, configuration]
---

One file, `/etc/authn-revokd/revokd.hcl` by default (`-config` names another).
It is read once, at start.

```hcl
state_dir = "/var/lib/authn-revokd/state"   # the verified copies: what orders the next list
refresh   = "1m"

source "univ-a-ssh" {
  url    = "https://login.univ-a.example/ssh/krl"    # and .../ssh/krl.sig beside it
  ssh_ca = "/etc/authn-revokd/ca/univ-a-ssh.pub"     # what the list must be signed by
}
source "univ-b-ssh" {
  url    = "http://mirror.cluster.local:8080/univ-b-ssh"   # a mirror: plain http is fine
  ssh_ca = "/etc/authn-revokd/ca/univ-b-ssh.pub"
}
source "univ-a-x509" {
  url     = "https://login.univ-a.example/x509/crl"
  x509_ca = "/etc/authn-revokd/ca/univ-a-x509.pem"
}

output "sshd" {                              # sshd_config: RevokedKeys /var/lib/authn-revokd/sshd.krl
  path    = "/var/lib/authn-revokd/sshd.krl"
  sources = ["univ-a-ssh", "univ-b-ssh"]     # merged into one file
}
output "tls" {                               # nginx: ssl_crl /var/lib/authn-revokd/univ-a.crl
  path    = "/var/lib/authn-revokd/univ-a.crl"
  sources = ["univ-a-x509"]
  format  = "pem"
}

# listen = "127.0.0.1:8080"                  # serve the verified lists: a mirror
```

## The keys

| key | default | |
|---|---|---|
| `state_dir` | | required, absolute; created `0700` if missing |
| `refresh` | `1m` | how often every source is fetched, a second or more; each wait varies by a tenth either way, so a fleet does not stay in step |
| `listen` | | `host:port`: serve the verified lists, a mirror; ignored with `-once` |

**`source "<name>"`**: one list. The name is letters, digits, `.`, `_` and
`-`, not starting with a dot, at most 64 characters: it names a file in the
state directory and a path of the mirror.

| key | |
|---|---|
| `url` | `https://`, `http://` or `file://`; a KRL's signature is fetched from the same URL with `.sig` appended |
| `ssh_ca` | the SSH CA's public key, one `authorized_keys` line: a KRL source. A certificate is refused here |
| `x509_ca` | the CA's PEM certificate: a CRL source |
| `max_age` | also refuse a list issued longer ago than this, besides its own expiry; refused on a source that feeds a CRL output |
| `revoke_keys` | let this source's list revoke **plain keys** in an output shared with other sources; KRL sources only |

**`output "<name>"`**: one file a server reads.

| key | |
|---|---|
| `path` | absolute; written beside itself and renamed over |
| `sources` | KRL sources, merged into one file; or exactly one CRL source |
| `format` | `der` (the default) or `pem`; CRL outputs only |
| `on_change` | a command and its arguments, run after the file changes, and again at every sync until it succeeds |

## One KRL for several CAs

`RevokedKeys` takes a single file before OpenSSH 10.3, so the KRL sources of an
output are merged, and **each list keeps its full effect on its own CA, and
none on another**:

- **Kept:** its serials and key IDs, its sections that name no CA (scoped to its
  own), and its own CA key, which revokes all its certificates.
- **Left out, and logged:** another CA's section, and another CA's key.
- **Plain user keys** are left out when the output has more than one source,
  unless the source has `revoke_keys = true`. A KRL cannot scope a key to one
  CA: sshd checks a certificate's own key against the file whoever signed it,
  so a key one CA names would lock its holder out under every CA of the file.
  An output with one source keeps them.

Each list is first merged alone. One that cannot be merged fails closed **for
its own CA only**; the merged file expires with the first of its current
inputs, so a reader that checks expiry sees authn-revokd stop.

## What one sync does {#sync}

Since v0.6.7, in the order a sync meets them:

- **Sources are fetched together**, at most 16 at once, each within two minutes
  (a fetch makes up to four requests). One upstream that never answers no longer
  delays every other source, and the outputs with them.
- **Each output file is compared with the disk at every sync** and written
  again if it differs, with `on_change` run: a file deleted, truncated or
  replaced behind the agent's back used to stay that way until the list next
  changed, and sshd refuses every login when its `RevokedKeys` is unreadable.
- **`on_change` is killed after one minute**, with the children that hold its
  output, and run again at the next sync like any other failure. It no longer
  runs with the agent's lock held, so `/healthz` and the next sync do not hang
  with it.
- **A list that lapses is refused when it lapses**, not at the next refresh: the
  agent wakes at the first expiry (or `max_age`) of a current list and fails
  closed then. With `refresh = "1h"` the last KRL used to stay on disk, current
  as far as sshd could tell, for up to an hour after the issuer stopped.
- **A `file://` source must be a regular file.** One naming a FIFO blocked the
  agent for ever in `open(2)`.
- **A URL in an error is shown without its password, query and fragment**, so
  that a token in a query does not reach the logs, nor the unauthenticated
  `/healthz` of a mirror.
- **A CRL number outside `0..2^159` is refused**: RFC 5280 5.2.3 defines
  `CRLNumber ::= INTEGER (0..MAX)` of at most 20 octets. The number `-1` was
  accepted until a fuzzer found it.
- **Temporary files** of a write killed between creating and renaming them are
  removed at start.

Bytes identical to the list already held are not verified and parsed again
(currency is still judged), which is what makes a source that sends no `ETag`
cheap to poll: a 100,000-entry CRL (2.1 MB) cost 300,138 allocations and
96,956,946 bytes per poll in v0.6.6 and costs 37 allocations and 4,776,864
bytes in v0.6.7 (`BenchmarkFetchUnchangedCRL`, allocations exact). Times were
not measured: the machine's load was 53 to 65.

## The mirror

With `listen`, authn-revokd serves what it holds, from memory, never from the
files a write may be half way through:

| | |
|---|---|
| `GET /<source>` | the list, with an `ETag`; `If-None-Match` answers `304` |
| `GET /<source>.sig` | a KRL's signature; `If-Match` on another ETag answers `412` |
| `GET /healthz` | `200 ok`, or `503` naming each source with no current list and each output that failed |

```
$ curl -s http://127.0.0.1:28474/healthz
ok
$ curl -s -D - -o /dev/null http://127.0.0.1:28474/bridge-ssh
HTTP/1.1 200 OK
Cache-Control: max-age=30
Content-Type: application/octet-stream
Etag: "dfd84d8513eb48d07ed72f2110316858"
Date: Mon, 26 Oct 2026 11:27:10 GMT
Content-Length: 130

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-Match: "stale"' http://127.0.0.1:28474/bridge-ssh.sig
412
```

A CRL source has no `.sig` (`404`). Mirrors chain: a mirror's source can be
another mirror, since every list verifies by itself. A slow upstream never
blocks the mirror's answers. From v0.6.7 the mirror's own connections have
deadlines: 10 s to read the request headers, 30 s the whole request, 2 minutes
to write the answer and 1 minute idle. A client that asked for a list and never
read it held its connection for good before.

## What is refused at start

Each of these exits `2` before anything is fetched:

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

So does a configuration that is not there:

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

Before v0.6.2 it was the HCL parser's message:
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

A CRL output also takes one source (a TLS server reads one CRL per issuer), and
a CRL source with `max_age` is refused, because nothing could enforce it:

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

A TLS server that loaded a CRL keeps it in memory until its `nextUpdate`,
whatever authn-revokd writes.

**The state directory** is held to sshd's StrictModes rule. Whoever can
replace or remove its files decides which list comes next, and an emptied state
lets a replayed older list in. So it may not be a symbolic link, writable by
group or others, or owned by anybody but authn-revokd's user or root. These exit
`1`:

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
