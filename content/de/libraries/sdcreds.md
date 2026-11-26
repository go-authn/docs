---
title: "sdcreds — systemd-Credentials, ohne systemd"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds liest und schreibt das systemd-Credential-Format (systemd-creds encrypt und decrypt) aus Go, mit einer Kommandozeile und einem s6-Helfer, der einem überwachten Dienst sein $CREDENTIALS_DIRECTORY gibt."
tags: [libraries, sdcreds, secrets, s6]
---

**Was, wenn ein Dienst die Credentials braucht, die eine systemd-Unit über
`LoadCredentialEncrypted=` erhält, und es kein systemd gibt?** `sdcreds` liest und
schreibt das [systemd-Credential](https://systemd.io/CREDENTIALS/)-Format
(`systemd-creds encrypt` / `decrypt`) aus Go, mit einer Kommandozeile und einem
Helfer, der einem von s6 überwachten Dienst dasselbe `$CREDENTIALS_DIRECTORY`
gibt.

Unterstützte Schlüssel: **null**, **host** (`/var/lib/systemd/credential.secret`)
und **host-scoped** (`--uid` / `--user`). TPM2- und Public-Key-Credentials werden
erkannt und mit `*UnsupportedModeError` abgelehnt; nichts wird geraten.

## Installation {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

Die Version, die diese Seiten beschreiben, ist v0.3.0.

## Kommandozeile {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

Dasselbe aus Go:

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run` entschlüsselt jede Datei von `--source`, **bevor** etwas eingehängt wird,
hängt ein `tmpfs` pro Dienst ein (`nodev,noexec,nosuid,nosymfollow,noswap`, Modus
0700, Größe und Inode-Anzahl begrenzt; `ramfs`, wenn der Kernel diese Optionen
nicht kennt), schreibt den Klartext mit 0400 und dem Dienstbenutzer als Besitzer,
hängt es schreibgeschützt neu ein, setzt `CREDENTIALS_DIRECTORY` und startet dann
den Dienst in einem Kindprozess, der Privilegien abgibt (`no_new_privs`, eine
leere Capability-Menge), und wartet auf ihn.

- `s6-run` bleibt der Prozess, den s6 überwacht: Es leitet `TERM`, `INT`, `HUP`,
  `QUIT`, `USR1`, `USR2`, `ALRM` und `CONT` an den Dienst weiter, beendet sich mit
  dessen Status (128 plus Signalnummer, wenn ein Signal ihn beendet hat), reicht
  die erhaltenen Deskriptoren weiter, und der Dienst wird beendet, wenn `s6-run`
  stirbt.
- Die Credentials werden entfernt, wenn der Dienst endet, und bevor `s6-run`
  fehlschlägt, wenn das Programm nicht ausgeführt werden kann.
- Das Einhängen geschieht standardmäßig in einem privaten Namensraum
  (`--unshare=false` schaltet das ab), es verschwindet also mit dem Dienst.
- Ein mit dem Null-Schlüssel versiegeltes Credential wird abgelehnt, es sei denn,
  `--allow-null` ist gesetzt, und eines ohne Namen wird immer abgelehnt.
- `sdcreds s6-finish --service=web` hängt verzögert aus und entfernt das
  Verzeichnis; es ist idempotent. Mit `--unshare=false` lässt ein `SIGKILL` von
  `s6-run` das Einhängen bestehen, bis `s6-finish` läuft: Setzen Sie es in das
  Finish-Skript des Dienstes.
- Höchstens 1024 Credentials und 16 MiB pro Dienst. Nur Linux; anderswo melden
  die Befehle `ErrUnsupported`.

Die mit `--secret` und `--machine-id-file` benannten Schlüsseldateien müssen
root gehören und für Gruppe und andere nicht beschreibbar sein, ebenso jedes
Verzeichnis darüber bis `/`. Die Schlüsseldatei wird einmal geöffnet, ohne einem
abschließenden Link zu folgen, und der Schlüssel wird aus dem Speicher von
`s6-run` gelöscht, sobald es mit den Credentials fertig ist. Nur das Kind nimmt
die Identität des Dienstes an; `s6-run` und alle seine Threads bleiben root.

### Eine Capability behalten: `--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

Die Option ist wiederholbar und kommagetrennt (`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`
oder je eine Option) und hat **keinen Standardwert**: ohne sie läuft der Dienst
mit leeren Capability-Mengen.

Es ist eine **Allowlist** von sieben Capabilities, von denen keine root-äquivalent
ist oder das Credential-tmpfs lesen oder schreiben oder `s6-run` signalisieren
kann: `CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`, `CAP_NET_RAW`, `CAP_NET_BROADCAST`,
`CAP_IPC_LOCK`, `CAP_WAKE_ALARM` und `CAP_BLOCK_SUSPEND`. Jede andere Capability
oder ein Name, der keine Capability ist, ist ein Fehler, der die Allowlist nennt und
gemeldet wird, bevor der Schlüssel gelesen oder etwas eingehängt wird.

Der Dienst hat in seinen Mengen bounding, permitted, inheritable, effective und
ambient genau die behaltenen Capabilities und sonst nichts. `no_new_privs` bleibt
aktiv, und die Securebits sind 0x3 (`SECBIT_NOROOT` gesetzt und gesperrt). Die
Rechte von `s6-run` selbst bleiben unverändert.

`CAP_NET_ADMIN` wirkt auf den Netzwerk-Namensraum, in dem der Dienst läuft; das ist
der des Hosts, sofern der Dienst nicht in einem eigenen Netzwerk-Namensraum
gestartet wird (`--unshare` gibt ihm nur einen privaten Mount-Namensraum): dort
kann er Schnittstellen, Routen und die Firewall ändern. Starten Sie einen solchen
Dienst in einem eigenen Netzwerk-Namensraum, wenn das wichtig ist.

## `sdcreds run`: OpenBSD und Linux {#run}

```sh
sdcreds run --service=web --user=svc --source=/etc/creds [--class=daemon] -- /usr/local/bin/web
```

`run` entschlüsselt die versiegelten Dateien von `--source`, macht sie dem
Programm als schreibgeschützte, `--user` gehörende Dateien unter
`$CREDENTIALS_DIRECTORY` sichtbar, startet es als dieser Benutzer und entfernt
sie, wenn es endet. Unter Linux ist es `s6-run` mit denselben Optionen.
`--check` führt jede Verweigerung aus und entschlüsselt nichts (für einen
`rc_pre` in rc.d). Eine Verweigerung beendet sich mit Status 2 und geschieht,
bevor der Host-Schlüssel gelesen wird. Unter OpenBSD liegen die Dateien in einem
Speicherdateisystem (MFS), das für den Dienst eingehängt und am Ende genullt
wird:

- **Es gibt keinen Mount-Namensraum.** Solange das Programm läuft, sind die
  Credentials für jeden Prozess sichtbar, der das Verzeichnis erreicht, und root
  kann sie immer lesen.
- **Der Host-Schlüssel** ist `/etc/sdcreds/host.key`, Eigentümer root, Modus
  0600; jeder andere Modus oder Eigentümer wird verweigert. Erzeugen Sie ihn mit
  `sdcreds setup --path /etc/sdcreds/host.key` und danach `chmod 600`. Die
  Maschinen-ID ist `sysctl hw.uuid`. `--secret` und `--machine-id-file`
  überschreiben beides und durchlaufen dieselben Prüfungen von Eigentümer und
  Modus.
- **`--user` ist nie root**: uid 0, gid 0 und jede ergänzende Gruppe 0 werden
  verweigert, in `run` wie in der Bibliothek (`s6.Run`, `delivery`); keine
  Option erlaubt es. Das Programm muss ein absoluter, normalisierter Pfad sein,
  den der Benutzer ausführen darf.
- **Wer sdcreds beendet, beendet das Programm** und hängt aus, auch mit
  `SIGKILL`. Ein Hilfsprozess hält die Dienstsperre und überwacht sdcreds; bei
  jedem Ende beendet er alles, was der Dienstbenutzer ausführt (nach realer uid,
  ein Programm, das `setsid` aufgerufen hat, entkommt also nicht), und hängt dann
  aus. Die Entscheidung zu töten trifft root: Der Hilfsprozess hält jeden
  gefundenen Prozess an, liest die Prozesstabelle erneut, bis sie sich nicht mehr
  ändert, sendet dann `SIGKILL` und wiederholt das, bis der Benutzer keinen
  Prozess mehr hat. Ein Prozess, bei dem nur die effektive uid die des
  Dienstbenutzers ist, gilt als beschäftigt, der Start wird also verweigert, er
  wird aber nicht getötet. Überlebt ein Prozess das Budget von 20 s, hängt der
  Hilfsprozess trotzdem aus (die Geheimnisse verschwinden), meldet den Fehler und
  endet mit einem Status ungleich null. Ein Benutzer gehört jeweils einer
  Auslieferung (die `.uid-<N>.lock` in `/var/run/sdcreds`), und `run` verweigert
  einen Benutzer, der bereits andere Prozesse hat: Geben Sie dem Dienst einen
  eigenen Benutzer. Sterben sdcreds und der Hilfsprozess beide,
  entfernt `sdcreds sweep [--base DIR] [--service S]` (oder der nächste Start des
  Dienstes) den Rest. Schlägt die Freigabe nach dem Ende des Programms fehl,
  beendet sich sdcreds mit Status 70 (oder dem Status des Programms, wenn das
  schon ein Fehler war) und nennt den Grund auf stderr.
- **Swap muss verschlüsselt sein.** `run` startet nicht, wenn
  `sysctl vm.swapencrypt.enable` 0 ist, nicht gelesen werden kann oder nicht
  existiert. Keine Option umgeht das. In der Bibliothek verlangt `s6.Config` ein
  `ReadSource` (der Befehl liefert den Leser, der die Vertrauenskette prüft),
  sonst verweigert `s6.Run`.
- **Die eingebetteten Dateisystem-Abbilder sind festgeschrieben**: Der sha256
  jeder `delivery/images/ffs-<N>MiB.gz` wird geprüft, bevor der Hilfsprozess sie
  dekomprimiert.
- **`--class`** wird zuerst in `/etc/login.conf.d/<class>` gesucht, dann in
  `/etc/login.conf`; `login.conf.db` wird nicht befragt. Die Ressourcengrenzen
  der Klasse gelten für das Programm und senken nur, was es sonst hätte; eine
  Klasse, die nicht gelesen oder geparst werden kann, wird verweigert. Priorität
  und umask werden nicht angewendet; das Programm erhält umask 077.
- **Die Umgebung des Programms ist eine Positivliste**: `PATH` (fester
  Standardwert), `CREDENTIALS_DIRECTORY`, `LANG`, `TZ`, `TERM` und `LC_*`.
  Deskriptoren über 2 werden vor dem Start geschlossen.
- **Speicher.** Der Klartext liegt kurz im Speicher des sdcreds-Prozesses.
  `mlockall` ist aus einem Go-Prozess unter OpenBSD nicht nutzbar (gemessen auf
  8.0); der Schutz sind daher `vm.swapencrypt.enable` (beim Start geprüft),
  abgeschaltete Core-Dumps und `kern.nosuidcoredump`. Ein von einem
  Administrator erzeugter Absturzabzug kann den Klartext weiterhin enthalten.
- `--keep-cap` gibt es nur unter Linux.

`docs/openbsd/authn_bridge` im Repository ist ein rc.d-Skript, das
go-authn/bridge auf diese Weise startet. Die Auslieferung ist auch eine
Bibliothek, das Paket `delivery`.

## Interoperabilität {#interop}

Beide Richtungen werden gegen das echte `systemd-creds` **262.2** getestet, aus
dem Tag `v262.2` gebaut (kein Distributionspaket).

- `testdata/systemd-v262.2` enthält 44 von systemd-creds geschriebene
  Credentials (null, host und host-scoped; mit und ohne Namen; kein, vergangenes
  und zukünftiges not-after; Nutzlasten von 0 B, 1 B und 64 KiB; fünf
  manipulierte Varianten), und `manifest.json` hält fest, was systemd-creds
  selbst für jeden von 272 Entschlüsselungsversuchen geantwortet hat (richtiger
  und falscher Name, vor und nach not-after, mit und ohne `--uid`). Die
  Bibliothek liefert für jeden dieselbe Antwort mit derselben Fehlerklasse.
- Mit festem IV reproduziert `Encrypt` die Bytes von systemd exakt.
- Im Container öffnet `systemd-creds decrypt`, was `Encrypt` geschrieben hat, und
  die Kommandozeile besteht denselben Hin- und Rückweg in beiden Richtungen.

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

Ohne `SDCREDS_REQUIRE_SYSTEMD=1` werden die Tests, die das Binary brauchen,
übersprungen; die CI setzt es, ein fehlendes Binary ist dort also ein Fehler. Die
1-MiB-Grenze wird nur von den Bibliothekstests abgedeckt, nicht von
Interop-Vektoren.

## Abweichungen von systemd {#deviations}

- Ein Host-Secret, dessen Machine-ID nicht passt, wird **abgelehnt**
  (`ErrHostKeyMachine`); systemd entfernt es.
- `--with-key=auto` bedeutet `host`: Hier gibt es kein TPM2.
- Ein mit dem Null-Schlüssel versiegeltes Credential bietet keine Geheimhaltung:
  `sdcreds decrypt` lehnt es auf jeder Maschine ab, es sei denn, `--allow-null`
  ist gesetzt (systemd dagegen prüft den Zustand von TPM2 und SecureBoot; diese
  Bibliotheksrichtlinie, `SystemNullPolicy`, wird von der CLI nicht verwendet).
- `SDCREDS_MACHINE_ID_FILE` (`encrypt`, `decrypt`, `setup`) verweist auf eine
  andere Machine-ID-Datei. `s6-run` ignoriert sie und
  `SYSTEMD_CREDENTIAL_SECRET`: Sein Schlüssel stammt aus den
  Standarddateien oder aus `--secret` und `--machine-id-file`.
- Eine variable IV-Größe wird beim Lesen akzeptiert, wie in systemd; diese
  Bibliothek schreibt immer 12 Bytes.
- Das Secret wird geöffnet, ohne einem abschließenden Symlink zu folgen, und muss
  eine reguläre Datei mit einem Link und Modus `0400` sein, wie es systemd
  verlangt.

## Sicherheit {#safety}

Jede Länge wird geprüft, bevor sie verwendet wird, bevor etwas alloziert wird, und
auf beiden Seiten ihrer Grenze; Credentials sind auf 1 MiB begrenzt (wie bei
systemd) und das Host-Secret auf 16 MiB. Die Parser werden in der CI mit
eingecheckter Korpusdatei gefuzzt, und `govulncheck` läuft in der CI. Das README
hat noch keine Performance-Tabelle: Die Messung ist aufgeschoben, ein offener
Punkt und kein Ergebnis.

## Referenz {#reference}

Das README unter
[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) ist die
maßgebliche Quelle für diese Seite. Siehe die `LICENSE` des Moduls.
