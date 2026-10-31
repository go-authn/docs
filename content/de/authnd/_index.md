---
title: "authnd, ein LDAP-Server für Personen, die anderswo verwaltet werden"
linkTitle: "authnd"
weight: 10
description: "Ein LDAP-Verzeichnis und optional ein Kerberos-Realm über Personen aus einer Konfigurationsdatei, einer SQL-Datenbank oder einem anderen Verzeichnis."
tags: [authnd, ldap]
---

**Die Personen eines Standorts stehen bereits in einer Datenbank, einer Datei oder einem
anderen Verzeichnis. Was sie authentifizieren will, spricht LDAP.** authnd ist die Fassade
davor: Es führt Binds und Suchen über die Quellen von
[go-authn/directory]({{< relref "/libraries/_index.md" >}}) aus, sodass das, was eine
Datenbank enthält, von allem gelesen werden kann, das ein Verzeichnis zu fragen weiß. Reines Go,
`CGO_ENABLED=0`, ein Binary. Diese Seiten beschreiben v0.13.0, dessen Einträge den
Standardschemata folgen und das Schema bestehen, das es unter `cn=Subschema` bereitstellt
und das ein Standort um sein eigenes erweitert
([SUPANN, eduPerson]({{< relref "/authnd/schemas.md" >}})) und mit
[DIT-Content-Rules, Name Forms und Structure Rules]({{< relref "/authnd/schemas.md#rules" >}})
auch um Formvorgaben, mit go-authn/ldap v0.11.0 und
go-authn/directory v0.16.0 darunter; was geprüft ist und
was nicht, steht auf der Seite [Stand]({{< relref "/status.md" >}}).

{{< callout type="warning" >}}
**Upgrade von v0.11.x**

- ⛔ **Sicherheit: Nehmen Sie v0.12.0, nicht v0.11.1.** Die Release-Binaries von
  v0.11.1 wurden mit Go 1.27.2 gebaut, dessen crypto/x509 den kompromittierten
  Zwischenzertifikaten, die GO-2026-6809 nennt, das Vertrauen nicht entzieht, und
  authnd prüft Zertifikate. v0.12.0 wird mit Go 1.27.3 gebaut, und seine
  `go`-Direktive lautet 1.27.3, sodass `go install` von selbst auf die
  korrigierte Toolchain wechselt.
- Eine Konfiguration, die die neuen Schlüssel nicht verwendet, veröffentlicht, was
  v0.11.1 veröffentlicht hat: Eine Klasse wird deklariert, nie abgeleitet, also
  ändert sich ohne `object_classes` nichts.
- Neu, alles optional: [`schema_files` und ein `schema`-Block]({{< relref "/authnd/schemas.md" >}})
  fügen dem bereitgestellten Schema die Definitionen eines Standorts hinzu, und
  `object_classes` und `group_object_classes` deklarieren die Hilfsklassen
  (AUXILIARY), die die Personen und Gruppen einer Quelle tragen. Eine Definition, die eine
  bereits vorhandene neu definiert, wird abgelehnt, selbst wortgleich, wie
  slapd sie ablehnt.
- `check` und die Startzeilen sagen, welche Dateien und Blöcke geladen wurden, was
  jede Quelle deklariert, welche Klassen einer Person mangels eines
  MUST vorenthalten wurden und über welche Gruppen sich zwei Quellen uneinig sind.

Führen Sie `authnd check` mit dem neuen Binary vor dem Neustart aus, wie
[Installation]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}) es sagt.
{{< /callout >}}

{{< callout type="warning" >}}
**Upgrade von v0.10.x**

- `publish_nt_hash = true` braucht nun einen [`samba`-Block]({{< relref "/authnd/tls.md#the-samba-block" >}}),
  sonst startet authnd nicht.
- Eine Person ohne `uidNumber`, `gidNumber` und `homeDirectory` ist kein
  `posixAccount` mehr, und eine Gruppe ohne `gidNumber` keine
  `posixGroup` mehr; ein Konsument, der nach diesen Klassen filtert, sieht daher weniger Einträge:
  siehe [die Einträge]({{< relref "/authnd/entries.md" >}}).
- Ein `users "ldap"`-Block liest standardmäßig mehr aus dem Verzeichnis dahinter:
  siehe [Personen]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

`authnd check` mit dem neuen Binary sagt alle drei vor dem Neustart.
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## Die kleinste Konfiguration {#the-smallest-configuration}

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

Personen werden als `uid=<name>,ou=people,<base_dn>` veröffentlicht, Gruppen als
`cn=<name>,ou=groups,<base_dn>`. Was jeder Eintrag *ist*, ergibt sich aus dem, was seine
Quelle geliefert hat: Eine Person ist ein `account`, oder ein `inetOrgPerson`, wenn es
ein `sn` gibt, und ein `posixAccount` nur mit `uidNumber`, `gidNumber` und
`homeDirectory`; jede Person ist ein `uidObject`. Eine Gruppe ist eine `posixGroup`
(mit `memberUid`), wenn sie eine `gidNumber` hat, andernfalls eine `groupOfNames`
(mit `member`-DNs), oder eine `organizationalRole`, wenn sie zudem leer ist.
`sshPublicKey` kommt hinzu, wenn die Person Schlüssel hat, und `sambaNTPassword`, wenn
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) es vorsieht
und eine SID angegeben werden kann. Jeder Eintrag besteht das unter
`cn=Subschema` bereitgestellte Schema, bevor er veröffentlicht wird: siehe
[die Einträge und das Schema]({{< relref "/authnd/entries.md" >}}). Bis
v0.10.2 war jede Person ein `posixAccount` und jede Gruppe eine `posixGroup`,
was auch immer sie hatten.

`--config` (`-c`) nimmt eine Datei oder ein Verzeichnis und darf wiederholt werden; ein
Verzeichnis steht für jede `.hcl`-Datei darin, in Namensreihenfolge gelesen und zu einer
Konfiguration zusammengeführt. Eine Konfiguration ohne `base_dn` oder ohne eine einzige
Person startet nicht.

## Wer sich binden und wer lesen darf {#who-may-bind-and-who-may-read}

Ein LDAP-Server soll Personen nachweisen, also sind seine Ablehnungen das eigentliche Design.
Dies sind Antworten des Release-Binarys v0.12.3 an den Client von OpenLDAP selbst:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| Anfrage | Antwort | warum |
|---|---|---|
| leerer Name, leeres Passwort (RFC 4513 §5.1.1, anonym) | Erfolg | sie sagt „ich bin niemand“, was stimmt, und ein Client sendet sie, bevor er irgendetwas herausgefunden hat |
| ein **Name** und ein leeres Passwort (§5.1.2, nicht authentifiziert) | `unwillingToPerform` | sie benennt jemanden und beweist nichts; §5.1.2 verlangt genau diesen Code. `invalidCredentials` würde einer Person sagen, ihr Passwort sei falsch |
| ein falsches Passwort oder ein Name, den hier niemand hat | `invalidCredentials` | beides wird nicht unterschieden |
| eine Suche durch jemand anderen als einen `reader` | `insufficientAccessRights` | ein Bind beweist, wer Sie sind; alle lesen zu dürfen, ist eine eigene Erlaubnis |
| `add`, `delete`, `modifyDN` | `unwillingToPerform` | dafür ist kein Handler angebunden; der eine Schreibvorgang ist [das eigene Passwort einer Person]({{< relref "/authnd/passwords.md" >}}) |

Ein `reader` ist ein Dienstkonto mit einem Bind-DN und `password` oder `password_file`; ein
Reader ohne beides wird beim Start abgelehnt (*ein Reader, der nichts beweist, ist eine anonyme
Suche mit zusätzlichen Schritten*). Ohne jeden Reader darf nichts suchen, und `check` sagt das.

Das Root-DSE wird einem anonymen Client beantwortet, wie es die Erkennung braucht:

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

`1.3.6.1.4.1.4203.1.11.1` ist die Password-Modify-Operation aus RFC 3062.
`subschemaSubentry` benennt das [Schema]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}),
das ebenfalls einem anonymen Client beantwortet wird.
`supportedSASLMechanisms: OAUTHBEARER` erscheint nur mit einem
[`oidc`-Block]({{< relref "/authnd/tokens.md" >}}).

## Wie es weitergeht {#where-to-go-next}

| | |
|---|---|
| [Installation]({{< relref "/authnd/install.md" >}}) | das Release-Binary, das Konto `authnd`, die systemd-Unit, Upgrades |
| [Woher die Personen kommen]({{< relref "/authnd/people.md" >}}) | `user`- und `group`-Blöcke, eine SQL-Datenbank, ein anderes LDAP-Verzeichnis |
| [Die Einträge und das Schema]({{< relref "/authnd/entries.md" >}}) | als was jede Person und jede Gruppe veröffentlicht wird, `cn=Subschema`, Attribute, was weggelassen oder zurückgehalten wird |
| [Standort-Schemata]({{< relref "/authnd/schemas.md" >}}) | `schema_files`, der `schema`-Block und `object_classes`: SUPANN, eduPerson oder die eigenen Attribute eines Standorts; DIT-Content-Rules, Name Forms und DIT-Structure-Rules |
| [`check`]({{< relref "/authnd/check.md" >}}) | die Konfiguration vor einem Neustart zurücklesen |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` oder StartTLS, und `publish_nt_hash` |
| [Ein Passwort ändern]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, und warum immer nach dem alten Passwort gefragt wird |
| [Ein Kerberos-Realm]({{< relref "/authnd/kerberos.md" >}}) | der Keytab, und wem ein Ticket ausgestellt werden kann |
| [Ein zweiter Faktor]({{< relref "/authnd/mfa.md" >}}) | ein Einmalcode am Ende des Passworts |
| [Ein Token beim Bind]({{< relref "/authnd/tokens.md" >}}) | OIDC über SASL `OAUTHBEARER` |
| [Betrieb]({{< relref "/authnd/operations.md" >}}) | Signale, Neustarts, was es protokolliert, woran man erkennt, dass es läuft |

{{< callout type="info" >}}
**Zu den Transkripten**

Jeder Befehl auf diesen Seiten wurde am 26. Oktober 2026 mit den veröffentlichten Binärdateien erneut ausgeführt und nicht abgetippt: `authnd` v0.12.3 (`authnd-darwin-arm64`, von `relverify` gegen `SHA256SUMS` und die Attestierung geprüft; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`), `authn-bridge` v0.23.4, `authn-revokd` v0.6.6, `sshcert-authorize` v0.1.9 und `ldapschema` v0.10.1. Was die Befehle ausgaben, steht hier. Zwei Transkripte sind Ausnahmen, und jedes sagt es dort, wo es steht: der Client `oidctool` auf [der Token-Seite]({{< relref "/authnd/tokens.md" >}}), ein für diese Seiten geschriebener Testclient, der zu keinem Release gehört und dessen Transkripte und Serverzeilen daneben vom Release-Binary v0.10.0 ausgegeben wurden; und die abgelaufenen Metadaten von RENATER auf [der Föderationsseite]({{< relref "/authn-bridge/federation.md" >}}), eine Datei, die nicht mehr veröffentlicht wird. Alle wurden von den OpenLDAP- und Heimdal-Clients gestellt, die mit macOS ausgeliefert werden, auf 127.0.0.1 an nicht privilegierten Ports, in einem Arbeitsverzeichnis. Deshalb nennen die zugrunde liegenden Konfigurationen Dateien über relative Pfade wie `etc/authnd/passwords/alice.pw`, und deshalb haben die Passwortdateien Namen wie `alice.pwin`. Die Pfade unter `/etc/authnd` in den Beispielen sind die, die ein installierter Server verwendet. Die Transkripte, die die Version von `authnd` ausgeben, wurden mit v0.13.0 erneut ausgeführt (`authnd-darwin-arm64`, von `relverify` gegen `SHA256SUMS` und die Attestierung geprüft; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.13.0`): die Root DSE hier und auf der Betriebsseite sowie `authnd --version`. Das Schema auf der Seite zu den Einträgen wurde von v0.12.4 ausgegeben (`mod github.com/go-authn/authnd v0.12.4`, `vcs.modified=false`); v0.13.0 gibt für ein Schema ohne Regeln keinen Wert von `dITContentRules`, `nameForms` oder `dITStructureRules` aus, was geprüft wurde. Womit der [Abschnitt zu den Regeln auf der Seite zu den Standort-Schemata]({{< relref "/authnd/schemas.md#rules" >}}) ausgeführt wurde, steht dort.
{{< /callout >}}
