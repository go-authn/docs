---
title: "ldap — LDAP 服务器的字节"
linkTitle: "ldap"
weight: 60
description: "go-authn/ldap 是作为服务器库的 LDAP 协议：线路格式、过滤器、各项操作及其限制，由处理程序决定如何作答。"
tags: [库, ldap, 目录]
---

**LDAP 服务器的字节是什么？** 它是一个库，而不是守护进程：线路格式、
过滤器、各项操作。[authnd]({{< relref "/authnd/_index.md" >}})是
运行它的服务器，并拥有配置、目录来源和
绑定策略；本库拥有字节。

```sh
go get github.com/go-authn/ldap@v0.10.1
```

依据 RFC 4511（协议）、4512（根 DSE 和模式）、
4513（认证）、4514 和 4515（DN 和过滤器的字符串形式）、4517 和
4518（语法、匹配规则、字符串准备）、4526、2696（分页
结果）、3672（子条目）、3673、4527（读取条目控制）、4532（whoami）
和 3045 编写。

`Server` 是一组处理程序，每个都是可选字段：`Bind`、`SASL`、
`Search`、`Compare`、`Extended`、`Add`、`Modify`、`Delete`、`ModifyDN`、
`Abandon`。为 nil 表示*此服务器不做这件事*，该操作
会得到 `unwillingToPerform` 的答复——而不是 `insufficientAccessRights`，后者会
引起关于并不存在的权限的争论。根 DSE 由服务器自己
作答，并且恰好发布它所遵从的内容。

## 示例 {#example}

一个服务器，有一个可以绑定的人员，以及一个搜索，它写出
过滤器所匹配的内容：

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

由 OpenLDAP 的 `ldapsearch`（2.4.28，即 macOS 所带的版本）发出请求，
dora 的密码保存在文件中：

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

`(uid=svc-*-prod)` 返回 `svc-web-prod` 而不是 `svc-web-stage`。本库
所取代的那个库，把该过滤器当作 `(uid=svc-*)` 求值，因此也返回了
`svc-web-stage`；这一缺陷正是编写本库的原因。
根 DSE 没有列出 StartTLS，因为没有给出 `TLSConfig`。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

**过滤器只有一种含义。** 它被解析或解码一次，形成一棵树，
`String`、`EncodeFilter` 和 `Matches` 都读取这棵树。不是 RFC 4512 §2.5
属性描述的属性，或不是 OID 的匹配规则，会被 `ParseFilter` 和
`DecodeFilter` 同时拒绝：在 v0.6.1 之前，针对属性 `!x` 的“存在”过滤器
打印回来后会被读成 NOT。

**在承诺了其他方式时使用明文。** StartTLS 是由*客户端*请求的，
因此仅仅提供它的服务器并没有承诺任何事。
`RequireTLS` 会拒绝未受保护连接上的每个操作，
返回 `confidentialityRequired`。

**失败的绑定不会保留任何东西。** RFC 4511 §4.2.1：连接在*收到*绑定请求时
就变为匿名，除非绑定成功否则保持匿名——因此用错误密码重新绑定
不会保留前一个人员的权限。没有 `Bind` 处理程序的简单绑定会得到
`authMethodNotSupported` 的答复，LDAPv2 则作为协议错误被拒绝。

{{< callout type="warning" >}}
**空密码的含义由处理程序决定**

未认证绑定——带有空密码的名称，RFC 4513 §5.1.2——会像任何其他简单绑定一样
交给 `Bind` 处理程序，而对其返回
`Success` 的处理程序会把连接绑定为该名称。请像示例那样在处理程序中拒绝它。
[directory]({{< relref "/libraries/directory.md" >}})的
`ldapdir` 在客户端一侧拒绝它。
{{< /callout >}}

**它不遵从的关键控制。** ManageDsaIT（RFC 3296）、密码
修改（RFC 3062）和取消（RFC 3909）被定义为常量，是因为
客户端可能发送它们，而不是因为它们会被应答：这里不跟随
别名或引荐，因此关键的 ManageDsaIT 会被
`unavailableCriticalExtension` 拒绝。

**未认证的对端能占用什么：**

| | 默认值 | |
|---|---|---|
| `MaxMessageSize` | 4 MiB | 声称有四吉字节的五字节头部会在预留任何内容之前被拒绝 |
| `MaxMessageElements` | 16384 | 在解码之前统计的 BER 元素数：在 v0.5.0 之前，4 MiB 的空字符串在任何绑定之前就占用了 373 MiB |
| `IdleTimeout` | 5 分钟 | 整个消息必须及时到达，而不仅仅是它的第一个字节；负值表示永不超时 |
| `MaxPending`、`MaxPendingAuth` | 100、1000 | 一个连接在绑定之前（`MaxPending`）和之后（`MaxPendingAuth`）可以有多少进行中的操作，对应 slapd 的 `conn_max_pending` 和 `conn_max_pending_auth`；超出的连接会收到断开通知并被关闭 |
| `MaxPagedSearches` | 4 | 每个连接打开的分页搜索数，每个都是停在下一个条目上的 goroutine |

过滤器的嵌套同样有界：Go 中的栈溢出会终止进程。
没有任何内容会记录断言*值*——过滤器携带的是某人键入的内容——只记录
过滤器的形状。

**分页搜索回答所问的问题。** 直到 v0.8.0，分页读取器会按处理程序写入的
样子发送每个条目：仅针对 `cn` 的分页搜索，返回的是
所有属性，包括操作属性，而 `typesOnly` 被
忽略，同样的搜索不分页时却遵循所选的属性。`ldapsearch
-E pr=N` 是客户端分页的方式，因此同一个问题得到了两个答案。自
v0.8.0 起，两者都应用所选的属性，`ldapsearch` 自己在 CI 中检查这一点。

没有模式时——`Server.Schema` 为 nil，这是默认值——每次比较
对值都不区分大小写：这是两者中读取时更安全的一种，因为
它绝不会隐藏精确比较本来能找到的条目。

## 模式 {#the-schema}

自 v0.8.0 起，包 `schema` 是 RFC 4512 §4 的目录模式，而
`Server.Schema` 使服务器使用它。nil 使服务器保持原样。

- `schema.Standard()` 内嵌 RFC 4512、4517、4519、4524、
  4523、2798、2307、3672 和 3045 的定义，外加 openssh-lpk 的 `ldapPublicKey` 和
  `sshPublicKey`，以及它们所需的两个 OpenLDAP 定义，均复制自
  RFC 文本；`schema/defs` 中的每个文件都指明其来源和章节。
  `schema.Build(append(schema.StandardFiles(), mine)...)` 添加
  部署自己的定义，并拒绝其 SUP、规则、语法、MUST 或 MAY
  无法解析的定义。
- `(*ldap.Entry).Validate(s)` 检查一条结构链，要求列出每个
  父类、每个 MUST、MUST 和 MAY 之外没有任何内容、SINGLE-VALUE、
  已知类型、符合其语法的值，以及条目中 RDN 的值——
  并以 `*schema.ValidationError` 的形式指出**每一个**问题。
- 有模式时，根 DSE 带有 `subschemaSubentry: cn=Subschema`，
  对 `cn=Subschema`（`ldap.SubschemaDN`）的 base 搜索由库来应答，
  与根 DSE 相同（RFC 4512 §4.2）。定义只有在按名称或用 `+` 请求时
  才会给出。它位于 `RequireTLS` 关卡之后。
- 过滤器使用模式的匹配规则求值（RFC 4517 §4.2，
  配合 RFC 4518 字符串准备），采用 RFC 4511 的三值逻辑：未知
  属性、对所请求的匹配没有规则的类型，或无效的
  断言值是 **Undefined**，绝不是错误。服务器会重新检查
  处理程序发送的每个条目，并丢弃过滤器未使其
  为 TRUE 的条目；处理程序用 `req.Matches(e)` 过滤，它使用同一个模式。

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

`mail` 属于 `inetOrgPerson`，而不属于 `account`。`uid` 没有 ORDERING
规则，因此对它的范围比较是 Undefined。

{{< callout type="info" >}}
**对 RFC 2307 的一处偏离：`uidNumber` 和 `gidNumber` 按整数排序**

RFC 2307 给 `uidNumber` 和 `gidNumber` 设置了 EQUALITY 规则而没有 ORDERING
规则，这会使对它们的每个范围过滤器都变为 Undefined——包括
SSSD 由 `ldap_min_id` 和 `ldap_max_id` 构建的那个。slapd 自己定义这两个
类型并带有 `ORDERING integerOrderingMatch`
（`servers/slapd/schema_prep.c`；其 `nis.schema` 把它们注释掉，
标为“builtin”），draft-howard-rfc2307bis-02 §2.1 也是如此，因此内嵌的
定义遵循它们。这一点，以及允许没有 DIT 内容规则的辅助类
（RFC 4512 §2.4.3 严格禁止；所有在用的服务器
都允许），都是明确说明的，而不是事后发现的。
{{< /callout >}}

有意不包含：DIT 内容规则、DIT 结构规则和名称
形式；通过 LDAP 更改模式；RFC 4523 的证书匹配规则
和 `directoryStringFirstComponentMatch`，它们已定义但未
实现，因此使用它们的断言是 Undefined；集合属性；
`lang-` 和 `binary` 之外的选项。

[authnd]({{< relref "/authnd/entries.md#the-schema-it-serves" >}})提供
此模式，并让它发布的每个条目都遵从它。

## 读取大型模式文件 {#reading-large-files}

直到 v0.10.0，`schema.Read` 的耗时与所读文件的续行数成平方关系：由短续行组成的 4 MiB 文件约需三分钟，1 MiB 就分配了 139.6 GB。读取不受自己控制的模式文件的程序，例如 authnd 在启动时读取 `schema_files`，可能被这样的文件拖住。从 v0.10.1 起耗时是线性的（`TestManyContinuationLinesJoinInLinearTime`），并且 `Read` 不再为了查看第一行而复制并拆分整个文件。

`schema.Format` 过去会写出超过 2000 字节的行，而 slapd 和 `Read` 会拒绝这样的行；现在它会折行。严格解析器约快 2.6 倍，在 `cosine.schema` 上分配 147 次而非 498 次。这是在负载较高的机器上测得的，并不是与 libldap 的比较，那个比较尚未进行。authnd 从 v0.12.3 起包含这些修复。

## 无法构建的模式 {#build-error}

自 v0.10.0 起，`schema.Build` 或 `schema.BuildFrom` 拒绝的定义是一个
`*schema.BuildError`，可用 `errors.As` 取得。程序应根据它的字段报告拒绝，
绝不要匹配错误信息。Build 在遇到第一个被拒绝的定义时就停止，
所以只有一个。

- `Kind` 是 Build 所做的各项检查之一：`UnknownReference`、
  `DuplicateOID`、`DuplicateName`、`SuperiorCycle`、`KindViolation`、
  `UsageMismatch`、`CollectiveMismatch` 和 `UsageViolation`。
- `Element`（语法、匹配规则、属性类型或对象类）、`OID` 和
  `Name`（它的第一个 NAME）属于被拒绝的定义，`Pos` 是它的起点：
  `file:line:column`，即 `.schema` 关键字所在的行，或 LDIF 中
  `attributeTypes:` 所在的行，该行被折叠或为 base64 时也一样；HCL 则是
  该块自身的位置。在代码中构建的定义没有位置。
- `Field` 是出错的术语（`SUP`、`EQUALITY`、`SYNTAX`、`MUST`、`NAME`
  ……），`Ref` 是错误所指之处：未定义的名称或 OID，或者另一个
  定义，连同它的 `RefOID` 和 `RefPos`。对于重复定义，它是第一个
  定义，信息中会说明它在哪里。

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

在空模块中用 `github.com/go-authn/ldap` v0.10.0 运行。第一个
类没有问题；第二个从第 4 行开始，别处并无错误，因此
`RefPos` 为空。`schema.Read` 返回的每个定义同样带有 `Pos`，
Position 的 `String` 在列未知时会省略列。

## HCL2 模式与转换器 {#hcl2-and-the-converter}

自 v0.9.0 起，模式既可以用 slapd 读取的文件编写，也可以用 HCL2 编写。包 `schema/hclschema` 把 HCL2 解码为
`schema.Read` 所返回的同一个
`*schema.Definitions`，并把它们编码回去（`hclschema.Decode`、`hclschema.Encode`）；`schema` 本身不依赖 HCL。
一个块就是一个定义，其类型说明是哪种定义：
`object_identifier`、`ldap_syntax`、`matching_rule`、`attribute_type` 或
`object_class`。标签是第一个 NAME。各个属性是
RFC 4512 §4.1 的术语，小写并以下划线连接（`desc`、`sup`、`equality`、
`single_value`、`kind`、`must`、`may`，等等），而语法的 `{len}` 是 `syntax_len`。

**只允许字面值。** 值是带引号的字符串、数字、布尔值或
这些值的列表。变量、函数、运算符或 `${...}` 模板
会在求值之前就被拒绝，因此读取模式绝不会运行它。
每个字段都由严格的 RFC 4512 解析器检查，需要位置的错误
会附带文件、行和列。

命令 `ldapschema` 在各种格式之间转换：

```sh
go install github.com/go-authn/ldap/cmd/ldapschema@v0.9.0
```

- `ldapschema to-hcl [--macros] FILE...` 读取 OpenLDAP `.schema` 文件、
  cn=config LDIF 和 subschema LDIF，并写出 HCL2。
- `ldapschema to-schema [--macros] FILE...` 读取 HCL2 并写出 OpenLDAP
  `.schema` 文件。
- `ldapschema check FILE...` 在 `schema.Standard()` 之上构建这些定义
  并报告。

输出到 stdout。命令成功时退出状态为 0，文件或定义被拒绝时为 1，
用法错误时为 2。

**读取器像 slapd 一样读取文件**，因为已发布的模式
是为 slapd 编写的：术语可按任意顺序、`.schema` 文件中 slapd 的续行方式
以及 LDIF 中的 RFC 2849 折行、base64 值、cn=config 的 `{N}` 前缀，
以及按文件顺序解析的 `objectidentifier` 宏。
导出的 `Parse*` 函数以及服务器所发布的内容仍然严格遵循 RFC
4512。

一个示例，在空目录中用 `ldapschema` v0.9.0 运行。该
模式是为本页虚构的：1.3.6.1.4.1.99999 是私用的示例
弧，并非分配给任何人。一个宏、一个属性类型、一个
辅助类：

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

输出默认使用数字 OID，因为客户端在 subschema 中看到的就是这种；
`--macros` 则保留宏名称。`check` 还会报告
`schema.Standard()` 已经有的定义，以及所有无人定义的引用，
而 `Build` 在第一个处就会停止。

**`check` 可能对 slapd 能加载的文件以 1 退出。** OpenLDAP 的 `core.schema`
引用了四样 slapd 内置而 `schema.Standard()` 没有
定义的东西：语法 1.3.6.1.4.1.1466.115.121.1.42 和
1.3.6.1.4.1.1466.115.121.1.43，以及匹配规则 `protocolInformationMatch`
和 `presentationAddressMatch`。`ldapschema check core.schema` 会将它们列为
`missing:` 并以 1 退出。请将其理解为“此处未定义”，而不是该文件的
缺陷。

**它不支持的：** DIT 内容规则、DIT 结构规则和名称
形式；`include` 指令，因为 `.schema` 文件是作为定义读取的，
并不作为 slapd 配置来运行；以及 `ldapsyntax` 上的 `X-SUBST`。

**已发布的模式可以转换。** 该版本在 OpenLDAP 的
`core`、`cosine`、`inetorgperson` 和 `nis`、RENATER 的 SUPANN 2021、
REFEDS 的 eduPerson 以及 Samba 的模式上做过测量：对每一个，`.schema` 转为 HCL
再转回，以及 LDIF 对照 `.schema`，得到的定义都相等。仓库中只有 OpenLDAP 的
文件。SUPANN 和 eduPerson 未在此重现；
请到其作者的页面阅读：
[SUPANN 2021](https://services.renater.fr/documentation/supann/supann2021/recommandations/tables_references/schemas_techniques_supann)
和 [eduPerson](https://github.com/REFEDS/eduperson)。

## 它对照什么检查 {#what-it-is-checked-against}

**OpenLDAP 的 `ldapsearch`**，在 CI 中，并且在已安装的地方是必需的：
Linux 测试通道、竞态检测器和覆盖率通道设置
`LDAP_REQUIRE_JUDGE=1`，因此缺少客户端会失败而不是跳过。Windows
没有它，会跳过这些测试。`ldaptest` 是本模块自己的线路客户端，
有意不作评判者：它只询问 `ldapsearch` 无法询问的，关于单个
连接状态的问题——一个套接字上的两次绑定、使用任意机制的 SASL 绑定、
StartTLS 之后再有更多 LDAP。

`FuzzMessage` 让客户端可能发送的每条消息都经过帧、
解码器和过滤器往返。覆盖率下限是 99.7%，三个
未覆盖的行在工作流中已指明。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/ldap@v0.10.1](https://pkg.go.dev/github.com/go-authn/ldap@v0.10.1)
