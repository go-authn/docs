---
title: "Mehrere Ressourcenserver: ein Token für jeweils einen"
linkTitle: "Resource Indicators"
weight: 45
description: "Resource Indicators nach RFC 8707 in authn-bridge: Ein Client, dessen audience mehrere Ressourcenserver nennt, fordert ein Access-Token an, das an einen von ihnen adressiert ist."
tags: [authn-bridge, oidc, tokens, rfc8707]
---

Ein Client, dessen `audience` mehrere Ressourcenserver nennt, etwa ein Portal vor
mehreren Dateiservern, erhält Access-Tokens, die an **alle** adressiert sind. Jeder
dieser Server kann dann ein Token, das er erhalten hat, den anderen vorlegen:
Deshalb, so RFC 8707 §3, sollte die Audience eingeschränkt werden. Seit v0.21.0
kann der Client mit dem Parameter `resource` aus RFC 8707 ein Token anfordern, das
an **nur einen** von ihnen adressiert ist.

Ohne `resource` ändert sich nichts: Das Access-Token ist für die ganze `audience`
des Clients, wie [die Seite über Tokens]({{< relref "/authn-bridge/tokens.md#the-access-token" >}})
beschreibt.

## Der Client {#the-client}

Es muss nichts eingeschaltet werden. Jede URI in der `audience` des Clients kann
angefordert werden:

```hcl
client "portal" {
  secret_file      = "etc/portal.secret"
  redirect_uris    = ["http://127.0.0.1:9/portal"]
  audience         = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
  refresh_lifetime = "8h"
}
```

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-10-18T10:46:00Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
```

`check` listet die Audience auf und sagt sonst nichts dazu. Insbesondere sagt es
nicht, welche Einträge angefordert werden können: nur eine **absolute URI ohne
Fragment**. Ein logischer Name wie `fileshare` oder eine URI mit `#` wird in
`audience` angenommen und landet weiterhin im Token, wenn keine Ressource genannt
wird; ein `resource`, das ihn nennt, wird aber abgelehnt.

## Ein Token für einen einzigen Server {#a-token-for-one-server}

Die Person meldet sich wie gewohnt an (hier bei einer Testföderation, mit einer
Autorisierungsanfrage, die keine Ressource nennt). Der Client nennt dann beim
Einlösen des Codes einen Server:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    --data-urlencode resource=https://fs-paris.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

Das `aud` ist der angeforderte Wert, genau so, wie er gesendet wurde, und nichts
sonst. Ein Server, der seine Audience prüft, wie es
[go-authn/oidc]({{< relref "/libraries/oidc.md" >}}) tut, nimmt dieses Token in
Paris an und lehnt es in Lyon ab.

## Ein anderer Server, beim nächsten Refresh {#another-server-at-the-next-refresh}

Das Refresh-Token behält den ganzen Grant (RFC 8707 §2.2), also kann der nächste
Refresh einen anderen Server anfordern:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-lyon.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
```

Der Wert von `scope` ist für beide Server derselbe: Der Anbieter verkleinert ihn
nicht je nach Ressource.

## Ein Server, den der Client nicht haben darf {#a-server-the-client-may-not-have}

Eine Ressource, die nicht in der `audience` des Clients steht, wird mit
`invalid_target` abgelehnt:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-nantes.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-nantes.example.org/\" is not one this client may ask a token for"
}
400
```

**Ein abgelehnter Refresh verbraucht das Refresh-Token nicht.** Die Anfrage wird
geprüft, bevor das Token verbraucht wird, sodass dasselbe Refresh-Token weiter
funktioniert. Ohne angeforderte Ressource liefert es ein Token für die ganze
Audience des Clients:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": [
    "https://fs-paris.example.org/",
    "https://fs-lyon.example.org/"
  ],
  "client_id": "portal",
  "scope": "openid profile"
}
```

Der Wert wird mit den Einträgen von `audience` als Zeichenkette verglichen, nicht
als URI normalisiert. Derselbe Server ohne sein abschließendes `/` ist eine andere
Ressource:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org \
    -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-paris.example.org\" is not one this client may ask a token for"
}
400
```

## Den Grant schon in der Autorisierungsanfrage begrenzen {#bounding-the-grant-at-the-authorization-request}

`resource` kann auch mit der Autorisierungsanfrage gesendet werden. Dann begrenzt
es den Grant: Der Code und die folgenden Refresh-Tokens gelten diesem Server, und
eine spätere Token-Anfrage kann ihn erneut nennen, aber nie einen anderen. Nach
einer Anmeldung, deren Autorisierungsanfrage
`resource=https://fs-paris.example.org/` enthielt:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
    -o tokens.json -w "%{http_code}\n"
200
$ jq -r .access_token tokens.json | cut -d. -f2 | tr "_-" "/+" |
    jq -R "@base64d | fromjson | {aud, client_id, scope}"
{
  "aud": "https://fs-paris.example.org/",
  "client_id": "portal",
  "scope": "openid profile"
}
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource \"https://fs-lyon.example.org/\" was not part of the authorization"
}
400
```

Mit einem `state`-Block werden die Ressourcen des Grants mit dem Refresh-Token
gespeichert, sodass ein Neustart ihn nicht erweitert.

Eine Ressource, die der Client nicht haben darf, wird auch am
Autorisierungs-Endpunkt abgelehnt, als Fehler an die Redirect-URI des Clients:

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**Eine Ressource pro Anfrage, an beiden Endpunkten.** Jeder doppelt gesendete
Parameter wird abgelehnt, auch `resource`. Am Token-Endpunkt lautet die Antwort
`invalid_request`. Am Autorisierungs-Endpunkt ist es eine Fehlerseite, und der
Client wird nicht weitergeleitet:

```
$ curl -s -o page.html -w "%{http_code}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-lyon.example.org/
400
$ grep -o "<p>.*</p>" page.html
<p>The parameter resource appears more than once.</p>
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-lyon.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_request",
  "error_description": "resource appears more than once"
}
400
```

Ein Grant für zwei der Server des Clients, aber nicht für alle, lässt sich also
nicht anfordern. Ein Token für mehr als einen Server ist die ganze `audience`,
angefordert, indem keine Ressource genannt wird.

## Die Regeln {#the-rules}

| | |
|---|---|
| **wo** | `resource` nimmt der Autorisierungs-Endpunkt an, und der Token-Endpunkt mit den Grants `authorization_code` und `refresh_token` |
| **wie viele** | eine pro Anfrage. Doppelt gesendet, wird es abgelehnt wie jeder wiederholte Parameter |
| **was genannt werden darf** | eine absolute URI ohne Fragment, die Zeichen für Zeichen ein Eintrag der `audience` des Clients ist |
| **das `aud` des Tokens** | die am Token-Endpunkt genannte Ressource; sonst die, die die Autorisierungsanfrage nannte; wenn keine von beiden, die ganze `audience` des Clients |
| **ein Refresh** | darf die Ressource nennen, die die Autorisierungsanfrage nannte, oder, wenn sie keine nannte, jede URI der `audience` des Clients. Das neue Refresh-Token behält den ganzen Grant |
| **abgelehnt** | `invalid_target`, am Autorisierungs-Endpunkt an die Redirect-URI gesendet, am Token-Endpunkt als Fehler `400` zurückgegeben. Ein abgelehnter Refresh verbraucht das Refresh-Token nicht |
| **andere Grants** | `resource` mit `client_credentials` oder dem Device Grant wird mit `invalid_target` abgelehnt, nicht ignoriert: Ein Client, der ein Token für einen Server angefordert hat, darf keines für einen anderen erhalten. Die Device-Autorisierungsanfrage liest `resource` nicht, also ist ein Device-Token immer für die ganze `audience` |
| **die eigenen Scopes des Anbieters** | ein Token mit `ssh`, `nfs`, `app_password`, `wireguard` oder `wireguard_peers` ist allein für den Anbieter, und nur der Aussteller selbst darf genannt werden |

Die Ablehnung anderer Grants, am Token-Endpunkt:

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=client_credentials \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

## Wo dies von RFC 8707 abweicht {#departures}

| RFC 8707 | authn-bridge v0.22.0 |
|---|---|
| §2: „Multiple `resource` parameters MAY be used“, und Abbildung 2 sendet zwei in derselben Autorisierungsanfrage | eine pro Anfrage. Der Autorisierungs-Endpunkt lehnt jeden wiederholten Parameter ab, unter Berufung auf RFC 6749 §3.1, auch `resource`, und antwortet mit einer Fehlerseite. Ein Grant kann keine Teilmenge von zwei oder mehr Servern nennen. Die README von v0.22.0 sagt, `resource` „may be repeated“ am Autorisierungs-Endpunkt; der Code lehnt es ab |
| §3: ein Autorisierungsserver „may be unwilling or unable to fulfill a token request with multiple resources“ | erlaubt, und so ist es: Am Token-Endpunkt ist ein zweites `resource` `invalid_request` |
| §2.2: der Parameter gilt „for all grant types“ | nur `authorization_code` und `refresh_token`. Mit `client_credentials` oder dem Device Grant wird er mit `invalid_target` abgelehnt, und die Device-Autorisierungsanfrage liest ihn nicht |
| §2: der Wert „SHOULD NOT include a query component“ | nicht geprüft. Geprüft wird, dass der Wert absolut ist, kein Fragment hat und in der `audience` des Clients steht |
| §2: der Server „may map from that value to a more general URI or abstract identifier“ | keine Zuordnung: Das `aud` ist der angeforderte Wert, mit `audience` als Zeichenkette verglichen |
| §2.2: „the authorization server should downscope the scope value“ je Ressource | nicht umgesetzt: Der Wert von `scope` ist der des Grants, welcher Server auch genannt wird |
| §2.1: eine Anfrage ohne `resource` MAY „by using a predefined default resource value“ verarbeitet werden | der Standardwert ist die ganze `audience` des Clients |
| §2.2: ein Refresh darf auf „those [resources] that were originally granted“ beschränkt werden, und das Refresh-Token „is bound to the full original grant“ | wie beschrieben |
