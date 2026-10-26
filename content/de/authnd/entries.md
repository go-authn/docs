---
title: "Die Einträge, die authnd veröffentlicht, und das Schema, das es bereitstellt"
linkTitle: "Einträge und Schema"
weight: 25
description: "Als was jede Person und jede Gruppe veröffentlicht wird, das unter cn=Subschema bereitgestellte Schema, das jeder Eintrag besteht, wie man Attribute in einer Datei oder einer SQL-Abfrage hinzufügt, und was weggelassen oder zurückgehalten wird."
tags: [authnd, ldap, schema, sql]
---

**Jeder Eintrag, den authnd veröffentlicht, besteht das Schema, das es bereitstellt.** Ab v0.11.0
ist jede Person und jede Gruppe ein Eintrag nach Standardschema, gebaut aus dem, was ihre Quelle
geliefert hat, und mit `schema.Validate` aus go-authn/ldap gegen das Schema geprüft, das ein
Client unter `cn=Subschema` lesen kann, bevor er je von einer Suche zurückgegeben wird. Ein
Client, der das Schema liest und ihm glaubt – ein LDAP-Browser, ein
Synchronisationswerkzeug, ein Verzeichnis, das dieses repliziert –, bekommt gezeigt, was ihm
gesagt wurde. Bis v0.10.2 war jede Person `top, person, posixAccount`, ohne eines
der Attribute, die diese Klassen verlangen, und `sambaNTPassword` stand an einem Eintrag
ohne eine Klasse, die es erlaubt.

{{< callout type="warning" >}}
**Ein Konsument, der nach `posixAccount` oder `posixGroup` filtert, sieht weniger Einträge**

Eine Person ohne `uidNumber`, `gidNumber` und `homeDirectory` ist kein
`posixAccount` mehr, und eine Gruppe ohne `gidNumber` ist keine
`posixGroup` mehr. Ein Programm, das `(objectClass=posixAccount)` oder
`(objectClass=posixGroup)` sucht, findet sie nicht mehr. Dazu gehört
`ldapdir` aus go-authn/directory bis v0.13.0 und damit go-fileshare, bis es
directory v0.14.0 verlangt, dessen Standardwerte auch `account`, `uidObject`
und `groupOfNames` lesen ([directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})).
Geben Sie Personen und Gruppen diese Attribute, oder richten Sie den Konsumenten auf
`(objectClass=uidObject)` aus, das jede Person trägt.
{{< /callout >}}

## Die Formen {#the-shapes}

Jede Oberklasse wird aufgeführt, wie RFC 4512 §3.3 es verlangt.

| eine Person mit… | `objectClass` | `cn` |
|---|---|---|
| keinem `sn` | `top`, `account` (RFC 4524 §3.1) | nur, wenn eine andere Klasse es erlaubt |
| `sn` | `top`, `person`, `organizationalPerson`, `inetOrgPerson` (RFC 4519, RFC 2798) | ja |
| … und `uidNumber`, `gidNumber`, `homeDirectory`, allen dreien | `+ posixAccount` (RFC 2307) | ja |
| … und SSH-Schlüsseln | `+ ldapPublicKey` (openssh-lpk), mit `sshPublicKey` | |
| … und einem veröffentlichten NT-Hash mit einer `sambaSID` | `+ sambaSamAccount` (Samba), mit `sambaSID` und `sambaNTPassword`: siehe [den `samba`-Block]({{< relref "/authnd/tls.md#the-samba-block" >}}) | erlaubt |
| … immer | `+ uidObject` (RFC 4519 §3.14), sodass `(objectClass=uidObject)` alle findet | |

| eine Gruppe mit… | `objectClass` | Mitglieder |
|---|---|---|
| einer `gidNumber` | `top`, `posixGroup` (RFC 2307) | `memberUid`, Namen |
| keiner `gidNumber`, mit jemandem darin | `top`, `groupOfNames` (RFC 4519 §3.5) | `member`, die DNs, die dieser Server veröffentlicht |
| keiner `gidNumber`, mit niemandem darin | `top`, `organizationalRole` (RFC 4519 §3.10) | keine |
| einer `gidNumber`, mit niemandem darin | `top`, `posixGroup` | keine: ein Attribut hat mindestens einen Wert |

`uid` ist der Name der Person, und `cn` ebenfalls, wo immer eine Klasse es erlaubt. Ein
`account` allein erlaubt kein `cn` (sein MAY ist `description`, `seeAlso`,
`l`, `o`, `ou` und `host`), daher trägt eine Person ohne `sn` und ohne das POSIX-Trio
`uid` und kein `cn`.

Warum diese Entscheidungen, aus authnds eigenen Gründen:

- **`posixGroup` folgt RFC 2307, nicht draft-howard-rfc2307bis-02.** Der
  Entwurf macht `posixGroup` AUXILIARY und ist unveröffentlicht abgelaufen; eine
  AUXILIARY-`posixGroup` bräuchte eine strukturelle Klasse daneben, `groupOfNames`, deren
  `member` eine leere Gruppe nicht liefern kann.
- **`organizationalRole` für eine leere Gruppe ohne `gidNumber`.**
  `groupOfNames` und `groupOfUniqueNames` verlangen beide ein Mitglied, und die Wege,
  eines zu erfinden, sind falsch: `member: ""` benennt das Root-DSE, und der
  eigene DN der Gruppe macht sie zu einem Mitglied ihrer selbst. `organizationalRole` ist die
  eine strukturelle Standardklasse, deren einziges MUST `cn` ist, und sie nimmt
  `description`, `ou` und `seeAlso` wie `groupOfNames`.
- **Hilfsklassen ohne DIT-Content-Rules.** RFC 4512 §2.4.3 verbietet
  Hilfsklassen an einem Eintrag, dessen strukturelle Klasse keine DIT-Content-Rule
  hat. Jeder verwendete Verzeichnisserver erlaubt sie, und `Validate` ebenso.

## Attribute hinzufügen {#adding-attributes}

Was eine Quelle über jemanden sagt, das nichts beweist – eine `uidNumber`, ein
Home-Verzeichnis, eine Mailadresse –, ist ein **Attribut**, veröffentlicht wie angegeben.
Es sind die [Attribute]({{< relref "/libraries/directory.md#attributes" >}}) aus go-authn/directory,
ab v0.13.0, und sie werden von Anmeldedaten getrennt gehalten: Ein Name, der ein
Geheimnis enthält, oder einer, den der Server selbst ableitet, wird abgelehnt, bevor irgendetwas
gelesen wird.

### In einem `user`- oder `group`-Block {#in-a-user-or-group-block}

```hcl
user "dora" {
  password_file   = "/etc/authnd/passwords/dora.pw"
  authorized_keys = ["ssh-ed25519 AAAA… dora@laptop"]
  attributes = {
    sn            = "Explorer"          # inetOrgPerson
    uidNumber     = "1000"              # the three: posixAccount
    gidNumber     = "1000"
    homeDirectory = "/home/dora"
    mail          = ["dora@example.org", "d.explorer@example.org"]
  }
}

group "engineers" {
  members    = ["dora", "eli"]
  attributes = { gidNumber = "2000" }   # a posixGroup; without it, a groupOfNames
}
```

Ein Wert ist eine Zeichenkette oder eine Liste von Zeichenketten; `null` lässt das Attribut weg.
Eine Zahl wird abgelehnt, weil ein LDAP-Wert eine Zeichenkette ist und authnd nicht
wählt, wie eine Zahl geschrieben wird:

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

Ebenso abgelehnt, unabhängig von der Groß-/Kleinschreibung: jeder Name, der ein Geheimnis enthält
(`userPassword`, `sambaNTPassword`, `unicodePwd`, `krbPrincipalKey` und der
Rest der Liste von go-authn/directory, oder jeder Name, der `password`,
`passwd`, `pwd`, `secret`, `credential`, `hash` oder `privatekey` enthält);
`sshPublicKey`, das `authorized_keys` hat; `uid`, `cn` und `objectClass`,
die der Server ableitet; `member`, `memberUid` und die anderen Mitgliedsattribute,
die `members` beantwortet; die operationalen Attribute, die ein Server
pflegt; und ein Name in numerischer Form (`2.5.4.35` ist `userPassword`).

### In einer SQL-Datenbank {#in-a-sql-database}

Zwei optionale Abfragen eines `users "sql"`-Blocks lesen Attribute **nach
Spaltenalias**. Die erste Spalte ist der Name der Person oder der Gruppe; jede weitere
Spalte ist ein Attribut, benannt nach ihrem Alias:

```hcl
users "sql" {
  driver   = "sqlite"
  dsn_file = "/etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

- Die positionalen Abfragen `users` und `groups` sind unverändert, und eine sechste
  positionale Spalte wird weiterhin abgelehnt: Attribute kommen nach Namen, in ihrer eigenen
  Abfrage.
- Eine Spalte, deren Alias keine Attributbeschreibung ist (ein Ausdruck ohne Alias
  wie `count(*)`) oder Anmeldedaten benennt, wird mit ihrer
  Spaltennummer abgelehnt, bevor eine Zeile gelesen wird.
- `NULL` und `''` gelten als fehlend. Ein Name kann in mehreren Zeilen zurückkommen, und die
  Werte aller werden behalten, sodass ein Join auf eine Adresstabelle einer
  Person mehrere gibt.
- Eine Gruppe, die nur in `groups_attributes` genannt wird, **existiert**, ohne jemanden darin:
  So wird die eigene primäre Gruppe einer Person geschrieben.

{{< callout type="warning" >}}
**Die Schreibweise eines Alias ist die der Datenbank**

PostgreSQL wandelt einen Alias ohne Anführungszeichen in Kleinbuchstaben um: `as uidNumber` kommt
als `uidnumber` zurück. Attributnamen unterscheiden nicht zwischen Groß- und Kleinschreibung,
also ist es dasselbe Attribut und der Eintrag für jeden LDAP-Client derselbe Eintrag, aber die
Schreibweise, die authnd ausgibt, ist die der Datenbank. Setzen Sie den Alias in Anführungszeichen,
wo die Schreibweise zählt: `gid as "gidNumber"`. SQLite behält einen Alias so, wie er geschrieben ist.
{{< /callout >}}

### Aus einem anderen LDAP-Verzeichnis {#from-another-ldap-directory}

Ein `users "ldap"`-Block kopiert die Attribute, die ihm genannt werden, aus dem Eintrag jeder
Person und jeder Gruppe: `attributes = ["mail", "uidNumber",
"homeDirectory"]` und `group_attributes = ["gidNumber"]`. Siehe
[Personen]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

## Eine Konfiguration und was sie veröffentlicht {#a-configuration-and-what-it-publishes}

Der SQL-Block oben, mit einem Lesekonto, über einer SQLite-Datenbank mit fünf Personen und
vier Gruppen, wie das Release-Binary v0.11.0 ihn prüft:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER  FROM               CAN PROVE             PUBLISHED AS                                                                         WITH
dora  a sqlite database  a password and 1 key  person, organizationalPerson, inetOrgPerson, posixAccount, ldapPublicKey, uidObject  uid, cn, sn, uidNumber, gidNumber, homeDirectory, mail and sshPublicKey
eli   a sqlite database  a password            account, posixAccount, uidObject                                                     uid, cn, uidNumber, gidNumber and homeDirectory
fay   a sqlite database  a password            person, organizationalPerson, inetOrgPerson, uidObject                               uid, cn, sn and mail
gus   a sqlite database  a password            account, uidObject                                                                   uid
hal   a sqlite database  a password            account, uidObject                                                                   uid

GROUP       MEMBERS       PUBLISHED AS
alumni      nobody        organizationalRole
engineers   dora and eli  posixGroup
nobody-yet  nobody        posixGroup
readers     fay and gus   groupOfNames

fay has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
gus has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
hal has no homeDirectory: not a posixAccount, published as account, uidObject
hal is published without uidNumber: no class of the entry allows it; posixAccount would
hal is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
hal is published without mail: no class of the entry allows it; inetOrgPerson would
group alumni has no gidNumber and nobody in it: not a posixGroup, published as an organizationalRole (a groupOfNames needs a member)
group readers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

`PUBLISHED AS` sind die Objektklassen jedes Eintrags, ohne `top`, und `WITH` seine
Attribute, abgelesen an den Einträgen, die eine Suche liefert. hal hat eine `uidNumber`, eine
`gidNumber` und eine `mail` und weder `homeDirectory` noch `sn`: hal ist ein `account`,
das keines der drei erlaubt, also werden sie weggelassen und der Rest wird
veröffentlicht. Der Server sagt dasselbe beim Start (und `stopping`, als er
angehalten wurde):

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

Zurückgelesen mit `ldapsearch` von OpenLDAP, mit dem Passwort des Lesekontos in einer Datei:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(|(uid=dora)(uid=eli)(uid=gus)(uid=hal))'
dn: uid=dora,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: ldapPublicKey
objectClass: uidObject
uid: dora
cn: dora
sn: Explorer
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/dora
mail: dora@example.org
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTfVR7FqXWE/0VEcjrUhK+Fz/MLqlwGPIxalr6onRMn dora@laptop

dn: uid=eli,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: uidObject
uid: eli
cn: eli
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/eli

dn: uid=gus,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: gus

dn: uid=hal,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: hal

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=groups,dc=example,dc=org '(objectClass=*)'
dn: cn=alumni,ou=groups,dc=example,dc=org
objectClass: top
objectClass: organizationalRole
cn: alumni
description: people who were here

dn: cn=engineers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: engineers
gidNumber: 2000
memberUid: dora
memberUid: eli

dn: cn=nobody-yet,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: nobody-yet
gidNumber: 2001

dn: cn=readers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
cn: readers
description: people who read
member: uid=fay,ou=people,dc=example,dc=org
member: uid=gus,ou=people,dc=example,dc=org
```

`alumni` wird nur in `groups_attributes` genannt, existiert also ohne jemanden
darin; ohne `gidNumber` ist es eine `organizationalRole`. `nobody-yet` hat eine
`gidNumber` und niemanden darin, ist also eine `posixGroup` ohne `memberUid`.

Welche Klasse wen findet:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=uidObject)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org

dn: uid=fay,ou=people,dc=example,dc=org

dn: uid=gus,ou=people,dc=example,dc=org

dn: uid=hal,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=posixAccount)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org
```

## Was weggelassen und was zurückgehalten wird {#what-is-dropped-and-what-is-withheld}

| angegeben | der Eintrag | warum |
|---|---|---|
| `uidNumber`, `gidNumber`, kein `homeDirectory`, kein `sn` | `account, uidObject`, ohne die beiden | *no class of the entry allows it; posixAccount would* |
| `mail`, kein `sn` | `account, uidObject`, ohne es | *no class of the entry allows it; inetOrgPerson would* |
| ein Typ, den das Schema nicht definiert | der Rest | *the schema served here does not define it* |
| `mail` an einer Gruppe ohne `gidNumber` | `groupOfNames`, ohne es | |
| zwei `homeDirectory`-Werte mit dem POSIX-Trio | **zurückgehalten**: SINGLE-VALUE, nichts zum Weglassen | |
| eine `gidNumber`, die keine Ganzzahl ist | **zurückgehalten**: nicht von ihrer Syntax | |

**Nur was eine Quelle geliefert hat, wird weggelassen**, und welches Attribut nicht erlaubt ist,
ist die Antwort von `Validate`, keine zweite Lesart des Schemas. Der Eintrag wird
nach dem Weglassen erneut validiert. Ein Eintrag, der dann immer noch scheitert, wird **zurückgehalten**:
Er fehlt in jeder Suche, das Startprotokoll nennt ihn, und `check` listet
ihn mit jedem Problem auf, das `Validate` gefunden hat. Ein Attribut, das authnd selbst ableitet
(`uid`, `cn`, `objectClass`, `sshPublicKey`, `sambaSID`, `sambaNTPassword`)
und das das Schema ablehnte, wäre ein Defekt in authnd und hält den Eintrag zurück,
statt ihn ohne es zu veröffentlichen.

Die `gidNumber` von alice ist hier ein Wort:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes = {
    uidNumber     = "1000"
    gidNumber     = "staff"
    homeDirectory = "/home/alice"
  }
}

user "bob" { password_file = "etc/authnd/bob.pw" }
```

```
$ authnd check cases/withheld.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS               WITH
alice  the configuration file  a password  NOT PUBLISHED (see below)  uid, cn, gidNumber, homeDirectory and uidNumber
bob    the configuration file  a password  account, uidObject         uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
alice is NOT published: as account, posixAccount, uidObject it fails the schema:
  - the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Bereitgestellt kann sich alice weiterhin binden und taucht in keiner Suche auf, und der Server
sagt beim Start, warum:

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

Zurückgehalten wird der Eintrag, den eine Suche liefert, nicht die Identität.

## Das Schema, das es bereitstellt {#the-schema-it-serves}

Das Root-DSE nennt es (`subschemaSubentry: cn=Subschema`, im
[Root-DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})),
und eine Basissuche auf `cn=Subschema` liefert es (RFC 4512 §4.2): die
Standarddefinitionen, die go-authn/ldap einbettet – RFC 4512, 4517, 4519, 4523,
4524, 2798, 2307, 3672 und 3045 sowie openssh-lpk –, dazu Sambas
`sambaSamAccount`, `sambaSID` und `sambaNTPassword`, wenn es einen
[`samba`-Block]({{< relref "/authnd/tls.md#the-samba-block" >}}) gibt. Die
Definitionen werden nur veröffentlicht, wenn sie namentlich oder mit `+` verlangt werden.
Gekürzt, wo markiert:

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -s base -b cn=Subschema '+' '*'
dn: cn=Subschema
objectClass: top
objectClass: subentry
objectClass: subschema
cn: Subschema
subtreeSpecification: {}
ldapSyntaxes: ( 1.3.6.1.4.1.1466.115.121.1.3 DESC 'Attribute Type Description' )
[...]
matchingRules: ( 2.5.13.15 NAME 'integerOrderingMatch' SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 )
[...]
attributeTypes: ( 1.3.6.1.1.1.1.0 NAME 'uidNumber' DESC 'An integer uniquely identifying a user in an         administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
attributeTypes: ( 1.3.6.1.1.1.1.1 NAME 'gidNumber' DESC 'An integer uniquely identifying a group in an         administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
[...]
objectClasses: ( 2.5.6.9 NAME 'groupOfNames' SUP top STRUCTURAL MUST ( member $ cn ) MAY ( businessCategory $ seeAlso $ owner $ ou $ o $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.3.1 NAME 'uidObject' SUP top AUXILIARY MUST uid )
objectClasses: ( 0.9.2342.19200300.100.4.5 NAME 'account' SUP top STRUCTURAL MUST uid MAY ( description $ seeAlso $ l $ o $ ou $ host ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.0 NAME 'posixAccount' DESC 'Abstraction of an account with POSIX attributes' SUP top AUXILIARY MUST ( cn $ uid $ uidNumber $ gidNumber $ homeDirectory ) MAY ( userPassword $ loginShell $ gecos $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.2 NAME 'posixGroup' DESC 'Abstraction of a group of accounts' SUP top STRUCTURAL MUST ( cn $ gidNumber ) MAY ( userPassword $ memberUid $ description ) )
[...]
```

Der ganze Eintrag umfasste 327 Zeilen: 49 Syntaxen, 40 Matching-Regeln, 36 Matching-Rule-Uses,
143 Attributtypen und 52 Objektklassen. Anders als eine Suche unterhalb
der Basis wird der Subschema-Eintrag, wie das Root-DSE, einem
anonymen Client beantwortet: Dieselbe Abfrage ohne `-D` und `-y` lieferte ihn.

**Filter verwenden die Matching-Regeln des Schemas**, sodass `(uidNumber>=1000)`
Ganzzahlen vergleicht. `uidNumber` und `gidNumber` haben `ORDERING
integerOrderingMatch`, was RFC 2307 ihnen nicht gibt; slapd und
draft-howard-rfc2307bis-02 tun es, und ebenso go-authn/ldap
([seine eine Abweichung]({{< relref "/libraries/ldap.md#the-schema" >}})).
Als Zeichenketten sortiert `1000` vor `999`:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=1000)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=999)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001
```

hal ist nicht dabei: Die `uidNumber` von hal wurde weggelassen. Ein Bereich auf einem Attribut
ohne ORDERING-Regel, etwa `uid`, ist Undefined und erfasst nichts.
