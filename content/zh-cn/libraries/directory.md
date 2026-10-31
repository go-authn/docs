---
title: "directory — 某人是谁，什么可以证明其身份"
linkTitle: "directory"
weight: 50
description: "go-authn/directory：关于人员及来源为其持有的凭据的统一模型，覆盖内存中的列表、SQL 数据库、LDAP 服务器或 HCL 配置。"
tags: [库, 目录, ldap, sql]
---

**某人是谁，什么可以证明其身份？** 一个统一的模型，覆盖保存在
内存中的列表、SQL 数据库、LDAP 服务器，或配置文件中的 `user` 和 `group`
块——其要点在于这个问题的后半部分。

```sh
go get github.com/go-authn/directory@v0.16.0
```

## 证明某人的依据并不单一 {#what-proves-somebody-is-not-one-thing}

这是协议的事实。NTLMv2（SMB）是质询-应答：客户端
从不发送密码，因此服务器必须持有密码或
`MD4(UTF16LE(password))`——即 NT 哈希——而 **LDAP 绑定无法
认证 SMB 会话**。KDC 必须用人员的密钥*解密*，因此
只有持有密码的来源才能支撑一个域。SSH 需要公钥。
第二因素需要那六位数字背后的密钥。

所以 `Identity` 会说明其来源给出了哪些 `Credential`——`Password`、
`NTHash`、`Verifier`（哈希比较或绑定）、`PublicKeys`、
`TOTPSecret`——而 `Identity.Can` 使服务器能够在有人于挂载时碰壁之前
就说出*你可以使用 WebDAV 而不能使用 SMB*。每种协议有自己的
方法：

| | 回答 | 来源 |
|---|---|---|
| `Verify(password)` | 任何被交给密码的程序 | 首先是来源的验证器（可能是 LDAP 绑定），否则是所持有的密码，在 SHA-256 摘要上做常量时间比较，因此连长度都不会泄露 |
| `NTKey()` | NTLMv2 | 发布的哈希，或由密码派生；两者皆无则为 `ErrNoCredential` |
| `Derive(f)`、`KerberosKey(f)` | KDC、AWS SigV4——任何必须*拥有*该秘密的程序 | 仅限密码；派生由调用方的函数完成 |
| `Keys()` | SSH | `authorized_keys` 各行 |
| `TOTPSecret()` | [totp]({{< relref "/libraries/totp.md" >}}) | 一个列，或调用方指名的 LDAP 属性 |

## 各个来源 {#the-sources}

| 包 | 读取 | 导入 |
|---|---|---|
| `directory` | `Static` 列表，以及按顺序排列的来源 `Set` | 仅标准库 |
| `directory/sqldir` | 任何 `*sql.DB`，使用**你自己的**查询 | 没有驱动：由程序选择 |
| `directory/ldapdir` | LDAP 服务器 | `go-ldap/ldap/v3` |
| `directory/hcldir` | 指名数据库或 LDAP 服务器的 `users` 块，以及保存人员的 `user`/`group` 块 | `x/crypto/ssh`、`hashicorp/hcl/v2`、`zclconf/go-cty` |
| `directory/ldaptest` | 用于测试的 LDAP 服务器 | `glauth/ldap` |

在 `Set` 中，**第一个**认识某个名称的来源拥有它，因此在本地
写下的服务账户不必放进 LDAP。组成员关系是
所有来源的**并集**。来源在服务器启动时读取；密码
校验可以每次都访问来源，因为不持有秘密就无法缓存
绑定。实现了 `GroupReader` 的来源（sqldir 和 ldapdir 都实现了）会批量一次读取所有组；
随后 `Set.Frozen()` 以 `Set` 自身的合并规则，从内存中应答 `Members`、`GroupAttributes`、
`GroupObjectClasses` 和 `GroupNames`。请关闭原来的 `Set`，而不是冻结后的那个。

`hcldir` 不解码 HCL：调用方解码该块并交给它。
它导入 HCL 只是为了写入，用于 `SetPassword`。构建标签 `nosql` 和
`noldap` 会把某一种来源从 `hcldir` 中完全去掉。

## 示例 {#example}

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

持有的密码同样会使 `Can(Verifier)` 为真：它可以被比较。

{{< callout type="info" >}}
**空组也是组：`Members` 会回答它，`Expand` 会拒绝它**

自 v0.12.0 起，对于某个来源中存在但其中无人的组，`Set.Members` 返回空列表而没有错误，
因此列出组的服务器可以发布它。
`Expand` 仍然拒绝它，返回 `ErrEmptyGroup`，它不同于
`ErrNoSuchGroup`：无人拥有的组是笔误或已删除的组，空
组则是待填充的组。容忍不授予任何权限的组的调用方
会对两者都进行测试。在 v0.11.x 中，对于空组，`Set.Members` 返回 `ErrNoSuchGroup`，
而通过 `Set` 对 `@nobody` 进行 `Expand` 则输出
`[] directory: no such group: "nobody"`。
{{< /callout >}}

## 属性 {#attributes}

自 v0.13.0 起，`Identity` 可以携带**属性**：来源对某人所说的、
不证明任何事的内容——`uidNumber`、主目录、邮件
地址。它们被有意与凭据分开存放：凭据
决定谁可以登录，属性则是对所有被允许搜索的人*发布*的。
[authnd]({{< relref "/authnd/entries.md" >}})之类的服务器把
它们转换为 LDAP 条目的属性，由其模式决定
该条目是什么。

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

名称是 RFC 4512 的属性描述，比较时忽略大小写和
选项的顺序，因此 `mail` 和 `MAIL` 是同一个属性，采用首次
给出的写法；完全重复的值只保留一次。值是
字符串，不作解释：`"1000"` 之所以是 `uidNumber`，是因为
服务器的模式这样规定。空值或没有值都会被拒绝。

| 被拒绝的 | 原因 |
|---|---|
| 56 个指名的秘密——`userPassword`、`authPassword`、`userPKCS12`、`sambaNTPassword`、`sambaLMPassword`、`unicodePwd`、`krbPrincipalKey`、`krb5Key`、`ipaNTHash`、`ipatokenOTPkey`、`oathSecret`、`olcRootPW`…… | 取自 RFC 4519、RFC 3112、RFC 2798，以及 Samba、Active Directory、MIT 和 Heimdal Kerberos、FreeIPA、389-ds 和 OpenLDAP 的模式 |
| 任何包含 `password`、`passwd`、`pwd`、`secret`、`credential`、`hash` 或 `privatekey` 的名称 | 列表只了解有人读过的模式；这条规则会误伤的唯一标准名称 `secretary`（RFC 4524）是被允许的 |
| `sshPublicKey` | 它有自己的路径 `WithPublicKeys`，使 `Can(PublicKeys)` 保持为真 |
| `uid`、`userid`、`cn`、`commonName`、`objectClass` | 服务器根据发布条目所用的名称派生它们 |
| `member`、`uniqueMember`、`memberUid`、`memberOf` | 成员关系由 `Members` 回答，第二个答案会与之不一致 |
| `createTimestamp`、`modifyTimestamp`、`creatorsName`、`modifiersName`、`structuralObjectClass`、`governingStructureRule`、`subschemaSubentry`、`entryDN`、`entryUUID` | 由服务器维护；配置只能伪造它们 |
| 数字形式的名称 | 拒绝是按名称进行的，而 `2.5.4.35` *就是* `userPassword` |

`ReservedAttributes()` 返回完整列表，共 75 个名称及其原因；
`CheckAttributeName` 单独应用该规则，使配置可以在读取任何内容之前
就被拒绝。

它们的来源：

- **`hcldir`**：`user` 和 `group` 块中的 `attributes = { … }`，每个名称对应一个字符串
  或字符串列表；数字会被拒绝，并在信息中给出修正方法
  （*write it as a string, "1000"*），`null` 表示不包含该
  属性。
- **`sqldir`**：两个可选查询，`users_attributes` 和
  `groups_attributes`（`Queries.PeopleAttributes`、`GroupAttributes`），
  **按列别名**读取：第一列是名称，其他每一列都是以其别名命名的
  属性。别名不是属性
  描述的列，或指名了凭据的列，会在读取任何行之前连同其列号一起被拒绝。
  `NULL` 和 `''` 视为不存在，同一名称的多行会累加值。
  只在那里出现名称的组存在，其中无人。
  ⛔ PostgreSQL 会把不带引号的别名转为小写（`as uidNumber` 返回
  `uidnumber`）：这是同一个属性，只是采用了数据库的写法。需要在意写法时，
  请加引号，`as "uidNumber"`。
- **`ldapdir`**：`Config.Attributes` 和 `GroupAttributes`（`users "ldap"` 块中的
  `attributes` 和 `group_attributes`）指名从每个人员和每个组的条目中
  复制什么，按 RFC 4512 的等价规则匹配，并以
  配置中的写法保留。除上述列表外，它还拒绝
  `totp_attribute` 以及组的命名属性和成员属性。目录另外返回的
  子类型（`description` 的 `description;lang-fr`）
  不会被复制：请按名称请求它。

组的属性来自 `Set.GroupAttributes`，通过可选的
`GroupAttributer`：**第一个给出某属性的来源拥有它**，因此本地文件中的
`gidNumber` 会覆盖目录的，而只有目录才有的 `description`
会照常通过，并且即使另一个来源已作答，损坏的来源仍然是错误。人员的属性
随人员一起提供，来自拥有该名称的来源。

## 对象类 {#object-classes}

自 v0.15.0 起，来源可以**声明**其人员和组所带的辅助对象类，
这样 [authnd]({{< relref "/authnd/schemas.md" >}}) 之类的服务器就能发布站点模式
（SUPANN、eduPerson）。类承诺了每个条目的形态（RFC 4512
§4.1.1），因此从不根据现有属性推断，也从不从数据中读取：
不来自数据库列，也不来自上游的 `objectClass` 值。数据库中出现某个
属性，不能改变已发布的类。

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

名称按书写顺序保留，每个只出现一次，忽略大小写（`EDUPERSON`
重复了 `eduPerson`）。本包只检查**拼写**，即 RFC 4512
的描述符：数字 OID、空格、引号和括号都会被拒绝，
并且该拒绝经过模糊测试。某个类是否已定义、是否为 AUXILIARY、是否不是
服务器自行派生的类，则由服务器对照它所提供的模式来检查。

它们来自哪里：

- **`hcldir`**：任一种 `users` 块中的 `object_classes` 和
  `group_object_classes`，以及 `user` 和 `group` 块中的 `object_classes`。
  错误会带有配置中的位置。
- **`sqldir`**：`WithObjectClasses` 和 `WithGroupObjectClasses`。
- **`ldapdir`**：`Config.ObjectClasses` 和 `Config.GroupObjectClasses`。

`Identity.ObjectClasses()` 返回某个人员的列表的副本。组的类
来自 `Set.GroupObjectClasses`，通过可选的 `GroupObjectClasser`，
与 `GroupAttributer` 并列。**第一个拥有该组并声明了类的来源整体决定**：
不声明任何类的来源不参与决定，而后面来源给出的不同列表会被忽略，
既不合并也不报错。（authnd 会在 `check` 中说明这一点。）

`sqldir.ClosesDB()` 把一个数据库交给它的来源，`(*sqldir.Source).Close`
会关闭它；`hcldir.Open` 现在返回 `*sqldir.Source` 本身。

## ldapdir 的默认值 {#ldapdir-defaults}

| 设置（`users "ldap"` / `ldapdir.Config`） | 自 v0.14.0 起的默认值 | 直到 v0.13.0 |
|---|---|---|
| `user_filter` / `UserFilter` | `(\|(objectClass=posixAccount)(objectClass=account)(objectClass=uidObject))`，`ldapdir.DefaultUserFilter` | `(objectClass=posixAccount)` |
| `user_attribute` / `UserAttribute` | `uid` | 相同 |
| `group_base_dn` / `GroupBaseDN` | `base_dn` | 相同 |
| `group_filter` / `GroupFilter` | `(\|(objectClass=posixGroup)(objectClass=groupOfNames))`，`ldapdir.DefaultGroupFilter` | `(objectClass=posixGroup)` |
| `group_attribute` / `GroupAttribute` | `cn` | 相同 |
| `group_member_attribute` / `MemberAttribute` | 无：`memberUid`（名称）**和** `member`（DN）；设置后，只读取这一个属性 | `memberUid` |

这三个类是携带 `uid` 的标准类：`posixAccount`
（RFC 2307）、`account`（RFC 4524 §3.1）和 `uidObject`（RFC 4519 §3.14）。
自 v0.11.0 起，go-authn/authnd 把没有 POSIX 属性的人员
发布为 `account` 或 `inetOrgPerson`，在每个人员上加 `uidObject`，并且
把没有 `gidNumber` 的组发布为 `groupOfNames`。在旧的
默认值下，这样的人员和组根本不会被读取。

{{< callout type="warning" >}}
**v0.14.0 扩大了机构目录所提供的内容**

持有并非 posixAccount 的 `account` 或 `uidObject` 条目的目录——
服务账户、以 uid 命名的主机、从别处导入的人员——现在会把它们交给
每个保留默认值的程序，并且其中每一个
都可以通过绑定对照目录来检查。其
`groupOfNames` 组会成为组，指名其中之一的 `@group` 规则现在
会授予它所说的权限。三个类都不具备的普通 `inetOrgPerson`
仍然不会被读取。若要完全保留旧的集合：

```hcl
users "ldap" {
  # ...
  user_filter            = "(objectClass=posixAccount)"
  group_filter           = "(objectClass=posixGroup)"
  group_member_attribute = "memberUid"
}
```
{{< /callout >}}

**`member` DN 不会添加人员。** 只有当它按
distinguishedNameMatch（RFC 4517 §4.2.15）是人员搜索所返回条目的 DN 时，才会映射到某人。
这些条目之外的 DN，或指名无人的 DN，都映射到
无人，当 alice 是从 `ou=people` 导入时，`uid=alice,ou=elsewhere,…` 也是如此。
直到 v0.13.0，member 属性中的 DN 会被缩减为其第一个 RDN 的
值，无论它属于谁，因此 `uid=alice,ou=elsewhere,…`、
`cn=alice,…` 和 `uid=zed,…` 会变成名为 alice、alice 和 zed 的成员。

测试目录 `ldaptest` 现在会对每次搜索应用 base 和过滤器，
给每个人员一个 `objectClass`（`Person.ObjectClasses`，默认为
`top`、`account`、`posixAccount`），并支持 `groupOfNames` 组
（`GroupsOfNames`），因此针对客户端过滤器的测试可以失败。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

- **没有人的组**，以及**没有任何来源拥有的组**，当 `Expand`
  把 `@group` 转换为人员时——是错误，而不是空列表：对无人授予
  任何权限的配置，读起来与有效的配置完全一样。前者是
  `ErrEmptyGroup`，后者是 `ErrNoSuchGroup`，`errors.Is` 可以将二者
  区分开。`Set.Members` 对空组回答空列表；没有任何
  来源拥有的组在那里同样是 `ErrNoSuchGroup`。*损坏*的来源
  与没有该组的来源分开报告，并且优先于空答复。
- **以明文访问的 LDAP 目录。** 简单绑定携带密码
  本身（RFC 4513），因此 `ldapdir.New` 和 `users "ldap"` 块
  会拒绝指向另一台机器的 `ldap://`，除非设置了 `StartTLS`。`ldaps://`、
  `ldapi://` 以及指向环回地址的 `ldap://` 会被接受。没有
  关闭这一点的开关。
- **LDAP 绑定时的空密码。** 在 LDAP 中，它是*未认证
  绑定*，大多数目录会以成功作答；`ldapdir` 不拨号，直接返回
  `ErrWrongPassword`。
- **把任何其他失败的绑定当作密码错误。** 只有 LDAP 结果 49，
  *invalidCredentials*，才是 `ErrWrongPassword`。绑定期间断开的连接、
  目录答复繁忙（51）或不可用（52），会作为
  `ldapdir: the directory did not answer the bind: …` 返回，并包装 LDAP 错误。
  两种情况下密码都被拒绝；不同的是，服务器的日志不再向
  输对了密码的人说*密码错误*。在 v0.11.2 之前，
  每个失败的绑定都是 `ErrWrongPassword`。
- **LDAP URL 中的凭据**——URL 会被打印出来；`BindDN` 和
  `BindPassword` 是字段。
- **不是 16 字节的 NT 哈希**（`ParseNTHash`），而不是将其填充
  成一个使每次登录都因密码错误而失败的哈希。
- **对没有密码的身份调用 `Derive` 或 `KerberosKey`。** 验证器说“是”
  并不等于密钥。
- **属于秘密的属性，或服务器自己回答的属性**——
  [上面的列表]({{< relref "/libraries/directory.md#attributes" >}})——无论在哪里配置：在块中、作为
  SQL 别名，还是在 ldapdir 要复制的列表中。

{{< callout type="warning" >}}
**NT 哈希和 TOTP 密钥是凭据，而不是凭据的哈希**

持有 `sambaNTPassword` 的人，就像持有密码一样
可以作为该人员进行认证；持有 TOTP 密钥的人
可以生成之后的每一个代码。`WithVerifier` 的错误只交给服务器，绝不交给客户端。
{{< /callout >}}

## 它对照什么检查 {#what-it-is-checked-against}

- **OpenLDAP 的 `ldapsearch`** 读取 `ldaptest` 的目录——条目、
  拥有它的那一个人员的 `sambaNTPassword`、组——并且在密码错误时被拒绝，
  返回 *Invalid credentials (49)*。CI 的 Linux 通道
  安装 `ldap-utils`；`ldapsearch` 不存在时测试会跳过，因为
  本模块的 CI 中没有任何东西会把这种跳过变成失败。
- **`ldapdir` 对照 `glauth/ldap`**，这是一个独立的 LDAP 服务器，而不是模拟；
  测试夹具允许未认证绑定，因此如果 `ldapdir`
  不再先拒绝它，测试就会失败。
- **`sqldir` 对照真实的 SQLite 数据库**，通过真实的驱动。
  属性查询还曾手工对照 PostgreSQL 18.6
  通过 pgx 运行过一次，不在 CI 中：不带引号的别名返回时变成了小写，
  但仍被找到，带引号的别名保留了大小写，而指名
  `userPassword` 的别名被拒绝。
- **ldapdir 的过滤器**对照 `ldaptest`，自 v0.14.0 起后者会应用它们：
  默认的用户过滤器会排除普通的 `inetOrgPerson`
  （`TestTheDefaultUserFilter`），而组过滤器不会添加任何身份
  （`TestTheGroupFilterAddsNoIdentity`）。
- **MD4** 对照 RFC 1320 的测试向量。

覆盖率通道在低于 85% 时失败（其声明的标准是 100%），
CI 中还会检查 `nosql` 和 `noldap` 构建。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/directory@v0.14.0](https://pkg.go.dev/github.com/go-authn/directory@v0.14.0)
