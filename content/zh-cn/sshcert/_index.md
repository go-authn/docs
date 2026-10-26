---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "SSH 用户证书的 GÉANT / EuroHPC 域授权扩展，以及 sshcert-authorize：sshd 用来询问证书是否面向本主机的、故障即拒绝的命令。"
tags: [sshcert, ssh, eurohpc]
---

**来自联邦 CA 的证书本身并不构成对所有信任该 CA 的主机的
许可。** EuroHPC 联邦平台的 SSH CA 将证书所面向的主机
写入一个扩展 `ssh-domain-grant@core.aai.geant.org`，而 `sshd` 会忽略它。go-authn/sshcert
读取并写入该扩展，它的命令 `sshcert-authorize` 就是
`sshd` 用来强制执行该扩展的程序。纯 Go，`CGO_ENABLED=0`。这些页面描述
v0.1.9。

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.9
$ sshcert-authorize -version
sshcert-authorize v0.1.9
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | `AuthorizedPrincipalsCommand`：它检查什么、拒绝什么，以及 sshd 如何调用它 |

## 扩展 {#the-extension}

其数据是主机模式的紧凑 JSON 数组，如 `["login.example.org"]`。`*`
在单个标签内匹配**一个或多个**字符，名称比较时
不区分大小写：

| 模式 | 匹配 | 不匹配 |
|---|---|---|
| `login.example.org` | `login.example.org`、`LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`、`a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

读取是严格的：只接受编码器所写出的内容。不能有
空白，`]` 之后不能有任何内容，不能有 JSON 转义，不能重复，最多 64 个
模式，每个模式只能由字母、数字、连字符和 `*` 组成，标签长度为 1 到 63
字节，总长最多 253 字节，并且**最右侧的标签中不能有 `*`**。`null`、对象、
数字和嵌套数组均被拒绝。`[]` 被接受，但不授予任何主机。

存在但格式错误的授权绝不会被报告为不存在。这一差别
正是该命令的全部意义所在。

## 谁在使用它 {#who-uses-it}

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})**
  为客户端的 `ssh_domain_grants` 写入该扩展，并在写入前用本包的 `ValidatePattern`
  检查每个模式。
- **go-fileshare** 的 SFTP 服务器通过 `ssh_domains` 读取它，并拒绝
  没有授权的证书，除非设置了 `ssh_accept_ungranted`。
- **sshcert-authorize** 是针对普通 `sshd` 的同一项检查。

## 许可证 {#licence}

BSD-3-Clause。
