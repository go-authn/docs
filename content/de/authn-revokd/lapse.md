---
title: "Wenn eine Liste verfällt"
linkTitle: "Wenn eine Liste verfällt"
weight: 40
description: "Was authn-revokd für sshd schreibt, wenn es keine aktuelle Liste einer CA hält: eine KRL, die den CA-Schlüssel selbst widerruft, sodass jedes Zertifikat dieser CA abgelehnt wird."
tags: [authn-revokd, widerruf, fail closed, sshd]
---

Eine Widerrufsprüfung, die alles durchlässt, wenn die Liste nicht zu bekommen ist, ist
genau die, die ein Angreifer aushebelt, der die Liste blockieren kann. Wenn authn-revokd also
keine aktuelle Liste einer Quelle hält, wird das, was die Liste dieser Quelle schützt,
**abgelehnt**, bis wieder eine aktuelle Liste eintrifft.

| Ausgabe | solange eine Quelle keine aktuelle Liste hat |
|---|---|
| eine KRL, für `sshd` | authn-revokd schreibt eine KRL, die **den CA-Schlüssel der Quelle widerruft** |
| eine CRL, für einen TLS-Server | die abgelaufene CRL bleibt an ihrem Platz; OpenSSL lehnt eine abgelaufene CRL von sich aus ab |

## Für sshd: die CA selbst widerrufen {#for-sshd-revoking-the-ca-itself}

`sshd` kennt keinen Ablauf einer Liste: Es würde die zuletzt geschriebene Datei für immer
weiterlesen. Es prüft aber den **CA-Schlüssel** jedes Zertifikats gegen
`RevokedKeys`. Anstelle der Liste, für die es nicht bürgen kann, setzt authn-revokd daher
den eigenen Schlüssel der CA in die Ausgabe, und jedes Zertifikat, das diese CA signiert hat, wird
abgelehnt, und nichts sonst.

Hier ist der Aussteller gestoppt, und die KRL-Quelle hat `max_age = "30s"`, sodass die
gehaltene Kopie innerhalb einer Minute statt einer Stunde verfällt. Die CRL-Quelle hat kein
`max_age`, und ihre Kopie ist noch aktuell:

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-11T10:50:24Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh` ist `not current`, und seine Ausgabe schlägt geschlossen fehl (fail closed); `bridge-x509`
ist nur `not fetched`, und seine CRL bleibt, wie sie war
([was `-once` meldet]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
`SHA256:Fpa/...` ist die SSH-CA der Bridge. Ein Zertifikat, das sie signiert hat, ist nun
für alles, was die Datei liest, widerrufen. Die Befehle oben liefen im Verzeichnis `revokd`,
in dem `out/` liegt; dieser läuft daneben, im Verzeichnis mit den Testzertifikaten, wie auf
[der Seite von sshcert-authorize]({{< relref "/sshcert/authorize.md#krl" >}}), daher ist
dieselbe Datei `../revokd/out/sshd.krl`:

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

Der Kommentar sagt `FAIL CLOSED` und nennt die Quelle, sodass eine Person, die
`ssh-keygen -Q -l` liest, sieht, warum. Das Datum der Datei ist 1970, wenn jede Quelle
verfallen ist. Die Ausgabe wird geschrieben, **sobald eine Synchronisierung es bemerkt**, was für den Daemon
sein nächster `refresh` ist und für den Timer sein nächster Takt. Wenn wieder eine aktuelle Liste
eintrifft, schreibt die nächste Synchronisierung sie anstelle des CA-Schlüssels, und die Zertifikate der CA
werden wieder angenommen.

Dasselbe geschieht **vor der ersten Liste**: Eine nie abgerufene Quelle hat nichts
Aktuelles, und ihre CA ist ab dem ersten Schreiben widerrufen. Eine neue Installation lehnt
die Zertifikate der CA ab, bis ihre erste Liste die Prüfung besteht, statt sie
ungeprüft anzunehmen.

### Jede CA für sich {#each-ca-for-itself}

In einer Ausgabe, die mehrere Quellen zusammenführt, wird nur die CA der verfallenen Quelle
widerrufen. Die anderen behalten ihre Listen. Eine Liste, die sich nicht zusammenführen lässt (jenseits der
Seriennummernbereiche, die go-authn/krl behält), schlägt nur für ihre eigene CA geschlossen fehl, und
`/healthz` nennt sie. Nur wenn sich die Listen einzeln, aber nicht gemeinsam zusammenführen lassen, wird jede CA
der Ausgabe widerrufen, und der Kommentar sagt es
(`FAIL CLOSED, the output could not be rendered`). Stattdessen die alte Datei zu behalten,
würde einen späteren Verfall unbemerkt lassen.

## Für einen TLS-Server: die CRL selbst {#for-a-tls-server-the-crl-itself}

Eine CRL sagt bereits, wann sie aufhört, aktuell zu sein, und OpenSSL lehnt eine ab, die
ihr `nextUpdate` überschritten hat („CRL has expired“). authn-revokd lässt daher die letzte geprüfte
CRL an ihrem Platz, und der TLS-Server schlägt von sich aus geschlossen fehl. Deshalb wird auch
`max_age` bei einer Quelle abgelehnt, die eine CRL-Ausgabe speist: Ein Server, der
die CRL geladen hat, behält sie bis zu ihrem `nextUpdate`, was auch immer authn-revokd schreibt.

## Leser, die den Ablauf selbst prüfen {#readers-that-check-the-expiry-themselves}

Die zusammengeführte KRL trägt einen Ablauf, den ersten ihrer aktuellen Eingaben. Ein Leser,
der ihn prüft, etwa `ssh_krl_file` von go-fileshare oder
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}}),
sieht authn-revokd anhalten, wie er den Aussteller anhalten sähe.

{{< callout type="warning" >}}
**Das funktioniert nur, solange authn-revokd läuft**

Dass die Datei geschlossen fehlschlägt, besorgt authn-revokd. Solange es gestoppt ist, liest sshd
weiter die zuletzt geschriebene Datei, aktuell oder nicht. Daher `Restart=always` beim
Daemon und die Überwachung der Unit, des Timers oder von `/healthz`.
{{< /callout >}}
