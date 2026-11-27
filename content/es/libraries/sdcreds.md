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

La versión que describen estas páginas es la v0.4.0.

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

## `sdcreds run`: OpenBSD y Linux {#run}

```sh
sdcreds run --service=web --user=svc --source=/etc/creds [--class=daemon] -- /usr/local/bin/web
```

`run` descifra los archivos sellados de `--source`, los hace visibles al
programa como archivos de solo lectura propiedad de `--user` bajo
`$CREDENTIALS_DIRECTORY`, lo ejecuta como ese usuario y los elimina cuando
termina. En Linux es `s6-run` con las mismas opciones. `--check` ejecuta todas
las negativas y no descifra nada (úselo en un `rc_pre` de rc.d). Una negativa
sale con estado 2 y ocurre antes de leer la clave del host. En OpenBSD los
archivos viven en un sistema de archivos en memoria (MFS) montado para el
servicio y puesto a cero al final:

- **No hay espacio de nombres de montaje.** Mientras el programa se ejecuta, las
  credenciales son visibles para cualquier proceso que alcance el directorio, y
  root siempre puede leerlas.
- **La clave del host** es `/etc/sdcreds/host.key`, propiedad de root, modo 0600;
  cualquier otro modo o propietario se rechaza. Créela con
  `sdcreds setup --path /etc/sdcreds/host.key` y luego `chmod 600`. El
  identificador de máquina es `sysctl hw.uuid`. `--secret` y
  `--machine-id-file` sustituyen a ambos y pasan por las mismas comprobaciones de
  propietario y modo.
- **`--user` nunca es root**: el uid 0, el gid 0 y cualquier grupo suplementario
  0 se rechazan, en `run` y en la biblioteca (`s6.Run`, `delivery`); ninguna
  opción lo permite. El programa debe ser una ruta absoluta y normalizada que el
  usuario pueda ejecutar.
- **Matar sdcreds mata el programa** y desmonta, incluso con `SIGKILL`. Un
  proceso auxiliar mantiene el cerrojo del servicio y vigila a sdcreds; sea cual
  sea el final, mata todo lo que ejecuta el usuario del servicio (por uid, así
  que un programa que llamó a `setsid` no escapa) y luego desmonta. root nunca
  envía una señal a un pid leído de una lista. Desde la v0.4.0 la muerte la
  provoca un proceso asesino de corta vida que root lanza y que pasa a
  credenciales divididas (uid real y guardado de un usuario asesino reservado,
  uid efectivo del usuario del servicio) antes de señalar nada: el núcleo le deja
  entonces señalar a todo proceso del usuario del servicio, mientras que ningún
  proceso de ese usuario puede señalarlo. El asesino envía `kill(-1, SIGKILL)`
  hasta que el núcleo no encuentra nada; los asesinos se serializan con un
  cerrojo (`/var/run/sdcreds-killer.lock`). **Requisito de instalación:** cree
  el usuario asesino, que no debe poseer ningún proceso ni ser root ni un usuario
  de servicio:
  `useradd -s /sbin/nologin -d /var/empty -c "sdcreds killer" _sdkill`. Sin él se
  rechaza el arranque de una entrega. Un proceso que solo retiene al usuario por
  un archivo set-uid ejecutado por otro usuario lo cuenta la comprobación de
  arranque, pero el asesino no lo alcanza: la liberación informa entonces de que
  un proceso sobrevivió y el siguiente arranque se rechaza hasta que desaparezca
  (falla de forma segura). Si un proceso sobrevive al
  presupuesto de 20 s, el auxiliar desmonta igualmente (los secretos
  desaparecen), informa del fallo y sale con un estado distinto de cero. Un
  usuario pertenece a una sola entrega a la vez (el `.uid-<N>.lock` de
  `/var/run/sdcreds`), y `run` rechaza a un usuario que ya tiene otros procesos:
  dé al servicio su propio usuario. Si sdcreds y el auxiliar mueren ambos,
  `sdcreds sweep [--base DIR] [--service S]` (o el siguiente arranque del
  servicio) elimina lo que queda. Si la liberación falla después de que el
  programa termine, sdcreds sale con estado 70 (o con el del programa si ya era
  un fallo) y explica el motivo por stderr.
- **Estado de salida de `run`** (desde la v0.4.0). El estado del programa se
  transmite tal cual (un programa matado por la señal `n` da `128+n`). Los
  finales propios de sdcreds tienen estados reservados, fuera de los rangos 0-2 y
  64-78 que suelen usar los demonios: **125** sdcreds se negó, no se inició nada
  (opción incorrecta, usuario desconocido o root, swap sin cifrar, una ejecución
  que sigue viva; permanente hasta que algo cambie); **126** sdcreds falló tras
  empezar (entrega, auxiliar perdido, programa no ejecutable; puede ser
  transitorio); **70** el programa terminó pero la liberación falló. Un programa
  que sale por sí mismo con 125 o 126 no se puede distinguir. Antes de la v0.4.0
  una negativa salía con 2 y un fallo con 1.
- **Reinicio.** Un arranque espera hasta 30 s a que la ejecución anterior del
  mismo servicio termine de desmontarse en lugar de ser rechazado; una ejecución
  que siga viva después se rechaza (125). Un segundo servicio para el mismo
  usuario sigue rechazándose de inmediato.
- **El swap debe estar cifrado.** `run` se niega a arrancar cuando
  `sysctl vm.swapencrypt.enable` es 0, no se puede leer o no existe. Ninguna
  opción lo evita. En la biblioteca, `s6.Config` necesita un `ReadSource` (el
  comando entrega el lector que recorre la cadena de confianza), o `s6.Run`
  rechaza.
- **Las imágenes de sistema de archivos incrustadas están fijadas**: el sha256 de
  cada `delivery/images/ffs-<N>MiB.gz` se comprueba antes de que el auxiliar la
  descomprima.
- **`--class`** se busca primero en `/etc/login.conf.d/<class>` y después en
  `/etc/login.conf`; no se consulta `login.conf.db`. Los límites de recursos de
  la clase se aplican al programa, solo reduciendo lo que tendría, y una clase
  que no se puede leer o analizar es una negativa. No se aplican la prioridad ni
  la umask; el programa recibe la umask 077.
- **El entorno del programa es una lista de permitidos**: `PATH` (valor fijo por
  defecto), `CREDENTIALS_DIRECTORY`, `LANG`, `TZ`, `TERM` y `LC_*`. Los
  descriptores por encima de 2 se cierran antes de ejecutarlo.
- **Pasar el entorno y descriptores** (OpenBSD, desde la v0.4.0).
  `--pass-env NOMBRE` (repetible) entrega tal cual al programa la variable
  `NOMBRE` del entorno de sdcreds (no se pasa si no está definida); `--pass-fd N`
  (repetible) mantiene abierto el descriptor `N` en el programa con el mismo
  número. Ambos se rechazan para lo que pertenece a sdcreds: `PATH`,
  `CREDENTIALS_DIRECTORY`, `__SDCREDS_*`; los descriptores 0 a 3; un descriptor
  que no está abierto o es close-on-exec. Un supervisor de un servicio de tipo
  notify pasa, por ejemplo,
  `--pass-env NOTIFY_SOCKET --pass-env LISTEN_FDS --pass-env LISTEN_PID --pass-fd 4`.
  `LISTEN_PID` se pasa tal cual: nombra el pid que esperaba quien llama, no el
  del programa.
- **Memoria.** El texto en claro está en la memoria del proceso sdcreds durante
  poco tiempo. `mlockall` no se puede usar desde un proceso Go en OpenBSD
  (medido en 8.0), así que la protección es `vm.swapencrypt.enable` (comprobado
  al arrancar), los volcados de memoria desactivados y `kern.nosuidcoredump`. Un
  volcado tomado por un administrador aún puede contener el texto en claro.
- `--keep-cap` solo existe en Linux.

`docs/openbsd/authn_bridge`, en el repositorio, es un script rc.d que ejecuta
go-authn/bridge de este modo. La entrega también es una biblioteca, el paquete
`delivery`.

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
