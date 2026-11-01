---
title: "Ejecutarlo: señales, reinicios y lo que dice"
linkTitle: "Operación"
weight: 80
description: "Qué lee authnd una sola vez, por qué SIGHUP no lo recarga, cómo se detiene, qué escribe en su salida, y cómo saber que está en marcha."
tags: [authnd, operación, señales, systemd]
---

## Lo lee todo una sola vez {#it-reads-everything-once}

Los archivos de configuración y la keytab se leen **al arrancar**. No hay recarga
de ellos, y la unidad empaquetada no tiene `ExecReload=`. Después de cambiar
cualquiera de los dos:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

El certificado TLS es la excepción desde la v0.15.0: authnd vuelve a mirar
`cert_file` y `key_file`, de modo que una renovación no necesita reinicio. Consulte
[renovar el certificado]({{< relref "/authnd/tls.md#renewal" >}}).

Aparte de los orígenes (véase abajo), lo único que se aplica mientras se ejecuta es una
[contraseña que una persona cambia a través de authnd]({{< relref "/authnd/passwords.md" >}}),
que vuelve a leer los bloques `user` y nada más.

Los orígenes son la excepción a «se lee una vez». Las personas y los grupos se
vuelven a leer en cada `refresh` (60 s por defecto; `refresh = "0"` lo desactiva)
en una instantánea nueva construida fuera de la ruta de servicio e intercambiada
de forma atómica, de modo que una persona o un miembro de grupo retirado desaparece
en un periodo, sin reiniciar. (v0.13.4 los leía una vez y exigía reiniciar para un
cambio en un grupo.) Un refresco fallido conserva los últimos datos buenos y se
registra una vez por racha de fallos, nombrando el origen. Donde la revocación
importa, defina `max_age` (por ejemplo `"10m"`): cuando los datos son más antiguos,
las búsquedas, los binds de las personas y los cambios de contraseña responden
`unavailable` (52) en lugar de datos obsoletos. Un origen que no se puede leer al arrancar, como una consulta de
grupos que no se ejecuta o una de varias bases caída, rechaza el arranque y
`check`, nombrando el origen y el grupo. Una entrada demasiado grande para un
mensaje LDAP (unos 3 MiB, que basta un solo valor de atributo de 10 MB para
alcanzar) no se publica, y se dice al arrancar y con `check`, como una entrada
que no cumple el esquema.

## Señales {#signals}

| señal | qué ocurre |
|---|---|
| `SIGTERM`, `SIGINT` | imprime `stopping`, cierra las escuchas **y todas las conexiones establecidas**, detiene el reino, cierra los orígenes, y termina con 0 una vez que el servidor ha terminado de verdad |
| `SIGHUP` | se captura y se registra, y authnd **sigue en marcha**. Vuelve a leer el certificado TLS de inmediato (v0.15.0); la configuración y la keytab no se recargan |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 1 person from the configuration file
hangup: authnd does not reload its configuration or keytab; restart it to apply those (the TLS certificate is read again)
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

Eso es una sola ejecución del binario v0.15.0: un `kill -HUP`, dos intentos de cambiar una contraseña
(el primero rechazado, el segundo aceptado), y después un `kill -TERM`. El proceso seguía ahí después del `SIGHUP`.

Un `SIGHUP` antes **mataba** authnd —lo que hace Go por defecto con una señal que
nadie maneja—, y systemd cuenta la muerte por `SIGHUP` como una salida limpia, así que
`Restart=on-failure` no lo volvía a arrancar: un solo `kill -HUP` o un solo
`postrotate` de logrotate dejaba un directorio fuera de servicio para siempre. Ahora se
captura para que la costumbre sea inofensiva, y la línea dice qué hacer en su lugar.

Cerrar las conexiones establecidas, no solo la escucha, es deliberado: un servidor
que dejara de aceptar y dejara sus conexiones abiertas respondiendo parecería
detenido sin estarlo, que es el reinicio que no surte efecto.

## Lo que escribe {#what-it-writes}

Todo va a la salida estándar, que con systemd es el journal (`journalctl -u authnd`):

- al arrancar, dónde escucha y a quién sirve —`ldap on …`, `ldaps on …` o
  `ldap+starttls on …`, y después `realm EXAMPLE.ORG on … (udp and tcp)` con un bloque
  `kerberos`—;
- cada bind rechazado bajo un bloque `mfa`, cada token rechazado, cada cambio de
  contraseña rechazado o completado, **con el motivo**, que nunca se le dice al
  cliente; consulte [el segundo factor]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})
  y [los tokens]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}});
- cada petición que el KDC rechaza, con el prefijo `kerberos:` y el código de error
  de Kerberos; consulte [el reino]({{< relref "/authnd/kerberos.md#kinit-against-it" >}});
- el propio registro de la biblioteca LDAP, en formato de texto `slog`, con nivel info.

Una simple contraseña incorrecta en un bind simple, sin bloque `mfa`, se responde con
`invalidCredentials` y authnd no la registra.

## Límites y plazos {#limits}

Desde la v0.15.0 authnd acota lo que un cliente, una fuente lenta o una avalancha
pueden obligarle a retener. Cuatro claves opcionales, en el nivel superior de la
configuración:

| clave | por defecto | significado |
|---|---|---|
| `max_connections` | `4096` (antes ilimitado) | el máximo de conexiones abiertas a la vez; `0` es ilimitado |
| `max_connections_per_ip` | ninguno | el máximo desde una dirección; no puede superar `max_connections` |
| `operation_timeout` | `30s` (antes ninguno) | lo máximo que puede durar una operación LDAP; `"0"` es ninguno, si no al menos `100ms` |
| `startup_timeout` | `60s` | lo máximo que puede durar abrir y leer por primera vez todas las fuentes; `"0"` es ninguno |

Una conexión por encima de un tope recibe `busy` (51) en un aviso de desconexión y
se cierra, nunca se pone en cola (RFC 4511 4.4.1). Una operación que sigue en curso
en `operation_timeout` recibe `timeLimitExceeded` (3), **incluso si su manejador está
bloqueado e ignora el plazo**: el resultado tardío se descarta. Una fuente que no
responde al arrancar hace que authnd se niegue a arrancar tras `startup_timeout`, con
un error que nombra la etapa y la fuente. Un número negativo, o una duración que no
se lee, se rechaza al arrancar y por `check`. Ponga `max_connections = 0` y
`operation_timeout = "0"` para el comportamiento de la v0.14.

`check` imprime los límites con los que servirá, para que nadie ejecute los valores
por defecto sin saberlo:

```
$ authnd check etc2/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org
limits: 200 connections, 20 per address; an operation may take 10s; startup may take no limit

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid

GROUP  MEMBERS  PUBLISHED AS
staff  alice    groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Esa configuración dice `max_connections = 200`, `max_connections_per_ip = 20`,
`operation_timeout = "10s"` y `startup_timeout = "0"`. Sin esas cuatro claves la línea
es `limits: 4096 connections, no limit per address; an operation may take 30s; startup
may take 1m0s`, que el mismo binario también imprimió.

### Una caída no es una contraseña incorrecta {#outage}

Cuando las personas se comprueban contra otro directorio (una fuente `ldap`) y ese
directorio no se puede consultar, porque la conexión se rechaza o se restablece,
responde `busy`, `unavailable` o `other`, o no responde dentro de `operation_timeout`,
authnd responde LDAP `unavailable` (52), **nunca** `invalidCredentials` (49). Esto vale
para un bind simple, para la contraseña antigua de un cambio de contraseña y para el
factor de contraseña de un bind `mfa`. Antes de la v0.15.0 se informaba como una
contraseña incorrecta, de modo que un formulario de inicio de sesión decía a la persona
que su contraseña era incorrecta mientras el directorio estaba caído. Una contraseña
incorrecta sigue dando 49. La causa está en el registro, no en lo que se dice al
cliente, y una caída no cuenta como un intento fallido.

## Cuando no arranca {#when-it-does-not-start}

Un rechazo es una línea en la salida de error estándar, con el prefijo `authnd:`, y el
código de salida 1; con la unidad, `Restart=on-failure` vuelve a intentarlo cada cinco
segundos y la línea aparece en el journal cada vez. Todo lo que `check` rechaza se
rechaza también aquí, y lo único que solo encuentra el servidor es una dirección en la
que no puede escuchar; consulte
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
La escucha LDAP, el certificado y el reino se abren antes de imprimir la primera línea,
así que un servidor que no puede arrancar solo imprime el rechazo. Aquí una segunda
instancia se encuentra con el puerto Kerberos de la primera:

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

La línea `ldap on …`, y `realm … on …` tras ella, significan que las dos mitades están
escuchando.

## Saber que está en marcha {#telling-that-it-is-up}

No hay endpoint de salud ni métricas. Lo que hay:

- **el proceso y su código de salida**: con systemd, `systemctl is-active
  authnd`. Si la escucha LDAP o el reino se detienen por sí solos, todo el proceso
  termina con ese error, así que un proceso vivo es uno cuyas dos mitades responden;
- **el root DSE**, que responde a un cliente anónimo y dice con qué versión se está
  hablando:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.13.0
```

En una [escucha StartTLS]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}})
esa consulta necesita `-ZZ`. Una sonda que prueba más —que un origen sigue
respondiendo— es un bind como una persona o como un reader reservado para ello; con un
bloque `users "ldap"`, ese bind llega al directorio que hay detrás de este.

## Qué vive dónde, y qué pierde un reinicio {#what-lives-where-and-what-a-restart-loses}

| | |
|---|---|
| configuración, contraseñas, DSN, certificado, keytab | los archivos que nombra la configuración; no se copia nada |
| una base de datos SQLite | donde diga su DSN; `/var/lib/authnd` con la unidad |
| recuentos y bloqueos del segundo factor | solo en memoria: **un reinicio los olvida**, incluida una persona bloqueada tras cien códigos incorrectos |
| códigos de un solo uso ya utilizados | solo en memoria |
