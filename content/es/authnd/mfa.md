---
title: "Un segundo factor, sobre un protocolo con un solo campo"
linkTitle: "Segundo factor"
weight: 70
description: "El bloque mfa: un código de un solo uso al final de la contraseña, cómo se separa y se comprueba, qué se cuenta contra quién, y quién no puede hacer un bind con él."
tags: [authnd, mfa, totp]
---

El bind simple de LDAP lleva un nombre y una contraseña y nada más: ningún sitio
para un código, ninguna ida y vuelta para pedirlo, y un cliente que habla LDAP no
va a aprender a hacerlo. Así que el código va al **final** de la contraseña, que es
lo que hacen los dispositivos que ofrecen esto, y lo que las personas ya saben
teclear:

```
password:  hunter2314159
           ^^^^^^^ ^^^^^^
           password  the six digits on their phone
```

```hcl
mfa {
  factors        = 2
  distinct_kinds = true     # two things they KNOW are not two factors
  # digits = 6, period = 30 (seconds) and window = 1 are the defaults
}

user "tess" {
  password_file = "/etc/authnd/passwords/tess.pw"
  totp_secret   = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"   # ⛔ this IS the second factor
}
```

| clave | por defecto | |
|---|---|---|
| `factors` | 2 | 1 se rechaza (*a password and nothing else: remove the block, or ask for 2*); más de 2 se rechaza, ya que un bind lleva una contraseña y un código y ninguna tercera cosa |
| `distinct_kinds` | `false` | los factores deben ser de clases distintas, que es lo que normalmente se entiende por «dos factores» |
| `digits` | 6 | de 6 a 10 (RFC 4226) |
| `period` | 30 | segundos que dura un código |
| `window` | 1 | pasos a cada lado del momento actual que se aceptan, para relojes que difieren. Cada paso es un paso más de tiempo para que otro adivine: fíjelo a propósito |
| `readers` | `false` | si los [readers]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) también llevan un código. Una cuenta de servicio no tiene teléfono; la que lo tenga recibe un `totp_secret` en su bloque `reader` |

El secreto también puede proceder de una columna de base de datos (la quinta) o de
un atributo LDAP (`totp_attribute`); consulte [las personas]({{< relref "/authnd/people.md" >}}).
Un `totp_secret` de menos de 128 bits (RFC 4226 R6) en un bloque `user` o `reader`
detiene el servidor, nombrando a la persona, en lugar de hacer fallar después cada
uno de sus inicios de sesión:

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## Quién no puede hacer un bind con él {#who-cannot-bind-under-it}

```
$ authnd check mfa
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS        WITH
alice  the configuration file  a password                             account, uidObject  uid
tess   the configuration file  a password and a one-time-code secret  account, uidObject  uid

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
tess has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject

a bind carries a password with a 6-digit code after it, of two different kinds
alice has no second factor here, and cannot bind while one is required
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

Esa es la pregunta que hay que hacerse antes de activar el bloque.

## Cómo son los binds {#what-the-binds-look-like}

La misma configuración en servicio, con el código de tess calculado a partir de su
secreto en el momento del bind:

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.only
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
dn:uid=tess,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.badcode
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.code
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin
dn:cn=reader,dc=example,dc=org
```

`tess.only` es la contraseña de tess sin código; `tess.both`, su contraseña y el
código vigente, enviados dos veces; `tess.badcode`, su contraseña y `000000`;
`alice.code`, la contraseña de alice y seis dígitos. Al cliente se le dice una sola
cosa —*invalid credentials*— sea cual sea la mitad incorrecta: cuál de ellas es un
dato sobre la cuenta, y decírselo a alguien que no ha probado nada acota su
siguiente intento. La salida del propio servidor dice cuál:

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## Lo que se deriva del campo único {#what-follows-from-the-one-field}

- **La separación es por longitud.** Los últimos `digits` caracteres son el código.
  Una contraseña que termina en dígitos no es problema: por eso la contraseña de
  tess, sola, se leyó como una contraseña incorrecta seguida de un código. Un campo
  *no más largo* que un código se rechaza en lugar de adivinarse, porque una
  contraseña corta no se puede distinguir de un código.
- **Siempre se comprueban las dos mitades.** Volver antes de tiempo ante una
  contraseña incorrecta diría, por el tiempo empleado, qué mitad era incorrecta.
- **Un código se usa una vez.** Es válido durante un paso entero, así que un
  servidor que acepta uno dos veces acepta una repetición; se rechaza todo paso
  hasta el último aceptado, no solo ese mismo.
- **Los intentos se limitan por nombre**, con los valores por defecto de
  go-authn/totp: tras cinco códigos incorrectos seguidos, a la persona se la
  rechaza durante quince minutos, código correcto incluido, y tras cien queda
  bloqueada hasta que authnd se reinicia. Los recuentos se guardan en memoria, por
  proceso.
- **Solo se cuenta un código que va detrás de la contraseña correcta**: de lo
  contrario, cualquiera que conociera un nombre podría bloquear a su titular con
  cinco binds. Detrás de una contraseña incorrecta, el código se calcula igualmente,
  contra nada que lo recuerde: la primera línea de la salida anterior, *not looked
  at*.
- **Un reader se cuenta bajo su DN tal como lo escribe la configuración**, así que
  `CN=Reader` no obtiene un cupo nuevo propio.
- **Nadie inscrito no es un código incorrecto.** Una persona sin secreto no ha
  respondido nada, en lugar de haber respondido mal, y la salida del servidor dice
  *nobody enrolled an authenticator for this person*.

## No con un reino {#not-with-a-realm}

Un bloque `kerberos` y un bloque `mfa` en una misma configuración se rechazan: un
`kinit` prueba la contraseña y nada más, y este KDC no tiene preautenticación de
segundo factor. Consulte
[el reino]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}}).

## Tokens, bajo la misma política {#tokens-under-the-same-policy}

Un token en el bind, con un [bloque `oidc`]({{< relref "/authnd/tokens.md" >}}),
se cuenta por lo que su emisor dice haber comprobado: el claim `amr`. Un token sin
`amr` es un solo factor, y esta política lo rechaza.
