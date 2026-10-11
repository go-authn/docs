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

Con `reflection = true`, contra un proveedor de prueba:

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.20.1",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-10T20:54:06.593823Z",
  "federation": {
    "metadataUrl": "file:///tmp/docs-patch-a2daf7c8/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-10-17T20:53:09Z",
    "lastRefresh": "2026-10-10T20:54:06.594642Z"
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
    "since": "2026-10-11T09:01:18.445930Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-10-12T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-11T09:01:18.498410Z",
    "until": "2026-10-12T08:00:00Z"
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
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-10-12T08:00:00Z: compromised
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
bridge_build_info{version="v0.20.1",goversion="go1.27.2",revision="d30d3b52b644c7db74c431c2a07b8d1aaeb1c0ff"} 1
bridge_start_time_seconds 1791665646
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1792270389
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1791665646
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
