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
go get github.com/go-authn/directory@v0.16.0
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
ohne das Geheimnis zu halten. Eine Quelle, die `GroupReader` implementiert (sqldir und
ldapdir tun das), liest alle Gruppen einmal im Block; `Set.Frozen()` beantwortet dann
`Members`, `GroupAttributes`, `GroupObjectClasses` und `GroupNames` aus dem Speicher,
mit der eigenen Zusammenführung des Sets. Schließen Sie das ursprüngliche Set, nicht das eingefrorene.

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

## Attribute {#attributes}

Ab v0.13.0 kann eine `Identity` **Attribute** tragen: was eine Quelle über jemanden
sagt, das nichts beweist – eine `uidNumber`, ein Home-Verzeichnis, eine
Mailadresse. Sie werden absichtlich von Anmeldedaten getrennt gehalten: Anmeldedaten
entscheiden, wer sich anmelden darf, ein Attribut wird an alle *veröffentlicht*, die suchen
dürfen. Ein Server wie [authnd]({{< relref "/authnd/entries.md" >}}) macht daraus
die Attribute eines LDAP-Eintrags, und sein Schema entscheidet, was der
Eintrag ist.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	a, err := directory.NewAttributes(
		directory.Attribute{Name: "uidNumber", Values: []string{"1000"}},
		directory.Attribute{Name: "mail", Values: []string{"dora@example.org"}},
		directory.Attribute{Name: "MAIL", Values: []string{"d.explorer@example.org", "dora@example.org"}},
	)
	fmt.Println(err)
	dora := directory.NewIdentity("dora", directory.WithPassword("hunter2"), directory.WithAttributes(a))
	fmt.Println(dora.Attributes().Names(), dora.Attributes().Get("UIDNUMBER"), dora.Attributes().Get("mail"))

	// What is published cannot hold a secret, nor what a server derives or answers itself.
	for _, name := range []string{"userPassword", "sambaNTPassword", "radiusHash", "cn", "memberUid", "2.5.4.35"} {
		_, err := directory.NewAttributes(directory.Attribute{Name: name, Values: []string{"x"}})
		fmt.Println(errors.Is(err, directory.ErrAttributeName), err)
	}
}
```

```
<nil>
[uidNumber mail] [1000] [dora@example.org d.explorer@example.org]
true directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "sambaNTPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "radiusHash" looks like it holds a secret (its name contains "hash"), and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "cn" is derived by the server from the name it publishes the entry under
true directory: not an attribute this package carries: "memberUid" is membership, which Members answers: a second answer would disagree with it
true directory: not an attribute this package carries: "2.5.4.35" is an OID: name it by its descriptor, so that what is refused by name stays refused
```

Namen sind Attributbeschreibungen nach RFC 4512, verglichen ohne Beachtung von Groß- und
Kleinschreibung und der Reihenfolge der Optionen, sodass `mail` und `MAIL` ein Attribut sind,
geschrieben so, wie es zuerst angegeben wurde; eine exakte Wiederholung eines Werts wird einmal
behalten. Werte sind Zeichenketten und werden nicht interpretiert: `"1000"` ist eine `uidNumber`, weil
das Schema eines Servers es so sagt. Ein leerer Wert oder gar keiner wird abgelehnt.

| abgelehnt | warum |
|---|---|
| 56 benannte Geheimnisse – `userPassword`, `authPassword`, `userPKCS12`, `sambaNTPassword`, `sambaLMPassword`, `unicodePwd`, `krbPrincipalKey`, `krb5Key`, `ipaNTHash`, `ipatokenOTPkey`, `oathSecret`, `olcRootPW`, … | abgelesen aus RFC 4519, RFC 3112, RFC 2798 und den Schemata von Samba, Active Directory, MIT- und Heimdal-Kerberos, FreeIPA, 389-ds und OpenLDAP |
| jeder Name, der `password`, `passwd`, `pwd`, `secret`, `credential`, `hash` oder `privatekey` enthält | eine Liste kennt nur die Schemata, die jemand gelesen hat; der eine Standardname, den dies erfassen würde, `secretary` (RFC 4524), ist erlaubt |
| `sshPublicKey` | es hat seinen eigenen Weg, `WithPublicKeys`, damit `Can(PublicKeys)` wahr bleibt |
| `uid`, `userid`, `cn`, `commonName`, `objectClass` | ein Server leitet sie aus dem Namen ab, unter dem er den Eintrag veröffentlicht |
| `member`, `uniqueMember`, `memberUid`, `memberOf` | Mitgliedschaft ist das, was `Members` beantwortet, und eine zweite Antwort würde widersprechen |
| `createTimestamp`, `modifyTimestamp`, `creatorsName`, `modifiersName`, `structuralObjectClass`, `governingStructureRule`, `subschemaSubentry`, `entryDN`, `entryUUID` | ein Server pflegt sie; eine Konfiguration könnte sie nur fälschen |
| ein Name in numerischer Form | Ablehnungen erfolgen nach Namen, und `2.5.4.35` *ist* `userPassword` |

`ReservedAttributes()` gibt die ganze Liste zurück, 75 Namen mit ihren Gründen;
`CheckAttributeName` wendet die Regel allein an, sodass eine Konfiguration
abgelehnt werden kann, bevor irgendetwas gelesen wird.

Woher sie kommen:

- **`hcldir`**: `attributes = { … }` in `user`- und `group`-Blöcken, eine Zeichenkette
  oder eine Liste von Zeichenketten pro Name; eine Zahl wird abgelehnt, mit der Korrektur in der
  Meldung (*write it as a string, "1000"*), und `null` lässt das Attribut
  weg.
- **`sqldir`**: zwei optionale Abfragen, `users_attributes` und
  `groups_attributes` (`Queries.PeopleAttributes`, `GroupAttributes`), gelesen
  **nach Spaltenalias**: Die erste Spalte ist der Name, jede weitere Spalte ein
  Attribut, benannt nach ihrem Alias. Eine Spalte, deren Alias keine Attributbeschreibung
  ist oder Anmeldedaten benennt, wird mit ihrer Spaltennummer abgelehnt,
  bevor eine Zeile gelesen wird. `NULL` und `''` gelten als fehlend, und mehrere Zeilen für einen
  Namen fügen Werte hinzu. Eine Gruppe, die nur dort genannt wird, existiert, ohne jemanden darin.
  ⛔ PostgreSQL wandelt einen Alias ohne Anführungszeichen in Kleinbuchstaben um (`as uidNumber` kommt als
  `uidnumber` zurück): dasselbe Attribut, in der Schreibweise der Datenbank. Setzen Sie ihn in Anführungszeichen,
  `as "uidNumber"`, wo die Schreibweise zählt.
- **`ldapdir`**: `Config.Attributes` und `GroupAttributes` (`attributes`
  und `group_attributes` in einem `users "ldap"`-Block) benennen, was aus dem
  Eintrag jeder Person und jeder Gruppe kopiert wird, abgeglichen nach RFC-4512-Äquivalenz und
  in der konfigurierten Schreibweise behalten. Über die obige Liste hinaus lehnt es das
  `totp_attribute` sowie das Benennungs- und das Mitgliedsattribut der Gruppe ab. Ein Subtyp,
  den das Verzeichnis zusätzlich liefert (`description;lang-fr` für `description`), wird
  nicht kopiert: Verlangen Sie ihn namentlich.

Die Attribute einer Gruppe kommen aus `Set.GroupAttributes`, über den optionalen
`GroupAttributer`: **Die erste Quelle, die ein Attribut liefert, besitzt es**, sodass eine
`gidNumber` in einer lokalen Datei die des Verzeichnisses überschreibt, während eine `description`,
die nur das Verzeichnis hat, durchkommt, und eine defekte Quelle ist ein Fehler, auch
wenn eine andere geantwortet hat. Die Attribute einer Person kommen mit der Person, von der
Quelle, der der Name gehört.

## Objektklassen {#object-classes}

Ab v0.15.0 kann eine Quelle die Hilfsklassen (AUXILIARY) **deklarieren**, die ihre Personen
und Gruppen tragen, damit ein Server wie
[authnd]({{< relref "/authnd/schemas.md" >}}) ein Standort-Schema
(SUPANN, eduPerson) veröffentlichen kann. Eine Klasse verspricht die Gestalt jedes Eintrags
(RFC 4512 §4.1.1), also wird sie nie aus den vorhandenen Attributen abgeleitet und nie
aus den Daten gelesen: keine Datenbankspalte, kein `objectClass`-Wert des Upstreams. Ein
Attribut, das in einer Datenbank auftaucht, kann eine veröffentlichte Klasse nicht ändern.

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	c, err := directory.NewObjectClasses("supannPerson", "eduPerson", "EDUPERSON")
	fmt.Println(c.Names(), err)
	ann := directory.NewIdentity("ann", directory.WithPassword("hunter2"), directory.WithObjectClasses(c))
	fmt.Println(ann.ObjectClasses())
	fmt.Println(directory.NewIdentity("bob").ObjectClasses())

	// A class is a name, never a number or a filter.
	for _, name := range []string{"edu Person", "1.3.6.1.4.1.5923.1.1.2", "x)(objectClass=*"} {
		_, err := directory.NewObjectClasses("eduPerson", name)
		fmt.Println(errors.Is(err, directory.ErrObjectClassName), err)
	}
}
```

```
[supannPerson eduPerson] <nil>
[supannPerson eduPerson]
[]
true directory: not an object class name: "edu Person" is not a descriptor: a letter, then letters, digits and hyphens (RFC 4512 §1.4)
true directory: not an object class name: "1.3.6.1.4.1.5923.1.1.2" is an OID: name the class by its descriptor, so that what is refused by name stays refused
true directory: not an object class name: "x)(objectClass=*" is not a descriptor: a letter, then letters, digits and hyphens (RFC 4512 §1.4)
```

Namen werden in der geschriebenen Reihenfolge, je einmal und ohne Beachtung der Groß- und
Kleinschreibung gehalten (`EDUPERSON` wiederholt `eduPerson`). Dieses Paket prüft nur die
**Schreibweise**, einen Deskriptor nach RFC 4512: numerische OIDs, Leerzeichen,
Anführungszeichen und Klammern werden abgelehnt, und die Ablehnung wird gefuzzt. Ob eine Klasse
definiert und AUXILIARY ist und keine, die der Server selbst ableitet, prüft der Server
gegen das Schema, das er bereitstellt.

Woher sie kommen:

- **`hcldir`**: `object_classes` und `group_object_classes` in einem `users`-Block
  beider Arten, und `object_classes` in einem `user`- und einem `group`-Block.
  Ein Fehler trägt die Position in der Konfiguration.
- **`sqldir`**: `WithObjectClasses` und `WithGroupObjectClasses`.
- **`ldapdir`**: `Config.ObjectClasses` und `Config.GroupObjectClasses`.

`Identity.ObjectClasses()` gibt eine Kopie der Liste einer Person zurück. Die einer Gruppe
kommen aus `Set.GroupObjectClasses`, über den optionalen `GroupObjectClasser`,
neben `GroupAttributer`. **Die erste Quelle, die die Gruppe hat und Klassen deklariert,
entscheidet, ganz**: Eine Quelle, die nichts deklariert, entscheidet nicht, und die
abweichende Liste einer späteren Quelle wird ignoriert, weder zusammengeführt noch ein
Fehler. (authnd sagt es in `check`.)

`sqldir.ClosesDB()` übergibt einer Quelle eine Datenbank, und `(*sqldir.Source).Close`
schließt sie; `hcldir.Open` gibt nun die `*sqldir.Source` selbst zurück.

## Die Standardwerte von ldapdir {#ldapdir-defaults}

| Einstellung (`users "ldap"` / `ldapdir.Config`) | Standard ab v0.14.0 | bis v0.13.0 |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`, `ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | derselbe |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | derselbe |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`, `ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | derselbe |
| `group_member_attribute` / `MemberAttribute` | keiner: `memberUid` (Namen) **und** `member` (DNs); gesetzt, ist es das eine Attribut, das gelesen wird | `memberUid` |

Die drei Klassen sind die Standardklassen, die eine `uid` tragen: `posixAccount`
(RFC 2307), `account` (RFC 4524 §3.1) und `uidObject` (RFC 4519 §3.14).
go-authn/authnd ab v0.11.0 veröffentlicht eine Person ohne die POSIX-Attribute
als `account` oder `inetOrgPerson`, setzt `uidObject` auf jede Person und
veröffentlicht eine Gruppe ohne `gidNumber` als `groupOfNames`. Mit den alten
Standardwerten wurden solche Personen und Gruppen überhaupt nicht gelesen.

{{< callout type="warning" >}}
**v0.14.0 erweitert, was das Verzeichnis einer Einrichtung liefert**

Ein Verzeichnis mit `account`- oder `uidObject`-Einträgen, die keine
posixAccounts sind – Dienstkonten, per uid benannte Hosts, von anderswo importierte
Personen –, gibt sie nun an jedes Programm weiter, das den Standard beibehalten hat, und jeder
davon kann dann per Bind gegen das Verzeichnis geprüft werden. Seine
`groupOfNames`-Gruppen werden zu Gruppen, und eine `@group`-Regel, die eine davon nennt,
gewährt nun, was sie sagt. Ein einfaches `inetOrgPerson` ohne eine der drei Klassen
wird weiterhin nicht gelesen. Um genau die alte Menge zu behalten:

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**Ein `member`-DN fügt keine Person hinzu.** Er wird nur dann auf jemanden abgebildet, wenn er
nach distinguishedNameMatch (RFC 4517 §4.2.15) der DN eines Eintrags ist, den die
Personensuche geliefert hat. Ein DN außerhalb dieser Einträge oder einer, der niemanden benennt, wird auf
niemanden abgebildet, ebenso `uid=alice,ou=elsewhere,…`, wenn alice aus
`ou=people` importiert wurde. Bis v0.13.0 wurde ein DN im Mitgliedsattribut auf den
Wert seines ersten RDN reduziert, wem auch immer er gehörte, sodass `uid=alice,ou=elsewhere,…`,
`cn=alice,…` und `uid=zed,…` zu Mitgliedern namens alice, alice und zed wurden.

`ldaptest`, das Testverzeichnis, wendet nun Basis und Filter auf jede Suche an,
gibt jeder Person eine `objectClass` (`Person.ObjectClasses`, standardmäßig
`top`, `account`, `posixAccount`) und hat `groupOfNames`-Gruppen
(`GroupsOfNames`), sodass ein Test der Filter eines Clients fehlschlagen kann.

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
- **Ein Attribut, das ein Geheimnis ist oder das ein Server selbst beantwortet** –
  [die Liste oben]({{< relref "/libraries/directory.md#attributes" >}}) –, wo immer es konfiguriert ist: in einem Block, als
  SQL-Alias oder in der Kopierliste von ldapdir.

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
- **`sqldir` gegen eine echte SQLite-Datenbank** über einen echten Treiber. Die
  Attributabfragen wurden außerdem einmal von Hand gegen PostgreSQL 18.6
  über pgx ausgeführt, nicht in der CI: Ein Alias ohne Anführungszeichen kam in Kleinbuchstaben zurück und wurde
  trotzdem gefunden, einer in Anführungszeichen behielt seine Schreibweise, und ein Alias, der
  `userPassword` benennt, wurde abgelehnt.
- **Die Filter von ldapdir** gegen `ldaptest`, das sie ab v0.14.0 anwendet:
  Der Standard-Benutzerfilter lässt ein einfaches `inetOrgPerson` aus
  (`TestTheDefaultUserFilter`), und der Gruppenfilter fügt keine Identität hinzu
  (`TestTheGroupFilterAddsNoIdentity`).
- **MD4** gegen die Testvektoren aus RFC 1320.

Die Coverage-Lane schlägt unter 85 % fehl (ihr erklärter Standard ist 100 %), und die
Builds mit `nosql` und `noldap` werden in der CI geprüft.

## Referenz {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
