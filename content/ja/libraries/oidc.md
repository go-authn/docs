---
title: "oidc — ベアラートークンの検証"
linkTitle: "oidc"
weight: 90
description: "go-authn/oidc は OpenID Connect トークンを検証して ID にする: ディスカバリー、鍵セット、アルゴリズムの許可リスト、そして重要な拒否。依存関係なし。"
tags: [ライブラリ, oidc, トークン]
---

**このベアラートークンは誰が尋ねていると述べ、それを信じるべきか。**
ディスカバリー、鍵セット、そしてリソースサーバーが行わなければならないチェックを、標準
ライブラリ以外の**依存関係なし**の純粋な Go で。

```sh
go get github.com/go-authn/oidc@v0.6.0
```

ここにログインフローはありません。リダイレクトも、コード交換も、クライアントシークレットも、
クッキーもありません。これは**リソースサーバー**側の半分です。トークンを伴って何かが届き、
これがそれが誰かを述べます。

## 例 {#example}

```go
package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"strings"

	"github.com/go-authn/oidc"
)

func main() {
	// Discovery happens here, at startup: an issuer that does not answer is
	// a server that cannot authenticate anybody.
	v, err := oidc.New(context.Background(), oidc.Config{
		Issuer:   "https://login.example.org",
		Audience: "fileshare",
		Type:     "at+jwt", // a resource server takes access tokens, not ID tokens
	})
	if err != nil {
		log.Fatal(err)
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		raw, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		tok, err := v.Verify(r.Context(), raw)
		if err != nil {
			log.Print(err) // which check refused it: for this log only
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		fmt.Fprintln(w, tok.Subject(), tok.Username(), tok.Groups())
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
```

`Verifier` は並行利用に対して安全で、鍵セットを保持します。起動時に一つ作って保持してください。
`Verify` のエラーは、サーバーのログのために、どのチェックがトークンを拒否したかを述べます。
クライアントには、どのチェックであっても一つの拒否が返ります。

何かが取得される前に `New` が拒否する三つの設定:

```go
package main

import (
	"context"
	"fmt"

	"github.com/go-authn/oidc"
)

func main() {
	ctx := context.Background()
	for _, cfg := range []oidc.Config{
		{Issuer: "http://login.example.org", Audience: "fileshare"},
		{Issuer: "https://login.example.org"},
		{Audience: "fileshare"},
	} {
		_, err := oidc.New(ctx, cfg)
		fmt.Println(err)
	}
}
```

```
oidc: http://login.example.org is not https: the key set decides every signature, and over cleartext so does anybody on the way
oidc: no audience: a token minted for another service is a valid token, and a verifier that does not check accepts every one the issuer ever signed
oidc: no issuer: a verifier without one accepts tokens from anybody
```

`Config` の残りは任意です。`JWKSURL` はディスカバリーを省略します。`UsernameClaim` と `GroupsClaim`
(既定は `groups`) はクレームを名指しします。`ClockSkew` と `MinRefresh` の既定は一分です。`Client` は
HTTP クライアントで、プロキシ、プライベート CA、タイムアウト用です。`Token` は `Subject`、`Issuer`、
`Audience`、`Email`、`EmailVerified`、`Username`、`Groups`、`Expiry`、`NotBefore`、`IssuedAt` を読みます。
`Claim(name, &v)` は他の任意のクレームをデコードし、`Has(name)` はそれがあるかどうかを述べます。

## 受け入れるもの {#what-it-accepts}

十種類の署名アルゴリズムを**許可リスト**として受け入れます。`RS256` `RS384` `RS512`、`PS256`
`PS384` `PS512`、`ES256` `ES384` `ES512`、`EdDSA` (Ed25519) です。`alg` がこれらのいずれでもない
トークンは、鍵が取得される前に拒否されます。`alg: none` と HMAC ファミリーはリストにないことで
拒否され、鍵はアルゴリズムの種類でなければなりません。`RS256` を主張するトークンは、RSA 鍵で
検証されるか、拒否されます。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

| | 理由 |
|---|---|
| `alg: none` | 署名されていないと自ら述べるトークンは、誰かが入力した JSON オブジェクトである |
| 公開鍵に対する HMAC | `HS256` は共有シークレットを取るが、発行者の鍵は公開されている。誰でもトークンを作れてしまう |
| 正しい発行者で**始まる**だけの発行者 | `iss` は全体で比較される。`https://login.example.org.evil.test` は正しい文字列で始まっている |
| 欠けている、または間違った**オーディエンス** | 別のサービス向けに作られたトークンは有効だが、これ宛てではない |
| **有効期限のない**トークン | 一度コピーされればパスワードになる |
| ループバック以外への、**平文の HTTP** 上の発行者、鍵セット、リダイレクト | 鍵セットがすべての署名を決める |
| 2048 ビット未満の RSA 鍵、または `n` や `e` が最短形式でないもの、曲線上にない EC 点 | 短い鍵の署名は偽造できる。v0.2.2 より前は、ゼロバイトでパディングした 1024 ビットのモジュラスが 2048 ビットとして通った |
| `sig` 以外の `use` で公開された鍵 | 鍵セットは正当に暗号化鍵も保持する |
| `Type` が設定されている場合は別の `typ` のトークン。未設定の場合は `JWT` または `at+jwt` 以外の `typ` (`typ` ヘッダーのないトークンは通る) | RFC 9068 §4: リソースサーバーは `typ: at+jwt` を確認する。そうでないと、オーディエンスが一致すれば ID トークンをアクセストークンと取り違える |
| 正規の base64url でない部分 | トークンは一つの文字列として検証される |

ECDSA の `s` と `n − s` はどちらも、アルゴリズムが許すとおり検証に通ります。そのため拒否リストや
リプレイキャッシュは、送られたトークンではなく `jti` や `sub` をキーとします。

**鍵はローテーションされますが、未知の鍵は発行者を叩く手段ではありません。** 保持しているどの鍵でも
検証できない署名には、`kid` が新しい場合でも、同じ `kid` が新しい鍵を運ぶ場合でも、`MinRefresh` ごとに
一度、鍵セットを取得し直す価値があります。取得の進行中に鍵セットが必要なトークンはそれを待ち、
失敗した取得もカウントされます。

**`Username()` がどの名前を返すか。** 既定では `preferred_username`、次に `email_verified` が true の
場合**のみ** `email`、次に `sub` です。未検証のメールは、その人が入力した文字列です (OIDC Core §5.1)。
設定された `UsernameClaim` は、フォールバックなしで、名指しされたとおりに読まれます。

## 複数の発行者と、特定の機関だけを受け入れる {#several-issuers-and-only-some-institutions}

**v0.5.0** から、`oidc.NewSet(v1, v2, …)` は複数の発行者のトークンを検証します。検証器ごとに audience と鍵セットを持ちます。トークンは **未検証の** `iss` により、その発行者に正確に設定された検証器へ振り分けられ、そこで検証されます（その発行者の鍵による署名、`iss` の再確認、audience、時刻）。`iss` の読み取りは鍵セットの選択にすぎず、偽造トークンは後続の検証で失敗します。未知の `iss` は `ErrUnknownIssuer` となりネットワークアクセスは発生しません。他の発行者の鍵セットを試すことはなく、同一発行者に対する 2 つの検証器は拒否され、`MaxTokenSize`（16 KiB）を超えるトークンはデコード前に拒否されます。

フェデレーションプロキシ（MyAccessID 経由の eduGAIN、eduTEAMS、Renater、Keycloak ブローカー）の背後では、`oidc.Accept{Claim, Values}` と `oidc.Check(accepts, token)` が、クレームが提供対象の機関のいずれの値も含まないトークンを拒否します。すべての accept が満たされる必要があり、複数値のクレームでは 1 つの値が一致すれば十分です。存在しないクレーム、または文字列（の配列）でないクレームは何も含みません。大文字小文字の扱いはクレームのスキーマに従います。`schac_home_organization`（SCHAC 1.6.0、ドメイン名、`caseIgnoreMatch`）、`eduperson_scoped_affiliation`、`voperson_external_affiliation` は大文字小文字を区別せず、他のクレームは完全一致で比較します。畳み込むのは ASCII 文字のみです（ケルビン記号 U+212A は `k` ではありません）。クレームは検証されるトークンに含まれている必要があります。MyAccessID は `schac_home_organization` を userinfo でのみ提供します。

## スコープ付きの名前と、そのスコープが誰のものか {#scoped-names}

アカウントは機関に属します。連合プロキシの背後では、1 つの発行者が多くの機関の人を保証します。`oidc.ScopedName(name, allowed, defaultScope)` は、この発行者が主張してよいスコープかどうかを Shibboleth のスコープ検査のように**確認した上で**、名前を ASCII 小文字の `local@scope` として返します（eduPersonPrincipalName は eduPerson スキーマで `caseIgnoreMatch`、単一値です）。別のスコープは `ErrScopeNotAllowed`、スコープもデフォルトもない名前は `ErrNoScope` です。`@` のない名前には `defaultScope`（スコープ付き名前より前からアカウントがある機関）が付き、これも許可されている必要があります。`Token.ScopedUsername` はトークンのユーザー名に対して同じことを行います。`UsernameClaim` に `eduperson_principal_name` または `voperson_id` を設定してください。スコープは最後の `@` の後ろの部分です。

## 何に対して検証されているか {#what-it-is-checked-against}

**pyjwt** がテストスイートのすべてのトークンに署名するので、検証器が同じ手による署名者に審査される
ことはありません。HMAC 混同トークンは、pyjwt が生成を拒否するため、手作業で偽造します。
`testdata/fixed.json` — pyjwt が固定の鍵で一度署名したトークン — により、s390x を含むアーキテクチャの
レーンが、時計を固定して本物の署名を検証できます。Linux のテストレーン、レース検出器、カバレッジ
レーンは pyjwt をインストールして `OIDC_REQUIRE_JUDGE` を設定するので、pyjwt がないとスキップでは
なく失敗します。HMAC の受け入れ、発行者の前方一致での比較、オーディエンスチェックの省略は、
それぞれ意図的に試され、いずれもテストを赤にします。カバレッジレーンの下限は 90% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/oidc@v0.6.0](https://pkg.go.dev/github.com/go-authn/oidc@v0.6.0)
