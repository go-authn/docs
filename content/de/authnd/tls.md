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
authnd hat keinen ACME-Client: Was auch immer die beiden Dateien schreibt –
[go-authn/servercert]({{< relref "/libraries/_index.md" >}}), certbot, die
eigene CA einer Installation –, schreibt sie, und authnd wird nach jeder Erneuerung **neu gestartet**,
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
ldaps on 127.0.0.1:3636, serving 2 people from the configuration file

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
objectClass: person
objectClass: posixAccount
uid: bob
cn: bob
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
Passwort zu erfahren. Daher wird es nur veröffentlicht, wenn es verlangt wird:

```hcl
publish_nt_hash = true
```

und das Verlangen wird abgelehnt, es sei denn, der Listener hat TLS oder ist Loopback
(`127.0.0.0/8`, `::1`, `localhost`) und damit in überhaupt keinem Netz:

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

Damit nennt `check` das Attribut pro Person und sagt, was es schützt:

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid, cn and sambaNTPassword
bob    the configuration file  an NT hash  uid, cn and sambaNTPassword

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2

this configuration can be served
```

und für den StartTLS-Listener *sambaNTPassword is published over TLS, once
StartTLS has been asked for*. Für alice ist kein NT-Hash hinterlegt; der Hash wird
aus dem Passwort abgeleitet, das für alice eingetragen ist. Der Hash von bob wird veröffentlicht, damit ein SMB-Server
ihn verwenden kann, und `check` sagt auch, dass bob sich nicht bei authnd selbst binden kann.

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
