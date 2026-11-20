---
title: "kdcd: un demonio KDC Kerberos para un reino"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd es un programa construido sobre la biblioteca kdc: AS y TGS por UDP y TCP, un solo archivo HCL, cada secreto en un archivo y un oyente TLS mutuo opcional que emite un TGT para una persona sin contraseña."
tags: [bibliotecas, kerberos, directorio, kdcd]
---

**¿Cómo se ejecuta como servicio la biblioteca [kdc]({{< relref "/libraries/kdc.md" >}})?**
`kdcd` es un demonio KDC Kerberos para un reino, construido sobre la biblioteca
[go-authn/kdc](https://github.com/go-authn/kdc). Responde a solicitudes AS y TGS por
UDP y TCP y, opcionalmente, **emite un TGT** para una persona que se probó en otro
lugar (un inicio de sesión con passkey en
[go-authn/bridge](https://github.com/go-authn/bridge)), por TLS mutuo. La
biblioteca guarda el protocolo; este programa guarda los sockets, la configuración
y las reglas de los secretos.

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

Instalación (el binario es `kdcd`: el KDC de MIT es `krb5kdc`, el de Heimdal es `kdc`):

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

Go puro, `CGO_ENABLED=0`; las versiones llevan un manifiesto `SHA256SUMS` y una
atestación de procedencia de compilación por binario. Como servicio: `packaging/systemd/`
(unidad y archivo sysusers; véase [Ejecutarlo](#running-it)).

## Qué debe contener el directorio {#what-the-directory-must-hold}

Un KDC descifra la preautenticación del cliente con la clave de larga duración de esa
persona, así que una **AS-REQ** solo puede atenderse para una persona cuyo origen guarda
una **contraseña**: un bloque `user` con `password_file`, o un bloque `users "sql"` que
la devuelva. Un origen que solo puede *verificar* una (un bind contra el LDAP de otro,
un hash) no puede atender una AS-REQ, por bien que responda a «¿es esta la contraseña?».
Es una propiedad de Kerberos, explicada en la
[documentación de la biblioteca](https://github.com/go-authn/kdc#readme) y en
la [página de kdc]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}}).

Un reino de la era de las passkeys no necesita nada de eso. Una persona **sin
contraseña** (un bloque `user "alice" {}`, o una fila de cualquier bloque `users`) está
en el directorio, no tiene clave y se le rechaza una AS-REQ con `KDC_ERR_NULL_KEY`.
Solo obtiene un TGT por el **oyente de mint**, de un llamador que la autenticó.
`kdcd` no añade ninguna vía de contraseña propia: ni opción, ni variable de entorno, ni
valor en línea; `password_file` existe porque la vía AS de la biblioteca lo necesita.

## Configuración {#configuration}

Un archivo HCL. Nada en él es un secreto; cada secreto es un archivo.

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: any number of these, in any mix.
user "alice" {}                           # a person with no password: mint only
user "bob" { password_file = "/etc/kdcd/bob.pw" }

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"
  users    = "select login, password from staff"
}
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/kdcd/bind.pw"
}
```

Los bloques `users` son los de [go-authn/directory/hcldir](https://github.com/go-authn/directory),
sin cambios. Un origen que solo puede verificar una contraseña, como un bind contra un
servidor LDAP, da a los llamadores de mint un directorio contra el que comprobar un
principal y no puede atender una AS-REQ.

`kdcd check --config FILE` lee y construye todo lo que construiría el demonio, abre el
directorio, no escucha en ninguna parte e imprime lo que sirve: el reino, las
direcciones, los principales de la keytab (nombre, kvno, etype; nunca una clave),
cuántas personas contiene el directorio y los llamadores de mint. Estado de salida 0 y
una última línea `ok`, o el primer rechazo.

### Con qué se niega a arrancar {#what-it-refuses-to-start-with}

| Rechazado | Por qué |
| --- | --- |
| una keytab, clave de mint, archivo de contraseña, DSN o contraseña de bind que **el grupo u otros puedan leer o escribir**, o que pertenezca a un uid distinto de root o del demonio | una copia que otra cuenta pueda leer falsifica tickets para cada persona del reino |
| un secreto escrito en línea (`password = "..."` no es un argumento) | los secretos viven en archivos, nunca en la configuración, una copia de ella o un registro |
| un archivo de configuración que el grupo u otros puedan escribir | quien lo escribe elige los llamadores de mint |
| una keytab sin clave `krbtgt/REALM`, o a la que falte un servicio listado, **en aes256-cts-hmac-sha1-96** (el único tipo que emite la biblioteca) | arrancaría y fallaría en el primer `kinit` |
| un comodín o un nombre de host en `listen` (se exige un literal IP), y **cualquier** comodín para `mint` | el KDC y el oyente de mint están en las interfaces que alguien eligió |
| un bloque `mint` sin llamadores, sin certificado o con uno caducado | la biblioteca lee la ausencia de llamadores como «mint desactivado»; esto lo dice en lugar de no emitir nada en silencio |
| `ldap://` a otra máquina sin `start_tls` | cada contraseña cruzaría la red tal como se escribió |

Los archivos secretos se abren **una vez** y se comprueba el archivo abierto (archivo
regular, modo, propietario), de modo que una comprobación no puede referirse a un archivo
y la lectura a otro (el modelo es `readKeytab` de go-fileshare). `dsn_file` y
`bind_password_file` los lee `hcldir` por nombre, después de comprobarlos del mismo modo.

## El modelo de confianza de mint {#the-mint-trust-model}

`POST https://<mint address>/mint` con `{"principal": "alice", "lifetime_seconds": 36000}`
devuelve un KRB-CRED (RFC 4120 5.8) con un TGT para `alice`, para que el llamador lo
entregue a la máquina de la persona ([go-authn/kinit](https://github.com/go-authn/kinit)
lo carga en una sesión de inicio de Windows). Lo que lo acota:

- **El llamador es el certificado de cliente TLS**, verificado por el oyente contra
  `client_ca_file` (TLS 1.3, `RequireAndVerifyClientCert`): una conexión sin certificado,
  o con uno que la CA no firmó, falla en el handshake antes de leer ningún HTTP. Un
  certificado verificado se compara después, por un **subjectAltName URI**, con
  `callers`, exactamente; un certificado que se verifica pero no figura recibe `403`.
  Nada en una cabecera o un cuerpo nombra al llamador.
- **Quien esté en `callers` puede obtener un TGT para cualquier principal del
  directorio** (nunca un servicio, nunca un nombre que el directorio no tenga), sin la
  clave de esa persona. Lo que el reino cree es la autenticación de la persona por el
  llamador, así que un llamador es tan de fiar como la keytab del KDC. Liste uno por
  proveedor de identidad, dé a cada uno su propio certificado y mantenga `client_ca_file`
  como una CA que no firma nada más.
- El ticket es `INITIAL | PRE-AUTHENT`, nunca renovable, reenviable ni delegable; su
  duración es la menor entre la solicitud, `lifetime` y diez horas.
- La clave de sesión sale de `crypto/rand`, deja el proceso una vez, en la respuesta, y
  nunca se registra. La respuesta lleva `Cache-Control: no-store`. El KRB-CRED lleva la
  clave en claro, así que **el canal TLS es el cifrado**: ponga el oyente en una
  interfaz interna.
- Solo se sirve `/mint`, con tiempos límite y un límite de cabeceras. Cada mint, y cada
  rechazo, se registra con la URI del llamador y el principal solicitado.

El modelo de amenazas completo es el de la pull request de la biblioteca,
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38), con la
[sección de emisión](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)
y las [notas de auditoría](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)
del README de la biblioteca; nada de ello se repite ni se debilita aquí.
El bloque `kerberos` de [go-authn/bridge](https://github.com/go-authn/bridge) es el lado
del llamador: su `kdc_url` es `https://<mint address>/mint`, su `ca_file` firma el
`cert_file` de arriba, y el nombre URI de su certificado de cliente es una entrada de `callers`.

## Ejecutarlo {#running-it}

`packaging/systemd/kdcd.service` lo ejecuta como el usuario del sistema de
`packaging/sysusers.d/kdcd.conf`, con el endurecimiento de la unidad de
[authn-bridge](https://github.com/go-authn/bridge). El puerto 88 es privilegiado, así
que la unidad concede exactamente `CAP_NET_BIND_SERVICE` y nada más.

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

Los secretos pertenecen a `kdcd` (o a root) con modo 0600; 0640 con grupo `kdcd` se
rechaza a propósito. Un cambio de configuración es `systemctl restart kdcd` (el demonio
no recarga; un cliente reintenta una conexión rechazada).

En Windows los bits de modo no significan nada y no se comprueban: ponga los archivos
donde solo pueda leerlos la cuenta que ejecuta el servicio.

## Lo que no está aquí {#not-here}

Entre reinos, PKINIT, FAST, tickets renovables o posfechados, un protocolo kadmin y
cualquier tipo de cifrado salvo aes256-cts-hmac-sha1-96 son límites de la propia
biblioteca ([go-authn/kdc](https://github.com/go-authn/kdc#readme)). `kdcd` aún no
tiene recarga ni punto de acceso de métricas.

## Referencia {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd), v0.1.0.
