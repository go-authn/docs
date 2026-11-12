---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "Un agent qui récupère des KRL et des CRL signées, ne garde que les listes qui se vérifient, les écrit là où sshd et les serveurs TLS les lisent, et refuse en cas de doute quand l'une d'elles expire."
tags: [authn-revokd, révocation, krl, crl]
---

**OpenSSH n'a aucun moyen de distribuer une KRL, et rien dans une KRL ne dit qu'elle est
périmée.** `sshd` lit un fichier qui a cessé d'être mis à jour il y a des mois comme la liste
en vigueur. authn-revokd comble ces deux lacunes pour les listes que publie
[authn-bridge]({{< relref "/authn-bridge/revocation.md" >}}) : il
récupère chaque liste, ne la garde que si elle se vérifie, l'écrit là où `sshd` ou un serveur
TLS la lit, et, quand une liste expire, en écrit une qui **révoque l'AC (autorité de certification)
elle-même**. Pur Go, `CGO_ENABLED=0`, un seul binaire. Ces pages décrivent la v0.7.0.

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.7.0
go: downloading github.com/go-authn/revocation v0.7.0
$ authn-revokd --version
authn-revokd v0.7.0
$ authn-revokd --help
authn-revokd fetches revocation lists, keeps only those that verify, writes
them where sshd and TLS servers read them (failing closed for sshd when a list
lapses) and, with listen, serves the verified copies as a mirror. SIGHUP syncs now.

The single-dash spellings -config, -once, -version and -help of earlier
releases are still accepted, with a deprecation warning on stderr.

Usage:
  authn-revokd [flags]

Flags:
  -c, --config string   the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -h, --help            help for authn-revokd
  -o, --once            sync once and exit: 1 when a list is not current, or could not be fetched
  -v, --version         version for authn-revokd
```

La commande est cobra depuis la v0.7.0 : options POSIX `--config`/`-c`, `--once`/`-o`,
`--version`/`-v`, `--help`/`-h`, et `--config=PATH`. `--help` écrit sur la
sortie standard et sort avec 0 (avant la v0.6.2, l'ancien `-help` sortait avec 2). Les
graphies à tiret simple des versions précédentes (`-config`, `-once`, `-version`,
`-help`, avec `=` ou une valeur séparée) sont toujours acceptées, avec une
ligne d'obsolescence par option sur l'erreur standard, et seront retirées dans une
version ultérieure ; les statuts de sortie sont inchangés (0 ; 1 pour un échec ou une liste
qui n'est pas en vigueur avec `--once` ; 2 pour une erreur d'usage ou une configuration
illisible), si bien qu'une unité déployée avec `-once` n'a besoin d'aucun changement.

Avant la v0.6.0, la commande s'appelait `revokd`, et lisait `/etc/revokd.hcl` par défaut.
Plus rien ne lit ce fichier ; quand il est présent et que le nouveau fichier par défaut ne l'est pas,
l'erreur nomme les deux chemins.

## Ce qu'il fait, en une exécution {#what-it-does-in-one-run}

Face à un émetteur de substitution sur l'interface de bouclage (un petit programme qui sert une KRL et une CRL
signées par des clés de test, avec les mêmes points d'accès qu'authn-bridge), avec une source KRL
et une source CRL :

```
$ authn-revokd --config revokd.hcl --once
bridge-ssh: version 0, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
bridge-x509: version 1794481424000, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261112T120344
# Comment: authn-revokd sshd
```

Une seconde exécution sans rien de nouveau n'affiche rien et sort avec 0 : une sortie n'est
réécrite que lorsque son contenu change.

## Pourquoi le transport n'a pas d'importance {#why-the-transport-does-not-matter}

Chaque liste s'authentifie elle-même : une KRL par une signature SSHSIG détachée faite avec la
propre clé de l'AC, une CRL par la signature de son AC. Chaque liste dit quand elle cesse d'être
en vigueur. Une liste peut donc arriver par HTTPS, par HTTP en clair à l'intérieur d'une grappe, par un miroir,
ou par un fichier. Le transport décide de la vitesse à laquelle un changement arrive, jamais de l'acceptation
d'une liste falsifiée ou périmée.

| | KRL | CRL |
|---|---|---|
| authentique | SSHSIG par la clé de l'AC SSH, espace de noms `krl@go-authn.github.io` | signée par son AC |
| en vigueur | `expires@go-authn.github.io`, que sshd ignore | `nextUpdate` |
| jamais en arrière | `krl_version`, puis date de génération | CRL Number, puis `thisUpdate` |
| refus en cas de doute | authn-revokd écrit une KRL qui révoque la clé de l'AC | OpenSSL refuse de lui-même une CRL expirée |

## Pour aller plus loin {#where-to-go-next}

| | |
|---|---|
| [L'installer]({{< relref "/authn-revokd/install.md" >}}) | le démon, ou `--once` sur un minuteur ; brancher sshd et nginx |
| [La configuration]({{< relref "/authn-revokd/configuration.md" >}}) | sources, sorties, le miroir, et ce qui est refusé |
| [Comment une liste est vérifiée]({{< relref "/authn-revokd/verification.md" >}}) | signature, dates, et jamais plus ancienne que la liste détenue, même après un redémarrage |
| [Quand une liste expire]({{< relref "/authn-revokd/lapse.md" >}}) | la KRL qui révoque l'AC elle-même |

## Ce qu'il ne fait pas {#what-it-does-not-do}

Une révocation n'atteint pas un serveur plus vite que la fréquence d'interrogation d'authn-revokd (`refresh`),
plus le délai de l'émetteur pour émettre à nouveau. Tant que l'émetteur est arrêté, ses
certificats sont refusés à partir de l'expiration de la liste. Quiconque détient la clé d'une AC peut
signer n'importe quelle liste, comme n'importe quel certificat.

## Licence {#licence}

BSD-3-Clause.
