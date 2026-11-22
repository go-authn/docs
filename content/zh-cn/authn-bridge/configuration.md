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

### `kerberos` 块 {#the-kerberos-block}

有了 `kerberos` 块,`kerberos_tickets = true` 的客户端就能为没有密码的人获取
Kerberos TGT(`POST /kerberos/tgt`):网桥通过双向认证的 TLS 向领域的 KDC 发出请求。

```hcl
kerberos {
  kdc_url   = "https://kdc.internal.example.org:8443/mint"  # https only
  ca_file   = "/etc/authn-bridge/kdc-ca.pem"                # signed the KDC's certificate
  cert_file = "/etc/authn-bridge/bridge-client.pem"         # URI name = what the KDC lists
  key_file  = "/etc/authn-bridge/bridge-client.key"
  validity  = "10h"                                         # at most ten hours
}
```

`check` 用一行报告该块:客户端证书的名称、到期的 UTC 日期和票据的有效期。

```
kerberos      https://kdc.internal.example.org:8443/mint, client certificate https://login.example.org until 2029-02-12, validity 10h
```

加载配置(因此 `check` 和服务器都一样)时,会指出字段名并拒绝首次登录时无法工作的内容:
已过期(与 `kdcd check` 对其签发证书的检查相同)或尚未生效的客户端证书、
不属于 `cert_file` 的 `key_file`、缺失或不含证书的 `ca_file`、
不是 `https` 的 `kdc_url`、超出范围的 `validity`。没有该块的配置不输出任何内容。

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

**数据库拒绝某一行时提供方怎么做**（v0.23.11 和 v0.23.12）。删除始终会
送达：排队等待删除的刷新令牌族或访问令牌，即一次吊销，即使在它之前排队的
某次写入被拒绝，也会到达数据库（此前，一个被拒绝的行会使之后的每次刷新都
停下，提供方一直处于未就绪状态，直到重启重新加载了本应被吊销的内容）。
数据库永久拒绝的行（约束、类型不匹配、值过大：PostgreSQL SQLSTATE 类别 22 或
23，MySQL 1048、1062、1264、1265、1292、1366、1406、1452，SQLite 的 constraint、
mismatch、too big）会被记录一次并被**放弃**：它在内存中继续有效，但无法在
重启后保留。因任何分类器都不认识的错误而被拒绝的行会被重试，并在至少三十秒内
经过五次刷新后以同样方式被放弃，条件是在此期间该行持续失败，而数据库接受了
别的东西（一次写入、一次删除或一次空操作探测）。一次刷新中什么都没有成功，
即数据库不在，不会计入任何一行，因此**中断不会放弃任何东西**。每个被放弃的行都
计入 `bridge_state_rows_rejected_total{kind}`，`kind` 为操作（`write`）；它的
上升需要运维人员去解读，因为被放弃的内容在重启后将不会存在。

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

## `mail`

自 v0.32.0 起。通行密钥总是可以取消待处理的删除请求，因此持有一把密钥的窃贼可以用它取消所有者用另一把密钥提出的删除请求。
只有通过一个不持有此人任何通行密钥的渠道发出通知，所有者才能看到。有了 `mail` 块，当通行密钥的删除被请求或被取消时，
网桥会向**账户自己的地址发送一封纯文本电子邮件**
（[运维人员看到什么]({{< relref "/authn-bridge/admin.md#passkey-removal-notices" >}})）。
没有 `mail` 块时，一切照旧。

```hcl
mail {
  host          = "smtp.example.org"
  security      = "tls"                      # "tls" (port 465, the default) or "starttls" (587)
  username      = "authn-bridge"
  password_from = "systemd-creds:smtp"       # a secretsource reference, never the password
  from          = "authn-bridge@example.org"
  # window      = "10m"                      # least time between two mails to one account
}
```

`password_from` 是一个 [secretsource](https://github.com/go-authn/secretsource)
引用：`systemd-creds:NAME`、`file:PATH`（仅所有者可读的普通文件，
`0600`）、`keychain:SERVICE/ACCOUNT`，以及 secretsource 的其他方案。
密码是一行非空内容，至多 4096 字节，并且不会从其他任何地方读取：
不是环境变量，不是命令行，也不是配置文件本身。没有方案的引用、过大或
多行的密钥、权限过宽的文件，以及缺少 `username` 和
`password_from` 的 `mail` 块，在启动时都会被拒绝。

`password_file = "PATH"` 仍然可用，但已**弃用**：它被当作
`password_from = "file:PATH"` 读取。同时设置两者是配置错误。

`file:` 会拒绝符号链接，也会拒绝属于运行 bridge 的用户之外其他用户的文件。
由 systemd 传递的凭据应使用 `systemd-creds:NAME` 读取，绝不要使用
`file:$CREDENTIALS_DIRECTORY/NAME`。

在 systemd 主机上，把密码封存到本机，并作为凭据交给服务：

```sh
printf %s 'the-smtp-password' | sudo systemd-creds encrypt --name=smtp \
  --with-key=host+tpm2 - /etc/credstore.encrypted/smtp.cred
```

```ini
# systemctl edit authn-bridge
[Service]
LoadCredentialEncrypted=smtp:/etc/credstore.encrypted/smtp.cred
```

请使用 `--with-key=host+tpm2`，不要带 `--tpm2-pcrs`：密钥由 TPM2
芯片和主机密钥文件派生，在固件和 Secure Boot 更新后依然有效。
不要单独使用 `--tpm2-pcrs=7`：固件或 shim 更新会使
凭据无法读取，网桥将拒绝启动。

**恢复。** 一旦丢失 TPM2 芯片或
`/var/lib/systemd/credential.secret`，凭据也随之丢失，解密失败会使网桥在
启动时停止。请把密码保存在不依赖这台机器的地方
（离线副本），用上面的命令从该副本重新封存，然后
`systemctl restart authn-bridge`。

- **通知谁。** 本地账户文件中该账户的 `mail`，以网桥所知为准，绝不使用取自请求的地址。该块需要 `local` 块：
  通知针对的是本地账户的通行密钥。
- **始终使用 TLS。** 隐式 TLS，或服务器提供并完成的 STARTTLS（否则不发送通知：绝不进行明文会话）。
  服务器证书按系统根证书和主机名验证。网桥只在 TLS 建立之后才进行认证（PLAIN，否则 LOGIN），
  绝不通过明文，即使对 127.0.0.1 也是如此；在 TLS 之后不宣告任何可用机制的服务器会被拒绝。
- **没有链接。** 正文不含可点击的 URL，并说明这一点，同时告诉读者从自己的书签打开账户页面。
  含有 CR、LF 或其他行分隔符的标头值会被拒绝。
- **频率限制。** 每个账户在每个 `window`（默认 `10m`）内最多一封邮件；其间到达的事件合并为一份摘要，在窗口结束时发送。

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
