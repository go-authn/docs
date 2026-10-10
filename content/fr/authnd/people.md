---
title: "D'où viennent les personnes"
linkTitle: "Personnes"
weight: 20
description: "Blocs user et group, une base de données SQL, un autre annuaire LDAP : comment chacun s'écrit, l'ordre dans lequel ils sont interrogés, et ce que chacun permet à une personne."
tags: [authnd, configuration, sql, ldap]
---

Un bloc `user` est l'annuaire entier d'un petit site, ou les comptes de service
qu'un grand site garde hors de sa base de données. Un site dont les personnes sont déjà
dans une base de données ou dans LDAP ne devrait pas les copier dans un second endroit qui devient
périmé : un bloc `users` les lit là où elles sont. Le bloc `users` est
le `hcldir` de go-authn/directory, le même que lit
[go-fileshare](https://github.com/go-fileshare/fileshare) : un même
annuaire est décrit de la même façon aux deux.

## Écrites dans la configuration {#written-in-the-configuration}

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| champ | ce que c'est |
|---|---|
| `password` | le mot de passe, en ligne |
| `password_file` | le même, lu depuis un fichier (blancs en début et fin retirés) |
| `nt_hash` | `MD4(UTF16LE(password))`, 32 caractères hexadécimaux — pour un site qui détient cela et non le mot de passe |
| `totp_secret` | un secret de code à usage unique en base32, d'au moins 128 bits ; voir [un second facteur]({{< relref "/authnd/mfa.md" >}}) |
| `authorized_keys` | des lignes `authorized_keys`, publiées comme `sshPublicKey` |
| `authorized_keys_file` | les mêmes, depuis un fichier |

Refusés au démarrage, en nommant la personne :

- `password` et `password_file` ensemble — dites lequel ;
- `password` et `nt_hash` ensemble — l'empreinte est dérivée du mot de passe,
  donc les deux peuvent être en désaccord ;
- `authorized_keys` et `authorized_keys_file` ensemble ;
- un `nt_hash` qui ne fait pas 32 caractères hexadécimaux, une ligne `authorized_keys` qui
  ne s'analyse pas, un `totp_secret` de moins de 128 bits ;
- le même `user` ou `group` deux fois, et un `group` sans membres.

Un membre de groupe qu'aucune source ne connaît est refusé aussi, ce qui attrape une
faute de frappe avant qu'elle n'accorde silencieusement rien du tout :

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**Un `nt_hash` seul ne peut pas se lier**

Une personne écrite avec seulement `nt_hash` est publiée, peut être transmise à un serveur
SMB par `sambaNTPassword`, et **ne peut pas se lier à authnd lui-même** : une
liaison simple LDAP envoie le mot de passe, et une empreinte NT n'est pas un moyen de le
vérifier ici. bob, ci-dessous, n'a qu'une empreinte NT, et cette empreinte est celle du
mot de passe envoyé :

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check` le dit, après les tableaux :

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```
{{< /callout >}}

## Dans une base de données SQL {#in-a-sql-database}

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**Les requêtes sont les vôtres**, parce que les personnes d'un site ont déjà la forme
de ce site. Les colonnes de la requête `users` sont lues **par position** : un nom,
puis l'un quelconque d'un mot de passe, d'une empreinte NT, de clés SSH (une par ligne) et d'un
secret de code à usage unique, dans cet ordre — jusqu'à cinq colonnes. Un NULL est un
identifiant que cette personne n'a pas. Une colonne de mot de passe est comparée telle qu'elle est
stockée : authnd n'a pas de réglage pour une colonne d'empreintes. La requête `groups` renvoie
un nom de groupe et un membre, une ligne par appartenance.

`driver` accepte `postgres` (ou `postgresql`, `pgx`), `mysql` (ou `mariadb`)
et `sqlite` (ou `sqlite3`). La base de données est contactée au démarrage, avant
que quoi que ce soit n'écoute, si bien qu'une base qui ne répond pas arrête le serveur là où
quelqu'un regarde :

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

PostgreSQL sur la même machine, par son socket et l'authentification peer,
n'a pas besoin de mot de passe dans le DSN : `host=/run/postgresql dbname=authnd user=authnd`.
SQLite dans le répertoire d'état : `file:/var/lib/authnd/people.db`.

Une clé qui appartient à l'autre sorte de bloc est refusée plutôt qu'ignorée :

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## Dans un autre annuaire LDAP {#in-another-ldap-directory}

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url` et `base_dn` sont obligatoires. Où se trouvent les personnes et les groupes, et quels
attributs les nomment :

| clé | défaut |
|---|---|
| `user_filter` | `(objectClass=posixAccount)` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(objectClass=posixGroup)` |
| `group_attribute` | `cn` |
| `group_member_attribute` | `memberUid` |
| `totp_attribute` | aucun : il n'existe pas d'attribut standard, et une supposition ne lirait rien tout en ayant l'air d'avoir cherché |
| `start_tls` | `false` |

`sambaNTPassword` et `sshPublicKey` sont lus sous ces noms. Deux choses
sont refusées avant que quoi que ce soit ne soit ouvert :

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

`ldap://` vers une adresse de bouclage et `ldapi://` sont acceptés : personne n'est
sur le chemin.

Un annuaire derrière celui-ci **vérifie** les mots de passe en s'y liant ; il ne
les transmet pas. Ici, un authnd se place devant un autre, sous une base différente :

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS
alice       ldap://127.0.0.1:3893   a password check  uid and cn
bob         ldap://127.0.0.1:3893   a password check  uid and cn
dora        ldap://127.0.0.1:3893   a password check  uid and cn
eli         ldap://127.0.0.1:3893   a password check  uid and cn
svc-backup  the configuration file  a password        uid and cn

GROUP      MEMBERS
engineers  dora and eli
staff      alice, bob and dora

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

*A password check* suffit pour une liaison, et ne suffit jamais pour un
[ticket Kerberos]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})
ni pour SMB.

## L'ordre, et l'unique exception {#order-and-the-one-exception}

Les sources sont interrogées **dans l'ordre où elles sont écrites**, et la première qui
connaît un nom le possède. Les blocs `user` viennent toujours en premier, si bien qu'un compte
de service écrit localement n'est pas supplanté par quelqu'un du même nom
dans la base de données. **L'appartenance aux groupes est l'union** de toutes les sources : `staff`
ci-dessus a alice et bob depuis un fichier et dora depuis une base de données.

{{< callout type="warning" >}}
**Deux noms qui ne diffèrent que par la casse sont refusés**

Un uid est comparé sans tenir compte de la casse (RFC 4519 §2.39), et tout DN aussi, si bien que
`Dora` dans le fichier et `dora` dans une base de données sont un seul nom pour LDAP et deux
personnes pour tout ce qui compare des octets — un changement de mot de passe par l'une atterrirait
sur l'autre. Une telle configuration ne démarre pas :

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## Lues une fois {#read-once}

Chaque source est lue **une fois, au démarrage**. Une personne ajoutée à la base de données, ou
une appartenance modifiée dans l'annuaire derrière celui-ci, est servie après un
redémarrage, pas avant. Cela inclut une colonne de mot de passe dans une base de données : elle est
lue avec le reste de la ligne. Un annuaire derrière celui-ci ne diffère qu'en ce
qu'une liaison est vérifiée en s'y liant, si bien qu'un mot de passe changé *là-bas* est
celui qui fonctionne. L'autre exception est un mot de passe qu'une personne change par
authnd lui-même, qui est [appliqué aussitôt]({{< relref "/authnd/passwords.md" >}}).
Il n'y a pas de rechargement ; voir [le faire tourner]({{< relref "/authnd/operations.md" >}}).
