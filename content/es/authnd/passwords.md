---
title: "Una persona que cambia su propia contraseña"
linkTitle: "Cambiar una contraseña"
weight: 50
description: "La única escritura que acepta authnd: la contraseña de la propia persona, mediante el RFC 3062 o un modify del RFC 4511, siempre con la contraseña anterior, escrita de vuelta en el archivo que declara a la persona."
tags: [authnd, contraseñas, ldappasswd]
---

Una persona puede cambiar **su propia** contraseña, y la de nadie más, mediante la
operación de modificación de contraseña del RFC 3062 (lo que envía `ldappasswd`) o
un modify del RFC 4511. En ambos casos, **la contraseña actual debe enviarse junto
con la nueva, sea cual sea el medio con el que hizo el bind la conexión**. De lo
contrario, una sesión con un bind hecho mediante un
[token OAUTHBEARER]({{< relref "/authnd/tokens.md" >}}) —de vida corta, y
posiblemente de un solo factor— podría convertirlo en una contraseña permanente que
además sirve para `kinit`.

Es el comportamiento de ppolicy de OpenLDAP con `pwdSafeModify` activado, con los
códigos de resultado que devuelve su `ppolicy.c`. El RFC 3062 §3 lo permite: "If
oldPasswd is not present, the server MAY use other policy to determine whether or
not to change the password."

## Con `ldappasswd` {#with-ldappasswd}

`-t` es un archivo que contiene la contraseña anterior, `-T` uno que contiene la
nueva; `-A` y `-S` las piden por teclado en su lugar.

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -T alice.new
Result: Insufficient access (50)
Additional info: a password change must send the old password with the new one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t wrong.pwin -T alice.new
Result: Server is unwilling to perform (53)
Additional info: the old password sent is not the current one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.new
dn:uid=alice,ou=people,dc=example,dc=org
```

La contraseña anterior deja de funcionar al instante, para un bind y —con un
[reino]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}})— para
`kinit`. El servidor lo indica en su salida:

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd no genera contraseñas: una petición sin contraseña nueva se rechaza con
`unwillingToPerform` (*this server does not generate passwords: send the one you
want*). Una contraseña inventada por el servidor tendría que devolverse por la
conexión, y el único lugar donde con seguridad acabaría es el historial de
desplazamiento de un terminal.

## Con `ldapmodify` {#with-ldapmodify}

El cambio es **un delete del valor anterior seguido de un add del nuevo, en una
sola petición**. El RFC 4511 §4.6 aplica los cambios de un modify en orden y de
forma atómica, así que el delete —y con él toda la petición— falla a menos que el
valor eliminado sea el que está guardado:

```
dn: uid=alice,ou=people,dc=example,dc=org
changetype: modify
delete: userPassword
userPassword: alice-test-pw
-
add: userPassword
userPassword: alice-new-pw
-
```

Un `replace` a secas no prueba nada, y cualquier cosa que no sea `userPassword` no
es algo que este servidor cambie:

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f replace.ldif
ldap_modify: Insufficient access (50)
	additional info: a password change must send the old password with the new one
modifying entry "uid=alice,ou=people,dc=example,dc=org"

$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f other.ldif
ldap_modify: Server is unwilling to perform (53)
	additional info: this server changes userPassword and nothing else, not cn
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

Un modify que pide una contraseña **y** alguna otra cosa se rechaza entero: un
modify es atómico, y atender la mitad informaría de un éxito sobre algo que nadie
pidió.

## Quién puede cambiar qué {#who-can-change-what}

| petición | respuesta |
|---|---|
| sin contraseña anterior, o un `replace: userPassword` a secas | `insufficientAccessRights` |
| una contraseña anterior que no es la actual | `unwillingToPerform` |
| la entrada de otra persona | `insufficientAccessRights`, *a password may be changed only by the person it belongs to* |
| una conexión anónima | `insufficientAccessRights`, *an anonymous connection has not said who it is* |
| alguien sin ninguna contraseña —solo puede haber hecho el bind con un token— | `unwillingToPerform`: un token bearer no es una contraseña, y no fija la primera. La fija un administrador en la configuración |
| alguien servido desde un bloque `users` | `unwillingToPerform`: authnd lee esos orígenes y no escribe en ellos |
| el archivo no se puede escribir | `other` (80), *the password could not be written*; el motivo figura en la salida del servidor |

La penúltima, con el binario de la versión, para dora, que procede de una base de
datos SQLite:

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

La persona se identifica **por identidad, no por DN**: el nombre propio de la sesión
debe ser exactamente el del destino, byte a byte, así que una sesión con un bind
como `uid=Backup` no puede cambiar la contraseña de `backup` aunque los dos DN se
consideren iguales al compararlos. Eso y el
[rechazo de nombres que solo difieren en mayúsculas y minúsculas]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})
son dos controles que no dependen el uno del otro.

## Dónde se escribe la contraseña nueva {#where-the-new-password-is-written}

De vuelta en **el archivo que declara a la persona**, y en ningún otro sitio:

- un bloque `user` con `password_file` reescribe **ese archivo**, conservando su
  propietario y su grupo cuando el proceso puede, y con su modo restringido a 0600
  como máximo, nunca ampliado;
- un bloque `user` con `password` en línea reescribe el archivo de configuración
  con el nuevo valor, conservando sus comentarios, su orden y su modo;
- a un bloque `user` con solo un `nt_hash` no se le da una contraseña: eso cambiaría
  con qué puede probar quién es la persona, lo cual es un cambio de la
  configuración.

Cada escritura va a un archivo temporal **en el mismo directorio** y después se
renombra, de modo que un disco lleno o un fallo dejan la contraseña anterior, no un
archivo vacío. Eso requiere acceso de escritura al directorio. Con la unidad
empaquetada, `ProtectSystem=strict` lo retira, y un cambio se rechaza así:

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

con el motivo en la salida del servidor:

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-863420940: permission denied
```

Así que guarde las contraseñas en un directorio propio, en el que el servicio pueda
escribir, y la configuración en solo lectura para él: el
[drop-in `ReadWritePaths=`]({{< relref "/authnd/install.md#the-configuration-directory" >}}).
Una persona cuya contraseña está escrita en línea necesitaría que el propio
`/etc/authnd` fuera escribible, lo que además permitiría al servicio reescribir su
propia configuración.

Tras una escritura correcta, los archivos de configuración se vuelven a leer **solo
para los bloques `user`**: una modificación ajena que espera en el disco no entra en
vigor a medias porque alguien haya cambiado una contraseña. Todo lo demás sigue
esperando a un reinicio. Aun así, los archivos se leen enteros, de modo que si uno
de ellos ya no carga, la contraseña se escribe y al cliente se le dice *the password
was written but this server did not reload it*: el servidor en ejecución conserva la
anterior hasta que se reinicia.
