---
title: "Las bibliotecas, una pregunta cada una"
linkTitle: "Bibliotecas"
weight: 50
description: "Los catorce módulos Go de go-authn: la pregunta que responde cada uno, la versión que describen estas páginas, y por qué son módulos separados."
tags: [bibliotecas]
---

Programas como [authnd]({{< relref "/authnd/_index.md" >}}) y
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) están construidos a partir de
módulos que se publican, se versionan y se prueban por separado. Cada uno responde
**una** pregunta, y un programa importa aquellos cuyas preguntas plantea.

Todos son Go puro y se compilan con `CGO_ENABLED=0`.

| módulo | la pregunta que responde | estas páginas describen | ruta de importación |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | ¿respondieron suficientes factores, de suficientes tipos, y cuáles? | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | ¿es correcto este código de seis dígitos, y se ha usado antes? | v0.4.2 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | ¿cómo se habla con una llave de seguridad, mediante informes de 64 bytes? | v0.6.2 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | ¿respondió *la* llave registrada, y la tocó una persona? | v0.4.2 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | ¿quién es alguien, y qué puede probarlo? | v0.15.0 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | ¿cuáles son los bytes de un servidor LDAP? | v0.10.2 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | ¿es válido este ticket Kerberos para este servicio? | v0.3.1 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | ¿cómo emite un reino tickets a partir de un directorio? | v0.4.3 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | ¿quién dice este token bearer que pregunta, y hay que creerlo? | v0.4.1 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | ¿qué dijo de esta persona el proveedor de identidad de una federación? | v0.4.1 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | ¿está revocado este certificado o esta clave SSH, tal como respondería sshd? | v0.6.1 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | ¿de dónde procede el certificado de servidor TLS de un demonio? | v0.5.2 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | ¿puede conectarse esta clave WireGuard, y de quién es? | v0.1.1 | `github.com/go-authn/wireguard` |
| [scim]({{< relref "/libraries/scim.md" >}}) | ¿a quién acaba de crear, cambiar o eliminar el proveedor de identidad? | v0.1.0 | `github.com/go-authn/scim` |

## Cómo se agrupan {#how-they-group}

**Factores**: si una persona está presente.
[mfa]({{< relref "/libraries/mfa.md" >}}) decide cuánta prueba basta y no sabe nada
de ningún dispositivo. [totp]({{< relref "/libraries/totp.md" >}}) es un factor: un
código de un teléfono. [fido]({{< relref "/libraries/fido.md" >}}) habla CTAP con una
llave de seguridad y no sabe nada de ninguna política;
[keyfactor]({{< relref "/libraries/keyfactor.md" >}}) es la única pieza que importa
ambos, y convierte una llave en un factor.

**El directorio, y su protocolo.**
[directory]({{< relref "/libraries/directory.md" >}}) es el modelo: una persona, y qué
credenciales guarda un origen para ella —una contraseña, un hash NT, un verificador,
claves SSH, un secreto de código de un solo uso—, y, aparte de ellas, los
atributos que la describen y no prueban nada.
[ldap]({{< relref "/libraries/ldap.md" >}}) es el protocolo LDAP en la red, como
servidor, y el esquema de directorio contra el que se puede comprobar una
entrada, leído de archivos de OpenLDAP o escrito en HCL2; lo que responde es
asunto del manejador.

**Kerberos, en dos mitades.** [krb5]({{< relref "/libraries/krb5.md" >}})
*acepta* tickets: una keytab, un AP-REQ que entra, un AP-REP que sale.
[kdc]({{< relref "/libraries/kdc.md" >}}) los *emite*, a partir de un directorio que
guarda contraseñas.

**Federación y tokens.** [saml]({{< relref "/libraries/saml.md" >}}) es un proveedor
de servicios SAML 2.0 delante de una federación como RENATER o eduGAIN.
[oidc]({{< relref "/libraries/oidc.md" >}}) verifica los tokens OpenID Connect que
firma un proveedor: la mitad del servidor de recursos, sin flujo de inicio de sesión.
[scim]({{< relref "/libraries/scim.md" >}}) va en el otro sentido: el punto de
acceso SCIM 2.0 al que llama un proveedor de identidad para crear, actualizar y
eliminar las personas y los grupos de su aplicación.

**Revocación y certificados.** [krl]({{< relref "/libraries/krl.md" >}}) lee, escribe
y comprueba las listas de revocación de claves de OpenSSH.
[servercert]({{< relref "/libraries/servercert.md" >}}) da a un demonio su certificado
TLS, a partir de archivos o de ACME.

**[wireguard]({{< relref "/libraries/wireguard.md" >}})** transporta la lista firmada
de claves públicas WireGuard que las personas han registrado ante un proveedor, y que
una pasarela convierte en pares.

## Por qué son módulos separados {#why-they-are-separate-modules}

**Un servicio que solo acepta tickets nunca enlaza un KDC.** Un servidor NFS verifica
los tickets que presenta un cliente; tiene una keytab y nada más que ver con un reino.
Si aceptar y emitir fueran un solo módulo, cada uno de esos servidores llevaría una
ruta de código de emisión de tickets que nunca ejecuta, y el módulo de directorio del
que un KDC lee las personas, que nunca usa.

Esto está medido, no es una intención. En un módulo temporal que solo importa
`github.com/go-authn/krb5@v0.3.1`:

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.1
```

La misma orden para un módulo que importa `github.com/go-authn/kdc@v0.4.3` lista
`github.com/go-authn/directory` y `github.com/go-authn/kdc`: emitir necesita las
personas, aceptar no.

La misma regla se cumple en los demás. `mfa` no importa nada fuera de la biblioteca
estándar, y `fido` no importa `mfa`: un programa que solo quiere hacer parpadear una
llave no lleva un paquete de políticas. `totp` solo depende de `mfa`, y `oidc` no tiene
ninguna dependencia. `directory` mantiene sus orígenes LDAP, SQL y HCL en
subpaquetes: el paquete principal no importa nada fuera de la biblioteca estándar, y
`sqldir` recibe un `*sql.DB`, así que el controlador de base de datos lo elige el
programa.

## Todas las páginas tienen las mismas partes {#every-page-has-the-same-parts}

La pregunta; la línea `go get` de la versión descrita; un ejemplo mínimo que compila
contra esa versión; lo que el módulo rechaza, según su código; y contra qué se
comprueba: la implementación que no es esta, nombrada en su CI o en sus pruebas. Donde
un README y el código discrepan, la página sigue al código.
