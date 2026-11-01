---
title: "状态"
weight: 60
description: "这些页面描述哪些版本、每个版本新增了什么，以及哪些功能尚未实现。"
tags: [状态, 发布版本]
---

这些页面是文档版本 **0.7**，描述的内容如下：

| 程序 | 版本 | 模块 |
|---|---|---|
| authnd | **v0.15.0** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.6** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.7** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

各个库的版本见[其自己的页面]({{< relref "/libraries/_index.md" >}})；
ldap 为 **v0.12.0**，可读取、强制执行并发布 DIT 内容规则、名称形式和 DIT 结构规则，带有针对无法构建的模式的类型化 `BuildError`、HCL2 模式和 `ldapschema` 转换器，
directory 为 **v0.17.0**，带有已声明的对象类。authnd
v0.15.0 内嵌 ldap v0.12.0 和 directory v0.17.0。
上述任何程序的新次版本号都对应一个新的文档版本，
因此读者在 `/docs/0.7/` 下找到的页面始终描述其所安装的版本；
之前各版本的页面保留在 `/docs/0.1/`、
`/docs/0.2/`、`/docs/0.3/`、`/docs/0.4/`、`/docs/0.5/` 和 `/docs/0.6/` 之下。

{{< callout type="warning" >}}
**从 v0.14.x 升级 authnd：两个默认值发生变化**

`max_connections` 为 `4096`（以前不限），`operation_timeout` 为 `30s`（以前无）；上游目录宕机时回答
`unavailable`（52），不再回答 `invalidCredentials`（49）。`max_connections = 0` 和 `operation_timeout = "0"`
恢复旧的行为。参见[限制与期限]({{< relref "/authnd/operations.md#limits" >}})。
{{< /callout >}}

{{< callout type="warning" >}}
**安全：请使用 authnd v0.12.0，而不是 v0.11.1**

authnd 要验证证书（`x509.Certificate.Verify`，据 `govulncheck`
可从 `main` 到达），而 Go 1.27.2 的 crypto/x509 不会不信任
GO-2026-6809 所指明的已被攻破的中间证书。**v0.11.1 的
发布二进制文件由 Go 1.27.2 构建，受此影响。** v0.12.0 由 Go 1.27.3
构建，其 `go` 指令为 1.27.3，因此 `go install` 会自动切换到
已修复的工具链；在 1.27.3 下运行 `govulncheck` 不报告任何漏洞。
它的发布二进制文件在 `go version -m` 中报告 `go1.27.3`。
参见[升级说明]({{< relref "/authnd/_index.md" >}})。
{{< /callout >}}

{{< callout type="warning" >}}
**安全：请使用 authn-bridge v0.23.3 和 authn-revokd v0.6.5**

在 Go 1.27.2 下，`govulncheck` 在这两个程序中都报告了 GO-2026-6809：`crypto/x509` 的 `Certificate.Verify` 未拒绝已知被攻破的中间证书。该问题已在 Go 1.26.10 和 1.27.3 中修复。**用较旧版本的 Go 构建的发布二进制文件受到影响。** v0.23.3 和 v0.6.5 使用 Go 1.27.3 构建，其 `go` 指令为 1.27.3，因此 `go install` 会自行切换到已修复的工具链；它们的发布二进制文件在 `go version -m` 中显示 `go1.27.3`。sshcert 不受影响，也没有新版本。
{{< /callout >}}

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
| v0.12.0 | [站点模式]({{< relref "/authnd/schemas.md" >}})：`schema_files`（OpenLDAP `.schema` 和 cn=config LDIF，按发布时的原样；重新定义会被拒绝，即使完全相同，如同 slapd 那样）和 `schema { }` 块；用 `object_classes` 按来源声明辅助类，在启动时验证，并连同其父类一起发布；`check` 报告这些文件、这些声明、因缺少 MUST 而未加到某个人员上的类，以及两个来源存在分歧的组。⛔ 由 Go 1.27.3 构建：v0.11.1 的二进制文件（Go 1.27.2）受 GO-2026-6809 影响 |
| v0.12.1 | 无法构建的模式文件或块，会在 go-authn/ldap v0.10.0 的 `BuildError` 所携带的位置被拒绝，并带有列（`site.schema:6:` 变为 `site.schema:6:1:`）；信息以拒绝的类型结尾，重复定义会指出它的第一个定义在哪里 |
| v0.12.2 | 发布的二进制文件改用 `-ldflags="-w"` 链接，不再用 `-s -w`：符号表得以保留，因此 `govulncheck -mode binary` 是精确的，不会报告未链接代码中的漏洞；约大 9 %（darwin/arm64 上从 18.8 MB 到 20.5 MB） |
| v0.12.3 | go-authn/ldap v0.10.1：`schema_files` 以线性时间读取。⛔ 直到 v0.12.2，由短续行组成的大型模式文件（4 MiB：约三分钟）会使启动停滞：由一个不受你控制的文件造成的拒绝服务 |
| v0.12.4 | go-authn/ldap v0.10.2:`cn=Subschema` 中 13 个 RFC 2307 定义(`uidNumber`、`gidNumber`、`ipHostNumber`、`ipNetworkNumber`、`ipNetmaskNumber`、`macAddress`,以及类 `ipService`、`ipProtocol`、`oncRpc`、`ipHost`、`ipNetwork`、`ieee802Device`、`bootableDevice`)的 DESC 值不再带有 RFC 页面排版的缩进:是 `DESC 'An integer uniquely identifying a user in an administrative domain'`,而不是 `... in an         administrative domain'` |
| v0.13.0 | [DIT 内容规则、名称形式和 DIT 结构规则]({{< relref "/authnd/schemas.md#rules" >}})（go-authn/ldap v0.11.0）：`schema_files` 和 `schema { }` 块接受这三类定义，authnd 会强制执行它们。内容规则为每个条目塑形：其 `AUX` 未列出的辅助类被去掉（连同只有它才允许的属性），`NOT` 属性被丢弃，缺少 `MUST` 的条目被排除在外；每一项都会记入日志并由 `check` 报告。只要有一条有效的结构规则，树（后缀、`ou=people`、`ou=groups`、`uid` 或 `cn` RDN）就会在启动时和由 `check` 检查，违规会**拒绝启动**，所有拒绝一并给出，且绝不回显机密；没有规则可放置的条目被排除在外。⛔ 不是有效 UTF-8 的 `schema { }` 字符串现在会被拒绝。发布 10,000 个人员时，有规则的每个条目 416 次分配，无规则则为 265 次（耗时是在负载下测得的，不可靠） |
| v0.13.1 | 仅优化性能，内嵌 go-authn/ldap v0.11.1：发布 10,000 个人员（`BenchmarkPublish10k`，`-cpu 1`）时，有规则的每个条目 364 次分配，无规则为 239 次（v0.13.0 为 416 和 265 次），一次运行使用规则时占用 102.5 MiB（v0.13.0 为 147.5 MiB）。耗时是在负载 10 到 16 时测得的，不可靠 |
| v0.13.2 | 仅优化性能，内嵌 go-authn/ldap v0.11.2：对含十个属性的条目，`Validate` 的分配从 76 次降为 12 次；发布 10,000 个人员（`BenchmarkPublish10k`，`-cpu 1`）时，有规则的每个条目 128 次分配，无规则为 85 次（v0.13.1 为 364 和 239 次），一次运行使用规则时占用 54.8 MiB（v0.13.1 为 102.5 MiB）。耗时（负载 8 到 11）：有规则时约从 158 ms 降到 90 ms |
| v0.13.3 | 仅优化性能，内嵌 go-authn/ldap v0.11.3：`unmet` 刚验证过的条目，如果没有变化，`validated` 不再重新验证；发布 10,000 个人员（`BenchmarkPublish10k`，`-cpu 1`）时，有规则的每个条目 97 次分配，无规则为 69 次（v0.13.2 为 128 和 85 次，分别降低 24 % 和 19 %）。耗时：有规则时约 66 ms，无规则时约 36 ms（负载 4.8） |
| v0.13.4 | 一次混沌测试。组与人员一样，在启动时只读取一次：在 SQLite 上，对 500 人、200 个各 50 人的组做一次搜索原本要 4.13 秒（每次搜索都重新查询组），现在只要 1.2 毫秒；搜索期间失败的组查询也不再把组从仍返回 Success 的应答中悄悄丢掉。启动时无法读取的来源（无法执行的组查询、多个数据库中有一个宕机）会拒绝启动和 `check`。超过约 3 MiB 的条目（一个 10 MB 的属性值）不会发布。发布内容按人员集合只构建一次。已用测试验证：在每个字节处截断的模式文件、被删除或损坏的数据库、恶意的行、空闲连接、过大的 BER 长度、嵌套 20,000 层的过滤器 |
| v0.14.0 | 变更：v0.13.4 修改组需要重启，因此从数据库中移除的成员会一直保有访问权限，直到有人重启 authnd。v0.14.0 恢复了及时撤销。`refresh`（默认 60 秒，`0` 表示关闭）会把每个来源（人员和组）重新读入一份在服务路径之外构建的新快照，并整体替换；刷新失败时保留最近一份良好的快照，且每一轮连续失败只记录一次日志，并点名来源。设置 `max_age`（默认不设置）后，一旦所提供的数据比它更旧，搜索、人员的 bind 和密码修改都会应答 `unavailable`。通过 authnd 写入的密码同样经过这一替换。实测：在 SQLite 上，对 500 人、200 个各 50 人的组做一次刷新约占一个核心 2 秒，一次搜索 0.5 毫秒（刷新开销已在 v0.14.1 修复） |
| v0.14.1 | 仅性能。刷新的开销不再随“组数 × 成员关系行数”增长：directory v0.16.0 对每个来源只批量读取一次。在 SQLite 上，对 500 人、200 个各 50 人的组做一次刷新由 1.87 秒降到 0.155 秒；对 10,000 人、2,000 个组做一次刷新由 391 秒（六个半刷新周期）降到 1.6 秒（60 秒周期的 2.7 %）。内存分配次数由 39,959,235 降到 3,095,482，以及由 6,373,736,235 降到 31,198,460。时间是在负载 17 至 67 下测得的，仅供参考；分配次数是精确的 |
| v0.15.0 | 可用性与安全，使用 go-authn/ldap v0.12.0 和 go-authn/directory v0.17.0。⛔ **两个默认值发生变化**：`max_connections` 为 `4096`（以前不限），`operation_timeout` 为 `30s`（以前无）。新增，可选：`max_connections_per_ip` 和 `startup_timeout`（`60s`）；[`check` 会打印限制]({{< relref "/authnd/operations.md#limits" >}})。超出上限的连接会收到 `busy` 并被关闭；超过期限的操作会收到 `timeLimitExceeded`，即使其处理程序被阻塞。绑定期间的上游故障（简单绑定、密码更改、`mfa` 的密码因素）回答 `unavailable`（52），绝不回答 `invalidCredentials`（49）；密码错误仍是 49。针对缓慢来源的启动会在 `startup_timeout` 之后失败，并指出阶段和来源。[TLS 证书会被重新读取]({{< relref "/authnd/tls.md#renewal" >}})，当 `cert_file` 或 `key_file` 变化时（5 秒后的第一次握手，以及 `SIGHUP`）；无法加载的证书对保持正在提供的证书，并只记录一次。分配次数见下面的库；挂钟时间未测量（开始时负载为 21） |

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
| v0.23.2 | 安全：go-authn/oidc v0.4.2，它拒绝超出 int64 范围的 `nbf`（尚未生效的令牌曾被接受）以及 `e = 0` 的 RSA 密钥（它曾被解析）；go-authn/wireguard v0.1.2 |
| v0.23.3 | 使用 Go 1.27.3 构建，针对 GO-2026-6809（`crypto/x509`：`Certificate.Verify` 未拒绝已知被攻破的中间证书）；`go` 指令为 1.27.3；行为没有变化 |
| v0.23.4 | 发布的二进制文件改用 `-w` 链接，不再用 `-s -w`，符号表得以保留，使 `govulncheck -mode binary` 精确；行为不变 |
| v0.23.6 | 审计、模糊测试和混沌测试，使用 go-authn/saml v0.5.1；没有增加或改变任何配置键。[元数据按时刷新]({{< relref "/authn-bridge/federation.md#refreshing-it" >}})：绝不安排在剩余 `validUntil` 的一半之后，没有有效元数据时一分钟后重试，间隔加倍直到一小时，所以临近到期时的一次刷新失败不再让提供方最长十二小时没有 IdP。断言重放键以其 SHA-256 存储：过长的 IdP `entityID` 曾使 PostgreSQL 和 MySQL 拒绝写入并卡住状态数据库。时钟可与 IdP 相差三分钟；相差一小时则以 400 页面拒绝。[测试了什么]({{< relref "/authn-bridge/federation.md#tested" >}})：XML 签名包装 XSW1 到 XSW8、CVE-2017-11427、DOCTYPE、外来的受众、接收方、请求和目的地，五个模糊测试器。每次登录一次 SHA-256 多花 0 到 2 次分配（`BenchmarkReplayUse`：0 次分配和 183 B，现在 2 次和 326 B）；挂钟时间未测量，负载 53 到 75 |

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
| v0.6.5 | 使用 Go 1.27.3 构建，针对 GO-2026-6809（`crypto/x509`：`Certificate.Verify` 未拒绝已知被攻破的中间证书）；`go` 指令为 1.27.3；行为没有变化 |
| v0.6.6 | 发布的二进制文件改用 `-w` 链接，不再用 `-s -w`，符号表得以保留，使 `govulncheck -mode binary` 精确；行为不变 |
| v0.6.7 | 审计、模糊测试、混沌测试和性能改进（[一次同步做什么]({{< relref "/authn-revokd/configuration.md#sync" >}})）。失效的列表在失效时就被拒绝，而不是等到下次刷新；来源并行获取（最多 16 个，每个两分钟）；`on_change` 在一分钟后被终止并重试；在代理背后被改动的输出文件会在下次同步时重写；`file://` 来源必须是普通文件；错误显示不带密码、查询和片段的 URL；`0..2^159` 之外的 CRL 编号被拒绝；镜像有读取、写入和空闲期限；过期的临时文件在启动时清除。再次轮询一个含 100,000 条记录的 CRL：每次轮询 300,138 次分配和 96,956,946 B，现在 37 次和 4,776,864 B（精确；时间未测量，负载 53 到 65）。govulncheck 仍列出 GO-2026-5932（`golang.org/x/crypto/openpgp`），它没有修复版本，也不会被调用 |

### sshcert {#sshcert}

| | |
|---|---|
| v0.1.0 | 域授权扩展，以及故障即拒绝的 `sshcert-authorize` |
| v0.1.2 | 每个标签都发布二进制文件、`SHA256SUMS` 和构建溯源信息 |
| v0.1.4 | 发布时检查每个二进制文件的构建信息 |
| v0.1.5 | `-version` 输出 `go install` 构建的模块版本，而不是 `dev` |
| v0.1.6 | 文档中的占位域名改用 RFC 2606 名称；行为不变 |
| v0.1.7 | 仅依赖项：golang.org/x/crypto v0.58.0 |
| v0.1.8 | 发布的二进制文件改用 `-w` 链接，不再用 `-s -w`，符号表得以保留，使 `govulncheck -mode binary` 精确；行为不变 |
| v0.1.9 | 使用 Go 1.27.3 构建；行为不变 |

### 各个库 {#the-libraries}

本文档版本所针对的库版本；每个
库的页面都说明了更早的版本改变了什么。

| | |
|---|---|
| directory v0.13.0 | [属性]({{< relref "/libraries/directory.md#attributes" >}})：除凭据之外，描述某人但不证明任何事的内容，以及永远不能作为属性的名称；`user` 和 `group` 块中的 `attributes`、`users_attributes` 和 `groups_attributes` 查询、ldapdir 的 `attributes` 和 `group_attributes` |
| directory v0.14.0 | ⛔ ldapdir 的[默认值]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})读取 `account` 和 `uidObject` 人员以及 `groupOfNames` 组，这扩大了机构目录所提供的内容；`member` DN 只映射到来源已导入的人员 |
| directory v0.15.0 | [对象类]({{< relref "/libraries/directory.md#object-classes" >}})，声明出来而从不推断：`users` 块中的 `object_classes` 和 `group_object_classes`，`user` 和 `group` 块中的 `object_classes`，sqldir 的 `WithObjectClasses` 和 ldapdir 的 `Config.ObjectClasses`；第一个声明某组的类的来源决定；`sqldir.ClosesDB` |
| directory v0.16.0 | [每个组只读取一次]({{< relref "/libraries/directory.md" >}})：`GroupReader` 和 `Set.Frozen`，使刷新不再随组数乘以成员行数增长 |
| directory v0.17.0 | [`ErrUnavailable`]({{< relref "/libraries/directory.md#unavailable" >}})，附带 `AsUnavailable` 和 `TransportFailure`：ldapdir 在 busy（51）、unavailable（52）、other（80）、timeLimitExceeded（3）、断开或被拒绝的连接以及连接或 TLS 失败时，对 `Verify` 和每次读取返回它；它绝不同时是 `ErrWrongPassword`，而 `invalidCredentials`（49）仍是后者。`ldaptest.Server.FailBindsWith(code)`。成员 DN 通过一次查找而不是一次扫描映射到人员，结果相同：在 10,000 人和 2,000 个各含 50 个 DN 的组上，`ReadGroups` 在 0.38 M 个对象中分配 13.1 MB，而不是 2.20 M 个对象 50.6 MB，DN 查找 0 次分配；整个刷新 7.17 M 次分配，而不是 9.72 M（精确；时间未测量，负载 65 到 105） |
| kdc v0.4.3 | 仅依赖项：以 go-authn/directory v0.12.0 为最低版本 |
| kdc v0.4.5 | 安全审计、模糊测试和混沌测试（[它拒绝什么]({{< relref "/libraries/kdc.md" >}})）：针对另一个域的请求回答 `KDC_ERR_WRONG_REALM`，无法读取的目录回答 `KDC_ERR_SVC_UNAVAILABLE`（以前是 `KDC_ERR_C_PRINCIPAL_UNKNOWN`），开始时间在 `MaxSkew` 之内的未来的 TGT 会被接受，解码器 panic 只丢弃一个请求，而不是使进程崩溃（一个格式错误的 AS-REQ 或 TGS-REQ 就能使其崩溃）；主体名称在日志中加引号。golang.org/x/net v0.62.0，go-authn/directory v0.16.1 |
| keyfactor v0.4.2 | 仅依赖项：以 go-authn/fido v0.6.2 和 golang.org/x/crypto v0.58.0 为最低版本 |
| krb5 v0.3.1 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
| krb5 v0.3.3 | 仅依赖项：golang.org/x/net v0.62.0、golang.org/x/crypto v0.58.0 和 go-uuid v1.0.4 清除了 `govulncheck` 在所需但不调用的模块中的 46 项发现中的 45 项；GO-2026-5932（`x/crypto/openpgp`）没有修复，且没有任何 go-authn 模块导入它；API 无变化 |
| krl v0.6.1 | 仅依赖项：golang.org/x/crypto v0.58.0；已用 Go 1.27.2 测试 |
| ldap v0.8.0 | [`schema` 包]({{< relref "/libraries/ldap.md#the-schema" >}})和 `Server.Schema`：`cn=Subschema`（RFC 4512 §4.2）、`Validate`、RFC 4517 匹配规则；`uidNumber` 和 `gidNumber` 按整数排序；分页搜索仅返回所请求的属性 |
| ldap v0.9.0 | [HCL2 模式]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})：包 `schema/hclschema` 和 `ldapschema` 命令（`to-hcl`、`to-schema`、`check`），在 OpenLDAP `.schema`、cn=config LDIF 与 HCL2 之间转换；读取器像 slapd 一样读取文件；不支持 DIT 内容和结构规则、名称形式、`include` 和 `X-SUBST`（v0.11.0 支持这些规则） |
| ldap v0.10.0 | 针对 `Build` 拒绝的定义的[类型化 `*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}})，用 `errors.As` 匹配：`Kind`、`Element`、`OID`、`Name`、`Field`、`Pos`（定义起始处的 file:line:column，折叠或 base64 的 LDIF 与 HCL 同样适用），以及指向另一个定义的 `Ref`、`RefOID` 和 `RefPos`；读取的每个定义都带有 `Pos`；信息中写作 "object classes" |
| ldap v0.10.1 | [`schema.Read`]({{< relref "/libraries/ldap.md#reading-large-files" >}}) 的耗时与续行数成线性关系（此前是平方：4 MiB 的文件约需三分钟），并且不再为了读取第一行而复制并拆分整个文件；`schema.Format` 会折行超过 2000 字节的行（slapd 和 `Read` 会拒绝这样的行）；严格解析器约快 2.6 倍（`cosine.schema` 上分配 147 次而非 498 次，在负载下测得） |
| ldap v0.10.2 | 内嵌模式(`schema.Standard()`)中 13 个 RFC 2307 定义的 DESC 写在一行上:它们带有 RFC 页面排版的缩进,读取器像 slapd 一样在引号内保留它,因此服务器发布的子模式里有成串的空格;现在有测试逐一检查内嵌的每个 DESC,并在同一 OID 已定义的地方与 OpenLDAP 的 `core`、`cosine`、`inetorgperson`、`nis` 模式比较 |
| ldap v0.11.0 | [DIT 内容规则、名称形式和 DIT 结构规则]({{< relref "/libraries/ldap.md#rules" >}})（RFC 4512 §4.1.6、§4.1.7）：从 `.schema` 和 LDIF 读取，由 `Format` 写出，经 HCL（`dit_content_rule`、`name_form`、`dit_structure_rule`）和 `ldapschema` 传递，由 `Build` 检查，由 `Validate` 强制执行（内容规则：AUX、MUST、MAY、NOT；名称形式：RDN；结构规则：`GoverningStructureRule`），并且仅在存在时才在 `cn=Subschema` 发布；`ValidateOptions{StrictAuxiliary}` 给出 RFC 4512 §2.4.3。⛔ slapd 只实现内容规则，因此 `Format` 写出的 `nameform` 和 `ditstructurerule` 关键字会被它拒绝；`OBSOLETE` 规则无效，而 slapd 会拒绝该条目；libldap 无法读取结构规则的 `SUP`。`hclschema.Decode` 拒绝不是 UTF-8 的字符串 |
| ldap v0.11.1 | 仅优化性能，结果不变：由可打印 ASCII 组成的字符串在字符串匹配规则（RFC 4518）的预处理中最多只分配一次，没有变化时不分配，对于含四个 RDN 的 DN，DN 解析器的分配从 11 次降为 6 次。结果与 v0.11.0 相同，已对 0x80 以下一个或两个字节的每个字符串用 v0.11.0 的代码核对，并用差分模糊测试检验 |
| ldap v0.11.2 | 仅优化性能，结果不变：对含十个属性的条目，`Validate` 的分配从 76 次降为 12 次（查找不再复制小写副本，描述不再拆分再拼合，用原地集合代替映射）。结果与 v0.11.1 相同，已在标准模式和带规则的模式下用随机条目对 v0.11.1 的 `Validate` 副本核对，并用差分模糊测试检验 |
| ldap v0.11.3 | 仅优化性能，结果不变：`GoverningStructureRule` 对一个账户的分配从 12 次降为 5 次（只读取 RDN 的类型），DN 解析器对含四个 RDN 的 DN 从 6 次降为 3 次。结果与 v0.11.2 相同，已用随机条目和每条上级规则对 v0.11.2 的 `GoverningStructureRule` 副本核对，并用差分模糊测试检验 |
| ldap v0.12.0 | [服务器的资源上限]({{< relref "/libraries/ldap.md" >}})：`Server.MaxConnections` 和 `Server.MaxConnectionsPerIP`（默认 0，不限；超出上限的连接会收到 `busy`（51）断开通知，RFC 4511 4.4.1，并被关闭）；`Server.Timeout` 由服务器强制执行，到期时即使处理程序被阻塞并忽略其上下文，对任何操作都回答 `timeLimitExceeded`（3）（迟到的结果被丢弃，goroutine 在返回之前计入 `MaxPending` 和 `MaxPendingAuth`）；客户端的搜索 `timeLimit` 适用于处理程序的上下文；处理程序的 `DeadlineExceeded` 只有在该操作自身的上下文已到期时才映射为代码 3。每次操作的分配次数（精确）：没有 `Timeout` 时之前和之后都是 3；有 `Timeout` 时之前 10，现在 16 |
| oidc v0.4.1 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
| scim v0.2.0 | [审计、模糊测试、混沌测试和性能改进]({{< relref "/libraries/scim.md#v020" >}})：`Server.ReadTimeout`（30 秒）、可选接口 `ConditionalDeleter`、没有 `If-Match` 的 PATCH 或 PUT 在输掉竞争后最多重做 32 次而不是回答 412、通过不匹配任何内容的过滤器移除会成功、没有路径的 PATCH 的键按排序顺序应用、`BearerAuth` 接受任意大小写的方案、`startIndex` 和 `count` 无论字长都被限定。针对 10,000 个用户的列表请求：100 条的一页从 789,417 次分配降到 14,952 次，`userName eq` 从 797,979 次降到 90 次，完整扫描从 818,847 次降到 361,098 次（精确；时间未测量，负载 65） |
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
