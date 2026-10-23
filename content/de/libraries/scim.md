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
go get github.com/go-authn/scim@v0.1.0
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

## Wogegen es geprüft wird {#what-it-is-checked-against}

**Was Identitätsanbieter tatsächlich senden**, mit deren Nutzdaten getestet:
das `"Replace"` von Entra ID, seine Boolean-Werte als Zeichenketten
(`"active": "False"`), sein Entfernen von Mitgliedern per Werteliste, sein
gefiltertes Hinzufügen, das eine E-Mail-Adresse anlegt; Oktas Replace ohne Pfad,
das die `id` wiederholt. Filter, PATCH und der ganze Handler werden gefuzzt
(`FuzzFilter`, `FuzzPatch`, `FuzzServer`), und die Untergrenze der
Coverage-Spur liegt bei 92 %.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
