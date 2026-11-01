---
title: "scim — Personen und Gruppen von einem Identitätsanbieter bereitstellen"
linkTitle: "scim"
weight: 140
description: "go-authn/scim ist ein SCIM-2.0-Service-Provider (RFC 7643, RFC 7644): Users und Groups über ein Backend, das Sie schreiben, mit getesteten Nutzdaten von Entra ID und Okta. Nur Standardbibliothek."
tags: [bibliotheken, scim, provisionierung]
---

**Wen hat der Identitätsanbieter gerade angelegt, geändert oder gelöscht?**
Ein Identitätsanbieter (Entra ID, Okta, Keycloak, …) legt Personen und Gruppen
in Ihrer Anwendung über HTTP an, aktualisiert und löscht sie; dieses Paket ist
dieser HTTP-Endpunkt, für Users und Groups (RFC 7643, RFC 7644), über einem
`Backend`, das Sie schreiben. Reines Go, `CGO_ENABLED=0`, nur Standardbibliothek.

```sh
go get github.com/go-authn/scim@v0.2.0
```

## Beispiel {#example}

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

Der Server vergibt Kennungen, Zeitstempel und Versionen, prüft die Eingabe und
wendet PATCH an; das `Backend` behält, was man ihm gibt, und erzwingt, was nur
es sehen kann: `ErrConflict` für einen vergebenen `userName` (409
`uniqueness`), `InvalidValue` für ein Mitglied, das nicht existiert (400
`invalidValue`), `ErrPrecondition`, wenn die gespeicherte Version nicht die
gelesene ist. `NewMemory()` ist die Referenzimplementierung.

Es bedient `/Users` und `/Groups` (Liste mit `filter`, `startIndex`, `count`,
`attributes`, `excludedAttributes`; Anlegen; Lesen, `PUT`, `PATCH` und `DELETE`
je Kennung mit `ETag` und `If-Match`), `/Users/.search` und `/Groups/.search`
sowie die Discovery-Endpunkte `/ServiceProviderConfig`, `/ResourceTypes` und
`/Schemas`. Die Filter decken die gesamte Grammatik von RFC 7644 §3.4.2.2 ab;
PATCH ist atomar: Eine fehlschlagende Operation lässt die Ressource, wie sie
war.

## Was es ablehnt und warum {#what-it-refuses-and-why}

Alles hier kommt von außen, also gehören die Grenzen zur API:

| | |
|---|---|
| ein Body über `MaxBodyBytes` (1 MiB), ein PATCH mit mehr als `MaxOperations` (100) oder einer, der die Ressource über die Body-Grenze wachsen lässt | 413 |
| eine Gruppe mit mehr als `MaxMembers` (10 000) | 400 `invalidValue` |
| ein Filter über 4 KiB, tiefer als 32 verschachtelt, mit unbekanntem Operator oder `gt` auf einem Boolean | 400 `invalidFilter` |
| Schreibzugriffe auf `id`, `meta`, `schemas` oder die `groups` eines Benutzers | 400 `mutability` |
| eine Ressource ohne ihr Kernschema, ein `userName`, der leer ist, über 256 Bytes lang ist oder Steuerzeichen enthält, zwei primäre E-Mail-Adressen | 400 |
| ein fehlendes oder falsches Bearer-Token (`BearerAuth`, in konstanter Zeit; ein leeres Token lässt niemanden ein) | 401 |
| jeder Backend-Fehler, der keine der Sentinels ist | 500 mit einem Body, der nichts sagt; der Fehler geht an `ErrorLog` |

**Nicht unterstützt**: Bulk-Operationen, Sortierung, Passwortänderungen, `/Me`
(als solche in `/ServiceProviderConfig` angekündigt).

## Was v0.2.0 geändert hat {#v020}

Nach einem Audit, einem Fuzzing- und Chaos-Durchgang und einem Performance-Durchgang. Was
ein Aufrufer sehen kann:

- **`Server.ReadTimeout`**, neu, Standard 30 s: Ein Request-Body, der länger zum
  Eintreffen braucht, wird mit einem 400 abgeschnitten. Er ersetzt das eigene
  `ReadTimeout` des `http.Server` für die Anfrage; ein negativer Wert lässt das des
  `http.Server` unberührt.
- **`ConditionalDeleter`**, eine neue optionale Schnittstelle, die ein `Backend`
  implementieren kann (`DeleteUserIf`, `DeleteGroupIf`), was `Memory` tut. `DELETE` mit
  `If-Match` prüfte die Version und löschte in zwei Schritten, sodass ein Schreibvorgang,
  der dazwischen landete, ungesehen gelöscht wurde.
- **Ein verlorenes Rennen wird wiederholt.** Ein `PATCH` oder `PUT` ohne `If-Match`, der
  ein Rennen gegen einen anderen Schreiber verlor, wurde mit 412 beantwortet, obwohl der
  Client keine Vorbedingung verlangt hatte; er wird jetzt auf der neueren Version
  wiederholt, höchstens 32-mal. Mit `If-Match` bleibt die Antwort 412. Von 24 gleichzeitigen
  PATCHes ohne `If-Match` scheiterten vorher 9 mit 412 und jetzt keiner.
- Das Entfernen eines Mitglieds oder eines beliebigen Elements über einen Filter, der
  nichts trifft, gelingt; es war ein 400 `noTarget` (RFC 7644 §3.5.2.2).
- Ein PATCH ohne Pfad wendet seine Schlüssel in sortierter Reihenfolge an; er nutzte die
  Reihenfolge der Map, sodass `name` und `name.givenName` in einem Objekt von Lauf zu Lauf
  eine andere Ressource ergaben.
- `BearerAuth` akzeptiert den Schemanamen in jeder Schreibweise (`bearer <token>`, RFC 7235
  §2.1).
- `startIndex` und `count` werden begrenzt, gleich wie groß ein `int` ist: Ein Wert darüber
  war auf 32-Bit-Zielen ein 400 und auf 64-Bit-Zielen eine begrenzte Seite.
- Ein `Filter.Equality()` gibt einem `Backend` den dekodierten String. Er ist Daten:
  Als Parameter an die Datenbank übergeben und nie in eine Abfrage einsetzen.

Bulk-Operationen, Sortierung und Passwortänderungen bleiben nicht unterstützt.

**Allokationen** einer Listenanfrage über 10.000 Benutzer und 200 Gruppen auf `Memory`,
exakt, aus `go test -bench`, Apple M4 Max:

| Listenanfrage | vorher | nachher |
|---|---|---|
| eine Seite mit 100 | 789.417 Allokationen, 47,7 MB | 14.952 Allokationen, 6,0 MB |
| `userName eq` | 797.979 Allokationen, 47,7 MB | 90 Allokationen, 12,6 KB |
| ein Filter, der jeden Benutzer durchläuft (`name.givenName eq` und `emails[...]`) | 818.847 Allokationen, 48 MB | 361.098 Allokationen, 29,7 MB |

Die Wanduhrzeit wurde nicht gemessen: Die Last lag bei 65, und die Regel verlangt unter 9.
Die verrauschten Einzelläufe (etwa 1,7 s zu 0,06 s für den durchlaufenden Filter) sind kein
Ergebnis. `FuzzPatchPath`, `FuzzPatchThenDecode`, `FuzzFilter` und `FuzzServer` liefen je
45 s mit 16 Workern, 1,3 bis 2,4 Millionen Ausführungen, und fanden keinen Fehler.

## Wogegen es geprüft wird {#what-it-is-checked-against}

**Was Identitätsanbieter tatsächlich senden**, mit deren Nutzdaten getestet:
das `"Replace"` von Entra ID, seine Boolean-Werte als Zeichenketten
(`"active": "False"`), sein Entfernen von Mitgliedern per Werteliste, sein
gefiltertes Hinzufügen, das eine E-Mail-Adresse anlegt; Oktas Replace ohne Pfad,
das die `id` wiederholt. Filter, PATCH und der ganze Handler werden gefuzzt
(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), und die Untergrenze der
Coverage-Spur liegt bei 92 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.2.0](https://pkg.go.dev/github.com/go-authn/scim@v0.2.0)
