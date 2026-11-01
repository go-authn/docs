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
go get github.com/go-authn/ldap@v0.12.0
```

Geschrieben nach RFC 4511 (das Protokoll), 4512 (das Root-DSE und das Schema),
4513 (Authentifizierung), 4514 und 4515 (String-Formen von DN und Filter), 4517 und
4518 (Syntaxen, Matching-Regeln, String-Vorbereitung), 4526, 2696 (Paged
Results), 3672 (Subentries), 3673, 4527 (Read-Entry-Controls), 4532 (whoami)
und 3045.

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
| `MaxConnections` | 0 (keine Grenze) | gleichzeitig gehaltene Verbindungen; eine darüber erhält eine Notice of Disconnection mit dem Ergebniscode `busy` (51, RFC 4511 4.4.1) und wird sofort geschlossen, nie in eine Warteschlange gestellt. Neu in v0.12.0 |
| `MaxConnectionsPerIP` | 0 (keine Grenze) | Verbindungen, die eine entfernte Adresse halten darf; ein Listener, der nicht TCP ist (ein Unix-Socket), unterliegt dem nicht. Neu in v0.12.0 |

**Eine Frist, die der Handler nicht ignorieren kann.** `Server.Timeout` (null: keine)
ist die Frist des Kontexts des Handlers, und seit v0.12.0 setzt der *Server* sie durch:
Zur Frist wird der Client bei jeder Operation (auch bei einem Bind, einem Compare oder
einem Schreibvorgang, nicht nur bei einer Suche) mit `timeLimitExceeded` (3)
beantwortet, ob der Handler zurückkehrt oder nicht. Vor v0.12.0 ließ ein Handler, der
seinen Kontext ignorierte, den Client für immer warten, und nur eine Suche bildete eine
Frist auf Code 3 ab, während ein Bind, Compare oder Schreibvorgang `other` antwortete.
Die Goroutine eines Handlers, der nicht zurückkehrt, lässt sich nicht beenden: Sie zählt
weiter gegen `MaxPending` und `MaxPendingAuth`, bis sie zurückkehrt, ihr spätes Ergebnis
wird verworfen, und ihre Message-ID wird inzwischen abgelehnt (`protocolError`); so sind
verwaiste Goroutinen pro Verbindung begrenzt, und eine Verbindung, deren Operationen
alle so ablaufen, erreicht die Pending-Grenze und wird geschlossen. **Ein Handler muss
seinen Kontext beachten, um freizugeben, was er hält.** Das `timeLimit` der Client-Suche
gilt jetzt auch für den Kontext des Handlers. Ein Handler-Fehler, der
`context.DeadlineExceeded` umhüllt, wird nur dann auf Code 3 abgebildet, wenn der eigene
Kontext der Operation abgelaufen ist; sonst bleibt er `other`. Keine Handler-Schnittstelle
hat sich geändert.

Die Kosten, in Allokationen pro Operation (`BenchmarkRun`, exakt): 3 vorher und jetzt
ohne `Timeout`; mit einem `Timeout` 10 vorher und 16 jetzt, für den Frist-Beobachter.
Zeiten sind nicht berichtbar: Die Last lag bei 65 (454 ns und 444 ns ohne `Timeout`,
981 ns und 1455 ns mit einem, nur als Anhaltspunkt). Die Abdeckung beträgt 99,9 % bei
einer Untergrenze von 99,7 %, und es wurde kein Parser und kein Decoder angefasst.

Auch die Verschachtelung von Filtern ist begrenzt: Ein Stack-Überlauf in Go beendet den Prozess.
Nichts loggt einen Assertion-*Wert* – ein Filter trägt, was jemand eingetippt hat –, nur
die Form des Filters.

**Eine seitenweise Suche beantwortet, was gefragt wurde.** Bis v0.8.0 sandte der Seitenleser
jeden Eintrag so, wie der Handler ihn geschrieben hatte: Eine seitenweise Suche nur nach `cn` kam
mit jedem Attribut zurück, einschließlich der operationalen, und `typesOnly` wurde
ignoriert, während dieselbe Suche ohne Seiten sich an die Auswahl hielt. `ldapsearch
-E pr=N` ist die Art, wie ein Client seitenweise liest, also bekam dieselbe Frage zwei Antworten.
Ab v0.8.0 wenden beide die Auswahl an, was `ldapsearch` selbst in der CI prüft.

Ohne Schema – `Server.Schema` nil, der Standard – ist jeder Vergleich auf dem Wert
unabhängig von Groß- und Kleinschreibung: die sicherere der beiden Varianten fürs Lesen, da sie
nie einen Eintrag verbirgt, den ein exakter Vergleich gefunden hätte.

## Das Schema {#the-schema}

Ab v0.8.0 ist das Paket `schema` das Verzeichnisschema aus RFC 4512 §4, und
`Server.Schema` lässt einen Server es verwenden. Nil lässt einen Server genau so, wie er war.

- `schema.Standard()` bettet die Definitionen aus RFC 4512, 4517, 4519, 4524,
  4523, 2798, 2307, 3672 und 3045 ein, dazu `ldapPublicKey` und
  `sshPublicKey` aus openssh-lpk und die beiden OpenLDAP-Definitionen, die sie brauchen, kopiert aus dem
  RFC-Text; jede Datei in `schema/defs` nennt ihre Quelle und ihren Abschnitt.
  `schema.Build(append(schema.StandardFiles(), mine)...)` fügt die eigenen Definitionen
  einer Installation hinzu und lehnt eine ab, deren SUP, Regeln, Syntaxen, MUST oder MAY
  sich nicht auflösen lassen.
- `(*ldap.Entry).Validate(s)` prüft eine strukturelle Kette mit jeder aufgeführten
  Oberklasse, jedes MUST, nichts außerhalb von MUST und MAY, SINGLE-VALUE,
  bekannte Typen, Werte ihrer Syntax und die Werte des RDN im Eintrag –
  und nennt **jedes** Problem, als `*schema.ValidationError`.
- Mit einem Schema trägt das Root-DSE `subschemaSubentry: cn=Subschema`, und
  eine Basissuche auf `cn=Subschema` (`ldap.SubschemaDN`) wird von der
  Bibliothek beantwortet, wie das Root-DSE (RFC 4512 §4.2). Die Definitionen kommen nur, wenn
  sie namentlich oder mit `+` verlangt werden. Sie liegt hinter der `RequireTLS`-Sperre.
- Filter werden mit den Matching-Regeln des Schemas ausgewertet (RFC 4517 §4.2,
  mit der String-Vorbereitung aus RFC 4518), in der dreiwertigen Logik von RFC 4511: Ein
  unbekanntes Attribut, ein Typ ohne Regel für den verlangten Abgleich oder ein ungültiger
  Assertion-Wert ist **Undefined**, nie ein Fehler. Der Server prüft jeden Eintrag,
  den ein Handler sendet, erneut und verwirft jene, die der Filter nicht
  TRUE macht; ein Handler filtert mit `req.Matches(e)`, das dasselbe Schema verwendet.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap"
	"github.com/go-authn/ldap/schema"
)

func main() {
	s := schema.Standard() // RFC 4512, 4517, 4519, 4524, 2798, 2307, ... and openssh-lpk

	// An account with posixAccount, and no homeDirectory.
	eli := &ldap.Entry{DN: "uid=eli,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "top", "account", "posixAccount"),
		ldap.StringAttribute("uid", "eli"),
		ldap.StringAttribute("cn", "eli"),
		ldap.StringAttribute("uidNumber", "1001"),
		ldap.StringAttribute("gidNumber", "1001"),
		ldap.StringAttribute("mail", "eli@example.org"),
	}}
	var v *schema.ValidationError
	if errors.As(eli.Validate(s), &v) {
		for _, p := range v.Problems {
			fmt.Println("-", p)
		}
	}

	// uidNumber orders as an integer: 1001 >= 999, which as strings it is not.
	for _, f := range []string{"(uidNumber>=999)", "(uid>=a)"} {
		filter, _ := ldap.ParseFilter(f)
		fmt.Println(f, ldap.Evaluate(filter, eli, s))
	}
}
```

```
- mail is not allowed by any of the entry's object classes
- homeDirectory is required by posixAccount and is missing
(uidNumber>=999) TRUE
(uid>=a) Undefined
```

`mail` gehört zu `inetOrgPerson`, nicht zu `account`. `uid` hat keine ORDERING-Regel,
daher ist ein Bereich darauf Undefined.

{{< callout type="info" >}}
**Eine Abweichung von RFC 2307: `uidNumber` und `gidNumber` werden als Ganzzahlen geordnet**

RFC 2307 gibt `uidNumber` und `gidNumber` eine EQUALITY-Regel und keine ORDERING-Regel,
was jeden Bereichsfilter auf ihnen Undefined machen würde – einschließlich
dessen, den SSSD aus `ldap_min_id` und `ldap_max_id` baut. slapd definiert beide
Typen selbst mit `ORDERING integerOrderingMatch`
(`servers/slapd/schema_prep.c`; seine `nis.schema` kommentiert sie als
„builtin“ aus), ebenso draft-howard-rfc2307bis-02 §2.1, daher folgen die eingebetteten
Definitionen ihnen. Das, und dass Hilfsklassen ohne DIT-Content-Rules erlaubt sind
(RFC 4512 §2.4.3 verbietet sie strikt; jeder verwendete Server erlaubt sie), wird
gesagt, statt entdeckt zu werden.
{{< /callout >}}

DIT-Content-Rules, Name Forms und DIT-Structure-Rules sind [ab
v0.11.0 vorhanden](#rules). Absichtlich nicht vorhanden: das Ändern des Schemas über LDAP; die Zertifikats-Matching-Regeln aus RFC 4523
und `directoryStringFirstComponentMatch`, die definiert und nicht
implementiert sind, sodass Assertions, die sie verwenden, Undefined sind; kollektive Attribute;
andere Optionen als `lang-` und `binary`.

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}) stellt
dieses Schema bereit und misst jeden Eintrag, den es veröffentlicht, daran.

## Eine große Schemadatei lesen {#reading-large-files}

Bis v0.10.0 brauchte `schema.Read` eine in der Zahl der Fortsetzungszeilen quadratische Zeit: eine Datei von 4 MiB aus kurzen Fortsetzungszeilen brauchte etwa drei Minuten, und 1 MiB belegte 139,6 GB. Ein Programm, das eine Schemadatei liest, die es nicht kontrolliert, wie authnd es beim Start mit seinen `schema_files` tut, konnte dadurch aufgehalten werden. Ab v0.10.1 ist die Zeit linear (`TestManyContinuationLinesJoinInLinearTime`), und `Read` kopiert und zerlegt nicht mehr die ganze Datei, um ihre erste Zeile anzusehen.

`schema.Format` schrieb Zeilen von mehr als 2000 Bytes, die slapd und `Read` ablehnen; es bricht sie jetzt um. Der strikte Parser ist etwa 2,6-mal schneller, mit 147 statt 498 Allokationen bei `cosine.schema`. Gegen libldap (macOS-SDK, `ldap_str2attributetype` und `ldap_str2objectclass` mit `LDAP_SCHEMA_ALLOW_ALL`) auf den 54 Definitionen von OpenLDAPs `cosine.schema`, gemessen am 2026-10-26 auf einem Apple M4 Max bei einer Last von 6,5 bis 7,6 (`-cpu 1 -count 10`, benchstat): go-authn/ldap 25,65 µs ± 32 %, libldap 35,62 µs ± 2 %, also etwa das 0,72-Fache der Zeit von libldap. Die Go-Seite macht 147 Allokationen (20,6 KiB) pro Lauf; `-benchmem` sieht die C-Allokationen von libldap nicht, daher gibt es dafür keine Zahl. Zum Nachmessen führen Sie `go test -bench . -benchmem -cpu 1 -count 10` in `bench/libldap` von go-authn/ldap aus (cgo und libldap sind nötig). authnd hat diese Korrekturen ab v0.12.3.

Ab v0.10.2 stehen die 13 DESC-Werte von RFC 2307 in `schema.Standard()` in einer Zeile. Bis v0.10.1 waren sie wie die RFC-Seite umbrochen, und weil eine Fortsetzungszeile ihre Einrückung nach dem ersten Zeichen behält (`fp_getline` von slapd, dem `Read` folgt), sendete ein Server, der sie veröffentlichte, `DESC 'An integer uniquely identifying a user in an         administrative domain'`. authnd hat die Korrektur ab v0.12.4.

## Ein Schema, das sich nicht aufbauen lässt {#build-error}

Ab v0.10.0 ist eine Definition, die `schema.Build` oder `schema.BuildFrom`
ablehnt, ein `*schema.BuildError`, den man mit `errors.As` findet. Ein Programm
meldet eine Ablehnung anhand seiner Felder, nie durch Abgleich der Meldung.
Build bricht bei der ersten Definition ab, die es ablehnt, es gibt also genau
eine.

- `Kind` ist eine der Prüfungen, die Build vornimmt: `UnknownReference`,
  `DuplicateOID`, `DuplicateName`, `SuperiorCycle`, `KindViolation`,
  `UsageMismatch`, `CollectiveMismatch` und `UsageViolation`.
- `Element` (Syntax, Matching-Regel, Attributtyp oder Objektklasse), `OID` und
  `Name` (sein erster NAME) gehören zur abgelehnten Definition, und `Pos` ist
  die Stelle, an der sie beginnt: `Datei:Zeile:Spalte`, die Zeile des
  `.schema`-Schlüsselworts oder der LDIF-Zeile `attributeTypes:`, auch wenn
  diese Zeile umgebrochen oder base64-kodiert ist, und bei HCL die Position des
  Blocks selbst. Eine im Code gebaute Definition hat keine.
- `Field` ist der fehlerhafte Begriff (`SUP`, `EQUALITY`, `SYNTAX`, `MUST`,
  `NAME` ...), und `Ref` das, worauf sich der Fehler bezieht: der undefinierte
  Name oder die OID, oder die andere Definition, mit ihren `RefOID` und
  `RefPos`. Bei einem Duplikat ist es die erste Definition, und die Meldung
  sagt, wo sie steht.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap/schema"
)

// An object class whose superclass is defined nowhere.
const site = `# site.schema
objectclass ( 1.3.6.1.4.1.99999.1.1 NAME 'siteMember'
	SUP top AUXILIARY )
objectclass ( 1.3.6.1.4.1.99999.1.2 NAME 'siteGuest'
	SUP nobody AUXILIARY )
`

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "site.schema", Data: []byte(site)})
	_, err := schema.Build(files...)

	var be *schema.BuildError
	if !errors.As(err, &be) {
		fmt.Println("not a BuildError:", err)
		return
	}
	fmt.Println("error:  ", be)
	fmt.Println("Kind:   ", be.Kind)
	fmt.Println("Element:", be.Element)
	fmt.Println("OID:    ", be.OID)
	fmt.Println("Name:   ", be.Name)
	fmt.Println("Field:  ", be.Field)
	fmt.Println("Ref:    ", be.Ref)
	fmt.Println("Pos:    ", be.Pos)
	fmt.Println("RefPos: ", be.RefPos.IsValid())
	fmt.Println("is UnknownReference:", be.Kind == schema.UnknownReference)
}
```

```
error:   site.schema:4:1: schema: the object class siteGuest has the superclass nobody, which is not defined
Kind:    unknown reference
Element: object class
OID:     1.3.6.1.4.1.99999.1.2
Name:    siteGuest
Field:   SUP
Ref:     nobody
Pos:     site.schema:4:1
RefPos:  false
is UnknownReference: true
```

Aus einem leeren Modul mit `github.com/go-authn/ldap` v0.10.1 ausgeführt. Die
erste Klasse ist in Ordnung; die zweite beginnt in Zeile 4, und sonst ist
nichts fehlerhaft, daher ist `RefPos` leer. Jede Definition, die `schema.Read`
zurückgibt, trägt ebenfalls eine `Pos`, und das `String` der Position lässt die
Spalte weg, wenn sie nicht bekannt ist.

## DIT-Content-Rules, Name Forms und DIT-Structure-Rules {#rules}

Ab v0.11.0 werden die drei Arten von Definitionen, die RFC 4512 §4.1.6 (DIT-Content-Rules)
und §4.1.7 (Name Forms, DIT-Structure-Rules) definiert und die dieses Paket bis dahin
ablehnte, gelesen, gebaut, durchgesetzt und veröffentlicht.

- **Typen.** `schema.DITContentRule`, `schema.NameForm` und
  `schema.DITStructureRule`, mit den strengen RFC-4512-Parsern
  `ParseDITContentRule`, `ParseNameForm` und `ParseDITStructureRule` (gefuzzt von
  `FuzzDefinition`) und Druckern. `schema.MaxRuleID` begrenzt eine Regel-ID auf 2^31-1
  auf jeder Plattform. `Definitions.DITContentRules`, `NameForms` und
  `DITStructureRules` halten, was `Read` zurückgibt.
- **Lesen und Schreiben.** `schema.Read` liest sie aus `.schema`-Dateien
  (`ditcontentrule`, die Direktive von slapd.conf(5), sowie `nameform` und
  `ditstructurerule` dieses Pakets, für die slapd keine hat) und aus LDIF
  (`olcDitContentRules`, `dITContentRules`, `nameForms`, `dITStructureRules`),
  Terme in beliebiger Reihenfolge, wie libldap sie liest. `Format` schreibt sie zurück. Vor
  v0.11.0 wurden diese Attribute abgelehnt.
- **Bauen.** `Build` verknüpft sie: Jede Klasse, jeder Typ, jede Name Form und jede
  übergeordnete Regel muss definiert sein; eine Content-Rule gilt für eine strukturelle Klasse, und ihre `AUX`
  sind Hilfsklassen; eine Name Form nennt eine strukturelle Klasse; Regel-IDs und Namen sind
  eindeutig. Es gibt zwei neue `BuildErrorKind`s, `DuplicateMember` und
  `PrecludedRequired`, und drei neue `Element`s, `ElementDITContentRule`,
  `ElementNameForm` und `ElementDITStructureRule`. `Schema` hat
  `DITContentRules`, `NameForms`, `DITStructureRules`, `DITContentRule(name)`,
  `DITContentRuleOf(class)`, `NameForm(name)` und `DITStructureRule(id)`.
- **Durchsetzen.** `Validate` setzt die aktive Content-Rule der strukturellen Klasse des Eintrags
  (`AUX`, `MUST`, `MAY`, `NOT`) und seine aktiven Name Forms durch, mit
  neuen `ProblemKind`s `AuxiliaryNotAllowed`, `Precluded`, `NameFormViolation` und
  `NoStructureRule`. Wo im Baum ein Eintrag stehen darf, braucht seinen Vorgänger, daher
  ist es `Schema.GoverningStructureRule(entry, superior)`: die Structure-Rule, die
  einen Eintrag unter der Regel eines Vorgängers regiert, oder, bei einem nil-Vorgänger, an der Wurzel
  des Teilbaums. Ohne aktive Structure-Rule gibt sie nil und keinen Fehler zurück.
  `Validate` liefert für ein Schema ohne Regeln dasselbe Ergebnis wie zuvor.
- **Veröffentlichen.** `cn=Subschema` veröffentlicht `dITContentRules`, `nameForms` und
  `dITStructureRules`, wenn das Schema welche hat.
- **Außerdem.** Die Syntaxen 1.3.6.1.4.1.1466.115.121.1.16, .17 und .35 werden
  geprüft. `hclschema` hat die Blöcke `dit_content_rule`, `name_form` und
  `dit_structure_rule`, und `ldapschema` konvertiert und prüft sie (siehe
  [unten](#hcl2-and-the-converter)). `bench/libldap` vergleicht die drei Parser
  mit denen von libldap.

Ein durchgespieltes Beispiel, unter dem Beispiel-Arc 1.3.6.1.4.1.99999: eine Content-Rule für
`inetOrgPerson` (`posixAccount` und `uidObject` dürfen hinzugefügt werden; eine Telefonnummer
ist verlangt; eine Beschreibung ist ausgeschlossen), die Name Forms eines Suffixes, von
`ou=`-Containern und von Personen, und die Structure-Rules, die sie platzieren:

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/ldap/schema"
)

const rules = `# rules.schema
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule'
	AUX ( posixAccount $ uidObject )
	MUST telephoneNumber
	NOT description )

nameform ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameform ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameform ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )

ditstructurerule ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
ditstructurerule ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
ditstructurerule ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
`

func attr(name string, values ...string) schema.Attribute {
	a := schema.Attribute{Description: name}
	for _, v := range values {
		a.Values = append(a.Values, []byte(v))
	}
	return a
}

func report(title string, err error) {
	fmt.Println(title)
	var v *schema.ValidationError
	if errors.As(err, &v) {
		for _, p := range v.Problems {
			fmt.Println("  -", p)
		}
		return
	}
	fmt.Println("  ", err)
}

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "rules.schema", Data: []byte(rules)})
	s, err := schema.Build(files...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// erin: an inetOrgPerson with a public key, a description, and no telephone number.
	erin := schema.Entry{DN: "uid=erin,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson", "ldapPublicKey"),
		attr("uid", "erin"), attr("cn", "erin"), attr("sn", "Evans"),
		attr("description", "on call"),
		attr("sshPublicKey", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl erin@example.org"),
	}}
	report("erin:", s.Validate(erin))

	// fay: named by cn, which the name form of inetOrgPerson does not allow.
	fay := schema.Entry{DN: "cn=fay,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson"),
		attr("uid", "fay"), attr("cn", "fay"), attr("sn", "Fox"),
		attr("telephoneNumber", "+33 1 23 45 67 89"),
	}}
	report("fay:", s.Validate(fay))

	// The rule that governs each entry is the superior of the next.
	suffix := schema.Entry{DN: "dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "domain"), attr("dc", "example"),
	}}
	people := schema.Entry{DN: "ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "organizationalUnit"), attr("ou", "people"),
	}}
	root, err := s.GoverningStructureRule(suffix, nil)
	fmt.Println("suffix:", root.Names[0], err)
	ou, err := s.GoverningStructureRule(people, root)
	fmt.Println("ou=people:", ou.Names[0], err)
	gina := schema.Entry{DN: "uid=gina,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson"),
		attr("uid", "gina"), attr("cn", "gina"), attr("sn", "Gray"),
		attr("telephoneNumber", "+33 1 23 45 67 89"),
	}}
	r, err := s.GoverningStructureRule(gina, ou)
	fmt.Println("uid=gina:", r.Names[0], err)
	_, err = s.GoverningStructureRule(gina, root)
	report("uid=gina directly under the suffix:", err)

	// hal: an account with posixAccount, and no content rule for account.
	hal := schema.Entry{DN: "uid=hal,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "account", "posixAccount"),
		attr("uid", "hal"), attr("cn", "hal"), attr("uidNumber", "1001"), attr("gidNumber", "100"),
		attr("homeDirectory", "/home/hal"),
	}}
	report("hal, as slapd allows it:", s.Validate(hal))
	report("hal, with StrictAuxiliary:", s.ValidateWith(hal, schema.ValidateOptions{StrictAuxiliary: true}))
}
```

```
erin:
  - the auxiliary class ldapPublicKey is not in the AUX of the DIT content rule examplePersonRule (RFC 4512 4.1.6)
  - description is precluded by the DIT content rule examplePersonRule (RFC 4512 4.1.6)
  - telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
fay:
  - the RDN (cn) is allowed by no name form of inetOrgPerson: examplePersonForm needs uid
suffix: exampleSuffix <nil>
ou=people: exampleUnit <nil>
uid=gina: examplePersons <nil>
uid=gina directly under the suffix:
  - no DIT structure rule allows inetOrgPerson under an entry governed by the rule exampleSuffix (X.501 13.7.5)
hal, as slapd allows it:
   <nil>
hal, with StrictAuxiliary:
  - the auxiliary class posixAccount is allowed by no DIT content rule: account has none (RFC 4512 2.4.3)
```

Aus einem leeren Modul mit `github.com/go-authn/ldap` v0.11.0 ausgeführt (go1.27.1).
`Validate` nennt **jedes** Problem, wie zuvor: erin verletzt die Content-Rule
gleich auf drei Arten.

**Wo sich das von slapd unterscheidet**, gesagt statt entdeckt:

- slapd implementiert nur Content-Rules: Es hat keine Direktive für Name Forms oder
  Structure-Rules, daher schreibt `Format` die Schlüsselwörter `nameform` und `ditstructurerule`,
  die slapd ablehnt. `ditcontentrule` ist die von slapd.
- Eine `OBSOLETE`-Regel ist inaktiv (RFC 4512 §4.1.6): Sie regiert nichts. slapd
  lehnt stattdessen den Eintrag ab.
- Ohne Content-Rule sind Hilfsklassen erlaubt. Das ist das Verhalten von slapd:
  sein Flag `SLAP_DISALLOW_AUX_WO_CR` wird von keinem `disallow`-Schlüsselwort gesetzt.
  `ValidateOptions{StrictAuxiliary: true}` liefert RFC 4512 §2.4.3,
  wie `hal` oben zeigt.
- libldap kann das `SUP` einer Structure-Rule nicht lesen.

`hclschema.Decode` lehnt jetzt einen String ab, der kein gültiges UTF-8 ist: Es nahm
einen an, der dann zu einem anderen String kodierte (gefunden von `FuzzDecode`).
[authnd]({{< relref "/authnd/schemas.md#rules" >}}) lädt diese Definitionen
aus seinen `schema_files` und dem `schema { }`-Block und setzt sie auf den Baum
und die Einträge durch, die es veröffentlicht.

## Schemas in HCL2, und der Konverter {#hcl2-and-the-converter}

Ab v0.9.0 lässt sich ein Schema auch in HCL2 schreiben, nicht nur in den
Dateien, die slapd liest. Das Paket `schema/hclschema` dekodiert HCL2 in
dieselben `*schema.Definitions`, die `schema.Read` liefert, und kodiert sie
wieder zurück (`hclschema.Decode`, `hclschema.Encode`); `schema` selbst hängt
nicht von HCL ab. Ein Block ist eine Definition, und sein Typ sagt, welche:
`object_identifier`, `ldap_syntax`, `matching_rule`, `attribute_type` oder
`object_class`. Das Label ist der erste NAME. Die Attribute sind die Begriffe
aus RFC 4512 §4.1, kleingeschrieben und mit Unterstrichen (`desc`, `sup`,
`equality`, `single_value`, `kind`, `must`, `may` und so weiter), und das
`{len}` einer Syntax heißt `syntax_len`.

**Nur Literalwerte.** Ein Wert ist eine Zeichenkette in Anführungszeichen, eine
Zahl, ein Boolean oder eine Liste davon. Eine Variable, eine Funktion, ein
Operator oder eine `${...}`-Vorlage wird abgelehnt, bevor irgendetwas
ausgewertet wird; ein Schema zu lesen führt es also nie aus. Jedes Feld prüft
der strenge Parser aus RFC 4512, und Fehler, die eine Position brauchen,
kommen mit Datei, Zeile und Spalte.

Der Befehl `ldapschema` konvertiert zwischen den Formaten:

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.11.0
```

- `ldapschema to-hcl [--macros] FILE...` liest `.schema`-Dateien von OpenLDAP,
  cn=config-LDIF und Subschema-LDIF und schreibt HCL2.
- `ldapschema to-schema [--macros] FILE...` liest HCL2 und schreibt eine
  OpenLDAP-`.schema`-Datei.
- `ldapschema check FILE...` baut die Definitionen auf `schema.Standard()` auf
  und berichtet.

Die Ausgabe geht auf stdout. Der Exit-Status ist 0, wenn der Befehl
funktioniert hat, 1, wenn eine Datei oder eine Definition abgelehnt wird, und 2
bei einem Aufruffehler.

**Die Leser lesen Dateien wie slapd**, weil veröffentlichte Schemas für slapd
geschrieben sind: Begriffe in beliebiger Reihenfolge, die Zeilenfortsetzung von
slapd in einer `.schema`-Datei und die Faltung nach RFC 2849 in LDIF,
Base64-Werte, das Präfix `{N}` von cn=config und `objectidentifier`-Makros,
aufgelöst in der Reihenfolge der Dateien. Die exportierten `Parse*`-Funktionen
und das, was ein Server veröffentlicht, bleiben streng RFC 4512.

Ein Beispiel, aus einem leeren Verzeichnis mit `ldapschema` v0.10.1 ausgeführt.
Das Schema ist für diese Seite erfunden: 1.3.6.1.4.1.99999 ist ein privater
Beispiel-Bogen, niemandem zugeteilt. Ein Makro, ein Attributtyp, eine
Hilfsklasse:

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1 NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1 NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top AUXILIARY
	MAY siteBadge )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

attribute_type "siteBadge" {
  oid          = "1.3.6.1.4.1.99999.1.1"
  desc         = "the badge number"
  equality     = "caseIgnoreMatch"
  syntax       = "1.3.6.1.4.1.1466.115.121.1.15"
  syntax_len   = 32
  single_value = true
}

object_class "sitePerson" {
  oid  = "1.3.6.1.4.1.99999.2.1"
  desc = "a person with a badge"
  sup  = ["top"]
  kind = "auxiliary"
  may  = ["siteBadge"]
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( 1.3.6.1.4.1.99999.1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( 1.3.6.1.4.1.99999.2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 1 attribute types, 1 object classes
build: ok, 2 definitions added to schema.Standard()
```

Numerische OIDs sind die Standardausgabe, weil ein Client sie im Subschema
sieht; `--macros` behält die Makronamen. `check` meldet außerdem die
Definitionen, die `schema.Standard()` schon hat, und jeden Verweis, den nichts
definiert, wo `Build` beim ersten aufhört.

**Ab v0.11.0 konvertiert `ldapschema` auch die drei Arten von [Regeln](#rules)**:
`ditcontentrule`, `nameform` und `ditstructurerule` in einer `.schema`-Datei und
die Blöcke `dit_content_rule`, `name_form` und `dit_structure_rule` in HCL. Eine
Structure-Rule wird mit ihrem ersten NAME benannt und hat eine `id`, die `form`, die sie
platziert, und die `sup`-Regeln (IDs), unter denen sie steht; `check` meldet jeden fehlenden
Verweis, den sie machen. Ausgeführt aus einem leeren Verzeichnis mit `ldapschema` v0.11.0
(mit `go install` aus dem Tag gebaut), ein Schema mit je einer:

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

# inetOrgPerson: may carry uidObject, must have a telephone number.
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'sitePersonRule'
	AUX uidObject
	MUST telephoneNumber )

nameform ( site:9.1 NAME 'siteDomainForm' OC domain MUST dc )

ditstructurerule ( 1 NAME 'siteSuffix' FORM siteDomainForm )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

dit_content_rule "sitePersonRule" {
  oid  = "2.16.840.1.113730.3.2.2"
  aux  = ["uidObject"]
  must = ["telephoneNumber"]
}

name_form "siteDomainForm" {
  oid  = "1.3.6.1.4.1.99999.9.1"
  oc   = "domain"
  must = ["dc"]
}

dit_structure_rule "siteSuffix" {
  id   = 1
  form = "siteDomainForm"
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

ditcontentrule ( 2.16.840.1.113730.3.2.2
	NAME 'sitePersonRule'
	AUX uidObject
	MUST telephoneNumber )

nameform ( site:9.1
	NAME 'siteDomainForm'
	OC domain
	MUST dc )

ditstructurerule ( 1
	NAME 'siteSuffix'
	FORM siteDomainForm )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 1 name forms, 1 DIT structure rules
build: ok, 3 definitions added to schema.Standard()
```

**`check` kann bei einer Datei, die slapd lädt, mit Status 1 enden.** Das
`core.schema` von OpenLDAP verweist auf vier Dinge, die slapd eingebaut hat und
die `schema.Standard()` nicht definiert: die Syntaxen
1.3.6.1.4.1.1466.115.121.1.42 und 1.3.6.1.4.1.1466.115.121.1.43 sowie die
Matching-Regeln `protocolInformationMatch` und `presentationAddressMatch`.
`ldapschema check core.schema` listet sie als `missing:` auf und endet mit
Status 1. Das ist zu lesen als »hier nicht definiert«, nicht als Mangel der
Datei.

**Was nicht unterstützt wird:** `include`-Anweisungen, denn eine `.schema`-Datei wird als
Definitionen gelesen und nicht wie eine slapd-Konfiguration ausgeführt; und
`X-SUBST` bei `ldapsyntax`.

**Veröffentlichte Schemas lassen sich konvertieren.** Die Version wurde an den
Dateien `core`, `cosine`, `inetorgperson` und `nis` von OpenLDAP gemessen, an
SUPANN 2021 von RENATER, an eduPerson von REFEDS und am Schema von Samba: bei
jedem ergeben `.schema` nach HCL und zurück sowie LDIF gegen `.schema` gleiche
Definitionen. Nur die Dateien von OpenLDAP liegen im Repository. SUPANN und
eduPerson werden hier nicht wiedergegeben; lesen Sie sie auf den Seiten ihrer
Autoren:
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)
und [eduPerson](https://github.com/REFEDS/eduperson).

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

[pkg.go.dev/github.com/go-authn/ldap](https://pkg.go.dev/github.com/go-authn/ldap)
