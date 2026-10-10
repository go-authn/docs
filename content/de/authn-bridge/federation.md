---
title: "Die Föderationsseite"
linkTitle: "Die Föderationsseite"
weight: 30
description: "Wie authn-bridge die Metadaten einer SAML-Föderation liest, deren Signierer festlegt, jeden IdP an seine eigenen Scopes bindet und eine Assertion in Claims umwandelt."
tags: [authn-bridge, saml, renater, edugain]
---

Auf dieser Seite ist authn-bridge ein SAML-Service-Provider. Er wird einmal bei
der Föderation registriert (der Fédération Éducation-Recherche von RENATER oder eduGAIN) und
vertraut den **Metadaten** der Föderation: einem signierten Dokument, das jeden
Mitglieds-IdP, dessen Signaturschlüssel und die Domains auflistet, für die jeder bürgen darf. Der SAML-Code
ist [go-authn/saml]({{< relref "/libraries/_index.md" >}}).

```hcl
saml {
  key_file  = "/var/lib/authn-bridge/saml.key"   # RSA: IdPs encrypt assertions to it
  cert_file = "/var/lib/authn-bridge/saml.crt"

  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"

  discovery = "https://discovery.renater.fr/renater"   # or leave it out for this provider's own list
  # idps    = ["https://idp.univ-example.fr/idp/shibboleth"]   # restrict; one entry skips the choice

  names             = { fr = "Passerelle OIDC", en = "OIDC gateway" }
  technical_contact = "admin@example.org"
}
```

| Schlüssel | Standard | |
|---|---|---|
| `entity_id` | der Aussteller + `/saml` | der Name dieses Service-Providers in der Föderation |
| `key_file`, `cert_file` | | der RSA-Schlüssel und das Zertifikat des SP |
| `metadata_url` | | `https://`, `file://` für eine Kopie, die etwas anderes pflegt, oder `http://` nur auf Loopback |
| `metadata_cert_file`, `metadata_fingerprint` | | das Signaturzertifikat der Föderation und sein SHA-256-Fingerabdruck, beide erforderlich |
| `discovery` | die eigene Liste dieses Anbieters | ein externer Discovery-Dienst, zu dem Personen geschickt werden |
| `idps` | jeder IdP der Föderation | beschränkt die Anmeldung auf diese Entity-IDs |
| `names`, `descriptions`, `information_url`, `privacy_statement_url`, `technical_contact` | der Host des Ausstellers als Name | was in die SP-Metadaten kommt |

## Der Signierer der Metadaten ist festgelegt {#the-metadatas-signer-is-pinned}

Das Zertifikat, das die Metadaten signiert, ist eine Datei auf diesem Host, und sein SHA-256-Fingerabdruck
steht in der Konfiguration. Das Zertifikat wird **bei jedem Start** gegen den
Fingerabdruck geprüft, sodass eine auf der Festplatte ersetzte Datei bemerkt
statt ihr vertraut wird:

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

Ein Schlüssel, der über denselben Kanal ankommt wie das Dokument, für das er bürgt, bürgt
für nichts. Deshalb stammt der Fingerabdruck von der Webseite der Föderation, nie aus
dem Download, der das Zertifikat geliefert hat:

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## Ein Dokument wird abgelehnt {#a-document-is-refused}

- wenn es nicht von diesem Zertifikat signiert ist, mit SHA-1 signiert ist oder seine
  Signatur ein anderes Element als die Wurzel abdeckt;
- **wenn es kein `validUntil` hat oder dieses überschritten ist.** Dies sind die eigenen
  Metadaten von RENATER, wie sie am 29. September 2026 veröffentlicht wurden, gelesen am 10. Oktober:

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

- wenn sein `validUntil` mehr als 28 Tage entfernt liegt: Ein Dokument, das jahrelang gültig ist,
  ist eines, das eine Wiedereinspielung jahrelang am Leben hält;
- **wenn es älter ist als das verwendete** (ein früheres `validUntil`). Es ist
  gültig signiert und noch nicht abgelaufen, also würde nichts anderes es ablehnen, und es
  kann dasjenige mit einem inzwischen widerrufenen Schlüssel sein, ausgeliefert von wem auch immer auf dem Weg steht;
- über einfaches `http` an etwas anderes als Loopback. Die Signatur würde eine
  Änderung erkennen, aber keinen Proxy, der das neue Dokument zurückhält und weiterhin
  das alte ausliefert.

## Die Aktualisierung {#refreshing-it}

Die Metadaten werden abgerufen, bevor der Anbieter lauscht, dann erneut nach drei
Vierteln der `cacheDuration` des Dokuments, nie früher als nach fünf Minuten und nie
später als nach zwölf Stunden, und immer dann, wenn `RefreshMetadata` der Admin-API es verlangt.
Eine fehlgeschlagene Aktualisierung behält die letzte gute Kopie, **aber nur bis zu deren eigenem
`validUntil`**. Danach wird für nichts mehr gebürgt, jeder IdP verschwindet, und
`/readyz` meldet, dass der Anbieter nicht bereit ist. Ein kurzzeitig nicht erreichbarer
Föderationsserver meldet niemanden ab; einer, der tagelang nicht erreichbar ist, lässt den
Anbieter nicht veralteten Schlüsseln vertrauen.

Innerhalb des Dokuments wird ein IdP nur behalten, wenn er SAML 2.0 spricht und einen
HTTP-Redirect-`SingleSignOnService` veröffentlicht. Eine zweimal beschriebene Entität wird
ganz verworfen, da nichts sagt, welche Beschreibung stimmt, und das unlesbare Zertifikat
eines Mitglieds lässt dieses Mitglied aus, nicht die Föderation.

## Was jeder IdP sagen darf {#what-each-idp-may-say}

Eine Föderation hat Hunderte von Mitgliedern, und jedes von ihnen könnte sonst behaupten, es sei
`alice@another-university.fr`. Die Metadaten jedes Mitglieds listen dessen
`shibmd:Scope`s auf, die Domains, für die es bürgen darf; ein Scope als regulärer Ausdruck wird
ignoriert, nicht beachtet.

**Identifikatoren.** Ein Wert mit Scope (`subject-id`, `pairwise-id`,
`eduPersonPrincipalName`, `eduPersonScopedAffiliation`) außerhalb der Scopes des
behauptenden IdP wird **verworfen**, und ein Wert mit mehr als einem `@` liegt in keinem
Scope.

**Gruppen.** Wenn sich über mehr als einen IdP angemeldet werden darf, wird ein Wert von `eduPersonEntitlement`
oder `isMemberOf` nur behalten, wenn sein Namensraum einer der Scopes dieses IdP ist
oder darunter liegt:

| Wert | sein Namensraum |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...` (AARC-G002) | `<domain>` |
| `https://<host>/...` | `<host>` |
| alles andere | keiner: verworfen |

Gruppen entscheiden, was eine Person tun darf, auf jedem Ressourcenserver und in jedem
Zertifikat; deshalb wird ein Wert, den niemand zuordnen kann, nicht weitergegeben. Ein
Community-Proxy, der Gruppen für Personen vieler Einrichtungen behauptet, wird ausdrücklich
per Entity-ID benannt, mit den Präfixen, die er behaupten darf:

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

Mit genau einem IdP in `saml { idps }` wird diesem IdP für jeden Wert vertraut.

## Von einer Assertion zu Claims {#from-an-assertion-to-claims}

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid` und `mail` sind an keinen Scope gebunden, und `affiliation` (`staff`,
`student`) benennt keine Einrichtung. Daher verlangt jeder dieser Werte, dass `saml { idps }` genau
einen IdP auflistet; bei mehreren werden sie [beim Start abgelehnt]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}}).

**`sub`.** Der Identifikator dahinter wird in dieser Reihenfolge genommen: `subject-id`, dann
`pairwise-id`, dann `eduPersonPrincipalName`, dann `eduPersonTargetedID`, dann
eine persistente NameID, deren Qualifier der IdP selbst ist. Er wird mit der Entity-ID des
IdP qualifiziert, und `sub` ist ein HMAC-SHA256 davon unter dem Subject-Salt:
stabil, nicht umkehrbar, keine Adresse. `public` ist für jeden Client gleich,
`pairwise` unterscheidet sich je Client. Ein IdP, der keinen dieser Werte freigibt, wird abgelehnt,
da niemand ein zweites Mal wiedererkannt werden könnte. **Mail ist nie ein Identifikator**, und
es gibt kein `email_verified`: Dass ein IdP eine Adresse behauptet, heißt nicht, dass irgendjemand
geprüft hat, ob die Person sie liest.

**Was die Anfrage vom IdP verlangt.** `prompt=none` wird zu `IsPassive`, und
ein IdP ohne Sitzung antwortet mit `login_required`. `prompt=login` und `max_age=0`
werden zu `ForceAuthn`; bei jedem anderen `max_age` wird eine Person, deren IdP sie
vor längerer Zeit authentifiziert hat, mit `ForceAuthn` zurückgeschickt. `acr_values` wird zu
`RequestedAuthnContext`, und ein IdP, der mit einem anderen Kontext antwortet, wird
abgelehnt: Einem Client, der einen zweiten Faktor verlangt hat, wird nie gesagt, er habe einen bekommen,
wenn das nicht so ist.

## Die SP-Metadaten {#the-sp-metadata}

`authn-bridge metadata` gibt aus, was bei der Föderation zu registrieren ist, ohne
etwas abzurufen (das Zertifikat ist hier gekürzt):

```
$ authn-bridge metadata --config etc/bridge.hcl
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui" xmlns:idpdisc="urn:oasis:names:tc:SAML:profiles:SSO:idp-discovery-protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" entityID="http://127.0.0.1:18080/saml">
  <md:SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol" AuthnRequestsSigned="false" WantAssertionsSigned="true">
    <md:Extensions>
      <mdui:UIInfo>
        <mdui:DisplayName xml:lang="en">127.0.0.1:18080</mdui:DisplayName>
      </mdui:UIInfo>
    </md:Extensions>
    <md:KeyDescriptor>
      <ds:KeyInfo>
        <ds:X509Data>
          <ds:X509Certificate>MIID…</ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#aes128-gcm"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#aes256-gcm"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#rsa-oaep"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p"/>
    </md:KeyDescriptor>
    <md:AssertionConsumerService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="http://127.0.0.1:18080/saml/acs" index="0" isDefault="true"/>
    <md:AttributeConsumingService index="0">
      <md:ServiceName xml:lang="en">127.0.0.1:18080</md:ServiceName>
      <md:RequestedAttribute Name="urn:oasis:names:tc:SAML:attribute:subject-id" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.6" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:0.9.2342.19200300.100.1.3" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.16.840.1.113730.3.1.241" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.5.4.42" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.5.4.4" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.7" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
    </md:AttributeConsumingService>
  </md:SPSSODescriptor>
</md:EntityDescriptor>
```

Assertions müssen signiert sein (`WantAssertionsSigned="true"`) und werden
per HTTP-POST an `/saml/acs` zugestellt. Dasselbe Dokument wird unter `/saml/metadata` ausgeliefert.

## Was abgelehnt wird {#what-is-refused}

Am ACS alles, was go-authn/saml ablehnt: eine unsignierte oder SHA-1-Assertion,
mehrere Assertions, eine wiedereingespielte, ein Identifikator in einem fremden Scope. Dann die
eigenen Ablehnungen dieses Anbieters:

- eine IdP-Antwort, die **in einen anderen Browser** zugestellt wird: Die Anmeldung wird
  über ihr eigenes versiegeltes Cookie gefunden, nie über den `RelayState`, den die Antwort
  trägt, sonst könnte jeder eine andere Person unter der eigenen Identität anmelden;
- ein IdP, den die Konfiguration nicht mehr zulässt oder den die Admin-API
  deaktiviert hat;
- eine Person oder eine Einrichtung, die [hier deaktiviert]({{< relref "/authn-bridge/admin.md" >}}) ist,
  was auch immer die Einrichtung sagt.

Beim Start eine Liste von IdPs zusammen mit dem Discovery-Dienst von RENATER, der
sie alle auflistet und nicht eingeschränkt werden kann:

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```
