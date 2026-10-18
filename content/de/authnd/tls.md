---
title: "TLS: ldaps:// oder StartTLS, und nicht beides zugleich"
linkTitle: "TLS"
weight: 40
description: "LDAP über TLS aus einem Zertifikat in Dateien bereitstellen, die Wahl zwischen ldaps:// und StartTLS, und warum sambaNTPassword nur über eines davon veröffentlicht wird."
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file` und `key_file` zusammen schalten TLS ein; eines ohne das andere wird
abgelehnt (*one without the other serves nothing*). TLS 1.2 ist das Minimum.
authnd hat keinen ACME-Client: Die beiden Dateien schreibt etwas anderes –
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}}), certbot, die
eigene CA einer Installation –, und authnd wird nach jeder Erneuerung **neu gestartet**,
weil das Zertifikat einmal gelesen wird, wenn der Listener öffnet.

## Zwei Wege, je ein Listener {#two-ways-one-listener-each}

| | `starttls` | der Listener | `check` sagt |
|---|---|---|---|
| **ldaps://** | nicht gesetzt | der TLS-Handshake findet statt, bevor ein einziges Byte LDAP gesprochen wird | `ldaps://…` |
| **StartTLS** | `starttls = true` | Klartext, hochgestuft, wenn der Client es verlangt (RFC 4511 §4.14) | `ldap+starttls://…` |

Es ist das eine oder das andere, und das muss so sein: Ein Listener kann nicht zugleich einen
Handshake verlangen und abwarten, ob einer angefordert wird. Welchen eine Installation will, hängt
von ihren **Clients** ab: `ldaps://` auf 636 ist das, wofür die meisten konfiguriert sind,
und StartTLS ist das, was ein Client verlangt, der auf 389 zeigt und bei dem „use TLS“
angehakt ist. Eine Installation, die beides braucht, betreibt zwei Instanzen, jede mit eigenem
`--config`. `starttls = true` ohne Zertifikat wird abgelehnt:

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps:// {#ldaps}

Der Server, ein von einer CA signiertes Zertifikat für `127.0.0.1` und die Kette, geprüft
von einem Client, der nicht dieses Programm ist:

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS, das ablehnt, bis es verlangt wird {#starttls-which-refuses-until-it-is-asked-for}

StartTLS wird vom **Client** angefordert; es bloß anzubieten, verspricht daher
nichts: Ein Client, der nie danach fragt, würde sich im Klartext binden. Ein Listener mit
`starttls = true` lehnt deshalb jeden Bind und jede Suche ab, bis die
Verbindung hochgestuft wurde, mit `confidentialityRequired`:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

(`-ZZ` heißt „StartTLS, und fehlschlagen, wenn es fehlschlägt“. `LDAPTLS_REQCERT=never` steht da,
weil das `ldapsearch`, das macOS mitliefert, dem Systemspeicher vertraut und sich nicht
anweisen ließ, dieser Test-CA zu vertrauen; die Kette wurde separat mit
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error` geprüft,
was `Verify return code: 0 (ok)` ergab.)

Diese Ablehnung macht `cert_file` zu einer Garantie statt zu einem Angebot – und
auf sie verlässt sich `publish_nt_hash`. Sie umfasst den anonymen Bind, den
`ldapsearch -x` vor dem Lesen des Root-DSE sendet; auf einem StartTLS-Listener
braucht daher auch diese Erkundungsabfrage `-ZZ`.

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword` ist das, was einem Samba- oder anderen SMB-Server erlaubt, Personen
über dieses Verzeichnis zu authentifizieren, und es ist **kein** Passwort-Hash in dem
Sinn, den ein Anmeldeformular meint: Wer `MD4(UTF16LE(password))` hält,
authentifiziert sich über NTLMv2 als diese Person, ohne je das
Passwort zu erfahren. Daher wird es nur veröffentlicht, wenn es verlangt wird, und ab
v0.11.0 zusammen mit der Domäne, zu der die SIDs der Personen gehören:

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

Das Verlangen wird abgelehnt, es sei denn, der Listener hat TLS oder ist Loopback
(`127.0.0.0/8`, `::1`, `localhost`) und damit in überhaupt keinem Netz:

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### Der `samba`-Block {#the-samba-block}

`sambaNTPassword` gehört zu Sambas `sambaSamAccount`, dessen MUST `uid` und
`sambaSID` ist, und keine andere Klasse erlaubt es. Jeder Eintrag, den authnd veröffentlicht,
besteht [das Schema, das es bereitstellt]({{< relref "/authnd/entries.md" >}}); das
Attribut wird daher nur an einem `sambaSamAccount` veröffentlicht, und dafür braucht es eine SID:

| Schlüssel | |
|---|---|
| `domain_sid` | erforderlich: die Domänen-SID des SMB-Servers, `S-1-5-21-…`, wie `net getlocalsid` sie ausgibt |
| `algorithmic_rid_base` | optional, standardmäßig `1000`, wie bei Samba. Eine ungerade Zahl oder eine unter 1000 wird abgelehnt: Samba würde stillschweigend eine andere verwenden |

Die `sambaSID` einer Person ist ihr eigenes `sambaSID`-Attribut, wenn eine Quelle eines
liefert ([Attribute]({{< relref "/authnd/entries.md#adding-attributes" >}})).
Andernfalls ist sie `domain_sid-RID`, mit RID = 2 × `uidNumber` +
`algorithmic_rid_base`: Sambas algorithmische Zuordnung (smb.conf(5),
*algorithmic rid base*). Eine Person mit einem NT-Schlüssel und keinem von beiden wird
**ohne** `sambaNTPassword` veröffentlicht, und `check` und das Startprotokoll sagen, wer. Die
Samba-Definitionen werden dem unter `cn=Subschema` bereitgestellten Schema nur hinzugefügt,
wenn der Block vorhanden ist; sie wurden aus den von Samba veröffentlichten OIDs, Namen und
Syntaxen geschrieben, nicht aus dessen `samba.schema` unter GPL-3.0 kopiert.

{{< callout type="error" >}}
**Inkompatibel für v0.10.x-Konfigurationen: `publish_nt_hash` ohne `samba`-Block startet nicht**

v0.10.x stellte `publish_nt_hash = true` allein bereit. Ab v0.11.0 wird diese
Konfiguration beim Start und von `check` abgelehnt, zusammen mit dem, was hinzuzufügen ist:

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

Führen Sie `check` mit dem neuen Binary vor dem Upgrade aus. Die Ablehnung ist beabsichtigt:
Der v0.10.x-Eintrag kann das Schema nicht bestehen, und die beiden stillen Alternativen –
das Attribut wegzulassen, was allen SMB nimmt, oder den Eintrag wegzulassen, was die
Person entfernt – würden beide geschehen, ohne dass etwas auf der
Konsole steht.
{{< /callout >}}

Ein `samba`-Block ohne `publish_nt_hash` wird ebenfalls abgelehnt, da er nichts
veröffentlichen würde:

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### Was `check` sagt {#what-check-says}

Drei Personen auf einem `ldaps://`-Listener: alice hat ein Passwort und das POSIX-Trio,
daher wird die SID abgeleitet (2 × 1000 + 1000); bob hat nur einen NT-Hash und eine
eigene `sambaSID`; carol hat ein Passwort und keines von beiden.

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

und für den StartTLS-Listener *sambaNTPassword is published over TLS, once
StartTLS has been asked for*. Für alice ist kein NT-Hash hinterlegt; der Hash wird
aus dem Passwort abgeleitet, das für alice eingetragen ist. Der Hash von bob wird veröffentlicht, damit ein SMB-Server
ihn verwenden kann, und `check` sagt auch, dass bob sich nicht bei authnd selbst binden kann.
Der Eintrag von carol wird ohne das Attribut veröffentlicht, und ein SMB-Server kann
carol erst bedienen, wenn eine Quelle eine `uidNumber` oder eine `sambaSID` für carol liefert.

Was ein Lesekonto erhält, über den StartTLS-Listener derselben Personen:

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

Nur ein [Lesekonto]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})
kann suchen, also sieht nur ein Lesekonto je das Attribut. Wer es lesen darf, ist
daher dieselbe Frage wie die, wer das Passwort eines Lesekontos hält.

{{< callout type="warning" >}}
**NTLMv2 braucht das Passwort oder seinen MD4, und nichts anderes genügt**

Ein Dateiserver, der authnd nach jemandem fragt, kann diese Person über SMB nur bedienen, wenn
die *Quelle* genug dafür hielt: ein Passwort oder den Hash. Einer Person, die
aus einem Verzeichnis kommt, das nur Passwörter prüft – *a password check* in
`check` –, kann nie ein `sambaNTPassword` gegeben werden, was auch immer authnd
dazwischen tut. Ohne `publish_nt_hash` kann es niemand: `check` sagt dann
*sambaNTPassword is not published, so nothing here can authenticate an SMB
session*.
{{< /callout >}}

## Auch Tokens brauchen es {#tokens-need-it-too}

Ein [`oidc`-Block]({{< relref "/authnd/tokens.md" >}}) lehnt ein Token über eine
Verbindung ab, die nicht verschlüsselt ist, es sei denn, `allow_plaintext = true` sagt, dass
TLS vor diesem Prozess terminiert wird.
