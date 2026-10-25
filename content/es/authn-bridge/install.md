---
title: "Instalar authn-bridge"
linkTitle: "Instalación"
weight: 10
description: "Un usuario estático, tres directorios y una unidad systemd endurecida: authn-bridge desde el binario de una versión hasta un servicio en marcha."
tags: [authn-bridge, instalación, systemd]
---

El repositorio incluye la unidad y el usuario con el que se ejecuta:
`packaging/systemd/authn-bridge.service` y
`packaging/sysusers.d/authn-bridge.conf`. Todo lo que sigue se ejecuta como root,
salvo que se indique lo contrario.

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | el binario |
| `/etc/authn-bridge/*.hcl` | la configuración, leída por orden de nombre; `root:authn-bridge`, `0750`, archivos `0640` |
| `/var/lib/authn-bridge/` | las claves, la sal de sujeto, el estado SQLite, los certificados emitidos, la lista de desactivados; `authn-bridge`, `0700` |
| `/run/authn-bridge/` | el socket de administración, cuando la configuración lo pide |

## El binario {#the-binary}

Una versión incluye `authn-bridge-<os>-<arch>` para Linux, macOS y Windows en
amd64 y arm64, un manifiesto `SHA256SUMS` y una atestación de procedencia de
compilación por binario; [verificar una descarga]({{< relref "/security/verifying-releases.md" >}})
explica cómo comprobar ambos. O compílelo, lo que registra la versión en el
binario:

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3
$ authn-bridge --version
authn-bridge version v0.23.3
```

La ruta importa: desde la v0.20.0 el programa está en `internal/app` y el
comando en `cmd/authn-bridge`, así que `go install github.com/go-authn/bridge@...`
no compila nada.

## El usuario, y por qué no es dinámico {#the-user-and-why-it-is-not-a-dynamic-one}

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

La unidad indica `User=authn-bridge`, no `DynamicUser=`. La clave de firma, la sal
de sujeto, la clave SAML y las autoridades de certificación se crean **antes** del
primer arranque, duran años y deben conservar un mismo propietario a través de
reinstalaciones y restauraciones de copias de seguridad. Un usuario dinámico
recibe su UID cuando arranca el servicio.

## Las claves {#the-keys}

Ejecute `keygen` como el usuario del servicio, para que sea propietario de lo que
escribe. Se niega a sobrescribir un archivo que ya existe:

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

En un servidor, las rutas están bajo `/var/lib/authn-bridge`, y el comando es
`runuser -u authn-bridge -- authn-bridge keygen ...`.

| opción | escribe | para |
|---|---|---|
| `--key` | una clave RSA 3072 | los tokens de ID (RS256), publicada en `/jwks` |
| `--salt` | 32 bytes aleatorios | cada `sub`, que es un HMAC bajo ella |
| `--access-token-key` | una clave P-256 | tokens de acceso firmados en ES256 en su lugar, mucho más cortos |
| `--ssh-ca` | una clave Ed25519 en formato OpenSSH | los [certificados SSH]({{< relref "/authn-bridge/certificates.md" >}}) y la firma de la KRL |
| `--x509-ca DIR` | `DIR/ca.key` (P-256) y `DIR/ca.crt`, válido diez años, longitud de ruta 0 | los certificados de cliente NFS y la CRL |

{{< callout type="warning" >}}
**Haga una copia de seguridad de la sal, y no la cambie nunca**

Una sal nueva da a cada persona un `sub` nuevo, y cada parte que confía en el
proveedor ve entonces a una persona nueva. Lo mismo ocurre si se borra al
desinstalar.
{{< /callout >}}

La clave y el certificado SAML se crean con `openssl`: son lo que registra la
federación y aquello hacia lo que cifra cada IdP. La clave debe ser RSA (los IdP
cifran hacia ella con RSA-OAEP). No es el certificado TLS, y no cambia con él.

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

El certificado de firma de los metadatos de la federación procede de la
federación, y también su huella SHA-256: tome la huella de la página web de la
federación, nunca de la misma descarga que el certificado. Consulte
[el lado de la federación]({{< relref "/authn-bridge/federation.md" >}}).

## La unidad {#the-unit}

Lo que concede, en resumen:

- `Type=exec`, `Restart=on-failure`, `RestartSec=5s`, `TimeoutStopSec=20s`.
  El proveedor cierra su escucha en menos de diez segundos tras `SIGTERM`.
- `StateDirectory=`, `RuntimeDirectory=` (ambos `0700`) y
  `ConfigurationDirectory=` (`0750`), `UMask=0077`. Con
  `ProtectSystem=strict`, todo lo demás es de solo lectura.
- Ninguna capacidad (`CapabilityBoundingSet=` y `AmbientCapabilities=` vacíos),
  `NoNewPrivileges=`, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`,
  `PrivateIPC=`, `ProtectHome=`, y protegidos el kernel, el reloj, el nombre de
  host y los grupos de control.
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`: TCP para la escucha, los
  metadatos, una CA ACME y una base de datos; un socket para la API de
  administración.
- `SystemCallFilter=@system-service`, menos `@privileged @resources`, rechazadas
  con `EPERM` en lugar de con la terminación del proceso.

Espera a `network-online.target`, porque los metadatos se descargan antes de que
el proveedor escuche.

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

La primera línea del diario es la que se muestra en
[la vista general]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}}).

### Los cambios requieren un reinicio {#changes-need-a-restart}

La configuración se lee una sola vez. La unidad no tiene `ExecReload=`, así que
`systemctl reload` se rechaza en lugar de fingir. Un `SIGHUP` (de logrotate, o por
costumbre) se captura, se registra y se ignora. Con el comportamiento por defecto
de Go mataría el proceso, y systemd lo contaría como una salida limpia que
`Restart=on-failure` no reinicia:

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

Los archivos de certificado TLS son la excepción: se releen cuando cambian.

### El puerto 443 {#port-443}

La escucha por defecto es `127.0.0.1:8080`, detrás de un proxy inverso TLS, y no
necesita ninguna capacidad. Para servir TLS por sí mismo en el puerto 443
(`cert_file` o `acme`), el proveedor necesita `CAP_NET_BIND_SERVICE` y debe salir
del espacio de nombres de usuario privado, ya que una capacidad que se tiene dentro
de él no se aplica a la red del host:

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## Actualizar, y volver atrás {#upgrading-and-going-back}

Haga primero una copia de seguridad de `/var/lib/authn-bridge`: contiene las
claves y la sal, que no se pueden volver a crear. Conserve el binario que
funciona, instale el nuevo y reinicie:

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

Volver atrás es lo mismo con `authn-bridge.previous`. Una versión más reciente
puede incluir una unidad más reciente: compárela con la suya, instálela y ejecute
`systemctl daemon-reload` antes del reinicio.

### Si viene de `bridge` {#coming-from-bridge}

La configuración no cambia; solo se han renombrado el comando y los archivos de la
versión. Cambie cada unidad, script, tarea cron y `bearer_token_command` que
ejecute `bridge`. La línea de registro y el prefijo de los errores dicen ahora
`authn-bridge`, así que una alerta que coincidía con `bridge v0.` debe coincidir
con `authn-bridge v0.`. Los nombres de las métricas (`bridge_*`), la tabla
`bridge_state` y la caché del lado del usuario (`go-authn-bridge` en el directorio
de configuración del usuario, `~/.config` en Linux) no cambian, así que
`authn-bridge token` reutiliza los inicios de sesión que `bridge` guardó en caché.
