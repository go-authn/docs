---
title: "Ein zweiter Faktor, über ein Protokoll mit einem einzigen Feld"
linkTitle: "Zweiter Faktor"
weight: 70
description: "Der mfa-Block: ein Einmalcode am Ende des Passworts, wie er abgetrennt und geprüft wird, was wem angerechnet wird und wer sich darunter nicht binden kann."
tags: [authnd, mfa, totp]
---

Der Simple Bind von LDAP trägt einen Namen und ein Passwort und sonst nichts – keinen Platz
für einen Code, keinen Roundtrip, um nach einem zu fragen, und ein Client, der LDAP spricht,
wird keinen lernen. Also kommt der Code an das **Ende** des Passworts, so wie es Appliances
machen, die das tun, und so, wie Personen es bereits zu tippen gewohnt sind:

```
password:  hunter2314159
           ^^^^^^^ ^^^^^^
           password  the six digits on their phone
```

```hcl
mfa {
  factors        = 2
  distinct_kinds = true     # two things they KNOW are not two factors
  # digits = 6, period = 30 (seconds) and window = 1 are the defaults
}

user "tess" {
  password_file = "/etc/authnd/passwords/tess.pw"
  totp_secret   = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"   # ⛔ this IS the second factor
}
```

| Schlüssel | Standard | |
|---|---|---|
| `factors` | 2 | 1 wird abgelehnt (*a password and nothing else: remove the block, or ask for 2*); mehr als 2 wird abgelehnt, da ein Bind ein Passwort und einen Code trägt und nichts Drittes |
| `distinct_kinds` | `false` | die Faktoren müssen von verschiedener Art sein – das, was man unter „Zwei-Faktor“ normalerweise versteht |
| `digits` | 6 | 6 bis 10 (RFC 4226) |
| `period` | 30 | Sekunden, die ein Code gilt |
| `window` | 1 | Schritte vor und nach dem aktuellen Zeitpunkt, die akzeptiert werden, für abweichende Uhren. Jeder Schritt ist ein Schritt mehr Ratezeit für jemand anderen: Setzen Sie ihn bewusst |
| `readers` | `false` | ob auch [Reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) einen Code mitsenden. Ein Dienstkonto hat kein Telefon; eines, das einen hat, bekommt ein `totp_secret` in seinem `reader`-Block |

Das Geheimnis kann ebenso aus einer Datenbankspalte (der fünften) oder einem LDAP-Attribut
(`totp_attribute`) kommen; siehe [Personen]({{< relref "/authnd/people.md" >}}).
Ein `totp_secret` in einem `user`- oder `reader`-Block unter 128 Bit (RFC 4226 R6) hält den
Server an und nennt die Person, statt später jede ihrer Anmeldungen scheitern zu lassen:

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## Wer sich darunter nicht binden kann {#who-cannot-bind-under-it}

```
$ authnd check mfa
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
alice has no second factor here, and cannot bind while one is required
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Das ist die Frage, die Sie stellen sollten, bevor Sie den Block einschalten.

## Wie die Binds aussehen {#what-the-binds-look-like}

Dieselbe Konfiguration, bereitgestellt; der Code von tess wird im Moment des Binds aus dem
Geheimnis des Kontos berechnet:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.only
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
dn:uid=tess,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.badcode
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.code
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin
dn:cn=reader,dc=example,dc=org
```

`tess.only` ist das Passwort von tess ohne Code; `tess.both` das Passwort und der aktuelle
Code, zweimal gesendet; `tess.badcode` das Passwort und `000000`; `alice.code` das Passwort von
alice und sechs Ziffern. Dem Client wird eine einzige Sache gesagt – *invalid credentials* –,
gleich welche Hälfte falsch war: welche, ist eine Tatsache über das Konto, und sie jemandem zu
sagen, der nichts bewiesen hat, grenzt den nächsten Rateversuch ein. Die eigene Ausgabe des
Servers sagt, welche:

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## Was aus dem einen Feld folgt {#what-follows-from-the-one-field}

- **Die Trennung erfolgt nach Länge.** Die letzten `digits` Zeichen sind der Code. Ein
  Passwort, das auf Ziffern endet, ist kein Problem – deshalb wurde das Passwort von tess allein
  als falsches Passwort gefolgt von einem Code gelesen. Ein Feld, das *nicht länger* als ein
  Code ist, wird abgelehnt, statt geraten zu werden, denn ein kurzes Passwort lässt sich nicht
  von einem Code unterscheiden.
- **Beide Hälften werden immer geprüft.** Bei einem falschen Passwort vorzeitig zurückzukehren,
  würde in der benötigten Zeit verraten, welche Hälfte falsch war.
- **Ein Code wird einmal verwendet.** Er ist einen ganzen Schritt lang gültig, also akzeptiert
  ein Server, der ihn zweimal akzeptiert, eine Wiederholung; jeder Schritt bis zum zuletzt
  akzeptierten wird abgelehnt, nicht nur derselbe.
- **Raten ist pro Name begrenzt**, mit den Standardwerten von go-authn/totp: Nach fünf falschen
  Codes in Folge wird eine Person fünfzehn Minuten lang abgelehnt, der richtige Code
  eingeschlossen, und nach hundert ist das Konto gesperrt, bis authnd neu startet. Die Zähler
  werden im Speicher gehalten, pro Prozess.
- **Nur ein Code hinter dem richtigen Passwort wird gezählt**: Sonst könnte jeder, der einen
  Namen kennt, das zugehörige Konto mit fünf Binds einfrieren. Hinter einem falschen Passwort
  wird der Code trotzdem berechnet, gegen nichts, was sich etwas merkt – die erste Zeile der
  Ausgabe oben, *not looked at*.
- **Ein Reader wird unter seinem DN gezählt, so wie die Konfiguration ihn schreibt**, sodass
  `CN=Reader` kein eigenes neues Kontingent bekommt.
- **Niemand eingeschrieben ist kein falscher Code.** Eine Person ohne Geheimnis hat nichts
  beantwortet, statt falsch zu antworten, und die Ausgabe des Servers sagt *nobody enrolled an
  authenticator for this person*.

## Nicht mit einem Realm {#not-with-a-realm}

Ein `kerberos`-Block und ein `mfa`-Block in einer Konfiguration werden abgelehnt: Ein `kinit`
beweist das Passwort und sonst nichts, und dieser KDC hat keine Pre-Authentication für einen
zweiten Faktor. Siehe [den Realm]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}}).

## Tokens, unter derselben Richtlinie {#tokens-under-the-same-policy}

Ein Token beim Bind, mit einem [`oidc`-Block]({{< relref "/authnd/tokens.md" >}}), wird danach
gezählt, was sein Aussteller nach eigener Angabe geprüft hat – dem Claim `amr`. Ein Token ohne
`amr` ist ein Faktor, und diese Richtlinie lehnt es ab.
