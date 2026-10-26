---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "La extensión de concesión de dominio de GÉANT / EuroHPC para los certificados SSH de usuario, y sshcert-authorize, el comando que falla en modo cerrado y al que sshd pregunta si un certificado está destinado a este host."
tags: [sshcert, ssh, eurohpc]
---

**Un certificado de la CA de una federación no es, por sí solo, permiso para todos
los hosts que confían en esa CA.** La CA SSH de la EuroHPC Federation Platform
escribe en una extensión, `ssh-domain-grant@core.aai.geant.org`, los hosts a los que
está destinado un certificado, y `sshd` la ignora. go-authn/sshcert lee y escribe esa
extensión, y su comando, `sshcert-authorize`, es lo que `sshd` ejecuta para hacerla
cumplir. Go puro, `CGO_ENABLED=0`. Estas páginas describen la v0.1.9.

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | el `AuthorizedPrincipalsCommand`: qué comprueba, qué rechaza y cómo lo llama sshd |

## La extensión {#the-extension}

Sus datos son un array JSON compacto de patrones de host, `["login.example.org"]`.
Un `*` coincide con **uno o más** caracteres dentro de una sola etiqueta, y los
nombres se comparan sin distinguir mayúsculas de minúsculas:

| patrón | coincide con | no coincide con |
|---|---|---|
| `login.example.org` | `login.example.org`, `LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`, `a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

La lectura es estricta: solo se acepta lo que escribe el codificador. Sin espacios
en blanco, nada después de `]`, sin secuencias de escape JSON, sin duplicados, como
máximo 64 patrones, cada uno formado por letras, dígitos, guiones y `*`, en
etiquetas de 1 a 63 bytes, como máximo 253 bytes, y **ningún `*` en la etiqueta
situada más a la derecha**. Se rechazan `null`, los objetos, los números y los
arrays anidados. Se acepta `[]`, que no concede ningún host.

Una concesión presente y mal formada nunca se notifica como ausente. Esa diferencia
es toda la razón de ser del comando.

## Quién la usa {#who-uses-it}

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})**
  escribe la extensión para los `ssh_domain_grants` de un cliente, tras comprobar
  cada patrón con el `ValidatePattern` de este paquete.
- El servidor SFTP de **go-fileshare** la lee con `ssh_domains`, y rechaza un
  certificado sin concesión salvo que se haya establecido `ssh_accept_ungranted`.
- **sshcert-authorize** es la misma comprobación para un `sshd` normal.

## Licencia {#licence}

BSD-3-Clause.
