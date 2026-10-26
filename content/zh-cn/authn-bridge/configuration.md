---
title: "配置"
linkTitle: "配置"
weight: 20
description: "authn-bridge 的 HCL 配置如何组织、check 输出什么，以及在任何人能够登录之前什么会被拒绝。"
tags: [authn-bridge, 配置]
---

一个 HCL 文件，或一个包含若干 HCL 文件的目录：`--config /etc/authn-bridge` 会读取其中的每个
`*.hcl` 文件，按名称顺序合并，并且 `--config` 可以多次给出。
配置在启动时读取，之后不再读取。

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

必需的有 `issuer`、`signing_key_file`、`subject_salt_file`、带有上述五个键的 `saml`
块，以及至少一个 `client`。其他一切都有
默认值或默认关闭。

## `check`，重启之前 {#check-before-a-restart}

`check` 像服务器一样读取配置，加载其所指名的每个密钥，**获取联邦的元数据**，
并说明将要提供什么服务：

```
$ authn-bridge check --config etc/bridge.hcl
issuer        http://127.0.0.1:28473
SAML entity   http://127.0.0.1:28473/saml
tls           none (a reverse proxy in front)
federation    1 IdPs, 1 usable here, valid until 2026-11-02T11:21:58Z
client        sftp (public, public subject, audience [sftp])
client        efp (public, public subject, audience [efp])
client        nfs (public, public subject, audience [nfs])
```

*此处可用*不包括 `saml { idps }` 没有列出的 IdP，也不包括被
[管理 API]({{< relref "/authn-bridge/admin.md" >}})禁用的 IdP：禁用上述
机构之后，同一命令输出
`federation    1 IdPs, 0 usable here`。联邦没有列出的
`idps` 条目会在这里被拒绝，尽管服务器带着它也能启动：

```
federation    1 IdPs, 0 usable here, valid until 2026-11-02T11:30:52Z
authn-bridge: idps names "https://idp.nowhere.example/idp", which the federation does not list
```

`authn-bridge metadata` 输出要向联邦注册的 SAML 元数据。参见
[联邦一侧]({{< relref "/authn-bridge/federation.md" >}})。

## 顶层 {#the-top-level}

| 键 | 默认值 | |
|---|---|---|
| `issuer` | | 提供方的名称，也是每个 URL 的基础。`https`，测试时可在环回主机上用 `http`；没有查询，没有片段；末尾的 `/` 会被去掉 |
| `listen` | `127.0.0.1:8080` | 公共监听器 |
| `cert_file`、`key_file` | | 用这些文件提供 TLS，文件更改时重新读取；要么一起设置，要么都不设置 |
| `acme` | | 改用来自 ACME CA 的证书提供 TLS（见下文）；不能与 `cert_file` 并用 |
| `signing_key_file` | | RSA，为 ID 令牌签名（RS256）；此处的 P-256 密钥会被拒绝 |
| `access_token_key_file` | 签名密钥 | 以 ES256 为访问令牌签名的 P-256 密钥；如果它就是签名密钥则被拒绝 |
| `retired_signing_key_files` | | 以前用于签名的密钥：仍在 `/jwks` 发布，但绝不用于签名 |
| `subject_salt_file` | | 至少 32 字节 |
| `code_lifetime` | `1m` | 至多十分钟（RFC 6749 4.1.2） |
| `token_lifetime` | `1h` | 访问令牌 |
| `id_token_lifetime` | `5m` | ID 令牌 |
| `trusted_proxies` | | 其 `X-Forwarded-For` 被信任的地址或前缀 |
| `requests_per_minute` | `120` | 一个地址每分钟可以发起的登录、设备授权和 ACS 提交次数；`0` 表示关闭限制 |
| `disabled_file` | | 保存被禁用人员和机构的位置；没有它，禁用会被拒绝 |
| `certificates_file` | | 签发的每个证书和 WireGuard 密钥；与 `ssh_ca`、`x509_ca` 或 `wireguard` 并用时必需 |

各个块：

| 块 | 页面 |
|---|---|
| `saml`、`claims` | [联邦一侧]({{< relref "/authn-bridge/federation.md" >}}) |
| `client` | 见下文，以及[令牌]({{< relref "/authn-bridge/tokens.md" >}}) |
| `state` | 见下文 |
| `ssh_ca`、`x509_ca` | [证书]({{< relref "/authn-bridge/certificates.md" >}}) |
| `app_passwords`、`wireguard` | [令牌]({{< relref "/authn-bridge/tokens.md" >}}) |
| `ssf` | [吊销]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |
| `admin`、`metrics` | [管理 API]({{< relref "/authn-bridge/admin.md" >}}) |
| `acme` | 见下文 |

## 客户端 {#a-client}

| 键 | 默认值 | |
|---|---|---|
| `secret_file` | | 客户端密钥，至少 16 个字符；缺省则为**公开**客户端 |
| `redirect_uris` | | 精确比较，但环回 URI 可以更改端口（RFC 8252）；`http` 仅限环回 |
| `audience` | 客户端 ID | 其访问令牌所发往的对象；有多个时，可以请求发往其中之一的令牌（[RFC 8707]({{< relref "/authn-bridge/resources.md" >}})） |
| `subject` | `public` | 或 `pairwise`：为此客户端提供不同的 `sub`（OIDC Core 8.1） |
| `name` | 客户端 ID | 显示在设备确认页面上 |
| `device` | `false` | 设备授权（RFC 8628）；这样的客户端不需要重定向 URI |
| `refresh_lifetime` | 关闭 | 刷新令牌，以及它们在**登录**之后多久结束 |
| `pkce` | `required` | 或 `or_nonce`，仅限机密客户端：用 `nonce` 代替 PKCE |
| `id_token_claims` | `false` | 同时把释放的声明复制到 ID 令牌中（opkssh 需要） |
| `access_token_groups` | `true` | `false` 会把人员的组从访问令牌中去掉，适用于粘贴到 ssh 的令牌（[令牌]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})）；与 `ssh_certificates` 或 `x509_certificates` 并用会被拒绝 |
| `ssh_certificates`、`ssh_*` | | [SSH 证书]({{< relref "/authn-bridge/certificates.md#ssh-certificates" >}}) |
| `x509_certificates` | | [NFS 客户端证书]({{< relref "/authn-bridge/certificates.md#x509-client-certificates-for-nfs-over-tls" >}}) |
| `app_passwords` | | 可以设置人员的[应用密码]({{< relref "/authn-bridge/tokens.md#application-passwords" >}}) |
| `wireguard_keys`、`wireguard_peers` | | [WireGuard]({{< relref "/authn-bridge/tokens.md#wireguard-keys" >}}) |
| `ssf_receiver`、`ssf_subject_format` | | [Shared Signals 接收方]({{< relref "/authn-bridge/revocation.md#shared-signals" >}}) |

没有重定向 URI 的客户端必须是设备客户端、SSF 接收方或
WireGuard 网关，否则它就无事可做。

## `state`：重启不得遗忘的内容 {#state-what-a-restart-must-not-forget}

```hcl
state {
  driver   = "postgres"                  # sqlite, postgres or mysql
  dsn_file = "/etc/authn-bridge/state.dsn"
}
```

刷新令牌族、刷新令牌及已退役的刷新令牌、在 `/userinfo` 处和证书签发时被
认可的访问令牌、已经接受的 SAML 断言和已经应答的登录、
SSF 流及其尚未送达的事件：同步写入一张表 `bridge_state`（缺失时创建），
并在启动时读取。刷新令牌以其 SHA-256 保存，绝不保存其本身。
没有该块时，它们保存在内存中，重启会使所有人退出登录。

进行中的登录不在其中。它保存在自己的 cookie 中，用
AES-256-GCM 密封，密钥由主体盐值派生，因此浏览器既
无法读取也无法更改它。

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

证书是为签发方的主机而设。`cache_dir` 保存私钥，
当其他用户可以访问或重新指向该目录时，提供方会拒绝启动。

## 启动时拒绝什么 {#what-is-refused-at-startup}

以下每一项都是 `authn-bridge check` 对提出该请求的配置所输出的内容。
服务器拒绝同样的配置：每一项都是从
配置及其所指名的文件中读出的。`check` 额外增加的唯一一项拒绝是联邦
没有列出的 `idps` 条目，见[上文](#check-before-a-restart)：
服务器在监听之前会获取同样的元数据，但不会用它来
约束 `idps`。

**会泄露的签发方、重定向和密钥：**

```
authn-bridge: issuer "http://login.example.org": an issuer is https (http only on loopback, for testing)
authn-bridge: client "web": redirect URI "http://app.example.org/callback": a code sent over cleartext http is a code anybody on the path has
authn-bridge: client "web": a secret of 5 characters is a password somebody can guess
authn-bridge: code_lifetime = 15m0s: an authorization code lives ten minutes at most
```

**任何机构都可以声称的名称：**

```
authn-bridge: claims: username = "uid" is not held to an IdP's scopes, so any IdP of the federation could name anybody: it needs saml { idps } to list exactly one IdP; with more, use eppn or subject_id
authn-bridge: claims: groups = "affiliation" carries no institution, so any IdP of the federation could grant any of its values: it needs saml { idps } to list exactly one IdP; with more, use scoped_affiliation
```

**签发后永远无法收回的内容：**

```
authn-bridge: ssh_ca: certificates_file is required with ssh_ca or x509_ca: a certificate that is not recorded can never be revoked
authn-bridge: ssh_ca: validity = 200h0m0s: more than a week, and a certificate lives that long on every server its revocation has not reached
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```

**不应当可以访问的监听器：**

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
authn-bridge: metrics: listen is the public listener; metrics have one of their own
```

**同一件事说了两遍的配置：**

```
authn-bridge: saml: an external discovery service lists every IdP; with `idps` restricted, leave `discovery` out and this provider lists them itself
authn-bridge: client "sftp" is declared twice
```

SSH 配置档自身的拒绝见[证书]({{< relref "/authn-bridge/certificates.md#what-the-profile-refuses" >}})，
联邦的拒绝见[联邦一侧]({{< relref "/authn-bridge/federation.md#what-is-refused" >}})。
