---
title: "Standort-Schemata und die Klassen, die eine Quelle deklariert"
linkTitle: "Standort-Schemata"
weight: 27
description: "SUPANN, eduPerson oder die eigenen Attribute eines Standorts bereitstellen: schema_files und der schema-Block fügen Definitionen hinzu, object_classes deklariert, welche Hilfsklassen die Personen und Gruppen einer Quelle tragen, und check sagt, was weggelassen wurde. Ab v0.13.0 werden DIT-Content-Rules, Name Forms und DIT-Structure-Rules durchgesetzt."
tags: [authnd, ldap, schema, konfiguration]
---

**Ein SUPANN- oder eduPerson-Attribut wird weggelassen, sofern keine Klasse seines Eintrags
es erlaubt.** authnd veröffentlicht nur, was das Schema zulässt, das es bereitstellt (siehe
[die Einträge]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})),
und das Standardschema kennt weder `supannEtablissement` noch
`eduPersonAffiliation`. Ab v0.12.0 sagt ein Standort drei Dinge, in dieser Reihenfolge:

1. **welche Definitionen hinzukommen**: `schema_files`, die Dateien, die sein slapd bereits
   lädt, und ein `schema { }`-Block für das, was nur lokal gilt;
2. **welche Hilfsklassen (AUXILIARY) seine Personen und Gruppen tragen**: `object_classes`;
3. nichts weiter. Eine Klasse wird **deklariert, nie abgeleitet**: Ein Attribut, das
   in einer Datenbank auftaucht, ändert nicht, als was ein Eintrag veröffentlicht wird.

{{< callout type="info" >}}
**Das Beispiel auf dieser Seite ist ein Beispiel**

`example.schema` unten wurde für diese Seite geschrieben. Seine OIDs liegen unter
`1.3.6.1.4.1.99999`, einem Zweig, der niemandem zugewiesen ist: Verwenden Sie Ihre eigenen und
kopieren Sie diese nie. Zu SUPANN siehe [das Ende der Seite](#supann).
{{< /callout >}}

## Ein Beispiel: ein Schema, eine Datenbank, eine Konfiguration {#an-example}

Ein Schema in der `.schema`-Form von OpenLDAP: eine Klasse, die eine Quelle deklarieren kann
(`exampleStaff`, AUXILIARY, mit einem MUST), und eine, die sie nicht kann
(`exampleUnit`, STRUCTURAL).

```
objectidentifier exampleRoot  1.3.6.1.4.1.99999
objectidentifier exampleAttr  exampleRoot:1
objectidentifier exampleClass exampleRoot:2

attributetype ( exampleAttr:1 NAME 'exampleBadge'
	DESC 'the number on a badge'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

attributetype ( exampleAttr:2 NAME 'exampleEmployeeId'
	DESC 'a staff number'
	EQUALITY caseExactMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

# AUXILIARY: it can be declared. exampleStaff has a MUST.
objectclass ( exampleClass:1 NAME 'exampleStaff' SUP top AUXILIARY
	DESC 'somebody employed: has a staff number'
	MUST exampleEmployeeId
	MAY exampleBadge )

# STRUCTURAL: it cannot be declared (an entry has one structural chain).
objectclass ( exampleClass:2 NAME 'exampleUnit' SUP top STRUCTURAL
	MUST cn )
```

Eine SQLite-Datenbank mit drei Personen, mit `sn`, einer Dienstmarke und einer Personalnummer
(`sqlite3 var/people.db < people.sql`):

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

Und die Konfiguration:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

# Files first, then the blocks: a definition may use anything before it.
schema_files = ["etc/authnd/example.schema"]

schema {
  attribute_type "exampleLocker" {
    oid    = "1.3.6.1.4.1.99999.1.3"
    syntax = "1.3.6.1.4.1.1466.115.121.1.15"
  }
  object_class "exampleLockerHolder" {
    oid  = "1.3.6.1.4.1.99999.2.3"
    kind = "auxiliary"
    may  = ["exampleLocker"]
  }
}

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret from staff"
  users_attributes = "select login, sn, badge as exampleBadge, empid as exampleEmployeeId, locker as exampleLocker from person_attrs"
  object_classes   = ["exampleStaff", "exampleLockerHolder"]   # declared, never inferred
}
```

Ohne die Zeile `object_classes` sagt `check`, was das Standardschema allein mit denselben
Personen macht: Die Attribute werden weggelassen, und jede Zeile nennt die Klasse, die es
behalten hätte.

```
$ authnd check cases/nodecl.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes

USER  FROM               CAN PROVE   PUBLISHED AS                                            WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ann is published without exampleBadge: no class of the entry allows it; exampleStaff would
ann is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
cat is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## `schema_files` {#schema-files}

`schema_files` ist eine Liste von OpenLDAP-`.schema`-Dateien oder cn=config-LDIF-Dateien.
Sie werden **wie veröffentlicht** geladen, der Reihe nach, auf dem Standardschema (und
den drei Definitionen von Samba, mit dem [`samba`-Block]({{< relref "/authnd/tls.md#the-samba-block" >}})), durch die
[slapd-kompatiblen Reader]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}) von go-authn/ldap:
beliebige Reihenfolge der Terme, Fortsetzungszeilen nach slapd und RFC 2849, Base64, Längenpräfixe
`{N}` und `objectidentifier`-Makros, die eine Datei definieren und die nächste
verwenden kann, wie über das `include` von slapd hinweg. Nichts wird vorher umgewandelt, also
ist die Datei, die der slapd eines Standorts lädt, die Datei, die authnd lädt. Die Definitionen werden unter
`cn=Subschema` bereitgestellt.

- Ein relativer Pfad ist relativ zum Arbeitsverzeichnis, wie jeder andere Pfad
  in der Konfiguration. Verwenden Sie in einem Dienst absolute Pfade: Das Arbeitsverzeichnis
  einer systemd-Unit ist `/`.
- Jede Datei muss eine reguläre Datei von höchstens 4 MiB sein und wird einmal gelesen, beim
  Start.
- Die Dateien entscheiden, was jeder Eintrag enthalten darf. Sie sind keine Geheimnisse, aber halten Sie
  sie bei der übrigen Konfiguration: `root:authnd`, Modus `0640`, in einem
  Verzeichnis, in das nur root schreibt ([Installation]({{< relref "/authnd/install.md" >}})).
- Eine Datei, die sich nicht aufbauen lässt, verweigert den Start und `check`, mit der Datei, der
  Zeile und der Spalte, in der die Definition beginnt, und der Art der Ablehnung am Ende der Meldung:
  eine unbekannte Oberklasse, ein unbekanntes Attribut, eine unbekannte Matching-Regel oder
  Syntax (`unknown reference`), eine STRUCTURAL-Klasse, die von einer AUXILIARY-Klasse abgeleitet ist
  (`kind violation`), eine OID oder ein Name, der doppelt definiert ist (`duplicate OID`,
  `duplicate name`). Seit v0.12.1 stammen Stelle und Art aus dem typisierten
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}) von
  go-authn/ldap, nicht aus dem Lesen seiner Meldung. Eine aus einer Datei gelesene Definition beginnt in
  Spalte 1, auch wenn ihr Text über mehrere Zeilen umgebrochen ist. Ein Duplikat sagt, wo seine
  erste Definition steht, und eine Neudefinition sagt, welche Standarddatei oder welche Zeile
  einer früheren Datei das Original enthält. Zwei Beispiele:

  `cases/unknown.schema` hat ein MAY, das nirgends definiert ist:

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema` gibt zwei Attributtypen dieselbe OID:

  ```
  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleA'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )

  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleB'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )
  ```

  ```
  $ authnd check cases/twice.hcl
  authnd: schema_files: cases/twice.schema:4:1: the attribute type 1.3.6.1.4.1.99999.1.9 is defined twice (first defined at cases/twice.schema:1:1) (duplicate OID)
  ```

### Eine Neudefinition wird abgelehnt, selbst eine identische {#redefinition}

Eine Datei darf nicht definieren, was schon da ist: die Definitionen des Standardschemas,
die von Samba oder die einer früheren Datei. Sie wird **selbst wortgleich** abgelehnt, was die
eigene Regel von slapd ist: Die Definitionen einer Schemadatei laufen durch
`parse_at` und `parse_oc`, und slapd beantwortet eine bereits indizierte OID oder einen bereits
indizierten Namen mit *Duplicate attributeType* (gleiche OID und Namen) oder *Inconsistent duplicate
attributeType* (`servers/slapd/at.c`, `oc.c`). Nur das fest einprogrammierte Schema von slapd
selbst darf Ersteres. Eine Datei, die slapd ablehnt, ist eine Datei, die authnd ablehnt.

Die andere Lesart müsste einen Gewinner auswählen, und das wäre eine stille Änderung dessen,
was jedem Client über ein Standardattribut gesagt wird; die Ablehnung nennt stattdessen die Zeile.
Die Ablehnung sagt, ob der Text derselbe war. Eine Datei, die `cn` (2.5.4.3) mit einer
eigenen Definition neu definiert:

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## Der `schema { }`-Block {#the-schema-block}

Für Definitionen, die nur lokal gelten, hält ein `schema`-Block sie in
HCL2, in der [Form von hclschema]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}):
`attribute_type`, `object_class`, `object_identifier`, `matching_rule` und
`ldap_syntax`. Er wird **nach** den Dateien gelesen, darf also deren
Definitionen verwenden, und es kann mehrere geben.

Werte müssen **Literale** sein: keine Variablen, keine Funktionen, kein `${...}` oder
`%{...}`. Der Block wird vom selben Decoder gelesen wie eine `.hcl`-Schemadatei,
mit denselben Grenzen, und jeder Fehler nennt die eigene Zeile und Spalte der Konfiguration.
Ein Block, der nicht in der nativen Syntax von HCL steht, wird abgelehnt.

## `object_classes` {#object-classes}

Eine Definition im Schema erlaubt ein Attribut; sie setzt die Klasse niemandem auf. Eine Quelle
**deklariert** die Hilfsklassen (AUXILIARY), mit denen ihre Personen und Gruppen
veröffentlicht werden:

| wo | Schlüssel | was er deklariert |
|---|---|---|
| `users`-Block, jede Art | `object_classes` | die Klassen jeder Person, die der Block liefert |
| `users`-Block, jede Art | `group_object_classes` | die Klassen jeder Gruppe |
| `user`-Block | `object_classes` | die Klassen dieser Person |
| `group`-Block | `object_classes` | die Klassen dieser Gruppe |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

Diese Schlüssel sind die von go-authn/directory, ab v0.15.0
([Bibliothek]({{< relref "/libraries/directory.md#object-classes" >}})). Namen
werden ohne Beachtung der Groß- und Kleinschreibung verglichen und je einmal in der geschriebenen
Reihenfolge gehalten.

Was authnd mit einer deklarierten Klasse macht:

- **Sie wird mit ihren Oberklassen veröffentlicht**, nach den Klassen, die authnd ableitet
  (RFC 4512 §3.3: Alle Oberklassen der genannten Klassen werden implizit
  hinzugefügt). Die Attribute, die die Klasse erlaubt, bleiben erhalten, statt weggelassen zu werden.
- **Sie wird nie abgeleitet.** Eine Person, deren Quelle nichts deklariert, verliert weiterhin
  die Attribute, die keine ihrer Klassen erlaubt, was auch immer die Datenbank enthält.
- **Einer Person, der ein MUST einer deklarierten Klasse fehlt, wird diese
  Klasse vorenthalten.** Ihre Attribute werden weggelassen wie jedes Attribut, das keine Klasse erlaubt, und
  beides wird gemeldet. Das ist die Regel, der authnd überall folgt: Die Person
  bleibt veröffentlicht, das Problem wird gesagt, nichts wird stillschweigend geändert.
  Die Person zurückzuhalten würde sie wegen eines fehlenden Attributs aus jeder Suche nehmen;
  die Klasse ohne ihr MUST zu veröffentlichen würde einen Eintrag liefern,
  der das bereitgestellte Schema nicht besteht.
- **Zwei Quellen können unterschiedliche Klassen für eine Gruppe deklarieren.** Die erste
  Quelle, die Klassen für eine Gruppe deklariert, entscheidet, ganz, und eine spätere Liste wird
  ignoriert: weder zusammengeführt noch ein Fehler. `check` sagt es.

Hier hat ann alles, cat hat kein Schließfach (ein MAY), und ben hat keine
`exampleEmployeeId`, ein MUST von `exampleStaff`:

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people

USER  FROM               CAN PROVE   PUBLISHED AS                                                                               WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn, exampleBadge, exampleEmployeeId and exampleLocker
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder                uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn and exampleEmployeeId

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder
ben is published without exampleStaff, which its source declares: ben has no exampleEmployeeId, which exampleStaff requires
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Das Startprotokoll trägt dieselben Zeilen, mit DNs:

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 3 people from a sqlite database
schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people
uid=ben,ou=people,dc=example,dc=org is published without exampleStaff, which its source declares: uid=ben,ou=people,dc=example,dc=org has no exampleEmployeeId, which exampleStaff requires
uid=ben,ou=people,dc=example,dc=org is published without exampleBadge: no class of the entry allows it; exampleStaff would

stopping
```

Und was das `ldapsearch` von OpenLDAP zurückliest, mit dem Passwort des Readers in einer
Datei. ann trägt beide Hilfsklassen und jedes Attribut, das sie erlauben; ben
trägt nur `exampleLockerHolder`, und seine Dienstmarke ist mit
`exampleStaff` verschwunden; cat trägt beide, mit ihrer Personalnummer:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(uid=*)'
dn: uid=ann,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: ann
cn: ann
sn: Archer
exampleBadge: B-0001
exampleEmployeeId: E-1001
exampleLocker: L-12

dn: uid=ben,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleLockerHolder
uid: ben
cn: ben
sn: Brook

dn: uid=cat,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: cat
cn: cat
sn: Cole
exampleEmployeeId: E-1003

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(objectClass=exampleStaff)' 1.1
dn: uid=ann,ou=people,dc=example,dc=org

dn: uid=cat,ou=people,dc=example,dc=org
```

## Was abgelehnt wird, und warum {#what-is-refused}

Eine deklarierte Klasse wird beim Start und von `check` gegen das bereitgestellte
Schema geprüft. Sie muss sein:

- **definiert**, vom Standardschema, einer Datei oder einem Block;
- **AUXILIARY** (RFC 4512 §4.1.1). Ein Eintrag hat genau eine STRUCTURAL-Kette
  (§2.4.2), die authnd aus dem wählt, was die Person hat; eine Deklaration
  kann keine zweite hinzufügen;
- **keine, die authnd selbst ableitet**: `account`, `inetOrgPerson` und seine
  Oberklassen, `posixAccount`, `posixGroup`, `ldapPublicKey`, `uidObject`,
  `sambaSamAccount`, `groupOfNames` und `organizationalRole`, unter jedem
  ihrer Namen. Diese ergeben sich aus dem, was eine Person oder Gruppe hat, und eine
  Deklaration kann `check` nicht überstimmen.

Andernfalls wird der Start abgelehnt, mit Nennung des Blocks, seiner Position und der Klasse.
`exampleUnit` ist STRUCTURAL:

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory prüft davor die **Schreibweise**: Eine Klasse ist ein
Deskriptor, nie eine OID, ein Leerzeichen, ein Anführungszeichen oder eine Klammer.

Ebenfalls abgelehnt, und aus demselben Grund, das Schema ehrlich zu halten:

| abgelehnt | warum |
|---|---|
| eine Datei, die eine Definition neu definiert, selbst wortgleich | die Regel von slapd: [oben](#redefinition) |
| eine Datei, die keine reguläre Datei ist oder über 4 MiB hat | eine FIFO würde den Start blockieren, `/dev/zero` würde nie enden |
| ein `schema`-Block mit einer Variablen, einer Funktion oder `${...}` | nur Literalwerte, wie in einer `.hcl`-Schemadatei |
| eine undefinierte Klasse in `object_classes` | ein Versprechen, das nichts prüfen kann |
| eine STRUCTURAL-Klasse oder eine, die authnd ableitet | die Liste oben |

## Was `check` ausgibt {#what-check-prints}

Vier Arten von Zeilen, zusätzlich zu [den üblichen]({{< relref "/authnd/check.md" >}}); das Startprotokoll trägt dieselben:

- **`schema: <file> adds …`** und **`schema: the schema block at <file>:<line>:<column> adds …`**:
  was jede Datei und jeder Block hinzugefügt hat, gezählt als Object-Identifier-Makros,
  Attributtypen und Objektklassen;
- **`<file>:<line>:<column>: users "sql" declares … for its people`** (ein
  `user`- oder `group`-Block sagt `user "ann" declares … for this person` und
  `group "staff" declares … for this group`): was jede Quelle deklariert;
- **`<name> is published without <class>, which its source declares: …`**,
  mit Nennung des MUST, das der Person fehlt;
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`**:
  zwei Quellen, die sich über eine Gruppe uneins sind, was sonst stumm bliebe.

Attribute, die mangels einer Klasse weggelassen werden, sind die Zeilen `is published without
<attribute>: no class of the entry allows it; <classes> would`, die
[die Einträge]({{< relref "/authnd/entries.md" >}}) bereits beschreiben: Mit einer
Deklaration nennen sie die Klasse, die Sie nicht deklariert haben.

## DIT-Content-Rules, Name Forms und DIT-Structure-Rules {#rules}

Ab v0.13.0 akzeptieren `schema_files` und der `schema { }`-Block auch die drei
Arten von Definitionen, die RFC 4512 §4.1.6 und §4.1.7 zu Klassen und
Attributen hinzufügen, und authnd **setzt sie durch** (go-authn/ldap v0.11.0 liest,
baut und prüft sie; [die Bibliotheksseite]({{< relref "/libraries/ldap.md#rules" >}})
sagt, wie):

| Definition | RFC 4512 | was sie sagt | was authnd damit tut |
|---|---|---|---|
| DIT-Content-Rule | §4.1.6 | für eine strukturelle Klasse: welche Hilfsklassen (`AUX`) hinzugefügt werden dürfen, welche Attribute verlangt (`MUST`), erlaubt (`MAY`) oder ausgeschlossen (`NOT`) sind | **formt jeden Eintrag** (Daten) |
| Name Form | §4.1.7.2 | aus welchen Attributnamen (dem RDN) ein Eintrag einer strukturellen Klasse besteht | **hält den Baum** (Konfiguration) |
| DIT-Structure-Rule | §4.1.7.1 | wo eine Name Form stehen darf: unter dem Eintrag, den die Regel regiert, die ihr `SUP` nennt | **hält den Baum** (Konfiguration) |

Sie werden unter `cn=Subschema` veröffentlicht (`dITContentRules`, `nameForms`,
`dITStructureRules`), **nur wenn es welche gibt**. Gibt es keine, gilt nichts auf dieser
Seite, und gegenüber v0.12.4 ändert sich nichts.

{{< callout type="info" >}}
**Derselbe Beispiel-Arc**

`rules.schema` unten ist, wie `example.schema` oben, für diese Seite geschrieben,
unter `1.3.6.1.4.1.99999`. Verwenden Sie Ihren eigenen Arc. Die OIDs der Content-Rule und
von `inetOrgPerson` sind per Definition dieselben: Eine Content-Rule trägt den Namen
der strukturellen Klasse, für die sie gilt.
{{< /callout >}}

### Ein Schema mit je einer, und sein HCL {#rules-example}

In der `.schema`-Form von OpenLDAP. `ditcontentrule` ist die Direktive von slapd.conf(5);
`nameform` und `ditstructurerule` sind die von go-authn/ldap, da slapd keine hat
([unten](#rules-slapd)). authnd prüft außerdem den Baum, den es veröffentlicht
(Suffix, `ou=people`, `ou=groups`, Accounts, Personen und Gruppen darunter), sodass die
Datei fünf Name Forms und fünf Structure-Rules enthält, nicht je eine:

```
# Rules for the tree authnd publishes. 1.3.6.1.4.1.99999 is an example arc:
# nobody is assigned it, use your own.

# A content rule belongs to a structural class and takes that class's OID.
# inetOrgPerson (2.16.840.1.113730.3.2.2): posixAccount and uidObject may be
# added, ldapPublicKey may not; telephoneNumber is required; description is
# precluded.
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule'
	AUX ( posixAccount $ uidObject )
	MUST telephoneNumber
	NOT description )

# A name form says which attribute names an entry of a structural class.
nameform ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameform ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameform ( 1.3.6.1.4.1.99999.9.3 NAME 'exampleAccountForm' OC account MUST uid )
nameform ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )
nameform ( 1.3.6.1.4.1.99999.9.5 NAME 'examplePosixGroupForm' OC posixGroup MUST cn )

# A structure rule gives a name form a place: the rule ID is a number, SUP
# names the rule of the parent entry.
ditstructurerule ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
ditstructurerule ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
ditstructurerule ( 3 NAME 'exampleAccounts' FORM exampleAccountForm SUP 2 )
ditstructurerule ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
ditstructurerule ( 5 NAME 'examplePosixGroups' FORM examplePosixGroupForm SUP 2 )
```

Dieselben Definitionen in HCL, wie `ldapschema` v0.11.0 sie schreibt
(`ldapschema to-hcl rules.schema`). Jeder Block ist eine Definition, benannt mit
ihrem ersten NAME; eine Structure-Rule hat eine `id`, die `form`, die sie platziert, und die
`sup`-Regeln, unter denen sie steht:

```hcl
dit_content_rule "examplePersonRule" {
  oid  = "2.16.840.1.113730.3.2.2"
  aux  = ["posixAccount", "uidObject"]
  must = ["telephoneNumber"]
  not  = ["description"]
}

name_form "exampleDomainForm" {
  oid  = "1.3.6.1.4.1.99999.9.1"
  oc   = "domain"
  must = ["dc"]
}

name_form "exampleUnitForm" {
  oid  = "1.3.6.1.4.1.99999.9.2"
  oc   = "organizationalUnit"
  must = ["ou"]
}

name_form "exampleAccountForm" {
  oid  = "1.3.6.1.4.1.99999.9.3"
  oc   = "account"
  must = ["uid"]
}

name_form "examplePersonForm" {
  oid  = "1.3.6.1.4.1.99999.9.4"
  oc   = "inetOrgPerson"
  must = ["uid"]
}

name_form "examplePosixGroupForm" {
  oid  = "1.3.6.1.4.1.99999.9.5"
  oc   = "posixGroup"
  must = ["cn"]
}

dit_structure_rule "exampleSuffix" {
  id   = 1
  form = "exampleDomainForm"
}

dit_structure_rule "exampleUnit" {
  id   = 2
  form = "exampleUnitForm"
  sup  = [1]
}

dit_structure_rule "exampleAccounts" {
  id   = 3
  form = "exampleAccountForm"
  sup  = [2]
}

dit_structure_rule "examplePersons" {
  id   = 4
  form = "examplePersonForm"
  sup  = [2]
}

dit_structure_rule "examplePosixGroups" {
  id   = 5
  form = "examplePosixGroupForm"
  sup  = [2]
}
```

Das ist, was unverändert in einen `schema { }`-Block gehört; die `.schema`-Datei ist,
was `schema_files` nimmt. `ldapschema to-schema rules.hcl` macht daraus wieder eine
`.schema`-Datei mit denselben Definitionen, und `ldapschema check` baut sie auf
dem Standardschema auf:

```
$ ldapschema check etc/authnd/rules.schema
read: 0 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 5 name forms, 5 DIT structure rules
build: ok, 11 definitions added to schema.Standard()
```

### Was eine Content-Rule mit einem Eintrag macht {#content-rules}

Die Konfiguration besteht aus zwei Personen und zwei Gruppen, mit den Regeln aus
`schema_files`. **dave** hat ein `sn` (ist also ein `inetOrgPerson`), eine Telefonnummer,
eine Beschreibung und einen öffentlichen SSH-Schlüssel; **erin** hat ein `sn` und sonst
nichts; **staff** hat eine `gidNumber`; **team** hat keine:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

schema_files = ["etc/authnd/rules.schema"]

user "dave" {
  password        = "dave-password"
  authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl dave@example.org"]
  attributes = {
    sn              = "Dumont"
    telephoneNumber = "+33 1 23 45 67 89"
    description     = "on call"
  }
}

user "erin" {
  password   = "erin-password"
  attributes = { sn = "Evans" }
}

group "staff" {
  members    = ["dave"]
  attributes = { gidNumber = "100" }
}

group "team" { members = ["dave"] }
```

Die Regel gilt für die **strukturelle Klasse** des Eintrags, und was sie bewirkt, wird
beim Start und von `check` Eintrag für Eintrag gesagt:

| die Regel sagt | der Eintrag | gesagt als |
|---|---|---|
| `AUX` führt eine Hilfsklasse nicht auf, ob deklariert oder von authnd abgeleitet (`posixAccount`, `ldapPublicKey`, `sambaSamAccount`, `uidObject`) | die Klasse wird **weggelassen**, mit den Attributen, die nur sie erlaubte (und dem `sshPublicKey`, `sambaSID` und `sambaNTPassword`, die authnd für sie hinzufügen würde); eine deklarierte Klasse, deren Oberklasse weggelassen wird, geht mit ihr | `<name> is published without <class>: the DIT content rule <rule> does not allow it (not in its AUX)` |
| `NOT` nennt ein Attribut | das Attribut wird **verworfen**, von wem auch immer es stammt | `<name> is published without <attribute>: the DIT content rule <rule> precludes it (NOT)` |
| `MUST` nennt ein Attribut, das dem Eintrag fehlt | der Eintrag wird **ausgelassen**: Die Regel gilt für den Eintrag als Ganzes, und keine Klasse kann weggelassen werden, um ihn gültig zu machen | `<name> is NOT published: … <attribute> is required by the DIT content rule <rule> and is missing (RFC 4512 4.1.6)` |

Ohne Content-Rule für ihre strukturelle Klasse sind die Hilfsklassen eines Eintrags
erlaubt, wie slapd sie erlaubt ([unten](#rules-slapd)).

```
$ authnd check etc/authnd/authnd.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules

USER  FROM                    CAN PROVE             PUBLISHED AS                                            WITH
dave  the configuration file  a password and 1 key  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn, sn and telephoneNumber
erin  the configuration file  a password            NOT PUBLISHED (see below)                               uid, cn and sn

GROUP  MEMBERS  PUBLISHED AS
staff  dave     posixGroup
team   dave     NOT PUBLISHED (see below)

dave has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
dave is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
dave is published without description: the DIT content rule examplePersonRule precludes it (NOT)
erin has no uidNumber, gidNumber or homeDirectory: not a posixAccount, and as person, organizationalPerson, inetOrgPerson, uidObject the entry fails the schema (below)
erin is NOT published: as person, organizationalPerson, inetOrgPerson, uidObject it fails the schema:
  - telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
group team is NOT published: as groupOfNames it fails the schema:
  - no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Der Server startet, und sein Log enthält dieselben drei Arten von Zeilen, mit DNs:

```
$ authnd --config etc/authnd/authnd.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules
uid=erin,ou=people,dc=example,dc=org is NOT published: it fails the schema: telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
cn=team,ou=groups,dc=example,dc=org is NOT published: it fails the schema: no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)
uid=dave,ou=people,dc=example,dc=org is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
uid=dave,ou=people,dc=example,dc=org is published without description: the DIT content rule examplePersonRule precludes it (NOT)
```

Was `ldapsearch` von OpenLDAP unter `cn=Subschema` liest, die drei Attribute, in denen die
Regeln veröffentlicht werden:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b cn=Subschema -s base '(objectClass=subschema)' dITContentRules nameForms dITStructureRules
dn: cn=Subschema
dITContentRules: ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule' AUX ( posixAccount $ uidObject ) MUST telephoneNumber NOT description )
nameForms: ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameForms: ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameForms: ( 1.3.6.1.4.1.99999.9.3 NAME 'exampleAccountForm' OC account MUST uid )
nameForms: ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )
nameForms: ( 1.3.6.1.4.1.99999.9.5 NAME 'examplePosixGroupForm' OC posixGroup MUST cn )
dITStructureRules: ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
dITStructureRules: ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
dITStructureRules: ( 3 NAME 'exampleAccounts' FORM exampleAccountForm SUP 2 )
dITStructureRules: ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
dITStructureRules: ( 5 NAME 'examplePosixGroups' FORM examplePosixGroupForm SUP 2 )
```

Und der Baum, abgefragt nach dem, was die Regeln berühren. Zuerst dieselbe Konfiguration
**ohne** `schema_files` (der Zeuge: Jeder Unterschied unten geht auf die Regeln zurück),
dann mit ihnen:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(|(uid=*)(cn=*))' dn objectClass description sshPublicKey
dn: uid=dave,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: ldapPublicKey
objectClass: uidObject
description: on call
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl dave@example.org

dn: uid=erin,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject

dn: cn=staff,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup

dn: cn=team,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
```

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(|(uid=*)(cn=*))' dn objectClass description sshPublicKey
dn: uid=dave,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject

dn: cn=staff,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
```

dave hat `ldapPublicKey` verloren und mit ihr seinen `sshPublicKey` (nicht in `AUX`),
und seine `description` (`NOT`). erin ist weg (`MUST telephoneNumber`), und ebenso
**team**: Es hat keine `gidNumber`, ist also eine `groupOfNames`, und keine Structure-Rule
platziert eine `groupOfNames` unter `ou=groups`. Das Letzte ist die Regel des Baums,
auf Daten angewandt, was der nächste Abschnitt erklärt.

### Was die Structure-Rules mit dem Baum machen {#structure-rules}

Mit **mindestens einer aktiven** DIT-Structure-Rule geht authnd beim Start und in
`check` den Baum durch, den es veröffentlichen wird:

- der **Suffix** (`base_dn`), mit der Klasse, die sein RDN nennt: `dc` eine
  `domain`, `o` eine `organization`, `ou` eine `organizationalUnit`, `c` ein
  `country`, `l` eine `locality`. Ein Suffix, der von einem anderen Attribut benannt wird,
  wird abgelehnt;
- `ou=people` und `ou=groups`, als `organizationalUnit`s;
- das RDN-Attribut, mit dem authnd seine Personen (`uid`) und seine Gruppen (`cn`) benennt.

Ein Container, den keine Regel platziert, ein Suffix einer Art, für die keine Regel eine
Name Form hat, eine Name Form, die `uid` oder `cn` ablehnt, oder ein Container, unter dem nichts
von dem, was authnd veröffentlicht, platziert werden könnte, **verweigert den Start, und
`check`**: alle Ablehnungen auf einmal, mit Nennung des DN, der Regel oder Name Form und der
Klausel, und ohne je ein Geheimnis zu wiederholen. Eine Person oder Gruppe, deren strukturelle
Klasse von ihren Daten abhängt (ein `sn`, eine `gidNumber`) und die unter ihrem Container
keine Regel hat, wird stattdessen **ausgelassen und gesagt**, wie team oben: Der Server
startet. Ohne aktive Structure-Rule ändert sich nichts.

Ein Schema, dessen einzige Structure-Rule für Personen, `peopleByCN`, eine Name Form
platziert, die `cn` will (`accountByCN`: `OC account MUST cn`):

```
$ authnd check cases/bad.hcl
authnd: DIT structure rules: authnd names its people uid=<name>,ou=people,dc=example,dc=org, and an account named so is refused: the RDN (uid) is allowed by the name form of no DIT structure rule that places account under an entry governed by the rule 2: accountByCN needs cn
```

authnd benennt seine Personen `uid=<name>`: Die Regeln müssen das erlauben. Und ein
Schema, dessen Regel für `organizationalUnit` kein `SUP` hat, sodass eine
`organizationalUnit` nur an der Wurzel stehen kann, lässt sowohl `ou=people` als auch
`ou=groups` ohne Platz und sagt beides auf einmal:

```
$ authnd check cases/root.hcl
authnd: DIT structure rules: ou=people,dc=example,dc=org, where authnd publishes its people, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
DIT structure rules: ou=groups,dc=example,dc=org, where authnd publishes its groups, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
```

Beide enden mit Status 1. Die Dateien dahinter (`cases/bad.schema` und
`cases/root.schema`) enthalten dieselben fünf Name Forms und nur die Structure-Rules,
die den Punkt machen.

### Wo authnd und slapd sich unterscheiden {#rules-slapd}

go-authn/ldap liest die OpenLDAP-Dateien, und einige der Regeln sind die von OpenLDAP.
Das sind die Unterschiede, gesagt statt entdeckt:

- **slapd implementiert nur Content-Rules.** Es hat keine Direktive für Name Forms
  oder Structure-Rules. `Format` schreibt die Schlüsselwörter `nameform` und
  `ditstructurerule`, die die dieser Bibliothek sind, und slapd lehnt sie ab: Halten Sie
  sie im HCL oder in einer Datei, die nur authnd liest. `ditcontentrule` ist die von slapd.
- **Eine `OBSOLETE`-Regel ist inaktiv** (RFC 4512 §4.1.6), ebenso ihre Name Form
  oder Structure-Rule. slapd lehnt stattdessen den Eintrag ab.
- **Ohne Content-Rule sind Hilfsklassen erlaubt.** Das ist das Verhalten von slapd
  (sein Flag `SLAP_DISALLOW_AUX_WO_CR` wird von keinem `disallow`-Schlüsselwort gesetzt)
  und das von authnd. RFC 4512 §2.4.3 sagt etwas anderes; die Bibliothek bietet es als
  `ValidateOptions{StrictAuxiliary: true}` an, und authnd setzt es nicht.
- **libldap kann das `SUP` einer Structure-Rule nicht lesen.** Eine Structure-Rule mit
  `SUP` wird hier gelesen und von libldap nicht, sodass die Ablehnung einer solchen Datei
  durch libldap kein Urteil über die Datei ist.
- Eine Datei, die eine Regel **neu definiert**, wird abgelehnt, selbst wortgleich, wie
  jede andere Definition ([oben](#redefinition)).

### Was es kostet {#rules-cost}

Gemessen am 28. Oktober 2026 mit `BenchmarkPublish10k` (go-authn/authnd,
`rules_bench_test.go`, `-cpu 1`) an authnd v0.13.1, das go-authn/ldap v0.11.1
einbettet: Das Veröffentlichen von 10.000 Personen macht **364 Allokationen
pro Eintrag** mit den Regeln aus `testdata/rules.schema` und **239** ohne
(v0.13.0: 416 und 265); ein Lauf braucht 102,5 MiB mit den Regeln und 65,4 MiB
ohne (v0.13.0: 147,5 und 88,0). Das schließt das Verwerfen einer ausgeschlossenen
Beschreibung und die erneute Validierung ein. Die Zeiten, etwa 157 ms gegen
100 ms (v0.13.0: 194 ms gegen 123 ms), wurden bei einer Last von 10 bis 16
gemessen und sind kein Verhältnis, dem man trauen sollte; nur die
Allokationszahlen sind es.

### Upgrade {#rules-upgrade}

Für ein Schema ohne Regeln ändert sich nichts: v0.12.4 lehnte alle drei Arten ab, sodass eine
Konfiguration, die darauf gestartet ist, keine enthält. Es gibt eine Ausnahme. Ein
`schema { }`-String, der **kein gültiges UTF-8** ist (eine überlange Kodierung, die HCL
durchlässt), startete auf v0.12.4 und wird jetzt abgelehnt, weil er nicht so
veröffentlicht werden könnte, wie er geschrieben wurde.

## SUPANN, als das echte Beispiel {#supann}

SUPANN ist der Attributsatz der französischen Hochschulbildung und Forschung
(`supannPerson`, `supannEtablissement`, `supannEntite` …), mit eduPerson
daneben. RENATER veröffentlicht das technische Schema, mit den anderen, auf seiner
Dokumentationsseite:

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**Laden Sie die Datei von dort herunter.** Sie wird auf dieser Seite nicht wiedergegeben: Sie
nennt keine Lizenz, also kopiert diese Seite sie nicht, und eine Kopie hier würde
veralten, wenn RENATER sie überarbeitet. Dann:

```sh
sudo install -o root -g authnd -m 0640 supann.schema eduperson.ldif /etc/authnd/
```

```hcl
schema_files = ["/etc/authnd/supann.schema", "/etc/authnd/eduperson.ldif"]

users "sql" {
  # ...
  users_attributes     = "select login, sn, etab as \"supannEtablissement\" from staff"
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}
```

Führen Sie `authnd check` aus und lesen Sie zuerst die `schema:`-Zeilen: Eine Datei, die slapd
lädt, lädt auch hier, und eine, die eine Standarddefinition neu definiert, wird
mit ihrer Zeile abgelehnt. Lesen Sie dann die Zeilen *published without*: Eine Person, der ein
MUST von `supannPerson` oder `eduPerson` fehlt, wird ohne die Klasse veröffentlicht, und
`check` nennt das MUST. Setzen Sie einen Alias in Anführungszeichen, wo es auf seine Schreibweise ankommt
(PostgreSQL wandelt einen Alias ohne Anführungszeichen in Kleinbuchstaben um; siehe
[die Einträge]({{< relref "/authnd/entries.md#in-a-sql-database" >}})).

{{< callout type="info" >}}
**Zu den Transkripten**

Jeder Befehl auf dieser Seite wurde am 26. Oktober 2026 mit dem Release-Binary v0.12.3 (`authnd-darwin-arm64`, gegen `SHA256SUMS` geprüft; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`) und `ldapsearch` von OpenLDAP erneut ausgeführt, auf 127.0.0.1, in einem Arbeitsverzeichnis, mit den gezeigten Dateien. Die Pfade sind aus diesem Grund relativ; ein Dienst verwendet absolute. Das Schema ist ein für diese Seite geschriebenes Beispiel.

Der Abschnitt zu [DIT-Content-Rules, Name Forms und DIT-Structure-Rules](#rules) wurde am 26. Oktober 2026 mit dem Release-Binary v0.13.0 ausgeführt (`authnd-darwin-arm64`, von `relverify` gegen `SHA256SUMS` und die Attestierung geprüft; `go version -m`: `go1.27.3`, `mod github.com/go-authn/authnd v0.13.0`; `authnd --version`: `authnd version v0.13.0`), mit `ldapsearch` von OpenLDAP und `ldapschema`, gebaut aus dem Tag go-authn/ldap v0.11.0 (`go install`, go1.27.1; es hat kein Release-Binary). Jede Ausgabe dort wurde von diesen Programmen ausgegeben, in einem Arbeitsverzeichnis, auf 127.0.0.1; die Dateien hinter den Transkripten sind daneben gezeigt oder beschrieben.
{{< /callout >}}
