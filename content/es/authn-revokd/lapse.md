---
title: "Cuando una lista caduca"
linkTitle: "Cuando una lista caduca"
weight: 40
description: "Lo que authn-revokd escribe para sshd cuando no tiene ninguna lista vigente de una CA: una KRL que revoca la propia clave de la CA, de modo que se rechaza cada certificado de esa CA."
tags: [authn-revokd, revocation, fail closed, sshd]
---

Una comprobación de revocación que deja pasar todo cuando no se puede obtener la
lista es la que derrota un atacante capaz de bloquear la lista. Así que cuando
authn-revokd no tiene ninguna lista vigente de un origen, lo que protege la lista de
ese origen se **rechaza**, hasta que vuelva a llegar una lista vigente.

| salida | mientras un origen no tiene lista vigente |
|---|---|
| una KRL, para `sshd` | authn-revokd escribe una KRL que **revoca la clave de la CA del origen** |
| una CRL, para un servidor TLS | la CRL caducada se deja en su sitio; OpenSSL rechaza por sí solo una CRL caducada |

## Para sshd: revocar la propia CA {#for-sshd-revoking-the-ca-itself}

`sshd` no tiene noción de la caducidad de una lista: seguiría leyendo para siempre el
último archivo escrito. Pero sí comprueba la **clave de la CA** de cada certificado
contra `RevokedKeys`. Así que, en lugar de la lista que no puede avalar, authn-revokd
pone en la salida la propia clave de la CA, y se rechaza cada certificado que firmó
esa CA, y nada más.

Aquí el emisor está detenido, y el origen KRL tiene `max_age = "30s"`, de modo que la
copia guardada caduca en menos de un minuto en lugar de una hora. El origen CRL no
tiene `max_age`, y su copia sigue vigente:

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/docs-patch-a2daf7c8/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-10T21:54:55Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:2zKzlmqkMRAvBYIAisepe9ulFWDmDbTVCjcfCylTkOo # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh` está `not current`, y su salida está en modo cerrado; `bridge-x509` solo
está `not fetched`, y su CRL se deja como estaba
([lo que informa `-once`]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})).
`SHA256:2zKz...` es la CA SSH del bridge. Un certificado firmado por ella queda ahora
revocado para todo lo que lea el archivo:

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

El comentario dice `FAIL CLOSED` y nombra el origen, así que una persona que lea
`ssh-keygen -Q -l` ve por qué. La fecha del archivo es 1970 cuando todos los orígenes
han caducado. La salida se escribe **en cuanto una sincronización lo detecta**, que
para el demonio es su siguiente `refresh` y para el temporizador su siguiente disparo.
Cuando vuelve a llegar una lista vigente, la siguiente sincronización la escribe en
lugar de la clave de la CA, y los certificados de la CA vuelven a aceptarse.

Lo mismo ocurre **antes de la primera lista**: un origen que nunca se ha descargado no
tiene nada vigente, y su CA queda revocada desde la primera escritura. Una instalación
nueva rechaza los certificados de la CA hasta que su primera lista se verifica, en
lugar de aceptarlos sin comprobar.

### Cada CA por su cuenta {#each-ca-for-itself}

En una salida que fusiona varios orígenes, solo se revoca la CA del origen caducado.
Los demás conservan sus listas. Una lista que no se puede fusionar (más allá de los
rangos de números de serie que admite go-authn/krl) falla en modo cerrado solo para su
propia CA, y `/healthz` la nombra. Solo si las listas se fusionan por separado pero no
juntas se revocan todas las CA de la salida, y el comentario lo dice
(`FAIL CLOSED, the output could not be rendered`). Conservar el archivo anterior en su
lugar dejaría pasar desapercibida una caducidad posterior.

## Para un servidor TLS: la propia CRL {#for-a-tls-server-the-crl-itself}

Una CRL ya dice cuándo deja de estar vigente, y OpenSSL rechaza una que ha pasado su
`nextUpdate` ("CRL has expired"). Así que authn-revokd deja en su sitio la última CRL
verificada, y el servidor TLS falla en modo cerrado por sí solo. Por eso también se
rechaza `max_age` en un origen que alimenta una salida CRL: un servidor que ha cargado
la CRL la conserva hasta su `nextUpdate`, escriba lo que escriba authn-revokd.

## Lectores que comprueban la caducidad por sí mismos {#readers-that-check-the-expiry-themselves}

La KRL fusionada lleva una caducidad, la primera de sus entradas vigentes. Un lector
que la comprueba, como el `ssh_krl_file` de go-fileshare o
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}}),
ve detenerse authn-revokd igual que vería detenerse el emisor.

{{< callout type="warning" >}}
**Esto solo funciona mientras authn-revokd se ejecuta**

Es authn-revokd quien pone el archivo en modo cerrado. Mientras está detenido, sshd
sigue leyendo el último archivo escrito, vigente o no. De ahí `Restart=always` en el
demonio, y la supervisión de la unidad, o del temporizador, o de `/healthz`.
{{< /callout >}}
