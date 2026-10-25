---
title: "krl — OpenSSH 鍵失効リスト"
linkTitle: "krl"
weight: 110
description: "go-authn/krl は OpenSSH の KRL を sshd が読むとおりに解析、構築、マージ、確認する。有効期限拡張付きで、ssh-keygen により検証される。"
tags: [ライブラリ, 失効, ssh]
---

**この SSH 証明書または鍵は、sshd が答えるとおりに失効しているか。** OpenSSH の `PROTOCOL.krl` の
バイナリ形式で、`sshd` が `RevokedKeys` を通じて読み込み、`ssh-keygen -k` が書き出すリストです。
`golang.org/x/crypto/ssh` にはこれに対するサポートがありません。

```sh
go get github.com/go-authn/krl@v0.6.1
```

`IsRevoked` は OpenSSH の `krl.c` にある `ssh_krl_check_key` に従います。証明書が失効しているのは、
署名した CA の下で、または任意の CA の下で、そのシリアルまたはキー ID が失効している場合、その CA
鍵が失効している場合、あるいはその証明書自身の鍵が blob または SHA-1 もしくは SHA-256 の
フィンガープリントで失効している場合です。シリアル 0 — CA が何も指名しないときに書くもの — は、
シリアルによって失効することは決してありません。

## 例 {#example}

```go
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"fmt"
	"time"

	"github.com/go-authn/krl"
	"golang.org/x/crypto/ssh"
)

func main() {
	ca := signer()
	user := signer()

	// The issuer: certificate 42 is revoked, and so is everything for key ID "alice".
	b := krl.NewBuilder(7, "revoked by the bridge")
	b.RevokeSerial(ca.PublicKey(), 42)
	b.RevokeKeyID(nil, "alice") // nil: under any CA
	b.SetExpires(time.Now().Add(time.Hour))
	data, err := b.Marshal(time.Now())
	if err != nil {
		panic(err)
	}

	// The server: parse the list, then ask about each certificate.
	k, err := krl.Parse(data)
	if err != nil {
		panic(err)
	}
	fmt.Println("version", k.Version, "signed", k.Signed, "expires set", !k.Expires.IsZero())
	for _, c := range []struct {
		serial uint64
		id     string
	}{{42, "bob"}, {43, "bob"}, {44, "alice"}} {
		fmt.Println(c.serial, c.id, k.IsRevoked(certificate(ca, user.PublicKey(), c.serial, c.id)))
	}
}

func signer() ssh.Signer {
	_, priv, _ := ed25519.GenerateKey(rand.Reader)
	s, _ := ssh.NewSignerFromKey(priv)
	return s
}

func certificate(ca ssh.Signer, key ssh.PublicKey, serial uint64, id string) *ssh.Certificate {
	c := &ssh.Certificate{
		Key: key, Serial: serial, KeyId: id, CertType: ssh.UserCert,
		ValidPrincipals: []string{id}, ValidBefore: ssh.CertTimeInfinity,
	}
	if err := c.SignCert(rand.Reader, ca); err != nil {
		panic(err)
	}
	return c
}
```

```
version 7 signed false expires set true
42 bob true
43 bob false
44 alice true
```

同じリストと証明書をファイルに書き出すと、OpenSSH 10.3p1 の `ssh-keygen -Q -f list.krl` から同じ
三つの答えが得られます。`REVOKED`、`ok`、`REVOKED` です。

## 有効期限: `expires@go-authn.github.io` {#expiry-expiresgo-authngithubio}

KRL には生成日時とバージョンがありますが、有効でなくなる時刻を述べるものがないため、古いコピーを
新しいものと区別できません。`Builder.SetExpires` はその時刻を、`ExtensionExpires` という名前の拡張
セクションに、**クリティカルではない**形で書き込むので、`sshd` と `ssh-keygen` はリストを読み込んで
それを無視します。`Parse` はそれを `KRL.Expires` に読み込みます。

{{< callout type="warning" >}}
**署名はない**

OpenSSH は KRL の署名セクションを書き込む手段を公開したことがなく、もう検証もしません。`Parse` は
それを読み飛ばして `Signed` を設定しますが、これは真正性については何も述べません。`Builder` は
決して署名を書き込みません。リストの完全性、したがってその有効期限の完全性は、トランスポート
(認証されたサーバーからの HTTPS)、または呼び出し側が確認する分離 SSHSIG 署名から得られますが、
後者はこのパッケージは行いません。
{{< /callout >}}

## マージ: sshd のための一つのファイル {#merging-one-file-for-sshd}

`sshd` は OpenSSH 10.3 まで単一の `RevokedKeys` ファイルしか読まなかったので、複数の CA を信頼する
サーバーは、それらのリストを一つにする必要があります。`Builder.Merge` は解析済みリストのすべての
失効を追加します。`Builder.MergeCA(k, ca, others...)` は `k` の `ca` 用セクション、`ca` に再スコープした
任意の CA 用セクション、明示的な鍵とフィンガープリントを保持し、他の CA 用のセクションと、`others`
の一つを指す鍵やフィンガープリントを、その数を数えたうえで除外します。`MergeOptions{DropKeys: true}`
を指定した `MergeCAWith` は、`ca` 自身のものを除くすべての明示的な鍵も除外します。すべての CA の
ユーザーを信頼しないリスト向けです。失効したユーザー鍵は、`sshd` が証明書自身の鍵を誰が署名した
かにかかわらず確認するため、マージされたファイルのどの CA の下でもそのユーザーを締め出します。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

`Parse` は `ssh-keygen` と `sshd` が拒否するものを拒否します。不正なマジックまたは形式バージョン、
切り詰められたデータまたは余分なデータ、未知のセクションまたは証明書サブセクション、クリティカルと
印された未知の拡張、OpenSSH が解析できない CA 鍵、シリアル 0、逆転したシリアル範囲、OpenSSH が読む
より大きなビットマップや 2^64−1 を超えて回り込むもの、です。不正な形式または繰り返された有効期限も
拒否します。不在として読むと、失効するはずのリストが決して失効しないものに変わってしまうからです。

`Builder` は、最初の無効なリクエストを返す `Marshal` の時点で拒否します。シリアル 0、下限が 0 または
上限より大きい範囲、NUL を含むキー ID またはコメント、CA 鍵が期待される場所に与えられた証明書、
生成日時より前の有効期限、です。

**意図的な違いが一つあります。** 近接した多数のまばらなシリアルに対して、`ssh-keygen -k` は自身の
リーダーが受け付けるより広いビットマップを書き、その後自分のファイルを拒否します (*bignum is too
large*)。`Parse` もそのファイルを、`sshd` と同様に拒否します。`Builder` はビットマップがそこまで広く
なる前に新しいセクションを始めるので、書いたものは常に読めます。

Parse は、OpenSSH と同じく、リストが失効させるものに比例して割り当てます。KRL は、巨大なものを
送らないと信頼できる出どころから来るべきです。

## 何に対して検証されているか {#what-it-is-checked-against}

**OpenSSH の `ssh-keygen`** を、Linux と macOS のレーンで。`KRL_REQUIRE_SSHKEYGEN=1` により、
ないと失敗になります (Windows は純粋な Go のテストのみ)。

- `ssh-keygen -k` が、あらゆるシリアルエンコーディング、キー ID、三つの CA と「任意の CA」、
  明示的な鍵、失効した CA 鍵を含めて書いた KRL: `IsRevoked` は 250 の証明書について
  `ssh-keygen -Q` と同じ答えを返し、同じ失効を与えた `Builder` は**同じバイト列**を書きます
- 両方で書いた 40 のランダムなシリアル集合: バイト単位で同一で、約 9000 の証明書について同じ答え
- あらゆる切り詰めと約 1400 の単一バイトの破損: `Parse` は `ssh-keygen` が拒否するものを正確に
  拒否します
- 有効期限拡張は `ssh-keygen` で読み込まれ、クリティカルと印した同じセクションは拒否されます
- マージされたリストは、その元のどれかが失効させるものを正確に失効させます

`ssh-keygen` が書いた KRL を種にした `FuzzParse` と `FuzzBuilder` が CI で動きます。カバレッジの下限は
100% で、`ssh-keygen` がある Linux レーンで測定されます。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/krl@v0.6.1](https://pkg.go.dev/github.com/go-authn/krl@v0.6.1)
