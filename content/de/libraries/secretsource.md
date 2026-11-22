---
title: "secretsource — ein Geheimnis aus einer Referenz"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource holt eine PIN, ein Passwort oder einen Wiederherstellungscode aus einer Referenz (Datei, macOS-Schlüsselbund, Secret Service, KeePassXC), damit keine Klartextdatei auf der Platte bleibt."
tags: [bibliotheken, secretsource, geheimnisse]
---

**Woher kommt eine PIN, wenn sie nicht in einer Datei liegen soll?** Eine
**Referenz** benennt, wo ein Geheimnis liegt; `secretsource.Open` holt es. Die
Referenz enthält kein Geheimnis und darf daher in einer Option, einem Skript
oder der Shell-Historie stehen.

```sh
go get github.com/go-authn/secretsource@v0.9.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Referenz | Liest |
|---|---|
| `file:PATH` | eine reguläre Datei, nur für den Besitzer lesbar (Unix: Modus 0600 oder strenger; Windows, seit v0.7.0: eine Zugriffsliste, die niemandem außer Besitzer, SYSTEM und der Gruppe Administratoren ein Lese- oder Schreibrecht gewährt); ein abschließender Zeilenumbruch wird entfernt; eine Datei, die leer ist oder nur einen Zeilenumbruch enthält, wird mit `ErrEmpty` abgelehnt (seit v0.6.0), und eine FIFO wird als keine reguläre Datei abgelehnt |
| `keychain:SERVICE/ACCOUNT` | ein generisches Passwort-Objekt im macOS-Schlüsselbund |
| `secretservice:SERVICE/ACCOUNT` | ein freedesktop-Secret-Service-Objekt mit den Attributen `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, Secret-Service-Integration von KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | das eine Secret-Service-Objekt mit all diesen Attributen; mehrere Treffer werden abgelehnt |
| `keepassxc:URL` | der KeePassXC-Eintrag, dessen **URL-Feld** diese URL ist (`https://NAME.invalid/...` ist eine gute Wahl, die sich nie auflöst); zwei Einträge mit derselben URL werden als mehrdeutig abgelehnt |
| `systemd-creds:NAME` | (Linux, seit v0.8.0) ein systemd-Credential, Byte für Byte zurückgegeben: kein Entfernen des abschließenden Zeilenumbruchs, anders als bei `file:`. Zuerst die Datei `NAME` in `$CREDENTIALS_DIRECTORY` (angelegt durch `LoadCredential=`, `LoadCredentialEncrypted=`, `SetCredentialEncrypted=`); sonst `NAME` oder `NAME.cred` in `credstore.encrypted` unter `/etc`, `/run`, `/usr/lib`, entschlüsselt mit `systemd-creds decrypt`. Auf anderen Systemen mit `ErrUnavailable` abgelehnt |

**`file:` folgt keinem symbolischen Link** (seit v0.9.0). Ein Link an der
letzten Komponente des Pfads, hängend oder nicht, wird abgelehnt: Unter Unix
wird die Datei mit `O_NOFOLLOW` geöffnet, unter Windows mit
`FILE_FLAG_OPEN_REPARSE_POINT`, und jeder Reparse-Punkt wird abgelehnt (auch
ein Cloud-Files-Platzhalter: auf eine gewöhnliche lokale Kopie verweisen). Unter
Unix muss die Datei außerdem dem aufrufenden Benutzer gehören; root ist nicht
ausgenommen. **Migration:** auf die echte Datei verweisen (`readlink -f PATH`).
Ein symbolischer Link in einem Verzeichnis weiter vorn im Pfad funktioniert
weiterhin.

`keepassxc:by-uuid/...` und `keepassxc:by-path/...` werden **abgelehnt**:
KeePassXC 2.8.0 stürzt ab, wenn eine Suche einen Eintrag ohne URL findet.

**Kein Schema führt einen Befehl aus**: eine Option darf nie einen Prozess
starten können. Eine Referenz ohne Schema wird abgelehnt, nicht als Pfad erraten
(`file:` ist die Schreibweise eines Pfads). Ein Geheimnis über 4096 Bytes oder
ein leeres von einem Manager oder einer `file:`-Referenz wird abgelehnt (`ErrEmpty`), und ein Aufruf endet mit seinem
Kontext (2 Minuten ohne Frist), auch wenn der Manager darauf wartet, dass Sie
ihn entsperren.

## systemd-Credentials {#systemd-creds}

Grammatik, genau: `systemd-creds:NAME`, das Schema in Kleinbuchstaben, ein
Doppelpunkt, dann der Credential-Name, wie er `LoadCredential=`,
`LoadCredentialEncrypted=` oder `systemd-creds encrypt --name=` übergeben wurde,
zum Beispiel `systemd-creds:smtp`. `NAME` ist ein einfacher Dateiname von 1 bis
255 Bytes: kein `/` (also kein Pfad), nicht `.` oder `..`, kein Steuerzeichen und
kein Suffix `.cred` (das Suffix gehört zur Datei; `smtp` findet `smtp` oder
`smtp.cred`).

- Die Datei in `$CREDENTIALS_DIRECTORY` wird mit `O_NOFOLLOW` geöffnet, muss eine
  reguläre Datei sein, die root oder dem Aufrufer gehört und für "andere" keinen
  Zugriff hat (Gruppenbits sind erlaubt: systemd gibt einem Dienst mit `User=`
  eine root gehörende Datei 0440 mit ACL); das Verzeichnis ebenso. Ein Symlink
  oder ein zu offener Modus wird abgelehnt.
- Sonst wird `systemd-creds decrypt --name=NAME PATH -` direkt ausgeführt: keine
  Shell, eine leere Umgebung, das Geheimnis nur von der Standardausgabe gelesen,
  höchstens 4096 Bytes, begrenzt durch den Kontext. Ein Aufrufer ohne root
  versucht zuerst `--user` (systemd 256 oder neuer).
- Kein Trimmen: ein abschließender Zeilenumbruch, NUL-Bytes und Nicht-UTF-8-Bytes
  bleiben erhalten; versiegeln Sie ein Passwort daher mit `printf %s`.
- Gemessen mit systemd 257 (Debian 13) und `--with-key=host`; nicht mit einem
  TPM2-Schlüssel gemessen. Eine fehlgeschlagene Entschlüsselung liefert
  `ErrUnavailable` und weist darauf hin, dass das Credential neu versiegelt
  werden muss.
- PCR-Bindung: `--tpm2-pcrs=` ist standardmäßig leer. Ein nacktes
  `--tpm2-pcrs=7` kann nach einem Firmware- oder Shim-Update oder einer
  vTPM-Migration jedes Credential sperren. Besser `--with-key=host+tpm2`, eine
  signierte PCR-Richtlinie (`--tpm2-public-key`, PCR 11) oder `systemd-pcrlock`,
  und eine Kopie des Geheimnisses zum erneuten Versiegeln aufbewahren.

## KeePassXC {#keepassxc}

KeePassXC wird über sein Browser-Integrationsprotokoll erreicht, unter macOS und
Linux; Windows ist noch nicht umgesetzt. Seit v0.6.0 wird unter Unix der Socket
abgelehnt, wenn er ein symbolischer Link ist oder sein Verzeichnis einem anderen
Benutzer gehört oder für Gruppe oder andere beschreibbar ist, und die uid des
verbundenen Peers wird nach dem Dial geprüft; dem alten Symlink
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` wird nicht mehr gefolgt
(dem echten Socket unter `app/org.keepassxc.KeePassXC/` schon).

Seit v0.6.1 wird die Zuordnungsdatei (der Ersatzspeicher, wenn weder die macOS-Keychain
noch ein Secret Service vorhanden ist) in eine neue temporäre Datei im selben Verzeichnis
geschrieben und auf den endgültigen Namen umbenannt; ein dort liegender symbolischer
Link wird also ersetzt, nicht verfolgt, und eine Datei mit lockererem Modus kommt als
0600 heraus. Unter Unix wird zuvor das Verzeichnis geprüft, wie das des Sockets: im
Besitz dieses Benutzers, nicht für Gruppe oder andere beschreibbar, kein symbolischer
Link; andernfalls wird nichts geschrieben.

Seit v0.8.1 schreibt
[`harden/privfile`]({{< relref "/libraries/harden.md#privfile" >}}) v0.2.0 diese
Datei. Unter Windows erhält sie jetzt eine geschützte Zugriffsliste nur für den
Eigentümer, wie in go-authn/kinit v0.3.2, und das Verzeichnis wird beim Schreiben
erneut geprüft, nicht nur davor.

1. Aktivieren Sie in KeePassXC *Settings > Browser Integration*.
2. Verknüpfen Sie diesen Rechner einmal je Datenbank und bestätigen Sie es in
   KeePassXC:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Legen Sie den Eintrag an und **füllen Sie sein URL-Feld** mit
   `https://fido.invalid/yubikey-5c` (jede URL, die kein anderer Eintrag
   nutzt: die Referenz ist diese URL). Prüfen Sie die Referenz, ohne das
   Geheimnis auszugeben:
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

Beim ersten Lesen eines Eintrags zeigt KeePassXC seinen Zugriffsdialog.

Verwendet von `fido --pin-from` (siehe [fido]({{< relref "/libraries/fido.md" >}}))
und von `theca --pin-from`, `--password-from` und `--recovery-from`.

## Ein Geheimnis aus einem Kommandozeilen-Flag übernehmen: `secretsource/secretflag` {#secretflag}

Ein Geheimnis, das als Flag-Wert übergeben wird, ist in `ps` sichtbar. Das
Paket `secretflag` gibt einem Befehl das Paar `--<name>` (veraltet, warnt auf
stderr) und `--<name>-from <ref>`, sich gegenseitig ausschließend, wobei die
Referenz von `secretsource.Open` aufgelöst wird:

```go
var password string
b := secretflag.Add(cmd, "password", &password, "the admin password") // cobra
// or: secretflag.AddStd(fs, os.Stderr, "password", &password, "the admin password", "p")
// ... after parsing:
if err := secretflag.Resolve(ctx, b); err != nil { return err }
```

`Add` registriert das Paar an einem cobra-Befehl, `AddStd` an einem
`flag.FlagSet` der Standardbibliothek (mit Aliasen wie `-t`); `Resolve` liest
die Referenzen. Verfügbar seit v0.10.0.

## Ein Geheimnis speichern: `secretsource store` {#store}

Kein Eintrag muss von Hand angelegt werden. `secretsource store REF [--group G]
[--login L] [--replace] [--generate N]` schreibt das Geheimnis für `keychain:`,
`secretservice:SERVICE/ACCOUNT`, `secretservice:KEY=VALUE` und `keepassxc:URL`:

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

Das Geheimnis wird zweimal ohne Echo eingegeben oder von der Standardeingabe
gelesen, wenn diese kein Terminal ist; es wird nie aus einem Argument oder der
Umgebung genommen. `--generate N` zieht N Buchstaben und Ziffern und gibt nichts
Geheimes aus. Ein vorhandener Eintrag wird abgelehnt, außer mit `--replace` (bei
KeePassXC aktualisiert das genau diesen, über seine URL gefundenen Eintrag).
`file:` wird abgelehnt.

Für `keepassxc:` nutzt es das `set-login` des Browser-Protokolls: der Eintrag
trägt immer die URL, über die er wiedergefunden wird, und ein Duplikat wird über
die URL gesucht. Der Login ist standardmäßig der Host der URL (`--login`), die
Gruppe ist `KeePassXC-Browser Passwords`, sofern `--group` nicht eine unterhalb
der Wurzel nennt, und `--title` wird abgelehnt, weil KeePassXC 2.8.0 es
ignoriert. KeePassXC zeigt seine eigenen Dialoge.

## Referenz {#reference}

Die README von
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) ist
für diese Seite maßgeblich.
