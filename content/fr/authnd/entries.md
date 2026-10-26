---
title: "Les entrées que publie authnd, et le schéma qu'il sert"
linkTitle: "Entrées et schéma"
weight: 25
description: "Ce sous quoi chaque personne et chaque groupe est publié, le schéma servi à cn=Subschema que respecte chaque entrée, comment ajouter des attributs dans un fichier ou une requête SQL, et ce qui est écarté ou retenu."
tags: [authnd, ldap, schéma, sql]
---

**Chaque entrée que publie authnd respecte le schéma qu'il sert.** Depuis la
v0.11.0, chaque personne et chaque groupe est une entrée des schémas standard,
construite à partir de ce que sa source a donné, et vérifiée par le
`schema.Validate` de go-authn/ldap contre le schéma qu'un client peut lire à
`cn=Subschema`, avant d'être jamais renvoyée par une recherche. Un client qui
lit le schéma et le croit — un navigateur LDAP, un outil de synchronisation, un
annuaire qui réplique celui-ci — se voit montrer ce qu'on lui a annoncé.
Jusqu'à la v0.10.2, chaque personne était `top, person, posixAccount` sans
aucun des attributs que ces classes exigent, et `sambaNTPassword` se trouvait
sur une entrée dont aucune classe ne l'autorise.

{{< callout type="warning" >}}
**Un consommateur qui filtre sur `posixAccount` ou `posixGroup` voit moins d'entrées**

Une personne sans `uidNumber`, `gidNumber` et `homeDirectory` n'est plus un
`posixAccount`, et un groupe sans `gidNumber` n'est plus un `posixGroup`. Un
programme qui cherche `(objectClass=posixAccount)` ou
`(objectClass=posixGroup)` ne les trouve plus. Cela comprend le `ldapdir` de
go-authn/directory jusqu'à la v0.13.0, et donc go-fileshare tant qu'il
n'exige pas directory v0.14.0, dont les valeurs par défaut lisent aussi
`account`, `uidObject` et `groupOfNames`
([directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})).
Donnez ces attributs aux personnes et aux groupes, ou pointez le consommateur
sur `(objectClass=uidObject)`, que porte chaque personne.
{{< /callout >}}

## Les formes {#the-shapes}

Chaque superclasse est listée, comme le demande la RFC 4512 §3.3.

| une personne avec… | `objectClass` | `cn` |
|---|---|---|
| pas de `sn` | `top`, `account` (RFC 4524 §3.1) | seulement quand une autre classe l'autorise |
| `sn` | `top`, `person`, `organizationalPerson`, `inetOrgPerson` (RFC 4519, RFC 2798) | oui |
| … et `uidNumber`, `gidNumber`, `homeDirectory`, les trois | `+ posixAccount` (RFC 2307) | oui |
| … et des clés SSH | `+ ldapPublicKey` (openssh-lpk), avec `sshPublicKey` | |
| … et une empreinte NT publiée avec un `sambaSID` | `+ sambaSamAccount` (Samba), avec `sambaSID` et `sambaNTPassword` : voir [le bloc `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}) | autorisé |
| … toujours | `+ uidObject` (RFC 4519 §3.14), si bien que `(objectClass=uidObject)` trouve tout le monde | |

| un groupe avec… | `objectClass` | membres |
|---|---|---|
| un `gidNumber` | `top`, `posixGroup` (RFC 2307) | `memberUid`, des noms |
| pas de `gidNumber`, quelqu'un dedans | `top`, `groupOfNames` (RFC 4519 §3.5) | `member`, les DN que publie ce serveur |
| pas de `gidNumber`, personne dedans | `top`, `organizationalRole` (RFC 4519 §3.10) | aucun |
| un `gidNumber`, personne dedans | `top`, `posixGroup` | aucun : un attribut a au moins une valeur |

`uid` est le nom de la personne, et `cn` aussi partout où une classe
l'autorise. Un `account` seul n'autorise pas `cn` (son MAY est `description`,
`seeAlso`, `l`, `o`, `ou` et `host`), si bien qu'une personne sans `sn` et
sans le trio POSIX porte `uid` et pas de `cn`.

Pourquoi ces choix, selon les raisons propres d'authnd :

- **`posixGroup` suit la RFC 2307, pas draft-howard-rfc2307bis-02.** Le
  brouillon fait de `posixGroup` une classe AUXILIARY et a expiré sans être
  publié ; un `posixGroup` AUXILIARY aurait besoin d'une classe structurelle à
  côté de lui, `groupOfNames`, dont un groupe vide ne peut pas donner le
  `member`.
- **`organizationalRole` pour un groupe vide sans `gidNumber`.**
  `groupOfNames` et `groupOfUniqueNames` exigent tous deux un membre, et les
  façons d'en inventer un sont fausses : `member: ""` nomme le DSE racine, et
  le DN du groupe lui-même en fait un membre de lui-même. `organizationalRole`
  est la seule classe structurelle standard dont l'unique MUST est `cn`, et
  elle prend `description`, `ou` et `seeAlso` comme `groupOfNames`.
- **Des classes auxiliaires sans règles de contenu DIT.** La RFC 4512 §2.4.3
  interdit les classes auxiliaires sur une entrée dont la classe structurelle
  n'a pas de règle de contenu DIT. Tous les serveurs d'annuaire en usage les
  autorisent, et `Validate` aussi.

## Ajouter des attributs {#adding-attributes}

Ce qu'une source dit de quelqu'un sans rien prouver — un `uidNumber`, un
répertoire personnel, une adresse de messagerie — est un **attribut**, publié
tel quel. Ce sont les [attributs]({{< relref "/libraries/directory.md#attributes" >}})
de go-authn/directory, depuis la v0.13.0, et ils sont tenus à l'écart des
identifiants : un nom qui contient un secret, ou un nom que le serveur dérive
lui-même, est refusé avant que quoi que ce soit ne soit lu.

### Dans un bloc `user` ou `group` {#in-a-user-or-group-block}

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

Une valeur est une chaîne ou une liste de chaînes ; `null` omet l'attribut.
Un nombre est refusé, parce qu'une valeur LDAP est une chaîne et qu'authnd ne
choisit pas comment un nombre s'écrit :

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

Sont refusés de la même façon, quelle que soit leur casse : tout nom qui
contient un secret (`userPassword`, `sambaNTPassword`, `unicodePwd`,
`krbPrincipalKey` et le reste de la liste de go-authn/directory, ou tout nom
contenant `password`, `passwd`, `pwd`, `secret`, `credential`, `hash` ou
`privatekey`) ; `sshPublicKey`, qui a `authorized_keys` ; `uid`, `cn` et
`objectClass`, que le serveur dérive ; `member`, `memberUid` et les autres
attributs d'appartenance, auxquels répond `members` ; les attributs
opérationnels qu'un serveur maintient ; et un nom sous forme numérique
(`2.5.4.35` est `userPassword`).

### Dans une base de données SQL {#in-a-sql-database}

Deux requêtes facultatives d'un bloc `users "sql"` lisent des attributs **par
alias de colonne**. La première colonne est le nom de la personne ou du
groupe ; chaque autre colonne est un attribut nommé par son alias :

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

- Les requêtes positionnelles `users` et `groups` sont inchangées, et une
  sixième colonne positionnelle est toujours refusée : les attributs viennent
  par nom, dans leur propre requête.
- Une colonne dont l'alias n'est pas une description d'attribut (une
  expression sans alias comme `count(*)`), ou nomme un identifiant, est
  refusée avec son numéro de colonne avant qu'une ligne ne soit lue.
- `NULL` et `''` valent absence. Un nom peut revenir sur plusieurs lignes, et
  les valeurs de toutes sont gardées, si bien qu'une jointure vers une table
  d'adresses en donne plusieurs à une personne.
- Un groupe nommé seulement dans `groups_attributes` **existe**, sans personne
  dedans : c'est ainsi que s'écrit le groupe principal propre d'une personne.

{{< callout type="warning" >}}
**La casse d'un alias est celle de la base de données**

PostgreSQL met en minuscules un alias sans guillemets : `as uidNumber` revient
sous la forme `uidnumber`. Les noms d'attributs ne tiennent pas compte de la
casse, donc c'est le même attribut et l'entrée est la même entrée pour tout
client LDAP, mais la graphie qu'affiche authnd est celle de la base. Mettez
l'alias entre guillemets là où la graphie compte : `gid as "gidNumber"`.
SQLite garde un alias tel qu'il est écrit.
{{< /callout >}}

### Depuis un autre annuaire LDAP {#from-another-ldap-directory}

Un bloc `users "ldap"` copie les attributs qu'on lui indique, depuis l'entrée
de chaque personne et celle de chaque groupe : `attributes = ["mail",
"uidNumber", "homeDirectory"]` et `group_attributes = ["gidNumber"]`. Voir
[personnes]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

## Une configuration, et ce qu'elle publie {#a-configuration-and-what-it-publishes}

Le bloc SQL ci-dessus, avec un lecteur, sur une base SQLite de cinq personnes
et quatre groupes, tel que le vérifie le binaire de la version v0.11.0 :

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

`PUBLISHED AS` donne les classes d'objets de chaque entrée, sans `top`, et
`WITH` ses attributs, lus sur les entrées que renvoie une recherche. hal a un
`uidNumber`, un `gidNumber` et un `mail`, et ni `homeDirectory` ni `sn` : hal
est un `account`, qui n'autorise aucun des trois, donc ils sont écartés et le
reste est publié. Le serveur dit la même chose au démarrage (et `stopping`
quand il a été arrêté) :

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

Relu par le `ldapsearch` d'OpenLDAP, avec le mot de passe du lecteur dans un
fichier :

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

`alumni` n'est nommé que dans `groups_attributes`, donc il existe sans
personne dedans ; sans `gidNumber`, c'est un `organizationalRole`.
`nobody-yet` a un `gidNumber` et personne, donc c'est un `posixGroup` sans
`memberUid`.

Quelle classe trouve qui :

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

## Ce qui est écarté, et ce qui est retenu {#what-is-dropped-and-what-is-withheld}

| donné | l'entrée | pourquoi |
|---|---|---|
| `uidNumber`, `gidNumber`, pas de `homeDirectory`, pas de `sn` | `account, uidObject`, sans les deux | *no class of the entry allows it; posixAccount would* |
| `mail`, pas de `sn` | `account, uidObject`, sans lui | *no class of the entry allows it; inetOrgPerson would* |
| un type que le schéma ne définit pas | le reste | *the schema served here does not define it* |
| `mail` sur un groupe sans `gidNumber` | `groupOfNames`, sans lui | |
| deux valeurs de `homeDirectory` avec le trio POSIX | **retenue** : SINGLE-VALUE, rien à écarter | |
| un `gidNumber` qui n'est pas un entier | **retenue** : pas de sa syntaxe | |

**Seul ce qu'une source a donné est écarté**, et quel attribut n'est pas
autorisé est la réponse de `Validate`, pas une seconde lecture du schéma.
L'entrée est validée de nouveau après l'écartement. Une entrée qui échoue
encore est **retenue** : elle est absente de toute recherche, le journal de
démarrage la nomme, et `check` la liste avec chaque problème trouvé par
`Validate`. Un attribut qu'authnd dérive lui-même (`uid`, `cn`, `objectClass`,
`sshPublicKey`, `sambaSID`, `sambaNTPassword`) et que le schéma refuserait
serait un défaut d'authnd, et retient l'entrée plutôt que de la publier sans.

Le `gidNumber` d'alice est ici un mot :

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

Une fois servie, alice peut toujours se lier et n'apparaît dans aucune
recherche, et le serveur dit pourquoi au démarrage :

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

Ce qui est retenu, c'est l'entrée que renvoie une recherche, pas l'identité.

## Le schéma qu'il sert {#the-schema-it-serves}

Le DSE racine le nomme (`subschemaSubentry: cn=Subschema`, sur
[le root DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})),
et une recherche de base sur `cn=Subschema` le renvoie (RFC 4512 §4.2) : les
définitions standard qu'embarque go-authn/ldap — RFC 4512, 4517, 4519, 4523,
4524, 2798, 2307, 3672 et 3045, et openssh-lpk — plus `sambaSamAccount`,
`sambaSID` et `sambaNTPassword` de Samba quand il y a un
[bloc `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}). Les
définitions ne sont publiées que lorsqu'on les demande par leur nom ou avec
`+`. Abrégé là où c'est indiqué :

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

L'entrée entière faisait 327 lignes : 49 syntaxes, 40 règles de
correspondance, 36 usages de règles de correspondance, 143 types d'attributs
et 52 classes d'objets. Contrairement à une recherche sous la base, l'entrée
de sous-schéma, comme le DSE racine, est servie à un client anonyme : la même
requête sans `-D` ni `-y` l'a renvoyée.

**Les filtres utilisent les règles de correspondance du schéma**, si bien que
`(uidNumber>=1000)` compare des entiers. `uidNumber` et `gidNumber` ont
`ORDERING integerOrderingMatch`, que la RFC 2307 ne leur donne pas ; slapd et
draft-howard-rfc2307bis-02 le font, et go-authn/ldap aussi
([son seul écart]({{< relref "/libraries/ldap.md#the-schema" >}})).
Comme chaînes, `1000` se classe avant `999` :

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

hal n'y est pas : le `uidNumber` de hal a été écarté. Une plage sur un
attribut sans règle ORDERING, comme `uid`, est Undefined et ne correspond à
rien.
