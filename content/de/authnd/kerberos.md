---
title: "Ein Kerberos-Realm für dieselben Personen"
linkTitle: "Kerberos-Realm"
weight: 60
description: "Der kerberos-Block, der Keytab, mit dem er Tickets signiert, wem ein Ticket ausgestellt werden kann und warum manche Personen nie eines bekommen, und warum er nicht neben einem mfa-Block stehen kann."
tags: [authnd, kerberos, kdc]
---

```hcl
kerberos {
  realm    = "EXAMPLE.ORG"               # required, upper case
  keytab   = "/etc/authnd/krb5.keytab"   # required; must hold krbtgt/EXAMPLE.ORG
  listen   = "127.0.0.1:88"              # the default; UDP and TCP both
  lifetime = "10h"                       # the default, MIT's
}
```

Ein `kerberos`-Block macht authnd zusätzlich zum Verzeichnis zu einem KDC, über
[go-authn/kdc]({{< relref "/libraries/_index.md" >}}): Denselben Personen werden Tickets
ausgestellt, statt dass sie nur nachgeschlagen werden. Er antwortet über UDP und TCP an
derselben Adresse, verlangt Pre-Authentication per verschlüsseltem Zeitstempel und stellt
ausschließlich `aes256-cts-hmac-sha1-96`-Tickets aus. `lifetime` ist eine Go-Dauer
(`"10h"`, `"90m"`). Verzeichnis und Realm sind gleichrangig: Hält eines von beiden an, hält der
Prozess an, denn ein Server, der weiter LDAP beantwortet, nachdem sein KDC gestorben ist, sähe
für alles, was kein Kerberos spricht, gesund aus.

Beim Start abgelehnt:

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

und ebenso ein Realm ohne Namen, ohne Keytab, eine Adresse, die sich nicht parsen lässt, eine
`lifetime`, die Go nicht lesen kann, und ein `kerberos`-Block neben einem `mfa`-Block (siehe
unten).

## Der Keytab {#the-keytab}

Der Keytab enthält den Schlüssel, mit dem authnd seine eigenen Tickets signiert –
`krbtgt/REALM@REALM` –, und einen Schlüssel je Dienst, für den es Tickets ausstellt. Es ist
dieselbe Datei, die diese Dienste lesen. Das krbtgt-Passwort wird nie wieder eingegeben, also
machen Sie es zufällig. Mit MITs `ktutil` (Paket `krb5-user` unter Debian und Ubuntu; dieses
Rezept ist das aus `docs/install.md` und wurde für diese Seiten nicht ausgeführt):

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

Fügen Sie den Schlüssel eines Dienstes auf dieselbe Weise hinzu
(`-p nfs/files.example.org@EXAMPLE.ORG`), und geben Sie diesem Dienst denselben Schlüssel in
seinem eigenen Keytab. Unter macOS schreibt Heimdals
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96`
einen zufälligen Schlüssel ganz ohne Passwort. In jedem Fall lesen Sie den Keytab vor dem Start
zurück (`klist -k` mit MIT, `ktutil -k <file> list` mit Heimdal):

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

Ein Keytab ohne `krbtgt/REALM` wird von `check` und beim Start abgelehnt; siehe
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
Der Keytab wird einmal gelesen, beim Start: Ihn zu ersetzen erfordert einen Neustart.

## Wem ein Ticket ausgestellt werden kann {#who-can-be-issued-a-ticket}

Ein KDC muss die Pre-Authentication des Clients mit dem langfristigen Schlüssel der Person
**entschlüsseln**, braucht also das **Passwort** der Person, nicht nur eine Möglichkeit, eines
zu prüfen. `check` sagt, wer ein Ticket bekommen kann und wer nicht, mit dem Grund:

```
$ authnd check realm
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP  MEMBERS        PUBLISHED AS
staff  alice and bob  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

| die Quelle hat | ein Ticket |
|---|---|
| ein Passwort (`password`, `password_file`, eine SQL-Passwortspalte) | ja |
| nur einen NT-Hash | **nein**: Er ist der RC4-HMAC-Schlüssel, und dieser Realm stellt nur AES aus |
| nur eine Passwortprüfung (ein `users "ldap"`-Verzeichnis hinter diesem) | **nein**: Eine Quelle, die ein Passwort nur verifiziert, kann keinen Schlüssel erzeugen |

Bei einem Verzeichnis hinter diesem lautet die letzte Zeile des Realm-Teils
*alice, bob, dora and eli: the source only verifies a password, so it cannot produce any key*.
Das ist strukturell und keine Frage der Konfiguration, und es in `check` zu finden ist besser,
als es von jemandem zu erfahren, dessen `kinit` behauptet, das richtige Passwort sei falsch.

## kinit dagegen {#kinit-against-it}

Eine `krb5.conf`, die diesen KDC nennt. ⛔ Bei MIT Kerberos stehen die geschweiften Klammern auf
eigenen Zeilen: Sein Parser ignoriert stillschweigend einen Realm, der in einer Zeile
geschrieben ist.

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

Dieselbe Konfiguration, bereitgestellt und befragt von Heimdals `kinit` unter macOS
(`--password-file` liest das Passwort aus einer Datei):

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:42:50 2026  Oct 26 22:42:50 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

Das Ticket gilt die standardmäßigen zehn Stunden. bob hat das Passwort eingegeben, aus dem
sein NT-Hash berechnet wurde, und wird trotzdem abgelehnt: Der Realm hat keinen Schlüssel für
dieses Konto. Der KDC schreibt, was er abgelehnt hat, mit dem Kerberos-Fehlercode, in seine
Ausgabe:

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required* ist die normale erste Runde eines `kinit`: Der Client fragt ohne
Pre-Authentication, erfährt, dass sie erforderlich ist, und fragt dann mit ihr erneut. Das
erfolgreiche `kinit` von alice hinterlässt nur diese Zeile.

{{< callout type="info" >}}
**Der Realm verrät, welche Namen existieren; das Verzeichnis nicht**

Ein LDAP-Bind für einen Namen, den niemand hat, wird mit `invalidCredentials` beantwortet,
genau wie ein falsches Passwort. Der KDC antwortet *no such principal in this realm*
(`KDC_ERR_C_PRINCIPAL_UNKNOWN`, Code 6), wie es Kerberos-KDCs tun. Mit einem `kerberos`-Block
an einer Adresse, die andere erreichen können, ist die Liste der Namen daher so erratbar wie
bei jedem KDC; `listen` ist standardmäßig Loopback.
{{< /callout >}}

## Ein über LDAP geändertes Passwort {#a-password-changed-over-ldap}

Der KDC liest dieselben Personen, die das Verzeichnis bereitstellt, daher erreicht ein
[über LDAP geändertes Passwort]({{< relref "/authnd/passwords.md" >}}) den Realm sofort – das
alte funktioniert für `kinit` in dem Moment nicht mehr, in dem es für einen Bind nicht mehr
funktioniert:

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## Nicht neben einem `mfa`-Block {#not-beside-an-mfa-block}

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

Die Pre-Authentication per verschlüsseltem Zeitstempel aus RFC 4120 ist allein mit dem Passwort
verschlüsselt. Ein zweiter Faktor braucht OTP-Pre-Authentication (RFC 6560) innerhalb von FAST
(RFC 6113), was dieser KDC nicht implementiert. Ein Realm hier würde den Personen, für die der
[`mfa`-Block]({{< relref "/authnd/mfa.md" >}}) zwei Faktoren verlangt, Tickets auf einen Faktor
hin aushändigen, und ein Ticket öffnet alles, was ein Bind öffnet – also fällt die Wahl
geschlossen aus: das eine oder das andere.

## Ports {#ports}

88 ist privilegiert. Unter der mitgelieferten Unit deckt `CAP_NET_BIND_SERVICE` ihn ab; ein
Server, der als gewöhnlicher Benutzer läuft, braucht einen hohen Port, wie oben, und eine
`krb5.conf`, die ihn nennt.
