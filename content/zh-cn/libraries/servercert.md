---
title: "servercert — 守护进程的 TLS 证书从哪里来"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert 提供 TLS 服务器证书，来自更改时会被重新读取的文件，或通过 autocert 来自 ACME CA，包括 External Account Binding。"
tags: [库, tls, acme, 证书]
---

**守护进程的 TLS 服务器证书从哪里来？** 磁盘上的证书和
密钥（更改时会被重新读取），或通过
[`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert) 来自 ACME CA，包括 External
Account Binding。

```sh
go get github.com/go-authn/servercert@v0.5.2
```

`Config` 恰好指名一个来源——`CertFile` 和 `KeyFile`，或 `ACME`——
而 `New` 返回一个 `*Source`，其 `TLSConfig()` 提供该来源，
`MinVersion` 为 TLS 1.2。

## 示例 {#example}

来自文件：

```go
package main

import (
	"log"
	"net/http"

	"github.com/go-authn/servercert"
)

func main() {
	src, err := servercert.New(servercert.Config{
		CertFile: "/etc/fileshare/tls/fullchain.pem",
		KeyFile:  "/etc/fileshare/tls/privkey.pem",
		OnError:  func(err error) { log.Print(err) }, // a renewal that did not load
	})
	if err != nil {
		log.Fatal(err) // unreadable, unparsable, or a key that is not the certificate's
	}
	srv := &http.Server{Addr: ":443", TLSConfig: src.TLSConfig()}
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
```

`Config.Check` 会拒绝无法工作的配置，并且不触碰任何东西——
不读取文件，不创建目录：

```go
package main

import (
	"fmt"

	"github.com/go-authn/servercert"
)

func main() {
	// Check touches nothing: no file is read, no directory created.
	for _, c := range []servercert.Config{
		{ACME: &servercert.ACME{Domains: []string{"*.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"192.0.2.10"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "acme"}},
		{CertFile: "/etc/fileshare/tls/fullchain.pem"},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme",
			DirectoryURL: "http://acme.example.org/directory"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
	} {
		fmt.Println(c.Check())
	}
}
```

```
servercert: ACME domain "*.example.org" is a wildcard; that needs dns-01, which autocert does not do
servercert: ACME domain "192.0.2.10" is an IP address; autocert issues only for DNS names
servercert: ACME.CacheDir "acme" is not an absolute path
servercert: CertFile and KeyFile go together; one of them is empty
servercert: ACME.DirectoryURL "http://acme.example.org/directory" is not an https URL (RFC 8555 §6.1)
<nil>
```

最后一个是 Let's Encrypt 生产环境：`DirectoryURL` 为空。

## 文件 {#files}

`New` 读取这一对文件，如果它无法读取、无法解析，或其密钥
不是该证书的密钥，则**立即**失败。此后，在握手期间最多每
10 秒重新读取一次文件；已更改的一对文件会
在不持有锁的情况下被解析并换入。**无法**加载的已更改文件对
——证书比其密钥先写入、被截断的文件——会向 `OnError` 报告
一次，并且上一对良好的文件继续提供服务，因此先后写入这两个文件的
续期作业绝不会使服务器停机。

## ACME {#acme}

autocert 应答两种质询类型，别无其他：`tls-alpn-01`（RFC 8737，
端口 443，ALPN `acme-tls/1`），以及在设置 `HTTPChallenge` 时的 `http-01`（RFC 8555
§8.3，端口 80，由 `Source.HTTPHandler` 提供）。没有 `dns-01`，因此没有
通配符证书，也没有 IP 地址证书。

证书在第一次 SNI 指名 `Domains` 之一的握手时获取，或在任何客户端之前由
`Source.Prefetch` 获取，并由 autocert 在过期之前续期。通过 IP 地址连接的客户端
不发送 SNI，得到的是第一个域的证书。

{{< callout type="warning" >}}
**请追加到 `NextProtos`，而不要替换它**

使用 ACME 时，`TLSConfig().NextProtos` 包含 `acme-tls/1`，没有它，CA 的
tls-alpn-01 验证就会失败。并且你必须追加：通告 ALPN 协议的 Go TLS 服务器
会拒绝所提供的协议与之没有交集的客户端，因此
基于 TLS 的 NFS 服务器要添加 `sunrpc`（RFC 9289）。`net/http` 自己会添加 `http/1.1` 和
`h2`。
{{< /callout >}}

**无需质询的 CA。** 当新订单已经是 `ready` 时，autocert 会立即返回，
这正是域名已预先验证的 CA 的答复：GÉANT
TCS，由 HARICA 提供服务，适用于 Enterprise Admin 账户。无法从互联网通过
80 或 443 端口访问的内部服务器，仍然可以获得公开
受信任的证书。EAB HMAC 密钥是秘密，因此配置中指名的是
保存它的**文件**（`EABHMACKeyFile`），而绝不是密钥本身。

`x/crypto/acme` 的一个缺陷被绕过了（[golang/go#77704](https://github.com/golang/go/issues/77704)）：
在完成订单之后，CA 仍在处理时，客户端会轮询完成响应的
`Location` 头中的 URL，而 RFC 8555 并没有把它放在那里。servercert 给 ACME 客户端提供了一个添加该头的传输，
其值取自较早的 newOrder 响应中订单的 URL。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

`Check` 拒绝：两个来源都没有或都有；只有一半的文件对；没有
域或缓存目录的 ACME；相对路径；只有一半的 EAB；属于 IP 地址、
通配符、单个标签、以点结尾，或不是有效主机名的域；
不是 https 的目录 URL（RFC 8555 §6.1）。

`New` 还会拒绝以下缓存目录——它保存私钥——：是
符号链接、对组或其他用户可访问、由进程有效用户之外的用户拥有，
或无法写入；缺失的目录会以 `0700` 创建并在之后检查。
其上的每个目录都只能由 root 或有效用户更改，
正如 sshd 的 `StrictModes` 对通往 `authorized_keys` 的路径所要求的，
其上的符号链接会被拒绝，除非由 root 拥有。
在 Windows 上，不检查权限和所有者——两者由 ACL 决定，而限制
它们是你的事——并且路径中任何位置的符号链接都会被拒绝。

## 它对照什么检查 {#what-it-is-checked-against}

**pebble**，即 Let's Encrypt 的测试 CA，用其 `ca`、`db`、`va`
和 `wfe` 包在进程内运行，配合 DNS 桩，签发真实的证书，由 `crypto/tls`
对照 pebble 的根证书验证：tls-alpn-01；通过 `HTTPHandler` 的 http-01
及其关闭 `HTTPChallenge` 的对照；EAB 的必需、缺失、错误、然后正确；
在没有任何质询端口开放时签发的预先验证的域，及其对照。有一个
测试在没有 golang/go#77704 变通办法的情况下运行同样的签发，并要求
它失败。覆盖率下限是 100%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/servercert@v0.5.2](https://pkg.go.dev/github.com/go-authn/servercert@v0.5.2)
