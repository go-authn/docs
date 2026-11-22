---
title: "harden — zwei Sicherheitsbausteine, geteilt"
linkTitle: "harden"
weight: 36
description: "go-authn/harden enthält die zwei Sicherheitsbausteine, die die go-authn-Repositories bisher je für sich kopiert hatten: die Regel „https oder Loopback“ für Umleitungen und eine atomar geschriebene private Datei."
tags: [bibliotheken, harden, sicherheit]
---

**Was hat jedes go-authn-Repository kopiert?** Zwei kleine Regeln, jetzt in
einem Modul ohne andere Abhängigkeit als die Standardbibliothek.

```sh
go get github.com/go-authn/harden@v0.2.0
```

## `redirect` {#redirect}

Die Regel, die gilt, bevor ein Token, ein Schlüsselsatz oder eine signierte
Assertion eine Verbindung überquert: **die URL ist https, oder sie benennt
diesen Rechner.**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| Funktion | |
|---|---|
| `CheckRedirect(req, via) error` | eine `http.Client`-Richtlinie: stoppt nach 10 Umleitungen und lehnt ein Ziel ab, das weder https noch Loopback ist (https zu http auf einem anderen Host ist der Fall, für den sie da ist). Hängen Sie Ihre eigene Richtlinie dahinter |
| `HTTPSOrLoopback(rawURL) error` | nil für `https://host/...` oder `http://` mit einem Loopback-Host. Lehnt fehlenden Host, andere Schemata und Klartext ab. Der Fehler nennt Schema und Host, nie die ganze URL |
| `Loopback(host) bool` | `host`, wie `url.URL.Hostname()` ihn liefert |

`Loopback` akzeptiert ein IP-Literal, das Loopback ist (127.0.0.0/8, `::1`,
IPv4-abgebildet `::ffff:127.0.0.1`), sowie `localhost` oder jeden Namen unter
`.localhost` (RFC 6761 Abschnitt 6.3), in jeder Groß- und Kleinschreibung, mit
oder ohne Punkt am Ende. Es vergleicht nie ein Präfix, also wird
`127.evil.example` abgelehnt, ebenso `0x7f.1`, `127.1`, `2130706433`, eine
IPv6-Zone und das eingeklammerte `[::1]` (Klammern sind URL-Syntax, nicht Teil
eines Hosts).

`Loopback` und `HTTPSOrLoopback` werden gegen eine zweite Lesart des RFC
gefuzzt; das Korpus ist eingecheckt.

Das wenden [oidc]({{< relref "/libraries/oidc.md" >}}) (v0.8.1),
[saml]({{< relref "/libraries/saml.md" >}}) (v0.7.3),
[wireguard]({{< relref "/libraries/wireguard.md" >}}), rp (v0.5.1) und awscred
(v0.3.1) an.

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write` legt Daten mit Modus 0600 unter `path` ab: eine temporäre Datei im selben
Verzeichnis, `fsync`, dann `rename`. Daraus folgt:

- ein Leser sieht die alte oder die neue Datei, nie eine halbe;
- ein unter `path` liegender symbolischer Link wird **ersetzt, nicht verfolgt**
  (worauf er zeigte, bleibt unberührt), und eine Datei mit lockererem Modus
  behält ihren Modus nicht;
- unter Unix wird ein Verzeichnis, das ein symbolischer Link ist, einem anderen
  gehört oder für Gruppe oder andere schreibbar ist, abgelehnt, bevor etwas
  geschrieben wird.

Das Verzeichnis legt es nicht an. Unter Windows gibt es keinen Modus zu lesen;
seit v0.2.0 wird die Datei mit einer geschützten Zugriffsliste angelegt, die
einen Eintrag enthält, das aktuelle Konto, gesetzt von `CreateFile` (die Liste
von kinit v0.3.2), sodass die Einträge des Ordners nie geerbt werden. Das Modul
verlangt `golang.org/x/sys`, das nur Windows-Builds nutzen.

Das schreibt kinits `--cred-file` (v0.3.3), wireguards `FloorFile` (v0.2.1), die
Zustandsdatei von `authn-revokd` (revocation v0.7.2) und die
KeePassXC-Zuordnungsdatei von
[secretsource]({{< relref "/libraries/secretsource.md" >}}) (v0.8.1).

## Untergrenzen {#floors}

go-authn/wireguard und go-authn/revocation halten beide über einen Neustart eine
Ordnungsuntergrenze, teilen sie aber nicht: wireguard hält nur Version und
Ausstellungszeit in einer eigenen kleinen Datei, revocation hält die ganze
signierte Liste und berechnet die Untergrenze durch deren Prüfung neu.
Gemeinsam ist nur das Schreiben der Datei, und das ist `privfile`.

## Referenz {#reference}

Das README unter
[github.com/go-authn/harden](https://github.com/go-authn/harden) ist die Quelle
der Wahrheit für diese Seite. BSD 3-Clause.
