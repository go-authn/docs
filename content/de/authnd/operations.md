---
title: "Betrieb: Signale, Neustarts und was es ausgibt"
linkTitle: "Betrieb"
weight: 80
description: "Was authnd einmal liest, warum SIGHUP es nicht neu lädt, wie es anhält, was es in seine Ausgabe schreibt und wie man erkennt, dass es läuft."
tags: [authnd, betrieb, signale, systemd]
---

## Es liest alles einmal {#it-reads-everything-once}

Die Konfigurationsdateien und die Keytab werden **beim Start** gelesen. Es gibt
kein Neuladen dieser Dateien, und die mitgelieferte Unit hat kein `ExecReload=`.
Nach einer Änderung an einer davon:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

Das TLS-Zertifikat ist seit v0.15.0 die Ausnahme: authnd sieht `cert_file` und
`key_file` erneut an, sodass eine Erneuerung keinen Neustart braucht. Siehe
[das Zertifikat erneuern]({{< relref "/authnd/tls.md#renewal" >}}).

Abgesehen von den Quellen (siehe unten) wird im laufenden Betrieb nur ein
[Passwort, das eine Person über authnd ändert]({{< relref "/authnd/passwords.md" >}}) angewendet;
es liest die `user`-Blöcke erneut und sonst nichts.

Die Quellen sind die Ausnahme von „einmal gelesen“. Personen und Gruppen werden bei
jedem `refresh` erneut gelesen (standardmäßig 60 s; `refresh = "0"` schaltet es ab),
in einen neuen Snapshot, der abseits des Antwortwegs gebaut und atomar ausgetauscht
wird; eine entfernte Person oder ein entferntes Gruppenmitglied ist daher innerhalb
einer Periode weg, ohne Neustart. (v0.13.4 las sie einmal und brauchte für eine
Gruppenänderung einen Neustart.) Ein fehlgeschlagener Refresh behält die letzten
guten Daten und wird einmal pro Fehlerserie protokolliert, mit Nennung der Quelle.
Wo es auf Sperrung ankommt, setzen Sie `max_age` (zum Beispiel `"10m"`): Sind die
Daten älter, antworten Suchen, Binds von Personen und Passwortänderungen mit
`unavailable` (52) statt mit veralteten Daten. Eine Quelle,
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
| `SIGHUP` | es wird abgefangen und protokolliert, und authnd **bleibt in Betrieb**. Es liest das TLS-Zertifikat sofort erneut (v0.15.0); die Konfiguration und die Keytab werden nicht neu geladen |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 1 person from the configuration file
hangup: authnd does not reload its configuration or keytab; restart it to apply those (the TLS certificate is read again)
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

Das ist ein einziger Lauf des Binaries v0.15.0: ein `kill -HUP`, zwei Versuche, ein Passwort zu ändern (der erste
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

## Grenzen und Fristen {#limits}

Ab v0.15.0 begrenzt authnd, was ein Client, eine langsame Quelle oder eine Flut
es festhalten lassen können. Vier optionale Schlüssel, auf der obersten Ebene
der Konfiguration:

| Schlüssel | Standard | Bedeutung |
|---|---|---|
| `max_connections` | `4096` (war unbegrenzt) | die meisten gleichzeitig offenen Verbindungen; `0` ist unbegrenzt |
| `max_connections_per_ip` | keiner | die meisten von einer Adresse; er darf `max_connections` nicht übersteigen |
| `operation_timeout` | `30s` (war keiner) | wie lange eine LDAP-Operation höchstens dauern darf; `"0"` ist keiner, sonst mindestens `100ms` |
| `startup_timeout` | `60s` | wie lange das Öffnen und erste Lesen aller Quellen höchstens dauern darf; `"0"` ist keiner |

Eine Verbindung über einer Grenze erhält `busy` (51) in einer Notice of
Disconnection und wird geschlossen, nie in eine Warteschlange gestellt
(RFC 4511 4.4.1). Eine Operation, die bei `operation_timeout` noch läuft, wird mit
`timeLimitExceeded` (3) beantwortet, **auch wenn ihr Handler blockiert ist und die
Frist ignoriert**: das späte Ergebnis wird verworfen. Antwortet eine Quelle beim
Start nicht, verweigert authnd den Start nach `startup_timeout`, mit einem Fehler,
der die Phase und die Quelle nennt. Eine negative Zahl oder eine Dauer, die sich
nicht lesen lässt, wird beim Start und von `check` abgelehnt. Mit
`max_connections = 0` und `operation_timeout = "0"` gilt das Verhalten von v0.14.

`check` gibt die Grenzen aus, mit denen es bedienen wird, damit niemand die
Standardwerte betreibt, ohne es zu wissen:

```
$ authnd check etc2/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org
limits: 200 connections, 20 per address; an operation may take 10s; startup may take no limit

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid

GROUP  MEMBERS  PUBLISHED AS
staff  alice    groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Diese Konfiguration sagt `max_connections = 200`, `max_connections_per_ip = 20`,
`operation_timeout = "10s"` und `startup_timeout = "0"`. Ohne diese vier Schlüssel
lautet die Zeile `limits: 4096 connections, no limit per address; an operation may
take 30s; startup may take 1m0s`, die dasselbe Binary ebenfalls ausgegeben hat.

### Ein Ausfall ist kein falsches Passwort {#outage}

Werden die Personen gegen ein anderes Verzeichnis geprüft (eine `ldap`-Quelle) und
lässt sich dieses Verzeichnis nicht fragen, weil die Verbindung abgelehnt oder
zurückgesetzt wird, es `busy`, `unavailable` oder `other` antwortet oder nicht
innerhalb von `operation_timeout` antwortet, antwortet authnd LDAP `unavailable`
(52), **nie** `invalidCredentials` (49). Das gilt für einen einfachen Bind, für das
alte Passwort einer Passwortänderung und für den Passwortfaktor eines `mfa`-Binds.
Vor v0.15.0 wurde das als falsches Passwort gemeldet, sodass ein Anmeldeformular
der Person sagte, ihr Passwort sei falsch, während das Verzeichnis ausgefallen war.
Ein falsches Passwort ergibt weiterhin 49. Die Ursache steht im Log, nicht in dem,
was der Client erfährt, und ein Ausfall zählt nicht als fehlgeschlagener Versuch.

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
