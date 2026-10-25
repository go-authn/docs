---
title: "The admin API, health and metrics"
linkTitle: "Admin API"
weight: 70
description: "Disabling a person or an institution through authn-bridge's gRPC admin API, and the health and metrics endpoints beside it."
tags: [authn-bridge, administration, grpc, metrics]
---

Both are off unless the configuration asks for them, and neither is ever on the
public listener.

```hcl
admin {
  listen = "unix:///run/authn-bridge/admin.sock"   # mode 0600
  # or over the network, mutual TLS and nothing less (loopback included):
  # listen         = "10.0.0.5:9443"
  # tls_cert_file  = "/etc/authn-bridge/admin.crt"
  # tls_key_file   = "/etc/authn-bridge/admin.key"
  # client_ca_file = "/etc/authn-bridge/operators-ca.crt"
  # reflection     = true                          # for grpcurl; off by default
}

metrics { listen = "127.0.0.1:9101" }              # /healthz /readyz /metrics

disabled_file = "/var/lib/authn-bridge/disabled.json"
```

The listener is grpc-transports/control's, shared with go-fileshare. The socket
is never reachable by another user, not even between bind and chmod, and is
never taken from an instance still running. TCP without all three TLS files is
refused, loopback included, since every local user can reach `127.0.0.1`:

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

A binary built with `-tags nogrpc` has no admin API, and refuses a configuration
with an `admin` block rather than start without it.

## The service

`bridge.admin.v1.AdminService` (`proto/bridge/admin/v1/admin.proto`), with
`grpc.health.v1` beside it, which reports `SERVING` while the provider is ready.

| | |
|---|---|
| `Status` | version, issuer, start time; the federation's metadata (IdPs, usable, valid until, last refresh, last error); what is held in memory |
| `RefreshMetadata` | fetch the federation's metadata now, and say how it went |
| `ListIdPs` | the federation's IdPs, as the institution list shows them (`query`, `limit`, 100 by default) |
| `ListClients` | the configured relying parties |
| `RevokePerson` | end their refresh token families, the access tokens those bought, their logins and device grants in progress and their application password, and revoke everything the certificate store holds for them: SSH and X.509 certificates (into the next KRL and CRL) and WireGuard keys |
| `DisablePerson`, `EnablePerson` | refuse somebody here, at login and at every token, whatever their institution says, and revoke what they hold; optionally `until` a time |
| `DisableIdP`, `EnableIdP` | the same for everybody one institution vouches for; a metadata refresh does not lift it |
| `ListDisabled` | who is disabled, why, by whom, since and until when |

With `reflection = true`, against a test provider:

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.3",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-25T18:44:30.210885Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-01T18:43:40Z",
    "lastRefresh": "2026-10-25T18:44:30.211975Z"
  },
  "counts": {}
}
```

## Disabling

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.example",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-11T09:48:39.136975Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-10-12T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-11T09:48:39.192047Z",
    "until": "2026-10-12T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked` counts what each call ended (refresh families, access tokens, logins,
application passwords, certificates); nothing was live here. Every call that
changes something is logged with who made it, the peer's `uid=` on the socket
or the client certificate's `cn=` over TLS:

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-10-12T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**A person is disabled as who they are.** Usernames compare without case, as
eppn, uid, mail and subject-id all do, so the same call with
`"Alice@Univ-Example.example"` lifts what was set for `alice@univ-example.example`
(`{"wasDisabled": true}`). The entry also records the stable identity of
everybody known under that name, so another spelling from their IdP does not let
them back in. A name with no `@` is also matched as a `sub`, for a person whose
IdP releases no username.

The entry is recorded **before** anything is revoked, so a grant racing the
revocation meets the entry.

**Disabling is kept in `disabled_file`, and refused without one.** Somebody
disabled until the next restart would be let back in by the next deployment:

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

A file that cannot be read stops the provider from starting, for the same
reason. A disabled institution counts as not usable in `Status`, `ListIdPs` and
[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}}).

What disabling reaches beyond the provider is on
[revocation]({{< relref "/authn-bridge/revocation.md" >}}): the KRL and the
CRL for certificates, Shared Signals for tokens. An application password
removed here stops working in go-fileshare when it next reads its directory;
call its `ReloadDirectory` after `DisablePerson` for the effect to be immediate.

{{< callout type="warning" >}}
**What `RevokePerson` cannot end**

An access token already handed out is a signed statement a resource server
checks on its own, valid there until it expires (an hour by default). An
SSH certificate already issued lasts its validity unless the server reads
the KRL, which is why both are short.
{{< /callout >}}

## Health and metrics

go-net-health/endpoint's, as in go-fileshare, on the `metrics` listener, which
must not be the public one (a configuration that makes it so is refused):

| | |
|---|---|
| `/healthz` | up while the process answers |
| `/readyz` | ready while the federation's metadata is loaded and within its `validUntil`, and no revocation is waiting to reach the state database |
| `/metrics` | Prometheus text, `bridge_*` families |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.23.3",goversion="go1.27.3",revision="b04769c43c24f684df9e0b5a0d1cb6997ee90d95"} 1
bridge_start_time_seconds 1792953870
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793558620
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1792953870
bridge_metadata_refreshes_total{result="failed"} 0
bridge_metadata_refreshes_total{result="ok"} 1
bridge_logins_in_progress 0
bridge_devices_waiting 0
bridge_refresh_families 0
bridge_access_tokens 0
bridge_disabled{kind="idp"} 0
bridge_disabled{kind="person"} 0
bridge_ssh_certificates_total 0
bridge_x509_certificates_total 0
```

The counters of logins by outcome (`bridge_logins_total`), of tokens by grant
(`bridge_tokens_issued_total`) and of application passwords
(`bridge_app_passwords_total`) appear only once they have counted something. **No label names a person or an institution**: which
universities' people use the service, and when, is not the provider's to
publish. Alert on `bridge_metadata_valid_until_timestamp_seconds` before the
time it gives is reached: past it, nobody can log in.
