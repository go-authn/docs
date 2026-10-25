---
title: "servercert — デーモンの TLS 証明書の出どころ"
linkTitle: "servercert"
weight: 120
description: "go-authn/servercert は、変更されると再読み込みされるファイル、または autocert を通じた ACME CA から TLS サーバー証明書を提供する。External Account Binding を含む。"
tags: [ライブラリ, tls, acme, 証明書]
---

**デーモンの TLS サーバー証明書はどこから来るか。** ディスク上の証明書と鍵で、変更されると再読み込み
されるもの、または [`autocert`](https://pkg.go.dev/golang.org/x/crypto/acme/autocert) を通じた ACME CA で、
External Account Binding を含みます。

```sh
go get github.com/go-authn/servercert@v0.5.2
```

`Config` はちょうど一つのソースを指名します。`CertFile` と `KeyFile`、または `ACME` です。`New` は
`*Source` を返し、その `TLSConfig()` がそれを提供します。`MinVersion` は TLS 1.2 です。

## 例 {#example}

ファイルから:

```go
package main

import (
	"log"
	"net/http"

	"github.com/go-authn/servercert"
)

func main() {
	src, err := servercert.New(servercert.Config{
		CertFile: "/etc/fileshare/tls/fullchain.pem",
		KeyFile:  "/etc/fileshare/tls/privkey.pem",
		OnError:  func(err error) { log.Print(err) }, // a renewal that did not load
	})
	if err != nil {
		log.Fatal(err) // unreadable, unparsable, or a key that is not the certificate's
	}
	srv := &http.Server{Addr: ":443", TLSConfig: src.TLSConfig()}
	log.Fatal(srv.ListenAndServeTLS("", ""))
}
```

`Config.Check` は動作しない設定を拒否し、何にも触れません。ファイルを読まず、ディレクトリも作りません。

```go
package main

import (
	"fmt"

	"github.com/go-authn/servercert"
)

func main() {
	// Check touches nothing: no file is read, no directory created.
	for _, c := range []servercert.Config{
		{ACME: &servercert.ACME{Domains: []string{"*.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"192.0.2.10"}, CacheDir: "/var/lib/fileshare/acme"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "acme"}},
		{CertFile: "/etc/fileshare/tls/fullchain.pem"},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme",
			DirectoryURL: "http://acme.example.org/directory"}},
		{ACME: &servercert.ACME{Domains: []string{"files.example.org"}, CacheDir: "/var/lib/fileshare/acme"}},
	} {
		fmt.Println(c.Check())
	}
}
```

```
servercert: ACME domain "*.example.org" is a wildcard; that needs dns-01, which autocert does not do
servercert: ACME domain "192.0.2.10" is an IP address; autocert issues only for DNS names
servercert: ACME.CacheDir "acme" is not an absolute path
servercert: CertFile and KeyFile go together; one of them is empty
servercert: ACME.DirectoryURL "http://acme.example.org/directory" is not an https URL (RFC 8555 §6.1)
<nil>
```

最後のものは Let's Encrypt の本番環境です。`DirectoryURL` が空だからです。

## ファイル {#files}

`New` はペアを読み、読めない、解析できない、または鍵が証明書のものでない場合に**その場で**失敗します。
その後は、最大で 10 秒に一度、ハンドシェイク中にファイルが再度読まれ、変更されたペアはロックを
保持せずに解析されて入れ替えられます。読み込みに**失敗する**変更されたペア — 鍵より先に書かれた
証明書、切り詰められたファイル — は `OnError` に一度報告され、最後の正常なペアが提供され続けるので、
二つのファイルを続けて書く更新ジョブがサーバーを落とすことはありません。

## ACME {#acme}

autocert は二種類のチャレンジに答え、他には答えません。`tls-alpn-01` (RFC 8737、ポート 443、ALPN
`acme-tls/1`) と、`HTTPChallenge` がある場合の `http-01` (RFC 8555 §8.3、ポート 80、
`Source.HTTPHandler` が提供) です。`dns-01` はないので、ワイルドカードも IP アドレスの証明書もありません。

証明書は、SNI が `Domains` のいずれかを指す最初のハンドシェイクで、または `Source.Prefetch` により
どのクライアントよりも前に取得され、期限切れの前に autocert により更新されます。IP アドレスで接続する
クライアントは SNI を送らないため、最初のドメインの証明書が提供されます。

{{< callout type="warning" >}}
**`NextProtos` は置き換えず、追加すること**

ACME では、`TLSConfig().NextProtos` が `acme-tls/1` を保持しており、これがないと CA の tls-alpn-01
検証が失敗します。そして追加しなければなりません。ALPN プロトコルを通知する Go の TLS サーバーは、
共通のものがない提示をするクライアントを拒否するので、NFS over TLS サーバーは `sunrpc` を追加します
(RFC 9289)。`net/http` は `http/1.1` と `h2` を自分で追加します。
{{< /callout >}}

**チャレンジの不要な CA。** autocert は、新しい注文がすでに `ready` の場合には直ちに返ります。これは
ドメインが事前検証された CA が返すもので、Enterprise Admin アカウントでの、HARICA が提供する GÉANT
TCS がそうです。インターネットからポート 80 にも 443 にも到達できない内部サーバーでも、公的に信頼
される証明書を得られます。EAB の HMAC 鍵はシークレットなので、設定は鍵そのものではなく、それを
保持する**ファイル** (`EABHMACKeyFile`) を指名します。

`x/crypto/acme` の欠陥の一つは回避されています
([golang/go#77704](https://github.com/golang/go/issues/77704))。CA がまだ処理中の注文を確定した後、
クライアントは確定応答の `Location` ヘッダーの URL をポーリングしますが、RFC 8555 はそこにそれを
置いていません。servercert は ACME クライアントに、そのヘッダーを、先の newOrder 応答にある注文の
URL で加えるトランスポートを与えます。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

`Check` が拒否するもの: ソースがない、または両方ある。ファイルペアの片方だけ。ドメインまたは
キャッシュディレクトリのない ACME。相対パス。EAB の片方だけ。IP アドレス、ワイルドカード、単一
ラベル、ドットで終わる、または有効なホスト名でないドメイン。https でないディレクトリ URL
(RFC 8555 §6.1)。

`New` はさらに、キャッシュディレクトリ — 秘密鍵を保持する — が、シンボリックリンクである、グループや
他者がアクセスできる、プロセスの実効ユーザー以外が所有している、または書き込めない場合に拒否
します。存在しなければ `0700` で作成され、その後で確認されます。その上のすべてのディレクトリは、
sshd の `StrictModes` が `authorized_keys` へのパスに求めるのと同じく、root か実効ユーザーだけが
変更できなければならず、その上のシンボリックリンクは、root が所有していない限り拒否されます。
Windows ではモードと所有者は確認されません。両方を決めるのは ACL で、それを制限するのはあなたの
仕事です。そしてパスのどこにあってもシンボリックリンクは拒否されます。

## 何に対して検証されているか {#what-it-is-checked-against}

**pebble**、Let's Encrypt のテスト CA を、その `ca`、`db`、`va`、`wfe` パッケージからプロセス内で、
DNS スタブとともに実行し、`crypto/tls` が pebble のルートに対して検証する本物の証明書を発行します。
tls-alpn-01、`HTTPHandler` を通じた http-01 と、`HTTPChallenge` をオフにした対照、EAB が必要、ない、
間違い、そして正しい場合、チャレンジ用ポートを開けずに発行された事前検証済みのドメインとその対照。
あるテストは golang/go#77704 の回避策なしで同じ発行を実行し、失敗を要求します。カバレッジの下限は
100% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/servercert@v0.5.2](https://pkg.go.dev/github.com/go-authn/servercert@v0.5.2)
