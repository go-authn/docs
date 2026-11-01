---
title: "El lado de la federación"
linkTitle: "El lado de la federación"
weight: 30
description: "Cómo authn-bridge lee los metadatos de una federación SAML, fija su firmante, limita cada IdP a sus propios ámbitos y convierte una aserción en claims."
tags: [authn-bridge, saml, renater, edugain]
---

En este lado, authn-bridge es un proveedor de servicios SAML. Se registra una sola
vez en la federación (la Fédération Éducation-Recherche de RENATER, o eduGAIN), y
confía en los **metadatos** de la federación: un único documento firmado que
enumera cada IdP miembro, sus claves de firma y los dominios que cada uno puede
avalar. El código SAML es [go-authn/saml]({{< relref "/libraries/_index.md" >}}).

```hcl
saml {
  key_file  = "/var/lib/authn-bridge/saml.key"   # RSA: IdPs encrypt assertions to it
  cert_file = "/var/lib/authn-bridge/saml.crt"

  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"

  discovery = "https://discovery.renater.fr/renater"   # or leave it out for this provider's own list
  # idps    = ["https://idp.univ-example.example/idp/shibboleth"]   # restrict; one entry skips the choice

  names             = { fr = "Passerelle OIDC", en = "OIDC gateway" }
  technical_contact = "admin@example.org"
}
```

| clave | por defecto | |
|---|---|---|
| `entity_id` | el emisor + `/saml` | el nombre de este proveedor de servicios en la federación |
| `key_file`, `cert_file` | | la clave RSA y el certificado del SP |
| `metadata_url` | | `https://`, `file://` para una copia que mantiene otra cosa, o `http://` solo en loopback |
| `metadata_cert_file`, `metadata_fingerprint` | | el certificado de firma de la federación y su huella SHA-256, ambos obligatorios |
| `discovery` | la propia lista de este proveedor | un servicio de descubrimiento externo al que enviar a las personas |
| `idps` | todos los IdP de la federación | restringe el inicio de sesión a estos entity IDs |
| `names`, `descriptions`, `information_url`, `privacy_statement_url`, `technical_contact` | el host del emisor como nombre | lo que va en los metadatos del SP |

## Se fija el firmante de los metadatos {#the-metadatas-signer-is-pinned}

El certificado que firma los metadatos es un archivo en este host, y su huella
SHA-256 está escrita en la configuración. El certificado se comprueba contra la
huella **en cada arranque**, de modo que un archivo sustituido en el disco se
detecta en lugar de recibir confianza:

```
authn-bridge: saml: fed/fed.crt is not the certificate with fingerprint 68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0
```

Una clave que llega por el mismo canal que el documento que avala no avala nada.
Por eso la huella se toma de la página web de la federación, nunca de la descarga
que trajo el certificado:

```sh
openssl x509 -in /etc/authn-bridge/metadata-signature-2026.pem -noout -fingerprint -sha256
```

## Cuándo se rechaza un documento {#a-document-is-refused}

- cuando no está firmado por ese certificado, o está firmado con SHA-1, o su
  firma cubre un elemento distinto de la raíz;
- **cuando no tiene `validUntil`, o lo ha sobrepasado.** Estos son los propios
  metadatos de RENATER tal como se publicaron el 29 de septiembre de 2026,
  leídos el 10 de octubre:

  ```
  $ authn-bridge check --config v/renater-expired.hcl
  authn-bridge: the federation's metadata: metadata expired at 2026-10-08T07:30:02Z
  ```

  *No se volvió a ejecutar: esos metadatos ya no se publican; esta es la salida capturada el 10 de octubre de 2026.*

- cuando su `validUntil` está a más de 28 días: un documento válido durante años
  es uno que una repetición mantiene vivo durante años;
- **cuando es más antiguo que el que está en uso** (un `validUntil` anterior).
  Está válidamente firmado y aún no ha caducado, así que nada más lo rechazaría,
  y puede ser el que lleva una clave revocada desde entonces, servido por quien
  se interponga en el camino;
- por `http` sin cifrar hacia cualquier cosa que no sea loopback. La firma
  detectaría un cambio, pero no un proxy que retiene el documento nuevo y sigue
  sirviendo el antiguo.

## Su actualización {#refreshing-it}

Los metadatos se descargan antes de que el proveedor escuche, y de nuevo según el
calendario de `Federation.Run` de go-authn/saml (desde la v0.23.6): nunca programado
más allá de la mitad de lo que queda del `validUntil` del documento, y entre cinco
minutos y doce horas (si no, tres cuartos de su `cacheDuration`), y siempre que lo
pida `RefreshMetadata` de la API de administración. Cuando no queda ningún metadato
válido, la descarga se reintenta al cabo de un minuto, y luego al doble de intervalo
hasta una hora. Hasta la v0.23.5 el bucle seguía esperando tres cuartos del
`cacheDuration` (doce horas sin uno) fuera cual fuese lo que quedaba de la vigencia:
una actualización fallida cerca del final podía dejar al proveedor sin IdP hasta doce
horas después de que el servidor de la federación volviera.
Una actualización que falla conserva la última copia buena,
**pero solo hasta su propio `validUntil`**: hasta entonces los inicios de sesión
continúan con ella, tanto si el servidor de la federación está lento, caído o sirve un
documento que no se verifica. A partir de ahí no se avala nada,
todos los IdP desaparecen, y `/readyz` indica que el proveedor no está listo. Un
servidor de la federación inalcanzable durante poco tiempo no cierra la sesión de
nadie; uno inalcanzable durante días no deja al proveedor confiando en claves
obsoletas.

El reloj del puente puede diferir del de un IdP en tres minutos en cualquier sentido: una
aserción cuyas horas caen dentro de ese margen se acepta, y una desfasada una hora se
rechaza con una página 400. La clave bajo la que se recuerda una aserción, para que no se
acepte dos veces, se guarda como su SHA-256 (desde la v0.23.6): un `entityID` de IdP o un
identificador de aserción largos superaban la columna `VARCHAR(128)` de la base de datos
de estado, que PostgreSQL y MySQL en modo estricto rechazan, de modo que la escritura
quedaba pendiente y el proveedor seguía sin estar listo. SQLite no se veía afectado.
Ninguna configuración cambia.

Dentro del documento, un IdP solo se conserva si habla SAML 2.0 y publica un
`SingleSignOnService` HTTP-Redirect. Una entidad descrita dos veces se descarta
por completo, ya que nada dice qué descripción es la correcta, y el certificado
ilegible de un miembro deja fuera a ese miembro, no a la federación.

## Lo que puede decir cada IdP {#what-each-idp-may-say}

Una federación tiene cientos de miembros, y cualquiera de ellos podría, si no,
decir que es `alice@another-university.example`. Los metadatos de cada miembro
enumeran sus `shibmd:Scope`, los dominios que puede avalar; un ámbito con
expresión regular se ignora, no se respeta.

**Identificadores.** Un valor con ámbito (`subject-id`, `pairwise-id`,
`eduPersonPrincipalName`, `eduPersonScopedAffiliation`) fuera de los ámbitos del
IdP que lo afirma se **descarta**, y un valor con más de una `@` no está en
ningún ámbito.

**Grupos.** Cuando más de un IdP puede iniciar sesión, un valor
`eduPersonEntitlement` o `isMemberOf` solo se conserva si su espacio de nombres es
uno de los ámbitos de ese IdP o está bajo uno de ellos:

| valor | su espacio de nombres |
|---|---|
| `urn:mace:<domain>:...` | `<domain>` |
| `urn:geant:<domain>:...` (AARC-G002) | `<domain>` |
| `https://<host>/...` | `<host>` |
| cualquier otra cosa | ninguno: se descarta |

Los grupos deciden lo que una persona puede hacer, en cada servidor de recursos y
en cada certificado, así que un valor que nadie puede situar no se transmite. Un
proxy comunitario que afirma grupos para personas de muchas instituciones se
nombra explícitamente, por entity ID, con los prefijos que puede afirmar:

```hcl
claims {
  trusted_groups = {
    "https://proxy.eduteams.org/saml2/idp/metadata.php" = ["urn:geant:eduteams.org:"]
  }
}
```

Con exactamente un IdP en `saml { idps }`, ese IdP es de confianza para cualquier
valor.

## De una aserción a los claims {#from-an-assertion-to-claims}

```hcl
claims {
  username = "eppn"            # preferred_username: eppn, subject_id, uid or mail
  groups   = ["entitlement"]   # groups: entitlement, scoped_affiliation, affiliation, is_member_of
}
```

`uid` y `mail` no están sujetos a ningún ámbito, y `affiliation` (`staff`,
`student`) no nombra ninguna institución. Por eso cada uno exige que
`saml { idps }` enumere exactamente un IdP; con más, [se rechazan al arrancar]({{< relref "/authn-bridge/configuration.md#what-is-refused-at-startup" >}}).

**`sub`.** El identificador en que se basa se toma en este orden: `subject-id`,
después `pairwise-id`, después `eduPersonPrincipalName`, después
`eduPersonTargetedID`, después un NameID persistente cuyo calificador es el propio
IdP. Se califica con el entity ID del IdP, y `sub` es un HMAC-SHA256 de él bajo la
sal de sujeto: estable, no reversible, no una dirección. `public` es igual para
todos los clientes, `pairwise` difiere por cliente. Un IdP que no entrega ninguno
de ellos se rechaza, ya que nadie podría ser reconocido dos veces. **El correo
nunca es un identificador**, y no hay `email_verified`: que un IdP afirme una
dirección no significa que alguien haya verificado que la persona la lee.

**Lo que la petición pide al IdP.** `prompt=none` se convierte en `IsPassive`, y
un IdP sin sesión responde `login_required`. `prompt=login` y `max_age=0` se
convierten en `ForceAuthn`; para cualquier otro `max_age`, a una persona a la que
su IdP autenticó hace más tiempo que ese se la devuelve con `ForceAuthn`.
`acr_values` se convierte en `RequestedAuthnContext`, y un IdP que responde con
otro contexto se rechaza: a un cliente que pidió un segundo factor nunca se le
dice que lo obtuvo cuando no es así.

## Los metadatos del SP {#the-sp-metadata}

`authn-bridge metadata` imprime lo que hay que registrar en la federación, sin
descargar nada (aquí el certificado está abreviado):

```
$ authn-bridge metadata --config etc/bridge.hcl
<?xml version="1.0" encoding="UTF-8"?>
<md:EntityDescriptor xmlns:md="urn:oasis:names:tc:SAML:2.0:metadata" xmlns:ds="http://www.w3.org/2000/09/xmldsig#" xmlns:mdui="urn:oasis:names:tc:SAML:metadata:ui" xmlns:idpdisc="urn:oasis:names:tc:SAML:profiles:SSO:idp-discovery-protocol" xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion" entityID="http://127.0.0.1:28473/saml">
  <md:SPSSODescriptor protocolSupportEnumeration="urn:oasis:names:tc:SAML:2.0:protocol" AuthnRequestsSigned="false" WantAssertionsSigned="true">
    <md:Extensions>
      <mdui:UIInfo>
        <mdui:DisplayName xml:lang="en">127.0.0.1:28473</mdui:DisplayName>
      </mdui:UIInfo>
    </md:Extensions>
    <md:KeyDescriptor>
      <ds:KeyInfo>
        <ds:X509Data>
          <ds:X509Certificate>MIID…</ds:X509Certificate>
        </ds:X509Data>
      </ds:KeyInfo>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#aes128-gcm"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#aes256-gcm"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2009/xmlenc11#rsa-oaep"/>
      <md:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#rsa-oaep-mgf1p"/>
    </md:KeyDescriptor>
    <md:AssertionConsumerService Binding="urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" Location="http://127.0.0.1:28473/saml/acs" index="0" isDefault="true"/>
    <md:AttributeConsumingService index="0">
      <md:ServiceName xml:lang="en">127.0.0.1:28473</md:ServiceName>
      <md:RequestedAttribute Name="urn:oasis:names:tc:SAML:attribute:subject-id" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.6" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:0.9.2342.19200300.100.1.3" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.16.840.1.113730.3.1.241" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.5.4.42" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:2.5.4.4" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
      <md:RequestedAttribute Name="urn:oid:1.3.6.1.4.1.5923.1.1.1.7" NameFormat="urn:oasis:names:tc:SAML:2.0:attrname-format:uri"/>
    </md:AttributeConsumingService>
  </md:SPSSODescriptor>
</md:EntityDescriptor>
```

Las aserciones deben estar firmadas (`WantAssertionsSigned="true"`), y se
entregan a `/saml/acs` por HTTP-POST. El mismo documento se sirve en
`/saml/metadata`.

## Lo que se rechaza {#what-is-refused}

En el ACS, todo lo que rechaza go-authn/saml: una aserción sin firmar o con SHA-1,
varias aserciones, una repetida, un identificador en un ámbito ajeno. Después, los
rechazos propios de este proveedor:

- una respuesta del IdP entregada **en otro navegador**: el inicio de sesión se
  encuentra mediante su propia cookie sellada, nunca mediante el `RelayState` que
  lleva la respuesta; si no, cualquiera podría enviar su propia respuesta del IdP al
  navegador de otra persona y hacer que esta iniciara sesión con la identidad de
  quien la envía;
- un IdP que la configuración ya no permite, o que la API de administración ha
  desactivado;
- una persona o una institución [desactivada aquí]({{< relref "/authn-bridge/admin.md" >}}),
  diga lo que diga la institución.

Al arrancar, una lista de IdP junto con el servicio de descubrimiento de RENATER,
que los enumera todos y no se puede restringir:

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
```

### Lo que se prueba {#tested}

Desde la v0.23.6 la sección «What it refuses» del README enumera lo que se prueba, de
extremo a extremo a través del ACS: el envoltorio de firma XML (XSW1 a XSW8 y sus
variantes con el mismo ID), el truncamiento por comentario (CVE-2017-11427), DOCTYPE y la
expansión de entidades, aserciones para otra audiencia, otro destinatario, otra petición
u otro destino, y la repetición. Hay fuzzers para el ACS (`FuzzACSAccept`), los metadatos
de la federación, la verificación de tokens de acceso (con semillas de confusión de
`alg`), la cookie de inicio de sesión y la coincidencia de URI de redirección:
`FuzzACSAccept` hizo 992 517 ejecuciones en tres minutos con 595 entradas de corpus y
ningún fallo, y los otros cuatro unos 90 segundos cada uno, sin fallos. Las pruebas de
caos desplazan el reloj del puente dos minutos (aceptado) y una hora (rechazado), y hacen
que el servidor de metadatos sea lento, esté caído, responda 500, basura, HTML, un
documento truncado o manipulado, o nada. El limitador de tasa ya no trata un reloj que
retrocede como tiempo negativo (vaciaba cada cubo en el tamaño del salto; los relojes de
producción no retroceden, así que es defensa en profundidad).
