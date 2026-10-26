---
title: "authnd：面向存放在别处的人员的 LDAP 服务器"
linkTitle: "authnd"
weight: 10
description: "一个 LDAP 目录，可选地附带一个 Kerberos 域，面向保存在配置文件、SQL 数据库或另一个目录中的人员。"
tags: [authnd, ldap]
---

**一个站点的人员早已存在于数据库、文件或另一个目录中。想要对他们进行
认证的系统使用的是 LDAP。** authnd 就是前端：它基于 [go-authn/directory]({{< relref "/libraries/_index.md" >}})
的各个来源进行绑定和搜索，因此数据库中保存的内容可以被任何懂得
如何查询目录的程序读取。纯 Go，`CGO_ENABLED=0`，单个二进制文件。这些页面描述
v0.12.4，它的条目遵循标准模式，并通过它在 `cn=Subschema` 处
提供的模式，站点可以用自己的模式对其扩展
（[SUPANN、eduPerson]({{< relref "/authnd/schemas.md" >}})），其下是 go-authn/ldap v0.10.2 和
go-authn/directory v0.15.0；哪些已经验证、哪些尚未验证，见
[状态]({{< relref "/status.md" >}})页面。

{{< callout type="warning" >}}
**从 v0.11.x 升级**

- ⛔ **安全：请使用 v0.12.0，而不是 v0.11.1。** v0.11.1 的发布二进制文件
  由 Go 1.27.2 构建，其 crypto/x509 不会不信任 GO-2026-6809 所指明的
  已被攻破的中间证书，而 authnd 要验证证书。v0.12.0 由 Go 1.27.3 构建，
  其 `go` 指令为 1.27.3，因此 `go install` 会自动切换到已修复的工具链。
- 不使用新键的配置，发布的内容与 v0.11.1 相同：类是声明出来的，从不推断，
  所以没有 `object_classes` 就不会有任何变化。
- 新增，且全部可选：[`schema_files` 和 `schema` 块]({{< relref "/authnd/schemas.md" >}})
  把站点的定义添加到所提供的模式中，`object_classes` 和
  `group_object_classes` 声明某个来源的人员和组所带的辅助类。重新定义
  已有定义的定义会被拒绝，即使逐字相同也一样，正如 slapd 所拒绝的那样。
- `check` 和启动日志会说明加载了哪些文件和块、每个来源声明了什么、
  哪些类因缺少 MUST 而未加到某个人员上，以及哪些组在两个来源之间存在分歧。

重启之前，请按[安装]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}})所述，
用新的二进制文件运行 `authnd check`。
{{< /callout >}}

{{< callout type="warning" >}}
**从 v0.10.x 升级**

- `publish_nt_hash = true` 现在需要一个 [`samba` 块]({{< relref "/authnd/tls.md#the-samba-block" >}})，
  否则 authnd 无法启动。
- 没有 `uidNumber`、`gidNumber` 和 `homeDirectory` 的人员不再是
  `posixAccount`，没有 `gidNumber` 的组也不再是
  `posixGroup`，因此按这些类过滤的使用方看到的条目会变少：
  参见[条目]({{< relref "/authnd/entries.md" >}})。
- `users "ldap"` 块默认读取其后目录的更多内容：
  参见[人员]({{< relref "/authnd/people.md#in-another-ldap-directory" >}})。

用新的二进制文件运行 `authnd check` 会在重启之前把这三点都告诉你。
{{< /callout >}}

```sh
authnd --config /etc/authnd      # serve
authnd check /etc/authnd         # say what would be served, without listening
```

## 最小配置 {#the-smallest-configuration}

```hcl
listen  = "127.0.0.1:3893"            # the default
base_dn = "dc=example,dc=org"         # required

reader "cn=reader,dc=example,dc=org" { password_file = "/etc/authnd/reader.pw" }

user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

group "staff" { members = ["alice"] }
```

人员发布为 `uid=<name>,ou=people,<base_dn>`，组发布为
`cn=<name>,ou=groups,<base_dn>`。每个条目*是什么*，取决于其
来源提供了什么：人员是 `account`，有 `sn` 时是
`inetOrgPerson`，只有具备 `uidNumber`、`gidNumber` 和
`homeDirectory` 时才是 `posixAccount`；每个人员都是 `uidObject`。组在有 `gidNumber` 时
是 `posixGroup`（带 `memberUid`），否则是 `groupOfNames`
（带 `member` DN），若同时为空则是 `organizationalRole`。
人员有密钥时会添加 `sshPublicKey`，而当
[`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})要求
且能给出 SID 时会添加 `sambaNTPassword`。每个条目在发布之前都要通过
`cn=Subschema` 处提供的模式：参见
[条目与模式]({{< relref "/authnd/entries.md" >}})。直到
v0.10.2，无论具备什么，每个人员都是 `posixAccount`，每个组都是 `posixGroup`。

`--config`（`-c`）接受文件或目录，并且可以重复；目录
指其中所有的 `.hcl` 文件，按名称顺序读取并合并为一个
配置。没有 `base_dn` 或其中没有任何人的配置
无法启动。

## 谁可以绑定，谁可以读取 {#who-may-bind-and-who-may-read}

LDAP 服务器的职责是证明人员身份，因此它的拒绝就是设计本身。
以下是 v0.12.3 发布的二进制文件对 OpenLDAP 自带客户端的答复：

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y wrong.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -w ''
ldap_bind: Server is unwilling to perform (53)
	additional info: an unauthenticated bind proves nothing, and this server does not accept one

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -b dc=example,dc=org '(uid=alice)'
Insufficient access (50)
Additional information: only a reader may search
```

| 请求 | 答复 | 原因 |
|---|---|---|
| 空名称、空密码（RFC 4513 §5.1.1，匿名） | 成功 | 它表示“我是无名者”，这是事实，而客户端在发现任何东西之前就会发送它 |
| **名称**加空密码（§5.1.2，未认证） | `unwillingToPerform` | 它指名了某人却没有证明任何事；§5.1.2 要求的正是这个代码。`invalidCredentials` 会告诉人们其密码有误 |
| 错误的密码，或此处无人使用的名称 | `invalidCredentials` | 二者不加区分 |
| 由 `reader` 之外的任何人发起的搜索 | `insufficientAccessRights` | 绑定证明你是谁；读取所有人则是另一件需要获得许可的事 |
| `add`、`delete`、`modifyDN` | `unwillingToPerform` | 没有为它们接入处理程序；唯一的写操作是[用户自己的密码]({{< relref "/authnd/passwords.md" >}}) |

`reader` 是带有绑定 DN 以及 `password` 或
`password_file` 的服务账户；两者都没有的 reader 在启动时被拒绝（*证明不了任何事的
reader 不过是多了几步的匿名搜索*）。没有任何 reader 时，
任何人都不能搜索，`check` 会如此提示。

根 DSE 会应答匿名客户端，因为发现机制需要它：

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.12.4
```

`1.3.6.1.4.1.4203.1.11.1` 是 RFC 3062 密码修改操作。
`subschemaSubentry` 指向[模式]({{< relref "/authnd/entries.md#the-schema-it-serves" >}})，
匿名客户端同样可以获得该模式。
`supportedSASLMechanisms: OAUTHBEARER` 只有在存在
[`oidc` 块]({{< relref "/authnd/tokens.md" >}})时才会出现。

## 接下来去哪里 {#where-to-go-next}

| | |
|---|---|
| [安装]({{< relref "/authnd/install.md" >}}) | 发布的二进制文件、`authnd` 账户、systemd 单元、升级 |
| [人员从哪里来]({{< relref "/authnd/people.md" >}}) | `user` 和 `group` 块、SQL 数据库、另一个 LDAP 目录 |
| [条目与模式]({{< relref "/authnd/entries.md" >}}) | 每个人员和组发布为什么、`cn=Subschema`、属性、哪些被丢弃或扣留 |
| [站点模式]({{< relref "/authnd/schemas.md" >}}) | `schema_files`、`schema` 块和 `object_classes`：SUPANN、eduPerson 或站点自己的属性 |
| [`check`]({{< relref "/authnd/check.md" >}}) | 在重启之前回读配置 |
| [TLS]({{< relref "/authnd/tls.md" >}}) | `ldaps://` 或 StartTLS，以及 `publish_nt_hash` |
| [更改密码]({{< relref "/authnd/passwords.md" >}}) | `ldappasswd`、`ldapmodify`，以及为什么总是要求提供旧密码 |
| [Kerberos 域]({{< relref "/authnd/kerberos.md" >}}) | keytab，以及谁可以获得票据 |
| [第二因素]({{< relref "/authnd/mfa.md" >}}) | 附在密码末尾的一次性代码 |
| [绑定时使用令牌]({{< relref "/authnd/tokens.md" >}}) | 基于 SASL `OAUTHBEARER` 的 OIDC |
| [运行]({{< relref "/authnd/operations.md" >}}) | 信号、重启、它记录什么日志、如何判断它已在运行 |

{{< callout type="info" >}}
**关于这些记录**

这些页面上显示的每条命令，都已于 2026-10-26 用已发布的二进制文件重新运行，而不是手工重写：`authnd` v0.12.3（`authnd-darwin-arm64`，已由 `relverify` 对照 `SHA256SUMS` 及其证明（attestation）核对；`go version -m`：`go1.27.3`，`mod github.com/go-authn/authnd v0.12.3`，`vcs.modified=false`）、`authn-bridge` v0.23.4、`authn-revokd` v0.6.6、`sshcert-authorize` v0.1.9 和 `ldapschema` v0.10.1。命令输出了什么，这里就是什么。有两份记录是例外，各自在所在之处注明：[令牌页面]({{< relref "/authnd/tokens.md" >}})上的 `oidctool` 客户端是为这些页面编写的测试客户端，不属于任何发布版本，它的记录以及旁边的服务器输出行由 v0.10.0 发布的二进制文件输出；另一份是[联邦页面]({{< relref "/authn-bridge/federation.md" >}})上 RENATER 已过期的元数据，该文件已不再发布。所有这些都由 macOS 自带的 OpenLDAP 和 Heimdal 客户端发出请求，在 127.0.0.1 的非特权端口上，在临时目录中进行。这就是为什么其背后的配置用相对路径指名文件，例如 `etc/authnd/passwords/alice.pw`，也是为什么密码文件的名称类似 `alice.pwin`。示例中的 `/etc/authnd` 路径是已安装的服务器所使用的路径。输出 `authnd` 版本或模式的记录已用 v0.12.4 重新运行（`authnd-darwin-arm64`，由 `relverify` 对照 `SHA256SUMS` 及其证明校验；`go version -m`：`go1.27.3`，`mod github.com/go-authn/authnd v0.12.4`，`vcs.modified=false`）：此处和运维页面的 root DSE、`authnd --version`，以及条目页面的模式。
{{< /callout >}}
