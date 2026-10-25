---
title: "安装 authn-bridge"
linkTitle: "安装"
weight: 10
description: "一个静态用户、三个目录和一个加固的 systemd 单元：从发布的二进制文件到运行中的 authn-bridge 服务。"
tags: [authn-bridge, 安装, systemd]
---

代码仓库提供了单元及其运行所用的用户：
`packaging/systemd/authn-bridge.service` 和
`packaging/sysusers.d/authn-bridge.conf`。除非另有说明，下面的一切都以 root 运行。

| | |
|---|---|
| `/usr/local/bin/authn-bridge` | 二进制文件 |
| `/etc/authn-bridge/*.hcl` | 配置，按名称顺序读取；`root:authn-bridge`，`0750`，文件 `0640` |
| `/var/lib/authn-bridge/` | 密钥、主体盐值、SQLite 状态、已签发的证书、禁用列表；`authn-bridge`，`0700` |
| `/run/authn-bridge/` | 管理套接字，当配置要求时 |

## 二进制文件 {#the-binary}

每个发布版本都带有适用于 Linux、macOS 和 Windows（amd64 与
arm64）的 `authn-bridge-<os>-<arch>`、一个 `SHA256SUMS` 清单，以及每个
二进制文件的构建溯源证明；[验证下载]({{< relref "/security/verifying-releases.md" >}})
说明了如何检查这两者。或者自行构建，这会将版本记录在二进制文件中：

```
$ go install github.com/go-authn/bridge/cmd/authn-bridge@v0.23.3
$ authn-bridge --version
authn-bridge version v0.23.3
```

路径很重要：自 v0.20.0 起，程序位于 `internal/app`，而
命令位于 `cmd/authn-bridge`，因此 `go install github.com/go-authn/bridge@...`
什么也构建不出来。

## 用户，以及为什么它不是动态用户 {#the-user-and-why-it-is-not-a-dynamic-one}

```sh
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
install -D -m 0644 authn-bridge.conf /etc/sysusers.d/authn-bridge.conf
systemd-sysusers                       # creates the authn-bridge user and group
install -m 0644 authn-bridge.service /etc/systemd/system/authn-bridge.service
systemctl daemon-reload

install -d -m 0750 -o root -g authn-bridge /etc/authn-bridge
install -d -m 0700 -o authn-bridge -g authn-bridge /var/lib/authn-bridge
```

单元指定的是 `User=authn-bridge`，而不是 `DynamicUser=`。签名密钥、
主体盐值、SAML 密钥和证书颁发机构都在首次启动**之前**
生成，会使用多年，并且在重新安装和
从备份恢复时必须保持同一个所有者。动态用户的 UID 是在服务启动时才获得的。

## 密钥 {#the-keys}

请以服务的用户身份运行 `keygen`，使其拥有它所写入的内容。它会拒绝
覆盖已经存在的文件：

```
$ mkdir var/nfs-ca
$ authn-bridge keygen --key var/oidc.key --salt var/salt --ssh-ca var/ssh-ca --x509-ca var/nfs-ca
wrote var/ssh-ca; its public half, for go-fileshare's trusted_user_ca_file:
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNOYvUrAPdRTB+38aml+twPN+2k1shD3l62v8NxrIje go-authn-bridge-ca
wrote var/oidc.key
wrote var/nfs-ca/ca.crt and its key; the certificate is what go-fileshare trusts for NFS over TLS
wrote var/salt -- keep it: a new salt is a new subject for everybody
$ authn-bridge keygen --key var/oidc.key
authn-bridge: open var/oidc.key: file exists
```

在服务器上，路径位于 `/var/lib/authn-bridge` 之下，命令是
`runuser -u authn-bridge -- authn-bridge keygen ...`。

| 标志 | 写入 | 用途 |
|---|---|---|
| `--key` | RSA 3072 密钥 | ID 令牌（RS256），发布在 `/jwks` |
| `--salt` | 32 个随机字节 | 每个 `sub`，即在它之下计算的 HMAC |
| `--access-token-key` | P-256 密钥 | 改用 ES256 为访问令牌签名，短得多 |
| `--ssh-ca` | OpenSSH 格式的 Ed25519 密钥 | [SSH 证书]({{< relref "/authn-bridge/certificates.md" >}})和 KRL 的签名 |
| `--x509-ca DIR` | `DIR/ca.key`（P-256）和 `DIR/ca.crt`，有效期十年，路径长度 0 | NFS 客户端证书和 CRL |

{{< callout type="warning" >}}
**备份盐值，并且绝不要更改它**

新的盐值会给每个人一个新的 `sub`，于是每个依赖方都会
看到一个新的人。卸载时删除它同样如此。
{{< /callout >}}

SAML 密钥和证书用 `openssl` 生成：它们是联邦所注册的内容，
也是每个 IdP 加密的对象。密钥必须是 RSA（IdP 用 RSA-OAEP
向它加密）。它不是 TLS 证书，也不随 TLS 证书
而更改。

```sh
runuser -u authn-bridge -- sh -c 'umask 077; openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
  -subj "/CN=login.example.org" \
  -keyout /var/lib/authn-bridge/saml.key -out /var/lib/authn-bridge/saml.crt'
```

联邦的元数据签名证书来自联邦，其 SHA-256
指纹也是如此：请从联邦的网页获取指纹，绝不要从与证书相同的下载中获取。参见
[联邦一侧]({{< relref "/authn-bridge/federation.md" >}})。

## 单元 {#the-unit}

简而言之，它授予的权限：

- `Type=exec`、`Restart=on-failure`、`RestartSec=5s`、`TimeoutStopSec=20s`。
  提供方在收到 `SIGTERM` 后十秒内关闭其监听器。
- `StateDirectory=`、`RuntimeDirectory=`（均为 `0700`）和
  `ConfigurationDirectory=`（`0750`），`UMask=0077`。在
  `ProtectSystem=strict` 下，其他一切都是只读的。
- 没有 capability（`CapabilityBoundingSet=` 和 `AmbientCapabilities=` 为空），
  `NoNewPrivileges=`、`PrivateUsers=`、`PrivateTmp=`、`PrivateDevices=`、
  `PrivateIPC=`、`ProtectHome=`，内核、时钟、主机名和控制
  组均受保护。
- `RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6`：TCP 用于监听器、
  元数据、ACME CA 和数据库；套接字用于管理 API。
- `SystemCallFilter=@system-service`，减去 `@privileged @resources`，被拒绝时
  返回 `EPERM` 而不是终止进程。

它会等待 `network-online.target`，因为元数据是在提供方监听之前
获取的。

```sh
systemctl enable --now authn-bridge
journalctl -u authn-bridge -n 20
```

日志中的第一行就是[概览]({{< relref "/authn-bridge/_index.md#what-it-prints-at-startup" >}})中
所示的那一行。

### 更改需要重启 {#changes-need-a-restart}

配置只读取一次。单元没有 `ExecReload=`，因此 `systemctl
reload` 会被拒绝，而不是假装执行。`SIGHUP`（来自 logrotate，或出于习惯）
会被捕获、记录并忽略。若交给 Go 的默认行为，它会终止进程，
而 systemd 会将其视为正常退出，`Restart=on-failure` 不会
重启它：

```
SIGHUP: ignored, nothing is reloaded; restart the service to apply a configuration change (TLS certificate files are re-read on their own)
```

TLS 证书文件是例外：它们在更改时会被重新读取。

### 443 端口 {#port-443}

默认监听器是 `127.0.0.1:8080`，位于 TLS 反向代理之后，不需要
任何 capability。若要自己在 443 端口提供 TLS（`cert_file` 或 `acme`），
提供方需要 `CAP_NET_BIND_SERVICE`，并且必须离开私有用户
命名空间，因为在其中持有的 capability 不适用于主机的
网络：

```ini
# /etc/systemd/system/authn-bridge.service.d/port-443.conf
[Service]
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
PrivateUsers=no
```

## 升级与回退 {#upgrading-and-going-back}

请先备份 `/var/lib/authn-bridge`：它保存着密钥和盐值，
无法重新生成。保留可用的二进制文件，安装新的，然后重启：

```sh
cp -p /usr/local/bin/authn-bridge /usr/local/bin/authn-bridge.previous
install -m 0755 authn-bridge-linux-amd64 /usr/local/bin/authn-bridge
systemctl restart authn-bridge
```

回退就是用 `authn-bridge.previous` 做同样的事。较新的版本可能附带
较新的单元：请将其与你的单元比较，安装它，并在重启之前
执行 `systemctl daemon-reload`。

### 从 `bridge` 迁移 {#coming-from-bridge}

配置不变；只有命令和发布的资产
改了名。请更改每个运行 `bridge` 的单元、脚本、cron 作业和 `bearer_token_command`。
日志行和错误前缀现在写作 `authn-bridge`，因此匹配 `bridge v0.` 的
告警必须改为匹配 `authn-bridge v0.`。指标名称
（`bridge_*`）、`bridge_state` 表和用户侧缓存
（用户配置目录中的 `go-authn-bridge`，在
Linux 上为 `~/.config`）保持不变，因此 `authn-bridge token` 会重用 `bridge`
缓存的登录。
