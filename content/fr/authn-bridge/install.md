---
title: "Installer authn-bridge"
linkTitle: "Installation"
weight: 10
description: "Un utilisateur statique, trois répertoires et une unité systemd durcie : authn-bridge, d'un binaire de version à un service en marche."
tags: [authn-bridge, installation, systemd]
---

Le dépôt fournit l'unité et l'utilisateur sous lequel elle s'exécute :
`packaging/systemd/authn-bridge.service` et
`packaging/sysusers.d/authn-bridge.conf`. Tout ce qui suit s'exécute en root sauf
mention contraire.

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | le binaire |
| `/etc/authn-bridge/*.hcl` | la configuration, lue dans l'ordre des noms ; `root:authn-bridge`, `0750`, fichiers `0640` |
| `/var/lib/authn-bridge/` | les clés, le sel de sujet, l'état SQLite, les certificats émis, la liste des désactivations ; `authn-bridge`, `0700` |
| `/run/authn-bridge/` | le socket d'administration, quand la configuration en demande un |

## Le binaire {#the-binary}

Une version contient `authn-bridge-<os>-<arch>` pour Linux, macOS et Windows sur
amd64 et arm64, un manifeste `SHA256SUMS` et une attestation de provenance de compilation par
binaire ; [vérifier un téléchargement]({{< relref "/security/verifying-releases.md" >}})
explique comment contrôler les deux. Ou bien compilez-le, ce qui inscrit la version dans le binaire :

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.0
$ authn-bridge --version
authn-bridge version v0.23.0
```

Le chemin compte : depuis v0.20.0 le programme se trouve dans `internal/app` et la
commande dans `cmd/authn-bridge`, si bien que `go install github.com/go-authn/bridge@...`
ne compile rien.

## L'utilisateur, et pourquoi il n'est pas dynamique {#the-user-and-why-it-is-not-a-dynamic-one}

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

L'unité indique `User=authn-bridge`, pas `DynamicUser=`. La clé de signature, le
sel de sujet, la clé SAML et les autorités de certification sont créés **avant**
le premier démarrage, vivent des années, et doivent garder un seul propriétaire à travers les réinstallations et
les restaurations depuis une sauvegarde. Un utilisateur dynamique reçoit son UID au démarrage du service.

## Les clés {#the-keys}

Exécutez `keygen` sous l'utilisateur du service, afin qu'il possède ce qu'il écrit. Il refuse
d'écraser un fichier déjà présent :

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

Sur un serveur, les chemins sont sous `/var/lib/authn-bridge`, et la commande est
`runuser -u authn-bridge -- authn-bridge keygen ...`.

| option | écrit | pour |
|---|---|---|
| `--key` | une clé RSA 3072 | les jetons d'identité (RS256), publiés à `/jwks` |
| `--salt` | 32 octets aléatoires | chaque `sub`, qui est un HMAC sous ce sel |
| `--access-token-key` | une clé P-256 | des jetons d'accès signés en ES256 à la place, bien plus courts |
| `--ssh-ca` | une clé Ed25519 au format OpenSSH | les [certificats SSH]({{< relref "/authn-bridge/certificates.md" >}}) et la signature de la KRL |
| `--x509-ca DIR` | `DIR/ca.key` (P-256) et `DIR/ca.crt`, valide dix ans, longueur de chemin 0 | les certificats clients NFS et la CRL |

{{< callout type="warning" >}}
**Sauvegardez le sel, et ne le changez jamais**

Un nouveau sel donne à chaque personne un nouveau `sub`, et chaque partie utilisatrice (relying party)
voit alors une nouvelle personne. Il en va de même si on le supprime à la désinstallation.
{{< /callout >}}

La clé et le certificat SAML sont créés avec `openssl` : ce sont eux que la
fédération enregistre et vers lesquels chaque IdP chiffre. La clé doit être RSA (les IdP
chiffrent vers elle en RSA-OAEP). Ce n'est pas le certificat TLS, et il ne change pas
avec lui.

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

Le certificat de signature des métadonnées de la fédération vient de la fédération, tout comme
son empreinte SHA-256 : prenez l'empreinte sur la page web de la fédération,
jamais dans le même téléchargement que le certificat. Voir
[le côté fédération]({{< relref "/authn-bridge/federation.md" >}}).

## L'unité {#the-unit}

Ce qu'elle accorde, en bref :

- `Type=exec`, `Restart=on-failure`, `RestartSec=5s`, `TimeoutStopSec=20s`.
  Le fournisseur arrête son écouteur dans les dix secondes qui suivent `SIGTERM`.
- `StateDirectory=`, `RuntimeDirectory=` (tous deux `0700`) et
  `ConfigurationDirectory=` (`0750`), `UMask=0077`. Avec
  `ProtectSystem=strict`, tout le reste est en lecture seule.
- Aucune capability (`CapabilityBoundingSet=` et `AmbientCapabilities=` vides),
  `NoNewPrivileges=`, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
  `PrivateIPC=`, `ProtectHome=`, le noyau, l'horloge, le nom d'hôte et les groupes
  de contrôle protégés.
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6` : TCP pour l'écouteur,
  les métadonnées, une AC ACME et une base de données ; un socket pour l'API d'administration.
- `SystemCallFilter=@system-service`, moins `@privileged @resources`, refusés
  avec `EPERM` plutôt que par un kill.

Elle attend `network-online.target`, parce que les métadonnées sont récupérées avant que
le fournisseur n'écoute.

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

La première ligne du journal est celle montrée dans
[la vue d'ensemble]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}}).

### Les changements exigent un redémarrage {#changes-need-a-restart}

La configuration est lue une seule fois. L'unité n'a pas d'`ExecReload=`, donc `systemctl
reload` est refusé plutôt que de faire semblant. Un `SIGHUP` (venu de logrotate, ou de l'habitude)
est intercepté, journalisé et ignoré. Laissé au comportement par défaut de Go, il tuerait le processus,
et systemd compterait cela comme une sortie propre que `Restart=on-failure` ne
relance pas :

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

Les fichiers de certificat TLS font exception : ils sont relus quand ils changent.

### Port 443 {#port-443}

L'écouteur par défaut est `127.0.0.1:8080`, derrière un proxy inverse TLS, et
n'a besoin d'aucune capability. Pour servir lui-même TLS sur le port 443 (`cert_file` ou `acme`),
le fournisseur a besoin de `CAP_NET_BIND_SERVICE` et doit quitter l'espace de noms
utilisateur privé, puisqu'une capability détenue à l'intérieur ne s'applique pas au
réseau de l'hôte :

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## Mettre à jour, et revenir en arrière {#upgrading-and-going-back}

Sauvegardez d'abord `/var/lib/authn-bridge` : il contient les clés et le sel, qui
ne peuvent pas être recréés. Gardez le binaire qui fonctionne, installez le nouveau, redémarrez :

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

Revenir en arrière se fait de la même façon avec `authn-bridge.previous`. Une version plus récente peut fournir une
unité plus récente : comparez-la avec la vôtre, installez-la et faites `systemctl daemon-reload`
avant le redémarrage.

### En venant de `bridge` {#coming-from-bridge}

La configuration est inchangée ; seuls la commande et les fichiers de version ont été
renommés. Modifiez chaque unité, script, tâche cron et `bearer_token_command` qui
exécute `bridge`. La ligne de journal et le préfixe des erreurs disent désormais `authn-bridge`, donc une
alerte qui correspondait à `bridge v0.` doit correspondre à `authn-bridge v0.`. Les noms de métriques
(`bridge_*`), la table `bridge_state` et le cache côté utilisateur
(`go-authn-bridge` dans le répertoire de configuration de l'utilisateur, `~/.config` sous
Linux) sont inchangés, donc `authn-bridge token` réutilise les connexions que `bridge`
avait mises en cache.
