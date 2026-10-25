---
title: "saml — 置于联邦之前的服务提供方"
linkTitle: "saml"
weight: 100
description: "go-authn/saml 是面向 RENATER 或 eduGAIN 等科研联邦的 SAML 2.0 服务提供方：已签名的元数据、AuthnRequest，以及在经过每项检查之后才读取的断言。"
tags: [库, saml, 联邦]
---

**此人的身份提供方对他们说了什么？** 面向 RENATER 的 Fédération
Éducation-Recherche 或 eduGAIN 等身份联邦的 SAML 2.0
服务提供方：它读取联邦的已签名元数据，
把人员送到其所属机构的身份提供方，并读回
该提供方所说的内容。

```sh
go get github.com/go-authn/saml@v0.4.1
```

它是 [authn-bridge]({{< relref "/authn-bridge/_index.md" >}})
面向联邦的那一半，任何想要成为
SAML SP 的程序都可以单独使用它。不包含：IdP、单点注销、artifact 绑定、已签名的
AuthnRequest、属性查询、SAML 1.1。

| | |
|---|---|
| `Federation` | 获取元数据，对照**固定的**证书验证它，并通过 `Run` 使其保持最新 |
| `ParseMetadata` | 同样的验证，针对已在手中的文档 |
| `DiscoveryURL`、`Chosen` | 将人员送到发现服务，并读回其所选择的 IdP |
| `SP.Request` | 通过 HTTP-Redirect 发送的 AuthnRequest，以及要保留的 `Pending` |
| `SP.Accept` | 提交到 ACS 的 `SAMLResponse`，被读取为 `Assertion` |
| `Assertion.Subject` | `subject-id`，然后是 `pairwise-id`，然后是 `eduPersonPrincipalName`，然后是 `eduPersonTargetedID`，然后是持久 NameID——绝不是邮件地址 |
| `SP.Metadata` | SP 自己的元数据，用于向联邦注册 |

## 示例 {#example}

发现和请求，其中一个 IdP 为手工描述：

```go
package main

import (
	"fmt"
	"net/url"

	"github.com/go-authn/saml"
)

func main() {
	// One IdP, as a federation's metadata would describe it.
	idp := &saml.IdP{
		EntityID: "https://idp.univ-example.example/idp/shibboleth",
		SSO:      "https://idp.univ-example.example/idp/profile/SAML2/Redirect/SSO",
		Scopes:   []string{"univ-example.example"},
	}
	md := &saml.Metadata{IdPs: map[string]*saml.IdP{idp.EntityID: idp}}

	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Federation: md,
	}

	// Send the person to the discovery service, then read back what it chose.
	d, _ := saml.DiscoveryURL("https://discovery.renater.fr/renater", sp.EntityID, "https://app.example.org/saml/chosen")
	fmt.Println(d)

	_, err := saml.Chosen(url.Values{"entityID": {"https://idp.attacker.example/idp"}}, md)
	fmt.Println(err)
	chosen, _ := saml.Chosen(url.Values{"entityID": {idp.EntityID}}, md)

	// The AuthnRequest, over HTTP-Redirect. Keep p, keyed by the RelayState,
	// and hand it to sp.Accept at the ACS.
	to, p, err := sp.Request(chosen, "s1", saml.Options{AuthnContext: []string{"https://refeds.org/profile/mfa"}})
	if err != nil {
		panic(err)
	}
	u, _ := url.Parse(to)
	fmt.Println(u.Host, u.Query().Has("SAMLRequest"), u.Query().Get("RelayState"), p.IdP, p.AuthnContext)

	// RelayState is limited to 80 bytes, and refused beyond that.
	_, _, err = sp.Request(chosen, string(make([]byte, 81)), saml.Options{})
	fmt.Println(err)
}
```

```
https://discovery.renater.fr/renater?entityID=https%3A%2F%2Fapp.example.org%2Fsaml&return=https%3A%2F%2Fapp.example.org%2Fsaml%2Fchosen&returnIDParam=entityID
the chosen identity provider is not in the federation
idp.univ-example.example true s1 https://idp.univ-example.example/idp/shibboleth [https://refeds.org/profile/mfa]
RelayState is limited to 80 bytes
```

在实际服务中，元数据来自联邦，而响应到达
ACS：

```go
package main

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"log"
	"net/http"
	"os"

	"github.com/go-authn/saml"
)

func main() {
	ctx := context.Background()

	// The federation's metadata signing certificate, downloaded ONCE and
	// checked against the fingerprint the federation publishes.
	fed := &saml.Federation{
		URL:  "https://pub.federation.renater.fr/metadata/fer/idps.xml",
		Cert: readCert("/etc/app/metadata-signature-2026.pem"),
	}
	if err := fed.Refresh(ctx); err != nil {
		log.Fatal(err)
	}
	go fed.Run(ctx, func(err error) { log.Print(err) })

	pair, err := tls.LoadX509KeyPair("/etc/app/saml.crt", "/etc/app/saml.key")
	if err != nil {
		log.Fatal(err)
	}
	sp := &saml.SP{
		EntityID:   "https://app.example.org/saml",
		ACS:        "https://app.example.org/saml/acs",
		Key:        pair.PrivateKey.(*rsa.PrivateKey), // assertions arrive encrypted to it
		Cert:       pair.Leaf,
		Federation: fed,
	}

	http.HandleFunc("/saml/acs", func(w http.ResponseWriter, r *http.Request) {
		p := pendingFor(r.PostFormValue("RelayState")) // what Request returned, from the session
		a, err := sp.Accept(r.PostFormValue("SAMLResponse"), p)
		if err != nil {
			log.Print(err) // for the log, not for the browser
			http.Error(w, "refused", http.StatusForbidden)
			return
		}
		id, from := a.Subject()
		log.Printf("%s (%s) from %s", id, from, a.IdP.EntityID)
	})
	log.Fatal(http.ListenAndServeTLS(":443", "/etc/app/tls.crt", "/etc/app/tls.key", nil))
}

func readCert(path string) *x509.Certificate {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		log.Fatal("no PEM block in ", path)
	}
	c, err := x509.ParseCertificate(blk.Bytes)
	if err != nil {
		log.Fatal(err)
	}
	return c
}

// pendingFor is the caller's session store.
func pendingFor(relayState string) saml.Pending { return saml.Pending{} }
```

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**元数据：**

| | 原因 |
|---|---|
| 不是由**固定的**证书签名 | 证书是一个参数，绝不与元数据一同获取：与它所担保的文档通过同一渠道到达的密钥，什么也担保不了 |
| 超过其 `validUntil`，或没有该字段 | 永不过期的已签名文档，意味着永远不会结束的密钥泄露。刷新失败时保留上一份良好的副本，直到该副本过期 |
| 有效期距今超过 28 天 | `Federation.MaxValidity` 可更改该界限；负值则取消它 |
| 比正在使用的副本更旧 | 回滚：签名有效，并且可能带有此后已被吊销的密钥 |
| 通过 `http://` 从环回之外的任何地方获取 | 签名可以发现更改，却发现不了扣留新文档的路径 |

元数据中 IdP 的证书之所以受信任，是因为联邦的签名
指名了它；不检查其日期，因为 IdP 证书常常是
自签名且已过期的。

**响应**在 `Accept` 时检查。下面的每项拒绝都会作为错误返回给
调用方，供服务器的日志使用：

| | 原因 |
|---|---|
| 没有任何签名，或使用 SHA-1 签名 | saml-profiles 4.1.4.5：通过 POST 时断言必须经过签名。Shibboleth IdP 默认对 Response 签名；两者皆可接受 |
| 多于一个断言 | 这正是已签名的断言与未签名的断言同时到达而读取了错误那个的方式（CVE-2022-41912） |
| 签名所覆盖范围之外的任何内容 | 绝不读取：只读取根据签名所摘要的字节重建的元素 |
| 位于 IdP 的 `Scopes` 之外的带 scope 标识符 | 丢弃：否则任何 IdP 都可以断言 `alice@another-university.example` |
| 没有已验证签名覆盖的 AES-CBC 密文 | 甚至不解密：未经认证的 CBC 是填充预言机。完全不接受 RSA PKCS#1 v1.5 密钥传输；接受 AES-GCM 和 RSA-OAEP |
| 另一个 audience、ACS 或请求；未经请求的响应；超过一小时的请求 | saml-profiles 4.1.4.3 |
| 已经使用过的断言 | 持有者断言属于持有它的任何人 |
| 它不理解的条件 | saml-core 2.5.1：该断言随后为 Indeterminate |
| 要求 MFA（`Options.AuthnContext`）时返回了密码 | IdP 可能忽略该请求 |
| 使用 `ForceAuthn` 时，早于请求的 `AuthnInstant` | IdP 重用了被要求不要重用的会话 |

{{< callout type="warning" >}}
**默认的重放缓存是单个进程的内存**

`SP.Replay` 默认为 `NewMemoryReplay()`。负载均衡器之后的多个实例
会各自接受同一个断言一次，而重启会清空
它。请基于共享存储实现 `Replay`；其 `Use` 必须是原子的。
{{< /callout >}}

## 它对照什么检查 {#what-it-is-checked-against}

- **RENATER 自己的元数据**，即 RENATER 于 2026-09-29 签名的版本，位于
  `testdata/fer-idps.xml.gz`，其证书对照 RENATER 发布的
  SHA-256 指纹检查。读取全部 343 个 IdP；改写
  某个 `Location` 的主机会被拒绝。各架构通道（包括 s390x）
  也会验证该签名。
- **xmlsec1** 根据模板签名并加密套件中的每个响应：
  GCM 和 CBC、使用 SHA-1 和 SHA-256 的 RSA-OAEP、Response 签名、
  断言签名、两者皆签。Linux 测试通道、竞态检测器和
  覆盖率通道安装它并设置 `SAML_REQUIRE_JUDGE`。
- **crewjam/saml 的 IdP** 在单独的 CI 作业中针对此 SP 的 AuthnRequest 写出完整的响应
  （`interop/crewjam`，自成一体的模块，不在已发布的
  模块中）：RSA-SHA256 加 AES-128-CBC 且 Response 已签名的响应被接受；其
  默认的 RSA-SHA1 被拒绝；去掉 Response 签名的同一个 CBC 断言
  在解密之前就被拒绝。

覆盖率通道的下限是 92%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/saml@v0.4.1](https://pkg.go.dev/github.com/go-authn/saml@v0.4.1)
