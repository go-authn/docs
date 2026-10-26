---
title: "サイトスキーマと、ソースが宣言するクラス"
linkTitle: "サイトスキーマ"
weight: 27
description: "SUPANN、eduPerson、またはサイト独自の属性を提供する: schema_files と schema ブロックが定義を追加し、object_classes がソースの人々とグループが持つ補助クラスを宣言し、check が何が外されたかを伝えます。v0.13.0 から、DIT コンテンツルール、ネームフォーム、DIT 構造ルールが適用されます。"
tags: [authnd, ldap, スキーマ, 設定]
---

**SUPANN や eduPerson の属性は、そのエントリのいずれかのクラスが許さない限り破棄されます。**
authnd は、提供するスキーマが許すものだけを公開します
([エントリ]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})を参照)。
標準スキーマは `supannEtablissement` も `eduPersonAffiliation` も知りません。
v0.12.0 から、サイトは次の三つを、この順序で述べます。

1. **どの定義を追加するか**: `schema_files`。サイトの slapd がすでに読み込んでいるファイルと、
   ローカルだけのものを書く `schema { }` ブロック
2. **人々とグループがどの補助クラスを持つか**: `object_classes`
3. それ以外にはありません。クラスは**宣言されるもので、推論されません**。データベースに
   現れた属性が、エントリの公開のされ方を変えることはありません。

{{< callout type="info" >}}
**このページの例は例です**

以下の `example.schema` は、このページのために書かれました。その OID は
`1.3.6.1.4.1.99999` の下にあり、これは誰にも割り当てられていない枝です。自分の OID を使い、
これらは決してコピーしないでください。SUPANN については[このページの末尾](#supann)を
参照してください。
{{< /callout >}}

## 例: スキーマ、データベース、設定 {#an-example}

OpenLDAP の `.schema` 形式のスキーマです。ソースが宣言できるクラスが一つ
(`exampleStaff`、AUXILIARY、MUST あり)、宣言できないクラスが一つ
(`exampleUnit`、STRUCTURAL) あります。

```
objectidentifier exampleRoot  1.3.6.1.4.1.99999
objectidentifier exampleAttr  exampleRoot:1
objectidentifier exampleClass exampleRoot:2

attributetype ( exampleAttr:1 NAME 'exampleBadge'
	DESC 'the number on a badge'
	EQUALITY caseIgnoreMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

attributetype ( exampleAttr:2 NAME 'exampleEmployeeId'
	DESC 'a staff number'
	EQUALITY caseExactMatch
	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15
	SINGLE-VALUE )

# AUXILIARY: it can be declared. exampleStaff has a MUST.
objectclass ( exampleClass:1 NAME 'exampleStaff' SUP top AUXILIARY
	DESC 'somebody employed: has a staff number'
	MUST exampleEmployeeId
	MAY exampleBadge )

# STRUCTURAL: it cannot be declared (an entry has one structural chain).
objectclass ( exampleClass:2 NAME 'exampleUnit' SUP top STRUCTURAL
	MUST cn )
```

`sn`、バッジ、社員番号を持つ三人の SQLite データベース
(`sqlite3 var/people.db < people.sql`):

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

そして設定:

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

# Files first, then the blocks: a definition may use anything before it.
schema_files = ["etc/authnd/example.schema"]

schema {
  attribute_type "exampleLocker" {
    oid    = "1.3.6.1.4.1.99999.1.3"
    syntax = "1.3.6.1.4.1.1466.115.121.1.15"
  }
  object_class "exampleLockerHolder" {
    oid  = "1.3.6.1.4.1.99999.2.3"
    kind = "auxiliary"
    may  = ["exampleLocker"]
  }
}

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret from staff"
  users_attributes = "select login, sn, badge as exampleBadge, empid as exampleEmployeeId, locker as exampleLocker from person_attrs"
  object_classes   = ["exampleStaff", "exampleLockerHolder"]   # declared, never inferred
}
```

`object_classes` の行がないと、`check` は標準スキーマだけが同じ人々をどう扱うかを伝えます。
属性は破棄され、各行はそれを保持したはずのクラスを挙げます。

```
$ authnd check cases/nodecl.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes

USER  FROM               CAN PROVE   PUBLISHED AS                                            WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn and sn

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ann is published without exampleBadge: no class of the entry allows it; exampleStaff would
ann is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
cat is published without exampleEmployeeId: no class of the entry allows it; exampleStaff would

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## `schema_files` {#schema-files}

`schema_files` は、OpenLDAP の `.schema` ファイルまたは cn=config LDIF ファイルの一覧です。
これらは**公開されているとおりに**、順に、標準スキーマ (と、[`samba` ブロック]({{< relref "/authnd/tls.md#the-samba-block" >}})
がある場合は Samba の三つの定義) の上に、go-authn/ldap の
[slapd 互換リーダー]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})によって読み込まれます。
項の順序は問われず、slapd と RFC 2849 の継続行、base64、`{N}` の長さ接頭辞、そして
`objectidentifier` マクロが使えます。マクロは、slapd の `include` をまたぐ場合と同様に、
あるファイルで定義し、次のファイルで使えます。事前に何も変換されないので、サイトの slapd が
読み込むファイルが、そのまま authnd が読み込むファイルです。定義は `cn=Subschema` で
提供されます。

- 相対パスは、設定の他のすべてのパスと同様に、作業ディレクトリからの相対です。サービスでは
  絶対パスを使ってください。systemd ユニットの作業ディレクトリは `/` です。
- 各ファイルは、4 MiB 以下の通常ファイルでなければならず、起動時に一度だけ読まれます。
- ファイルは、すべてのエントリが何を持てるかを決めます。秘密ではありませんが、他の設定と一緒に
  保管してください。`root:authnd`、モード `0640`、root だけが書き込めるディレクトリです
  ([インストール]({{< relref "/authnd/install.md" >}}))。
- ビルドできないファイルは、起動と `check` を拒否します。メッセージには、ファイル、行、定義の始まる列が示され、
  末尾に拒否の種類が付きます。未知のスーパークラス、属性、マッチングルール、構文
  (`unknown reference`)、補助クラスから派生した構造クラス (`kind violation`)、
  二度定義された OID や名前 (`duplicate OID`、`duplicate name`) などです。v0.12.1 から、
  場所と種類は、メッセージを読み解くのではなく、go-authn/ldap の型付きの
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}}) から得られます。
  ファイルから読んだ定義は、テキストが複数行に折り返されていても、1 列目から始まります。
  重複は最初の定義の場所を示し、再定義は、元の定義を保持する標準ファイル、
  または先のファイルの行を示します。二つの例:

  `cases/unknown.schema` には、どこにも定義されていない MAY があります。

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema` は、二つの属性型に一つの OID を与えています。

  ```
  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleA'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )

  attributetype ( 1.3.6.1.4.1.99999.1.9 NAME 'exampleB'
  	SYNTAX 1.3.6.1.4.1.1466.115.121.1.15 )
  ```

  ```
  $ authnd check cases/twice.hcl
  authnd: schema_files: cases/twice.schema:4:1: the attribute type 1.3.6.1.4.1.99999.1.9 is defined twice (first defined at cases/twice.schema:1:1) (duplicate OID)
  ```

### 再定義は、同一であっても拒否される {#redefinition}

ファイルは、すでにあるものを定義してはなりません。標準スキーマの定義、Samba の定義、
先のファイルの定義です。**一語一句同じであっても**拒否され、これは slapd 自身の規則です。
スキーマファイルの定義は `parse_at` と `parse_oc` を通り、slapd は、すでに索引にある OID や
名前に対して *Duplicate attributeType* (OID も名前も同じ場合) または *Inconsistent duplicate
attributeType* と答えます (`servers/slapd/at.c`、`oc.c`)。前者が許されるのは、slapd 自身の
ハードコードされたスキーマだけです。slapd が拒否するファイルは、authnd も拒否します。

もう一方の解釈では勝者を選ばなければならず、それは標準属性が何であるかについて、すべての
クライアントに伝えられる内容を黙って変えてしまいます。拒否すれば、代わりに行が示されます。
拒否は、テキストが同じだったかどうかも伝えます。`cn` (2.5.4.3) を独自の定義で再定義する
ファイル:

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## `schema { }` ブロック {#the-schema-block}

ローカルだけの定義のために、`schema` ブロックがそれを HCL2 で保持します。
[hclschema の形]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})で、
`attribute_type`、`object_class`、`object_identifier`、`matching_rule`、`ldap_syntax` です。
これはファイルの**後に**読まれるので、ファイルの定義を使うことができ、複数置けます。

値は**リテラル**でなければなりません。変数も関数も、`${...}` や `%{...}` も使えません。
ブロックは、`.hcl` スキーマファイルを読むのと同じデコーダーで、同じ上限のもとにデコードされ、
すべてのエラーは設定自身の行と列を示します。HCL のネイティブ構文ではないブロックは拒否されます。

## `object_classes` {#object-classes}

スキーマの定義は属性を許しますが、誰かにクラスを付けるわけではありません。ソースは、自分の
人々とグループが公開される際の補助クラスを**宣言**します。

| どこで | キー | 何を宣言するか |
|---|---|---|
| `users` ブロック、どの種類でも | `object_classes` | そのブロックが与えるすべての人のクラス |
| `users` ブロック、どの種類でも | `group_object_classes` | すべてのグループのクラス |
| `user` ブロック | `object_classes` | その人のクラス |
| `group` ブロック | `object_classes` | そのグループのクラス |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

これらのキーは go-authn/directory のもので、v0.15.0 からです
([ライブラリ]({{< relref "/libraries/directory.md#object-classes" >}}))。名前は大文字小文字を
無視して比較され、書かれた順序で一度だけ保持されます。

宣言されたクラスについて authnd がすること:

- **スーパークラスとともに公開されます。** authnd が導出するクラスの後に置かれます
  (RFC 4512 §3.3: 名前を挙げられたクラスのすべてのスーパークラスが暗黙に追加される)。
  そのクラスが許す属性は、破棄されずに保持されます。
- **推論されることは決してありません。** ソースが何も宣言しない人は、データベースに何が
  あっても、自分のどのクラスも許さない属性を失い続けます。
- **宣言されたクラスの MUST が足りない人は、そのクラスなしで公開されます。** その属性は、
  どのクラスも許さない属性と同様に破棄され、両方が報告されます。これは authnd がどこでも
  従う規則です。人は公開されたままで、問題は伝えられ、何も黙って変更されません。
  人を保留すれば、一つの属性が足りないだけでその人はすべての検索から消えます。MUST なしで
  クラスを公開すれば、提供するスキーマに適合しないエントリを提供することになります。
- **二つのソースが一つのグループに異なるクラスを宣言することがあります。** グループのクラスを
  宣言する最初のソースが全体を決め、後の一覧は無視されます。マージもエラーもありません。
  `check` がそれを伝えます。

ここでは ann はすべてを持ち、cat にはロッカーがなく (MAY)、ben には `exampleStaff` の MUST である
`exampleEmployeeId` がありません。

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people

USER  FROM               CAN PROVE   PUBLISHED AS                                                                               WITH
ann   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn, exampleBadge, exampleEmployeeId and exampleLocker
ben   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder                uid, cn and sn
cat   a sqlite database  a password  person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder  uid, cn, sn and exampleEmployeeId

ann has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder
ben has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleLockerHolder
ben is published without exampleStaff, which its source declares: ben has no exampleEmployeeId, which exampleStaff requires
ben is published without exampleBadge: no class of the entry allows it; exampleStaff would
cat has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject, exampleStaff, exampleLockerHolder

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

起動時のログにも、DN を使った同じ行が出ます。

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 3 people from a sqlite database
schema: etc/authnd/example.schema adds 3 object identifier macros, 2 attribute types and 2 object classes
schema: the schema block at etc/authnd/authnd.hcl:9:1 adds 1 attribute type and 1 object class: exampleLocker and exampleLockerHolder
etc/authnd/authnd.hcl:26:22: users "sql" declares exampleStaff and exampleLockerHolder for its people
uid=ben,ou=people,dc=example,dc=org is published without exampleStaff, which its source declares: uid=ben,ou=people,dc=example,dc=org has no exampleEmployeeId, which exampleStaff requires
uid=ben,ou=people,dc=example,dc=org is published without exampleBadge: no class of the entry allows it; exampleStaff would

stopping
```

そして、リーダーのパスワードをファイルに置いて、OpenLDAP の `ldapsearch` が読み戻したもの。
ann は両方の補助クラスと、それらが許すすべての属性を持ちます。ben は `exampleLockerHolder` だけを
持ち、バッジは `exampleStaff` とともになくなっています。cat は両方を持ち、社員番号があります。

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(uid=*)'
dn: uid=ann,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: ann
cn: ann
sn: Archer
exampleBadge: B-0001
exampleEmployeeId: E-1001
exampleLocker: L-12

dn: uid=ben,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleLockerHolder
uid: ben
cn: ben
sn: Brook

dn: uid=cat,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject
objectClass: exampleStaff
objectClass: exampleLockerHolder
uid: cat
cn: cat
sn: Cole
exampleEmployeeId: E-1003

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y etc/authnd/reader.pw -b ou=people,dc=example,dc=org '(objectClass=exampleStaff)' 1.1
dn: uid=ann,ou=people,dc=example,dc=org

dn: uid=cat,ou=people,dc=example,dc=org
```

## 何が拒否され、なぜか {#what-is-refused}

宣言されたクラスは、起動時と `check` で、提供されるスキーマに照らして検査されます。次の
条件を満たさなければなりません。

- **定義されている**こと。標準スキーマ、ファイル、またはブロックによって。
- **AUXILIARY** であること (RFC 4512 §4.1.1)。エントリには構造のチェーンがちょうど一つあり
  (§2.4.2)、それは人が持つものから authnd が選びます。宣言で二つ目を加えることはできません。
- **authnd が自ら導出するものではない**こと: `account`、`inetOrgPerson` とそのスーパークラス、
  `posixAccount`、`posixGroup`、`ldapPublicKey`、`uidObject`、`sambaSamAccount`、
  `groupOfNames`、`organizationalRole`。どの名前でも同じです。これらは人またはグループが
  持つものから決まり、宣言が `check` を覆すことはできません。

そうでなければ、起動はブロック、その位置、クラスを示して拒否されます。`exampleUnit` は
STRUCTURAL です。

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory はその前に**綴り**を検査します。クラスは記述子であり、OID、空白、引用符、
丸括弧であってはなりません。

スキーマを正直に保つという同じ理由で、次のものも拒否されます。

| 拒否されるもの | 理由 |
|---|---|
| 定義を再定義するファイル。一語一句同じでも | slapd の規則: [上記](#redefinition) |
| 通常ファイルではない、または 4 MiB を超えるファイル | FIFO は起動を止め、`/dev/zero` は終わらない |
| 変数、関数、`${...}` を含む `schema` ブロック | `.hcl` スキーマファイルと同様に、リテラルの値のみ |
| `object_classes` の未定義のクラス | 何も検査できない約束 |
| STRUCTURAL のクラス、または authnd が導出するクラス | 上のリスト |

## `check` が表示するもの {#what-check-prints}

[通常の行]({{< relref "/authnd/check.md" >}})に加えて四種類の行があり、起動時のログにも同じものが出ます。

- **`schema: <file> adds …`** と **`schema: the schema block at <file>:<line>:<column> adds …`**:
  各ファイルと各ブロックが追加したもの。オブジェクト識別子マクロ、属性型、オブジェクトクラスとして数えられる
- **`<file>:<line>:<column>: users "sql" declares … for its people`** (`user` や `group`
  ブロックでは `user "ann" declares … for this person`、`group "staff" declares … for this group`):
  各ソースが宣言するもの
- **`<name> is published without <class>, which its source declares: …`**:
  その人に足りない MUST を示す
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`**:
  グループについて二つのソースが食い違っている状態で、そのままなら黙ったままになる

クラスが足りないために破棄された属性は、[エントリ]({{< relref "/authnd/entries.md" >}})がすでに
説明している `is published without <attribute>: no class of the entry allows it; <classes> would`
の行です。宣言がある場合、この行はあなたがまだ宣言していないクラスを挙げます。

## DIT コンテンツルール、ネームフォーム、DIT 構造ルール {#rules}

v0.13.0 から、`schema_files` と `schema { }` ブロックは、RFC 4512 §4.1.6 と §4.1.7 がクラスと属性に
加える三種類の定義も受け付け、authnd はそれらを**適用します** (go-authn/ldap v0.11.0 がそれらを
読み、構築し、検査します。方法は[ライブラリのページ]({{< relref "/libraries/ldap.md#rules" >}})に
あります)。

| 定義 | RFC 4512 | 何を述べるか | authnd がそれをどうするか |
|---|---|---|---|
| DIT コンテンツルール | §4.1.6 | 一つの構造クラスについて、どの補助クラス (`AUX`) を加えてよいか、どの属性が必須 (`MUST`)、許可 (`MAY`)、排除 (`NOT`) か | **各エントリの形を定める** (データ) |
| ネームフォーム | §4.1.7.2 | 構造クラスのエントリが、どの属性名 (RDN) で名付けられるか | **木を保つ** (設定) |
| DIT 構造ルール | §4.1.7.1 | ネームフォームをどこに置けるか: その `SUP` が指すルールが支配するエントリの下 | **木を保つ** (設定) |

これらは、あるときに**限って** `cn=Subschema` で公開されます (`dITContentRules`、`nameForms`、
`dITStructureRules`)。なければ、このページのことは何も当てはまらず、v0.12.4 から何も変わりません。

{{< callout type="info" >}}
**同じ例示用アーク**

以下の `rules.schema` は、上の `example.schema` と同様に、このページのために書いたもので、
`1.3.6.1.4.1.99999` の下にあります。自分のアークを使ってください。コンテンツルールの OID と
`inetOrgPerson` の OID は、定義上同じです。コンテンツルールは、それが対象とする構造クラスの
名前で呼ばれます。
{{< /callout >}}

### 一種類ずつ含むスキーマと、その HCL {#rules-example}

OpenLDAP の `.schema` 形式です。`ditcontentrule` は slapd.conf(5) のディレクティブです。
`nameform` と `ditstructurerule` は go-authn/ldap のもので、slapd にはありません
([後述](#rules-slapd))。authnd は、公開する木 (サフィックス、`ou=people`、`ou=groups`、
その下のアカウント、人々、グループ) も検査するので、ファイルには一種類ずつではなく、
五つのネームフォームと五つの構造ルールがあります。

```
# Rules for the tree authnd publishes. 1.3.6.1.4.1.99999 is an example arc:
# nobody is assigned it, use your own.

# A content rule belongs to a structural class and takes that class's OID.
# inetOrgPerson (2.16.840.1.113730.3.2.2): posixAccount and uidObject may be
# added, ldapPublicKey may not; telephoneNumber is required; description is
# precluded.
ditcontentrule ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule'
	AUX ( posixAccount $ uidObject )
	MUST telephoneNumber
	NOT description )

# A name form says which attribute names an entry of a structural class.
nameform ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameform ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameform ( 1.3.6.1.4.1.99999.9.3 NAME 'exampleAccountForm' OC account MUST uid )
nameform ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )
nameform ( 1.3.6.1.4.1.99999.9.5 NAME 'examplePosixGroupForm' OC posixGroup MUST cn )

# A structure rule gives a name form a place: the rule ID is a number, SUP
# names the rule of the parent entry.
ditstructurerule ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
ditstructurerule ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
ditstructurerule ( 3 NAME 'exampleAccounts' FORM exampleAccountForm SUP 2 )
ditstructurerule ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
ditstructurerule ( 5 NAME 'examplePosixGroups' FORM examplePosixGroupForm SUP 2 )
```

同じ定義を、`ldapschema` v0.11.0 が書いたとおりに HCL で示します
(`ldapschema to-hcl rules.schema`)。各ブロックが一つの定義で、最初の NAME をラベルにします。
構造ルールには `id`、それが配置する `form`、その下に置かれる `sup` ルールがあります。

```hcl
dit_content_rule "examplePersonRule" {
  oid  = "2.16.840.1.113730.3.2.2"
  aux  = ["posixAccount", "uidObject"]
  must = ["telephoneNumber"]
  not  = ["description"]
}

name_form "exampleDomainForm" {
  oid  = "1.3.6.1.4.1.99999.9.1"
  oc   = "domain"
  must = ["dc"]
}

name_form "exampleUnitForm" {
  oid  = "1.3.6.1.4.1.99999.9.2"
  oc   = "organizationalUnit"
  must = ["ou"]
}

name_form "exampleAccountForm" {
  oid  = "1.3.6.1.4.1.99999.9.3"
  oc   = "account"
  must = ["uid"]
}

name_form "examplePersonForm" {
  oid  = "1.3.6.1.4.1.99999.9.4"
  oc   = "inetOrgPerson"
  must = ["uid"]
}

name_form "examplePosixGroupForm" {
  oid  = "1.3.6.1.4.1.99999.9.5"
  oc   = "posixGroup"
  must = ["cn"]
}

dit_structure_rule "exampleSuffix" {
  id   = 1
  form = "exampleDomainForm"
}

dit_structure_rule "exampleUnit" {
  id   = 2
  form = "exampleUnitForm"
  sup  = [1]
}

dit_structure_rule "exampleAccounts" {
  id   = 3
  form = "exampleAccountForm"
  sup  = [2]
}

dit_structure_rule "examplePersons" {
  id   = 4
  form = "examplePersonForm"
  sup  = [2]
}

dit_structure_rule "examplePosixGroups" {
  id   = 5
  form = "examplePosixGroupForm"
  sup  = [2]
}
```

これが `schema { }` ブロックの中身で、そのまま入れられます。`.schema` ファイルは
`schema_files` が受け取るものです。`ldapschema to-schema rules.hcl` はそれを同じ定義の
`.schema` ファイルに戻し、`ldapschema check` はそれを標準スキーマの上に構築します。

```
$ ldapschema check etc/authnd/rules.schema
read: 0 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 5 name forms, 5 DIT structure rules
build: ok, 11 definitions added to schema.Standard()
```

### コンテンツルールがエントリに何をするか {#content-rules}

設定は二人の人と二つのグループで、ルールは `schema_files` から読み込まれます。**dave** は `sn` を
持ち (したがって `inetOrgPerson`)、電話番号、description、SSH 公開鍵があります。**erin** は `sn`
だけです。**staff** は `gidNumber` を持ち、**team** は持ちません。

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

schema_files = ["etc/authnd/rules.schema"]

user "dave" {
  password        = "dave-password"
  authorized_keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl dave@example.org"]
  attributes = {
    sn              = "Dumont"
    telephoneNumber = "+33 1 23 45 67 89"
    description     = "on call"
  }
}

user "erin" {
  password   = "erin-password"
  attributes = { sn = "Evans" }
}

group "staff" {
  members    = ["dave"]
  attributes = { gidNumber = "100" }
}

group "team" { members = ["dave"] }
```

ルールはエントリの**構造クラス**に適用され、何をするかは、起動時と `check` で、エントリごとに
次のように伝えられます。

| ルールの内容 | エントリ | 伝えられ方 |
|---|---|---|
| `AUX` が補助クラスを挙げていない。宣言されたものでも、authnd が導出するもの (`posixAccount`、`ldapPublicKey`、`sambaSamAccount`、`uidObject`) でも同じ | そのクラスは**外され**、それだけが許していた属性も外される (さらにそのクラスのために authnd が加える `sshPublicKey`、`sambaSID`、`sambaNTPassword` も)。上位クラスが外された宣言済みクラスも一緒に外れる | `<name> is published without <class>: the DIT content rule <rule> does not allow it (not in its AUX)` |
| `NOT` が属性を挙げている | その属性は、誰が与えたものであれ**破棄される** | `<name> is published without <attribute>: the DIT content rule <rule> precludes it (NOT)` |
| `MUST` が挙げる属性がエントリにない | エントリは**公開されない**。ルールはエントリ全体に適用され、クラスを外しても有効にはできない | `<name> is NOT published: … <attribute> is required by the DIT content rule <rule> and is missing (RFC 4512 4.1.6)` |

構造クラスにコンテンツルールがなければ、エントリの補助クラスは、slapd が許すのと同じく許可されます
([後述](#rules-slapd))。

```
$ authnd check etc/authnd/authnd.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules

USER  FROM                    CAN PROVE             PUBLISHED AS                                            WITH
dave  the configuration file  a password and 1 key  person, organizationalPerson, inetOrgPerson, uidObject  uid, cn, sn and telephoneNumber
erin  the configuration file  a password            NOT PUBLISHED (see below)                               uid, cn and sn

GROUP  MEMBERS  PUBLISHED AS
staff  dave     posixGroup
team   dave     NOT PUBLISHED (see below)

dave has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
dave is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
dave is published without description: the DIT content rule examplePersonRule precludes it (NOT)
erin has no uidNumber, gidNumber or homeDirectory: not a posixAccount, and as person, organizationalPerson, inetOrgPerson, uidObject the entry fails the schema (below)
erin is NOT published: as person, organizationalPerson, inetOrgPerson, uidObject it fails the schema:
  - telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
group team is NOT published: as groupOfNames it fails the schema:
  - no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

サーバーは起動し、そのログには、DN 付きで同じ三種類の行が出ます。

```
$ authnd --config etc/authnd/authnd.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules
uid=erin,ou=people,dc=example,dc=org is NOT published: it fails the schema: telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
cn=team,ou=groups,dc=example,dc=org is NOT published: it fails the schema: no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)
uid=dave,ou=people,dc=example,dc=org is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
uid=dave,ou=people,dc=example,dc=org is published without description: the DIT content rule examplePersonRule precludes it (NOT)
```

OpenLDAP の `ldapsearch` が `cn=Subschema` で読む、ルールが公開される三つの属性です。

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b cn=Subschema -s base '(objectClass=subschema)' dITContentRules nameForms dITStructureRules
dn: cn=Subschema
dITContentRules: ( 2.16.840.1.113730.3.2.2 NAME 'examplePersonRule' AUX ( posixAccount $ uidObject ) MUST telephoneNumber NOT description )
nameForms: ( 1.3.6.1.4.1.99999.9.1 NAME 'exampleDomainForm' OC domain MUST dc )
nameForms: ( 1.3.6.1.4.1.99999.9.2 NAME 'exampleUnitForm' OC organizationalUnit MUST ou )
nameForms: ( 1.3.6.1.4.1.99999.9.3 NAME 'exampleAccountForm' OC account MUST uid )
nameForms: ( 1.3.6.1.4.1.99999.9.4 NAME 'examplePersonForm' OC inetOrgPerson MUST uid )
nameForms: ( 1.3.6.1.4.1.99999.9.5 NAME 'examplePosixGroupForm' OC posixGroup MUST cn )
dITStructureRules: ( 1 NAME 'exampleSuffix' FORM exampleDomainForm )
dITStructureRules: ( 2 NAME 'exampleUnit' FORM exampleUnitForm SUP 1 )
dITStructureRules: ( 3 NAME 'exampleAccounts' FORM exampleAccountForm SUP 2 )
dITStructureRules: ( 4 NAME 'examplePersons' FORM examplePersonForm SUP 2 )
dITStructureRules: ( 5 NAME 'examplePosixGroups' FORM examplePosixGroupForm SUP 2 )
```

そして木を、ルールが触れるものについて尋ねます。まず、`schema_files` を**使わない**同じ設定
(対照です。以下の違いはすべてルールによるものです)、次にそれを使う場合です。

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(|(uid=*)(cn=*))' dn objectClass description sshPublicKey
dn: uid=dave,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: ldapPublicKey
objectClass: uidObject
description: on call
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl dave@example.org

dn: uid=erin,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject

dn: cn=staff,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup

dn: cn=team,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
```

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(|(uid=*)(cn=*))' dn objectClass description sshPublicKey
dn: uid=dave,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: uidObject

dn: cn=staff,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
```

dave は `ldapPublicKey` を失い、それとともに `sshPublicKey` も失いました (`AUX` にない)。
`description` も失いました (`NOT`)。erin はいなくなりました (`MUST telephoneNumber`)。
**team** もです。`gidNumber` がないので `groupOfNames` ですが、`ou=groups` の下に `groupOfNames` を
置く構造ルールがありません。この最後のものは、木のルールがデータに適用されたもので、
次の節で説明します。

### 構造ルールが木に何をするか {#structure-rules}

DIT 構造ルールが**少なくとも一つ有効**であれば、authnd は公開する木を、起動時と `check` で歩きます。

- **サフィックス** (`base_dn`)。その RDN が指すクラスを与えます。`dc` は `domain`、`o` は
  `organization`、`ou` は `organizationalUnit`、`c` は `country`、`l` は `locality` です。
  それ以外の属性で名付けられたサフィックスは拒否されます。
- `ou=people` と `ou=groups`。`organizationalUnit` として。
- authnd が人々 (`uid`) とグループ (`cn`) を名付けるのに使う RDN 属性。

どのルールも配置しないコンテナー、どのルールにもネームフォームがない種類のサフィックス、`uid` や
`cn` を拒むネームフォーム、authnd が公開するものを何も置けなくなるコンテナーは、**起動を拒否し、
`check` も失敗させます**。拒否はすべて一度に、DN、ルールまたはネームフォーム、条項を挙げて示され、
シークレットは決してそのまま出力されません。構造クラスがデータ (`sn`、`gidNumber`) に依存し、
そのコンテナーの下にルールがない人やグループは、代わりに**外されてそう伝えられ**ます。上の team の
ようにで、サーバーは起動します。有効な構造ルールがなければ、何も変わりません。

人々のための唯一の構造ルール `peopleByCN` が、`cn` を求めるネームフォーム
(`accountByCN`: `OC account MUST cn`) を配置するスキーマです。

```
$ authnd check cases/bad.hcl
authnd: DIT structure rules: authnd names its people uid=<name>,ou=people,dc=example,dc=org, and an account named so is refused: the RDN (uid) is allowed by the name form of no DIT structure rule that places account under an entry governed by the rule 2: accountByCN needs cn
```

authnd は人々を `uid=<name>` と名付けます。ルールはそれを許さなければなりません。そして
`organizationalUnit` のルールに `SUP` がなく、`organizationalUnit` が根にしか置けないスキーマでは、
`ou=people` も `ou=groups` も居場所がなくなり、両方が一度に伝えられます。

```
$ authnd check cases/root.hcl
authnd: DIT structure rules: ou=people,dc=example,dc=org, where authnd publishes its people, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
DIT structure rules: ou=groups,dc=example,dc=org, where authnd publishes its groups, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
```

どちらも終了ステータス 1 で終わります。その背後のファイル (`cases/bad.schema` と
`cases/root.schema`) には、同じ五つのネームフォームと、論点を示す構造ルールだけがあります。

### authnd と slapd の違い {#rules-slapd}

go-authn/ldap は OpenLDAP のファイルを読み、ルールの一部は OpenLDAP のものです。
違いは、見つけさせるのではなく、ここに書いておきます。

- **slapd が実装するのはコンテンツルールだけです。** ネームフォームや構造ルールのディレクティブは
  ありません。`Format` は `nameform` と `ditstructurerule` のキーワードを書きますが、これは
  このライブラリのもので、slapd は拒否します。それらは HCL に置くか、authnd だけが読むファイルに
  置いてください。`ditcontentrule` は slapd のものです。
- **`OBSOLETE` のルールは無効です** (RFC 4512 §4.1.6)。そのネームフォームや構造ルールも同様です。
  slapd はそのエントリを代わりに拒否します。
- **コンテンツルールがなければ、補助クラスは許可されます。** これは slapd の動作
  (`SLAP_DISALLOW_AUX_WO_CR` フラグはどの `disallow` キーワードでも設定されません) で、authnd も
  同じです。RFC 4512 §2.4.3 は別のことを述べており、ライブラリは `ValidateOptions{StrictAuxiliary:
  true}` としてそれを提供しますが、authnd は設定しません。
- **libldap は構造ルールの `SUP` を読めません。** `SUP` のある構造ルールはここでは読まれ、
  libldap では読まれないので、libldap がそのようなファイルを拒否しても、ファイルの評決では
  ありません。
- ルールを**再定義する**ファイルは、一語一句同じでも、他のすべての定義と同様に拒否されます
  ([上記](#redefinition))。

### コスト {#rules-cost}

2026-10-26 に `BenchmarkPublish10k` (go-authn/authnd、`rules_bench_test.go`) で計測しました。
10,000 人を公開すると、`testdata/rules.schema` のルールありでは**エントリごとに 416 回の割り当て**、
なしでは **265 回**です。これには、排除された description の破棄と再検証が含まれます。時間は
192 ms 対 118 ms で、負荷 8〜14 で計測したため、比率としては信頼できません。信頼できるのは
割り当て回数だけです。

### アップグレード {#rules-upgrade}

ルールのないスキーマでは何も変わりません。v0.12.4 は三種類とも拒否していたので、それで起動した
設定にはルールがありません。例外が一つあります。**有効な UTF-8 でない** `schema { }` の文字列
(HCL が通してしまう冗長なエンコーディング) は v0.12.4 では起動しましたが、今は拒否されます。
書かれたとおりには公開できないからです。

## 実例としての SUPANN {#supann}

SUPANN はフランスの高等教育・研究の属性セットです (`supannPerson`、`supannEtablissement`、
`supannEntite`…)。その横に eduPerson があります。RENATER は技術スキーマを他のものとともに
ドキュメントのページで公開しています。

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**ファイルはそこからダウンロードしてください。** このサイトには転載しません。ライセンスが
明記されていないのでこのページはコピーせず、RENATER が改訂すればここにあるコピーは古くなる
からです。それから:

```sh
sudo install -o root -g authnd -m 0640 supann.schema eduperson.ldif /etc/authnd/
```

```hcl
schema_files = ["/etc/authnd/supann.schema", "/etc/authnd/eduperson.ldif"]

users "sql" {
  # ...
  users_attributes     = "select login, sn, etab as \"supannEtablissement\" from staff"
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}
```

`authnd check` を実行し、まず `schema:` の行を読んでください。slapd が読み込むファイルはここでも
読み込まれ、標準の定義を再定義するファイルは行を示して拒否されます。次に *published without*
の行を読んでください。`supannPerson` や `eduPerson` の MUST が足りない人は、そのクラスなしで
公開され、`check` はその MUST を挙げます。綴りが重要な場合はエイリアスを引用符で囲んでください
(PostgreSQL は引用符のないものを小文字にします。
[エントリ]({{< relref "/authnd/entries.md#in-a-sql-database" >}})を参照)。

{{< callout type="info" >}}
**トランスクリプトについて**

このページのコマンドはすべて、2026-10-26 に v0.12.3 のリリースバイナリ (`authnd-darwin-arm64`、`SHA256SUMS` と照合済み、`go version -m`: `go1.27.3`、`mod github.com/go-authn/authnd v0.12.3`、`vcs.modified=false`) と OpenLDAP の `ldapsearch` で、127.0.0.1 上の作業用ディレクトリに、示したファイルを置いて再実行したものです。パスが相対なのはそのためで、サービスでは絶対パスを使います。スキーマはこのページのために書いた例です。

[DIT コンテンツルール、ネームフォーム、DIT 構造ルール](#rules)の節は、2026-10-26 に v0.13.0 のリリースバイナリ (`authnd-darwin-arm64`、`relverify` で `SHA256SUMS` とその証明 (attestation) を照合済み、`go version -m`: `go1.27.3`、`mod github.com/go-authn/authnd v0.13.0`、`authnd --version`: `authnd version v0.13.0`)、OpenLDAP の `ldapsearch`、go-authn/ldap v0.11.0 のタグからビルドした `ldapschema` (`go install`、go1.27.1。リリースバイナリはありません) で実行しました。そこにあるすべての出力はそれらのプログラムが作業用ディレクトリで 127.0.0.1 上に出力したもので、トランスクリプトの背後のファイルは、そばに示してあるか説明してあります。
{{< /callout >}}
