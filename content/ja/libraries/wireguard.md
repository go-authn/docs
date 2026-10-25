---
title: "wireguard — この鍵は誰のもので、接続してよいか"
linkTitle: "wireguard"
weight: 130
description: "go-authn/wireguard は WireGuard 公開鍵を厳格に定義し、ゲートウェイがピアに変える、プロバイダーが署名した登録済み鍵のリストを運ぶ。"
tags: [ライブラリ, wireguard, トークン]
---

**この WireGuard 鍵は接続してよいか。誰のものか。** WireGuard はピアをその静的な公開鍵だけで認証します。
証明書も、有効期限も、失効もありません。そのためこの問いはプロトコルの外で答えられ、答えが変わる
たびに答え直されます。プロバイダー — [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) — が答え
ます。このモジュールは、プロバイダーとゲートウェイが合意する内容です。

```sh
go get github.com/go-authn/wireguard@v0.1.1
```

唯一の依存関係は [oidc]({{< relref "/libraries/oidc.md" >}}) v0.4.0 で、リストを検証します。

二つのことを行います。`ParseKey` は公開鍵とは何かを述べ、`Source.Fetch` は人々が登録した鍵の、
プロバイダーが署名した `List` を取得します。それぞれが `Peer` で、`Key`、`Subject`、`Username`、
`Device`、そしてリースの終了時刻を持ちます。

{{< callout type="info" >}}
**ここを通るのは公開鍵だけ**

秘密鍵はデバイス上で生成され、デバイスを決して離れません。このパッケージには、それを置く場所が
ありません。
{{< /callout >}}

## 例 {#example}

```go
package main

import (
	"crypto/ecdh"
	"encoding/base64"
	"fmt"
	"strings"

	"github.com/go-authn/wireguard"
)

func main() {
	// A public key as wg(8) prints it. Here it is derived from a fixed
	// private key; on a device, `wg genkey | wg pubkey` makes one, and the
	// private half never leaves it.
	priv, _ := ecdh.X25519().NewPrivateKey([]byte(strings.Repeat("\x2a", 32)))
	text := base64.StdEncoding.EncodeToString(priv.PublicKey().Bytes())

	k, err := wireguard.ParseKey(text)
	fmt.Println(k, err)

	// The all-zero key authenticates nobody.
	_, err = wireguard.ParseKey(base64.StdEncoding.EncodeToString(make([]byte, 32)))
	fmt.Println(err)

	// Unpadded is another spelling of the same bytes, and is refused.
	_, err = wireguard.ParseKey(strings.TrimRight(text, "="))
	fmt.Println(err)
}
```

```
B6r/Pp/BZydVRPTDpqF82Dfy7G54zYpXsePfs8wDWnY= <nil>
wireguard: the key is a point of low order, which authenticates nobody
wireguard: the key is not base64: illegal base64 data at input byte 40
```

ゲートウェイは一つの `Source` を保持し、リストを取得します。

```go
package main

import (
	"context"
	"log"
	"os"
	"time"

	"github.com/go-authn/wireguard"
)

func main() {
	ctx := context.Background()
	src, err := wireguard.NewSource(ctx, wireguard.SourceConfig{
		Issuer:       "https://bridge.example.org",
		ClientID:     "gateway-1",
		ClientSecret: readSecret("/etc/gateway/client-secret"),
	})
	if err != nil {
		log.Fatal(err)
	}
	for {
		l, err := src.Fetch(ctx) // signed, typ wireguard-peers+jwt, for this gateway, not older
		if err != nil {
			log.Print(err)
		} else {
			for _, p := range l.Peers {
				log.Printf("peer %s is %s (%s) until %s", p.Key, p.Subject, p.Username, p.Expires)
			}
		}
		time.Sleep(time.Minute)
	}
}

// readSecret reads the client secret from a file: never from the command
// line or the environment.
func readSecret(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		log.Fatal(err)
	}
	return string(b)
}
```

`NewSource` は起動時にプロバイダーの設定を読みます。`Fetch` はゲートウェイ自身のトークン
(`client_credentials`、スコープ `wireguard_peers`) を取得し、発行者の下の `/wireguard/peers` から
リストを取得し、go-authn/oidc で検証します。プロバイダーの鍵セットに対する署名、発行者、
オーディエンス (このゲートウェイの `ClientID`)、有効期限、そして `typ` `wireguard-peers+jwt`
(`ListType`) です。そのためアクセストークンも ID トークンもリストとして通らず、リストもトークン
として通りません。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**鍵** (`ParseKey`):

- 同じバイト列の他のあらゆる綴り。デコードは厳格で、テキストは受け取ったとおりに出力し直せなければ
  ならないので、テキストをキーとするストアが一つの鍵を二つの名前で保持することはありません
- 低位数の点、その中にはすべてゼロの鍵が含まれます。そのような鍵との交換はどれも、相手側の鍵に
  かかわらず同じ共有シークレットを与える (RFC 7748 §6.1) ので、誰も認証しません。`crypto/ecdh` は
  交換を計算して判断するので、最上位ビットの変種も拒否されます

**リスト** (`Fetch`):

| | 理由 |
|---|---|
| この `Source` がすでに取得したものより低い `version` のリスト | 古いリストも署名されており、その後に取り下げられた鍵が載っているかもしれない |
| 二度載っている鍵 | ゲートウェイがどちらを保持しても、もう一人のトラフィックが間違った名前で届く |
| サブジェクトのないピア | 誰のものでもない |
| 鍵ではない鍵 | 上記を参照 |
| 平文の発行者またはトークンエンドポイント。ループバックを除く | ゲートウェイのシークレットとリストが、誰でも読めるリンクを通ることになる |
| `ClientID` と `ClientSecret` のない `SourceConfig` | ゲートウェイは自分自身のクライアントとしてリストを読む |

リストは `exp` を運びます。それまでに新しいものを取得できないゲートウェイは、古いリストではなく、
リストを持たなくなります。`Peer.Subject` は、鍵を登録したクライアントから見たその人の `sub`、
パブリックまたはペアワイズで、ゲートウェイがその人のアクセストークンにも見つける値です。

## 何に対して検証されているか {#what-it-is-checked-against}

**`wg(8)` 自体**、wireguard-tools のものが、`ParseKey` が受け入れなければならない鍵を作ります。
それは Linux のテストレーン、レース検出器、カバレッジレーンにインストールされ、
`WIREGUARD_REQUIRE_JUDGE=1` を設定するので、`wg` がないとスキップではなく失敗します。低位数の
テストは libsodium が列挙する七つの点を、最上位ビットありとなしの両方で確認します。カバレッジの
下限は 100% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/wireguard@v0.1.1](https://pkg.go.dev/github.com/go-authn/wireguard@v0.1.1)
