---
title: "L'exploiter : signaux, redémarrages et ce qu'il dit"
linkTitle: "Exploitation"
weight: 80
description: "Ce qu'authnd lit une seule fois, pourquoi SIGHUP ne le recharge pas, comment il s'arrête, ce qu'il écrit sur sa sortie, et comment savoir qu'il tourne."
tags: [authnd, operations, signals, systemd]
---

## Il lit tout une seule fois {#it-reads-everything-once}

Les fichiers de configuration, chaque source derrière eux, le certificat TLS et
le keytab sont lus **au démarrage**. Il n'y a pas de rechargement, et l'unité fournie
n'a pas d'`ExecReload=`. Après avoir modifié l'un d'eux :

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

La seule chose appliquée pendant qu'il tourne est un
[mot de passe qu'une personne change via authnd]({{< relref "/authnd/passwords.md" >}}),
qui relit les blocs `user` et rien d'autre.

## Signaux {#signals}

| signal | ce qui se passe |
|---|---|
| `SIGTERM`, `SIGINT` | il affiche `stopping`, ferme les écouteurs **et chaque connexion établie**, arrête le royaume, ferme les sources, et sort avec 0 une fois que le serveur a réellement terminé |
| `SIGHUP` | il est intercepté et journalisé, et authnd **reste en marche** sans rien recharger |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
hangup: authnd does not reload; restart it to apply a changed configuration, certificate or keytab
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

C'est une seule exécution : un `kill -HUP`, deux changements de mot de passe, puis un `kill -TERM`.
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
vendorName: go-authn/authnd
vendorVersion: v0.10.0
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
