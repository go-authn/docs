---
title: "kdcd — 面向单个域的 Kerberos KDC 守护进程"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd 是构建在 kdc 库之上的程序：基于 UDP 和 TCP 的 AS 与 TGS、一个 HCL 文件、每个秘密都是文件，以及一个可选的双向 TLS 监听器，为没有密码的人铸造 TGT。"
tags: [库, kerberos, 目录, kdcd]
---

**[kdc]({{< relref "/libraries/kdc.md" >}}) 库如何作为服务运行？**
`kdcd` 是面向单个域的 Kerberos KDC 守护进程，构建在库
[go-authn/kdc](https://github.com/go-authn/kdc) 之上。它通过 UDP 和 TCP 应答 AS 与 TGS 请求，
并且可选地，通过双向 TLS 为在别处证明了自己身份的人（在
[go-authn/bridge](https://github.com/go-authn/bridge) 的 passkey 登录）**铸造 TGT**。
库持有协议；本程序持有套接字、配置，以及关于秘密的规则。

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

安装（二进制文件名为 `kdcd`：MIT 的 KDC 是 `krb5kdc`，Heimdal 的是 `kdc`）：

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

纯 Go，`CGO_ENABLED=0`；发布版附带 `SHA256SUMS` 清单，每个二进制文件还有一份构建来源证明。
作为服务：`packaging/systemd/`（单元文件和 sysusers 文件；见[运行](#running-it)）。

## 目录必须持有什么 {#what-the-directory-must-hold}

KDC 用那个人的长期密钥解密客户端的预认证，因此只有当来源持有**密码**时，才能为该人处理
**AS-REQ**：带 `password_file` 的 `user` 块，或返回密码的 `users "sql"` 块。只能*验证*
密码的来源（对他人 LDAP 的绑定、哈希）无法处理 AS-REQ，无论它回答“这是密码吗”回答得多好。
这是 Kerberos 的性质，在
[库的文档](https://github.com/go-authn/kdc#readme)和
[kdc 页面]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}})中有解释。

passkey 时代的域不需要这些。**没有密码**的人（`user "alice" {}` 块，或任意 `users` 块的一行）
在目录中，没有密钥，AS-REQ 会以 `KDC_ERR_NULL_KEY` 被拒绝。他们只能通过 **mint 监听器**
获得 TGT，由对其完成认证的调用方提供。`kdcd` 不增加任何自己的密码路径：没有标志、没有环境变量、
没有内联值；`password_file` 的存在是因为库的 AS 路径需要它。

## 配置 {#configuration}

一个 HCL 文件。其中没有任何秘密；每个秘密都是一个文件。

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: any number of these, in any mix.
user "alice" {}                           # a person with no password: mint only
user "bob" { password_file = "/etc/kdcd/bob.pw" }

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"
  users    = "select login, password from staff"
}
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/kdcd/bind.pw"
}
```

`users` 块就是 [go-authn/directory/hcldir](https://github.com/go-authn/directory) 的块，
原样使用。只能验证密码的来源，例如对 LDAP 服务器的绑定，会给 mint 调用方一个用来核对主体的
目录，但无法处理 AS-REQ。

`kdcd check --config FILE` 读取并构建守护进程会构建的一切，打开目录，不监听任何地址，
并打印它所提供的内容：域、地址、keytab 的主体（名称、kvno、etype；绝不打印密钥）、
目录持有的人数、mint 调用方。退出状态 0 且最后一行为 `ok`，或者是第一个拒绝。

### 它拒绝启动的情形 {#what-it-refuses-to-start-with}

| 被拒绝的 | 原因 |
| --- | --- |
| 组或其他用户**可读或可写**的 keytab、mint 密钥、密码文件、DSN 或绑定密码，或属于 root 和守护进程之外的 uid 的 | 另一个账户能读到的副本，可以为域中每个人伪造票据 |
| 内联书写的秘密（`password = "..."` 不是一个参数） | 秘密存放在文件中，绝不放在配置、其备份或日志里 |
| 组或其他用户可写的配置文件 | 谁能写它，谁就能选择 mint 调用方 |
| 没有 `krbtgt/REALM` 密钥，或缺少所列服务的 keytab，**以 aes256-cts-hmac-sha1-96**（库所签发的唯一类型） | 它会启动，然后在第一次 `kinit` 时失败 |
| `listen` 中的通配符或主机名（要求 IP 字面量），以及 `mint` 的**任何**通配符 | KDC 和 mint 监听器位于某人选定的接口上 |
| 没有调用方、没有证书或证书已过期的 `mint` 块 | 库把没有调用方读作“mint 关闭”；这里把它说出来，而不是悄悄地什么也不铸造 |
| 没有 `start_tls` 而连向另一台机器的 `ldap://` | 每个密码都会按输入的原样穿过网络 |

秘密文件只被打开**一次**，并且检查的是已打开的文件（常规文件、模式、属主），因此检查不会针对
一个文件而读取针对另一个文件（模型是 go-fileshare 的 `readKeytab`）。`dsn_file` 和
`bind_password_file` 在以同样方式检查之后，由 `hcldir` 按名称读取。

## mint 的信任模型 {#the-mint-trust-model}

向 `POST https://<mint address>/mint` 发送 `{"principal": "alice", "lifetime_seconds": 36000}`，
返回一个 KRB-CRED（RFC 4120 5.8），其中装有 `alice` 的 TGT，由调用方交给此人的机器
（[go-authn/kinit](https://github.com/go-authn/kinit) 把它载入 Windows 登录会话）。其约束是：

- **调用方就是 TLS 客户端证书**，由监听器对照 `client_ca_file` 验证（TLS 1.3，
  `RequireAndVerifyClientCert`）：没有证书，或证书不是该 CA 签发的连接，在读取任何 HTTP 之前
  就在握手阶段失败。通过验证的证书随后通过 **URI subjectAltName** 与 `callers` 精确匹配；
  通过验证但未列出的证书得到 `403`。头部或正文中没有任何内容指明调用方。
- **列在 `callers` 中的任何一方，都能为目录中的任何主体获得 TGT**（绝不是服务，绝不是目录中
  没有的名称），而无需此人的密钥。域所信任的是调用方对此人的认证，所以调用方与 KDC 的
  keytab 同样受信任。每个身份提供方列一个，给每个单独的证书，并让 `client_ca_file` 成为
  不签发任何其他东西的 CA。
- 票据为 `INITIAL | PRE-AUTHENT`，绝不可续期、可转发或可代理；其有效期取请求、`lifetime`
  和十小时三者中的最小值。
- 会话密钥由 `crypto/rand` 生成，仅在应答中离开进程一次，且绝不记入日志。应答带
  `Cache-Control: no-store`。KRB-CRED 以明文携带密钥，所以**TLS 通道就是加密**：
  请把监听器放在内部接口上。
- 只提供 `/mint`，带有超时和头部大小限制。每一次 mint 和每一次拒绝，都会连同调用方的 URI
  和所请求的主体一起记入日志。

完整的威胁模型是库的拉取请求
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38) 的威胁模型，并附有库 README 的
[铸造一节](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)和
[审计说明](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)；
这里不重复其中任何内容，也不削弱它。
[go-authn/bridge](https://github.com/go-authn/bridge) 的 `kerberos` 块是调用方这一侧：
其 `kdc_url` 是 `https://<mint address>/mint`，其 `ca_file` 签发上面的 `cert_file`，
其客户端证书的 URI 名称是 `callers` 中的一项。

## 运行 {#running-it}

`packaging/systemd/kdcd.service` 以 `packaging/sysusers.d/kdcd.conf` 中的系统用户运行它，
并采用 [authn-bridge](https://github.com/go-authn/bridge) 单元的加固。88 端口是特权端口，
所以该单元恰好授予 `CAP_NET_BIND_SERVICE`，别无其他。

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

秘密应属于 `kdcd`（或 root），模式为 0600；组为 `kdcd` 的 0640 被有意拒绝。更改配置就是
`systemctl restart kdcd`（守护进程不重新加载；客户端会重试被拒绝的连接）。

在 Windows 上，模式位没有意义，也不检查：请把文件放在只有运行该服务的账户才能读取的位置。

## 不在此处 {#not-here}

跨域、PKINIT、FAST、可续期或后置日期的票据、kadmin 协议，以及 aes256-cts-hmac-sha1-96
之外的任何加密类型，都是库自身的限制（[go-authn/kdc](https://github.com/go-authn/kdc#readme)）。
`kdcd` 目前还没有重新加载，也没有指标端点。

## 参考 {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd)，v0.1.0。
