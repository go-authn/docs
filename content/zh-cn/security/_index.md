---
title: "安全"
linkTitle: "安全"
weight: 55
description: "各个程序拒绝什么、吊销如何从提供方传到每台服务器，以及如何分辨真正的二进制文件与其他文件。"
tags: [安全]
---

go-authn 的职责是证明人员身份，因此它的拒绝就是设计本身，而不是
例外。本节汇集了跨越程序边界的那些拒绝；
每个程序自己的页面则说明它各自拒绝什么。

## 最重要的拒绝 {#the-refusals-that-matter-most}

| | 拒绝什么 | 原因 |
|---|---|---|
| authnd | 由已声明的 `reader` 之外的任何人发起的搜索 | 绑定证明的是某人是谁；它并不是列出所有人的许可 |
| authnd | 为来源中没有密码的人员签发 Kerberos 票据 | KDC 需要由密码派生的密钥；NT 哈希或密码校验都无法产生该密钥（[原因]({{< relref "/authnd/kerberos.md" >}})） |
| authnd | 与 `mfa` 块并存的 `kerberos` 块 | kinit 只携带密码，别无其他，因此该域会对 `mfa` 块要求两个因素的人员只凭一个因素签发票据 |
| authn-bridge | 无人签名的断言，以及来自机构自身范围之外的标识符 | 联邦的每个成员都受到信任，因此每个成员都必须只对其自己的人员负责：否则任何一个机构都可以指称任何人 |
| authn-revokd | 未签名、已过期或比其已持有的列表更旧的列表 | 中间的镜像可以延迟列表，但绝不能伪造或回滚列表 |
| authn-revokd | 信任已过期的列表 | 它会写入一个吊销 CA 本身的列表，因此 sshd 会拒绝，而不是信任陈旧的列表 |
| sshcert-authorize | 域授权未指明本主机的证书 | 来自联邦 CA 的证书本身并不构成对所有信任该 CA 的主机的许可 |

## 端到端的一次吊销 {#a-revocation-end-to-end}

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}})对 KRL（用于 SSH 证书）和 CRL（用于 X.509 客户端证书）
   签名并标注日期，然后发布它们。
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}})获取每个列表，
   验证其签名和日期，拒绝比其已持有的列表更旧的列表
   （重启之后也一样），然后才将其写入服务器读取的位置。
3. sshd（`RevokedKeys`）、go-fileshare 以及其他任何程序读取的都是
   已经验证过的文件。

CAEP `session-revoked` 事件通过提供方的 Shared Signals
发送方，使任何列表都无法逐一指名的内容失效：即在某个时刻之前
签发给某人的一切。go-fileshare 的文档描述了接收端：
[吊销列表](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)、
[共享信号](https://go-fileshare.github.io/docs/latest/security/shared-signals/)。

## 发布版本 {#releases}

每个二进制文件都由发布工作流根据带标签的提交构建，并且可以用三种方式
检查：[验证下载]({{< relref "/security/verifying-releases.md" >}})。
