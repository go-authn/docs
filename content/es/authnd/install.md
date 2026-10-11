---
title: "Instalar authnd"
linkTitle: "Instalación"
weight: 10
description: "El binario de la versión y cómo comprobarlo, la cuenta authnd, la unidad systemd y lo que concede, y cómo actualizarlo, volver atrás y desinstalarlo."
tags: [authnd, instalación, systemd]
---

El repositorio incluye los dos archivos que necesita un host con systemd:
`packaging/sysusers.d/authnd.conf` (la cuenta) y
`packaging/systemd/authnd.service` (la unidad). Esta página explica ambos y los
pasos que los rodean. Los servicios versionados de go-pkgx están pensados para
hacer esto por usted más adelante; todavía no existen.

## El binario de la versión {#the-release-binary}

Cada etiqueta publica `authnd-<os>-<arch>` para linux, darwin y windows en amd64
y arm64 (`.exe` en windows), compilado con `CGO_ENABLED=0`, un manifiesto
`SHA256SUMS`, y una atestación de procedencia de compilación para cada binario.

```sh
version=v0.10.1
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

Deténgase si alguna de las dos comprobaciones falla. El flujo de trabajo de
publicación se niega a publicar un binario que no declare exactamente la etiqueta
con la que se publica, así que la versión es algo que se puede comparar:

```
$ authnd --version
authnd version v0.10.1
```

### Compilar solo lo que quiere {#building-only-what-you-want}

El servidor siempre está; dos etiquetas de compilación dejan fuera orígenes de
personas. `-tags nosql` elimina los tres controladores de base de datos (PostgreSQL
mediante pgx, MySQL/MariaDB, SQLite mediante modernc.org/sqlite) y el bloque
`users "sql"`; `-tags noldap` elimina el cliente LDAP y el bloque `users "ldap"`.
A una configuración que nombra un bloque con el que el binario no se compiló se le
dice así —*this binary was built without SQL support (-tags nosql)*— en lugar de
decirle que el bloque no existe. Los binarios de las versiones se compilan sin
etiquetas.

## La cuenta {#the-account}

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

Una cuenta estática de sysusers.d, **no** `DynamicUser=`. Los archivos que lee
authnd —archivos de contraseña, un DSN, una keytab, una clave TLS— son secretos que
se entregan de antemano al grupo `authnd`, y un
[cambio de contraseña]({{< relref "/authnd/passwords.md" >}}) escribe de vuelta en
ellos. Un uid dinámico no existe hasta que arranca el servicio, y un archivo que
escribiera pertenecería a un número que más tarde designa a otra persona.

Los dos archivos vienen del directorio `packaging/` de la etiqueta de la versión,
la misma versión que el binario: copie ese directorio junto al binario, desde una
copia de la etiqueta o, para v0.10.1, desde
<https://github.com/go-authn/authnd/tree/v0.10.1/packaging>.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## Lo que concede la unidad, y por qué {#what-the-unit-grants-and-why}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

El resto de la unidad es el endurecimiento habitual (`ProtectHome`, `PrivateTmp`,
`PrivateDevices`, `ProtectProc=invisible`, las protecciones del kernel y de cgroups,
`MemoryDenyWriteExecute`, `SystemCallFilter=@system-service`,
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`). Tres cosas que **deja fuera**
son deliberadas:

| | |
|---|---|
| `ExecReload=` | authnd no tiene recarga. Lee su configuración, su certificado y su keytab una sola vez; consulte [ejecutarlo]({{< relref "/authnd/operations.md" >}}) |
| `PrivateUsers=` | dentro de un espacio de nombres de usuario, `CAP_NET_BIND_SERVICE` deja de aplicarse a la red del host, y el bind al 389 se rechaza |
| `ProcSubset=pid` | oculta `/proc/sys`, donde Go lee `net/core/somaxconn`, y la cola de cada escucha cae al valor de reserva de Go, 128 |

Tampoco se fijan `IPAddressAllow=`/`IPAddressDeny=`: qué redes pueden consultar un
directorio le corresponde decirlo al sitio, en un drop-in:

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

La única capacidad es para los puertos privilegiados: LDAP 389, LDAPS 636, y
Kerberos 88 por UDP y TCP. A un PostgreSQL o un MariaDB en la misma máquina se llega
por su socket, que un sistema de archivos de solo lectura permite. El directorio de
estado, `/var/lib/authnd`, está ahí para una base de datos SQLite; authnd no guarda
ningún estado propio: los recuentos de bloqueo del segundo factor viven en memoria y
se reinician en cada reinicio.

## El directorio de configuración {#the-configuration-directory}

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

Cada archivo de su interior es `root:authnd`, modo `0640`. Los secretos van en
archivos nombrados por claves `*_file` en lugar de en línea: un archivo tiene
permisos, y una configuración que alguien pega no los tiene. Con
`ProtectSystem=strict` el servicio no puede escribir bajo `/etc`, lo cual es
correcto para la configuración e incorrecto para las contraseñas que las personas
cambian por sí mismas: deles un directorio propio:

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

Por qué ese directorio y no el archivo se explica en
[cambiar una contraseña]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}}).

| clave | por defecto | |
|---|---|---|
| `base_dn` | — (obligatorio) | la raíz del árbol, p. ej. `dc=example,dc=org`; un valor sin `=` se rechaza |
| `listen` | `127.0.0.1:3893` | una dirección. Loopback por defecto: un directorio que aparece en todas las interfaces en cuanto arranca es una decisión que alguien debería tomar a propósito. Un sitio que necesita LDAP y LDAPS ejecuta dos instancias |
| `reader "<dn>"` | ninguno | una cuenta de servicio que puede buscar; consulte [quién puede leer]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) |
| `cert_file`, `key_file`, `starttls`, `publish_nt_hash` | desactivado | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`, `group`, `users` | — | [las personas]({{< relref "/authnd/people.md" >}}); al menos un bloque `user` o `users` |
| `kerberos` | ninguno | [un reino]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | ninguno | [un segundo factor]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | ninguno | [un token en el bind]({{< relref "/authnd/tokens.md" >}}) |

Una ruta relativa en la configuración se resuelve respecto al directorio en el que
se ejecuta el proceso, no al del archivo de configuración; la unidad se ejecuta desde
`/`, así que escriba las rutas absolutas.

Antes de cada arranque:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check` se describe en [su propia página]({{< relref "/authnd/check.md" >}});
ejecutarlo como `authnd` prueba además que la cuenta puede leer todos los archivos.

## Actualizar, volver atrás, desinstalar {#upgrade-roll-back-remove}

Compruebe la configuración con el binario **nuevo** antes de que sustituya al
anterior, y conserve el anterior. El binario nuevo se instala primero junto al
anterior: eso lo hace ejecutable y lo deja donde la cuenta `authnd` puede
ejecutarlo.

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

Compare `packaging/` en la nueva etiqueta con lo que está instalado. Volver atrás es
la misma instalación a partir de `authnd.previous`, y un reinicio.

Para desinstalarlo:

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`, `/var/lib/authnd` y la cuenta `authnd` se dejan en su sitio: los dos
primeros guardan las credenciales de las personas, y a un uid que se reutiliza se le
pueden dar los archivos de otra persona. Elimínelos deliberadamente.
