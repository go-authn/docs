---
title: "directory – wer jemand ist und was das beweist"
linkTitle: "directory"
weight: 50
description: "go-authn/directory: ein Modell einer Person und der Anmeldedaten, die eine Quelle für sie hält, über einer Liste im Speicher, einer SQL-Datenbank, einem LDAP-Server oder einer HCL-Konfiguration."
tags: [bibliotheken, verzeichnis, ldap, sql]
---

**Wer ist jemand, und was kann das beweisen?** Ein Modell über einer Liste im
Speicher, einer SQL-Datenbank, einem LDAP-Server oder `user`- und `group`-Blöcken in einer
Konfigurationsdatei – und worauf es ankommt, ist die zweite Hälfte der Frage.

```sh
go get github.com/go-authn/directory@v0.14.0
```

## Was jemanden beweist, ist nicht eine einzige Sache {#what-proves-somebody-is-not-one-thing}

Das ist eine Tatsache über Protokolle. NTLMv2 (SMB) ist ein Challenge-Response-Verfahren: Der Client
sendet nie das Passwort, also muss der Server das Passwort halten oder
`MD4(UTF16LE(password))` – den NT-Hash –, und **ein LDAP-Bind kann keine
SMB-Sitzung authentifizieren**. Ein KDC muss mit dem Schlüssel der Person *entschlüsseln*, also
kann nur eine Quelle, die das Passwort hält, einen Realm tragen. SSH braucht einen öffentlichen Schlüssel.
Ein zweiter Faktor braucht das Geheimnis hinter den sechs Ziffern.

Daher sagt eine `Identity`, welche `Credential`s ihre Quelle geliefert hat – `Password`,
`NTHash`, `Verifier` (ein Hash-Vergleich oder ein Bind), `PublicKeys`,
`TOTPSecret` –, und mit `Identity.Can` kann ein Server sagen: *Sie können WebDAV nutzen, aber nicht
SMB*, bevor jemand beim Einhängen auf eine Ablehnung stößt. Jedes Protokoll hat seine eigene
Methode:

| | beantwortet | woraus |
|---|---|---|
| `Verify(password)` | alles, dem das Passwort übergeben wird | zuerst der Verifier der Quelle (das kann ein LDAP-Bind sein), sonst das gehaltene Passwort, in konstanter Zeit über SHA-256-Digests verglichen, sodass nicht einmal die Länge durchsickert |
| `NTKey()` | NTLMv2 | der veröffentlichte Hash oder aus dem Passwort abgeleitet; `ErrNoCredential`, wenn keines von beiden vorliegt |
| `Derive(f)`, `KerberosKey(f)` | ein KDC, AWS SigV4 – alles, was das Geheimnis *besitzen* muss | nur das Passwort; die Ableitung ist die Funktion des Aufrufers |
| `Keys()` | SSH | `authorized_keys`-Zeilen |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | eine Spalte oder ein LDAP-Attribut, das der Aufrufer benennt |

## Die Quellen {#the-sources}

| Paket | liest | importiert |
|---|---|---|
| `directory` | eine `Static`-Liste und ein `Set` von Quellen in Reihenfolge | nur die Standardbibliothek |
| `directory/sqldir` | eine beliebige `*sql.DB`, mit **Ihren** Abfragen | keinen Treiber: Das Programm wählt einen |
| `directory/ldapdir` | einen LDAP-Server | `go-ldap/ldap/v3` |
| `directory/hcldir` | einen `users`-Block, der eine Datenbank oder einen LDAP-Server benennt, und `user`-/`group`-Blöcke, die Personen enthalten | `x/crypto/ssh`, `hashicorp/hcl/v2`, `zclconf/go-cty` |
| `directory/ldaptest` | einen LDAP-Server, gegen den getestet wird | `glauth/ldap` |

In einem `Set` gehört ein Name der **ersten** Quelle, die ihn kennt; ein lokal
eingetragenes Dienstkonto muss also nicht ins LDAP. Die Gruppenmitgliedschaft ist die
**Vereinigung** aller Quellen. Quellen werden gelesen, wenn ein Server startet; eine Passwortprüfung
kann jedes Mal die Quelle erreichen, denn ein Bind lässt sich nicht zwischenspeichern,
ohne das Geheimnis zu halten.

`hcldir` dekodiert kein HCL: Der Aufrufer dekodiert den Block und übergibt ihn.
Es importiert HCL nur zum Schreiben, für `SetPassword`. Die Build-Tags `nosql` und
`noldap` lassen eine Art ganz aus `hcldir` heraus.

## Beispiel {#example}

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	local := &directory.Static{
		Name: "the configuration file",
		People: []*directory.Identity{
			directory.NewIdentity("dora", directory.WithPassword("hunter2")),
			directory.NewIdentity("eli", directory.WithVerifier(func(pw string) error {
				return directory.ErrWrongPassword // a bind against somebody else's LDAP, say
			})),
			directory.NewIdentity("svc-backup", directory.WithPublicKeys("ssh-ed25519 AAAA...elided... backup")),
		},
		Groups: map[string][]string{"staff": {"dora", "eli"}, "nobody": {}},
	}
	people := directory.NewSet(local) // more sources after it: sqldir, ldapdir...

	ids, _ := people.Identities()
	for _, id := range ids {
		fmt.Println(id.Name(), "password:", id.Can(directory.Password), "verifier:", id.Can(directory.Verifier),
			"keys:", id.Can(directory.PublicKeys), "from", id.Where())
	}

	// NTLMv2 needs MD4(UTF16LE(password)): dora's can be derived, eli's cannot.
	for _, id := range ids[:2] {
		_, err := id.NTKey()
		fmt.Println(id.Name(), "SMB:", err == nil, errors.Is(err, directory.ErrNoCredential))
	}

	// An empty group is an empty answer; a group nobody has is an error.
	fmt.Println(people.Members("nobody"))
	fmt.Println(people.Members("admins"))

	// @group is expanded; an empty group, or one nobody has, is refused.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	_, err := directory.Expand([]string{"@nobody"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
	_, err = directory.Expand([]string{"@admins"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[] <nil>
[] directory: no such group: "admins", in the configuration file
[dora eli svc-backup] <nil>
[] directory: the group has no members: "nobody": nobody would be allowed
directory: the group has no members: "nobody": nobody would be allowed true false
directory: no such group: "admins", in the configuration file false true
```

Ein gehaltenes Passwort beantwortet auch `Can(Verifier)`: Es lässt sich vergleichen.

{{< callout type="info" >}}
**Eine leere Gruppe ist eine Gruppe: `Members` beantwortet sie, `Expand` lehnt sie ab**

Seit v0.12.0 gibt `Set.Members` für eine Gruppe, die eine Quelle hat, in der
aber niemand ist, eine leere Liste und keinen Fehler zurück, sodass ein Server,
der Gruppen auflistet, sie veröffentlichen kann. `Expand` lehnt sie weiterhin
ab, mit `ErrEmptyGroup`, das nicht `ErrNoSuchGroup` ist: Eine Gruppe, die
niemand hat, ist ein Tippfehler oder eine gelöschte Gruppe, eine leere ist eine
Gruppe, die zu füllen ist. Ein Aufrufer, der eine Gruppe duldet, die nichts
gewährt, prüft auf beide. In v0.11.x gab `Set.Members` für eine leere Gruppe
`ErrNoSuchGroup` zurück, und `Expand` von `@nobody` über das `Set` gab
`[] directory: no such group: "nobody"` aus.
{{< /callout >}}

## Was es ablehnt und warum {#what-it-refuses-and-why}

- **Eine Gruppe, in der niemand ist**, und **eine Gruppe, die keine Quelle
  hat**, wenn `Expand` `@gruppe` in Personen auflöst – Fehler, keine leeren
  Listen: Eine Konfiguration, die niemandem etwas gewährt, liest sich genau wie
  eine, die funktioniert. Die erste ist `ErrEmptyGroup`, die zweite
  `ErrNoSuchGroup`, und `errors.Is` unterscheidet sie. `Set.Members`
  beantwortet eine leere Gruppe mit einer leeren Liste; eine Gruppe, die keine
  Quelle hat, ist auch dort `ErrNoSuchGroup`. Eine Quelle, die *defekt* ist,
  wird getrennt von einer gemeldet, der die Gruppe fehlt, und hat Vorrang vor
  einer leeren Antwort.
- **Ein LDAP-Verzeichnis, das im Klartext erreicht wird.** Ein Simple Bind trägt das
  Passwort selbst (RFC 4513), daher lehnen `ldapdir.New` und ein `users "ldap"`-Block
  `ldap://` zu einer anderen Maschine ab, sofern `StartTLS` nicht gesetzt ist. `ldaps://`,
  `ldapi://` und `ldap://` zu einer Loopback-Adresse werden akzeptiert. Es gibt keinen
  Schalter, um das abzuschalten.
- **Ein leeres Passwort bei einem LDAP-Bind.** In LDAP ist das ein *unauthentifizierter
  Bind*, den die meisten Verzeichnisse mit Erfolg beantworten; `ldapdir` antwortet
  `ErrWrongPassword`, ohne eine Verbindung aufzubauen.
- **Jeder andere fehlgeschlagene Bind, als falsches Passwort gewertet.** Nur das LDAP-Ergebnis 49,
  *invalidCredentials*, ist `ErrWrongPassword`. Eine während des Binds abgebrochene Verbindung
  oder ein Verzeichnis, das „busy“ (51) oder „unavailable“ (52) antwortet, wird als
  `ldapdir: the directory did not answer the bind: …` zurückgegeben, das den LDAP-Fehler umhüllt.
  Das Passwort wird in jedem Fall abgelehnt; was sich ändert, ist, dass das Log eines Servers
  nicht mehr *falsches Passwort* zu jemandem sagt, der es richtig eingegeben hat. Vor v0.11.2
  war jeder fehlgeschlagene Bind `ErrWrongPassword`.
- **Anmeldedaten in einer LDAP-URL** – eine URL wird ausgegeben; `BindDN` und
  `BindPassword` sind Felder.
- **Ein NT-Hash, der nicht 16 Bytes lang ist** (`ParseNTHash`), statt ihn zu einem Hash
  aufzufüllen, der jede Anmeldung als falsches Passwort scheitern lässt.
- **`Derive` oder `KerberosKey` für eine Identität ohne das Passwort.** Das Ja eines
  Verifiers ist kein Schlüssel.

{{< callout type="warning" >}}
**Der NT-Hash und das TOTP-Geheimnis sind Anmeldedaten, keine Hashes davon**

Wer `sambaNTPassword` hält, authentifiziert sich als diese Person genau so, als
hielte man das Passwort selbst; wer ein TOTP-Geheimnis hält, erzeugt jeden künftigen
Code. Der Fehler von `WithVerifier` geht an den Server, nie an den Client.
{{< /callout >}}

## Wogegen es geprüft wird {#what-it-is-checked-against}

- **OpenLDAPs `ldapsearch`** liest das Verzeichnis von `ldaptest` – die Einträge, das
  `sambaNTPassword` der einen Person, die es hat, die Gruppe – und wird bei einem falschen
  Passwort mit „Invalid credentials (49)“ abgelehnt. Die Linux-Lanes der CI
  installieren `ldap-utils`; wo `ldapsearch` fehlt, wird der Test übersprungen, da
  nichts in der CI dieses Moduls dieses Überspringen in einen Fehlschlag verwandelt.
- **`ldapdir` gegen `glauth/ldap`**, einen unabhängigen LDAP-Server, keine Attrappe;
  die Fixture erlaubt den unauthentifizierten Bind, sodass der Test fehlschlägt, wenn `ldapdir`
  aufhört, ihn vorher abzulehnen.
- **`sqldir` gegen eine echte SQLite-Datenbank** über einen echten Treiber.
- **MD4** gegen die Testvektoren aus RFC 1320.

Die Coverage-Lane schlägt unter 85 % fehl (ihr erklärter Standard ist 100 %), und die
Builds mit `nosql` und `noldap` werden in der CI geprüft.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
