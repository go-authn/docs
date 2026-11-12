---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "Un agente que descarga KRL y CRL firmadas, conserva solo las listas que se verifican, las escribe donde las leen sshd y los servidores TLS, y falla en modo cerrado cuando una caduca."
tags: [authn-revokd, revocación, krl, crl]
---

**OpenSSH no tiene forma de distribuir una KRL, y nada en una KRL dice que esté
desfasada.** `sshd` lee como lista vigente un archivo que dejó de actualizarse hace
meses. authn-revokd cierra ambas brechas para las listas que publica
[authn-bridge]({{< relref "/authn-bridge/revocation.md" >}}): descarga cada lista, la
conserva solo si se verifica, la escribe donde la lee `sshd` o un servidor TLS y,
cuando una lista caduca, escribe una que **revoca la propia CA**. Go puro,
`CGO_ENABLED=0`, un solo binario. Estas páginas describen la v0.7.0.

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.7.0
go: downloading github.com/go-authn/revocation v0.7.0
$ authn-revokd --version
authn-revokd v0.7.0
$ authn-revokd --help
authn-revokd fetches revocation lists, keeps only those that verify, writes
them where sshd and TLS servers read them (failing closed for sshd when a list
lapses) and, with listen, serves the verified copies as a mirror. SIGHUP syncs now.

The single-dash spellings -config, -once, -version and -help of earlier
releases are still accepted, with a deprecation warning on stderr.

Usage:
  authn-revokd [flags]

Flags:
  -c, --config string   the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -h, --help            help for authn-revokd
  -o, --once            sync once and exit: 1 when a list is not current, or could not be fetched
  -v, --version         version for authn-revokd
```

El comando es cobra desde la v0.7.0: indicadores POSIX `--config`/`-c`,
`--once`/`-o`, `--version`/`-v`, `--help`/`-h`, y `--config=RUTA`. `--help`
imprime en la salida estándar y termina con 0 (antes de la v0.6.2 el antiguo
`-help` terminaba con 2). Las grafías con un solo guion de las versiones
anteriores (`-config`, `-once`, `-version`, `-help`, con `=` o con el valor
aparte) se siguen aceptando, con una línea de aviso de obsolescencia por
indicador en la salida de error estándar, y se eliminarán en una versión
posterior; los códigos de salida no cambian (0; 1 por un fallo o una lista no
vigente con `--once`; 2 por un error de uso o una configuración ilegible), de
modo que una unidad desplegada con `-once` no necesita cambios.

Antes de la v0.6.0 el comando se llamaba `revokd`, y leía `/etc/revokd.hcl` por
defecto. Ya nada lee ese archivo; cuando existe y el nuevo valor por defecto no, el
error nombra las dos rutas.

## Lo que hace, en una ejecución {#what-it-does-in-one-run}

Contra un emisor de sustitución en loopback (un pequeño programa que sirve una KRL
y una CRL firmadas con claves de prueba, con los mismos endpoints que authn-bridge),
con un origen KRL y un origen CRL:

```
$ authn-revokd --config revokd.hcl --once
bridge-ssh: version 0, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
bridge-x509: version 1794481424000, issued 2026-11-12T11:03:44Z, expires 2026-11-12T12:03:44Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261112T120344
# Comment: authn-revokd sshd
```

Una segunda ejecución sin nada nuevo no imprime nada y termina con 0: una salida solo
se reescribe cuando cambia su contenido.

## Por qué el transporte no importa {#why-the-transport-does-not-matter}

Cada lista se autentica a sí misma: una KRL mediante una firma SSHSIG separada hecha
con la propia clave de la CA, una CRL mediante la firma de su CA. Cada lista dice
cuándo deja de estar vigente. Así que una lista puede llegar por HTTPS, por HTTP sin
cifrar dentro de un clúster, desde un espejo o desde un archivo. El transporte decide
lo rápido que llega un cambio, nunca si se acepta una lista falsificada o desfasada.

| | KRL | CRL |
|---|---|---|
| auténtica | SSHSIG con la clave de la CA SSH, espacio de nombres `krl@go-authn.github.io` | firmada por su CA |
| vigente | `expires@go-authn.github.io`, que sshd ignora | `nextUpdate` |
| nunca hacia atrás | `krl_version`, y después la fecha de generación | CRL Number, y después `thisUpdate` |
| en modo cerrado | authn-revokd escribe una KRL que revoca la clave de la CA | OpenSSL rechaza por sí solo una CRL caducada |

## Por dónde seguir {#where-to-go-next}

| | |
|---|---|
| [Instalarlo]({{< relref "/authn-revokd/install.md" >}}) | el demonio, o `--once` con un temporizador; conectar sshd y nginx |
| [La configuración]({{< relref "/authn-revokd/configuration.md" >}}) | orígenes, salidas, el espejo, y lo que se rechaza |
| [Cómo se verifica una lista]({{< relref "/authn-revokd/verification.md" >}}) | firma, fechas, y nunca más antigua que la lista guardada, también entre reinicios |
| [Cuando una lista caduca]({{< relref "/authn-revokd/lapse.md" >}}) | la KRL que revoca la propia CA |

## Lo que no hace {#what-it-does-not-do}

Una revocación no llega a un servidor más rápido de lo que authn-revokd consulta
(`refresh`), más el retraso del emisor en volver a emitir. Mientras el emisor está
caído, sus certificados se rechazan a partir de la caducidad de la lista. Quien tenga
la clave de una CA puede firmar cualquier lista, igual que puede firmar cualquier
certificado.

## Licencia {#licence}

BSD-3-Clause.
