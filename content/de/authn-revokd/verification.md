---
title: "Wie eine Liste geprüft wird"
linkTitle: "Prüfung"
weight: 30
description: "Was authn-revokd prüft, bevor es eine Liste behält: die Signatur, die Daten und dass sie nie älter ist als die Liste, die es hält, auch über Neustarts hinweg."
tags: [authn-revokd, widerruf, sicherheit]
---

Eine Liste, die die Prüfung nicht besteht, wird nie geschrieben, bereitgestellt oder verwendet. Die letzte gute
Kopie bleibt. Ein Abruf, der fehlschlägt, aus welchem Grund auch immer, ersetzt sie nie durch eine leere
Antwort, die nichts widerrufen würde.

## Die Signatur {#the-signature}

**Eine KRL** wird mit ihrer Signatur abgerufen, `<url>.sig`: eine ASCII-armierte SSHSIG über
die ganze Datei, mit dem als `ssh_ca` konfigurierten **SSH-CA-Schlüssel**, im Namensraum
`krl@go-authn.github.io`. Der Namensraum verhindert, dass die Signatur für etwas anderes
gehalten wird. Wer signiert, hasht mit SHA-512; SHA-256 wird ebenfalls akzeptiert. Eine RSA-Signatur
in der SHA-1-Form, die PROTOCOL.sshsig verbietet, wird abgelehnt.

Die KRL selbst muss sich so parsen lassen, wie `sshd` sie parst, und darf nicht den eigenen
Signaturabschnitt von OpenSSH enthalten, den OpenSSH nie prüft.

Eine von einem anderen Schlüssel signierte Liste wird abgelehnt:

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:6iM7YPhdfXxQEj/PUf7CYbqBuSiVTVMx2VADj63cAg4: public key does not match
bridge-x509: version 1793014030593, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
output sshd: wrote /tmp/authn/revokd/out/other.krl
output tls: wrote /tmp/authn/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

Hier nannte `ssh_ca` einen Schlüssel, der die Liste der Bridge nicht signiert hat, und die Fehlermeldung nennt
diesen Schlüssel. Eine Signatur, die die Prüfung nicht besteht, kann auch von einer Liste stammen, die
zwischen den beiden Anfragen neu ausgestellt wurde; daher werden beide noch einmal abgerufen, bevor sie gemeldet wird.
Dies war der erste Abruf dieser Quelle, es gab also keine gute Kopie zu behalten, und
die Ausgabe ist sofort die [geschlossen fehlschlagende Liste (fail closed)]({{< relref "/authn-revokd/lapse.md" >}}).
(Vor v0.6.2 stand bei demselben Fehler „the list changed between it and its
signature“ vor der obigen Meldung, als sei die Liste erneut ausgestellt worden.)

Die Signatur wird mit `If-Match: <the list's ETag>` abgerufen. Eine zwischen den beiden Anfragen
neu ausgestellte Liste antwortet `412`, und beide werden erneut abgerufen.

**Eine CRL** wird gegen das als `x509_ca` konfigurierte CA-Zertifikat geprüft: zuerst ihre
Signatur, auf den Rohbytes, **bevor** der Rest geparst wird, sodass eine große,
von irgendjemandem signierte CRL eine Signaturprüfung kostet statt eines Parsens. Dann muss ihr
Aussteller das Subject dieses Zertifikats sein; sie muss eine CRL Number und ein
`nextUpdate` nach ihrem `thisUpdate` haben; und sie darf keine Delta-CRL sein, keine
kritische Erweiterung außer der CRL Number und dem Authority Key Identifier tragen
und keine kritische Eintragserweiterung.

Eine KRL muss außerdem **angeben, wann sie abläuft**, in der Erweiterung
`expires@go-authn.github.io`: Eine, die das nicht tut, ließe sich nie von einer veralteten unterscheiden.

Die Größe ist begrenzt: eine KRL auf 32 MiB, ihre Signatur auf 64 KiB, eine CRL auf 64 MiB.

## Die Daten {#the-dates}

Eine Liste ist aktuell, wenn:

- jetzt vor ihrem Ablauf liegt (die Erweiterung der KRL, das `nextUpdate` der CRL);
- sie nicht mehr als fünf Minuten in der Zukunft ausgestellt wurde: Ein Aussteller, dessen Uhr
  um mehr als das vorgeht, schreibt Listen, deren Alter sich nicht feststellen lässt;
- sie mit `max_age` vor nicht längerer Zeit als dieser ausgestellt wurde.

Eine Liste, die nicht aktuell ist, wird beim Abruf abgelehnt. Ein `304 Not Modified` ist keine
Neuigkeit: Die gehaltene Kopie kann inzwischen abgelaufen sein, und sie wird bei jeder
Synchronisierung erneut beurteilt.

## Nie älter als die gehaltene Liste {#never-older-than-the-list-held}

Die Position einer Liste ist ihre **Version** (die `krl_version` der KRL, die CRL
Number), dann ihre **Ausstellungszeit** (das Erstellungsdatum der KRL, das `thisUpdate`
der CRL). Eine Liste darf die gehaltene nur ersetzen, wenn sie eine höhere
Version hat oder dieselbe Version später ausgestellt wurde: dieselben Widerrufe, neu ausgestellt
mit einem neuen Ablauf. Alles andere ist ein Rollback: eine wieder eingespielte oder wiederhergestellte ältere
Liste, noch signiert und nicht abgelaufen, die zurücknehmen würde, was die neuere
widerrufen hat.

### Auch über Neustarts hinweg {#across-restarts-too}

Die gehaltene Liste wird in `state_dir` aufbewahrt, eine Datei pro Quelle, die die Liste und
ihre Signatur zusammen enthält, geschrieben durch eine einzige Umbenennung mit synchronisiertem Verzeichnis.
Beim Start wird jede Kopie **erneut geprüft** (abgelaufen oder nicht, sie ordnet, was als
Nächstes kommt), und einer Kopie, die die Prüfung nicht mehr besteht, wird nicht vertraut, nicht einmal, um die
nächste zu ordnen, und das Log sagt es.

Hier wird eine Quelle nach einem Neustart auf eine Liste gerichtet, die ein früherer Bridge-Prozess
neunzehn Sekunden zuvor bereitgestellt hat, noch signiert und noch nicht abgelaufen:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
bridge-x509: version 1793014030593, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/authn/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-26T11:26:49Z, the copy held at 2026-10-26T11:27:10Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-26T12:27:10Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261026T122710
# Comment: authn-revokd sshd
```

Der erste Lauf hat keine Ausgabe geschrieben: Die Dateien enthielten diese Listen bereits.
Die ältere Liste wird abgelehnt, und die Ausgabe behält die neuere. Der Prozess, der
sie abgelehnt hat, hatte die neuere Liste nie gesehen: Er hat sie aus `state_dir` zurückgelesen.

Da der Zustand das ist, was einen Rollback erkennbar macht, unterliegt das Verzeichnis der
StrictModes-Regel von sshd ([die Konfiguration]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}})).
Ein Absturz zwischen zwei Schreibvorgängen kann kein Paar hinterlassen, das die Prüfung nicht besteht, was
den Rollback-Schutz mitnehmen würde: Die Liste und ihre Signatur sind eine Datei.

## Was `-once` meldet {#what--once-reports}

`-once` endet mit `1`, wenn eine Quelle keine aktuelle Liste hat, wenn ihr **letzter Abruf
fehlgeschlagen ist** oder wenn eine Ausgabe nicht geschrieben werden konnte, und seine letzte Zeile sagt, welcher
der ersten beiden Fälle es ist:

| letzte Zeile | die Quelle | ihre Ausgaben |
|---|---|---|
| `not current: <source>` | hält keine aktuelle Liste: nie abgerufen, abgelaufen oder über `max_age` hinaus | für sshd fail-closed |
| `not fetched: <source> (the list held is current until <T>)` | ihr Abruf ist fehlgeschlagen, aber die gehaltene Kopie ist noch aktuell | aus dieser Kopie geschrieben, unverändert, bis `T` |

Hier ist der Aussteller gestoppt, während beide gehaltenen Listen noch aktuell sind:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-26T12:27:10Z), bridge-x509 (the list held is current until 2026-10-26T12:27:10Z)
```

Dieser Durchlauf ließ `sshd.krl`, wie es war. Sobald eine gehaltene Liste verfällt, wird dieselbe Quelle
als `not current` gemeldet, und beide Arten können sich die Zeile teilen, wie unter
[Wenn eine Liste verfällt]({{< relref "/authn-revokd/lapse.md" >}}). Vor v0.6.2
wurden beide Fälle als `not current` gemeldet, was besagte, eine Liste sei verfallen, obwohl nur
ihr Abruf fehlgeschlagen war; der Exit-Status war auch damals `1`.

Das `/healthz` des Spiegels urteilt stattdessen nach der gehaltenen Kopie und antwortete `ok`, während
der Aussteller ausgefallen war und die Kopien noch aktuell waren.
