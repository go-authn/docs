---
title: "Lo que revoca, y cómo se enteran los servidores"
linkTitle: "Revocación"
weight: 60
description: "La KRL y la CRL firmadas y fechadas que authn-bridge publica para los certificados que ha revocado, y el transmisor de Shared Signals que llega a lo que ninguna lista puede nombrar."
tags: [authn-bridge, revocación, krl, crl, señales compartidas]
---

Desactivar a una persona o una institución ([la API de administración]({{< relref "/authn-bridge/admin.md" >}}))
pone fin a todo lo que vuelve al proveedor: los tokens de actualización,
`/userinfo`, los certificados nuevos, las contraseñas de aplicación. Lo que ya ha
entregado se comprueba en otro lugar, contra claves, y tres mecanismos llegan a
ello:

| credencial | se retira mediante |
|---|---|
| un certificado SSH firmado por esta CA | la **KRL**, `GET /ssh/krl`, con su firma en `/ssh/krl.sig` |
| un certificado de cliente X.509 | la **CRL**, `GET /x509/crl` |
| un token de acceso, un certificado de opkssh, cualquier cosa que un servidor verifica por sí solo | un evento **Shared Signals** `session-revoked` |

La revocación es permanente. Volver a activar a una persona no le devuelve sus
certificados; recibe otros nuevos. Una lista de la que se pudiera retirar una
revocación sería una lista que podría editar cualquiera que alcance la API de
administración.

## Las listas {#the-lists}

Ambas se emiten como indica el protocolo de go-authn/revocation, de modo que
puedan viajar por cualquier medio (un espejo, HTTP sin cifrar, un archivo) y
seguir pudiendo comprobarlas quien las lea:

| | KRL | CRL |
|---|---|---|
| formato | `PROTOCOL.krl` de OpenSSH, escrito por go-authn/krl: lo que leen `RevokedKeys` de `sshd` y `ssh-keygen -Q` | DER, RFC 5280 |
| firmada | una SSHSIG separada con la clave de la CA SSH, espacio de nombres `krl@go-authn.github.io` | por la CA que firma los certificados |
| vigente hasta | su extensión `expires@go-authn.github.io` (que sshd ignora) | su `nextUpdate` |
| ordenada por | su `krl_version`, y luego su fecha de generación | su CRL Number, y luego `thisUpdate` |

Cada lista indica que deja de estar vigente **una hora** después de emitirse. Una
lista se conserva y se sirve sin cambios hasta que ha recorrido la mitad de ese
plazo, o hasta que se revoca algo; la petición siguiente obtiene entonces una
nueva emisión. Una emisión nunca lleva una fecha anterior a la que sustituye,
aunque el reloj retroceda, ya que un lector rechaza como reversión una emisión
anterior de la misma versión. El CRL Number aumenta en cada emisión.

La KRL de un proveedor de prueba sin nada revocado:

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "db5b4e920d2da3911da51a8f70db8c4f"
Date: Sun, 11 Oct 2026 09:48:14 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261011T114814
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**El ETag es el del contenido.** Un lector sondea con `If-None-Match`, y obtiene
`304` mientras la emisión que tiene siga siendo la que se sirve; como el contenido
cambia al menos cada media hora, un lector que sondea nunca conserva una copia más
allá de su caducidad:

```
$ curl -s -o /dev/null -H 'If-None-Match: "db5b4e920d2da3911da51a8f70db8c4f"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**La firma se descarga con `If-Match`** sobre el ETag de la lista. Si la lista se
ha vuelto a emitir entretanto, la respuesta es `412`, en lugar de una firma que no
le corresponde:

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "db5b4e920d2da3911da51a8f70db8c4f"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen` comprueba la firma, y la rechaza en cualquier otro espacio de
nombres:

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
```

donde `allowed` es la línea
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>`.

La CRL, emitida quince segundos después:

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 11 09:48:29 2026 GMT
    Next Update: Oct 11 10:48:29 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            2A:90:7A:50:FF:65:52:BA:70:4E:E1:F8:70:EE:7A:FC:B1:8B:FE:4E
        X509v3 CRL Number: 
            1791712109993
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:37:90:14:6f:c1:f2:ea:98:29:04:61:88:a8:17:
        88:e3:f6:84:9d:46:a7:fc:2b:ac:81:26:47:9d:ac:84:23:38:
        02:20:0a:a6:93:cb:7d:2d:81:e4:59:d4:0d:a0:fd:f4:6e:75:
        c9:0d:53:e7:92:49:ac:a1:31:a8:90:09:91:d1:87:b6
```

Un certificado permanece en su lista hasta que caduca: un certificado caducado se
rechaza en todas partes sin necesidad de figurar en la lista.

### Quién las lee {#who-reads-them}

- Un `sshd` normal, o nginx y otros servidores TLS:
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) descarga las listas,
  conserva solo las que se verifican, las escribe donde las leen los servidores, y
  falla en modo cerrado para sshd cuando una lista caduca.
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
  las descarga y las verifica por sí mismo, y rechaza los certificados del
  proveedor mientras no tenga ninguna lista vigente.

## Shared Signals {#shared-signals}

Un token de acceso o un certificado de opkssh se comprueba donde se usa, y ninguna
lista puede nombrarlo. Por eso el proveedor es un transmisor de OpenID Shared
Signals: con `DisablePerson`, `RevokePerson` y `DisableIdP` pone en cola un evento
CAEP **`session-revoked`** (todo lo emitido a este sujeto antes de la hora del
evento queda anulado) para cada receptor que lo haya solicitado.

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **Solo entrega por sondeo** (RFC 8936): el receptor pregunta; desde aquí no se
  establece ninguna conexión saliente.
- Un receptor se autentica con un token de acceso obtenido mediante la concesión
  **client credentials**, para un cliente `ssf_receiver` con un secreto, scope
  `ssf`. Solo ve sus propios flujos, diez como máximo.
- Los eventos son SET (RFC 8417) firmados con la clave de los tokens de ID, sin
  `exp` ni `sub`. El sujeto es, por defecto, la **cuenta**, `acct:<username>`: un
  `sub` puede ser pairwise, uno por cliente. Un receptor configurado con
  `ssf_subject_format = "iss_sub"` recibe en su lugar el emisor y el `sub`
  público.
- La desactivación de una institución es un evento por cada persona de la que el
  proveedor tiene rastro allí, y uno cuyo sujeto es el **tenant**, el entity ID de
  la institución, con sus ámbitos, que cubre a las personas que el proveedor ha
  olvidado.
- Los flujos y los eventos no entregados se conservan en la base de datos `state`
  hasta que se confirman o pasa `event_retention`. Un evento que un receptor
  notifica como erróneo se vuelve a entregar, hasta diez veces.

El bloque SSF se rechaza sin un bloque `state`:

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
