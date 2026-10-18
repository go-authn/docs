---
title: "kdc – Kerberos-Tickets aus einem Verzeichnis ausstellen"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc ist die ausstellende Hälfte von Kerberos: AS und TGS über UDP und TCP, Pre-Authentication verpflichtend, ein Verschlüsselungstyp, Personen aus einem go-authn-Verzeichnis."
tags: [bibliotheken, kerberos, verzeichnis]
---

**Wie stellt ein Realm Tickets aus einem Verzeichnis aus?** AS-REQ und TGS-REQ, über
UDP und TCP, mit verpflichtender Pre-Authentication per verschlüsseltem Zeitstempel, für die
Personen, die ein [directory]({{< relref "/libraries/directory.md" >}}) kennt, und die
Dienste, die eine Keytab hält. Es läuft unter
[authnd]({{< relref "/authnd/_index.md" >}}).

```sh
go get github.com/go-authn/kdc@v0.4.2
```

In v0.4.2 verlangt sein `go.mod` mindestens `go-authn/directory` v0.11.1 und
gokrb5 v8.4.4: Mindestversionen, sodass ein Programm, das directory v0.14.0 verlangt, die
Version, die diese Seiten beschreiben, mit v0.14.0 gebaut wird, wie authnd v0.11.0. Die
annehmende Hälfte ist [krb5]({{< relref "/libraries/krb5.md" >}}), und ein Dienst,
der Tickets nur prüft, braucht dieses Modul überhaupt nicht.

Nicht implementiert: Cross-Realm-Referrals, PKINIT, FAST, erneuerbare oder vordatierte
Tickets und jegliches kadmin-Protokoll. Schlüssel kommen aus dem Verzeichnis und aus einer
Keytab und werden dort geändert, wo sie liegen.

## Nur eine Quelle, die das Passwort hält, kann einen Realm tragen {#only-a-source-holding-the-password-can-back-a-realm}

Ein KDC muss die Pre-Authentication des Clients mit dem Langzeitschlüssel dieser Person
**entschlüsseln**, daher kann ein `directory.Verifier` – ein Bind gegen das LDAP von jemand anderem,
ein Hash-Vergleich – nicht dienen, wie gut er auch beantwortet, *ob dies das
richtige Passwort ist*. Eine Person, deren Quelle kein Passwort hält, erhält die Antwort
`KDC_ERR_NULL_KEY` („null key“), nie den Code, den ein falsches Passwort bekommt, sodass es
sich als zu behebende Konfiguration liest und nicht als neu einzugebendes Passwort.

## Beispiel {#example}

Ein Realm im Speicher, auf Loopback:

```go
package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/go-authn/directory"
	"github.com/go-authn/kdc"
	"github.com/jcmturner/gokrb5/v8/iana/etypeID"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

func main() {
	// People: a source that holds PASSWORDS. A verifier cannot back a realm.
	people := &directory.Static{Name: "the configuration file", People: []*directory.Identity{
		directory.NewIdentity("alice", directory.WithPassword("correct horse battery staple")),
	}}

	// Services: the realm's own krbtgt key, and one per service.
	kt := keytab.New()
	for _, p := range []string{"krbtgt/EXAMPLE.ORG", "nfs/files.example.org"} {
		if err := kt.AddEntry(p, "EXAMPLE.ORG", rand.Text(), time.Now(), 1, etypeID.AES256_CTS_HMAC_SHA1_96); err != nil {
			log.Fatal(err)
		}
	}

	// A keytab without krbtgt/REALM is refused before anything listens.
	_, err := kdc.New(kdc.Config{Realm: "OTHER.ORG", People: people, Services: kt})
	fmt.Println(err)

	srv, err := kdc.New(kdc.Config{
		Realm:    "EXAMPLE.ORG",
		People:   people,
		Services: kt,
		Logf:     log.Printf, // why each request was refused; never a key
	})
	if err != nil {
		log.Fatal(err)
	}
	pc, err := net.ListenPacket("udp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	go srv.ServeTCP(ln)
	fmt.Println("EXAMPLE.ORG answers on", pc.LocalAddr())
	log.Fatal(srv.ServeUDP(pc))
}
```

Mit einer `krb5.conf`, die für `EXAMPLE.ORG` `kdc = tcp/127.0.0.1:18088` nennt, erhält das
Heimdal-`kinit`, das macOS mitliefert (1.5.1), ein Ticket-Granting-Ticket, mit
`KRB5_CONFIG=krb5.conf` und `KRB5CCNAME=FILE:cc`:

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:54:46 2026  Oct 11 07:54:46 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:54:46 2026  Oct 11 07:54:46 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 10 21:54:47 2026  Oct 11 07:54:46 2026  nfs/files.example.org@EXAMPLE.ORG
```

Die zehn Stunden sind der Standardwert von `Config.Lifetime`, und das Service-Ticket endet mit
dem Ticket-Granting-Ticket, mit dem es erworben wurde. Der KDC hat in seinem eigenen Log gesagt, warum er jede
Anfrage abgelehnt hat:

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/10 21:54:46 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/10 21:54:47 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

Die erste Ablehnung jedes Austauschs ist das Protokoll bei der Arbeit: Der `KRB-ERROR`,
der Pre-Authentication verlangt, trägt einen `ETYPE-INFO2`-Hinweis, der den
Etype und das Salt nennt, und der Client versucht es mit einem Zeitstempel erneut.

{{< callout type="info" >}}
**Vor v0.4.2 bekam ein `till` von 19700101000000Z ein Ticket, das bereits abgelaufen war**

RFC 4120 §5.4.1: Ein `till` von 19700101000000Z verlangt die maximale Endzeit,
die die Richtlinie des KDC erlaubt. Heimdals `kgetcred` sendet genau das. v0.4.1
prüfte nur auf die Nullzeit von Go, nahm also die Unix-Epoche als echtes Ende und
stellte ein Service-Ticket aus, das `klist` als `>>>Expired<<<` anzeigte; MITs `kvno`,
der Prüfstein der CI, sendet ein echtes `till` und traf nie auf den Fall. v0.4.2 stellt das
längste erlaubte Ticket aus, wie oben, und beantwortet ein `till`, das bereits vergangen ist,
mit `KDC_ERR_NEVER_VALID` statt mit einem Ticket, das bei Ankunft abgelaufen ist
([go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19)).
{{< /callout >}}

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Bei der Konfiguration** (`New`): kein Realm (`ErrNoRealm`), kein Verzeichnis
(`ErrNoPeople`), keine Keytab (`ErrNoServices`) oder eine Keytab ohne
`krbtgt/REALM@REALM` (`ErrNoTGTKey`) – statt zu starten und beim
ersten `kinit` zu scheitern, wo der Fehler eine Person erreicht, die ihn nicht beheben kann.

**Beim AS:** Eine Anfrage ohne Pre-Authentication wird mit der
Forderung danach beantwortet, und der Schlüssel der Person wird erst abgeleitet, wenn es einen Zeitstempel
zu prüfen gibt, sodass ein gefälschtes UDP-Paket, das einen echten Principal nennt, keine
Schlüsselableitung kostet. Ein falsches Passwort, ein Zeitstempel unter einem anderen Etype und einer von vor
einer Stunde werden alle mit `KDC_ERR_PREAUTH_FAILED` beantwortet, dem Code, den ein falsches Passwort
bekommt; der Fehlertext nennt den Grund, und `Logf` ebenso. Ein Dienst, der ein eigenes TGT anfordert, wird abgelehnt: Dienste
authentifizieren sich über eine Keytab.

**Ein Verschlüsselungstyp.** Tickets und Schlüssel sind ausschließlich `aes256-cts-hmac-sha1-96`
(Etype 18). Eine Anfrage, deren Etype-Liste 18 nicht enthält, wird mit
`KDC_ERR_ETYPE_NOSUPP` beantwortet, bevor irgendjemand nachgeschlagen wird. Ist `Logf` gesetzt, hält das Log
beide Etypes fest, sodass ein Betreiber eine nicht passende Chiffre von einem
vertippten Passwort unterscheiden kann.

**Beim TGS** (RFC 4120 §3.3.2) wird ein Ticket nur ausgestellt, wenn:

- das vorgelegte Ticket ein TGT dieses Realms ist, entschlüsselt mit dem
  `krbtgt/REALM`-Schlüssel, den der KDC benennt – nicht mit dem Schlüssel des Dienstes, den das
  Ticket angeblich betrifft (`KRB_AP_ERR_NOT_US`);
- der Authenticator sich mit seinem Sitzungsschlüssel entschlüsseln lässt, innerhalb von `MaxSkew`;
- seine Prüfsumme über den Body dieser Anfrage läuft, so wie die Bytes angekommen sind, verschlüsselt mit
  dem Sitzungsschlüssel (`KRB_AP_ERR_INAPP_CKSUM`, wenn sie fehlt oder ohne Schlüssel ist,
  `KRB_AP_ERR_MODIFIED`, wenn sie falsch ist);
- das TGT nicht über sein Ende hinaus ist (`KRB_AP_ERR_TKT_EXPIRED`), nicht vor seinem Beginn
  liegt und nicht als ungültig markiert ist (`KRB_AP_ERR_TKT_NYV`), ohne erlaubte Abweichung: Die Uhr
  dieses KDC hat diese Zeiten geschrieben;
- der Client zu diesem Realm gehört und noch im Verzeichnis steht
  (`KDC_ERR_C_PRINCIPAL_UNKNOWN`).

**Lebensdauern.** `Config.Lifetime` begrenzt ein Ticket, zehn Stunden, wenn null; ein Client,
der weniger verlangt, bekommt weniger, und ein mit einem TGT erworbenes Ticket endet nicht später als
dieses TGT, sodass ein erneutes Anfordern von `krbtgt` ein Credential nicht verlängern kann.

**Was eine nicht authentifizierte Gegenstelle belegen kann:** Eine TCP-Nachricht, einschließlich ihrer Länge,
muss innerhalb von 30 Sekunden ankommen; höchstens 256 TCP-Verbindungen werden gleichzeitig bedient,
und höchstens 64 Datagramme werden gleichzeitig beantwortet – eines mehr wird verworfen, und der
Client sendet erneut oder weicht auf TCP aus.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**MITs eigene `kinit` und `kvno`**, über pkgx, gegen einen in Go gebauten Realm –
kein MIT-KDC ist beteiligt, nur der Client wird geliehen.
`TestMITClientGetsATGTAndAServiceTicket` holt ein TGT und ein Service-Ticket und
prüft die Schlüsselversion, die `kvno` meldet. Die Linux-Test-Lane, der Race-Detector
und die Coverage-Lane setzen `KDC_REQUIRE_JUDGE=1`, und ein weiterer Schritt schlägt fehl,
sofern das Log nicht „were served by this realm“ sagt. Die Tests halten auch die
Ablehnungen fest, die ein echter Client nie auslöst: ein Zeitstempel unter dem falschen Schlüssel, einer
von vor einer Stunde, eine Drei-Byte-Chiffre, ein Dienst, der direkt über einen
AS-REQ angefordert wird, ein gefälschtes Service-Ticket beim TGS und ein Realm, der von einem Verifier getragen wird.
Die Untergrenze der Coverage-Lane liegt bei 80 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/kdc@v0.4.2](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.2)
