---
title: "secretsource — un secreto desde una referencia"
linkTitle: "secretsource"
weight: 35
description: "go-authn/secretsource obtiene un PIN, una contraseña o un código de recuperación desde una referencia (un archivo, el Llavero de macOS, un Secret Service, KeePassXC), para que ningún archivo en claro quede en el disco."
tags: [bibliotecas, secretsource, secretos]
---

**¿De dónde sale un PIN, cuando no debe quedar en un archivo?** Una
**referencia** dice dónde vive un secreto; `secretsource.Open` lo trae. La
referencia no contiene ningún secreto, así que puede estar en una opción, un
script o el historial del shell.

```sh
go get github.com/go-authn/secretsource@v0.9.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Referencia | Lee |
|---|---|
| `file:PATH` | un archivo regular legible solo por su propietario (Unix: modo 0600 o más estricto; Windows, desde la v0.7.0: una lista de acceso que no concede derecho de lectura ni de escritura a nadie salvo el propietario, SYSTEM y el grupo Administradores); se quita un salto de línea final; un archivo vacío, o que solo contiene un fin de línea, se rechaza con `ErrEmpty` (desde la v0.6.0), y una FIFO se rechaza por no ser un archivo regular |
| `keychain:SERVICE/ACCOUNT` | un elemento de contraseña genérica del Llavero de macOS |
| `secretservice:SERVICE/ACCOUNT` | un elemento de Secret Service de freedesktop con atributos `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, integración Secret Service de KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | el único elemento de Secret Service con todos esos atributos; varias coincidencias se rechazan |
| `keepassxc:URL` | la entrada de KeePassXC cuyo **campo URL** es esa URL (`https://NOMBRE.invalid/...` es una buena elección, que nunca se resuelve); dos entradas con la misma URL se rechazan por ambiguas |
| `systemd-creds:NAME` | (Linux, desde v0.8.0) una credencial de systemd, devuelta byte a byte: no se elimina el salto de línea final, a diferencia de `file:`. Primero el archivo `NAME` en `$CREDENTIALS_DIRECTORY` (colocado por `LoadCredential=`, `LoadCredentialEncrypted=`, `SetCredentialEncrypted=`); si no, `NAME` o `NAME.cred` en `credstore.encrypted` de `/etc`, `/run`, `/usr/lib`, descifrado con `systemd-creds decrypt`. Se rechaza con `ErrUnavailable` en otros sistemas |

**`file:` no sigue un enlace simbólico** (desde v0.9.0). Un enlace en el último
componente de la ruta, colgante o no, se rechaza: en Unix el archivo se abre con
`O_NOFOLLOW`, en Windows con `FILE_FLAG_OPEN_REPARSE_POINT` y cualquier punto de
reanálisis se rechaza (también un marcador de posición de archivos en la nube:
apunte a una copia local ordinaria). En Unix, el archivo debe además pertenecer
al usuario que llama; root no queda exento. **Migración:** apunte al archivo
real (`readlink -f PATH`). Un enlace simbólico en un directorio anterior de la
ruta sigue funcionando.

`keepassxc:by-uuid/...` y `keepassxc:by-path/...` se **rechazan**: KeePassXC
2.8.0 se cierra con un fallo cuando una búsqueda encuentra una entrada sin URL.

**Ningún esquema ejecuta un comando**: una opción nunca debe poder iniciar un
proceso. Una referencia sin esquema se rechaza, no se adivina como ruta (`file:`
es la forma de escribir una ruta). Un secreto de más de 4096 bytes, o vacío
desde un gestor o un `file:`, se rechaza (`ErrEmpty`), y una llamada termina con su contexto (2 minutos
sin plazo) aunque el gestor esté esperando que lo desbloquee.

## Credenciales de systemd {#systemd-creds}

Gramática, exactamente: `systemd-creds:NAME`, el esquema en minúsculas, dos
puntos y el nombre de la credencial tal como se dio a `LoadCredential=`,
`LoadCredentialEncrypted=` o `systemd-creds encrypt --name=`, por ejemplo
`systemd-creds:smtp`. `NAME` es un nombre de archivo simple de 1 a 255 bytes: sin
`/` (por tanto, no es una ruta), ni `.` ni `..`, sin caracteres de control y sin
sufijo `.cred` (el sufijo pertenece al archivo; `smtp` encuentra `smtp` o
`smtp.cred`).

- El archivo de `$CREDENTIALS_DIRECTORY` se abre con `O_NOFOLLOW`, debe ser un
  archivo regular propiedad de root o del llamador, sin acceso para "otros" (los
  bits de grupo se aceptan: systemd da a un servicio con `User=` un archivo 0440
  de root con una ACL); el directorio igual. Se rechaza un enlace simbólico o un
  modo demasiado abierto.
- Si no, se ejecuta directamente `systemd-creds decrypt --name=NAME PATH -`: sin
  shell, con entorno vacío, el secreto leído solo de la salida estándar, como
  máximo 4096 bytes, acotado por el contexto. Un llamador que no es root prueba
  primero `--user` (systemd 256 o posterior).
- Sin recorte: se conservan el salto de línea final, los bytes NUL y los bytes que
  no son UTF-8; selle una contraseña con `printf %s`.
- Medido en systemd 257 (Debian 13) con `--with-key=host`; no medido con una clave
  TPM2. Un descifrado fallido devuelve `ErrUnavailable` e indica que quizá haya
  que volver a sellar la credencial.
- Vinculación a PCR: `--tpm2-pcrs=` es vacío por defecto. Un `--tpm2-pcrs=7`
  desnudo puede bloquear todas las credenciales tras una actualización de
  firmware o de shim o una migración de vTPM. Prefiera `--with-key=host+tpm2`, una
  política de PCR firmada (`--tpm2-public-key`, PCR 11) o `systemd-pcrlock`, y
  conserve una copia del secreto para volver a sellarlo.

## KeePassXC {#keepassxc}

KeePassXC se alcanza por su protocolo de integración con el navegador, en macOS
y Linux; Windows aún no está implementado. Desde la v0.6.0, en Unix, el socket se
rechaza cuando es un enlace simbólico o cuando su directorio es propiedad de otro
usuario o es escribible por el grupo u otros, y el uid del par conectado se comprueba
tras el dial; el enlace simbólico heredado
`$XDG_RUNTIME_DIR/org.keepassxc.KeePassXC.BrowserServer` ya no se sigue (sí el socket
real bajo `app/org.keepassxc.KeePassXC/`).

Desde la v0.6.1, el archivo de asociación (el almacén de reserva, usado cuando no hay
ni el llavero de macOS ni un Secret Service) se escribe en un archivo temporal nuevo del
mismo directorio y se renombra al nombre final, de modo que un enlace simbólico dejado
en ese nombre se sustituye, no se sigue, y un archivo de modo más permisivo queda en
0600. En Unix se comprueba antes el directorio, como el del socket: propiedad de este
usuario, no escribible por el grupo ni por otros, no un enlace simbólico; si no, no se
escribe nada.

1. En KeePassXC, active *Settings > Browser Integration*.
2. Asocie esta máquina una vez por base de datos y apruébelo en KeePassXC:
   ```sh
   go install github.com/go-authn/secretsource/cmd/secretsource@latest
   secretsource keepassxc associate
   ```
3. Cree la entrada y **rellene su campo URL** con
   `https://fido.invalid/yubikey-5c` (cualquier URL que ninguna otra entrada
   use: la referencia es esa URL). Compruebe la referencia sin imprimir el
   secreto:
   ```sh
   secretsource check 'keepassxc:https://fido.invalid/yubikey-5c'
   ```

La primera lectura de una entrada muestra el diálogo de acceso de KeePassXC.

Lo usan `fido --pin-from` (véase [fido]({{< relref "/libraries/fido.md" >}})) y
`theca --pin-from`, `--password-from` y `--recovery-from`.

## Tomar un secreto de una opción de la línea de comandos: `secretsource/secretflag` {#secretflag}

Un secreto pasado como valor de una opción es visible en `ps`. El paquete
`secretflag` da a un comando el par `--<nombre>` (obsoleta, avisa por stderr) y
`--<nombre>-from <ref>`, mutuamente excluyentes, con la referencia resuelta por
`secretsource.Open`:

```go
var password string
b := secretflag.Add(cmd, "password", &password, "the admin password") // cobra
// or: secretflag.AddStd(fs, os.Stderr, "password", &password, "the admin password", "p")
// ... after parsing:
if err := secretflag.Resolve(ctx, b); err != nil { return err }
```

`Add` registra el par en un comando de cobra, `AddStd` en un `flag.FlagSet` de
la biblioteca estándar (con alias como `-t`); `Resolve` lee las referencias.
Disponible desde v0.10.0.

## Guardar un secreto: `secretsource store` {#store}

No hace falta crear ninguna entrada a mano. `secretsource store REF [--group G]
[--login L] [--replace] [--generate N]` escribe el secreto para `keychain:`,
`secretservice:SERVICE/ACCOUNT`, `secretservice:KEY=VALUE` y `keepassxc:URL`:

```sh
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c'
secretsource store 'keepassxc:https://fido.invalid/yubikey-5c' --generate 24
printf '%s' "$PIN" | secretsource store keychain:fido/yubikey-5c
```

El secreto se escribe dos veces sin eco, o se lee de la entrada estándar cuando
no es un terminal; nunca se toma de un argumento ni del entorno. `--generate N`
genera N letras y dígitos y no imprime nada secreto. Una entrada existente se
rechaza salvo con `--replace` (en KeePassXC actualiza esa entrada, hallada por
su URL). `file:` se rechaza.

Para `keepassxc:` usa el `set-login` del protocolo del navegador: la entrada
siempre lleva la URL que permite encontrarla de nuevo, y un duplicado se busca
por URL. El usuario por defecto es el host de la URL (`--login`), el grupo es
`KeePassXC-Browser Passwords` salvo que `--group` nombre uno bajo la raíz, y
`--title` se rechaza porque KeePassXC 2.8.0 lo ignora. KeePassXC muestra sus
propios diálogos.

## Referencia {#reference}

El README de
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) es
la fuente de verdad de esta página.
