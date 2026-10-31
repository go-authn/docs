---
title: "人员从哪里来"
linkTitle: "人员"
weight: 20
description: "user 和 group 块、SQL 数据库、另一个 LDAP 目录：各自如何编写、查询它们的顺序，以及每种方式允许人员做什么。"
tags: [authnd, 配置, sql, ldap]
---

对于小型站点，`user` 块就是整个目录；对于大型站点，则是它不放进数据库的服务
账户。人员已经存在于数据库或 LDAP 中的站点，不应把他们复制到另一个
会逐渐过时的地方，因此 `users` 块直接从他们所在之处读取。`users` 块是
go-authn/directory 的 `hcldir`，与
[go-fileshare](https://github.com/go-fileshare/fileshare) 所读取的相同：
同一个目录对两者的描述方式是一致的。

## 在配置中编写 {#written-in-the-configuration}

```hcl
user "alice" { password_file = "/etc/authnd/passwords/alice.pw" }

user "carol" {
  nt_hash         = "…"                                   # MD4(UTF16LE(password)), 32 hex
  authorized_keys = ["ssh-ed25519 AAAA… carol@laptop"]    # published as sshPublicKey
}

group "staff" { members = ["alice", "carol"] }
```

| 字段 | 含义 |
|---|---|
| `password` | 密码，内联写入 |
| `password_file` | 同上，从文件读取（去除前后空白） |
| `nt_hash` | `MD4(UTF16LE(password))`，32 个十六进制字符——适用于持有它而没有密码的站点 |
| `totp_secret` | base32 一次性代码密钥，至少 128 位；参见[第二因素]({{< relref "/authnd/mfa.md" >}}) |
| `authorized_keys` | `authorized_keys` 各行，发布为 `sshPublicKey` |
| `authorized_keys_file` | 同上，来自文件 |
| `attributes` | 自 v0.11.0 起，描述人员但不证明任何事的内容——`sn`、`uidNumber`、`gidNumber`、`homeDirectory`、`mail`……——以字符串或字符串列表的映射表示；`group` 块也接受它。它们决定条目发布为什么：参见[条目]({{< relref "/authnd/entries.md#adding-attributes" >}}) |
| `object_classes` | 自 v0.12.0 起，该人员（在 `group` 块中则是该组）发布时所带的辅助类，例如 `["siteMember"]`：声明出来，从不推断，并在[站点模式]({{< relref "/authnd/schemas.md#object-classes" >}})中定义 |

启动时被拒绝，并指名相关人员：

- 同时有 `password` 和 `password_file`——请指明用哪一个；
- 同时有 `password` 和 `nt_hash`——哈希由密码派生，
  因此两者可能不一致；
- 同时有 `authorized_keys` 和 `authorized_keys_file`；
- 不是 32 个十六进制字符的 `nt_hash`、无法解析的 `authorized_keys` 行、
  不足 128 位的 `totp_secret`；
- 重复的 `user` 或 `group`，以及没有成员的 `group`。

没有任何来源认识的组成员同样会被拒绝，这样可以在笔误
悄悄地什么权限也不授予之前就将其发现：

```
$ authnd check cases/typo.hcl
authnd: group "staff" has "alise" in it, who is not in the configuration file
```

{{< callout type="warning" >}}
**仅有 `nt_hash` 无法绑定**

只写有 `nt_hash` 的人员会被发布，可以通过 `sambaNTPassword` 交给 SMB
服务器，但**无法绑定到 authnd 本身**：LDAP 简单绑定发送的是
密码，而 NT 哈希在这里并不能用来校验密码。下面的 bob 只有 NT 哈希，
而该哈希正是所发送密码的哈希：

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=bob,ou=people,dc=example,dc=org -y bob.pwin
ldap_bind: Invalid credentials (49)
```

`check` 会在表格之后说明这一点：

```
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
```

**为什么按设计拒绝。** NT 哈希是 `MD4(UTF16LE(password))`，
不加盐且计算很快（MS-NLMP §3.3.1，NTOWFv1）。接受它来校验 LDAP 绑定
会扩大泄露的哈希所能打开的范围，从 SMB 扩大到所有通过 authnd
绑定的应用程序。Kerberos 出于相关的原因拒绝这些人员：NT 哈希
是 RC4-HMAC 密钥（RFC 4757 §2），而该域只签发 AES。这是
有意的决定，而不是缺失的功能，也没有更改它的选项。

**应当怎么做。** 从只保存 NT 哈希的目录（Samba、导出的 AD）迁移时，
请在每个人员的来源中为其提供真正的密码或密码校验：
重置密码，或使用 `users "ldap"` 来源，由其
上游目录自行校验密码。不要把 NT 哈希作为唯一的
凭据保留。
{{< /callout >}}

## 在 SQL 数据库中 {#in-a-sql-database}

```hcl
users "sql" {
  driver   = "postgres"                      # or mysql (mariadb), or sqlite
  dsn_file = "/etc/authnd/pg.dsn"            # required: a DSN may hold a password
  users    = "select login, secret, nt_hash from staff"   # required
  groups   = "select team, member from team_members"      # optional
}
```

**查询由你自己编写**，因为站点的人员已经按该站点的
形态存放。`users` 查询的列**按位置**读取：先是名称，
然后依次是密码、NT 哈希、SSH 密钥（每行一个）和
一次性代码密钥中的任意几项——最多五列。NULL 表示
此人没有该凭据。密码列按其存储的原样比较：
authnd 没有针对哈希列的设置。`groups` 查询返回
组名和成员，每个成员关系一行。

另有两个可选查询，**按列别名**而不是按位置读取属性：
`users_attributes`（名称，然后每个属性一列）和
`groups_attributes`（组，然后同样）。不带引号的别名会被
PostgreSQL 转为小写。参见[条目]({{< relref "/authnd/entries.md#in-a-sql-database" >}})。

**`users` 块所给出之人员的类**，声明在其查询旁边
（自 v0.12.0 起，`users "ldap"` 块中也是同样的两个键）：

```hcl
users "sql" {
  # ...
  object_classes       = ["supannPerson", "eduPerson"]   # every person this block gives
  group_object_classes = ["supannGroupe"]                # every group
}
```

每个类都必须是所提供的模式（标准模式，或
[`schema_files` 和 `schema` 块]({{< relref "/authnd/schemas.md" >}})）所定义的
AUXILIARY 类，并且不能是 authnd 自行派生的类。缺少已声明类的某个 MUST 的人员，
发布时不带该类，`check` 会说明这一点。

`driver` 接受 `postgres`（或 `postgresql`、`pgx`）、`mysql`（或 `mariadb`）
和 `sqlite`（或 `sqlite3`）。数据库在启动时、任何监听之前就会被访问，
因此没有应答的数据库会在有人关注的时候使服务器停止：

```
$ authnd check cases/nodb
authnd: users "sql": the postgres database is not answering: failed to connect to `user=authnd database=authnd`:
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
	127.0.0.1:1 (127.0.0.1): dial error: dial tcp 127.0.0.1:1: connect: connection refused
```

同一台机器上的 PostgreSQL 通过其套接字和对等认证，
DSN 中无需密码：`host=/run/postgresql dbname=authnd user=authnd`。
状态目录中的 SQLite：`file:/var/lib/authnd/people.db`。

属于另一种块的键会被拒绝而不是被忽略：

```
$ authnd check cases/sqlwrongkey.hcl
authnd: users "sql" has base_dn in it, which belongs to an ldap block
```

## 在另一个 LDAP 目录中 {#in-another-ldap-directory}

```hcl
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/authnd/upstream.pw"
}
```

`url` 和 `base_dn` 是必需的。人员和组位于何处，以及
哪些属性为它们命名：

| 键 | 默认值 |
|---|---|
| `user_filter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))` |
| `user_attribute` | `uid` |
| `group_base_dn` | `base_dn` |
| `group_filter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))` |
| `group_attribute` | `cn` |
| `group_member_attribute` | 无：`memberUid`（名称）**和** `member`（DN）；设置后，只读取这一个属性 |
| `totp_attribute` | 无：没有标准属性，而猜测的结果是读不到任何内容，却看起来像是已经读过了 |
| `attributes`、`group_attributes` | 无：从每个人员的条目和每个组的条目中复制的属性，例如 `["mail", "uidNumber", "homeDirectory"]` 和 `["gidNumber"]`（[条目]({{< relref "/authnd/entries.md#adding-attributes" >}})） |
| `object_classes`、`group_object_classes` | 无：自 v0.12.0 起，从该目录读取的每个人员和每个组所带的辅助类（[站点模式]({{< relref "/authnd/schemas.md#object-classes" >}})）；上游条目所带的类从不复制 |
| `start_tls` | `false` |

`member` DN 只有在它是人员搜索所返回的条目的 DN 时才算数：
这些条目之外的 DN，或指名无人的 DN，都映射到无人，并且
名称绝不会从 DN 中读出。`sambaNTPassword` 和 `sshPublicKey` 按这些名称
读取。

{{< callout type="warning" >}}
**自 v0.11.0 起，默认值会读取机构目录中更多的内容**

该块属于 go-authn/directory，而 authnd
v0.11.0 内嵌的 directory v0.14.0 放宽了其默认值：直到 v0.10.2，`user_filter` 为
`(objectClass=posixAccount)`，`group_filter` 为 `(objectClass=posixGroup)`，
`group_member_attribute` 为 `memberUid`。持有并非 posixAccount 的
`account` 或 `uidObject` 条目的目录——服务账户、以 uid
命名的主机、从别处导入的人员——现在会把它们交给 authnd，
每一个都可以通过绑定来校验；其 `groupOfNames` 组在这里也会成为组。
若要完全保留旧的集合，请写下旧的值：

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

在打开任何内容之前，有两件事会被拒绝：

```
$ authnd check cases/ldap-clear.hcl
authnd: users "ldap" would send every password to "ldap.example.org" in the clear: use ldaps://, or start_tls = true (RFC 4513 §5.1.3)

$ authnd check cases/ldap-cred.hcl
authnd: users "ldap" has credentials in its url, and a url is printed: use bind_dn with bind_password_file
```

指向环回地址的 `ldap://` 和 `ldapi://` 会被接受：途中
没有任何人。

位于此服务之后的目录是通过绑定到它来**校验**密码的；它
不会把密码交出来。这里一个 authnd 在另一个之前提供服务，使用不同的 base；
后面的那个就是 [`check`]({{< relref "/authnd/check.md#a-configuration-that-can-be-served" >}})
的示例，在 3893 上提供服务：

```hcl
listen  = "127.0.0.1:3894"
base_dn = "dc=example,dc=net"

users "ldap" {
  url                = "ldap://127.0.0.1:3893"
  base_dn            = "ou=people,dc=example,dc=org"
  group_base_dn      = "ou=groups,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "etc/authnd/reader.pw"
}

user "svc-backup" { password_file = "etc/authnd/svc-backup.pw" }
```

```
$ authnd check front2
ldap://127.0.0.1:3894, base dc=example,dc=net

USER        FROM                    CAN PROVE         PUBLISHED AS        WITH
alice       ldap://127.0.0.1:3893   a password check  account, uidObject  uid
bob         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
dora        ldap://127.0.0.1:3893   a password check  account, uidObject  uid
eli         ldap://127.0.0.1:3893   a password check  account, uidObject  uid
svc-backup  the configuration file  a password        account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
svc-backup has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

其后目录所发布的每个人员都是 `account`，每个组
都是 `groupOfNames`，因为它们都没有 POSIX 属性：默认值会读取它们，
而组的 `member` DN 映射到所导入的人员。若使用直到 v0.10.2 的默认值，
`(objectClass=posixAccount)` 一个也匹配不到。

*密码校验*足以用于绑定，却永远不足以用于
[Kerberos 票据]({{< relref "/authnd/kerberos.md#who-can-be-issued-a-ticket" >}})
或 SMB。

## 顺序，以及唯一的例外 {#order-and-the-one-exception}

各个来源**按编写的顺序**被查询，第一个
认识某个名称的来源拥有它。`user` 块始终排在最前，因此本地
写下的服务账户不会被数据库中的同名人员覆盖。**组成员关系是**
所有来源的**并集**：`group` 块和数据库的 `groups` 查询
都指名的组，拥有两者的成员。

{{< callout type="warning" >}}
**仅大小写不同的两个名称会被拒绝**

uid 的比较忽略大小写（RFC 4519 §2.39），每个 DN 也是如此，因此
文件中的 `Dora` 和数据库中的 `dora` 对 LDAP 来说是同一个名称，对任何
按字节比较的程序来说却是两个人——其中一人更改密码会落到
另一人身上。这样的配置无法启动：

```
$ authnd check cases/case.hcl
authnd: "Dora" (from the configuration file) and "dora" (from a sqlite database) differ only by case, and an LDAP name does not tell them apart: a uid is compared ignoring case. Rename one of them
```
{{< /callout >}}

## 启动时读取，之后每次刷新再读 {#read-once}

每个来源都**在启动时读取，之后每个 `refresh` 再读取一次**。添加到数据库或从数据库中移除的人员，
或此服务之后目录中更改的成员关系，无需重启，在一个周期内即会生效。这包括数据库中的密码列：它
与该行一起读取。此服务之后的目录的不同之处仅在于，
绑定是通过绑定到它来校验的，因此在*那里*更改的密码
才是有效的。人员通过
authnd 本身更改的密码会[立即生效]({{< relref "/authnd/passwords.md" >}})。
刷新失败时会保留最近一份良好的数据，何时停止提供则由 `max_age` 决定；参见[运行]({{< relref "/authnd/operations.md" >}})。
配置文件、证书和 keytab 仍然需要重启。
