---
title: "Tokens, Passwörter und Schlüssel"
linkTitle: "Tokens"
weight: 40
description: "Was eine Anwendung von authn-bridge erhält: ID-Tokens und Access-Tokens, den Device Grant, Anwendungspasswörter für SMB und S3 sowie WireGuard-Schlüssel."
tags: [authn-bridge, oidc, token, wireguard]
---

Alle Zugangsdaten hier beginnen mit derselben Anmeldung bei der Einrichtung der Person.
Was sich unterscheidet, ist, für wen die Zugangsdaten bestimmt sind und wie sie zurückgenommen werden. Die
Zertifikate stehen auf [einer eigenen Seite]({{< relref "/authn-bridge/certificates.md" >}}).

## Was der Anbieter veröffentlicht {#what-the-provider-publishes}

```
$ curl -s http://127.0.0.1:28473/.well-known/openid-configuration | jq .
{
  "authorization_endpoint": "http://127.0.0.1:28473/authorize",
  "authorization_response_iss_parameter_supported": true,
  "claims_parameter_supported": false,
  "claims_supported": [
    "sub",
    "iss",
    "aud",
    "exp",
    "iat",
    "auth_time",
    "nonce",
    "acr",
    "name",
    "given_name",
    "family_name",
    "preferred_username",
    "email",
    "groups",
    "eduperson_principal_name",
    "eduperson_scoped_affiliation",
    "eduperson_entitlement",
    "entitlements",
    "eduperson_assurance",
    "eduperson_orcid",
    "schac_home_organization",
    "voperson_id"
  ],
  "code_challenge_methods_supported": [
    "S256"
  ],
  "device_authorization_endpoint": "http://127.0.0.1:28473/device_authorization",
  "grant_types_supported": [
    "authorization_code",
    "refresh_token",
    "urn:ietf:params:oauth:grant-type:device_code"
  ],
  "id_token_signing_alg_values_supported": [
    "RS256"
  ],
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "request_parameter_supported": false,
  "request_uri_parameter_supported": false,
  "response_modes_supported": [
    "query"
  ],
  "response_types_supported": [
    "code"
  ],
  "scopes_supported": [
    "openid",
    "profile",
    "email",
    "eduperson",
    "groups"
  ],
  "subject_types_supported": [
    "public",
    "pairwise"
  ],
  "token_endpoint": "http://127.0.0.1:28473/token",
  "token_endpoint_auth_methods_supported": [
    "client_secret_basic",
    "client_secret_post",
    "none"
  ],
  "userinfo_endpoint": "http://127.0.0.1:28473/userinfo"
}
```

Der Authorization-Code-Flow, mit **PKCE S256, verpflichtend für jeden Client**. Eine
Anfrage ohne `code_challenge_method` wird abgelehnt, statt als S256 gelesen zu werden,
da RFC 7636 `plain` zum Standard macht. Ein vertraulicher Client, der mit
`pkce = "or_nonce"` konfiguriert ist, darf stattdessen eine OpenID-`nonce` senden.

## Das ID-Token {#the-id-token}

Für den Client, und über die Anmeldung, nicht über die Person: RS256, `aud` die Client-ID,
`sub`, `auth_time`, `at_hash`, die `nonce`, wenn die Anfrage eine hatte, und
`acr`, wenn der IdP angegeben hat, welchen Authentifizierungskontext er verwendet hat. Lebensdauer
`id_token_lifetime`, standardmäßig fünf Minuten.

**Nichts über die Person steht darin.** Die Claims, die die Scopes freigeben, stehen unter
`/userinfo`, wie OIDC Core 5.4 es vorsieht, wenn ein Access-Token ausgestellt wird, und eines
wird immer ausgestellt. Ein Client, dessen ID-Token selbst die Zugangsdaten sind, etwa opkssh,
setzt `id_token_claims = true`, um sie hineinkopieren zu lassen. Ein ID-Token wird nur
für eine Anfrage mit dem Scope `openid` ausgestellt.

| Scope | gibt frei |
|---|---|
| `profile` | `name`, `given_name`, `family_name`, `preferred_username` |
| `email` | `email` (nie `email_verified`) |
| `eduperson` | `eduperson_principal_name`, `eduperson_scoped_affiliation`, `eduperson_entitlement` und `entitlements`, `eduperson_assurance`, `eduperson_orcid`, `schac_home_organization`, `voperson_id` (die SAML-`subject-id`, in Kleinbuchstaben) |
| `groups` | `groups` |

## Das Access-Token {#the-access-token}

Für die Ressourcenserver in der `audience` des Clients, wie RFC 9068 es beschreibt:
signiert mit `signing_key_file` (RS256) oder `access_token_key_file` (ES256),
`typ: at+jwt`, gültig für `token_lifetime` (standardmäßig eine Stunde). Es trägt, was ein
Ressourcenserver braucht, um zu entscheiden, ohne jemanden zu fragen: `preferred_username`,
`groups`, `idp` (die Entity-ID des IdP, der gebürgt hat), `scope`, `client_id`
und `session_end`, wenn der IdP angegeben hat, wann seine Sitzung endet.
Die Gruppen lassen sich pro Client weglassen: [weiter unten](#what-it-leaves-out).

Ein Client, dessen `audience` mehrere Ressourcenserver nennt, kann mit `resource`
aus RFC 8707 ein Token anfordern, das an einen von ihnen adressiert ist: siehe
[mehrere Ressourcenserver]({{< relref "/authn-bridge/resources.md" >}}).

### Was es weglässt, und warum {#what-it-leaves-out}

**Kein `auth_time` und kein `acr`**, obwohl RFC 9068 beides erlaubt. Beide
bleiben im ID-Token, wo OIDC Core sie vorsieht. Nichts liest sie aus einem
Access-Token: weder dieser Anbieter, der ein Token über seine `jti` nachschlägt,
noch go-fileshare. Ein Access-Token wird aber auch als SSH-Antwort im
keyboard-interactive-Verfahren eingefügt (mccli von ssh-oidc, von motley-cue an
`/userinfo` geprüft), und OpenSSH liest davon 1023 Zeichen; allein das `acr`
eines IdP, `urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport`,
belegt etwa 90 davon. Vor v0.22.0 trug das Access-Token beide.

Die Länge eines ES256-Access-Tokens (`access_token_key_file`) für einen langen
eppn und drei AARC-Entitlements, gemessen von `TestES256AccessTokens` in
authn-bridge mit einem Aussteller realer Länge, gegen die Längen der
`shibmd:Scope`-Einträge in den Metadaten von RENATER (743 Scopes):

| Scope-Länge | | Zeichen |
|---|---|---|
| 13 | Median | 885 |
| 22 | 95. Perzentil | 945 |
| 29 | 99. Perzentil | 992 |
| 44 | der längste | **1092: zu lang** |

Vor v0.22.0 war dasselbe Token 1014 / 1074 / 1121 / 1221 Zeichen lang: zu lang
ab dem 95. Perzentil. Was weiterhin nicht passt, sind die längsten Scopes und
vor allem viele Gruppen: Jedes Entitlement fügt seine ganze URN hinzu, und
nichts begrenzt, wie viele ein IdP schickt. Ein RS256-Access-Token, signiert mit
einem 3072-Bit-Schlüssel, ist schon vor jeder Gruppe etwa 1150 Zeichen lang;
ein Token für SSH wird daher mit ES256 signiert. Ab 1023 Zeichen fragt mccli
motley-cue stattdessen nach einem Einmalpasswort, was motley-cue standardmäßig
erlaubt; ein Token, das in ein gewöhnliches `ssh` eingefügt wird, muss passen.

**Keine Gruppen, für einen Client, der das verlangt** (v0.23.0). Jede Gruppe
fügt ihre ganze URN hinzu, und nichts begrenzt, wie viele ein IdP schickt; kein
Schlüssel und kein Signaturverfahren sorgt also sicher dafür, dass ein Token mit
Gruppen passt. Ein Client mit `access_token_groups = false` erhält
Access-Tokens ohne die `groups` der Person:

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
}
```

Gedacht ist das für ssh-oidc: oidc-agent holt das Token, mccli fügt es als
keyboard-interactive-Antwort ein, und motley-cue prüft es an `/userinfo` und
liest dort die Gruppen. Gemessen von `TestAccessTokenWithoutGroups` in
authn-bridge ist ein ES256-Token für jemanden in 50 Gruppen, mit dem längsten
RENATER-Scope (44) und einem Aussteller realer Länge, 732 Zeichen lang.

Gegen eine Testföderation meldet sich eine Person in drei Gruppen über diesen
Client an, mit dem Device Grant:

```
$ authn-bridge token --issuer http://127.0.0.1:28473 --client oidc-agent --scope "openid eduperson groups" --cache var/tokens.json > at
To log in, open http://127.0.0.1:28473/device
and enter the code DHBT-DBZD
(or open http://127.0.0.1:28473/device?user_code=DHBT-DBZD)
$ tr -d '\n' < at | wc -c
     625
```

Das Token nennt die Person und ihren IdP, aber keine Gruppe:

```
$ cut -d. -f2 at | tr "_-" "/+" | jq -R "@base64d | fromjson"
{
  "aud": "ssh",
  "client_id": "oidc-agent",
  "exp": 1791741018,
  "iat": 1791737418,
  "idp": "https://idp.univ-example.example/idp/shibboleth",
  "iss": "http://127.0.0.1:28473",
  "jti": "0zVsbDeAwcubhCCFXtj9Dh0u-93sDBza5sti7EmcSL8",
  "preferred_username": "alice@univ-example.example",
  "scope": "openid eduperson groups",
  "sub": "KEQ1dJYNUw8TtXF5HNbuy3EYZ3rmFMKiqaVY8RH7eLE"
}
```

`/userinfo` liefert sie weiterhin, als `groups` (Scope `groups`) und als
`eduperson_entitlement` (Scope `eduperson`):

```
$ { printf 'Authorization: Bearer '; cat at; } > auth.hdr
$ curl -s -H @auth.hdr http://127.0.0.1:28473/userinfo | jq .
{
  "eduperson_entitlement": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "eduperson_principal_name": "alice@univ-example.example",
  "entitlements": [
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example",
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example"
  ],
  "groups": [
    "urn:geant:univ-example.example:group:hpc-users#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique#idp.univ-example.example",
    "urn:geant:univ-example.example:group:physique:calcul#idp.univ-example.example"
  ],
  "sub": "KEQ1dJYNUw8TtXF5HNbuy3EYZ3rmFMKiqaVY8RH7eLE"
}
```

**Der Standard bleibt `true`.** go-fileshare braucht, wie jeder
Ressourcenserver, der allein anhand des Tokens entscheidet, die Gruppen darin:
Weggelassen werden sie nur für einen Client, dessen Tokens an einen Server
gehen, der `/userinfo` liest.

**Abgelehnt zusammen mit Zertifikaten.** SSH- und X.509-Zertifikate übernehmen
die Gruppen der Person aus dem Access-Token; ein Client mit
`access_token_groups = false` und `ssh_certificates` oder `x509_certificates`
würde also Zertifikate ohne Gruppen ausstellen, und ein Server, der nach Gruppen
autorisiert, würde die Person abweisen, ohne dass irgendwo stünde, warum.
`check` lehnt die Kombination ab, wie der Server beim Start:

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
  ssh_certificates    = true
}
```

```
$ authn-bridge check --config etc/bridge.hcl
authn-bridge: client "oidc-agent": access_token_groups = false with ssh_certificates or x509_certificates: the certificates take the groups from the access token, and would carry none -- use one client for the certificates and another for tokens pasted into ssh
$ echo $?
1
```

Die Zertifikate bekommen dann einen eigenen Client, die in ssh eingefügten Tokens einen anderen.

Ein Token mit einem der eigenen Scopes des Anbieters (`ssh`, `nfs`,
`app_password`, `wireguard`, `wireguard_peers`) ist **allein an den Anbieter**
adressiert: Sein `aud` ist der Aussteller, und diese Endpunkte lehnen jedes andere ab. Ein Token,
das ein Ressourcenserver erhalten hat, kann hier nicht wiedereingespielt werden:

```
$ curl -s -X POST http://127.0.0.1:28473/ssh/certificate -d x -D - -o -
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Www-Authenticate: Bearer error="invalid_token"
X-Content-Type-Options: nosniff
Date: Sun, 11 Oct 2026 09:48:07 GMT
Content-Length: 23

the token is not valid
```

Ein bereits ausgegebenes Access-Token ist eine signierte Aussage, die ein Ressourcenserver
selbst prüft. Was [`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})
beendet, ist alles, was damit hierher zurückkommt; der Ressourcenserver erfährt es
über [Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}).

## Ohne Browser: der Device Grant {#without-a-browser-the-device-grant}

Ein WebDAV-Client, ein Skript, ein Terminal hat keinen Browser, den es zu einer Universität schicken könnte. Ein
Client mit `device = true` fordert einen Code an (RFC 8628), und die Person meldet sich
auf einem beliebigen anderen Gerät an:

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone` gibt
ein Access-Token aus, meldet sich beim ersten Mal an und aktualisiert danach; es ist
der Device-Client von golang.org/x/oauth2, kein hier geschriebener.

| | |
|---|---|
| Benutzercodes | acht Buchstaben aus `BCDFGHJKLMNPQRSTVWXZ` (keine Vokale, keine Ziffern), zehn Minuten gültig; zehn **falsche** Codes pro Host in dieser Zeit (eine IPv4-Adresse, ein IPv6-/64), und zehnmal so viele für das /24 oder /48 darum herum |
| Abfrage | alle fünf Sekunden; schnelleres Abfragen bringt `slow_down` ein |
| wartende Geräte | höchstens 20.000; darüber hinaus wird das älteste verdrängt, statt alle abzulehnen |
| Refresh-Tokens | bei jeder Verwendung rotiert, innerhalb einer Familie, deren Ende bei der Anmeldung durch `refresh_lifetime` festgelegt wird; ein ausgemustertes, das erneut verwendet wird, widerruft die Familie und die Access-Tokens, die sie erworben hat |

## Anwendungspasswörter {#application-passwords}

NTLMv2 und SigV4 beweisen ein Geheimnis, das der Server bereits besitzen muss; deshalb genügt für SMB
oder S3 kein Token. Ein Client mit `app_passwords = true` erlaubt einem Token mit dem
Scope `app_password`, eines festzulegen, das erzeugt und einmal angezeigt wird:
`authn-bridge app-password --issuer ... --client files` (`--remove` löscht es).

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

Die Tabelle wird angelegt, falls sie fehlt: `login, password, nt_hash, expires, idp`.
Gespeichert wird nur, was die Protokolle brauchen: der NT-Hash für SMB, das Passwort selbst
nur, wenn `store` es verlangt. go-fileshare liest sie mit einem `users "sql"`-Block;
benennen Sie die Spalten in dessen Abfrage, nie `*`.

Eine Person zu deaktivieren, entfernt ihr Passwort; eine Einrichtung zu deaktivieren, entfernt die Passwörter
ihrer Personen. Ein entferntes Passwort funktioniert in go-fileshare nicht mehr, sobald es
sein Verzeichnis das nächste Mal liest.

## WireGuard-Schlüssel {#wireguard-keys}

WireGuard authentifiziert einen Peer über seinen öffentlichen Schlüssel und sonst nichts: kein
Zertifikat, kein Ablauf, kein Widerruf. Deshalb hält der Anbieter die Antwort auf
*Wem gehört dieser Schlüssel, und darf er noch verbinden?* bereit. Der VPN-Client des Geräts
registriert den öffentlichen Schlüssel für eine Leasingdauer; der private Schlüssel verlässt das Gerät nie;
ein Gateway liest die gültigen Schlüssel als eine Liste, die allein für es signiert ist.

```hcl
certificates_file = "/var/lib/authn-bridge/certificates.json"   # keys are recorded beside the certificates

wireguard {
  lifetime = "24h"              # the default: how long a key is listed; registering again renews it
  max_keys = 10                 # the default: devices per person
}

client "vpn" {                  # what people log in with
  device         = true
  wireguard_keys = true
}

client "vpn-gw" {               # the gateway's own client
  secret_file     = "/etc/authn-bridge/vpn-gw.secret"
  wireguard_peers = ["vpn"]     # the clients whose keys it reads
  ssf_receiver    = true        # optional: told at once when somebody is disabled
}
```

| | |
|---|---|
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`, mit einem Token des Scopes `wireguard`; antwortet mit dem Ende der Leasingdauer |
| `DELETE /wireguard/key` | `{"public_key": "..."}`: Wer den Schlüssel besitzt, nimmt ihn zurück |
| `GET /wireguard/peers` | für das eigene `client_credentials`-Token des Gateways, Scope `wireguard_peers`: ein signiertes JWT vom Typ `wireguard-peers+jwt`, an dieses Gateway adressiert, fünf Minuten gültig |

Ein Schlüssel, den jemand anderes hält, ein zurückgenommener Schlüssel und ein Schlüssel zu viel werden
mit `409` abgelehnt. Ein Gateway-Client muss vertraulich sein und Clients benennen,
die `wireguard_keys` haben. Das Format der Liste und die Seite des Gateways gehören zu
go-authn/wireguard.

## OpenPubkey und opkssh {#openpubkey-and-opkssh}

opkssh macht aus einem ID-Token SSH-Anmeldungen ganz ohne CA, und das Token, das es
erzeugt (ein PK Token), überdauert das ID-Token darin. Der Anbieter gibt die
`nonce` im Code-Flow und im Device-Flow unverändert zurück, signiert mit RS256 und hält
einen ausgemusterten Schlüssel so lange **veröffentlicht**, wie `retired_signing_key_files` ihn
nennt, damit ein vor einer Rotation signiertes PK Token weiterhin geprüft werden kann:

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

Geben Sie opkssh einen eigenen Client mit `id_token_claims = true`: Es ordnet Personen
anhand der Claims des PK Token zu, und sein ID-Token reist zu jedem Server, bei dem es sich anmeldet.
