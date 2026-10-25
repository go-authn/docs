---
title: "go-authn"
linkTitle: "首页"
type: docs
cascade:
  type: docs
description: "纯 Go 实现的身份认证：证明某人在场的各类因素、说明人员身份的目录、Kerberos 的两个部分，以及置于 SAML 联邦之前的 OpenID Connect 提供方。"
---

**两个问题，而且它们并不相同。** *此人此刻是否在场？* 不同于
*此人是谁，又凭什么证明？* go-authn 同时回答这两个问题：
证明在场的各类因素；一个记录每个人**凭什么得到证明**而不只是一个密码字段的目录；
Kerberos 的两个部分；以及置于 SAML 联邦之前的 OpenID Connect 提供方。纯 Go，`CGO_ENABLED=0`。
这些页面描述[状态页]({{< relref "/status.md" >}})中列出的各个版本。

## 四个程序 {#four-programs}

| | 它是什么 | 这些页面描述的版本 |
|---|---|---|
| [authnd]({{< relref "/authnd/_index.md" >}}) | 一个 LDAP 服务器，可选地附带一个 Kerberos 域，面向存放在别处的人员：文件、SQL 数据库、另一个目录 | v0.12.0 |
| [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) | 置于 SAML 联邦（RENATER、eduGAIN）之前的 OpenID Connect 提供方，同时签发 SSH 证书，并签署用于吊销这些证书的列表 | v0.23.1 |
| [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) | 获取这些列表，在任何服务器读取之前逐一验证，并在某个列表过期时故障即拒绝 | v0.6.4 |
| [sshcert]({{< relref "/sshcert/_index.md" >}}) | `sshcert-authorize`，由 sshd 调用，用于询问证书的域授权是否指明了本主机 | v0.1.7 |

每个程序都是适用于 Linux、macOS 和 Windows（amd64 与 arm64）的单个静态二进制文件，
并附带 `SHA256SUMS` 和构建溯源信息发布：
[验证下载]({{< relref "/security/verifying-releases.md" >}})。

```sh
go install github.com/go-authn/authnd@v0.12.0
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.1
go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.4
```

这些命令命名为 `authn-*`（以及 `authnd`），是因为它们安装在还运行其他程序的机器上：
在 `/usr/bin` 中放一个裸的 `bridge` 或 `revokd`，就会占用别人可能需要的名字。

## 以及它们之下的库 {#and-the-libraries-under-them}

这些程序都很薄。它们的功能都在
[十四个模块]({{< relref "/libraries/_index.md" >}})中，每个模块只回答一个问题，
因此只*接受* Kerberos 票据的服务永远不会链接 KDC，
只校验一次性代码的服务也永远不会链接目录。

## 为什么目录要记录证明某人的依据 {#why-the-directory-carries-what-proves-somebody}

SMB 需要 NT 哈希；S3 需要密码本身，因为 SigV4 要用它计算
HMAC；Kerberos 域需要由密码派生的密钥，而 NT
哈希并不是这个密钥。只持有其中一种的身份，只能服务某些
协议，无论此人输入什么，都无法服务另一些协议。因此 go-authn 的目录
记录**每个人能够证明什么**，而 `authnd check` 会在
重启任何东西之前，打印出谁可以获得 Kerberos 票据，谁永远
不能：

```
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself
```

这正是 authnd v0.11.0 自身的输出：[完整内容]({{< relref "/authnd/check.md" >}})。

## 由他人的工具来评判 {#judged-by-other-peoples-tools}

依据对某个协议的一种解读构建的测试夹具，只能印证这一种解读。
因此这些服务器由并非它们自己编写的客户端来读取：OpenLDAP 自带的
`ldapsearch` 绑定到 authnd，MIT 自带的 `kinit` 从其域获取票据，
OpenSSH 读取 authn-bridge 签发的证书和 KRL。
