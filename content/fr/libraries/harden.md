---
title: "harden — deux primitives de sécurité, partagées"
linkTitle: "harden"
weight: 36
description: "go-authn/harden réunit les primitives de sécurité que les dépôts go-authn avaient chacun copiées : la règle de redirection https-ou-loopback, un fichier privé écrit de façon atomique, et le verrouillage mémoire avec durcissement des core dumps."
tags: [libraries, harden, security]
---

**Qu'est-ce que chaque dépôt go-authn avait copié ?** Deux petites règles, désormais
dans un seul module sans autre dépendance que la bibliothèque standard.

```sh
go get github.com/go-authn/harden@v0.3.0
```

## `redirect` {#redirect}

La règle appliquée avant qu'un jeton, un jeu de clés ou une assertion signée ne
franchisse un lien : **l'URL est en https, ou elle désigne cette machine.**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| Fonction | |
|---|---|
| `CheckRedirect(req, via) error` | une politique d'`http.Client` : s'arrête après 10 redirections et refuse une cible qui n'est ni en https ni loopback (de https vers http sur un autre hôte est le cas pour lequel elle existe). Chaînez votre propre politique après elle |
| `HTTPSOrLoopback(rawURL) error` | nil pour `https://host.example/...`, ou `http://` avec un hôte loopback. Refuse l'absence d'hôte, les autres schémas et le clair. L'erreur nomme le schéma et l'hôte, jamais l'URL entière |
| `Loopback(host) bool` | `host` tel que le renvoie `url.URL.Hostname()` |

`Loopback` accepte un littéral IP loopback (127.0.0.0/8, `::1`, `::ffff:127.0.0.1`
IPv4-mappé), et `localhost` ou tout nom sous `.localhost` (RFC 6761 section 6.3),
quelle que soit la casse, avec ou sans le point final. Elle ne compare jamais un
préfixe, si bien que `127.evil.example` est refusé, de même que `0x7f.1`, `127.1`,
`2130706433`, une zone IPv6 et le `[::1]` entre crochets (les crochets sont de la
syntaxe d'URL, pas une partie d'un hôte).

`Loopback` et `HTTPSOrLoopback` sont fuzzées contre une seconde lecture de la RFC ; le
corpus est versionné.

C'est ce qu'appliquent [oidc]({{< relref "/libraries/oidc.md" >}}) (v0.8.1),
[saml]({{< relref "/libraries/saml.md" >}}) (v0.7.3),
[wireguard]({{< relref "/libraries/wireguard.md" >}}), rp (v0.5.1) et awscred
(v0.3.1).

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write` dépose des données à `path` avec le mode 0600 : un fichier temporaire dans le
même répertoire, `fsync`, puis `rename`. Ainsi :

- un lecteur voit l'ancien fichier ou le nouveau, jamais la moitié de l'un ;
- un lien symbolique laissé à `path` est **remplacé, pas suivi** (ce qu'il désignait
  est intact), et un fichier de mode plus large ne garde pas son mode ;
- sous Unix, un répertoire qui est un lien symbolique, appartient à quelqu'un d'autre
  ou est inscriptible par le groupe ou les autres est refusé avant que rien ne soit
  écrit.

Elle ne crée pas le répertoire. Sous Windows il n'y a pas de mode à lire ; depuis la
v0.2.0 le fichier est créé avec une liste d'accès protégée contenant une seule entrée,
le compte courant, posée par `CreateFile` (la liste de kinit v0.3.2), si bien que les
entrées du dossier ne sont jamais héritées. Le module requiert `golang.org/x/sys`,
utilisé seulement par les compilations Windows.

C'est elle qui écrit le `--cred-file` de kinit (v0.3.3), le `FloorFile` de wireguard
(v0.2.1), le fichier d'état d'`authn-revokd` (revocation v0.7.2) et le fichier
d'association KeePassXC de
[secretsource]({{< relref "/libraries/secretsource.md" >}}) (v0.8.1).

## Planchers {#floors}

go-authn/wireguard et go-authn/revocation gardent tous deux un plancher d'ordre d'un
redémarrage à l'autre, mais ils ne partagent pas de plancher : wireguard garde une
simple version et l'heure d'émission dans un petit fichier à lui, revocation garde
toute la liste signée et recalcule le plancher en la vérifiant. Seule l'écriture du
fichier est commune, et c'est `privfile`.

## `memlock` {#memlock}

Depuis la v0.3.0 (venu de theca) : garder le matériel de clé hors du swap, des
fichiers core et des débogueurs.

```go
import "github.com/go-authn/harden/memlock"

region, err := memlock.Lock(unsafe.Pointer(&key[0]), uintptr(len(key)))
if err != nil { ... } // refusé : le dire, ou s'arrêter
defer region.Release()
```

| Fonction | |
|---|---|
| `Lock(p, n) (*Region, error)` | verrouille les pages de la plage avec `mlock` (Linux, macOS, les BSD) ou `VirtualLock` (Windows). **Un refus est une erreur** : rien ne reste verrouillé et l'appelant décide. Les pages partagées par deux régions restent verrouillées jusqu'à la libération des deux |
| `(*Locker).LockBestEffort(p, n, report)` | pareil, mais chaque refus est transmis à `report` et le reste se verrouille quand même. Le nom le dit : à n'utiliser que là où tourner sans verrou est acceptable |
| `(*Region).Release()` | déverrouille ; sans danger sur nil et appelée deux fois |
| `DisableDumps() error` | `RLIMIT_CORE` à 0 et, sous Linux, `PR_SET_DUMPABLE` à 0 ; sous macOS seulement, `PT_DENY_ATTACH` |

Toute autre plateforme reçoit une `*UnsupportedError` (elle correspond à
`errors.ErrUnsupported`), jamais un succès silencieux.

**Elle garantit** que les pages de la plage sont verrouillées en mémoire de
`Lock` à `Release`, ou que vous recevez une erreur. **Elle ne garantit pas**
qu'aucune copie n'existe : le ramasse-miettes de Go peut copier un objet du tas
avant son verrouillage ; verrouillez donc une mémoire qui ne bouge pas et
gardez le secret en un seul endroit. Les limites du système s'appliquent
toujours (`RLIMIT_MEMLOCK` ; sous Windows, la taille du working set). Windows n'a
pas d'équivalent de `PR_SET_DUMPABLE` ni de `PT_DENY_ATTACH` : un débogueur du
même utilisateur ou un administrateur peut lire le processus.

## Référence {#reference}

Le README de
[github.com/go-authn/harden](https://github.com/go-authn/harden) fait foi pour cette
page. BSD 3-Clause.
