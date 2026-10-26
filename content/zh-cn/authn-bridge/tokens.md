---
title: "令牌、密码和密钥"
linkTitle: "令牌"
weight: 40
description: "应用程序从 authn-bridge 得到什么：ID 令牌和访问令牌、设备授权、用于 SMB 和 S3 的应用密码，以及 WireGuard 密钥。"
tags: [authn-bridge, oidc, 令牌, wireguard]
---

这里的每种凭据都始于在人员所属机构的同一次登录。
不同之处在于凭据是为谁而设，以及如何收回。证书见
[它们自己的页面]({{< relref "/authn-bridge/certificates.md" >}})。

## 提供方发布什么 {#what-the-provider-publishes}

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

授权码流程，**每个客户端都必须使用 PKCE S256**。没有
`code_challenge_method` 的请求会被拒绝，而不是被当作 S256 处理，
因为 RFC 7636 将 `plain` 定为默认值。配置了
`pkce = "or_nonce"` 的机密客户端可以改为发送 OpenID `nonce`。

## ID 令牌 {#the-id-token}

它面向客户端，关于登录而不是关于人员：RS256，`aud` 为客户端
ID，`sub`、`auth_time`、`at_hash`，请求带有 `nonce` 时的 `nonce`，以及
IdP 说明其所用认证上下文时的 `acr`。有效期为
`id_token_lifetime`，默认五分钟。

**其中没有任何关于人员的内容。** scope 所释放的声明位于
`/userinfo`，这正是 OIDC Core 5.4 在签发访问令牌时的规定，而访问令牌
总会签发。ID 令牌本身就是凭据的客户端（例如 opkssh）
设置 `id_token_claims = true`，以便把它们复制进去。ID 令牌只会
为带有 `openid` scope 的请求签发。

| scope | 释放 |
|---|---|
| `profile` | `name`、`given_name`、`family_name`、`preferred_username` |
| `email` | `email`（绝不含 `email_verified`） |
| `eduperson` | `eduperson_principal_name`、`eduperson_scoped_affiliation`、`eduperson_entitlement` 和 `entitlements`、`eduperson_assurance`、`eduperson_orcid`、`schac_home_organization`、`voperson_id`（SAML 的 `subject-id`，转为小写） |
| `groups` | `groups` |

## 访问令牌 {#the-access-token}

面向客户端 `audience` 中的资源服务器，如 RFC 9068 所述：
用 `signing_key_file`（RS256）或 `access_token_key_file`（ES256）签名，
`typ: at+jwt`，有效期为 `token_lifetime`（默认一小时）。它携带资源
服务器无需询问任何人即可作出决定所需的内容：`preferred_username`、
`groups`、`idp`（为之担保的 IdP 的实体 ID）、`scope`、`client_id`，
以及 IdP 说明其会话何时结束时的 `session_end`。
组可以按客户端省略：见[下文](#what-it-leaves-out)。

`audience` 指名多个资源服务器的客户端，可以用 RFC 8707 的 `resource`
请求发往其中一个的令牌：参见
[多个资源服务器]({{< relref "/authn-bridge/resources.md" >}})。

### 它省略了什么，以及原因 {#what-it-leaves-out}

**没有 `auth_time`，也没有 `acr`**，尽管 RFC 9068 允许两者。它们仍保留在
ID 令牌中，OIDC Core 把它们放在那里。没有任何程序从访问令牌中读取它们：
不是本提供方（它按 `jti` 查找令牌），也不是
go-fileshare。然而，访问令牌也会被粘贴为 SSH
keyboard-interactive 的答案（ssh-oidc 的 mccli，由 motley-cue 在
`/userinfo` 检查），而 OpenSSH 只读取其中的 1023 个字符；仅 IdP 的 `acr`，
`urn:oasis:names:tc:SAML:2.0:ac:classes:PasswordProtectedTransport`，
就占大约 90 个。在 v0.22.0 之前，访问令牌同时携带两者。

ES256 访问令牌（`access_token_key_file`）在长 eppn 和三个 AARC entitlement
情况下的长度，由 authn-bridge 的 `TestES256AccessTokens` 测量，
使用真实长度的签发方，并对照 RENATER 元数据的 `shibmd:Scope`
长度（743 个 scope）：

| scope 长度 | | 字符数 |
|---|---|---|
| 13 | 中位数 | 885 |
| 22 | 第 95 百分位 | 945 |
| 29 | 第 99 百分位 | 992 |
| 44 | 最长 | **1092：超出** |

在 v0.22.0 之前，同一个令牌为 1014 / 1074 / 1121 / 1221 个字符：从
第 95 百分位起就超出了。仍然放不下的是最长的 scope，
尤其是许多组：每个 entitlement 都会加上其完整的 URN，而且没有任何东西
限制 IdP 发送多少个。用 3072 位密钥签名的 RS256 访问令牌，在
没有任何组的情况下就有大约 1150 个字符，因此用于 SSH 的令牌
使用 ES256 签名。超过 1023 个字符时，mccli 会改为向 motley-cue 索要一次性
密码，motley-cue 默认允许这样做；粘贴到普通
`ssh` 中的令牌则必须放得下。

**对提出要求的客户端不含组**（v0.23.0）。每个组都会加上其完整的
URN，而且没有任何东西限制 IdP 发送多少个，因此没有任何密钥和任何签名
算法能够确保携带组的令牌一定放得下。`access_token_groups = false`
的客户端得到的访问令牌不含人员的 `groups`：

```hcl
client "oidc-agent" {
  device              = true
  audience            = ["ssh"]
  access_token_groups = false
}
```

它面向 ssh-oidc：oidc-agent 获取令牌，mccli 将其作为
keyboard-interactive 的答案粘贴，而 motley-cue 在 `/userinfo` 检查它并在那里读取
组。由 authn-bridge 的 `TestAccessTokenWithoutGroups` 测量，对于属于 50 个组的人员，
在最长的 RENATER scope（44）和真实长度的签发方情况下，
ES256 令牌为 732 个字符。

针对测试联邦，一个属于三个组的人员通过该客户端用设备授权登录：

```
$ authn-bridge token --issuer http://127.0.0.1:28473 --client oidc-agent --scope "openid eduperson groups" --cache var/tokens.json > at
To log in, open http://127.0.0.1:28473/device
and enter the code ZNBP-NMXM
(or open http://127.0.0.1:28473/device?user_code=ZNBP-NMXM)
$ tr -d '\n' < at | wc -c
     625
```

令牌指明了人员及其 IdP，但没有任何组：

```
$ cut -d. -f2 at | tr "_-" "/+" | jq -R "@base64d | fromjson"
{
  "aud": "ssh",
  "client_id": "oidc-agent",
  "exp": 1793017858,
  "iat": 1793014258,
  "idp": "https://idp.univ-example.example/idp/shibboleth",
  "iss": "http://127.0.0.1:28473",
  "jti": "T1qu1-IjIqirgQedQ6hkQCUfeM0OFANOESdXKc3yrJA",
  "preferred_username": "alice@univ-example.example",
  "scope": "openid eduperson groups",
  "sub": "UmCstEtvM1rTavlxDxNPVw-jCNFAZhdRXU405Uz985o"
}
```

`/userinfo` 仍然提供这些组，作为 `groups`（scope `groups`）和
`eduperson_entitlement`（scope `eduperson`）：

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
  "sub": "UmCstEtvM1rTavlxDxNPVw-jCNFAZhdRXU405Uz985o",
  "voperson_id": "a1b2c3@univ-example.example"
}
```

**默认值仍为 `true`。** go-fileshare 与任何仅凭令牌
作出决定的资源服务器一样，需要令牌中带有组：只有在令牌
发往读取 `/userinfo` 的服务器的客户端上，才省略它们。

**与证书并用时被拒绝。** SSH 和 X.509 证书从访问令牌中获取人员的
组，因此带有 `access_token_groups = false`
以及 `ssh_certificates` 或 `x509_certificates` 的客户端，会签发不含
任何组的证书，而按组授权的服务器会拒绝该人员，
却没有任何地方说明原因。`check` 与服务器在启动时一样，会拒绝
这种组合：

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

请为证书使用一个客户端，为粘贴到 ssh 中的令牌使用另一个客户端。

带有提供方自身 scope（`ssh`、`nfs`、
`app_password`、`wireguard`、`wireguard_peers`）之一的令牌**只发往提供方**：
其 `aud` 是签发方，这些端点会拒绝其他任何令牌。资源服务器
收到的令牌无法在此重放：

```
$ curl -s -X POST http://127.0.0.1:28473/ssh/certificate -d x -D - -o -
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Www-Authenticate: Bearer error="invalid_token"
X-Content-Type-Options: nosniff
Date: Mon, 26 Oct 2026 11:36:20 GMT
Content-Length: 23

the token is not valid
```

已经发放的访问令牌是资源服务器自行检查的签名声明。
[`RevokePerson`]({{< relref "/authn-bridge/admin.md" >}})终止的是
带着它回到这里的一切；资源服务器通过
[Shared Signals]({{< relref "/authn-bridge/revocation.md#shared-signals" >}})得知。

## 没有浏览器：设备授权 {#without-a-browser-the-device-grant}

WebDAV 客户端、脚本、终端都没有可以把人带到大学登录页的浏览器。
带有 `device = true` 的客户端会索要代码（RFC 8628），人员在任何其他设备上
登录：

```hcl
client "rclone" {
  device           = true
  audience         = ["fileshare"]
  refresh_lifetime = "720h"     # refresh tokens, off unless set
  name             = "rclone (WebDAV)"
}
```

`authn-bridge token --issuer https://login.example.org --client rclone` 输出
一个访问令牌，第一次时登录，之后则刷新；它使用的是
golang.org/x/oauth2 的设备客户端，而不是这里编写的。

| | |
|---|---|
| 用户代码 | 取自 `BCDFGHJKLMNPQRSTVWXZ` 的八个字母（没有元音，没有数字），有效期十分钟；在此期间每个主机（IPv4 地址、IPv6 /64）最多允许十个**错误**代码，其周围的 /24 或 /48 则允许十倍之多 |
| 轮询 | 每五秒一次；轮询更快会得到 `slow_down` |
| 等待中的设备 | 最多 20,000 个；超过后最旧的会被挤出，而不是拒绝所有人 |
| 刷新令牌 | 每次使用都会轮换，位于一个在登录时由 `refresh_lifetime` 固定其终点的族之中；已退役的令牌被再次使用会吊销该族及其所换取的访问令牌 |

## 应用密码 {#application-passwords}

NTLMv2 和 SigV4 证明的是服务器必须已经持有的秘密，因此没有任何令牌
适用于 SMB 或 S3。带有 `app_passwords = true` 的客户端允许带有
`app_password` scope 的令牌设置一个，生成后只显示一次：
`authn-bridge app-password --issuer ... --client files`（`--remove` 将其删除）。

```hcl
app_passwords {
  driver   = "sqlite"          # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/apppw.dsn"
  store    = ["nt_hash"]       # the default, SMB only; add "password" for S3
  lifetime = "2160h"           # the default, 90 days
  # table  = "app_passwords"   # the default
}
```

该表在缺失时创建：`login, password, nt_hash, expires, idp`。
只存储协议所需的内容：SMB 用的 NT 哈希，仅当 `store` 要求时才存储
密码本身。go-fileshare 用 `users "sql"` 块读取它；
请在其查询中写明列名，绝不要用 `*`。

禁用某人会移除其密码；禁用某机构会移除该机构所有人员的密码。被移除的密码
在 go-fileshare 下次读取其目录时失效。

## WireGuard 密钥 {#wireguard-keys}

WireGuard 仅凭公钥认证对端，别无其他：没有
证书，没有过期，没有吊销。因此提供方保存着对
*这把密钥是谁的，它是否仍可连接？* 的回答。设备的 VPN 客户端
为一段租期注册公钥；私钥从不离开设备；
网关读取有效密钥，其形式是仅为它签名的列表。

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
| `POST /wireguard/key` | `{"public_key": "...", "device": "laptop"}`，带有 `wireguard` scope 的令牌；答复租期的结束时间 |
| `DELETE /wireguard/key` | `{"public_key": "..."}`：所有者收回一把密钥 |
| `GET /wireguard/peers` | 使用网关自己的 `client_credentials` 令牌，scope 为 `wireguard_peers`：一个类型为 `wireguard-peers+jwt` 的签名 JWT，发往该网关，有效期五分钟 |

别人持有的密钥、已被收回的密钥，以及超出数量上限的密钥，都会被
以 `409` 拒绝。网关客户端必须是机密客户端，并且必须指名
具有 `wireguard_keys` 的客户端。列表的格式以及网关一侧的内容
属于 go-authn/wireguard。

## OpenPubkey 与 opkssh {#openpubkey-and-opkssh}

opkssh 把 ID 令牌变成 SSH 登录，完全不需要 CA，而它所生成的令牌
（PK Token）比其中的 ID 令牌存活更久。提供方在授权码流程和设备流程中原样返回
`nonce`，使用 RS256 签名，并且只要 `retired_signing_key_files` 指名了某把
已退役的密钥，就会一直**发布**它，使轮换之前签名的
PK Token 仍然可以验证：

```hcl
retired_signing_key_files = ["/var/lib/authn-bridge/oidc-2026-03.key"]
```

请给 opkssh 一个专属的客户端并设置 `id_token_claims = true`：它根据 PK Token 的声明
匹配人员，而它的 ID 令牌会传到它所登录的每台服务器。
