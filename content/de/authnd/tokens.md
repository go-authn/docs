---
title: "Ein Token beim Bind, in einem Feld, das nicht das Passwort ist"
linkTitle: "Tokens (OIDC)"
weight: 75
description: "Der oidc-Block: ein OpenID-Connect-Token in einem SASL-OAUTHBEARER-Bind, für wie viele Faktoren es zählt und was abgelehnt wird."
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}}) prüft ein Token und macht daraus eine
Identität. Der naheliegende Weg, eines zu einem LDAP-Server zu tragen, ist das Passwortfeld,
und das funktioniert einmal und dann nicht mehr: Im Passwortfeld nimmt der
[`mfa`-Block]({{< relref "/authnd/mfa.md" >}}) den Code vom Ende ab, und
ein Token kann nicht beides sein.

Also geht das Token dorthin, wo das Protokoll einen Platz dafür hat. Die Zugangsdaten eines
**SASL**-Binds sind ein Oktett-String in der eigenen Form des Mechanismus, und die
`OAUTHBEARER`-Form aus RFC 7628 ist ein GS2-Header, gefolgt von Schlüssel-Wert-Paaren, von denen eines
`auth=Bearer <token>` ist:

```
n,,^Aauth=Bearer eyJ…^A^A
```

Das Passwortfeld bleibt unberührt. Auf einem einzigen Listener kann zur selben Zeit eine
Person ein Passwort mit einem Code am Ende eingeben und eine andere ein
Token senden.

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer` und `audience` sind Pflicht. Ohne `username_claim` ist der Name
`preferred_username`, dann `email`, wenn `email_verified` wahr ist, dann `sub`.
Mit dem Block kündigt das Root-DSE den Mechanismus an:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

Ohne ihn wird jeder SASL-Bind mit `authMethodNotSupported` beantwortet – *nicht auf
diesem Weg*, was einen Client anderswohin schickt als *falsches Passwort*.

## Die Discovery findet beim Start statt {#discovery-happens-at-startup}

Das Discovery-Dokument und die Schlüssel des Anbieters werden gelesen, wenn der Server startet,
und von `check`. Ein Anbieter, der nicht erreichbar ist, hält den Server dort an, wo
jemand zusieht, statt später jeden Bind abzulehnen:

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

Ein Aussteller, der nicht `https` ist, wird abgelehnt, außer auf Loopback:

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## Wie viele Faktoren ist ein Token? {#how-many-factors-is-a-token}

**So viele, wie der Aussteller nach eigener Aussage geprüft hat, und nicht mehr.** Ein Token trägt
`amr` aus RFC 8176, die Methoden, die der Anbieter verwendet hat. Das ist der einzige Beleg,
den es gibt; also zählt die `mfa`-Richtlinie genau ihn, **nach Art**:

| `amr`-Methode | Art |
|---|---|
| `pwd`, `pin`, `kba`, `mca` | Wissen |
| `otp`, `hwk`, `swk`, `sms`, `tel`, `sc`, `pop`, `user`, `wia`, `mfa` | Besitz |
| `fpt`, `face`, `iris`, `retina`, `vbm`, `geo` | Inhärenz |
| alles andere | unbekannt, was `distinct_kinds` nie erfüllt |
| überhaupt kein `amr` | ein Faktor, Besitz – das Token selbst |

Zwei Methoden einer Art sind ein Faktor. Die Alternative wäre, dass dieser Server
einen zweiten Faktor erfindet, den niemand erbracht hat; und ein Server, der dem
Aussteller glaubt, *wer* das ist, hat keinen eigenen Grund, ihm nicht zu glauben,
*wie* er es geprüft hat.

Mit einem `mfa`-Block sagt `check` es:

```
$ authnd check sasl
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
or a token from http://127.0.0.1:18481, over SASL OAUTHBEARER over TLS
  a token counts for the factors its amr claim names, so one with no amr is refused by this policy
alice has no second factor here, so a password cannot satisfy this policy; a token whose amr names two kinds still can
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

alice hat kein `totp_secret`, also kann ein Passwort mit Code für dieses Konto
nie genügen; ein Token, dessen `amr` zwei Arten nennt, kann es, wie der erste Bind unten
zeigt.

## Wie die Binds aussehen {#what-the-binds-look-like}

Der Aussteller ist hier ein kleiner Testanbieter auf Loopback, und `oidctool` ein Test-Client,
der für diese Seiten geschrieben wurde: Er signiert ein Token für den angegebenen Namen, mit
dem angegebenen `amr`, sendet es in einem `OAUTHBEARER`-Bind (mit einer `authzid`, wenn ein
fünftes Argument eine nennt) und gibt den Ergebniscode des Binds und die
SASL-Zugangsdaten des Servers aus. Gegen die Konfiguration oben, über `ldaps://`:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 0, serverSaslCreds 

$ ./oidctool alice '' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","kba"]' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls tess
bind result 14, serverSaslCreds {"status":"insufficient_scope","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}

$ ./oidctool zed '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 14, serverSaslCreds {"status":"invalid_token","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}
```

0 ist Erfolg, 49 `invalidCredentials`, 14 `saslBindInProgress`. Ein
`["pwd","kba"]`-Token nennt zwei Methoden einer Art, zählt also einmal. Und
gegen dieselbe Konfiguration ohne `cert_file` und `key_file`, auf einem Klartext-Listener:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13 ist `confidentialityRequired`: Über eine unverschlüsselte Verbindung wird kein
Token angenommen.

Was der Server für die vier abgelehnten Binds über `ldaps://` geschrieben hat:

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

und für den im Klartext:

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

Ein erfolgreicher `OAUTHBEARER`-Bind hinterlässt die Verbindung gebunden als
`uid=<name>,ou=people,<base_dn>`, so geschrieben wie jeder andere Eintrag.

## Was es ablehnt {#what-it-refuses}

- **Ein Token im Klartext.** Ein Bearer-Token braucht keine andere Hälfte: Wer es
  von der Leitung liest, ist diese Person, bis es abläuft. `allow_plaintext = true`
  gibt es für eine Installation, die TLS vor diesem Prozess terminiert, und
  `check` sagt dann *a token may cross this socket in the clear*.
- **Eine Anfrage, jemand anderes zu sein.** Der GS2-Header darf eine `authzid` nennen. Ein
  Token für alice, das die Anfrage trägt, als tess zu handeln, wird abgelehnt, nicht stillschweigend
  als das eine oder das andere behandelt.
- **Ein Token für jemanden, den keine Quelle hier veröffentlicht.** Der Client erfährt nur
  `invalid_token`; welche Namen es gibt, ist nichts, was man Rateversuch für Rateversuch
  herausgibt. Der Grund steht in der Ausgabe des Servers.
- **Channel Binding.** Ein GS2-Header mit `p=` – der Client besteht auf
  Channel Binding – wird abgelehnt: Dieser Server unterstützt es nicht, und den
  Header anzunehmen, während nichts gebunden wird, ließe den Client glauben, der Kanal sei
  geprüft worden.
- **Ein Mechanismus, den dieser Server nicht spricht**, mit `authMethodNotSupported`.

Eine Ablehnung des Tokens selbst ist die aus RFC 7628 §3.2.3: ein JSON-Fehler mit
`openid-configuration`, zurückgegeben als `saslBindInProgress`, damit der Client
das `^A` senden kann, das den Austausch beendet. Ein Token, das die Prüfung besteht, aber die
`mfa`-Richtlinie nicht erfüllt, wird schlicht mit `invalidCredentials` beantwortet, wie der
zweite und dritte Bind oben zeigen.

{{< callout type="info" >}}
**Ein Token setzt kein Passwort**

Eine Person, die sich bisher nur mit einem Token angemeldet hat, kann diese Sitzung nicht nutzen,
um sich ein erstes Passwort zu geben, und eine Person, die eines hat, muss es weiterhin senden,
um es zu ändern. Siehe [Passwort ändern]({{< relref "/authnd/passwords.md" >}}).
{{< /callout >}}
