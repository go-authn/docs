---
title: "État"
weight: 60
description: "Les versions que décrivent ces pages, ce que chaque version a ajouté, et ce qui n'est pas encore implémenté."
tags: [état, versions]
---

Ces pages sont la version **0.3** de la documentation, et décrivent :

| programme | version | module |
|---|---|---|
| authnd | **v0.10.2** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.0** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.3** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.6** | `github.com/go-authn/sshcert` |

Les versions des bibliothèques sont sur [leur propre page]({{< relref "/libraries/_index.md" >}}) ;
directory est en **v0.12.0** : `Members` répond `[]` pour un groupe vide ;
`Expand` le refuse avec `ErrEmptyGroup`.
Une nouvelle version mineure de l'un des programmes ci-dessus est une nouvelle version de la documentation,
de sorte que les pages qu'une personne trouve sous `/docs/0.3/` continuent de décrire ce
qu'elle a installé ; celles des versions précédentes restent sous `/docs/0.1/` et
`/docs/0.2/`.

## Ce que chaque version a ajouté {#what-each-release-added}

Chaque ligne est le changement pour lequel une version a été publiée. Les versions qui n'ont fait que mettre à jour
des dépendances sont omises.

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

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | l'extension de délégation de domaine, et un `sshcert-authorize` qui refuse en cas de doute |
| v0.1.2 | binaires de version, `SHA256SUMS` et provenance de compilation à chaque étiquette |
| v0.1.4 | la publication vérifie les informations de compilation de chaque binaire |
| v0.1.5 | `-version` affiche la version du module d'une compilation `go install`, et non `dev` |
| v0.1.6 | des domaines d'exemple aux noms de la RFC 2606, dans la documentation ; aucun changement de comportement |

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
