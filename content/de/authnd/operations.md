---
title: "Betrieb: Signale, Neustarts und was es ausgibt"
linkTitle: "Betrieb"
weight: 80
description: "Was authnd einmal liest, warum SIGHUP es nicht neu lädt, wie es anhält, was es in seine Ausgabe schreibt und wie man erkennt, dass es läuft."
tags: [authnd, betrieb, signale, systemd]
---

## Es liest alles einmal {#it-reads-everything-once}

Die Konfigurationsdateien, jede Quelle dahinter, das TLS-Zertifikat und
die Keytab werden **beim Start** gelesen. Es gibt kein Neuladen, und die mitgelieferte Unit
hat kein `ExecReload=`. Nach einer Änderung an einem davon:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

Das Einzige, was im laufenden Betrieb angewendet wird, ist ein
[Passwort, das eine Person über authnd ändert]({{< relref "/authnd/passwords.md" >}});
es liest die `user`-Blöcke erneut und sonst nichts.

Dazu gehören die **Gruppen**. Eine Suche fragt keine Datenbank etwas: Eine
Änderung an einer Gruppe in einer Datenbank wird durch einen Neustart
übernommen, und eine Datenbank, die ausfällt, während authnd läuft, ändert
keine Antwort. (Vor v0.13.4 fragte jede Suche die Gruppen erneut ab — 4,13 s
pro Suche bei 200 Gruppen mit SQLite —, und eine fehlgeschlagene Abfrage ließ
die Gruppe aus einer Antwort fallen, die dennoch Success meldete.) Eine Quelle,
die beim Start nicht gelesen werden kann, etwa eine Gruppenabfrage, die nicht
läuft, oder eine von mehreren ausgefallenen Datenbanken, verweigert den Start
und `check` und nennt die Quelle und die Gruppe. Ein Eintrag, der für eine
LDAP-Nachricht zu groß ist (etwa 3 MiB, was ein einziger 10-MB-Attributwert
erreicht), wird nicht veröffentlicht; das wird beim Start und von `check`
gemeldet, wie bei einem Eintrag, der das Schema verletzt.

## Signale {#signals}

| Signal | was geschieht |
|---|---|
| `SIGTERM`, `SIGINT` | es gibt `stopping` aus, schließt die Listener **und jede bestehende Verbindung**, hält den Realm an, schließt die Quellen und beendet sich mit 0, sobald der Server wirklich fertig ist |
| `SIGHUP` | es wird abgefangen und protokolliert, und authnd **bleibt in Betrieb**, ohne etwas neu zu laden |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
hangup: authnd does not reload; restart it to apply a changed configuration, certificate or keytab
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

Das ist ein einziger Lauf: ein `kill -HUP`, zwei Versuche, ein Passwort zu ändern (der erste
abgelehnt, der zweite angenommen), dann ein `kill -TERM`.
Der Prozess war nach dem `SIGHUP` noch da.

Ein `SIGHUP` hat authnd früher **beendet** – Gos Standardverhalten für ein Signal, das
niemand behandelt –, und systemd wertet einen Tod durch `SIGHUP` als sauberes Beenden, sodass
`Restart=on-failure` es nicht wieder startete: Ein einziges `kill -HUP` oder ein einziges
logrotate-`postrotate` legte ein Verzeichnis dauerhaft lahm. Jetzt wird es abgefangen, damit die
Gewohnheit harmlos ist, und die Logzeile sagt, was stattdessen zu tun ist.

Dass auch bestehende Verbindungen geschlossen werden, nicht nur der Listener, ist Absicht: Ein
Server, der keine Verbindungen mehr annimmt, seine offenen aber weiter beantwortet, sähe
angehalten aus, ohne es zu sein – genau der Neustart, der nicht greift.

## Was es schreibt {#what-it-writes}

Alles geht auf die Standardausgabe, die unter systemd das Journal ist
(`journalctl -u authnd`):

- beim Start, wo es lauscht und wen es bedient – `ldap on …`, `ldaps on …`
  oder `ldap+starttls on …`, dann `realm EXAMPLE.ORG on … (udp and tcp)` bei einem
  `kerberos`-Block;
- jeder abgelehnte Bind unter einem `mfa`-Block, jedes abgelehnte Token, jede
  abgelehnte oder abgeschlossene Passwortänderung, **mit dem Grund** – den der
  Client nie erfährt; siehe [den zweiten Faktor]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})
  und [Tokens]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}});
- jede Anfrage, die das KDC ablehnt, mit dem Präfix `kerberos:` und dem Kerberos-Fehlercode;
  siehe [den Realm]({{< relref "/authnd/kerberos.md#kinit-against-it" >}});
- das eigene Log der LDAP-Bibliothek, im `slog`-Textformat, auf Stufe info.

Ein schlicht falsches Passwort bei einem einfachen Bind, ohne `mfa`-Block, wird mit
`invalidCredentials` beantwortet und von authnd selbst nicht protokolliert.

## Wenn es nicht startet {#when-it-does-not-start}

Eine Ablehnung ist eine Zeile auf der Standardfehlerausgabe, mit dem Präfix `authnd:`, und
Exit-Status 1; unter der Unit versucht es `Restart=on-failure` dann alle fünf
Sekunden erneut, und die Zeile steht jedes Mal im Journal. Alles, was `check` ablehnt,
wird auch hier abgelehnt, und das Einzige, was nur der Server findet, ist eine Adresse,
auf der er nicht lauschen kann – siehe
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
Der LDAP-Listener, das Zertifikat und der Realm werden alle geöffnet, bevor die
erste Zeile ausgegeben wird; ein Server, der nicht starten kann, gibt daher nur die
Ablehnung aus. Hier trifft eine zweite Instanz auf den Kerberos-Port der ersten:

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

Die Zeile `ldap on …` und danach `realm … on …` bedeuten, dass beide Hälften
lauschen.

## Erkennen, dass es läuft {#telling-that-it-is-up}

Es gibt keinen Health-Endpunkt und keine Metriken. Was es gibt:

- **den Prozess und seinen Exit-Status** – unter systemd `systemctl is-active
  authnd`. Hält der LDAP-Listener oder der Realm von selbst an, endet der
  ganze Prozess mit diesem Fehler; ein lebender Prozess ist also einer, dessen beide
  Hälften antworten;
- **das Root-DSE**, das einem anonymen Client antwortet und sagt, mit welcher Version
  er spricht:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.13.0
```

Auf einem [StartTLS-Listener]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}})
braucht diese Abfrage `-ZZ`. Eine Probe, die mehr beweist – dass eine Quelle noch
antwortet –, ist ein Bind als eine Person oder als ein eigens dafür vorgehaltenes Lesekonto; mit einem
`users "ldap"`-Block erreicht dieser Bind das Verzeichnis hinter diesem.

## Was wo liegt und was ein Neustart verliert {#what-lives-where-and-what-a-restart-loses}

| | |
|---|---|
| Konfiguration, Passwörter, DSN, Zertifikat, Keytab | die Dateien, die die Konfiguration nennt; nichts wird kopiert |
| eine SQLite-Datenbank | wo ihr DSN es sagt; `/var/lib/authnd` unter der Unit |
| Zähler und Sperren des zweiten Faktors | nur im Speicher: **ein Neustart vergisst sie**, auch eine Person, die nach hundert falschen Codes gesperrt wurde |
| verwendete Einmalcodes | nur im Speicher |
