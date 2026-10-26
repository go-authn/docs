---
title: "列表过期时"
linkTitle: "列表过期时"
weight: 40
description: "当 authn-revokd 没有某个 CA 的当前列表时，它为 sshd 写出什么：吊销 CA 密钥本身的 KRL，使该 CA 的每个证书都被拒绝。"
tags: [authn-revokd, 吊销, 故障即拒绝, sshd]
---

在无法获得列表时就放行一切的吊销检查，
会被能够阻断列表的攻击者击败。因此，当 authn-revokd 持有
某个来源的当前列表时，该来源的列表所保护的内容会被
**拒绝**，直到再次收到当前有效的列表。

| 输出 | 当某个来源没有当前列表时 |
|---|---|
| 用于 `sshd` 的 KRL | authn-revokd 写出一个**吊销该来源 CA 密钥**的 KRL |
| 用于 TLS 服务器的 CRL | 过期的 CRL 保持原样；OpenSSL 自行拒绝过期的 CRL |

## 对 sshd：吊销 CA 本身 {#for-sshd-revoking-the-ca-itself}

`sshd` 没有列表过期的概念：它会永远继续读取最后写出的
文件。但它会拿每个证书的 **CA 密钥**对照 `RevokedKeys` 检查。
因此，在无法为之担保的列表的位置上，authn-revokd
把 CA 自己的密钥放进输出，该 CA 签发的每个证书
都会被拒绝，而其他一切不受影响。

这里签发方已停止，并且 KRL 来源设置了 `max_age = "30s"`，因此所持有的
副本在一分钟内而不是一小时内就会过期。CRL 来源没有
`max_age`，其副本仍然有效：

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-26T12:27:10Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:AnDb/hVURvKYmNr3UBTfpWL0OVGHgKRMbSFicCNn/O4 # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh` 是 `not current`，其输出已故障即拒绝；`bridge-x509`
只是 `not fetched`，其 CRL 保持原样
（[`-once` 报告什么]({{< relref "/authn-revokd/verification.md#what--once-reports" >}})）。
`SHA256:AnDb/...` 是 bridge 的 SSH CA。对于读取该文件的任何程序而言，
它签发的证书现在都已被吊销。上面的命令
在 `revokd` 目录中运行，`out/` 就在那里；下面这条在它旁边运行，
位于存放测试证书的目录中，如
[sshcert-authorize 页面]({{< relref "/sshcert/authorize.md#krl" >}})所示，因此
同一个文件是 `../revokd/out/sshd.krl`：

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

注释写有 `FAIL CLOSED` 并指名来源，因此阅读
`ssh-keygen -Q -l` 的人能看到原因。当每个来源都已过期时，文件的日期是 1970 年。输出会在**同步一发现问题时**
立即写出，对守护进程来说是其下一次 `refresh`，对定时器来说是其下一次触发。当
再次收到当前有效的列表时，下一次同步会用它取代 CA 的密钥，
该 CA 的证书又会被接受。

**在第一个列表之前**也是如此：从未获取过的来源没有任何
当前有效的内容，其 CA 从第一次写入起就被吊销。新的安装在其第一个列表通过验证之前
会拒绝该 CA 的证书，而不是未经检查就接受它们。

### 每个 CA 各自处理 {#each-ca-for-itself}

在合并多个来源的输出中，只有过期来源的 CA 会被
吊销。其他 CA 保留各自的列表。无法合并的列表（超出
go-authn/krl 所保留的序列号范围）只对其自己的 CA 故障即拒绝，并且
`/healthz` 会指名它。只有当各个列表单独可以合并而合在一起不行时，才会吊销
输出中的每个 CA，注释会这样说明
（`FAIL CLOSED, the output could not be rendered`）。如果改为保留旧文件，
之后的过期就会无人察觉。

## 对 TLS 服务器：CRL 本身 {#for-a-tls-server-the-crl-itself}

CRL 本身就声明了它何时不再有效，OpenSSL 会拒绝超过
其 `nextUpdate` 的 CRL（“CRL has expired”）。因此 authn-revokd 把最后一个已验证的
CRL 留在原处，TLS 服务器自行故障即拒绝。这也是为什么
为 CRL 输出提供数据的来源上会拒绝 `max_age`：加载了
CRL 的服务器会一直保留它直到其 `nextUpdate`，无论 authn-revokd 写出什么。

## 自行检查过期时间的读取方 {#readers-that-check-the-expiry-themselves}

合并后的 KRL 带有过期时间，即其当前输入中最早的一个。检查它的读取方，
例如 go-fileshare 的 `ssh_krl_file` 或
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}})，
会像看到签发方停止那样看到 authn-revokd 停止。

{{< callout type="warning" >}}
**这只在 authn-revokd 运行时有效**

文件由 authn-revokd 来故障即拒绝。它停止期间，sshd 继续
读取最后写出的文件，无论其是否仍然有效。因此守护进程要设置 `Restart=always`，
并监控该单元、定时器或 `/healthz`。
{{< /callout >}}
