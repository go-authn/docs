---
title: "La configuración"
linkTitle: "Configuración"
weight: 20
description: "Cómo se organiza la configuración HCL de authn-bridge, qué muestra check, y qué se rechaza antes de que nadie pueda iniciar sesión."
tags: [authn-bridge, configuración]
---

Un archivo HCL, o un directorio de ellos: `--config /etc/authn-bridge` lee todos los
`*.hcl` que hay allí por orden de nombre y los fusiona, y `--config` puede indicarse
más de una vez. La configuración se lee al arrancar y nunca más.

```hcl
issuer            = "https://login.example.org"       # https; compared whole by every relying party
listen            = "127.0.0.1:8080"                  # the default: plain HTTP behind a TLS proxy
signing_key_file  = "/var/lib/authn-bridge/oidc.key"  # authn-bridge keygen --key
subject_salt_file = "/var/lib/authn-bridge/salt"      # authn-bridge keygen --salt; never change it
disabled_file     = "/var/lib/authn-bridge/disabled.json"
certificates_file = "/var/lib/authn-bridge/certificates.json"

saml {
  key_file             = "/var/lib/authn-bridge/saml.key"
  cert_file            = "/var/lib/authn-bridge/saml.crt"
  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"
}

state {
  driver   = "sqlite"                                 # or postgres, mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}

client "my-app" {
  secret_file   = "/etc/authn-bridge/my-app.secret"   # absent: a public client
  redirect_uris = ["https://app.example.org/callback"]
}
```

Lo obligatorio es `issuer`, `signing_key_file`, `subject_salt_file`, un bloque
`saml` con las cinco claves de arriba, y al menos un `client`. Todo lo demás tiene un
valor por defecto o está desactivado.

## `check`, antes de un reinicio {#check-before-a-restart}

`check` lee la configuración igual que el servidor, carga todas las claves que
nombra, **obtiene los metadatos de la federación**, y dice qué se serviría:

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-11-02T11:21:58Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*Usable here* deja fuera un IdP que `saml { idps }` no enumera, y uno que la
[API de administración]({{< relref "/authn-bridge/admin.md" >}}) ha desactivado: con
la institución de arriba desactivada, la misma orden muestra
`federation    1 IdPs, 0 usable here`. Una entrada de `idps` que la federación no
enumera se rechaza aquí, aunque el servidor arrancaría con ella:

```
federation    1 IdPs, 0 usable here, valid until 2026-11-02T11:30:52Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata` muestra los metadatos SAML que hay que registrar en la
federación. Consulte [el lado de la federación]({{< relref "/authn-bridge/federation.md" >}}).

## El nivel superior {#the-top-level}

| clave | por defecto | |
|---|---|---|
| `issuer` | | el nombre del proveedor y la base de todas las URL. `https`, o `http` en un host de loopback para pruebas; sin consulta, sin fragmento; una `/` final se elimina |
| `listen` | `127.0.0.1:8080` | la escucha pública |
| `cert_file`, `key_file` | | servir TLS a partir de estos archivos, releídos cuando cambian; los dos juntos o ninguno |
| `acme` | | servir TLS con un certificado de una CA ACME en su lugar (más abajo); no junto con `cert_file` |
| `signing_key_file` | | RSA, firma los tokens de ID (RS256); una clave P-256 aquí se rechaza |
| `access_token_key_file` | la clave de firma | una clave P-256 que firma los tokens de acceso en ES256; se rechaza si es la clave de firma |
| `retired_signing_key_files` | | claves que firmaron antes: se siguen publicando en `/jwks`, nunca se usan para firmar |
| `subject_salt_file` | | al menos 32 bytes |
| `code_lifetime` | `1m` | diez minutos como máximo (RFC 6749 4.1.2) |
| `token_lifetime` | `1h` | tokens de acceso |
| `id_token_lifetime` | `5m` | tokens de ID |
| `trusted_proxies` | | direcciones o prefijos cuyo `X-Forwarded-For` se cree |
| `requests_per_minute` | `120` | inicios de sesión, concesiones de dispositivo y envíos al ACS que una dirección puede iniciar por minuto; `0` desactiva el límite |
| `disabled_file` | | dónde se guardan las personas y las instituciones desactivadas; sin él, la desactivación se rechaza |
| `certificates_file` | | cada certificado y clave WireGuard emitidos; obligatorio con `ssh_ca`, `x509_ca` o `wireguard` |

Los bloques:

| bloque | página |
|---|---|
| `saml`, `claims` | [el lado de la federación]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | más abajo, y [tokens]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | más abajo |
| `ssh_ca`, `x509_ca` | [certificados]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`, `wireguard` | [tokens]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [revocación]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`, `metrics` | [la API de administración]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | más abajo |

## Un cliente {#a-client}

| clave | por defecto | |
|---|---|---|
| `secret_file` | | el secreto del cliente, de al menos 16 caracteres; si falta, un cliente **público** |
| `redirect_uris` | | se comparan exactamente, salvo que una URI de loopback puede cambiar de puerto (RFC 8252); `http` solo en loopback |
| `audience` | el ID del cliente | a quién se dirigen sus tokens de acceso; si son varios, puede pedirse un token para uno ([RFC 8707]({{< relref "/authn-bridge/resources.md" >}})) |
| `subject` | `public` | o `pairwise`: un `sub` distinto para este cliente (OIDC Core 8.1) |
| `name` | el ID del cliente | se muestra en la página de confirmación del dispositivo |
| `device` | `false` | la concesión de dispositivo (RFC 8628); un cliente así no necesita URI de redirección |
| `refresh_lifetime` | desactivado | tokens de actualización, y cuánto tiempo después del **inicio de sesión** terminan |
| `pkce` | `required` | o `or_nonce`, solo para un cliente confidencial: un `nonce` en lugar de PKCE |
| `id_token_claims` | `false` | copiar también los claims entregados en el token de ID (opkssh lo necesita) |
| `access_token_groups` | `true` | `false` deja fuera de los tokens de acceso los grupos de la persona, para tokens que se pegan en ssh ([tokens]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})); se rechaza junto con `ssh_certificates` o `x509_certificates` |
| `ssh_certificates`, `ssh_*` | | [certificados SSH]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [certificados de cliente NFS]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | puede establecer la [contraseña de aplicación]({{< relref "/authn-bridge/tokens.md#application-passwords" >}}) de la persona |
| `wireguard_keys`, `wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`, `ssf_subject_format` | | un [receptor Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

Un cliente sin URI de redirección debe ser un cliente de dispositivo, un receptor
SSF o una pasarela WireGuard; si no, no habría nada que pudiera hacer.

## `state`: lo que un reinicio no debe olvidar {#state-what-a-restart-must-not-forget}

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

Las familias de tokens de actualización, los tokens de actualización y los
retirados, los tokens de acceso aceptados en `/userinfo` y para los certificados,
las aserciones SAML ya aceptadas y los inicios de sesión ya respondidos, los flujos
SSF y sus eventos no entregados: se escriben de inmediato en una sola tabla,
`bridge_state` (creada si falta), y se leen al arrancar. Un token de actualización
se guarda como su SHA-256, nunca tal cual. Sin el bloque viven en memoria, y un
reinicio cierra la sesión de todo el mundo.

Un inicio de sesión en curso no está en ella. Viaja en su propia cookie, sellada con
AES-256-GCM bajo una clave derivada de la sal de sujeto, así que el navegador no
puede ni leerla ni modificarla.

## `acme` {#acme}

```hcl
acme {
  accept_terms_of_service = true                     # the operator's agreement; no default
  cache_dir               = "/var/lib/authn-bridge/acme"
  email                   = "noc@example.org"
  # directory_url         = "..."                    # Let's Encrypt by default
  # eab_key_id            = "..."                    # External Account Binding (GÉANT TCS / HARICA)
  # eab_hmac_key_file     = "/etc/authn-bridge/harica-eab.key"
  # http_listen           = ":80"                    # http-01, and a redirect to https
  # directory_ca_file     = "..."                    # a private ACME CA's own TLS
}
```

El certificado es para el host del emisor. `cache_dir` contiene claves privadas, y
el proveedor se niega a arrancar sobre uno que otro usuario pudiera alcanzar o
redirigir.

## Lo que se rechaza al arrancar {#what-is-refused-at-startup}

Cada uno de estos es la salida de `authn-bridge check` sobre una configuración que
lo pedía. El servidor rechaza las mismas configuraciones: cada una se lee de la
configuración y de los archivos que nombra. El único rechazo que añade `check` es la
entrada de `idps` que la federación no enumera, [más arriba](#check-before-a-restart):
el servidor obtiene los mismos metadatos antes de escuchar, pero no contrasta
`idps` con ellos.

**Un emisor, una redirección, un secreto que se filtran:**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**Un nombre que cualquier institución podría reclamar:**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**Algo emitido que nunca podría retirarse:**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: more than a week, and a certificate lives that long on every server its revocation has not reached
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**Una escucha que no debería ser alcanzable:**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**Una configuración que dice dos veces lo mismo:**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

Los rechazos propios del perfil SSH están en [certificados]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}}),
y los de la federación en [el lado de la federación]({{< relref "/authn-bridge/federation.md#what-is-refused" >}}).
