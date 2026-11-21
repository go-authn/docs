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
go get github.com/go-authn/secretsource@v0.6.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Referenz | Liest |
|---|---|
| `file:PATH` | eine reguläre Datei, nur für den Besitzer lesbar (Modus 0600 oder strenger); ein abschließender Zeilenumbruch wird entfernt; eine Datei, die leer ist oder nur einen Zeilenumbruch enthält, wird mit `ErrEmpty` abgelehnt (seit v0.6.0), und eine FIFO wird als keine reguläre Datei abgelehnt |
| `keychain:SERVICE/ACCOUNT` | ein generisches Passwort-Objekt im macOS-Schlüsselbund |
| `secretservice:SERVICE/ACCOUNT` | ein freedesktop-Secret-Service-Objekt mit den Attributen `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, Secret-Service-Integration von KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | das eine Secret-Service-Objekt mit all diesen Attributen; mehrere Treffer werden abgelehnt |
| `keepassxc:URL` | der KeePassXC-Eintrag, dessen **URL-Feld** diese URL ist (`https://NAME.invalid/...` ist eine gute Wahl, die sich nie auflöst); zwei Einträge mit derselben URL werden als mehrdeutig abgelehnt |

`keepassxc:by-uuid/...` und `keepassxc:by-path/...` werden **abgelehnt**:
KeePassXC 2.8.0 stürzt ab, wenn eine Suche einen Eintrag ohne URL findet.

**Kein Schema führt einen Befehl aus**: eine Option darf nie einen Prozess
starten können. Eine Referenz ohne Schema wird abgelehnt, nicht als Pfad erraten
(`file:` ist die Schreibweise eines Pfads). Ein Geheimnis über 4096 Bytes oder
ein leeres von einem Manager oder einer `file:`-Referenz wird abgelehnt (`ErrEmpty`), und ein Aufruf endet mit seinem
Kontext (2 Minuten ohne Frist), auch wenn der Manager darauf wartet, dass Sie
ihn entsperren.

## KeePassXC {#keepassxc}

KeePassXC wird über sein Browser-Integrationsprotokoll erreicht, unter macOS und
Linux; Windows ist noch nicht umgesetzt. Seit v0.6.0 wird unter Unix der Socket
abgelehnt, wenn er ein symbolischer Link ist oder sein Verzeichnis einem anderen
Benutzer gehört oder für Gruppe oder andere beschreibbar ist, und die uid des
verbundenen Peers wird nach dem Dial geprüft; dem alten Symlink
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` wird nicht mehr gefolgt
(dem echten Socket unter `app/org.keepassxc.KeePassXC/` schon).

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
