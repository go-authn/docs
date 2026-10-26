---
title: "ldap — LDAP サーバーのバイト列"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap はサーバーライブラリとしての LDAP プロトコル: ワイヤー、フィルター、操作とその上限。何に答えるかはハンドラーが決める。"
tags: [ライブラリ, ldap, ディレクトリ]
---

**LDAP サーバーのバイト列とは何か。** デーモンではなくライブラリです。ワイヤー、フィルター、操作。
[authnd]({{< relref "/authnd/_index.md" >}}) はこれを動かし、設定、ディレクトリのソース、バインドの
ポリシーを所有するサーバーで、これはバイト列を所有します。

```sh
go get github.com/go-authn/ldap@v0.11.0
```

RFC 4511 (プロトコル)、4512 (ルート DSE とスキーマ)、4513 (認証)、4514 と 4515 (DN とフィルターの
文字列形式)、4517 と 4518 (構文、マッチングルール、文字列の準備)、4526、2696 (ページング結果)、
3672 (サブエントリ)、3673、4527 (エントリ読み取りコントロール)、4532 (whoami)、3045 から書かれて
います。

`Server` はハンドラーの集合で、それぞれ任意のフィールドです。`Bind`、`SASL`、`Search`、`Compare`、
`Extended`、`Add`、`Modify`、`Delete`、`ModifyDN`、`Abandon`。nil は*このサーバーはそれを行わない*
ことを意味し、その操作には `unwillingToPerform` が返ります。存在しない権限についての議論を始めて
しまう `insufficientAccessRights` ではありません。ルート DSE はサーバー自身が応答し、サーバーが
尊重するものだけを正確に公開します。

## 例 {#example}

バインドできる人が一人いて、フィルターに一致するものを書き出す検索を持つサーバー:

```go
package main

import (
	"context"
	"crypto/subtle"
	"log"
	"log/slog"
	"os"

	"github.com/go-authn/ldap"
)

var people = []*ldap.Entry{
	{DN: "uid=dora,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "dora")}},
	{DN: "uid=svc-web-prod,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-prod")}},
	{DN: "uid=svc-web-stage,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "posixAccount"), ldap.StringAttribute("uid", "svc-web-stage")}},
}

// binder checks one password. A real one asks a directory: see go-authn/directory.
type binder struct{}

func (binder) Bind(_ context.Context, _ ldap.Session, req *ldap.BindRequest) (ldap.Result, error) {
	if req.Name == "" && len(req.Simple) == 0 {
		return ldap.Result{Code: ldap.Success}, nil // anonymous: the connection stays unbound
	}
	// A name with an empty password is an UNAUTHENTICATED bind (RFC 4513
	// 5.1.2). This package hands it to the handler, and the handler refuses it:
	// the comparison below does, since the password is never empty.
	ok := ldap.EqualDN(req.Name, "uid=dora,ou=people,dc=example,dc=org") &&
		subtle.ConstantTimeCompare(req.Simple, []byte("hunter2")) == 1
	if !ok {
		return ldap.Refuse(ldap.InvalidCredentials, "invalid credentials"), nil
	}
	return ldap.Result{Code: ldap.Success}, nil
}

// searcher writes each entry in scope that the filter matches, as it finds it.
type searcher struct{}

func (searcher) Search(_ context.Context, s ldap.Session, req *ldap.SearchRequest, w ldap.EntryWriter) (ldap.Result, error) {
	if s.BoundDN() == "" {
		return ldap.Refuse(ldap.InsufficientAccessRights, "bind first"), nil
	}
	for _, e := range people {
		if ldap.InScope(e.DN, req.BaseObject, req.Scope) && req.Filter.Matches(e) {
			if err := w.Entry(e); err != nil {
				return ldap.Result{}, err // the client went away, or a limit was reached
			}
		}
	}
	return ldap.Result{Code: ldap.Success}, nil
}

func main() {
	srv := &ldap.Server{
		Bind:           binder{},
		Search:         searcher{},
		NamingContexts: []string{"dc=example,dc=org"},
		Log:            slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// On anything but loopback: TLSConfig, and RequireTLS so that a
		// client that never asks for StartTLS is refused rather than
		// sending its password in the clear.
	}
	log.Fatal(srv.ListenAndServe("127.0.0.1:3389"))
}
```

OpenLDAP の `ldapsearch` (macOS が同梱する 2.4.28) で、dora のパスワードをファイルに入れて問い合わせ
ます。

```
$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw \
    -b ou=people,dc=example,dc=org '(uid=svc-*-prod)' uid
dn: uid=svc-web-prod,ou=people,dc=example,dc=org
uid: svc-web-prod

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -b ou=people,dc=example,dc=org '(uid=*)' uid
Insufficient access (50)
Additional information: bind first

$ ldapsearch -LLL -x -H ldap://127.0.0.1:3389 -s base -b '' namingContexts supportedLDAPVersion supportedExtension
dn:
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3

$ printf 'dn: uid=dora,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: uid\nuid: x\n' |
    ldapmodify -x -H ldap://127.0.0.1:3389 -D uid=dora,ou=people,dc=example,dc=org -y dora.pw
ldap_modify: Server is unwilling to perform (53)
	additional info: this server does not modify entries
modifying entry "uid=dora,ou=people,dc=example,dc=org"
```

`(uid=svc-*-prod)` は `svc-web-prod` を返し、`svc-web-stage` は返しません。このライブラリが置き換えた
ライブラリは、そのフィルターを `(uid=svc-*)` として評価し、`svc-web-stage` も返しました。その欠陥が、
このライブラリが書かれた理由です。`TLSConfig` が与えられていないので、ルート DSE は StartTLS を列挙
しません。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

**フィルターは一つのことを意味します。** 一度ツリーに解析またはデコードされ、`String`、
`EncodeFilter`、`Matches` はすべてそのツリーを読みます。RFC 4512 §2.5 の属性記述でない属性や、OID
でないマッチングルールは、`ParseFilter` と `DecodeFilter` の両方で拒否されます。v0.6.1 より前は、
属性 `!x` に対する「存在」フィルターは、出力し直すと NOT として読まれていました。

**別の約束をしたのに平文であること。** StartTLS を求めるのは*クライアント*なので、提供するだけの
サーバーは何も約束していません。`RequireTLS` は、保護されていない接続でのすべての操作を
`confidentialityRequired` で拒否します。

**失敗したバインドは何も残しません。** RFC 4511 §4.2.1: バインドリクエストを*受信した*時点で接続は
匿名になり、バインドが成功しない限りそのままです。そのため間違ったパスワードでの再バインドは、
前の人の権限を保持しません。`Bind` ハンドラーのない単純バインドには `authMethodNotSupported` が
返り、LDAPv2 はプロトコルエラーとして拒否されます。

{{< callout type="warning" >}}
**空のパスワードの意味はハンドラーが決める**

未認証バインド — 名前があり、パスワードが空のもの、RFC 4513 §5.1.2 — は、他の単純バインドと同様に
`Bind` ハンドラーに渡され、それに `Success` を返すハンドラーは、その名前として接続をバインドします。
例のように、ハンドラーで拒否してください。[directory]({{< relref "/libraries/directory.md" >}}) の
`ldapdir` は、クライアント側でそれを拒否します。
{{< /callout >}}

**尊重しないクリティカルコントロール。** ManageDsaIT (RFC 3296)、パスワード変更 (RFC 3062)、
キャンセル (RFC 3909) は、クライアントが送る可能性があるために定数として名付けられているだけで、
応答されるわけではありません。ここではエイリアスもリファーラルも辿らないので、クリティカルな
ManageDsaIT は `unavailableCriticalExtension` で拒否されます。

**認証されていない相手が保持できるもの:**

| | 既定値 | |
|---|---|---|
| `MaxMessageSize` | 4 MiB | 四ギガバイトを主張する五バイトのヘッダーは、何かが確保される前に拒否される |
| `MaxMessageElements` | 16384 | デコード前に数えられる BER 要素。v0.5.0 より前は、4 MiB の空文字列がバインド前に 373 MiB を保持した |
| `IdleTimeout` | 5 分 | 最初のバイトではなく、メッセージ全体が時間内に届かなければならない。負の値は無期限 |
| `MaxPending`、`MaxPendingAuth` | 100、1000 | 一つの接続がバインド前 (`MaxPending`) とバインド後 (`MaxPendingAuth`) に処理中として持てる操作。slapd の `conn_max_pending` と `conn_max_pending_auth` と同じ。超えた接続には切断通知が送られて閉じられる |
| `MaxPagedSearches` | 4 | 接続ごとに開けるページング検索。それぞれが次のエントリで待機する goroutine |

フィルターの入れ子にも上限があります。Go のスタックオーバーフローはプロセスを終了させるからです。
アサーションの*値*はどこにもログに記録されません。フィルターは誰かが入力したものを運ぶので、記録される
のはフィルターの形だけです。

**ページング検索は尋ねられたことに答えます。** v0.8.0 まで、ページのリーダーは各エントリをハンドラーが
書いたとおりに送っていました。`cn` だけのページング検索が、操作属性を含むすべての属性付きで返り、
`typesOnly` は無視されました。ページングなしの同じ検索は選択を守っていました。`ldapsearch -E pr=N` が
クライアントのページングの方法なので、同じ質問に二つの答えがあったのです。v0.8.0 からは両方が選択を
適用し、それは `ldapsearch` 自身が CI で確認します。

スキーマがない場合 — `Server.Schema` が nil、既定 — すべての比較は値について大文字小文字を区別
しません。完全一致の比較なら見つかったエントリを隠すことがないので、読み取りにとって安全なほうです。

## スキーマ {#the-schema}

v0.8.0 から、パッケージ `schema` は RFC 4512 §4 のディレクトリスキーマであり、`Server.Schema` により
サーバーがそれを使います。nil ならサーバーは以前とまったく同じです。

- `schema.Standard()` は、RFC 4512、4517、4519、4524、4523、2798、2307、3672、3045 の定義に加え、
  openssh-lpk の `ldapPublicKey` と `sshPublicKey`、およびそれらが必要とする二つの OpenLDAP 定義を
  組み込んでいます。いずれも RFC のテキストからコピーしたもので、`schema/defs` の各ファイルが出典と
  節を名指ししています。`schema.Build(append(schema.StandardFiles(), mine)...)` は、デプロイ固有の
  ものを追加し、SUP、ルール、構文、MUST、MAY が解決できないものは拒否します。
- `(*ldap.Entry).Validate(s)` は、すべてのスーパークラスを列挙した一つの構造チェーン、すべての
  MUST、MUST と MAY の外のものがないこと、SINGLE-VALUE、既知の型、その構文の値、エントリ内の
  RDN の値を確認し、**すべての**問題を `*schema.ValidationError` として挙げます。
- スキーマがあると、ルート DSE は `subschemaSubentry: cn=Subschema` を運び、`cn=Subschema`
  (`ldap.SubschemaDN`) のベース検索は、ルート DSE と同様にライブラリが応答します (RFC 4512 §4.2)。
  定義は、名前で、または `+` で求めた場合にのみ返ります。`RequireTLS` のゲートの背後にあります。
- フィルターは、スキーマのマッチングルール (RFC 4517 §4.2、RFC 4518 の文字列準備を伴う) で、
  RFC 4511 の三値論理により評価されます。未知の属性、求められた一致のルールがない型、無効なアサーション
  値は **Undefined** であり、エラーにはなりません。サーバーは、ハンドラーが送るすべてのエントリを
  再確認し、フィルターが TRUE にしないものを破棄します。ハンドラーは、同じスキーマを使う
  `req.Matches(e)` でフィルターします。

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap"
	"github.com/go-authn/ldap/schema"
)

func main() {
	s := schema.Standard() // RFC 4512, 4517, 4519, 4524, 2798, 2307, ... and openssh-lpk

	// An account with posixAccount, and no homeDirectory.
	eli := &ldap.Entry{DN: "uid=eli,ou=people,dc=example,dc=org", Attributes: []*ldap.Attribute{
		ldap.StringAttribute("objectClass", "top", "account", "posixAccount"),
		ldap.StringAttribute("uid", "eli"),
		ldap.StringAttribute("cn", "eli"),
		ldap.StringAttribute("uidNumber", "1001"),
		ldap.StringAttribute("gidNumber", "1001"),
		ldap.StringAttribute("mail", "eli@example.org"),
	}}
	var v *schema.ValidationError
	if errors.As(eli.Validate(s), &v) {
		for _, p := range v.Problems {
			fmt.Println("-", p)
		}
	}

	// uidNumber orders as an integer: 1001 >= 999, which as strings it is not.
	for _, f := range []string{"(uidNumber>=999)", "(uid>=a)"} {
		filter, _ := ldap.ParseFilter(f)
		fmt.Println(f, ldap.Evaluate(filter, eli, s))
	}
}
```

```
- mail is not allowed by any of the entry's object classes
- homeDirectory is required by posixAccount and is missing
(uidNumber>=999) TRUE
(uid>=a) Undefined
```

`mail` は `account` ではなく `inetOrgPerson` に属します。`uid` には ORDERING ルールがないので、それに
対する範囲指定は Undefined です。

{{< callout type="info" >}}
**RFC 2307 からの逸脱が一つ: `uidNumber` と `gidNumber` は整数として順序付けされる**

RFC 2307 は `uidNumber` と `gidNumber` に EQUALITY ルールを与えるだけで ORDERING ルールを与えて
いないので、それらへのすべての範囲フィルターが Undefined になってしまいます。SSSD が `ldap_min_id`
と `ldap_max_id` から作るものも含めてです。slapd は両方の型を `ORDERING integerOrderingMatch` 付きで
自ら定義しており (`servers/slapd/schema_prep.c`。その `nis.schema` では "builtin" としてコメント
アウトされている)、draft-howard-rfc2307bis-02 §2.1 も同様なので、組み込みの定義はそれらに従って
います。これと、DIT コンテンツルールなしで補助クラスを許可すること (RFC 4512 §2.4.3 は厳密には
それを禁じていますが、実用されているどのサーバーも許可しています) は、発見されるのではなく、
ここに述べられています。
{{< /callout >}}

DIT コンテンツルール、ネームフォーム、DIT 構造ルールは [v0.11.0 から入っています](#rules)。
意図的にないもの: LDAP 経由でのスキーマ
変更。RFC 4523 の証明書マッチングルールと `directoryStringFirstComponentMatch`。これらは定義は
されていますが実装されておらず、それらを使うアサーションは Undefined になります。集合属性。
`lang-` と `binary` 以外のオプション。

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}}) はこのスキーマを提供し、公開する
すべてのエントリをこれに適合させています。

## 大きなスキーマファイルを読む {#reading-large-files}

v0.10.0 までは、`schema.Read` は読んだファイルの継続行の数に対して二乗の時間がかかった。短い継続行から成る 4 MiB のファイルに約 3 分かかり、1 MiB で 139.6 GB を割り当てた。authnd が起動時に `schema_files` でするように、管理していないスキーマファイルを読むプログラムは、そのようなファイルで止められる可能性があった。v0.10.1 からは時間が線形であり (`TestManyContinuationLinesJoinInLinearTime`)、`Read` は最初の行を調べるためにファイル全体をコピーして分割することもしない。

`schema.Format` は 2000 バイトを超える行を書いていたが、slapd と `Read` はそれを拒否する。今は折り返す。厳格なパーサーは約 2.6 倍速く、`cosine.schema` での割り当ては 498 回から 147 回になった。libldap (macOS SDK、`LDAP_SCHEMA_ALLOW_ALL` 付きの `ldap_str2attributetype` と `ldap_str2objectclass`) との比較は、OpenLDAP の `cosine.schema` の 54 個の定義で、2026-10-26 に Apple M4 Max、負荷 6.5〜7.6 で計測した (`-cpu 1 -count 10`、benchstat)。go-authn/ldap は 25.65 µs ± 32 %、libldap は 35.62 µs ± 2 % で、libldap の約 0.72 倍の時間である。Go 側は 1 回あたり 147 回の割り当て (20.6 KiB)。`-benchmem` は libldap の C の割り当てを見られないため、その数値はない。再現するには、go-authn/ldap の `bench/libldap` で `go test -bench . -benchmem -cpu 1 -count 10` を実行する (cgo と libldap が必要)。authnd にはこれらの修正が v0.12.3 から入っている。

v0.10.2 から、`schema.Standard()` の RFC 2307 の 13 個の DESC の値は 1 行です。v0.10.1 までは RFC のページのように折り返されており、継続行は最初の 1 文字の後のインデントを保つため(`Read` が従う slapd の `fp_getline`)、それを公開するサーバーは `DESC 'An integer uniquely identifying a user in an         administrative domain'` を送っていました。authnd では v0.12.4 から修正されています。

## ビルドできないスキーマ {#build-error}

v0.10.0 から、`schema.Build` または `schema.BuildFrom` が拒否する定義は `*schema.BuildError` で、
`errors.As` で取り出せます。プログラムは拒否を、メッセージを照合するのではなく、そのフィールドから
報告します。Build は最初に拒否した定義で止まるので、報告される定義は一つです。

- `Kind` は、Build が行うすべてのチェックのいずれかです: `UnknownReference`、
  `DuplicateOID`、`DuplicateName`、`SuperiorCycle`、`KindViolation`、
  `UsageMismatch`、`CollectiveMismatch`、`UsageViolation`。
- `Element` (構文、マッチングルール、属性型、オブジェクトクラス)、`OID`、`Name` (最初の NAME) は、
  拒否された定義のもので、`Pos` はその始まる位置です: `file:line:column`。`.schema` のキーワードの行、
  または LDIF の `attributeTypes:` の行で、その行が折り返されていても base64 でも同じです。
  HCL ではブロック自身の位置です。コードで組み立てた定義には位置がありません。
- `Field` は誤りのある項 (`SUP`、`EQUALITY`、`SYNTAX`、`MUST`、`NAME` ...)、`Ref` はエラーが指すものです:
  未定義の名前または OID、あるいはもう一方の定義で、その `RefOID` と `RefPos` が付きます。
  重複の場合は最初の定義で、その場所はメッセージに示されます。

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/ldap/schema"
)

// An object class whose superclass is defined nowhere.
const site = `# site.schema
objectclass ( 1.3.6.1.4.1.99999.1.1 NAME 'siteMember'
	SUP top AUXILIARY )
objectclass ( 1.3.6.1.4.1.99999.1.2 NAME 'siteGuest'
	SUP nobody AUXILIARY )
`

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "site.schema", Data: []byte(site)})
	_, err := schema.Build(files...)

	var be *schema.BuildError
	if !errors.As(err, &be) {
		fmt.Println("not a BuildError:", err)
		return
	}
	fmt.Println("error:  ", be)
	fmt.Println("Kind:   ", be.Kind)
	fmt.Println("Element:", be.Element)
	fmt.Println("OID:    ", be.OID)
	fmt.Println("Name:   ", be.Name)
	fmt.Println("Field:  ", be.Field)
	fmt.Println("Ref:    ", be.Ref)
	fmt.Println("Pos:    ", be.Pos)
	fmt.Println("RefPos: ", be.RefPos.IsValid())
	fmt.Println("is UnknownReference:", be.Kind == schema.UnknownReference)
}
```

```
error:   site.schema:4:1: schema: the object class siteGuest has the superclass nobody, which is not defined
Kind:    unknown reference
Element: object class
OID:     1.3.6.1.4.1.99999.1.2
Name:    siteGuest
Field:   SUP
Ref:     nobody
Pos:     site.schema:4:1
RefPos:  false
is UnknownReference: true
```

空のモジュールから `github.com/go-authn/ldap` v0.10.1 で実行した例です。最初のクラスは問題なく、
二つ目が 4 行目から始まり、ほかに誤りはないので、`RefPos` は空です。`schema.Read` が返す
すべての定義も `Pos` を持ち、Position の `String` は、列が分からないときは列を省きます。

## DIT コンテンツルール、ネームフォーム、DIT 構造ルール {#rules}

v0.11.0 から、RFC 4512 §4.1.6 (DIT コンテンツルール) と §4.1.7 (ネームフォーム、DIT 構造ルール) が
定める三種類の定義は、それまでこのパッケージが拒否していましたが、読み込み、構築、適用、公開が
行われます。

- **型。** `schema.DITContentRule`、`schema.NameForm`、`schema.DITStructureRule`。厳格な RFC 4512
  パーサー `ParseDITContentRule`、`ParseNameForm`、`ParseDITStructureRule` (`FuzzDefinition` で
  ファジング) とプリンターが付きます。`schema.MaxRuleID` は、ルール ID をどのプラットフォームでも
  2^31-1 に制限します。`Definitions.DITContentRules`、`NameForms`、`DITStructureRules` は `Read` が
  返すものを保持します。
- **読み書き。** `schema.Read` は、`.schema` ファイル (`ditcontentrule` は slapd.conf(5) の
  ディレクティブ、`nameform` と `ditstructurerule` はこのパッケージのもので、slapd にはありません) と
  LDIF (`olcDitContentRules`、`dITContentRules`、`nameForms`、`dITStructureRules`) からそれらを読み、
  項は libldap が読むのと同じく任意の順序です。`Format` はそれらを書き戻します。v0.11.0 より前は、
  これらの属性は拒否されていました。
- **構築。** `Build` はそれらを結び付けます。すべてのクラス、型、ネームフォーム、上位ルールが
  定義されていなければならず、コンテンツルールは構造クラスのためのもので、その `AUX` は補助クラスで
  なければならず、ネームフォームは構造クラスを指名し、ルールの ID と名前は一意でなければなりません。
  `BuildErrorKind` が二つ、`DuplicateMember` と `PrecludedRequired`、`Element` が三つ、
  `ElementDITContentRule`、`ElementNameForm`、`ElementDITStructureRule` が新しく加わりました。
  `Schema` には `DITContentRules`、`NameForms`、`DITStructureRules`、`DITContentRule(name)`、
  `DITContentRuleOf(class)`、`NameForm(name)`、`DITStructureRule(id)` があります。
- **適用。** `Validate` は、エントリの構造クラスの有効なコンテンツルール (`AUX`、`MUST`、`MAY`、
  `NOT`) とその有効なネームフォームを適用し、新しい `ProblemKind` として `AuxiliaryNotAllowed`、
  `Precluded`、`NameFormViolation`、`NoStructureRule` を返します。エントリが木のどこに置けるかには
  その上位エントリが必要なので、それは `Schema.GoverningStructureRule(entry, superior)` です。
  上位のルールの下にあるエントリを支配する構造ルールを返し、上位が nil なら部分木の根にあるものを
  返します。有効な構造ルールがなければ、nil を返しエラーにはしません。ルールのないスキーマでは、
  `Validate` の結果はこれまでと同じです。
- **公開。** `cn=Subschema` は、スキーマにあるときに `dITContentRules`、`nameForms`、
  `dITStructureRules` を公開します。
- **そのほか。** 構文 1.3.6.1.4.1.1466.115.121.1.16、.17、.35 が検査されます。`hclschema` には
  ブロック `dit_content_rule`、`name_form`、`dit_structure_rule` があり、`ldapschema` はそれらを
  変換して検査します ([後述](#hcl2-and-the-converter))。`bench/libldap` は、三つのパーサーを
  libldap のものと比較します。

例示用アーク 1.3.6.1.4.1.99999 の下での実例です。`inetOrgPerson` のコンテンツルール (`posixAccount`
と `uidObject` は追加してよく、電話番号は必須で、description は排除されます)、サフィックス、`ou=`
コンテナー、人々のネームフォーム、それらを配置する構造ルールです。

```go
package main

import (
	"errors"
	"fmt"
	"os"

	"github.com/go-authn/ldap/schema"
)

const rules = `# rules.schema
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule'
	AUX ( posixAccount $ uidObject )
	MUST telephoneNumber
	NOT description )

nameform ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameform ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameform ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )

ditstructurerule ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
ditstructurerule ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
ditstructurerule ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
`

func attr(name string, values ...string) schema.Attribute {
	a := schema.Attribute{Description: name}
	for _, v := range values {
		a.Values = append(a.Values, []byte(v))
	}
	return a
}

func report(title string, err error) {
	fmt.Println(title)
	var v *schema.ValidationError
	if errors.As(err, &v) {
		for _, p := range v.Problems {
			fmt.Println("  -", p)
		}
		return
	}
	fmt.Println("  ", err)
}

func main() {
	files := append(schema.StandardFiles(), schema.File{Name: "rules.schema", Data: []byte(rules)})
	s, err := schema.Build(files...)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	// erin: an inetOrgPerson with a public key, a description, and no telephone number.
	erin := schema.Entry{DN: "uid=erin,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson", "ldapPublicKey"),
		attr("uid", "erin"), attr("cn", "erin"), attr("sn", "Evans"),
		attr("description", "on call"),
		attr("sshPublicKey", "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl erin@example.org"),
	}}
	report("erin:", s.Validate(erin))

	// fay: named by cn, which the name form of inetOrgPerson does not allow.
	fay := schema.Entry{DN: "cn=fay,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson"),
		attr("uid", "fay"), attr("cn", "fay"), attr("sn", "Fox"),
		attr("telephoneNumber", "+33 1 23 45 67 89"),
	}}
	report("fay:", s.Validate(fay))

	// The rule that governs each entry is the superior of the next.
	suffix := schema.Entry{DN: "dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "domain"), attr("dc", "example"),
	}}
	people := schema.Entry{DN: "ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "organizationalUnit"), attr("ou", "people"),
	}}
	root, err := s.GoverningStructureRule(suffix, nil)
	fmt.Println("suffix:", root.Names[0], err)
	ou, err := s.GoverningStructureRule(people, root)
	fmt.Println("ou=people:", ou.Names[0], err)
	gina := schema.Entry{DN: "uid=gina,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "person", "organizationalPerson", "inetOrgPerson"),
		attr("uid", "gina"), attr("cn", "gina"), attr("sn", "Gray"),
		attr("telephoneNumber", "+33 1 23 45 67 89"),
	}}
	r, err := s.GoverningStructureRule(gina, ou)
	fmt.Println("uid=gina:", r.Names[0], err)
	_, err = s.GoverningStructureRule(gina, root)
	report("uid=gina directly under the suffix:", err)

	// hal: an account with posixAccount, and no content rule for account.
	hal := schema.Entry{DN: "uid=hal,ou=people,dc=example,dc=org", Attributes: []schema.Attribute{
		attr("objectClass", "top", "account", "posixAccount"),
		attr("uid", "hal"), attr("cn", "hal"), attr("uidNumber", "1001"), attr("gidNumber", "100"),
		attr("homeDirectory", "/home/hal"),
	}}
	report("hal, as slapd allows it:", s.Validate(hal))
	report("hal, with StrictAuxiliary:", s.ValidateWith(hal, schema.ValidateOptions{StrictAuxiliary: true}))
}
```

```
erin:
  - the auxiliary class ldapPublicKey is not in the AUX of the DIT content rule examplePersonRule (RFC 4512 4.1.6)
  - description is precluded by the DIT content rule examplePersonRule (RFC 4512 4.1.6)
  - telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
fay:
  - the RDN (cn) is allowed by no name form of inetOrgPerson: examplePersonForm needs uid
suffix: exampleSuffix <nil>
ou=people: exampleUnit <nil>
uid=gina: examplePersons <nil>
uid=gina directly under the suffix:
  - no DIT structure rule allows inetOrgPerson under an entry governed by the rule exampleSuffix (X.501 13.7.5)
hal, as slapd allows it:
   <nil>
hal, with StrictAuxiliary:
  - the auxiliary class posixAccount is allowed by no DIT content rule: account has none (RFC 4512 2.4.3)
```

空のモジュールから `github.com/go-authn/ldap` v0.11.0 (go1.27.1) で実行した例です。
`Validate` はこれまでどおり**すべての**問題を挙げます。erin は、コンテンツルールを一度に三通りで破っています。

**slapd との違い**は、見つけさせるのではなく、ここに書いておきます。

- slapd が実装するのはコンテンツルールだけです。ネームフォームや構造ルールのディレクティブはないので、
  `Format` は slapd が拒否する `nameform` と `ditstructurerule` のキーワードを書きます。
  `ditcontentrule` は slapd のものです。
- `OBSOLETE` のルールは無効です (RFC 4512 §4.1.6)。何も支配しません。slapd はそのエントリを
  代わりに拒否します。
- コンテンツルールがなければ、補助クラスは許可されます。これは slapd の動作で、その
  `SLAP_DISALLOW_AUX_WO_CR` フラグはどの `disallow` キーワードでも設定されません。
  `ValidateOptions{StrictAuxiliary: true}` は RFC 4512 §2.4.3 を与えます。上の `hal` が示すとおりです。
- libldap は構造ルールの `SUP` を読めません。

`hclschema.Decode` は、有効な UTF-8 でない文字列を拒否するようになりました。以前は受け入れ、
それが別の文字列にエンコードされていました (`FuzzDecode` で発見)。
[authnd]({{< relref "/authnd/schemas.md#rules" >}}) は、`schema_files` と `schema { }` ブロックから
これらの定義を読み込み、公開する木とエントリに適用します。

## HCL2 のスキーマと、コンバーター {#hcl2-and-the-converter}

v0.9.0 から、スキーマは slapd が読むファイルに加えて HCL2 でも書けます。パッケージ
`schema/hclschema` は HCL2 を、`schema.Read` が返すのと同じ `*schema.Definitions` にデコードし、
それを再びエンコードします (`hclschema.Decode`、`hclschema.Encode`)。`schema` 自体は HCL への依存を
持ちません。一つのブロックが一つの定義で、その型がどれかを示します。`object_identifier`、
`ldap_syntax`、`matching_rule`、`attribute_type`、`object_class` です。ラベルは最初の NAME です。
属性は RFC 4512 §4.1 の項を、小文字とアンダースコアにしたもの (`desc`、`sup`、`equality`、
`single_value`、`kind`、`must`、`may` など) で、構文の `{len}` は `syntax_len` です。

**リテラル値のみ。** 値は、引用符付きの文字列、数値、真偽値、またはそれらのリストです。変数、関数、
演算子、`${...}` テンプレートは、何かが評価される前に拒否されるので、スキーマを読んでもそれが
実行されることはありません。各フィールドは厳格な RFC 4512 パーサーで確認され、位置が必要なエラーには
ファイル、行、列が付きます。

コマンド `ldapschema` は形式間を変換します。

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.11.0
```

- `ldapschema to-hcl [--macros] FILE...` は OpenLDAP の `.schema` ファイル、cn=config LDIF、
  サブスキーマ LDIF を読み、HCL2 を書きます。
- `ldapschema to-schema [--macros] FILE...` は HCL2 を読み、OpenLDAP の `.schema` ファイルを書きます。
- `ldapschema check FILE...` は `schema.Standard()` の上に定義を構築して報告します。

出力は標準出力に行きます。終了ステータスは、コマンドが動作したときは 0、ファイルや定義が拒否された
ときは 1、使い方のエラーは 2 です。

**リーダーは slapd と同じようにファイルを読みます。** 公開されているスキーマは slapd 向けに書かれて
いるためです。項の順序は任意、`.schema` ファイルでは slapd の行継続、LDIF では RFC 2849 の折り返し、
base64 値、cn=config の `{N}` 接頭辞、ファイルの順序で解決される `objectidentifier` マクロです。
エクスポートされた `Parse*` 関数と、サーバーが公開するものは、厳格な RFC 4512 のままです。

`ldapschema` v0.10.1 で、空のディレクトリから実行した例です。スキーマはこのページのために作った
もので、1.3.6.1.4.1.99999 は私的利用の例示用アークであり、誰かに割り当てられたものではありません。
一つのマクロ、一つの属性型、一つの補助クラスです。

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1 NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1 NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top AUXILIARY
	MAY siteBadge )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

attribute_type "siteBadge" {
  oid          = "1.3.6.1.4.1.99999.1.1"
  desc         = "the badge number"
  equality     = "caseIgnoreMatch"
  syntax       = "1.3.6.1.4.1.1466.115.121.1.15"
  syntax_len   = 32
  single_value = true
}

object_class "sitePerson" {
  oid  = "1.3.6.1.4.1.99999.2.1"
  desc = "a person with a badge"
  sup  = ["top"]
  kind = "auxiliary"
  may  = ["siteBadge"]
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( 1.3.6.1.4.1.99999.1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( 1.3.6.1.4.1.99999.2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

attributetype ( site:1.1
	NAME 'siteBadge'
	DESC 'the badge number'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15{32}
	SINGLE-VALUE )

objectclass ( site:2.1
	NAME 'sitePerson'
	DESC 'a person with a badge'
	SUP top
	AUXILIARY
	MAY siteBadge )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 1 attribute types, 1 object classes
build: ok, 2 definitions added to schema.Standard()
```

出力では数値の OID が既定です。クライアントがサブスキーマで見るのがそれだからです。`--macros` は
マクロ名を保ちます。`check` は、`schema.Standard()` にすでにある定義と、何も定義していないすべての
参照も報告します。`Build` は最初のもので止まります。

**v0.11.0 から、`ldapschema` は三種類の[ルール](#rules)も変換します**。`.schema` ファイルでは
`ditcontentrule`、`nameform`、`ditstructurerule`、HCL ではブロック `dit_content_rule`、
`name_form`、`dit_structure_rule` です。構造ルールのラベルは最初の NAME で、`id`、それが配置する
`form`、その下に置かれる `sup` ルール (ID) を持ちます。`check` は、それらが作る未解決の参照をすべて
報告します。空のディレクトリから `ldapschema` v0.11.0 (タグから `go install` でビルド) で実行した、
それぞれ一つずつ含むスキーマの例です。

```
$ cat site.schema
# An example arc: 1.3.6.1.4.1.99999 is for private use.
objectidentifier site 1.3.6.1.4.1.99999

# inetOrgPerson: may carry uidObject, must have a telephone number.
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'sitePersonRule'
	AUX uidObject
	MUST telephoneNumber )

nameform ( site:9.1 NAME 'siteDomainForm' OC domain MUST dc )

ditstructurerule ( 1 NAME 'siteSuffix' FORM siteDomainForm )

$ ldapschema to-hcl site.schema
object_identifier "site" {
  oid = "1.3.6.1.4.1.99999"
}

dit_content_rule "sitePersonRule" {
  oid  = "2.16.840.1.113730.3.2.2"
  aux  = ["uidObject"]
  must = ["telephoneNumber"]
}

name_form "siteDomainForm" {
  oid  = "1.3.6.1.4.1.99999.9.1"
  oc   = "domain"
  must = ["dc"]
}

dit_structure_rule "siteSuffix" {
  id   = 1
  form = "siteDomainForm"
}

$ ldapschema to-hcl site.schema > site.hcl
$ ldapschema to-schema --macros site.hcl
objectidentifier site 1.3.6.1.4.1.99999

ditcontentrule ( 2.16.840.1.113730.3.2.2
	NAME 'sitePersonRule'
	AUX uidObject
	MUST telephoneNumber )

nameform ( site:9.1
	NAME 'siteDomainForm'
	OC domain
	MUST dc )

ditstructurerule ( 1
	NAME 'siteSuffix'
	FORM siteDomainForm )

$ ldapschema check site.schema
read: 1 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 1 name forms, 1 DIT structure rules
build: ok, 3 definitions added to schema.Standard()
```

**`check` は、slapd が読み込めるファイルに対して終了コード 1 を返すことがあります。** OpenLDAP の
`core.schema` は、slapd が組み込みで持ち `schema.Standard()` が定義していない四つのものを参照して
います。構文 1.3.6.1.4.1.1466.115.121.1.42 と 1.3.6.1.4.1.1466.115.121.1.43、そしてマッチングルール
`protocolInformationMatch` と `presentationAddressMatch` です。`ldapschema check core.schema` はそれらを
`missing:` として挙げて 1 で終了します。これはファイルの欠陥ではなく、「ここでは定義されていない」と
読んでください。

**サポートしないもの:** `include` ディレクティブ
(`.schema` ファイルは定義として読まれ、slapd の設定として実行されないため)。`ldapsyntax` の
`X-SUBST`。

**公開されているスキーマは変換できます。** リリースは、OpenLDAP の `core`、`cosine`、
`inetorgperson`、`nis`、RENATER の SUPANN 2021、REFEDS の eduPerson、Samba のスキーマで測定されました。
それぞれについて、`.schema` から HCL へ、そして戻す変換と、LDIF と `.schema` の比較が、等しい定義を
与えます。リポジトリにあるのは OpenLDAP のファイルだけです。SUPANN と eduPerson はここには再掲
していません。作者のページで読んでください:
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)
と [eduPerson](https://github.com/REFEDS/eduperson)。

## 何に対して検証されているか {#what-it-is-checked-against}

**OpenLDAP の `ldapsearch`** を CI で、インストールされている場所では必須として。Linux のテストレーン、
レース検出器、カバレッジレーンは `LDAP_REQUIRE_JUDGE=1` を設定するので、クライアントがないとスキップ
ではなく失敗します。Windows にはなく、それらのテストをスキップします。このモジュール自身のワイヤー
クライアントである `ldaptest` は、意図的に審判ではありません。`ldapsearch` に尋ねられないこと、
つまり一つの接続の状態についてだけを尋ねます。一つのソケット上の二つのバインド、任意のメカニズムを
使う SASL バインド、StartTLS の後に続く LDAP です。

`FuzzMessage` は、クライアントが送りうるすべてのメッセージを、フレーム、デコーダー、フィルターの
往復に通します。カバレッジの下限は 99.7% で、到達しない三行はワークフローに名前が挙げられています。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/ldap@v0.11.0](https://pkg.go.dev/github.com/go-authn/ldap@v0.11.0)
