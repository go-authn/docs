---
title: "authnd, un serveur LDAP pour des personnes qui sont ailleurs"
linkTitle: "authnd"
weight: 10
description: "Un annuaire LDAP, et en option un royaume Kerberos, sur des personnes tenues dans un fichier de configuration, une base de données SQL ou un autre annuaire."
tags: [authnd, ldap]
---

**Les personnes d'un site sont déjà dans une base de données, un fichier ou un autre annuaire. Ce
qui veut les authentifier parle LDAP.** authnd est la façade : il
se lie et cherche sur les sources de [go-authn/directory]({{< relref "/libraries/_index.md" >}}),
si bien que ce que contient une base de données peut être lu par tout ce qui sait
interroger un annuaire. Pur Go, `CGO_ENABLED=0`, un seul binaire. Ces pages décrivent
la v0.11.0, dont les entrées suivent les schémas standard et respectent le schéma
qu'elle sert à `cn=Subschema`, avec go-authn/ldap v0.8.0 et go-authn/directory
v0.14.0 en dessous ; ce qui est vérifié et ce qui ne l'est pas figure sur la
page [état]({{< relref "/status.md" >}}).

{{< callout type="warning" >}}
**Mise à niveau depuis la v0.10.x**

- `publish_nt_hash = true` demande désormais un [bloc `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}),
  sans quoi authnd ne démarre pas.
- Une personne sans `uidNumber`, `gidNumber` et `homeDirectory` n'est plus
  un `posixAccount`, et un groupe sans `gidNumber` n'est plus un
  `posixGroup`, si bien qu'un consommateur qui filtre sur ces classes voit
  moins d'entrées : voir [les entrées]({{< relref "/authnd/entries.md" >}}).
- Un bloc `users "ldap"` lit par défaut davantage de l'annuaire derrière lui :
  voir [personnes]({{< relref "/authnd/people.md#in-another-ldap-directory" >}}).

`authnd check` avec le nouveau binaire dit ces trois choses avant le redémarrage.
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## La plus petite configuration {#the-smallest-configuration}

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

Les personnes sont publiées sous `uid=<name>,ou=people,<base_dn>`, les groupes
sous `cn=<name>,ou=groups,<base_dn>`. Ce que *est* chaque entrée découle de ce
que sa source a donné : une personne est un `account`, ou un `inetOrgPerson`
quand il y a un `sn`, et un `posixAccount` seulement avec `uidNumber`,
`gidNumber` et `homeDirectory` ; chaque personne est un `uidObject`. Un groupe
est un `posixGroup` (avec `memberUid`) quand il a un `gidNumber`, sinon un
`groupOfNames` (avec des DN `member`), ou un `organizationalRole` quand il est
de plus vide. `sshPublicKey` est ajouté quand la personne a des clés, et
`sambaNTPassword` quand
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}}) le dit
et qu'un SID peut être donné. Chaque entrée respecte le schéma servi à
`cn=Subschema` avant d'être publiée : voir
[les entrées et le schéma]({{< relref "/authnd/entries.md" >}}). Jusqu'à la
v0.10.2, chaque personne était un `posixAccount` et chaque groupe un
`posixGroup`, quoi qu'ils aient.

`--config` (`-c`) prend un fichier ou un répertoire et peut être répété ; un répertoire
vaut tous les fichiers `.hcl` qu'il contient, lus dans l'ordre des noms et fusionnés en une seule
configuration. Une configuration sans `base_dn`, ou sans personne dedans, ne
démarre pas.

## Qui peut se lier, et qui peut lire {#who-may-bind-and-who-may-read}

On demande à un serveur LDAP de prouver des personnes : ses refus sont donc la conception même.
Voici les réponses du binaire de la version v0.10.0 au client propre d'OpenLDAP :

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| requête | réponse | pourquoi |
|---|---|---|
| nom vide, mot de passe vide (RFC 4513 §5.1.1, anonyme) | succès | elle dit « je ne suis personne », ce qui est vrai, et un client l'envoie avant d'avoir découvert quoi que ce soit |
| un **nom** et un mot de passe vide (§5.1.2, non authentifiée) | `unwillingToPerform` | elle nomme quelqu'un et ne prouve rien ; le §5.1.2 demande exactement ce code. `invalidCredentials` dirait à une personne que son mot de passe était faux |
| un mauvais mot de passe, ou un nom que personne ici ne porte | `invalidCredentials` | les deux ne sont pas distingués |
| une recherche par quiconque n'est pas un `reader` | `insufficientAccessRights` | se lier prouve qui vous êtes ; lire tout le monde est une autre chose, à autoriser à part |
| `add`, `delete`, `modifyDN` | `unwillingToPerform` | aucun gestionnaire n'y est branché ; la seule écriture est [le mot de passe d'une personne, par elle-même]({{< relref "/authnd/passwords.md" >}}) |

Un `reader` est un compte de service avec un DN de liaison et `password` ou
`password_file` ; un reader qui n'a ni l'un ni l'autre est refusé au démarrage (*un reader qui
ne prouve rien, c'est une recherche anonyme avec des étapes en plus*). Sans aucun reader,
rien ne peut chercher, et `check` le dit.

Le DSE racine est servi à un client anonyme, comme la découverte l'exige :

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.11.0
```

`1.3.6.1.4.1.4203.1.11.1` est l'opération de modification de mot de passe de la RFC 3062.
`subschemaSubentry` nomme le [schéma]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}),
qui est servi aussi à un client anonyme.
`supportedSASLMechanisms: OAUTHBEARER` n'apparaît qu'avec un
[bloc `oidc`]({{< relref "/authnd/tokens.md" >}}).

## Pour aller plus loin {#where-to-go-next}

| | |
|---|---|
| [L'installer]({{< relref "/authnd/install.md" >}}) | le binaire de la version, le compte `authnd`, l'unité systemd, les mises à niveau |
| [D'où viennent les personnes]({{< relref "/authnd/people.md" >}}) | les blocs `user` et `group`, une base de données SQL, un autre annuaire LDAP |
| [Les entrées et le schéma]({{< relref "/authnd/entries.md" >}}) | ce sous quoi chaque personne et chaque groupe est publié, `cn=Subschema`, les attributs, ce qui est écarté ou retenu |
| [`check`]({{< relref "/authnd/check.md" >}}) | relire la configuration avant de redémarrer |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` ou StartTLS, et `publish_nt_hash` |
| [Changer un mot de passe]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, et pourquoi l'ancien mot de passe est toujours demandé |
| [Un royaume Kerberos]({{< relref "/authnd/kerberos.md" >}}) | le keytab, et qui peut recevoir un ticket |
| [Un second facteur]({{< relref "/authnd/mfa.md" >}}) | un code à usage unique au bout du mot de passe |
| [Un jeton à la liaison]({{< relref "/authnd/tokens.md" >}}) | OIDC sur SASL `OAUTHBEARER` |
| [L'exploiter]({{< relref "/authnd/operations.md" >}}) | signaux, redémarrages, ce qu'il journalise, comment savoir qu'il tourne |

{{< callout type="info" >}}
**À propos des transcriptions**

Chaque tableau de `check`, chaque ligne de démarrage, les entrées relues avec
`ldapsearch`, le root DSE et `cn=Subschema`, les refus liés à `samba` et les
lignes `--version` ont été affichés par le binaire de la version v0.11.0
(`authnd-darwin-arm64`, `go version -m` : `mod github.com/go-authn/authnd v0.11.0`,
`vcs.modified=false`). De même pour les refus de configuration de ces pages,
que la v0.11.0 a affichés octet pour octet comme la v0.10.0. Les liaisons, les
`kinit`, les changements de mot de passe et les échanges de jetons ont été
affichés par le binaire de la version v0.10.0 et n'ont pas été relancés pour la
v0.11.0, dont les notes de version n'en changent aucun. Tous ont été demandés
par les clients OpenLDAP et Heimdal livrés avec macOS, sur 127.0.0.1 sur des
ports non privilégiés, dans un répertoire de travail sous `/tmp`. C'est
pourquoi les configurations derrière elles nomment des fichiers par des chemins relatifs comme
`etc/authnd/passwords/alice.pw`, et pourquoi les fichiers de mots de passe ont des noms comme
`alice.pwin`. Les chemins `/etc/authnd` des exemples sont ceux qu'utilise un serveur
installé.
{{< /callout >}}
