---
title: "複数のリソースサーバー: 一度に一つ宛てのトークン"
linkTitle: "リソースインジケーター"
weight: 45
description: "authn-bridge における RFC 8707 リソースインジケーター: audience が複数のリソースサーバーを指すクライアントが、そのうち一つ宛てのアクセストークンを要求する。"
tags: [authn-bridge, oidc, トークン, rfc8707]
---

`audience` が複数のリソースサーバー、たとえば複数のファイルサーバーの手前にあるポータルを指す
クライアントは、それら**すべて**宛てのアクセストークンを受け取ります。そうすると、それらの
サーバーのどれもが、受け取ったトークンを他のサーバーに提示できてしまいます。RFC 8707 §3 が、
オーディエンスを制限すべき理由としているのはこれです。v0.21.0 からは、クライアントは RFC 8707 の
`resource` パラメーターを使って、そのうち**一つ**宛てのトークンを要求できます。このページは
v0.23.4 を説明しており、v0.22.0 の違いは[末尾](#departures)にあります。

`resource` がなければ何も変わりません。アクセストークンはクライアントの `audience` 全体宛てで、
[トークンのページ]({{< relref "/authn-bridge/tokens.md#the-access-token" >}})が説明するとおりです。

## クライアント {#the-client}

有効にする必要のあるものはありません。クライアントの `audience` にあるすべての URI を要求
できます。以下の例では、リフレッシュトークンを持つ機密クライアントと、同じオーディエンスを持つ
デバイスクライアントを使います。

```hcl
client "portal" {
  secret_file      = "etc/portal.secret"
  redirect_uris    = ["http://127.0.0.1:9/portal"]
  audience         = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
  refresh_lifetime = "8h"
}

client "files-cli" {
  device   = true
  audience = ["https://fs-paris.example.org/", "https://fs-lyon.example.org/"]
}
```

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-11-02T11:30:50Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
client        files-cli (public, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
```

`check` はオーディエンスを列挙するだけで、それ以上のことは述べません。特に、どのエントリが
要求できるかは述べません。要求できるのは、**フラグメントのない絶対 URI** だけです。
`fileshare` のような論理名や、`#` を含む URI は `audience` に受け入れられ、リソースが指名され
ないときはトークンに入りますが、それを指名する `resource` は拒否されます。

## 一つのサーバー宛てのトークン {#a-token-for-one-server}

人は通常どおりログインします (ここではテスト用フェデレーションに対して、認可リクエストは
リソースを指名しません)。その後、クライアントはコードを交換する際に一つのサーバーを指名します。

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

`aud` は要求された値そのままで、送られたとおりのものです。他には何もありません。
[go-authn/oidc]({{< relref "/libraries/oidc.md" >}}) のようにオーディエンスを検証するサーバーは、
このトークンをパリでは受け入れ、リヨンでは拒否します。

## 次のリフレッシュで別のサーバー {#another-server-at-the-next-refresh}

リフレッシュトークンはグラント全体を保持する (RFC 8707 §2.2) ので、次のリフレッシュでは
別のサーバーを要求できます。

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

`scope` は両方のサーバーで同じです。プロバイダーはリソースごとにそれを絞り込みません。

## クライアントが持てないサーバー {#a-server-the-client-may-not-have}

クライアントの `audience` にないリソースは、`invalid_target` で拒否されます。

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

**拒否されたリフレッシュは、リフレッシュトークンを消費しません。** リクエストはトークンが使い
切られる前に検証されるので、同じリフレッシュトークンが引き続き使えます。リソースを指定
しなければ、クライアントのオーディエンス全体宛てのトークンが得られます。

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

値は `audience` のエントリと文字列として比較され、URI として正規化されることはありません。
末尾の `/` のない同じサーバーは、別のリソースです。

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

## 認可リクエストでグラントを限定する {#bounding-the-grant-at-the-authorization-request}

`resource` は認可リクエストとともに送ることもできます。その場合はグラントを限定します。
コードとそれに続くリフレッシュトークンはそのサーバー宛てになり、後のトークンリクエストは
それをもう一度指名できますが、別のものは決して指名できません。認可リクエストが
`resource=https://fs-paris.example.org/` を運んだログインの後:

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

認可リクエストは**複数の** `resource` 値を運べます。そこで繰り返してよい唯一のパラメーター
です。それぞれが検証され、二度与えられた値は一度として数えられ、グラントは指名されたサーバー
宛てになります。認可リクエストが `resource=https://fs-paris.example.org/` と
`resource=https://fs-lyon.example.org/` を運んだログインの後、コードは両方宛てのトークンを
与え、各リフレッシュはどちらかを要求できます。

```
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=authorization_code -d code="$(cat code)" \
    -d code_verifier="$(cat verifier)" -d redirect_uri=http://127.0.0.1:9/portal \
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
$ curl -s --netrc-file etc/portal.netrc http://127.0.0.1:28473/token \
    -d grant_type=refresh_token -d refresh_token="$(jq -r .refresh_token tokens.json)" \
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

`state` ブロックがあれば、グラントのリソースはリフレッシュトークンとともに保存されるので、
再起動で範囲が広がることはありません。

クライアントが持てないリソースは、認可エンドポイントでも、クライアントのリダイレクト URI に
返されるエラーとして拒否されます。良い値の中にそのような値が一つあるだけで、リクエスト全体が
拒否されます。

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**トークンエンドポイントでは、リクエストごとにリソースは一つ。** トークンは、一つのサーバー宛て、
グラントのサーバー宛て、または `audience` 全体宛てのいずれかで、トークンリクエストが選んだ
リストに宛てられることは決してありません。そこでの二つ目の `resource` は、他の繰り返された
パラメーターと同様に拒否されます。

```
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

## ルール {#the-rules}

| | |
|---|---|
| **どこで** | `resource` は認可エンドポイントと、`authorization_code` および `refresh_token` グラントでのトークンエンドポイントが受け付ける |
| **いくつ** | 認可エンドポイントでは複数: それぞれが検証され、拒否された一つがリクエスト全体を拒否する。トークンエンドポイントでは一つ: 二つ目は `invalid_request` |
| **何を指名できるか** | クライアントの `audience` のエントリと一字一句同じ、フラグメントのない絶対 URI |
| **トークンの `aud`** | トークンエンドポイントで指名されたリソース。なければ、認可リクエストが指名したリソースを指定された順で。どちらもなければ、クライアントの `audience` 全体 |
| **リフレッシュ** | 認可リクエストが指名したリソースのいずれか、何も指名しなかった場合はクライアントの `audience` のどの URI でも指名できる。新しいリフレッシュトークンはグラント全体を保持する |
| **拒否** | `invalid_target`。認可エンドポイントではリダイレクト URI に返され、トークンエンドポイントでは `400` エラーとして返される。拒否されたリフレッシュはリフレッシュトークンを消費しない |
| **その他のグラント** | `client_credentials` での `resource`、デバイス認可リクエストまたはデバイストークンのポーリング時の `resource` は、無視されずに `invalid_target` で拒否される。一つのサーバー宛てのトークンを求めたクライアントが、別のサーバー宛てのものを受け取ってはならないため。デバイストークンは常に `audience` 全体宛て |
| **プロバイダー自身のスコープ** | `ssh`、`nfs`、`app_password`、`wireguard`、`wireguard_peers` を持つトークンはプロバイダー専用で、指名できるのは発行者自身だけ |

トークンエンドポイントとデバイス認可リクエストでの、その他のグラントの拒否:

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

```
$ curl -s http://127.0.0.1:28473/device_authorization -d client_id=files-cli \
    --data-urlencode resource=https://fs-paris.example.org/ -w "\n%{http_code}\n" | jq .
{
  "error": "invalid_target",
  "error_description": "resource indicators are taken with the authorization_code and refresh_token grants"
}
400
```

## RFC 8707 からの逸脱 {#departures}

| RFC 8707 | authn-bridge v0.23.4 |
|---|---|
| §2: "Multiple `resource` parameters MAY be used" | 認可エンドポイントでは記述どおり。トークンエンドポイントでは一つ: 二つ目の `resource` は `invalid_request` で、これは §3 が認めている ("an authorization server may be unwilling or unable to fulfill a token request with multiple resources") |
| §2.2: パラメーターは "for all grant types" に適用される | `authorization_code` と `refresh_token` のみ。`client_credentials` やデバイスグラントでは、デバイス認可リクエストでもポーリング時でも、`invalid_target` で拒否される |
| §2: 値は "SHOULD NOT include a query component" | 検証しない。検証するのは、値が絶対 URI で、フラグメントがなく、クライアントの `audience` にあること |
| §2: サーバーは "may map from that value to a more general URI or abstract identifier" | マッピングなし: `aud` は要求された値で、`audience` と文字列として比較される |
| §2.2: 各リソースについて "the authorization server should downscope the scope value" | 行わない: `scope` はグラントのもので、どのサーバーを指名しても同じ |
| §2.1: `resource` のないリクエストは "by using a predefined default resource value" で処理してよい | 既定値はクライアントの `audience` 全体 |
| §2.2: リフレッシュは "to those [resources] that were originally granted" に限定でき、リフレッシュトークンは "is bound to the full original grant" | 記述どおり |

**v0.22.1 より前**は、v0.22.0 は認可エンドポイントでの繰り返された `resource` を、他の繰り返された
パラメーターと同様にエラーページで拒否していたため、グラントが二つのサーバーを指名することは
できませんでした。またそのデバイス認可リクエストは `resource` を読まなかったため、一つの
サーバーを求めたデバイスが `audience` 全体宛てのトークンを得ていました。
