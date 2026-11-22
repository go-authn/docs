---
title: "harden — dos primitivas de seguridad, compartidas"
linkTitle: "harden"
weight: 36
description: "go-authn/harden reúne las primitivas de seguridad que los repositorios de go-authn habían copiado cada uno: la regla de redirección https-o-loopback, un archivo privado escrito de forma atómica y el bloqueo de memoria con endurecimiento contra los volcados de core."
tags: [bibliotecas, harden, seguridad]
---

**¿Qué copiaba cada repositorio de go-authn?** Dos reglas pequeñas, ahora en un
solo módulo sin más dependencia que la biblioteca estándar.

```sh
go get github.com/go-authn/harden@v0.3.0
```

## `redirect` {#redirect}

La regla que se aplica antes de que un token, un conjunto de claves o una
aserción firmada crucen un enlace: **la URL es https, o nombra esta máquina.**

```go
import "github.com/go-authn/harden/redirect"

client := &http.Client{Timeout: 30 * time.Second, CheckRedirect: redirect.CheckRedirect}

if err := redirect.HTTPSOrLoopback(issuer); err != nil { ... }
```

| Función | |
|---|---|
| `CheckRedirect(req, via) error` | una política de `http.Client`: se detiene tras 10 redirecciones y rechaza un destino que no sea https ni loopback (de https a http en otro host es el caso para el que existe). Encadene su propia política después de ella |
| `HTTPSOrLoopback(rawURL) error` | nil para `https://host.example/...`, o `http://` con un host loopback. Rechaza la ausencia de host, otros esquemas y el texto en claro. El error nombra el esquema y el host, nunca la URL entera |
| `Loopback(host) bool` | `host` tal como lo devuelve `url.URL.Hostname()` |

`Loopback` acepta un literal IP que sea loopback (127.0.0.0/8, `::1`,
`::ffff:127.0.0.1` mapeado desde IPv4), y `localhost` o cualquier nombre bajo
`.localhost` (RFC 6761 sección 6.3), en cualquier combinación de mayúsculas, con
o sin el punto final. Nunca compara un prefijo, así que `127.evil.example` se
rechaza, como `0x7f.1`, `127.1`, `2130706433`, una zona IPv6 y el `[::1]` entre
corchetes (los corchetes son sintaxis de URL, no parte de un host).

`Loopback` y `HTTPSOrLoopback` se fuzzean contra una segunda lectura del RFC; el
corpus está versionado.

Es lo que aplican [oidc]({{< relref "/libraries/oidc.md" >}}) (v0.8.1),
[saml]({{< relref "/libraries/saml.md" >}}) (v0.7.3),
[wireguard]({{< relref "/libraries/wireguard.md" >}}), rp (v0.5.1) y awscred
(v0.3.1).

## `privfile` {#privfile}

```go
import "github.com/go-authn/harden/privfile"

err := privfile.Write(path, ticket)
```

`Write` pone los datos en `path` con modo 0600: un archivo temporal en el mismo
directorio, `fsync`, luego `rename`. Así:

- un lector ve el archivo antiguo o el nuevo, nunca la mitad de uno;
- un enlace simbólico dejado en `path` se **sustituye, no se sigue** (aquello a
  lo que apuntaba no se toca), y un archivo de modo más permisivo no conserva su
  modo;
- en Unix, un directorio que es un enlace simbólico, pertenece a otro o admite
  escritura de grupo u otros se rechaza antes de escribir nada.

No crea el directorio. En Windows no hay un modo que leer; desde la v0.2.0 el
archivo se crea con una lista de acceso protegida que contiene una sola entrada,
la cuenta actual, fijada por `CreateFile` (la lista de kinit v0.3.2), de modo que
nunca se heredan las entradas de la carpeta. El módulo requiere
`golang.org/x/sys`, que solo usan las compilaciones para Windows.

Es lo que escribe el `--cred-file` de kinit (v0.3.3), el `FloorFile` de wireguard
(v0.2.1), el archivo de estado de `authn-revokd` (revocation v0.7.2) y el archivo
de asociación de KeePassXC de
[secretsource]({{< relref "/libraries/secretsource.md" >}}) (v0.8.1).

## Suelos {#floors}

go-authn/wireguard y go-authn/revocation conservan ambos un suelo de orden a
través de un reinicio, pero no comparten el suelo: wireguard guarda una versión
y una hora de emisión desnudas en un pequeño archivo propio, revocation guarda
toda la lista firmada y recalcula el suelo verificándola. Solo la escritura del
archivo es común, y eso es `privfile`.

## `memlock` {#memlock}

Desde la v0.3.0 (llegado de theca): mantener el material de claves fuera del
swap, de los archivos core y de los depuradores.

```go
import "github.com/go-authn/harden/memlock"

region, err := memlock.Lock(unsafe.Pointer(&key[0]), uintptr(len(key)))
if err != nil { ... } // rechazado: decirlo, o detenerse
defer region.Release()
```

| Función | |
|---|---|
| `Lock(p, n) (*Region, error)` | bloquea las páginas del rango con `mlock` (Linux, macOS, los BSD) o `VirtualLock` (Windows). **Un rechazo es un error**: nada queda bloqueado y quien llama decide. Las páginas que comparten dos regiones siguen bloqueadas hasta que se liberan ambas |
| `(*Locker).LockBestEffort(p, n, report)` | igual, pero cada rechazo se entrega a `report` y el resto se bloquea de todos modos. El nombre lo dice: úsese solo donde ejecutar sin bloqueo sea aceptable |
| `(*Region).Release()` | desbloquea; es inocua con nil y llamada dos veces |
| `DisableDumps() error` | `RLIMIT_CORE` a 0 y, en Linux, `PR_SET_DUMPABLE` a 0; solo en macOS, además, `PT_DENY_ATTACH` |

Cualquier otra plataforma recibe un `*UnsupportedError` (coincide con
`errors.ErrUnsupported`), nunca un éxito silencioso.

**Garantiza** que las páginas del rango están bloqueadas en memoria desde
`Lock` hasta `Release`, o que recibe un error. **No garantiza** que no exista
ninguna copia: el recolector de basura de Go puede copiar un objeto del heap
antes de bloquearlo; bloquee, por tanto, memoria que no se mueve y guarde el
secreto en un solo lugar. Los límites del sistema siguen aplicándose
(`RLIMIT_MEMLOCK`; en Windows, el tamaño del working set). Windows no tiene
equivalente de `PR_SET_DUMPABLE` ni de `PT_DENY_ATTACH`: un depurador del mismo
usuario o un administrador puede leer el proceso.

## Referencia {#reference}

El README de
[github.com/go-authn/harden](https://github.com/go-authn/harden) es la fuente de
verdad de esta página. BSD 3-Clause.
