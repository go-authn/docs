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

Die Version, die diese Seiten beschreiben, ist v0.4.1.

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
  jedem Ende beendet er alles, was der Dienstbenutzer ausführt (nach uid, ein
  Programm, das `setsid` aufgerufen hat, entkommt also nicht), und hängt dann
  aus. root signalisiert nie eine pid, die es aus einer Liste gelesen hat. Seit
  v0.4.0 übernimmt das Töten ein kurzlebiger Killer-Prozess, den root startet und
  der vor jedem Signal auf geteilte Berechtigungen umschaltet (reale und
  gespeicherte uid eines reservierten Killer-Benutzers, effektive uid des
  Dienstbenutzers): Der Kernel lässt ihn dann jeden Prozess des Dienstbenutzers
  signalisieren, während kein Prozess dieses Benutzers ihn signalisieren kann.
  Der Killer sendet `kill(-1, SIGKILL)`, bis der Kernel nichts mehr findet;
  die Tötungen eines Dienstbenutzers werden durch eine Sperre dieses Benutzers
  serialisiert (`/var/run/sdcreds-killer-<uid>.lock`), und eine Tötung eines
  anderen Benutzers lässt eine Freigabe nie warten oder aufgeben. Zwei Killer
  verschiedener Benutzer teilen die reale uid des Killers und können einander
  signalisieren: Ein Killer, der daran stirbt, wird erneut gestartet, denn die
  Prozesstabelle entscheidet, und ein Benutzer, der beim Budget nicht leer ist,
  wird gemeldet (sicher im Fehlerfall).
  **Installationsvoraussetzung:** Legen Sie den Killer-Benutzer an, der keinen
  Prozess besitzen und weder root noch ein Dienstbenutzer sein darf:
  `useradd -s /sbin/nologin -d /var/empty -c "sdcreds killer" _sdkill`. Ohne ihn
  oder wenn er einen Prozess besitzt, wird der Start einer Auslieferung
  verweigert (ein Start wartet bis zu 20 s auf den Killer einer laufenden
  Freigabe). Ein Prozess, der den Benutzer nur
  über eine set-uid-Datei hält, die ein anderer Benutzer ausführt, wird von der
  Startprüfung gezählt, vom Killer aber nicht erreicht: Die Freigabe meldet dann,
  dass ein Prozess überlebt hat, und der nächste Start wird verweigert, bis er
  verschwunden ist (sicher im Fehlerfall). Überlebt ein Prozess das Budget von
  20 s, hängt der Hilfsprozess trotzdem aus (die Geheimnisse verschwinden), meldet
  den Fehler und endet mit einem Status ungleich null. Ein Benutzer gehört jeweils einer
  Auslieferung (die `.uid-<N>.lock` in `/var/run/sdcreds`), und `run` verweigert
  einen Benutzer, der bereits andere Prozesse hat: Geben Sie dem Dienst einen
  eigenen Benutzer. Sterben sdcreds und der Hilfsprozess beide,
  entfernt `sdcreds sweep [--base DIR] [--service S]` (oder der nächste Start des
  Dienstes) den Rest. Schlägt die Freigabe nach dem Ende des Programms fehl,
  beendet sich sdcreds mit Status 70, gleich welchen Status das Programm selbst
  hatte (er wird mit dem Grund auf stderr ausgegeben).
- **Exit-Status von `run`** (seit v0.4.0). Der Status des Programms wird
  durchgereicht (ein durch Signal `n` beendetes Programm ergibt `128+n`). Die
  eigenen Enden von sdcreds haben reservierte Status außerhalb der Bereiche 0-2
  und 64-78, die Daemonen üblicherweise nutzen: **125** sdcreds hat verweigert,
  nichts wurde gestartet (falsche Option, unbekannter oder root-Benutzer,
  unverschlüsselter Swap, ein noch lebender Lauf; dauerhaft, bis sich etwas
  ändert); **126** sdcreds ist nach dem Beginn gescheitert (Auslieferung,
  Hilfsprozess verloren, Programm nicht ausführbar; kann vorübergehend sein);
  **70** das Programm ist beendet, aber die Freigabe ist fehlgeschlagen, gleich welchen
  Status das Programm selbst hatte (er wird dann auf stderr ausgegeben). Ein
  Programm, das selbst mit 125 oder 126 endet, ist nicht zu unterscheiden. Vor
  v0.4.0 endete eine Verweigerung mit 2 und ein Fehler mit 1.
- **Neustart.** Ein Start wartet bis zu 47 s, bis der vorherige Lauf desselben
  Dienstes den Abbau beendet hat (der bis zu 46 s dauern kann), statt verweigert
  zu werden; ein nach 47 s noch lebender Lauf wird verweigert (125). Ein zweiter Dienst für denselben Benutzer
  wird weiterhin sofort verweigert.
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
- **Umgebung und Deskriptoren durchreichen** (OpenBSD, seit v0.4.0).
  `--pass-env NAME` (wiederholbar) reicht die Variable `NAME` aus der Umgebung
  von sdcreds unverändert an das Programm weiter (nicht, wenn sie nicht gesetzt
  ist); `--pass-fd N` (wiederholbar) hält den Deskriptor `N` im Programm unter
  derselben Nummer offen. Beides wird für das verweigert, was sdcreds gehört:
  `PATH`, `CREDENTIALS_DIRECTORY`, `__SDCREDS_*`; die Deskriptoren 0 bis 3; einen
  Deskriptor, der nicht offen oder close-on-exec ist. Ein Supervisor eines
  Dienstes vom Typ notify übergibt zum Beispiel
  `--pass-env NOTIFY_SOCKET --pass-env LISTEN_FDS --pass-env LISTEN_PID --pass-fd 4`.
  `LISTEN_PID` wird unverändert weitergereicht: Es nennt die pid, die der Aufrufer
  erwartet hat, nicht die des Programms.
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
