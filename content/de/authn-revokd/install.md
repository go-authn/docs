---
title: "authn-revokd installieren"
linkTitle: "Installation"
weight: 10
description: "authn-revokd als gehärteter systemd-Dienst oder als einmaliger Lauf mit einem Timer, und wie sshd und ein TLS-Server an das angebunden werden, was es schreibt."
tags: [authn-revokd, installation, systemd]
---

Das Repository liefert in `packaging/` drei Units und ein Konto mit:
`authn-revokd.service` (der Daemon), `authn-revokd-once.service` mit
`authn-revokd-once.timer` (die Alternative) und
`sysusers.d/authn-revokd.conf`.

| Pfad | was | Eigentümer, Modus |
|---|---|---|
| `/usr/local/bin/authn-revokd` | das Binary | root, `0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | das Systemkonto `authn-revokd` | root, `0644` |
| `/etc/systemd/system/authn-revokd.service` | der Daemon | root, `0644` |
| `/etc/authn-revokd/revokd.hcl` | die Konfiguration, das Standard-`-config` | root, `0644` |
| `/etc/authn-revokd/ca/` | die CA-Schlüssel und -Zertifikate, von denen die Listen signiert sein müssen | root, `0755`; die Dateien darin `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`, der einzige beschreibbare Ort | authn-revokd, `0755` |
| `/var/lib/authn-revokd/state/` | `state_dir`: die geprüften Kopien | authn-revokd, `0700` |
| `/var/lib/authn-revokd/sshd.krl` | eine Ausgabe: was `sshd` liest | authn-revokd, `0644` |

**Schreiben Sie die Ausgaben nach `/var/lib/authn-revokd` und lassen Sie die Server dorthin zeigen.**
Eine Ausgabe wird neben ihrem endgültigen Namen geschrieben und darüber umbenannt, daher muss ihr
*Verzeichnis* beschreibbar sein. `/etc/ssh` beschreibbar zu machen, würde dem
Konto `authn-revokd` erlauben, `sshd_config` zu ersetzen. Ausgaben haben `0644`, trotz
`UMask=0077` ausdrücklich per chmod gesetzt, damit `sshd` und ein TLS-Server, der unter seinem
eigenen Benutzer läuft, sie lesen können; der Zustand bleibt `0700`.

## Das Binary, das Konto, die Unit {#the-binary-the-account-the-unit}

Ein Release enthält `authn-revokd-<os>-<arch>` für Linux, macOS und Windows auf
amd64 und arm64, mit `SHA256SUMS` und Build-Provenienz
([einen Download prüfen]({{< relref "/security/verifying-releases.md" >}})). Oder
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.2`.

Das Konto und die Unit stammen aus dem Verzeichnis `packaging/` des
Release-Tags, derselben Version wie das Binary: Kopieren Sie dieses Verzeichnis
neben das Binary, aus einem Checkout des Tags oder, für v0.6.2, von
<https://github.com/go-authn/revocation/tree/v0.6.2/packaging>.

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

Das Konto ist statisch, nicht `DynamicUser=`. authn-revokd lehnt ein Zustandsverzeichnis
ab, das jemand anderem gehört als seiner eigenen UID oder root, und der Zustand muss die
nächste Liste über Neustarts und Aktualisierungen hinweg weiter ordnen. Mit einem dynamischen Benutzer lägen die
Dateien unter `/var/lib/private`, `0700` root, und ein TLS-Server, der unter seinem eigenen
Benutzer läuft, könnte die CRL nicht lesen.

## Der Daemon {#the-daemon}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

und darum herum: `User=authn-revokd`, überhaupt keine Capability, `NoNewPrivileges=`,
`ProtectSystem=strict` mit `StateDirectory=authn-revokd` (`0755`) als einzigem
beschreibbarem Ort, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
`PrivateIPC=`, nur `AF_INET AF_INET6 AF_UNIX`, die Systemaufrufe von `@system-service`
abzüglich `@privileged @resources`.

**`Restart=always`, weil sshd den Ablauf in der KRL ignoriert.** Dass die Datei
geschlossen fehlschlägt (fail closed), wenn eine Liste verfällt, besorgt *dieser Prozess*. Solange er gestoppt ist, liest sshd
weiter die letzte Datei, die er geschrieben hat, und ein zwischenzeitlich ausgesprochener Widerruf kommt nie
an. Überwachen Sie die Unit oder `/healthz`, wenn der Spiegel aktiv ist.

**`systemctl reload` synchronisiert sofort.** Es sendet `SIGHUP`, und der Agent ruft jede
Quelle sofort ab statt beim nächsten `refresh`:

```
hangup: syncing now
```

Die Konfiguration wird dabei nicht neu gelesen; sie wird einmal gelesen, beim Start: Nach einer
Änderung an `revokd.hcl` `systemctl restart authn-revokd`. (Vor v0.6.0 beendete ein
nicht abgefangenes `SIGHUP` den Prozess, und systemd wertet das als sauberes Ende.)

### Aktivieren Sie es, BEVOR Sie sshd anbinden {#enable-it-before-wiring-sshd}

{{< callout type="warning" >}}
**sshd lehnt jedes Zertifikat ab, wenn `RevokedKeys` eine Datei nennt, die nicht existiert**

Starten Sie daher zuerst authn-revokd und warten Sie, bis die Ausgabe vorhanden ist:
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl` gibt ihren Kommentar aus,
`authn-revokd sshd`, solange jede Quelle aktuell ist.
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

Dann in `/etc/ssh/sshd_config`:

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

und `sshd -t && systemctl reload ssh`. sshd liest `RevokedKeys` bei jeder
Authentifizierung, braucht also kein Neuladen, wenn authn-revokd die Datei neu schreibt: Die
atomare Umbenennung genügt.

### Die CRL eines TLS-Servers {#a-tls-servers-crl}

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

Ein TLS-Server liest seine CRL, wenn er seine Konfiguration lädt, daher muss er
neu geladen werden, wenn sich die Datei ändert. Ein `on_change`-Befehl läuft unter dem
Konto `authn-revokd`, das kein `systemctl reload nginx` ausführen kann: Lassen Sie stattdessen systemd
die Datei überwachen, als root, mit einer Path-Unit (`PathChanged=` auf die Ausgabe), die
einen `oneshot` startet, der `systemctl reload nginx` ausführt.

## Oder: `-once`, mit einem Timer {#or--once-on-a-timer}

`authn-revokd -once` synchronisiert einmal und endet, mit `1`, wenn eine Liste nicht aktuell ist oder
nicht abgerufen werden konnte ([was `-once` meldet]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
Die Ausgaben werden in jedem Fall geschrieben, und für sshd fail-closed, sobald eine Liste
verfällt.

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

Der einmalige Lauf hat das Konto und die Härtung des Daemons. `TimeoutStartSec=5min`
verhindert, dass eine Synchronisierung, die an einer Quelle hängt, den nächsten Takt überdauert, und
`RandomizedDelaySec=10s` verhindert, dass eine gemeinsam gestartete Flotte ihren
Aussteller im Gleichschritt abfragt.

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**Aktivieren Sie nie beide**: Die Units stehen in Konflikt, sodass das Starten der einen die andere stoppt.
Der Daemon bleibt die bessere Wahl. Er lässt eine verfallene Liste bei seinem nächsten
`refresh` geschlossen fehlschlagen, wo der Timer auf seinen nächsten Takt wartet, und nur der Daemon dient als
Spiegel: `listen` wird mit `-once` ignoriert. Ein Timer, der nicht mehr auslöst, ist ein Daemon,
der angehalten hat; überwachen Sie also `systemctl status authn-revokd-once`.

## Aktualisieren und zurückgehen {#upgrading-and-going-back}

Installieren Sie das neue Binary neben dem alten, tauschen Sie, starten Sie neu. Der Zustand bleibt erhalten:
Die geprüften Kopien ordnen weiterhin die nächsten Listen, sodass weder eine Aktualisierung noch ein
Zurückgehen auf ein älteres Binary eine ältere Liste hereinlässt.

## Deinstallieren {#uninstalling}

Entfernen Sie **zuerst** `RevokedKeys` und `ssl_crl` aus der Konfiguration der Server
und laden Sie sie neu: sshd lehnt jedes Zertifikat ab, sobald die Datei fehlt.
