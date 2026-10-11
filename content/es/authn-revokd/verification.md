---
title: "Cómo se verifica una lista"
linkTitle: "Verificación"
weight: 30
description: "Lo que comprueba authn-revokd antes de conservar una lista: la firma, las fechas, y que nunca sea más antigua que la lista que tiene, también entre reinicios."
tags: [authn-revokd, revocación, seguridad]
---

Una lista que no se verifica nunca se escribe, se sirve ni se usa. La última copia
buena se queda. Una descarga que falla, por el motivo que sea, nunca la sustituye por
una respuesta vacía, que no revocaría nada.

## La firma {#the-signature}

**Una KRL** se descarga con su firma, `<url>.sig`: un SSHSIG en formato armored sobre
todo el archivo, hecho con la **clave de la CA SSH** configurada como `ssh_ca`, en el
espacio de nombres `krl@go-authn.github.io`. El espacio de nombres impide que la firma
se tome por cualquier otra cosa. Un firmante calcula el hash con SHA-512; también se
acepta SHA-256. Una firma RSA en la forma SHA-1, que PROTOCOL.sshsig prohíbe, se
rechaza.

La propia KRL debe poder analizarse como la analiza `sshd`, y no debe llevar la
sección de firma propia de OpenSSH, que OpenSSH nunca verifica.

Una lista firmada con cualquier otra clave se rechaza:

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:SLbG7N+YZ/TQ6B3I1DQLYo2/6In4OWx5GYkRfKIxpxo: public key does not match
bridge-x509: version 1791665695047, issued 2026-10-10T20:54:55Z, expires 2026-10-10T21:54:55Z
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/other.krl
output tls: wrote /tmp/docs-patch-a2daf7c8/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

Aquí `ssh_ca` nombraba una clave que no firmó la lista del bridge, y el error nombra
esa clave. Una firma que no se verifica también puede deberse a una lista emitida de
nuevo entre las dos peticiones, así que ambas se descargan una vez más antes de
informar. Era la primera descarga de ese origen, así que no había ninguna copia buena
que conservar, y la salida es directamente la
[lista en modo cerrado]({{< relref "/authn-revokd/lapse.md" >}}). (Antes de la v0.6.2,
el mismo fallo llevaba "the list changed between it and its signature" delante del
mensaje anterior, como si la lista se hubiera emitido de nuevo.)

La firma se descarga con `If-Match: <the list's ETag>`. Una lista emitida de nuevo
entre las dos peticiones responde `412`, y ambas se descargan otra vez.

**Una CRL** se comprueba contra el certificado de CA configurado como `x509_ca`:
primero su firma, sobre los bytes en bruto, **antes** de analizar el resto, de modo
que una CRL grande firmada por cualquiera cuesta una comprobación de firma y no un
análisis. Después, su emisor debe ser el sujeto de ese certificado; debe tener un CRL
Number y un `nextUpdate` posterior a su `thisUpdate`; y no debe ser una CRL delta, ni
llevar una extensión crítica distinta del CRL Number y del Authority Key Identifier,
ni una extensión de entrada crítica.

Una KRL también debe **decir cuándo caduca**, en la extensión
`expires@go-authn.github.io`: una que no lo dice nunca podría distinguirse de una
desfasada.

Los cuerpos tienen límites: una KRL, 32 MiB; su firma, 64 KiB; una CRL, 64 MiB.

## Las fechas {#the-dates}

Una lista está vigente cuando:

- el momento actual es anterior a su caducidad (la extensión de la KRL, el
  `nextUpdate` de la CRL);
- no se emitió más de cinco minutos en el futuro: un emisor cuyo reloj va adelantado
  más que eso escribe listas cuya antigüedad no se puede conocer;
- con `max_age`, no se emitió hace más tiempo que eso.

Una lista que no está vigente se rechaza al descargarla. Un `304 Not Modified` no es
ninguna novedad: la copia guardada puede haber caducado desde entonces, y se vuelve a
juzgar en cada sincronización.

## Nunca más antigua que la lista guardada {#never-older-than-the-list-held}

La posición de una lista es su **versión** (el `krl_version` de la KRL, el CRL Number),
y después su **momento de emisión** (la fecha de generación de la KRL, el `thisUpdate`
de la CRL). Una lista solo puede sustituir a la guardada cuando tiene una versión más
alta, o la misma versión emitida más tarde: las mismas revocaciones, emitidas de nuevo
con una nueva caducidad. Cualquier otra cosa es una vuelta atrás: una lista más
antigua reproducida o restaurada, todavía firmada y sin caducar, que anularía la
revocación de lo que la más reciente revocó.

### También entre reinicios {#across-restarts-too}

La lista guardada se conserva en `state_dir`, un archivo por origen que contiene la
lista y su firma juntas, escrito con un único renombrado y con el directorio
sincronizado. Al arrancar, cada copia **se verifica de nuevo** (caducada o no, ordena
lo que viene después), y una copia que ya no se verifica no merece confianza, ni
siquiera para ordenar la siguiente, y así se indica en el registro.

Aquí, tras un reinicio, se hace apuntar un origen a una lista que un proceso bridge
anterior sirvió catorce segundos antes, todavía firmada y todavía sin caducar:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-10T20:54:50Z, expires 2026-10-10T21:54:50Z
bridge-x509: version 1791665695047, issued 2026-10-10T20:54:55Z, expires 2026-10-10T21:54:55Z
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/sshd.krl
output tls: wrote /tmp/docs-patch-a2daf7c8/revokd/out/bridge.crl
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/docs-patch-a2daf7c8/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-10T20:54:36Z, the copy held at 2026-10-10T20:54:50Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-10T21:54:50Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261010T225450
# Comment: authn-revokd sshd
```

La lista más antigua se rechaza y la salida conserva la más reciente. El proceso que
la rechazó nunca había visto la lista más reciente: la releyó de `state_dir`.

Como el estado es lo que permite detectar una vuelta atrás, el directorio se somete a
la regla StrictModes de sshd ([la configuración]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}})).
Un fallo entre dos escrituras no puede dejar un par que no se verifique, lo que se
llevaría consigo la protección contra la vuelta atrás: la lista y su firma son un solo
archivo.

## Lo que informa `-once` {#what--once-reports}

`-once` termina con `1` cuando un origen no tiene lista vigente, cuando su **última
descarga falló**, o cuando no se pudo escribir una salida, y su última línea dice cuál
de los dos primeros casos es:

| última línea | el origen | sus salidas |
|---|---|---|
| `not current: <source>` | no tiene ninguna lista vigente: nunca descargada, caducada, o más allá de `max_age` | en modo cerrado para sshd |
| `not fetched: <source> (the list held is current until <T>)` | su descarga falló, pero la copia guardada sigue vigente | escritas a partir de esa copia, sin cambios, hasta `T` |

Aquí el emisor está detenido mientras las dos listas guardadas siguen vigentes:

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-10T21:54:50Z), bridge-x509 (the list held is current until 2026-10-10T21:54:55Z)
```

Esa ejecución dejó `sshd.krl` como estaba. En cuanto caduca una lista guardada, el
mismo origen se notifica como `not current`, y ambos tipos pueden compartir la línea,
como en [cuando una lista caduca]({{< relref "/authn-revokd/lapse.md" >}}). Antes de la
v0.6.2, ambos casos se notificaban como `not current`, lo que decía que una lista había
caducado cuando solo había fallado su descarga; el código de salida ya era `1`
entonces.

El `/healthz` del espejo juzga en cambio por la copia guardada, y respondió `ok`
mientras el emisor estaba caído y las copias seguían vigentes.
