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
go get github.com/go-authn/secretsource@v0.2.0
```

```go
s, err := secretsource.Open(ctx, "keepassxc:by-path/Keys/Yubikey PIN")
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
| `keepassxc:by-uuid/HEX` | la entrada de KeePassXC con ese UUID (32 dígitos hexadecimales) |
| `keepassxc:by-path/Group/Title` | la entrada en esa ruta (se omite el nombre del grupo raíz); un título compartido por dos grupos se rechaza por ambiguo, use `by-uuid/` |
| `keepassxc:URL` | la entrada cuyo campo URL coincide |

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
3. Compruebe una referencia sin imprimir el secreto:
   ```sh
   secretsource check 'keepassxc:by-path/Yubikey PIN'
   ```

La primera lectura de una entrada muestra el diálogo de acceso de KeePassXC.

Lo usan `fido --pin-from` (véase [fido]({{< relref "/libraries/fido.md" >}})) y
`theca --pin-from`, `--password-from` y `--recovery-from`.

## Referencia {#reference}

El README de
[github.com/go-authn/secretsource](https://github.com/go-authn/secretsource) es
la fuente de verdad de esta página.
