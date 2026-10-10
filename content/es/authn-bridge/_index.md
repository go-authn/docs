---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "Un proveedor OpenID Connect delante de una federación SAML: las personas inician sesión en su propia institución, y las aplicaciones obtienen tokens, certificados SSH y certificados de cliente X.509."
tags: [authn-bridge, oidc, saml]
---

**Las personas inician sesión en su propia universidad, a través de la Fédération
Éducation-Recherche de RENATER o de eduGAIN, y las aplicaciones obtienen un token
OpenID Connect.** El mismo inicio de sesión permite también certificar una clave SSH,
emitir un certificado de cliente X.509 para NFS sobre TLS, establecer una contraseña
de aplicación para SMB y S3, o registrar una clave WireGuard. El proveedor puede
revocar lo que ha emitido, y publica listas firmadas de lo que ha revocado; un
token de acceso ya entregado sigue siendo válido hasta que caduca. Go puro, `CGO_ENABLED=0`, un solo binario. Estas páginas describen la
v0.20.1.

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.20.1

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

Antes de la v0.20.0 la orden se llamaba `bridge`. Ese es también el `/sbin/bridge`
de iproute2, instalado en prácticamente todos los sistemas Linux, y ganaba el que
apareciera primero en el `PATH`. La ruta del módulo sigue siendo
`github.com/go-authn/bridge`.

## Por qué un puente {#why-a-bridge}

Una federación de investigación habla SAML. Sus miembros son cientos de proveedores
de identidad, uno por institución, enumerados en un documento de metadatos firmado
que publica la federación. Las aplicaciones que se escriben hoy quieren OpenID
Connect, y confían en un único proveedor. authn-bridge es ese único proveedor: un
proveedor de servicio SAML por un lado, registrado una sola vez en la federación, y
un proveedor OpenID por el otro.

Una pasarela decide quién es cada cual para todas las aplicaciones que tiene detrás,
así que la mayor parte de este programa son rechazos. Rechaza los metadatos que la
federación no firmó, una aserción que nombra a alguien del dominio de otra
institución, grupos sobre los que un IdP no tiene autoridad, y una configuración que
dejaría pasar cualquiera de estas cosas. Una configuración que no puede servirse de
forma segura no arranca.

## Qué muestra al arrancar {#what-it-prints-at-startup}

```
$ authn-bridge --config etc/bridge-admin.hcl
authn-bridge v0.20.1: http://127.0.0.1:28473 on 127.0.0.1:28473
metrics on 127.0.0.1:28475
admin API on unix:///tmp/docs-patch-a2daf7c8/run/admin.sock
```

Este es un proveedor de prueba en loopback (un emisor `http://` solo se acepta en un
host de loopback). Obtiene los metadatos de la federación **antes** de ponerse a
escuchar. Un proveedor que no puede nombrar ni una sola institución es uno a través
del cual nadie puede iniciar sesión, así que sin los metadatos termina en lugar de
arrancar.

## Por dónde seguir {#where-to-go-next}

| | |
|---|---|
| [Instalarlo]({{< relref "/authn-bridge/install.md" >}}) | el usuario, los directorios, la unidad systemd, las claves |
| [La configuración]({{< relref "/authn-bridge/configuration.md" >}}) | cada bloque, `check`, y lo que se rechaza al arrancar |
| [El lado de la federación]({{< relref "/authn-bridge/federation.md" >}}) | los metadatos, la huella de su firmante, los ámbitos, y lo que un IdP puede afirmar |
| [Tokens]({{< relref "/authn-bridge/tokens.md" >}}) | tokens de ID, tokens de acceso, la concesión de dispositivo, contraseñas de aplicación, claves WireGuard |
| [Certificados]({{< relref "/authn-bridge/certificates.md" >}}) | certificados SSH, el perfil EuroHPC, certificados de cliente X.509 para NFS |
| [Revocación]({{< relref "/authn-bridge/revocation.md" >}}) | la KRL y la CRL firmadas, y el transmisor Shared Signals |
| [La API de administración]({{< relref "/authn-bridge/admin.md" >}}) | desactivar a una persona o una institución, salud y métricas |

Las listas que firma las lee [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
para un `sshd` corriente o un servidor TLS, y
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/),
que las comprueba por sí mismo.

## Lo que no es {#what-it-is-not}

- **Un solo proceso.** Con un bloque `state`, los tokens de actualización y los
  tokens de acceso aceptados en `/userinfo` sobreviven a un reinicio. Los inicios de
  sesión en curso, los códigos y las concesiones de dispositivo no. El estado se
  escribe de inmediato y se lee al arrancar, así que dos instancias sobre una misma
  base de datos no verían cada una lo que escribió la otra.
- Ni registro dinámico de clientes, ni cierre de sesión por canal frontal o trasero.
- Ni usuarios ni grupos que añadir. Las personas existen porque su institución
  responde por ellas, y sus grupos son los que esta afirma.

## Licencia {#licence}

BSD-3-Clause.
