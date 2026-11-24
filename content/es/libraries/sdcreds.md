---
title: "sdcreds — credenciales de systemd, sin systemd"
linkTitle: "sdcreds"
weight: 37
description: "go-authn/sdcreds lee y escribe el formato de credenciales de systemd (systemd-creds encrypt y decrypt) desde Go, con una línea de comandos y un ayudante de s6 que da a un servicio supervisado su $CREDENTIALS_DIRECTORY."
tags: [libraries, sdcreds, secrets, s6]
---

**¿Y si un servicio necesita las credenciales que una unidad de systemd recibe
con `LoadCredentialEncrypted=`, y no hay systemd?** `sdcreds` lee y escribe el
formato de [credencial de systemd](https://systemd.io/CREDENTIALS/)
(`systemd-creds encrypt` / `decrypt`) desde Go, con una línea de comandos y un
ayudante que da a un servicio supervisado por s6 el mismo
`$CREDENTIALS_DIRECTORY`.

Claves admitidas: **null**, **host** (`/var/lib/systemd/credential.secret`) y
**host-scoped** (`--uid` / `--user`). Las credenciales TPM2 y de clave pública se
reconocen y se rechazan con `*UnsupportedModeError`; no se adivina nada.

## Instalación {#install}

```sh
go install github.com/go-authn/sdcreds/cmd/sdcreds@latest
```

La versión que describen estas páginas es la v0.2.0.

## Línea de comandos {#cli}

```sh
sdcreds setup                                  # create the host secret if missing
sdcreds encrypt --name=db-password plain.txt db-password.cred
sdcreds decrypt db-password.cred -             # the name must match the file name
```

Lo mismo desde Go:

```go
host := sdcreds.HostKeyFile{} // $SYSTEMD_CREDENTIAL_SECRET or the default path
blob, err := sdcreds.Encrypt(secret, sdcreds.EncryptOptions{Key: sdcreds.IDHost, HostKey: host, Name: "db-password"})
text := sdcreds.Armor(blob, sdcreds.ArmorWidth) // what systemd-creds prints
raw, _ := sdcreds.Unarmor([]byte(text))
plain, md, err := sdcreds.Decrypt(raw, sdcreds.DecryptOptions{HostKey: host, Name: &name})
```

## s6 {#s6}

```sh
sdcreds s6-run --service=web --user=svc --source=/etc/creds -- /usr/bin/web
```

`s6-run` descifra cada archivo de `--source` **antes** de montar nada, monta un
`tmpfs` propio del servicio (`nodev,noexec,nosuid,nosymfollow,noswap`, modo 0700,
tamaño y número de inodos acotados; `ramfs` si el kernel no tiene esas
opciones), escribe el texto en claro con modo 0400 y como propietario el usuario
del servicio, lo vuelve a montar en solo lectura, define `CREDENTIALS_DIRECTORY`
y luego inicia el servicio en un proceso hijo que abandona los privilegios
(`no_new_privs`, un conjunto de capacidades vacío) y lo espera.

- `s6-run` sigue siendo el proceso que s6 supervisa: reenvía `TERM`, `INT`,
  `HUP`, `QUIT`, `USR1`, `USR2`, `ALRM` y `CONT` al servicio, termina con su
  estado (128 más el número de señal si una señal lo mató), transmite los
  descriptores recibidos, y el servicio se mata si `s6-run` muere.
- Las credenciales se retiran cuando el servicio termina, y antes de que
  `s6-run` falle si el programa no se puede ejecutar.
- El montaje vive por defecto en un espacio de nombres privado
  (`--unshare=false` lo desactiva), así que desaparece con el servicio.
- Una credencial sellada con la clave null se rechaza salvo que se indique
  `--allow-null`, y una que no lleva nombre se rechaza siempre.
- `sdcreds s6-finish --service=web` desmonta de forma diferida y elimina el
  directorio; es idempotente. Con `--unshare=false`, un `SIGKILL` de `s6-run` deja
  el montaje en su sitio hasta que se ejecuta `s6-finish`: póngalo en el script
  finish del servicio.
- Como máximo 1024 credenciales y 16 MiB por servicio. Solo Linux; en otros
  sistemas los comandos informan `ErrUnsupported`.

Los archivos de clave indicados por `--secret` y `--machine-id-file` deben
pertenecer a root y no ser escribibles por el grupo ni por otros, y lo mismo
cada directorio por encima hasta `/`. El archivo de clave se abre una sola vez,
sin seguir un enlace final, y la clave se borra de la memoria de `s6-run`
cuando termina con las credenciales. Solo el hijo adopta la identidad del
servicio; `s6-run` y todos sus hilos siguen siendo root.

### Conservar una capacidad: `--keep-cap` {#keep-cap}

```sh
sdcreds s6-run --service=vpn --user=svc --source=/etc/creds --keep-cap=CAP_NET_ADMIN -- /usr/bin/vpn
```

La opción es repetible y separada por comas (`--keep-cap=CAP_NET_ADMIN,CAP_NET_RAW`
o una opción cada una) y **no tiene valor por defecto**: sin ella, el servicio se
ejecuta con todos los conjuntos de capacidades vacíos.

Es una **lista de permitidas** de siete capacidades, ninguna equivalente a root ni
capaz de leer o escribir el tmpfs de credenciales ni de enviar señales a `s6-run`:
`CAP_NET_ADMIN`, `CAP_NET_BIND_SERVICE`, `CAP_NET_RAW`, `CAP_NET_BROADCAST`,
`CAP_IPC_LOCK`, `CAP_WAKE_ALARM` y `CAP_BLOCK_SUSPEND`. Cualquier otra capacidad, o
un nombre que no sea una capacidad, es un error que nombra la lista, notificado
antes de leer la clave o de montar nada.

El servicio tiene, en sus conjuntos bounding, permitted, inheritable, effective y
ambient, exactamente las capacidades conservadas y nada más. `no_new_privs`
permanece activo, y los securebits valen 0x3 (`SECBIT_NOROOT` activado y
bloqueado). Los privilegios del propio `s6-run` no cambian.

`CAP_NET_ADMIN` actúa sobre el espacio de nombres de red en el que se ejecuta el
servicio, que es el del host salvo que el servicio se inicie en un espacio de
nombres de red propio (`--unshare` solo le da un espacio de nombres de montaje
privado): allí puede cambiar interfaces, rutas y el cortafuegos. Ejecute ese
servicio en su propio espacio de nombres de red cuando importe.

## Interoperabilidad {#interop}

Ambas direcciones se prueban contra el `systemd-creds` real **262.2**, compilado
a partir de la etiqueta `v262.2` (sin paquete de distribución).

- `testdata/systemd-v262.2` contiene 44 credenciales escritas por systemd-creds
  (null, host y host-scoped; con y sin nombre; not-after ausente, pasado y
  futuro; cargas de 0 B, 1 B y 64 KiB; cinco variantes manipuladas), y
  `manifest.json` registra lo que el propio systemd-creds respondió en cada uno
  de los 272 intentos de descifrado (nombre correcto e incorrecto, antes y
  después de not-after, con y sin `--uid`). La biblioteca da la misma
  respuesta, con la misma clase de error, en todos.
- Con un IV fijo, `Encrypt` reproduce exactamente los bytes de systemd.
- En el contenedor, `systemd-creds decrypt` abre lo que escribió `Encrypt`, y la
  línea de comandos pasa el mismo viaje de ida y vuelta en ambas direcciones.

```sh
docker build -t sdcreds-interop docker
docker run --rm --privileged -e SDCREDS_REQUIRE_SYSTEMD=1 -e SDCREDS_S6_INTEGRATION=1 \
  -v "$PWD":/src/sdcreds -w /src/sdcreds sdcreds-interop \
  sh -c 'echo 0123456789abcdef0123456789abcdef > /etc/machine-id && go test -count=1 ./...'
```

Sin `SDCREDS_REQUIRE_SYSTEMD=1`, las pruebas que necesitan el binario se omiten;
la CI lo define, de modo que allí un binario ausente es un fallo. El límite de
1 MiB solo lo cubren las pruebas de la biblioteca, no vectores de
interoperabilidad.

## Diferencias respecto a systemd {#deviations}

- Un secreto de host cuyo identificador de máquina no coincide se **rechaza**
  (`ErrHostKeyMachine`); systemd lo elimina.
- `--with-key=auto` significa `host`: aquí no hay TPM2.
- Una credencial sellada con la clave null no tiene secreto: `sdcreds decrypt` la
  rechaza en cualquier máquina salvo que se indique `--allow-null` (systemd, en
  cambio, consulta el estado de TPM2 y SecureBoot; esa política de la
  biblioteca, `SystemNullPolicy`, no la usa la CLI).
- `SDCREDS_MACHINE_ID_FILE` (`encrypt`, `decrypt`, `setup`) apunta a otro
  archivo de identificador de máquina. `s6-run` lo ignora, y también
  `SYSTEMD_CREDENTIAL_SECRET`: su clave viene de los archivos por defecto, o de
  `--secret` y `--machine-id-file`.
- Un tamaño de IV variable se acepta al leer, como en systemd; esta biblioteca
  siempre escribe 12 bytes.
- El secreto se abre sin seguir un enlace simbólico final, y debe ser un archivo
  regular con un solo enlace y modo `0400`, como exige systemd.

## Seguridad {#safety}

Cada longitud se comprueba antes de usarla, antes de asignar nada, y a ambos
lados de su límite; las credenciales se limitan a 1 MiB (como systemd) y el
secreto de host a 16 MiB. Los analizadores se fuzzean en la CI con el corpus
versionado, y `govulncheck` se ejecuta en la CI. El README aún no tiene tabla de
rendimiento: la medición está aplazada, un punto abierto y no un resultado.

## Referencia {#reference}

El README de
[github.com/go-authn/sdcreds](https://github.com/go-authn/sdcreds) es la fuente
de verdad de esta página. Consulte el `LICENSE` del módulo.
