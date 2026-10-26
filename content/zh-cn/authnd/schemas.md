---
title: "站点模式，以及来源声明的类"
linkTitle: "站点模式"
weight: 27
description: "提供 SUPANN、eduPerson 或站点自己的属性：schema_files 和 schema 块添加定义，object_classes 声明某个来源的人员和组所带的辅助类，check 则说明哪些被丢弃。"
tags: [authnd, ldap, 模式, 配置]
---

**除非条目的某个类允许，否则 SUPANN 或 eduPerson 属性会被丢弃。**
authnd 只发布它所提供的模式允许的内容（参见
[条目]({{< relref "/authnd/entries.md#what-is-dropped-and-what-is-withheld" >}})），
而标准模式对 `supannEtablissement` 或
`eduPersonAffiliation` 一无所知。自 v0.12.0 起，站点按以下顺序说明三件事：

1. **要添加哪些定义**：`schema_files`，即其 slapd 已经加载的文件，
   以及用于纯本地内容的 `schema { }` 块；
2. **其人员和组带哪些辅助类**：`object_classes`；
3. 仅此而已。类是**声明出来的，从不推断**：数据库中出现某个
   属性，不会改变条目发布为什么。

{{< callout type="info" >}}
**本页的示例只是示例**

下面的 `example.schema` 是为本页编写的。它的 OID 位于
`1.3.6.1.4.1.99999` 之下，这是一个没有分配给任何人的弧：请使用你自己的，
切勿照抄这些。关于 SUPANN，请参见[本页末尾](#supann)。
{{< /callout >}}

## 一个示例：模式、数据库、配置 {#an-example}

一份 OpenLDAP `.schema` 形式的模式：一个来源可以声明的类
（`exampleStaff`，AUXILIARY，带一个 MUST），和一个不能声明的类
（`exampleUnit`，STRUCTURAL）。

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

一个包含三个人的 SQLite 数据库，带有 `sn`、工牌和员工编号
（`sqlite3 var/people.db < people.sql`）：

```sql
create table staff (login text primary key, secret text);
create table person_attrs (login text primary key, sn text, badge text, empid text, locker text);
insert into staff values ('ann', 'ann-password'), ('ben', 'ben-password'), ('cat', 'cat-password');
insert into person_attrs values ('ann', 'Archer', 'B-0001', 'E-1001', 'L-12'), ('ben', 'Brook', 'B-0002', null, null), ('cat', 'Cole', null, 'E-1003', null);
```

以及配置：

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

没有 `object_classes` 这一行时，`check` 会说明单靠标准模式对同样的人员做了什么：
这些属性被丢弃，每一行都指明了本可以保留它的类。

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

`schema_files` 是 OpenLDAP `.schema` 文件或 cn=config LDIF 文件的列表。
它们按**发布时的原样**，依次加载到标准模式之上（如果有
[`samba` 块]({{< relref "/authnd/tls.md#the-samba-block" >}})，还有 Samba 的三个定义），
由 go-authn/ldap 的 [slapd 兼容读取器]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})处理：
支持任意的项顺序、slapd 和 RFC 2849 的续行、base64、`{N}` 长度
前缀，以及 `objectidentifier` 宏——一个文件可以定义，下一个文件可以
使用，如同跨越 slapd 的 `include`。事先不做任何转换，所以
站点的 slapd 加载的文件，就是 authnd 加载的文件。这些定义由
`cn=Subschema` 提供。

- 相对路径相对于工作目录，与配置中的其他每个路径一样。在服务中请使用绝对路径：
  systemd 单元的工作目录是 `/`。
- 每个文件必须是不超过 4 MiB 的普通文件，并且只在启动时读取
  一次。
- 这些文件决定每个条目可以包含什么。它们不是机密，但请与
  配置的其余部分放在一起：`root:authnd`，权限 `0640`，位于
  只有 root 可写的目录中（[安装]({{< relref "/authnd/install.md" >}})）。
- 无法构建的文件会使启动以及 `check` 被拒绝，并给出文件、行
  和定义起始的列，信息末尾是拒绝的类型：未知的父类、属性、
  匹配规则或语法（`unknown reference`），由辅助类派生的结构类
  （`kind violation`），重复定义的 OID 或名称（`duplicate OID`、
  `duplicate name`）。自 v0.12.1 起，位置和类型来自 go-authn/ldap 的类型化
  [`*schema.BuildError`]({{< relref "/libraries/ldap.md#build-error" >}})，而不是
  通过解析它的错误信息。从文件读取的定义从第 1 列开始，
  即使其文本折叠成多行也一样。重复定义会指出它的第一个定义在哪里，
  重新定义则会指出原件在哪个标准文件，或更早文件的哪一行。两个示例：

  `cases/unknown.schema` 有一个在任何地方都未定义的 MAY：

  ```
  # exampleB has a MAY that is defined nowhere.
  objectclass ( 1.3.6.1.4.1.99999.2.9 NAME 'exampleB' SUP top AUXILIARY
  	MAY noSuchAttribute )
  ```

  ```
  $ authnd check cases/unknown.hcl
  authnd: schema_files: cases/unknown.schema:2:1: the object class exampleB has MAY noSuchAttribute, which is not a defined attribute type (unknown reference)
  ```

  `cases/twice.schema` 给两个属性类型赋予同一个 OID：

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

### 重新定义会被拒绝，即使完全相同 {#redefinition}

文件不得定义已经存在的内容：标准模式的
定义、Samba 的定义，或更早的文件的定义。**即使逐字相同**也会被拒绝，
这正是 slapd 自己的规则：模式文件的定义要经过
`parse_at` 和 `parse_oc`，对于已被索引的 OID 或名称，slapd 会回答
*Duplicate attributeType*（OID 和名称都相同）或 *Inconsistent duplicate
attributeType*（`servers/slapd/at.c`、`oc.c`）。只有 slapd 自己硬编码的
模式才允许前一种情形。slapd 拒绝的文件，authnd 也拒绝。

另一种解读则必须挑出一个胜者，而这会悄悄改变
每个客户端被告知的某个标准属性的内容；拒绝则会指出具体的行。
拒绝信息会说明文本是否相同。下面是一个用自己的定义
重新定义 `cn`（2.5.4.3）的文件：

```
$ authnd check cases/dup.hcl
authnd: schema_files: cases/cn-copy.schema:1:1: the attribute type cn (2.5.4.3) is already defined by the standard schema (rfc4519.schema:42:1), and this is a different definition: a schema file adds definitions and never replaces one -- slapd refuses this too ("Duplicate attributeType", servers/slapd/at.c and oc.c). Remove it from this file
```

## `schema { }` 块 {#the-schema-block}

对于纯本地的定义，`schema` 块以 HCL2 保存它们，
采用 [hclschema 的形态]({{< relref "/libraries/ldap.md#hcl2-and-the-converter" >}})：
`attribute_type`、`object_class`、`object_identifier`、`matching_rule` 和
`ldap_syntax`。它在文件**之后**读取，因此可以使用文件中的
定义，并且可以有多个。

值必须是**字面量**：不能有变量、函数，也不能有 `${...}` 或
`%{...}`。该块由读取 `.hcl` 模式文件的同一个解码器解码，
使用相同的界限，每个错误都会指明配置自己的
行和列。不是 HCL 原生语法的块会被拒绝。

## `object_classes` {#object-classes}

模式中的定义允许某个属性；它并不会把类加到任何人身上。来源**声明**
其人员和组发布时所带的辅助类：

| 位置 | 键 | 它声明什么 |
|---|---|---|
| `users` 块，任意种类 | `object_classes` | 该块给出的每个人员的类 |
| `users` 块，任意种类 | `group_object_classes` | 每个组的类 |
| `user` 块 | `object_classes` | 该人员的类 |
| `group` 块 | `object_classes` | 该组的类 |

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]
  group_object_classes = ["supannGroupe"]
}

user  "alice" { object_classes = ["siteMember"] }
group "staff" { object_classes = ["supannGroupe"] }
```

这些键属于 go-authn/directory，自 v0.15.0 起
（[库]({{< relref "/libraries/directory.md#object-classes" >}})）。名称
比较时忽略大小写，并且只保留一次，按书写顺序。

authnd 如何处理已声明的类：

- **它连同其父类一起发布**，排在 authnd 派生的类之后
  （RFC 4512 §3.3：所指名的类的全部父类都被隐式
  加入）。该类允许的属性会被保留，而不是丢弃。
- **它从不推断。** 来源不声明任何类的人员，无论数据库中保存了什么，
  都会继续失去其所有类都不允许的属性。
- **缺少已声明类的某个 MUST 的人员，发布时不带该类。**
  其属性像任何没有类允许的属性一样被丢弃，两者都会被报告。这就是
  authnd 处处遵循的规则：人员仍然发布，问题被说明，
  不会悄悄改变任何东西。扣留该人员，会使其因为缺少一个属性而从每次搜索中消失；
  而发布不带 MUST 的类，则会提供一个不通过所提供模式检查的
  条目。
- **两个来源可以为同一个组声明不同的类。** 第一个为某个组声明类的
  来源整体决定，后面的列表会被忽略：既不合并也不报错。`check` 会说明这一点。

这里 ann 一应俱全，cat 没有储物柜（一个 MAY），而 ben 没有
`exampleEmployeeId`，它是 `exampleStaff` 的 MUST：

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

启动日志带有同样的行，只是使用 DN：

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

以及 OpenLDAP 的 `ldapsearch` 读回的内容，读取器的密码放在
文件中。ann 带有两个辅助类，以及它们允许的每个属性；ben
只带 `exampleLockerHolder`，他的工牌随 `exampleStaff` 一起消失了；
cat 两个类都带，并带有她的员工编号：

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

## 什么会被拒绝，以及原因 {#what-is-refused}

已声明的类会在启动时由 `check` 对照所提供的模式进行检查。
它必须是：

- **已定义的**，由标准模式、文件或块定义；
- **AUXILIARY**（RFC 4512 §4.1.1）。一个条目恰好有一条结构链
  （§2.4.2），由 authnd 根据此人所具有的内容选择；声明
  不能再添加第二条；
- **不是 authnd 自行派生的类**：`account`、`inetOrgPerson` 及其
  父类、`posixAccount`、`posixGroup`、`ldapPublicKey`、`uidObject`、
  `sambaSamAccount`、`groupOfNames` 和 `organizationalRole`，无论用其
  哪个名称。这些类取决于人员或组所具有的内容，而声明
  不能推翻 `check`。

否则启动会被拒绝，并指明块、其位置和类。
`exampleUnit` 是 STRUCTURAL：

```
$ authnd check cases/structural.hcl
authnd: cases/structural.hcl:10:20: users "sql" object_classes: exampleUnit is STRUCTURAL, and an entry has exactly one structural chain (RFC 4512 §2.4.2), which authnd chooses: only an AUXILIARY class (§4.1.1) can be declared
```

go-authn/directory 会在此之前检查**拼写**：类是
描述符，绝不是 OID、空格、引号或括号。

同样被拒绝的，出于同样保持模式诚实的理由：

| 被拒绝的 | 原因 |
|---|---|
| 重新定义某个定义的文件，即使逐字相同 | slapd 的规则：[见上文](#redefinition) |
| 不是普通文件，或超过 4 MiB 的文件 | FIFO 会阻塞启动，`/dev/zero` 永远不会结束 |
| 含有变量、函数或 `${...}` 的 `schema` 块 | 只允许字面值，与 `.hcl` 模式文件相同 |
| `object_classes` 中未定义的类 | 一个无法检验的承诺 |
| STRUCTURAL 类，或 authnd 派生的类 | 上面的列表 |

## `check` 会输出什么 {#what-check-prints}

四类行，附加在[通常的那些]({{< relref "/authnd/check.md" >}})之上；启动日志带有同样的行：

- **`schema: <file> adds …`** 和 **`schema: the schema block at <file>:<line>:<column> adds …`**：
  每个文件和每个块添加了什么，按对象标识符
  宏、属性类型和对象类计数；
- **`<file>:<line>:<column>: users "sql" declares … for its people`**（
  `user` 或 `group` 块则说 `user "ann" declares … for this person` 和
  `group "staff" declares … for this group`）：每个来源声明了什么；
- **`<name> is published without <class>, which its source declares: …`**，
  指明此人缺少的 MUST；
- **`group staff: the configuration file declares supannGroupe and a postgres
  database declares eduMember; the first is published and the second is
  ignored (the first source that declares classes for a group decides)`**：
  两个来源对某个组存在分歧，否则这会悄无声息。

因缺少类而被丢弃的属性，就是
[条目]({{< relref "/authnd/entries.md" >}})已经描述过的
`is published without <attribute>: no class of the entry allows it; <classes> would` 这些行：
有了声明之后，它们指明的是你尚未声明的类。

## SUPANN，作为真实的示例 {#supann}

SUPANN 是法国高等教育与研究领域的属性集
（`supannPerson`、`supannEtablissement`、`supannEntite`……），旁边还有 eduPerson。
RENATER 在其文档页面上与其他模式一起发布了技术模式：

<https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann>

**请从那里下载文件。** 本站不转载它：它没有声明
许可证，所以本页不复制它，而且 RENATER 修订之后，这里的副本会
过时。然后：

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

运行 `authnd check`，先读 `schema:` 这些行：slapd
能加载的文件，在这里也能加载，而重新定义标准定义的文件会被拒绝，
并给出其所在行。然后读 *published without* 这些行：缺少
`supannPerson` 或 `eduPerson` 的某个 MUST 的人员，发布时不带该类，
`check` 会指明该 MUST。当别名的拼写很重要时，请给它加引号
（PostgreSQL 会把不带引号的别名转为小写；参见
[条目]({{< relref "/authnd/entries.md#in-a-sql-database" >}})）。

{{< callout type="info" >}}
**关于这些记录**

此页面上的每条命令都已于 2026-10-26 重新运行，使用 v0.12.3 发布的二进制文件（`authnd-darwin-arm64`，已对照 `SHA256SUMS` 核对；`go version -m`：`go1.27.3`，`mod github.com/go-authn/authnd v0.12.3`，`vcs.modified=false`）和 OpenLDAP 的 `ldapsearch`，在 127.0.0.1 上、一个临时目录中，并使用所示的文件。路径因此是相对的；服务使用绝对路径。该模式是为此页面编写的示例。
{{< /callout >}}
