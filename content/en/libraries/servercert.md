---
title: "servercert — where a daemon's TLS certificate comes from"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert serves a TLS server certificate from files re-read when they change, or from an ACME CA through autocert, External Account Binding included."
tags: [libraries, tls, acme, certificates]
---

**Where does a daemon's TLS server certificate come from?** A certificate and
key on disk, re-read when they change, or an ACME CA through
[`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert), External
Account Binding included.

```sh
go get github.com/go-authn/servercert@v0.7.0
```

A `Config` names exactly one source — `CertFile` and `KeyFile`, or `ACME` —
and `New` returns a `*Source` whose `TLSConfig()` serves it, with
`MinVersion` TLS 1.2.

## Example

From files:

```go
package main

import (
	"log"
	"net/http"

	"github.com/go-authn/servercert"
)

func main() {
	src, err := servercert.New(servercert.Config{
		CertFile: "/etc/fileshare/tls/fullchain.pem",
		KeyFile:  "/etc/fileshare/tls/privkey.pem",
		OnError:  func(err error) { log.Print(err) }, // a renewal that did not load
	})
	if err != nil {
		log.Fatal(err) // unreadable, unparsable, or a key that is not the certificate's
	}
	srv := &http.Server{Addr: ":443", TLSConfig: src.TLSConfig()}
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
```

`Config.Check` refuses a configuration that cannot work, and touches nothing —
no file read, no directory created:

```go
package main

import (
	"fmt"

	"github.com/go-authn/servercert"
)

func main() {
	// Check touches nothing: no file is read, no directory created.
	for _, c := range []servercert.Config{
		{ACME: &servercert.ACME{Domains: []string{"*.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"192.0.2.10"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "acme"}},
		{CertFile: "/etc/fileshare/tls/fullchain.pem"},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme",
			DirectoryURL: "http://acme.example.org/directory"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
	} {
		fmt.Println(c.Check())
	}
}
```

```
servercert: ACME domain "*.example.org" is a wildcard; that needs dns-01, which autocert does not do
servercert: ACME domain "192.0.2.10" is an IP address; autocert issues only for DNS names
servercert: ACME.CacheDir "acme" is not an absolute path
servercert: CertFile and KeyFile go together; one of them is empty
servercert: ACME.DirectoryURL "http://acme.example.org/directory" is not an https URL (RFC 8555 §6.1)
<nil>
```

The last one is Let's Encrypt production: `DirectoryURL` empty.

## Files

`New` reads the pair and fails **now** on one that is unreadable, does not
parse, or whose key is not the certificate's. After that, at most once every
10 seconds and during a handshake, the files are read again; a changed pair is
parsed without holding a lock and swapped in. A changed pair that does **not**
load — the certificate written before its key, a truncated file — is reported
once to `OnError`, and the last good pair stays in service, so a renewal job
that writes the two files one after the other never takes the server down.

## ACME

autocert answers two challenge types and no other: `tls-alpn-01` (RFC 8737,
port 443, ALPN `acme-tls/1`) and, with `HTTPChallenge`, `http-01` (RFC 8555
§8.3, port 80, served by `Source.HTTPHandler`). Without `ACME.DNS` there is no
`dns-01`, hence no wildcard; an IP-address certificate is never issued.

### dns-01: a server the CA cannot reach (since v0.7.0)

`ACME.DNS` proves control of the names with a TXT record at
`_acme-challenge.<name>` (RFC 8555 §8.4). The server needs no inbound port and
may sit on a private LAN address, and `Domains` may hold a wildcard
(`*.school.example`, which does not cover `school.example`: list both).
Issuance goes through `x/crypto/acme` (autocert has no dns-01): one certificate
for every name, kept 0600 in `CacheDir`, renewed in the background, the old one
serving meanwhile. `DNS` excludes `HTTPChallenge`.

```go
DNS: &servercert.DNS{
    CredentialsFile: "/etc/relay/dns-update.conf", // 0600, owned by the user
    Provider: func(b []byte) (servercert.DNSSolver, error) { return rfc2136.New(b) },
    Resolver: "192.0.2.53:53", // optional: wait until the TXT is visible there
}
```

A provider is two methods, `Present(ctx, name, value)` and
`CleanUp(ctx, name, value)`, each on one TXT value (a wildcard and its base name
share one record name). The credentials file is read under the checks of
`EABHMACKeyFile` and handed to `Provider`; never an argument, an environment
variable or a URL. The module `github.com/go-authn/servercert/rfc2136` (v0.1.0)
is the provider for a name server that takes RFC 2136 dynamic updates signed
with TSIG (RFC 8945): `server`, `zone`, `key`, `algorithm` (hmac-sha256, -384
or -512) and `secret` in one file.

Certificates are obtained at the first handshake whose SNI names one of
`Domains`, or before any client by `Source.Prefetch`, and renewed by autocert
before they expire. A client that connects by IP address sends no SNI and is
served the first domain's certificate.

{{< callout type="warning" >}}
**Append to `NextProtos`, never replace it**

With ACME, `TLSConfig().NextProtos` holds `acme-tls/1`, without which the CA's
tls-alpn-01 validation fails. And append you must: a Go TLS server that
advertises ALPN protocols refuses a client whose offer shares none, so an
NFS-over-TLS server adds `sunrpc` (RFC 9289). `net/http` adds `http/1.1` and
`h2` itself.
{{< /callout >}}

**A CA that needs no challenge.** autocert returns at once when a new order is
already `ready`, which is what a CA with pre-validated domains answers: GÉANT
TCS, served by HARICA, for an Enterprise Admin account. An internal server
reachable on neither port 80 nor 443 from the Internet can still get a publicly
trusted certificate. The EAB HMAC key is a secret, so the configuration names
a **file** holding it (`EABHMACKeyFile`), never the key.

One defect of `x/crypto/acme` is worked around ([golang/go#77704](https://github.com/golang/go/issues/77704)):
after finalizing an order the CA is still processing, the client polls the URL
in the finalize response's `Location` header, which RFC 8555 does not put
there. servercert gives the ACME client a transport that adds that header, with
the order's URL from the earlier newOrder response.

## What it refuses, and why

`Check` refuses: neither or both sources; half a file pair; ACME without
domains or cache directory; a relative path; half an EAB; a domain that is an
IP address, a wildcard, a single label, ends with a dot, or is not a valid host
name; a directory URL that is not https (RFC 8555 §6.1).

`New` also refuses a cache directory — it holds private keys — that is a
symbolic link, is accessible by group or others, is owned by a user other than
the process's effective user, or cannot be written; a missing one is created
`0700` and checked after. Every directory above it must be changeable only by
root or the effective user, as sshd's `StrictModes` asks of the path to
`authorized_keys`, and a symbolic link above it is refused unless root owns it.
On Windows, mode and owner are not checked — ACLs decide both, and restricting
them is yours — and a symbolic link anywhere in the path is refused.

`New` (and every reload) also refuses a **secret file** that group or others can read or write: the TLS `KeyFile` and the ACME `EABHMACKeyFile` (since v0.6.0), as OpenSSH refuses a private key, with `chmod 600 it`. The mode is read from the opened file, not from its name. A replacement key written readable is not taken: the current certificate keeps serving and `OnError` is called. Not checked on Windows, where ACLs decide. **Upgrade:** `chmod 600` (or `0400`) both files before deploying.

## What it is checked against

**pebble**, Let's Encrypt's test CA, run in-process from its `ca`, `db`, `va`
and `wfe` packages with a DNS stub, issuing real certificates that `crypto/tls`
verifies against pebble's root: tls-alpn-01; http-01 through `HTTPHandler` and
its control with `HTTPChallenge` off; EAB required, absent, wrong, then right;
a pre-validated domain issued with no challenge port open, and its control. A
test runs the same issuance without the golang/go#77704 workaround and requires
it to fail. The coverage floor is 100%.

## Reference

[pkg.go.dev/github.com/go-authn/servercert@v0.7.0](https://pkg.go.dev/github.com/go-authn/servercert@v0.7.0)
