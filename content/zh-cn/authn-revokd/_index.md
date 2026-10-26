---
title: "authn-revokd"
linkTitle: "authn-revokd"
weight: 30
description: "一个获取已签名 KRL 和 CRL 的代理：只保留通过验证的列表，将其写到 sshd 和 TLS 服务器读取的位置，并在某个列表过期时故障即拒绝。"
tags: [authn-revokd, 吊销, krl, crl]
---

**OpenSSH 没有分发 KRL 的办法，而 KRL 中也没有任何内容表明它已
过时。** `sshd` 会把几个月前就停止更新的文件当作当前
列表读取。authn-revokd 弥补了这两个缺口，针对
[authn-bridge]({{< relref "/authn-bridge/revocation.md" >}})发布的列表：它
获取每个列表，只有验证通过才保留，将其写到 `sshd` 或 TLS
服务器读取的位置，并且在列表过期时写出一个**吊销 CA
本身**的列表。纯 Go，`CGO_ENABLED=0`，单个二进制文件。这些页面描述 v0.6.6。

```
$ go install github.com/go-authn/revocation/cmd/authn-revokd@v0.6.6
go: github.com/go-authn/revocation@v0.6.6 requires go >= 1.27.3; switching to go1.27.3
$ authn-revokd -version
authn-revokd v0.6.6
$ authn-revokd -help
Usage of authn-revokd:
  -config string
    	the configuration file (default "/etc/authn-revokd/revokd.hcl")
  -once
    	sync once and exit: 1 when a list is not current, or could not be fetched
  -version
    	print the version and exit
```

`-help` 以 0 退出；在 v0.6.2 之前它以 2 退出。

在 v0.6.0 之前，该命令名为 `revokd`，默认读取 `/etc/revokd.hcl`。
现在没有任何程序读取该文件；当它存在而新的默认文件不存在时，
错误信息会同时指出两个路径。

## 一次运行中它做什么 {#what-it-does-in-one-run}

针对环回地址上的测试 authn-bridge，带有一个 KRL 来源和一个 CRL 来源：

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
bridge-x509: version 1793014030593, issued 2026-10-26T11:27:10Z, expires 2026-10-26T12:27:10Z
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
output tls: wrote /tmp/authn/revokd/out/bridge.crl
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261026T122710
# Comment: authn-revokd sshd
```

没有新内容的第二次运行不输出任何内容并以 0 退出：只有内容改变时，输出才会
被重写。

## 为什么传输方式无关紧要 {#why-the-transport-does-not-matter}

每个列表都能自我认证：KRL 通过 CA 自己的密钥生成的分离式 SSHSIG 签名，
CRL 通过其 CA 的签名。每个列表都声明它何时不再
有效。因此列表可以通过 HTTPS、集群内的普通 HTTP、镜像
或文件传来。传输方式决定变更到达的速度，但绝不决定是否
接受伪造或过时的列表。

| | KRL | CRL |
|---|---|---|
| 真实性 | 由 SSH CA 密钥生成的 SSHSIG，命名空间 `krl@go-authn.github.io` | 由其 CA 签名 |
| 当前有效 | `expires@go-authn.github.io`，sshd 会忽略它 | `nextUpdate` |
| 绝不倒退 | `krl_version`，然后是生成日期 | CRL Number，然后是 `thisUpdate` |
| 故障即拒绝 | authn-revokd 写出吊销 CA 密钥的 KRL | OpenSSL 自行拒绝过期的 CRL |

## 接下来去哪里 {#where-to-go-next}

| | |
|---|---|
| [安装]({{< relref "/authn-revokd/install.md" >}}) | 守护进程，或定时器上的 `-once`；接入 sshd 和 nginx |
| [配置]({{< relref "/authn-revokd/configuration.md" >}}) | 来源、输出、镜像，以及什么会被拒绝 |
| [列表如何验证]({{< relref "/authn-revokd/verification.md" >}}) | 签名、日期，以及绝不早于所持列表（重启之后也一样） |
| [列表过期时]({{< relref "/authn-revokd/lapse.md" >}}) | 吊销 CA 本身的 KRL |

## 它不做什么 {#what-it-does-not-do}

吊销到达服务器的速度不会快于 authn-revokd 的轮询（`refresh`），
再加上签发方重新签发的延迟。签发方宕机期间，其
证书从列表过期之时起就会被拒绝。持有 CA 密钥的人可以
签署任何列表，正如他们可以签发任何证书一样。

## 许可证 {#licence}

BSD-3-Clause。
