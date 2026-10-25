---
title: "多个资源服务器：每次获取其中一个的令牌"
linkTitle: "资源指示符"
weight: 45
description: "authn-bridge 中的 RFC 8707 资源指示符：audience 指名多个资源服务器的客户端，请求发往其中一个的访问令牌。"
tags: [authn-bridge, oidc, 令牌, rfc8707]
---

`audience` 指名多个资源服务器的客户端（例如位于多个文件服务器
之前的门户），得到的访问令牌是发往它们**所有**服务器的。
这些服务器中的任何一个都可以拿着收到的令牌去
向其他服务器出示：RFC 8707 §3 说明，这正是应当限制 audience 的原因。自
v0.21.0 起，客户端可以用 RFC 8707 的 `resource` 参数请求发往其中**一个**
服务器的令牌。本页描述 v0.23.3；v0.22.0 的不同之处见
[末尾](#departures)。

没有 `resource` 时，一切不变：访问令牌发往客户端的全部
`audience`，如[令牌页面]({{< relref "/authn-bridge/tokens.md#the-access-token" >}})
所述。

## 客户端 {#the-client}

无需启用任何东西。客户端 `audience` 中的每个 URI 都可以被请求。
下面的示例使用带有刷新令牌的机密客户端，以及具有相同 audience 的设备
客户端：

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
federation    1 IdPs, 1 usable here, valid until 2026-10-18T15:48:27Z
client        portal (confidential, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
client        files-cli (public, public subject, audience [https://fs-paris.example.org/ https://fs-lyon.example.org/])
```

`check` 列出 audience，对其不作其他说明。尤其是，它不会
说明哪些条目可以被请求：只有**不带片段的绝对 URI**可以。
诸如 `fileshare` 之类的逻辑名称，或带有 `#` 的 URI，会被
`audience` 接受，并且在没有指名资源时仍然会放入令牌，
但指名它的 `resource` 会被拒绝。

## 发往一个服务器的令牌 {#a-token-for-one-server}

人员照常登录（此处针对测试联邦，授权请求中不指名
资源）。客户端随后在交换授权码时指名一个服务器：

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

`aud` 就是所请求的值，与发送时完全一致，别无其他。检查其 audience 的
服务器（如 [go-authn/oidc]({{< relref "/libraries/oidc.md" >}})）
会在巴黎接受此令牌，在里昂拒绝它。

## 下一次刷新时换另一个服务器 {#another-server-at-the-next-refresh}

刷新令牌保留整个授权（RFC 8707 §2.2），因此下一次刷新可以
请求另一个服务器：

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

两个服务器的 `scope` 相同：提供方不会按
资源缩减它。

## 客户端不可拥有的服务器 {#a-server-the-client-may-not-have}

不在客户端 `audience` 中的资源会被拒绝，返回
`invalid_target`：

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

**被拒绝的刷新不会消耗刷新令牌。** 请求在令牌被用掉之前
就已检查，因此同一个刷新令牌仍然可用。若不请求
资源，它给出的是发往客户端全部 audience 的令牌：

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

该值与 `audience` 条目按字符串比较，不会像 URI 一样被规范化。
去掉末尾 `/` 的同一个服务器是另一个资源：

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

## 在授权请求处限定授权范围 {#bounding-the-grant-at-the-authorization-request}

`resource` 也可以随授权请求一起发送。此时它限定
授权范围：授权码以及随后的刷新令牌都发往该服务器，
之后的令牌请求可以再次指名它，但绝不能指名另一个。在授权请求带有
`resource=https://fs-paris.example.org/` 的登录之后：

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

授权请求可以带有**多个** `resource` 值：这是在那里唯一
可以重复的参数。每个值都会被检查，重复给出的值只算一次，
授权就发往所指名的那些服务器。在授权请求带有
`resource=https://fs-paris.example.org/` 和
`resource=https://fs-lyon.example.org/` 的登录之后，授权码给出发往两者的令牌，
而每次刷新都可以请求其中任何一个：

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

有 `state` 块时，授权的资源会与刷新令牌一起存储，
因此重启不会使其范围变宽。

客户端不可拥有的资源在授权端点同样会被拒绝，
以发回客户端重定向 URI 的错误形式。正常值之中混有一个这样的值
就会拒绝整个请求：

```
$ curl -s -o /dev/null -w "%{http_code} %{redirect_url}\n" -G http://127.0.0.1:28473/authorize \
    -d response_type=code -d client_id=portal -d scope=openid -d state=s1 \
    --data-urlencode redirect_uri=http://127.0.0.1:9/portal \
    -d code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM -d code_challenge_method=S256 \
    --data-urlencode resource=https://fs-paris.example.org/ \
    --data-urlencode resource=https://fs-nantes.example.org/
302 http://127.0.0.1:9/portal?error=invalid_target&error_description=resource+%22https%3A%2F%2Ffs-nantes.example.org%2F%22+is+not+one+this+client+may+ask+a+token+for&iss=http%3A%2F%2F127.0.0.1%3A28473&state=s1
```

**在令牌端点，每个请求一个资源。** 令牌发往一个服务器、
发往授权所指名的那些服务器，或发往整个 `audience`；它绝不会发往
由令牌请求选择的列表。那里的第二个 `resource` 会像任何重复的
参数一样被拒绝：

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

## 规则 {#the-rules}

| | |
|---|---|
| **在何处** | 授权端点接受 `resource`，令牌端点在 `authorization_code` 和 `refresh_token` 授权中接受它 |
| **多少个** | 在授权端点可以有多个：每个都会被检查，一个被拒绝就会拒绝整个请求。在令牌端点只能有一个：第二个是 `invalid_request` |
| **可以指名什么** | 不带片段的绝对 URI，且逐字符等于客户端 `audience` 中的某一项 |
| **令牌的 `aud`** | 令牌端点所指名的资源；若没有，则是授权请求按给定顺序所指名的资源；若两者都没有，则是客户端的整个 `audience` |
| **刷新** | 可以指名授权请求所指名的资源之一，或者在它没有指名任何资源时，指名客户端 `audience` 中的任意 URI。新的刷新令牌保留整个授权 |
| **被拒绝** | `invalid_target`，在授权端点发回重定向 URI，在令牌端点则作为 `400` 错误返回。被拒绝的刷新不会消耗刷新令牌 |
| **其他授权** | 在 `client_credentials`、设备授权请求或轮询设备令牌时带有 `resource`，会被以 `invalid_target` 拒绝而不是忽略：请求某一服务器令牌的客户端，绝不能收到发往另一个服务器的令牌。设备令牌始终发往整个 `audience` |
| **提供方自己的 scope** | 带有 `ssh`、`nfs`、`app_password`、`wireguard` 或 `wireguard_peers` 的令牌只发往提供方本身，且只能指名签发方自己 |

在令牌端点和设备授权请求处对其他授权的拒绝：

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

## 与 RFC 8707 的偏离之处 {#departures}

| RFC 8707 | authn-bridge v0.23.3 |
|---|---|
| §2：“Multiple `resource` parameters MAY be used” | 在授权端点，照此执行。在令牌端点只能有一个：第二个 `resource` 是 `invalid_request`，§3 允许这样做（“an authorization server may be unwilling or unable to fulfill a token request with multiple resources”） |
| §2.2：该参数适用于“for all grant types” | 仅限 `authorization_code` 和 `refresh_token`。对于 `client_credentials` 或设备授权，它会被以 `invalid_target` 拒绝，在设备授权请求处和轮询时都是如此 |
| §2：该值“SHOULD NOT include a query component” | 不检查。检查的是该值为绝对 URI、没有片段，并且在客户端的 `audience` 中 |
| §2：服务器“may map from that value to a more general URI or abstract identifier” | 不做映射：`aud` 就是所请求的值，与 `audience` 按字符串比较 |
| §2.2：“the authorization server should downscope the scope value”，针对每个资源 | 未做到：`scope` 是授权的 scope，无论指名哪个服务器 |
| §2.1：没有 `resource` 的请求 MAY 通过“by using a predefined default resource value”来处理 | 默认值是客户端的整个 `audience` |
| §2.2：刷新可以限制为“to those [resources] that were originally granted”，并且刷新令牌“is bound to the full original grant” | 照此执行 |

**在 v0.22.1 之前**，v0.22.0 在授权端点会像拒绝任何其他重复的参数一样，以错误页面
拒绝重复的 `resource`，因此一个授权无法指名两个服务器；并且它的设备授权请求
不读取 `resource`，所以请求某一服务器的设备得到的是发往整个
`audience` 的令牌。
