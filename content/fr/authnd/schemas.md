---
title: "Schémas de site, et les classes qu'une source déclare"
linkTitle: "Schémas de site"
weight: 27
description: "Servir SUPANN, eduPerson ou les attributs propres à un site : schema_files et le bloc schema ajoutent des définitions, object_classes déclare quelles classes auxiliaires portent les personnes et les groupes d'une source, et check dit ce qui a été retiré."
tags: [authnd, ldap, schéma, configuration]
---

**Un attribut SUPANN ou eduPerson est écarté tant qu'une classe de son entrée
ne l'autorise pas.** authnd ne publie que ce que permet le schéma qu'il sert (voir
[les entrées]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})),
et le schéma standard ne connaît rien de `supannEtablissement` ni de
`eduPersonAffiliation`. À partir de la v0.12.0, un site dit trois choses, dans cet ordre :

1. **quelles définitions ajouter** : `schema_files`, les fichiers que son slapd
   charge déjà, et un bloc `schema { }` pour ce qui n'est que local ;
2. **quelles classes auxiliaires portent ses personnes et ses groupes** : `object_classes` ;
3. rien d'autre. Une classe est **déclarée, jamais déduite** : un attribut
   qui apparaît dans une base de données ne change pas ce sous quoi une entrée est publiée.

{{< callout type="info" >}}
**L'exemple de cette page est un exemple**

`example.schema` ci-dessous a été écrit pour cette page. Ses OID sont sous
`1.3.6.1.4.1.99999`, un arc que personne ne se voit attribuer : utilisez les vôtres, et ne
copiez jamais ceux-ci. Pour SUPANN, voir [la fin de la page](#supann).
{{< /callout >}}

## Un exemple : un schéma, une base de données, une configuration {#an-example}

Un schéma sous la forme `.schema` d'OpenLDAP : une classe qu'une source peut déclarer
(`exampleStaff`, AUXILIARY, avec un MUST), et une qu'elle ne peut pas
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

Une base de données SQLite de trois personnes, avec `sn`, un badge et un numéro de personnel
(`sqlite3 var/people.db < people.sql`) :

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

Et la configuration :

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

Sans la ligne `object_classes`, `check` dit ce que fait le schéma standard
seul des mêmes personnes : les attributs sont écartés, et chaque ligne
nomme la classe qui les aurait gardés.

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

`schema_files` est une liste de fichiers `.schema` d'OpenLDAP ou de fichiers LDIF cn=config.
Ils sont chargés **tels que publiés**, dans l'ordre, par-dessus le schéma standard (et
les trois définitions de Samba, avec le [bloc `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}})), par les
[lecteurs compatibles slapd]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}) de go-authn/ldap :
n'importe quel ordre des termes, les continuations de slapd et de la RFC 2849, le base64, les préfixes
de longueur `{N}`, et les macros `objectidentifier`, qu'un fichier peut définir et que le suivant
utilise, comme à travers l'`include` de slapd. Rien n'est converti au préalable : le fichier
que charge le slapd d'un site est le fichier que charge authnd. Les définitions sont servies à
`cn=Subschema`.

- Un chemin relatif l'est au répertoire de travail, comme tous les autres chemins
  de la configuration. Utilisez des chemins absolus dans un service : le répertoire de
  travail d'une unité systemd est `/`.
- Chaque fichier doit être un fichier ordinaire d'au plus 4 Mio, et il est lu une seule fois, au
  démarrage.
- Les fichiers décident de ce que chaque entrée peut contenir. Ce ne sont pas des secrets, mais gardez-les
  avec le reste de la configuration : `root:authnd`, mode `0640`, dans un
  répertoire que seul root peut écrire ([l'installation]({{< relref "/authnd/install.md" >}})).
- Un fichier qui ne se construit pas refuse le démarrage, et `check`, avec le
  fichier, la ligne et la colonne où la définition commence, et le genre de
  refus à la fin du message : une superclasse, un attribut, une règle de
  comparaison ou une syntaxe inconnus (`unknown reference`), une classe
  structurelle dérivée d'une classe auxiliaire (`kind violation`), un OID ou un
  nom défini deux fois (`duplicate OID`, `duplicate name`). Depuis la v0.12.1,
  la place et le genre viennent de la
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}) typée
  de go-authn/ldap, et non de la lecture de son message. Une définition lue dans
  un fichier commence à la colonne 1, y compris quand son texte est replié sur
  plusieurs lignes. Un doublon dit où se trouve sa première définition, et une
  redéfinition dit quel fichier standard, ou quelle ligne d'un fichier
  précédent, détient l'original. Deux exemples :

  `cases/unknown.schema` a un MAY qui n'est défini nulle part :

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema` donne un même OID à deux types d'attribut :

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

### Une redéfinition est refusée, même identique {#redefinition}

Un fichier ne peut pas définir ce qui est déjà là : les définitions du schéma standard,
celles de Samba, ou celles d'un fichier précédent. Elle est refusée **même mot
pour mot**, ce qui est la règle de slapd lui-même : les définitions d'un fichier de schéma passent par
`parse_at` et `parse_oc`, et slapd répond à un OID ou un nom déjà indexé
par *Duplicate attributeType* (mêmes OID et noms) ou *Inconsistent duplicate
attributeType* (`servers/slapd/at.c`, `oc.c`). Seul le schéma codé en dur de slapd
a le droit au premier. Un fichier que slapd refuse est un fichier qu'authnd refuse.

L'autre lecture devrait choisir un gagnant, et ce serait un changement silencieux de
ce que l'on dit à chaque client qu'est un attribut standard ; refuser nomme la ligne
à la place. Le refus dit si le texte était le même. Un fichier qui
redéfinit `cn` (2.5.4.3) avec une définition qui lui est propre :

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## Le bloc `schema { }` {#the-schema-block}

Pour les définitions qui ne sont que locales, un bloc `schema` les contient en
HCL2, dans la [forme de hclschema]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}) :
`attribute_type`, `object_class`, `object_identifier`, `matching_rule` et
`ldap_syntax`. Il est lu **après** les fichiers, il peut donc utiliser leurs
définitions, et il peut y en avoir plusieurs.

Les valeurs doivent être des **littéraux** : ni variables, ni fonctions, ni `${...}` ni
`%{...}`. Le bloc est décodé par le même décodeur que celui qui lit un fichier de schéma
`.hcl`, avec les mêmes bornes, et chaque erreur nomme la ligne et la colonne de la
configuration elle-même. Un bloc qui n'est pas dans la syntaxe native de HCL est refusé.

## `object_classes` {#object-classes}

Une définition dans le schéma autorise un attribut ; elle ne met la classe sur
personne. Une source **déclare** les classes auxiliaires sous lesquelles ses personnes et ses groupes
sont publiés :

| où | clé | ce qu'elle déclare |
|---|---|---|
| bloc `users`, de toute sorte | `object_classes` | les classes de chaque personne que donne le bloc |
| bloc `users`, de toute sorte | `group_object_classes` | les classes de chaque groupe |
| bloc `user` | `object_classes` | les classes de cette personne |
| bloc `group` | `object_classes` | les classes de ce groupe |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

Ces clés sont celles de go-authn/directory, à partir de la v0.15.0
([bibliothèque]({{< relref "/libraries/directory.md#object-classes" >}})). Les noms
sont comparés sans tenir compte de la casse, et gardés une seule fois, dans l'ordre où ils sont écrits.

Ce que fait authnd d'une classe déclarée :

- **Elle est publiée avec ses superclasses**, après les classes qu'authnd déduit
  (RFC 4512 §3.3 : toutes les superclasses des classes nommées sont implicitement
  ajoutées). Les attributs que la classe autorise sont gardés au lieu d'être écartés.
- **Elle n'est jamais déduite.** Une personne dont la source ne déclare rien continue
  de perdre les attributs qu'aucune de ses classes n'autorise, quoi que contienne la base de données.
- **Une personne à qui manque un MUST d'une classe déclarée est publiée sans cette
  classe.** Ses attributs sont écartés comme tout attribut qu'aucune classe n'autorise, et
  les deux sont rapportés. C'est la règle qu'authnd suit partout : la personne
  reste publiée, le problème est dit, rien n'est changé en silence.
  Retenir la personne la sortirait de toute recherche pour un seul attribut manquant ;
  publier la classe sans son MUST servirait une entrée qui
  ne respecte pas le schéma servi.
- **Deux sources peuvent déclarer des classes différentes pour un même groupe.** La première
  source qui déclare des classes pour un groupe décide, en entier, et une liste ultérieure est
  ignorée : ni fusionnée ni une erreur. `check` le dit.

Ici ann a tout, cat n'a pas de casier (un MAY), et ben n'a pas
`exampleEmployeeId`, un MUST de `exampleStaff` :

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

Le journal de démarrage porte les mêmes lignes, avec des DN :

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

Et ce que relit le `ldapsearch` d'OpenLDAP, avec le mot de passe du lecteur dans un
fichier. ann porte les deux classes auxiliaires, et tous les attributs qu'elles autorisent ; ben
ne porte que `exampleLockerHolder`, et son badge a disparu avec
`exampleStaff` ; cat porte les deux, avec son numéro de personnel :

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

## Ce qui est refusé, et pourquoi {#what-is-refused}

Une classe déclarée est vérifiée au démarrage, et par `check`, contre le schéma
servi. Elle doit être :

- **définie**, par le schéma standard, un fichier ou un bloc ;
- **AUXILIARY** (RFC 4512 §4.1.1). Une entrée a exactement une chaîne structurelle
  (§2.4.2), qu'authnd choisit d'après ce que la personne a ; une déclaration
  ne peut pas en ajouter une seconde ;
- **pas une classe qu'authnd déduit lui-même** : `account`, `inetOrgPerson` et ses
  superclasses, `posixAccount`, `posixGroup`, `ldapPublicKey`, `uidObject`,
  `sambaSamAccount`, `groupOfNames` et `organizationalRole`, sous n'importe lequel de
  leurs noms. Elles découlent de ce qu'une personne ou un groupe a, et une
  déclaration ne peut pas passer outre `check`.

Sinon le démarrage est refusé, en nommant le bloc, sa position et la classe.
`exampleUnit` est STRUCTURAL :

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory vérifie la **graphie** avant cela : une classe est un
descripteur, jamais un OID, un espace, un guillemet ni une parenthèse.

Refusés aussi, pour la même raison de garder le schéma honnête :

| refusé | pourquoi |
|---|---|
| un fichier qui redéfinit une définition, même mot pour mot | la règle de slapd : [ci-dessus](#redefinition) |
| un fichier qui n'est pas un fichier ordinaire, ou de plus de 4 Mio | un FIFO bloquerait le démarrage, `/dev/zero` ne finirait jamais |
| un bloc `schema` avec une variable, une fonction ou `${...}` | des valeurs littérales seulement, comme dans un fichier de schéma `.hcl` |
| une classe indéfinie dans `object_classes` | une promesse que rien ne peut vérifier |
| une classe STRUCTURAL, ou une que déduit authnd | la liste ci-dessus |

## Ce qu'affiche `check` {#what-check-prints}

Quatre sortes de lignes, en plus de [celles d'habitude]({{< relref "/authnd/check.md" >}}) ; le journal de démarrage porte les mêmes :

- **`schema: <file> adds …`** et **`schema: the schema block at <file>:<line>:<column> adds …`** :
  ce que chaque fichier et chaque bloc a ajouté, compté en macros d'identifiant
  d'objet, types d'attribut et classes d'objet ;
- **`<file>:<line>:<column>: users "sql" declares … for its people`** (un
  bloc `user` ou `group` dit `user "ann" declares … for this person` et
  `group "staff" declares … for this group`) : ce que déclare chaque source ;
- **`<name> is published without <class>, which its source declares: …`**,
  en nommant le MUST qui manque à la personne ;
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`** :
  deux sources en désaccord sur un groupe, ce qui serait sinon silencieux.

Les attributs écartés faute d'une classe sont les lignes `is published without
<attribute>: no class of the entry allows it; <classes> would` que
[les entrées]({{< relref "/authnd/entries.md" >}}) décrivent déjà : avec une
déclaration, elles nomment la classe que vous n'avez pas déclarée.

## SUPANN, comme exemple réel {#supann}

SUPANN est l'ensemble d'attributs de l'enseignement supérieur et de la recherche français
(`supannPerson`, `supannEtablissement`, `supannEntite`…), avec eduPerson
à côté. RENATER publie le schéma technique, avec les autres, sur sa page
de documentation :

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**Téléchargez le fichier depuis là.** Il n'est pas reproduit sur ce site : il
n'indique aucune licence, cette page ne le copie donc pas, et une copie ici deviendrait
périmée quand RENATER le révise. Ensuite :

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

Lancez `authnd check` et lisez d'abord les lignes `schema:` : un fichier que slapd
charge se charge ici, et un fichier qui redéfinit une définition standard est refusé
avec sa ligne. Lisez ensuite les lignes *published without* : une personne à qui manque un
MUST de `supannPerson` ou d'`eduPerson` est publiée sans la classe, et
`check` nomme le MUST. Mettez un alias entre guillemets là où sa graphie compte
(PostgreSQL met en minuscules un alias sans guillemets ; voir
[les entrées]({{< relref "/authnd/entries.md#in-a-sql-database" >}})).

{{< callout type="info" >}}
**À propos des transcriptions**

Chaque commande de cette page a été relancée le 26 octobre 2026 avec le binaire de la version v0.12.3 (`authnd-darwin-arm64`, vérifié avec `SHA256SUMS` ; `go version -m` : `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`) et le `ldapsearch` d'OpenLDAP, sur 127.0.0.1, dans un répertoire de travail jetable, avec les fichiers montrés. Les chemins sont relatifs pour cette raison ; un service utilise des chemins absolus. Le schéma est un exemple écrit pour cette page.
{{< /callout >}}
