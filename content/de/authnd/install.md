---
title: "authnd installieren"
linkTitle: "Installation"
weight: 10
description: "Das Release-Binary und wie man es prüft, das Konto authnd, die systemd-Unit und was sie gewährt, sowie Upgrade, Rollback und Entfernen."
tags: [authnd, installation, systemd]
---

Das Repository enthält die beiden Dateien, die ein systemd-Host braucht:
`packaging/sysusers.d/authnd.conf` (das Konto) und
`packaging/systemd/authnd.service` (die Unit). Diese Seite erklärt beide und die Schritte
drumherum. Die versionierten Dienste von go-pkgx sollen das später für Sie übernehmen; es gibt
sie noch nicht.

## Das Release-Binary {#the-release-binary}

Jeder Tag veröffentlicht `authnd-<os>-<arch>` für linux, darwin und windows auf amd64 und
arm64 (`.exe` unter windows), gebaut mit `CGO_ENABLED=0`, ein `SHA256SUMS`-Manifest und eine
Build-Provenance-Attestierung für jedes Binary.

```sh
version=v0.12.0
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

Brechen Sie ab, wenn eine der beiden Prüfungen fehlschlägt. Der Release-Workflow lehnt es ab,
ein Binary zu veröffentlichen, das nicht genau den Tag meldet, unter dem es veröffentlicht wird,
daher ist die Version etwas, das sich vergleichen lässt:

```
$ authnd --version
authnd version v0.12.0
```

### Nur bauen, was Sie wollen {#building-only-what-you-want}

Der Server ist immer enthalten; zwei Build-Tags lassen weg, woher Personen kommen können.
`-tags nosql` entfernt die drei Datenbanktreiber (PostgreSQL über pgx, MySQL/MariaDB, SQLite
über modernc.org/sqlite) und den Block `users "sql"`; `-tags noldap` entfernt den LDAP-Client
und den Block `users "ldap"`. Einer Konfiguration, die einen Block nennt, ohne den das Binary
gebaut wurde, wird genau das gesagt – *this binary was built without SQL support (-tags
nosql)* – statt dass der Block nicht existiere. Die Release-Binarys werden ohne Tags gebaut.

## Das Konto {#the-account}

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

Ein statisches Konto aus sysusers.d, **nicht** `DynamicUser=`. Die Dateien, die authnd liest –
Passwortdateien, ein DSN, ein Keytab, ein TLS-Schlüssel –, sind Geheimnisse, die der Gruppe
`authnd` vorab übergeben werden, und eine [Passwortänderung]({{< relref "/authnd/passwords.md" >}})
schreibt in sie zurück. Eine dynamische UID existiert erst, wenn der Dienst startet, und eine
Datei, die sie geschrieben hat, gehörte dann einer Nummer, die später jemand anderen bezeichnet.

Die beiden Dateien stammen aus dem Verzeichnis `packaging/` des Release-Tags, derselben
Version wie das Binary: Kopieren Sie dieses Verzeichnis neben das Binary, aus einem
Checkout des Tags oder, für v0.12.0, von
<https://github.com/go-authn/authnd/tree/v0.12.0/packaging>.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## Was die Unit gewährt, und warum {#what-the-unit-grants-and-why}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

Der Rest der Unit ist die übliche Härtung (`ProtectHome`, `PrivateTmp`, `PrivateDevices`,
`ProtectProc=invisible`, die Kernel- und cgroup-Schutzmechanismen,
`MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`,
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`). Drei Dinge, die sie **weglässt**, sind
Absicht:

| | |
|---|---|
| `ExecReload=` | authnd hat kein Neuladen. Es liest seine Konfiguration, sein Zertifikat und seinen Keytab einmal; siehe [Betrieb]({{< relref "/authnd/operations.md" >}}) |
| `PrivateUsers=` | innerhalb eines User-Namespace gilt `CAP_NET_BIND_SERVICE` nicht mehr für das Netzwerk des Hosts, und der Bind an 389 wird abgelehnt |
| `ProcSubset=pid` | es verbirgt `/proc/sys`, wo Go `net/core/somaxconn` liest, und der Backlog jedes Listeners fällt auf Gos Ersatzwert 128 |

`IPAddressAllow=`/`IPAddressDeny=` sind ebenfalls nicht gesetzt: Welche Netze ein Verzeichnis
fragen dürfen, hat der Standort zu entscheiden, in einem Drop-in:

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

Die eine Capability ist für die privilegierten Ports da: LDAP 389, LDAPS 636 und Kerberos 88
über UDP und TCP. Ein PostgreSQL oder MariaDB auf derselben Maschine wird über seinen Socket
erreicht, was ein schreibgeschütztes Dateisystem zulässt. Das Zustandsverzeichnis
`/var/lib/authnd` ist für eine SQLite-Datenbank da; authnd selbst hält keinen Zustand – die
Sperrzähler des zweiten Faktors liegen im Speicher und werden bei jedem Neustart zurückgesetzt.

## Das Konfigurationsverzeichnis {#the-configuration-directory}

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

Jede Datei darin `root:authnd`, Modus `0640`. Geheimnisse gehören in Dateien, die über
`*_file`-Schlüssel benannt werden, statt inline: Eine Datei hat Berechtigungen, eine
Konfiguration, die jemand einfügt, nicht. Mit `ProtectSystem=strict` kann der Dienst nicht unter
`/etc` schreiben, was für die Konfiguration richtig ist und für die Passwörter, die Personen
selbst ändern, falsch – geben Sie diesen ein eigenes Verzeichnis:

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

Warum dieses Verzeichnis und nicht die Datei, erklärt
[Ein Passwort ändern]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}}).

| Schlüssel | Standard | |
|---|---|---|
| `base_dn` | – (erforderlich) | die Wurzel des Baums, z. B. `dc=example,dc=org`; ein Wert ohne `=` wird abgelehnt |
| `listen` | `127.0.0.1:3893` | eine Adresse. Standardmäßig Loopback: Ein Verzeichnis, das auf jeder Schnittstelle erscheint, sobald es startet, ist eine Entscheidung, die jemand bewusst treffen sollte. Ein Standort, der LDAP und LDAPS braucht, betreibt zwei Instanzen |
| `reader "<dn>"` | keiner | ein Dienstkonto, das suchen darf; siehe [wer lesen darf]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) |
| `cert_file`, `key_file`, `starttls`, `publish_nt_hash`, `samba` | aus | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`, `group`, `users` | – | [die Personen]({{< relref "/authnd/people.md" >}}); mindestens ein `user`- oder `users`-Block |
| `kerberos` | keiner | [ein Realm]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | keiner | [ein zweiter Faktor]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | keiner | [ein Token beim Bind]({{< relref "/authnd/tokens.md" >}}) |

Ein relativer Pfad in der Konfiguration wird gegen das Verzeichnis aufgelöst, in dem der
Prozess läuft, nicht gegen das der Konfigurationsdatei; die Unit läuft in `/`, also schreiben
Sie Pfade absolut.

Vor jedem Start:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check` wird auf [einer eigenen Seite]({{< relref "/authnd/check.md" >}}) beschrieben; es als
`authnd` auszuführen, beweist auch, dass das Konto jede Datei lesen kann.

## Upgrade, Rollback, Entfernen {#upgrade-roll-back-remove}

Prüfen Sie die Konfiguration mit dem **neuen** Binary, bevor es das alte ersetzt, und behalten
Sie das alte. Das neue Binary wird zuerst neben dem alten installiert: Das macht es ausführbar
und legt es dorthin, wo das Konto `authnd` es ausführen kann.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

Vergleichen Sie `packaging/` am neuen Tag mit dem, was installiert ist (das von v0.12.0 ist
das von v0.11.1, unverändert). Ein Rollback ist dieselbe Installation aus
`authnd.previous` und ein Neustart.

Von v0.10.x auf v0.11.0 ist das `check` oben der Schritt, auf den es ankommt: Eine
Konfiguration mit `publish_nt_hash = true` und ohne
[`samba`-Block]({{< relref "/authnd/tls.md#the-samba-block" >}}) wird dort abgelehnt
statt erst beim Neustart, und die Zeilen nach seinen Tabellen sagen, wer kein
`posixAccount` mehr ist und welche Gruppen keine `posixGroup`s mehr sind
([die Einträge]({{< relref "/authnd/entries.md" >}})).

⛔ Von v0.11.1 auf v0.12.0 spielen Sie das Upgrade ein, was Sie sonst auch tun: Die
Release-Binaries von v0.11.1 wurden mit Go 1.27.2 gebaut und sind von GO-2026-6809
(crypto/x509) betroffen, was v0.12.0, gebaut mit Go 1.27.3, nicht ist. Die Konfiguration
braucht keine Änderung; um das eigene Schema eines Standorts bereitzustellen, siehe
[Standort-Schemata]({{< relref "/authnd/schemas.md" >}}), und nennen Sie die Dateien
mit absoluten Pfaden, denn das Arbeitsverzeichnis einer systemd-Unit ist `/`.

Zum Entfernen:

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`, `/var/lib/authnd` und das Konto `authnd` bleiben bestehen: Die ersten beiden
enthalten die Zugangsdaten von Personen, und einer wiederverwendeten UID können die Dateien
eines anderen Kontos zufallen. Entfernen Sie sie bewusst.
