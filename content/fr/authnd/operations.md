---
title: "L'exploiter : signaux, redémarrages et ce qu'il dit"
linkTitle: "Exploitation"
weight: 80
description: "Ce qu'authnd lit une seule fois, pourquoi SIGHUP ne le recharge pas, comment il s'arrête, ce qu'il écrit sur sa sortie, et comment savoir qu'il tourne."
tags: [authnd, exploitation, signaux, systemd]
---

## Il lit tout une seule fois {#it-reads-everything-once}

Les fichiers de configuration et le keytab sont lus **au démarrage**. Il n'y a
pas de rechargement de ces fichiers, et l'unité fournie n'a pas d'`ExecReload=`.
Après avoir modifié l'un d'eux :

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

Le certificat TLS fait exception depuis la v0.15.0 : authnd examine de nouveau
`cert_file` et `key_file`, si bien qu'un renouvellement n'exige pas de
redémarrage. Voir [renouveler le certificat]({{< relref "/authnd/tls.md#renewal" >}}).

Hors les sources (voir plus bas), la seule chose appliquée pendant qu'il tourne est un
[mot de passe qu'une personne change via authnd]({{< relref "/authnd/passwords.md" >}}),
qui relit les blocs `user` et rien d'autre.

Les sources sont l'exception à « lu une fois ». Les personnes et les groupes sont
relus à chaque `refresh` (60 s par défaut ; `refresh = "0"` le désactive) dans un
nouvel instantané construit hors du chemin de service et échangé de façon
atomique : une personne ou un membre de groupe retiré disparaît en une période,
sans redémarrage. (v0.13.4 les lisait une fois et exigeait un redémarrage pour un
changement de groupe.) Un rafraîchissement qui échoue garde les dernières bonnes
données et est journalisé une fois par série d'échecs, en nommant la source. Là
où la révocation compte, définissez `max_age` (par exemple `"10m"`) : une fois les
données plus anciennes, les recherches, les liaisons des personnes et les
changements de mot de passe répondent `unavailable` (52) au lieu de données
périmées. Une source illisible au
démarrage, par exemple une requête de groupes qui ne s'exécute pas ou l'une de
plusieurs bases hors service, refuse le démarrage et `check`, en nommant la
source et le groupe. Une entrée trop grande pour un message LDAP (environ
3 Mio, qu'une seule valeur d'attribut de 10 Mo suffit à atteindre) n'est pas
publiée, et c'est dit au démarrage et par `check`, comme pour une entrée qui
échoue au schéma.

## Signaux {#signals}

| signal | ce qui se passe |
|---|---|
| `SIGTERM`, `SIGINT` | il affiche `stopping`, ferme les écouteurs **et chaque connexion établie**, arrête le royaume, ferme les sources, et sort avec 0 une fois que le serveur a réellement terminé |
| `SIGHUP` | il est intercepté et journalisé, et authnd **reste en marche**. Il relit aussitôt le certificat TLS (v0.15.0) ; la configuration et le keytab ne sont pas rechargés |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 1 person from the configuration file
hangup: authnd does not reload its configuration or keytab; restart it to apply those (the TLS certificate is read again)
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

C'est une seule exécution du binaire v0.15.0 : un `kill -HUP`, deux tentatives de changement de mot de passe (la première
refusée, la seconde acceptée), puis un `kill -TERM`.
Le processus était toujours là après le `SIGHUP`.

Un `SIGHUP` **tuait** autrefois authnd — le comportement par défaut de Go pour un signal que personne ne gère
— et systemd compte une mort par `SIGHUP` comme une sortie propre, si bien que
`Restart=on-failure` ne le relançait pas : un seul `kill -HUP` ou un seul `postrotate`
de logrotate mettait un annuaire hors service pour de bon. Il est désormais intercepté pour que
l'habitude soit sans danger, et la ligne dit quoi faire à la place.

Fermer les connexions établies, et pas seulement l'écouteur, est délibéré : un
serveur qui cesserait d'accepter en laissant ses connexions ouvertes répondre
paraîtrait arrêté sans l'être, et c'est le redémarrage qui ne prend pas.

## Ce qu'il écrit {#what-it-writes}

Tout va sur la sortie standard, qui sous systemd est le journal
(`journalctl -u authnd`) :

- au démarrage, où il écoute et qui il sert — `ldap on …`, `ldaps on …`
  ou `ldap+starttls on …`, puis `realm EXAMPLE.ORG on … (udp and tcp)` avec un
  bloc `kerberos` ;
- chaque liaison refusée sous un bloc `mfa`, chaque jeton refusé, chaque
  changement de mot de passe refusé ou effectué, **avec la raison** — que le
  client n'apprend jamais ; voir [le second facteur]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})
  et [les jetons]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}}) ;
- chaque requête que le KDC refuse, préfixée par `kerberos:`, avec le code d'erreur
  Kerberos ; voir [le royaume]({{< relref "/authnd/kerberos.md#kinit-against-it" >}}) ;
- le journal propre de la bibliothèque LDAP, au format texte de `slog`, au niveau info.

Un simple mauvais mot de passe sur une liaison simple, sans bloc `mfa`, reçoit la réponse
`invalidCredentials` et n'est pas journalisé par authnd lui-même.

## Limites et délais {#limits}

Depuis la v0.15.0, authnd borne ce qu'un client, une source lente ou un afflux
peuvent lui faire retenir. Quatre clés facultatives, au premier niveau de la
configuration :

| clé | défaut | signification |
|---|---|---|
| `max_connections` | `4096` (illimité auparavant) | le plus grand nombre de connexions ouvertes à la fois ; `0` pour illimité |
| `max_connections_per_ip` | aucun | le plus grand nombre depuis une même adresse ; il ne peut pas dépasser `max_connections` |
| `operation_timeout` | `30s` (aucun auparavant) | la durée maximale d'une opération LDAP ; `"0"` pour aucune, sinon au moins `100ms` |
| `startup_timeout` | `60s` | la durée maximale pour ouvrir et lire une première fois toutes les sources ; `"0"` pour aucune |

Une connexion au-delà d'un plafond reçoit `busy` (51) dans une notification de
déconnexion et est fermée, jamais mise en file (RFC 4511 4.4.1). Une opération
encore en cours à `operation_timeout` reçoit `timeLimitExceeded` (3), **même si
son gestionnaire est bloqué et ignore l'échéance** : le résultat tardif est
abandonné. Une source qui ne répond pas au démarrage fait refuser le démarrage
après `startup_timeout`, avec une erreur qui nomme l'étape et la source. Un
nombre négatif, ou une durée qui ne se lit pas, est refusé au démarrage et par
`check`. Mettez `max_connections = 0` et `operation_timeout = "0"` pour retrouver
le comportement de la v0.14.

`check` affiche les limites avec lesquelles il servira, pour que personne ne
fonctionne avec les défauts sans le savoir :

```
$ authnd check etc2/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org
limits: 200 connections, 20 per address; an operation may take 10s; startup may take no limit

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid

GROUP  MEMBERS  PUBLISHED AS
staff  alice    groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Cette configuration dit `max_connections = 200`, `max_connections_per_ip = 20`,
`operation_timeout = "10s"` et `startup_timeout = "0"`. Sans ces quatre clés, la
ligne est `limits: 4096 connections, no limit per address; an operation may take
30s; startup may take 1m0s`, que le même binaire a aussi affichée.

### Une panne n'est pas un mauvais mot de passe {#outage}

Quand les personnes sont vérifiées auprès d'un autre annuaire (une source
`ldap`) et que cet annuaire ne peut pas être interrogé, parce que la connexion
est refusée ou réinitialisée, qu'il répond `busy`, `unavailable` ou `other`, ou
qu'il ne répond pas dans `operation_timeout`, authnd répond LDAP `unavailable`
(52), **jamais** `invalidCredentials` (49). C'est vrai pour une liaison simple,
pour l'ancien mot de passe d'un changement de mot de passe et pour le facteur
mot de passe d'une liaison `mfa`. Avant la v0.15.0, cela était rapporté comme un
mauvais mot de passe : un formulaire de connexion disait à la personne que son
mot de passe était faux alors que l'annuaire était en panne. Un mauvais mot de
passe donne toujours 49. La cause est dans le journal, pas dans ce que le client
apprend, et une panne n'est pas comptée comme un essai raté.

## Quand il ne démarre pas {#when-it-does-not-start}

Un refus, c'est une ligne sur la sortie d'erreur standard, préfixée par `authnd:`, et le code
de sortie 1 ; sous l'unité, `Restart=on-failure` réessaie alors toutes les cinq
secondes et la ligne figure chaque fois dans le journal. Tout ce que `check` refuse
est refusé ici aussi, et la seule chose que seul le serveur découvre est une adresse
sur laquelle il ne peut pas écouter — voir
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
L'écouteur LDAP, le certificat et le royaume sont tous ouverts avant que la
première ligne soit affichée : un serveur qui ne peut pas démarrer n'affiche donc que le
refus. Ici, une seconde instance se heurte au port Kerberos de la première :

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

La ligne `ldap on …`, et `realm … on …` après elle, signifient que les deux moitiés
écoutent.

## Savoir qu'il tourne {#telling-that-it-is-up}

Il n'y a ni point de terminaison de santé ni métriques. Ce qu'il y a :

- **le processus et son code de sortie** — sous systemd, `systemctl is-active
  authnd`. Si l'écouteur LDAP ou le royaume s'arrête de lui-même, le
  processus entier se termine avec cette erreur : un processus vivant est donc un processus dont les deux
  moitiés répondent ;
- **le DSE racine**, qui répond à un client anonyme et dit à quelle version
  on parle :

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

Sur un [écouteur StartTLS]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}}),
cette requête demande `-ZZ`. Une sonde qui prouve davantage — qu'une source répond
encore — est une liaison en tant que personne ou en tant que reader gardé à cet effet ; avec un
bloc `users "ldap"`, cette liaison atteint l'annuaire derrière celui-ci.

## Ce qui vit où, et ce qu'un redémarrage perd {#what-lives-where-and-what-a-restart-loses}

| | |
|---|---|
| configuration, mots de passe, DSN, certificat, keytab | les fichiers que nomme la configuration ; rien n'est copié |
| une base de données SQLite | là où le dit son DSN ; `/var/lib/authnd` sous l'unité |
| compteurs et verrouillages du second facteur | en mémoire seulement : **un redémarrage les oublie**, y compris une personne verrouillée après cent codes faux |
| codes à usage unique déjà utilisés | en mémoire seulement |
