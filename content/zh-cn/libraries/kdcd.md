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

## 没有密码 {#no-passwords}

**`kdcd` 中没有密码路径，也无法开启**（v0.2.0 中移除；v0.1.0 有 `password_file`）。
这里的人没有长期密钥，所以针对某人的 **AS-REQ** 无论客户端发送什么，按设计都以
`KDC_ERR_NULL_KEY` 应答。人只能通过 **mint 监听器**获得 TGT，由用 passkey 对其完成认证的
调用方（go-authn/bridge）提供。

- 目录说明**谁存在，以及他们的组**。来源所携带的内容，除名称外都到不了 KDC：每个身份在库看到
  之前都被仅以名称重建（`nameOnly`），所以即使来源确实公布了密码，也不会派生出密钥。
  下面加载时的拒绝是为了说明原因，而不是唯一的防线。
- 服务和 `krbtgt/REALM` 把密钥保存在 keytab 中：**随机密钥**，绝不由密码派生（例如，用您的
  keytab 工具从 `/dev/urandom` 取 32 字节生成）。
- `password_file`、指名密码或 NT 哈希列的 `users` 查询或属性、`bind_password_file`、
  `bind_dn`（简单绑定就是密码），以及含有密码的 DSN：加载时被拒绝，并指明移除及其版本。
- `ldap` 来源以**匿名**方式读取。通过客户端证书或 SASL EXTERNAL 的服务绑定目前不可用，因为
  `go-authn/directory` 的 `hcldir.Block` 没有对应字段；在有之前，`bind_dn` 会被拒绝。

库一侧的说明见 [kdc 页面]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}})。

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

# The directory: who exists. Any number of these, in any mix.
user "alice@poc.test" {}                  # a name; a TGT only through mint

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"              # no password in it: a client certificate or a socket
  users    = "select login as name from staff"
}
users "ldap" {                            # read anonymously
  url      = "ldaps://ldap.example.org"
  base_dn  = "ou=people,dc=example,dc=org"
}
```

`users` 块就是 [go-authn/directory/hcldir](https://github.com/go-authn/directory) 的块；
kdcd 拒绝其中携带密码的部分（见上文）。

**密钥：文件或引用。** `keytab_file` 和 `key_file`（在 `mint` 中）指向一个文件，按下文所述检查。`keytab_from` 和 `key_from` 则接受 secretsource 引用，例如 `systemd-creds:kdc-keytab`：由 systemd 为服务解密的凭据（`LoadCredentialEncrypted=`，用 `systemd-creds encrypt --with-key=host+tpm2` 封存，切勿只用 `--tpm2-pcrs=7`）。二者择一，不可同时设置。`_from` 键中拒绝 `file:`。`keytab_file` 保留且不弃用：keytab 和密钥是二进制的，`file:` 会去掉末尾一个换行（以字节 0x0a 结尾的密钥会被破坏），而引用最多 4096 字节，所以更大的 keytab 仍放在 `keytab_file`。自 secretsource v0.9.0 起，`file:` 还会拒绝符号链接和属于其他 uid 的文件。`dsn_file` 不含密码，因此没有 `_from`。

`kdcd check --config FILE` 读取并构建守护进程会构建的一切，打开目录，不监听任何地址，
并打印它所提供的内容：域、地址、keytab 的主体（名称、kvno、etype；绝不打印密钥）、
目录持有的人数、mint 调用方。退出状态 0 且最后一行为 `ok`，或者是第一个拒绝。

### 它拒绝启动的情形 {#what-it-refuses-to-start-with}

| 被拒绝的 | 原因 |
| --- | --- |
| 组或其他用户**可读或可写**的 keytab、mint 密钥或 DSN 文件，或属于 root 和守护进程之外的 uid 的 | 另一个账户能读到的副本，可以为域中每个人伪造票据 |
| **任何密码路径**：`password_file`（即使为空）、`bind_password_file`、`bind_dn`、指名 `password`、`passwd`、`nt_hash`、`userPassword`... 的 `users`/`groups` 查询或属性、携带密码的 DSN | v0.2.0 中移除：这里没有人拥有密钥；消息会这样说明。查询和 DSN 的检查尽力而为；它们漏掉的由 `nameOnly` 兜住 |
| 内联书写的秘密（`password = "..."` 不是一个参数） | 秘密存放在文件中，绝不放在配置、其备份或日志里 |
| 组或其他用户可写的配置文件 | 谁能写它，谁就能选择 mint 调用方 |
| 没有 `krbtgt/REALM` 密钥，或缺少所列服务的 keytab，**以 aes256-cts-hmac-sha1-96**（库所签发的唯一类型） | 它会启动，然后在第一次 `kinit` 时失败 |
| `listen` 中的通配符或主机名（要求 IP 字面量），以及 `mint` 的**任何**通配符 | KDC 和 mint 监听器位于某人选定的接口上 |
| 没有调用方、没有证书或证书已过期的 `mint` 块 | 库把没有调用方读作“mint 关闭”；这里把它说出来，而不是悄悄地什么也不铸造 |
| 没有 `start_tls` 而连向另一台机器的 `ldap://` | 每个密码都会按输入的原样穿过网络 |

秘密文件只被打开**一次**，并且检查的是已打开的文件（常规文件、模式、属主），因此检查不会针对
一个文件而读取针对另一个文件（模型是 go-fileshare 的 `readKeytab`）。`dsn_file` 在以同样方式检查之后，
由 `hcldir` 按名称读取。

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

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd)，v0.2.0。
