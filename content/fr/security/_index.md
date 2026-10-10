---
title: "Sécurité"
linkTitle: "Sécurité"
weight: 55
description: "Ce que les programmes refusent, comment une révocation voyage du fournisseur jusqu'à chaque serveur, et comment distinguer un binaire authentique de tout le reste."
tags: [security]
---

On demande à go-authn de prouver des personnes, si bien que ses refus sont la conception plutôt que
les exceptions. Cette section rassemble ceux qui traversent les frontières entre programmes ;
les pages de chaque programme disent ce qu'il refuse de lui-même.

## Les refus qui comptent le plus {#the-refusals-that-matter-most}

| | ce qui est refusé | pourquoi |
|---|---|---|
| authnd | une recherche par quiconque n'est pas un `reader` déclaré | une liaison prouve qui est quelqu'un ; ce n'est pas une permission de lister tout le monde |
| authnd | un ticket Kerberos pour une personne dont la source ne détient pas de mot de passe | un KDC a besoin d'une clé dérivée du mot de passe ; une empreinte NT ou une vérification de mot de passe ne peut pas en produire une ([pourquoi]({{< relref "/authnd/kerberos.md" >}})) |
| authnd | un bloc `kerberos` à côté d'un bloc `mfa` | un kinit porte le mot de passe et rien d'autre, donc le royaume émettrait des tickets sur un seul facteur à des personnes à qui le bloc `mfa` en impose deux |
| authn-bridge | une assertion que personne n'a signée, un identifiant hors du périmètre propre de l'établissement | une fédération ne vaut que ce que vaut la chose la plus étroite que chaque membre peut affirmer |
| authn-revokd | une liste non signée, expirée, ou plus ancienne que celle qu'il détient | un miroir intermédiaire peut retarder une liste, jamais la falsifier ni la faire reculer |
| authn-revokd | se fier à une liste qui a expiré | il en écrit une qui révoque l'AC elle-même, de sorte que sshd refuse au lieu de se fier à une liste périmée |
| sshcert-authorize | un certificat dont la délégation de domaine ne nomme pas cet hôte | un certificat d'une AC de fédération n'est pas, à lui seul, une permission pour chaque hôte qui fait confiance à cette AC |

## Une révocation, de bout en bout {#a-revocation-end-to-end}

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) signe et date une
   KRL (pour les certificats SSH) et une CRL (pour les certificats clients X.509), et
   les publie.
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) récupère chaque liste,
   vérifie sa signature et ses dates, refuse une liste plus ancienne que celle qu'il détient
   (même après un redémarrage), et ensuite seulement l'écrit là où le serveur la lit.
3. sshd (`RevokedKeys`), go-fileshare et tout le reste lisent un fichier qui a
   déjà été vérifié.

Un événement CAEP `session-revoked`, par l'émetteur de signaux partagés (Shared Signals)
du fournisseur, annule ce qu'aucune liste ne peut nommer : tout ce qui a été émis pour une personne avant
un moment donné. La documentation de go-fileshare décrit le côté réception :
[listes de révocation](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
[signaux partagés](https://go-fileshare.github.io/docs/latest/security/shared-signals/).

## Versions {#releases}

Chaque binaire est compilé par le workflow de publication à partir d'un commit étiqueté et peut être
vérifié de trois façons : [vérifier un téléchargement]({{< relref "/security/verifying-releases.md" >}}).
