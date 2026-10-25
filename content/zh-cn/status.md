---
title: "状态"
weight: 60
description: "这些页面描述哪些版本、每个版本新增了什么，以及哪些功能尚未实现。"
tags: [状态, 发布版本]
---

这些页面是文档版本 **0.4**，描述的内容如下：

| 程序 | 版本 | 模块 |
|---|---|---|
| authnd | **v0.11.1** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.1** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.4** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.7** | `github.com/go-authn/sshcert` |

各个库的版本见[其自己的页面]({{< relref "/libraries/_index.md" >}})；
ldap 为 **v0.9.0**，带有 HCL2 模式和 `ldapschema` 转换器，
directory 为 **v0.14.0**，带有属性以及更宽的 ldapdir 默认值。authnd
v0.11.1 内嵌 ldap v0.8.0 和 directory v0.14.0。
上述任何程序的新次版本号都对应一个新的文档版本，
因此读者在 `/docs/0.4/` 下找到的页面始终描述其所安装的版本；
之前各版本的页面保留在 `/docs/0.1/`、
`/docs/0.2/` 和 `/docs/0.3/` 之下。

## 每个版本新增了什么 {#what-each-release-added}

每一行都是发布该版本所针对的变更。仅更新依赖项的版本不列出，
但本文档版本所描述的除外。

### authnd {#authnd}

| | |
|---|---|
| v0.1.0 | 一个面向存放在别处的人员的 LDAP 服务器：文件、SQL 数据库、另一个目录 |
| v0.2.0 | 第二因素，通过只有一个字段的协议实现 |
| v0.5.0 | 密码变更只涉及恰好一个身份；重新加载不存在竞态；KDC 可以看到变更 |
| v0.6.0 | oidc、directory、ldap、totp 和 mfa 的安全修复 |
| v0.7.0 | 更改密码必须提供旧密码；机密以定长摘要进行比较 |
| v0.8.2 | 代码只有在密码正确时才算数；reader 以其配置的 DN 作为键 |
| v0.9.0 | 使用 Go 1.27.1 构建和测试，固定版本而非 `stable` |
| v0.9.2 | 每个标签都发布二进制文件、`SHA256SUMS` 和构建溯源信息 |
| v0.9.3 | 二进制文件在检出目录之外构建；每个都必须准确报告标签 |
| v0.9.4 | `SIGHUP` 不再终止 authnd：它会被记录，但不会重新加载任何内容 |
| v0.9.5 | 发布时检查**每一个**二进制文件的构建信息，而不是只检查一个 |
| v0.9.6 | `check` 说明每个人为何无法获得票据 |
| v0.10.0 | `check` 像服务器一样打开证书和 keytab；它指出谁无法用密码绑定，以及令牌仍然放行谁；监听行在域打开之后输出 |
| v0.10.1 | go-authn/kdc v0.4.2：`till` 为 19700101000000Z 时获得最长的票据，而不是一张在 1970 年就已过期的票据 |
| v0.10.2 | go-authn/directory v0.12.0：空组发布为不带 `memberUid` 的 `posixGroup` |
| v0.11.0 | [标准模式条目]({{< relref "/authnd/entries.md" >}})，每个条目都受 `cn=Subschema` 所提供的模式约束；`attributes`、`users_attributes` 和 `groups_attributes`；`(uidNumber>=1000)` 按整数比较。⛔ `publish_nt_hash` 需要一个 [`samba` 块]({{< relref "/authnd/tls.md#the-samba-block" >}})，并且按 `posixAccount` 或 `posixGroup` 过滤的使用方看到的条目会变少 |
| v0.11.1 | 启动行只列出有人从中获得服务的来源：没有 `user` 块时，不再列出配置文件 |

### authn-bridge {#authn-bridge}

| | |
|---|---|
| v0.1.0 | 置于 SAML 联邦之前的 OpenID Connect 提供方 |
| v0.2.0 | 设备授权、SSH 证书、应用密码、OpenPubkey |
| v0.3.0 | 管理 API（`bridge.admin.v1`），以及 `/healthz`、`/readyz`、`/metrics` |
| v0.4.0 | ES256 访问令牌 |
| v0.5.0 | 通过与 go-fileshare 共享的 go-authn/servercert 提供 TLS |
| v0.6.0 | 可吊销的证书：SSH KRL，以及配合 CRL 用于 NFS 的 X.509 |
| v0.7.0 | 重启后仍保留的状态：刷新令牌和已认可的访问令牌 |
| v0.8.0 | Shared Signals 发送方：CAEP `session-revoked` |
| v0.9.0 | 针对 v0.8.1 的对抗性审查所作的修复 |
| v0.10.0 | 可在任何地方检查的吊销列表：已签名的 KRL、过期时间、内容的 ETag |
| v0.10.2 | 每次签发都有 CRL 编号；绝不签发早于上一次的日期 |
| v0.11.0 | 组受其身份提供方约束；按身份禁用；仅限 bridge 的受众 |
| v0.12.0 | 进行中的登录保存在其密封的 cookie 中，而不是内存中 |
| v0.13.0 | 机密客户端可以用 nonce 保护其代码（RFC 9700 2.1.1） |
| v0.16.0 | `max_age` 仅在上次认证过旧时才要求重新认证 |
| v0.16.3 | 第二次审查：每种写法都被吊销、按 `sub` 禁用、重启后不再重放 |
| v0.17.0 | WireGuard 密钥，由用户注册并列出供网关使用 |
| v0.18.0 | 不含个人声明的 ID 令牌；go-authn/saml v0.4.0 |
| v0.19.0 | EuroHPC SSH CA 配置档，按客户端选择启用 |
| v0.19.3 | 每个标签都发布二进制文件、`SHA256SUMS` 和构建溯源信息 |
| v0.20.0 | 命令为 `authn-bridge`；加固的 systemd 单元和安装指南 |
| v0.20.1 | 修正已不再正确的注释和拒绝信息；README 列出 `RevokePerson` 所吊销的全部内容 |
| v0.21.0 | [RFC 8707 资源指示符]({{< relref "/authn-bridge/resources.md" >}})：`audience` 指名多个资源服务器的客户端可以请求发往其中一个的令牌。比 v0.20.1 早一小时打标签，v0.20.1 同样包含这些功能，并带有 v0.20.1 的更正，而它没有 |
| v0.21.1 | golang.org/x/net v0.60.0，以修复其 HTTP/2 公告，以及 Go 1.27.2；再次包含 v0.20.1 的更正；占位域名改用 RFC 2606 名称 |
| v0.22.0 | 访问令牌不再携带 `auth_time` 或 `acr`（ID 令牌仍然携带），使 ES256 令牌在 RENATER 的 scope 中直到第 99 百分位都能放入 OpenSSH 的 1023 个字符 |
| v0.22.1 | `resource` 可在授权端点重复出现，用于限定在多个服务器范围内的授权；在 `device_authorization` 处被拒绝而不是被忽略（[资源指示符]({{< relref "/authn-bridge/resources.md" >}})） |
| v0.23.0 | `access_token_groups = false`：令牌被粘贴到 ssh 中的客户端不携带组（[令牌]({{< relref "/authn-bridge/tokens.md#what-it-leaves-out" >}})） |
| v0.23.1 | 仅依赖项：go-jose/v4 v4.1.6、golang.org/x/crypto v0.58.0、golang.org/x/net v0.61.0；go-authn/directory v0.12.0、revocation v0.6.3、saml v0.4.1、servercert v0.5.1、sshcert v0.1.6 |

### authn-revokd {#authn-revokd}

| | |
|---|---|
| v0.1.0 | 已签名且会过期的吊销列表：协议、库，以及 revokd（代理和镜像） |
| v0.2.0 | 对抗性审查的修复 |
| v0.2.1 | 每个 CA 的列表与其自身的密钥吊销合并；解析 CRL 之前先检查其签名 |
| v0.3.0 | 限定范围的密钥吊销；按 CA 故障即拒绝；检查状态目录的所有者 |
| v0.5.0 | 每个标签都发布二进制文件、`SHA256SUMS` 和构建溯源信息 |
| v0.6.0 | 命令为 `authn-revokd`；systemd 单元和安装指南；`SIGHUP` 立即同步 |
| v0.6.1 | `-version` 输出到标准输出 |
| v0.6.2 | `-once` 区分获取失败与列表过期；由另一把密钥签名的列表不再被称为竞态；`-help` 以 0 退出 |
| v0.6.3 | 示例和文档中的占位域名改用 RFC 2606 名称；行为不变 |
| v0.6.4 | 仅依赖项：golang.org/x/crypto v0.58.0 |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | 域授权扩展，以及故障即拒绝的 `sshcert-authorize` |
| v0.1.2 | 每个标签都发布二进制文件、`SHA256SUMS` 和构建溯源信息 |
| v0.1.4 | 发布时检查每个二进制文件的构建信息 |
| v0.1.5 | `-version` 输出 `go install` 构建的模块版本，而不是 `dev` |
| v0.1.6 | 文档中的占位域名改用 RFC 2606 名称；行为不变 |
| v0.1.7 | 仅依赖项：golang.org/x/crypto v0.58.0 |

### 各个库 {#the-libraries}

本文档版本所针对的库版本；每个
库的页面都说明了更早的版本改变了什么。

| | |
|---|---|
| directory v0.13.0 | [属性]({{< relref "/libraries/directory.md#attributes" >}})：除凭据之外，描述某人但不证明任何事的内容，以及永远不能作为属性的名称；`user` 和 `group` 块中的 `attributes`、`users_attributes` 和 `groups_attributes` 查询、ldapdir 的 `attributes` 和 `group_attributes` |
| directory v0.14.0 | ⛔ ldapdir 的[默认值]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})读取 `account` 和 `uidObject` 人员以及 `groupOfNames` 组，这扩大了机构目录所提供的内容；`member` DN 只映射到来源已导入的人员 |
| kdc v0.4.3 | 仅依赖项：以 go-authn/directory v0.12.0 为最低版本 |
| keyfactor v0.4.2 | 仅依赖项：以 go-authn/fido v0.6.2 和 golang.org/x/crypto v0.58.0 为最低版本 |
| krb5 v0.3.1 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
| krl v0.6.1 | 仅依赖项：golang.org/x/crypto v0.58.0；已用 Go 1.27.2 测试 |
| ldap v0.8.0 | [`schema` 包]({{< relref "/libraries/ldap.md#the-schema" >}})和 `Server.Schema`：`cn=Subschema`（RFC 4512 §4.2）、`Validate`、RFC 4517 匹配规则；`uidNumber` 和 `gidNumber` 按整数排序；分页搜索仅返回所请求的属性 |
| ldap v0.9.0 | [HCL2 模式]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})：包 `schema/hclschema` 和 `ldapschema` 命令（`to-hcl`、`to-schema`、`check`），在 OpenLDAP `.schema`、cn=config LDIF 与 HCL2 之间转换；读取器像 slapd 一样读取文件；不支持 DIT 内容和结构规则、名称形式、`include` 和 `X-SUBST` |
| oidc v0.4.1 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
| servercert v0.5.2 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
| totp v0.4.2 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
| wireguard v0.1.1 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |

## 尚未实现 {#not-implemented-yet}

- **通过 LDAP 写入**，除了用户更改自己的密码之外。authnd
  应答对自己 `userPassword` 的 modify 操作，以及 RFC 3062 密码修改
  操作（`ldappasswd` 所发送的），两者都只在提供当前密码时才有效，
  除此之外不支持任何其他操作：add、delete 和 modifyDN 存在于 go-authn/ldap 中，
  但有意没有接入（`server.go`）。该库将 modify 表示为
  有序列表（RFC 4511 4.6），并应答读取条目控制（RFC 4527），
  因此基础已经具备；缺少的是谁可以写什么的策略。
- **Kerberos 内部的第二因素**：FAST（RFC 6113）中的 OTP
  预认证（RFC 6560）。在它出现之前，`kerberos` 块与 `mfa` 块
  不能同时配置。
- **RC4-HMAC**：该域只签发 aes256-cts-hmac-sha1-96，因此仅以 NT 哈希
  为人所知的用户无法获得票据。这是一个选择（RC4 已被 RFC 8429
  弃用），而不是有待填补的缺口。
