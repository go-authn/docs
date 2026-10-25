---
title: "kdc — ディレクトリから Kerberos チケットを発行する"
linkTitle: "kdc"
weight: 80
description: "go-authn/kdc は Kerberos の発行側: UDP と TCP の AS と TGS、事前認証必須、暗号化タイプは一つ、人々は go-authn のディレクトリから。"
tags: [ライブラリ, kerberos, ディレクトリ]
---

**レルムはディレクトリからどうチケットを発行するか。** AS-REQ と TGS-REQ を UDP と TCP で、暗号化
タイムスタンプによる事前認証を必須として、[ディレクトリ]({{< relref "/libraries/directory.md" >}})が
知る人々と、キータブが保持するサービスのために処理します。
[authnd]({{< relref "/authnd/_index.md" >}}) の下で動作します。

```sh
go get github.com/go-authn/kdc@v0.4.3
```

v0.4.3 では、その `go.mod` が少なくとも `go-authn/directory` v0.12.0 と gokrb5 v8.4.4 を要求します。
これは最小バージョンなので、これらのページが説明するバージョンである directory v0.14.0 を要求する
プログラムは、authnd v0.12.0 と同様に v0.15.0 でビルドされます。受け入れ側の半分は
[krb5]({{< relref "/libraries/krb5.md" >}}) で、チケットを検証するだけのサービスは、このモジュールを
まったく必要としません。

未実装のもの: クロスレルムのリファーラル、PKINIT、FAST、更新可能または後日付のチケット、
kadmin プロトコル。鍵はディレクトリとキータブから来て、それらがある場所で変わります。

## パスワードを保持するソースだけがレルムを支えられる {#only-a-source-holding-the-password-can-back-a-realm}

KDC は、クライアントの事前認証を、その人の長期鍵で**復号**しなければならないので、
`directory.Verifier` — 他人の LDAP へのバインド、ハッシュの比較 — は、*これは正しいパスワードか*に
どれだけうまく答えても、役に立ちません。ソースにパスワードがない人には、間違ったパスワードが得る
コードではなく `KDC_ERR_NULL_KEY` (*null key*) が返るので、入力し直すべきパスワードではなく、直す
べき設定として読めます。

## 例 {#example}

メモリ上のレルムを、ループバックで:

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

`EXAMPLE.ORG` に `kdc = tcp/127.0.0.1:18088` を指定した `krb5.conf` を用い、
`KRB5_CONFIG=krb5.conf` と `KRB5CCNAME=FILE:cc` を設定して、macOS が同梱する Heimdal の `kinit`
(1.5.1) でチケット発行チケットを得ます。

```
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < alice.pw
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:54:46 2026  Oct 11 07:54:46 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 10 21:54:46 2026  Oct 11 07:54:46 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 10 21:54:47 2026  Oct 11 07:54:46 2026  nfs/files.example.org@EXAMPLE.ORG
```

十時間は `Config.Lifetime` の既定値で、サービスチケットは、それを得たチケット発行チケットとともに
終わります。KDC は、拒否した各リクエストの理由を、自身のログに書きました。

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/10 21:54:46 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/10 21:54:46 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/10 21:54:47 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

各やり取りの最初の拒否は、プロトコルが動いている証拠です。事前認証を要求する `KRB-ERROR` は
etype とソルトを示す `ETYPE-INFO2` のヒントを運び、クライアントはタイムスタンプを付けて再度
試みます。

{{< callout type="info" >}}
**v0.4.2 より前は、`till` が 19700101000000Z だと、すでに期限切れのチケットが発行された**

RFC 4120 §5.4.1: 19700101000000Z の `till` は、KDC のポリシーが許す最大の終了時刻を求めます。
Heimdal の `kgetcred` はまさにそれを送ります。v0.4.1 は Go のゼロ時刻だけを検査していたので、
Unix エポックを本物の終了時刻と受け取り、`klist` で `>>>Expired<<<` と表示されるサービス
チケットを発行しました。CI の審判である MIT の `kvno` は本物の `till` を送るので、このケースに
出会いませんでした。v0.4.2 は上記のとおり許される最長のチケットを発行し、すでに過ぎた `till` には、
到着時に期限切れのチケットではなく `KDC_ERR_NEVER_VALID` を返します
([go-authn/kdc#19](https://github.com/go-authn/kdc/pull/19))。
{{< /callout >}}

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**設定時** (`New`): レルムがない (`ErrNoRealm`)、ディレクトリがない (`ErrNoPeople`)、キータブがない
(`ErrNoServices`)、または `krbtgt/REALM@REALM` のないキータブ (`ErrNoTGTKey`)。起動して最初の
`kinit` で失敗し、そのエラーが直せない人に届くのではなく、設定時に拒否します。

**AS では:** 事前認証のないリクエストにはそれを要求する応答が返り、人の鍵は確認すべきタイムスタンプ
が届くまで導出されないので、実在のプリンシパルを名指しする偽装 UDP パケットは鍵導出のコストを
負わせません。間違ったパスワード、別の etype のタイムスタンプ、一時間前のタイムスタンプは、
すべて間違ったパスワードが得るコードである `KDC_ERR_PREAUTH_FAILED` で答えられます。エラー
テキストが理由を名指しし、`Logf` も同様です。自分自身の TGT を求めるサービスは拒否されます。
サービスはキータブから認証します。

**暗号化タイプは一つ。** チケットと鍵は `aes256-cts-hmac-sha1-96` (etype 18) のみです。etype の
リストに 18 がないリクエストには、誰かを検索する前に `KDC_ERR_ETYPE_NOSUPP` が返ります。`Logf` が
設定されていれば、ログは両方の etype を記録するので、運用者は暗号の不一致とパスワードの
入力ミスを区別できます。

**TGS では** (RFC 4120 §3.3.2)、チケットは次の場合にのみ発行されます。

- 提示されたチケットがこのレルムの TGT で、チケットが主張するサービスの鍵ではなく、KDC が
  名指しする `krbtgt/REALM` の鍵で復号されている (`KRB_AP_ERR_NOT_US`)
- オーセンティケーターがそのセッション鍵で、`MaxSkew` 以内に復号される
- そのチェックサムが、届いたとおりのこのリクエストの本体に対するもので、セッション鍵で
  鍵付けされている (欠けているか鍵付けされていなければ `KRB_AP_ERR_INAPP_CKSUM`、間違っていれば
  `KRB_AP_ERR_MODIFIED`)
- TGT が終了時刻を過ぎておらず (`KRB_AP_ERR_TKT_EXPIRED`)、開始時刻より前でなく、無効のフラグも
  立っておらず (`KRB_AP_ERR_TKT_NYV`)、時計のずれは許されない: その時刻はこの KDC の時計が
  書いたものだから
- クライアントがこのレルムのもので、まだディレクトリにいる (`KDC_ERR_C_PRINCIPAL_UNKNOWN`)

**有効期間。** `Config.Lifetime` がチケットの上限で、ゼロのときは十時間です。それより短いものを
求めたクライアントはそれを得ます。TGT で得たチケットはその TGT より後に終わらないので、`krbtgt` を
再度求めても認証情報を延長できません。

**認証されていない相手が保持できるもの:** TCP メッセージは、その長さも含めて 30 秒以内に届かなければ
なりません。同時に提供される TCP 接続は最大 256、同時に応答されるデータグラムは最大 64 で、
それを超えるものは破棄され、クライアントは再送するか TCP にフォールバックします。

## 何に対して検証されているか {#what-it-is-checked-against}

**MIT 純正の `kinit` と `kvno`** を pkgx 経由で、Go で構築したレルムに対して。MIT の KDC は関与
せず、クライアントだけを借りています。`TestMITClientGetsATGTAndAServiceTicket` は TGT とサービス
チケットを取得し、`kvno` が報告する鍵バージョンを確認します。Linux のテストレーン、レース検出器、
カバレッジレーンは `KDC_REQUIRE_JUDGE=1` を設定し、さらにログに *were served by this realm* と
ない限り失敗するステップがあります。テストは、本物のクライアントが引き起こさない拒否も固定
します。間違った鍵のタイムスタンプ、一時間前のタイムスタンプ、三バイトの暗号、AS-REQ から直接
求められるサービス、TGS での偽造サービスチケット、検証器に支えられたレルムです。カバレッジ
レーンの下限は 80% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/kdc@v0.4.3](https://pkg.go.dev/github.com/go-authn/kdc@v0.4.3)
