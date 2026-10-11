---
title: "authn-bridge installieren"
linkTitle: "Installation"
weight: 10
description: "Ein statischer Benutzer, drei Verzeichnisse und eine gehärtete systemd-Unit: authn-bridge vom Release-Binary zum laufenden Dienst."
tags: [authn-bridge, installation, systemd]
---

Das Repository liefert die Unit und den Benutzer, unter dem sie läuft:
`packaging/systemd/authn-bridge.service` und
`packaging/sysusers.d/authn-bridge.conf`. Alles Folgende läuft als root, sofern
nicht anders angegeben.

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | das Binary |
| `/etc/authn-bridge/*.hcl` | die Konfiguration, in Namensreihenfolge gelesen; `root:authn-bridge`, `0750`, Dateien `0640` |
| `/var/lib/authn-bridge/` | Schlüssel, das Subject-Salt, der SQLite-Zustand, die ausgestellten Zertifikate, die Liste der Deaktivierten; `authn-bridge`, `0700` |
| `/run/authn-bridge/` | der Admin-Socket, wenn die Konfiguration einen verlangt |

## Das Binary {#the-binary}

Ein Release enthält `authn-bridge-<os>-<arch>` für Linux, macOS und Windows auf
amd64 und arm64, ein `SHA256SUMS`-Manifest und eine Build-Provenance-Attestierung je
Binary; [einen Download prüfen]({{< relref "/security/verifying-releases.md" >}})
beschreibt, wie beides geprüft wird. Oder bauen Sie es selbst, was die Version im Binary festhält:

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.0
$ authn-bridge --version
authn-bridge version v0.23.0
```

Der Pfad ist wichtig: Ab v0.20.0 liegt das Programm in `internal/app` und der
Befehl in `cmd/authn-bridge`, sodass `go install github.com/go-authn/bridge@...`
nichts baut.

## Der Benutzer, und warum er kein dynamischer ist {#the-user-and-why-it-is-not-a-dynamic-one}

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

Die Unit nennt `User=authn-bridge`, nicht `DynamicUser=`. Der Signaturschlüssel, das
Subject-Salt, der SAML-Schlüssel und die Zertifizierungsstellen werden **vor** dem
ersten Start erzeugt, leben jahrelang und müssen über Neuinstallationen und
Wiederherstellungen aus Backups hinweg einen einzigen Eigentümer behalten. Ein dynamischer Benutzer erhält seine UID erst, wenn der Dienst startet.

## Die Schlüssel {#the-keys}

Führen Sie `keygen` als Benutzer des Dienstes aus, damit ihm gehört, was es schreibt. Es lehnt
es ab, eine bereits vorhandene Datei zu überschreiben:

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

Auf einem Server liegen die Pfade unter `/var/lib/authn-bridge`, und der Befehl lautet
`runuser -u authn-bridge -- authn-bridge keygen ...`.

| Flag | schreibt | für |
|---|---|---|
| `--key` | einen RSA-3072-Schlüssel | ID-Tokens (RS256), veröffentlicht unter `/jwks` |
| `--salt` | 32 Zufallsbytes | jedes `sub`, das ein HMAC darunter ist |
| `--access-token-key` | einen P-256-Schlüssel | stattdessen mit ES256 signierte Access-Tokens, viel kürzer |
| `--ssh-ca` | einen Ed25519-Schlüssel im OpenSSH-Format | die [SSH-Zertifikate]({{< relref "/authn-bridge/certificates.md" >}}) und die Signatur der KRL |
| `--x509-ca DIR` | `DIR/ca.key` (P-256) und `DIR/ca.crt`, zehn Jahre gültig, Pfadlänge 0 | NFS-Client-Zertifikate und die CRL |

{{< callout type="warning" >}}
**Sichern Sie das Salt, und ändern Sie es nie**

Ein neues Salt gibt jeder Person ein neues `sub`, und jede Relying Party sieht
dann eine neue Person. Dasselbe gilt, wenn es bei der Deinstallation gelöscht wird.
{{< /callout >}}

Der SAML-Schlüssel und das Zertifikat werden mit `openssl` erzeugt: Sie sind das, was die
Föderation registriert und wofür jeder IdP verschlüsselt. Der Schlüssel muss RSA sein (IdPs
verschlüsseln dafür mit RSA-OAEP). Er ist nicht das TLS-Zertifikat und ändert sich nicht
mit diesem.

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

Das Signaturzertifikat der Föderationsmetadaten stammt von der Föderation, und ebenso
sein SHA-256-Fingerabdruck: Nehmen Sie den Fingerabdruck von der Webseite der Föderation,
nie aus demselben Download wie das Zertifikat. Siehe
[die Föderationsseite]({{< relref "/authn-bridge/federation.md" >}}).

## Die Unit {#the-unit}

Was sie gewährt, in Kürze:

- `Type=exec`, `Restart=on-failure`, `RestartSec=5s`, `TimeoutStopSec=20s`.
  Der Anbieter fährt seinen Listener innerhalb von zehn Sekunden nach `SIGTERM` herunter.
- `StateDirectory=`, `RuntimeDirectory=` (beide `0700`) und
  `ConfigurationDirectory=` (`0750`), `UMask=0077`. Mit
  `ProtectSystem=strict` ist alles andere schreibgeschützt.
- Keine Capability (`CapabilityBoundingSet=` und `AmbientCapabilities=` leer),
  `NoNewPrivileges=`, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
  `PrivateIPC=`, `ProtectHome=`; Kernel, Uhr, Hostname und Control
  Groups geschützt.
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`: TCP für den Listener,
  die Metadaten, eine ACME-CA und eine Datenbank; ein Socket für die Admin-API.
- `SystemCallFilter=@system-service`, abzüglich `@privileged @resources`, abgelehnt
  mit `EPERM` statt mit einem Kill.

Sie wartet auf `network-online.target`, weil die Metadaten abgerufen werden, bevor
der Anbieter lauscht.

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

Die erste Zeile im Journal ist die, die auf
[der Übersicht]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}}) gezeigt wird.

### Änderungen erfordern einen Neustart {#changes-need-a-restart}

Die Konfiguration wird einmal gelesen. Die Unit hat kein `ExecReload=`, daher wird `systemctl
reload` abgelehnt, statt so zu tun als ob. Ein `SIGHUP` (von logrotate oder aus Gewohnheit)
wird abgefangen, protokolliert und ignoriert. Dem Standardverhalten von Go überlassen, würde es den Prozess beenden,
und systemd würde das als sauberes Beenden werten, das `Restart=on-failure` nicht
neu startet:

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

TLS-Zertifikatsdateien sind die Ausnahme: Sie werden neu gelesen, wenn sie sich ändern.

### Port 443 {#port-443}

Der Standard-Listener ist `127.0.0.1:8080`, hinter einem TLS-Reverse-Proxy, und
braucht keine Capability. Um TLS selbst auf Port 443 auszuliefern (`cert_file` oder `acme`),
braucht der Anbieter `CAP_NET_BIND_SERVICE` und muss den privaten User-Namespace
verlassen, da eine darin gehaltene Capability nicht für das Netzwerk des Hosts
gilt:

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## Aktualisieren und zurückgehen {#upgrading-and-going-back}

Sichern Sie zuerst `/var/lib/authn-bridge`: Es enthält die Schlüssel und das Salt, die
sich nicht neu erzeugen lassen. Behalten Sie das funktionierende Binary, installieren Sie das neue, starten Sie neu:

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

Zurückgehen funktioniert genauso mit `authn-bridge.previous`. Ein neueres Release kann eine
neuere Unit mitbringen: Vergleichen Sie sie mit Ihrer, installieren Sie sie und führen Sie vor dem Neustart
`systemctl daemon-reload` aus.

### Umstieg von `bridge` {#coming-from-bridge}

Die Konfiguration ist unverändert; nur der Befehl und die Release-Assets wurden
umbenannt. Ändern Sie jede Unit, jedes Skript, jeden Cronjob und jedes `bearer_token_command`, das
`bridge` ausführt. Die Logzeile und das Fehlerpräfix lauten jetzt `authn-bridge`, sodass ein
Alarm, der auf `bridge v0.` passte, auf `authn-bridge v0.` passen muss. Metriknamen
(`bridge_*`), die Tabelle `bridge_state` und der benutzerseitige Cache
(`go-authn-bridge` im Konfigurationsverzeichnis des Benutzers, `~/.config` unter
Linux) sind unverändert, sodass `authn-bridge token` die Anmeldungen wiederverwendet, die `bridge`
zwischengespeichert hat.
