---
title: "Stand"
weight: 60
description: "Welche Releases diese Seiten beschreiben, was jedes Release hinzugefügt hat und was noch nicht implementiert ist."
tags: [stand, releases]
---

Diese Seiten sind die Dokumentationsversion **0.3** und beschreiben:

| Programm | Release | Modul |
|---|---|---|
| authnd | **v0.10.2** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.0** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.3** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.6** | `github.com/go-authn/sshcert` |

Die Versionen der Bibliotheken stehen auf [ihrer eigenen Seite]({{< relref "/libraries/_index.md" >}});
directory ist bei **v0.12.0**: `Members` antwortet `[]` für eine leere Gruppe;
`Expand` lehnt sie mit `ErrEmptyGroup` ab.
Eine neue Minor-Version eines der obigen Programme ist eine neue Dokumentationsversion,
sodass die Seiten, die jemand unter `/docs/0.3/` findet, weiterhin beschreiben, was
installiert wurde; die der früheren Releases bleiben unter `/docs/0.1/` und
`/docs/0.2/`.

## Was jedes Release hinzugefügt hat {#what-each-release-added}

Jede Zeile ist die Änderung, für die ein Release erstellt wurde. Releases, die nur
Abhängigkeiten aktualisiert haben, sind weggelassen.

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

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | die Domain-Grant-Erweiterung und ein fail-closed `sshcert-authorize` |
| v0.1.2 | Release-Binaries, `SHA256SUMS` und Build-Provenienz bei jedem Tag |
| v0.1.4 | das Release prüft die Build-Informationen jedes Binarys |
| v0.1.5 | `-version` gibt die Modulversion eines mit `go install` erstellten Builds aus, nicht `dev` |
| v0.1.6 | Platzhalter-Domains mit Namen nach RFC 2606, in der Dokumentation; keine Verhaltensänderung |

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
