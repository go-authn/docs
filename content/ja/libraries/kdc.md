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
これを土台にした単独のデーモンが [kdcd]({{< relref "/libraries/kdcd.md" >}}) です。

```sh
go get github.com/go-authn/kdc@v0.8.1
```

v0.7.0 から v0.8.1 まで: Windows クライアントの TGS-REQ を受け入れます (その RSA-MD5 のオーセンティケーター
チェックサムは MIT も受け入れます)。チケットはフラグと starttime を持ちます。`Server.Mint`、`Server.MintHandler`、
`Config.MintCallers` は、鍵を持たない人のための TGT を、相互認証された TLS 越しに許可リストにある呼び出し元へ
KRB-CRED として発行します (既定では無効)。TGS は、オーセンティケーターがチケットと別のクライアントを
名指ししたとき `KRB_AP_ERR_BADMATCH` で答えます。additional-tickets フィールドが不正なリクエストは、
gokrb5 がデコードする前に破棄されます。

v0.8.1 では、その `go.mod` が少なくとも `go-authn/directory` v0.17.0 と gokrb5 v8.4.4 を要求します。
これは最小バージョンなので、directory v0.17.0 を要求する
プログラムは、authnd v0.16.2 と同様に v0.18.0 でビルドされます。受け入れ側の半分は
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

## パスワード由来の認証を有効にする {#allow-password-derived-as}

v0.11.0 以降、ディレクトリが保持するパスワードから人の鍵を導出すること
（string-to-key、RFC 3962）は**既定で無効**です。有効にするには
`Config.AllowPasswordDerivedAS` を設定します。無効のとき、エントリにパスワードを
持つ人への AS-REQ には `KDC_ERR_POLICY`（*KDC のポリシーが要求を拒否*、
RFC 4120 §7.5.9）が返り、エラー文と `Logf` の行がこのオプションを名指しします。
keytab の鍵（`krbtgt`、サービス）と TGS は影響を受けません。

## PAC を求めるサービスのために {#pac}

v0.12.0 以降、`Config.PAC` に挙げたサービスのサービスチケットは Privilege
Attribute Certificate（[MS-PAC]: LOGON_INFO、CLIENT_INFO、UPN_DNS_INFO、
PAC_REQUESTOR と各署名）を運びます。**既定では無効**で、`Config.PAC` が nil
ならどのチケットにも付きません。

```go
PAC: &kdc.PAC{
	DomainSID: "S-1-5-21-1111111111-2222222222-3333333333", // NewDomainSID makes one
	Services:  []string{"nfs/files.example.org"},
},
```

RID はディレクトリの番号です。`uidNumber` がユーザーの RID、`gidNumber` が
グループの RID で、`gidNumber` のないグループは省かれます。`uidNumber` の
**ない**人、または同じ番号を持つ二つのアカウントは `KDC_ERR_POLICY` で拒否
されます。運ぶグループは最大 256 です。KDC のドメイン SID を持つ `member
server` の Samba 4.22（`winbindd` あり）はこれらのチケットを受け入れました。
`PAC.NetBIOSDomain` は Samba の `workgroup` と等しくなければなりません。

**大きな PAC と UDP。** v0.12.1 以降（RFC 4120 §7.2.1）、1465 バイトを超える
応答はデータグラムでは送られません。クライアントは
`KRB_ERR_RESPONSE_TOO_BIG` を受け取り、TCP で要求を繰り返します。1465 は
この KDC の選択であり、標準ではありません。

**本人がどうログインしたか。** v0.13.0 以降、`Config.PAC` を設定すると、すべての
PAC が `S-1-18-1`（*authentication authority asserted identity*）を持ち、
`MintHandler` で発行されたチケットはドメイン内で作られた SID も持ちます。TGT には
krbtgt 鍵で署名された CAMMAC（[RFC 8129]、MIT の形式）が入り、ログイン方法と要求者の
`uidNumber` を記録します。そのため発行要求は、本人がどうログインしたかを
`"method"`（`passkey`、`federated`、`machine`）で伝えなければならず、PAC 設定下で
これがないと応答は `400` です。TGS では、印が検証できない TGT は
`KRB_AP_ERR_MODIFIED` で、`uidNumber` がディレクトリのものと一致しなくなった TGT
（同名でアカウントを削除して作り直した場合、CVE-2021-42287）は
`KDC_ERR_TGT_REVOKED` で拒否されます。クライアントの enc-authorization-data は無視
されます。アップグレード前に発行された TGT には印がなく、パスワードログインとして
最長 10 時間受け付けられ、その後は拒否されます。**アップグレードの注意:** PAC を設定した
KDC を更新する前に、`go-authn/bridge` が `method` を送るようにしてください。サービス
チケットのインジケータはまだ実装されていません。

## 索引を渡す: `Finder` {#finder}

AS-REQ と TGS-REQ はどれも一人を検索します。通常の `directory.Source` では、それは
`Identities()` と走査です。10,000 人では走査が AS-REQ の CPU の半分を占め、
`Identities()` でデータベースや LDAP サーバーを読むソースは、認証なしのものを含む
すべてのリクエストで丸ごと読まれます。**v0.6.0 から**、索引を持つソースは

```go
Find(name string) (*directory.Identity, bool, error)
```

を実装でき、レルムは走査の代わりにそれに問い合わせます。アイデンティティの名前は
プリンシパルと**完全に**一致しなければなりません (プリンシパルは大文字と小文字を区別するので、
名前が異なる応答は未知のプリンシパルです)。エラーは `KDC_ERR_SVC_UNAVAILABLE` になります。
`Finder` があれば検索は CPU プロファイルのしきい値を下回り、リクエストに残るのは主に
gokrb5 の ASN.1 エンコードです。
[authnd]({{< relref "/authnd/kerberos.md#where-the-realm-reads-people" >}}) は
この方法でレルムにリフレッシュされたスナップショットを渡します。

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
		AllowPasswordDerivedAS: true, // off by default since v0.11.0
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
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
$ kinit --password-file=STDIN alice@EXAMPLE.ORG < bad.pw
kinit: Password incorrect
$ kinit --password-file=STDIN bob@EXAMPLE.ORG < alice.pw
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
$ kgetcred nfs/files.example.org@EXAMPLE.ORG
$ klist
Credentials cache: FILE:cc
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG
Oct 26 12:34:16 2026  Oct 26 22:34:16 2026  nfs/files.example.org@EXAMPLE.ORG
```

十時間は `Config.Lifetime` の既定値で、サービスチケットは、それを得たチケット発行チケットとともに
終わります。KDC は、拒否した各リクエストの理由を、自身のログに書きました。

```
kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/OTHER.ORG" realm: OTHER.ORG kvno: 0 etype: 18
EXAMPLE.ORG answers on 127.0.0.1:18088
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
2026/10/26 12:34:16 the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
2026/10/26 12:34:16 refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
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
  `KRB_AP_ERR_MODIFIED`)。v0.7.0 から、Windows クライアントが送る RSA-MD5 (type 7) チェックサム
  (鍵なしだがセッション鍵で封じられている) は MIT と同様に受け入れられる。CRC32、MD4、SHA-1 は拒否のまま
- TGT が終了時刻を過ぎておらず (`KRB_AP_ERR_TKT_EXPIRED`)、開始時刻より前でなく、無効のフラグも
  立っておらず (`KRB_AP_ERR_TKT_NYV`)、時計のずれは許されない: その時刻はこの KDC の時計が
  書いたものだから
- クライアントがこのレルムのもので、まだディレクトリにいる (`KDC_ERR_C_PRINCIPAL_UNKNOWN`)
- オーセンティケーターが名指しするクライアントが、チケットのものと同じ (名前とレルム。`KRB_AP_ERR_BADMATCH`、v0.8.0 から)

**v0.5.0 から**、バイト単位でまったく同じリクエストが再び届いたとき (UDP
で応答を失ったクライアント、または再送する攻撃者) は、再処理せずに以前の応答を
返します。MIT の KDC の lookaside (`src/kdc/replay.c`) の移植です。エントリは
2 分間保持され、合計 10 MiB 未満に抑えられ、古いものから捨てられます。
`KRB-ERROR` は保存されないため、`KDC_ERR_SVC_UNAVAILABLE` を返されたクライアン
トは、ディレクトリが戻れば改めて処理されます。オーセンティケータのリプレイキャッ
シュは意図的にありません: MIT の KDC は TGS でこれを無効にしています。再送が
`KRB_AP_ERR_REPEAT` で失敗してしまうからであり、また再送者は自分が持たない鍵で
封じられた応答を開けないからです。読めないディレクトリは、正しいパスワードでも
AS と TGS で `KDC_ERR_SVC_UNAVAILABLE` になり、`KDC_ERR_PREAUTH_FAILED` には決し
てならない (ロックアウトに数えられない) うえ、検証器 (`ldap` 上流) が Kerberos
から呼ばれることはありません (`KDC_ERR_NULL_KEY`)。コスト: リクエストあたり 2
アロケーション (`BenchmarkTGSReq` 1,784 から 1,786)。マシンに負荷がかかっていた
ため、時間は比較していません。

**v0.4.5 から**、セキュリティ監査とファジング・カオスの実施を経て:

- 別のレルム向けのリクエストは、AS でも TGS でも、処理されずに `KDC_ERR_WRONG_REALM` で答えられます。
- 読み取れないディレクトリは `KDC_ERR_SVC_UNAVAILABLE` で答えられ、`KDC_ERR_C_PRINCIPAL_UNKNOWN` ではなくなりました。
- 開始が `MaxSkew` 以内の未来にある TGT は受け入れられます (時計のステップ)。以前は TGT の開始に許容のずれはありませんでした。
- **不正な AS-REQ または TGS-REQ 一つでプロセスがクラッシュし得ました**。gokrb5 v8.4.4 の
  `unmarshalTicketsSequence` が、認証の前にパニックします。デコーダーをパニックさせるリクエストは破棄され、
  パニックとそのスタックがログに記録されます。
  v0.8.1 から、その既知の形、つまり `[11] SEQUENCE` でない additional-tickets フィールドは、gokrb5 が
  デコードする前に破棄されます。デコーダーのそれ以外のパニックは、依然としてリクエスト一つを失います。
- ネットワークから来たプリンシパル名は、行を偽造できないようにログで引用符で囲まれます。
- 依存関係は golang.org/x/net v0.62.0 (GO-2026-6866、GO-2026-6860) と go-authn/directory v0.16.1 です。
  GO-2026-5932 (`golang.org/x/crypto/openpgp`) は上流に修正がなく、呼び出されていません。

`FuzzHandle` は二回の実行 (90 秒と 150 秒) で約 1,400 万回実行され、パニックが外へ出ることはありませんでした。
`BenchmarkASNoPreauth`、10,000 人のうち最後の一人を事前認証なしで: 1 リクエストあたり 508 回のアロケーション、
18,999 バイト、112 µs です。この経路のコードは変わっていないため、以前の数字はありません。時間は目安にすぎません。
負荷が 65 だったので、MIT の `krb5kdc` との比較は行っていません。

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

[pkg.go.dev/github.com/go-authn/kdc@v0.8.1](https://pkg.go.dev/github.com/go-authn/kdc@v0.8.1)
