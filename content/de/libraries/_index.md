---
title: "Die Bibliotheken, je eine Frage"
linkTitle: "Bibliotheken"
weight: 50
description: "Die vierzehn Go-Module von go-authn: die Frage, die jedes beantwortet, die Version, die diese Seiten beschreiben, und warum sie getrennte Module sind."
tags: [bibliotheken]
---

Programme wie [authnd]({{< relref "/authnd/_index.md" >}}) und
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) sind aus
Modulen gebaut, die eigenständig veröffentlicht, versioniert und getestet werden. Jedes beantwortet
**eine** Frage, und ein Programm importiert diejenigen, deren Fragen es stellt.

Alle sind reines Go und bauen mit `CGO_ENABLED=0`.

| Modul | die Frage, die es beantwortet | diese Seiten beschreiben | Importpfad |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | Haben genug Faktoren geantwortet, von genug Arten, und welche? | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | Stimmt dieser sechsstellige Code, und wurde er schon einmal verwendet? | v0.4.2 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | Wie spricht man mit einem Sicherheitsschlüssel, über 64-Byte-Reports? | v0.6.2 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | Hat *der registrierte* Schlüssel geantwortet, und hat eine Person ihn berührt? | v0.4.2 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | Wer ist jemand, und was kann das beweisen? | v0.15.0 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | Was sind die Bytes eines LDAP-Servers? | v0.11.1 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | Taugt dieses Kerberos-Ticket für diesen Dienst? | v0.3.1 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | Wie stellt ein Realm Tickets aus einem Verzeichnis aus? | v0.4.3 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | Wer fragt laut diesem Bearer-Token, und sollte man ihm glauben? | v0.4.1 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | Was hat der Identitätsanbieter einer Föderation über diese Person gesagt? | v0.4.1 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | Ist dieses SSH-Zertifikat oder dieser Schlüssel widerrufen, so wie sshd antworten würde? | v0.6.1 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | Woher kommt das TLS-Serverzertifikat eines Daemons? | v0.5.2 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | Darf dieser WireGuard-Schlüssel sich verbinden, und wem gehört er? | v0.1.1 | `github.com/go-authn/wireguard` |
| [scim]({{< relref "/libraries/scim.md" >}}) | Wen hat der Identitätsanbieter gerade angelegt, geändert oder gelöscht? | v0.1.0 | `github.com/go-authn/scim` |

## Wie sie sich gruppieren {#how-they-group}

**Faktoren** – ob eine Person anwesend ist.
[mfa]({{< relref "/libraries/mfa.md" >}}) entscheidet, wie viel Nachweis genug ist, und
kennt kein Gerät. [totp]({{< relref "/libraries/totp.md" >}}) ist ein
Faktor: ein Code von einem Telefon. [fido]({{< relref "/libraries/fido.md" >}}) spricht
CTAP mit einem Sicherheitsschlüssel und kennt keine Richtlinie;
[keyfactor]({{< relref "/libraries/keyfactor.md" >}}) ist das eine Stück, das
beide importiert und aus einem Schlüssel einen Faktor macht.

**Das Verzeichnis und sein Protokoll.**
[directory]({{< relref "/libraries/directory.md" >}}) ist das Modell: eine Person
und welche Anmeldedaten eine Quelle für sie hält – ein Passwort, ein NT-Hash, ein
Verifier, SSH-Schlüssel, ein Geheimnis für Einmalcodes – und, getrennt davon, die
Attribute, die sie beschreiben und nichts beweisen.
[ldap]({{< relref "/libraries/ldap.md" >}}) ist das LDAP-Leitungsprotokoll, als
Server, und das Verzeichnisschema, gegen das ein Eintrag geprüft werden kann, gelesen aus
OpenLDAP-Dateien oder in HCL2 geschrieben; was es antwortet, ist Sache des
Handlers.

**Kerberos, in zwei Hälften.** [krb5]({{< relref "/libraries/krb5.md" >}})
*nimmt* Tickets *an*: eine Keytab, ein AP-REQ herein, ein AP-REP hinaus.
[kdc]({{< relref "/libraries/kdc.md" >}}) *stellt* sie *aus*, aus einem Verzeichnis, das
Passwörter hält.

**Föderation und Tokens.** [saml]({{< relref "/libraries/saml.md" >}}) ist ein
SAML-2.0-Service-Provider vor einer Föderation wie RENATER oder eduGAIN.
[oidc]({{< relref "/libraries/oidc.md" >}}) prüft die OpenID-Connect-Tokens,
die ein Anbieter signiert – die Hälfte des Resource-Servers, ohne Anmeldeablauf.
[scim]({{< relref "/libraries/scim.md" >}}) geht in die andere Richtung: der
SCIM-2.0-Endpunkt, den ein Identitätsanbieter aufruft, um die Personen und
Gruppen Ihrer Anwendung anzulegen, zu aktualisieren und zu löschen.

**Widerruf und Zertifikate.** [krl]({{< relref "/libraries/krl.md" >}})
liest, schreibt und prüft OpenSSH-Sperrlisten für Schlüssel.
[servercert]({{< relref "/libraries/servercert.md" >}}) gibt einem Daemon sein TLS-Zertifikat,
aus Dateien oder über ACME.

**[wireguard]({{< relref "/libraries/wireguard.md" >}})** überträgt die signierte
Liste der öffentlichen WireGuard-Schlüssel, die Personen bei einem Anbieter registriert haben und die ein
Gateway in Peers umwandelt.

## Warum sie getrennte Module sind {#why-they-are-separate-modules}

**Ein Dienst, der nur Tickets annimmt, bindet nie einen KDC ein.** Ein NFS-Server
prüft die Tickets, die ein Client vorlegt; er hat eine Keytab und sonst nichts mit
einem Realm zu tun. Wären Annehmen und Ausstellen ein Modul, trüge jeder solche Server
einen Codepfad zum Ausstellen von Tickets mit sich, den er nie ausführt, und das Verzeichnismodul,
aus dem ein KDC Personen liest und das er nie benutzt.

Das ist gemessen, nicht beabsichtigt. In einem Wegwerfmodul, das nur
`github.com/go-authn/krb5@v0.3.1` importiert:

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.1
```

Derselbe Befehl für ein Modul, das `github.com/go-authn/kdc@v0.4.3` importiert,
listet `github.com/go-authn/directory` und `github.com/go-authn/kdc` auf: Das Ausstellen
braucht die Personen, das Annehmen nicht.

Dieselbe Regel gilt auch anderswo. `mfa` importiert nichts außerhalb der Standardbibliothek,
und `fido` importiert `mfa` nicht: Ein Programm, das nur einen
Schlüssel blinken lassen will, trägt kein Richtlinienpaket mit sich. `totp` hängt nur von `mfa` ab, und
`oidc` hat überhaupt keine Abhängigkeit. `directory` hält seine LDAP-, SQL- und HCL-Quellen
in Unterpaketen: Das Kernpaket importiert nichts außerhalb der Standardbibliothek,
und `sqldir` nimmt eine `*sql.DB`, sodass der Datenbanktreiber die Wahl des
Programms ist.

## Jede Seite hat dieselben Teile {#every-page-has-the-same-parts}

Die Frage; die `go get`-Zeile für die beschriebene Version; ein minimales Beispiel,
das gegen diese Version kompiliert; was das Modul ablehnt, aus seinem Code;
und wogegen es geprüft wird – die Implementierung, die nicht diese ist,
benannt in seiner CI oder seinen Tests. Wo eine README und der Code sich widersprechen, folgt die Seite
dem Code.
