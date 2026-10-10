---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "Un fournisseur OpenID Connect devant une fédération SAML : les personnes se connectent dans leur propre établissement, et les applications obtiennent des jetons, des certificats SSH et des certificats clients X.509."
tags: [authn-bridge, oidc, saml]
---

**Les personnes se connectent dans leur propre université, par la Fédération
Éducation-Recherche de RENATER ou par eduGAIN, et les applications obtiennent un jeton OpenID Connect.**
La même connexion peut aussi faire certifier une clé SSH, faire émettre un certificat
client X.509 pour NFS sur TLS, définir un mot de passe d'application pour SMB et S3, ou
enregistrer une clé WireGuard. Tout ce que le fournisseur a émis, il peut le reprendre, et il
publie des listes signées de ce qu'il a révoqué. Pur Go, `CGO_ENABLED=0`, un seul
binaire. Ces pages décrivent la v0.20.1.

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.20.1

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

Avant la v0.20.0, la commande s'appelait `bridge`. C'est aussi le
`/sbin/bridge` d'iproute2, installé sur pratiquement tous les systèmes Linux, et celui qui venait
en premier dans `PATH` l'emportait. Le chemin du module est toujours `github.com/go-authn/bridge`.

## Pourquoi un pont {#why-a-bridge}

Une fédération de recherche parle SAML. Ses membres sont des centaines de fournisseurs
d'identité, un par établissement, listés dans un document de métadonnées signé que
la fédération publie. Les applications écrites aujourd'hui veulent OpenID Connect, et font confiance à un seul
fournisseur. authn-bridge est ce fournisseur unique : un fournisseur de service SAML d'un
côté, enregistré une seule fois auprès de la fédération, et un fournisseur OpenID de l'autre.

Une passerelle décide de qui est chacun pour chaque application derrière elle, aussi l'essentiel
de ce programme consiste-t-il en refus. Il refuse des métadonnées que la fédération n'a pas signées, une
assertion qui désigne quelqu'un du domaine d'un autre établissement, des groupes sur lesquels un IdP
n'a aucune autorité, et une configuration qui laisserait passer l'un d'eux.
Une configuration qui ne peut pas être servie en sécurité ne démarre pas.

## Ce qu'il affiche au démarrage {#what-it-prints-at-startup}

```
$ authn-bridge --config etc/bridge-admin.hcl
authn-bridge v0.20.1: http://127.0.0.1:28473 on 127.0.0.1:28473
metrics on 127.0.0.1:28475
admin API on unix:///tmp/docs-patch-a2daf7c8/run/admin.sock
```

Il s'agit d'un fournisseur de test sur l'interface de bouclage (un émetteur `http://` n'est accepté que sur un
hôte de bouclage). Il récupère les métadonnées de la fédération **avant** de se mettre à l'écoute. Un
fournisseur qui ne peut nommer aucun établissement est un fournisseur par lequel personne ne peut se connecter :
sans les métadonnées, il s'arrête plutôt que de démarrer.

## Pour aller plus loin {#where-to-go-next}

| | |
|---|---|
| [L'installer]({{< relref "/authn-bridge/install.md" >}}) | l'utilisateur, les répertoires, l'unité systemd, les clés |
| [La configuration]({{< relref "/authn-bridge/configuration.md" >}}) | chaque bloc, `check`, et ce qui est refusé au démarrage |
| [Le côté fédération]({{< relref "/authn-bridge/federation.md" >}}) | les métadonnées, l'empreinte de leur signataire, les portées, et ce qu'un IdP peut affirmer |
| [Jetons]({{< relref "/authn-bridge/tokens.md" >}}) | jetons d'identité (ID tokens), jetons d'accès, l'autorisation d'appareil, mots de passe d'application, clés WireGuard |
| [Certificats]({{< relref "/authn-bridge/certificates.md" >}}) | certificats SSH, le profil EuroHPC, certificats clients X.509 pour NFS |
| [Révocation]({{< relref "/authn-bridge/revocation.md" >}}) | la KRL et la CRL signées, et l'émetteur de signaux partagés (Shared Signals) |
| [L'API d'administration]({{< relref "/authn-bridge/admin.md" >}}) | désactiver une personne ou un établissement, santé et métriques |

Les listes qu'il signe sont lues par [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
pour un `sshd` ordinaire ou un serveur TLS, et par
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
qui les vérifie lui-même.

## Ce qu'il n'est pas {#what-it-is-not}

- **Un seul processus.** Avec un bloc `state`, les jetons de rafraîchissement et les jetons d'accès
  honorés à `/userinfo` survivent à un redémarrage. Les connexions en cours, les codes et
  les autorisations d'appareil, non. L'état est écrit au fil de l'eau et lu au démarrage, si bien que
  deux instances sur une même base de données manqueraient chacune ce que l'autre a écrit.
- Pas d'enregistrement dynamique de clients, et pas de déconnexion front-channel ni back-channel.
- Pas d'utilisateurs ni de groupes à ajouter. Les personnes existent parce que leur établissement se porte
  garant d'elles, et leurs groupes sont ce qu'il affirme.

## Licence {#licence}

BSD-3-Clause.
