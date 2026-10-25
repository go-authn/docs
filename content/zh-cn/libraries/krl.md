---
title: "krl — OpenSSH 密钥吊销列表"
linkTitle: "krl"
weight: 110
description: "go-authn/krl 按 sshd 读取的方式解析、构建、合并和检查 OpenSSH KRL，带有过期扩展，并由 ssh-keygen 评判。"
tags: [库, 吊销, ssh]
---

**这个 SSH 证书或密钥是否已被吊销——按 sshd 的回答？** OpenSSH 的
`PROTOCOL.krl` 的二进制格式，即 `sshd` 通过
`RevokedKeys` 加载、`ssh-keygen -k` 写出的列表。`golang.org/x/crypto/ssh` 不
支持它。

```sh
go get github.com/go-authn/krl@v0.6.1
```

`IsRevoked` 遵循 OpenSSH `krl.c` 中的 `ssh_krl_check_key`：当证书的序列号或 key ID
在签发它的 CA 之下或在任何 CA 之下被吊销、当其 CA 密钥被吊销，
或当其自身的密钥按 blob 或按 SHA-1 或 SHA-256
指纹被吊销时，该证书即被吊销。序列号 0——CA 在不指明序列号时写入的值——
绝不会按序列号被吊销。

## 示例 {#example}

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

同样的列表和证书写入文件后，OpenSSH 10.3p1 的
`ssh-keygen -Q -f list.krl` 给出同样的三个答案：`REVOKED`、`ok`、
`REVOKED`。

## 过期：`expires@go-authn.github.io` {#expiry-expiresgo-authngithubio}

KRL 有生成日期和版本，却没有任何内容说明它何时不再
有效，因此陈旧的副本无法与新的副本区分开。
`Builder.SetExpires` 把该时间写入名为
`ExtensionExpires` 的扩展节，**非关键**，因此 `sshd` 和 `ssh-keygen` 会加载列表
并忽略它；`Parse` 将其读入 `KRL.Expires`。

{{< callout type="warning" >}}
**没有签名**

OpenSSH 从未提供写入 KRL 签名节的办法，现在也不再
验证它。`Parse` 会跳过它并设置 `Signed`，这并不说明任何关于真实性的事；
`Builder` 从不写入它。列表的完整性，以及其过期时间的完整性，来自其
传输——来自经过认证的服务器的 HTTPS——或来自由调用方检查的分离式
SSHSIG 签名，本包不做这件事。
{{< /callout >}}

## 合并：为 sshd 提供一个文件 {#merging-one-file-for-sshd}

在 OpenSSH 10.3 之前，`sshd` 只读取一个 `RevokedKeys` 文件，因此信任多个 CA 的服务器
需要把它们的列表合成一个。`Builder.Merge` 添加已解析列表的
每一条吊销。`Builder.MergeCA(k, ca, others...)` 保留 `k` 中
`ca` 的节、其任意 CA 的节（重新限定到 `ca`），以及其显式密钥
和指纹，并排除——同时计数——其他 CA 的节，以及指定 `others` 之一的
密钥或指纹。带有
`MergeOptions{DropKeys: true}` 的 `MergeCAWith` 还会排除除
`ca` 自己的密钥之外的所有显式密钥，用于不被信任可涵盖每个 CA 的用户的列表：
被吊销的用户密钥会使该用户在合并文件的每个 CA 之下都被锁在门外，因为 `sshd` 会检查
证书自身的密钥，无论是谁签发的。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

`Parse` 拒绝 `ssh-keygen` 和 `sshd` 所拒绝的内容：错误的 magic 或格式
版本、被截断或有多余的数据、未知的节或证书
子节、标记为关键的未知扩展、OpenSSH 无法解析的 CA 密钥、
序列号 0、颠倒的序列号范围、大于 OpenSSH 所读取的位图，
或回绕超过 2^64−1 的位图。它还会拒绝格式错误或重复的过期时间：
若将其读作不存在，就会把本应过期的列表变成永不过期的列表。

`Builder` 在 `Marshal` 时拒绝（返回第一个无效请求）：
序列号 0、低端为 0 或高于高端的范围、包含 NUL 的 key ID 或
注释、在应给出 CA 密钥的位置给出的证书，以及
早于生成日期的过期时间。

**一处有意的差异。** 对于许多相互靠近的稀疏序列号，
`ssh-keygen -k` 会写出比其自身读取器所能接受的更宽的位图，然后
拒绝自己的文件（*bignum is too large*）。`Parse` 同样会拒绝该文件，
`sshd` 也会；`Builder` 则会在位图变得那么宽之前开始新的节，
因此它写出的内容始终可读。

Parse 的内存分配与列表所吊销的内容成正比，OpenSSH 也是如此：KRL
应当来自被信任不会发送巨大列表的来源。

## 它对照什么检查 {#what-it-is-checked-against}

**OpenSSH 的 `ssh-keygen`**，在 Linux 和 macOS 通道上，那里
`KRL_REQUIRE_SSHKEYGEN=1` 使缺失成为失败（Windows 只运行
纯 Go 测试）：

- 由 `ssh-keygen -k` 写出的 KRL，涵盖每种序列号编码、key ID、三个
  CA 加“任意 CA”、显式密钥和被吊销的 CA 密钥：对 250 个证书，`IsRevoked` 的回答
  与 `ssh-keygen -Q` 相同，并且给定相同吊销内容的 `Builder` 写出**相同的字节**；
- 两者写出的 40 组随机序列号集合：逐字节相同，且对大约 9000 个证书
  给出相同的回答；
- 每一种截断以及大约 1400 次单字节破坏：`Parse` 所拒绝的
  恰好就是 `ssh-keygen` 所拒绝的；
- 过期扩展可在 `ssh-keygen` 中加载，而标记为关键的同一节
  会被拒绝；
- 合并后的列表所吊销的，恰好就是其某个来源所吊销的。

以 `ssh-keygen` 写出的 KRL 为种子的 `FuzzParse`，以及 `FuzzBuilder`，都在 CI 中运行。
覆盖率下限是 100%，在存在 `ssh-keygen` 的 Linux 通道上测量。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/krl@v0.6.1](https://pkg.go.dev/github.com/go-authn/krl@v0.6.1)
