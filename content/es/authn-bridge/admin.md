---
title: "La API de administración, salud y métricas"
linkTitle: "API de administración"
weight: 70
description: "Desactivar a una persona o una institución mediante la API de administración gRPC de authn-bridge, y los endpoints de salud y métricas que la acompañan."
tags: [authn-bridge, administración, grpc, métricas]
---

Ambas están desactivadas salvo que la configuración las pida, y ninguna está nunca
en la escucha pública.

```hcl
admin {
  listen = "unix:///run/authn-bridge/admin.sock"   # mode 0600
  # or over the network, mutual TLS and nothing less (loopback included):
  # listen         = "10.0.0.5:9443"
  # tls_cert_file  = "/etc/authn-bridge/admin.crt"
  # tls_key_file   = "/etc/authn-bridge/admin.key"
  # client_ca_file = "/etc/authn-bridge/operators-ca.crt"
  # reflection     = true                          # for grpcurl; off by default
}

metrics { listen = "127.0.0.1:9101" }              # /healthz /readyz /metrics

disabled_file = "/var/lib/authn-bridge/disabled.json"
```

La escucha es la de grpc-transports/control, compartida con go-fileshare. El socket
nunca es alcanzable por otro usuario, ni siquiera entre el bind y el chmod, y nunca
se le quita a una instancia que sigue en marcha. TCP sin los tres archivos TLS se
rechaza, loopback incluido, ya que cualquier usuario local puede alcanzar
`127.0.0.1`:

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

Un binario compilado con `-tags nogrpc` no tiene API de administración, y rechaza
una configuración con un bloque `admin` en lugar de arrancar sin ella.

## El servicio {#the-service}

`bridge.admin.v1.AdminService` (`proto/bridge/admin/v1/admin.proto`), con
`grpc.health.v1` a su lado, que informa `SERVING` mientras el proveedor está listo.

| | |
|---|---|
| `Status` | versión, emisor, hora de arranque; los metadatos de la federación (IdP, utilizables, válidos hasta, última actualización, último error); lo que se guarda en memoria |
| `RefreshMetadata` | obtener ahora los metadatos de la federación, e informar de cómo ha ido |
| `ListIdPs` | los IdP de la federación, tal como los muestra la lista de instituciones (`query`, `limit`, 100 por defecto) |
| `ListClients` | las partes confiantes configuradas |
| `RevokePerson` | terminar las familias de tokens de actualización de la persona, los tokens de acceso que estos obtuvieron, sus inicios de sesión y concesiones de dispositivo en curso y su contraseña de aplicación, y revocar todo lo que el almacén de certificados guarda para ella: certificados SSH y X.509 (en la próxima KRL y CRL) y claves WireGuard |
| `DisablePerson`, `EnablePerson` | rechazar a alguien aquí, al iniciar sesión y en cada token, diga lo que diga su institución, y revocar lo que tiene; opcionalmente `until` una hora |
| `DisableIdP`, `EnableIdP` | lo mismo para todas las personas por las que responde una institución; una actualización de metadatos no lo levanta |
| `ListDisabled` | quién está desactivado, por qué, por quién, desde cuándo y hasta cuándo |

Quitar un IdP de `saml { idps }` termina lo que avalaba, como lo hace
`DisableIdP` (desde la v0.23.7): un inicio de sesión nuevo se rechaza, y
también cada concesión de quien pasó por él, en el siguiente uso, con
`institution not configured`: un token de refresco (incluso tras un reinicio),
una contraseña de aplicación, una solicitud de certificado SSH. Vuelva a
poner el IdP y funcionan de nuevo; no hace falta revocar nada.

Con `reflection = true`, contra un proveedor de prueba:

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.4",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-26T11:22:17.441725Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-02T11:22:16Z",
    "lastRefresh": "2026-10-26T11:22:17.442875Z"
  },
  "counts": {}
}
```

## Desactivar {#disabling}

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.example",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-26T11:22:17.952680Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-11-27T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-26T11:21:27.038956Z",
    "until": "2026-11-27T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked` cuenta lo que terminó cada llamada (familias de actualización, tokens de
acceso, inicios de sesión, contraseñas de aplicación, certificados); aquí no había
nada vivo. Cada llamada que cambia algo se registra junto con quién la hizo: el
`uid=` del par en el socket o el `cn=` del certificado de cliente sobre TLS:

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-11-27T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**Se desactiva a una persona por quien es.** Los nombres de usuario se comparan sin
distinguir mayúsculas, como hacen eppn, uid, mail y subject-id, así que la misma
llamada con `"Alice@Univ-Example.example"` levanta lo que se estableció para
`alice@univ-example.example` (`{"wasDisabled": true}`). La entrada registra también la
identidad estable de todas las personas conocidas con ese nombre, de modo que otra
grafía procedente de su IdP no le permite volver a entrar. Un nombre sin `@` se
compara también como un `sub`, para una persona cuyo IdP no entrega ningún nombre de
usuario.

La entrada se registra **antes** de revocar nada, así que una concesión que compite
con la revocación se encuentra con la entrada.

**Los nombres pliegan solo las letras ASCII** (desde la v0.23.8). La lista de desactivados, los principales de certificado y el subject-id comparan los nombres de usuario con `ASCIILower` de go-authn/oidc, así que un signo Kelvin (U+212A) no es una "k": `kate` y su grafía con un signo Kelvin son dos personas, con dos entradas de desactivación y dos principales de certificado. Desactivar a una no desactiva a la otra.

**La desactivación se guarda en `disabled_file`, y se rechaza sin él.** A alguien
desactivado hasta el próximo reinicio lo dejaría volver a entrar el próximo
despliegue:

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

Un archivo que no se puede leer impide que el proveedor arranque, por la misma
razón. Una institución desactivada cuenta como no utilizable en `Status`, `ListIdPs`
y [`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}}).

Lo que la desactivación alcanza más allá del proveedor se explica en
[revocación]({{< relref "/authn-bridge/revocation.md" >}}): la KRL y la CRL para los
certificados, Shared Signals para los tokens. Una contraseña de aplicación eliminada
aquí deja de funcionar en go-fileshare la próxima vez que este lee su directorio;
llame a su `ReloadDirectory` después de `DisablePerson` para que el efecto sea
inmediato.

{{< callout type="warning" >}}
**Lo que `RevokePerson` no puede terminar**

Un token de acceso ya entregado es una declaración firmada que un servidor de
recursos comprueba por su cuenta, válida allí hasta que caduca (una hora por
defecto). Un certificado SSH ya emitido dura lo que su validez salvo que el
servidor lea la KRL, y por eso ambos son cortos.
{{< /callout >}}

## Avisos de eliminación de passkeys {#passkey-removal-notices}

Con un [bloque `mail`]({{< relref "/authn-bridge/configuration.md#mail" >}}) (desde
la v0.32.0), una cuenta local recibe un aviso, en su propia dirección, cuando se
pide o se cancela la eliminación de una passkey, de modo que quien robe una clave no
pueda cancelar en silencio la eliminación del propietario. Afecta **solo a las
cuentas locales**, y el aviso es un correo por cuenta y por `window` (10 minutos por
defecto): los eventos que llegan entretanto se reúnen en un solo resumen. Lo que ve
un operador depende del evento:

- **Una petición de eliminación cuyo aviso no puede enviarse queda pendiente.** No se
  ejecuta al terminar su plazo. El bridge reintenta (5 intentos, con una pausa
  creciente), luego registra `GAVE UP` bien visible; un reinicio la reanuda, y
  también el siguiente evento. Entretanto la clave sigue funcionando, como antes. El
  registro lleva `notice_pending` hasta que un aviso se ha entregado.
- **Una cancelación se aplica aunque su correo falle.** El fallo se registra
  (`mailing <login> failed`) y se muestra en la página de la cuenta, que dice que el
  aviso no pudo enviarse.
- **Una cuenta sin dirección utilizable** no se bloquea: su eliminación sigue como
  sin bloque `mail`, el registro dice `<login> has no usable mail address ...
  nobody is told`, y la página de la cuenta lo dice.

Sin bloque `mail`, nada cambia.

## El registro y las cuentas locales {#journal-and-local-accounts}

Desde la v0.37.0, cada inicio de sesión correcto deja una línea en el
registro, y ninguna contiene un secreto: ni código, ni token, ni aserción, ni
dirección de correo, ni nombre, ni grupo.

```text
login: <username> via <idp entityID> for <client_id> from <address>
login: <login> via <issuer>/local with passkey <8 hex> for <client_id> from <address>
account: <username> confirmed through <idp entityID> from <address>
account: audit: <login> stepup <16 hex> from <address>
token: authorization_code issued to <client_id> for <username>
token: refresh_token issued to <client_id> for <username>
```

Las dos primeras son un inicio de sesión en el punto de autorización, a través
de una institución y con una passkey local (`<8 hex>` es el ID de la passkey,
tal como lo imprime `local: <login> enrolled a passkey (<8 hex>)`). Las dos
siguientes son el inicio de sesión en la página de la cuenta, a través de una
institución y con una passkey. Las dos últimas son los tokens entregados a un
cliente.

Ejecute `authn-bridge local-account …` como **root** cuando el directorio de
cuentas es `root:authn-bridge` 0750 y el archivo 0640, la disposición
documentada: el comando reemplaza el archivo mediante uno temporal contiguo, y
como `authn-bridge` falla con `open /etc/authn-bridge-local/.accounts-NNN:
permission denied`. Conserva el propietario y el modo del archivo. Por SSH,
`ssh host sudo authn-bridge local-account … --name "Dos palabras"` necesita una
capa más de comillas (`--name '"Dos palabras"'`), porque ssh une sus argumentos
en una sola cadena que el shell remoto vuelve a dividir.

## Qué cuentas acepta un cliente {#client-accounts}

Desde la v0.38.0, un bloque `client` puede aceptar un solo tipo de persona:

```hcl
client "forgejo" {
  secret_file   = "/etc/authn-bridge/forgejo.secret"
  redirect_uris = ["https://git.example.org/user/oauth2/bridge/callback"]
  accounts      = ["local"]   # "local", "federated", or both (the default)
}
```

`accounts = ["local"]` es para un servicio que quiere una llave de hardware: se
rechaza a una persona de una institución SAML. La regla se aplica en todo lugar
donde se concede o se usa un permiso, no solo donde se ofrece el inicio de
sesión. El punto de autorización envía a la persona al único camino que el
cliente acepta (`prompt=none` para un cliente solo de cuentas locales responde
`login_required`); el paso de la federación, el paso de la passkey y el final
del inicio de sesión rechazan cada uno un inicio de sesión del otro tipo; el
canje del código, una renovación y una consulta de dispositivo rechazan a una
persona del otro tipo, de modo que un permiso obtenido antes de escribir la
restricción termina con ella. La respuesta es `access_denied`, en el URI de
redirección del cliente durante un inicio de sesión y en el punto de tokens
después. `authn-bridge check` muestra la restricción en la línea del cliente,
`local` exige un bloque `local`, y `bridge_logins_total{result="wrong_account_kind"}`
cuenta los rechazos. El diario dice por qué:

```text
login: <username> via <idp entityID> refused for <client_id>: this client takes local accounts only
token: account kind not accepted by this client: <why> (<username> via <idp> for <client_id>)
```

Límite conocido: los puntos de certificados (SSH, X.509, Kerberos, WireGuard) no
están ligados a ningún cliente, por lo que `accounts` no se aplica a ellos.

## Administradores que invitan desde la web {#web-invitations}

Desde la v0.39.0, un administrador puede invitar una cuenta local en
`/account/invite` (login, dirección de correo, nombre opcional), sin shell en el
host. Es la misma invitación que la de la línea de comandos, y el enlace se
envía solo por correo, a la persona invitada. Los administradores se nombran en
el bloque `local`, con los modelos de autenticador que pueden usar:

```hcl
local {
  admins        = ["alice"]
  admin_aaguids = ["9dd8d593-2213-438a-97f8-d6b813d51c27"]
  mds_dir       = "/var/lib/authn-bridge/mds"
}
```

La página exige un bloque `mail`, una aserción con verificación del usuario de
tres minutos como máximo y un token CSRF; cada administrador puede invitar diez
cuentas por hora. El modelo de la passkey de un administrador debe estar
**probado**, no declarado: el registro pide al navegador una atestación directa,
go-authn/webauthn v0.5.0 la verifica (una declaración `packed` con cadena `x5c`
cuyo certificado lleva la extensión `id-fido-gen-ce-aaguid`, igual al AAGUID del
autenticador; `self` y `none` se verifican pero no prueban ningún modelo, y un
certificado sin esa extensión tampoco), y el modelo se
contrasta con los metadatos FIDO MDS3, mediante `mds` de go-authn/fido v0.16.0.
Solo entonces el bridge registra el modelo, y la página no lee nada más. Un
modelo que los metadatos declaren después revocado o comprometido deja de abrir
la página. Una clave registrada sin modelo probado sigue permitiendo iniciar
sesión; no abre nada.

Los metadatos se guardan en `mds_dir`, opcional, que por defecto es
`/var/lib/authn-bridge/mds`, debe ser una ruta absoluta y se rechaza sin
`admins`. Una goroutine en segundo plano los descarga, nunca una petición. El
host necesita:

- un directorio donde el servicio pueda escribir (`mds_dir`; una ruta distinta
  de la predeterminada debe figurar en los `ReadWritePaths=` de la unidad);
- HTTPS saliente hacia `mds3.fidoalliance.org` y HTTP simple saliente hacia los
  puntos de distribución de CRL de sus certificados;
- un reloj correcto.

El servicio arranca sin los metadatos y reintenta; hasta que lleguen, ninguna
clave de administrador queda probada y la página rechaza.

**Volver a registrar la clave de un administrador.** Una clave registrada antes
de la v0.39.0 no tiene atestación verificada. Para cada administrador: iniciar
sesión con la clave existente, abrir `/account`, confirmar con la clave y
añadir una passkey con el autenticador permitido (por ejemplo la YubiKey Bio),
aceptando la petición del navegador de compartir su marca y modelo. La
respuesta debe decir `attested: true`; entonces `/account/invite` funciona.
Después, eliminar la clave antigua.

## Salud y métricas {#health-and-metrics}

Los de go-net-health/endpoint, como en go-fileshare, en la escucha `metrics`, que no
debe ser la pública (una configuración que la hace pública se rechaza):

| | |
|---|---|
| `/healthz` | activo mientras el proceso responde |
| `/readyz` | listo mientras los metadatos de la federación están cargados y dentro de su `validUntil`, y ninguna revocación espera llegar a la base de datos de estado |
| `/metrics` | texto Prometheus, familias `bridge_*` |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.23.4",goversion="go1.27.3",revision="6e0156cb516ace9091d4070c425258febc48f6ee"} 1
bridge_start_time_seconds 1793013737
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793618536
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1793013737
bridge_metadata_refreshes_total{result="failed"} 0
bridge_metadata_refreshes_total{result="ok"} 1
bridge_logins_in_progress 0
bridge_devices_waiting 0
bridge_refresh_families 0
bridge_access_tokens 0
bridge_disabled{kind="idp"} 0
bridge_disabled{kind="person"} 0
bridge_ssh_certificates_total 0
bridge_x509_certificates_total 0
```

Los contadores de inicios de sesión por resultado (`bridge_logins_total`), de tokens
por concesión (`bridge_tokens_issued_total`) y de contraseñas de aplicación
(`bridge_app_passwords_total`) solo aparecen cuando han contado algo. **Ninguna etiqueta nombra a una
persona ni a una institución**: qué universidades tienen personas que usan el
servicio, y cuándo, no le corresponde publicarlo al proveedor.
Alerte sobre `bridge_metadata_valid_until_timestamp_seconds` antes de que se alcance
el instante que indica: pasado ese momento, nadie puede iniciar sesión.
