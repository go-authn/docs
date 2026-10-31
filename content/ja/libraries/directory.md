---
title: "directory — 誰であるか、そして何がその人を証明するか"
linkTitle: "directory"
weight: 50
description: "go-authn/directory: メモリ上のリスト、SQL データベース、LDAP サーバー、または HCL 設定にある人と、ソースがその人について保持する認証情報の一つのモデル。"
tags: [ライブラリ, ディレクトリ, ldap, sql]
---

**ある人は誰で、何がその人を証明できるか。** メモリ上のリスト、SQL データベース、LDAP サーバー、
または設定ファイルの `user` と `group` ブロックに対する一つのモデルです。その要点は、問いの後半に
あります。

```sh
go get github.com/go-authn/directory@v0.16.0
```

## 何が人を証明するかは一つではない {#what-proves-somebody-is-not-one-thing}

これはプロトコルについての事実です。NTLMv2 (SMB) はチャレンジレスポンスで、クライアントは
パスワードを送らないので、サーバーはパスワードか `MD4(UTF16LE(password))`、つまり NT ハッシュを
保持していなければならず、**LDAP バインドでは SMB セッションを認証できません**。KDC は、その人の
鍵で*復号*しなければならないので、パスワードを保持するソースだけがレルムを支えられます。SSH には
公開鍵が必要です。第二要素には、六桁の数字の背後にあるシークレットが必要です。

そのため `Identity` は、そのソースがどの `Credential` を与えたかを述べます。`Password`、
`NTHash`、`Verifier` (ハッシュの比較またはバインド)、`PublicKeys`、`TOTPSecret` です。そして
`Identity.Can` により、誰かがマウント時に拒否に遭う前に、サーバーは *WebDAV は使えるが SMB は使え
ない*と言えます。各プロトコルには専用のメソッドがあります。

| | 答えるもの | 取得元 |
|---|---|---|
| `Verify(password)` | パスワードを渡されるもの全般 | まずソースの検証器 (LDAP バインドのこともある)、なければ保持しているパスワード。SHA-256 ダイジェストで一定時間比較されるので、長さすら漏れない |
| `NTKey()` | NTLMv2 | 公開されたハッシュ、またはパスワードから導出したもの。どちらもなければ `ErrNoCredential` |
| `Derive(f)`、`KerberosKey(f)` | KDC、AWS SigV4 — シークレットを*所持*しなければならないもの | パスワードのみ。導出は呼び出し側の関数 |
| `Keys()` | SSH | `authorized_keys` の行 |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | 列、または呼び出し側が名指しする LDAP 属性 |

## ソース {#the-sources}

| パッケージ | 読むもの | インポートするもの |
|---|---|---|
| `directory` | `Static` リストと、順序付きのソースの `Set` | 標準ライブラリのみ |
| `directory/sqldir` | 任意の `*sql.DB`。**あなたの**クエリで | ドライバーなし: プログラムが選ぶ |
| `directory/ldapdir` | LDAP サーバー | `go-ldap/ldap/v3` |
| `directory/hcldir` | データベースや LDAP サーバーを指す `users` ブロックと、人を保持する `user`/`group` ブロック | `x/crypto/ssh`、`hashicorp/hcl/v2`、`zclconf/go-cty` |
| `directory/ldaptest` | テスト対象となる LDAP サーバー | `glauth/ldap` |

`Set` では、ある名前を**最初に**知っているソースがそれを所有するので、ローカルに書かれた
サービスアカウントを LDAP に入れる必要はありません。グループのメンバーシップは、すべてのソースの
**和集合**です。ソースはサーバーの起動時に読まれます。パスワードの検証は、毎回ソースに到達
してもよいことになっています。シークレットを保持せずにバインドをキャッシュすることはできない
からです。`GroupReader` を実装するソース (sqldir と ldapdir が実装しています) は、すべてのグループを一括で 1 回だけ読み込みます。すると `Set.Frozen()` は、`Members`、`GroupAttributes`、`GroupObjectClasses`、`GroupNames` に、`Set` 自身のマージ規則でメモリから答えます。閉じるのは凍結した `Set` ではなく、元の `Set` です。

`hcldir` は HCL をデコードしません。呼び出し側がブロックをデコードして渡します。HCL を
インポートするのは、`SetPassword` のために書き込むためだけです。ビルドタグ `nosql` と `noldap` は、
`hcldir` からその種類を完全に除きます。

## 例 {#example}

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	local := &directory.Static{
		Name: "the configuration file",
		People: []*directory.Identity{
			directory.NewIdentity("dora", directory.WithPassword("hunter2")),
			directory.NewIdentity("eli", directory.WithVerifier(func(pw string) error {
				return directory.ErrWrongPassword // a bind against somebody else's LDAP, say
			})),
			directory.NewIdentity("svc-backup", directory.WithPublicKeys("ssh-ed25519 AAAA...elided... backup")),
		},
		Groups: map[string][]string{"staff": {"dora", "eli"}, "nobody": {}},
	}
	people := directory.NewSet(local) // more sources after it: sqldir, ldapdir...

	ids, _ := people.Identities()
	for _, id := range ids {
		fmt.Println(id.Name(), "password:", id.Can(directory.Password), "verifier:", id.Can(directory.Verifier),
			"keys:", id.Can(directory.PublicKeys), "from", id.Where())
	}

	// NTLMv2 needs MD4(UTF16LE(password)): dora's can be derived, eli's cannot.
	for _, id := range ids[:2] {
		_, err := id.NTKey()
		fmt.Println(id.Name(), "SMB:", err == nil, errors.Is(err, directory.ErrNoCredential))
	}

	// An empty group is an empty answer; a group nobody has is an error.
	fmt.Println(people.Members("nobody"))
	fmt.Println(people.Members("admins"))

	// @group is expanded; an empty group, or one nobody has, is refused.
	fmt.Println(directory.Expand([]string{"@staff", "svc-backup"}, people))
	fmt.Println(directory.Expand([]string{"@nobody"}, local))
	_, err := directory.Expand([]string{"@nobody"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
	_, err = directory.Expand([]string{"@admins"}, people)
	fmt.Println(err, errors.Is(err, directory.ErrEmptyGroup), errors.Is(err, directory.ErrNoSuchGroup))
}
```

```
dora password: true verifier: true keys: false from the configuration file
eli password: false verifier: true keys: false from the configuration file
svc-backup password: false verifier: false keys: true from the configuration file
dora SMB: true false
eli SMB: false true
[] <nil>
[] directory: no such group: "admins", in the configuration file
[dora eli svc-backup] <nil>
[] directory: the group has no members: "nobody": nobody would be allowed
directory: the group has no members: "nobody": nobody would be allowed true false
directory: no such group: "admins", in the configuration file false true
```

保持しているパスワードは `Can(Verifier)` にも答えます。比較できるからです。

{{< callout type="info" >}}
**空のグループもグループである: `Members` は答え、`Expand` は拒否する**

v0.12.0 から、`Set.Members` は、ソースにあるがメンバーのいないグループに対して、エラーなしで
空のリストを返すので、グループを一覧するサーバーはそれを公開できます。`Expand` は依然として
`ErrEmptyGroup` でそれを拒否し、これは `ErrNoSuchGroup` ではありません。誰も持っていない
グループは誤字か削除されたグループで、空のグループは埋めるべきグループです。何も許可しない
グループを許容する呼び出し側は、両方をテストします。v0.11.x では、`Set.Members` は空の
グループに `ErrNoSuchGroup` を返し、`Set` 経由の `@nobody` の `Expand` は
`[] directory: no such group: "nobody"` と出力していました。
{{< /callout >}}

## 属性 {#attributes}

v0.13.0 から、`Identity` は**属性**を運べます。ソースが誰かについて述べるもので、何も証明しない
もの、たとえば `uidNumber`、ホームディレクトリ、メールアドレスです。これらは意図的に認証情報とは
切り離されています。認証情報は誰がログインできるかを決め、属性は検索を許されたすべての人に
*公開*されます。[authnd]({{< relref "/authnd/entries.md" >}}) のようなサーバーはそれらを LDAP
エントリの属性に変え、そのスキーマがエントリが何であるかを決めます。

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	a, err := directory.NewAttributes(
		directory.Attribute{Name: "uidNumber", Values: []string{"1000"}},
		directory.Attribute{Name: "mail", Values: []string{"dora@example.org"}},
		directory.Attribute{Name: "MAIL", Values: []string{"d.explorer@example.org", "dora@example.org"}},
	)
	fmt.Println(err)
	dora := directory.NewIdentity("dora", directory.WithPassword("hunter2"), directory.WithAttributes(a))
	fmt.Println(dora.Attributes().Names(), dora.Attributes().Get("UIDNUMBER"), dora.Attributes().Get("mail"))

	// What is published cannot hold a secret, nor what a server derives or answers itself.
	for _, name := range []string{"userPassword", "sambaNTPassword", "radiusHash", "cn", "memberUid", "2.5.4.35"} {
		_, err := directory.NewAttributes(directory.Attribute{Name: name, Values: []string{"x"}})
		fmt.Println(errors.Is(err, directory.ErrAttributeName), err)
	}
}
```

```
<nil>
[uidNumber mail] [1000] [dora@example.org d.explorer@example.org]
true directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "sambaNTPassword" holds a secret, and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "radiusHash" looks like it holds a secret (its name contains "hash"), and attributes are published: a credential has its own option or none
true directory: not an attribute this package carries: "cn" is derived by the server from the name it publishes the entry under
true directory: not an attribute this package carries: "memberUid" is membership, which Members answers: a second answer would disagree with it
true directory: not an attribute this package carries: "2.5.4.35" is an OID: name it by its descriptor, so that what is refused by name stays refused
```

名前は RFC 4512 の属性記述で、大文字小文字とオプションの順序を無視して比較されるので、`mail` と
`MAIL` は一つの属性であり、最初に与えられた綴りで保持されます。値の完全な繰り返しは一度だけ
保持されます。値は文字列であり、解釈されません。`"1000"` が `uidNumber` であるのは、サーバーの
スキーマがそう述べるからです。空の値、または値がないものは拒否されます。

| 拒否されるもの | 理由 |
|---|---|
| 名前を挙げた 56 個のシークレット — `userPassword`、`authPassword`、`userPKCS12`、`sambaNTPassword`、`sambaLMPassword`、`unicodePwd`、`krbPrincipalKey`、`krb5Key`、`ipaNTHash`、`ipatokenOTPkey`、`oathSecret`、`olcRootPW`、… | RFC 4519、RFC 3112、RFC 2798 と、Samba、Active Directory、MIT および Heimdal Kerberos、FreeIPA、389-ds、OpenLDAP のスキーマから読み取ったもの |
| `password`、`passwd`、`pwd`、`secret`、`credential`、`hash`、`privatekey` を含む名前 | リストが知っているのは誰かが読んだスキーマだけである。これで捕まる唯一の標準名 `secretary` (RFC 4524) は許可される |
| `sshPublicKey` | 専用の経路 `WithPublicKeys` があり、`Can(PublicKeys)` が true のままになる |
| `uid`、`userid`、`cn`、`commonName`、`objectClass` | サーバーがエントリを公開する名前から導出する |
| `member`、`uniqueMember`、`memberUid`、`memberOf` | メンバーシップは `Members` が答えるもので、二つ目の答えは食い違う |
| `createTimestamp`、`modifyTimestamp`、`creatorsName`、`modifiersName`、`structuralObjectClass`、`governingStructureRule`、`subschemaSubentry`、`entryDN`、`entryUUID` | サーバーが維持するもので、設定は偽造することしかできない |
| 数値形式の名前 | 拒否は名前によるもので、`2.5.4.35` は `userPassword` *である* |

`ReservedAttributes()` は、理由を伴う 75 個の名前の全リストを返します。`CheckAttributeName` は
規則だけを適用するので、何かが読まれる前に設定を拒否できます。

出どころ:

- **`hcldir`**: `user` と `group` ブロックの `attributes = { … }`。名前ごとに文字列または文字列の
  リスト。数値は、修正方法をメッセージに添えて拒否され (*write it as a string, "1000"*)、
  `null` はその属性を省きます。
- **`sqldir`**: 二つの任意のクエリ `users_attributes` と `groups_attributes`
  (`Queries.PeopleAttributes`、`GroupAttributes`) が、**列のエイリアスで**読みます。最初の列が名前で、
  他のすべての列が、そのエイリアスで名付けられた属性です。エイリアスが属性記述でない列や、
  認証情報を名指しする列は、行が読まれる前に列番号付きで拒否されます。`NULL` と `''` は存在
  しないものとして扱われ、一つの名前に複数の行があると値が加わります。そこにだけ名前のある
  グループは、メンバーなしで存在します。⛔ PostgreSQL は引用符のないエイリアスを小文字にします
  (`as uidNumber` は `uidnumber` として返る)。同じ属性ですが、データベースの綴りです。綴りが
  重要な場合は `as "uidNumber"` のように引用符で囲んでください。
- **`ldapdir`**: `Config.Attributes` と `GroupAttributes` (`users "ldap"` ブロックの `attributes` と
  `group_attributes`) が、各人のエントリと各グループのエントリから何をコピーするかを名指しし、
  RFC 4512 の等価性で照合され、設定された綴りで保持されます。上のリストに加えて、
  `totp_attribute` と、グループの命名属性およびメンバー属性も拒否します。ディレクトリが追加で
  返すサブタイプ (`description` に対する `description;lang-fr`) はコピーされません。名前で
  求めてください。

グループの属性は、任意の `GroupAttributer` を通じて `Set.GroupAttributes` から得られます。
**属性を最初に与えたソースがそれを所有する**ので、ローカルファイルの `gidNumber` はディレクトリの
ものを上書きしつつ、ディレクトリにしかない `description` は通ります。そして壊れたソースは、
別のソースが答えたときでもエラーです。人の属性は、その名前を所有するソースから、その人とともに
来ます。

## オブジェクトクラス {#object-classes}

v0.15.0 から、ソースは自分の人々とグループが持つ補助オブジェクトクラスを**宣言**できます。
これにより、[authnd]({{< relref "/authnd/schemas.md" >}}) のようなサーバーがサイトスキーマ
(SUPANN、eduPerson) を公開できます。クラスはすべてのエントリの形を約束するもの (RFC 4512
§4.1.1) なので、存在する属性から推論されることは決してなく、データから読まれることも
決してありません。データベースの列も、上流の `objectClass` の値もそうです。データベースに
現れた属性が、公開されるクラスを変えることはできません。

```go
package main

import (
	"errors"
	"fmt"

	"github.com/go-authn/directory"
)

func main() {
	c, err := directory.NewObjectClasses("supannPerson", "eduPerson", "EDUPERSON")
	fmt.Println(c.Names(), err)
	ann := directory.NewIdentity("ann", directory.WithPassword("hunter2"), directory.WithObjectClasses(c))
	fmt.Println(ann.ObjectClasses())
	fmt.Println(directory.NewIdentity("bob").ObjectClasses())

	// A class is a name, never a number or a filter.
	for _, name := range []string{"edu Person", "1.3.6.1.4.1.5923.1.1.2", "x)(objectClass=*"} {
		_, err := directory.NewObjectClasses("eduPerson", name)
		fmt.Println(errors.Is(err, directory.ErrObjectClassName), err)
	}
}
```

```
[supannPerson eduPerson] <nil>
[supannPerson eduPerson]
[]
true directory: not an object class name: "edu Person" is not a descriptor: a letter, then letters, digits and hyphens (RFC 4512 §1.4)
true directory: not an object class name: "1.3.6.1.4.1.5923.1.1.2" is an OID: name the class by its descriptor, so that what is refused by name stays refused
true directory: not an object class name: "x)(objectClass=*" is not a descriptor: a letter, then letters, digits and hyphens (RFC 4512 §1.4)
```

名前は書かれた順序で、大文字小文字を無視して一度だけ保持されます (`EDUPERSON` は
`eduPerson` の繰り返しです)。このパッケージが検査するのは RFC 4512 の記述子としての
**綴り**だけです。数値 OID、空白、引用符、丸括弧は拒否され、その拒否はファジングされています。
クラスが定義されているか、AUXILIARY か、サーバーが導出するものでないかは、サーバーが
提供するスキーマに照らして、サーバー側が検査します。

どこから来るか:

- **`hcldir`**: どちらの種類の `users` ブロックでも `object_classes` と `group_object_classes`、
  そして `user` と `group` ブロックの `object_classes`。エラーには設定内の位置が付きます。
- **`sqldir`**: `WithObjectClasses` と `WithGroupObjectClasses`。
- **`ldapdir`**: `Config.ObjectClasses` と `Config.GroupObjectClasses`。

`Identity.ObjectClasses()` は人の一覧のコピーを返します。グループのものは、任意の
`GroupObjectClasser` を通じて `Set.GroupObjectClasses` から得られ、`GroupAttributer` の
横に並びます。**そのグループを持ち、クラスを宣言する最初のソースが、全体を決めます**。
何も宣言しないソースは決めず、後のソースの異なる一覧は無視され、マージもエラーもありません。
(authnd は `check` でそれを知らせます。)

`sqldir.ClosesDB()` はデータベースをそのソースに渡し、`(*sqldir.Source).Close` がそれを閉じます。
`hcldir.Open` は `*sqldir.Source` そのものを返すようになりました。

## ldapdir の既定値 {#ldapdir-defaults}

| 設定 (`users "ldap"` / `ldapdir.Config`) | v0.14.0 からの既定値 | v0.13.0 まで |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`、`ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | 同じ |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | 同じ |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`、`ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | 同じ |
| `group_member_attribute` / `MemberAttribute` | なし: `memberUid` (名前)**と** `member` (DN)。設定すると、それが読まれる唯一の属性になる | `memberUid` |

三つのクラスは `uid` を運ぶ標準のクラスです。`posixAccount` (RFC 2307)、`account`
(RFC 4524 §3.1)、`uidObject` (RFC 4519 §3.14) です。go-authn/authnd は v0.11.0 から、POSIX 属性の
ない人を `account` または `inetOrgPerson` として公開し、すべての人に `uidObject` を付け、
`gidNumber` のないグループを `groupOfNames` として公開します。古い既定値では、そのような人や
グループはまったく読まれませんでした。

{{< callout type="warning" >}}
**v0.14.0 は、組織のディレクトリが提供する範囲を広げる**

posixAccount ではない `account` や `uidObject` のエントリ — サービスアカウント、uid で名付けられた
ホスト、他から取り込まれた人々 — を持つディレクトリは、既定値を保っているすべてのプログラムに
それらを渡すようになり、そのそれぞれをバインドでディレクトリに対して検証できます。その
`groupOfNames` のグループはグループになり、それを名指しする `@group` ルールは、述べるとおりのものを
許可するようになります。三つのクラスのどれも持たない単なる `inetOrgPerson` は、引き続き読まれません。
以前とまったく同じ集合を保つには:

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**`member` DN は人を追加しません。** それが誰かに対応付けられるのは、distinguishedNameMatch
(RFC 4517 §4.2.15) により、人々の検索が返したエントリの DN である場合だけです。それらのエントリの
外にある DN や誰も指さない DN は誰にも対応付けられず、alice が `ou=people` から取り込まれた場合の
`uid=alice,ou=elsewhere,…` も同様です。v0.13.0 までは、member 属性の DN は誰のものであっても最初の
RDN の値に還元されていたので、`uid=alice,ou=elsewhere,…`、`cn=alice,…`、`uid=zed,…` は、alice、
alice、zed という名前のメンバーになっていました。

テスト用ディレクトリ `ldaptest` は、すべての検索にベースとフィルターを適用するようになり、各人に
`objectClass` を与え (`Person.ObjectClasses`、既定は `top`、`account`、`posixAccount`)、
`groupOfNames` のグループ (`GroupsOfNames`) を持つので、クライアントのフィルターのテストが失敗
できるようになりました。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

- **メンバーのいないグループ**と**どのソースにもないグループ**を、`Expand` が `@group` を人々に
  変えるときに — 空のリストではなくエラー。誰にも何も許可しない設定は、動作する設定と見分けが
  つかないからです。前者は `ErrEmptyGroup`、後者は `ErrNoSuchGroup` で、`errors.Is` で区別できます。
  `Set.Members` は空のグループに空のリストを返し、どのソースにもないグループはそこでも
  `ErrNoSuchGroup` です。*壊れた*ソースは、グループを持たないソースとは別に報告され、空の答えより
  優先されます。
- **平文で到達する LDAP ディレクトリ。** 単純バインドはパスワードそのものを運ぶ (RFC 4513) ので、
  `ldapdir.New` と `users "ldap"` ブロックは、`StartTLS` が設定されていない限り、他のマシンへの
  `ldap://` を拒否します。`ldaps://`、`ldapi://`、ループバックアドレスへの `ldap://` は受け入れ
  られます。これを無効にするスイッチはありません。
- **LDAP バインドでの空のパスワード。** LDAP では*未認証バインド*であり、ほとんどのディレクトリは
  成功で応答します。`ldapdir` は接続せずに `ErrWrongPassword` を返します。
- **間違ったパスワードと取り違えられる、その他の失敗したバインド。** LDAP の結果 49、
  *invalidCredentials* だけが `ErrWrongPassword` です。バインド中に切断された接続や、ビジー (51) や
  利用不可 (52) と答えるディレクトリは、LDAP エラーをラップした
  `ldapdir: the directory did not answer the bind: …` として返されます。パスワードはどちらの場合も
  拒否されますが、正しく入力した人に対して、サーバーのログが*間違ったパスワード*と述べることは
  なくなります。v0.11.2 より前は、失敗したバインドはすべて `ErrWrongPassword` でした。
- **LDAP URL 内の認証情報** — URL は出力されます。`BindDN` と `BindPassword` はフィールドです。
- **16 バイトでない NT ハッシュ** (`ParseNTHash`)。パディングして、あらゆるログインを間違った
  パスワードとして失敗させるハッシュにするのではなく、拒否します。
- **パスワードのない ID に対する `Derive` または `KerberosKey`。** 検証器の「はい」は鍵ではありません。
- **シークレットである属性、またはサーバー自身が答える属性** —
  [上のリスト]({{< relref "/libraries/directory.md#attributes" >}}) — を、設定される場所を問わず:
  ブロック内、SQL のエイリアス、ldapdir のコピーするリストのいずれでも。

{{< callout type="warning" >}}
**NT ハッシュと TOTP シークレットは認証情報であり、その認証情報のハッシュではない**

`sambaNTPassword` を持つ者は、パスワードを持つのとまったく同様にその人として認証されます。
TOTP シークレットを持つ者は、将来のすべてのコードを生成できます。`WithVerifier` のエラーは
サーバーに渡り、クライアントには決して渡りません。
{{< /callout >}}

## 何に対して検証されているか {#what-it-is-checked-against}

- **OpenLDAP の `ldapsearch`** が `ldaptest` のディレクトリを読みます。エントリ、それを持つ唯一の人の
  `sambaNTPassword`、グループです。間違ったパスワードには *Invalid credentials (49)* で拒否されます。
  CI の Linux レーンは `ldap-utils` をインストールします。`ldapsearch` がない場合、テストはスキップ
  されます。このモジュールの CI には、そのスキップを失敗に変えるものはありません。
- **`ldapdir` と `glauth/ldap`**。偽物ではない、独立した LDAP サーバーです。フィクスチャは未認証
  バインドを許可するので、`ldapdir` がそれを先に拒否しなくなると、テストは失敗します。
- **`sqldir` と本物の SQLite データベース**を、本物のドライバー経由で。属性クエリは、PostgreSQL 18.6
  に対して pgx 経由で一度手作業でも実行しました (CI ではありません)。引用符のないエイリアスは
  小文字で返されながらも見つかり、引用符付きのものは大文字小文字を保ち、`userPassword` を
  名指しするエイリアスは拒否されました。
- **ldapdir のフィルター**と `ldaptest`。v0.14.0 からこれがフィルターを適用します。既定の
  ユーザーフィルターは単なる `inetOrgPerson` を除き (`TestTheDefaultUserFilter`)、グループ
  フィルターは ID を追加しません (`TestTheGroupFilterAddsNoIdentity`)。
- **MD4** と RFC 1320 のテストベクター。

カバレッジレーンは 85% を下回ると失敗し (宣言された基準は 100%)、`nosql` と `noldap` のビルドは
CI で確認されます。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
