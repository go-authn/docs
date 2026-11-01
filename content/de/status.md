---
title: "Stand"
weight: 60
description: "Welche Releases diese Seiten beschreiben, was jedes Release hinzugefügt hat und was noch nicht implementiert ist."
tags: [stand, releases]
---

Diese Seiten sind die Dokumentationsversion **0.7** und beschreiben:

| Programm | Release | Modul |
|---|---|---|
| authnd | **v0.15.0** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.6** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.7** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

Die Versionen der Bibliotheken stehen auf [ihrer eigenen Seite]({{< relref "/libraries/_index.md" >}});
ldap ist bei **v0.12.0**, mit DIT-Content-Rules, Name Forms und DIT-Structure-Rules, die
gelesen, durchgesetzt und veröffentlicht werden, einem typisierten `BuildError` für ein Schema, das sich nicht aufbauen lässt,
Schemas in HCL2 und dem Konverter `ldapschema`,
und directory bei **v0.17.0**, mit deklarierten Objektklassen. authnd
v0.15.0 bettet ldap v0.12.0 und directory v0.17.0 ein.
Eine neue Minor-Version eines der obigen Programme ist eine neue Dokumentationsversion,
sodass die Seiten, die jemand unter `/docs/0.7/` findet, weiterhin beschreiben, was
installiert wurde; die der früheren Releases bleiben unter `/docs/0.1/`,
`/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/`, `/docs/0.5/` und `/docs/0.6/`.

{{< callout type="warning" >}}
**authnd von v0.14.x aktualisieren: zwei Standardwerte ändern sich**

`max_connections` ist `4096` (war unbegrenzt) und `operation_timeout` ist `30s` (war
keiner); ein ausgefallenes vorgelagertes Verzeichnis wird mit `unavailable` (52)
beantwortet und nicht mehr mit `invalidCredentials` (49). `max_connections = 0` und
`operation_timeout = "0"` ergeben das alte Verhalten. Siehe
[Grenzen und Fristen]({{< relref "/authnd/operations.md#limits" >}}).
{{< /callout >}}

{{< callout type="warning" >}}
**Sicherheit: Verwenden Sie authnd v0.12.0, nicht v0.11.1**

authnd prüft Zertifikate (`x509.Certificate.Verify`, laut `govulncheck` von `main`
aus erreicht), und das crypto/x509 von Go 1.27.2 entzog den kompromittierten
Zwischenzertifikaten, die GO-2026-6809 nennt, das Vertrauen nicht. **Die
Release-Binaries von v0.11.1 wurden mit Go 1.27.2 gebaut und sind betroffen.** v0.12.0 wird
mit Go 1.27.3 gebaut, und seine `go`-Direktive lautet 1.27.3, sodass `go install`
von selbst auf die korrigierte Toolchain wechselt; `govulncheck` unter 1.27.3 meldet
keine Schwachstellen. Sein Release-Binary meldet `go1.27.3` in
`go version -m`. Siehe [den Upgrade-Hinweis]({{< relref "/authnd/_index.md" >}}).
{{< /callout >}}

{{< callout type="warning" >}}
**Sicherheit: nehmen Sie authn-bridge v0.23.3 und authn-revokd v0.6.5**

Unter Go 1.27.2 meldet `govulncheck` GO-2026-6809 in beiden Programmen: `Certificate.Verify` aus `crypto/x509` wies bekannte kompromittierte Zwischenzertifikate nicht zurück. Behoben ist es in Go 1.26.10 und 1.27.3. **Release-Binaries, die mit einem älteren Go gebaut wurden, sind betroffen.** v0.23.3 und v0.6.5 sind mit Go 1.27.3 gebaut, und ihre `go`-Direktive ist 1.27.3; `go install` wechselt daher von selbst zur korrigierten Toolchain, und ihre Release-Binaries melden in `go version -m` `go1.27.3`. sshcert ist nicht betroffen und hat kein neues Release.
{{< /callout >}}

## Was jedes Release hinzugefügt hat {#what-each-release-added}

Jede Zeile ist die Änderung, für die ein Release erstellt wurde. Releases, die nur
Abhängigkeiten aktualisiert haben, sind weggelassen, außer denen, die diese Dokumentationsversion beschreibt.

### authnd {#authnd}

| | |
|---|---|
| v0.1.0 | ein LDAP-Server für Personen, die anderswo geführt werden: in einer Datei, einer SQL-Datenbank, einem anderen Verzeichnis |
| v0.2.0 | ein zweiter Faktor, über ein Protokoll mit nur einem Feld |
| v0.5.0 | Passwortänderungen, die genau eine Identität betreffen; ein Neuladen ohne Race; der KDC sieht Änderungen |
| v0.6.0 | die Sicherheitskorrekturen von oidc, directory, ldap, totp und mfa |
| v0.7.0 | das alte Passwort ist erforderlich, um es zu ändern; Geheimnisse werden als Digests fester Länge verglichen |
| v0.8.2 | ein Code zählt nur hinter dem richtigen Passwort; ein Leser wird über seinen konfigurierten DN zugeordnet |
| v0.9.0 | gebaut und getestet mit Go 1.27.1, gepinnt statt `stable` |
| v0.9.2 | Release-Binaries, `SHA256SUMS` und Build-Provenienz bei jedem Tag |
| v0.9.3 | Binaries außerhalb des Checkouts gebaut; jedes muss genau den Tag melden |
| v0.9.4 | ein `SIGHUP` beendet authnd nicht mehr: Es wird protokolliert, und nichts wird neu geladen |
| v0.9.5 | das Release prüft die Build-Informationen **jedes** Binarys, nicht nur eines |
| v0.9.6 | `check` sagt, warum einer Person kein Ticket ausgestellt werden kann |
| v0.10.0 | `check` öffnet das Zertifikat und die Keytab, wie es der Server tut; es nennt, wer sich nicht mit einem Passwort binden kann und wen ein Token noch zulässt; die Zeile zum Lauschen kommt, nachdem der Realm geöffnet ist |
| v0.10.1 | go-authn/kdc v0.4.2: ein `till` von 19700101000000Z erhält das längste Ticket, nicht eines, das 1970 abgelaufen ist |
| v0.10.2 | go-authn/directory v0.12.0: Eine leere Gruppe wird als `posixGroup` ohne `memberUid` veröffentlicht |
| v0.11.0 | [Einträge nach Standardschema]({{< relref "/authnd/entries.md" >}}), jeder an dem unter `cn=Subschema` bereitgestellten Schema gemessen; `attributes`, `users_attributes` und `groups_attributes`; `(uidNumber>=1000)` vergleicht Ganzzahlen. ⛔ `publish_nt_hash` braucht einen [`samba`-Block]({{< relref "/authnd/tls.md#the-samba-block" >}}), und ein Konsument, der nach `posixAccount` oder `posixGroup` filtert, sieht weniger Einträge |
| v0.11.1 | die Startzeile nennt nur die Quellen, aus denen jemand bereitgestellt wird: ohne `user`-Block nennt sie die Konfigurationsdatei nicht mehr |
| v0.12.0 | [Standort-Schemata]({{< relref "/authnd/schemas.md" >}}): `schema_files` (OpenLDAP-`.schema` und cn=config-LDIF, wie veröffentlicht; eine Neudefinition wird abgelehnt, selbst eine identische, wie slapd es tut) und ein `schema { }`-Block; Hilfsklassen (AUXILIARY), pro Quelle mit `object_classes` deklariert, beim Start validiert und mit ihren Oberklassen veröffentlicht; `check` meldet die Dateien, die Deklarationen, die einer Person wegen eines fehlenden MUST vorenthaltenen Klassen und Gruppen, bei denen sich zwei Quellen uneins sind. ⛔ Mit Go 1.27.3 gebaut: Die Binaries von v0.11.1 (Go 1.27.2) sind von GO-2026-6809 betroffen |
| v0.12.1 | eine Schemadatei oder ein Schemablock, der sich nicht aufbauen lässt, wird an der Stelle abgelehnt, die der `BuildError` von go-authn/ldap v0.10.0 trägt, mit einer Spalte (`site.schema:6:` wird zu `site.schema:6:1:`); die Meldung endet mit der Art der Ablehnung, und bei einem Duplikat steht, wo seine erste Definition ist |
| v0.12.2 | Release-Binaries werden mit `-ldflags="-w"` statt `-s -w` gelinkt: die Symboltabelle bleibt erhalten, sodass `govulncheck -mode binary` genau ist, statt Schwachstellen in nicht gelinktem Code zu melden; etwa 9 % größer (18,8 MB auf 20,5 MB unter darwin/arm64) |
| v0.12.3 | go-authn/ldap v0.10.1: `schema_files` werden in linearer Zeit gelesen. ⛔ Bis v0.12.2 hielt eine große Schemadatei aus kurzen Fortsetzungszeilen (4 MiB: etwa drei Minuten) den Start auf: ein Denial of Service durch eine Datei, die man nicht kontrolliert |
| v0.12.4 | go-authn/ldap v0.10.2: die DESC-Werte von 13 RFC-2307-Definitionen in `cn=Subschema` (`uidNumber`, `gidNumber`, `ipHostNumber`, `ipNetworkNumber`, `ipNetmaskNumber`, `macAddress` und die Klassen `ipService`, `ipProtocol`, `oncRpc`, `ipHost`, `ipNetwork`, `ieee802Device`, `bootableDevice`) tragen nicht mehr die Einrückung des Seitenumbruchs der RFC: `DESC 'An integer uniquely identifying a user in an administrative domain'` statt `... in an         administrative domain'` |
| v0.13.0 | [DIT-Content-Rules, Name Forms und DIT-Structure-Rules]({{< relref "/authnd/schemas.md#rules" >}}) (go-authn/ldap v0.11.0): `schema_files` und der `schema { }`-Block akzeptieren die drei Arten, und authnd setzt sie durch. Eine Content-Rule formt jeden Eintrag: Eine Hilfsklasse, die ihr `AUX` nicht aufführt, wird weggelassen (mit den Attributen, die nur sie erlaubte), ein `NOT`-Attribut wird verworfen, ein Eintrag, dem ein `MUST` fehlt, wird ausgelassen; jedes wird protokolliert und von `check` gemeldet. Mit einer aktiven Structure-Rule wird der Baum (Suffix, `ou=people`, `ou=groups`, das RDN `uid` oder `cn`) beim Start und von `check` geprüft, und eine Verletzung **verweigert den Start**, alle Ablehnungen auf einmal, ohne je ein Geheimnis zu wiederholen; ein Eintrag, den keine Regel platziert, wird ausgelassen. ⛔ Ein `schema { }`-String, der kein gültiges UTF-8 ist, wird jetzt abgelehnt. Das Veröffentlichen von 10.000 Personen macht 416 Allokationen pro Eintrag mit den Regeln gegenüber 265 ohne (Zeiten unter Last gemessen, nicht verlässlich) |
| v0.13.1 | Nur Leistung, mit go-authn/ldap v0.11.1: Das Veröffentlichen von 10.000 Personen (`BenchmarkPublish10k`, `-cpu 1`) macht 364 Allokationen pro Eintrag mit den Regeln und 239 ohne, gegenüber 416 und 265 bei v0.13.0, und 102,5 MiB pro Lauf mit den Regeln gegenüber 147,5. Die Zeiten wurden bei einer Last von 10 bis 16 gemessen und sind nicht verlässlich |
| v0.13.2 | Nur Leistung, mit go-authn/ldap v0.11.2: `Validate` macht für einen Eintrag mit zehn Attributen 12 statt 76 Allokationen; das Veröffentlichen von 10.000 Personen (`BenchmarkPublish10k`, `-cpu 1`) macht 128 Allokationen pro Eintrag mit den Regeln und 85 ohne, gegenüber 364 und 239 bei v0.13.1, und 54,8 MiB pro Lauf mit den Regeln gegenüber 102,5. Zeiten (Last 8 bis 11): etwa 90 ms gegenüber 158 ms mit den Regeln |
| v0.13.3 | Nur Leistung, mit go-authn/ldap v0.11.3: ein Eintrag, den `unmet` gerade validiert hat, wird von `validated` nicht erneut validiert, wenn er sich nicht geändert hat; das Veröffentlichen von 10.000 Personen (`BenchmarkPublish10k`, `-cpu 1`) macht 97 Allokationen pro Eintrag mit den Regeln und 69 ohne, gegenüber 128 und 85 bei v0.13.2 (−24 % und −19 %); etwa 66 ms und 36 ms (Last 4,8) |
| v0.13.4 | Ein Chaos-Durchgang. Gruppen werden einmal beim Start gelesen, wie die Personen: Eine Suche über 500 Personen und 200 Gruppen zu je 50 dauerte mit SQLite 4,13 s (jede Suche fragte die Gruppen erneut ab) und dauert 1,2 ms, und eine Gruppenabfrage, die während einer Suche fehlschlug, lässt die Gruppe nicht mehr aus einer Antwort fallen, die Success meldet. Eine beim Start nicht lesbare Quelle (eine Gruppenabfrage, die nicht läuft, eine von mehreren ausgefallenen Datenbanken) verweigert den Start und `check`. Ein Eintrag über etwa 3 MiB (ein einziger 10-MB-Attributwert) wird nicht veröffentlicht. Die Veröffentlichung wird einmal pro Personenbestand aufgebaut. Gehalten, mit Tests: an jedem Byte abgeschnittene Schemadateien, eine entfernte oder beschädigte Datenbank, feindliche Zeilen, ruhende Verbindungen, überlange BER-Längen, 20.000 Ebenen tief verschachtelte Filter |
| v0.14.0 | Geändert: v0.13.4 verlangte für eine Gruppenänderung einen Neustart, sodass ein aus einer Datenbank entferntes Mitglied den Zugriff behielt, bis jemand authnd neu startete. v0.14.0 stellt die rechtzeitige Sperrung wieder her. `refresh` (standardmäßig 60 s, `0` schaltet es ab) liest jede Quelle, Personen und Gruppen, in einen neuen Snapshot ein, der abseits des Antwortwegs gebaut und als Ganzes ausgetauscht wird; ein fehlgeschlagener Refresh behält den letzten guten Snapshot und wird einmal pro Fehlerserie protokolliert, mit Nennung der Quelle. `max_age` (standardmäßig nicht gesetzt) lässt Suchen, Binds von Personen und Passwortänderungen mit `unavailable` antworten, sobald die ausgelieferten Daten älter sind. Ein über authnd geschriebenes Passwort läuft durch denselben Austausch. Gemessen: Ein Refresh von 500 Personen und 200 Gruppen zu je 50 kostet mit SQLite etwa 2 s eines Kerns, eine Suche 0,5 ms (die Refresh-Kosten sind in v0.14.1 behoben) |
| v0.14.1 | Nur Performance. Ein Refresh wächst nicht mehr mit Gruppen mal Mitgliedschaftszeilen: directory v0.16.0 liest jede Quelle einmal, im Block. Ein Refresh von 500 Personen und 200 Gruppen zu je 50 mit SQLite sinkt von 1,87 s auf 0,155 s, einer von 10.000 Personen und 2.000 Gruppen von 391 s (sechseinhalb Refresh-Perioden) auf 1,6 s (2,7 % der 60-s-Periode). Die Allokationen sinken von 39.959.235 auf 3.095.482 und von 6.373.736.235 auf 31.198.460. Die Zeiten wurden bei einer Last von 17 bis 67 gemessen und sind Richtwerte; die Allokationszahlen sind exakt |
| v0.15.0 | Verfügbarkeit und Sicherheit, mit go-authn/ldap v0.12.0 und go-authn/directory v0.17.0. ⛔ **Zwei Standardwerte ändern sich**: `max_connections` ist `4096` (war unbegrenzt) und `operation_timeout` ist `30s` (war keiner). Neu, optional: `max_connections_per_ip` und `startup_timeout` (`60s`); [`check` gibt die Grenzen aus]({{< relref "/authnd/operations.md#limits" >}}). Eine Verbindung über der Grenze erhält `busy` und wird geschlossen; eine Operation über der Frist wird mit `timeLimitExceeded` beantwortet, auch wenn ihr Handler blockiert ist. Ein vorgelagerter Ausfall während eines Binds (einfacher Bind, Passwortänderung, Passwortfaktor von `mfa`) ergibt `unavailable` (52), nie `invalidCredentials` (49); ein falsches Passwort ergibt weiterhin 49. Ein Start gegen eine langsame Quelle scheitert nach `startup_timeout` und nennt Phase und Quelle. [Das TLS-Zertifikat wird erneut gelesen]({{< relref "/authnd/tls.md#renewal" >}}), wenn sich `cert_file` oder `key_file` ändern (erster Handshake nach 5 s und bei `SIGHUP`); ein Paar, das sich nicht laden lässt, behält das ausgelieferte Zertifikat und wird einmal protokolliert. Allokationszahlen stehen bei den Bibliotheken unten; Wanduhrzeit nicht gemessen (Last 21 zu Beginn) |

### authn-bridge {#authn-bridge}

| | |
|---|---|
| v0.1.0 | ein OpenID-Connect-Anbieter vor einer SAML-Föderation |
| v0.2.0 | der Device Grant, SSH-Zertifikate, Anwendungspasswörter, OpenPubkey |
| v0.3.0 | eine Admin-API (`bridge.admin.v1`) sowie `/healthz`, `/readyz`, `/metrics` |
| v0.4.0 | ES256-Access-Tokens |
| v0.5.0 | TLS über go-authn/servercert, gemeinsam mit go-fileshare |
| v0.6.0 | Zertifikate, die widerrufen werden können: eine SSH-KRL und X.509 für NFS mit einer CRL |
| v0.7.0 | Zustand, der einen Neustart übersteht: Refresh-Tokens und anerkannte Access-Tokens |
| v0.8.0 | ein Shared-Signals-Sender: CAEP `session-revoked` |
| v0.9.0 | die Korrekturen eines adversarialen Reviews von v0.8.1 |
| v0.10.0 | Sperrlisten, die überall geprüft werden können: eine signierte KRL, ein Ablaufdatum, ein ETag des Inhalts |
| v0.10.2 | eine CRL-Nummer für jede Ausgabe; nie eine Ausgabe, die vor der letzten datiert ist |
| v0.11.0 | Gruppen an ihren Identitätsanbieter gebunden; Deaktivieren nach Identität; eine Audience nur für die Bridge |
| v0.12.0 | eine laufende Anmeldung lebt in ihrem versiegelten Cookie, nicht im Speicher |
| v0.13.0 | ein vertraulicher Client darf seinen Code mit der Nonce schützen (RFC 9700 2.1.1) |
| v0.16.0 | `max_age` verlangt eine neue Authentifizierung nur, wenn die letzte zu alt ist |
| v0.16.3 | ein zweites Review: jede Schreibweise widerrufen, Deaktivieren nach `sub`, keine Wiederholung über Neustarts hinweg |
| v0.17.0 | WireGuard-Schlüssel, von Personen registriert und für ein Gateway aufgelistet |
| v0.18.0 | ein ID-Token ohne die Claims der Person; go-authn/saml v0.4.0 |
| v0.19.0 | das EuroHPC-SSH-CA-Profil, pro Client aktivierbar |
| v0.19.3 | Release-Binaries, `SHA256SUMS` und Build-Provenienz bei jedem Tag |
| v0.20.0 | der Befehl heißt `authn-bridge`; eine gehärtete systemd-Unit und eine Installationsanleitung |
| v0.20.1 | Kommentare und eine Ablehnungsmeldung, die nicht mehr zutrafen; das README nennt alles, was `RevokePerson` widerruft |
| v0.21.0 | [Resource Indicators nach RFC 8707]({{< relref "/authn-bridge/resources.md" >}}): Ein Client, dessen `audience` mehrere Ressourcenserver nennt, kann ein Token anfordern, das an nur einen adressiert ist. Eine Stunde vor v0.20.1 getaggt, die sie ebenfalls enthält, und ohne die Korrekturen von v0.20.1 |
| v0.21.1 | golang.org/x/net v0.60.0 wegen seiner HTTP/2-Sicherheitshinweise, und Go 1.27.2; wieder die Korrekturen von v0.20.1; Platzhalter-Domains mit Namen nach RFC 2606 |
| v0.22.0 | das Access-Token trägt kein `auth_time` und kein `acr` mehr (das ID-Token schon), damit ein ES256-Token bis zum 99. Perzentil der RENATER-Scopes in die 1023 Zeichen von OpenSSH passt |
| v0.22.1 | `resource` darf am Autorisierungs-Endpunkt wiederholt werden, für einen auf mehrere Server begrenzten Grant; an `device_authorization` abgelehnt statt ignoriert ([Resource Indicators]({{< relref "/authn-bridge/resources.md" >}})) |
| v0.23.0 | `access_token_groups = false`: ein Client, dessen Tokens in ssh eingefügt werden, trägt keine Gruppen ([Tokens]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})) |
| v0.23.1 | nur Abhängigkeiten: go-jose/v4 v4.1.6, golang.org/x/crypto v0.58.0, golang.org/x/net v0.61.0; go-authn/directory v0.12.0, revocation v0.6.3, saml v0.4.1, servercert v0.5.1, sshcert v0.1.6 |
| v0.23.2 | Sicherheit: go-authn/oidc v0.4.2, das ein `nbf` außerhalb des int64-Bereichs ablehnt (ein noch nicht gültiges Token wurde akzeptiert) und einen RSA-Schlüssel mit `e = 0` (er wurde geparst); go-authn/wireguard v0.1.2 |
| v0.23.3 | mit Go 1.27.3 gebaut, wegen GO-2026-6809 (`crypto/x509`: `Certificate.Verify` wies bekannte kompromittierte Zwischenzertifikate nicht zurück); die `go`-Direktive ist 1.27.3; keine Verhaltensänderung |
| v0.23.4 | Release-Binaries werden mit `-w` statt `-s -w` gelinkt, die Symboltabelle bleibt also für ein genaues `govulncheck -mode binary` erhalten; keine Verhaltensänderung |
| v0.23.6 | ein Audit-, Fuzzing- und Chaos-Durchgang, mit go-authn/saml v0.5.1; kein Konfigurationsschlüssel hinzugefügt oder geändert. [Metadaten werden rechtzeitig aktualisiert]({{< relref "/authn-bridge/federation.md#refreshing-it" >}}): nie über die Hälfte des verbleibenden `validUntil` hinaus geplant, und ohne gültige Metadaten nach einer Minute wiederholt, im doppelten Abstand bis zu einer Stunde, sodass eine fehlgeschlagene Aktualisierung kurz vor dem Ablauf den Anbieter nicht mehr bis zu zwölf Stunden ohne IdP lässt. Der Replay-Schlüssel der Assertion wird als SHA-256 gespeichert: Eine lange `entityID` eines IdP ließ PostgreSQL und MySQL den Schreibvorgang ablehnen und blockierte die Zustandsdatenbank. Die Uhr darf von der eines IdP um drei Minuten abweichen; eine Stunde wird mit einer 400-Seite abgelehnt. [Was getestet wird]({{< relref "/authn-bridge/federation.md#tested" >}}): XML Signature Wrapping XSW1 bis XSW8, CVE-2017-11427, DOCTYPE, fremde Audience, Empfänger, Anfrage und Ziel, fünf Fuzzer. Ein SHA-256 pro Anmeldung kostet 0 bis 2 Allokationen mehr (`BenchmarkReplayUse`: 0 Allokationen und 183 B, jetzt 2 und 326 B); Wanduhrzeit nicht gemessen, Last 53 bis 75 |

### authn-revokd {#authn-revokd}

| | |
|---|---|
| v0.1.0 | signierte, ablaufende Sperrlisten: das Protokoll, die Bibliothek und revokd (Agent und Spiegel) |
| v0.2.0 | die Korrekturen eines adversarialen Reviews |
| v0.2.1 | die Liste jeder CA mit ihren eigenen Schlüsselwiderrufen zusammengeführt; die Signatur einer CRL wird geprüft, bevor sie geparst wird |
| v0.3.0 | Schlüsselwiderrufe mit Geltungsbereich; geschlossenes Fehlschlagen pro CA; der Eigentümer des Zustandsverzeichnisses wird geprüft |
| v0.5.0 | Release-Binaries, `SHA256SUMS` und Build-Provenienz bei jedem Tag |
| v0.6.0 | der Befehl heißt `authn-revokd`; systemd-Units und eine Installationsanleitung; `SIGHUP` synchronisiert sofort |
| v0.6.1 | `-version` gibt auf der Standardausgabe aus |
| v0.6.2 | `-once` unterscheidet einen fehlgeschlagenen Abruf von einer verfallenen Liste; eine von einem anderen Schlüssel signierte Liste wird nicht mehr als Race bezeichnet; `-help` endet mit 0 |
| v0.6.3 | Platzhalter-Domains mit Namen nach RFC 2606, in den Beispielen und der Dokumentation; keine Verhaltensänderung |
| v0.6.4 | nur Abhängigkeiten: golang.org/x/crypto v0.58.0 |
| v0.6.5 | mit Go 1.27.3 gebaut, wegen GO-2026-6809 (`crypto/x509`: `Certificate.Verify` wies bekannte kompromittierte Zwischenzertifikate nicht zurück); die `go`-Direktive ist 1.27.3; keine Verhaltensänderung |
| v0.6.6 | Release-Binaries werden mit `-w` statt `-s -w` gelinkt, die Symboltabelle bleibt also für ein genaues `govulncheck -mode binary` erhalten; keine Verhaltensänderung |
| v0.6.7 | ein Audit-, Fuzzing-, Chaos- und Performance-Durchgang ([was ein Sync tut]({{< relref "/authn-revokd/configuration.md#sync" >}})). Eine Liste, die abläuft, wird abgelehnt, wenn sie abläuft, nicht bei der nächsten Aktualisierung; Quellen werden parallel abgerufen (höchstens 16, je zwei Minuten); `on_change` wird nach einer Minute beendet und wiederholt; eine hinter dem Rücken des Agenten geänderte Ausgabedatei wird beim nächsten Sync neu geschrieben; eine `file://`-Quelle muss eine reguläre Datei sein; ein Fehler zeigt eine URL ohne Passwort, Query und Fragment; eine CRL-Nummer außerhalb von `0..2^159` wird abgelehnt; der Spiegel hat Lese-, Schreib- und Leerlauf-Fristen; veraltete temporäre Dateien werden beim Start entfernt. Eine CRL mit 100.000 Einträgen erneut abgefragt: 300.138 Allokationen und 96.956.946 B pro Abfrage, jetzt 37 und 4.776.864 B (exakt; Zeiten nicht gemessen, Last 53 bis 65). govulncheck listet weiterhin GO-2026-5932 (`golang.org/x/crypto/openpgp`), das keine korrigierte Version hat und nicht aufgerufen wird |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | die Domain-Grant-Erweiterung und ein fail-closed `sshcert-authorize` |
| v0.1.2 | Release-Binaries, `SHA256SUMS` und Build-Provenienz bei jedem Tag |
| v0.1.4 | das Release prüft die Build-Informationen jedes Binarys |
| v0.1.5 | `-version` gibt die Modulversion eines mit `go install` erstellten Builds aus, nicht `dev` |
| v0.1.6 | Platzhalter-Domains mit Namen nach RFC 2606, in der Dokumentation; keine Verhaltensänderung |
| v0.1.7 | nur Abhängigkeiten: golang.org/x/crypto v0.58.0 |
| v0.1.8 | Release-Binaries werden mit `-w` statt `-s -w` gelinkt, die Symboltabelle bleibt also für ein genaues `govulncheck -mode binary` erhalten; keine Verhaltensänderung |
| v0.1.9 | mit Go 1.27.3 gebaut; keine Verhaltensänderung |

### Die Bibliotheken {#the-libraries}

Die Bibliotheks-Releases, für die diese Dokumentationsversion erstellt wurde; die Seite
jeder Bibliothek sagt, was frühere geändert haben.

| | |
|---|---|
| directory v0.13.0 | [Attribute]({{< relref "/libraries/directory.md#attributes" >}}): was jemanden beschreibt und nichts beweist, getrennt von Anmeldedaten, mit den Namen, die nie eines sein können; `attributes` in `user`- und `group`-Blöcken, die Abfragen `users_attributes` und `groups_attributes`, `attributes` und `group_attributes` von ldapdir |
| directory v0.14.0 | ⛔ die [Standardwerte]({{< relref "/libraries/directory.md#ldapdir-defaults" >}}) von ldapdir lesen Personen mit `account` und `uidObject` und Gruppen mit `groupOfNames`, was erweitert, was das Verzeichnis einer Einrichtung liefert; ein `member`-DN wird nur auf eine Person abgebildet, die die Quelle importiert hat |
| directory v0.15.0 | [Objektklassen]({{< relref "/libraries/directory.md#object-classes" >}}), deklariert und nie abgeleitet: `object_classes` und `group_object_classes` in `users`-Blöcken, `object_classes` in `user`- und `group`-Blöcken, `WithObjectClasses` für sqldir und `Config.ObjectClasses` für ldapdir; die erste Quelle, die die Klassen einer Gruppe deklariert, entscheidet; `sqldir.ClosesDB` |
| directory v0.16.0 | [jede Gruppe einmal gelesen]({{< relref "/libraries/directory.md" >}}): `GroupReader` und `Set.Frozen`, sodass eine Aktualisierung nicht mehr mit Gruppen mal Mitgliedschaftszeilen wächst |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}}), mit `AsUnavailable` und `TransportFailure`: ldapdir gibt ihn zurück für busy (51), unavailable (52), other (80), timeLimitExceeded (3), abgebrochene oder abgelehnte Verbindungen und Verbindungs- oder TLS-Fehler, bei `Verify` und jedem Lesen; er ist nie zugleich `ErrWrongPassword`, und `invalidCredentials` (49) bleibt dieser. `ldaptest.Server.FailBindsWith(code)`. Ein Member-DN wird einer Person mit einem Nachschlagen statt eines Durchlaufs zugeordnet, mit denselben Ergebnissen: `ReadGroups` bei 10.000 Personen und 2.000 Gruppen mit je 50 DNs alloziert 13,1 MB in 0,38 Mio. Objekten statt 50,6 MB in 2,20 Mio., ein DN-Nachschlagen 0 Allokationen; die gesamte Aktualisierung 7,17 Mio. Allokationen statt 9,72 Mio. (exakt; Zeiten nicht gemessen, Last 65 bis 105) |
| kdc v0.4.3 | nur Abhängigkeiten: go-authn/directory v0.12.0 als Mindestversion |
| kdc v0.4.5 | ein Sicherheitsaudit-, Fuzzing- und Chaos-Durchgang ([was es ablehnt]({{< relref "/libraries/kdc.md" >}})): eine Anfrage für einen anderen Realm wird mit `KDC_ERR_WRONG_REALM` beantwortet, ein nicht lesbares Verzeichnis mit `KDC_ERR_SVC_UNAVAILABLE` (es war `KDC_ERR_C_PRINCIPAL_UNKNOWN`), ein TGT, dessen Beginn innerhalb von `MaxSkew` in der Zukunft liegt, wird akzeptiert, und eine Panik des Decoders verwirft eine Anfrage, statt den Prozess abstürzen zu lassen (eine einzige fehlerhafte AS-REQ oder TGS-REQ konnte ihn abstürzen lassen); Principal-Namen werden im Log in Anführungszeichen gesetzt. golang.org/x/net v0.62.0, go-authn/directory v0.16.1 |
| keyfactor v0.4.2 | nur Abhängigkeiten: go-authn/fido v0.6.2 und golang.org/x/crypto v0.58.0 als Mindestversionen |
| krb5 v0.3.1 | mit Go 1.27.2 getestet; weder der Code noch `go.mod` haben sich geändert |
| krb5 v0.3.3 | nur Abhängigkeiten: golang.org/x/net v0.62.0, golang.org/x/crypto v0.58.0 und go-uuid v1.0.4 beseitigen 45 von 46 `govulncheck`-Funden in verlangten, aber nicht aufgerufenen Modulen; GO-2026-5932 (`x/crypto/openpgp`) hat keine Korrektur und wird von keinem go-authn-Modul importiert; keine API-Änderung |
| krl v0.6.1 | nur Abhängigkeiten: golang.org/x/crypto v0.58.0; mit Go 1.27.2 getestet |
| ldap v0.8.0 | [Paket `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) und `Server.Schema`: `cn=Subschema` (RFC 4512 §4.2), `Validate`, Matching-Regeln nach RFC 4517; `uidNumber` und `gidNumber` werden als Ganzzahlen geordnet; eine seitenweise Suche hält sich an die angeforderten Attribute |
| ldap v0.9.0 | [Schemas in HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): das Paket `schema/hclschema` und der Befehl `ldapschema` (`to-hcl`, `to-schema`, `check`) zwischen OpenLDAP-`.schema`, cn=config-LDIF und HCL2; die Leser lesen Dateien wie slapd; DIT-Content-Regeln, DIT-Structure-Regeln, Name Forms, `include` und `X-SUBST` werden nicht unterstützt (v0.11.0 unterstützt die Regeln) |
| ldap v0.10.0 | [ein typisierter `*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}) für eine Definition, die `Build` ablehnt, mit `errors.As` abgeglichen: `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos` (Datei:Zeile:Spalte, an der die Definition beginnt, auch für umgebrochenes oder base64-kodiertes LDIF und HCL) sowie `Ref`, `RefOID` und `RefPos` für die andere Definition; jede gelesene Definition trägt eine `Pos`; „object classes“ in einer Meldung |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) ist linear in der Zahl der Fortsetzungszeilen (es war quadratisch: eine Datei von 4 MiB brauchte etwa drei Minuten) und kopiert und zerlegt nicht mehr die ganze Datei, um ihre erste Zeile zu lesen; `schema.Format` bricht Zeilen über 2000 Bytes um, die slapd und `Read` ablehnen; der strikte Parser ist etwa 2,6-mal schneller (147 statt 498 Allokationen bei `cosine.schema`, unter Last gemessen) |
| ldap v0.10.2 | die DESC-Werte von 13 RFC-2307-Definitionen im eingebetteten Schema (`schema.Standard()`) stehen in einer Zeile: sie trugen die Einrückung des RFC-Seitenumbruchs, die der Leser wie slapd innerhalb der Anführungszeichen behält, sodass das von einem Server veröffentlichte Subschema Folgen von Leerzeichen enthielt; ein Test prüft jetzt jeden eingebetteten DESC darauf und, wo dieselbe OID definiert ist, gegen die Schemas `core`, `cosine`, `inetorgperson` und `nis` von OpenLDAP |
| ldap v0.11.0 | [DIT-Content-Rules, Name Forms und DIT-Structure-Rules]({{< relref "/libraries/ldap.md#rules" >}}) (RFC 4512 §4.1.6, §4.1.7) aus `.schema` und LDIF gelesen, von `Format` geschrieben, über HCL (`dit_content_rule`, `name_form`, `dit_structure_rule`) und `ldapschema` weitergereicht, von `Build` geprüft, von `Validate` durchgesetzt (Content-Rules: AUX, MUST, MAY, NOT; Name Forms: das RDN; Structure-Rules: `GoverningStructureRule`) und nur bei Vorhandensein unter `cn=Subschema` veröffentlicht; `ValidateOptions{StrictAuxiliary}` liefert RFC 4512 §2.4.3. ⛔ slapd implementiert nur Content-Rules, daher schreibt `Format` die Schlüsselwörter `nameform` und `ditstructurerule`, die es ablehnt; eine `OBSOLETE`-Regel ist inaktiv, wo slapd den Eintrag ablehnt; libldap kann das `SUP` einer Structure-Rule nicht lesen. `hclschema.Decode` lehnt einen String ab, der kein UTF-8 ist |
| ldap v0.11.1 | Nur Leistung, kein geändertes Ergebnis: Ein String aus druckbarem ASCII wird für die String-Vergleichsregeln (RFC 4518) mit höchstens einer Allokation aufbereitet, ohne eine, wenn sich nichts ändert, und der DN-Parser macht für einen DN mit vier RDNs 6 statt 11 Allokationen. Die Ergebnisse sind die von v0.11.0, gegen dessen Code an jedem String aus einem oder zwei Bytes unter 0x80 und mit einem differenziellen Fuzzer geprüft |
| ldap v0.11.2 | Nur Leistung, kein geändertes Ergebnis: `Validate` macht für einen Eintrag mit zehn Attributen 12 statt 76 Allokationen (Nachschlagen ohne Kleinbuchstaben-Kopie, Beschreibungen nicht zerlegt und wieder zusammengesetzt, Mengen an Ort und Stelle statt Maps). Die Ergebnisse sind die von v0.11.1, gegen eine Kopie von dessen `Validate` an Zufallseinträgen unter dem Standardschema und einem Regelschema und mit einem differenziellen Fuzzer geprüft |
| ldap v0.11.3 | Nur Leistung, kein geändertes Ergebnis: `GoverningStructureRule` macht für ein Konto 5 statt 12 Allokationen (es liest nur die Typen des RDN), und der DN-Parser 3 statt 6 für einen DN mit vier RDNs. Die Ergebnisse sind die von v0.11.2, gegen eine Kopie von dessen `GoverningStructureRule` an Zufallseinträgen und jeder übergeordneten Regel und mit einem differenziellen Fuzzer geprüft |
| ldap v0.12.0 | [Ressourcengrenzen für den Server]({{< relref "/libraries/ldap.md" >}}): `Server.MaxConnections` und `Server.MaxConnectionsPerIP` (Standard 0, keine Grenze; eine Verbindung über einer Grenze erhält eine Notice of Disconnection `busy` (51), RFC 4511 4.4.1, und wird geschlossen); `Server.Timeout` wird vom Server durchgesetzt, der zur Frist bei jeder Operation `timeLimitExceeded` (3) antwortet, auch wenn der Handler blockiert ist und seinen Kontext ignoriert (das späte Ergebnis wird verworfen, und die Goroutine zählt gegen `MaxPending` und `MaxPendingAuth`, bis sie zurückkehrt); das `timeLimit` der Client-Suche gilt für den Kontext des Handlers; ein `DeadlineExceeded` eines Handlers wird nur dann auf Code 3 abgebildet, wenn der eigene Kontext der Operation abgelaufen ist. Allokationen pro Operation (exakt): 3 vorher und nachher ohne `Timeout`; 10 vorher und 16 jetzt mit einem |
| oidc v0.4.1 | mit Go 1.27.2 getestet; weder der Code noch `go.mod` haben sich geändert |
| scim v0.2.0 | [ein Audit-, Fuzzing-, Chaos- und Performance-Durchgang]({{< relref "/libraries/scim.md#v020" >}}): `Server.ReadTimeout` (30 s), die optionale Schnittstelle `ConditionalDeleter`, ein PATCH oder PUT ohne `If-Match` wird nach einem verlorenen Rennen bis zu 32-mal wiederholt statt mit 412 beantwortet, das Entfernen über einen Filter, der nichts trifft, gelingt, die Schlüssel eines PATCH ohne Pfad werden in sortierter Reihenfolge angewandt, `BearerAuth` akzeptiert das Schema in jeder Schreibweise, `startIndex` und `count` werden bei jeder Wortbreite begrenzt. Eine Listenanfrage über 10.000 Benutzer: eine Seite mit 100 von 789.417 auf 14.952 Allokationen, `userName eq` von 797.979 auf 90, ein vollständiger Durchlauf von 818.847 auf 361.098 (exakt; Zeiten nicht gemessen, Last 65) |
| servercert v0.5.2 | mit Go 1.27.2 getestet; weder der Code noch `go.mod` haben sich geändert |
| totp v0.4.2 | mit Go 1.27.2 getestet; weder der Code noch `go.mod` haben sich geändert |
| wireguard v0.1.1 | mit Go 1.27.2 getestet; weder der Code noch `go.mod` haben sich geändert |

## Noch nicht implementiert {#not-implemented-yet}

- **Schreibvorgänge über LDAP**, über das Ändern des eigenen Passworts durch eine
  Person hinaus. authnd beantwortet ein Modify des eigenen `userPassword` und die
  Password-Modify-Operation nach RFC 3062 (was `ldappasswd` sendet), beide nur mit
  dem aktuellen Passwort, und sonst nichts: Add, Delete und ModifyDN existieren in
  go-authn/ldap und sind bewusst nicht angebunden (`server.go`). Die Bibliothek
  führt ein Modify als geordnete Liste (RFC 4511 4.6) und beantwortet die Read
  Entry Controls (RFC 4527), die Form ist also vorhanden; was fehlt, ist die Regel,
  wer was schreiben darf.
- **Ein zweiter Faktor innerhalb von Kerberos**: OTP-Pre-Authentication (RFC 6560)
  in FAST (RFC 6113). Solange es sie nicht gibt, können ein `kerberos`-Block und ein
  `mfa`-Block nicht gemeinsam konfiguriert werden.
- **RC4-HMAC**: Der Realm stellt nur aes256-cts-hmac-sha1-96 aus, sodass einer Person,
  die nur über einen NT-Hash bekannt ist, kein Ticket ausgestellt werden kann. Das ist
  eine Entscheidung (RC4 ist durch RFC 8429 als veraltet eingestuft), keine Lücke,
  die darauf wartet, gefüllt zu werden.
