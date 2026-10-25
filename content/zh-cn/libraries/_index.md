---
title: "各个库，每个只回答一个问题"
linkTitle: "库"
weight: 50
description: "十四个 go-authn Go 模块：每个模块回答的问题、这些页面所描述的版本，以及它们为什么是独立的模块。"
tags: [库]
---

[authnd]({{< relref "/authnd/_index.md" >}}) 和
[authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) 等程序，是由
独立发布、独立版本管理并独立测试的模块构建而成。每个模块回答
**一个**问题，程序导入的是它所要提出的那些问题对应的模块。

它们全部是纯 Go，可用 `CGO_ENABLED=0` 构建。

| 模块 | 它回答的问题 | 这些页面描述的版本 | 导入路径 |
|---|---|---|---|
| [mfa]({{< relref "/libraries/mfa.md" >}}) | 是否有足够多、足够多种类的因素作出了回答，是哪些？ | v0.5.0 | `github.com/go-authn/mfa` |
| [totp]({{< relref "/libraries/totp.md" >}}) | 这个六位数字代码是否正确，以前是否用过？ | v0.4.2 | `github.com/go-authn/totp` |
| [fido]({{< relref "/libraries/fido.md" >}}) | 如何通过 64 字节报告与安全密钥通信？ | v0.6.2 | `github.com/go-authn/fido` |
| [keyfactor]({{< relref "/libraries/keyfactor.md" >}}) | *已注册的*那把密钥是否作出了回答，是否有人触摸过它？ | v0.4.2 | `github.com/go-authn/keyfactor` |
| [directory]({{< relref "/libraries/directory.md" >}}) | 某人是谁，什么可以证明其身份？ | v0.15.0 | `github.com/go-authn/directory` |
| [ldap]({{< relref "/libraries/ldap.md" >}}) | LDAP 服务器的字节是什么？ | v0.9.0 | `github.com/go-authn/ldap` |
| [krb5]({{< relref "/libraries/krb5.md" >}}) | 这张 Kerberos 票据对此服务是否有效？ | v0.3.1 | `github.com/go-authn/krb5` |
| [kdc]({{< relref "/libraries/kdc.md" >}}) | 域如何根据目录签发票据？ | v0.4.3 | `github.com/go-authn/kdc` |
| [oidc]({{< relref "/libraries/oidc.md" >}}) | 这个持有者令牌声称是谁在发出请求，是否应当相信？ | v0.4.1 | `github.com/go-authn/oidc` |
| [saml]({{< relref "/libraries/saml.md" >}}) | 联邦的身份提供方对此人说了什么？ | v0.4.1 | `github.com/go-authn/saml` |
| [krl]({{< relref "/libraries/krl.md" >}}) | 按 sshd 的回答，这个 SSH 证书或密钥是否已被吊销？ | v0.6.1 | `github.com/go-authn/krl` |
| [servercert]({{< relref "/libraries/servercert.md" >}}) | 守护进程的 TLS 服务器证书从哪里来？ | v0.5.2 | `github.com/go-authn/servercert` |
| [wireguard]({{< relref "/libraries/wireguard.md" >}}) | 这把 WireGuard 密钥是否可以连接，它是谁的？ | v0.1.1 | `github.com/go-authn/wireguard` |
| [scim]({{< relref "/libraries/scim.md" >}}) | 身份提供方刚刚创建、更改或删除了谁？ | v0.1.0 | `github.com/go-authn/scim` |

## 它们如何分组 {#how-they-group}

**认证因素**——人员是否在场。
[mfa]({{< relref "/libraries/mfa.md" >}})决定多少证明才足够，
不了解任何设备。[totp]({{< relref "/libraries/totp.md" >}})是一个
因素：来自手机的代码。[fido]({{< relref "/libraries/fido.md" >}})用
CTAP 与安全密钥通信，不了解任何策略；
[keyfactor]({{< relref "/libraries/keyfactor.md" >}})是同时
导入两者的那一个，把密钥变成一个因素。

**目录及其协议。**
[directory]({{< relref "/libraries/directory.md" >}})是模型：人员，
以及来源为其持有哪些凭据——密码、NT 哈希、
验证器、SSH 密钥、一次性代码密钥——此外，还有
描述人员但不证明任何事的属性。
[ldap]({{< relref "/libraries/ldap.md" >}})是作为服务器的 LDAP 线路协议，
以及可用来检查条目的目录模式，这些模式可从
OpenLDAP 文件读取或用 HCL2 编写；它如何作答则是处理程序的事。

**Kerberos，分为两部分。** [krb5]({{< relref "/libraries/krb5.md" >}})
*接受*票据：keytab、传入的 AP-REQ、传出的 AP-REP。
[kdc]({{< relref "/libraries/kdc.md" >}})*签发*票据，来自保存密码的
目录。

**联邦与令牌。** [saml]({{< relref "/libraries/saml.md" >}})是置于
RENATER 或 eduGAIN 等联邦之前的 SAML 2.0 服务提供方。
[oidc]({{< relref "/libraries/oidc.md" >}})验证提供方
签署的 OpenID Connect 令牌——即资源服务器一半，没有登录流程。
[scim]({{< relref "/libraries/scim.md" >}})是另一个方向：身份提供方调用的
SCIM 2.0 端点，用来创建、更新和删除你的应用程序的人员和
组。

**吊销与证书。** [krl]({{< relref "/libraries/krl.md" >}})
读取、写入并检查 OpenSSH 密钥吊销列表。
[servercert]({{< relref "/libraries/servercert.md" >}})从文件或 ACME 为守护进程提供
TLS 证书。

**[wireguard]({{< relref "/libraries/wireguard.md" >}})** 携带人员已向提供方注册的
WireGuard 公钥的签名列表，网关会将其转换为对端。

## 为什么它们是独立的模块 {#why-they-are-separate-modules}

**只接受票据的服务永远不会链接 KDC。** NFS 服务器
验证客户端出示的票据；它有一个 keytab，与域再无其他
关系。如果接受和签发是同一个模块，每个这样的服务器
都会带上它从不运行的票据签发代码路径，以及
KDC 读取人员所用的 directory 模块，而它从不使用该模块。

这是测量得到的，而不是意图。在只导入
`github.com/go-authn/krb5@v0.3.1` 的临时模块中：

```sh
$ GOWORK=off go list -deps . | grep go-authn
github.com/go-authn/krb5
$ GOWORK=off go list -m all | grep go-authn
github.com/go-authn/krb5 v0.3.1
```

对于导入 `github.com/go-authn/kdc@v0.4.3` 的模块，同样的命令
会列出 `github.com/go-authn/directory` 和 `github.com/go-authn/kdc`：签发
需要人员，接受则不需要。

同样的规则在其他地方也成立。`mfa` 不导入标准库之外的任何内容，
而 `fido` 不导入 `mfa`：只想让
密钥闪烁的程序不必携带策略包。`totp` 只依赖 `mfa`，而
`oidc` 完全没有依赖。`directory` 把它的 LDAP、SQL 和 HCL
来源放在子包中：核心包不导入标准库之外的任何内容，
而 `sqldir` 接受 `*sql.DB`，因此数据库驱动由
程序自行选择。

## 每个页面都有相同的组成部分 {#every-page-has-the-same-parts}

问题；所述版本的 `go get` 行；一个能针对该版本
编译的最小示例；该模块依据其代码拒绝什么；
以及它对照什么进行检查——不是本实现的那个实现，
在其 CI 或测试中指名。当 README 与代码不一致时，页面
以代码为准。
