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
go get github.com/go-authn/secretsource@v0.5.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:https://fido.invalid/yubikey-5c")
if err != nil { ... }
defer s.Close()          // overwrites the bytes
use(s.Bytes())
```

| Referencia | Lee |
|---|---|
| `file:PATH` | un archivo regular legible solo por su propietario (modo 0600 o más estricto); se quita un salto de línea final |
| `keychain:SERVICE/ACCOUNT` | un elemento de contraseña genérica del Llavero de macOS |
| `secretservice:SERVICE/ACCOUNT` | un elemento de Secret Service de freedesktop con atributos `service=SERVICE`, `account=ACCOUNT` (GNOME Keyring, KWallet, integración Secret Service de KeePassXC) |
| `secretservice:KEY=VALUE[,KEY=VALUE...]` | el único elemento de Secret Service con todos esos atributos; varias coincidencias se rechazan |
| `keepassxc:URL` | la entrada de KeePassXC cuyo **campo URL** es esa URL (`https://NOMBRE.invalid/...` es una buena elección, que nunca se resuelve); dos entradas con la misma URL se rechazan por ambiguas |

`keepassxc:by-uuid/...` y `keepassxc:by-path/...` se **rechazan**: KeePassXC
2.8.0 se cierra con un fallo cuando una búsqueda encuentra una entrada sin URL.

**Ningún esquema ejecuta un comando**: una opción nunca debe poder iniciar un
proceso. Una referencia sin esquema se rechaza, no se adivina como ruta (`file:`
es la forma de escribir una ruta). Un secreto de más de 4096 bytes, o vacío
desde un gestor, se rechaza, y una llamada termina con su contexto (2 minutos
sin plazo) aunque el gestor esté esperando que lo desbloquee.

## KeePassXC {#keepassxc}

KeePassXC se alcanza por su protocolo de integración con el navegador, en macOS
y Linux; Windows aún no está implementado.

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
