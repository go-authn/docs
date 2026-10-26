---
title: "安装 authn-revokd"
linkTitle: "安装"
weight: 10
description: "作为加固的 systemd 服务，或作为定时器上的一次性任务运行 authn-revokd，以及如何让 sshd 和 TLS 服务器接入它所写出的内容。"
tags: [authn-revokd, 安装, systemd]
---

代码仓库在 `packaging/` 中提供了三个单元和一个账户：
`authn-revokd.service`（守护进程）、`authn-revokd-once.service` 与
`authn-revokd-once.timer`（替代方案），以及
`sysusers.d/authn-revokd.conf`。

| 路径 | 内容 | 所有者，权限 |
|---|---|---|
| `/usr/local/bin/authn-revokd` | 二进制文件 | root，`0755` |
| `/usr/lib/sysusers.d/authn-revokd.conf` | `authn-revokd` 系统账户 | root，`0644` |
| `/etc/systemd/system/authn-revokd.service` | 守护进程 | root，`0644` |
| `/etc/authn-revokd/revokd.hcl` | 配置，即默认的 `-config` | root，`0644` |
| `/etc/authn-revokd/ca/` | 列表必须据以签名的 CA 密钥和证书 | root，`0755`；其中的文件为 `0644` |
| `/var/lib/authn-revokd/` | `StateDirectory=`，唯一可写的位置 | authn-revokd，`0755` |
| `/var/lib/authn-revokd/state/` | `state_dir`：已验证的副本 | authn-revokd，`0700` |
| `/var/lib/authn-revokd/sshd.krl` | 一个输出：`sshd` 所读取的内容 | authn-revokd，`0644` |

**请将输出写到 `/var/lib/authn-revokd`，并让服务器指向那里。**
输出先写在其最终名称旁边，然后重命名覆盖，因此它的
*目录*必须可写。如果让 `/etc/ssh` 可写，`authn-revokd`
账户就能替换 `sshd_config`。输出为 `0644`，尽管有 `UMask=0077`
仍会显式 chmod，使以自己的用户运行的 `sshd` 和 TLS 服务器
可以读取它们；状态保持 `0700`。

## 二进制文件、账户、单元 {#the-binary-the-account-the-unit}

每个发布版本都带有适用于 Linux、macOS 和 Windows（amd64 与
arm64）的 `authn-revokd-<os>-<arch>`，附带 `SHA256SUMS` 和构建溯源信息
（[验证下载]({{< relref "/security/verifying-releases.md" >}})）。或者
`go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.6`。

账户和单元来自发布标签的 `packaging/` 目录，与二进制文件的
版本相同：把该目录复制到二进制文件旁边，可以来自该标签的检出副本，
或者对于 v0.6.6，来自
<https://github.com/go-authn/revocation/tree/v0.6.6/packaging>。

```sh
install -m 0755 authn-revokd-linux-amd64 /usr/local/bin/authn-revokd
install -m 0644 packaging/sysusers.d/authn-revokd.conf /usr/lib/sysusers.d/authn-revokd.conf
systemd-sysusers /usr/lib/sysusers.d/authn-revokd.conf
install -m 0644 packaging/systemd/authn-revokd.service /etc/systemd/system/
systemctl daemon-reload
```

账户是静态的，而不是 `DynamicUser=`。authn-revokd 拒绝由其自己的 uid 或 root 之外的任何人
所拥有的状态目录，并且状态必须在重启和升级之间继续
为下一个列表排序。使用动态用户时，文件会位于 `/var/lib/private` 之下，权限为 root `0700`，而以
自己的用户运行的 TLS 服务器将无法读取 CRL。

## 守护进程 {#the-daemon}

```ini
[Service]
Type=exec
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
```

此外还有：`User=authn-revokd`，完全没有 capability，`NoNewPrivileges=`，
`ProtectSystem=strict`，其中 `StateDirectory=authn-revokd`（`0755`）是唯一
可写的位置，以及 `PrivateUsers=`、`PrivateTmp=`、`PrivateDevices=`、
`PrivateIPC=`，仅 `AF_INET AF_INET6 AF_UNIX`，`@system-service` 系统调用
减去 `@privileged @resources`。

**`Restart=always`，因为 sshd 会忽略 KRL 中的过期时间。** 当列表过期时，
文件由*此进程*来故障即拒绝。它停止期间，sshd
继续读取其写出的最后一个文件，而期间签发的吊销永远不会
到达。请监控该单元，或在启用镜像时监控 `/healthz`。

**`systemctl reload` 立即同步。** 它发送 `SIGHUP`，代理会立即获取每个
来源，而不是等到下一次 `refresh`：

```
hangup: syncing now
```

它不会重新读取配置，配置只在启动时读取一次：更改 `revokd.hcl`
之后，请执行 `systemctl restart authn-revokd`。（在 v0.6.0 之前，未捕获的
`SIGHUP` 会终止进程，而 systemd 会将其视为正常退出。）

### 先启用它，再接入 sshd {#enable-it-before-wiring-sshd}

{{< callout type="warning" >}}
**当 `RevokedKeys` 指名的文件不存在时，sshd 会拒绝每一个证书**

因此请先启动 authn-revokd，并等到输出出现：
`ssh-keygen -Q -l -f /var/lib/authn-revokd/sshd.krl` 在每个来源都有效时
会输出其注释 `authn-revokd sshd`。
{{< /callout >}}

```sh
systemctl enable --now authn-revokd
journalctl -u authn-revokd -n 20     # "<source>: version N, issued ..., expires ..."
                                     # "output sshd: wrote /var/lib/authn-revokd/sshd.krl"
```

然后，在 `/etc/ssh/sshd_config` 中：

```
TrustedUserCAKeys /etc/ssh/ca/univ-a-ssh.pub
RevokedKeys /var/lib/authn-revokd/sshd.krl
```

并执行 `sshd -t && systemctl reload ssh`。sshd 在每次认证时都会读取 `RevokedKeys`，
因此 authn-revokd 重写该文件时无需重新加载：
原子重命名就足够了。

### TLS 服务器的 CRL {#a-tls-servers-crl}

```nginx
ssl_client_certificate /etc/authn-revokd/ca/univ-a-x509.pem;
ssl_verify_client      on;
ssl_crl                /var/lib/authn-revokd/univ-a.crl;   # format = "pem"
```

TLS 服务器在加载配置时读取其 CRL，因此文件更改时必须
重新加载它。`on_change` 命令以 `authn-revokd` 账户运行，
该账户不能执行 `systemctl reload nginx`：请改让 systemd 以 root 身份
监视该文件，用路径单元（对输出设置 `PathChanged=`）
启动一个运行 `systemctl reload nginx` 的 `oneshot`。

## 或者：定时器上的 `-once` {#or--once-on-a-timer}

`authn-revokd -once` 同步一次后退出，当列表不是当前有效的或
无法获取时退出码为 `1`（[`-once` 报告什么]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})）。
无论如何输出都会被写入，并且在列表
过期后对 sshd 故障即拒绝。

```ini
# authn-revokd-once.service
[Unit]
Conflicts=authn-revokd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/authn-revokd -config /etc/authn-revokd/revokd.hcl -once
TimeoutStartSec=5min
```

```ini
# authn-revokd-once.timer
[Unit]
Conflicts=authn-revokd.service

[Timer]
OnBootSec=30s
OnUnitActiveSec=1min
AccuracySec=5s
RandomizedDelaySec=10s

[Install]
WantedBy=timers.target
```

一次性任务使用守护进程的账户和加固设置。`TimeoutStartSec=5min`
防止卡在某个来源上的同步比下一次触发存活得更久，而
`RandomizedDelaySec=10s` 防止一起启动的整批机器同步地轮询
其签发方。

```sh
install -m 0644 authn-revokd-once.service authn-revokd-once.timer /etc/systemd/system/
systemctl daemon-reload
systemctl disable --now authn-revokd
systemctl enable --now authn-revokd-once.timer
```

**切勿同时启用两者**：这些单元相互冲突，启动其一会停止另一个。
守护进程仍是更好的选择。它在下一次 `refresh` 时就对过期列表故障即拒绝，
而定时器要等到下一次触发，并且只有守护进程可以充当
镜像：`listen` 在 `-once` 下会被忽略。停止触发的定时器就等于
停止的守护进程，因此请监控 `systemctl status authn-revokd-once`。

## 升级与回退 {#upgrading-and-going-back}

把新的二进制文件安装在旧文件旁边，替换，然后重启。状态会延续：
已验证的副本继续为后续列表排序，因此无论是升级还是
回退到较旧的二进制文件，都不会让较旧的列表进入。

## 卸载 {#uninstalling}

**先**从服务器的配置中移除 `RevokedKeys` 和 `ssl_crl`，
并重新加载它们：文件一旦消失，sshd 就会拒绝每一个证书。
