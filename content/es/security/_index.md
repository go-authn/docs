---
title: "Seguridad"
linkTitle: "Seguridad"
weight: 55
description: "Qué rechazan los programas, cómo viaja una revocación desde el proveedor hasta cada servidor y cómo distinguir un binario auténtico de cualquier otro."
tags: [security]
---

A go-authn se le pide que pruebe a las personas, así que sus rechazos son el diseño
y no las excepciones. Esta sección reúne los que cruzan las fronteras entre
programas; las páginas de cada programa dicen lo que rechaza por sí solo.

## Los rechazos que más importan {#the-refusals-that-matter-most}

| | qué se rechaza | por qué |
|---|---|---|
| authnd | una búsqueda de cualquiera que no sea un `reader` declarado | un bind prueba quién es alguien; no es permiso para listar a todo el mundo |
| authnd | un ticket Kerberos para una persona cuyo origen no guarda ninguna contraseña | un KDC necesita una clave derivada de la contraseña; un hash NT o una comprobación de contraseña no pueden producirla ([por qué]({{< relref "/authnd/kerberos.md" >}})) |
| authnd | un bloque `kerberos` junto a un bloque `mfa` | un kinit lleva la contraseña y nada más, así que el reino emitiría tickets con un solo factor a personas que, según el bloque `mfa`, necesitan dos |
| authn-bridge | una aserción que nadie firmó, un identificador ajeno al ámbito propio de la institución | una federación no vale más que lo más restringido que cada miembro puede afirmar |
| authn-revokd | una lista sin firmar, caducada o más antigua que la que tiene | un espejo intermedio puede retrasar una lista, nunca falsificarla ni hacerla retroceder |
| authn-revokd | confiar en una lista que ha caducado | escribe una que revoca la propia CA, de modo que sshd rechaza en lugar de confiar en una lista obsoleta |
| sshcert-authorize | un certificado cuya concesión de dominio no nombra este host | un certificado de la CA de una federación no es, por sí solo, permiso para todos los hosts que confían en esa CA |

## Una revocación, de principio a fin {#a-revocation-end-to-end}

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) firma y fecha una
   KRL (para los certificados SSH) y una CRL (para los certificados de cliente
   X.509), y las publica.
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) descarga cada lista,
   verifica su firma y sus fechas, rechaza una más antigua que la que tiene
   (también tras un reinicio), y solo entonces la escribe donde la lee el servidor.
3. sshd (`RevokedKeys`), go-fileshare y cualquier otro leen un archivo que ya se ha
   verificado.

Un evento CAEP `session-revoked`, a través del transmisor de Shared Signals del
proveedor, anula lo que ninguna lista puede nombrar: todo lo emitido a una persona
antes de un momento dado. La documentación de go-fileshare describe el lado
receptor:
[listas de revocación](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
[shared signals](https://go-fileshare.github.io/docs/latest/security/shared-signals/).

## Versiones {#releases}

Cada binario lo compila el flujo de publicación a partir de un commit etiquetado y
se puede comprobar de tres maneras: [verificar una descarga]({{< relref "/security/verifying-releases.md" >}}).
