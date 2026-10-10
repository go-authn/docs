---
title: "Die Admin-API, Health und Metriken"
linkTitle: "Admin-API"
weight: 70
description: "Eine Person oder eine Einrichtung über die gRPC-Admin-API von authn-bridge deaktivieren, und die Health- und Metrik-Endpunkte daneben."
tags: [authn-bridge, administration, grpc, metrics]
---

Beide sind aus, solange die Konfiguration sie nicht verlangt, und keiner von beiden liegt je auf dem
öffentlichen Listener.

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

Der Listener ist der von grpc-transports/control, gemeinsam mit go-fileshare. Der Socket
ist nie für einen anderen Benutzer erreichbar, nicht einmal zwischen bind und chmod, und wird
nie einer noch laufenden Instanz weggenommen. TCP ohne alle drei TLS-Dateien wird
abgelehnt, Loopback eingeschlossen, denn jeder lokale Benutzer kann `127.0.0.1` erreichen:

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

Ein mit `-tags nogrpc` gebautes Binary hat keine Admin-API und lehnt eine Konfiguration
mit einem `admin`-Block ab, statt ohne sie zu starten.

## Der Dienst {#the-service}

`bridge.admin.v1.AdminService` (`proto/bridge/admin/v1/admin.proto`), mit
`grpc.health.v1` daneben, das `SERVING` meldet, solange der Anbieter bereit ist.

| | |
|---|---|
| `Status` | Version, Aussteller, Startzeit; die Metadaten der Föderation (IdPs, nutzbare, gültig bis, letzte Aktualisierung, letzter Fehler); was im Speicher gehalten wird |
| `RefreshMetadata` | die Metadaten der Föderation jetzt holen und sagen, wie es gelaufen ist |
| `ListIdPs` | die IdPs der Föderation, wie die Liste der Einrichtungen sie zeigt (`query`, `limit`, standardmäßig 100) |
| `ListClients` | die konfigurierten Relying Parties |
| `RevokePerson` | die Refresh-Token-Familien der Person beenden, die damit erlangten Access-Tokens, ihre laufenden Anmeldungen und Device Grants und ihr Anwendungspasswort, und alles widerrufen, was der Zertifikatsspeicher für sie hält: SSH- und X.509-Zertifikate (in die nächste KRL und CRL) und WireGuard-Schlüssel |
| `DisablePerson`, `EnablePerson` | jemanden hier ablehnen, bei der Anmeldung und bei jedem Token, was auch immer die Einrichtung sagt, und widerrufen, was die Person hält; optional `until` zu einem Zeitpunkt |
| `DisableIdP`, `EnableIdP` | dasselbe für alle, für die eine Einrichtung bürgt; eine Aktualisierung der Metadaten hebt es nicht auf |
| `ListDisabled` | wer deaktiviert ist, warum, von wem, seit wann und bis wann |

Mit `reflection = true`, gegen einen Testanbieter:

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.20.1",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-10T20:54:06.593823Z",
  "federation": {
    "metadataUrl": "file:///tmp/docs-patch-a2daf7c8/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-10-17T20:53:09Z",
    "lastRefresh": "2026-10-10T20:54:06.594642Z"
  },
  "counts": {}
}
```

## Deaktivieren {#disabling}

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.fr","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.fr",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-10T19:23:33.341944Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.fr/idp/shibboleth","reason":"compromised","until":"2026-10-11T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.fr/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-10T19:23:33.363575Z",
    "until": "2026-10-11T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked` zählt, was jeder Aufruf beendet hat (Refresh-Familien, Access-Tokens, Anmeldungen,
Anwendungspasswörter, Zertifikate); hier war nichts aktiv. Jeder Aufruf, der
etwas ändert, wird mit seinem Urheber protokolliert, der `uid=` der Gegenseite am Socket
oder dem `cn=` des Client-Zertifikats über TLS:

```
disabled alice@univ-example.fr (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.fr: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.fr/idp/shibboleth by uid=501 until 2026-10-11T08:00:00Z: compromised
revoked IdP https://idp.univ-example.fr/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.fr by uid=501
```

**Eine Person wird als die deaktiviert, die sie ist.** Benutzernamen werden ohne Beachtung der
Groß- und Kleinschreibung verglichen, wie es eppn, uid, mail und subject-id alle tun; derselbe Aufruf mit
`"Alice@Univ-Example.fr"` hebt also auf, was für `alice@univ-example.fr` gesetzt wurde
(`{"wasDisabled": true}`). Der Eintrag hält außerdem die stabile Identität aller fest,
die unter diesem Namen bekannt sind, sodass eine andere Schreibweise von ihrem IdP sie nicht
wieder hereinlässt. Ein Name ohne `@` wird auch als `sub` abgeglichen, für eine Person, deren
IdP keinen Benutzernamen herausgibt.

Der Eintrag wird **vor** jedem Widerruf festgehalten, sodass ein Grant, der mit dem
Widerruf um die Wette läuft, auf den Eintrag trifft.

**Die Deaktivierung wird in `disabled_file` festgehalten und ohne diese Datei abgelehnt.** Jemand,
der nur bis zum nächsten Neustart deaktiviert wäre, würde vom nächsten Deployment wieder hereingelassen:

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.fr"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

Eine Datei, die sich nicht lesen lässt, verhindert aus demselben Grund den Start des Anbieters.
Eine deaktivierte Einrichtung zählt in `Status`, `ListIdPs` und
[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}}) als nicht nutzbar.

Was die Deaktivierung über den Anbieter hinaus erreicht, steht unter
[Widerruf]({{< relref "/authn-bridge/revocation.md" >}}): die KRL und die
CRL für Zertifikate, Shared Signals für Tokens. Ein hier entferntes Anwendungspasswort
funktioniert in go-fileshare nicht mehr, sobald es sein Verzeichnis das nächste Mal liest;
rufen Sie dessen `ReloadDirectory` nach `DisablePerson` auf, damit die Wirkung sofort eintritt.

{{< callout type="warning" >}}
**Was `RevokePerson` nicht beenden kann**

Ein bereits ausgegebenes Access-Token ist eine signierte Aussage, die ein Resource Server
selbst prüft, und dort gültig, bis es abläuft (standardmäßig eine Stunde). Ein
bereits ausgestelltes SSH-Zertifikat gilt für seine Gültigkeitsdauer, es sei denn, der Server liest
die KRL; deshalb sind beide kurzlebig.
{{< /callout >}}

## Health und Metriken {#health-and-metrics}

Die von go-net-health/endpoint, wie in go-fileshare, auf dem `metrics`-Listener, der
nicht der öffentliche sein darf:

| | |
|---|---|
| `/healthz` | aktiv, solange der Prozess antwortet |
| `/readyz` | bereit, solange die Metadaten der Föderation geladen und innerhalb ihres `validUntil` sind und kein Widerruf darauf wartet, die Zustandsdatenbank zu erreichen |
| `/metrics` | Prometheus-Text, `bridge_*`-Familien |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.20.1",goversion="go1.27.2",revision="d30d3b52b644c7db74c431c2a07b8d1aaeb1c0ff"} 1
bridge_start_time_seconds 1791665646
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1792270389
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1791665646
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

Anmeldungen nach Ergebnis, Tokens nach Grant und Anwendungspasswörter erscheinen, sobald sie
etwas gezählt haben. **Kein Label nennt eine Person oder eine Einrichtung**: Von welchen
Universitäten Personen den Dienst nutzen, und wann, zu veröffentlichen ist nicht Sache des
Anbieters. `bridge_metadata_valid_until_timestamp_seconds` ist die Metrik, auf die
alarmiert werden sollte, bevor der Zeitpunkt erreicht ist: Danach kann sich niemand anmelden.
