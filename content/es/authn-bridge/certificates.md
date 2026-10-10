---
title: "Certificados"
linkTitle: "Certificados"
weight: 50
description: "Los certificados de usuario SSH que firma authn-bridge, su perfil para la EuroHPC Federation Platform, y los certificados de cliente X.509 que emite para NFS sobre TLS."
tags: [authn-bridge, ssh, x509, eurohpc]
---

Una persona que ha iniciado sesión puede obtener la certificación de una clave
pública SSH, o la emisión de un certificado de cliente X.509, durante unas horas. Un
servidor que confía en la CA del proveedor la deja entrar sin ningún archivo de
cuentas que editar allí. Cada certificado **se registra en `certificates_file` antes
de entregarse**: uno que no se puede registrar no se emite, ya que nunca podría
revocarse, y los revocados se publican en la
[KRL y la CRL]({{< relref "/authn-bridge/revocation.md" >}}).

## Certificados SSH {#ssh-certificates}

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

ssh_ca {
  key_file = "/var/lib/authn-bridge/ssh-ca"   # authn-bridge keygen --ssh-ca; Ed25519
  validity = "12h"                            # the default; a week at most
}

client "sftp" {
  device           = true
  ssh_certificates = true
}
```

`authn-bridge ssh-cert --issuer https://login.example.org --client sftp` inicia
sesión con un código, envía `~/.ssh/id_ed25519.pub` (o `--key`) a
`/ssh/certificate` con un token del ámbito `ssh`, y escribe `<key>-cert.pub` a su
lado, donde lo encuentran `ssh` y `sftp`.

La clave de la CA debe ser Ed25519: una clave de CA RSA firma con SHA-1 salvo que se
le indique otra cosa, y OpenSSH lo rechaza por defecto desde la 8.8.

**Lo que dice el certificado.**

- **Exactamente un principal**, el `preferred_username` de la persona salvo que el
  perfil del cliente indique otro claim. Un certificado sin principal es válido para
  *cualquier* usuario (PROTOCOL.certkeys), así que una persona sin nombre de usuario
  no obtiene ninguno. Un nombre que contiene una coma, un espacio, una comilla, una
  barra invertida o un carácter de control se rechaza (`403`): `sshd` lee
  `principals="a,b"` y las entradas de `AuthorizedPrincipalsFile` como listas, así
  que uno de esos nombres son dos.
- **Key ID** `<principal> sub=<sub> jti=<token id>`: lo que registra `sshd`.
- **Ninguna extensión `permit-*`** por defecto. SFTP no necesita ninguna, y un
  certificado que no permite pty, ni reenvío, ni archivo rc concede acceso a los
  archivos y nada más.
- **Los grupos de la persona** en la extensión `groups@go-authn.org`, uno por línea,
  cuando el token lleva grupos. OpenSSH la ignora; está firmada, así que un servidor
  que autoriza por grupo puede creérsela.
- **Válido** desde hace cinco minutos (para relojes que no coinciden) hasta
  `validity` a partir de ahora, o hasta que termine la sesión del IdP si eso ocurre
  antes.
- **La clave** debe ser Ed25519, ECDSA P-256/384/521, una llave de seguridad
  (`sk-`), o RSA de al menos 2048 bits. Un certificado se rechaza como clave.

## El perfil de CA SSH de EuroHPC {#the-eurohpc-ssh-ca-profile}

La CA SSH de la EuroHPC Federation Platform (GÉANT / MyAccessID) emite certificados
Ed25519 válidos una hora, con un principal que nombra a la persona en toda la
federación, y los hosts a los que van destinados en la extensión
`ssh-domain-grant@core.aai.geant.org` de GÉANT. Un cliente puede hacer que sus
certificados se emitan con esa forma. Cada clave es propia del cliente y opcional;
un cliente que no establece ninguna obtiene el certificado descrito arriba.

```hcl
client "efp" {
  device              = true
  ssh_certificates    = true
  ssh_principal_claim = "voperson_id"               # the default is preferred_username
  ssh_validity        = "1h"                        # never longer than ssh_ca's, nor the IdP's session
  ssh_extensions      = ["permit-pty"]              # none by default
  ssh_domain_grants   = ["login.hpc.example.org"]   # the hosting entity's hosts
  # ssh_source_address = ["192.0.2.0/24"]           # the source-address critical option
}
```

| clave | |
|---|---|
| `ssh_principal_claim` | `preferred_username`, `sub`, `voperson_id` o `eduperson_principal_name`. Los dos últimos los entrega el ámbito `eduperson`, que el token debe tener (`authn-bridge ssh-cert --scope eduperson`); si no, o cuando el IdP no entregó ese atributo, la respuesta es `403` indicando cuál |
| `ssh_extensions` | entre `permit-pty`, `permit-user-rc`, `permit-port-forwarding`, `permit-agent-forwarding`, `permit-X11-forwarding` |
| `ssh_source_address` | direcciones o prefijos CIDR, escritos en forma canónica en `source-address` |
| `ssh_validity` | nunca más larga que la `validity` de `ssh_ca` (igual se acepta), para este cliente |
| `ssh_domain_grants` | patrones de dominio, comprobados por `ValidatePattern` de [go-authn/sshcert]({{< relref "/sshcert/_index.md" >}}) y codificados por su `EncodeDomainGrant` |

### Lo que rechaza el perfil {#what-the-profile-refuses}

Cada uno al arrancar, según `authn-bridge check`:

```
authn-bridge: client "efp": ssh_validity = 24h0m0s: longer than the ssh_ca validity, 12h0m0s
authn-bridge: client "efp": ssh_extensions: "no-touch-required" is not one of permit-X11-forwarding, permit-agent-forwarding, permit-port-forwarding, permit-pty, permit-user-rc
authn-bridge: client "src": ssh_source_address: "192.0.2.1/24" has bits set under its mask: 192.0.2.0/24?
authn-bridge: client "x": ssh_principal_claim, ssh_extensions, ssh_source_address, ssh_validity and ssh_domain_grants shape SSH certificates: they need ssh_certificates = true
```

`no-touch-required` no se ofrece: dispensa de la prueba de presencia del usuario de
la llave de seguridad **propia** de la persona, y no le corresponde al proveedor
renunciar a ella para todas las personas de un cliente.

Una concesión de dominio se ajusta a la sintaxis de la especificación, y después a
la política propia de este proveedor: minúsculas, al menos dos etiquetas, y un
comodín solo por debajo de un dominio registrable. Lo que queda fijo a la derecha
del último comodín no debe ser un sufijo público (la Public Suffix List): `*.ac.uk`
concedería todas las instituciones que hay por debajo.

```
authn-bridge: client "efp": ssh_domain_grants: "*.ac.uk": a wildcard over the public suffix "ac.uk" grants every domain under it
authn-bridge: client "efp": ssh_domain_grants: "Login.hpc.example.org": written in lower case, as hosting entities' domains are compared
authn-bridge: client "efp": ssh_domain_grants: "login.hpc.*": sshcert: invalid domain pattern: pattern "login.hpc.*" has a wildcard in its rightmost label
```

### Confiar en ella desde un sitio {#trusting-it-from-a-site}

`GET /ssh/config` publica la clave de la CA con la misma forma con la que EFP publica
la suya, así que un sitio sigue las instrucciones de confianza de EFP con la URL de
este proveedor:

```
$ curl -s http://127.0.0.1:28473/ssh/config
{"PublicKey":"ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHFRUBlwxcGmmqW2lBI9bJyN4LL0/4U0NZwOOwBFPWw9"}
```

```sh
curl -s https://login.example.org/ssh/config | jq -r '.PublicKey' > /etc/ssh/bridge-ssh-ca.pub
echo "TrustedUserCAKeys /etc/ssh/bridge-ssh-ca.pub" >> /etc/ssh/sshd_config
```

sshd ignora la concesión de dominio. El sitio filtra según ella con un
`AuthorizedPrincipalsCommand`: [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}),
que rechaza un certificado cuya concesión no nombra el host, y uno sin ninguna
concesión. La CA no figura en el documento de descubrimiento de OpenID: ningún
metadato de OpenID Connect nombra una CA SSH.

Lo que sigue siendo distinto de la CA propia de EFP: con `ssh_principal_claim =
"voperson_id"`, como arriba, el principal es el `subject-id` que entregó la
institución de la persona, en minúsculas, no un identificador de MyAccessID; la
extensión de grupos está presente cuando el token lleva grupos; y **hay una KRL**,
`GET /ssh/krl`, que enumera los certificados de las personas desactivadas aquí.

## Certificados de cliente X.509, para NFS sobre TLS {#x509-client-certificates-for-nfs-over-tls}

NFS sobre TLS (RFC 9289) puede nombrar al cliente por su certificado.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"

x509_ca {
  key_file  = "/var/lib/authn-bridge/nfs-ca/ca.key"   # authn-bridge keygen --x509-ca /var/lib/authn-bridge/nfs-ca
  cert_file = "/var/lib/authn-bridge/nfs-ca/ca.crt"   # what go-fileshare trusts
  validity  = "12h"                                   # the default; a week at most
}

client "nfs" {
  device            = true
  x509_certificates = true
}
```

`authn-bridge nfs-cert --issuer ... --client nfs` genera una clave P-256 en la
máquina de la persona, envía una solicitud de certificado a `/x509/cert` con un
token del ámbito `nfs`, y escribe el certificado y la clave. La clave de la CA debe
ser P-256, y su certificado el de una CA que firma certificados y CRL.

**Lo que dice el certificado.** El sujeto y las extensiones de la solicitud se
ignoran: lo que se certifica es la persona del token, no lo que pidió.

- La persona, `user@domain`, como **un único** `otherName` de subjectAltName
  `1.3.6.1.4.1.2238.1.1.1` que contiene un UTF8String, donde lo lee
  `rpc.tlsservd -u` de FreeBSD. Un nombre de usuario sin `@`, o de menos de tres
  bytes, se rechaza.
- Cada grupo como un nombre URI a su lado:
  `tag:go-authn.github.io,2026:group:<the group, percent-encoded>`.
- El CN es el nombre de usuario; a partir de 64 caracteres el sujeto queda vacío y
  el subjectAltName es crítico (RFC 5280).
- Solo autenticación de cliente, y un punto de distribución de CRL:
  `<issuer>/x509/crl`.
- Válido desde hace cinco minutos hasta `validity`, la sesión del IdP o el propio
  certificado de la CA, lo que termine primero.
- Una clave P-256 o RSA (de 2048 bits o más), y una solicitud firmada con ella.

{{< callout type="warning" >}}
**Un certificado nombra la máquina, no a quien la usa**

RFC 9289: el servidor "cannot utilize the remote TLS peer identity to
authenticate RPC users". Linux establece el certificado de cliente por
montaje, así que todas las personas que usan ese montaje son la persona que
nombra. Esto es para una máquina que usa una sola persona, y
`authn-bridge nfs-cert` lo indica.
{{< /callout >}}

## Una solicitud de certificado mantenida abierta durante una desactivación {#a-certificate-request-held-open-across-a-disabling}

El token se comprueba cuando empieza la solicitud y el cuerpo se lee después, al
ritmo al que el cliente lo envíe. Así que primero se registra el certificado, y
después se vuelven a comprobar el token y la persona: si entretanto se desactivó a
la persona, o se revocó el token, el certificado recién registrado se revoca y la
respuesta es `401`. O la revocación vio el certificado, o el certificado ve la
revocación.
