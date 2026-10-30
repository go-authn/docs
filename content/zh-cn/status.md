---
title: "状态"
weight: 60
description: "这些页面描述哪些版本、每个版本新增了什么，以及哪些功能尚未实现。"
tags: [状态, 发布版本]
---

这些页面是文档版本 **0.6**，描述的内容如下：

| 程序 | 版本 | 模块 |
|---|---|---|
| authnd | **v0.13.3** | `github.com/go-authn/authnd` |
| authn-bridge | **v0.23.4** | `github.com/go-authn/bridge` |
| authn-revokd | **v0.6.6** | `github.com/go-authn/revocation` |
| sshcert-authorize | **v0.1.9** | `github.com/go-authn/sshcert` |

各个库的版本见[其自己的页面]({{< relref "/libraries/_index.md" >}})；
ldap 为 **v0.11.3**，可读取、强制执行并发布 DIT 内容规则、名称形式和 DIT 结构规则，带有针对无法构建的模式的类型化 `BuildError`、HCL2 模式和 `ldapschema` 转换器，
directory 为 **v0.15.0**，带有已声明的对象类。authnd
v0.13.3 内嵌 ldap v0.11.3 和 directory v0.15.0。
上述任何程序的新次版本号都对应一个新的文档版本，
因此读者在 `/docs/0.6/` 下找到的页面始终描述其所安装的版本；
之前各版本的页面保留在 `/docs/0.1/`、
`/docs/0.2/`、`/docs/0.3/`、`/docs/0.4/` 和 `/docs/0.5/` 之下。

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
| v0.13.3 | 仅优化性能，内嵌 go-authn/ldap v0.11.3：`unmet` 刚验证过的条目，如果没有变化，`validated` 不再重新验证；发布 10,000 个人员（`BenchmarkPublish10k`，`-cpu 1`）时，有规则的每个条目 97 次分配，无规则为 69 次（v0.13.2 为 110 和 72 次）。耗时：有规则时约从 70 ms 降到 66 ms（负载 4.8） |

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
| kdc v0.4.3 | 仅依赖项：以 go-authn/directory v0.12.0 为最低版本 |
| keyfactor v0.4.2 | 仅依赖项：以 go-authn/fido v0.6.2 和 golang.org/x/crypto v0.58.0 为最低版本 |
| krb5 v0.3.1 | 已用 Go 1.27.2 测试；代码和 `go.mod` 均未改变 |
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
