---
title: "Comment une liste est vérifiée"
linkTitle: "Vérification"
weight: 30
description: "Ce qu'authn-revokd vérifie avant de garder une liste : la signature, les dates, et qu'elle n'est jamais plus ancienne que la liste qu'il détient, même après un redémarrage."
tags: [authn-revokd, revocation, security]
---

Une liste qui ne se vérifie pas n'est jamais écrite, servie ni utilisée. La dernière bonne
copie reste. Une récupération qui échoue, pour quelque raison que ce soit, ne la remplace jamais par une réponse
vide, qui ne révoquerait rien.

## La signature {#the-signature}

**Une KRL** est récupérée avec sa signature, `<url>.sig` : une SSHSIG en armure ASCII sur
le fichier entier, faite avec la **clé de l'AC SSH** configurée comme `ssh_ca`, dans l'espace de noms
`krl@go-authn.github.io`. L'espace de noms empêche que la signature soit prise
pour autre chose. Un signataire hache en SHA-512 ; SHA-256 est aussi accepté. Une
signature RSA sous la forme SHA-1, que PROTOCOL.sshsig interdit, est refusée.

La KRL elle-même doit s'analyser comme `sshd` l'analyse, et ne doit pas porter la propre
section de signature d'OpenSSH, qu'OpenSSH ne vérifie jamais.

Une liste signée par toute autre clé est refusée :

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:SLbG7N+YZ/TQ6B3I1DQLYo2/6In4OWx5GYkRfKIxpxo: public key does not match
bridge-x509: version 1791665695047, issued 2026-10-10T20:54:55Z, expires 2026-10-10T21:54:55Z
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/other.krl
output tls: wrote /tmp/docs-patch-a2daf7c8/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

Ici, `ssh_ca` nommait une clé qui n'avait pas signé la liste du bridge, et l'erreur nomme
cette clé. Une signature qui ne se vérifie pas peut aussi être une liste émise de nouveau
entre les deux requêtes, les deux sont donc récupérées une fois de plus avant que ce ne soit signalé.
C'était la première récupération de cette source, il n'y avait donc aucune bonne copie à garder, et
la sortie est d'emblée la [liste qui refuse en cas de doute]({{< relref "/authn-revokd/lapse.md" >}}).
(Avant la v0.6.2, le même échec était signalé comme « the list changed between
it and its signature », devant les mêmes mots.)

La signature est récupérée avec `If-Match: <the list's ETag>`. Une liste émise
de nouveau entre les deux requêtes répond `412`, et les deux sont récupérées de nouveau.

**Une CRL** est vérifiée par rapport au certificat d'AC configuré comme `x509_ca` : sa
signature d'abord, sur les octets bruts, **avant** que le reste ne soit analysé, si bien qu'une grosse
CRL signée par n'importe qui coûte une vérification de signature plutôt qu'une analyse. Ensuite, son
émetteur doit être le sujet de ce certificat ; elle doit avoir un CRL Number et un
`nextUpdate` postérieur à son `thisUpdate` ; et elle ne doit être ni une delta CRL, ni porter une
extension critique autre que le CRL Number et l'Authority Key Identifier,
ni une extension d'entrée critique.

Une KRL doit aussi **dire quand elle expire**, dans l'extension `expires@go-authn.github.io` :
une KRL qui ne le dit pas ne pourrait jamais être distinguée d'une KRL périmée.

Les corps sont bornés : une KRL à 32 Mio, sa signature à 64 Kio, une CRL à 64 Mio.

## Les dates {#the-dates}

Une liste est en vigueur quand :

- maintenant est avant son expiration (l'extension de la KRL, le `nextUpdate` de la CRL) ;
- elle n'a pas été émise plus de cinq minutes dans le futur : un émetteur dont l'horloge
  avance de plus que cela écrit des listes dont l'âge ne peut pas être connu ;
- avec `max_age`, elle n'a pas été émise depuis plus longtemps que cela.

Une liste qui n'est pas en vigueur est refusée à la récupération. Un `304 Not Modified` n'apporte
rien de nouveau : la copie détenue a pu expirer depuis, et elle est jugée de nouveau à chaque
synchronisation.

## Jamais plus ancienne que la liste détenue {#never-older-than-the-list-held}

La position d'une liste est sa **version** (le `krl_version` de la KRL, le CRL
Number), puis son **heure d'émission** (la date de génération de la KRL, le
`thisUpdate` de la CRL). Une liste ne peut remplacer celle détenue que si elle a une
version plus élevée, ou la même version émise plus tard : les mêmes révocations, émises de nouveau
avec une nouvelle expiration. Tout le reste est un retour en arrière : une liste plus ancienne rejouée ou restaurée,
toujours signée et non expirée, qui annulerait la révocation de ce que la plus récente avait
révoqué.

### Même après un redémarrage {#across-restarts-too}

La liste détenue est conservée dans `state_dir`, un fichier par source contenant la liste et
sa signature ensemble, écrit par un seul renommage avec synchronisation du répertoire.
Au démarrage, chaque copie est **vérifiée de nouveau** (expirée ou non, elle ordonne ce qui vient
ensuite), et une copie qui ne se vérifie plus n'est pas digne de confiance, pas même pour ordonner la
suivante, et le journal le dit.

Ici, une source est dirigée, après un redémarrage, vers une liste qu'un processus bridge antérieur
avait servie quatorze secondes plus tôt, toujours signée et toujours non expirée :

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-10T20:54:50Z, expires 2026-10-10T21:54:50Z
bridge-x509: version 1791665695047, issued 2026-10-10T20:54:55Z, expires 2026-10-10T21:54:55Z
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/sshd.krl
output tls: wrote /tmp/docs-patch-a2daf7c8/revokd/out/bridge.crl
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/docs-patch-a2daf7c8/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-10T20:54:36Z, the copy held at 2026-10-10T20:54:50Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-10T21:54:50Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261010T225450
# Comment: authn-revokd sshd
```

La liste plus ancienne est refusée et la sortie garde la plus récente. Le processus qui
l'a refusée n'avait jamais vu la liste plus récente : il l'a relue depuis `state_dir`.

Puisque c'est l'état qui rend un retour en arrière détectable, le répertoire est soumis à la
règle StrictModes de sshd ([la configuration]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}})).
Un plantage entre deux écritures ne peut pas laisser une paire qui ne se vérifie pas, ce qui
emporterait avec elle la protection contre le retour en arrière : la liste et sa signature sont un seul fichier.

## Ce que signale `-once` {#what--once-reports}

`-once` sort avec `1` quand une source n'a aucune liste en vigueur, quand sa **dernière récupération
a échoué**, ou quand une sortie n'a pas pu être écrite, et sa dernière ligne dit lequel
des deux premiers cas c'est :

| dernière ligne | la source | ses sorties |
|---|---|---|
| `not current: <source>` | ne détient aucune liste en vigueur : jamais récupérée, expirée, ou au-delà de `max_age` | refusent en cas de doute pour sshd |
| `not fetched: <source> (the list held is current until <T>)` | sa récupération a échoué, mais la copie détenue est toujours en vigueur | écrites à partir de cette copie, inchangées, jusqu'à `T` |

Ici, l'émetteur est arrêté alors que les deux listes détenues sont toujours en vigueur :

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-10T21:54:50Z), bridge-x509 (the list held is current until 2026-10-10T21:54:55Z)
```

Cette exécution a laissé `sshd.krl` tel quel. Une fois qu'une liste détenue expire, la même source est
signalée `not current`, et les deux sortes peuvent partager la ligne, comme dans
[quand une liste expire]({{< relref "/authn-revokd/lapse.md" >}}). Avant la v0.6.2,
les deux cas étaient signalés `not current`, ce qui disait qu'une liste avait expiré alors que seule
sa récupération avait échoué ; le code de sortie était déjà `1`.

Le `/healthz` du miroir juge plutôt d'après la copie détenue, et a répondu `ok` pendant que
l'émetteur était arrêté et que les copies étaient toujours en vigueur.
