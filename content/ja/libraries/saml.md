---
title: "saml — フェデレーションの手前に置くサービスプロバイダー"
linkTitle: "saml"
weight: 100
description: "go-authn/saml は RENATER や eduGAIN のような研究フェデレーション向けの SAML 2.0 サービスプロバイダー: 署名付きメタデータ、AuthnRequest、そしてあらゆるチェックの後に読まれるアサーション。"
tags: [ライブラリ, saml, フェデレーション]
---

**この人の ID プロバイダーは、その人について何と述べたか。** RENATER の Fédération
Éducation-Recherche や eduGAIN のような ID フェデレーション向けの SAML 2.0 サービスプロバイダーです。
フェデレーションの署名付きメタデータを読み、人々をその人自身の所属機関の ID プロバイダーに送り、
そのプロバイダーが述べることを読み戻します。

```sh
go get github.com/go-authn/saml@v0.4.1
```

これは [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) のフェデレーションに面した半分で、
SAML SP になりたいものなら単独でも使えます。ここにないもの: IdP、シングルログアウト、アーティファクト
バインディング、署名付き AuthnRequest、属性クエリ、SAML 1.1。

| | |
|---|---|
| `Federation` | メタデータを取得し、**固定された**証明書に対して検証し、`Run` で最新に保つ |
| `ParseMetadata` | すでに手元にある文書に対する同じ検証 |
| `DiscoveryURL`、`Chosen` | 人をディスカバリーサービスに送り、選ばれた IdP を読み戻す |
| `SP.Request` | HTTP-Redirect 経由の AuthnRequest と、保持すべき `Pending` |
| `SP.Accept` | ACS に POST された `SAMLResponse` を `Assertion` に読み込む |
| `Assertion.Subject` | `subject-id`、次に `pairwise-id`、次に `eduPersonPrincipalName`、次に `eduPersonTargetedID`、次に永続的な NameID — メールは決して使わない |
| `SP.Metadata` | フェデレーションに登録する、SP 自身のメタデータ |

## 例 {#example}

ディスカバリーとリクエスト。一つの IdP を手作業で記述して:

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

サービスでは、メタデータはフェデレーションから来て、応答は ACS に届きます。

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

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**メタデータ:**

| | 理由 |
|---|---|
| **固定された**証明書で署名されていない | 証明書はパラメーターであり、メタデータと一緒に取得されることは決してない。保証する対象の文書と同じ経路で届く鍵は、何も保証しない |
| `validUntil` を過ぎている、またはない | 期限のない署名付き文書は、終わらない鍵の漏えいである。更新に失敗しても、最後の正常なコピーは、そのコピーが期限切れになるまで保持される |
| 現在から 28 日を超えて有効 | `Federation.MaxValidity` で上限を変更できる。負の値で上限なし |
| 使用中のコピーより古い | ロールバック: 正しく署名されていて、その後に失効した鍵を運んでいるかもしれない |
| ループバック以外から `http://` で取得 | 署名は変更を検出するが、新しい文書を止める経路は検出できない |

メタデータ内の IdP の証明書は、フェデレーションの署名がそれを名指ししているために信頼されます。
IdP の証明書は自己署名で期限切れのことが多いので、その日付は見られません。

**応答**は `Accept` で検証されます。以下の各拒否は、サーバーのログのために、エラーとして呼び出し側に
返されます。

| | 理由 |
|---|---|
| 何も署名されていない、または SHA-1 で署名されている | saml-profiles 4.1.4.5: POST ではアサーションに署名が必要。Shibboleth IdP は既定で Response に署名する。どちらでも受け入れられる |
| 複数のアサーション | 署名付きと署名なしのものが同時に届き、間違ったほうが読まれる手口 (CVE-2022-41912) |
| 署名が対象とした範囲の外にあるすべて | 決して読まれない。署名がダイジェストしたバイト列から再構築された要素だけが読まれる |
| IdP の `Scopes` の外にあるスコープ付き識別子 | 破棄される。そうでなければ、どの IdP も `alice@another-university.example` を表明できてしまう |
| 検証済みの署名が対象としていない AES-CBC 暗号文 | 復号すらされない。認証なしの CBC はパディングオラクルである。RSA PKCS#1 v1.5 の鍵転送はまったく受け入れられず、AES-GCM と RSA-OAEP は受け入れられる |
| 別のオーディエンス、ACS、またはリクエスト。求められていない応答。一時間より古いリクエスト | saml-profiles 4.1.4.3 |
| すでに使われたアサーション | ベアラーアサーションは、それを持つ者そのものである |
| 理解できない条件 | saml-core 2.5.1: その場合アサーションは Indeterminate |
| MFA が求められたのに返されたパスワード (`Options.AuthnContext`) | IdP はリクエストを無視することがある |
| `ForceAuthn` の場合に、リクエストより前の `AuthnInstant` | IdP が、再利用しないよう求められたセッションを再利用した |

{{< callout type="warning" >}}
**既定のリプレイキャッシュは一つのプロセスのメモリ**

`SP.Replay` の既定は `NewMemoryReplay()` です。ロードバランサーの背後に複数のインスタンスがあると、
それぞれが同じアサーションを一度ずつ受け入れてしまい、再起動で空になります。共有ストレージ上に
`Replay` を実装してください。その `Use` はアトミックでなければなりません。
{{< /callout >}}

## 何に対して検証されているか {#what-it-is-checked-against}

- **RENATER 自身のメタデータ**。RENATER が 2026-09-29 に署名したもので、`testdata/fer-idps.xml.gz` に
  あり、その証明書は RENATER が公開する SHA-256 フィンガープリントと照合されます。343 すべての IdP が
  読まれ、一つの `Location` のホストを書き換えたものは拒否されます。s390x を含むアーキテクチャの
  レーンも、その署名を検証します。
- **xmlsec1** がスイート内のすべての応答に、テンプレートから署名し暗号化します。GCM と CBC、
  SHA-1 と SHA-256 の RSA-OAEP、Response に署名、アサーションに署名、その両方。Linux のテスト
  レーン、レース検出器、カバレッジレーンがそれをインストールして `SAML_REQUIRE_JUDGE` を設定します。
- **crewjam/saml の IdP** が、別の CI ジョブ (`interop/crewjam`。独自のモジュールで、公開される
  モジュールには含まれない) で、この SP の AuthnRequest に対する完全な応答を書きます。AES-128-CBC
  付きの RSA-SHA256 で Response に署名したものは受け入れられ、その既定の RSA-SHA1 は拒否され、
  Response の署名を取り除いた同じ CBC アサーションは、復号の前に拒否されます。

カバレッジレーンの下限は 92% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/saml@v0.4.1](https://pkg.go.dev/github.com/go-authn/saml@v0.4.1)
