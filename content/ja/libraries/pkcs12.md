---
title: "pkcs12 — アップロードされた .p12 の中の鍵と証明書"
linkTitle: "pkcs12"
weight: 116
description: "go-authn/pkcs12 は PKCS#12 (.p12 / .pfx、RFC 7292) ファイルを純 Go で読み取る。信頼できないアップロード向けに作られ、リソースの上限はすべて無効にできないオプションで、OpenSSL が判定役を務める。"
tags: [ライブラリ, 証明書, 鍵]
---

**誰かが送ってきたこのファイルには、どの秘密鍵とどの証明書が入っているか。**
PKCS#12（[RFC 7292](https://www.rfc-editor.org/rfc/rfc7292)）は、エクスポーターが
鍵、その証明書、チェーンの残りを書き込む `.p12` / `.pfx` コンテナです。
`golang.org/x/crypto/pkcs12` は非推奨で、SHA-1 と 3DES/RC2 のまま凍結されている
ため、OpenSSL 3 と 4 や最近の Windows がデフォルトで書くもの（PBES2、AES、
SHA-2 の MAC）を拒否します。このモジュールはそれらを、標準ライブラリ以外に依存
せずに読み取り、**信頼できないアップロード**向けに作られています。

```sh
go get github.com/go-authn/pkcs12@v0.1.0
```

**デコードのみ**を行います。エンコーダーはありません。チェーンを信頼するかどうかは
`crypto/x509` の `Verify` が扱う、別の判断です。

## 例 {#example}

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/pkcs12"
)

func main() {
	data, err := os.ReadFile("upload.p12")
	if err != nil {
		panic(err)
	}

	b, err := pkcs12.Decode(data, "the password", nil)
	switch {
	case errors.Is(err, pkcs12.ErrIncorrectPassword):
		fmt.Println("ask again:", err)
		return
	case err != nil: // hostile, unsupported, too costly...
		fmt.Println("refused:", err)
		return
	}

	// b.PrivateKey   *rsa.PrivateKey, *ecdsa.PrivateKey, ed25519.PrivateKey or *ecdh.PrivateKey
	// b.Certificate  the certificate holding the key's public half
	// b.CACerts      every other certificate, in file order
	fmt.Println("certificate for", b.Certificate.Subject, "and", len(b.CACerts), "more")
}
```

`Decode(data, password, *Options) (*Bundle, error)` は、デフォルト値を使うなら
`nil` を受け取ります。`Bundle` には、鍵、その公開側を持つ証明書、残りの証明書が
ファイル順に入ります。

## オプションとデフォルト値 {#options-and-their-defaults}

ゼロのフィールドはデフォルト値を意味し、**どのフィールドも上限を無効にできません**。

| フィールド | デフォルト | 意味 |
|---|---|---|
| `MaxInputSize` | 8 MiB | `len(data)` |
| `MaxIterations` | 1 000 000 | 1 回の鍵導出の反復回数 |
| `MaxWork` | 5 000 000 | ファイル全体での反復回数 x 出力ブロック数 |
| `MaxDepth` | 16 | BER のネストと、構成された文字列の断片のネスト |
| `MaxBags` | 1024 | ファイル内の SafeBag |
| `MaxAuthSafes` | 32 | AuthenticatedSafe の ContentInfo |
| `MaxCertSize` | 32 KiB | 証明書 1 つの DER |
| `MaxCertBytes` | 512 KiB | 全証明書を合わせた DER |
| `MaxRSABits` | 8192 | RSA のモジュラス |
| `AllowNoMAC` | `false` | 完全性 MAC のないファイル（`openssl pkcs12 -nomac`）を読む。そうでなければ `ErrNoMAC` |
| `NoPassword` | `false` | ファイルがパスワードなしでエクスポートされた。空のパスワード `""` とは別 |

2 つの真偽値は、この形式の 2 つの曖昧さです。`AllowNoMAC` を使うと、内容を認証
するものがなくなり、間違ったパスワードは復号の失敗でしか分かりません。**空**の
パスワード（`""`）と**存在しない**パスワード（`NoPassword`）は異なる鍵を導出し、
どちらも使えます。`""` かつ `NoPassword` が false なら、`Decode` はまず空を、次に
存在しないほうを試します。エクスポーターによってどちらを書くかが異なるためです。
`NoPassword` が true なら存在しないほうだけを試し、パスワード引数は `""` でなければ
なりません。

## 読み取れるもの {#what-it-reads}

| 層 | 対応 |
|---|---|
| 暗号化 | PBES2（[RFC 8018](https://www.rfc-editor.org/rfc/rfc8018)）、HMAC-SHA-1/224/256/384/512 上の PBKDF2 と AES-128/192/256-CBC |
| 旧式の暗号化 | `pbeWithSHAAnd3-KeyTripleDES-CBC`、`pbeWithSHAAnd2-KeyTripleDES-CBC`、`pbeWithSHAAnd40BitRC2-CBC` と 128 ビット版。RC2 はモジュール内で実装 |
| 完全性 | SHA-1/224/256/384/512 の HMAC MAC（RFC 7292 付録 B の KDF）と **PBMAC1**（[RFC 9579](https://www.rfc-editor.org/rfc/rfc9579)） |
| パスワード | 付録 B.1 に従う BMPString、BMP 外の文字はサロゲートペア |
| エンコーディング | BER。Windows と Java が書く不定長と構成された OCTET STRING を含む |
| バッグ | 暗号化された鍵バッグと平文の鍵バッグ、証明書バッグ。CRL、シークレット、セーフコンテンツのバッグは読み飛ばす |

**`ErrUnsupported` として拒否されるもの:** 公開鍵による完全性とプライバシーの
モード（`signedData`、`envelopedData`）、RC4、scrypt、PKCS#12 固有以外の PBES1、
PBMAC1 内の SHA-1、証明書または PKCS#8 鍵の中の BER（DER ではないもの）。

## エラー {#errors}

| エラー | 意味 |
|---|---|
| `ErrMalformed` | このパッケージが読める PKCS#12 ファイルではない |
| `ErrUnsupported` | 読めるが、ここで実装されていないものを使っている |
| `ErrLimit` | `Options` の上限を超える。処理の前に拒否される |
| `ErrIncorrectPassword` | 間違ったパスワードと改ざんされたファイル。設計上、同じ答え |
| `ErrNoMAC` | MAC がなく、`AllowNoMAC` が設定されていない |
| `ErrNoPrivateKey` | ファイルに秘密鍵がない |
| `ErrMultipleKeys` | ファイルに秘密鍵が複数ある |
| `ErrNoCertificate` | 秘密鍵に一致する証明書がない |
| `ErrPassword` | 使えないパスワード |

すべての拒否は、これらのうちちょうど 1 つをラップし、ファズ対象はそれを不変条件
として保っています。

## セキュリティ上の上限 {#the-security-bounds}

上記の上限はすべて**処理の前に**検査され、すべての長さフィールドは、何かを確保する
前に実際に存在するバイト数と照合されます。512 バイトを超えるソルトと、1024 文字を
超えるパスワードは拒否されます。

MAC は、**何かを復号する前に、一定時間で**検証されます。

`crypto/x509` は、数千の小さな名前でできた証明書では、そのサイズの 43 倍から 52 倍
まで確保し、`crypto/rsa` は鍵が宣言する数に対する算術で鍵を検証するため、モジュラス
よりはるかに長い因数は超線形の CPU を消費します。どちらも外部からは直せないので、
そこに届くものを先に制限します。証明書は `MaxCertSize` と `MaxCertBytes` で、
すべての PKCS#8 鍵（最大 32 KiB）は `encoding/asn1` で読まれ、モジュラスが
`MaxRSABits` を超える場合、因数や指数がモジュラスの許す長さを超える場合、数が正で
ない場合、またはマルチプライムの場合は、型付きで拒否されます（`ErrUnsupported`）。

**リクエストあたりのメモリ。** デフォルトのオプションでは、悪意あるファイルは
1 回の `Decode` に約 25 MB を確保させます（合わせて測定：最悪の証明書と、受け入れ
られる最大の鍵、8192 ビットで 25.1 MB、そのうち約 20 MB は戻るまで生きたまま）。
ファイルは 530 KB です。アップロードをデコードするサービスは、たとえばセマフォで
同時のデコード数を制限し、短いチェーンしか想定しないなら `MaxCertBytes` を下げる
べきです。

## 制限事項 {#limitations}

- **CRT 値のない RSA 鍵は拒否されます**（`ErrUnsupported`）。`Dp`、`Dq`、`Qinv`
  のない鍵は、`crypto/x509` に渡る前に拒否されます。RFC 8017 はそれらを要求し、
  どのエクスポーター（OpenSSL、Windows、Java の keytool）も書きますが、
  `crypto/x509` は欠けた値を多倍長演算で導出します。8192 ビットで 16.4 MB と
  21 744 回の確保、値がある場合は 0.36 MB と 618 回です。
- **[go-authn/pkcs12#2](https://github.com/go-authn/pkcs12/issues/2)、オープン、
  LOW。** `GODEBUG=x509rsacrt=0` の下では、`crypto/x509` は無効な CRT 値を捨てて
  再計算し、事前チェックはそれらが*存在する*ことしか確かめません。CRT 値が誤った
  8192 ビット鍵はこれを通り抜け、最悪の証明書と組み合わせるとデコードは 39.4 MB
  （比 74.7）に達し、テストが断言する上限の外に出ます。運用者が有効にする必要が
  あり、モジュールの `go.mod` はその設定がデフォルトではない Go バージョンを宣言
  しています。デフォルト設定では、同じ入力は `ErrMalformed` として拒否されます。
- デコードのみで、チェーンの判断はしません。

## 何と照合されているか {#what-it-is-checked-against}

**OpenSSL が判定役です。** OpenSSL 4.1 が書いた 23 個のファイル（AES/PBES2、
`-legacy` の 3DES と RC2、`-nomac`、複数の証明書、RSA、EC と Ed25519、PBMAC1）が
テストにあり、各ファイルの中身について OpenSSL 自身が述べることを記したマニフェスト
が付いています。

**増幅。** `TestAmplification` は、多数の小さなバッグ、多数の証明書、深い不定長の
ネスト、長い OCTET STRING の連鎖、4 GiB の長さの主張に対して、確保バイト数を入力
バイト数に対して制限し、拒否が `crypto/x509` の呼び出しの前に起きることを断言
します。モジュールはファズも行われ（コーパスはコミット済み）、ブロックカバレッジ
は 100 %、`-race` と `govulncheck` で実行されます。

**`software.sslmate.com/src/go-pkcs12`** は、別の `oracle/` モジュールにあります。
両方が試せる 23 ファイルのうち、両方が 18 を読み、リーフ、チェーンの順序、鍵は
バイト単位で同一です。残りの 5 を読めるのはこのパッケージだけです（RC2-128、
SHA-384 の MAC、MAC なし、BMP 外の文字を含む 2 つのパスワード）。向こうが読めて
こちらが拒否するものはありません。

[cms]({{< relref "/libraries/cms.md" >}}) と組み合わせられます。ここで `.p12` を
デコードし、あちらで署名します。
