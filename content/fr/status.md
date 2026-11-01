---
title: "État"
weight: 60
description: "Les versions que décrivent ces pages, ce que chaque version a ajouté, et ce qui n'est pas encore implémenté."
tags: [état, versions]
---

Ces pages sont la version **0.7** de la documentation, et décrivent :

| programme | version | module |
|---|---|---|
| authnd | **v0.15.0** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.6** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.7** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

Les versions des bibliothèques sont sur [leur propre page]({{< relref "/libraries/_index.md" >}}) ;
ldap est en **v0.12.0**, avec les règles de contenu DIT, les formes de noms et
les règles de structure DIT lues, appliquées et publiées, une `BuildError` typée
pour un schéma qui ne se construit pas, les schémas en HCL2 et le convertisseur
`ldapschema`, et directory en **v0.17.0**, avec les classes d'objet déclarées.
authnd v0.15.0 embarque ldap v0.12.0 et directory v0.17.0.
Une nouvelle version mineure de l'un des programmes ci-dessus est une nouvelle version de la documentation,
de sorte que les pages qu'une personne trouve sous `/docs/0.7/` continuent de décrire ce
qu'elle a installé ; celles des versions précédentes restent sous `/docs/0.1/`,
`/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/`, `/docs/0.5/` et `/docs/0.6/`.

{{< callout type="warning" >}}
**Mise à jour d'authnd depuis la v0.14.x : deux valeurs par défaut changent**

`max_connections` vaut `4096` (illimité auparavant) et `operation_timeout` vaut `30s`
(aucun auparavant) ; un annuaire amont en panne reçoit la réponse `unavailable` (52)
et non plus `invalidCredentials` (49). `max_connections = 0` et
`operation_timeout = "0"` redonnent l'ancien comportement. Voir
[limites et délais]({{< relref "/authnd/operations.md#limits" >}}).
{{< /callout >}}

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

{{< callout type="warning" >}}
**Sécurité : prenez authn-bridge v0.23.3 et authn-revokd v0.6.5**

Sous Go 1.27.2, `govulncheck` signale GO-2026-6809 dans les deux programmes : `Certificate.Verify` de `crypto/x509` ne rejetait pas des certificats intermédiaires compromis connus. Le correctif est dans Go 1.26.10 et 1.27.3. **Les binaires de version construits avec un Go plus ancien sont concernés.** v0.23.3 et v0.6.5 sont construits avec Go 1.27.3 et leur directive `go` vaut 1.27.3 ; `go install` bascule donc de lui-même vers la chaîne d'outils corrigée, et leurs binaires de version affichent `go1.27.3` dans `go version -m`. sshcert n'est pas concerné et n'a pas de nouvelle version.
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
| v0.12.1 | un fichier ou un bloc de schéma qui ne se construit pas est refusé à la position que porte la `BuildError` de go-authn/ldap v0.10.0, avec une colonne (`site.schema:6:` devient `site.schema:6:1:`) ; le message se termine par le genre de refus, et un doublon dit où se trouve sa première définition |
| v0.12.2 | les binaires de release sont liés avec `-ldflags="-w"` au lieu de `-s -w` : la table des symboles est conservée, donc `govulncheck -mode binary` est précis au lieu de signaler des vulnérabilités dans du code qui n'est pas lié ; environ 9 % plus gros (18,8 Mo à 20,5 Mo sur darwin/arm64) |
| v0.12.3 | go-authn/ldap v0.10.1 : les `schema_files` sont lus en temps linéaire. ⛔ Jusqu'à v0.12.2, un gros fichier de schéma fait de courtes lignes de continuation (4 Mio : environ trois minutes) bloquait le démarrage : un déni de service par un fichier qu'on ne maîtrise pas |
| v0.12.4 | go-authn/ldap v0.10.2 : les valeurs de DESC de 13 définitions de la RFC 2307 dans `cn=Subschema` (`uidNumber`, `gidNumber`, `ipHostNumber`, `ipNetworkNumber`, `ipNetmaskNumber`, `macAddress` et les classes `ipService`, `ipProtocol`, `oncRpc`, `ipHost`, `ipNetwork`, `ieee802Device`, `bootableDevice`) ne portent plus l'indentation de la mise en page de la RFC : `DESC 'An integer uniquely identifying a user in an administrative domain'`, et non `... in an         administrative domain'` |
| v0.13.0 | [règles de contenu DIT, formes de noms et règles de structure DIT]({{< relref "/authnd/schemas.md#rules" >}}) (go-authn/ldap v0.11.0) : `schema_files` et le bloc `schema { }` acceptent les trois sortes, et authnd les applique. Une règle de contenu façonne chaque entrée : une classe auxiliaire que son `AUX` ne liste pas est écartée (avec les attributs que seule elle autorisait), un attribut `NOT` est retiré, une entrée à laquelle manque un `MUST` est laissée de côté ; chaque cas est journalisé et signalé par `check`. Avec une règle de structure active, l'arbre (suffixe, `ou=people`, `ou=groups`, le RDN `uid` ou `cn`) est vérifié au démarrage et par `check`, et une violation **empêche le démarrage**, tous les refus à la fois, sans jamais répéter un secret ; une entrée qu'aucune règle ne place est laissée de côté. ⛔ Une chaîne `schema { }` qui n'est pas de l'UTF-8 valide est désormais refusée. Publier 10 000 personnes fait 416 allocations par entrée avec les règles contre 265 sans (durées mesurées sous charge, non fiables) |
| v0.13.1 | Performance seulement, avec go-authn/ldap v0.11.1 : publier 10 000 personnes (`BenchmarkPublish10k`, `-cpu 1`) fait 364 allocations par entrée avec les règles et 239 sans, contre 416 et 265 en v0.13.0, et 102,5 Mio par exécution avec les règles contre 147,5. Les durées ont été mesurées sous une charge de 10 à 16 et ne sont pas fiables |
| v0.13.2 | Performance seulement, avec go-authn/ldap v0.11.2 : `Validate` fait 12 allocations au lieu de 76 pour une entrée de dix attributs ; publier 10 000 personnes (`BenchmarkPublish10k`, `-cpu 1`) fait 128 allocations par entrée avec les règles et 85 sans, contre 364 et 239 en v0.13.1, et 54,8 Mio par exécution avec les règles contre 102,5. Durées (charge de 8 à 11) : environ 90 ms contre 158 ms avec les règles |
| v0.13.3 | Performance seulement, avec go-authn/ldap v0.11.3 : une entrée que `unmet` vient de valider n'est pas validée à nouveau par `validated` si elle n'a pas changé ; publier 10 000 personnes (`BenchmarkPublish10k`, `-cpu 1`) fait 97 allocations par entrée avec les règles et 69 sans, contre 128 et 85 en v0.13.2 (−24 % et −19 %) ; environ 66 ms et 36 ms (charge 4,8) |
| v0.13.4 | Un passage de chaos. Les groupes sont lus une fois, au démarrage, comme les personnes : une recherche sur 500 personnes et 200 groupes de 50 avec SQLite prenait 4,13 s (chaque recherche interrogeait de nouveau les groupes) et prend 1,2 ms, et une requête de groupes qui échouait pendant une recherche ne retire plus le groupe d'une réponse qui dit Success. Une source illisible au démarrage (une requête de groupes qui ne s'exécute pas, l'une de plusieurs bases hors service) refuse le démarrage et `check`. Une entrée de plus d'environ 3 Mio (une seule valeur d'attribut de 10 Mo) n'est pas publiée. La publication est construite une fois par ensemble de personnes. Tenu, avec des tests : fichiers de schéma coupés à chaque octet, base supprimée ou corrompue, lignes hostiles, connexions inactives, longueurs BER démesurées, filtres imbriqués sur 20 000 niveaux |
| v0.14.0 | Changé : v0.13.4 exigeait un redémarrage pour un changement de groupe, si bien qu'un membre retiré d'une base gardait son accès jusqu'à ce que quelqu'un redémarre authnd. v0.14.0 rétablit une révocation dans les temps. `refresh` (60 s par défaut, `0` le désactive) relit chaque source, personnes et groupes, dans un nouvel instantané construit hors du chemin de service et échangé d'un bloc ; un rafraîchissement qui échoue garde le dernier bon instantané et est journalisé une fois par série d'échecs, en nommant la source. `max_age` (non défini par défaut) fait répondre `unavailable` aux recherches, aux binds des personnes et aux changements de mot de passe dès que les données servies sont plus anciennes. Un mot de passe écrit via authnd passe par le même échange. Mesuré : un rafraîchissement de 500 personnes et 200 groupes de 50 avec SQLite coûte environ 2 s d'un cœur, et une recherche 0,5 ms (le coût du rafraîchissement est corrigé en v0.14.1) |
| v0.14.1 | Performance uniquement. Un rafraîchissement ne croît plus avec groupes × lignes d'appartenance : directory v0.16.0 lit chaque source une seule fois, en bloc. Un rafraîchissement de 500 personnes et 200 groupes de 50 avec SQLite passe de 1,87 s à 0,155 s, et celui de 10 000 personnes et 2 000 groupes de 391 s (six périodes de rafraîchissement et demie) à 1,6 s (2,7 % de la période de 60 s). Les allocations passent de 39 959 235 à 3 095 482 et de 6 373 736 235 à 31 198 460. Les durées ont été mesurées sous une charge de 17 à 67 et sont indicatives ; les nombres d'allocations sont exacts |
| v0.15.0 | Disponibilité et sécurité, avec go-authn/ldap v0.12.0 et go-authn/directory v0.17.0. ⛔ **Deux valeurs par défaut changent** : `max_connections` vaut `4096` (illimité auparavant) et `operation_timeout` vaut `30s` (aucun auparavant). Nouveau, facultatif : `max_connections_per_ip` et `startup_timeout` (`60s`) ; [`check` affiche les limites]({{< relref "/authnd/operations.md#limits" >}}). Une connexion au-delà du plafond reçoit `busy` et est fermée ; une opération qui dépasse l'échéance reçoit `timeLimitExceeded`, même si son gestionnaire est bloqué. Une panne amont pendant une liaison (liaison simple, changement de mot de passe, facteur mot de passe de `mfa`) donne `unavailable` (52), jamais `invalidCredentials` (49) ; un mauvais mot de passe donne toujours 49. Un démarrage face à une source lente échoue après `startup_timeout`, en nommant l'étape et la source. [Le certificat TLS est relu]({{< relref "/authnd/tls.md#renewal" >}}) quand `cert_file` ou `key_file` changent (premier handshake après 5 s, et sur `SIGHUP`) ; une paire qui ne se charge pas garde le certificat servi et est journalisée une fois. Les nombres d'allocations sont dans les bibliothèques ci-dessous ; temps réel non mesuré (charge 21 au départ) |

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
| v0.23.2 | sécurité : go-authn/oidc v0.4.2, qui refuse un `nbf` hors de l'intervalle int64 (un jeton pas encore valide était accepté) et une clé RSA avec `e = 0` (elle était analysée) ; go-authn/wireguard v0.1.2 |
| v0.23.3 | construit avec Go 1.27.3, pour GO-2026-6809 (`crypto/x509` : `Certificate.Verify` ne rejetait pas des certificats intermédiaires compromis connus) ; la directive `go` vaut 1.27.3 ; aucun changement de comportement |
| v0.23.4 | les binaires de release sont liés avec `-w` au lieu de `-s -w`, la table des symboles est donc conservée pour un `govulncheck -mode binary` précis ; aucun changement de comportement |
| v0.23.6 | une passe d'audit, de fuzzing et de chaos, avec go-authn/saml v0.5.1 ; aucune clé de configuration ajoutée ou modifiée. [Les métadonnées sont rafraîchies à temps]({{< relref "/authn-bridge/federation.md#refreshing-it" >}}) : jamais programmées au-delà de la moitié du `validUntil` restant, et, sans métadonnées valides, retentées après une minute puis à intervalle doublé jusqu'à une heure, si bien qu'un rafraîchissement échoué près de l'expiration ne laisse plus le fournisseur sans IdP jusqu'à douze heures. La clé de rejeu d'assertion est stockée sous forme de SHA-256 : un `entityID` d'IdP long faisait refuser l'écriture par PostgreSQL et MySQL et bloquait la base d'état. L'horloge peut différer de celle d'un IdP de trois minutes ; une heure est refusée avec une page 400. [Ce qui est testé]({{< relref "/authn-bridge/federation.md#tested" >}}) : l'enveloppement de signature XSW1 à XSW8, CVE-2017-11427, DOCTYPE, audience, destinataire, requête et destination étrangers, cinq fuzzers. Un SHA-256 par connexion coûte 0 à 2 allocations de plus (`BenchmarkReplayUse` : 0 allocation et 183 o, maintenant 2 et 326 o) ; temps réel non mesuré, charge 53 à 75 |

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
| v0.6.5 | construit avec Go 1.27.3, pour GO-2026-6809 (`crypto/x509` : `Certificate.Verify` ne rejetait pas des certificats intermédiaires compromis connus) ; la directive `go` vaut 1.27.3 ; aucun changement de comportement |
| v0.6.6 | les binaires de release sont liés avec `-w` au lieu de `-s -w`, la table des symboles est donc conservée pour un `govulncheck -mode binary` précis ; aucun changement de comportement |
| v0.6.7 | une passe d'audit, de fuzzing, de chaos et de performance ([ce que fait une synchronisation]({{< relref "/authn-revokd/configuration.md#sync" >}})). Une liste qui expire est refusée quand elle expire, pas au rafraîchissement suivant ; les sources sont récupérées en parallèle (16 au plus, deux minutes chacune) ; `on_change` est tué au bout d'une minute et relancé ; un fichier de sortie modifié dans le dos de l'agent est réécrit à la synchronisation suivante ; une source `file://` doit être un fichier ordinaire ; une erreur montre une URL sans son mot de passe, sa requête ni son fragment ; un numéro de CRL hors de `0..2^159` est refusé ; le miroir a des échéances de lecture, d'écriture et d'inactivité ; les fichiers temporaires périmés sont supprimés au démarrage. Un CRL de 100 000 entrées interrogé de nouveau : 300 138 allocations et 96 956 946 o par interrogation, maintenant 37 et 4 776 864 o (exact ; temps non mesurés, charge 53 à 65). govulncheck liste encore GO-2026-5932 (`golang.org/x/crypto/openpgp`), qui n'a pas de version corrigée et n'est pas appelé |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | l'extension de délégation de domaine, et un `sshcert-authorize` qui refuse en cas de doute |
| v0.1.2 | binaires de version, `SHA256SUMS` et provenance de compilation à chaque étiquette |
| v0.1.4 | la publication vérifie les informations de compilation de chaque binaire |
| v0.1.5 | `-version` affiche la version du module d'une compilation `go install`, et non `dev` |
| v0.1.6 | des domaines d'exemple aux noms de la RFC 2606, dans la documentation ; aucun changement de comportement |
| v0.1.7 | dépendances seulement : golang.org/x/crypto v0.58.0 |
| v0.1.8 | les binaires de release sont liés avec `-w` au lieu de `-s -w`, la table des symboles est donc conservée pour un `govulncheck -mode binary` précis ; aucun changement de comportement |
| v0.1.9 | construit avec Go 1.27.3 ; aucun changement de comportement |

### Les bibliothèques {#the-libraries}

Les versions des bibliothèques pour lesquelles cette version de la
documentation a été faite ; la page de chaque bibliothèque dit ce qu'ont
changé les précédentes.

| | |
|---|---|
| directory v0.13.0 | [les attributs]({{< relref "/libraries/directory.md#attributes" >}}) : ce qui décrit quelqu'un sans rien prouver, à part des identifiants, avec les noms qui ne peuvent jamais en être un ; `attributes` dans les blocs `user` et `group`, les requêtes `users_attributes` et `groups_attributes`, les `attributes` et `group_attributes` de ldapdir |
| directory v0.14.0 | ⛔ les [valeurs par défaut]({{< relref "/libraries/directory.md#ldapdir-defaults" >}}) de ldapdir lisent les personnes `account` et `uidObject` et les groupes `groupOfNames`, ce qui élargit ce que donne l'annuaire d'un établissement ; un DN `member` ne correspond qu'à une personne que la source a importée |
| directory v0.15.0 | [classes d'objet]({{< relref "/libraries/directory.md#object-classes" >}}), déclarées et jamais déduites : `object_classes` et `group_object_classes` dans les blocs `users`, `object_classes` dans les blocs `user` et `group`, `WithObjectClasses` pour sqldir et `Config.ObjectClasses` pour ldapdir ; la première source qui déclare les classes d'un groupe décide ; `sqldir.ClosesDB` |
| directory v0.16.0 | [chaque groupe lu une fois]({{< relref "/libraries/directory.md" >}}) : `GroupReader` et `Set.Frozen`, si bien qu'un rafraîchissement ne croît plus avec groupes fois lignes d'appartenance |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}}), avec `AsUnavailable` et `TransportFailure` : ldapdir le renvoie pour busy (51), unavailable (52), other (80), timeLimitExceeded (3), connexions coupées ou refusées et échecs de connexion ou de TLS, sur `Verify` et chaque lecture ; il n'est jamais aussi `ErrWrongPassword`, et `invalidCredentials` (49) reste ce dernier. `ldaptest.Server.FailBindsWith(code)`. Un DN de membre est associé à une personne par une seule recherche au lieu d'un balayage, avec les mêmes résultats : `ReadGroups` sur 10 000 personnes et 2 000 groupes de 50 DN alloue 13,1 Mo en 0,38 M objets au lieu de 50,6 Mo en 2,20 M, une recherche de DN 0 allocation ; le rafraîchissement entier 7,17 M allocations au lieu de 9,72 M (exact ; temps non mesurés, charge 65 à 105) |
| kdc v0.4.3 | dépendances seulement : go-authn/directory v0.12.0 comme minimum |
| kdc v0.4.5 | une passe d'audit de sécurité, de fuzzing et de chaos ([ce qu'il refuse]({{< relref "/libraries/kdc.md" >}})) : une requête pour un autre royaume reçoit `KDC_ERR_WRONG_REALM`, un annuaire illisible `KDC_ERR_SVC_UNAVAILABLE` (c'était `KDC_ERR_C_PRINCIPAL_UNKNOWN`), un TGT dont le début tombe dans `MaxSkew` dans le futur est accepté, et une panique du décodeur abandonne une requête au lieu de faire planter le processus (une seule AS-REQ ou TGS-REQ mal formée pouvait le faire planter) ; les noms de principal sont entre guillemets dans le journal. golang.org/x/net v0.62.0, go-authn/directory v0.16.1 |
| keyfactor v0.4.2 | dépendances seulement : go-authn/fido v0.6.2 et golang.org/x/crypto v0.58.0 comme minimums |
| krb5 v0.3.1 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |
| krb5 v0.3.3 | dépendances seulement : golang.org/x/net v0.62.0, golang.org/x/crypto v0.58.0 et go-uuid v1.0.4 éliminent 45 des 46 résultats de `govulncheck` dans des modules requis et non appelés ; GO-2026-5932 (`x/crypto/openpgp`) n'a pas de correctif et n'est importé par aucun module go-authn ; aucun changement d'API |
| krl v0.6.1 | dépendances seulement : golang.org/x/crypto v0.58.0 ; testée avec Go 1.27.2 |
| ldap v0.8.0 | [le paquet `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) et `Server.Schema` : `cn=Subschema` (RFC 4512 §4.2), `Validate`, les règles de correspondance de la RFC 4517 ; `uidNumber` et `gidNumber` s'ordonnent comme des entiers ; une recherche paginée s'en tient aux attributs demandés |
| ldap v0.9.0 | [les schémas en HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}) : le paquet `schema/hclschema` et la commande `ldapschema` (`to-hcl`, `to-schema`, `check`) entre `.schema` d'OpenLDAP, LDIF cn=config et HCL2 ; les lecteurs lisent les fichiers comme slapd ; les règles de contenu et de structure DIT, les formes de noms, `include` et `X-SUBST` ne sont pas gérés (la v0.11.0 gère les règles) |
| ldap v0.10.0 | [une `*schema.BuildError` typée]({{< relref "/libraries/ldap.md#build-error" >}}) pour une définition que `Build` refuse, reconnue avec `errors.As` : `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos` (fichier:ligne:colonne où la définition commence, y compris pour le LDIF replié ou en base64 et le HCL), et `Ref`, `RefOID` et `RefPos` pour l'autre définition ; chaque définition lue porte un `Pos` ; « object classes » dans un message |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) est linéaire en nombre de lignes de continuation (il était quadratique : un fichier de 4 Mio prenait environ trois minutes) et ne copie ni ne découpe plus tout le fichier pour lire sa première ligne ; `schema.Format` replie les lignes de plus de 2000 octets, que slapd et `Read` refusent ; l'analyseur strict est environ 2,6 fois plus rapide (147 allocations au lieu de 498 sur `cosine.schema`, mesuré sous charge) |
| ldap v0.10.2 | les DESC de 13 définitions de la RFC 2307 du schéma embarqué (`schema.Standard()`) tiennent sur une ligne : ils portaient l'indentation de la mise en page de la RFC, que le lecteur garde entre guillemets comme slapd, si bien que le sous-schéma publié par un serveur contenait des suites d'espaces ; un test vérifie maintenant chaque DESC embarqué et, là où le même OID est défini, le compare aux schémas `core`, `cosine`, `inetorgperson` et `nis` d'OpenLDAP |
| ldap v0.11.0 | [règles de contenu DIT, formes de noms et règles de structure DIT]({{< relref "/libraries/ldap.md#rules" >}}) (RFC 4512 §4.1.6, §4.1.7) lues dans `.schema` et LDIF, écrites par `Format`, transportées par le HCL (`dit_content_rule`, `name_form`, `dit_structure_rule`) et `ldapschema`, vérifiées par `Build`, appliquées par `Validate` (règles de contenu : AUX, MUST, MAY, NOT ; formes de noms : le RDN ; règles de structure : `GoverningStructureRule`) et publiées à `cn=Subschema` seulement quand elles existent ; `ValidateOptions{StrictAuxiliary}` donne la RFC 4512 §2.4.3. ⛔ slapd n'implémente que les règles de contenu, si bien que `Format` écrit des mots-clés `nameform` et `ditstructurerule` qu'il refuse ; une règle `OBSOLETE` est inactive là où slapd refuse l'entrée ; libldap ne sait pas lire le `SUP` d'une règle de structure. `hclschema.Decode` refuse une chaîne qui n'est pas de l'UTF-8 |
| ldap v0.11.1 | Performance seulement, aucun changement de résultat : une chaîne d'ASCII imprimable est préparée pour les règles de comparaison de chaînes (RFC 4518) avec au plus une allocation, aucune quand rien ne change, et l'analyseur de DN fait 6 allocations au lieu de 11 pour un DN de quatre RDN. Les résultats sont ceux de la v0.11.0, vérifiés contre son code sur toute chaîne d'un ou deux octets inférieurs à 0x80 et par un fuzzer différentiel |
| ldap v0.11.2 | Performance seulement, aucun changement de résultat : `Validate` fait 12 allocations pour une entrée de dix attributs au lieu de 76 (recherches sans copie en minuscules, descriptions ni découpées ni recollées, ensembles sur place au lieu de maps). Les résultats sont ceux de la v0.11.1, vérifiés contre une copie de son `Validate` sur des entrées aléatoires sous le schéma standard et un schéma à règles, et par un fuzzer différentiel |
| ldap v0.11.3 | Performance seulement, aucun changement de résultat : `GoverningStructureRule` fait 5 allocations au lieu de 12 pour un compte (il ne lit que les types du RDN), et l'analyseur de DN 3 au lieu de 6 pour un DN de quatre RDN. Les résultats sont ceux de la v0.11.2, vérifiés contre une copie de son `GoverningStructureRule` sur des entrées aléatoires et chaque règle supérieure, et par un fuzzer différentiel |
| ldap v0.12.0 | [bornes de ressources pour le serveur]({{< relref "/libraries/ldap.md" >}}) : `Server.MaxConnections` et `Server.MaxConnectionsPerIP` (0 par défaut, aucune limite ; une connexion au-delà d'un plafond reçoit une notification de déconnexion `busy` (51), RFC 4511 4.4.1, et est fermée) ; `Server.Timeout` est appliqué par le serveur, qui répond `timeLimitExceeded` (3) pour toute opération à l'échéance même si le gestionnaire est bloqué et ignore son contexte (le résultat tardif est abandonné, et la goroutine compte dans `MaxPending` et `MaxPendingAuth` jusqu'à son retour) ; le `timeLimit` de recherche du client s'applique au contexte du gestionnaire ; un `DeadlineExceeded` de gestionnaire devient le code 3 seulement quand le contexte propre de l'opération a expiré. Allocations par opération (exact) : 3 avant et après sans `Timeout` ; 10 avant et 16 maintenant avec un |
| oidc v0.4.1 | testée avec Go 1.27.2 ; ni le code ni le `go.mod` n'ont changé |
| scim v0.2.0 | [une passe d'audit, de fuzzing, de chaos et de performance]({{< relref "/libraries/scim.md#v020" >}}) : `Server.ReadTimeout` (30 s), l'interface facultative `ConditionalDeleter`, un PATCH ou PUT sans `If-Match` rejoué jusqu'à 32 fois après une course perdue au lieu de recevoir 412, le retrait par un filtre qui ne correspond à rien réussit, les clés d'un PATCH sans chemin appliquées dans l'ordre trié, `BearerAuth` accepte le schéma en toute casse, `startIndex` et `count` bornés quelle que soit la taille du mot. Une requête de liste sur 10 000 utilisateurs : une page de 100 de 789 417 à 14 952 allocations, `userName eq` de 797 979 à 90, un balayage complet de 818 847 à 361 098 (exact ; temps non mesurés, charge 65) |
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
