---
title: "fido — セキュリティキーと話す"
linkTitle: "fido"
weight: 30
description: "go-authn/fido は、任意の 64 バイトトランスポート上でセキュリティキーに CTAPHID と CTAP2 で話しかける: ハンドシェイク、登録、アサーション、PIN を、純粋な Go で。"
tags: [ライブラリ, fido, 要素]
---

**セキュリティキーとどう話すか。** FIDO クライアント・認証器間プロトコル — CTAPHID のフレーミング、
チャネルのハンドシェイク、認証情報を登録し、署名を求め、PIN をトークンと交換する CTAP2 コマンド —
を、あらゆるオペレーティングシステム上の純粋な Go で。

```sh
go get github.com/go-authn/fido@v0.6.2
```

ここにプラットフォーム固有のものはありません。`Transport` は一つの認証器との間で 64 バイトの
レポートを運び、デバイスの名前を述べます。そのレポートがどこから来るか、つまり macOS の IOKit、
Linux の hidraw、ブラウザーの WebHID は、他の誰かのパッケージの仕事です。その上にあるすべては
ここにあります。

| | |
|---|---|
| `Open(ctx, t)` | ブロードキャストチャネルでの `INIT` ハンドシェイク。専用のチャネルを持つ `*Key` を返す。`Key` が `t` を所有する: `Close` がそれを閉じ、失敗した `Open` も閉じる |
| `Key.Ping`、`Key.Wink` | 往復と点滅 — *これらの鍵のうちどれがこれか*を尋ねる最も安価な方法 |
| `Key.GetInfo` | バージョン、拡張、AAGUID、オプション、PIN プロトコル |
| `Key.MakeCredential`、`Key.GetAssertion` | 登録と署名。`ParseAuthData` が認証器データを読み、`AuthData.PublicKey` が P-256 の COSE 鍵を `*ecdsa.PublicKey` に変える |
| `Key.PINRetries`、`Key.KeyAgreement`、`Key.PINToken` | `authenticatorClientPIN`、両方の PIN/UV 認証プロトコル |
| `Split`、`NewReassembler`、`ParseInit`、`Key.CBOR` | フレーミング。別の方法で鍵を駆動する人のためにエクスポートされている |

`AuthData.PublicKey` は変換であり検証ではありません。どのアルゴリズムを認めるか、そして逆戻りした
署名カウンターをどうするかは、呼び出し側の仕事です。[keyfactor]({{< relref "/libraries/keyfactor.md" >}})
はそのような呼び出し側の一つです。

## 例 {#example}

鍵なしでフレーミングだけ: メッセージをレポートに切り分け、元に戻します。

```go
package main

import (
	"bytes"
	"fmt"

	"github.com/go-authn/fido"
)

func main() {
	// A 200-byte ping, cut into the 64-byte reports a key reads...
	payload := bytes.Repeat([]byte{0xA5}, 200)
	reports, err := fido.Split(0x01020304, fido.CmdPing, payload)
	if err != nil {
		panic(err)
	}
	fmt.Println(len(reports), "reports of", len(reports[0]), "bytes")

	// ...and put back together, as a reply would be.
	r := fido.NewReassembler(0x01020304)
	for _, rep := range reports {
		msg, done, err := r.Feed(rep)
		if err != nil {
			panic(err)
		}
		if done {
			fmt.Println(bytes.Equal(msg.Data, payload), msg.Cmd == fido.CmdPing)
		}
	}

	// A report for another channel is an error, not something to drop.
	other, _ := fido.Split(0x0A0B0C0D, fido.CmdPing, []byte("hi"))
	_, _, err = fido.NewReassembler(0x01020304).Feed(other[0])
	fmt.Println(err)

	// The framing's real limit, not the length field's.
	fmt.Println(fido.MaxMessage)
}
```

```
4 reports of 64 bytes
true true
fido: the report belongs to another channel
7609
```

鍵がある場合は、`fido.Open(ctx, transport)` がハンドシェイクを行い、返される `*Key` がその後の
すべてのコマンドを運びます。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**鍵は、尋ねられたことに答えると信頼されません。** 送ったものとは別のコマンドを運ぶ応答は拒否
されます (CTAP 2.1 §11.2.9 は各応答に固有のコマンドを与えており、libfido2 も確認しています)。
送ったものではない nonce を持つ `INIT` 応答は拒否されます。同じ鍵上の別のプログラムの
ハンドシェイクだからです。そのプロトコルの長さではない PIN トークンも、プロトコル 1 では 16 または
32 バイト、プロトコル 2 ではちょうど 32 バイトでなければ、拒否されます。

**キープアライブは応答ではありません。** 指を待つ鍵は、約百ミリ秒ごとに `CTAPHID_KEEPALIVE` を
送ります。それは読み飛ばされ、タッチにかかってよい時間の唯一の上限はコンテキストです。

**フレーミングが運べるより長いメッセージ。** 二つの長さバイトは 65535 を許しますが、初期化
パケットの 57 バイトと、59 バイトの継続パケット 128 個では 7609 (`MaxMessage`) になります。それを
超えるとシーケンス番号が `0x80` に達し、鍵はそれを新しいメッセージとして読みます。`Split` は
`ErrTooLong` を返します。

**つじつまの合わないレポート**: 別のチャネルのもの (`ErrWrongChannel` — 一つの鍵に二つの
プログラム)、順序の乱れた継続パケット (`ErrOutOfOrder`)、パケットより短いレポート
(`ErrShortPacket`)、17 バイトより短い `INIT` 応答 (`ErrTruncated`)。

**鍵が対応すると述べていないコマンド。** `Wink` は `CapWink` のない鍵には送られず、`GetInfo` は
`CapCBOR` のない鍵には送られません。鍵が `CTAPHID_ERROR` で答え、呼び出し側がその拒否と故障を
区別しなければならなくなるからです。

**空の PIN**と、`AuthData.PublicKey` での P-256 以外のものは、半端にデコードせず名前を挙げて拒否
されます。

{{< callout type="warning" >}}
**間違った PIN は再試行回数を消費する**

CTAP は認証器に PIN の再試行カウンターを与えており、最大八回で、間違った PIN のたびに一つ
消費されます。連続して三回間違った PIN を入力すると、鍵を抜いて挿し直すまで PIN がブロック
されます。カウンターがゼロに達すると、永久にブロックされます。それを解除するのはリセットだけで、
リセットは鍵上のすべての認証情報を消去します。誰かに入力を促す前に `Key.PINRetries` に問い合わせて
ください。残りの再試行回数と、鍵が抜き差しを待っているかどうかが分かります。

鍵が PIN を拒否したとき、エラーはどちらかを述べます。抜き差しで解除される
CTAP2_ERR_PIN_AUTH_BLOCKED (`0x34`) は
`too many wrong PINs in a row; unplug the key and plug it in again (0x34)` と表示されます。
リセットでしか解除されない CTAP2_ERR_PIN_BLOCKED (`0x32`) は
`the PIN is blocked: no tries are left, and only a reset, which erases the credentials, unblocks it (0x32)`
と表示されます。v0.6.2 より前は、二つの文が入れ替わっていました。抜き差しするだけでよい鍵が
ロックされていると呼ばれ、そう告げられた人は、リセットして鍵上のすべての認証情報を失うかも
しれませんでした。
{{< /callout >}}

## 何に対して検証されているか {#what-it-is-checked-against}

CI にはセキュリティキーがないので、テストは、送られたものを再構成するフェイクのトランスポートを
使います。拒否する鍵、止まる鍵、ビジーと言い続ける鍵、チャネルを別のプログラムと共有する鍵を
模し、カバレッジは 100% に保たれています。二つのフィクスチャはこのコードの外から来ています。

- `testdata/yubikey-fido-5.7.4-getinfo.hex`。**YubiKey FIDO 5.7.4 から取得した** `GetInfo` 応答で、
  `ctap2_test.go` がデコードします。
- `testdata/webauthn-reference-authdata.b64`。**go-webauthn/webauthn** のテストからのサンプルで、
  認証器データのパーサーと `AuthData.PublicKey` を確認します。

ステータスコードの表は libfido2 の `err.h` に従っています。モジュールの README には、本物の
YubiKey に対して行った登録とアサーションの実行が記録されており、署名は鍵が渡した公開鍵で検証
されています。その実行は CI の一部ではありません。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/fido@v0.6.2](https://pkg.go.dev/github.com/go-authn/fido@v0.6.2)
