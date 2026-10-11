---
title: "Instalar authn-revokd"
linkTitle: "Instalación"
weight: 10
description: "authn-revokd como servicio systemd endurecido, o como ejecución única con un temporizador, y cómo conectar sshd y un servidor TLS a lo que escribe."
tags: [authn-revokd, instalación, systemd]
---

El repositorio incluye en `packaging/` tres unidades y una cuenta:
`authn-revokd.service` (el demonio), `authn-revokd-once.service` con
`authn-revokd-once.timer` (la alternativa), y
`sysusers.d/authn-revokd.conf`.

| ruta | qué | propietario, modo |
|---|---|---|
| `/usr/local/bin/authn-revokd` | el binario | root, `0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | la cuenta de sistema `authn-revokd` | root, `0644` |
| `/etc/systemd/system/authn-revokd.service` | el demonio | root, `0644` |
| `/etc/authn-revokd/revokd.hcl` | la configuración, el `-config` por defecto | root, `0644` |
| `/etc/authn-revokd/ca/` | las claves y los certificados de CA con los que deben estar firmadas las listas | root, `0755`; los archivos que contiene, `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`, el único lugar con escritura | authn-revokd, `0755` |
| `/var/lib/authn-revokd/state/` | `state_dir`: las copias verificadas | authn-revokd, `0700` |
| `/var/lib/authn-revokd/sshd.krl` | una salida: lo que lee `sshd` | authn-revokd, `0644` |

**Escriba las salidas en `/var/lib/authn-revokd`, y haga que los servidores apunten
allí.** Una salida se escribe junto a su nombre definitivo y se renombra encima de
él, así que su *directorio* debe permitir escritura. Hacer escribible `/etc/ssh`
permitiría a la cuenta `authn-revokd` sustituir `sshd_config`. Las salidas son
`0644`, con un chmod explícito pese a `UMask=0077`, para que `sshd` y un servidor TLS
que se ejecuta con su propio usuario puedan leerlas; el estado sigue en `0700`.

## El binario, la cuenta, la unidad {#the-binary-the-account-the-unit}

Una versión incluye `authn-revokd-<os>-<arch>` para Linux, macOS y Windows en amd64
y arm64, con `SHA256SUMS` y procedencia de compilación
([verificar una descarga]({{< relref "/security/verifying-releases.md" >}})). O bien
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.3`.

La cuenta y la unidad vienen del directorio `packaging/` de la etiqueta de la
versión, la misma versión que el binario: copie ese directorio junto al
binario, desde una copia de la etiqueta o, para v0.6.3, desde
<https://github.com/go-authn/revocation/tree/v0.6.3/packaging>.

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

La cuenta es estática, no `DynamicUser=`. authn-revokd rechaza un directorio de
estado cuyo propietario no sea su propio uid o root, y el estado debe seguir
ordenando la siguiente lista entre reinicios y actualizaciones. Con un usuario
dinámico los archivos quedarían bajo `/var/lib/private`, `0700` de root, y un
servidor TLS que se ejecuta con su propio usuario no podría leer la CRL.

## El demonio {#the-daemon}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

y a su alrededor: `User=authn-revokd`, ninguna capacidad, `NoNewPrivileges=`,
`ProtectSystem=strict` con `StateDirectory=authn-revokd` (`0755`) como único lugar
con escritura, `PrivateUsers=`, `PrivateTmp=`, `PrivateDevices=`, `PrivateIPC=`,
solo `AF_INET AF_INET6 AF_UNIX`, y las llamadas al sistema `@system-service` menos
`@privileged @resources`.

**`Restart=always`, porque sshd ignora la caducidad de la KRL.** Es *este proceso*
quien pone el archivo en modo cerrado cuando una lista caduca. Mientras está
detenido, sshd sigue leyendo el último archivo que escribió, y una revocación emitida
entretanto nunca llega. Supervise la unidad, o `/healthz` cuando el espejo está
activado.

**`systemctl reload` sincroniza en el acto.** Envía `SIGHUP`, y el agente descarga
todos los orígenes de inmediato en lugar de en el siguiente `refresh`:

```
hangup: syncing now
```

No vuelve a leer la configuración, que se lee una sola vez, al arrancar: después de
cambiar `revokd.hcl`, `systemctl restart authn-revokd`. (Antes de la v0.6.0 un
`SIGHUP` no capturado mataba el proceso, y systemd lo cuenta como una salida limpia.)

### Actívelo ANTES de conectar sshd {#enable-it-before-wiring-sshd}

{{< callout type="warning" >}}
**sshd rechaza todos los certificados cuando `RevokedKeys` nombra un archivo que no existe**

Así que arranque primero authn-revokd, y espere a que la salida esté ahí:
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl` imprime su comentario,
`authn-revokd sshd` mientras todos los orígenes están vigentes.
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

Después, en `/etc/ssh/sshd_config`:

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

y `sshd -t && systemctl reload ssh`. sshd lee `RevokedKeys` en cada autenticación,
así que no necesita recargarse cuando authn-revokd reescribe el archivo: basta con el
renombrado atómico.

### La CRL de un servidor TLS {#a-tls-servers-crl}

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

Un servidor TLS lee su CRL cuando carga su configuración, así que hay que recargarlo
cuando cambia el archivo. Una orden `on_change` se ejecuta con la cuenta
`authn-revokd`, que no puede hacer `systemctl reload nginx`: deje que systemd vigile
el archivo en su lugar, como root, con una unidad path (`PathChanged=` sobre la
salida) que arranque un `oneshot` que ejecute `systemctl reload nginx`.

## O bien: `-once`, con un temporizador {#or--once-on-a-timer}

`authn-revokd -once` sincroniza una vez y termina, con `1` cuando una lista no está
vigente o no se pudo descargar
([lo que informa `-once`]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
Las salidas se escriben en cualquier caso, y quedan en modo cerrado para sshd en
cuanto una lista caduca.

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

La ejecución única tiene la cuenta y el endurecimiento del demonio.
`TimeoutStartSec=5min` evita que una sincronización que se cuelga en un origen
sobreviva al siguiente disparo, y `RandomizedDelaySec=10s` evita que un parque de
máquinas arrancado a la vez consulte a su emisor al unísono.

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**Nunca active los dos**: las unidades entran en conflicto, así que arrancar una
detiene la otra. El demonio sigue siendo la mejor opción. Pone en modo cerrado una
lista caducada en su siguiente `refresh`, mientras que el temporizador espera a su
siguiente disparo, y solo el demonio sirve como espejo: `listen` se ignora con
`-once`. Un temporizador que deja de dispararse es un demonio que se ha detenido, así
que supervise `systemctl status authn-revokd-once`.

## Actualizar, y volver atrás {#upgrading-and-going-back}

Instale el nuevo binario junto al anterior, intercámbielos, reinicie. El estado se
conserva: las copias verificadas siguen ordenando las listas siguientes, así que ni
una actualización ni una vuelta a un binario anterior dejan entrar una lista más
antigua.

## Desinstalar {#uninstalling}

Quite **primero** `RevokedKeys` y `ssl_crl` de la configuración de los servidores, y
recárguelos: sshd rechaza todos los certificados en cuanto el archivo desaparece.
