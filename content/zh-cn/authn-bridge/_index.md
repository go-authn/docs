---
title: "authn-bridge"
linkTitle: "authn-bridge"
weight: 20
description: "置于 SAML 联邦之前的 OpenID Connect 提供方：人员在自己所属的机构登录，应用程序获得令牌、SSH 证书和 X.509 客户端证书。"
tags: [authn-bridge, oidc, saml]
---

**人员在自己所属的大学登录，通过 RENATER 的 Fédération
Éducation-Recherche 或 eduGAIN，而应用程序得到 OpenID Connect 令牌。**
同一次登录还可以让 SSH 密钥获得认证、为基于 TLS 的 NFS 签发 X.509 客户端证书、
为 SMB 和 S3 设置应用密码，或注册 WireGuard 密钥。提供方可以吊销其所签发的内容，并且
会发布其已吊销内容的签名列表；已经发放的访问令牌
在过期之前仍然有效。纯 Go，`CGO_ENABLED=0`，单个
二进制文件。这些页面描述 v0.23.3。

```sh
go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3

authn-bridge keygen   --key /var/lib/authn-bridge/oidc.key --salt /var/lib/authn-bridge/salt
authn-bridge metadata --config /etc/authn-bridge > sp.xml   # register this with the federation
authn-bridge check    --config /etc/authn-bridge
authn-bridge          --config /etc/authn-bridge            # serve
```

在 v0.20.0 之前，该命令名为 `bridge`。这同时也是 iproute2 的
`/sbin/bridge`，几乎每个 Linux 系统都安装了它，而在 `PATH` 中
排在前面的那个会胜出。模块路径仍然是 `github.com/go-authn/bridge`。

## 为什么需要 bridge {#why-a-bridge}

科研联邦使用 SAML。它的成员是数百个身份
提供方，每个机构一个，列在联邦发布的签名元数据文档中。
今天编写的应用程序想要 OpenID Connect，并信任一个
提供方。authn-bridge 就是这一个提供方：一侧是 SAML 服务
提供方，向联邦注册一次；另一侧是 OpenID 提供方。

网关要为其后的每个应用程序决定每个人是谁，因此这个程序的大部分
内容都是拒绝。它拒绝联邦没有签名的元数据、
指称来自另一个机构域的人员的断言、IdP
无权管辖的组，以及会放行其中任何一项的配置。
无法安全提供服务的配置不会启动。

## 启动时它输出什么 {#what-it-prints-at-startup}

```
$ authn-bridge --config etc/bridge-admin.hcl
authn-bridge v0.23.3: http://127.0.0.1:28473 on 127.0.0.1:28473
metrics on 127.0.0.1:28475
admin API on unix:///tmp/authn/run/admin.sock
```

这是环回地址上的测试提供方（`http://` 签发方只在
环回主机上被接受）。它在监听**之前**获取联邦的元数据。无法指名任何
一个机构的提供方是无人能够通过它登录的，
因此没有元数据时它会退出而不是启动。

## 接下来去哪里 {#where-to-go-next}

| | |
|---|---|
| [安装]({{< relref "/authn-bridge/install.md" >}}) | 用户、目录、systemd 单元、密钥 |
| [配置]({{< relref "/authn-bridge/configuration.md" >}}) | 每个块、`check`，以及启动时拒绝什么 |
| [联邦一侧]({{< relref "/authn-bridge/federation.md" >}}) | 元数据、其签名者的指纹、scope，以及 IdP 可以断言什么 |
| [令牌]({{< relref "/authn-bridge/tokens.md" >}}) | ID 令牌、访问令牌、设备授权、应用密码、WireGuard 密钥 |
| [资源指示符]({{< relref "/authn-bridge/resources.md" >}}) | 每次针对客户端的一个资源服务器获取令牌（RFC 8707） |
| [证书]({{< relref "/authn-bridge/certificates.md" >}}) | SSH 证书、EuroHPC 配置档、用于 NFS 的 X.509 客户端证书 |
| [吊销]({{< relref "/authn-bridge/revocation.md" >}}) | 已签名的 KRL 和 CRL，以及 Shared Signals 发送方 |
| [管理 API]({{< relref "/authn-bridge/admin.md" >}}) | 禁用人员或机构、健康检查和指标 |

它所签署的列表由 [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})
为普通的 `sshd` 或 TLS 服务器读取，也由
[go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
读取，后者自行检查这些列表。

## 它不是什么 {#what-it-is-not}

- **单进程。** 有 `state` 块时，刷新令牌以及在 `/userinfo` 处
  被认可的访问令牌在重启后仍然保留。进行中的登录、授权码和
  设备授权则不会。状态是同步写入并在启动时读取的，因此
  同一数据库上的两个实例会各自错过对方写入的内容。
- 没有动态客户端注册，也没有前端或后端通道注销。
- 没有可添加的用户或组。人员之所以存在，是因为其机构为
  他们担保，而他们的组就是机构所断言的内容。

## 许可证 {#licence}

BSD-3-Clause。
