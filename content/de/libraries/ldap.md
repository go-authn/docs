---
title: "ldap – die Bytes eines LDAP-Servers"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap ist das LDAP-Protokoll als Server-Bibliothek: die Leitung, der Filter, die Operationen und ihre Grenzen, mit Handlern, die entscheiden, was beantwortet wird."
tags: [bibliotheken, ldap, verzeichnis]
---

**Was sind die Bytes eines LDAP-Servers?** Eine Bibliothek, kein Daemon: die Leitung,
der Filter, die Operationen. [authnd]({{< relref "/authnd/_index.md" >}}) ist der
Server, der sie ausführt und dem die Konfiguration, die Verzeichnisquellen und die
Bind-Richtlinie gehören; dieser Bibliothek gehören die Bytes.

```sh
go get github.com/go-authn/ldap@v0.8.0
```

Geschrieben nach RFC 4511 (das Protokoll), 4512 (das Root-DSE), 4513
(Authentifizierung), 4514 und 4515 (String-Formen von DN und Filter), 4526, 2696
(Paged Results), 3673, 4527 (Read-Entry-Controls), 4532 (whoami) und 3045.

Ein `Server` ist eine Menge von Handlern, jeder ein optionales Feld: `Bind`, `SASL`,
`Search`, `Compare`, `Extended`, `Add`, `Modify`, `Delete`, `ModifyDN`,
`Abandon`. Ein nil-Handler bedeutet *dieser Server tut das nicht*, und die Operation
wird mit `unwillingToPerform` beantwortet – nicht mit `insufficientAccessRights`, was
einen Streit über Berechtigungen beginnen würde, die es nicht gibt. Das Root-DSE wird
vom Server selbst beantwortet und veröffentlicht genau das, was er einhält.

## Beispiel {#example}

Ein Server mit einer Person, die sich binden kann, und einer Suche, die schreibt, was der
Filter trifft:

```go
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"log/slog"
	"os"

	"github.com/go-authn/ldap"
)

var people = []*ldap.Entry{
	{DN: "uid=dora,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "dora")}},
	{DN: "uid=svc-web-prod,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-prod")}},
	{DN: "uid=svc-web-stage,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-stage")}},
}

// binder checks one password. A real one asks a directory: see go-authn/directory.
type binder struct{}

func (binder) Bind(_ context.Context, _ ldap.Session, req *ldap.BindRequest) (ldap.Result, error) {
	if req.Name == "" && len(req.Simple) == 0 {
		return ldap.Result{Code: ldap.Success}, nil // anonymous: the connection stays unbound
	}
	// A name with an empty password is an UNAUTHENTICATED bind (RFC 4513
	// 5.1.2). This package hands it to the handler, and the handler refuses it:
	// the comparison below does, since the password is never empty.
	ok := ldap.EqualDN(req.Name, "uid=dora,ou=people,dc=example,dc=org") &&
		subtle.ConstantTimeCompare(req.Simple, []byte("hunter2")) == 1
	if !ok {
		return ldap.Refuse(ldap.InvalidCredentials, "invalid credentials"), nil
	}
	return ldap.Result{Code: ldap.Success}, nil
}

// searcher writes each entry in scope that the filter matches, as it finds it.
type searcher struct{}

func (searcher) Search(_ context.Context, s ldap.Session, req *ldap.SearchRequest, w ldap.EntryWriter) (ldap.Result, error) {
	if s.BoundDN() == "" {
		return ldap.Refuse(ldap.InsufficientAccessRights, "bind first"), nil
	}
	for _, e := range people {
		if ldap.InScope(e.DN, req.BaseObject, req.Scope) && req.Filter.Matches(e) {
			if err := w.Entry(e); err != nil {
				return ldap.Result{}, err // the client went away, or a limit was reached
			}
		}
	}
	return ldap.Result{Code: ldap.Success}, nil
}

func main() {
	srv := &ldap.Server{
		Bind:           binder{},
		Search:         searcher{},
		NamingContexts: []string{"dc=example,dc=org"},
		Log:            slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// On anything but loopback: TLSConfig, and RequireTLS so that a
		// client that never asks for StartTLS is refused rather than
		// sending its password in the clear.
	}
	log.Fatal(srv.ListenAndServe("127.0.0.1:3389"))
}
```

Abgefragt mit OpenLDAPs `ldapsearch` (2.4.28, wie macOS es mitliefert), mit dem Passwort von dora
in einer Datei:

```
$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw \
    -b ou=people,dc=example,dc=org '(uid=svc-*-prod)' uid
dn: uid=svc-web-prod,ou=people,dc=example,dc=org
uid: svc-web-prod

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -b ou=people,dc=example,dc=org '(uid=*)' uid
Insufficient access (50)
Additional information: bind first

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -s base -b '' namingContexts supportedLDAPVersion supportedExtension
dn:
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3

$ printf 'dn: uid=dora,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: uid\nuid: x\n' |
    ldapmodify -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw
ldap_modify: Server is unwilling to perform (53)
	additional info: this server does not modify entries
modifying entry "uid=dora,ou=people,dc=example,dc=org"
```

`(uid=svc-*-prod)` liefert `svc-web-prod` und nicht `svc-web-stage`. Die Bibliothek,
die diese ersetzt, wertete diesen Filter als `(uid=svc-*)` aus und lieferte auch
`svc-web-stage`; dieser Defekt ist der Grund, warum diese Bibliothek geschrieben wurde. Das
Root-DSE führt StartTLS nicht auf, weil keine `TLSConfig` angegeben wurde.

## Was es ablehnt und warum {#what-it-refuses-and-why}

**Ein Filter bedeutet eine Sache.** Er wird einmal in einen Baum geparst oder dekodiert, und
`String`, `EncodeFilter` und `Matches` lesen alle diesen Baum. Ein Attribut, das
keine Attributbeschreibung nach RFC 4512 §2.5 ist, oder eine Matching Rule, die keine
OID ist, wird sowohl von `ParseFilter` als auch von `DecodeFilter` abgelehnt: Vor v0.6.1 las sich zurückgeschrieben
ein „present“-Filter auf dem Attribut `!x` als NOT.

**Klartext, wenn etwas anderes versprochen wurde.** StartTLS wird vom
*Client* angefordert, daher hat ein Server, der es lediglich anbietet, nichts versprochen.
`RequireTLS` lehnt jede Operation auf einer Verbindung, die nicht geschützt ist,
mit `confidentialityRequired` ab.

**Ein fehlgeschlagener Bind behält nichts.** RFC 4511 §4.2.1: Die Verbindung wird
anonym, sobald die Bind-Anfrage *empfangen* wird, und bleibt es, sofern der Bind nicht
gelingt – ein erneuter Bind mit falschem Passwort behält also nicht die Rechte der vorherigen
Person. Ein Simple Bind ohne `Bind`-Handler wird mit
`authMethodNotSupported` beantwortet, und LDAPv2 wird als Protokollfehler abgelehnt.

{{< callout type="warning" >}}
**Der Handler entscheidet, was ein leeres Passwort bedeutet**

Ein unauthentifizierter Bind – ein Name mit leerem Passwort, RFC 4513 §5.1.2 – wird
wie jeder andere Simple Bind an den `Bind`-Handler übergeben, und ein Handler, der
dafür `Success` zurückgibt, bindet die Verbindung unter diesem Namen. Lehnen Sie ihn im
Handler ab, wie es das Beispiel tut. `ldapdir` aus [directory]({{< relref "/libraries/directory.md" >}})
lehnt ihn auf der Client-Seite ab.
{{< /callout >}}

**Ein kritisches Control, das es nicht einhält.** ManageDsaIT (RFC 3296), Password
Modify (RFC 3062) und Cancel (RFC 3909) sind als Konstanten benannt, weil ein
Client sie senden kann, nicht weil sie beantwortet werden: Nichts hier folgt
Aliasen oder Referrals, daher wird ein kritisches ManageDsaIT mit
`unavailableCriticalExtension` abgelehnt.

**Was eine nicht authentifizierte Gegenstelle belegen kann:**

| | Standard | |
|---|---|---|
| `MaxMessageSize` | 4 MiB | ein Fünf-Byte-Header, der vier Gigabyte ankündigt, wird abgelehnt, bevor irgendetwas reserviert wird |
| `MaxMessageElements` | 16384 | BER-Elemente, gezählt vor dem Dekodieren: vor v0.5.0 belegten 4 MiB leerer Strings 373 MiB vor jedem Bind |
| `IdleTimeout` | 5 Minuten | die ganze Nachricht muss rechtzeitig ankommen, nicht ihr erstes Byte; negativ bedeutet nie |
| `MaxPending`, `MaxPendingAuth` | 100, 1000 | Operationen, die eine Verbindung vor ihrem Bind (`MaxPending`) und danach (`MaxPendingAuth`) gleichzeitig laufen haben darf, wie `conn_max_pending` und `conn_max_pending_auth` von slapd; eine Verbindung, die darüber geht, erhält eine Notice of Disconnection und wird geschlossen |
| `MaxPagedSearches` | 4 | offene seitenweise Suchen pro Verbindung, jede eine Goroutine, die auf ihren nächsten Eintrag wartet |

Auch die Verschachtelung von Filtern ist begrenzt: Ein Stack-Überlauf in Go beendet den Prozess.
Nichts loggt einen Assertion-*Wert* – ein Filter trägt, was jemand eingetippt hat –, nur
die Form des Filters.

Es gibt kein Schema, daher ist jeder Vergleich auf dem Wert unabhängig von Groß- und Kleinschreibung.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**OpenLDAPs `ldapsearch`**, in der CI, und verpflichtend, wo es installiert ist: Die
Linux-Test-Lane, der Race-Detector und die Coverage-Lane setzen
`LDAP_REQUIRE_JUDGE=1`, sodass ein fehlender Client zum Fehlschlag führt, statt übersprungen zu werden. Windows
hat keinen und überspringt diese Tests. `ldaptest`, der eigene Leitungs-Client dieses Moduls, ist
absichtlich nicht der Prüfstein: Er fragt nur, was `ldapsearch` nicht kann, über den Zustand einer
Verbindung – zwei Binds auf einem Socket, ein SASL-Bind mit einem beliebigen
Mechanismus, StartTLS gefolgt von weiterem LDAP.

`FuzzMessage` schickt jede Nachricht, die ein Client senden kann, durch das Framing, die
Decoder und den Filter-Rundlauf. Die Coverage-Untergrenze liegt bei 99,7 %, wobei die drei
nicht erreichten Zeilen im Workflow benannt sind.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/ldap@v0.8.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.8.0)
