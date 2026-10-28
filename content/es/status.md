---
title: "Estado"
weight: 60
description: "Qué versiones describen estas páginas, qué añadió cada versión y qué no está implementado todavía."
tags: [estado, versiones]
---

Estas páginas son la versión **0.6** de la documentación, y describen:

| programa | versión | módulo |
|---|---|---|
| authnd | **v0.13.1** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.4** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.6** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

Las versiones de las bibliotecas están en [su propia página]({{< relref "/libraries/_index.md" >}});
ldap está en la **v0.11.1**, con reglas de contenido DIT, formas de nombre y
reglas de estructura DIT leídas, aplicadas y publicadas, un `BuildError` tipado
para un esquema que no se construye, los esquemas en HCL2 y el conversor
`ldapschema`, y directory en la **v0.15.0**, con clases de objeto declaradas.
authnd v0.13.1 incorpora ldap v0.11.1 y directory v0.15.0.
Una nueva versión menor de cualquiera de los programas anteriores es una nueva
versión de la documentación, de modo que las páginas que alguien encuentra bajo
`/docs/0.6/` siguen describiendo lo que instaló; las de las versiones anteriores
siguen bajo `/docs/0.1/`, `/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/` y `/docs/0.5/`.

{{< callout type="warning" >}}
**Seguridad: use authnd v0.12.0, no la v0.11.1**

authnd verifica certificados (`x509.Certificate.Verify`, alcanzado desde `main`
según `govulncheck`), y el crypto/x509 de Go 1.27.2 no dejaba de confiar en los
certificados intermedios comprometidos que nombra GO-2026-6809. **Los binarios
de la versión v0.11.1 se compilaron con Go 1.27.2 y están afectados.** La
v0.12.0 se compila con Go 1.27.3 y su directiva `go` es 1.27.3, así que
`go install` cambia por sí solo a la cadena de herramientas corregida;
`govulncheck` con 1.27.3 no informa de ninguna vulnerabilidad. Su binario de
la versión informa `go1.27.3` en `go version -m`. Consulte
[la nota de actualización]({{< relref "/authnd/_index.md" >}}).
{{< /callout >}}

{{< callout type="warning" >}}
**Seguridad: use authn-bridge v0.23.3 y authn-revokd v0.6.5**

Con Go 1.27.2, `govulncheck` notifica GO-2026-6809 en ambos programas: `Certificate.Verify` de `crypto/x509` no rechazaba certificados intermedios comprometidos conocidos. Se corrige en Go 1.26.10 y 1.27.3. **Los binarios de versión compilados con un Go anterior están afectados.** v0.23.3 y v0.6.5 se compilan con Go 1.27.3 y su directiva `go` es 1.27.3, de modo que `go install` cambia por sí solo a la cadena de herramientas corregida; sus binarios de versión indican `go1.27.3` en `go version -m`. sshcert no está afectado y no tiene una versión nueva.
{{< /callout >}}

## Qué añadió cada versión {#what-each-release-added}

Cada línea es el cambio para el que se publicó una versión. Se omiten las versiones
que solo actualizaron dependencias, salvo las que describe esta versión de la documentación.

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
| v0.10.2 | go-authn/directory v0.12.0: un grupo vacío se publica como `posixGroup` sin `memberUid` |
| v0.11.0 | [entradas de esquema estándar]({{< relref "/authnd/entries.md" >}}), cada una sometida al esquema servido en `cn=Subschema`; `attributes`, `users_attributes` y `groups_attributes`; `(uidNumber>=1000)` compara enteros. ⛔ `publish_nt_hash` necesita un [bloque `samba`]({{< relref "/authnd/tls.md#the-samba-block" >}}), y un consumidor que filtra por `posixAccount` o `posixGroup` ve menos entradas |
| v0.11.1 | la línea de arranque solo nombra las fuentes desde las que se sirve a alguien: sin bloque `user`, ya no nombra el archivo de configuración |
| v0.12.0 | [esquemas de un sitio]({{< relref "/authnd/schemas.md" >}}): `schema_files` (`.schema` de OpenLDAP y LDIF de cn=config, tal como se publican; una redefinición se rechaza, incluso idéntica, como hace slapd) y un bloque `schema { }`; clases auxiliares declaradas por origen con `object_classes`, validadas al arrancar y publicadas con sus superclases; `check` informa de los archivos, de las declaraciones, de las clases omitidas en una persona por falta de un MUST y de los grupos sobre los que dos orígenes discrepan. ⛔ Compilada con Go 1.27.3: los binarios de la v0.11.1 (Go 1.27.2) están afectados por GO-2026-6809 |
| v0.12.1 | un archivo o bloque de esquema que no se construye se rechaza en la posición que lleva el `BuildError` de go-authn/ldap v0.10.0, con una columna (`site.schema:6:` pasa a ser `site.schema:6:1:`); el mensaje termina con el tipo de rechazo, y un duplicado dice dónde está su primera definición |
| v0.12.2 | los binarios de la versión se enlazan con `-ldflags="-w"` en lugar de `-s -w`: se conserva la tabla de símbolos, de modo que `govulncheck -mode binary` es preciso en vez de señalar vulnerabilidades en código que no está enlazado; alrededor de un 9 % más grandes (de 18,8 MB a 20,5 MB en darwin/arm64) |
| v0.12.3 | go-authn/ldap v0.10.1: los `schema_files` se leen en tiempo lineal. ⛔ Hasta v0.12.2, un archivo de esquema grande de líneas de continuación cortas (4 MiB: unos tres minutos) bloqueaba el arranque: una denegación de servicio por un archivo que no se controla |
| v0.12.4 | go-authn/ldap v0.10.2: los valores de DESC de 13 definiciones de RFC 2307 en `cn=Subschema` (`uidNumber`, `gidNumber`, `ipHostNumber`, `ipNetworkNumber`, `ipNetmaskNumber`, `macAddress` y las clases `ipService`, `ipProtocol`, `oncRpc`, `ipHost`, `ipNetwork`, `ieee802Device`, `bootableDevice`) ya no llevan la sangría de la paginación de la RFC: `DESC 'An integer uniquely identifying a user in an administrative domain'`, y no `... in an         administrative domain'` |
| v0.13.0 | [reglas de contenido DIT, formas de nombre y reglas de estructura DIT]({{< relref "/authnd/schemas.md#rules" >}}) (go-authn/ldap v0.11.0): `schema_files` y el bloque `schema { }` aceptan los tres tipos, y authnd los aplica. Una regla de contenido da forma a cada entrada: una clase auxiliar que su `AUX` no enumera se deja fuera (con los atributos que solo ella permitía), un atributo `NOT` se descarta, una entrada a la que le falta un `MUST` se deja fuera; cada caso se registra en el log y lo informa `check`. Con una regla de estructura activa, el árbol (el sufijo, `ou=people`, `ou=groups`, el RDN `uid` o `cn`) se comprueba al arrancar y con `check`, y una infracción **impide el arranque**, con todos los rechazos a la vez y sin repetir nunca un secreto; una entrada que ninguna regla ubica se deja fuera. ⛔ Una cadena `schema { }` que no es UTF-8 válido se rechaza ahora. Publicar 10 000 personas hace 416 asignaciones por entrada con las reglas frente a 265 sin ellas (tiempos medidos bajo carga, no fiables) |
| v0.13.1 | Solo rendimiento, con go-authn/ldap v0.11.1: publicar 10 000 personas (`BenchmarkPublish10k`, `-cpu 1`) hace 364 asignaciones por entrada con las reglas y 239 sin ellas, frente a 416 y 265 en la v0.13.0, y 102,5 MiB por ejecución con las reglas frente a 147,5. Los tiempos se midieron con una carga de 10 a 16 y no son fiables |

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
| v0.21.0 | [los indicadores de recurso del RFC 8707]({{< relref "/authn-bridge/resources.md" >}}): un cliente cuya `audience` nombra varios servidores de recursos puede pedir un token dirigido a uno solo. Etiquetada una hora antes que la v0.20.1, que también los tiene, y sin las correcciones de la v0.20.1 |
| v0.21.1 | golang.org/x/net v0.60.0, por sus avisos de seguridad de HTTP/2, y Go 1.27.2; de nuevo las correcciones de la v0.20.1; dominios de ejemplo con nombres del RFC 2606 |
| v0.22.0 | el token de acceso ya no lleva `auth_time` ni `acr` (el token de ID sí), para que un token ES256 quepa en los 1023 caracteres de OpenSSH hasta el percentil 99 de los scopes de RENATER |
| v0.22.1 | `resource` puede repetirse en el endpoint de autorización, para una concesión acotada a varios servidores; se rechaza en `device_authorization` en vez de ignorarse ([indicadores de recurso]({{< relref "/authn-bridge/resources.md" >}})) |
| v0.23.0 | `access_token_groups = false`: un cliente cuyos tokens se pegan en ssh no lleva grupos ([tokens]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})) |
| v0.23.1 | solo dependencias: go-jose/v4 v4.1.6, golang.org/x/crypto v0.58.0, golang.org/x/net v0.61.0; go-authn/directory v0.12.0, revocation v0.6.3, saml v0.4.1, servercert v0.5.1, sshcert v0.1.6 |
| v0.23.2 | seguridad: go-authn/oidc v0.4.2, que rechaza un `nbf` fuera del rango de int64 (se aceptaba un token que aún no era válido) y una clave RSA con `e = 0` (se analizaba); go-authn/wireguard v0.1.2 |
| v0.23.3 | compilada con Go 1.27.3, por GO-2026-6809 (`crypto/x509`: `Certificate.Verify` no rechazaba certificados intermedios comprometidos conocidos); la directiva `go` es 1.27.3; ningún cambio de comportamiento |
| v0.23.4 | los binarios de la versión se enlazan con `-w` en lugar de `-s -w`, de modo que se conserva la tabla de símbolos para un `govulncheck -mode binary` preciso; sin cambio de comportamiento |

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
| v0.6.4 | solo dependencias: golang.org/x/crypto v0.58.0 |
| v0.6.5 | compilada con Go 1.27.3, por GO-2026-6809 (`crypto/x509`: `Certificate.Verify` no rechazaba certificados intermedios comprometidos conocidos); la directiva `go` es 1.27.3; ningún cambio de comportamiento |
| v0.6.6 | los binarios de la versión se enlazan con `-w` en lugar de `-s -w`, de modo que se conserva la tabla de símbolos para un `govulncheck -mode binary` preciso; sin cambio de comportamiento |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | la extensión de concesión de dominio, y un `sshcert-authorize` que falla en modo cerrado |
| v0.1.2 | binarios de versión, `SHA256SUMS` y procedencia de compilación en cada etiqueta |
| v0.1.4 | la publicación comprueba la información de compilación de cada binario |
| v0.1.5 | `-version` muestra la versión del módulo de una compilación con `go install`, no `dev` |
| v0.1.6 | dominios de ejemplo con nombres del RFC 2606, en la documentación; ningún cambio de comportamiento |
| v0.1.7 | solo dependencias: golang.org/x/crypto v0.58.0 |
| v0.1.8 | los binarios de la versión se enlazan con `-w` en lugar de `-s -w`, de modo que se conserva la tabla de símbolos para un `govulncheck -mode binary` preciso; sin cambio de comportamiento |
| v0.1.9 | compilado con Go 1.27.3; sin cambio de comportamiento |

### Las bibliotecas {#the-libraries}

Las versiones de las bibliotecas para las que se hizo esta versión de la
documentación; la página de cada biblioteca dice lo que cambiaron las
anteriores.

| | |
|---|---|
| directory v0.13.0 | [atributos]({{< relref "/libraries/directory.md#attributes" >}}): lo que describe a alguien y no prueba nada, aparte de las credenciales, con los nombres que nunca pueden serlo; `attributes` en los bloques `user` y `group`, las consultas `users_attributes` y `groups_attributes`, `attributes` y `group_attributes` de ldapdir |
| directory v0.14.0 | ⛔ los [valores por defecto]({{< relref "/libraries/directory.md#ldapdir-defaults" >}}) de ldapdir leen personas `account` y `uidObject` y grupos `groupOfNames`, lo que amplía lo que entrega el directorio de una institución; un DN en `member` solo corresponde a una persona que el origen importó |
| directory v0.15.0 | [clases de objeto]({{< relref "/libraries/directory.md#object-classes" >}}), declaradas y nunca deducidas: `object_classes` y `group_object_classes` en los bloques `users`, `object_classes` en los bloques `user` y `group`, `WithObjectClasses` para sqldir y `Config.ObjectClasses` para ldapdir; decide el primer origen que declara las clases de un grupo; `sqldir.ClosesDB` |
| kdc v0.4.3 | solo dependencias: go-authn/directory v0.12.0 como mínimo |
| keyfactor v0.4.2 | solo dependencias: go-authn/fido v0.6.2 y golang.org/x/crypto v0.58.0 como mínimos |
| krb5 v0.3.1 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| krl v0.6.1 | solo dependencias: golang.org/x/crypto v0.58.0; probada con Go 1.27.2 |
| ldap v0.8.0 | [el paquete `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) y `Server.Schema`: `cn=Subschema` (RFC 4512 §4.2), `Validate`, las reglas de comparación del RFC 4517; `uidNumber` y `gidNumber` se ordenan como enteros; una búsqueda paginada se ciñe a los atributos pedidos |
| ldap v0.9.0 | [los esquemas en HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): el paquete `schema/hclschema` y el comando `ldapschema` (`to-hcl`, `to-schema`, `check`) entre `.schema` de OpenLDAP, LDIF cn=config y HCL2; los lectores leen los archivos como slapd; las reglas de contenido y de estructura del DIT, las formas de nombre, `include` y `X-SUBST` no se admiten (la v0.11.0 admite las reglas) |
| ldap v0.10.0 | [un `*schema.BuildError` tipado]({{< relref "/libraries/ldap.md#build-error" >}}) para una definición que `Build` rechaza, que se obtiene con `errors.As`: `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos` (archivo:línea:columna donde empieza la definición, también para LDIF plegado o en base64 y para HCL), y `Ref`, `RefOID` y `RefPos` para la otra definición; toda definición leída lleva una `Pos`; «clases de objeto» en un mensaje |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) es lineal en el número de líneas de continuación (era cuadrático: un archivo de 4 MiB tardaba unos tres minutos) y ya no copia ni divide todo el archivo para leer su primera línea; `schema.Format` pliega las líneas de más de 2000 bytes, que slapd y `Read` rechazan; el analizador estricto es unas 2,6 veces más rápido (147 asignaciones en lugar de 498 en `cosine.schema`, medido bajo carga) |
| ldap v0.10.2 | los DESC de 13 definiciones de RFC 2307 del esquema incorporado (`schema.Standard()`) van en una sola línea: llevaban la sangría de la paginación de la RFC, que el lector conserva dentro de las comillas como slapd, así que el subesquema que publicaba un servidor tenía series de espacios; una prueba comprueba ahora cada DESC incorporado y, donde se define el mismo OID, lo compara con los esquemas `core`, `cosine`, `inetorgperson` y `nis` de OpenLDAP |
| ldap v0.11.0 | [reglas de contenido DIT, formas de nombre y reglas de estructura DIT]({{< relref "/libraries/ldap.md#rules" >}}) (RFC 4512 §4.1.6, §4.1.7) leídas de `.schema` y LDIF, escritas por `Format`, transportadas por HCL (`dit_content_rule`, `name_form`, `dit_structure_rule`) y por `ldapschema`, comprobadas por `Build`, aplicadas por `Validate` (reglas de contenido: AUX, MUST, MAY, NOT; formas de nombre: el RDN; reglas de estructura: `GoverningStructureRule`) y publicadas en `cn=Subschema` solo cuando existen; `ValidateOptions{StrictAuxiliary}` da el RFC 4512 §2.4.3. ⛔ slapd solo implementa las reglas de contenido, así que `Format` escribe las palabras clave `nameform` y `ditstructurerule`, que él rechaza; una regla `OBSOLETE` está inactiva donde slapd rechaza la entrada; libldap no puede leer el `SUP` de una regla de estructura. `hclschema.Decode` rechaza una cadena que no es UTF-8 |
| ldap v0.11.1 | Solo rendimiento, sin cambio de resultado: una cadena de ASCII imprimible se prepara para las reglas de comparación de cadenas (RFC 4518) con una asignación como máximo, ninguna cuando nada cambia, y el analizador de DN hace 6 asignaciones en lugar de 11 para un DN de cuatro RDN. Los resultados son los de la v0.11.0, comprobados contra su código en cada cadena de uno o dos bytes por debajo de 0x80 y con un fuzzer diferencial |
| oidc v0.4.1 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| servercert v0.5.2 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| totp v0.4.2 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| wireguard v0.1.1 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |

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
