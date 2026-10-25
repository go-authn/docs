---
title: "列表如何验证"
linkTitle: "验证"
weight: 30
description: "authn-revokd 在保留列表之前检查什么：签名、日期，以及它绝不早于所持有的列表（重启之后也一样）。"
tags: [authn-revokd, 吊销, 安全]
---

未通过验证的列表绝不会被写入、提供或使用。最后一份良好的
副本得以保留。无论出于什么原因而失败的获取，都绝不会用空的
答复取代它，那样会什么也不吊销。

## 签名 {#the-signature}

**KRL** 连同其签名 `<url>.sig` 一起获取：对整个文件的
装甲式 SSHSIG，由配置为 `ssh_ca` 的 **SSH CA 密钥**签署，命名空间为
`krl@go-authn.github.io`。该命名空间防止签名被当作
其他东西。签名者使用 SHA-512 哈希；SHA-256 也被接受。PROTOCOL.sshsig 所禁止的
SHA-1 形式的 RSA 签名会被拒绝。

KRL 本身必须能被 `sshd` 解析，且不得带有 OpenSSH 自己的
签名节，OpenSSH 从不验证该节。

由任何其他密钥签名的列表会被拒绝：

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:xm8VDcZUh44N+RQSiPbroPInzkMhN/KCWI/TC+9HPNQ: public key does not match
bridge-x509: version 1791712224691, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
output sshd: wrote /tmp/authn/revokd/out/other.krl
output tls: wrote /tmp/authn/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

这里 `ssh_ca` 指名了一把没有为 bridge 的列表签名的密钥，错误信息指出了
该密钥。无法验证的签名也可能是两次请求之间重新
签发了列表，因此在报告之前会把两者再各获取一次。
这是该来源的第一次获取，所以没有可保留的良好副本，输出立即就是
[故障即拒绝的列表]({{< relref "/authn-revokd/lapse.md" >}})。（在 v0.6.2 之前，同样的失败会在上面这条信息前面
带有“the list changed between it and
its signature”，仿佛列表被重新签发了。）

签名用 `If-Match: <the list's ETag>` 获取。在两次请求之间
重新签发的列表会答复 `412`，两者会被再次获取。

**CRL** 对照配置为 `x509_ca` 的 CA 证书检查：首先对原始字节检查
签名，**在**解析其余部分**之前**，因此由任何人签署的大型
CRL 只需付出一次签名检查而不是一次解析的代价。然后其
签发方必须是该证书的主体；它必须有 CRL Number 和晚于其 `thisUpdate` 的
`nextUpdate`；并且它不得是增量 CRL，也不得带有 CRL Number 和 Authority Key Identifier 之外的
关键扩展，也不得带有关键的条目扩展。

KRL 还必须在 `expires@go-authn.github.io`
扩展中**说明它何时过期**：没有该扩展的列表将无法与过时的列表区分开。

正文有大小限制：KRL 为 32 MiB，其签名为 64 KiB，CRL 为 64 MiB。

## 日期 {#the-dates}

列表在以下情况下是当前有效的：

- 现在早于其过期时间（KRL 的扩展，CRL 的 `nextUpdate`）；
- 其签发时间没有比现在晚五分钟以上：时钟超前超过该值的签发方
  所写出的列表，其年龄无从得知；
- 有 `max_age` 时，其签发时间距今不超过该值。

不是当前有效的列表在获取时即被拒绝。`304 Not Modified` 不算
新消息：所持有的副本可能此后已经过期，因此在每次
同步时都会重新判断。

## 绝不早于所持有的列表 {#never-older-than-the-list-held}

列表的位置由其**版本**（KRL 的 `krl_version`，CRL 的
CRL Number）决定，然后是其**签发时间**（KRL 的生成日期，CRL 的
`thisUpdate`）。只有当列表具有更高的版本，或相同版本但签发更晚时，
才可以取代所持有的列表：即相同的吊销内容，带着新的过期时间重新签发。其他任何情形都是回滚：
重放或恢复的较旧列表，仍然有签名且未过期，却会撤销
较新列表所吊销的内容。

### 重启之后也一样 {#across-restarts-too}

所持有的列表保存在 `state_dir` 中，每个来源一个文件，将列表
及其签名放在一起，通过一次重命名写入并同步目录。
启动时每个副本都会**重新验证**（无论是否已过期，它都决定
接下来的顺序），无法再通过验证的副本不被信任，甚至不能用于为下一个
列表排序，并会在日志中说明。

这里，重启之后把一个来源指向了较早的 bridge 进程在十九秒之前
提供的列表，该列表仍有签名且未过期：

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
bridge-x509: version 1791712224691, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/authn/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-11T09:50:05Z, the copy held at 2026-10-11T09:50:24Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-11T10:50:24Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261011T115024
# Comment: authn-revokd sshd
```

第一次运行没有写入输出：文件中已经保存了这些列表。较旧的
列表被拒绝，输出保留较新的那个。拒绝它的进程
从未见过较新的列表：它是从 `state_dir` 中读回的。

由于状态使回滚可以被检测到，该目录受
sshd 的 StrictModes 规则约束（[配置]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}})）。
两次写入之间的崩溃不会留下无法验证的一对文件，那会连带使
回滚防护失效：列表及其签名是同一个文件。

## `-once` 报告什么 {#what--once-reports}

当某个来源没有当前列表、其**最后一次获取失败**，或某个输出
无法写入时，`-once` 以 `1` 退出，其最后一行会说明
前两种情形中的哪一种：

| 最后一行 | 来源 | 其输出 |
|---|---|---|
| `not current: <source>` | 没有当前列表：从未获取、已过期，或超过 `max_age` | 对 sshd 故障即拒绝 |
| `not fetched: <source> (the list held is current until <T>)` | 其获取失败，但所持有的副本仍然有效 | 根据该副本原样写出，直到 `T` |

这里签发方已停止，而所持有的两个列表仍然有效：

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-11T10:50:24Z), bridge-x509 (the list held is current until 2026-10-11T10:50:24Z)
```

该次运行保持 `sshd.krl` 原样。一旦所持有的列表过期，同一个来源就会
被报告为 `not current`，并且两种情形可以出现在同一行，如
[列表过期时]({{< relref "/authn-revokd/lapse.md" >}})所示。在 v0.6.2 之前，
两种情形都报告为 `not current`，而在仅仅是获取失败时却说列表已
过期；当时的退出状态同样是 `1`。

镜像的 `/healthz` 则根据所持有的副本来判断，在
签发方宕机而副本仍然有效期间，答复 `ok`。
