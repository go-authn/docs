---
title: "Installer authnd"
linkTitle: "Installation"
weight: 10
description: "Le binaire de la version et comment le vérifier, le compte authnd, l'unité systemd et ce qu'elle accorde, et la mise à niveau, le retour arrière et la désinstallation."
tags: [authnd, install, systemd]
---

Le dépôt contient les deux fichiers dont un hôte systemd a besoin :
`packaging/sysusers.d/authnd.conf` (le compte) et
`packaging/systemd/authnd.service` (l'unité). Cette page explique les deux et
les étapes qui les entourent. Les services versionnés de go-pkgx sont censés le faire pour
vous plus tard ; ils n'existent pas encore.

## Le binaire de la version {#the-release-binary}

Chaque étiquette publie `authnd-<os>-<arch>` pour linux, darwin et windows sur amd64
et arm64 (`.exe` sous windows), compilé avec `CGO_ENABLED=0`, un manifeste `SHA256SUMS`,
et une attestation de provenance de compilation pour chaque binaire.

```sh
version=v0.10.1
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

Arrêtez-vous si l'une des deux vérifications échoue. Le workflow de publication refuse de publier un binaire
qui n'annonce pas exactement l'étiquette sous laquelle il est publié : la version est donc
quelque chose à comparer :

```
$ authnd --version
authnd version v0.10.1
```

### Ne compiler que ce que vous voulez {#building-only-what-you-want}

Le serveur est toujours là ; deux étiquettes de compilation retirent des provenances
possibles des personnes. `-tags nosql` retire les trois pilotes de base de données (PostgreSQL via pgx,
MySQL/MariaDB, SQLite via modernc.org/sqlite) et le bloc `users "sql"` ;
`-tags noldap` retire le client LDAP et le bloc `users "ldap"`. Une
configuration qui nomme un bloc sans lequel le binaire a été compilé se le voit dire —
*this binary was built without SQL support (-tags nosql)* — plutôt que de s'entendre dire que
le bloc n'existe pas. Les binaires des versions sont compilés sans étiquettes.

## Le compte {#the-account}

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

Un compte statique issu de sysusers.d, **pas** `DynamicUser=`. Les fichiers qu'authnd
lit — fichiers de mots de passe, un DSN, un keytab, une clé TLS — sont des secrets confiés au
groupe `authnd` à l'avance, et un [changement de mot de passe]({{< relref "/authnd/passwords.md" >}})
y réécrit. Un uid dynamique n'existe pas avant que le service démarre,
et un fichier qu'il a écrit appartiendrait à un numéro qui désignera plus tard quelqu'un d'autre.

Les deux fichiers viennent du répertoire `packaging/` de l'étiquette de la version,
la même version que le binaire : copiez ce répertoire à côté du binaire, depuis
une extraction de l'étiquette ou, pour v0.10.1, depuis
<https://github.com/go-authn/authnd/tree/v0.10.1/packaging>.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## Ce que l'unité accorde, et pourquoi {#what-the-unit-grants-and-why}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

Le reste de l'unité est le durcissement habituel (`ProtectHome`, `PrivateTmp`,
`PrivateDevices`, `ProtectProc=invisible`, les protections du noyau et des cgroups,
`MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`,
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`). Trois choses qu'elle
**omet** le sont délibérément :

| | |
|---|---|
| `ExecReload=` | authnd n'a pas de rechargement. Il lit sa configuration, son certificat et son keytab une seule fois ; voir [l'exploiter]({{< relref "/authnd/operations.md" >}}) |
| `PrivateUsers=` | dans un espace de noms utilisateur, `CAP_NET_BIND_SERVICE` ne s'applique plus au réseau de l'hôte, et la liaison au port 389 est refusée |
| `ProcSubset=pid` | il masque `/proc/sys`, où Go lit `net/core/somaxconn`, et le backlog de chaque écouteur retombe à la valeur de repli de Go, 128 |

`IPAddressAllow=`/`IPAddressDeny=` ne sont pas définis non plus : quels réseaux peuvent interroger
un annuaire, c'est au site de le dire, dans un drop-in :

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

L'unique capacité sert aux ports privilégiés : LDAP 389, LDAPS 636, et
Kerberos 88 en UDP et TCP. Un PostgreSQL ou un MariaDB sur la même machine est
joint par sa socket, ce qu'un système de fichiers en lecture seule permet. Le répertoire
d'état, `/var/lib/authnd`, est là pour une base de données SQLite ; authnd ne garde aucun
état propre — les compteurs de verrouillage du second facteur vivent en mémoire et sont
remis à zéro à chaque redémarrage.

## Le répertoire de configuration {#the-configuration-directory}

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

Chaque fichier qu'il contient est `root:authnd`, en mode `0640`. Les secrets vont dans des fichiers nommés par
des clés `*_file` plutôt qu'en ligne : un fichier a des permissions, une configuration
que quelqu'un colle n'en a pas. Avec `ProtectSystem=strict`, le service ne peut pas écrire
sous `/etc`, ce qui est juste pour la configuration et faux pour les
mots de passe que les personnes changent elles-mêmes — donnez-leur un répertoire à part :

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

Pourquoi ce répertoire et pas le fichier est expliqué dans
[changer un mot de passe]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}}).

| clé | défaut | |
|---|---|---|
| `base_dn` | — (obligatoire) | la racine de l'arbre, par exemple `dc=example,dc=org` ; une valeur sans `=` est refusée |
| `listen` | `127.0.0.1:3893` | une seule adresse. Boucle locale par défaut : un annuaire qui apparaît sur toutes les interfaces dès qu'il démarre est une décision que quelqu'un devrait prendre exprès. Un site qui a besoin de LDAP et de LDAPS lance deux instances |
| `reader "<dn>"` | aucun | un compte de service qui peut chercher ; voir [qui peut lire]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) |
| `cert_file`, `key_file`, `starttls`, `publish_nt_hash` | désactivé | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`, `group`, `users` | — | [les personnes]({{< relref "/authnd/people.md" >}}) ; au moins un bloc `user` ou `users` |
| `kerberos` | aucun | [un royaume]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | aucun | [un second facteur]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | aucun | [un jeton à la liaison]({{< relref "/authnd/tokens.md" >}}) |

Un chemin relatif dans la configuration est résolu par rapport au répertoire dans lequel
le processus s'exécute, pas à celui du fichier de configuration ; l'unité s'exécute depuis `/`, donc
écrivez des chemins absolus.

Avant chaque démarrage :

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check` est décrit sur [sa propre page]({{< relref "/authnd/check.md" >}}) ;
le lancer sous `authnd` prouve aussi que le compte peut lire chaque fichier.

## Mettre à niveau, revenir en arrière, désinstaller {#upgrade-roll-back-remove}

Vérifiez la configuration avec le **nouveau** binaire avant qu'il ne remplace l'ancien,
et gardez l'ancien. Le nouveau binaire est d'abord installé à côté de l'ancien :
cela le rend exécutable, et le place là où le compte `authnd` peut le lancer.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

Comparez `packaging/` à la nouvelle étiquette avec ce qui est installé. Revenir en arrière, c'est
la même installation depuis `authnd.previous`, et un redémarrage.

Pour le désinstaller :

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`, `/var/lib/authnd` et le compte `authnd` sont laissés en place :
les deux premiers contiennent les identifiants des personnes, et un uid réutilisé peut se voir
attribuer les fichiers de quelqu'un d'autre. Supprimez-les délibérément.
