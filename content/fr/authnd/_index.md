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
la v0.15.0, dont les entrées suivent les schémas standard et respectent le schéma
qu'elle sert à `cn=Subschema`, qu'un site étend avec le sien
([SUPANN, eduPerson]({{< relref "/authnd/schemas.md" >}})) et façonne grâce aux
[règles de contenu DIT, formes de noms et règles de structure]({{< relref "/authnd/schemas.md#rules" >}}),
avec go-authn/ldap v0.12.0 et
go-authn/directory v0.17.0 en dessous ; ce qui est vérifié et ce qui ne l'est pas figure sur la
page [état]({{< relref "/status.md" >}}).

{{< callout type="warning" >}}
**Mise à jour depuis la v0.14.x**

- ⛔ **Deux valeurs par défaut changent.** `max_connections` vaut `4096` (illimité
  auparavant) et `operation_timeout` vaut `30s` (aucun auparavant). Un site qui
  garde plus de connexions ouvertes, ou qui exécute une opération de plus de 30
  secondes, définit la clé ; `0` (`"0"` pour la durée) est l'ancien comportement.
  Voir [limites]({{< relref "/authnd/operations.md#limits" >}}).
- Nouveau, tout facultatif : `max_connections_per_ip` et `startup_timeout` (`60s`).
- Un annuaire amont en panne reçoit la réponse `unavailable` (52), et non plus
  `invalidCredentials` (49) : un client qui lit 49 comme « mauvais mot de passe »
  et 52 comme « réessayez plus tard » distingue désormais les deux.
- Un certificat TLS renouvelé est servi sans redémarrage :
  [renouveler le certificat]({{< relref "/authnd/tls.md#renewal" >}}).

`authnd check` affiche les limites avec lesquelles il servira.
{{< /callout >}}

{{< callout type="warning" >}}
**Mise à niveau depuis la v0.11.x**

- ⛔ **Sécurité : prenez la v0.12.0, pas la v0.11.1.** Les binaires de la
  v0.11.1 ont été compilés avec Go 1.27.2, dont crypto/x509 ne révoque pas la
  confiance dans les certificats intermédiaires compromis que nomme
  GO-2026-6809, et authnd vérifie des certificats. La v0.12.0 est compilée avec
  Go 1.27.3, et sa directive `go` est 1.27.3 : `go install` passe donc de
  lui-même à la chaîne d'outils corrigée.
- Une configuration qui n'utilise pas les nouvelles clés publie ce que publiait
  la v0.11.1 : une classe est déclarée, jamais déduite, si bien que sans
  `object_classes` rien ne change.
- Nouveau, tout est facultatif : [`schema_files` et un bloc `schema`]({{< relref "/authnd/schemas.md" >}})
  ajoutent les définitions d'un site au schéma servi, et `object_classes` et
  `group_object_classes` déclarent les classes auxiliaires que portent les
  personnes et les groupes d'une source. Une définition qui en redéfinit une
  déjà présente est refusée, même mot pour mot, comme le refuse slapd.
- `check` et le journal de démarrage disent quels fichiers et quels blocs ont
  été chargés, ce que déclare chaque source, quelles classes ont été retirées
  à une personne faute d'un MUST, et quels groupes deux sources
  décrivent différemment.

Lancez `authnd check` avec le nouveau binaire avant le redémarrage, comme le
dit [l'installation]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}}).
{{< /callout >}}

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
Voici les réponses du binaire de la version v0.12.3 au client propre d'OpenLDAP :

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
vendorVersion: v0.13.0
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
| [Schémas de site]({{< relref "/authnd/schemas.md" >}}) | `schema_files`, le bloc `schema` et `object_classes` : SUPANN, eduPerson ou les attributs propres à un site ; règles de contenu DIT, formes de noms et règles de structure DIT |
| [`check`]({{< relref "/authnd/check.md" >}}) | relire la configuration avant de redémarrer |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` ou StartTLS, et `publish_nt_hash` |
| [Changer un mot de passe]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`, `ldapmodify`, et pourquoi l'ancien mot de passe est toujours demandé |
| [Un royaume Kerberos]({{< relref "/authnd/kerberos.md" >}}) | le keytab, et qui peut recevoir un ticket |
| [Un second facteur]({{< relref "/authnd/mfa.md" >}}) | un code à usage unique au bout du mot de passe |
| [Un jeton à la liaison]({{< relref "/authnd/tokens.md" >}}) | OIDC sur SASL `OAUTHBEARER` |
| [L'exploiter]({{< relref "/authnd/operations.md" >}}) | signaux, redémarrages, limites de connexions et délais, ce qu'il journalise, comment savoir qu'il tourne |

{{< callout type="info" >}}
**À propos des transcriptions**

Chaque commande montrée sur ces pages a été relancée le 26 octobre 2026 avec les binaires publiés, et non retapée : `authnd` v0.12.3 (`authnd-darwin-arm64`, vérifié par `relverify` avec `SHA256SUMS` et son attestation ; `go version -m` : `go1.27.3`, `mod github.com/go-authn/authnd v0.12.3`, `vcs.modified=false`), `authn-bridge` v0.23.4, `authn-revokd` v0.6.6, `sshcert-authorize` v0.1.9 et `ldapschema` v0.10.1. Ce que les commandes ont affiché est ce qui figure ici. Deux transcriptions font exception, et chacune le dit là où elle se trouve : le client `oidctool` de [la page des jetons]({{< relref "/authnd/tokens.md" >}}), un client de test écrit pour ces pages et qui ne fait partie d'aucune version publiée, dont les transcriptions et les lignes du serveur qui les accompagnent ont été affichées par le binaire de la version v0.10.0 ; et les métadonnées expirées de RENATER sur [la page de la fédération]({{< relref "/authn-bridge/federation.md" >}}), un fichier qui n'est plus publié. Toutes ont été demandées par les clients OpenLDAP et Heimdal livrés avec macOS, sur 127.0.0.1 sur des ports non privilégiés, dans un répertoire de travail jetable. C'est pourquoi les configurations derrière elles nomment des fichiers par des chemins relatifs comme `etc/authnd/passwords/alice.pw`, et pourquoi les fichiers de mots de passe ont des noms comme `alice.pwin`. Les chemins `/etc/authnd` des exemples sont ceux qu'utilise un serveur installé. Les transcriptions qui impriment la version d'`authnd` ont été rejouées avec v0.13.0 (`authnd-darwin-arm64`, vérifié par `relverify` contre `SHA256SUMS` et son attestation ; `go version -m` : `go1.27.3`, `mod github.com/go-authn/authnd v0.13.0`) : la root DSE ici et sur la page d'exploitation, et `authnd --version`. Le schéma de la page des entrées a été affiché par v0.12.4 (`mod github.com/go-authn/authnd v0.12.4`, `vcs.modified=false`) ; v0.13.0 n'affiche aucune valeur de `dITContentRules`, `nameForms` ou `dITStructureRules` pour un schéma sans règles, ce qui a été vérifié. La [section des règles de la page des schémas de site]({{< relref "/authnd/schemas.md#rules" >}}) dit avec quoi elle a été rejouée.

Les transcriptions nouvelles de la version 0.7 de la documentation (la ligne `limits:` de `check`, et l'exécution avec signaux de la page d'exploitation) ont été produites le 2026-11-01 par `authnd` v0.15.0, compilé avec `go install` depuis l'étiquette (`go version -m` : `go1.27.3`, `mod github.com/go-authn/authnd v0.15.0` ; `authnd --version` : `authnd version v0.15.0`) et par `ldappasswd` d'OpenLDAP, sur 127.0.0.1, dans un répertoire de travail. `authn-bridge --version` a affiché `authn-bridge version v0.23.6` et `authn-revokd -version` a affiché `authn-revokd v0.6.7`, compilés de la même façon. Les autres transcriptions n'ont pas été rejouées pour cette version : chacune a été produite par la version que son texte nomme, et les pages d'authn-bridge et d'authn-revokd décrivent un comportement que v0.23.6 et v0.6.7 ne changent pas dans ce qu'une transcription montre.
{{< /callout >}}
