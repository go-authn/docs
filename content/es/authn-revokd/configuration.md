---
title: "La configuración"
linkTitle: "Configuración"
weight: 20
description: "El revokd.hcl de authn-revokd: de dónde proceden las listas, con qué deben estar firmadas, en qué archivos se escriben, y el espejo."
tags: [authn-revokd, configuración]
---

Un solo archivo, `/etc/authn-revokd/revokd.hcl` por defecto (`-config` nombra otro).
Se lee una sola vez, al arrancar.

```hcl
state_dir = "/var/lib/authn-revokd/state"   # the verified copies: what orders the next list
refresh   = "1m"

source "univ-a-ssh" {
  url    = "https://login.univ-a.example/ssh/krl"    # and .../ssh/krl.sig beside it
  ssh_ca = "/etc/authn-revokd/ca/univ-a-ssh.pub"     # what the list must be signed by
}
source "univ-b-ssh" {
  url    = "http://mirror.cluster.local:8080/univ-b-ssh"   # a mirror: plain http is fine
  ssh_ca = "/etc/authn-revokd/ca/univ-b-ssh.pub"
}
source "univ-a-x509" {
  url     = "https://login.univ-a.example/x509/crl"
  x509_ca = "/etc/authn-revokd/ca/univ-a-x509.pem"
}

output "sshd" {                              # sshd_config: RevokedKeys /var/lib/authn-revokd/sshd.krl
  path    = "/var/lib/authn-revokd/sshd.krl"
  sources = ["univ-a-ssh", "univ-b-ssh"]     # merged into one file
}
output "tls" {                               # nginx: ssl_crl /var/lib/authn-revokd/univ-a.crl
  path    = "/var/lib/authn-revokd/univ-a.crl"
  sources = ["univ-a-x509"]
  format  = "pem"
}

# listen = "127.0.0.1:8080"                  # serve the verified lists: a mirror
```

## Las claves {#the-keys}

| clave | por defecto | |
|---|---|---|
| `state_dir` | | obligatoria, absoluta; se crea con `0700` si no existe |
| `refresh` | `1m` | con qué frecuencia se descarga cada origen, un segundo o más; cada espera varía una décima en un sentido u otro, para que un parque de máquinas no quede sincronizado |
| `listen` | | `host:port`: servir las listas verificadas, un espejo; se ignora con `-once` |

**`source "<name>"`**: una lista. El nombre está formado por letras, dígitos, `.`,
`_` y `-`, no empieza por un punto, y tiene como máximo 64 caracteres: nombra un
archivo del directorio de estado y una ruta del espejo.

| clave | |
|---|---|
| `url` | `https://`, `http://` o `file://`; la firma de una KRL se descarga de la misma URL con `.sig` añadido |
| `ssh_ca` | la clave pública de la CA SSH, una línea `authorized_keys`: un origen KRL. Aquí se rechaza un certificado |
| `x509_ca` | el certificado PEM de la CA: un origen CRL |
| `max_age` | rechazar también una lista emitida hace más tiempo que esto, además de su propia caducidad; se rechaza en un origen que alimenta una salida CRL |
| `revoke_keys` | permitir que la lista de este origen revoque **claves simples** en una salida compartida con otros orígenes; solo orígenes KRL |

**`output "<name>"`**: un archivo que lee un servidor.

| clave | |
|---|---|
| `path` | absoluta; se escribe a su lado y se renombra encima |
| `sources` | orígenes KRL, fusionados en un solo archivo; o exactamente un origen CRL |
| `format` | `der` (por defecto) o `pem`; solo salidas CRL |
| `on_change` | una orden y sus argumentos, que se ejecuta después de que cambie el archivo, y de nuevo en cada sincronización hasta que tenga éxito |

## Una KRL para varias CA {#one-krl-for-several-cas}

Antes de OpenSSH 10.3, `RevokedKeys` admite un solo archivo, así que los orígenes KRL
de una salida se fusionan, y **cada lista conserva todo su efecto sobre su propia CA,
y ninguno sobre otra**:

- **Se conservan:** sus números de serie e identificadores de clave, sus secciones
  que no nombran ninguna CA (limitadas a la suya), y la propia clave de su CA, que
  revoca todos sus certificados.
- **Se dejan fuera, y se registran:** la sección de otra CA, y la clave de otra CA.
- Las **claves de usuario simples** se dejan fuera cuando la salida tiene más de un
  origen, salvo que el origen tenga `revoke_keys = true`. Una KRL no puede limitar una
  clave a una sola CA: sshd comprueba la propia clave de un certificado contra el
  archivo, sea quien sea quien lo firmó, así que una clave que nombra una CA dejaría
  fuera a su titular bajo todas las CA del archivo. Una salida con un solo origen las
  conserva.

Cada lista se fusiona primero por separado. Una que no se puede fusionar falla en modo
cerrado **solo para su propia CA**; el archivo fusionado caduca con la primera de sus
entradas vigentes, así que un lector que comprueba la caducidad ve detenerse
authn-revokd.

## El espejo {#the-mirror}

Con `listen`, authn-revokd sirve lo que tiene, desde la memoria, nunca desde los
archivos que una escritura puede tener a medias:

| | |
|---|---|
| `GET /<source>` | la lista, con un `ETag`; `If-None-Match` responde `304` |
| `GET /<source>.sig` | la firma de una KRL; `If-Match` con otro ETag responde `412` |
| `GET /healthz` | `200 ok`, o `503` nombrando cada origen sin lista vigente y cada salida que ha fallado |

```
$ curl -s http://127.0.0.1:28474/healthz
ok
$ curl -s -D - -o /dev/null http://127.0.0.1:28474/bridge-ssh
HTTP/1.1 200 OK
Cache-Control: max-age=30
Content-Type: application/octet-stream
Etag: "dfd84d8513eb48d07ed72f2110316858"
Date: Mon, 26 Oct 2026 11:27:10 GMT
Content-Length: 130

$ curl -s -o /dev/null -w "%{http_code}\n" -H 'If-Match: "stale"' http://127.0.0.1:28474/bridge-ssh.sig
412
```

Un origen CRL no tiene `.sig` (`404`). Los espejos se encadenan: el origen de un
espejo puede ser otro espejo, puesto que cada lista se verifica por sí misma. Un
origen lento nunca bloquea las respuestas del espejo.

## Lo que se rechaza al arrancar {#what-is-refused-at-start}

Cada uno de estos casos termina con `2` antes de descargar nada:

```
authn-revokd: v/relative-state.hcl: state_dir "state": an absolute path
authn-revokd: v/refresh.hcl: refresh "500ms": a duration of a second or more
authn-revokd: v/both-ca.hcl: source "bridge-ssh": ssh_ca and x509_ca together: one source is one list
authn-revokd: v/sig-name.hcl: source "bridge-ssh.sig": a name that ends in .sig, or healthz, is a path the mirror already serves
authn-revokd: v/mixed.hcl: output "sshd" mixes KRL and CRL sources
authn-revokd: v/krl-format.hcl: output "sshd": format is for CRL outputs; a KRL is what sshd reads
authn-revokd: v/revoke-keys-crl.hcl: source "bridge-x509": revoke_keys is for a KRL source (ssh_ca): a CRL revokes its own CA's certificates only
```

Lo mismo ocurre con una configuración que no existe:

```
$ authn-revokd -config nowhere.hcl -once
authn-revokd: nowhere.hcl: no such file or directory
```

Antes de la v0.6.2 era el mensaje del analizador HCL:
`nowhere.hcl: <nil>: Failed to read file; The configuration file "nowhere.hcl" could not be read.`

Una salida CRL admite además un solo origen (un servidor TLS lee una CRL por emisor),
y un origen CRL con `max_age` se rechaza, porque nada podría hacerlo cumplir:

```
authn-revokd: v/crl-maxage.hcl: output "tls": source "bridge-x509" has a max_age, which a CRL output cannot enforce: the TLS server judges a CRL by its nextUpdate alone. Remove max_age, or ask the CA for a closer nextUpdate
```

Un servidor TLS que ha cargado una CRL la conserva en memoria hasta su `nextUpdate`,
escriba lo que escriba authn-revokd.

**El directorio de estado** se somete a la regla StrictModes de sshd. Quien pueda
sustituir o eliminar sus archivos decide qué lista viene después, y un estado vaciado
deja entrar una lista más antigua reproducida. Así que no puede ser un enlace
simbólico, ni tener escritura para el grupo o para otros, ni pertenecer a nadie que no
sea el usuario de authn-revokd o root. Estos casos terminan con `1`:

```
authn-revokd: state_dir /tmp/authn/revokd/state-wide is writable by its group or by others (mode -rwxrwxrwx): whoever can write there decides which list comes next
authn-revokd: state_dir /tmp/authn/revokd/state-link is a symbolic link (L---------): whoever owns it decides where the state is; name the directory itself
```
