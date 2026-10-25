---
title: "go-authn"
linkTitle: "Startseite"
type: docs
cascade:
  type: docs
description: "Authentifizierung in reinem Go: die Faktoren, die belegen, dass jemand anwesend ist, ein Verzeichnis, das sagt, wer jemand ist, beide Hälften von Kerberos und ein OpenID-Connect-Anbieter vor einer SAML-Föderation."
---

**Zwei Fragen, und sie sind nicht dieselbe.** *Ist diese Person hier, jetzt?* ist
nicht *Wer ist diese Person, und was würde es belegen?* go-authn beantwortet beide:
die Faktoren, die Anwesenheit belegen, ein Verzeichnis, das festhält, was jede
Person **belegt**, statt eines Passwortfelds, beide Hälften von Kerberos und einen
OpenID-Connect-Anbieter vor einer SAML-Föderation. Reines Go, `CGO_ENABLED=0`.
Diese Seiten beschreiben die Releases, die auf der [Seite „Stand“]({{< relref "/status.md" >}}) aufgeführt sind.

## Vier Programme {#four-programs}

| | was es ist | diese Seiten beschreiben |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | ein LDAP-Server, und optional ein Kerberos-Realm, für Personen, die anderswo geführt werden: in einer Datei, einer SQL-Datenbank, einem anderen Verzeichnis | v0.12.0 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | ein OpenID-Connect-Anbieter vor einer SAML-Föderation (RENATER, eduGAIN), der außerdem SSH-Zertifikate ausstellt und die Listen signiert, die sie widerrufen | v0.23.3 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | ruft diese Listen ab, prüft jede, bevor ein Server sie liest, und schlägt geschlossen fehl (fail closed), wenn eine verfällt | v0.6.5 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`, das sshd fragt, ob der Domain-Grant eines Zertifikats diesen Host nennt | v0.1.7 |

Jedes ist ein statisches Binary für Linux, macOS und Windows auf amd64 und arm64,
veröffentlicht mit `SHA256SUMS` und Build-Provenienz:
[einen Download prüfen]({{< relref "/security/verifying-releases.md" >}}).

```sh
go install github.com/go-authn/authnd@v0.12.0
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.5
```

Die Befehle heißen `authn-*` (und `authnd`), weil sie auf Maschinen installiert
werden, auf denen noch anderes läuft: Ein bloßes `bridge` oder `revokd` in `/usr/bin`
würde einen Namen belegen, den jemand anderes brauchen könnte.

## Und die Bibliotheken darunter {#and-the-libraries-under-them}

Die Programme sind schlank. Was sie tun, steckt in
[vierzehn Modulen]({{< relref "/libraries/_index.md" >}}), eines pro Frage, sodass
ein Dienst, der Kerberos-Tickets nur *annimmt*, nie einen KDC einbindet, und einer,
der nur einen Einmalcode prüft, nie ein Verzeichnis.

## Warum das Verzeichnis festhält, was jemanden belegt {#why-the-directory-carries-what-proves-somebody}

SMB braucht einen NT-Hash; S3 braucht das Passwort selbst, weil SigV4 daraus einen
HMAC berechnet; ein Kerberos-Realm braucht einen aus dem Passwort abgeleiteten
Schlüssel, und ein NT-Hash ist nicht dieser Schlüssel. Eine Identität, die nur eines
davon hält, kann manche Protokolle bedienen und andere nie, was auch immer die Person
eintippt. Deshalb hält das Verzeichnis von go-authn fest, **was jede Person belegen
kann**, und `authnd check` gibt aus, bevor irgendetwas neu gestartet wird, wem ein
Kerberos-Ticket ausgestellt werden kann und wem nie:

```
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

Das ist die eigene Ausgabe von authnd v0.11.0: [die vollständige]({{< relref "/authnd/check.md" >}}).

## Geprüft mit den Werkzeugen anderer {#judged-by-other-peoples-tools}

Eine Testumgebung, die aus einer einzigen Lesart eines Protokolls gebaut ist, kann nur
diese Lesart bestätigen. Deshalb werden die Server von Clients gelesen, die sie nicht
geschrieben haben: OpenLDAPs eigenes `ldapsearch` bindet sich an authnd, MITs eigenes
`kinit` bezieht Tickets aus seinem Realm, und OpenSSH liest die Zertifikate und KRLs,
die authn-bridge ausstellt.
