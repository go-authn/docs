---
title: "kdcd – ein Kerberos-KDC-Daemon für einen Realm"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd ist ein Programm auf Basis der Bibliothek kdc: AS und TGS über UDP und TCP, eine HCL-Datei, jedes Geheimnis eine Datei und ein optionaler Mutual-TLS-Listener, der ein TGT für eine Person ohne Passwort ausstellt."
tags: [bibliotheken, kerberos, verzeichnis, kdcd]
---

**Wie läuft die Bibliothek [kdc]({{< relref "/libraries/kdc.md" >}}) als Dienst?**
`kdcd` ist ein Kerberos-KDC-Daemon für einen Realm, gebaut auf der Bibliothek
[go-authn/kdc](https://github.com/go-authn/kdc). Er beantwortet AS- und TGS-Anfragen
über UDP und TCP und **stellt** optional **ein TGT aus** für eine Person, die sich
anderswo ausgewiesen hat (eine Passkey-Anmeldung bei
[go-authn/bridge](https://github.com/go-authn/bridge)), über Mutual TLS. Die
Bibliothek hält das Protokoll; dieses Programm hält die Sockets, die Konfiguration
und die Regeln für die Geheimnisse.

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

Installation (das Binary heißt `kdcd`: der KDC von MIT ist `krb5kdc`, der von Heimdal `kdc`):

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

Reines Go, `CGO_ENABLED=0`; Releases tragen ein `SHA256SUMS`-Manifest und pro Binary
eine Build-Provenance-Attestierung. Als Dienst: `packaging/systemd/` (Unit und
sysusers-Datei; siehe [Betrieb](#running-it)).

## Keine Passwörter {#no-passwords}

`kdcd` setzt `AllowPasswordDerivedAS` der Bibliothek nie (seit kdc v0.11.0
standardmäßig aus) und hat keine Option dafür.

**In `kdcd` gibt es keinen Passwortpfad, und keiner lässt sich einschalten** (in v0.2.0
entfernt; v0.1.0 hatte `password_file`). Eine Person hat hier keinen Langzeitschlüssel,
daher wird ein **AS-REQ** für eine Person absichtlich mit `KDC_ERR_NULL_KEY`
beantwortet, was der Client auch sendet. Ein TGT erhält eine Person nur über den
**Mint-Listener**, von einem Aufrufer, der sie per Passkey authentifiziert hat
(go-authn/bridge).

- Ein Verzeichnis sagt, **wer existiert, und ihre Gruppen**. Von dem, was eine Quelle
  trägt, erreicht den KDC nur der Name: jede Identität wird, bevor die Bibliothek sie
  sieht, nur mit dem Namen neu aufgebaut (`nameOnly`), sodass selbst ein Passwort, das
  eine Quelle veröffentlicht hat, keinen Schlüssel ableitet. Die Ablehnungen beim Laden
  unten sagen, warum; sie sind nicht die einzige Sperre.
- Dienste und `krbtgt/REALM` behalten ihre Schlüssel in der Keytab: **zufällige
  Schlüssel**, nie aus einem Passwort abgeleitet (erzeugen Sie sie zum Beispiel mit 32
  Bytes aus `/dev/urandom` über Ihr Keytab-Werkzeug).
- `password_file`, eine `users`-Abfrage oder ein Attribut, das eine Passwort- oder
  NT-Hash-Spalte nennt, ein `bind_password_file`, ein `bind_dn` (ein einfacher Bind ist
  ein Passwort) oder ein DSN mit Passwort: beim Laden abgelehnt, mit Nennung der
  Entfernung und der Version.
- Eine `ldap`-Quelle wird **anonym** gelesen. Ein Dienst-Bind per Clientzertifikat oder
  SASL EXTERNAL ist noch nicht verfügbar, weil `hcldir.Block` von `go-authn/directory`
  kein Feld dafür hat; bis es eines hat, wird `bind_dn` abgelehnt.

Die Seite der Bibliothek ist auf der
[kdc-Seite]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}}) erklärt.

## Konfiguration {#configuration}

Eine HCL-Datei. Nichts darin ist ein Geheimnis; jedes Geheimnis ist eine Datei.

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: who exists. Any number of these, in any mix.
user "alice@poc.test" {}                  # a name; a TGT only through mint

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"              # no password in it: a client certificate or a socket
  users    = "select login as name from staff"
}
users "ldap" {                            # read anonymously
  url      = "ldaps://ldap.example.org"
  base_dn  = "ou=people,dc=example,dc=org"
}
```

Die `users`-Blöcke sind die von [go-authn/directory/hcldir](https://github.com/go-authn/directory);
kdcd lehnt die Teile davon ab, die ein Passwort tragen (siehe oben).

**Geheimnisse: eine Datei oder eine Referenz.** `keytab_file` und `key_file` (in `mint`)
benennen eine Datei, geprüft wie unten beschrieben. `keytab_from` und `key_from` nehmen
stattdessen eine secretsource-Referenz, etwa `systemd-creds:kdc-keytab`: ein Credential,
das systemd für den Dienst entschlüsselt (`LoadCredentialEncrypted=`, versiegelt mit
`systemd-creds encrypt --with-key=host+tpm2`, nie ein bloßes `--tpm2-pcrs=7`). Eines von
beiden, nicht beide. `file:` wird in einem `_from`-Schlüssel abgelehnt. `keytab_file` bleibt
und ist nicht veraltet: Keytab und Schlüssel sind binär, `file:` entfernt einen
abschließenden Zeilenumbruch (das würde einen Schlüssel mit Endbyte 0x0a beschädigen), und
eine Referenz fasst höchstens 4096 Byte, ein größerer Keytab bleibt also in `keytab_file`.
Seit secretsource v0.9.0 lehnt `file:` außerdem einen Symlink und eine Datei eines anderen
uid ab. `dsn_file` enthält kein Passwort, daher kein `_from`.

`kdcd check --config FILE` liest und baut alles, was der Daemon bauen würde, öffnet
das Verzeichnis, lauscht nirgends und gibt aus, was er bedient: den Realm, die
Adressen, die Principals der Keytab (Name, kvno, etype; nie ein Schlüssel), wie viele
Personen das Verzeichnis enthält, die Mint-Aufrufer. Exit-Status 0 und eine letzte
Zeile `ok`, oder die erste Ablehnung.

### Womit er den Start verweigert {#what-it-refuses-to-start-with}

| Abgelehnt | Warum |
| --- | --- |
| eine Keytab, ein Mint-Schlüssel oder eine DSN-Datei, die **Gruppe oder andere lesen oder schreiben können**, oder die einer anderen uid als root oder der des Daemons gehört | eine Kopie, die ein anderes Konto lesen kann, fälscht Tickets für jede Person des Realms |
| **jeder Passwortpfad**: `password_file` (auch leer), `bind_password_file`, `bind_dn`, eine `users`-/`groups`-Abfrage oder ein Attribut, das `password`, `passwd`, `nt_hash`, `userPassword`... nennt, ein DSN mit Passwort | in v0.2.0 entfernt: keine Person hat hier einen Schlüssel; die Meldung sagt es. Die Prüfungen von Abfrage und DSN sind nach bestem Bemühen; `nameOnly` hält, was ihnen entgeht |
| ein inline geschriebenes Geheimnis (`password = "..."` ist kein Argument) | Geheimnisse leben in Dateien, nie in der Konfiguration, einer Sicherung davon oder einem Log |
| eine Konfigurationsdatei, die Gruppe oder andere schreiben können | wer sie schreibt, wählt die Mint-Aufrufer |
| eine Keytab ohne `krbtgt/REALM`-Schlüssel oder der ein aufgeführter Dienst fehlt, **in aes256-cts-hmac-sha1-96** (dem einen Typ, den die Bibliothek ausstellt) | er würde starten und beim ersten `kinit` scheitern |
| ein Platzhalter oder ein Hostname in `listen` (ein IP-Literal ist verlangt) und **jeder** Platzhalter für `mint` | der KDC und der Mint-Listener liegen auf den Schnittstellen, die jemand gewählt hat |
| ein `mint`-Block ohne Aufrufer, ohne Zertifikat oder mit abgelaufenem | die Bibliothek liest „keine Aufrufer" als „Mint aus"; dies sagt es, statt stillschweigend nichts auszustellen |
| `ldap://` zu einer anderen Maschine ohne `start_tls` | jedes Passwort ginge so im Netz, wie es getippt wurde |

Geheimnisdateien werden **einmal** geöffnet, und die geöffnete Datei wird geprüft
(reguläre Datei, Modus, Besitzer), sodass eine Prüfung nicht eine Datei und das Lesen
eine andere betreffen kann (das Vorbild ist `readKeytab` von go-fileshare).
`dsn_file` liest `hcldir` über den Namen, nachdem sie auf
dieselbe Weise geprüft wurde.

## Das Mint-Vertrauensmodell {#the-mint-trust-model}

`POST https://<mint address>/mint` mit `{"principal": "alice", "lifetime_seconds": 36000}`
liefert einen KRB-CRED (RFC 4120 5.8) mit einem TGT für `alice`, den der Aufrufer an
den Rechner der Person weitergibt ([go-authn/kinit](https://github.com/go-authn/kinit)
lädt ihn in eine Windows-Anmeldesitzung). Was ihn begrenzt:

- **Der Aufrufer ist das TLS-Clientzertifikat**, vom Listener gegen `client_ca_file`
  geprüft (TLS 1.3, `RequireAndVerifyClientCert`): eine Verbindung ohne Zertifikat
  oder mit einem, das die CA nicht signiert hat, scheitert im Handshake, bevor ein
  HTTP gelesen wird. Ein geprüftes Zertifikat wird dann über einen **URI-subjectAltName**
  exakt mit `callers` verglichen; ein Zertifikat, das sich prüfen lässt, aber nicht
  aufgeführt ist, bekommt `403`. Nichts in einem Header oder Body nennt den Aufrufer.
- **Wer in `callers` steht, kann ein TGT für jeden Principal des Verzeichnisses
  erhalten** (nie einen Dienst, nie einen Namen, den das Verzeichnis nicht kennt), ohne
  den Schlüssel dieser Person. Die eigene Authentifizierung der Person durch den
  Aufrufer ist, was der Realm glaubt, also ist ein Aufrufer so vertrauenswürdig wie
  die Keytab des KDC. Führen Sie je einen pro Identitätsanbieter auf, geben Sie jedem
  ein eigenes Zertifikat, und halten Sie `client_ca_file` eine CA, die sonst nichts signiert.
- Das Ticket ist `INITIAL | PRE-AUTHENT`, nie erneuerbar, weiterleitbar oder
  stellvertretend; seine Laufzeit ist das Kleinste aus Anfrage, `lifetime` und zehn Stunden.
- Der Sitzungsschlüssel stammt aus `crypto/rand`, verlässt den Prozess einmal, in der
  Antwort, und wird nie protokolliert. Die Antwort trägt `Cache-Control: no-store`.
  Der KRB-CRED trägt den Schlüssel im Klartext, also **ist der TLS-Kanal die
  Verschlüsselung**: Legen Sie den Listener auf eine interne Schnittstelle.
- Nur `/mint` wird bedient, mit Timeouts und Header-Limit. Jedes Mint und jede
  Ablehnung wird mit der URI des Aufrufers und dem angefragten Principal protokolliert.

Das vollständige Bedrohungsmodell ist das der Pull Request der Bibliothek,
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38), mit dem
[Abschnitt zum Ausstellen](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)
und den [Audit-Notizen](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)
im README der Bibliothek; nichts davon wird hier wiederholt oder abgeschwächt.
Der `kerberos`-Block von [go-authn/bridge](https://github.com/go-authn/bridge) ist die
Aufruferseite: sein `kdc_url` ist `https://<mint address>/mint`, sein `ca_file`
signiert das obige `cert_file`, und der URI-Name seines Clientzertifikats ist ein
Eintrag in `callers`.

## Betrieb {#running-it}

`packaging/systemd/kdcd.service` betreibt ihn als Systembenutzer aus
`packaging/sysusers.d/kdcd.conf`, mit der Härtung der Unit von
[authn-bridge](https://github.com/go-authn/bridge). Port 88 ist privilegiert, daher
gewährt die Unit genau `CAP_NET_BIND_SERVICE` und sonst nichts.

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

Geheimnisse gehören `kdcd` (oder root) im Modus 0600; 0640 mit Gruppe `kdcd` wird
absichtlich abgelehnt. Eine Konfigurationsänderung ist `systemctl restart kdcd`
(der Daemon lädt nicht neu; ein Client wiederholt eine abgelehnte Verbindung).

Unter Windows bedeuten die Modusbits nichts und werden nicht geprüft: Legen Sie die
Dateien dorthin, wo nur das Konto, das den Dienst ausführt, sie lesen kann.

## Nicht hier {#not-here}

Cross-Realm, PKINIT, FAST, erneuerbare oder vordatierte Tickets, ein kadmin-Protokoll
und jeder Verschlüsselungstyp außer aes256-cts-hmac-sha1-96 sind die eigenen Grenzen
der Bibliothek ([go-authn/kdc](https://github.com/go-authn/kdc#readme)). `kdcd` hat
noch kein Neuladen und keinen Metrik-Endpunkt.

## Referenz {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd), v0.2.0.
