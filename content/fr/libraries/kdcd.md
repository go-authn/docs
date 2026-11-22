---
title: "kdcd — un démon KDC Kerberos pour un royaume"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd est un programme construit sur la bibliothèque kdc : AS et TGS sur UDP et TCP, un seul fichier HCL, chaque secret dans un fichier, et un écouteur TLS mutuel facultatif qui émet un TGT pour une personne sans mot de passe."
tags: [bibliothèques, kerberos, annuaire, kdcd]
---

**Comment la bibliothèque [kdc]({{< relref "/libraries/kdc.md" >}}) s'exécute-t-elle comme un service ?**
`kdcd` est un démon KDC Kerberos pour un royaume, construit sur la bibliothèque
[go-authn/kdc](https://github.com/go-authn/kdc). Il répond aux requêtes AS et TGS
sur UDP et TCP et, facultativement, **émet un TGT** pour une personne qui s'est
prouvée ailleurs (une connexion par passkey chez
[go-authn/bridge](https://github.com/go-authn/bridge)), en TLS mutuel. La
bibliothèque détient le protocole ; ce programme détient les sockets, la
configuration et les règles sur les secrets.

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

Installation (le binaire est `kdcd` : le KDC de MIT est `krb5kdc`, celui de Heimdal est `kdc`) :

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

Go pur, `CGO_ENABLED=0` ; les versions publiées portent un manifeste `SHA256SUMS` et une
attestation de provenance de construction par binaire. Comme service : `packaging/systemd/`
(unité et fichier sysusers ; voir [L'exécuter](#running-it)).

## Pas de mots de passe {#no-passwords}

**Il n'y a aucun chemin de mot de passe dans `kdcd`, et aucun ne peut être activé**
(supprimé en v0.2.0 ; la v0.1.0 avait `password_file`). Une personne n'a ici aucune clé à
long terme, donc une **AS-REQ** pour une personne reçoit `KDC_ERR_NULL_KEY` par
conception, quoi que le client envoie. Une personne n'obtient un TGT que par l'**écouteur
de mint**, d'un appelant qui l'a authentifiée par une passkey (go-authn/bridge).

- Un annuaire dit **qui existe, et ses groupes**. Rien de ce qu'une source porte
  n'atteint le KDC hors le nom : chaque identité est reconstruite sans rien d'autre que
  le nom avant que la bibliothèque ne la voie (`nameOnly`), si bien que même un mot de
  passe qu'une source aurait publié ne dérive aucune clé. Les refus au chargement
  ci-dessous sont là pour dire pourquoi, pas pour être la seule garde.
- Les services et `krbtgt/REALM` gardent leurs clés dans le keytab : des **clés
  aléatoires**, jamais dérivées d'un mot de passe (générez-les, par exemple, avec 32
  octets de `/dev/urandom` au moyen de votre outil de keytab).
- `password_file`, une requête ou un attribut de `users` nommant une colonne de mot de
  passe ou d'empreinte NT, un `bind_password_file`, un `bind_dn` (une liaison simple est
  un mot de passe), ou un DSN contenant un mot de passe : refusés au chargement, en
  nommant la suppression et la version.
- Une source `ldap` est lue **anonymement**. Une liaison de service par certificat client
  ou SASL EXTERNAL n'est pas encore disponible, car `hcldir.Block` de `go-authn/directory`
  n'a pas de champ pour cela ; tant qu'il n'en a pas, `bind_dn` est refusé.

Le côté bibliothèque est expliqué sur la
[page kdc]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}}).

## Configuration {#configuration}

Un seul fichier HCL. Rien dedans n'est un secret ; chaque secret est un fichier.

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: who exists. Any number of these, in any mix.
user "alice@poc.test" {}                  # a name; a TGT only through mint

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"              # no password in it: a client certificate or a socket
  users    = "select login as name from staff"
}
users "ldap" {                            # read anonymously
  url      = "ldaps://ldap.example.org"
  base_dn  = "ou=people,dc=example,dc=org"
}
```

Les blocs `users` sont ceux de [go-authn/directory/hcldir](https://github.com/go-authn/directory) ;
kdcd refuse les parties qui portent un mot de passe (voir plus haut).

**Secrets : un fichier, ou une référence.** `keytab_file` et `key_file` (dans `mint`)
désignent un fichier, vérifié comme décrit plus bas. `keytab_from` et `key_from`
prennent à la place une référence secretsource, par exemple `systemd-creds:kdc-keytab` :
un credential que systemd déchiffre pour le service (`LoadCredentialEncrypted=`,
scellé avec `systemd-creds encrypt --with-key=host+tpm2`, jamais un `--tpm2-pcrs=7`
seul). Une seule des deux formes, pas les deux. `file:` est refusé dans une clé `_from`.
`keytab_file` reste et n'est pas déprécié : un keytab et une clé sont binaires, `file:`
retire un saut de ligne final (ce qui corromprait une clé finissant par l'octet 0x0a), et
une référence tient au plus 4096 octets, donc un keytab plus gros reste dans `keytab_file`.
Depuis secretsource v0.9.0, `file:` refuse aussi un lien symbolique et un fichier
appartenant à un autre uid. `dsn_file` ne contient aucun mot de passe : pas de `_from`.

`kdcd check --config FILE` lit et construit tout ce que le démon construirait, ouvre
l'annuaire, n'écoute nulle part, et affiche ce qu'il sert : le royaume, les adresses, les
principaux du keytab (nom, kvno, etype ; jamais une clé), le nombre de personnes que
l'annuaire contient, les appelants du mint. Code de sortie 0 et une dernière ligne `ok`,
ou le premier refus.

### Ce avec quoi il refuse de démarrer {#what-it-refuses-to-start-with}

| Refusé | Pourquoi |
| --- | --- |
| un keytab, une clé de mint ou un fichier DSN que **le groupe ou les autres peuvent lire ou écrire**, ou qui appartient à un uid autre que root ou celui du démon | une copie qu'un autre compte peut lire falsifie des tickets pour chaque personne du royaume |
| **tout chemin de mot de passe** : `password_file` (même vide), `bind_password_file`, `bind_dn`, une requête ou un attribut de `users`/`groups` nommant `password`, `passwd`, `nt_hash`, `userPassword`..., un DSN portant un mot de passe | supprimé en v0.2.0 : aucune personne n'a de clé ici ; le message le dit. Les contrôles de requête et de DSN sont au mieux ; `nameOnly` retient ce qui leur échappe |
| un secret écrit en ligne (`password = "..."` n'est pas un argument) | les secrets vivent dans des fichiers, jamais dans la configuration, une sauvegarde de celle-ci, ou un journal |
| un fichier de configuration que le groupe ou les autres peuvent écrire | qui l'écrit choisit les appelants du mint |
| un keytab sans clé `krbtgt/REALM`, ou auquel manque un service listé, **en aes256-cts-hmac-sha1-96** (le seul type que la bibliothèque émet) | il démarrerait et échouerait au premier `kinit` |
| un joker ou un nom d'hôte dans `listen` (un littéral IP est exigé), et **tout** joker pour `mint` | le KDC et l'écouteur de mint sont sur les interfaces que quelqu'un a choisies |
| un bloc `mint` sans appelants, sans certificat, ou avec un certificat expiré | la bibliothèque lit l'absence d'appelants comme « mint désactivé » ; ceci le dit au lieu de ne rien émettre en silence |
| `ldap://` vers une autre machine sans `start_tls` | chaque mot de passe traverserait le réseau tel que saisi |

Les fichiers secrets sont ouverts **une seule fois** et le fichier ouvert est vérifié
(fichier ordinaire, mode, propriétaire), si bien qu'un contrôle ne peut pas porter sur un
fichier et la lecture sur un autre (le modèle est `readKeytab` de go-fileshare).
`dsn_file` est lu par `hcldir` par son nom, après avoir été
vérifié de la même façon.

## Le modèle de confiance du mint {#the-mint-trust-model}

`POST https://<mint address>/mint` avec `{"principal": "alice", "lifetime_seconds": 36000}`
renvoie un KRB-CRED (RFC 4120 5.8) contenant un TGT pour `alice`, que l'appelant remet à la
machine de la personne ([go-authn/kinit](https://github.com/go-authn/kinit) le charge dans
une session d'ouverture Windows). Ce qui le borne :

- **L'appelant est le certificat client TLS**, vérifié par l'écouteur contre
  `client_ca_file` (TLS 1.3, `RequireAndVerifyClientCert`) : une connexion sans
  certificat, ou avec un certificat que la CA n'a pas signé, échoue à la poignée de main
  avant qu'aucun HTTP ne soit lu. Un certificat vérifié est ensuite comparé, par un
  **subjectAltName URI**, à `callers`, exactement ; un certificat qui se vérifie mais
  n'est pas listé reçoit `403`. Rien dans un en-tête ou un corps ne nomme l'appelant.
- **Quiconque figure dans `callers` peut obtenir un TGT pour n'importe quel principal de
  l'annuaire** (jamais un service, jamais un nom que l'annuaire n'a pas), sans la clé de
  cette personne. C'est l'authentification de la personne par l'appelant que le royaume
  croit, si bien qu'un appelant est aussi digne de confiance que l'est le keytab du KDC.
  Listez-en un par fournisseur d'identité, donnez à chacun son propre certificat, et
  gardez `client_ca_file` comme une CA qui ne signe rien d'autre.
- Le ticket est `INITIAL | PRE-AUTHENT`, jamais renouvelable, transmissible ni
  mandataire ; sa durée est la plus petite de la demande, de `lifetime` et de dix heures.
- La clé de session est tirée de `crypto/rand`, ne quitte le processus qu'une fois, dans
  la réponse, et n'est jamais journalisée. La réponse porte `Cache-Control: no-store`.
  Le KRB-CRED porte la clé en clair, si bien que **le canal TLS est le chiffrement** :
  placez l'écouteur sur une interface interne.
- Seul `/mint` est servi, avec des délais et une limite d'en-tête. Chaque mint, et chaque
  refus, est journalisé avec l'URI de l'appelant et le principal demandé.

Le modèle de menaces complet est celui de la pull request de la bibliothèque,
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38), avec la
[section sur l'émission](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)
et les [notes d'audit](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)
du README de la bibliothèque ; rien n'en est répété ni affaibli ici.
Le bloc `kerberos` de [go-authn/bridge](https://github.com/go-authn/bridge) est le côté
appelant : son `kdc_url` est `https://<mint address>/mint`, son `ca_file` signe le
`cert_file` ci-dessus, et le nom URI de son certificat client est une entrée de `callers`.

## L'exécuter {#running-it}

`packaging/systemd/kdcd.service` l'exécute sous l'utilisateur système de
`packaging/sysusers.d/kdcd.conf`, avec le durcissement de l'unité de
[authn-bridge](https://github.com/go-authn/bridge). Le port 88 est privilégié, donc
l'unité accorde exactement `CAP_NET_BIND_SERVICE` et rien d'autre.

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

Les secrets appartiennent à `kdcd` (ou à root) en mode 0600 ; 0640 avec le groupe `kdcd`
est refusé exprès. Un changement de configuration se fait par `systemctl restart kdcd`
(le démon ne recharge pas ; un client réessaie une connexion refusée).

Sous Windows les bits de mode ne signifient rien et ne sont pas vérifiés : placez les
fichiers là où seul le compte qui exécute le service peut les lire.

## Pas ici {#not-here}

Inter-royaumes, PKINIT, FAST, tickets renouvelables ou postdatés, protocole kadmin, et
tout type de chiffrement autre que aes256-cts-hmac-sha1-96 sont des limites propres à la
bibliothèque ([go-authn/kdc](https://github.com/go-authn/kdc#readme)). `kdcd` n'a pas
encore de rechargement ni de point d'accès de métriques.

## Référence {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd), v0.2.0.
