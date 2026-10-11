---
title: "La configuration"
linkTitle: "Configuration"
weight: 20
description: "Le revokd.hcl d'authn-revokd : d'où viennent les listes, par quoi elles doivent être signées, dans quels fichiers elles sont écrites, et le miroir."
tags: [authn-revokd, configuration]
---

Un seul fichier, `/etc/authn-revokd/revokd.hcl` par défaut (`-config` en nomme un autre).
Il est lu une seule fois, au démarrage.

```hcl
state_dir = "/var/lib/authn-revokd/state"   # the verified copies: what orders the next list
refresh   = "1m"

source "univ-a-ssh" {
  url    = "https://login.univ-a.example/ssh/krl"    # and .../ssh/krl.sig beside it
  ssh_ca = "/etc/authn-revokd/ca/univ-a-ssh.pub"     # what the list must be signed by
}
source "univ-b-ssh" {
  url    = "http://mirror.cluster.local:8080/univ-b-ssh"   # a mirror: plain http is fine
  ssh_ca = "/etc/authn-revokd/ca/univ-b-ssh.pub"
}
source "univ-a-x509" {
  url     = "https://login.univ-a.example/x509/crl"
  x509_ca = "/etc/authn-revokd/ca/univ-a-x509.pem"
}

output "sshd" {                              # sshd_config: RevokedKeys /var/lib/authn-revokd/sshd.krl
  path    = "/var/lib/authn-revokd/sshd.krl"
  sources = ["univ-a-ssh", "univ-b-ssh"]     # merged into one file
}
output "tls" {                               # nginx: ssl_crl /var/lib/authn-revokd/univ-a.crl
  path    = "/var/lib/authn-revokd/univ-a.crl"
  sources = ["univ-a-x509"]
  format  = "pem"
}

# listen = "127.0.0.1:8080"                  # serve the verified lists: a mirror
```

## Les clés {#the-keys}

| clé | par défaut | |
|---|---|---|
| `state_dir` | | obligatoire, absolu ; créé en `0700` s'il manque |
| `refresh` | `1m` | la fréquence à laquelle chaque source est récupérée, une seconde ou plus ; chaque attente varie d'un dixième dans un sens ou dans l'autre, pour qu'un parc ne reste pas en cadence |
| `listen` | | `host:port` : servir les listes vérifiées, un miroir ; ignoré avec `-once` |

**`source "<name>"`** : une liste. Le nom est fait de lettres, de chiffres, de `.`, `_` et
`-`, ne commence pas par un point, et fait au plus 64 caractères : il nomme un fichier dans le
répertoire d'état et un chemin du miroir.

| clé | |
|---|---|
| `url` | `https://`, `http://` ou `file://` ; la signature d'une KRL est récupérée à la même URL suivie de `.sig` |
| `ssh_ca` | la clé publique de l'AC SSH, une ligne `authorized_keys` : une source KRL. Un certificat est refusé ici |
| `x509_ca` | le certificat PEM de l'AC : une source CRL |
| `max_age` | refuser aussi une liste émise depuis plus longtemps que cela, en plus de sa propre expiration ; refusé sur une source qui alimente une sortie CRL |
| `revoke_keys` | permettre à la liste de cette source de révoquer des **clés simples** dans une sortie partagée avec d'autres sources ; sources KRL seulement |

**`output "<name>"`** : un fichier que lit un serveur.

| clé | |
|---|---|
| `path` | absolu ; écrit à côté de lui-même puis renommé par-dessus |
| `sources` | des sources KRL, fusionnées en un seul fichier ; ou exactement une source CRL |
| `format` | `der` (par défaut) ou `pem` ; sorties CRL seulement |
| `on_change` | une commande et ses arguments, exécutée après que le fichier a changé, et de nouveau à chaque synchronisation jusqu'à ce qu'elle réussisse |

## Une KRL pour plusieurs AC {#one-krl-for-several-cas}

`RevokedKeys` n'accepte qu'un seul fichier avant OpenSSH 10.3, les sources KRL d'une
sortie sont donc fusionnées, et **chaque liste garde tout son effet sur sa propre AC, et
aucun sur une autre** :

- **Conservés :** ses numéros de série et identifiants de clé, ses sections qui ne nomment aucune AC (restreintes à la
  sienne), et la propre clé de son AC, qui révoque tous ses certificats.
- **Écartés, et journalisés :** la section d'une autre AC, et la clé d'une autre AC.
- Les **clés utilisateur simples** sont écartées quand la sortie a plus d'une source,
  sauf si la source a `revoke_keys = true`. Une KRL ne peut pas restreindre une clé à une seule
  AC : sshd vérifie la propre clé d'un certificat par rapport au fichier, quel que soit le signataire,
  si bien qu'une clé nommée par une AC exclurait la personne qui la détient sous toutes les AC du fichier.
  Une sortie à une seule source les conserve.

Chaque liste est d'abord fusionnée seule. Une liste qui ne peut pas être fusionnée refuse en cas de doute **pour
sa propre AC seulement** ; le fichier fusionné expire avec la première de ses entrées
en vigueur, si bien qu'un lecteur qui vérifie l'expiration voit l'arrêt d'authn-revokd.

## Le miroir {#the-mirror}

Avec `listen`, authn-revokd sert ce qu'il détient, depuis la mémoire, jamais depuis les
fichiers qu'une écriture peut avoir laissés à moitié écrits :

| | |
|---|---|
| `GET /<source>` | la liste, avec un `ETag` ; `If-None-Match` répond `304` |
| `GET /<source>.sig` | la signature d'une KRL ; `If-Match` sur un autre ETag répond `412` |
| `GET /healthz` | `200 ok`, ou `503` en nommant chaque source sans liste en vigueur et chaque sortie qui a échoué |

```
$ curl -s http://127.0.0.1:28474/healthz
ok
$ curl -s -D - -o /dev/null http://127.0.0.1:28474/bridge-ssh
HTTP/1.1 200 OK
Cache-Control: max-age=30
Content-Type: application/octet-stream
Etag: "83278365ecb0f44b05170bb12f151756"
Date: Sun, 11 Oct 2026 09:51:05 GMT
Content-Length: 130

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-Match: "stale"' http://127.0.0.1:28474/bridge-ssh.sig
412
```

Une source CRL n'a pas de `.sig` (`404`). Les miroirs s'enchaînent : la source d'un miroir peut être
un autre miroir, puisque chaque liste se vérifie par elle-même. Un amont lent ne
bloque jamais les réponses du miroir.

## Ce qui est refusé au démarrage {#what-is-refused-at-start}

Chacune de ces erreurs sort avec `2` avant que quoi que ce soit ne soit récupéré :

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

De même pour une configuration absente :

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

Avant la v0.6.2, c'était le message de l'analyseur HCL :
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

Une sortie CRL ne prend aussi qu'une seule source (un serveur TLS lit une CRL par émetteur), et
une source CRL avec `max_age` est refusée, parce que rien ne pourrait le faire respecter :

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

Un serveur TLS qui a chargé une CRL la garde en mémoire jusqu'à son `nextUpdate`,
quoi qu'authn-revokd écrive.

**Le répertoire d'état** est soumis à la règle StrictModes de sshd. Quiconque peut
remplacer ou supprimer ses fichiers décide de la liste qui vient ensuite, et un état vidé
laisse entrer une liste plus ancienne rejouée. Il ne peut donc pas être un lien symbolique, ni être accessible en écriture
par le groupe ou les autres, ni appartenir à quiconque d'autre que l'utilisateur d'authn-revokd ou root. Ces erreurs sortent
avec `1` :

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
