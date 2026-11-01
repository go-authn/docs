---
title: "check, avant de redémarrer ce par quoi des gens se connectent"
linkTitle: "check"
weight: 30
description: "Ce qu'authnd check ouvre, ce qu'il affiche sur une configuration avant qu'elle ne soit servie, comment le lire, et la seule défaillance qu'il ne peut pas voir."
tags: [authnd, check, configuration]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check` lit la configuration exactement comme le serveur, **ouvre
tout ce que le serveur ouvre avant d'écouter** — les fichiers, la base de données,
l'annuaire derrière celui-ci, le document de découverte du fournisseur d'identité,
le certificat et la clé TLS, le keytab — et affiche ce qui serait publié
et à qui, **sans écouter**. Il affiche d'où vient chaque identifiant
et jamais ce qu'il contient. Il sort avec 0 et termine par *this configuration
can be served*, ou sort avec 1 et la phrase qui arrête le serveur.

## Une configuration qui peut être servie {#a-configuration-that-can-be-served}

Deux blocs `user`, un reader et une base de données SQLite, dans un répertoire de deux
fichiers (`authnd.hcl` et `people.hcl`) :

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## Le lire {#reading-it}

La première ligne donne le schéma, l'adresse et la base : `ldap://`,
`ldaps://` ou `ldap+starttls://` — voir [TLS]({{< relref "/authnd/tls.md" >}}).

| colonne | |
|---|---|
| `FROM` | la source qui possède le nom : *the configuration file*, *a sqlite database* (ou postgres, mysql), ou l'url d'un annuaire derrière celui-ci |
| `CAN PROVE` | *a password* (détenu, donc il peut être comparé et des clés peuvent en être dérivées), *a password check* (un autre annuaire répond oui ou non), *an NT hash*, *N keys*, *a one-time-code secret*, ou *nothing* |
| `PUBLISHED AS` | les classes d'objets de l'entrée, sans `top`, telles que les donnent [les formes]({{< relref "/authnd/entries.md#the-shapes" >}}) — ou *NOT PUBLISHED (see below)* pour une entrée qui ne respecte pas le schéma |
| `WITH` | les attributs que porte l'entrée, lus sur l'entrée que renvoie une recherche : `uid` ; `cn` partout où une classe l'autorise ; ce qu'ont donné les sources, moins ce qui a été écarté ; `sshPublicKey` quand il y a des clés ; `sambaSID` et `sambaNTPassword` quand [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) est activé et que la personne a une clé NT et un SID |

Le tableau des groupes a lui aussi une colonne `PUBLISHED AS` : `posixGroup`,
`groupOfNames` ou `organizationalRole`. Jusqu'à la v0.10.2, `PUBLISHED AS`
était la liste des attributs, *uid and cn* pour presque tout le monde, et il
n'y avait pas de colonne `WITH`.

Les lignes après les tableaux disent ce qu'une personne doit savoir avant de se fier à
la configuration. D'abord, au sujet [des entrées]({{< relref "/authnd/entries.md" >}}) :

- **qui n'est pas un `posixAccount`**, et lesquels de `uidNumber`,
  `gidNumber` et `homeDirectory` lui manquent ;
- **quels groupes n'ont pas de `gidNumber`**, et ce sous quoi ils sont
  publiés à la place ;
- **chaque attribut écarté** parce qu'aucune classe de son entrée ne
  l'autorise, et quelles classes l'autoriseraient ;
- **chaque entrée non publiée**, avec chaque problème trouvé par la
  vérification du schéma ;
- **qui a une clé NT et pas de `sambaSID`**, et donc pas de `sambaNTPassword`.

À partir de la v0.12.0, entre la première ligne et les tableaux, ce qu'un
[schéma de site]({{< relref "/authnd/schemas.md" >}}) a ajouté, et ce que
déclarent les sources :

- **les fichiers de schéma et les blocs `schema` chargés**, et ce que chacun ajoute :
  `schema: etc/authnd/example.schema adds 3 object identifier macros, 2
  attribute types and 2 object classes` ;
- **les classes que déclare chaque source** : `users "sql" declares exampleStaff and
  exampleLockerHolder for its people`, avec la position de la déclaration ;
- **chaque classe retirée à une personne ou à un groupe**, parce qu'il lui
  manque un MUST d'une classe que déclare sa source : `ben is published without exampleStaff, which its
  source declares: ben has no exampleEmployeeId, which exampleStaff
  requires`, puis, après les lignes des attributs, ceux qu'elle a emportés avec elle ;
- **un groupe pour lequel deux sources déclarent des classes différentes** : la liste de
  la première source est publiée et celle de la seconde ignorée.

Un fichier qui ne se construit pas, une redéfinition, et une classe déclarée
qui est indéfinie, STRUCTURAL ou que authnd déduit lui-même arrêtent `check` et le
serveur de la même façon, avec la position du fichier ou de la configuration.

Ensuite, au sujet des liaisons et des recherches :

- **ce que porte une liaison** : *a password*, ou, avec un [bloc `mfa`]({{< relref "/authnd/mfa.md" >}}),
  *a password with a 6-digit code after it* ; avec un [bloc `oidc`]({{< relref "/authnd/tokens.md" >}}),
  d'où viennent les jetons et par quoi ;
- **qui ne peut pas du tout se lier avec un mot de passe** : les personnes connues seulement par une
  empreinte NT — voir [personnes]({{< relref "/authnd/people.md#written-in-the-configuration" >}}) ;
- **qui peut chercher** : les readers, ou *no reader is declared: nothing may
  search, and binds are not affected* ;
- **si `sambaNTPassword` est publié**, et par quoi — voir
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) ;
- avec un [bloc `kerberos`]({{< relref "/authnd/kerberos.md" >}}), le royaume et
  **qui peut et qui ne peut pas recevoir un ticket**, avec la raison ;
- avec un bloc `mfa`, **qui n'a pas de second facteur**, et ne peut donc pas se lier avec
  un mot de passe ; avec un bloc `oidc` à côté, la ligne ajoute qu'un jeton dont
  l'`amr` nomme deux sortes le peut encore ;
- un **groupe qui nomme quelqu'un qu'aucune source ne connaît**.

Ce dernier est publié tel quel — une façade pour un système porte
légitimement des noms qu'un autre possède — mais c'est dit, parce que l'autre
lecture est une faute de frappe. Dans un `posixGroup`, l'inconnu est un
`memberUid` ; dans un `groupOfNames`, c'est un DN `member` qui ne nomme
aucune entrée d'ici, ici `member: uid=zoe,ou=people,dc=example,dc=org`, que
le `ldapdir` de go-authn/directory fait correspondre, depuis la v0.14.0, à
personne. Ici la table
`team_members` de la base de données a une ligne pour `zoe`, qui n'est personne ici :

```
GROUP      MEMBERS              PUBLISHED AS
engineers  dora, eli and zoe    groupOfNames
staff      alice, bob and dora  groupOfNames
[...]
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

(Un *bloc* `group` qui nomme un inconnu est refusé d'emblée ; voir
[personnes]({{< relref "/authnd/people.md#written-in-the-configuration" >}}).)

Depuis la v0.15.0, la deuxième ligne de la sortie est `limits:` : les limites de
connexions, l'échéance d'une opération et l'échéance du démarrage avec lesquelles
authnd fonctionnera, valeurs par défaut comprises. Les transcriptions de cette
page ont été produites par des versions antérieures et ne la montrent pas. On en
trouvera une vraie dans [limites et délais]({{< relref "/authnd/operations.md#limits" >}}).

## Ce qu'il refuse {#what-it-refuses}

Chacun de ces cas arrête `check` comme le serveur, avec le code de sortie 1. Ils
figurent sur les pages auxquelles ils appartiennent ; quelques-uns, tels qu'affichés :

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## Le certificat, le keytab, et la seule chose qu'il ne peut pas voir {#the-certificate-the-keytab-and-the-one-thing-it-cannot-see}

Un certificat qui ne se charge pas et un keytab sans `krbtgt/REALM` sont
refusés par `check`, dans les termes qu'emploierait le serveur :

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

Ce que `check` ne peut pas savoir sans écouter, c'est **si les ports sont
libres**. Un second serveur sur la même adresse Kerberos passe `check` et est
refusé au démarrage :

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## Le lancer sous le compte de service {#run-it-as-the-service-account}

```sh
sudo -u authnd authnd check /etc/authnd
```

pour qu'un fichier que seul root peut lire échoue ici, et non au redémarrage. Lancez-le
avec le **nouveau** binaire avant une mise à niveau ; voir [installation]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}).
