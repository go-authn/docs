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
go get github.com/go-authn/ldap@v0.9.0
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

Absichtlich nicht vorhanden: DIT-Content-Rules, DIT-Structure-Rules und Name-Forms;
das Ändern des Schemas über LDAP; die Zertifikats-Matching-Regeln aus RFC 4523
und `directoryStringFirstComponentMatch`, die definiert und nicht
implementiert sind, sodass Assertions, die sie verwenden, Undefined sind; kollektive Attribute;
andere Optionen als `lang-` und `binary`.

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}) stellt
dieses Schema bereit und misst jeden Eintrag, den es veröffentlicht, daran.

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
go install github.com/go-authn/ldap/cmd/ldapschema@v0.9.0
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

Ein Beispiel, aus einem leeren Verzeichnis mit `ldapschema` v0.9.0 ausgeführt.
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

**`check` kann bei einer Datei, die slapd lädt, mit Status 1 enden.** Das
`core.schema` von OpenLDAP verweist auf vier Dinge, die slapd eingebaut hat und
die `schema.Standard()` nicht definiert: die Syntaxen
1.3.6.1.4.1.1466.115.121.1.42 und 1.3.6.1.4.1.1466.115.121.1.43 sowie die
Matching-Regeln `protocolInformationMatch` und `presentationAddressMatch`.
`ldapschema check core.schema` listet sie als `missing:` auf und endet mit
Status 1. Das ist zu lesen als »hier nicht definiert«, nicht als Mangel der
Datei.

**Was nicht unterstützt wird:** DIT-Content-Regeln, DIT-Structure-Regeln und
Name Forms; `include`-Anweisungen, denn eine `.schema`-Datei wird als
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

[pkg.go.dev/github.com/go-authn/ldap@v0.9.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.9.0)
