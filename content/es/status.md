---
title: "Estado"
weight: 60
description: "Qué versiones describen estas páginas, qué añadió cada versión y qué no está implementado todavía."
tags: [estado, versiones]
---

Estas páginas son la versión **0.2** de la documentación, y describen:

| programa | versión | módulo |
|---|---|---|
| authnd | **v0.10.1** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.22.0** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.3** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.6** | `github.com/go-authn/sshcert` |

Las versiones de las bibliotecas están en [su propia página]({{< relref "/libraries/_index.md" >}}).
Una nueva versión menor de cualquiera de los programas anteriores es una nueva
versión de la documentación, de modo que las páginas que alguien encuentra bajo
`/docs/0.2/` siguen describiendo lo que instaló; las de las versiones anteriores
siguen bajo `/docs/0.1/`.

## Qué añadió cada versión {#what-each-release-added}

Cada línea es el cambio para el que se publicó una versión. Se omiten las versiones
que solo actualizaron dependencias.

### authnd {#authnd}

| | |
|---|---|
| v0.1.0 | un servidor LDAP para personas que están en otro lugar: un archivo, una base de datos SQL, otro directorio |
| v0.2.0 | un segundo factor, sobre un protocolo con un solo campo |
| v0.5.0 | cambios de contraseña que afectan exactamente a una identidad; una recarga sin condición de carrera; el KDC ve los cambios |
| v0.6.0 | las correcciones de seguridad de oidc, directory, ldap, totp y mfa |
| v0.7.0 | para cambiar una contraseña se exige la anterior; los secretos se comparan como resúmenes de longitud fija |
| v0.8.2 | un código solo cuenta detrás de la contraseña correcta; un lector se identifica por su DN configurado |
| v0.9.0 | compilado y probado con Go 1.27.1, fijado en lugar de `stable` |
| v0.9.2 | binarios de versión, `SHA256SUMS` y procedencia de compilación en cada etiqueta |
| v0.9.3 | binarios compilados fuera de la copia de trabajo; cada uno debe indicar exactamente la etiqueta |
| v0.9.4 | un `SIGHUP` ya no termina authnd: se registra en el log y no se recarga nada |
| v0.9.5 | la publicación comprueba la información de compilación de **cada** binario, no de uno solo |
| v0.9.6 | `check` dice por qué no se le puede emitir un ticket a cada persona |
| v0.10.0 | `check` abre el certificado y el keytab, como hace el servidor; nombra a quién no puede hacer un bind con contraseña y a quién sigue admitiendo un token; la línea de escucha llega después de que se abre el reino |
| v0.10.1 | go-authn/kdc v0.4.2: un `till` de 19700101000000Z obtiene el ticket más largo, no uno caducado en 1970 |

### authn-bridge {#authn-bridge}

| | |
|---|---|
| v0.1.0 | un proveedor OpenID Connect delante de una federación SAML |
| v0.2.0 | el device grant, certificados SSH, contraseñas de aplicación, OpenPubkey |
| v0.3.0 | una API de administración (`bridge.admin.v1`), y `/healthz`, `/readyz`, `/metrics` |
| v0.4.0 | tokens de acceso ES256 |
| v0.5.0 | TLS mediante go-authn/servercert, compartido con go-fileshare |
| v0.6.0 | certificados que se pueden revocar: una KRL SSH, y X.509 para NFS con una CRL |
| v0.7.0 | estado que sobrevive a un reinicio: tokens de actualización y tokens de acceso aceptados |
| v0.8.0 | un transmisor de Shared Signals: CAEP `session-revoked` |
| v0.9.0 | las correcciones de una revisión adversarial de la v0.8.1 |
| v0.10.0 | listas de revocación que se pueden comprobar en cualquier lugar: una KRL firmada, una caducidad, un ETag del contenido |
| v0.10.2 | un número de CRL en cada emisión; nunca una emisión fechada antes de la última |
| v0.11.0 | grupos ligados a su proveedor de identidad; desactivación por identidad; una audiencia exclusiva del bridge |
| v0.12.0 | un inicio de sesión en curso vive en su cookie sellada, no en memoria |
| v0.13.0 | un cliente confidencial puede proteger su código con el nonce (RFC 9700 2.1.1) |
| v0.16.0 | `max_age` pide una nueva autenticación solo cuando la última es demasiado antigua |
| v0.16.3 | una segunda revisión: todas las grafías revocadas, desactivación por `sub`, ninguna reutilización entre reinicios |
| v0.17.0 | claves WireGuard, registradas por las personas y listadas para una pasarela |
| v0.18.0 | un token de ID sin los claims de la persona; go-authn/saml v0.4.0 |
| v0.19.0 | el perfil de CA SSH de EuroHPC, opcional por cliente |
| v0.19.3 | binarios de versión, `SHA256SUMS` y procedencia de compilación en cada etiqueta |
| v0.20.0 | el comando es `authn-bridge`; una unidad systemd endurecida y una guía de instalación |
| v0.20.1 | comentarios y un mensaje de rechazo que ya no eran ciertos; el README dice todo lo que revoca `RevokePerson` |
| v0.21.0 | los indicadores de recurso del RFC 8707: un cliente cuya `audience` nombra varios servidores de recursos puede pedir un token dirigido a uno solo. Etiquetada una hora antes que la v0.20.1, que también los tiene, y sin las correcciones de la v0.20.1 |
| v0.21.1 | golang.org/x/net v0.60.0, por sus avisos de seguridad de HTTP/2, y Go 1.27.2; de nuevo las correcciones de la v0.20.1; dominios de ejemplo con nombres del RFC 2606 |
| v0.22.0 | el token de acceso ya no lleva `auth_time` ni `acr` (el token de ID sí), para que un token ES256 quepa en los 1023 caracteres de OpenSSH hasta el percentil 99 de los scopes de RENATER |

### authn-revokd {#authn-revokd}

| | |
|---|---|
| v0.1.0 | listas de revocación firmadas y con caducidad: el protocolo, la biblioteca y revokd (agente y espejo) |
| v0.2.0 | las correcciones de una revisión adversarial |
| v0.2.1 | la lista de cada CA fusionada con sus propias revocaciones de claves; la firma de una CRL se comprueba antes de analizarla |
| v0.3.0 | revocaciones de claves con ámbito; falla en modo cerrado por CA; se comprueba el propietario del directorio de estado |
| v0.5.0 | binarios de versión, `SHA256SUMS` y procedencia de compilación en cada etiqueta |
| v0.6.0 | el comando es `authn-revokd`; unidades systemd y una guía de instalación; `SIGHUP` sincroniza de inmediato |
| v0.6.1 | `-version` escribe en la salida estándar |
| v0.6.2 | `-once` distingue una descarga fallida de una lista caducada; una lista firmada por otra clave ya no se califica de condición de carrera; `-help` sale con 0 |
| v0.6.3 | dominios de ejemplo con nombres del RFC 2606, en los ejemplos y la documentación; ningún cambio de comportamiento |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | la extensión de concesión de dominio, y un `sshcert-authorize` que falla en modo cerrado |
| v0.1.2 | binarios de versión, `SHA256SUMS` y procedencia de compilación en cada etiqueta |
| v0.1.4 | la publicación comprueba la información de compilación de cada binario |
| v0.1.5 | `-version` muestra la versión del módulo de una compilación con `go install`, no `dev` |
| v0.1.6 | dominios de ejemplo con nombres del RFC 2606, en la documentación; ningún cambio de comportamiento |

## Aún no implementado {#not-implemented-yet}

- **Escrituras mediante LDAP**, más allá de que una persona cambie su propia
  contraseña. authnd responde a una modificación del propio `userPassword` y a la
  operación de modificación de contraseña de la RFC 3062 (lo que envía
  `ldappasswd`), ambas solo con la contraseña actual, y a nada más: add, delete y
  modifyDN existen en go-authn/ldap y deliberadamente no están conectados
  (`server.go`). La biblioteca representa una modificación como una lista ordenada
  (RFC 4511 4.6) y responde a los controles de lectura de entrada (RFC 4527), así
  que la forma está ahí; lo que falta es la política de quién puede escribir qué.
- **Un segundo factor dentro de Kerberos**: la preautenticación OTP (RFC 6560) en
  FAST (RFC 6113). Mientras no exista, no se pueden configurar a la vez un bloque
  `kerberos` y un bloque `mfa`.
- **RC4-HMAC**: el reino emite solo aes256-cts-hmac-sha1-96, de modo que a una
  persona conocida únicamente por un hash NT no se le puede emitir un ticket. Es una
  decisión (la RFC 8429 declara obsoleto RC4), no un hueco a la espera de rellenarse.
