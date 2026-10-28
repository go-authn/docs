---
title: "站点模式，以及来源声明的类"
linkTitle: "站点模式"
weight: 27
description: "提供 SUPANN、eduPerson 或站点自己的属性：schema_files 和 schema 块添加定义，object_classes 声明某个来源的人员和组所带的辅助类，check 则说明哪些被丢弃。从 v0.13.0 起，DIT 内容规则、名称形式和 DIT 结构规则会被强制执行。"
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

## DIT 内容规则、名称形式和 DIT 结构规则 {#rules}

从 v0.13.0 起，`schema_files` 和 `schema { }` 块还接受 RFC 4512 §4.1.6 和 §4.1.7
为类和属性所增加的三类定义，并且 authnd **强制执行**它们（go-authn/ldap v0.11.0
读取、构建并检查它们；[库页面]({{< relref "/libraries/ldap.md#rules" >}})
说明了方式）：

| 定义 | RFC 4512 | 它说明什么 | authnd 如何处理 |
|---|---|---|---|
| DIT 内容规则 | §4.1.6 | 针对一个结构类：可以添加哪些辅助类（`AUX`），哪些属性是必需的（`MUST`）、允许的（`MAY`）或被排除的（`NOT`） | **为每个条目塑形**（数据） |
| 名称形式 | §4.1.7.2 | 某个结构类的条目由哪些属性命名（RDN） | **约束树**（配置） |
| DIT 结构规则 | §4.1.7.1 | 名称形式可以放在哪里：在由其 `SUP` 所指名的规则所管辖的条目之下 | **约束树**（配置） |

它们**只有在存在时**才会在 `cn=Subschema` 发布（`dITContentRules`、`nameForms`、
`dITStructureRules`）。没有时，此页面的内容都不适用，与 v0.12.4 相比
也没有任何变化。

{{< callout type="info" >}}
**同一个示例弧**

下面的 `rules.schema` 与上面的 `example.schema` 一样，是为此页面编写的，
位于 `1.3.6.1.4.1.99999` 之下。请使用你自己的弧。内容规则的 OID 与
`inetOrgPerson` 的 OID 按定义是相同的：内容规则以它所针对的结构类命名。
{{< /callout >}}

### 每类各一条的模式，及其 HCL {#rules-example}

采用 OpenLDAP 的 `.schema` 形式。`ditcontentrule` 是 slapd.conf(5) 的指令；
`nameform` 和 `ditstructurerule` 是 go-authn/ldap 的，因为 slapd 没有它们
（[见下文](#rules-slapd)）。authnd 还会检查它所发布的树
（后缀、`ou=people`、`ou=groups`，以及其下的账户、人员和组），
因此该文件包含五个名称形式和五条结构规则，而不是每类各一个：

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

同样的定义用 HCL 写出，即 `ldapschema` v0.11.0 所写的形式
（`ldapschema to-hcl rules.schema`）。每个块是一个定义，以其第一个 NAME 作标签；
结构规则有 `id`、它所放置的 `form`，以及它位于其下的 `sup` 规则：

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

这就是 `schema { }` 块内部的内容，原样不变；`.schema` 文件则是
`schema_files` 所接受的。`ldapschema to-schema rules.hcl` 把它转回
定义相同的 `.schema` 文件，而 `ldapschema check` 在标准模式之上构建它：

```
$ ldapschema check etc/authnd/rules.schema
read: 0 object identifiers, 0 syntaxes, 0 matching rules, 0 attribute types, 0 object classes
read: 1 DIT content rules, 5 name forms, 5 DIT structure rules
build: ok, 11 definitions added to schema.Standard()
```

### 内容规则对条目做了什么 {#content-rules}

配置是两个人员和两个组，规则从 `schema_files` 加载。**dave** 有 `sn`
（因此他是 `inetOrgPerson`）、电话号码、描述和一个 SSH 公钥；**erin** 有 `sn`，
别无其他；**staff** 有 `gidNumber`；**team** 没有：

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

规则适用于条目的**结构类**，它做了什么，会在启动时以及由 `check` 逐个条目说明：

| 规则说 | 条目 | 表述为 |
|---|---|---|
| `AUX` 没有列出某个辅助类，无论是已声明的还是 authnd 派生的（`posixAccount`、`ldapPublicKey`、`sambaSamAccount`、`uidObject`） | 该类被**去掉**，连同只有它才允许的属性（以及 authnd 为它添加的 `sshPublicKey`、`sambaSID` 和 `sambaNTPassword`）；其超类被去掉的已声明类随之去掉 | `<name> is published without <class>: the DIT content rule <rule> does not allow it (not in its AUX)` |
| `NOT` 指名某个属性 | 该属性被**丢弃**，无论由谁提供 | `<name> is published without <attribute>: the DIT content rule <rule> precludes it (NOT)` |
| `MUST` 指名条目所缺少的属性 | 该条目被**排除在外**：规则适用于整个条目，没有哪个类可以去掉而使它有效 | `<name> is NOT published: … <attribute> is required by the DIT content rule <rule> and is missing (RFC 4512 4.1.6)` |

结构类没有内容规则的条目，其辅助类是允许的，
与 slapd 允许它们一样（[见下文](#rules-slapd)）。

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

服务器启动，其日志带有同样三类行，只是带有 DN：

```
$ authnd --config etc/authnd/authnd.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
schema: etc/authnd/rules.schema adds 1 DIT content rule, 5 name forms and 5 DIT structure rules
uid=erin,ou=people,dc=example,dc=org is NOT published: it fails the schema: telephoneNumber is required by the DIT content rule examplePersonRule and is missing (RFC 4512 4.1.6)
cn=team,ou=groups,dc=example,dc=org is NOT published: it fails the schema: no active DIT structure rule has a name form for groupOfNames (X.501 13.7.5)
uid=dave,ou=people,dc=example,dc=org is published without ldapPublicKey: the DIT content rule examplePersonRule does not allow it (not in its AUX)
uid=dave,ou=people,dc=example,dc=org is published without description: the DIT content rule examplePersonRule precludes it (NOT)
```

OpenLDAP 的 `ldapsearch` 在 `cn=Subschema` 处读到的内容，即发布规则所用的三个属性：

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

再看树，查询规则所涉及的内容。先是**没有** `schema_files` 的同一配置
（对照：下面的每一处差异都是规则造成的），然后是有它们的：

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

dave 失去了 `ldapPublicKey`，随之失去了他的 `sshPublicKey`（不在 `AUX` 中），
还有他的 `description`（`NOT`）。erin 不见了（`MUST telephoneNumber`），
**team** 也是：它没有 `gidNumber`，因此是 `groupOfNames`，而没有任何结构
规则把 `groupOfNames` 放在 `ou=groups` 之下。最后这一点是树的
规则应用于数据，下一节会加以说明。

### 结构规则对树做了什么 {#structure-rules}

只要有**至少一条有效的** DIT 结构规则，authnd 就会在启动时和 `check` 中
遍历它将要发布的树：

- **后缀**（`base_dn`），按其 RDN 所指名的类处理：`dc` 对应
  `domain`，`o` 对应 `organization`，`ou` 对应 `organizationalUnit`，`c` 对应
  `country`，`l` 对应 `locality`。以任何其他属性命名的后缀
  都会被拒绝；
- `ou=people` 和 `ou=groups`，作为 `organizationalUnit`；
- authnd 用来命名人员的 RDN 属性（`uid`）和命名组的 RDN 属性（`cn`）。

没有规则放置的容器、没有任何规则有名称形式与之对应的那种后缀、
拒绝 `uid` 或 `cn` 的名称形式，或者其下无法放置 authnd 所发布的任何内容的容器，
都会**拒绝启动，也使 `check` 失败**：每一项拒绝一并给出，指明 DN、规则或名称形式
以及子句，并且绝不回显机密。结构类取决于其数据（`sn`、
`gidNumber`）且其容器之下没有规则的人员或组，则会**被排除在外并加以说明**，
如上面的 team：服务器照常启动。没有有效的结构规则时，
一切不变。

一个模式，其人员唯一的结构规则 `peopleByCN` 放置了一个需要 `cn` 的
名称形式（`accountByCN`：`OC account MUST cn`）：

```
$ authnd check cases/bad.hcl
authnd: DIT structure rules: authnd names its people uid=<name>,ou=people,dc=example,dc=org, and an account named so is refused: the RDN (uid) is allowed by the name form of no DIT structure rule that places account under an entry governed by the rule 2: accountByCN needs cn
```

authnd 以 `uid=<name>` 命名其人员：规则必须允许这一点。再看一个
模式，其 `organizationalUnit` 的规则没有 `SUP`，因此
`organizationalUnit` 只能位于根部，于是 `ou=people` 和
`ou=groups` 都没有位置，并且两者一并给出：

```
$ authnd check cases/root.hcl
authnd: DIT structure rules: ou=people,dc=example,dc=org, where authnd publishes its people, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
DIT structure rules: ou=groups,dc=example,dc=org, where authnd publishes its groups, as an organizationalUnit: no DIT structure rule allows organizationalUnit under an entry governed by the rule suffix (X.501 13.7.5)
```

两者都以状态 1 退出。它们背后的文件（`cases/bad.schema` 和
`cases/root.schema`）包含相同的五个名称形式，以及只用于说明问题的
结构规则。

### authnd 与 slapd 的不同之处 {#rules-slapd}

go-authn/ldap 读取 OpenLDAP 的文件，其中有些规则是 OpenLDAP 的。
这些是不同之处，是明确说明的，而不是事后发现的：

- **slapd 只实现内容规则。** 它没有用于名称形式或结构规则的指令。
  `Format` 写出 `nameform` 和 `ditstructurerule`
  关键字，它们是本库的，slapd 会拒绝它们：请把这些保留在
  HCL 中，或只由 authnd 读取的文件中。`ditcontentrule` 是 slapd 的。
- **`OBSOLETE` 规则无效**（RFC 4512 §4.1.6），其名称形式
  或结构规则也是如此。slapd 反而会拒绝该条目。
- **没有内容规则时，允许辅助类。** 这是 slapd 的
  行为（它的 `SLAP_DISALLOW_AUX_WO_CR` 标志不会被任何 `disallow`
  关键字设置），也是 authnd 的行为。RFC 4512 §2.4.3 的说法相反；本库把它
  提供为 `ValidateOptions{StrictAuxiliary: true}`，而 authnd 并未设置它。
- **libldap 无法读取结构规则的 `SUP`。** 带 `SUP` 的结构规则
  在这里可以读取，libldap 则不行，因此 libldap 拒绝这样的文件
  并不是对该文件的裁决。
- **重新定义**某条规则的文件会被拒绝，即使逐字相同，与其他
  所有定义一样（[见上文](#redefinition)）。

### 它的代价 {#rules-cost}

于 2026-10-28 在内嵌 go-authn/ldap v0.11.1 的 authnd v0.13.1 上，用 `BenchmarkPublish10k`（go-authn/authnd，
`rules_bench_test.go`，`-cpu 1`）测得：发布 10,000 个人员，使用 `testdata/rules.schema` 的规则时
**每个条目 364 次分配**，不使用时为 **239** 次（v0.13.0：416 和 265 次），
一次运行使用规则时占用 102.5 MiB，不使用时占用 65.4 MiB（v0.13.0：147.5 和 88.0）。
这包括丢弃被排除的描述并再次验证。耗时
约为 157 ms 对 100 ms（v0.13.0：194 ms 对 123 ms），是在负载 10 到 16 时测得的，其比值不可信；
只有分配次数可信。

### 升级 {#rules-upgrade}

没有规则的模式不会有任何变化：v0.12.4 拒绝这三类定义，因此在它上面
启动过的配置不含任何规则。有一个例外。**不是有效 UTF-8** 的
`schema { }` 字符串（HCL 放行的一种过长编码）曾在 v0.12.4 上启动，
现在会被拒绝，因为它无法按所写的内容发布。

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

[DIT 内容规则、名称形式和 DIT 结构规则](#rules)一节于 2026-10-26 用 v0.13.0 发布的二进制文件运行（`authnd-darwin-arm64`，由 `relverify` 对照 `SHA256SUMS` 及其证明核对；`go version -m`：`go1.27.3`，`mod github.com/go-authn/authnd v0.13.0`；`authnd --version`：`authnd version v0.13.0`）、OpenLDAP 的 `ldapsearch`，以及从 go-authn/ldap v0.11.0 标签构建的 `ldapschema`（`go install`，go1.27.1；它没有发布的二进制文件）。那里的每一项输出都由这些程序打印，在临时目录中、127.0.0.1 上；记录背后的文件在旁边给出或加以描述。
{{< /callout >}}
