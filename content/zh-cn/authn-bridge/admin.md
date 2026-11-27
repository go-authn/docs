---
title: "管理 API、健康检查和指标"
linkTitle: "管理 API"
weight: 70
description: "通过 authn-bridge 的 gRPC 管理 API 禁用人员或机构，以及它旁边的健康检查和指标端点。"
tags: [authn-bridge, 管理, grpc, 指标]
---

除非配置要求，否则两者都是关闭的，并且都绝不会出现在
公共监听器上。

```hcl
admin {
  listen = "unix:///run/authn-bridge/admin.sock"   # mode 0600
  # or over the network, mutual TLS and nothing less (loopback included):
  # listen         = "10.0.0.5:9443"
  # tls_cert_file  = "/etc/authn-bridge/admin.crt"
  # tls_key_file   = "/etc/authn-bridge/admin.key"
  # client_ca_file = "/etc/authn-bridge/operators-ca.crt"
  # reflection     = true                          # for grpcurl; off by default
}

metrics { listen = "127.0.0.1:9101" }              # /healthz /readyz /metrics

disabled_file = "/var/lib/authn-bridge/disabled.json"
```

该监听器来自 grpc-transports/control，与 go-fileshare 共用。套接字
不会被其他用户访问，即使在 bind 与 chmod 之间也不会，并且
绝不会从仍在运行的实例手中夺取。没有全部三个 TLS 文件的 TCP 会
被拒绝，环回地址也不例外，因为每个本地用户都可以访问 `127.0.0.1`：

```
authn-bridge: admin: control: listen address "127.0.0.1:9443" is TCP, which requires mutual TLS (loopback included: any local user can reach it); missing TLSCertFile, TLSKeyFile, ClientCAFile
```

用 `-tags nogrpc` 构建的二进制文件没有管理 API，并且会拒绝带有
`admin` 块的配置，而不是在没有它的情况下启动。

## 服务 {#the-service}

`bridge.admin.v1.AdminService`（`proto/bridge/admin/v1/admin.proto`），旁边是
`grpc.health.v1`，它在提供方就绪时报告 `SERVING`。

| | |
|---|---|
| `Status` | 版本、签发方、启动时间；联邦的元数据（IdP、可用数量、有效期至、上次刷新、上次错误）；内存中保存的内容 |
| `RefreshMetadata` | 立即获取联邦的元数据，并说明结果如何 |
| `ListIdPs` | 联邦的 IdP，与机构列表所显示的一致（`query`、`limit`，默认 100） |
| `ListClients` | 已配置的依赖方 |
| `RevokePerson` | 终止其刷新令牌族、由此获得的访问令牌、进行中的登录和设备授权，以及其应用密码，并吊销证书存储中为其保存的一切：SSH 和 X.509 证书（进入下一个 KRL 和 CRL）以及 WireGuard 密钥 |
| `DisablePerson`、`EnablePerson` | 在此处拒绝某人，包括登录时和每个令牌上，无论其机构怎么说，并吊销其所持有的内容；可选地设置 `until` 时间 |
| `DisableIdP`、`EnableIdP` | 对某一机构所担保的所有人做同样的事；元数据刷新不会解除它 |
| `ListDisabled` | 谁被禁用、原因、由谁禁用、从何时起、到何时为止 |

把一个 IdP 从 `saml { idps }` 中移除，会像 `DisableIdP` 一样终止它所担保的一切（自 v0.23.7 起）：
新的登录被拒绝，经由它而来的人的每一项授权也会在下次使用时以 `institution not configured` 被拒绝，
包括刷新令牌（即使跨越重启）、应用密码和 SSH 证书请求。把 IdP 放回去，它们就重新可用；无需吊销任何东西。

设置 `reflection = true`，针对测试提供方：

```
$ grpcurl -plaintext -unix $PWD/run/admin.sock bridge.admin.v1.AdminService/Status
{
  "version": "v0.23.4",
  "issuer": "http://127.0.0.1:28473",
  "started": "2026-10-26T11:22:17.441725Z",
  "federation": {
    "metadataUrl": "file:///tmp/authn/fed/metadata.xml",
    "idps": 1,
    "usable": 1,
    "validUntil": "2026-11-02T11:22:16Z",
    "lastRefresh": "2026-10-26T11:22:17.442875Z"
  },
  "counts": {}
}
```

## 禁用 {#disabling}

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example","reason":"left the lab"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
{
  "disabled": {
    "username": "alice@univ-example.example",
    "reason": "left the lab",
    "by": "uid=501",
    "since": "2026-10-26T11:22:17.952680Z"
  },
  "revoked": {}
}
$ grpcurl -plaintext -unix -d '{"entity_id":"https://idp.univ-example.example/idp/shibboleth","reason":"compromised","until":"2026-11-27T08:00:00Z"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisableIdP
{
  "disabled": {
    "entityId": "https://idp.univ-example.example/idp/shibboleth",
    "reason": "compromised",
    "by": "uid=501",
    "since": "2026-10-26T11:21:27.038956Z",
    "until": "2026-11-27T08:00:00Z"
  },
  "revoked": {}
}
```

`revoked` 统计每次调用所终止的内容（刷新令牌族、访问令牌、登录、
应用密码、证书）；这里没有任何有效内容。每个
改变了某些内容的调用都会记录日志，说明是谁发起的：套接字上对端的 `uid=`，
或 TLS 上客户端证书的 `cn=`：

```
disabled alice@univ-example.example (0 known identities) by uid=501 until enabled again: left the lab
revoked alice@univ-example.example: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
disabled IdP https://idp.univ-example.example/idp/shibboleth by uid=501 until 2026-11-27T08:00:00Z: compromised
revoked IdP https://idp.univ-example.example/idp/shibboleth: 0 refresh families, 0 access tokens, 0 logins, 0 app passwords, 0 certificates
enabled alice@univ-example.example by uid=501
```

**人员是按其真实身份被禁用的。** 用户名的比较不区分大小写，
eppn、uid、mail 和 subject-id 都是如此，因此用
`"Alice@Univ-Example.example"` 发出的同一调用会解除为 `alice@univ-example.example`
设置的禁用（`{"wasDisabled": true}`）。该条目还会记录
以该名称为人所知的所有人的稳定身份，因此其 IdP 给出的另一种写法不会让
他们重新进入。不含 `@` 的名称也会作为 `sub` 进行匹配，用于其
IdP 不释放用户名的人员。

条目在吊销任何内容**之前**记录，因此与吊销竞争的授权
会遇到该条目。

**名称只折叠 ASCII 字母**（自 v0.23.8 起）。禁用列表、证书主体和 subject-id 用 go-authn/oidc 的 `ASCIILower` 比较用户名，因此开尔文符号（U+212A）不是 "k"：`kate` 和带开尔文符号的写法是两个人，有两个禁用条目和两个证书主体。禁用其中一个不会禁用另一个。

**禁用保存在 `disabled_file` 中，没有它则会被拒绝。** 禁用到下一次
重启为止的人员，会被下一次部署放回来：

```
$ grpcurl -plaintext -unix -d '{"username":"alice@univ-example.example"}' $PWD/run/admin.sock bridge.admin.v1.AdminService/DisablePerson
ERROR:
  Code: FailedPrecondition
  Message: disabling needs disabled_file in the configuration: without it, a restart would forget who is disabled
```

无法读取的文件会因同样的原因使提供方无法启动。被禁用的机构在
`Status`、`ListIdPs` 和
[`check`]({{< relref "/authn-bridge/configuration.md#check-before-a-restart" >}})中都算作不可用。

禁用在提供方之外产生的影响见
[吊销]({{< relref "/authn-bridge/revocation.md" >}})：证书使用 KRL 和
CRL，令牌使用 Shared Signals。在此处移除的应用密码，
会在 go-fileshare 下次读取其目录时失效；
请在 `DisablePerson` 之后调用其 `ReloadDirectory`，以使效果立即生效。

{{< callout type="warning" >}}
**`RevokePerson` 无法终止的内容**

已经发放的访问令牌是资源服务器自行检查的签名声明，
在那里直到过期之前都有效（默认一小时）。已经签发的
SSH 证书在其有效期内一直有效，除非服务器读取
KRL，这正是两者都很短的原因。
{{< /callout >}}

## 通行密钥删除通知 {#passkey-removal-notices}

有了 [`mail` 块]({{< relref "/authn-bridge/configuration.md#mail" >}})（自
v0.32.0 起），当通行密钥的删除被请求或被取消时，本地账户会在其自己的地址收到通知，
这样持有一把密钥的窃贼就无法悄悄取消所有者的删除请求。它**只涉及本地账户**，
通知为每个账户在每个 `window`（默认 10 分钟）内一封邮件：其间到达的事件合并为一份摘要。
运维人员看到什么取决于事件：

- **发不出通知的删除请求保持待处理。** 延迟结束时它不会被执行。网桥会重试（5 次，间隔逐渐变长），
  然后输出醒目的 `GAVE UP` 日志；重启会让它继续，下一个事件也会。其间该密钥照常可用。
  在通知送达之前，记录带有 `notice_pending`。
- **取消即使邮件失败也会生效。** 失败会被记入日志（`mailing <login> failed`），并显示在账户页面上，
  页面会说明通知无法发送。
- **没有可用地址的账户**不会被阻止：其删除照常进行，与没有 `mail` 块时一样，日志会写
  `<login> has no usable mail address ... nobody is told`，账户页面也会说明。

没有 `mail` 块时，一切照旧。

## 日志与本地账户 {#journal-and-local-accounts}

自 v0.37.0 起，每次成功登录都会在日志中留下一行，且任何一行都不含机密：不会输出
代码、令牌、断言、邮箱地址、姓名或组。

```text
login: <username> via <idp entityID> for <client_id> from <address>
login: <login> via <issuer>/local with passkey <8 hex> for <client_id> from <address>
account: <username> confirmed through <idp entityID> from <address>
account: audit: <login> stepup <16 hex> from <address>
token: authorization_code issued to <client_id> for <username>
token: refresh_token issued to <client_id> for <username>
```

前两行是授权端点上的登录，分别经由机构和使用本地通行密钥（`<8 hex>` 是通行密钥的
ID，与 `local: <login> enrolled a passkey (<8 hex>)` 所打印的相同）。接下来两行是
账户页面的登录，分别经由机构和使用通行密钥。最后两行是发给客户端的令牌。

当账户目录为 `root:authn-bridge` 0750、文件为 0640（文档中的布局）时，请以 **root**
身份运行 `authn-bridge local-account …`：该命令通过旁边的临时文件来替换账户文件，
以 `authn-bridge` 身份运行会失败，报
`open /etc/authn-bridge-local/.accounts-NNN: permission denied`。它会保留文件的所有者
和权限。经由 SSH 运行时，`ssh host sudo authn-bridge local-account … --name "Two words"`
需要再加一层引号（`--name '"Two words"'`），因为 ssh 会把参数拼成一个字符串，由远端
shell 再次拆分。

## 客户端接受哪些账户 {#client-accounts}

自 v0.38.0 起，`client` 块可以只接受一种人：

```hcl
client "forgejo" {
  secret_file   = "/etc/authn-bridge/forgejo.secret"
  redirect_uris = ["https://git.example.org/user/oauth2/bridge/callback"]
  accounts      = ["local"]   # "local", "federated", or both (the default)
}
```

`accounts = ["local"]` 适用于要求硬件密钥的服务：SAML 机构的人会被拒绝。这条规则
不只在提供登录的地方成立，而是在每一个授予或使用授权的地方都成立。授权端点只把人
送往客户端接受的那一条路径（对仅限本地账户的客户端使用 `prompt=none` 会返回
`login_required`）；联盟步骤、通行密钥步骤和登录结束处各自拒绝另一种登录；
授权码兑换、刷新和设备轮询也拒绝另一种人，因此在写入限制之前取得的授权会随限制
一并失效。响应为 `access_denied`：登录期间发往客户端的重定向 URI，之后由令牌端点
返回。`authn-bridge check` 在客户端那一行打印该限制，`local` 需要 `local` 块，
`bridge_logins_total{result="wrong_account_kind"}` 统计被拒绝的次数。日志会说明原因：

```text
login: <username> via <idp entityID> refused for <client_id>: this client takes local accounts only
token: account kind not accepted by this client: <why> (<username> via <idp> for <client_id>)
```

已知限制：证书端点（SSH、X.509、Kerberos、WireGuard）不与任何客户端绑定，
因此 `accounts` 不适用于它们。

## 从网页发出邀请的管理员 {#web-invitations}

自 v0.39.0 起，管理员无需主机上的 shell，即可在 `/account/invite` 邀请本地账户
（登录名、电子邮件地址、可选的姓名）。这与命令行的邀请相同，链接只通过电子邮件
发给被邀请的人。管理员在 `local` 块中指定，并附上他们可使用的认证器型号：

```hcl
local {
  admins        = ["alice"]
  admin_aaguids = ["9dd8d593-2213-438a-97f8-d6b813d51c27"]
  mds_dir       = "/var/lib/authn-bridge/mds"
  admin_min_certification = "L2"   # optional
}
```

该页面需要 `mail` 块、不超过三分钟的用户验证断言和 CSRF 令牌；每位管理员每小时
最多邀请十个账户。管理员通行密钥的型号必须是**被证明**的，而不是自报的：注册时
向浏览器请求 direct 证明，由 go-authn/webauthn v0.5.0 验证（带 `x5c` 证书链的
`packed` 声明，其证书须带有与认证器 AAGUID 相等的 `id-fido-gen-ce-aaguid` 扩展；
`self` 和 `none` 能通过验证，但不证明任何型号，缺少该扩展的证书同样不能），再通过
go-authn/fido v0.16.0 的 `mds` 与 FIDO MDS3 元数据核对该型号。到这一步，bridge
才记录型号，页面也只读取这一项。此后被元数据报告为已撤销或已泄露的型号，不再能
打开该页面。未能证明型号而注册的密钥仍可登录，但打不开任何东西。

**最低认证级别。** `admin_min_certification`（可选；`"L1"`、`"L1plus"`、`"L2"`、
`"L2plus"`、`"L3"` 或 `"L3plus"`，其他值是配置错误，没有 `admins` 时会被拒绝）
是管理员通行密钥的型号至少应具备的 FIDO 认证级别，读取自同一份 MDS3 元数据。
顺序以规范为准（MDS 3.1 §3.1.4.1）：L1 < L1plus < L2 < L2plus < L3 < L3plus。
级别指型号的*当前*级别：已生效的最新 `FIDO_CERTIFIED_Lx` 状态报告（§3.1.3）。
没有这类报告的型号（旧的 `FIDO_CERTIFIED` 不计入任何级别）无法满足任何最低
要求。与已撤销、已泄露状态一样，它在注册时**以及每次打开页面时**检查：型号
之后被降级到最低要求以下或被撤销，仍可登录，但不再能打开管理员页面。未设置时
不要求任何级别。自 authn-bridge v0.41.0（go-authn/fido v0.17.0）起可用。

元数据保存在 `mds_dir` 中。该项可选，默认值为 `/var/lib/authn-bridge/mds`，必须
是绝对路径，没有 `admins` 时会被拒绝。下载由后台 goroutine 完成，从不在请求中
进行。主机需要：

- 服务可写的目录（`mds_dir`；默认以外的路径必须列入单元的 `ReadWritePaths=`）；
- 到 `mds3.fidoalliance.org` 的出站 HTTPS，以及到其证书的 CRL 分发点的出站明文
  HTTP；
- 正确的时钟。

服务在没有元数据时也能启动并重试；在元数据到位之前，没有管理员密钥被证明，
页面会拒绝。

**重新注册管理员的密钥。** v0.39.0 之前注册的密钥没有经过验证的证明。对每位
管理员：用现有密钥登录，打开 `/account`，用密钥确认，然后用允许的认证器（例如
YubiKey Bio）添加通行密钥，并接受浏览器关于分享其品牌和型号的提示。回应必须
显示 `attested: true`；此后 `/account/invite` 即可使用。之后删除旧密钥。

## 健康检查和指标 {#health-and-metrics}

来自 go-net-health/endpoint，与 go-fileshare 相同，位于 `metrics` 监听器上，该监听器
不得是公共监听器（使其成为公共监听器的配置会被拒绝）：

| | |
|---|---|
| `/healthz` | 进程能应答时即为正常 |
| `/readyz` | 联邦的元数据已加载且在其 `validUntil` 之内，并且没有等待写入状态数据库的吊销时即为就绪 |
| `/metrics` | Prometheus 文本，`bridge_*` 系列 |

```
$ curl -s http://127.0.0.1:28475/metrics | grep "^bridge_"
bridge_build_info{version="v0.23.4",goversion="go1.27.3",revision="6e0156cb516ace9091d4070c425258febc48f6ee"} 1
bridge_start_time_seconds 1793013737
bridge_ready 1
bridge_metadata_valid_until_timestamp_seconds 1793618536
bridge_metadata_idps 1
bridge_metadata_last_refresh_timestamp_seconds 1793013737
bridge_metadata_refreshes_total{result="failed"} 0
bridge_metadata_refreshes_total{result="ok"} 1
bridge_logins_in_progress 0
bridge_devices_waiting 0
bridge_refresh_families 0
bridge_access_tokens 0
bridge_disabled{kind="idp"} 0
bridge_disabled{kind="person"} 0
bridge_ssh_certificates_total 0
bridge_x509_certificates_total 0
```

按结果统计的登录计数器（`bridge_logins_total`）、按授权类型统计的令牌计数器
（`bridge_tokens_issued_total`）和应用密码计数器
（`bridge_app_passwords_total`）只有在统计到某些内容之后才会出现。**没有任何标签指名人员或机构**：哪些
大学的人员使用该服务，以及何时使用，不应由提供方来
公布。请在 `bridge_metadata_valid_until_timestamp_seconds` 所给出的
时间到达之前设置告警：过了这个时间，没有人能够登录。
