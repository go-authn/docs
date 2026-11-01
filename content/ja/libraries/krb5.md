---
title: "krb5 — Kerberos チケットを受け入れる"
linkTitle: "krb5"
weight: 70
description: "go-authn/krb5 は Kerberos の受け入れ側: キータブ、検証される AP-REQ、相互認証に必要な AP-REP、そしてセッション鍵の下で署名され封印されるメッセージ。"
tags: [ライブラリ, kerberos]
---

**この Kerberos チケットはこのサービスに有効か。** Kerberos の**受け入れ側**の半分、そしてその半分だけ
です。キータブを保持し、クライアントが提示する AP-REQ を検証し、サービスが本物であることを証明する
AP-REP で応答し、その交換が確立した鍵の下でメッセージの署名、検証、封印、開封を行います。

```sh
go get github.com/go-authn/krb5@v0.3.3
```

v0.3.3 は API もコードも変えません。間接依存の golang.org/x/net を v0.62.0、golang.org/x/crypto を v0.58.0、
github.com/hashicorp/go-uuid を v1.0.4 に上げます。`govulncheck` は、必要としていても呼び出していないモジュールで 46 件を
報告していましたが、今は 1 件、GO-2026-5932 (`golang.org/x/crypto/openpgp`) だけです。これには修正版がなく、go-authn の
どれもインポートしていません。コードから到達できる検出は、前も後も 0 です。

KDC とは決して話さず、チケットを発行することもないので、誰のチケットを受け入れるかは他の誰かの
判断です。発行側は [kdc]({{< relref "/libraries/kdc.md" >}}) で、このモジュールはそれに依存しません。
[別々である理由]({{< relref "/libraries/_index.md#why-they-are-separate-modules" >}})を参照してください。
チケットの復号は [gokrb5](https://github.com/jcmturner/gokrb5) のものです。

## 存在する理由 {#why-it-exists}

gokrb5 はクライアントライブラリです。AP-REQ は検証できますが、それに答える AP-REP は構築できません。
すべての GSS-API クライアントは相互認証を求めます。MIT 自身の `gss-client` は `GSS_C_MUTUAL_FLAG` を
設定し、無効にする手段がありません。そのため、AP-REP を作れないサービスはコンテキストをまったく
完了できません。それを構築することが、このモジュールが加えるもののほとんどです。

## 例 {#example}

```go
package main

import (
	"errors"
	"fmt"
	"log"

	"github.com/go-authn/krb5"
	"github.com/jcmturner/gokrb5/v8/keytab"
)

// establish is one GSS-API exchange: the client's AP-REQ in, the AP-REP out.
func establish(a *krb5.Acceptor, token []byte) (*krb5.Context, []byte, error) {
	ctx, apRep, err := a.Accept(token)
	if err != nil {
		return nil, nil, err // no context: refuse, never fall back to something weaker
	}
	// The client will not consider the context open until it has verified
	// apRep, so sending it back is not optional.
	log.Printf("%s (user %q, realm %q) until %s", ctx.Principal(), ctx.User(), ctx.Realm(), ctx.Expires())
	return ctx, apRep, nil
}

func main() {
	// In a service: krb5.Load("/etc/krb5.keytab", krb5.Principal("nfs/files.example.org")).
	// Here, an empty keytab, so the refusals can be seen.
	a := krb5.New(keytab.New(), krb5.Principal("nfs/files.example.org"))

	_, _, err := establish(a, []byte("not a token"))
	fmt.Println(errors.Is(err, krb5.ErrNotAToken), err)

	_, err = krb5.Load("/nonexistent/krb5.keytab")
	fmt.Println(errors.Is(err, krb5.ErrNoKeytab), err)
}
```

```
true krb5: not a GSS-API krb5 token: asn1: structure error: explicitly tagged member didn't match
true krb5: keytab "/nonexistent/krb5.keytab": open /nonexistent/krb5.keytab: no such file or directory
```

`krb5.New` が受け取る `keytab.New` のために `github.com/jcmturner/gokrb5/v8` が必要です。
`krb5.Load` は代わりにパスからキータブを読みます。

`Accept` の後、`*Context` は誰であるかを述べます。`Principal()` (`alice@EXAMPLE.ORG`)、または
`User()` と `Realm()` を別々に。プリンシパルをローカルアカウントに対応付けることは呼び出し側の
ポリシーです。`alice@EXAMPLE.ORG` と `alice@PARTNER.ORG` はどちらも "alice" に答えます。
`Expires()` はその背後のチケットが終わる時刻で、長寿命の接続を保持するサーバーは、それを過ぎたら
尊重を止めるべきです。`MIC`/`VerifyMIC` と `Wrap`/`Unwrap` は署名を行い、`Seal`/`Unseal` は機密性を
加えます (`sec=krb5p`)。`Context` は並行利用に対して安全ではなく、`Acceptor` は安全です。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**このサービスが受け入れないチケット** — 間違ったサービス、間違った鍵、期限切れ、リプレイ、
`ClockSkew` (既定は五分で、MIT と同じ) を超える時計 — は `ErrRejected` です。GSS-API krb5 トークンで
ないバイト列は `ErrNotAToken`、AP-REQ でないトークンは `ErrNotAPReq` です。エラーは意図的に粗くして
あります。クライアントはチケットが拒否されたことを知るだけで、どのチェックが拒否したかは決して
知りません。エラーはコンテキストがないことを意味し、返されるトークンは空です。

**アクセプターが応答しないプリンシパル。** `krb5.Principal("nfs/files.example.org")` を指定すると、
複数のサービスを保持するキータブでも、そのサービスにだけ応答します。

**署名が一致しないメッセージ**は `ErrBadMIC` で、長さ、ヘッダー、シーケンス、チェックサムの
どれが一致しなくてもそうです。アクセプターは鍵用途 23 で署名し 25 で検証するので、このサーバーが
作ったトークンを、クライアントが署名したかのように送り返すことはできません。

**`Unwrap` に渡された封印済みトークン**は `ErrSealed` で、不正な署名とは区別されます。完全性
のみのトークンを読む呼び出し側に、メッセージのように読める暗号文を渡してはならないからです。
**`Unseal` に渡された封印されていないトークン**は `ErrNotSealed` です。機密性を約束したプロトコルに、
平文で回線を渡ったものを渡してはなりません。

アクセプターのサブ鍵は主張しません。コンテキスト鍵は、イニシエーターがオーセンティケーターに入れた
サブ鍵、または何も送らなかった場合はチケットのセッション鍵です (RFC 4121 §4.3)。

{{< callout type="warning" >}}
**キータブは保存時のシークレット**

そのパスは設定ファイルや `KRB5_KTNAME` から来ることがありますが、中の鍵をログに記録したり、
出力したり、環境変数で運んだりしてはなりません。
{{< /callout >}}

## 何に対して検証されているか {#what-it-is-checked-against}

**本物の MIT KDC と MIT 純正の `gss-client`** を、`gss-server` の代わりにこのパッケージに対して
行います。`test/kdc.sh` が、ループバック上に特権なしで使い捨てのレルムを構築します。CI は pkgx
経由で MIT Kerberos を入手します (Ubuntu のパッケージは `gss-client` を含みません)。Linux のテスト
レーン、レース検出器、カバレッジレーンは `KRB5_REQUIRE_JUDGE=1` を設定するので、フィクスチャが
ないと失敗します。さらにあるステップが `TestMITClientAgainstThisAcceptor` を実行し、ログに
*authenticated as alice@* がない限り失敗します。審判が黙って動かなくなったのに緑のレーンは受け入れ
られません。`TestMITClientSealed` は機密性を有効にして同じことを行います。

macOS、Windows、クロスアーキテクチャのレーンにはレルムがなく、そこでは審判はスキップされます。
カバレッジレーンの下限は 90% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/krb5@v0.3.3](https://pkg.go.dev/github.com/go-authn/krb5@v0.3.3)
