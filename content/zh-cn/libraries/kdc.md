---
title: "kdc — 根据目录签发 Kerberos 票据"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc 是 Kerberos 的签发一半：基于 UDP 和 TCP 的 AS 与 TGS、要求预认证、单一加密类型、人员来自 go-authn 目录。"
tags: [库, kerberos, 目录]
---

**域如何根据目录签发票据？** 基于 UDP 和 TCP 的 AS-REQ 和 TGS-REQ，
要求加密时间戳预认证，面向
[directory]({{< relref "/libraries/directory.md" >}})所了解的人员以及
keytab 所持有的服务。它运行在
[authnd]({{< relref "/authnd/_index.md" >}})之下。

```sh
go get github.com/go-authn/kdc@v0.4.3
```

在 v0.4.3，其 `go.mod` 至少要求 `go-authn/directory` v0.12.0 和
gokrb5 v8.4.4：这只是最低版本，因此要求 directory v0.14.0（即这些页面所
描述的版本）的程序会用 v0.15.0 构建，authnd v0.13.0 就是如此。
接受的一半是 [krb5]({{< relref "/libraries/krb5.md" >}})，只
验证票据的服务完全不需要本模块。

未实现：跨域引荐、PKINIT、FAST、可续期或后置日期的
票据，以及任何 kadmin 协议。密钥来自目录和
keytab，并在它们所在之处更改。

## 只有持有密码的来源才能支撑域 {#only-a-source-holding-the-password-can-back-a-realm}

KDC 必须用该人员的长期密钥**解密**客户端的预认证，
因此 `directory.Verifier`——对别人的 LDAP 的绑定、
哈希比较——无法胜任，无论它多么准确地回答*这是不是
正确的密码*。来源中没有密码的人员会得到
`KDC_ERR_NULL_KEY`（*null key*）的答复，而不是密码错误时得到的代码，因此
这读起来是需要修正的配置，而不是需要重新键入的密码。

## 示例 {#example}

内存中的域，在环回地址上：

```go
package main

import (
	"crypto/rand"
	"fmt"
	"log"
	"net"
	"time"

	"github.com/go-authn/directory"
	"github.com/go-authn/kdc"
	"github.com/jcmturner/gokrb5/v8/iana/etypeID"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

func main() {
	// People: a source that holds PASSWORDS. A verifier cannot back a realm.
	people := &directory.Static{Name: "the configuration file", People: []*directory.Identity{
		directory.NewIdentity("alice", directory.WithPassword("correct horse battery staple")),
	}}

	// Services: the realm's own krbtgt key, and one per service.
	kt := keytab.New()
	for _, p := range []string{"krbtgt/EXAMPLE.ORG", "nfs/files.example.org"} {
		if err := kt.AddEntry(p, "EXAMPLE.ORG", rand.Text(), time.Now(), 1, etypeID.AES256_CTS_HMAC_SHA1_96); err != nil {
			log.Fatal(err)
		}
	}

	// A keytab without krbtgt/REALM is refused before anything listens.
	_, err := kdc.New(kdc.Config{Realm: "OTHER.ORG", People: people, Services: kt})
	fmt.Println(err)

	srv, err := kdc.New(kdc.Config{
		Realm:    "EXAMPLE.ORG",
		People:   people,
		Services: kt,
		Logf:     log.Printf, // why each request was refused; never a key
	})
	if err != nil {
		log.Fatal(err)
	}
	pc, err := net.ListenPacket("udp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:18088")
	if err != nil {
		log.Fatal(err)
	}
	go srv.ServeTCP(ln)
	fmt.Println("EXAMPLE.ORG answers on", pc.LocalAddr())
	log.Fatal(srv.ServeUDP(pc))
}
```

使用为 `EXAMPLE.ORG` 指明 `kdc = tcp/127.0.0.1:18088` 的 `krb5.conf`，
macOS 自带的 Heimdal `kinit`（1.5.1）可以获得票据授予票据，
环境变量为 `KRB5_CONFIG=krb5.conf` 和 `KRB5CCNAME=FILE:cc`：

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  nfs/files.example.org@EXAMPLE.ORG
```

十小时是 `Config.Lifetime` 的默认值，服务票据与换取它的票据授予票据
同时结束。KDC 在自己的日志中说明了拒绝每个
请求的原因：

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

每次交换的第一次拒绝是协议在正常工作：要求预认证的
`KRB-ERROR` 携带一个 `ETYPE-INFO2` 提示，指明
etype 和盐值，客户端随后带着时间戳再试一次。

{{< callout type="info" >}}
**在 v0.4.2 之前，`till` 为 19700101000000Z 会得到已经过期的票据**

RFC 4120 §5.4.1：`till` 为 19700101000000Z 表示请求 KDC 策略
所允许的最大结束时间。Heimdal 的 `kgetcred` 发送的正是这个值。v0.4.1
只测试 Go 的零时间，因此把 Unix 纪元当作真实的结束时间，并
签发了 `klist` 显示为 `>>>Expired<<<` 的服务票据；MIT 的 `kvno`
（CI 的评判者）发送的是真实的 `till`，从未遇到这种情形。v0.4.2 签发
所允许的最长票据，如上所示，并对已经过去的 `till` 答复
`KDC_ERR_NEVER_VALID`，而不是一张到达即过期的票据
（[go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19)）。
{{< /callout >}}

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**在配置时**（`New`）：没有域（`ErrNoRealm`）、没有目录
（`ErrNoPeople`）、没有 keytab（`ErrNoServices`），或者 keytab 中没有
`krbtgt/REALM@REALM`（`ErrNoTGTKey`）——而不是启动之后在
第一次 `kinit` 时才失败，那样错误只会到达无法修复它的人员那里。

**在 AS 处：** 没有预认证的请求会得到要求预认证的
答复，并且在有时间戳可检查之前不会派生人员的密钥，
因此指名真实 principal 的伪造 UDP 数据包不会带来密钥
派生的开销。错误的密码、使用另一个 etype 的时间戳以及一小时前的时间戳
都会得到 `KDC_ERR_PREAUTH_FAILED` 的答复，即密码错误时得到的代码；
错误文本指明原因，`Logf` 也是如此。服务请求自己的 TGT 会被拒绝：服务
通过 keytab 认证。

**单一加密类型。** 票据和密钥仅限 `aes256-cts-hmac-sha1-96`
（etype 18）。etype 列表中没有 18 的请求，会在查找任何人之前
就得到 `KDC_ERR_ETYPE_NOSUPP` 的答复。设置了 `Logf` 时，日志会
记录两个 etype，使运维人员能够区分密码套件不匹配与
密码输错。

**在 TGS 处**（RFC 4120 §3.3.2），只有在以下情况下才会签发票据：

- 出示的票据是本域的 TGT，用 KDC 所指明的
  `krbtgt/REALM` 密钥解密——而不是用票据声称的任何服务的密钥
  （`KRB_AP_ERR_NOT_US`）；
- 认证符能用其会话密钥解密，且在 `MaxSkew` 之内；
- 其校验和是针对本请求的正文（以其到达时的字节），并用
  会话密钥作密钥（缺失或无密钥时为 `KRB_AP_ERR_INAPP_CKSUM`，
  错误时为 `KRB_AP_ERR_MODIFIED`）；
- TGT 未过结束时间（`KRB_AP_ERR_TKT_EXPIRED`），未早于其开始时间，
  也未被标记为无效（`KRB_AP_ERR_TKT_NYV`），且不允许时钟偏差：
  这些时间是此 KDC 的时钟写入的；
- 客户端属于本域，且仍在目录中
  （`KDC_ERR_C_PRINCIPAL_UNKNOWN`）。

**有效期。** `Config.Lifetime` 为票据设上限，为零时是十小时；请求更短有效期的
客户端会得到更短的有效期，而用 TGT 换取的票据，其结束时间不会晚于
该 TGT，因此再次请求 `krbtgt` 不能延长凭据。

**未认证的对端能占用什么：** TCP 消息（包括其长度）
必须在 30 秒内到达；同时最多服务 256 个 TCP 连接，
同时最多应答 64 个数据报——多出的一个会被丢弃，
客户端会重发或回退到 TCP。

## 它对照什么检查 {#what-it-is-checked-against}

**MIT 自己的 `kinit` 和 `kvno`**，通过 pkgx，对照用 Go 构建的域——
不涉及 MIT KDC，只是借用了客户端。
`TestMITClientGetsATGTAndAServiceTicket` 获取 TGT 和服务票据，
并检查 `kvno` 报告的密钥版本。Linux 测试通道、竞态检测器
和覆盖率通道设置 `KDC_REQUIRE_JUDGE=1`，并且还有一个步骤会
在日志没有写明 *were served by this realm* 时失败。测试还固定了
真实客户端永远不会触发的拒绝情形：使用错误密钥的时间戳、
一小时前的时间戳、三字节的密码套件、直接通过
AS-REQ 请求的服务、TGS 处伪造的服务票据，以及由验证器支撑的域。
覆盖率通道的下限是 80%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/kdc@v0.4.3](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.3)
