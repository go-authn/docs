---
title: "Jetons, mots de passe et clés"
linkTitle: "Jetons"
weight: 40
description: "Ce qu'une application obtient d'authn-bridge : jetons d'identité et jetons d'accès, l'octroi par appareil, des mots de passe d'application pour SMB et S3, et des clés WireGuard."
tags: [authn-bridge, oidc, jetons, wireguard]
---

Chaque identifiant ici commence par la même connexion auprès de l'établissement de la personne.
Ce qui diffère, c'est à qui l'identifiant est destiné, et comment il est repris. Les
certificats ont [leur propre page]({{< relref "/authn-bridge/certificates.md" >}}).

## Ce que publie le fournisseur {#what-the-provider-publishes}

```
$ curl -s http://127.0.0.1:28473/.well-known/openid-configuration | jq .
{
  "authorization_endpoint": "http://127.0.0.1:28473/authorize",
  "authorization_response_iss_parameter_supported": true,
  "claims_parameter_supported": false,
  "claims_supported": [
    "sub",
    "iss",
    "aud",
    "exp",
    "iat",
    "auth_time",
    "nonce",
    "acr",
    "name",
    "given_name",
    "family_name",
    "preferred_username",
    "email",
    "groups",
    "eduperson_principal_name",
    "eduperson_scoped_affiliation",
    "eduperson_entitlement",
    "entitlements",
    "eduperson_assurance",
    "eduperson_orcid",
    "schac_home_organization",
    "voperson_id"
  ],
  "code_challenge_methods_supported": [
    "S256"
  ],
  "device_authorization_endpoint": "http://127.0.0.1:28473/device_authorization",
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ],
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "request_parameter_supported": false,
  "request_uri_parameter_supported": false,
  "response_modes_supported": [
    "query"
  ],
  "response_types_supported": [
    "code"
  ],
  "scopes_supported": [
    "openid",
    "profile",
    "email",
    "eduperson",
    "groups"
  ],
  "subject_types_supported": [
    "public",
    "pairwise"
  ],
  "token_endpoint": "http://127.0.0.1:28473/token",
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "none"
  ],
  "userinfo_endpoint": "http://127.0.0.1:28473/userinfo"
}
```

Le flux par code d'autorisation, avec **PKCE S256 exigé pour chaque client**. Une
requête sans `code_challenge_method` est refusée plutôt que lue comme S256,
puisque la RFC 7636 fait de `plain` la valeur par défaut. Un client confidentiel configuré
`pkce = "or_nonce"` peut envoyer à la place un `nonce` OpenID.

## Le jeton d'identité {#the-id-token}

Pour le client, et sur la connexion, pas sur la personne : RS256, `aud` l'ID
du client, `sub`, `auth_time`, `at_hash`, le `nonce` quand la requête en avait un, et
`acr` quand l'IdP a dit quel contexte d'authentification il a utilisé. Durée de vie
`id_token_lifetime`, cinq minutes par défaut.

**Rien sur la personne n'y figure.** Les revendications que les portées transmettent sont à
`/userinfo`, comme le dit OIDC Core 5.4 quand un jeton d'accès est émis, et il l'est
toujours. Un client dont le jeton d'identité est lui-même l'identifiant, comme opkssh,
définit `id_token_claims = true` pour les y faire copier. Un jeton d'identité n'est
émis que pour une requête comportant la portée `openid`.

| portée | transmet |
|---|---|
| `profile` | `name`, `given_name`, `family_name`, `preferred_username` |
| `email` | `email` (jamais `email_verified`) |
| `eduperson` | `eduperson_principal_name`, `eduperson_scoped_affiliation`, `eduperson_entitlement` et `entitlements`, `eduperson_assurance`, `eduperson_orcid`, `schac_home_organization`, `voperson_id` (le `subject-id` SAML, en minuscules) |
| `groups` | `groups` |

## Le jeton d'accès {#the-access-token}

Pour les serveurs de ressources de l'`audience` du client, comme le décrit la RFC 9068 :
signé avec `signing_key_file` (RS256) ou `access_token_key_file` (ES256),
`typ: at+jwt`, valide `token_lifetime` (une heure par défaut). Il porte ce dont un
serveur de ressources a besoin pour décider sans demander à personne : `preferred_username`,
`groups`, `idp` (l'entity ID de l'IdP qui s'est porté garant), `scope`, `client_id`,
et `session_end` quand l'IdP a dit quand sa session prend fin.
Les groupes peuvent être omis, client par client : [plus bas](#what-it-leaves-out).

Un client dont l'`audience` nomme plusieurs serveurs de ressources peut demander
un jeton adressé à l'un d'eux, avec le `resource` de la RFC 8707 : voir
[plusieurs serveurs de ressources]({{< relref "/authn-bridge/resources.md" >}}).

### Ce qu'il ne contient pas, et pourquoi {#what-it-leaves-out}

**Ni `auth_time` ni `acr`**, bien que la RFC 9068 autorise les deux. Ils restent
dans le jeton d'identité, où OIDC Core les place. Rien ne les lit dans un jeton
d'accès : ni ce fournisseur, qui retrouve un jeton par son `jti`, ni
go-fileshare. Or un jeton d'accès est aussi collé comme réponse SSH
keyboard-interactive (mccli de ssh-oidc, vérifié par motley-cue sur
`/userinfo`), et OpenSSH en lit 1023 caractères ; l'`acr` d'un IdP à lui seul,
`urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport`, en occupe
environ 90. Avant la v0.22.0, le jeton d'accès portait les deux.

La longueur d'un jeton d'accès ES256 (`access_token_key_file`) pour un eppn long
et trois entitlements AARC, mesurée par `TestES256AccessTokens` d'authn-bridge
avec un émetteur de longueur réelle, face aux longueurs des `shibmd:Scope` des
métadonnées de RENATER (743 scopes) :

| longueur du scope | | caractères |
|---|---|---|
| 13 | médiane | 885 |
| 22 | 95e centile | 945 |
| 29 | 99e centile | 992 |
| 44 | le plus long | **1092 : au-delà** |

Avant la v0.22.0, le même jeton faisait 1014 / 1074 / 1121 / 1221 caractères :
au-delà dès le 95e centile. Ce qui ne tient toujours pas, ce sont les scopes les
plus longs et surtout les groupes nombreux : chaque entitlement ajoute son URN
entière, et rien ne borne le nombre qu'un IdP en envoie. Un jeton d'accès RS256,
signé avec une clé de 3072 bits, fait environ 1150 caractères avant le moindre
groupe : un jeton destiné à SSH est donc signé en ES256. Au-delà de 1023
caractères, mccli demande à motley-cue un mot de passe à usage unique à la
place, ce que motley-cue autorise par défaut ; un jeton collé dans un `ssh`
ordinaire doit tenir.

**Aucun groupe, pour un client qui le demande** (v0.23.0). Chaque groupe
ajoute son URN entière, et rien ne borne le nombre qu'un IdP en envoie : aucune
clé ni aucun algorithme de signature ne garantit qu'un jeton portant des groupes
tienne. Un client configuré avec `access_token_groups = false` reçoit des jetons
d'accès sans les `groups` de la personne :

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
}
```

Il est fait pour ssh-oidc : oidc-agent obtient le jeton, mccli le colle comme
réponse keyboard-interactive, et motley-cue le vérifie sur `/userinfo` et y lit
les groupes. Mesuré par `TestAccessTokenWithoutGroups` d'authn-bridge, un jeton
ES256 pour une personne membre de 50 groupes, avec le scope le plus long de
RENATER (44) et un émetteur de longueur réelle, fait 732 caractères.

Face à une fédération de test, une personne membre de trois groupes se connecte
par ce client, avec le device grant :

```
$ authn-bridge token --issuer http://127.0.0.1:28473 --client oidc-agent --scope "openid eduperson groups" --cache var/tokens.json > at
To log in, open http://127.0.0.1:28473/device
and enter the code DHBT-DBZD
(or open http://127.0.0.1:28473/device?user_code=DHBT-DBZD)
$ tr -d '\n' < at | wc -c
     625
```

Le jeton nomme la personne et son IdP, et aucun groupe :

```
$ cut -d. -f2 at | tr "_-" "/+" | jq -R "@base64d | fromjson"
{
  "aud": "ssh",
  "client_id": "oidc-agent",
  "exp": 1791741018,
  "iat": 1791737418,
  "idp": "https://idp.univ-example.example/idp/shibboleth",
  "iss": "http://127.0.0.1:28473",
  "jti": "0zVsbDeAwcubhCCFXtj9Dh0u-93sDBza5sti7EmcSL8",
  "preferred_username": "alice@univ-example.example",
  "scope": "openid eduperson groups",
  "sub": "KEQ1dJYNUw8TtXF5HNbuy3EYZ3rmFMKiqaVY8RH7eLE"
}
```

`/userinfo` les sert toujours, sous `groups` (portée `groups`) et sous
`eduperson_entitlement` (portée `eduperson`) :

```
$ { printf 'Authorization: Bearer '; cat at; } > auth.hdr
$ curl -s -H @auth.hdr http://127.0.0.1:28473/userinfo | jq .
{
  "eduperson_entitlement": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "eduperson_principal_name": "alice@univ-example.example",
  "entitlements": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "groups": [
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example"
  ],
  "sub": "KEQ1dJYNUw8TtXF5HNbuy3EYZ3rmFMKiqaVY8RH7eLE"
}
```

**La valeur par défaut reste `true`.** go-fileshare, comme tout serveur de
ressources qui décide sur le seul jeton, a besoin des groupes dedans : on ne les
omet que pour un client dont les jetons vont à un serveur qui lit `/userinfo`.

**Refusé avec les certificats.** Les certificats SSH et X.509 prennent les
groupes de la personne dans le jeton d'accès : un client avec
`access_token_groups = false` et `ssh_certificates` ou `x509_certificates`
émettrait des certificats qui n'en portent aucun, et un serveur qui autorise par
groupe refuserait la personne sans que rien nulle part ne dise pourquoi. `check`,
comme le serveur au démarrage, refuse la combinaison :

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
  ssh_certificates    = true
}
```

```
$ authn-bridge check --config etc/bridge.hcl
authn-bridge: client "oidc-agent": access_token_groups = false with ssh_certificates or x509_certificates: the certificates take the groups from the access token, and would carry none -- use one client for the certificates and another for tokens pasted into ssh
$ echo $?
1
```

Les certificats ont alors leur propre client, et les jetons collés dans ssh un autre.

Un jeton portant l'une des portées propres au fournisseur (`ssh`, `nfs`,
`app_password`, `wireguard`, `wireguard_peers`) est adressé **au seul
fournisseur** : son `aud` est l'émetteur, et ces points de terminaison refusent toute autre valeur. Un jeton
qu'un serveur de ressources a reçu ne peut pas être rejoué ici :

```
$ curl -s -X POST http://127.0.0.1:28473/ssh/certificate -d x -D - -o -
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Www-Authenticate: Bearer error="invalid_token"
X-Content-Type-Options: nosniff
Date: Sun, 11 Oct 2026 09:48:07 GMT
Content-Length: 23

the token is not valid
```

Un jeton d'accès déjà distribué est une déclaration signée qu'un serveur de ressources
vérifie seul. Ce à quoi [`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})
met fin, c'est tout ce qui revient ici avec lui ; le serveur de ressources l'apprend
par [Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}).

## Sans navigateur : l'octroi par appareil {#without-a-browser-the-device-grant}

Un client WebDAV, un script, un terminal n'a pas de navigateur à envoyer vers une université. Un
client avec `device = true` demande un code (RFC 8628), et la personne se connecte
sur n'importe quel autre appareil :

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone` affiche
un jeton d'accès, en se connectant la première fois et en rafraîchissant ensuite ; c'est
le client device de golang.org/x/oauth2, pas un client écrit ici.

| | |
|---|---|
| codes utilisateur | huit lettres parmi `BCDFGHJKLMNPQRSTVWXZ` (ni voyelles, ni chiffres), valides dix minutes ; dix codes **erronés** par hôte pendant ce temps (une adresse IPv4, un /64 IPv6), et dix fois plus pour le /24 ou le /48 qui l'entoure |
| interrogation | toutes les cinq secondes ; interroger plus vite vaut `slow_down` |
| appareils en attente | 20 000 au plus ; au-delà, le plus ancien est évincé plutôt que tout le monde refusé |
| jetons de rafraîchissement | renouvelés à chaque usage, au sein d'une famille dont la fin est fixée à la connexion par `refresh_lifetime` ; un jeton retiré réutilisé révoque la famille et les jetons d'accès qu'elle a obtenus |

## Mots de passe d'application {#application-passwords}

NTLMv2 et SigV4 prouvent un secret que le serveur doit déjà détenir, donc aucun jeton ne
convient pour SMB ou S3. Un client avec `app_passwords = true` permet à un jeton de
portée `app_password` d'en définir un, généré et affiché une seule fois :
`authn-bridge app-password --issuer ... --client files` (`--remove` le supprime).

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

La table est créée si elle manque : `login, password, nt_hash, expires, idp`.
Seul ce dont les protocoles ont besoin est stocké : l'empreinte NT pour SMB, le mot de passe lui-même
seulement quand `store` le demande. go-fileshare la lit avec un bloc `users "sql"` ;
nommez les colonnes dans sa requête, jamais `*`.

Désactiver une personne supprime son mot de passe ; désactiver un établissement supprime ceux
de ses personnes. Un mot de passe supprimé cesse de fonctionner dans go-fileshare à sa prochaine lecture
de son annuaire.

## Clés WireGuard {#wireguard-keys}

WireGuard authentifie un pair par sa clé publique et rien d'autre : pas de
certificat, pas d'expiration, pas de révocation. Le fournisseur garde donc la réponse à
*à qui est cette clé, et peut-elle encore se connecter ?* Le client VPN de l'appareil
enregistre la clé publique, pour un bail ; la clé privée ne quitte jamais l'appareil ;
une passerelle lit les clés en vigueur sous la forme d'une liste signée pour elle seule.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"   # keys are recorded beside the certificates

wireguard {
  lifetime = "24h"              # the default: how long a key is listed; registering again renews it
  max_keys = 10                 # the default: devices per person
}

client "vpn" {                  # what people log in with
  device         = true
  wireguard_keys = true
}

client "vpn-gw" {               # the gateway's own client
  secret_file     = "/etc/authn-bridge/vpn-gw.secret"
  wireguard_peers = ["vpn"]     # the clients whose keys it reads
  ssf_receiver    = true        # optional: told at once when somebody is disabled
}
```

| | |
|---|---|
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`, avec un jeton de portée `wireguard` ; répond la fin du bail |
| `DELETE /wireguard/key` | `{"public_key": "..."}` : la personne propriétaire reprend une clé |
| `GET /wireguard/peers` | pour le jeton `client_credentials` propre à la passerelle, portée `wireguard_peers` : un JWT signé de type `wireguard-peers+jwt`, adressé à cette passerelle, valide cinq minutes |

Une clé que quelqu'un d'autre détient, une clé qui a été reprise, et une clé de trop sont
refusées avec `409`. Un client passerelle doit être confidentiel, et doit nommer des clients
qui ont `wireguard_keys`. Le format de la liste, et le côté passerelle, relèvent de
go-authn/wireguard.

## OpenPubkey et opkssh {#openpubkey-and-opkssh}

opkssh transforme un jeton d'identité en connexions SSH sans aucune AC, et le jeton qu'il
fabrique (un PK Token) survit au jeton d'identité qu'il contient. Le fournisseur renvoie le
`nonce` tel quel dans le flux par code et dans le flux par appareil, signe en RS256, et garde
une clé retirée **publiée** aussi longtemps que `retired_signing_key_files` la
nomme, afin qu'un PK Token signé avant une rotation se vérifie encore :

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

Donnez à opkssh un client à lui avec `id_token_claims = true` : il reconnaît les personnes
d'après les revendications du PK Token, et son jeton d'identité voyage vers chaque serveur auquel il se connecte.
