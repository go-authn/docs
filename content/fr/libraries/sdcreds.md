---
title: "sdcreds — les credentials systemd, sans systemd"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds lit et écrit le format de credentials systemd (systemd-creds encrypt et decrypt) depuis Go, avec une ligne de commande et un assistant s6 qui donne à un service supervisé son $CREDENTIALS_DIRECTORY."
tags: [libraries, sdcreds, secrets, s6]
---

**Et si un service a besoin des credentials qu'une unité systemd reçoit par
`LoadCredentialEncrypted=`, sans systemd ?** `sdcreds` lit et écrit le format de
[credential systemd](https://systemd.io/CREDENTIALS/) (`systemd-creds encrypt` /
`decrypt`) depuis Go, avec une ligne de commande et un assistant qui donne à un
service supervisé par s6 le même `$CREDENTIALS_DIRECTORY`.

Clés prises en charge : **null**, **host** (`/var/lib/systemd/credential.secret`)
et **host-scoped** (`--uid` / `--user`). Les credentials TPM2 et à clé publique
sont reconnus et refusés avec `*UnsupportedModeError` ; rien n'est deviné.

## Installation {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

La version décrite par ces pages est la v0.3.0.

## Ligne de commande {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

La même chose depuis Go :

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run` déchiffre chaque fichier de `--source` **avant** de monter quoi que ce
soit, monte un `tmpfs` propre au service (`nodev,noexec,nosuid,nosymfollow,noswap`,
mode 0700, taille et nombre d'inodes bornés ; `ramfs` si le noyau n'a pas ces
options), écrit le texte en clair en 0400 au nom de l'utilisateur du service, le
remonte en lecture seule, définit `CREDENTIALS_DIRECTORY`, puis lance le service
dans un processus fils qui abandonne ses privilèges (`no_new_privs`, un ensemble
de capacités vide) et l'attend.

- `s6-run` reste le processus que s6 supervise : il transmet `TERM`, `INT`,
  `HUP`, `QUIT`, `USR1`, `USR2`, `ALRM` et `CONT` au service, se termine avec son
  statut (128 plus le numéro du signal si un signal l'a tué), transmet les
  descripteurs reçus, et le service est tué si `s6-run` meurt.
- Les credentials sont retirés à la fin du service, et avant que `s6-run` ne
  échoue si le programme ne peut pas être exécuté.
- Le montage vit par défaut dans un espace de noms privé (`--unshare=false`
  le désactive), il disparaît donc avec le service.
- Un credential scellé avec la clé null est refusé sauf si `--allow-null` est
  donné, et un credential sans nom est toujours refusé.
- `sdcreds s6-finish --service=web` démonte de façon paresseuse et supprime le
  répertoire ; il est idempotent. Avec `--unshare=false`, un `SIGKILL` de `s6-run`
  laisse le montage en place jusqu'à l'exécution de `s6-finish` : placez-le dans
  le script finish du service.
- Au plus 1024 credentials et 16 MiB par service. Linux uniquement ; ailleurs,
  les commandes signalent `ErrUnsupported`.

Les fichiers de clé désignés par `--secret` et `--machine-id-file` doivent
appartenir à root et ne pas être modifiables par le groupe ni les autres, de même
que chaque répertoire au-dessus jusqu'à `/`. Le fichier de clé est ouvert une
seule fois, sans suivre un lien final, et la clé est effacée de la mémoire de
`s6-run` dès qu'il a fini avec les credentials. Seul le processus fils prend
l'identité du service ; `s6-run` et tous ses threads restent root.

### Conserver une capacité : `--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

L'option est répétable et séparée par des virgules (`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`
ou une option chacune) et n'a **aucune valeur par défaut** : sans elle, le service
s'exécute avec tous les ensembles de capacités vides.

C'est une **liste d'autorisation** de sept capacités, dont aucune n'équivaut à root
ni ne permet de lire ou d'écrire le tmpfs des credentials ni de signaler `s6-run` :
`CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`, `CAP_NET_RAW`, `CAP_NET_BROADCAST`,
`CAP_IPC_LOCK`, `CAP_WAKE_ALARM` et `CAP_BLOCK_SUSPEND`. Toute autre capacité, ou un
nom qui n'est pas une capacité, est une erreur qui nomme la liste, signalée avant
que la clé soit lue ou que quoi que ce soit soit monté.

Le service a, dans ses ensembles borné (bounding), permis, héritable, effectif et
ambiant, exactement les capacités conservées et rien d'autre. `no_new_privs` reste
actif, et les securebits valent 0x3 (`SECBIT_NOROOT` posé et verrouillé). Les
privilèges de `s6-run` lui-même ne changent pas.

`CAP_NET_ADMIN` agit sur l'espace de noms réseau où s'exécute le service, qui est
celui de l'hôte sauf si le service est lancé dans un espace de noms réseau propre
(`--unshare` ne lui donne qu'un espace de noms de montage privé) : il peut alors
modifier les interfaces, les routes et le pare-feu. Lancez un tel service dans son
propre espace de noms réseau quand cela compte.

## `sdcreds run` : OpenBSD et Linux {#run}

```sh
sdcreds run --service=web --user=svc --source=/etc/creds [--class=daemon] -- /usr/local/bin/web
```

`run` déchiffre les fichiers scellés de `--source`, les rend visibles au
programme comme des fichiers en lecture seule appartenant à `--user` sous
`$CREDENTIALS_DIRECTORY`, le lance sous cet utilisateur et les supprime quand il
se termine. Sous Linux, c'est `s6-run` avec les mêmes options. `--check` exécute
tous les refus et ne déchiffre rien (à utiliser dans un `rc_pre` de rc.d). Un
refus sort avec le statut 2 et intervient avant la lecture de la clé d'hôte.
Sous OpenBSD, les fichiers vivent dans un système de fichiers en mémoire (MFS)
monté pour le service et mis à zéro à la fin :

- **Il n'y a pas d'espace de noms de montage.** Tant que le programme tourne, les
  credentials sont visibles de tout processus qui peut atteindre le répertoire,
  et root peut toujours les lire.
- **La clé d'hôte** est `/etc/sdcreds/host.key`, appartenant à root, mode 0600 ;
  tout autre mode ou propriétaire est refusé. Créez-la avec
  `sdcreds setup --path /etc/sdcreds/host.key`, puis `chmod 600`. L'identifiant
  de machine est `sysctl hw.uuid`. `--secret` et `--machine-id-file` remplacent
  l'un et l'autre et passent par les mêmes contrôles de propriétaire et de mode.
- **`--user` n'est jamais root** : l'uid 0, le gid 0 et tout groupe supplémentaire
  0 sont refusés, dans `run` comme dans la bibliothèque (`s6.Run`, `delivery`) ;
  aucune option ne l'autorise. Le programme doit être un chemin absolu normalisé
  que l'utilisateur peut exécuter.
- **Tuer sdcreds tue le programme** et démonte, même avec `SIGKILL`. Un processus
  auxiliaire tient le verrou du service et surveille sdcreds ; quelle que soit la
  fin, il tue tout ce que l'utilisateur du service exécute (par uid réel, donc un
  programme qui a appelé `setsid` n'y échappe pas), puis démonte. La décision de
  tuer revient à root : l'auxiliaire arrête chaque processus trouvé, relit la
  table des processus jusqu'à ce qu'elle ne change plus, envoie `SIGKILL`, et
  recommence jusqu'à ce que l'utilisateur n'ait plus de processus. Un processus
  dont seul l'uid effectif est celui de l'utilisateur du service est compté comme
  occupé, donc le démarrage est refusé, mais il n'est pas tué. Si un processus
  survit au budget de 20 s, l'auxiliaire démonte quand même (les secrets
  disparaissent), signale l'échec et sort avec un statut non nul. Un utilisateur
  n'appartient qu'à une livraison à la fois (le `.uid-<N>.lock` de
  `/var/run/sdcreds`), et `run` refuse un utilisateur qui a déjà d'autres
  processus : donnez au service son propre utilisateur. Si sdcreds et l'auxiliaire
  meurent tous deux, `sdcreds sweep [--base DIR] [--service S]` (ou le prochain
  démarrage du service) supprime ce qui reste. Si la libération échoue après la
  fin du programme, sdcreds sort avec le statut 70 (ou celui du programme s'il
  était déjà un échec) et en donne la raison sur stderr.
- **Le swap doit être chiffré.** `run` refuse de démarrer quand
  `sysctl vm.swapencrypt.enable` vaut 0, est illisible ou n'existe pas. Aucune
  option ne le contourne. Dans la bibliothèque, `s6.Config` exige un `ReadSource`
  (la commande fournit le lecteur qui parcourt la confiance), sinon `s6.Run`
  refuse.
- **Les images de système de fichiers embarquées sont épinglées** : le sha256 de
  chaque `delivery/images/ffs-<N>MiB.gz` est vérifié avant que l'auxiliaire ne la
  décompresse.
- **`--class`** est cherchée d'abord dans `/etc/login.conf.d/<class>`, puis dans
  `/etc/login.conf` ; `login.conf.db` n'est pas consulté. Les limites de
  ressources de la classe s'appliquent au programme, en ne faisant jamais que
  réduire ce qu'il aurait, et une classe illisible ou inanalysable est un refus.
  La priorité et l'umask ne sont pas appliqués ; le programme a l'umask 077.
- **L'environnement du programme est une liste d'autorisation** : `PATH` (valeur
  fixe par défaut), `CREDENTIALS_DIRECTORY`, `LANG`, `TZ`, `TERM` et `LC_*`. Les
  descripteurs au-delà de 2 sont fermés avant l'exécution.
- **Mémoire.** Le texte en clair est dans la mémoire du processus sdcreds pendant
  un court moment. `mlockall` est inutilisable depuis un processus Go sous
  OpenBSD (mesuré sur 8.0) ; la protection est donc `vm.swapencrypt.enable`
  (vérifié au démarrage), les vidages mémoire désactivés et
  `kern.nosuidcoredump`. Un vidage pris par un administrateur peut encore
  contenir le texte en clair.
- `--keep-cap` n'existe que sous Linux.

`docs/openbsd/authn_bridge`, dans le dépôt, est un script rc.d qui lance
go-authn/bridge de cette façon. La livraison est aussi une bibliothèque, le
paquet `delivery`.

## Interopérabilité {#interop}

Les deux sens sont testés contre le vrai `systemd-creds` **262.2**, compilé à
partir du tag `v262.2` (aucun paquet de distribution).

- `testdata/systemd-v262.2` contient 44 credentials écrits par systemd-creds
  (null, host et host-scoped ; avec et sans nom ; not-after absent, passé et
  futur ; charges de 0 o, 1 o et 64 KiB ; cinq variantes altérées), et
  `manifest.json` consigne ce que systemd-creds a lui-même répondu pour chacune
  des 272 tentatives de déchiffrement (bon et mauvais nom, avant et après
  not-after, avec et sans `--uid`). La bibliothèque donne la même réponse, avec
  la même classe d'erreur, pour chacune.
- Avec un IV fixe, `Encrypt` reproduit exactement les octets de systemd.
- Dans le conteneur, `systemd-creds decrypt` ouvre ce que `Encrypt` a écrit, et
  la ligne de commande réussit le même aller-retour dans les deux sens.

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

Sans `SDCREDS_REQUIRE_SYSTEMD=1`, les tests qui ont besoin du binaire sont
ignorés ; la CI le définit, si bien qu'un binaire absent y est un échec. La
limite de 1 MiB n'est couverte que par les tests de la bibliothèque, pas par des
vecteurs d'interopérabilité.

## Écarts par rapport à systemd {#deviations}

- Un secret d'hôte dont l'identifiant de machine ne correspond pas est **refusé**
  (`ErrHostKeyMachine`) ; systemd le supprime.
- `--with-key=auto` signifie `host` : il n'y a pas de TPM2 ici.
- Un credential scellé avec la clé null n'a aucun secret : `sdcreds decrypt` le
  refuse sur toute machine sauf si `--allow-null` est donné (systemd consulte
  plutôt l'état du TPM2 et de SecureBoot ; cette politique de la bibliothèque,
  `SystemNullPolicy`, n'est pas utilisée par la CLI).
- `SDCREDS_MACHINE_ID_FILE` (`encrypt`, `decrypt`, `setup`) désigne un autre
  fichier d'identifiant de machine. `s6-run` l'ignore, ainsi que
  `SYSTEMD_CREDENTIAL_SECRET` : sa clé vient des fichiers par défaut, ou de
  `--secret` et `--machine-id-file`.
- Une taille d'IV variable est acceptée en lecture, comme dans systemd ; cette
  bibliothèque écrit toujours 12 octets.
- Le secret est ouvert sans suivre un lien symbolique final, et doit être un
  fichier ordinaire avec un seul lien et le mode `0400`, comme l'exige systemd.

## Sûreté {#safety}

Chaque longueur est vérifiée avant d'être utilisée, avant toute allocation, et
des deux côtés de sa borne ; les credentials sont limités à 1 MiB (comme
systemd) et le secret d'hôte à 16 MiB. Les analyseurs sont fuzzés en CI avec le
corpus versionné, et `govulncheck` tourne en CI. Le README n'a pas encore de
tableau de performances : la mesure est différée, un point ouvert et non un
résultat.

## Référence {#reference}

Le README de
[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) fait foi pour
cette page. Voir le `LICENSE` du module.
