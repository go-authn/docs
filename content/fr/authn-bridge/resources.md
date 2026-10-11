---
title: "Plusieurs serveurs de ressources : un jeton pour un seul à la fois"
linkTitle: "Indicateurs de ressource"
weight: 45
description: "Les indicateurs de ressource de la RFC 8707 dans authn-bridge : un client dont l'audience nomme plusieurs serveurs de ressources demande un jeton d'accès adressé à l'un d'eux."
tags: [authn-bridge, oidc, jetons, rfc8707]
---

Un client dont l'`audience` nomme plusieurs serveurs de ressources, comme un
portail devant plusieurs serveurs de fichiers, obtient des jetons d'accès adressés
à **tous**. N'importe lequel de ces serveurs peut alors prendre un jeton qu'il a
reçu et le présenter aux autres : c'est la raison, dit la RFC 8707 §3, de
restreindre l'audience. Depuis la v0.21.0, le client peut demander, avec le
paramètre `resource` de la RFC 8707, un jeton adressé à **un seul** d'entre eux.
Cette page décrit la v0.23.0 ; ce que la v0.22.0 faisait autrement figure
[à la fin](#departures).

Sans `resource`, rien ne change : le jeton d'accès est pour toute l'`audience` du
client, comme le décrit [la page des jetons]({{< relref "/authn-bridge/tokens.md#the-access-token" >}}).

## Le client {#the-client}

Il n'y a rien à activer. Chaque URI de l'`audience` du client peut être demandée.
Les exemples ci-dessous utilisent un client confidentiel avec jetons de
rafraîchissement, et un client par appareil de même audience :

```hcl
client "portal" {
  secret_file      = "etc/portal.secret"
  redirect_uris    = ["http://127.0.0.1:9/portal"]
  audience         = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
  refresh_lifetime = "8h"
}

client "files-cli" {
  device   = true
  audience = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
}
```

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-18T15:48:27Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
client        files-cli (public, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
```

`check` liste l'audience et n'en dit pas plus. En particulier, il ne dit pas
quelles entrées peuvent être demandées : seule une **URI absolue sans fragment**
peut l'être. Un nom logique comme `fileshare`, ou une URI avec un `#`, est accepté
dans `audience` et figure toujours dans le jeton quand aucune ressource n'est
nommée, mais un `resource` qui le nomme est refusé.

## Un jeton pour un seul serveur {#a-token-for-one-server}

La personne se connecte comme d'habitude (ici, auprès d'une fédération de test,
avec une demande d'autorisation qui ne nomme aucune ressource). Le client nomme
ensuite un serveur en échangeant le code :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

L'`aud` est la valeur demandée, exactement telle qu'elle a été envoyée, et rien
d'autre. Un serveur qui vérifie son audience, comme le fait
[go-authn/oidc]({{< relref "/libraries/oidc.md" >}}), accepte ce jeton à Paris et
le refuse à Lyon.

## Un autre serveur, au rafraîchissement suivant {#another-server-at-the-next-refresh}

Le jeton de rafraîchissement garde l'autorisation entière (RFC 8707 §2.2) : le
rafraîchissement suivant peut donc demander un autre serveur :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

La valeur de `scope` est la même pour les deux serveurs : le fournisseur ne la
réduit pas selon la ressource.

## Un serveur que le client ne peut pas avoir {#a-server-the-client-may-not-have}

Une ressource absente de l'`audience` du client est refusée avec
`invalid_target` :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-nantes.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-nantes.example.org/\" is not one this client may ask a token for"
}
400
```

**Un rafraîchissement refusé ne consomme pas le jeton de rafraîchissement.** La
demande est vérifiée avant que le jeton ne soit utilisé, si bien que le même jeton
de rafraîchissement fonctionne encore. Sans ressource demandée, il donne un jeton
pour toute l'audience du client :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
```

La valeur est comparée aux entrées d'`audience` comme une chaîne, sans être
normalisée comme une URI. Le même serveur sans son `/` final est une autre
ressource :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org \
    -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-paris.example.org\" is not one this client may ask a token for"
}
400
```

## Borner l'autorisation dès la demande d'autorisation {#bounding-the-grant-at-the-authorization-request}

`resource` peut aussi accompagner la demande d'autorisation. Il borne alors
l'autorisation : le code, et les jetons de rafraîchissement qui suivent, sont
pour ce serveur, et une demande de jeton ultérieure peut le nommer à nouveau,
jamais en nommer un autre. Après une connexion dont la demande d'autorisation
portait `resource=https://fs-paris.example.org/` :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-lyon.example.org/\" was not part of the authorization"
}
400
```

La demande d'autorisation peut porter **plusieurs** valeurs de `resource` : c'est
le seul paramètre qui puisse y être répété. Chacune est vérifiée, une valeur
donnée deux fois compte une fois, et l'autorisation vaut pour les serveurs
nommés. Après une connexion dont la demande d'autorisation portait
`resource=https://fs-paris.example.org/` et
`resource=https://fs-lyon.example.org/`, le code donne un jeton pour les deux, et
chaque rafraîchissement peut demander l'un ou l'autre :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

Avec un bloc `state`, les ressources de l'autorisation sont conservées avec le
jeton de rafraîchissement : un redémarrage ne l'élargit pas.

Une ressource que le client ne peut pas avoir est refusée aussi au point de
terminaison d'autorisation, par une erreur renvoyée à l'URI de redirection du
client. Une seule valeur de ce genre parmi des valeurs correctes fait refuser
toute la demande :

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**Au point de terminaison de jeton, une ressource par requête.** Un jeton est
pour un serveur, pour les serveurs de l'autorisation, ou pour toute
l'`audience` ; jamais pour une liste choisie par la demande de jeton. Un second
`resource` y est refusé comme tout paramètre répété :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_request",
  "error_description": "resource appears more than once"
}
400
```

## Les règles {#the-rules}

| | |
|---|---|
| **où** | `resource` est accepté par le point de terminaison d'autorisation, et par le point de terminaison de jeton avec les octrois `authorization_code` et `refresh_token` |
| **combien** | au point de terminaison d'autorisation, plusieurs : chacun est vérifié, et un seul refusé fait refuser la demande. Au point de terminaison de jeton, un seul : un second donne `invalid_request` |
| **ce qui peut être nommé** | une URI absolue sans fragment qui est, caractère pour caractère, une entrée de l'`audience` du client |
| **l'`aud` du jeton** | la ressource nommée au point de terminaison de jeton ; à défaut, les ressources qu'a nommées la demande d'autorisation, dans l'ordre donné ; à défaut des deux, toute l'`audience` du client |
| **un rafraîchissement** | peut nommer l'une des ressources qu'a nommées la demande d'autorisation ou, si elle n'en nommait aucune, n'importe quelle URI de l'`audience` du client. Le nouveau jeton de rafraîchissement garde l'autorisation entière |
| **refusé** | `invalid_target`, renvoyé à l'URI de redirection au point de terminaison d'autorisation, et rendu comme une erreur `400` par le point de terminaison de jeton. Un rafraîchissement refusé ne consomme pas le jeton de rafraîchissement |
| **autres octrois** | `resource` avec `client_credentials`, dans la demande d'autorisation d'appareil ou en interrogeant pour un jeton d'appareil est refusé avec `invalid_target`, pas ignoré : un client qui a demandé un jeton pour un serveur ne doit pas en recevoir un pour un autre. Un jeton obtenu par appareil est toujours pour toute l'`audience` |
| **les portées propres au fournisseur** | un jeton portant `ssh`, `nfs`, `app_password`, `wireguard` ou `wireguard_peers` est pour le seul fournisseur, et seul l'émetteur lui-même peut être nommé |

Le refus des autres octrois, au point de terminaison de jeton et dans la demande
d'autorisation d'appareil :

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=client_credentials \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

```
$ curl -s http://127.0.0.1:28473/device_authorization -d client_id=files-cli \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

## Là où cela s'écarte de la RFC 8707 {#departures}

| RFC 8707 | authn-bridge v0.23.0 |
|---|---|
| §2 : « Multiple `resource` parameters MAY be used » | au point de terminaison d'autorisation, tel quel. Au point de terminaison de jeton, un seul : un second `resource` donne `invalid_request`, ce que permet le §3 (« an authorization server may be unwilling or unable to fulfill a token request with multiple resources ») |
| §2.2 : le paramètre s'applique « for all grant types » | seulement `authorization_code` et `refresh_token`. Avec `client_credentials` ou l'octroi par appareil, il est refusé avec `invalid_target`, dans la demande d'autorisation d'appareil comme lors de l'interrogation |
| §2 : la valeur « SHOULD NOT include a query component » | non vérifié. Ce qui est vérifié, c'est que la valeur est absolue, n'a pas de fragment, et figure dans l'`audience` du client |
| §2 : le serveur « may map from that value to a more general URI or abstract identifier » | aucune correspondance : l'`aud` est la valeur demandée, comparée à `audience` comme une chaîne |
| §2.2 : « the authorization server should downscope the scope value » pour chaque ressource | non fait : la valeur de `scope` reste celle de l'autorisation, quel que soit le serveur nommé |
| §2.1 : une demande sans `resource` MAY être traitée « by using a predefined default resource value » | la valeur par défaut est toute l'`audience` du client |
| §2.2 : un rafraîchissement peut être limité « to those [resources] that were originally granted », et le jeton de rafraîchissement « is bound to the full original grant » | tel quel |

**Avant la v0.22.1**, la v0.22.0 refusait un `resource` répété au point de
terminaison d'autorisation par une page d'erreur, comme tout autre paramètre
répété, si bien qu'une autorisation ne pouvait pas nommer deux serveurs ; et sa
demande d'autorisation d'appareil ne lisait pas `resource`, si bien qu'un
appareil qui demandait un seul serveur recevait un jeton pour toute
l'`audience`.
