---
title: "Ejecutarlo: señales, reinicios y lo que dice"
linkTitle: "Operación"
weight: 80
description: "Qué lee authnd una sola vez, por qué SIGHUP no lo recarga, cómo se detiene, qué escribe en su salida, y cómo saber que está en marcha."
tags: [authnd, operación, señales, systemd]
---

## Lo lee todo una sola vez {#it-reads-everything-once}

Los archivos de configuración, todos los orígenes que hay detrás, el certificado TLS
y la keytab se leen **al arrancar**. No hay recarga, y la unidad empaquetada no tiene
`ExecReload=`. Después de cambiar cualquiera de ellos:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

Lo único que se aplica mientras se ejecuta es una
[contraseña que una persona cambia a través de authnd]({{< relref "/authnd/passwords.md" >}}),
que vuelve a leer los bloques `user` y nada más.

## Señales {#signals}

| señal | qué ocurre |
|---|---|
| `SIGTERM`, `SIGINT` | imprime `stopping`, cierra las escuchas **y todas las conexiones establecidas**, detiene el reino, cierra los orígenes, y termina con 0 una vez que el servidor ha terminado de verdad |
| `SIGHUP` | se captura y se registra, y authnd **sigue en marcha** sin recargar nada |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
hangup: authnd does not reload; restart it to apply a changed configuration, certificate or keytab
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

Eso es una sola ejecución: un `kill -HUP`, dos intentos de cambiar una contraseña
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
vendorVersion: v0.12.0
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
