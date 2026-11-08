---
title: "Estado"
weight: 60
description: "Qué versiones describen estas páginas, qué añadió cada versión y qué no está implementado todavía."
tags: [estado, versiones]
---

Estas páginas son la versión **0.11** de la documentación, y describen:

| programa | versión | módulo |
|---|---|---|
| authnd | **v0.18.6** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.12** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.7.0** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

Las versiones de las bibliotecas están en [su propia página]({{< relref "/libraries/_index.md" >}});
ldap está en la **v0.12.3**, con reglas de contenido DIT, formas de nombre y
reglas de estructura DIT leídas, aplicadas y publicadas, un `BuildError` tipado
para un esquema que no se construye, los esquemas en HCL2 y el conversor
`ldapschema`, y directory en la **v0.21.0**, con clases de objeto declaradas, un plazo en cada consulta SQL
y un `GroupNames` que informa de las fuentes que fallaron.
authnd v0.18.6 incorpora ldap v0.12.3 y directory v0.20.0.
Una nueva versión menor de cualquiera de los programas anteriores es una nueva
versión de la documentación, de modo que las páginas que alguien encuentra bajo
`/docs/0.11/` siguen describiendo lo que instaló; las de las versiones anteriores
siguen bajo `/docs/0.1/`, `/docs/0.2/`, `/docs/0.3/`, `/docs/0.4/`, `/docs/0.5/`, `/docs/0.6/`, `/docs/0.7/`, `/docs/0.8/`, `/docs/0.9/` y `/docs/0.10/`.

{{< callout type="warning" >}}
**Actualizar authnd desde v0.16.x: `max_age` vale diez minutos por defecto**

Los datos servidos no tenían límite de antigüedad, así que una persona eliminada de una fuente que después dejó de poder leerse seguía autenticándose mientras durara la caída. Desde v0.17.0 `max_age` vale diez minutos (al menos diez períodos de `refresh`; sin valor por defecto con `refresh = "0"`) y, pasado ese tiempo, las búsquedas, los binds de las personas y los cambios de contraseña responden `unavailable` (52). Defina `max_age` con lo que pueda tolerar, o `"0"` para no tener límite. Consulte [la nota de actualización]({{< relref "/authnd/_index.md" >}}) y [cómo se rechazan los datos obsoletos]({{< relref "/authnd/operations.md#it-reads-everything-once" >}}).
{{< /callout >}}

{{< callout type="warning" >}}
**Actualizar authnd desde la v0.15.x: `oidc { domains }` es obligatorio**

Una configuración con un bloque `oidc` no arranca sin `domains`, y el nombre de
un token debe ser exactamente un `local@scope` de un dominio permitido: detrás
de un proxy de federación, la alice de cualquier institución se autenticaba
como la alice local. Añada `domains`, configure
`username_claim = "eduperson_principal_name"` y añada `local_domain` si los
nombres de su directorio son simples. Véase
[la nota de actualización]({{< relref "/authnd/_index.md" >}}) y
[el nombre debe tener ámbito]({{< relref "/authnd/tokens.md#scoped-name" >}}).
{{< /callout >}}

{{< callout type="warning" >}}
**Actualizar authnd desde la v0.14.x: dos valores por defecto cambian**

`max_connections` es `4096` (antes ilimitado) y `operation_timeout` es `30s` (antes
ninguno); un directorio de origen caído se responde con `unavailable` (52) y ya no con
`invalidCredentials` (49). `max_connections = 0` y `operation_timeout = "0"` dan el
comportamiento anterior. Consulte
[límites y plazos]({{< relref "/authnd/operations.md#limits" >}}).
{{< /callout >}}

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
| v0.13.2 | Solo rendimiento, con go-authn/ldap v0.11.2: `Validate` hace 12 asignaciones en lugar de 76 para una entrada de diez atributos; publicar 10 000 personas (`BenchmarkPublish10k`, `-cpu 1`) hace 128 asignaciones por entrada con las reglas y 85 sin ellas, frente a 364 y 239 en la v0.13.1, y 54,8 MiB por ejecución con las reglas frente a 102,5. Tiempos (carga de 8 a 11): unos 90 ms frente a 158 ms con las reglas |
| v0.13.3 | Solo rendimiento, con go-authn/ldap v0.11.3: una entrada que `unmet` acaba de validar no la vuelve a validar `validated` si no ha cambiado; publicar 10 000 personas (`BenchmarkPublish10k`, `-cpu 1`) hace 97 asignaciones por entrada con las reglas y 69 sin ellas, frente a 128 y 85 en la v0.13.2 (−24 % y −19 %); unos 66 ms y 36 ms (carga 4,8) |
| v0.13.4 | Una pasada de caos. Los grupos se leen una vez, al arrancar, como las personas: una búsqueda sobre 500 personas y 200 grupos de 50 en SQLite tardaba 4,13 s (cada búsqueda volvía a consultar los grupos) y tarda 1,2 ms, y una consulta de grupos que fallaba durante una búsqueda ya no quita el grupo de una respuesta que dice Success. Un origen que no se puede leer al arrancar (una consulta de grupos que no se ejecuta, una de varias bases caída) rechaza el arranque y `check`. Una entrada de más de unos 3 MiB (un solo valor de atributo de 10 MB) no se publica. La publicación se construye una vez por conjunto de personas. Resiste, con pruebas: archivos de esquema cortados en cada byte, una base eliminada o corrupta, filas hostiles, conexiones inactivas, longitudes BER desmesuradas, filtros anidados a 20 000 niveles |
| v0.14.0 | Cambiado: v0.13.4 exigía reiniciar para un cambio en un grupo, de modo que un miembro retirado de una base conservaba el acceso hasta que alguien reiniciaba authnd. v0.14.0 restablece la revocación a tiempo. `refresh` (60 s por defecto, `0` lo desactiva) vuelve a leer cada origen, personas y grupos, en una instantánea nueva construida fuera de la ruta de servicio e intercambiada entera; un refresco fallido conserva la última instantánea buena y se registra una vez por racha de fallos, nombrando el origen. `max_age` (sin definir por defecto) hace que las búsquedas, los binds de las personas y los cambios de contraseña respondan `unavailable` cuando los datos servidos son más antiguos. Una contraseña escrita a través de authnd pasa por el mismo intercambio. Medido: un refresco de 500 personas y 200 grupos de 50 en SQLite cuesta unos 2 s de un núcleo, y una búsqueda 0,5 ms (el coste del refresco se corrige en v0.14.1) |
| v0.14.1 | Solo rendimiento. Un refresco ya no crece con grupos × filas de pertenencia: directory v0.16.0 lee cada origen una sola vez, en bloque. Un refresco de 500 personas y 200 grupos de 50 en SQLite pasa de 1,87 s a 0,155 s, y el de 10 000 personas y 2 000 grupos de 391 s (seis periodos de refresco y medio) a 1,6 s (el 2,7 % del periodo de 60 s). Las asignaciones de memoria bajan de 39 959 235 a 3 095 482 y de 6 373 736 235 a 31 198 460. Los tiempos se midieron con una carga de 17 a 67 y son indicativos; los recuentos de asignaciones son exactos |
| v0.15.0 | Disponibilidad y seguridad, con go-authn/ldap v0.12.0 y go-authn/directory v0.17.0. ⛔ **Dos valores por defecto cambian**: `max_connections` es `4096` (antes ilimitado) y `operation_timeout` es `30s` (antes ninguno). Nuevo, opcional: `max_connections_per_ip` y `startup_timeout` (`60s`); [`check` imprime los límites]({{< relref "/authnd/operations.md#limits" >}}). Una conexión por encima del tope recibe `busy` y se cierra; una operación que supera el plazo recibe `timeLimitExceeded`, incluso si su manejador está bloqueado. Una caída del origen durante un bind (bind simple, cambio de contraseña, factor de contraseña de `mfa`) da `unavailable` (52), nunca `invalidCredentials` (49); una contraseña incorrecta sigue dando 49. Un arranque frente a una fuente lenta falla tras `startup_timeout`, nombrando la etapa y la fuente. [El certificado TLS se vuelve a leer]({{< relref "/authnd/tls.md#renewal" >}}) cuando cambian `cert_file` o `key_file` (primer handshake tras 5 s, y con `SIGHUP`); un par que no se carga conserva el certificado servido y se registra una vez. Los recuentos de asignaciones están en las bibliotecas de abajo; tiempo de reloj no medido (carga 21 al inicio) |
| v0.15.1 | Kerberos, con go-authn/kdc v0.5.0: una retransmisión idéntica byte a byte recibe su respuesta anterior (el *lookaside* del MIT), y una caída del directorio da `KDC_ERR_SVC_UNAVAILABLE`, nunca `KDC_ERR_PREAUTH_FAILED`, también con la contraseña correcta, así que nunca cuenta para un bloqueo. golang.org/x/net v0.62.0. Ningún cambio de configuración |
| v0.16.0 | ⛔ Seguridad, con go-authn/oidc v0.6.1 y go-authn/directory v0.18.0. **Cambio incompatible para un despliegue con un bloque `oidc`**: [`domains` es obligatorio]({{< relref "/authnd/tokens.md#scoped-name" >}}) y el servidor no arranca sin él. El nombre del token debe ser exactamente un `local@scope` de un dominio permitido (se rechaza un nombre sin ámbito, el de otra institución o uno con dos `@`); `local_domain`, opcional y uno de `domains`, asigna las personas de ese ámbito a nombres de directorio simples, y los demás ámbitos se buscan enteros, como `local@scope`. Detrás de un proxy de federación, la alice de cualquier institución se autenticaba como la alice local. Dos entradas de una misma fuente que comparten un uid son un error al arrancar y al refrescar, no una elección silenciosa. [Nota de actualización]({{< relref "/authnd/_index.md" >}}) |
| v0.16.1 | `kerberos { listen = "host:0" }` recibe un solo puerto para UDP y TCP (recibía dos, y un `krb5.conf` nombra uno); la línea de arranque nombra ese puerto. Las pruebas ya no eligen un puerto para liberarlo y luego nombrarlo, lo que fallaba en un runner con `address already in use` |
| v0.16.2 | ⛔ Seguridad. [El reino lee la instantánea]({{< relref "/authnd/kerberos.md#where-the-realm-reads-people" >}}), nunca las fuentes: cada AS-REQ y TGS-REQ, incluida una AS-REQ no autenticada por UDP, ejecutaba la consulta completa de personas de cada fuente SQL y una búsqueda de subárbol en cada origen `ldap`. `max_age` vale ahora también para Kerberos (`KDC_ERR_SVC_UNAVAILABLE` después). Una persona eliminada de una base de datos deja de obtener tickets en un periodo de `refresh`, como en los bind LDAP. Con go-authn/kdc v0.6.0 |
| v0.17.0 | ⛔ Seguridad, segunda pasada, con go-authn/ldap v0.12.1. **Cambio incompatible: [`max_age` tiene ahora un valor por defecto]({{< relref "/authnd/operations.md#it-reads-everything-once" >}})** de diez minutos (al menos diez períodos de `refresh`; sin valor por defecto con `refresh = "0"`), cuando antes era ilimitado: una persona eliminada de una fuente que después dejó de poder leerse seguía autenticándose mientras durara la caída. Pasado ese tiempo, las búsquedas, los binds de las personas y los cambios de contraseña responden `unavailable` (52); `max_age = "0"` se acepta y significa sin límite, a propósito. [El nombre de un token se compara solo con plegado de mayúsculas ASCII]({{< relref "/authnd/tokens.md#scoped-name" >}}): `Kate@univ-a.example` con un signo Kelvin (U+212A) ya no se vincula como `kate`. [Como máximo 64 comprobaciones por fuente]({{< relref "/authnd/operations.md#outage" >}}) pueden estar pendientes ante un ascendente; la 65.ª recibe `unavailable` de inmediato (400 binds contra un ascendente que nunca responde dejaban 1620 goroutines retenidas, ahora 257). [Nota de actualización]({{< relref "/authnd/_index.md" >}}) |
| v0.18.0 | [Una comprobación de contraseña ante un ascendente se cancela, no solo se acota]({{< relref "/authnd/operations.md#outage" >}}): el bind y el factor de contraseña usan `Identity.VerifyContext` (go-authn/directory v0.19.0), que cierra la conexión con el ascendente cuando termina el presupuesto del bind, de modo que no queda nada en ejecución. 400 binds contra un ascendente que nunca responde: 1620 goroutines retenidas (v0.16.2), 257 (v0.17.0, el tope), 4 (v0.18.0); el tope de 64 comprobaciones por fuente se mantiene, para las fuentes cuya comprobación no se puede cancelar. Los plegados de nombres vienen de go-authn/oidc v0.7.0. Sin cambios de configuración |
| v0.18.1 | [El plazo de arranque nombra la fuente SQL que estaba abriendo]({{< relref "/authnd/operations.md#limits" >}}): `opening sql pgx (dsn_file …) did not answer`, donde antes decía `opening sql` para cualquier bloque SQL; el controlador y el archivo que contiene el DSN, nunca el DSN. Pruebas: caos contra un PostgreSQL real en un clúster desechable (servidor detenido durante un refresco, conexión reiniciada a mitad de consulta, un oyente que nunca responde, el reino Kerberos durante una caída); se omiten sin los binarios del servidor, salvo con `AUTHND_REQUIRE_PG=1`. Sin cambios de configuración |
| v0.18.2 | [Una lectura SQL colgada ya no congela el refresco]({{< relref "/authnd/people.md" >}}): una base de datos que aceptó la conexión y dejó de responder dejaba el refresco bloqueado en la consulta, cada tic posterior se omitía, y pasado `max_age` todo respondía `unavailable` hasta reiniciar. Un bloque `users "sql"` tiene ahora `query_timeout`, por defecto tres cuartos de `refresh`, con go-authn/directory v0.20.0. **Cambio de comportamiento:** una consulta aislada más lenta que el plazo falla; fije `query_timeout` para una más lenta |
| v0.18.3 | [Devuelto significa detenido]({{< relref "/authnd/operations.md" >}}): cuando un apagado devuelve el control, la escucha LDAP y los dos sockets Kerberos están cerrados y el servidor ha terminado, de modo que un reinicio puede enlazar de inmediato. Un apagado que llegaba antes de que el servidor alcanzara la biblioteca Kerberos devolvía el control con los sockets UDP y TCP del reino aún abiertos. Sin cambios de configuración |
| v0.18.4 | Un refresco sobre un upstream LDAP hace una cuarta parte de las asignaciones de antes, con go-authn/ldap v0.12.2: la comprobación de esquema de las entradas publicadas comparaba cada par de valores `member` y analizaba ambos DN cada vez. Un refresco de 10 000 personas y 2000 grupos de 50 DN contra un upstream LDAP en el mismo proceso (`BenchmarkRefreshLDAP10k2k`, recuentos exactos): 37,6 M de asignaciones y 2,43 GB antes, 9,95 M y 651 MB después. Sin cambios de configuración |
| v0.18.5 | Un bind contra un upstream que no responde se contesta `unavailable` (52), no `timeLimitExceeded` (3), también en un host cargado. El presupuesto del bind termina antes del plazo de `operation_timeout` de la biblioteca en una décima parte de este, al menos 250 ms y como máximo la mitad; antes era solo una décima (30 ms para `"300ms"`), que un host cargado agotaba. Sin cambios de configuración |
| v0.18.6 | go-authn/ldap v0.12.3: el mismo refresco hace 8,35 M de asignaciones y 573 MB (9,95 M y 651 MB en la v0.18.4). Lo que queda es sobre todo la biblioteca de protocolo LDAP del cliente y el servidor de prueba en el mismo proceso. Sin cambios de configuración |

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
| v0.23.6 | una pasada de auditoría, fuzzing y caos, con go-authn/saml v0.5.1; no se añadió ni cambió ninguna clave de configuración. [Los metadatos se actualizan a tiempo]({{< relref "/authn-bridge/federation.md#refreshing-it" >}}): nunca programados más allá de la mitad del `validUntil` restante, y sin metadatos válidos se reintentan al cabo de un minuto, duplicando hasta una hora, de modo que una actualización fallida cerca de la caducidad ya no deja al proveedor sin IdP hasta doce horas. La clave de repetición de la aserción se guarda como su SHA-256: un `entityID` de IdP largo hacía que PostgreSQL y MySQL rechazaran la escritura y bloqueaba la base de datos de estado. El reloj puede diferir del de un IdP en tres minutos; una hora se rechaza con una página 400. [Lo que se prueba]({{< relref "/authn-bridge/federation.md#tested" >}}): envoltorio de firma XML XSW1 a XSW8, CVE-2017-11427, DOCTYPE, audiencia, destinatario, petición y destino ajenos, cinco fuzzers. Un SHA-256 por inicio de sesión cuesta de 0 a 2 asignaciones más (`BenchmarkReplayUse`: 0 asignaciones y 183 B, ahora 2 y 326 B); tiempo de reloj no medido, carga 53 a 75 |
| v0.23.7 | seguridad: un token de refresco, una contraseña de aplicación o una solicitud de certificado SSH de un IdP quitado de `saml { idps }` se rechaza en su siguiente uso, con `institution not configured`, como hace `DisableIdP` ([API de administración]({{< relref "/authn-bridge/admin.md" >}})); vuelva a poner el IdP y funcionan de nuevo |
| v0.23.8 | seguridad: [una persona se desactiva por quien es]({{< relref "/authn-bridge/admin.md" >}}): los nombres de usuario (la lista de desactivados, los principales de certificado, el subject-id) se pliegan solo con letras ASCII, con `ASCIILower` de go-authn/oidc v0.7.0, de modo que `kate` y su grafía con un signo Kelvin (U+212A) son dos personas, con dos entradas de desactivación y dos principales de certificado |
| v0.23.9 | seguridad, con go-authn/saml v0.6.0: [`schac_home_organization` se libera]({{< relref "/authn-bridge/tokens.md" >}}) en los tokens y userinfo solo si es uno de los valores `shibmd:Scope` del IdP que lo afirma (exactos, sensibles a mayúsculas). Un IdP de una institución podía afirmar la de otra, y un servicio que filtre por la reclamación (el `accept` de la pasarela) lo admitiría como esa institución. **Actualización:** un IdP cuyos metadatos no publican ningún Scope para su dominio ya no tiene la reclamación liberada |
| v0.23.10 | seguridad: [un `AuthnInstant` posterior a ahora más los tres minutos de desfase de reloj]({{< relref "/authn-bridge/federation.md" >}}) contaba como una autenticación reciente bajo `max_age` (su tiempo transcurrido resultaba negativo). Ahora es un tiempo transcurrido desconocido (OIDC Core 3.1.2.1), y a la persona se la devuelve al IdP con `ForceAuthn`, como a una caducada. Dentro del desfase nada cambia |
| v0.23.11 | [una fila de estado que la base de datos rechaza definitivamente ya no detiene todos los vaciados posteriores]({{< relref "/authn-bridge/configuration.md#state-what-a-restart-must-not-forget" >}}), revocaciones incluidas: las eliminaciones siempre fluyen, y una fila rechazada definitivamente (clase SQLSTATE 22 y 23 de PostgreSQL, MySQL 1048, 1062, 1264, 1265, 1292, 1366, 1406, 1452, SQLite constraint, mismatch, too big) se registra una vez, se cuenta en el nuevo `bridge_state_rows_rejected_total{kind}` y se abandona: funciona en memoria y no sobrevive a un reinicio |
| v0.23.12 | una fila de estado rechazada con un error que ningún clasificador conoce se abandona tras cinco vaciados a lo largo de al menos treinta segundos en los que la base de datos aceptó otra cosa mientras la fila seguía fallando; un vaciado en el que nada tiene éxito, por estar la base de datos ausente, no cuenta contra ninguna fila, de modo que **una caída no hace abandonar nada**. El comportamiento ya no depende de la lista de clases de error del controlador |

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
| v0.6.7 | una pasada de auditoría, fuzzing, caos y rendimiento ([lo que hace una sincronización]({{< relref "/authn-revokd/configuration.md#sync" >}})). Una lista que caduca se rechaza cuando caduca, no en la siguiente actualización; las fuentes se descargan en paralelo (16 como máximo, dos minutos cada una); `on_change` se mata al cabo de un minuto y se reintenta; un archivo de salida modificado a espaldas del agente se reescribe en la siguiente sincronización; una fuente `file://` debe ser un archivo regular; un error muestra una URL sin su contraseña, consulta ni fragmento; se rechaza un número de CRL fuera de `0..2^159`; el espejo tiene plazos de lectura, escritura y reposo; los archivos temporales obsoletos se eliminan al arrancar. Un CRL de 100 000 entradas consultado de nuevo: 300 138 asignaciones y 96 956 946 B por consulta, ahora 37 y 4 776 864 B (exacto; tiempos no medidos, carga 53 a 65). govulncheck sigue listando GO-2026-5932 (`golang.org/x/crypto/openpgp`), que no tiene versión corregida y no se llama |
| v0.6.8 | seguridad: [una copia de estado no verificable conserva su lugar como suelo de ordenación]({{< relref "/authn-revokd/verification.md#across-restarts-too" >}}). Un archivo de estado dañado, o escrito con otra clave de la CA, se trataba como si no hubiera copia, de modo que una lista más antigua reproducida, firmada y sin caducar, se aceptaba y deshacía la revocación de lo que la más reciente había revocado. Ahora su versión y su hora de emisión se conservan, sin verificar, como un suelo: una lista por debajo de él se rechaza como vuelta atrás hasta que se tiene una que se verifica y lo sigue, y su contenido no se usa nunca. El registro nombra el archivo que hay que eliminar, `<source>.state`, si la CA se sustituyó y sus listas vuelven a empezar con una versión más baja |
| v0.7.0 | **el comando es cobra**, como los demás de la flota: `--config`/`-c`, `--once`/`-o`, `--version`/`-v`, `--help`/`-h`, `--config=RUTA`; `--help` imprime en la salida estándar. [Las grafías con un solo guion de las versiones anteriores]({{< relref "/authn-revokd/_index.md" >}}) (`-config`, `-once`, `-version`, `-help`) se siguen aceptando, con una línea de aviso de obsolescencia por indicador en la salida de error estándar, y se eliminarán en una versión posterior. Los códigos de salida no cambian. Las unidades de `packaging/` y la guía de instalación usan la nueva grafía; las unidades desplegadas no necesitan cambios. **Actualización:** pase sus unidades y scripts a `--config` y `--once` antes de que se eliminen las antiguas |

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
| directory v0.16.0 | [cada grupo leído una vez]({{< relref "/libraries/directory.md" >}}): `GroupReader` y `Set.Frozen`, de modo que una actualización ya no crece con grupos por filas de pertenencia |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}}), con `AsUnavailable` y `TransportFailure`: ldapdir lo devuelve para busy (51), unavailable (52), other (80), timeLimitExceeded (3), conexiones cortadas o rechazadas y fallos de conexión o de TLS, en `Verify` y en cada lectura; nunca es también `ErrWrongPassword`, y `invalidCredentials` (49) sigue siendo este último. `ldaptest.Server.FailBindsWith(code)`. Un DN de miembro se asigna a una persona con una búsqueda en lugar de un recorrido, con los mismos resultados: `ReadGroups` con 10 000 personas y 2000 grupos de 50 DN asigna 13,1 MB en 0,38 M de objetos en lugar de 50,6 MB en 2,20 M, una búsqueda de DN 0 asignaciones; la actualización completa 7,17 M de asignaciones en lugar de 9,72 M (exacto; tiempos no medidos, carga 65 a 105) |
| directory v0.18.0 | [un nombre que tienen dos entradas de una misma fuente es `ErrAmbiguous`]({{< relref "/libraries/directory.md" >}}): ldapdir compara el uid sin distinguir mayúsculas y nombra los dos DN, `Set.Identities` rechaza un nombre que una fuente lista dos veces, y entre fuentes la primera sigue siendo la dueña; `ldaptest.Person.UID`. Un directorio con tales duplicados no se carga hasta corregirlos |
| directory v0.19.0 | [una comprobación de contraseña se puede cancelar]({{< relref "/libraries/directory.md" >}}): `directory.WithContextVerifier` e `Identity.VerifyContext(ctx, password)`; en una identidad de `ldapdir`, la conexión con el ascendente se cierra cuando termina el contexto y la respuesta es `ErrUnavailable` (go-ldap no tiene contexto ni tiempo de espera por defecto, así que un bind contra un ascendente que acepta y nunca responde esperaba para siempre). La conexión inicial de una comprobación también termina en el plazo del contexto. `Verify` y `WithVerifier` no cambian. **Actualización:** un servidor que acota una comprobación debe llamar a `VerifyContext` |
| directory v0.20.0 | [cada consulta tiene un plazo]({{< relref "/libraries/directory.md" >}}): `sqldir.WithQueryTimeout(d)`, por defecto `sqldir.DefaultQueryTimeout` (30 s), `0` para ninguno; cubre la lectura de las filas, y el controlador cierra la conexión al vencer el plazo (antes, una base de datos que dejaba de responder bloqueaba la lectura para siempre). `hcldir.Block.QueryTimeout` (`query_timeout` en un bloque `sql`) llega hasta ahí, comprobado sin red y rechazado en un bloque `ldap`. La interfaz `Source` no cambia. **Actualización:** una consulta de más de 30 s ahora falla; indique `WithQueryTimeout` para una más lenta |
| directory v0.21.0 | [`Set.GroupNames` informa de las fuentes que fallaron]({{< relref "/libraries/directory.md" >}}): devuelve los nombres de las fuentes que respondieron y un `errors.Join` de `"<describe>: <err>"` por cada una que falló (`errors.Is` sigue reconociendo `ErrUnavailable`); el error se descartaba siempre que otra fuente respondía. **Cambio de comportamiento:** un llamante que solo comprobaba `err != nil` ve ahora un error donde veía una lista parcial, y los nombres vuelven con él. Use los nombres y registre el error |
| fido v0.6.4 | [`PINToken` con permisos]({{< relref "/libraries/fido.md" >}}) envía `permissions` bajo la clave 0x09 y `rpId` bajo 0x0A, como las numera CTAP 2.1 (§6.5.5); usaba 0x07 y 0x08, y una YubiKey 5 respondía `CTAP2_ERR_MISSING_PARAMETER` (0x14) |
| kdc v0.4.3 | solo dependencias: go-authn/directory v0.12.0 como mínimo |
| kdc v0.4.5 | una pasada de auditoría de seguridad, fuzzing y caos ([lo que rechaza]({{< relref "/libraries/kdc.md" >}})): una petición para otro reino se responde con `KDC_ERR_WRONG_REALM`, un directorio ilegible con `KDC_ERR_SVC_UNAVAILABLE` (era `KDC_ERR_C_PRINCIPAL_UNKNOWN`), se acepta un TGT cuyo inicio está dentro de `MaxSkew` en el futuro, y un pánico del decodificador descarta una petición en lugar de hacer caer el proceso (una sola AS-REQ o TGS-REQ mal formada podía hacerlo caer); los nombres de principal se entrecomillan en el registro. golang.org/x/net v0.62.0, go-authn/directory v0.16.1 |
| kdc v0.5.0 | [el *lookaside*]({{< relref "/libraries/kdc.md" >}}) del KDC del MIT: una solicitud ya vista, byte a byte, recibe su respuesta anterior, durante dos minutos y por debajo de 10 MiB en total; un `KRB-ERROR` nunca se guarda; a propósito no hay caché de repetición de autenticadores, que el MIT desactiva en el TGS. Las pruebas fijan un directorio ilegible en `KDC_ERR_SVC_UNAVAILABLE` en el AS, con la contraseña correcta, y en el TGS. Dos asignaciones más por solicitud |
| kdc v0.6.0 | [`Finder`]({{< relref "/libraries/kdc.md#finder" >}}): a una fuente que mantiene un índice por nombre se le pregunta en lugar de recorrerla. Con 10 000 personas el recorrido era la mitad de la CPU de una AS-REQ; con un `Finder` la búsqueda queda por debajo del umbral del perfil. Una respuesta cuyo nombre difiere del principal es un principal desconocido (un principal distingue mayúsculas y minúsculas) |
| keyfactor v0.4.2 | solo dependencias: go-authn/fido v0.6.2 y golang.org/x/crypto v0.58.0 como mínimos |
| krb5 v0.3.1 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| krb5 v0.3.3 | solo dependencias: golang.org/x/net v0.62.0, golang.org/x/crypto v0.58.0 y go-uuid v1.0.4 eliminan 45 de los 46 hallazgos de `govulncheck` en módulos requeridos y no llamados; GO-2026-5932 (`x/crypto/openpgp`) no tiene corrección y ningún módulo go-authn lo importa; sin cambio de API |
| krl v0.6.1 | solo dependencias: golang.org/x/crypto v0.58.0; probada con Go 1.27.2 |
| ldap v0.8.0 | [el paquete `schema`]({{< relref "/libraries/ldap.md#the-schema" >}}) y `Server.Schema`: `cn=Subschema` (RFC 4512 §4.2), `Validate`, las reglas de comparación del RFC 4517; `uidNumber` y `gidNumber` se ordenan como enteros; una búsqueda paginada se ciñe a los atributos pedidos |
| ldap v0.9.0 | [los esquemas en HCL2]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}}): el paquete `schema/hclschema` y el comando `ldapschema` (`to-hcl`, `to-schema`, `check`) entre `.schema` de OpenLDAP, LDIF cn=config y HCL2; los lectores leen los archivos como slapd; las reglas de contenido y de estructura del DIT, las formas de nombre, `include` y `X-SUBST` no se admiten (la v0.11.0 admite las reglas) |
| ldap v0.10.0 | [un `*schema.BuildError` tipado]({{< relref "/libraries/ldap.md#build-error" >}}) para una definición que `Build` rechaza, que se obtiene con `errors.As`: `Kind`, `Element`, `OID`, `Name`, `Field`, `Pos` (archivo:línea:columna donde empieza la definición, también para LDIF plegado o en base64 y para HCL), y `Ref`, `RefOID` y `RefPos` para la otra definición; toda definición leída lleva una `Pos`; «clases de objeto» en un mensaje |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) es lineal en el número de líneas de continuación (era cuadrático: un archivo de 4 MiB tardaba unos tres minutos) y ya no copia ni divide todo el archivo para leer su primera línea; `schema.Format` pliega las líneas de más de 2000 bytes, que slapd y `Read` rechazan; el analizador estricto es unas 2,6 veces más rápido (147 asignaciones en lugar de 498 en `cosine.schema`, medido bajo carga) |
| ldap v0.10.2 | los DESC de 13 definiciones de RFC 2307 del esquema incorporado (`schema.Standard()`) van en una sola línea: llevaban la sangría de la paginación de la RFC, que el lector conserva dentro de las comillas como slapd, así que el subesquema que publicaba un servidor tenía series de espacios; una prueba comprueba ahora cada DESC incorporado y, donde se define el mismo OID, lo compara con los esquemas `core`, `cosine`, `inetorgperson` y `nis` de OpenLDAP |
| ldap v0.11.0 | [reglas de contenido DIT, formas de nombre y reglas de estructura DIT]({{< relref "/libraries/ldap.md#rules" >}}) (RFC 4512 §4.1.6, §4.1.7) leídas de `.schema` y LDIF, escritas por `Format`, transportadas por HCL (`dit_content_rule`, `name_form`, `dit_structure_rule`) y por `ldapschema`, comprobadas por `Build`, aplicadas por `Validate` (reglas de contenido: AUX, MUST, MAY, NOT; formas de nombre: el RDN; reglas de estructura: `GoverningStructureRule`) y publicadas en `cn=Subschema` solo cuando existen; `ValidateOptions{StrictAuxiliary}` da el RFC 4512 §2.4.3. ⛔ slapd solo implementa las reglas de contenido, así que `Format` escribe las palabras clave `nameform` y `ditstructurerule`, que él rechaza; una regla `OBSOLETE` está inactiva donde slapd rechaza la entrada; libldap no puede leer el `SUP` de una regla de estructura. `hclschema.Decode` rechaza una cadena que no es UTF-8 |
| ldap v0.11.1 | Solo rendimiento, sin cambio de resultado: una cadena de ASCII imprimible se prepara para las reglas de comparación de cadenas (RFC 4518) con una asignación como máximo, ninguna cuando nada cambia, y el analizador de DN hace 6 asignaciones en lugar de 11 para un DN de cuatro RDN. Los resultados son los de la v0.11.0, comprobados contra su código en cada cadena de uno o dos bytes por debajo de 0x80 y con un fuzzer diferencial |
| ldap v0.11.2 | Solo rendimiento, sin cambio de resultado: `Validate` hace 12 asignaciones para una entrada de diez atributos en lugar de 76 (búsquedas sin copia en minúsculas, descripciones sin dividir ni volver a unir, conjuntos en el sitio en lugar de mapas). Los resultados son los de la v0.11.1, comprobados contra una copia de su `Validate` con entradas aleatorias bajo el esquema estándar y un esquema con reglas, y con un fuzzer diferencial |
| ldap v0.11.3 | Solo rendimiento, sin cambio de resultado: `GoverningStructureRule` hace 5 asignaciones en lugar de 12 para una cuenta (lee solo los tipos del RDN), y el analizador de DN 3 en lugar de 6 para un DN de cuatro RDN. Los resultados son los de la v0.11.2, comprobados contra una copia de su `GoverningStructureRule` con entradas aleatorias y cada regla superior, y con un fuzzer diferencial |
| ldap v0.12.0 | [límites de recursos para el servidor]({{< relref "/libraries/ldap.md" >}}): `Server.MaxConnections` y `Server.MaxConnectionsPerIP` (0 por defecto, sin límite; una conexión por encima de un tope recibe un aviso de desconexión `busy` (51), RFC 4511 4.4.1, y se cierra); el servidor aplica `Server.Timeout`, y responde `timeLimitExceeded` (3) en cualquier operación al vencer el plazo incluso si el manejador está bloqueado e ignora su contexto (el resultado tardío se descarta, y la goroutine cuenta contra `MaxPending` y `MaxPendingAuth` hasta que vuelve); el `timeLimit` de búsqueda del cliente se aplica al contexto del manejador; un `DeadlineExceeded` de manejador se traduce al código 3 solo cuando el contexto propio de la operación ha vencido. Asignaciones por operación (exacto): 3 antes y después sin `Timeout`; 10 antes y 16 ahora con uno |
| ldap v0.12.1 | [un bind abandona las búsquedas paginadas en curso]({{< relref "/libraries/ldap.md" >}}) (RFC 4511 4.2.1): una búsqueda iniciada por una persona ya no sigue entregando a la conexión cuando esta es anónima o de otra persona |
| ldap v0.12.2 | la comprobación de valores duplicados de `Validate` encuentra valores iguales con una clave, en lugar de comparar cada par: un `groupOfNames` de 50 DN `member` hace 1065 asignaciones y 68 KB en lugar de 14 907 y 959 KB (exacto). Las respuestas son las de la comprobación por pares, comparadas en listas aleatorias |
| ldap v0.12.3 | un DN simple (RDN de `type=value`, ASCII imprimible, sin escape) obtiene su clave de sus bytes con una asignación en lugar de 17, y cualquier otro DN toma el análisis completo; 265 asignaciones por grupo de 50. Las claves son las del análisis completo, sostenidas por una prueba diferencial y un fuzzer (39 M de ejecuciones) |
| oidc v0.4.1 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| oidc v0.6.1 | [`ScopedName`]({{< relref "/libraries/oidc.md#scoped-names" >}}) rechaza un nombre con más de un `@` (`ErrBadName`) |
| oidc v0.7.0 | [`ASCIILower` y `EqualASCIIFold`]({{< relref "/libraries/oidc.md#scoped-names" >}}): el único plegado solo ASCII para nombres, porque `strings.ToLower` y `strings.EqualFold` pliegan Unicode e igualan el signo Kelvin U+212A con "k" |
| saml v0.6.0 | [`schacHomeOrganization` se ciñe a los valores `shibmd:Scope` del IdP]({{< relref "/libraries/saml.md" >}}) (exactos, sensibles a mayúsculas) y se descarta en caso contrario, como ya ocurría con `eduPersonPrincipalName`, `subject-id`, `pairwise-id` y la afiliación con ámbito (las páginas de atributos de SWITCH y SAFIRE lo piden a una parte confiante). **Actualización:** un IdP cuyos metadatos no publican ningún Scope para su dominio ya no tiene el atributo leído |
| saml v0.6.1 | [cuatro objetivos de fuzzing y pruebas de entrada hostil]({{< relref "/libraries/saml.md#fuzzing" >}}): `FuzzAccept`, `FuzzParseMetadata`, `FuzzDecrypt` y `FuzzLimits`, con el corpus versionado y reproducido por `go test`, y de 1,1 a 5,1 millones de ejecuciones de cada uno sin ningún cuelgue, fallo ni violación de propiedad; se rechazan una bomba billion-laughs, una entidad externa, 80 000 y 1 048 576 niveles de anidamiento, 60 000 hermanos, un `CipherValue` y una respuesta de tamaño excesivo, con 4 a 8 MiB asignados como máximo. Un trabajo `fuzz` ejecuta cada objetivo 30 s en la CI. Sin cambio de comportamiento |
| scim v0.2.0 | [una pasada de auditoría, fuzzing, caos y rendimiento]({{< relref "/libraries/scim.md#v020" >}}): `Server.ReadTimeout` (30 s), la interfaz opcional `ConditionalDeleter`, un PATCH o PUT sin `If-Match` rehecho hasta 32 veces tras una carrera perdida en lugar de responder 412, quitar mediante un filtro que no coincide con nada tiene éxito, las claves de un PATCH sin ruta se aplican en orden ordenado, `BearerAuth` acepta el esquema en cualquier caso, `startIndex` y `count` acotados sea cual sea el ancho de palabra. Una petición de lista sobre 10 000 usuarios: una página de 100 de 789 417 a 14 952 asignaciones, `userName eq` de 797 979 a 90, un recorrido completo de 818 847 a 361 098 (exacto; tiempos no medidos, carga 65) |
| scim v0.2.1 | [`If-None-Match` según la RFC 7232 §3.2]({{< relref "/libraries/scim.md#v021" >}}): listas de etiquetas de entidad, `*`, comparación débil, y el 304 lleva el `ETag`; `Memory` comprueba la unicidad de `userName` mediante un índice (O(N) en lugar de O(N^2) llamadas a `EqualFold` para cargar N usuarios); un filtro de lista que ningún índice responde se evalúa sobre los atributos de primer nivel que nombra: de 361 095 a 162 695 asignaciones por petición sobre 10 000 usuarios, de 36,1 a 16,3 por usuario (exacto) |
| servercert v0.5.2 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| servercert v0.6.0 | [la `KeyFile` TLS y la `EABHMACKeyFile` ACME se rechazan]({{< relref "/libraries/servercert.md" >}}) cuando el grupo u otros pueden leerlas o escribirlas, en `New` y en cada recarga (una clave de reemplazo legible se notifica a `OnError` y no se toma; el certificado actual sigue sirviéndose); no se comprueba en Windows. **Actualización:** `chmod 600` en ambos archivos |
| totp v0.4.2 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| wireguard v0.1.1 | probada con Go 1.27.2; no cambian ni el código ni el `go.mod` |
| wireguard v0.1.4 | las peticiones de token y de lista de la fuente ya no siguen redirecciones, porque llevan el secreto Basic o el token Bearer; una redirección es un error ([qué rechaza]({{< relref "/libraries/wireguard.md" >}})) |

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
