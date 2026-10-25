---
title: "keyfactor — 登録された鍵、タッチされた"
linkTitle: "keyfactor"
weight: 40
description: "go-authn/keyfactor はセキュリティキーを mfa の要素に変える: CTAP を話すあらゆるデバイスを信頼するのではなく、登録に照らして応答を検証する。"
tags: [ライブラリ, fido, mfa, 要素]
---

**登録された鍵が答えたか、そして人がそれにタッチしたか。**
`keyfactor` は、CTAP を話しポリシーについては何も知らない [fido]({{< relref "/libraries/fido.md" >}}) と、
どれだけの証明で十分かを判断しデバイスについては何も知らない [mfa]({{< relref "/libraries/mfa.md" >}})
の間にある唯一の部品です。どちらも相手をインポートしません。これが両方をインポートします。

```sh
go get github.com/go-authn/keyfactor@v0.4.2
```

v0.4.2 では、その `go.mod` が少なくとも `go-authn/fido` v0.6.2 と `go-authn/mfa` v0.5.0、つまりこれらの
ページが説明するバージョンを要求します。

プラットフォームが提供するのは `Opener`、つまりこのシステムで鍵をどう見つけるか、それだけです。
それ以外のすべては、CTAP があるところならどこでも同じです。アサーション、チェック、誰かの
最後の PIN 試行を使い切ることの拒否です。

## 例 {#example}

```go
package main

import (
	"context"
	"crypto/ecdsa"
	"errors"
	"fmt"

	"github.com/go-authn/fido"
	"github.com/go-authn/keyfactor"
	"github.com/go-authn/mfa"
)

func main() {
	// The platform supplies the Opener: how a key is found on this system.
	// This one finds nothing, and says so the way a policy understands.
	open := func(context.Context) (fido.Transport, error) {
		return nil, keyfactor.Unavailable(errors.New("no security key is plugged in"))
	}

	// From the registration: the credential ID and its public key, which
	// fido.AuthData.PublicKey returns from the attestation.
	var pub *ecdsa.PublicKey // nil here, to show the refusal

	f := keyfactor.New(open, keyfactor.Options{
		RPID:         "example.test",
		CredentialID: []byte{0x01, 0x02},
		PublicKey:    pub,
	})
	fmt.Println(f.Name(), f.Kind())

	_, err := mfa.Verify(context.Background(), mfa.Policy{Count: 1}, f)
	fmt.Println(err)
}
```

```
your security key possession
mfa: 1 factor(s) needed, 0 answered: your security key (possession): keyfactor: no public key for the credential; without one any device that answers would pass, so pass the one from the registration
```

拒否は `Opener` が呼ばれる前に行われます。登録の公開鍵があれば、同じ要素が鍵を開き、新しい
ランダムなチャレンジに対するアサーションを求め、応答を検証します。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**デバイスが答えることは、鍵が答えることではありません。** プログラム可能な USB ボードも
セキュリティキーと同じように CTAP を話すので、応答は登録に照らして検証されます。

| 拒否されるもの | メッセージ |
|---|---|
| 何かが開かれる前: `Opener` がない、`RPID` がない、`PublicKey` がない、または P-256 でない鍵 | `keyfactor: no opener; …`、`… needs a relying party id …`、`… no public key for the credential; …`、`… is not on P-256 …` |
| `RPID` の SHA-256 ではないリライングパーティーのハッシュ | `… answered for another relying party` |
| デバイスが名指しする場合の、`CredentialID` 以外の認証情報 | `… answered with a credential other than the one asked for` |
| 認証器データとチャレンジに対する、`PublicKey` が作っていない署名 | `… answered with a signature the credential's key did not make` |
| `UP` フラグがない | `… answered without anyone touching it` |
| `PIN` が与えられたのに `UV` フラグがない | `… was asked to establish who holds it and did not` |

**最後の PIN 試行は推測で使い切られません。** まず `PINRetries` が尋ねられます。抜き差しするまで
これ以上 PIN を受け付けない鍵は拒否され、残りが**一回以下**の鍵も拒否されます。CTAP では、連続
三回の間違った PIN が、鍵が抜かれるまで鍵の PIN をブロックし、再試行カウンターがゼロに達すると
永久にブロックされます。それを解除するのはリセットだけで、そのリセットは鍵上のすべての認証情報を
消去します。

鍵自身が PIN を拒否したとき、エラーは fido のものであり、fido v0.6.2 からは二つのうち正しいほうを
名指しします。抜き差しでブロックが解除される場合は
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)`、リセットでしか解除されない
場合は
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`
です。fido v0.6.2 より前は、二つの文が入れ替わっていました。

**PIN は第二要素ではありません。** 種類は `mfa.Possession` のままです。鍵に入力された PIN は鍵を
保護するもので、このマシンに対しては誰も識別しません。

**空のポートは拒否ではありません。** 何も見つけられない `Opener` は、そのエラーを
`keyfactor.Unavailable` でラップし、`mfa.ErrUnavailable` として印が付けられ、ポリシーは
*問い合わせできなかった*ことを*いいえと言われた*こととは別に数えます。

{{< callout type="warning" >}}
**保護できないもの: PIN のハッシュは、応答するどのデバイスにも届く**

CTAP では、プラットフォームが何かに署名される前に、デバイス自身と合意したシークレットで暗号化した
`LEFT(SHA-256(PIN), 16)` を鍵に渡します。偽造されたデバイスは要素としては拒否されますが、そのハッシュを
受け取っており、短い PIN はオフライン探索で破られます。それがプロトコルです。長い PIN を使い、
出どころの分からない鍵には PIN を入力しないでください。
{{< /callout >}}

## 何に対して検証されているか {#what-it-is-checked-against}

テストは、トランスポートではなく**認証器**を偽装し、go-authn/fido 自身のエクスポートされた
フレーミングから組み立てています。CTAPHID ハンドシェイク、CTAP2 アサーション、ClientPIN の交換です。
PIN の半分は、プロトコル 2 の認証器側を独立して演じます。独自の ECDH、HKDF、AES-CBC を仕様から
書いたもの (`fakepin_test.go`) なので、一バイトでも違う導出はやり取りを失敗させます。
`forged_test.go` は認証情報を持たないデバイスです。カバレッジは 100% に保たれ、テストは八つの
アーキテクチャで実行されます。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2](https://pkg.go.dev/github.com/go-authn/keyfactor@v0.4.2)
