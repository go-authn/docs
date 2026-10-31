---
title: "安装 authnd"
linkTitle: "安装"
weight: 10
description: "发布的二进制文件及其检查方法、authnd 账户、systemd 单元及其授予的权限，以及升级、回滚和移除。"
tags: [authnd, 安装, systemd]
---

代码仓库中带有 systemd 主机所需的两个文件：
`packaging/sysusers.d/authnd.conf`（账户）和
`packaging/systemd/authnd.service`（单元）。本页解释这两个文件以及
相关的步骤。go-pkgx 的带版本服务以后会替你完成这些；
目前它们尚不存在。

## 发布的二进制文件 {#the-release-binary}

每个标签都会发布适用于 linux、darwin 和 windows（amd64
与 arm64，windows 上带 `.exe`）的 `authnd-<os>-<arch>`，以 `CGO_ENABLED=0` 构建，另有 `SHA256SUMS`
清单，以及针对每个二进制文件的构建溯源证明。

```sh
version=v0.13.0
arch=amd64          # or arm64
base=https://github.com/go-authn/authnd/releases/download/$version

curl -fsSLO "$base/authnd-linux-$arch"
curl -fsSLO "$base/SHA256SUMS"

sha256sum -c SHA256SUMS --ignore-missing                      # the bytes the release published
gh attestation verify "authnd-linux-$arch" --repo go-authn/authnd   # built by the release workflow, at that tag
```

只要有一项检查失败就停下来。发布工作流拒绝发布其报告的版本
与发布所用标签不完全一致的二进制文件，因此版本
是可以比对的：

```
$ authnd --version
authnd version v0.13.0
```

### 只构建你想要的部分 {#building-only-what-you-want}

服务器始终存在；两个构建标签可以去掉人员的来源：
`-tags nosql` 去掉三个数据库驱动（通过 pgx 的 PostgreSQL、
MySQL/MariaDB、通过 modernc.org/sqlite 的 SQLite）以及 `users "sql"` 块；
`-tags noldap` 去掉 LDAP 客户端和 `users "ldap"` 块。若配置指名了
该二进制文件构建时未包含的块，会收到明确的提示——
*this binary was built without SQL support (-tags nosql)*——而不是说
该块不存在。发布的二进制文件不带任何标签构建。

## 账户 {#the-account}

```
#Type Name   ID Description                          Home           Shell
u     authnd -  "authnd LDAP directory and Kerberos KDC" /var/lib/authnd -
```

这是 sysusers.d 的静态账户，**不是** `DynamicUser=`。authnd
读取的文件——密码文件、DSN、keytab、TLS 密钥——都是预先授予
`authnd` 组的机密，而[密码更改]({{< relref "/authnd/passwords.md" >}})
会写回其中。动态 uid 在服务启动之前并不存在，
而它所写的文件会属于一个日后可能代表别人的数字。

这两个文件来自发布标签的 `packaging/` 目录，与
二进制文件的版本相同：把该目录复制到二进制文件旁边，可以来自该标签的
检出副本，或者对于 v0.13.0，来自
<https://github.com/go-authn/authnd/tree/v0.13.0/packaging>。

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd
sudo install -m 0644 packaging/sysusers.d/authnd.conf  /usr/lib/sysusers.d/authnd.conf
sudo systemd-sysusers /usr/lib/sysusers.d/authnd.conf
sudo install -m 0644 packaging/systemd/authnd.service /etc/systemd/system/authnd.service
sudo systemd-analyze verify /etc/systemd/system/authnd.service
sudo systemctl daemon-reload
```

## 单元授予了什么，以及原因 {#what-the-unit-grants-and-why}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authnd --config /etc/authnd
Restart=on-failure
RestartSec=5s

User=authnd
Group=authnd
UMask=0077

AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=yes

StateDirectory=authnd
StateDirectoryMode=0700

ProtectSystem=strict
```

单元的其余部分是常见的加固设置（`ProtectHome`、`PrivateTmp`、
`PrivateDevices`、`ProtectProc=invisible`、内核和 cgroup 保护、
`MemoryDenyWriteExecute`、`SystemCallFilter=@system-service`、
`RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX`）。它有三项
**有意省略**：

| | |
|---|---|
| `ExecReload=` | authnd 没有重新加载功能。它只读取一次配置、证书和 keytab；参见[运行]({{< relref "/authnd/operations.md" >}}) |
| `PrivateUsers=` | 在用户命名空间内，`CAP_NET_BIND_SERVICE` 不再适用于主机的网络，对 389 的绑定会被拒绝 |
| `ProcSubset=pid` | 它会隐藏 `/proc/sys`（Go 在那里读取 `net/core/somaxconn`），使每个监听器的 backlog 退回到 Go 的后备值 128 |

`IPAddressAllow=`/`IPAddressDeny=` 同样没有设置：哪些网络可以查询
目录由站点自行决定，写在 drop-in 中：

```sh
sudo systemctl edit authnd
```

```ini
[Service]
IPAddressDeny=any
IPAddressAllow=localhost 10.0.0.0/8
```

这唯一的 capability 用于特权端口：LDAP 389、LDAPS 636，以及
通过 UDP 和 TCP 的 Kerberos 88。同一台机器上的 PostgreSQL 或 MariaDB 通过
其套接字访问，只读文件系统允许这样做。状态
目录 `/var/lib/authnd` 用于 SQLite 数据库；authnd 自身不保存任何
状态——第二因素的锁定计数保存在内存中，并在每次重启时
重置。

## 配置目录 {#the-configuration-directory}

```sh
sudo install -d -o root -g authnd -m 0750 /etc/authnd
```

其中每个文件都是 `root:authnd`，权限 `0640`。机密放在由
`*_file` 键指名的文件中，而不是内联写入：文件有权限，而别人
粘贴的配置没有。在 `ProtectSystem=strict` 下，服务不能写入
`/etc` 之下，这对配置是正确的，对人员自己更改的
密码却是错误的——请为这些密码单独准备一个目录：

```sh
sudo install -d -o authnd -g authnd -m 0700 /etc/authnd/passwords
sudo systemctl edit authnd
```

```ini
[Service]
ReadWritePaths=/etc/authnd/passwords
```

为什么是这个目录而不是文件，在
[更改密码]({{< relref "/authnd/passwords.md#where-the-new-password-is-written" >}})中有说明。

| 键 | 默认值 | |
|---|---|---|
| `base_dn` | —（必需） | 树的根，例如 `dc=example,dc=org`；不含 `=` 的值会被拒绝 |
| `listen` | `127.0.0.1:3893` | 一个地址。默认环回：目录一启动就出现在每个接口上，这是应当有人有意作出的决定。需要 LDAP 和 LDAPS 的站点运行两个实例 |
| `reader "<dn>"` | 无 | 可以搜索的服务账户；参见[谁可以读取]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}}) |
| `refresh` | `60s` | 每个来源被重新读取的频率；`0` 表示关闭；参见[运行]({{< relref "/authnd/operations.md" >}}) |
| `max_age` | 未设置 | 一旦所提供的数据比它更旧就拒绝过期数据（`unavailable`）；参见[运行]({{< relref "/authnd/operations.md" >}}) |
| `cert_file`、`key_file`、`starttls`、`publish_nt_hash`、`samba` | 关闭 | [TLS]({{< relref "/authnd/tls.md" >}}) |
| `user`、`group`、`users` | — | [人员]({{< relref "/authnd/people.md" >}})；至少一个 `user` 或 `users` 块 |
| `kerberos` | 无 | [域]({{< relref "/authnd/kerberos.md" >}}) |
| `mfa` | 无 | [第二因素]({{< relref "/authnd/mfa.md" >}}) |
| `oidc` | 无 | [绑定时使用令牌]({{< relref "/authnd/tokens.md" >}}) |

配置中的相对路径相对于进程运行所在的目录解析，
而不是配置文件所在的目录；单元从 `/` 运行，因此
请写绝对路径。

每次启动之前：

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl enable --now authnd
journalctl -u authnd
```

`check` 在[它自己的页面]({{< relref "/authnd/check.md" >}})中介绍；
以 `authnd` 身份运行它，也能证明该账户可以读取每个文件。

## 升级、回滚、移除 {#upgrade-roll-back-remove}

在新二进制文件替换旧二进制文件之前，先用**新的**二进制文件检查配置，
并保留旧的二进制文件。新二进制文件先安装在旧文件旁边：
这样它就成为可执行文件，并位于 `authnd` 账户可以
运行它的位置。

```sh
sudo install -m 0755 "authnd-linux-$arch" /usr/local/bin/authnd.new
sudo -u authnd /usr/local/bin/authnd.new check /etc/authnd
sudo cp /usr/local/bin/authnd /usr/local/bin/authnd.previous
sudo mv /usr/local/bin/authnd.new /usr/local/bin/authnd
sudo systemctl restart authnd
authnd --version
```

将新标签处的 `packaging/` 与已安装的内容进行比较（v0.12.0 的与
v0.11.1 的相同，没有变化）。回滚就是从
`authnd.previous` 做同样的安装，然后重启。

从 v0.10.x 到 v0.11.0，上面的 `check` 是关键的一步：
带有 `publish_nt_hash = true` 而没有
[`samba` 块]({{< relref "/authnd/tls.md#the-samba-block" >}})的配置会在
这一步被拒绝，而不是在重启时；表格之后的各行会说明谁
不再是 `posixAccount`，以及哪些组不再是 `posixGroup`
（[条目]({{< relref "/authnd/entries.md" >}})）。

⛔ 从 v0.11.1 到 v0.12.0，无论如何都要升级：v0.11.1 的发布二进制文件
由 Go 1.27.2 构建，受 GO-2026-6809（crypto/x509）影响，而由
Go 1.27.3 构建的 v0.12.0 不受影响。配置无需改动；要提供站点自己的
模式，请参见[站点模式]({{< relref "/authnd/schemas.md" >}})，
并用绝对路径指名这些文件，因为 systemd 单元的工作目录是 `/`。

移除它：

```sh
sudo systemctl disable --now authnd
sudo rm /etc/systemd/system/authnd.service
sudo rm -r /etc/systemd/system/authnd.service.d     # if a drop-in was added
sudo systemctl daemon-reload
sudo rm /usr/local/bin/authnd /usr/local/bin/authnd.previous /usr/lib/sysusers.d/authnd.conf
```

`/etc/authnd`、`/var/lib/authnd` 和 `authnd` 账户会保留：
前两者保存着人员的凭据，而被重用的 uid 可能
获得别人的文件。请有意识地逐一移除它们。
