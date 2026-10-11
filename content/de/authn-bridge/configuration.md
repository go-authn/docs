---
title: "Die Konfiguration"
linkTitle: "Konfiguration"
weight: 20
description: "Wie die HCL-Konfiguration von authn-bridge aufgebaut ist, was check ausgibt und was abgelehnt wird, bevor sich jemand anmelden kann."
tags: [authn-bridge, konfiguration]
---

Eine HCL-Datei oder ein Verzeichnis davon: `--config /etc/authn-bridge` liest jede
`*.hcl` darin in Namensreihenfolge und führt sie zusammen, und `--config` darf mehr
als einmal angegeben werden. Die Konfiguration wird beim Start gelesen und danach nie wieder.

```hcl
issuer            = "https://login.example.org"       # https; compared whole by every relying party
listen            = "127.0.0.1:8080"                  # the default: plain HTTP behind a TLS proxy
signing_key_file  = "/var/lib/authn-bridge/oidc.key"  # authn-bridge keygen --key
subject_salt_file = "/var/lib/authn-bridge/salt"      # authn-bridge keygen --salt; never change it
disabled_file     = "/var/lib/authn-bridge/disabled.json"
certificates_file = "/var/lib/authn-bridge/certificates.json"

saml {
  key_file             = "/var/lib/authn-bridge/saml.key"
  cert_file            = "/var/lib/authn-bridge/saml.crt"
  metadata_url         = "https://pub.federation.renater.fr/metadata/fer/idps.xml"
  metadata_cert_file   = "/etc/authn-bridge/metadata-signature-2026.pem"
  metadata_fingerprint = "68:2F:20:58:41:9E:D0:79:EB:FE:3C:27:D6:A4:A4:09:39:6F:AE:3F:10:5F:22:EA:04:0F:04:F3:78:2D:5C:C0"
}

state {
  driver   = "sqlite"                                 # or postgres, mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}

client "my-app" {
  secret_file   = "/etc/authn-bridge/my-app.secret"   # absent: a public client
  redirect_uris = ["https://app.example.org/callback"]
}
```

Erforderlich sind `issuer`, `signing_key_file`, `subject_salt_file`, ein `saml`-Block
mit den fünf Schlüsseln oben und mindestens ein `client`. Alles andere hat einen
Standardwert oder ist aus.

## `check`, vor einem Neustart {#check-before-a-restart}

`check` liest die Konfiguration so, wie der Server es tut, lädt jeden Schlüssel, den sie
nennt, **holt die Metadaten der Föderation** und sagt, was bedient würde:

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-17T19:16:33Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*Usable here* lässt einen IdP aus, den `saml { idps }` nicht aufführt, und einen, den die
[Admin-API]({{< relref "/authn-bridge/admin.md" >}}) deaktiviert hat: Ist die
Einrichtung oben deaktiviert, gibt derselbe Befehl
`federation    1 IdPs, 0 usable here` aus. Ein `idps`-Eintrag, den die Föderation
nicht aufführt, wird hier abgelehnt, obwohl der Server damit starten würde:

```
federation    1 IdPs, 0 usable here, valid until 2026-10-17T19:16:33Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata` gibt die SAML-Metadaten aus, die bei der
Föderation zu registrieren sind. Siehe [die Seite der Föderation]({{< relref "/authn-bridge/federation.md" >}}).

## Die oberste Ebene {#the-top-level}

| Schlüssel | Standard | |
|---|---|---|
| `issuer` | | der Name des Anbieters und die Basis jeder URL. `https`, oder `http` auf einem Loopback-Host zum Testen; keine Query, kein Fragment; ein abschließendes `/` wird entfernt |
| `listen` | `127.0.0.1:8080` | der öffentliche Listener |
| `cert_file`, `key_file` | | TLS aus diesen Dateien bedienen, neu gelesen, wenn sie sich ändern; beide zusammen oder keine |
| `acme` | | TLS stattdessen mit einem Zertifikat einer ACME-CA bedienen (unten); nicht zusammen mit `cert_file` |
| `signing_key_file` | | RSA, signiert ID-Tokens (RS256); ein P-256-Schlüssel hier wird abgelehnt |
| `access_token_key_file` | der Signaturschlüssel | ein P-256-Schlüssel, der Access-Tokens mit ES256 signiert; abgelehnt, wenn er der Signaturschlüssel ist |
| `retired_signing_key_files` | | Schlüssel, die früher signiert haben: weiterhin unter `/jwks` veröffentlicht, nie zum Signieren verwendet |
| `subject_salt_file` | | mindestens 32 Bytes |
| `code_lifetime` | `1m` | höchstens zehn Minuten (RFC 6749 4.1.2) |
| `token_lifetime` | `1h` | Access-Tokens |
| `id_token_lifetime` | `5m` | ID-Tokens |
| `trusted_proxies` | | Adressen oder Präfixe, deren `X-Forwarded-For` geglaubt wird |
| `requests_per_minute` | `120` | Anmeldungen, Device Grants und ACS-POSTs, die eine Adresse pro Minute beginnen darf; `0` schaltet die Grenze ab |
| `disabled_file` | | wo deaktivierte Personen und Einrichtungen festgehalten werden; ohne sie wird das Deaktivieren abgelehnt |
| `certificates_file` | | jedes ausgestellte Zertifikat und jeder WireGuard-Schlüssel; erforderlich mit `ssh_ca`, `x509_ca` oder `wireguard` |

Die Blöcke:

| Block | Seite |
|---|---|
| `saml`, `claims` | [die Seite der Föderation]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | unten, und [Tokens]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | unten |
| `ssh_ca`, `x509_ca` | [Zertifikate]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`, `wireguard` | [Tokens]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [Widerruf]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`, `metrics` | [die Admin-API]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | unten |

## Ein Client {#a-client}

| Schlüssel | Standard | |
|---|---|---|
| `secret_file` | | das Client-Geheimnis, mindestens 16 Zeichen; fehlt es, ein **öffentlicher** Client |
| `redirect_uris` | | exakt verglichen, außer dass eine Loopback-URI den Port wechseln darf (RFC 8252); `http` nur auf Loopback |
| `audience` | die Client-ID | an wen seine Access-Tokens adressiert sind |
| `subject` | `public` | oder `pairwise`: ein anderes `sub` für diesen Client (OIDC Core 8.1) |
| `name` | die Client-ID | auf der Bestätigungsseite für Geräte angezeigt |
| `device` | `false` | der Device Grant (RFC 8628); ein solcher Client braucht keine Redirect-URI |
| `refresh_lifetime` | aus | Refresh-Tokens, und wie lange nach der **Anmeldung** sie enden |
| `pkce` | `required` | oder `or_nonce`, nur für einen vertraulichen Client: eine `nonce` statt PKCE |
| `id_token_claims` | `false` | die freigegebenen Claims auch ins ID-Token kopieren (opkssh braucht das) |
| `ssh_certificates`, `ssh_*` | | [SSH-Zertifikate]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [NFS-Client-Zertifikate]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | darf das [Anwendungspasswort]({{< relref "/authn-bridge/tokens.md#application-passwords" >}}) der Person setzen |
| `wireguard_keys`, `wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`, `ssf_subject_format` | | ein [Shared-Signals-Empfänger]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

Ein Client ohne Redirect-URI muss ein Device-Client, ein SSF-Empfänger oder ein
WireGuard-Gateway sein, sonst gäbe es nichts, was er tun könnte.

## `state`: was ein Neustart nicht vergessen darf {#state-what-a-restart-must-not-forget}

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

Refresh-Token-Familien, die Refresh-Tokens und die ausgemusterten, die Access-Tokens,
die an `/userinfo` und für Zertifikate akzeptiert werden, die bereits angenommenen SAML-Assertions
und die bereits beantworteten Anmeldungen, die SSF-Streams und ihre nicht zugestellten
Ereignisse: in eine Tabelle durchgeschrieben, `bridge_state` (angelegt, falls sie fehlt), und
beim Start gelesen. Ein Refresh-Token wird als sein SHA-256 aufbewahrt, nie als es selbst.
Ohne den Block leben sie im Speicher, und ein Neustart meldet alle ab.

Eine laufende Anmeldung ist nicht darin. Sie reist in ihrem eigenen Cookie, versiegelt mit
AES-256-GCM unter einem aus dem Subject-Salt abgeleiteten Schlüssel, sodass der Browser sie
weder lesen noch ändern kann.

## `acme` {#acme}

```hcl
acme {
  accept_terms_of_service = true                     # the operator's agreement; no default
  cache_dir               = "/var/lib/authn-bridge/acme"
  email                   = "noc@example.org"
  # directory_url         = "..."                    # Let's Encrypt by default
  # eab_key_id            = "..."                    # External Account Binding (GÉANT TCS / HARICA)
  # eab_hmac_key_file     = "/etc/authn-bridge/harica-eab.key"
  # http_listen           = ":80"                    # http-01, and a redirect to https
  # directory_ca_file     = "..."                    # a private ACME CA's own TLS
}
```

Das Zertifikat gilt für den Host des Ausstellers. `cache_dir` enthält private Schlüssel, und
der Anbieter verweigert den Start auf einem Verzeichnis, das ein anderer Benutzer erreichen oder umlenken könnte.

## Was beim Start abgelehnt wird {#what-is-refused-at-startup}

Jedes davon ist die Ausgabe von `authn-bridge check` für eine Konfiguration, die
danach verlangt hat. Der Server lehnt dieselben Konfigurationen ab: Jede ergibt sich aus der
Konfiguration und den Dateien, die sie nennt. Die einzige Ablehnung, die `check` hinzufügt, ist
der `idps`-Eintrag, den die Föderation nicht aufführt, [weiter oben](#check-before-a-restart):
Der Server ruft dieselben Metadaten ab, bevor er lauscht, gleicht `idps` aber nicht
mit ihnen ab.

**Ein Aussteller, eine Umleitung, ein Geheimnis, die etwas preisgeben:**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**Ein Name, den jede Einrichtung beanspruchen könnte:**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**Etwas Ausgestelltes, das sich nie zurücknehmen ließe:**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: more than a week, and a certificate lives that long on every server its revocation has not reached
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**Ein Listener, der nicht erreichbar sein sollte:**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**Eine Konfiguration, die eine Sache zweimal sagt:**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

Die eigenen Ablehnungen des SSH-Profils stehen unter [Zertifikate]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}}),
die der Föderation unter [die Seite der Föderation]({{< relref "/authn-bridge/federation.md#what-is-refused" >}}).
