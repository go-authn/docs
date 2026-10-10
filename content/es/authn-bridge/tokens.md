---
title: "Tokens, contraseñas y claves"
linkTitle: "Tokens"
weight: 40
description: "Lo que una aplicación obtiene de authn-bridge: tokens de ID y tokens de acceso, la concesión de dispositivo, contraseñas de aplicación para SMB y S3, y claves WireGuard."
tags: [authn-bridge, oidc, tokens, wireguard]
---

Cada credencial de esta página empieza con el mismo inicio de sesión en la
institución de la persona. Lo que cambia es para quién es la credencial, y cómo se
retira. Los certificados tienen [su propia página]({{< relref "/authn-bridge/certificates.md" >}}).

## Lo que publica el proveedor {#what-the-provider-publishes}

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

El flujo de código de autorización, con **PKCE S256 obligatorio para todos los
clientes**. Una petición sin `code_challenge_method` se rechaza en lugar de leerse
como S256, ya que el RFC 7636 hace de `plain` el valor por defecto. Un cliente
confidencial configurado con `pkce = "or_nonce"` puede enviar en su lugar un
`nonce` de OpenID.

## El token de ID {#the-id-token}

Para el cliente, y sobre el inicio de sesión, no sobre la persona: RS256, `aud` el
ID del cliente, `sub`, `auth_time`, `at_hash`, el `nonce` cuando la petición lo
llevaba, y `acr` cuando el IdP indicó qué contexto de autenticación usó. Duración
`id_token_lifetime`, cinco minutos por defecto.

**No contiene nada sobre la persona.** Los claims que entregan los scopes están en
`/userinfo`, como indica OIDC Core 5.4 cuando se emite un token de acceso, y
siempre se emite uno. Un cliente cuyo token de ID es en sí mismo la credencial,
como opkssh, establece `id_token_claims = true` para que se copien en él. Un token
de ID solo se emite para una petición con el scope `openid`.

| scope | entrega |
|---|---|
| `profile` | `name`, `given_name`, `family_name`, `preferred_username` |
| `email` | `email` (nunca `email_verified`) |
| `eduperson` | `eduperson_principal_name`, `eduperson_scoped_affiliation`, `eduperson_entitlement` y `entitlements`, `eduperson_assurance`, `eduperson_orcid`, `schac_home_organization`, `voperson_id` (el `subject-id` de SAML, en minúsculas) |
| `groups` | `groups` |

## El token de acceso {#the-access-token}

Para los servidores de recursos de la `audience` del cliente, como describe el
RFC 9068: firmado con `signing_key_file` (RS256) o `access_token_key_file`
(ES256), `typ: at+jwt`, válido durante `token_lifetime` (una hora por defecto).
Lleva lo que un servidor de recursos necesita para decidir sin preguntar a nadie:
`preferred_username`, `groups`, `idp` (el entity ID del IdP que lo avaló),
`scope`, `client_id`, `auth_time`, y `session_end` cuando el IdP indicó cuándo
termina su sesión.

Un token que tiene uno de los scopes propios del proveedor (`ssh`, `nfs`,
`app_password`, `wireguard`, `wireguard_peers`) va dirigido **solo al
proveedor**: su `aud` es el emisor, y esos endpoints rechazan cualquier otro. Un
token que ha recibido un servidor de recursos no se puede reutilizar aquí:

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

Un token de acceso ya entregado es una declaración firmada que un servidor de
recursos comprueba por su cuenta. Lo que [`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})
termina es todo lo que vuelve aquí con él; el servidor de recursos se entera
mediante [Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}).

## Sin navegador: la concesión de dispositivo {#without-a-browser-the-device-grant}

Un cliente WebDAV, un script o un terminal no tienen ningún navegador que enviar a
una universidad. Un cliente con `device = true` pide un código (RFC 8628), y la
persona inicia sesión en cualquier otro dispositivo:

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone` imprime un
token de acceso, iniciando sesión la primera vez y actualizándolo a partir de
entonces; es el cliente de dispositivo de golang.org/x/oauth2, no uno escrito aquí.

| | |
|---|---|
| códigos de usuario | ocho letras de `BCDFGHJKLMNPQRSTVWXZ` (sin vocales, sin dígitos), válidos diez minutos; diez códigos **erróneos** por host en ese tiempo (una dirección IPv4, un /64 IPv6), y diez veces más para el /24 o /48 que lo rodea |
| sondeo | cada cinco segundos; sondear más deprisa provoca `slow_down` |
| dispositivos en espera | 20 000 como máximo; por encima, se expulsa al más antiguo en lugar de rechazar a todos |
| tokens de actualización | rotados en cada uso, dentro de una familia cuyo final se fija en el inicio de sesión mediante `refresh_lifetime`; uno retirado que se vuelve a usar revoca la familia y los tokens de acceso obtenidos con ella |

## Contraseñas de aplicación {#application-passwords}

NTLMv2 y SigV4 prueban un secreto que el servidor ya debe tener, así que ningún
token sirve para SMB o S3. Un cliente con `app_passwords = true` permite que un
token con el scope `app_password` establezca una, generada y mostrada una sola
vez: `authn-bridge app-password --issuer ... --client files` (`--remove` la
borra).

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

La tabla se crea si no existe: `login, password, nt_hash, expires, idp`. Solo se
guarda lo que necesitan los protocolos: el hash NT para SMB, y la propia
contraseña solo cuando `store` lo pide. go-fileshare la lee con un bloque
`users "sql"`; nombre las columnas en su consulta, nunca `*`.

Desactivar a una persona elimina su contraseña; desactivar una institución elimina
las de sus personas. Una contraseña eliminada deja de funcionar en go-fileshare
cuando este vuelve a leer su directorio.

## Claves WireGuard {#wireguard-keys}

WireGuard autentica a un par por su clave pública y nada más: sin certificado, sin
caducidad, sin revocación. Por eso el proveedor guarda la respuesta a *¿de quién
es esta clave, y puede seguir conectándose?* El cliente VPN del dispositivo
registra la clave pública, por un tiempo de concesión; la clave privada nunca sale
del dispositivo; una pasarela lee las claves activas como una lista firmada solo
para ella.

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
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`, con un token del scope `wireguard`; responde con el final de la concesión |
| `DELETE /wireguard/key` | `{"public_key": "..."}`: el propietario retira una clave |
| `GET /wireguard/peers` | para el token `client_credentials` propio de la pasarela, scope `wireguard_peers`: un JWT firmado de tipo `wireguard-peers+jwt`, dirigido a esa pasarela, válido cinco minutos |

Una clave que tiene otra persona, una clave que se ha retirado y una clave de más
se rechazan con `409`. Un cliente de pasarela debe ser confidencial, y debe nombrar
clientes que tengan `wireguard_keys`. El formato de la lista, y el lado de la
pasarela, son los de go-authn/wireguard.

## OpenPubkey y opkssh {#openpubkey-and-opkssh}

opkssh convierte un token de ID en inicios de sesión SSH sin ninguna CA, y el
token que crea (un PK Token) sobrevive al token de ID que contiene. El proveedor
devuelve el `nonce` literalmente en el flujo de código y en el flujo de
dispositivo, firma en RS256, y mantiene una clave retirada **publicada** mientras
`retired_signing_key_files` la nombre, para que un PK Token firmado antes de una
rotación siga verificándose:

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

Dé a opkssh un cliente propio con `id_token_claims = true`: identifica a las
personas por los claims del PK Token, y su token de ID viaja a cada servidor en el
que inicia sesión.
