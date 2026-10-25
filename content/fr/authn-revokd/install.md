---
title: "Installer authn-revokd"
linkTitle: "Installation"
weight: 10
description: "authn-revokd comme service systemd durci, ou comme exécution ponctuelle sur un minuteur, et comment brancher sshd et un serveur TLS sur ce qu'il écrit."
tags: [authn-revokd, installation, systemd]
---

Le dépôt fournit trois unités et un compte dans `packaging/` :
`authn-revokd.service` (le démon), `authn-revokd-once.service` avec
`authn-revokd-once.timer` (l'alternative), et
`sysusers.d/authn-revokd.conf`.

| chemin | quoi | propriétaire, mode |
|---|---|---|
| `/usr/local/bin/authn-revokd` | le binaire | root, `0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | le compte système `authn-revokd` | root, `0644` |
| `/etc/systemd/system/authn-revokd.service` | le démon | root, `0644` |
| `/etc/authn-revokd/revokd.hcl` | la configuration, le `-config` par défaut | root, `0644` |
| `/etc/authn-revokd/ca/` | les clés et certificats d'AC par lesquels les listes doivent être signées | root, `0755` ; les fichiers qu'il contient `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`, le seul emplacement accessible en écriture | authn-revokd, `0755` |
| `/var/lib/authn-revokd/state/` | `state_dir` : les copies vérifiées | authn-revokd, `0700` |
| `/var/lib/authn-revokd/sshd.krl` | une sortie : ce que lit `sshd` | authn-revokd, `0644` |

**Écrivez les sorties dans `/var/lib/authn-revokd`, et faites pointer les serveurs là.**
Une sortie est écrite à côté de son nom final puis renommée par-dessus, son
*répertoire* doit donc être accessible en écriture. Rendre `/etc/ssh` accessible en écriture permettrait au
compte `authn-revokd` de remplacer `sshd_config`. Les sorties sont en `0644`, par un chmod
explicite malgré `UMask=0077`, afin que `sshd` et un serveur TLS tournant sous son
propre utilisateur puissent les lire ; l'état reste en `0700`.

## Le binaire, le compte, l'unité {#the-binary-the-account-the-unit}

Une version contient `authn-revokd-<os>-<arch>` pour Linux, macOS et Windows sur
amd64 et arm64, avec `SHA256SUMS` et la provenance de compilation
([vérifier un téléchargement]({{< relref "/security/verifying-releases.md" >}})). Ou
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.5`.

Le compte et l'unité viennent du répertoire `packaging/` de l'étiquette de la
version, la même version que le binaire : copiez ce répertoire à côté du
binaire, depuis une extraction de l'étiquette ou, pour v0.6.5, depuis
<https://github.com/go-authn/revocation/tree/v0.6.5/packaging>.

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

Le compte est statique, pas `DynamicUser=`. authn-revokd refuse un répertoire d'état
appartenant à quiconque d'autre que son propre uid ou root, et l'état doit continuer
d'ordonner la liste suivante à travers les redémarrages et les mises à jour. Avec un utilisateur dynamique, les
fichiers se trouveraient sous `/var/lib/private`, `0700` root, et un serveur TLS tournant
sous son propre utilisateur ne pourrait pas lire la CRL.

## Le démon {#the-daemon}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

et autour : `User=authn-revokd`, aucune capability, `NoNewPrivileges=`,
`ProtectSystem=strict` avec `StateDirectory=authn-revokd` (`0755`) comme seul
emplacement accessible en écriture, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
`PrivateIPC=`, `AF_INET AF_INET6 AF_UNIX` seulement, les appels système `@system-service`
moins `@privileged @resources`.

**`Restart=always`, parce que sshd ignore l'expiration dans la KRL.** C'est *ce processus*
qui fait refuser le fichier en cas de doute quand une liste expire. Tant qu'il est arrêté, sshd
continue de lire le dernier fichier qu'il a écrit, et une révocation émise entre-temps n'arrive
jamais. Surveillez l'unité, ou `/healthz` quand le miroir est actif.

**`systemctl reload` synchronise immédiatement.** Il envoie `SIGHUP`, et l'agent récupère toutes
les sources d'un coup au lieu d'attendre le prochain `refresh` :

```
hangup: syncing now
```

Il ne relit pas la configuration, qui est lue une seule fois, au démarrage : après
avoir modifié `revokd.hcl`, `systemctl restart authn-revokd`. (Avant la v0.6.0, un
`SIGHUP` non intercepté tuait le processus, et systemd compte cela comme une sortie propre.)

### L'activer AVANT de brancher sshd {#enable-it-before-wiring-sshd}

{{< callout type="warning" >}}
**sshd refuse tous les certificats quand `RevokedKeys` nomme un fichier qui n'existe pas**

Démarrez donc authn-revokd d'abord, et attendez que la sortie soit là :
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl` affiche son commentaire,
`authn-revokd sshd` tant que toutes les sources sont en vigueur.
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

Puis, dans `/etc/ssh/sshd_config` :

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

et `sshd -t && systemctl reload ssh`. sshd lit `RevokedKeys` à chaque
authentification, il n'a donc pas besoin d'être rechargé quand authn-revokd réécrit le fichier : le
renommage atomique suffit.

### La CRL d'un serveur TLS {#a-tls-servers-crl}

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

Un serveur TLS lit sa CRL quand il charge sa configuration, il doit donc être
rechargé quand le fichier change. Une commande `on_change` s'exécute sous le
compte `authn-revokd`, qui ne peut pas faire `systemctl reload nginx` : laissez plutôt systemd surveiller
le fichier, en tant que root, avec une unité path (`PathChanged=` sur la sortie) qui
démarre un `oneshot` exécutant `systemctl reload nginx`.

## Ou : `-once`, sur un minuteur {#or--once-on-a-timer}

`authn-revokd -once` synchronise une fois et sort, avec `1` quand une liste n'est pas en vigueur ou
n'a pas pu être récupérée ([ce que signale `-once`]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
Les sorties sont écrites dans tous les cas, et refusent en cas de doute pour sshd dès qu'une liste
expire.

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

L'exécution ponctuelle a le compte et le durcissement du démon. `TimeoutStartSec=5min`
empêche une synchronisation bloquée sur une source de survivre au déclenchement suivant, et
`RandomizedDelaySec=10s` empêche un parc démarré en même temps d'interroger son
émetteur en cadence.

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**N'activez jamais les deux** : les unités sont en conflit, donc démarrer l'une arrête l'autre.
Le démon reste le meilleur choix. Il fait refuser une liste expirée à son prochain
`refresh`, là où le minuteur attend son prochain déclenchement, et seul le démon sert de
miroir : `listen` est ignoré avec `-once`. Un minuteur qui cesse de se déclencher est un démon
qui s'est arrêté, alors surveillez `systemctl status authn-revokd-once`.

## Mettre à jour, et revenir en arrière {#upgrading-and-going-back}

Installez le nouveau binaire à côté de l'ancien, échangez-les, redémarrez. L'état est conservé :
les copies vérifiées continuent d'ordonner les listes suivantes, si bien que ni une mise à jour ni un
retour à un binaire plus ancien ne laisse entrer une liste plus ancienne.

## Désinstaller {#uninstalling}

Retirez `RevokedKeys` et `ssl_crl` de la configuration des serveurs **d'abord**,
et rechargez-les : sshd refuse tous les certificats dès que le fichier a disparu.
