---
title: "Varios servidores de recursos: un token para uno a la vez"
linkTitle: "Indicadores de recurso"
weight: 45
description: "Los indicadores de recurso del RFC 8707 en authn-bridge: un cliente cuya audience nombra varios servidores de recursos pide un token de acceso dirigido a uno de ellos."
tags: [authn-bridge, oidc, tokens, rfc8707]
---

Un cliente cuya `audience` nombra varios servidores de recursos, como un portal
delante de varios servidores de ficheros, recibe tokens de acceso dirigidos a
**todos** ellos. Cualquiera de esos servidores puede entonces tomar un token que
recibió y presentarlo a los demás: por eso, dice el RFC 8707 §3, conviene
restringir la audiencia. Desde la v0.21.0, el cliente puede pedir, con el
parámetro `resource` del RFC 8707, un token dirigido a **uno solo** de ellos.
Esta página describe la v0.23.0; lo que la v0.22.0 hacía de otro modo está
[al final](#departures).

Sin `resource`, nada cambia: el token de acceso es para toda la `audience` del
cliente, como describe [la página de tokens]({{< relref "/authn-bridge/tokens.md#the-access-token" >}}).

## El cliente {#the-client}

No hay nada que activar. Cada URI de la `audience` del cliente puede pedirse. Los
ejemplos siguientes usan un cliente confidencial con tokens de actualización, y
un cliente de dispositivo con la misma audiencia:

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

`check` lista la audiencia y no dice nada más de ella. En particular, no dice qué
entradas pueden pedirse: solo puede pedirse una **URI absoluta sin fragmento**. Un
nombre lógico como `fileshare`, o una URI con `#`, se acepta en `audience` y sigue
yendo al token cuando no se nombra ningún recurso, pero un `resource` que lo
nombre se rechaza.

## Un token para un solo servidor {#a-token-for-one-server}

La persona inicia sesión como siempre (aquí, contra una federación de prueba, con
una solicitud de autorización que no nombra ningún recurso). Después, el cliente
nombra un servidor al canjear el código:

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

El `aud` es el valor pedido, exactamente como se envió, y nada más. Un servidor
que comprueba su audiencia, como hace [go-authn/oidc]({{< relref "/libraries/oidc.md" >}}),
acepta este token en París y lo rechaza en Lyon.

## Otro servidor, en la siguiente actualización {#another-server-at-the-next-refresh}

El token de actualización conserva la concesión entera (RFC 8707 §2.2), así que la
siguiente actualización puede pedir otro servidor:

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

El valor de `scope` es el mismo para los dos servidores: el proveedor no lo reduce
según el recurso.

## Un servidor que el cliente no puede tener {#a-server-the-client-may-not-have}

Un recurso que no está en la `audience` del cliente se rechaza con
`invalid_target`:

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

**Una actualización rechazada no gasta el token de actualización.** La solicitud
se comprueba antes de consumir el token, de modo que el mismo token de
actualización sigue funcionando. Sin recurso pedido, da un token para toda la
audiencia del cliente:

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

El valor se compara con las entradas de `audience` como una cadena, sin
normalizarlo como URI. El mismo servidor sin su `/` final es otro recurso:

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

## Acotar la concesión en la solicitud de autorización {#bounding-the-grant-at-the-authorization-request}

`resource` también puede enviarse con la solicitud de autorización. Entonces
acota la concesión: el código, y los tokens de actualización que siguen, son para
ese servidor, y una solicitud de token posterior puede volver a nombrarlo, pero
nunca otro. Tras un inicio de sesión cuya solicitud de autorización llevaba
`resource=https://fs-paris.example.org/`:

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

La solicitud de autorización puede llevar **varios** valores de `resource`: es el
único parámetro que puede repetirse en ella. Cada uno se comprueba, un valor dado
dos veces cuenta una sola, y la concesión es para los servidores nombrados. Tras
un inicio de sesión cuya solicitud de autorización llevaba
`resource=https://fs-paris.example.org/` y
`resource=https://fs-lyon.example.org/`, el código da un token para ambos, y cada
actualización puede pedir cualquiera de los dos:

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

Con un bloque `state`, los recursos de la concesión se guardan con el token de
actualización, así que un reinicio no la amplía.

Un recurso que el cliente no puede tener también se rechaza en el endpoint de
autorización, como un error enviado a la URI de redirección del cliente. Uno solo
de esos valores entre otros correctos hace rechazar toda la solicitud:

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**En el endpoint de token, un recurso por solicitud.** Un token es para un
servidor, para los servidores de la concesión o para toda la `audience`; nunca
para una lista que elija la solicitud de token. Un segundo `resource` se rechaza
allí como cualquier parámetro repetido:

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

## Las reglas {#the-rules}

| | |
|---|---|
| **dónde** | `resource` lo acepta el endpoint de autorización, y el endpoint de token con las concesiones `authorization_code` y `refresh_token` |
| **cuántos** | en el endpoint de autorización, varios: cada uno se comprueba, y uno rechazado hace rechazar la solicitud. En el endpoint de token, uno: un segundo es `invalid_request` |
| **qué puede nombrarse** | una URI absoluta sin fragmento que sea, carácter por carácter, una entrada de la `audience` del cliente |
| **el `aud` del token** | el recurso nombrado en el endpoint de token; si no hay ninguno, los recursos que nombró la solicitud de autorización, en el orden dado; si no hay ninguno de los dos, toda la `audience` del cliente |
| **una actualización** | puede nombrar uno de los recursos que nombró la solicitud de autorización o, si no nombró ninguno, cualquier URI de la `audience` del cliente. El nuevo token de actualización conserva la concesión entera |
| **rechazado** | `invalid_target`, enviado a la URI de redirección en el endpoint de autorización y devuelto como error `400` por el endpoint de token. Una actualización rechazada no gasta el token de actualización |
| **otras concesiones** | `resource` con `client_credentials`, en la solicitud de autorización de dispositivo o al sondear un token de dispositivo se rechaza con `invalid_target`, no se ignora: un cliente que pidió un token para un servidor no debe recibir uno para otro. Un token de dispositivo es siempre para toda la `audience` |
| **los scopes propios del proveedor** | un token con `ssh`, `nfs`, `app_password`, `wireguard` o `wireguard_peers` es solo para el proveedor, y solo puede nombrarse el propio emisor |

El rechazo de las otras concesiones, en el endpoint de token y en la solicitud de
autorización de dispositivo:

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

## Dónde se aparta del RFC 8707 {#departures}

| RFC 8707 | authn-bridge v0.23.0 |
|---|---|
| §2: «Multiple `resource` parameters MAY be used» | en el endpoint de autorización, tal cual. En el endpoint de token, uno: un segundo `resource` es `invalid_request`, lo que permite el §3 («an authorization server may be unwilling or unable to fulfill a token request with multiple resources») |
| §2.2: el parámetro se aplica «for all grant types» | solo `authorization_code` y `refresh_token`. Con `client_credentials` o con la concesión de dispositivo se rechaza con `invalid_target`, tanto en la solicitud de autorización de dispositivo como al sondear |
| §2: el valor «SHOULD NOT include a query component» | no se comprueba. Lo que se comprueba es que el valor sea absoluto, no tenga fragmento y esté en la `audience` del cliente |
| §2: el servidor «may map from that value to a more general URI or abstract identifier» | ninguna correspondencia: el `aud` es el valor pedido, comparado con `audience` como cadena |
| §2.2: «the authorization server should downscope the scope value» para cada recurso | no se hace: el valor de `scope` es el de la concesión, sea cual sea el servidor nombrado |
| §2.1: una solicitud sin `resource` MAY procesarse «by using a predefined default resource value» | el valor por defecto es toda la `audience` del cliente |
| §2.2: una actualización puede limitarse «to those [resources] that were originally granted», y el token de actualización «is bound to the full original grant» | tal cual |

**Antes de la v0.22.1**, la v0.22.0 rechazaba un `resource` repetido en el
endpoint de autorización con una página de error, como cualquier otro parámetro
repetido, así que una concesión no podía nombrar dos servidores; y su solicitud
de autorización de dispositivo no leía `resource`, así que un dispositivo que
pedía un solo servidor recibía un token para toda la `audience`.
