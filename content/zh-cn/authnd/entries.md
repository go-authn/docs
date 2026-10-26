---
title: "authnd 发布的条目，以及它提供的模式"
linkTitle: "条目与模式"
weight: 25
description: "每个人员和组发布为什么、每个条目都要通过的 cn=Subschema 处所提供的模式、如何在文件或 SQL 查询中添加属性，以及哪些被丢弃或扣留。"
tags: [authnd, ldap, 模式, sql]
---

**authnd 发布的每个条目都要通过它所提供的模式。** 从 v0.11.0 起，
每个人员和组都是标准模式条目，由其来源所提供的内容构建，并在被搜索返回之前，
用 go-authn/ldap 的 `schema.Validate` 对照客户端可以在 `cn=Subschema` 读取的模式
进行检查。读取该模式并信任它的客户端——LDAP 浏览器、
同步工具、复制此目录的目录——看到的就是它被告知的内容。直到 v0.10.2，
每个人员都是 `top, person, posixAccount`，却没有这些类所要求的
任何属性，而且 `sambaNTPassword` 位于
没有任何类允许它的条目上。

{{< callout type="warning" >}}
**按 `posixAccount` 或 `posixGroup` 过滤的使用方看到的条目会变少**

没有 `uidNumber`、`gidNumber` 和 `homeDirectory` 的人员不再是
`posixAccount`，没有 `gidNumber` 的组也不再是
`posixGroup`。搜索 `(objectClass=posixAccount)` 或
`(objectClass=posixGroup)` 的程序不再能找到它们。这包括
直到 v0.13.0 的 go-authn/directory 的 `ldapdir`，因此也包括 go-fileshare，直到它
要求 directory v0.14.0，后者的默认值还会读取 `account`、`uidObject`
和 `groupOfNames`（[directory]({{< relref "/libraries/directory.md#ldapdir-defaults" >}})）。
请为人员和组提供这些属性，或者让使用方改查
`(objectClass=uidObject)`，每个人员都带有该类。
{{< /callout >}}

## 各种形态 {#the-shapes}

按 RFC 4512 §3.3 的要求，列出了每个父类。

| 具有以下情形的人员… | `objectClass` | `cn` |
|---|---|---|
| 没有 `sn` | `top`、`account`（RFC 4524 §3.1） | 仅当另一个类允许时 |
| `sn` | `top`、`person`、`organizationalPerson`、`inetOrgPerson`（RFC 4519、RFC 2798） | 有 |
| … 以及 `uidNumber`、`gidNumber`、`homeDirectory`，三者齐备 | `+ posixAccount`（RFC 2307） | 有 |
| … 以及 SSH 密钥 | `+ ldapPublicKey`（openssh-lpk），带 `sshPublicKey` | |
| … 以及带有 `sambaSID` 的已发布 NT 哈希 | `+ sambaSamAccount`（Samba），带 `sambaSID` 和 `sambaNTPassword`：参见 [`samba` 块]({{< relref "/authnd/tls.md#the-samba-block" >}}) | 允许 |
| … 始终 | `+ uidObject`（RFC 4519 §3.14），因此 `(objectClass=uidObject)` 能找到所有人 | |

| 具有以下情形的组… | `objectClass` | 成员 |
|---|---|---|
| 有 `gidNumber` | `top`、`posixGroup`（RFC 2307） | `memberUid`，名称 |
| 没有 `gidNumber`，其中有人 | `top`、`groupOfNames`（RFC 4519 §3.5） | `member`，即本服务器发布的 DN |
| 没有 `gidNumber`，其中无人 | `top`、`organizationalRole`（RFC 4519 §3.10） | 无 |
| 有 `gidNumber`，其中无人 | `top`、`posixGroup` | 无：属性至少有一个值 |

`uid` 是人员的名称，在类允许的地方 `cn` 也是。单独的
`account` 不允许 `cn`（其 MAY 是 `description`、`seeAlso`、
`l`、`o`、`ou` 和 `host`），因此没有 `sn` 也没有 POSIX
三元组的人员带有 `uid` 而没有 `cn`。

这些选择的原因，出自 authnd 自己的理由：

- **`posixGroup` 遵循 RFC 2307，而不是 draft-howard-rfc2307bis-02。**
  该草案把 `posixGroup` 定为 AUXILIARY，并且未经发布就已过期；AUXILIARY
  的 `posixGroup` 需要旁边有一个结构类，即 `groupOfNames`，而空组
  无法提供它的 `member`。
- **没有 `gidNumber` 的空组使用 `organizationalRole`。**
  `groupOfNames` 和 `groupOfUniqueNames` 都要求有成员，而凭空
  造一个成员的办法都是错误的：`member: ""` 指向根 DSE，
  而组自己的 DN 会使它成为自己的成员。`organizationalRole` 是唯一一个
  只有 `cn` 为 MUST 的标准结构类，并且它像 `groupOfNames` 一样接受
  `description`、`ou` 和 `seeAlso`。
- **没有 DIT 内容规则的辅助类。** RFC 4512 §2.4.3 禁止在
  其结构类没有 DIT 内容规则的条目上使用辅助类。所有在用的目录服务器
  都允许这样做，`Validate` 也是如此
  （`ValidateOptions{StrictAuxiliary: true}` 是严格的解读，authnd 并未设置它）。
  结构类**有**内容规则的类，从 v0.13.0 起受该规则约束：见
  [规则]({{< relref "/authnd/schemas.md#rules" >}})。

## 添加属性 {#adding-attributes}

来源对某人所说的、不证明任何事的内容——`uidNumber`、
主目录、邮件地址——是**属性**，按原样发布。
它们是 go-authn/directory 从 v0.13.0 起的[属性]({{< relref "/libraries/directory.md#attributes" >}})，
并且与凭据分开存放：保存机密的名称，或服务器自行派生的名称，
会在读取任何内容之前被拒绝。

### 在 `user` 或 `group` 块中 {#in-a-user-or-group-block}

```hcl
user "dora" {
  password_file   = "/etc/authnd/passwords/dora.pw"
  authorized_keys = ["ssh-ed25519 AAAA… dora@laptop"]
  attributes = {
    sn            = "Explorer"          # inetOrgPerson
    uidNumber     = "1000"              # the three: posixAccount
    gidNumber     = "1000"
    homeDirectory = "/home/dora"
    mail          = ["dora@example.org", "d.explorer@example.org"]
  }
}

group "engineers" {
  members    = ["dora", "eli"]
  attributes = { gidNumber = "2000" }   # a posixGroup; without it, a groupOfNames
}
```

值是字符串或字符串列表；`null` 表示不包含该属性。
数字会被拒绝，因为 LDAP 的值是字符串，authnd 不会
决定数字的写法：

```
$ authnd check cases/number.hcl
authnd: user "alice": attributes: uidNumber is the number 1000: write it as a string, "1000" -- an LDAP value is a string, and this does not choose how a number is spelled

$ authnd check cases/secret.hcl
authnd: user "alice": attributes: directory: not an attribute this package carries: "userPassword" holds a secret, and attributes are published: a credential has its own option or none
```

以同样方式被拒绝的还有（无论大小写）：任何保存机密的名称
（`userPassword`、`sambaNTPassword`、`unicodePwd`、`krbPrincipalKey` 以及
go-authn/directory 列表中的其余名称，或任何包含 `password`、
`passwd`、`pwd`、`secret`、`credential`、`hash` 或 `privatekey` 的名称）；
`sshPublicKey`，它有 `authorized_keys`；`uid`、`cn` 和 `objectClass`，
由服务器派生；`member`、`memberUid` 以及其他成员关系
属性，由 `members` 负责；服务器维护的操作属性；
以及数字形式的名称（`2.5.4.35` 即 `userPassword`）。

### 在 SQL 数据库中 {#in-a-sql-database}

`users "sql"` 块的两个可选查询**按列别名**读取属性。第一列是
人员或组的名称；其他每一列都是以其别名命名的属性：

```hcl
users "sql" {
  driver   = "sqlite"
  dsn_file = "/etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

- 按位置的 `users` 和 `groups` 查询不变，第六个
  位置列仍然被拒绝：属性按名称提供，使用它们自己的
  查询。
- 别名不是属性描述的列（没有别名的
  表达式，如 `count(*)`），或指名了凭据的列，会在读取任何行之前连同其
  列号一起被拒绝。
- `NULL` 和 `''` 视为不存在。一个名称可以出现在多行中，并且
  所有行的值都会保留，因此与地址表连接会
  使一个人员得到多个值。
- 只在 `groups_attributes` 中出现名称的组**存在**，其中无人：
  人员自己的主组就是这样写的。

{{< callout type="warning" >}}
**别名的大小写由数据库决定**

PostgreSQL 会把不带引号的别名折叠为小写：`as uidNumber` 返回的
是 `uidnumber`。属性名称不区分大小写，因此对每个 LDAP 客户端来说
它是同一个属性、同一个条目，但 authnd 输出的写法是数据库的写法。
需要在意写法时，请给别名加引号：`gid as "gidNumber"`。SQLite 保留别名的原样。
{{< /callout >}}

### 来自另一个 LDAP 目录 {#from-another-ldap-directory}

`users "ldap"` 块会从每个人员和每个组的条目中复制它被告知要复制的属性：
`attributes = ["mail", "uidNumber",
"homeDirectory"]` 以及 `group_attributes = ["gidNumber"]`。参见
[人员]({{< relref "/authnd/people.md#in-another-ldap-directory" >}})。

## 一份配置，以及它发布什么 {#a-configuration-and-what-it-publishes}

上面的 SQL 块，加上一个 reader，位于一个包含五个人员和
四个组的 SQLite 数据库之上，由 v0.11.0 发布的二进制文件检查：

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

users "sql" {
  driver   = "sqlite"
  dsn_file = "etc/authnd/people.dsn"
  users    = "select login, secret, null, ssh_keys from staff"
  groups   = "select team, member from teams"
  users_attributes  = "select login, sn, uid as uidNumber, gid as gidNumber, home as homeDirectory, mail from person_attrs"
  groups_attributes = "select team, gid as gidNumber, description from team_attrs"
}
```

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER  FROM               CAN PROVE             PUBLISHED AS                                                                         WITH
dora  a sqlite database  a password and 1 key  person, organizationalPerson, inetOrgPerson, posixAccount, ldapPublicKey, uidObject  uid, cn, sn, uidNumber, gidNumber, homeDirectory, mail and sshPublicKey
eli   a sqlite database  a password            account, posixAccount, uidObject                                                     uid, cn, uidNumber, gidNumber and homeDirectory
fay   a sqlite database  a password            person, organizationalPerson, inetOrgPerson, uidObject                               uid, cn, sn and mail
gus   a sqlite database  a password            account, uidObject                                                                   uid
hal   a sqlite database  a password            account, uidObject                                                                   uid

GROUP       MEMBERS       PUBLISHED AS
alumni      nobody        organizationalRole
engineers   dora and eli  posixGroup
nobody-yet  nobody        posixGroup
readers     fay and gus   groupOfNames

fay has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as person, organizationalPerson, inetOrgPerson, uidObject
gus has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
hal has no homeDirectory: not a posixAccount, published as account, uidObject
hal is published without uidNumber: no class of the entry allows it; posixAccount would
hal is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
hal is published without mail: no class of the entry allows it; inetOrgPerson would
group alumni has no gidNumber and nobody in it: not a posixGroup, published as an organizationalRole (a groupOfNames needs a member)
group readers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

`PUBLISHED AS` 是每个条目的对象类（不含 `top`），`WITH` 是其
属性，取自搜索所返回的条目。hal 有 `uidNumber`、
`gidNumber` 和 `mail`，却没有 `homeDirectory` 或 `sn`：hal 是 `account`，
它不允许这三者中的任何一个，因此它们被丢弃，其余内容
照常发布。服务器在启动时也会说同样的话（被
停止时则输出 `stopping`）：

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 5 people from a sqlite database
uid=hal,ou=people,dc=example,dc=org is published without uidNumber: no class of the entry allows it; posixAccount would
uid=hal,ou=people,dc=example,dc=org is published without gidNumber: no class of the entry allows it; posixAccount and posixGroup would
uid=hal,ou=people,dc=example,dc=org is published without mail: no class of the entry allows it; inetOrgPerson would

stopping
```

由 OpenLDAP 的 `ldapsearch` 读回，reader 的密码保存在文件中：

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(|(uid=dora)(uid=eli)(uid=gus)(uid=hal))'
dn: uid=dora,ou=people,dc=example,dc=org
objectClass: top
objectClass: person
objectClass: organizationalPerson
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: ldapPublicKey
objectClass: uidObject
uid: dora
cn: dora
sn: Explorer
uidNumber: 1000
gidNumber: 1000
homeDirectory: /home/dora
mail: dora@example.org
sshPublicKey: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKTfVR7FqXWE/0VEcjrUhK+Fz/MLqlwGPIxalr6onRMn dora@laptop

dn: uid=eli,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: uidObject
uid: eli
cn: eli
uidNumber: 1001
gidNumber: 1001
homeDirectory: /home/eli

dn: uid=gus,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: gus

dn: uid=hal,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: uidObject
uid: hal

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=groups,dc=example,dc=org '(objectClass=*)'
dn: cn=alumni,ou=groups,dc=example,dc=org
objectClass: top
objectClass: organizationalRole
cn: alumni
description: people who were here

dn: cn=engineers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: engineers
gidNumber: 2000
memberUid: dora
memberUid: eli

dn: cn=nobody-yet,ou=groups,dc=example,dc=org
objectClass: top
objectClass: posixGroup
cn: nobody-yet
gidNumber: 2001

dn: cn=readers,ou=groups,dc=example,dc=org
objectClass: top
objectClass: groupOfNames
cn: readers
description: people who read
member: uid=fay,ou=people,dc=example,dc=org
member: uid=gus,ou=people,dc=example,dc=org
```

`alumni` 只在 `groups_attributes` 中出现名称，因此它存在而其中无人；
没有 `gidNumber`，它就是 `organizationalRole`。`nobody-yet` 有
`gidNumber` 而无人，因此它是不带 `memberUid` 的 `posixGroup`。

哪个类能找到谁：

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=uidObject)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org

dn: uid=fay,ou=people,dc=example,dc=org

dn: uid=gus,ou=people,dc=example,dc=org

dn: uid=hal,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(objectClass=posixAccount)' 1.1
dn: uid=dora,ou=people,dc=example,dc=org

dn: uid=eli,ou=people,dc=example,dc=org
```

## 哪些被丢弃，哪些被扣留 {#what-is-dropped-and-what-is-withheld}

| 给出的内容 | 条目 | 原因 |
|---|---|---|
| `uidNumber`、`gidNumber`，没有 `homeDirectory`，没有 `sn` | `account, uidObject`，不含这两者 | *no class of the entry allows it; posixAccount would* |
| `mail`，没有 `sn` | `account, uidObject`，不含它 | *no class of the entry allows it; inetOrgPerson would* |
| 模式未定义的类型 | 其余部分 | *the schema served here does not define it* |
| 没有 `gidNumber` 的组上的 `mail` | `groupOfNames`，不含它 | |
| 带有 POSIX 三元组的两个 `homeDirectory` 值 | **扣留**：SINGLE-VALUE，没有可丢弃的内容 | |
| 不是整数的 `gidNumber` | **扣留**：不符合其语法 | |

**只有来源所提供的内容才会被丢弃**，而哪个属性不被允许
是 `Validate` 的答案，而不是对模式的第二次解读。丢弃之后，条目会
再次验证。仍然失败的条目会被**扣留**：
它不出现在任何搜索中，启动日志会指名它，而 `check` 会
列出它以及 `Validate` 发现的每个问题。如果 authnd 自己派生的属性
（`uid`、`cn`、`objectClass`、`sshPublicKey`、`sambaSID`、`sambaNTPassword`）
被模式拒绝，那就是 authnd 的缺陷，并且它会扣留该条目，
而不是在缺少该属性的情况下发布它。

这里 alice 的 `gidNumber` 是一个单词：

```hcl
listen  = "127.0.0.1:3893"
base_dn = "dc=example,dc=org"

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes = {
    uidNumber     = "1000"
    gidNumber     = "staff"
    homeDirectory = "/home/alice"
  }
}

user "bob" { password_file = "etc/authnd/bob.pw" }
```

```
$ authnd check cases/withheld.hcl
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS               WITH
alice  the configuration file  a password  NOT PUBLISHED (see below)  uid, cn, gidNumber, homeDirectory and uidNumber
bob    the configuration file  a password  account, uidObject         uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
alice is NOT published: as account, posixAccount, uidObject it fails the schema:
  - the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

投入服务后，alice 仍然可以绑定，但不会出现在任何搜索中，服务器会在
启动时说明原因：

```
$ authnd --config cases/withheld.hcl
ldap on 127.0.0.1:3893, serving 2 people from the configuration file
uid=alice,ou=people,dc=example,dc=org is NOT published: it fails the schema: the value "staff" of gidNumber is not of its syntax 1.3.6.1.4.1.1466.115.121.1.27

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
dn:uid=alice,ou=people,dc=example,dc=org

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uid=alice)'
```

被扣留的是搜索所返回的条目，而不是身份本身。

## 它提供的模式 {#the-schema-it-serves}

根 DSE 指名了它（`subschemaSubentry: cn=Subschema`，见
[根 DSE]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})），
对 `cn=Subschema` 的 base 搜索会返回它（RFC 4512 §4.2）：即
go-authn/ldap 内嵌的标准定义——RFC 4512、4517、4519、4523、
4524、2798、2307、3672 和 3045，以及 openssh-lpk——此外，在存在
[`samba` 块]({{< relref "/authnd/tls.md#the-samba-block" >}})时，还有 Samba 的
`sambaSamAccount`、`sambaSID` 和 `sambaNTPassword`。这些
定义只有在按名称或用 `+` 请求时才会发布。标记之处
已作删节：

```
$ ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -s base -b cn=Subschema '+' '*'
dn: cn=Subschema
objectClass: top
objectClass: subentry
objectClass: subschema
cn: Subschema
subtreeSpecification: {}
ldapSyntaxes: ( 1.3.6.1.4.1.1466.115.121.1.3 DESC 'Attribute Type Description' )
[...]
matchingRules: ( 2.5.13.15 NAME 'integerOrderingMatch' SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 )
[...]
attributeTypes: ( 1.3.6.1.1.1.1.0 NAME 'uidNumber' DESC 'An integer uniquely identifying a user in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
attributeTypes: ( 1.3.6.1.1.1.1.1 NAME 'gidNumber' DESC 'An integer uniquely identifying a group in an administrative domain' EQUALITY integerMatch ORDERING integerOrderingMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
[...]
objectClasses: ( 2.5.6.9 NAME 'groupOfNames' SUP top STRUCTURAL MUST ( member $ cn ) MAY ( businessCategory $ seeAlso $ owner $ ou $ o $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.3.1 NAME 'uidObject' SUP top AUXILIARY MUST uid )
objectClasses: ( 0.9.2342.19200300.100.4.5 NAME 'account' SUP top STRUCTURAL MUST uid MAY ( description $ seeAlso $ l $ o $ ou $ host ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.0 NAME 'posixAccount' DESC 'Abstraction of an account with POSIX attributes' SUP top AUXILIARY MUST ( cn $ uid $ uidNumber $ gidNumber $ homeDirectory ) MAY ( userPassword $ loginShell $ gecos $ description ) )
[...]
objectClasses: ( 1.3.6.1.1.1.2.2 NAME 'posixGroup' DESC 'Abstraction of a group of accounts' SUP top STRUCTURAL MUST ( cn $ gidNumber ) MAY ( userPassword $ memberUid $ description ) )
[...]
```

完整的条目有 327 行：49 个语法、40 个匹配规则、36 个匹配
规则用法、143 个属性类型和 52 个对象类。与 base 之下的搜索不同，
subschema 条目与根 DSE 一样会应答匿名客户端：不带 `-D` 和 `-y` 的相同查询
也返回了它。

**过滤器使用模式的匹配规则**，因此 `(uidNumber>=1000)`
按整数比较。`uidNumber` 和 `gidNumber` 带有 `ORDERING
integerOrderingMatch`，RFC 2307 并未给予它们这一点；slapd 和
draft-howard-rfc2307bis-02 给予了，go-authn/ldap 也是如此
（[它唯一的偏离]({{< relref "/libraries/ldap.md#the-schema" >}})）。
按字符串比较时，`1000` 排在 `999` 之前：

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=1000)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001

$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin -b dc=example,dc=org '(uidNumber>=999)' uidNumber
dn: uid=dora,ou=people,dc=example,dc=org
uidNumber: 1000

dn: uid=eli,ou=people,dc=example,dc=org
uidNumber: 1001
```

hal 不在其中：hal 的 `uidNumber` 被丢弃了。对没有 ORDERING 规则的属性
（如 `uid`）进行范围比较结果为 Undefined，不匹配任何内容。
