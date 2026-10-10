---
title: "Un token en el bind, en un campo que no es la contraseña"
linkTitle: "Tokens (OIDC)"
weight: 75
description: "El bloque oidc: un token de OpenID Connect transportado en un bind SASL OAUTHBEARER, cuántos factores cuenta y qué se rechaza."
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}}) verifica un token y obtiene de
él una identidad. La forma obvia de llevar uno a un servidor LDAP es el campo de la
contraseña, y funciona una vez y luego deja de hacerlo: el campo de la contraseña es
donde el [bloque `mfa`]({{< relref "/authnd/mfa.md" >}}) separa el código del final,
y un token no puede ser ambas cosas.

Así que el token va donde el protocolo tiene un sitio para él. Las credenciales de
un bind **SASL** son una cadena de octetos con la forma propia del mecanismo, y la
forma `OAUTHBEARER` del RFC 7628 es una cabecera GS2 seguida de pares clave/valor,
uno de los cuales es `auth=Bearer <token>`:

```
n,,^Aauth=Bearer eyJ…^A^A
```

El campo de la contraseña no se toca. En una misma escucha, al mismo tiempo, una
persona puede teclear una contraseña con un código al final y otra puede enviar un
token.

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer` y `audience` son obligatorios. Sin `username_claim`, el nombre es
`preferred_username`, después `email` cuando `email_verified` es verdadero, y después
`sub`. Con el bloque, el root DSE anuncia el mecanismo:

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

Sin él, a todo bind SASL se le responde `authMethodNotSupported` —*así no*—, lo que
envía a un cliente a un sitio distinto que *contraseña incorrecta*.

## El descubrimiento ocurre al arrancar {#discovery-happens-at-startup}

El documento de descubrimiento y las claves del proveedor se leen cuando el servidor
arranca, y también con `check`. Un proveedor que no se puede alcanzar detiene el
servidor allí donde alguien está mirando, en lugar de rechazar después todos los
binds:

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

Un emisor que no es `https` se rechaza, salvo en loopback:

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## ¿Cuántos factores es un token? {#how-many-factors-is-a-token}

**Los que el emisor dice haber comprobado, y nada más.** Un token lleva el `amr` del
RFC 8176, los métodos que usó el proveedor. Es la única prueba que existe, así que es
lo que cuenta la política `mfa`, **por clase**:

| método `amr` | clase |
|---|---|
| `pwd`, `pin`, `kba`, `mca` | conocimiento |
| `otp`, `hwk`, `swk`, `sms`, `tel`, `sc`, `pop`, `user`, `wia`, `mfa` | posesión |
| `fpt`, `face`, `iris`, `retina`, `vbm`, `geo` | inherencia |
| cualquier otro | desconocida, que nunca satisface `distinct_kinds` |
| ningún `amr` | un factor, de posesión: el propio token |

Dos métodos de una misma clase son un solo factor. La alternativa sería que este
servidor inventara un segundo factor que nadie realizó; y un servidor que cree al
emisor sobre *quién* es esta persona no tiene ningún motivo aparte para no creerle
sobre *cómo* lo comprobó.

Con un bloque `mfa`, `check` lo dice:

```
$ authnd check sasl
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS
alice  the configuration file  a password                             uid and cn
tess   the configuration file  a password and a one-time-code secret  uid and cn

a bind carries a password with a 6-digit code after it, of two different kinds
or a token from http://127.0.0.1:18481, over SASL OAUTHBEARER over TLS
  a token counts for the factors its amr claim names, so one with no amr is refused by this policy
alice has no second factor here, so a password cannot satisfy this policy; a token whose amr names two kinds still can
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

alice no tiene `totp_secret`, así que una contraseña con un código nunca puede bastar
en su caso; un token cuyo `amr` nombra dos clases sí puede, como muestra el primer
bind de más abajo.

## Cómo son los binds {#what-the-binds-look-like}

El emisor aquí es un pequeño proveedor de prueba en loopback, y `oidctool` un cliente
de prueba escrito para estas páginas: firma un token para el nombre indicado, con el
`amr` indicado, lo envía en un bind `OAUTHBEARER` (con un `authzid` cuando un quinto
argumento lo nombra), e imprime el código de resultado del bind y las credenciales
SASL del servidor. Contra la configuración anterior, sobre `ldaps://`:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 0, serverSaslCreds 

$ ./oidctool alice '' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","kba"]' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls tess
bind result 14, serverSaslCreds {"status":"insufficient_scope","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}

$ ./oidctool zed '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 14, serverSaslCreds {"status":"invalid_token","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}
```

0 es éxito, 49 `invalidCredentials`, 14 `saslBindInProgress`. Un token
`["pwd","kba"]` nombra dos métodos de una misma clase, así que cuenta una vez. Y con
la misma configuración sin `cert_file` ni `key_file`, en una escucha sin cifrar:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13 es `confidentialityRequired`: un token no se acepta por una conexión que no
está cifrada.

Lo que escribió el servidor para los cuatro binds rechazados sobre `ldaps://`:

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

y para el que va sin cifrar:

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

Un bind `OAUTHBEARER` correcto deja la conexión con un bind como
`uid=<name>,ou=people,<base_dn>`, escrito como cualquier otra entrada.

## Lo que rechaza {#what-it-refuses}

- **Un token sin cifrar.** Un token bearer no necesita ninguna otra mitad: quien lo
  lea en la red es esa persona hasta que caduque. `allow_plaintext = true` existe
  para un despliegue que termina TLS delante de este proceso, y `check` dice entonces
  *a token may cross this socket in the clear*.
- **Una petición para ser otra persona.** La cabecera GS2 puede nombrar un `authzid`.
  Un token para alice que lleva una petición para actuar como tess se rechaza, no se
  trata discretamente como ninguna de las dos.
- **Un token para alguien a quien ningún origen de aquí publica.** Al cliente solo se
  le dice `invalid_token`; qué nombres existen no es algo que se deba revelar intento
  a intento. El motivo figura en la salida del servidor.
- **La vinculación de canal.** Una cabecera GS2 con `p=` —el cliente exige
  vinculación de canal (channel binding)— se rechaza: este servidor no la hace, y
  aceptar la cabecera sin vincular nada haría creer al cliente que el canal se había
  comprobado.
- **Un mecanismo que este servidor no habla**, con `authMethodNotSupported`.

El rechazo del propio token es el del RFC 7628 §3.2.3: un error JSON que lleva
`openid-configuration`, devuelto como `saslBindInProgress` para que el cliente pueda
enviar el `^A` que pone fin al intercambio. A un token que se verifica pero no
satisface la política `mfa` se le responde simplemente `invalidCredentials`, como
muestran el segundo y el tercer bind de más arriba.

{{< callout type="info" >}}
**Un token no fija una contraseña**

Una persona que solo ha iniciado sesión con un token no puede usar esa sesión para
darse una primera contraseña, y una persona que ya tiene una debe enviarla igualmente
para cambiarla. Consulte [cambiar una contraseña]({{< relref "/authnd/passwords.md" >}}).
{{< /callout >}}
