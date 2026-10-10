---
title: "Un reino Kerberos para las mismas personas"
linkTitle: "Reino Kerberos"
weight: 60
description: "El bloque kerberos, la keytab con la que firma los tickets, a quién se le puede emitir un ticket y por qué a algunas personas nunca, y por qué no puede estar junto a un bloque mfa."
tags: [authnd, kerberos, kdc]
---

```hcl
kerberos {
  realm    = "EXAMPLE.ORG"               # required, upper case
  keytab   = "/etc/authnd/krb5.keytab"   # required; must hold krbtgt/EXAMPLE.ORG
  listen   = "127.0.0.1:88"              # the default; UDP and TCP both
  lifetime = "10h"                       # the default, MIT's
}
```

Un bloque `kerberos` convierte authnd en un KDC además de un directorio, mediante
[go-authn/kdc]({{< relref "/libraries/_index.md" >}}): a las mismas personas se les
emiten tickets en lugar de solo buscarlas. Responde por UDP y TCP en la misma
dirección, exige la preautenticación por marca de tiempo cifrada, y solo emite
tickets `aes256-cts-hmac-sha1-96`. `lifetime` es una duración de Go (`"10h"`,
`"90m"`). El directorio y el reino están al mismo nivel: si uno de los dos se
detiene, el proceso se detiene, porque un servidor que siguiera respondiendo LDAP
después de que muriera su KDC parecería sano a todo lo que no habla Kerberos.

Se rechaza al arrancar:

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

e igualmente un reino sin nombre, sin keytab, una dirección que no se puede
analizar, un `lifetime` que Go no sabe leer, y un bloque `kerberos` junto a un
bloque `mfa` (más abajo).

## La keytab {#the-keytab}

La keytab guarda la clave con la que authnd firma sus propios tickets
—`krbtgt/REALM@REALM`— y una clave por cada servicio al que emite tickets. Es el
mismo archivo que leen esos servicios. La contraseña de krbtgt no se vuelve a
escribir nunca, así que hágala aleatoria. Con el `ktutil` de MIT (paquete
`krb5-user` en Debian y Ubuntu; esta receta es la que da `docs/install.md`, y no se
ejecutó para estas páginas):

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

Añada la clave de un servicio del mismo modo (`-p nfs/files.example.org@EXAMPLE.ORG`),
y dé a ese servicio la misma clave en su propia keytab. En macOS, el
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96` de Heimdal
escribe una clave aleatoria sin contraseña alguna. En ambos casos, relea la keytab
antes de arrancar (`klist -k` con MIT, `ktutil -k <file> list` con Heimdal):

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

Una keytab sin `krbtgt/REALM` la rechaza `check`, y también el arranque; consulte
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}}).
La keytab se lee una sola vez, al arrancar: sustituirla requiere un reinicio.

## A quién se le puede emitir un ticket {#who-can-be-issued-a-ticket}

Un KDC debe **descifrar** la preautenticación del cliente con la clave de larga
duración de esa persona, así que necesita la **contraseña** de la persona, no solo
una forma de comprobarla. `check` dice a quién se le puede y a quién no, con el
motivo:

```
$ authnd check realm
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS
alice  the configuration file  a password  uid and cn
bob    the configuration file  an NT hash  uid and cn
dora   a sqlite database       a password  uid and cn
eli    a sqlite database       an NT hash  uid and cn

realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

| el origen tiene | un ticket |
|---|---|
| una contraseña (`password`, `password_file`, una columna de contraseña SQL) | sí |
| solo un hash NT | **no**: es la clave RC4-HMAC, y este reino solo emite AES |
| solo una comprobación de contraseña (un directorio `users "ldap"` detrás de este) | **no**: un origen que solo verifica una contraseña no puede producir ninguna clave |

Para un directorio detrás de este, la última línea de la parte del reino dice
*alice, bob, dora and eli: the source only verifies a password, so it cannot
produce any key*. Eso es estructural, no una cuestión de configuración, y
descubrirlo en `check` es mejor que descubrirlo por alguien cuyo `kinit` dice que
su contraseña correcta es incorrecta.

## kinit contra él {#kinit-against-it}

Un `krb5.conf` que nombra este KDC. ⛔ Para MIT Kerberos, las llaves van en líneas
propias: su analizador ignora en silencio un reino escrito en una sola línea.

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

La misma configuración, servida y consultada con el `kinit` de Heimdal de macOS
(`--password-file` lee la contraseña de un archivo):

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:48:29 2026  Oct 11 07:48:29 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

El ticket dura las diez horas por defecto. bob escribió la contraseña a partir de la
cual se calculó su hash NT, y aun así se rechaza: el reino no tiene ninguna clave
para esa persona. El KDC escribe en su salida lo que ha rechazado, con el código de
error de Kerberos:

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required* es la primera ronda normal de un `kinit`: el cliente
pregunta sin preautenticación, se le dice que es obligatoria, y vuelve a preguntar
con ella. El `kinit` correcto de alice solo deja esa línea.

{{< callout type="info" >}}
**El reino dice qué nombres existen; el directorio no**

Un bind LDAP para un nombre que nadie tiene se responde con `invalidCredentials`,
igual que una contraseña incorrecta. El KDC responde *no such principal in this
realm* (`KDC_ERR_C_PRINCIPAL_UNKNOWN`, código 6), como hacen los KDC de Kerberos.
Con un bloque `kerberos` en una dirección que otros pueden alcanzar, la lista de
nombres es por tanto tan adivinable como en cualquier KDC; `listen` queda por
defecto en loopback.
{{< /callout >}}

## Una contraseña cambiada por LDAP {#a-password-changed-over-ldap}

El KDC lee las mismas personas que sirve el directorio, así que una
[contraseña cambiada por LDAP]({{< relref "/authnd/passwords.md" >}}) llega al reino
de inmediato: la anterior deja de funcionar para `kinit` en el momento en que deja
de funcionar para un bind:

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## No junto a un bloque `mfa` {#not-beside-an-mfa-block}

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

La preautenticación por marca de tiempo cifrada del RFC 4120 se basa solo en la
contraseña. Un segundo factor necesita la preautenticación OTP (RFC 6560) dentro de
FAST (RFC 6113), que este KDC no implementa. Un reino aquí entregaría tickets con un
solo factor a las personas que según el [bloque `mfa`]({{< relref "/authnd/mfa.md" >}})
necesitan dos, y un ticket abre todo lo que abre un bind; así que la elección se
hace en modo cerrado: uno u otro.

## Puertos {#ports}

El 88 es privilegiado. Con la unidad empaquetada, `CAP_NET_BIND_SERVICE` lo cubre;
un servidor ejecutado como usuario normal necesita un puerto alto, como arriba, y
un `krb5.conf` que lo nombre.
