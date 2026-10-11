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

Sin `resource`, nada cambia: el token de acceso es para toda la `audience` del
cliente, como describe [la página de tokens]({{< relref "/authn-bridge/tokens.md#the-access-token" >}}).

## El cliente {#the-client}

No hay nada que activar. Cada URI de la `audience` del cliente puede pedirse:

```hcl
client "portal" {
  secret_file      = "etc/portal.secret"
  redirect_uris    = ["http://127.0.0.1:9/portal"]
  audience         = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
  refresh_lifetime = "8h"
}
```

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-18T10:46:00Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
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

Con un bloque `state`, los recursos de la concesión se guardan con el token de
actualización, así que un reinicio no la amplía.

Un recurso que el cliente no puede tener también se rechaza en el endpoint de
autorización, como un error enviado a la URI de redirección del cliente:

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**Un recurso por solicitud, en ambos endpoints.** Todo parámetro enviado dos veces
se rechaza, `resource` incluido. En el endpoint de token, la respuesta es
`invalid_request`. En el endpoint de autorización es una página de error, y el
cliente no es redirigido:

```
$ curl -s -o page.html -w "%{http_code}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-lyon.example.org/
400
$ grep -o "<p>.*</p>" page.html
<p>The parameter resource appears more than once.</p>
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

Por tanto, no puede pedirse una concesión para dos de los servidores del cliente
sin incluirlos todos. Un token para más de un servidor es toda la `audience`, y se
pide sin nombrar ningún recurso.

## Las reglas {#the-rules}

| | |
|---|---|
| **dónde** | `resource` lo acepta el endpoint de autorización, y el endpoint de token con las concesiones `authorization_code` y `refresh_token` |
| **cuántos** | uno por solicitud. Enviado dos veces, se rechaza como cualquier parámetro repetido |
| **qué puede nombrarse** | una URI absoluta sin fragmento que sea, carácter por carácter, una entrada de la `audience` del cliente |
| **el `aud` del token** | el recurso nombrado en el endpoint de token; si no hay ninguno, el que nombró la solicitud de autorización; si no hay ninguno de los dos, toda la `audience` del cliente |
| **una actualización** | puede nombrar el recurso que nombró la solicitud de autorización o, si no nombró ninguno, cualquier URI de la `audience` del cliente. El nuevo token de actualización conserva la concesión entera |
| **rechazado** | `invalid_target`, enviado a la URI de redirección en el endpoint de autorización y devuelto como error `400` por el endpoint de token. Una actualización rechazada no gasta el token de actualización |
| **otras concesiones** | `resource` con `client_credentials` o con la concesión de dispositivo se rechaza con `invalid_target`, no se ignora: un cliente que pidió un token para un servidor no debe recibir uno para otro. La solicitud de autorización de dispositivo no lee `resource`, así que un token de dispositivo es siempre para toda la `audience` |
| **los scopes propios del proveedor** | un token con `ssh`, `nfs`, `app_password`, `wireguard` o `wireguard_peers` es solo para el proveedor, y solo puede nombrarse el propio emisor |

El rechazo de las otras concesiones, en el endpoint de token:

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

## Dónde se aparta del RFC 8707 {#departures}

| RFC 8707 | authn-bridge v0.22.0 |
|---|---|
| §2: «Multiple `resource` parameters MAY be used», y la figura 2 envía dos en una misma solicitud de autorización | uno por solicitud. El endpoint de autorización rechaza todo parámetro repetido, citando el RFC 6749 §3.1, `resource` incluido, y responde con una página de error. Una concesión no puede nombrar un subconjunto de dos servidores o más. El README de la v0.22.0 dice que `resource` «may be repeated» en el endpoint de autorización; el código lo rechaza |
| §3: un servidor de autorización «may be unwilling or unable to fulfill a token request with multiple resources» | permitido, y así es: en el endpoint de token, un segundo `resource` es `invalid_request` |
| §2.2: el parámetro se aplica «for all grant types» | solo `authorization_code` y `refresh_token`. Con `client_credentials` o con la concesión de dispositivo se rechaza con `invalid_target`, y la solicitud de autorización de dispositivo no lo lee |
| §2: el valor «SHOULD NOT include a query component» | no se comprueba. Lo que se comprueba es que el valor sea absoluto, no tenga fragmento y esté en la `audience` del cliente |
| §2: el servidor «may map from that value to a more general URI or abstract identifier» | ninguna correspondencia: el `aud` es el valor pedido, comparado con `audience` como cadena |
| §2.2: «the authorization server should downscope the scope value» para cada recurso | no se hace: el valor de `scope` es el de la concesión, sea cual sea el servidor nombrado |
| §2.1: una solicitud sin `resource` MAY procesarse «by using a predefined default resource value» | el valor por defecto es toda la `audience` del cliente |
| §2.2: una actualización puede limitarse «to those [resources] that were originally granted», y el token de actualización «is bound to the full original grant» | tal cual |
