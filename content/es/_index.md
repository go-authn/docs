---
title: "go-authn"
linkTitle: "Inicio"
type: docs
cascade:
  type: docs
description: "Autenticación en Go puro: los factores que prueban que alguien está presente, un directorio que dice quién es, las dos mitades de Kerberos y un proveedor OpenID Connect delante de una federación SAML."
---

**Dos preguntas, y no son la misma.** *¿Está esta persona aquí, ahora?* no es
*¿quién es esta persona, y qué lo probaría?* go-authn responde a ambas: los
factores que prueban la presencia, un directorio que guarda lo que **prueba** a
cada persona en lugar de un campo de contraseña, las dos mitades de Kerberos y un
proveedor OpenID Connect delante de una federación SAML. Go puro, `CGO_ENABLED=0`.
Estas páginas describen las versiones que figuran en la [página de estado]({{< relref "/status.md" >}}).

## Cuatro programas {#four-programs}

| | qué es | estas páginas describen |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | un servidor LDAP, y opcionalmente un reino Kerberos, para personas que están en otro lugar: un archivo, una base de datos SQL, otro directorio | v0.13.4 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | un proveedor OpenID Connect delante de una federación SAML (RENATER, eduGAIN), que además emite certificados SSH y firma las listas que los revocan | v0.23.4 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | descarga esas listas, verifica cada una antes de que ningún servidor la lea y falla en modo cerrado cuando una caduca | v0.6.6 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`, al que sshd pregunta si la concesión de dominio de un certificado nombra este host | v0.1.9 |

Cada uno es un único binario estático para Linux, macOS y Windows en amd64 y arm64,
publicado con `SHA256SUMS` y procedencia de compilación:
[verificar una descarga]({{< relref "/security/verifying-releases.md" >}}).

```sh
go install github.com/go-authn/authnd@v0.13.0
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.4
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.6
```

Los comandos se llaman `authn-*` (y `authnd`) porque se instalan en máquinas que
ejecutan otras cosas: un `bridge` o un `revokd` a secas en `/usr/bin` ocuparía un
nombre que otra persona puede necesitar.

## Y las bibliotecas que hay debajo {#and-the-libraries-under-them}

Los programas son finos. Lo que hacen reside en
[catorce módulos]({{< relref "/libraries/_index.md" >}}), una pregunta cada uno, de modo
que un servicio que solo *acepta* tickets Kerberos nunca enlaza un KDC, y uno que
solo comprueba un código de un solo uso nunca enlaza un directorio.

## Por qué el directorio guarda lo que prueba a alguien {#why-the-directory-carries-what-proves-somebody}

SMB necesita un hash NT; S3 necesita la propia contraseña, porque SigV4 calcula un
HMAC a partir de ella; un reino Kerberos necesita una clave derivada de la
contraseña, y un hash NT no es esa clave. Una identidad que solo tiene una de ellas
puede servir a unos protocolos y nunca a otros, escriba lo que escriba la persona.
Por eso el directorio de go-authn registra **lo que cada persona puede probar**, y
`authnd check` muestra, antes de reiniciar nada, a quién se le podría emitir un
ticket Kerberos y a quién nunca:

```
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

Esa es la salida real de authnd v0.11.0: [completa]({{< relref "/authnd/check.md" >}}).

## Juzgado con herramientas ajenas {#judged-by-other-peoples-tools}

Un banco de pruebas construido a partir de una lectura de un protocolo solo puede
confirmar esa lectura. Por eso los servidores los leen clientes que no escribieron:
el propio `ldapsearch` de OpenLDAP hace un bind contra authnd, el propio `kinit` de
MIT obtiene tickets de su reino, y OpenSSH lee los certificados y las KRL que emite
authn-bridge.
