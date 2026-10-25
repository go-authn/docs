---
title: "État"
weight: 60
description: "Les versions que décrivent ces pages, ce que chaque version a ajouté, et ce qui n'est pas encore implémenté."
tags: [état, versions]
---

Ces pages sont la version **0.5** de la documentation, et décrivent :

| programme | version | module |
|---|---|---|
| authnd | **v0.12.0** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.1** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.4** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.7** | `github.com/go-authn/sshcert` |

Les versions des bibliothèques sont sur [leur propre page]({{< relref "/libraries/_index.md" >}}) ;
ldap est en **v0.9.0**, avec les schémas en HCL2 et le convertisseur
`ldapschema`, et directory en **v0.15.0**, avec les classes d'objet déclarées.
authnd v0.12.0 embarque ldap v0.9.0 et directory v0.15.0.
Une nouvelle version mineure de l'un des programmes ci-dessus est une nouvelle version de la documentation,
de sorte que les pages qu'une personne trouve sous `/docs/0.5/` continuent de décrire ce
qu'elle a installé ; celles des versions précédentes restent sous `/docs/0.1/`,
`/docs/0.2/`, `/docs/0.3/` et `/docs/0.4/`.

{{< callout type="warning" >}}
**Sécurité : utilisez authnd v0.12.0, pas la v0.11.1**

authnd vérifie des certificats (`x509.Certificate.Verify`, atteint depuis `main`
selon `govulncheck`), et le crypto/x509 de Go 1.27.2 ne révoquait pas la
confiance dans les certificats intermédiaires compromis que nomme GO-2026-6809.
**Les binaires de la v0.11.1 ont été compilés avec Go 1.27.2 et sont touchés.**
La v0.12.0 est compilée avec Go 1.27.3 et sa directive `go` est 1.27.3 : `go install`
passe donc de lui-même à la chaîne d'outils corrigée ; `govulncheck` sous 1.27.3
ne signale aucune vulnérabilité. Son binaire de la version affiche `go1.27.3` dans
`go version -m`. Voir [la note de mise à niveau]({{< relref "/authnd/_index.md" >}}).
{{< /callout >}}

## Ce que chaque version a ajouté {#what-each-release-added}

Chaque ligne est le changement pour lequel une version a été publiée. Les versions qui n'ont fait que mettre à jour
des dépendances sont omises, sauf celles que décrit cette version de la documentation.

### authnd {#authnd}

| | |
|---|---|
| v0.1.0 | un serveur LDAP pour des personnes qui sont ailleurs : un fichier, une base de données SQL, un autre annuaire |
| v0.2.0 | un second facteur, sur un protocole qui n'a qu'un champ |
| v0.5.0 | des changements de mot de passe qui touchent exactement une identité ; un rechargement sans concurrence ; le KDC voit les changements |
| v0.6.0 | les correctifs de sécurité d'oidc, directory, ldap, totp et mfa |
| v0.7.0 | l'ancien mot de passe est exigé pour en changer ; les secrets sont comparés sous forme d'empreintes de longueur fixe |
| v0.8.2 | un code ne compte que derrière le bon mot de passe ; un lecteur est identifié par son DN configuré |
| v0.9.0 | compilé et testé avec Go 1.27.1, épinglé au lieu de `stable` |
| v0.9.2 | binaires de version, `SHA256SUMS` et provenance de compilation à chaque étiquette |
| v0.9.3 | binaires compilés hors de l'extraction ; chacun doit annoncer exactement l'étiquette |
| v0.9.4 | un `SIGHUP` n'arrête plus authnd : il est journalisé, et rien n'est rechargé |
| v0.9.5 | la publication vérifie les informations de compilation de **chaque** binaire, pas d'un seul |
| v0.9.6 | `check` dit pourquoi chaque personne ne peut pas recevoir de ticket |
| v0.10.0 | `check` ouvre le certificat et le keytab, comme le fait le serveur ; il nomme qui ne peut pas se lier avec un mot de passe, et qui un jeton admet encore ; la ligne d'écoute vient après l'ouverture du royaume |
| v0.10.1 | go-authn/kdc v0.4.2 : un `till` de 19700101000000Z obtient le ticket le plus long, et non un ticket expiré en 1970 |
| v0.10.2 | go-authn/directory v0.12.0 : un groupe vide est publié comme `posixGroup` sans `memberUid` |
| v0.11.0 | [des entrées des schémas standard]({{< relref "/authnd/entries.md" >}}), chacune soumise au schéma servi à `cn=Subschema` ; `attributes`, `users_attributes` et `groups_attributes` ; `(uidNumber>=1000)` compare des entiers. ⛔ `publish_nt_hash` demande un [bloc `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}), et un consommateur qui filtre sur `posixAccount` ou `posixGroup` voit moins d'entrées |
| v0.11.1 | la ligne de démarrage ne nomme que les sources d'où quelqu'un est servi : sans bloc `user`, elle ne nomme plus le fichier de configuration |
| v0.12.0 | [schémas de site]({{< relref "/authnd/schemas.md" >}}) : `schema_files` (`.schema` OpenLDAP et LDIF cn=config, tels que publiés ; une redéfinition est refusée, même identique, comme le fait slapd) et un bloc `schema { }` ; classes auxiliaires déclarées par source avec `object_classes`, validées au démarrage et publiées avec leurs superclasses ; `check` rapporte les fichiers, les déclarations, les classes retirées à une personne faute d'un MUST, et les groupes sur lesquels deux sources sont en désaccord. ⛔ Compilée avec Go 1.27.3 : les binaires de la v0.11.1 (Go 1.27.2) sont touchés par GO-2026-6809 |

### authn-bridge {#authn-bridge}

| | |
|---|---|
| v0.1.0 | un fournisseur OpenID Connect devant une fédération SAML |
| v0.2.0 | l'autorisation d'appareil (device grant), les certificats SSH, les mots de passe d'application, OpenPubkey |
| v0.3.0 | une API d'administration (`bridge.admin.v1`), et `/healthz`, `/readyz`, `/metrics` |
| v0.4.0 | jetons d'accès ES256 |
| v0.5.0 | TLS par go-authn/servercert, partagé avec go-fileshare |
| v0.6.0 | des certificats révocables : une KRL SSH, et X.509 pour NFS avec une CRL |
| v0.7.0 | un état qui survit à un redémarrage : jetons de rafraîchissement et jetons d'accès honorés |
| v0.8.0 | un émetteur de signaux partagés (Shared Signals) : `session-revoked` CAEP |
| v0.9.0 | les correctifs d'une revue adverse de la v0.8.1 |
| v0.10.0 | des listes de révocation vérifiables n'importe où : une KRL signée, une expiration, un ETag du contenu |
| v0.10.2 | un numéro de CRL pour chaque émission ; jamais une émission datée d'avant la précédente |
| v0.11.0 | les groupes rattachés à leur fournisseur d'identité ; désactivation par identité ; une audience propre au bridge |
| v0.12.0 | une connexion en cours vit dans son cookie scellé, pas en mémoire |
| v0.13.0 | un client confidentiel peut protéger son code avec le nonce (RFC 9700 2.1.1) |
| v0.16.0 | `max_age` ne demande une nouvelle authentification que lorsque la dernière est trop ancienne |
| v0.16.3 | une seconde revue : toutes les graphies révoquées, désactivation par `sub`, pas de rejeu d'un redémarrage à l'autre |
| v0.17.0 | clés WireGuard, enregistrées par les personnes et listées pour une passerelle |
| v0.18.0 | un jeton d'identité (ID token) sans les revendications de la personne ; go-authn/saml v0.4.0 |
| v0.19.0 | le profil de l'AC SSH EuroHPC, activable par client |
| v0.19.3 | binaires de version, `SHA256SUMS` et provenance de compilation à chaque étiquette |
| v0.20.0 | la commande s'appelle `authn-bridge` ; une unité systemd durcie et un guide d'installation |
| v0.20.1 | des commentaires et un message de refus qui n'étaient plus vrais ; le README dit tout ce que `RevokePerson` révoque |
| v0.21.0 | [les indicateurs de ressource de la RFC 8707]({{< relref "/authn-bridge/resources.md" >}}) : un client dont l'`audience` nomme plusieurs serveurs de ressources peut demander un jeton adressé à un seul. Étiquetée une heure avant la v0.20.1, qui les contient aussi, et sans les corrections de la v0.20.1 |
| v0.21.1 | golang.org/x/net v0.60.0, pour ses avis de sécurité HTTP/2, et Go 1.27.2 ; de nouveau les corrections de la v0.20.1 ; des domaines d'exemple aux noms de la RFC 2606 |
| v0.22.0 | le jeton d'accès ne porte plus `auth_time` ni `acr` (le jeton d'identité, si), pour qu'un jeton ES256 tienne dans les 1023 caractères d'OpenSSH jusqu'au 99e centile des scopes de RENATER |
| v0.22.1 | `resource` peut être répété au point de terminaison d'autorisation, pour une autorisation bornée à plusieurs serveurs ; refusé à `device_authorization` au lieu d'être ignoré ([indicateurs de ressource]({{< relref "/authn-bridge/resources.md" >}})) |
| v0.23.0 | `access_token_groups = false` : un client dont les jetons sont collés dans ssh ne porte aucun groupe ([jetons]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})) |
| v0.23.1 | dépendances seulement : go-jose/v4 v4.1.6, golang.org/x/crypto v0.58.0, golang.org/x/net v0.61.0 ; go-authn/directory v0.12.0, revocation v0.6.3, saml v0.4.1, servercert v0.5.1, sshcert v0.1.6 |

### authn-revokd {#authn-revokd}

| | |
|---|---|
| v0.1.0 | des listes de révocation signées et à expiration : le protocole, la bibliothèque, et revokd (agent et miroir) |
| v0.2.0 | les correctifs d'une revue adverse |
| v0.2.1 | la liste de chaque AC fusionnée avec ses propres révocations de clés ; la signature d'une CRL vérifiée avant son analyse |
| v0.3.0 | révocations de clés délimitées ; refus en cas de doute par AC ; le propriétaire du répertoire d'état vérifié |
| v0.5.0 | binaires de version, `SHA256SUMS` et provenance de compilation à chaque étiquette |
| v0.6.0 | la commande s'appelle `authn-revokd` ; des unités systemd et un guide d'installation ; `SIGHUP` synchronise immédiatement |
| v0.6.1 | `-version` écrit sur la sortie standard |
| v0.6.2 | `-once` distingue une récupération échouée d'une liste expirée ; une liste signée par une autre clé n'est plus appelée une concurrence ; `-help` sort avec 0 |
| v0.6.3 | des domaines d'exemple aux noms de la RFC 2606, dans les exemples et la documentation ; aucun changement de comportement |
| v0.6.4 | dépendances seulement : golang.org/x/crypto v0.58.0 |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | l'extension de délégation de domaine, et un `sshcert-authorize` qui refuse en cas de doute |
| v0.1.2 | binaires de version, `SHA256SUMS` et provenance de compilation à chaque étiquette |
| v0.1.4 | la publication vérifie les informations de compilation de chaque binaire |
| v0.1.5 | `-version` affiche la version du module d'une compilation `go install`, et non `dev` |
| v0.1.6 | des domaines d'exemple aux noms de la RFC 2606, dans la documentation ; aucun changement de comportement |
| v0.1.7 | dépendances seulement : golang.org/x/crypto v0.58.0 |

### Les bibliothèques {#the-libraries}

Les versions des bibliothèques pour lesquelles cette version de la
documentation a été faite ; la page de chaque bibliothèque dit ce qu'ont
changé les précédentes.

| | |
|---|---|
| directory v0.13.0 | [les attributs]({{< relref "/libraries/directory.md#attributes" >}}) : ce qui décrit quelqu'un sans rien prouver, à part des identifiants, avec les noms qui ne peuvent jamais en être un ; `attributes` dans les blocs `user` et `group`, les requêtes `users_attributes` et `groups_attributes`, les `attributes` et `group_attributes` de ldapdir |
| directory v0.14.0 | ⛔ les [valeurs par défaut]({{< relref "/libraries/directory.md#ldapdir-defaults" >}}) de ldapdir lisent les personnes `account` et `uidObject` et les groupes `groupOfNames`, ce qui élargit ce que donne l'annuaire d'un établissement ; un DN `member` ne correspond qu'à une personne que la source a importée |
| directory v0.15.0 | [classes d'objet]({{< relref "/libraries/directory.md#object-classes" >}}), déclarées et jamais déduites : `object_classes` et `group_object_classes` dans les blocs `users`, `object_classes` dans les blocs `user` et `group`, `WithObjectClasses` pour sqldir et `Config.ObjectClasses` pour ldapdir ; la première source qui déclare les classes d'un groupe décide ; `sqldir.ClosesDB` |
| kdc v0.4.3 | dépendances seulement : go-authn/directory v0.12.0 comme minimum |
| keyfactor v0.4.2 | dépendances seulement : go-authn/fido v0.6.2 et golang.org/x/crypto v0.58.0 comme minimums |
| krb5 v0.3.1 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |
| krl v0.6.1 | dépendances seulement : golang.org/x/crypto v0.58.0 ; testée avec Go 1.27.2 |
| ldap v0.8.0 | [le paquet `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) et `Server.Schema` : `cn=Subschema` (RFC 4512 §4.2), `Validate`, les règles de correspondance de la RFC 4517 ; `uidNumber` et `gidNumber` s'ordonnent comme des entiers ; une recherche paginée s'en tient aux attributs demandés |
| ldap v0.9.0 | [les schémas en HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}) : le paquet `schema/hclschema` et la commande `ldapschema` (`to-hcl`, `to-schema`, `check`) entre `.schema` d'OpenLDAP, LDIF cn=config et HCL2 ; les lecteurs lisent les fichiers comme slapd ; les règles de contenu et de structure DIT, les formes de noms, `include` et `X-SUBST` ne sont pas gérés |
| oidc v0.4.1 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |
| servercert v0.5.2 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |
| totp v0.4.2 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |
| wireguard v0.1.1 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |

## Pas encore implémenté {#not-implemented-yet}

- **Les écritures par LDAP**, au-delà d'une personne qui change son propre mot de passe. authnd
  répond à une modification de son propre `userPassword` et à l'opération de modification de mot de passe
  de la RFC 3062 (ce qu'envoie `ldappasswd`), toutes deux uniquement avec le mot de passe actuel, et
  à rien d'autre : add, delete et modifyDN existent dans go-authn/ldap et ne sont
  délibérément pas branchés (`server.go`). La bibliothèque porte une modification sous forme de liste
  ordonnée (RFC 4511 4.6) et répond aux contrôles de lecture d'entrée (RFC 4527), donc
  la forme est là ; ce qui manque, c'est la politique de qui peut écrire quoi.
- **Un second facteur dans Kerberos** : la pré-authentification OTP (RFC 6560) dans
  FAST (RFC 6113). Tant qu'elle n'existe pas, un bloc `kerberos` et un bloc `mfa`
  ne peuvent pas être configurés ensemble.
- **RC4-HMAC** : le royaume n'émet que aes256-cts-hmac-sha1-96, donc une personne
  connue uniquement par une empreinte NT ne peut pas recevoir de ticket. C'est un choix (RC4 est
  déprécié par la RFC 8429), pas une lacune en attente d'être comblée.
