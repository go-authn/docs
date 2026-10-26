---
title: "サイトスキーマと、ソースが宣言するクラス"
linkTitle: "サイトスキーマ"
weight: 27
description: "SUPANN、eduPerson、またはサイト独自の属性を提供する: schema_files と schema ブロックが定義を追加し、object_classes がソースの人々とグループが持つ補助クラスを宣言し、check が何が外されたかを伝えます。"
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
{{< /callout >}}
