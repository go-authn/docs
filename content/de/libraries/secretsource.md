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
go get github.com/go-authn/secretsource@v0.2.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:by-path/Keys/Yubikey PIN")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Referenz | Liest |
|---|---|
| `file:PATH` | eine reguläre Datei, nur für den Besitzer lesbar (Modus 0600 oder strenger); ein abschließender Zeilenumbruch wird entfernt |
| `keychain:SERVICE/ACCOUNT` | ein generisches Passwort-Objekt im macOS-Schlüsselbund |
| `secretservice:SERVICE/ACCOUNT` | ein freedesktop-Secret-Service-Objekt mit den Attributen `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, Secret-Service-Integration von KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | das eine Secret-Service-Objekt mit all diesen Attributen; mehrere Treffer werden abgelehnt |
| `keepassxc:by-uuid/HEX` | der KeePassXC-Eintrag mit dieser UUID (32 Hexziffern) |
| `keepassxc:by-path/Group/Title` | der Eintrag unter diesem Pfad (der Name der Wurzelgruppe entfällt); ein Titel, den zwei Gruppen teilen, wird als mehrdeutig abgelehnt, nehmen Sie `by-uuid/` |
| `keepassxc:URL` | der Eintrag, dessen URL-Feld passt |

**Kein Schema führt einen Befehl aus**: eine Option darf nie einen Prozess
starten können. Eine Referenz ohne Schema wird abgelehnt, nicht als Pfad erraten
(`file:` ist die Schreibweise eines Pfads). Ein Geheimnis über 4096 Bytes oder
ein leeres von einem Manager wird abgelehnt, und ein Aufruf endet mit seinem
Kontext (2 Minuten ohne Frist), auch wenn der Manager darauf wartet, dass Sie
ihn entsperren.

## KeePassXC {#keepassxc}

KeePassXC wird über sein Browser-Integrationsprotokoll erreicht, unter macOS und
Linux; Windows ist noch nicht umgesetzt.

1. Aktivieren Sie in KeePassXC *Settings > Browser Integration*.
2. Verknüpfen Sie diesen Rechner einmal je Datenbank und bestätigen Sie es in
   KeePassXC:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Prüfen Sie eine Referenz, ohne das Geheimnis auszugeben:
   ```sh
   secretsource check 'keepassxc:by-path/Yubikey PIN'
   ```

Beim ersten Lesen eines Eintrags zeigt KeePassXC seinen Zugriffsdialog.

Verwendet von `fido --pin-from` (siehe [fido]({{< relref "/libraries/fido.md" >}}))
und von `theca --pin-from`, `--password-from` und `--recovery-from`.

## Referenz {#reference}

Die README von
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) ist
für diese Seite maßgeblich.
