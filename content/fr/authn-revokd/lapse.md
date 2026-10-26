---
title: "Quand une liste expire"
linkTitle: "Quand une liste expire"
weight: 40
description: "Ce qu'authn-revokd écrit pour sshd quand il ne détient aucune liste en vigueur d'une AC : une KRL qui révoque la clé de l'AC elle-même, de sorte que chaque certificat de cette AC est refusé."
tags: [authn-revokd, révocation, refus en cas de doute, sshd]
---

Une vérification de révocation qui laisse tout passer quand la liste ne peut pas être obtenue est
celle que déjoue un attaquant capable de bloquer la liste. Donc quand authn-revokd ne détient
aucune liste en vigueur d'une source, ce que protège la liste de cette source est
**refusé**, jusqu'à ce qu'une liste en vigueur arrive de nouveau.

| sortie | tant qu'une source n'a aucune liste en vigueur |
|---|---|
| une KRL, pour `sshd` | authn-revokd écrit une KRL qui **révoque la clé de l'AC de la source** |
| une CRL, pour un serveur TLS | la CRL expirée est laissée en place ; OpenSSL refuse de lui-même une CRL expirée |

## Pour sshd : révoquer l'AC elle-même {#for-sshd-revoking-the-ca-itself}

`sshd` n'a aucune notion de l'expiration d'une liste : il continuerait indéfiniment à lire le dernier fichier
écrit. Mais il vérifie la **clé de l'AC** de chaque certificat par rapport à
`RevokedKeys`. Donc, à la place de la liste dont il ne peut pas se porter garant, authn-revokd
met la propre clé de l'AC dans la sortie, et chaque certificat que cette AC a signé est
refusé, et rien d'autre.

Ici, l'émetteur est arrêté, et la source KRL a `max_age = "30s"`, si bien que la
copie détenue expire en moins d'une minute au lieu d'une heure. La source CRL n'a pas de
`max_age`, et sa copie est toujours en vigueur :

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-26T12:27:10Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4 # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh` est `not current`, et sa sortie refuse en cas de doute ; `bridge-x509`
est seulement `not fetched`, et sa CRL est laissée telle quelle
([ce que signale `-once`]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
`SHA256:AnDb/...` est l'AC SSH du bridge. Un certificat qu'elle a signé est désormais
révoqué pour tout ce qui lit le fichier. Les commandes ci-dessus ont tourné dans le
répertoire `revokd`, où se trouve `out/` ; celle-ci tourne à côté, dans le répertoire
qui contient les certificats de test, comme sur
[la page de sshcert-authorize]({{< relref "/sshcert/authorize.md#krl" >}}) : le même
fichier y est donc `../revokd/out/sshd.krl` :

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

Le commentaire dit `FAIL CLOSED` et nomme la source, si bien qu'une personne qui lit
`ssh-keygen -Q -l` voit pourquoi. La date du fichier est 1970 quand toutes les sources ont
expiré. La sortie est écrite **dès qu'une synchronisation s'en aperçoit**, c'est-à-dire, pour le démon,
à son prochain `refresh`, et pour le minuteur, à son prochain déclenchement. Quand une liste en vigueur
arrive de nouveau, la synchronisation suivante l'écrit à la place de la clé de l'AC, et les
certificats de l'AC sont de nouveau acceptés.

La même chose se produit **avant la première liste** : une source jamais récupérée n'a rien
d'en vigueur, et son AC est révoquée dès la première écriture. Une nouvelle installation refuse
les certificats de l'AC jusqu'à ce que sa première liste se vérifie, plutôt que de les accepter
sans contrôle.

### Chaque AC pour elle-même {#each-ca-for-itself}

Dans une sortie qui fusionne plusieurs sources, seule l'AC de la source expirée est
révoquée. Les autres gardent leurs listes. Une liste qui ne peut pas être fusionnée (au-delà des
plages de numéros de série que conserve go-authn/krl) refuse en cas de doute pour sa propre AC seulement, et
`/healthz` la nomme. Ce n'est que si les listes fusionnent chacune seule mais pas ensemble que toutes les AC
de la sortie sont révoquées, et le commentaire le dit
(`FAIL CLOSED, the output could not be rendered`). Garder l'ancien fichier à la place
laisserait passer inaperçue une expiration ultérieure.

## Pour un serveur TLS : la CRL elle-même {#for-a-tls-server-the-crl-itself}

Une CRL dit déjà quand elle cesse d'être en vigueur, et OpenSSL en refuse une qui a dépassé
son `nextUpdate` (« CRL has expired »). authn-revokd laisse donc la dernière CRL vérifiée
en place, et le serveur TLS refuse de lui-même en cas de doute. C'est aussi pourquoi
`max_age` est refusé sur une source qui alimente une sortie CRL : un serveur qui a chargé
la CRL la garde jusqu'à son `nextUpdate`, quoi qu'authn-revokd écrive.

## Les lecteurs qui vérifient eux-mêmes l'expiration {#readers-that-check-the-expiry-themselves}

La KRL fusionnée porte une expiration, la première de celles de ses entrées en vigueur. Un lecteur
qui la vérifie, comme `ssh_krl_file` de go-fileshare ou
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}}),
voit l'arrêt d'authn-revokd comme il verrait l'arrêt de l'émetteur.

{{< callout type="warning" >}}
**Cela ne fonctionne que tant qu'authn-revokd tourne**

C'est authn-revokd qui fait refuser le fichier en cas de doute. Tant qu'il est arrêté, sshd continue de
lire le dernier fichier écrit, en vigueur ou non. D'où `Restart=always` sur
le démon, et la surveillance de l'unité, ou du minuteur, ou de `/healthz`.
{{< /callout >}}
