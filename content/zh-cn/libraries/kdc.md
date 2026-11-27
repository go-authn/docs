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
[authnd]({{< relref "/authnd/_index.md" >}})之下。基于它构建的独立守护进程是
[kdcd]({{< relref "/libraries/kdcd.md" >}})。

```sh
go get github.com/go-authn/kdc@v0.8.1
```

v0.7.0 至 v0.8.1：接受 Windows 客户端的 TGS-REQ（其 RSA-MD5 认证符校验和，MIT 同样接受）；票据带有标志和
starttime；`Server.Mint`、`Server.MintHandler` 和 `Config.MintCallers` 通过双向认证的 TLS，为白名单中的调用方
签发无密钥人员的 TGT，形式为 KRB-CRED，默认关闭；当认证符所指的客户端与票据不同时，TGS 回答
`KRB_AP_ERR_BADMATCH`；additional-tickets 字段格式错误的请求会在 gokrb5 解码之前被丢弃。

在 v0.8.1，其 `go.mod` 至少要求 `go-authn/directory` v0.17.0 和
gokrb5 v8.4.4：这只是最低版本，因此要求 directory v0.17.0
的程序会用 v0.18.0 构建，authnd v0.16.2 就是如此。
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

## 启用基于密码派生的认证 {#allow-password-derived-as}

自 v0.11.0 起，从目录所持有的密码派生个人密钥（string-to-key，RFC 3962）
**默认关闭**。设置 `Config.AllowPasswordDerivedAS` 即可开启。关闭时，对条目中
含有密码的人发出的 AS-REQ 会得到 `KDC_ERR_POLICY`（*KDC 策略拒绝该请求*，
RFC 4120 §7.5.9），错误文本和 `Logf` 行都会点明该选项。keytab 中的密钥
（`krbtgt`、服务）和 TGS 不受影响。

## 为需要 PAC 的服务 {#pac}

自 v0.12.0 起，`Config.PAC` 中列出的服务的服务票据携带 Privilege Attribute
Certificate（[MS-PAC]：LOGON_INFO、CLIENT_INFO、UPN_DNS_INFO、PAC_REQUESTOR
以及各签名）。它**默认关闭**：`Config.PAC` 为 nil 时，任何票据都不带 PAC。

```go
PAC: &kdc.PAC{
	DomainSID: "S-1-5-21-1111111111-2222222222-3333333333", // NewDomainSID makes one
	Services:  []string{"nfs/files.example.org"},
},
```

RID 取自目录的编号：`uidNumber` 是用户 RID，`gidNumber` 是组 RID，没有
`gidNumber` 的组被省略。**没有** `uidNumber` 的人，或两个编号相同的账户，会以
`KDC_ERR_POLICY` 被拒绝。最多携带 256 个组。使用 KDC 域 SID 的 `member server`
角色 Samba 4.22（带 `winbindd`）接受了这些票据；`PAC.NetBIOSDomain` 必须等于
Samba 的 `workgroup`。

**大 PAC 与 UDP。** 自 v0.12.1 起（RFC 4120 §7.2.1），超过 1465 字节的应答不再
作为数据报发送：客户端收到 `KRB_ERR_RESPONSE_TOO_BIG`，改用 TCP 重复请求。
1465 是此 KDC 的选择，不是标准。

**此人是如何登录的。** 自 v0.13.0 起，设置 `Config.PAC` 后，每个 PAC 都带有
`S-1-18-1`（*authentication authority asserted identity*），经 `MintHandler` 签发的
票据还带有在域内生成的 SID。TGT 中含有用 krbtgt 密钥签名的 CAMMAC（[RFC 8129]，
MIT 格式），记录登录方式和请求者的 `uidNumber`。因此签发请求必须说明此人是如何登录
的，即 `"method"`：`passkey`、`federated` 或 `machine`；配置了 PAC 而缺少它时，应答为
`400`。在 TGS，标记无法验证的 TGT 以 `KRB_AP_ERR_MODIFIED` 拒绝；`uidNumber` 与目录
不再一致的 TGT（账户被删除后以同名重建，CVE-2021-42287）以 `KDC_ERR_TGT_REVOKED`
拒绝。客户端自带的 enc-authorization-data 被忽略。升级前签发的 TGT 没有标记，按密码
登录最多接受 10 小时，之后拒绝。**升级说明：**在配置了 PAC 的 KDC 升级之前，
`go-authn/bridge` 必须先发送 `method`。服务票据上的指示符尚未实现。

## 给它一个索引：`Finder` {#finder}

每个 AS-REQ 和 TGS-REQ 都要查找一个人。使用普通的 `directory.Source` 时，这就是
`Identities()` 加一次遍历：10,000 人时，遍历占 AS-REQ CPU 的一半；而在
`Identities()` 中读取数据库或 LDAP 服务器的来源，会被每个请求（包括未经认证的请求）
完整读取一遍。**自 v0.6.0 起**，持有索引的来源可以实现

```go
Find(name string) (*directory.Identity, bool, error)
```

域会询问它而不是遍历。身份的名称必须与主体**完全**相同——主体区分大小写，因此名称不同的
应答视为未知主体——错误则回答 `KDC_ERR_SVC_UNAVAILABLE`。有 `Finder` 时，查找低于
CPU 性能剖析的阈值；请求剩下的主要是 gokrb5 的 ASN.1 编码。
[authnd]({{< relref "/authnd/kerberos.md#where-the-realm-reads-people" >}}) 正是这样把
刷新后的快照交给域的。

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
		AllowPasswordDerivedAS: true, // off by default since v0.11.0
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
  错误时为 `KRB_AP_ERR_MODIFIED`）。自 v0.7.0 起，Windows 客户端发送的 RSA-MD5（类型 7）校验和
  （无密钥，但由会话密钥封装）会被接受，与 MIT 相同；CRC32、MD4 和 SHA-1 仍被拒绝；
- TGT 未过结束时间（`KRB_AP_ERR_TKT_EXPIRED`），未早于其开始时间，
  也未被标记为无效（`KRB_AP_ERR_TKT_NYV`），且不允许时钟偏差：
  这些时间是此 KDC 的时钟写入的；
- 客户端属于本域，且仍在目录中
  （`KDC_ERR_C_PRINCIPAL_UNKNOWN`）；
- 认证符所指的客户端与票据中的相同，名称和域都一致
  （`KRB_AP_ERR_BADMATCH`，自 v0.8.0 起）。

**自 v0.5.0 起**，逐字节完全相同的请求再次到达时（通过 UDP 丢失了应答的客户端，
或重放者），会得到它已经得到过的应答，而不再重新处理：移植自 MIT KDC 的
lookaside（`src/kdc/replay.c`）。条目保留两分钟，总量保持在 10 MiB 以下，最旧的先被
丢弃；`KRB-ERROR` 从不保存，因此收到 `KDC_ERR_SVC_UNAVAILABLE` 的客户端在目录恢复后会
被重新处理。这里有意不设认证符重放缓存：MIT 的 KDC 在 TGS 上关闭了它，因为重传会因
`KRB_AP_ERR_REPEAT` 而失败，而重放者也打不开用他没有的密钥封装的应答。无法读取的目录在
AS 和 TGS 上都返回 `KDC_ERR_SVC_UNAVAILABLE`，即使密码正确也是如此——绝不是
`KDC_ERR_PREAUTH_FAILED`，因此不会计入锁定——而且 Kerberos 从不调用验证器（`ldap`
上游）（`KDC_ERR_NULL_KEY`）。代价：每个请求多两次分配（`BenchmarkTGSReq` 从 1,784 到
1,786）；机器负载较高，未比较耗时。

**自 v0.4.5 起**，经过安全审计以及模糊测试和混沌测试：

- 针对另一个域的请求在 AS 和 TGS 处都回答 `KDC_ERR_WRONG_REALM`，而不是被处理；
- 无法读取的目录回答 `KDC_ERR_SVC_UNAVAILABLE`，不再回答 `KDC_ERR_C_PRINCIPAL_UNKNOWN`；
- 开始时间在 `MaxSkew` 之内的未来的 TGT 会被接受（时钟跳变），而以前 TGT 的开始时间不允许任何偏差；
- **一个格式错误的 AS-REQ 或 TGS-REQ 就能使进程崩溃**：gokrb5 v8.4.4 的 `unmarshalTicketsSequence`
  在任何认证之前就会 panic。现在，使解码器 panic 的请求会被丢弃，panic 及其堆栈会被记录。
  自 v0.8.1 起，导致它的已知形态，即不是 `[11] SEQUENCE` 的 additional-tickets 字段，会在 gokrb5 解码之前被丢弃；
  解码器的其他 panic 仍会使一个请求丢失；
- 来自网络的主体名称在日志中加引号，使其无法伪造一行；
- 依赖项为 golang.org/x/net v0.62.0（GO-2026-6866、GO-2026-6860）和 go-authn/directory v0.16.1。
  GO-2026-5932（`golang.org/x/crypto/openpgp`）在上游没有修复，且不会被调用。

`FuzzHandle` 在两次运行（90 秒和 150 秒）中执行了约 1400 万次，没有任何 panic 逃出。`BenchmarkASNoPreauth`，
10,000 人中的最后一人，不带预认证：每个请求 508 次分配、18,999 字节、112 µs；没有之前的数字，因为该路径上的
代码没有变化。时间仅供参考：负载为 65，所以没有与 MIT 的 `krb5kdc` 作比较。

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

[pkg.go.dev/github.com/go-authn/kdc@v0.8.1](https://pkg.go.dev/github.com/go-authn/kdc@v0.8.1)
