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
`CGO_ENABLED=0`, ein Binary. Diese Seiten beschreiben v0.10.1, das sich von v0.10.0 nur durch
den eingebetteten KDC (go-authn/kdc v0.4.2) unterscheidet; was geprüft ist und was nicht, steht
auf der Seite [Stand]({{< relref "/status.md" >}}).

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

Personen werden als `uid=<name>,ou=people,<base_dn>` (`posixAccount`) veröffentlicht,
Gruppen als `cn=<name>,ou=groups,<base_dn>` (`posixGroup`, mit `memberUid`).
Jeder Eintrag trägt `uid` und `cn`; `sambaNTPassword` und `sshPublicKey` kommen hinzu,
wenn die Person sie hat, und beim ersten nur, wenn
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) es vorsieht.

`--config` (`-c`) nimmt eine Datei oder ein Verzeichnis und darf wiederholt werden; ein
Verzeichnis steht für jede `.hcl`-Datei darin, in Namensreihenfolge gelesen und zu einer
Konfiguration zusammengeführt. Eine Konfiguration ohne `base_dn` oder ohne eine einzige
Person startet nicht.

## Wer sich binden und wer lesen darf {#who-may-bind-and-who-may-read}

Ein LDAP-Server soll Personen nachweisen, also sind seine Ablehnungen das eigentliche Design.
Dies sind Antworten des Release-Binarys v0.10.0 an den Client von OpenLDAP selbst:

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
vendorName: go-authn/authnd
vendorVersion: v0.10.0
```

`1.3.6.1.4.1.4203.1.11.1` ist die Password-Modify-Operation aus RFC 3062.
`supportedSASLMechanisms: OAUTHBEARER` erscheint nur mit einem
[`oidc`-Block]({{< relref "/authnd/tokens.md" >}}).

## Wie es weitergeht {#where-to-go-next}

| | |
|---|---|
| [Installation]({{< relref "/authnd/install.md" >}}) | das Release-Binary, das Konto `authnd`, die systemd-Unit, Upgrades |
| [Woher die Personen kommen]({{< relref "/authnd/people.md" >}}) | `user`- und `group`-Blöcke, eine SQL-Datenbank, ein anderes LDAP-Verzeichnis |
| [`check`]({{< relref "/authnd/check.md" >}}) | die Konfiguration vor einem Neustart zurücklesen |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` oder StartTLS, und `publish_nt_hash` |
| [Ein Passwort ändern]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, und warum immer nach dem alten Passwort gefragt wird |
| [Ein Kerberos-Realm]({{< relref "/authnd/kerberos.md" >}}) | der Keytab, und wem ein Ticket ausgestellt werden kann |
| [Ein zweiter Faktor]({{< relref "/authnd/mfa.md" >}}) | ein Einmalcode am Ende des Passworts |
| [Ein Token beim Bind]({{< relref "/authnd/tokens.md" >}}) | OIDC über SASL `OAUTHBEARER` |
| [Betrieb]({{< relref "/authnd/operations.md" >}}) | Signale, Neustarts, was es protokolliert, woran man erkennt, dass es läuft |

{{< callout type="info" >}}
**Zu den Transkripten**

Jeder Ausgabeblock auf diesen Seiten wurde vom Release-Binary v0.10.0
(`authnd-darwin-arm64`) ausgegeben – v0.10.1 gab für die beiden verglichenen Konfigurationen
byte für byte dasselbe `check` aus – sowie von den OpenLDAP- und Heimdal-Clients, die mit
macOS ausgeliefert werden, ausgeführt auf 127.0.0.1 an nicht privilegierten Ports, in einem
Arbeitsverzeichnis unter `/tmp`. Deshalb nennen die zugrunde liegenden Konfigurationen Dateien
über relative Pfade wie `etc/authnd/passwords/alice.pw`, und deshalb haben die Passwortdateien
Namen wie `alice.pwin`. Die Pfade unter `/etc/authnd` in den Beispielen sind die, die ein
installierter Server verwendet.
{{< /callout >}}
