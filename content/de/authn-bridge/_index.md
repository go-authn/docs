---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "Ein OpenID-Connect-Anbieter vor einer SAML-Föderation: Personen melden sich bei ihrer eigenen Einrichtung an, und Anwendungen erhalten Tokens, SSH-Zertifikate und X.509-Client-Zertifikate."
tags: [authn-bridge, oidc, saml]
---

**Personen melden sich an ihrer eigenen Universität an, über die Fédération
Éducation-Recherche von RENATER oder über eduGAIN, und Anwendungen erhalten ein OpenID-Connect-Token.**
Dieselbe Anmeldung kann außerdem einen SSH-Schlüssel zertifizieren lassen, ein
X.509-Client-Zertifikat für NFS über TLS ausstellen lassen, ein Anwendungspasswort für SMB und S3
setzen oder einen WireGuard-Schlüssel registrieren. Der Anbieter kann widerrufen, was er
ausgestellt hat, und er veröffentlicht signierte Listen dessen, was er widerrufen hat; ein bereits
ausgegebenes Zugriffstoken bleibt gültig, bis es abläuft. Reines Go,
`CGO_ENABLED=0`, ein Binary. Diese Seiten beschreiben v0.22.1.

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.22.1

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

Vor v0.20.0 hieß der Befehl `bridge`. So heißt auch `/sbin/bridge` aus iproute2,
das auf praktisch jedem Linux-System installiert ist, und gewonnen hat, was im
`PATH` zuerst kam. Der Modulpfad ist weiterhin `github.com/go-authn/bridge`.

## Warum eine Brücke {#why-a-bridge}

Eine Forschungsföderation spricht SAML. Ihre Mitglieder sind Hunderte von
Identitätsanbietern, einer pro Einrichtung, aufgeführt in einem signierten Metadatendokument, das die
Föderation veröffentlicht. Heute geschriebene Anwendungen wollen OpenID Connect und vertrauen einem
Anbieter. authn-bridge ist dieser eine Anbieter: auf der einen Seite ein SAML-Service-Provider,
einmal bei der Föderation registriert, auf der anderen ein OpenID-Provider.

Ein Gateway entscheidet für jede Anwendung dahinter, wer jemand ist; daher besteht der größte Teil
dieses Programms aus Ablehnungen. Es lehnt Metadaten ab, die die Föderation nicht signiert hat, eine
Assertion, die jemanden aus der Domain einer anderen Einrichtung nennt, Gruppen, über die ein IdP
keine Befugnis hat, und eine Konfiguration, die irgendetwas davon durchließe.
Eine Konfiguration, die sich nicht sicher bedienen lässt, startet nicht.

## Was es beim Start ausgibt {#what-it-prints-at-startup}

```
$ authn-bridge --config etc/bridge-admin.hcl
authn-bridge v0.22.1: http://127.0.0.1:28473 on 127.0.0.1:28473
admin API on unix:///tmp/authn/run/admin.sock
metrics on 127.0.0.1:28475
```

Das ist ein Testanbieter auf Loopback (ein `http://`-Aussteller wird nur auf einem
Loopback-Host akzeptiert). Er holt die Metadaten der Föderation, **bevor** er lauscht. Ein
Anbieter, der keine einzige Einrichtung nennen kann, ist einer, über den sich niemand anmelden kann;
ohne die Metadaten beendet er sich daher, statt zu starten.

## Wie es weitergeht {#where-to-go-next}

| | |
|---|---|
| [Installation]({{< relref "/authn-bridge/install.md" >}}) | der Benutzer, die Verzeichnisse, die systemd-Unit, die Schlüssel |
| [Die Konfiguration]({{< relref "/authn-bridge/configuration.md" >}}) | jeder Block, `check` und was beim Start abgelehnt wird |
| [Die Seite der Föderation]({{< relref "/authn-bridge/federation.md" >}}) | Metadaten, der Fingerabdruck ihres Signierers, Scopes und was ein IdP behaupten darf |
| [Tokens]({{< relref "/authn-bridge/tokens.md" >}}) | ID-Tokens, Access-Tokens, der Device Grant, Anwendungspasswörter, WireGuard-Schlüssel |
| [Resource Indicators]({{< relref "/authn-bridge/resources.md" >}}) | ein Token für jeweils nur einen der Ressourcenserver eines Clients (RFC 8707) |
| [Zertifikate]({{< relref "/authn-bridge/certificates.md" >}}) | SSH-Zertifikate, das EuroHPC-Profil, X.509-Client-Zertifikate für NFS |
| [Widerruf]({{< relref "/authn-bridge/revocation.md" >}}) | die signierte KRL und CRL und der Shared-Signals-Sender |
| [Die Admin-API]({{< relref "/authn-bridge/admin.md" >}}) | eine Person oder eine Einrichtung deaktivieren, Health und Metriken |

Die Listen, die es signiert, liest [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
für ein einfaches `sshd` oder einen TLS-Server, und
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
das sie selbst prüft.

## Was es nicht ist {#what-it-is-not}

- **Ein Prozess.** Mit einem `state`-Block überstehen Refresh-Tokens und die an
  `/userinfo` akzeptierten Access-Tokens einen Neustart. Laufende Anmeldungen, Codes und
  Device Grants nicht. Der Zustand wird durchgeschrieben und beim Start gelesen; zwei
  Instanzen auf einer Datenbank würden daher jeweils verpassen, was die andere geschrieben hat.
- Keine dynamische Client-Registrierung und kein Front- oder Back-Channel-Logout.
- Keine Benutzer oder Gruppen zum Anlegen. Personen existieren, weil ihre Einrichtung für sie
  bürgt, und ihre Gruppen sind das, was diese behauptet.

## Lizenz {#licence}

BSD-3-Clause.
