---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "What sshcert-authorize checks when sshd runs it as an AuthorizedPrincipalsCommand, what it refuses, and why a certificate with no domain grant is refused too."
tags: [sshcert, ssh, sshd, eurohpc]
---

`sshd` asks it, for each certificate login, which principals may log into the
account. It answers with the account's principals only if the certificate's
domain grant names this host; otherwise it answers nothing, and `sshd` refuses
the certificate. It takes the arguments, flags, output and log format of GÉANT's
`ssh-cert-authorize`, and differs in what it refuses.

## How sshd calls it

```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/efp-ssh-ca.pub
AuthorizedPrincipalsCommand /usr/local/bin/sshcert-authorize %u %k
AuthorizedPrincipalsCommandUser nobody
```

```sh
install -o root -g root -m 0755 sshcert-authorize /usr/local/bin/
echo login.example.org > /etc/ssh/cert-allowed-domain.conf
```

and, for each local account, the principals that may log into it, one per line,
in `/etc/ssh/auth_principals/<account>`. sshd runs the command only from a path
owned by root and writable by nobody else.

`%u` is the account being logged into. `%k` is the certificate, base64; a whole
`ssh-...-cert-v01@openssh.com BASE64` line is read too, and when the argument is
absent the certificate is read from standard input. A third argument, when one
is given (sshd's `%t`), must be the certificate's type, or the certificate is
refused.

| exit | prints | sshd |
|---|---|---|
| `0` | the account's principals, one per line | lets the certificate in if one of its principals is among them |
| `1` | nothing | refuses it |
| `2` | nothing | refuses it: the arguments were wrong |

{{< callout type="info" >}}
**It does not check the signature, the CA or the validity dates**

Nothing in the command verifies the certificate's signature or its
validity window: sshd, which trusts the CA through `TrustedUserCAKeys`,
does that. The command decides one question, whether the certificate is
meant for this host and this account.
{{< /callout >}}

## What it refuses

In the order it checks:

1. an account name that is empty, `.`, `..`, or holds `/`, `\` or a NUL;
2. a host with no domain configured, or one that is not a valid host name;
3. a certificate that does not parse, a plain key, or a host certificate;
4. a `%t` that is not the certificate's type;
5. with `--krl`, a certificate the list revokes, or **every** certificate when
   the list cannot be read or has expired;
6. a domain grant that is present and malformed, **whatever the flags**;
7. **no domain grant at all**, unless `--allow-no-grant`;
8. a grant none of whose patterns matches any of the host's names;
9. an account with no principals file, or an empty one.

The host's names are `--domain`, or the variable `--domain-env` names, or the
lines of `--domain-file` (blank lines and `#` comments ignored; several lines are
several names, any of which may match).

Against certificates signed by a test CA for the account `alice`, whose
principals file lists `a1b2c3@univ-example.example`, on a host called
`login.hpc.example.org`:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

The last line is the answer sshd reads; the lines before it are the log, here on
standard error. A certificate granted other hosts:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

A certificate with no grant:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

An account with no principals file, and a plain key:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

Each of these exited `1`, and printed nothing on standard output.

## Why a certificate with no grant is refused

GÉANT's `ssh-cert-authorize` lets a certificate with no domain grant through
("might be valid for non-domain-based auth"), and one whose grant it cannot
parse, or that is empty. Then a site that trusts **two** CAs in
`TrustedUserCAKeys` (the federation's, and its own for staff, or a test CA)
lets a certificate from the second CA in on every host, for any principal in a
principals file, with no domain check at all. The domain filter is only a filter
if a certificate that does not say where it may be used is refused.

A site that really wants GÉANT's behaviour says so, and the command logs each
time it applies it:

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
```

Even then, a grant that is present but malformed is refused.

## `--krl` {#krl}

`RevokedKeys` is sshd's own check, made before the command runs, for every key
and certificate, and it also revokes a CA key; prefer it. `--krl FILE` checks an
OpenSSH KRL inside the command, and adds what sshd does not do: it refuses
**every** certificate once the list has expired (its `expires@go-authn.github.io`
extension, which sshd ignores), and every certificate when the list cannot be
read. A list with no expiry is used without one.

Three runs: with the KRL [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
writes, first a current one, then the fail-closed one it writes when the
issuer's list [lapses]({{< relref "/authn-revokd/lapse.md" >}}); and last with
`--krl` naming a file that does not exist:

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4
```

The second run is refused because the fail-closed list revokes the
certificate's **CA key**: the check covers the certificate's own key, its serial
and key ID, and the key that signed it. The third is refused because the list
cannot be read: no list is not taken to mean nothing revoked.

## Flags

```
$ sshcert-authorize -help
usage: sshcert-authorize [flags] USER [CERTIFICATE [KEYTYPE]]

An sshd AuthorizedPrincipalsCommand (%u %k) that refuses a certificate whose
ssh-domain-grant@core.aai.geant.org extension does not grant this host, or that has none.

  -allow-no-grant
    	let in a certificate with no domain grant (GÉANT's behaviour); a malformed grant is still refused
  -debug
    	log details
  -domain string
    	the host's domain (overrides --domain-env and --domain-file)
  -domain-env string
    	environment variable holding the host's domain
  -domain-file string
    	file holding the host's domain, one name per line (default "/etc/ssh/cert-allowed-domain.conf")
  -extension string
    	name of the domain-grant extension (default "ssh-domain-grant@core.aai.geant.org")
  -krl string
    	refuse certificates this OpenSSH KRL revokes, and every certificate once it has expired or cannot be read
  -principals-dir string
    	directory of principals files, one per user (default "/etc/ssh/auth_principals")
  -syslog
    	log to syslog, facility AUTH (--syslog=false: to stderr) (default true)
  -version
    	print the version and exit
```

**Logs** are `key=value` lines (`action=cert_processed`, `action=denied`,
`action=authorized`, with `serial` and `ca_fingerprint`), to syslog, facility
AUTH, by default. sshd discards the command's standard error, so keep syslog on
in production; `--debug` also writes everything to standard error. A value that
comes from the client, such as the account name, is quoted when it holds a
space, `=`, a quote or a control character, so it cannot forge a log field.

**`-version`** prints the module version, in a release binary and in one
built by `go install` alike:

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

Before v0.1.5, a binary from `go install` printed `sshcert-authorize dev`.
