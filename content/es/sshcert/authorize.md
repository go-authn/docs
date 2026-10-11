---
title: "sshcert-authorize"
linkTitle: "sshcert-authorize"
weight: 10
description: "Qué comprueba sshcert-authorize cuando sshd lo ejecuta como AuthorizedPrincipalsCommand, qué rechaza y por qué también se rechaza un certificado sin concesión de dominio."
tags: [sshcert, ssh, sshd, eurohpc]
---

`sshd` le pregunta, en cada inicio de sesión con certificado, qué principales pueden
iniciar sesión en la cuenta. Responde con los principales de la cuenta solo si la
concesión de dominio del certificado nombra este host; en caso contrario no responde
nada, y `sshd` rechaza el certificado. Adopta los argumentos, las opciones, la salida
y el formato de log del `ssh-cert-authorize` de GÉANT, y se diferencia en lo que
rechaza.

## Cómo lo llama sshd {#how-sshd-calls-it}

```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/efp-ssh-ca.pub
AuthorizedPrincipalsCommand /usr/local/bin/sshcert-authorize %u %k
AuthorizedPrincipalsCommandUser nobody
```

```sh
install -o root -g root -m 0755 sshcert-authorize /usr/local/bin/
echo login.example.org > /etc/ssh/cert-allowed-domain.conf
```

y, para cada cuenta local, los principales que pueden iniciar sesión en ella, uno por
línea, en `/etc/ssh/auth_principals/<account>`. sshd solo ejecuta el comando desde
una ruta cuyo propietario es root y en la que nadie más puede escribir.

`%u` es la cuenta en la que se inicia sesión. `%k` es el certificado, en base64;
también se lee una línea completa `ssh-...-cert-v01@openssh.com BASE64`, y cuando
falta el argumento el certificado se lee de la entrada estándar. Un tercer
argumento, cuando lo hay (el `%t` de sshd), debe ser el tipo del certificado; si no,
el certificado se rechaza.

| salida | muestra | sshd |
|---|---|---|
| `0` | los principales de la cuenta, uno por línea | deja pasar el certificado si uno de sus principales está entre ellos |
| `1` | nada | lo rechaza |
| `2` | nada | lo rechaza: los argumentos eran incorrectos |

{{< callout type="info" >}}
**No comprueba la firma, la CA ni las fechas de validez**

Nada en el comando verifica la firma del certificado ni su periodo de
validez: lo hace sshd, que confía en la CA mediante `TrustedUserCAKeys`.
El comando decide una sola cuestión: si el certificado está destinado a
este host y a esta cuenta.
{{< /callout >}}

## Qué rechaza {#what-it-refuses}

En el orden en que lo comprueba:

1. un nombre de cuenta vacío, `.`, `..`, o que contiene `/`, `\` o un NUL;
2. un host sin dominio configurado, o con uno que no es un nombre de host válido;
3. un certificado que no se puede analizar, una clave simple o un certificado de host;
4. un `%t` que no es el tipo del certificado;
5. con `--krl`, un certificado que la lista revoca, o **todos** los certificados
   cuando la lista no se puede leer o ha caducado;
6. una concesión de dominio presente y mal formada, **sean cuales sean las opciones**;
7. **ninguna concesión de dominio**, salvo con `--allow-no-grant`;
8. una concesión ninguno de cuyos patrones coincide con alguno de los nombres del host;
9. una cuenta sin archivo de principales, o con uno vacío.

Los nombres del host son `--domain`, o la variable que nombra `--domain-env`, o las
líneas de `--domain-file` (se ignoran las líneas en blanco y los comentarios `#`;
varias líneas son varios nombres, cualquiera de los cuales puede coincidir).

Con certificados firmados por una CA de prueba para la cuenta `alice`, cuyo archivo
de principales lista `a1b2c3@univ-example.example`, en un host llamado
`login.hpc.example.org`:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
a1b2c3@univ-example.example
```

La última línea es la respuesta que lee sshd; las líneas anteriores son el log, aquí
en la salida de error estándar. Un certificado que concede otros hosts:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-other-cert.pub)"
INFO: action=cert_processed serial=1003 key_id="a1b2c3@univ-example.example other host" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="domain not granted" grant=["*.elsewhere.example.net"] serial=1003 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
```

Un certificado sin concesión:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="no domain grant" serial=1002 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
```

Una cuenta sin archivo de principales, y una clave simple:

```
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals bob "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=bob domain=login.hpc.example.org reason="no principals file for the user" serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
$ sshcert-authorize --syslog=false --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice.pub)"
WARNING: action=denied user=alice domain=login.hpc.example.org reason="a ssh-ed25519 key, not a certificate"
```

Cada uno de ellos salió con `1`, y no mostró nada en la salida estándar.

## Por qué se rechaza un certificado sin concesión {#why-a-certificate-with-no-grant-is-refused}

El `ssh-cert-authorize` de GÉANT deja pasar un certificado sin concesión de dominio
("might be valid for non-domain-based auth"), y también uno cuya concesión no puede
analizar, o que está vacía. Entonces un sitio que confía en **dos** CA en
`TrustedUserCAKeys` (la de la federación, y la suya propia para el personal, o una CA
de prueba) deja entrar un certificado de la segunda CA en todos los hosts, para
cualquier principal de un archivo de principales, sin ninguna comprobación de
dominio. El filtro de dominio solo es un filtro si se rechaza un certificado que no
dice dónde puede usarse.

Un sitio que de verdad quiere el comportamiento de GÉANT lo indica, y el comando lo
registra en el log cada vez que lo aplica:

```
$ sshcert-authorize --syslog=false --allow-no-grant --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-nogrant-cert.pub)"
INFO: action=cert_processed serial=1002 key_id="a1b2c3@univ-example.example no grant" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=no_grant_allowed user=alice domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1002 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
a1b2c3@univ-example.example
```

Incluso entonces, una concesión presente pero mal formada se rechaza.

## `--krl` {#krl}

`RevokedKeys` es la comprobación propia de sshd, hecha antes de que se ejecute el
comando, para cada clave y cada certificado, y además revoca una clave de CA;
prefiérala. `--krl FILE` comprueba una KRL de OpenSSH dentro del comando, y añade lo
que sshd no hace: rechaza **todos** los certificados en cuanto la lista ha caducado
(su extensión `expires@go-authn.github.io`, que sshd ignora), y todos los
certificados cuando la lista no se puede leer. Una lista sin caducidad se usa sin
ella.

Tres ejecuciones: con la KRL que escribe [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}),
primero una vigente y después la de modo cerrado que escribe cuando la lista del emisor
[caduca]({{< relref "/authn-revokd/lapse.md" >}}); y por último con `--krl` apuntando a un
archivo que no existe:

```
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
INFO: action=authorized user=alice cert_principals=["a1b2c3@univ-example.example"] server_principals=["a1b2c3@univ-example.example"] domain=login.hpc.example.org serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
a1b2c3@univ-example.example
$ sshcert-authorize --syslog=false --krl ../revokd/out/sshd.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="certificate revoked" serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
$ sshcert-authorize --syslog=false --krl missing.krl --domain-file cert-allowed-domain.conf --principals-dir auth_principals alice "$(cut -d' ' -f2 alice-cert.pub)"
INFO: action=cert_processed serial=1001 key_id="a1b2c3@univ-example.example granted" extension=ssh-domain-grant@core.aai.geant.org ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
WARNING: action=denied user=alice domain=login.hpc.example.org reason="KRL unreadable: open missing.krl: no such file or directory" serial=1001 ca_fingerprint=SHA256:7GyzrO0VHgZU9+qMOkMF94eTVc9IXbMBal/1TyL1BGk
```

La segunda ejecución se rechaza porque la lista de modo cerrado revoca la **clave de la CA** del
certificado: la comprobación abarca la propia clave del certificado, su número de
serie y su ID de clave, y la clave que lo firmó. La tercera se rechaza porque la lista
no se puede leer: la falta de lista no se toma por «nada revocado».

## Opciones {#flags}

```
$ sshcert-authorize -help
usage: sshcert-authorize [flags] USER [CERTIFICATE [KEYTYPE]]

An sshd AuthorizedPrincipalsCommand (%u %k) that refuses a certificate whose
ssh-domain-grant@core.aai.geant.org extension does not grant this host, or that has none.

  -allow-no-grant
    	let in a certificate with no domain grant (GÉANT's behaviour); a malformed grant is still refused
  -debug
    	log details
  -domain string
    	the host's domain (overrides --domain-env and --domain-file)
  -domain-env string
    	environment variable holding the host's domain
  -domain-file string
    	file holding the host's domain, one name per line (default "/etc/ssh/cert-allowed-domain.conf")
  -extension string
    	name of the domain-grant extension (default "ssh-domain-grant@core.aai.geant.org")
  -krl string
    	refuse certificates this OpenSSH KRL revokes, and every certificate once it has expired or cannot be read
  -principals-dir string
    	directory of principals files, one per user (default "/etc/ssh/auth_principals")
  -syslog
    	log to syslog, facility AUTH (--syslog=false: to stderr) (default true)
  -version
    	print the version and exit
```

Los **logs** son líneas `key=value` (`action=cert_processed`, `action=denied`,
`action=authorized`, con `serial` y `ca_fingerprint`), enviadas por defecto a syslog,
facilidad AUTH. sshd descarta la salida de error estándar del comando, así que
mantenga syslog activado en producción; `--debug` también escribe todo en la salida
de error estándar. Un valor que procede del cliente, como el nombre de cuenta, se
entrecomilla cuando contiene un espacio, `=`, una comilla o un carácter de control,
de modo que no puede falsificar un campo del log.

**`-version`** muestra la versión del módulo, tanto en un binario de versión como en
uno compilado con `go install`:

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.5
$ sshcert-authorize -version
sshcert-authorize v0.1.5
```

Antes de la v0.1.5, un binario de `go install` mostraba `sshcert-authorize dev`.
