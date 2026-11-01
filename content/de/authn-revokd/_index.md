---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "Ein Agent, der signierte KRLs und CRLs abruft, nur die Listen behält, die die Prüfung bestehen, sie dorthin schreibt, wo sshd und TLS-Server sie lesen, und geschlossen fehlschlägt, wenn eine verfällt."
tags: [authn-revokd, widerruf, krl, crl]
---

**OpenSSH hat keine Möglichkeit, eine KRL zu verteilen, und nichts in einer KRL sagt, dass sie
veraltet ist.** `sshd` liest eine Datei, die seit Monaten nicht mehr aktualisiert wurde, als die
aktuelle Liste. authn-revokd schließt beide Lücken für die Listen, die
[authn-bridge]({{< relref "/authn-bridge/revocation.md" >}}) veröffentlicht: Es
ruft jede Liste ab, behält sie nur, wenn sie die Prüfung besteht, schreibt sie dorthin, wo `sshd` oder ein
TLS-Server sie liest, und schreibt, wenn eine Liste verfällt, eine, die **die CA selbst
widerruft**. Reines Go, `CGO_ENABLED=0`, ein Binary. Diese Seiten beschreiben v0.6.7.

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.6
go: github.com/go-authn/revocation@v0.6.6 requires go >= 1.27.3; switching to go1.27.3
$ authn-revokd -version
authn-revokd v0.6.6
$ authn-revokd -help
Usage of authn-revokd:
  -config string
    	the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -once
    	sync once and exit: 1 when a list is not current, or could not be fetched
  -version
    	print the version and exit
```

`-help` endet mit 0; vor v0.6.2 endete es mit 2.

Vor v0.6.0 hieß der Befehl `revokd` und las standardmäßig `/etc/revokd.hcl`.
Nichts liest diese Datei mehr; wenn sie vorhanden ist und der neue Standard nicht,
nennt die Fehlermeldung beide Pfade.

## Was es tut, in einem Durchlauf {#what-it-does-in-one-run}

Gegen eine Test-authn-bridge auf Loopback, mit einer KRL-Quelle und einer CRL-Quelle:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
bridge-x509: version 1793014030593, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261026T122710
# Comment: authn-revokd sshd
```

Ein zweiter Durchlauf ohne Neues gibt nichts aus und endet mit 0: Eine Ausgabe wird
nur neu geschrieben, wenn sich ihr Inhalt ändert.

## Warum der Transport keine Rolle spielt {#why-the-transport-does-not-matter}

Jede Liste authentifiziert sich selbst: eine KRL durch eine abgetrennte SSHSIG-Signatur mit dem
eigenen Schlüssel der CA, eine CRL durch die Signatur ihrer CA. Jede Liste sagt, wann sie aufhört,
aktuell zu sein. Eine Liste darf also über HTTPS kommen, über einfaches HTTP innerhalb eines Clusters, über einen Spiegel
oder aus einer Datei. Der Transport entscheidet, wie schnell eine Änderung ankommt, nie, ob eine
gefälschte oder veraltete Liste übernommen wird.

| | KRL | CRL |
|---|---|---|
| authentisch | SSHSIG mit dem Schlüssel der SSH-CA, Namensraum `krl@go-authn.github.io` | von ihrer CA signiert |
| aktuell | `expires@go-authn.github.io`, das sshd ignoriert | `nextUpdate` |
| nie rückwärts | `krl_version`, dann Erstellungsdatum | CRL Number, dann `thisUpdate` |
| geschlossen fehlschlagen | authn-revokd schreibt eine KRL, die den CA-Schlüssel widerruft | OpenSSL lehnt eine abgelaufene CRL von sich aus ab |

## Wie es weitergeht {#where-to-go-next}

| | |
|---|---|
| [Die Installation]({{< relref "/authn-revokd/install.md" >}}) | der Daemon oder `-once` mit einem Timer; sshd und nginx anbinden |
| [Die Konfiguration]({{< relref "/authn-revokd/configuration.md" >}}) | Quellen, Ausgaben, der Spiegel und was abgelehnt wird |
| [Wie eine Liste geprüft wird]({{< relref "/authn-revokd/verification.md" >}}) | Signatur, Daten und nie älter als die gehaltene Liste, auch über Neustarts hinweg |
| [Wenn eine Liste verfällt]({{< relref "/authn-revokd/lapse.md" >}}) | die KRL, die die CA selbst widerruft |

## Was es nicht tut {#what-it-does-not-do}

Ein Widerruf erreicht einen Server nicht schneller, als authn-revokd abfragt (`refresh`),
zuzüglich der Verzögerung, mit der der Aussteller neu ausstellt. Solange der Aussteller ausgefallen ist, werden seine
Zertifikate ab dem Ablauf der Liste abgelehnt. Wer den Schlüssel einer CA hält, kann
jede Liste signieren, so wie jedes Zertifikat.

## Lizenz {#licence}

BSD-3-Clause.
