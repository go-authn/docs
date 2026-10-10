---
title: "Jetons, mots de passe et clés"
linkTitle: "Jetons"
weight: 40
description: "Ce qu'une application obtient d'authn-bridge : jetons d'identité et jetons d'accès, l'octroi par appareil, des mots de passe d'application pour SMB et S3, et des clés WireGuard."
tags: [authn-bridge, oidc, tokens, wireguard]
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
`auth_time`, et `session_end` quand l'IdP a dit quand sa session prend fin.

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
Date: Sat, 10 Oct 2026 19:18:09 GMT
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
