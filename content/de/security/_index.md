---
title: "Sicherheit"
linkTitle: "Sicherheit"
weight: 55
description: "Was die Programme ablehnen, wie ein Widerruf vom Anbieter zu jedem Server gelangt und wie sich ein echtes Binary von allem anderen unterscheiden lässt."
tags: [security]
---

go-authn soll Personen belegen, daher sind seine Ablehnungen das Design und nicht die
Ausnahmen. Dieser Abschnitt sammelt diejenigen, die Programmgrenzen überschreiten; die
eigenen Seiten jedes Programms sagen, was es für sich allein ablehnt.

## Die wichtigsten Ablehnungen {#the-refusals-that-matter-most}

| | was abgelehnt wird | warum |
|---|---|---|
| authnd | eine Suche durch jemand anderen als einen deklarierten `reader` | ein Bind belegt, wer jemand ist; er ist keine Erlaubnis, alle aufzulisten |
| authnd | ein Kerberos-Ticket für eine Person, deren Quelle kein Passwort hält | ein KDC braucht einen aus dem Passwort abgeleiteten Schlüssel; ein NT-Hash oder eine Passwortprüfung kann keinen erzeugen ([warum]({{< relref "/authnd/kerberos.md" >}})) |
| authnd | ein `kerberos`-Block neben einem `mfa`-Block | ein kinit trägt das Passwort und sonst nichts, also würde der Realm Personen, die laut `mfa`-Block zwei Faktoren brauchen, Tickets auf einen Faktor ausstellen |
| authn-bridge | eine Assertion, die niemand signiert hat, ein Bezeichner außerhalb des eigenen Bereichs der Einrichtung | jedem Mitglied einer Föderation wird geglaubt, also muss jedes auf seine eigenen Personen beschränkt sein: sonst könnte jede Einrichtung jeden benennen |
| authn-revokd | eine Liste, die unsigniert, abgelaufen oder älter als die gehaltene ist | ein Spiegel dazwischen darf eine Liste verzögern, sie aber nie fälschen oder zurücksetzen |
| authn-revokd | einer verfallenen Liste zu vertrauen | es schreibt eine, die die CA selbst widerruft, sodass sshd ablehnt, statt einer veralteten Liste zu vertrauen |
| sshcert-authorize | ein Zertifikat, dessen Domain-Grant diesen Host nicht nennt | ein Zertifikat von der CA einer Föderation ist für sich allein keine Erlaubnis für jeden Host, der dieser CA vertraut |

## Ein Widerruf, von Anfang bis Ende {#a-revocation-end-to-end}

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) signiert und datiert eine
   KRL (für SSH-Zertifikate) und eine CRL (für X.509-Client-Zertifikate) und
   veröffentlicht sie.
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) ruft jede Liste ab,
   prüft ihre Signatur und ihre Daten, lehnt eine ab, die älter ist als die gehaltene
   (auch über einen Neustart hinweg), und schreibt sie erst dann dorthin, wo der Server sie liest.
3. sshd (`RevokedKeys`), go-fileshare und alles andere lesen eine Datei, die bereits
   geprüft wurde.

Ein CAEP-`session-revoked`-Ereignis über den Shared-Signals-Sender des Anbieters macht
ungültig, was keine Liste benennen kann: alles, was einer Person vor einem bestimmten
Zeitpunkt ausgestellt wurde. Die Dokumentation von go-fileshare beschreibt die
empfangende Seite:
[Sperrlisten](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
[Shared Signals](https://go-fileshare.github.io/docs/latest/security/shared-signals/).

## Releases {#releases}

Jedes Binary wird vom Release-Workflow aus einem getaggten Commit gebaut und kann auf
drei Arten geprüft werden: [einen Download prüfen]({{< relref "/security/verifying-releases.md" >}}).
