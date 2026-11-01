---
title: "重启人员赖以登录的服务之前先用 check"
linkTitle: "check"
weight: 30
description: "authnd check 会打开什么、在配置投入服务之前它会输出什么、如何阅读，以及它无法发现的那一种故障。"
tags: [authnd, 检查, 配置]
---

```
authnd check /etc/authnd
authnd check --config a.hcl --config b.hcl
```

`check` 读取配置的方式与服务器完全相同，并**在监听之前打开
服务器所要打开的一切**——文件、数据库、
位于此服务之后的目录、身份提供方的发现文档、
TLS 证书和密钥、keytab——然后输出将要发布什么、
发布给谁，**而不进行监听**。它输出每个凭据
来自何处，但绝不输出其中的内容。它以 0 退出并以 *this configuration
can be served* 结束，或者以 1 退出并给出使服务器无法启动的那一句话。

## 可以投入服务的配置 {#a-configuration-that-can-be-served}

两个 `user` 块、一个 reader 和一个 SQLite 数据库，位于包含两个
文件（`authnd.hcl` 和 `people.hcl`）的目录中：

```
$ authnd check etc/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP      MEMBERS              PUBLISHED AS
engineers  dora and eli         groupOfNames
staff      alice, bob and dora  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group engineers has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

## 如何阅读 {#reading-it}

第一行是协议方案、地址和 base：`ldap://`、
`ldaps://` 或 `ldap+starttls://`——参见 [TLS]({{< relref "/authnd/tls.md" >}})。

| 列 | |
|---|---|
| `FROM` | 拥有该名称的来源：*the configuration file*、*a sqlite database*（或 postgres、mysql），或位于此服务之后的目录的 url |
| `CAN PROVE` | *a password*（已持有，因此可以比较并由它派生密钥）、*a password check*（由另一个目录回答是或否）、*an NT hash*、*N keys*、*a one-time-code secret*，或 *nothing* |
| `PUBLISHED AS` | 条目的对象类（不含 `top`），按[各种形态]({{< relref "/authnd/entries.md#the-shapes" >}})给出——对于未通过模式检查的条目则为 *NOT PUBLISHED (see below)* |
| `WITH` | 条目所带的属性，取自搜索所返回的条目：`uid`；类允许时的 `cn`；来源所提供的内容减去被丢弃的；有密钥时的 `sshPublicKey`；以及在 [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})开启且此人具有 NT 密钥和 SID 时的 `sambaSID` 和 `sambaNTPassword` |

组表也有 `PUBLISHED AS` 列：`posixGroup`、
`groupOfNames` 或 `organizationalRole`。直到 v0.10.2，`PUBLISHED AS` 是
属性列表，对几乎所有人都是 *uid and cn*，并且没有
`WITH` 列。

表格之后的各行说明了在依赖该配置之前
需要知道的事。首先是关于[条目]({{< relref "/authnd/entries.md" >}})：

- **谁不是 `posixAccount`**，以及他们缺少 `uidNumber`、`gidNumber`
  和 `homeDirectory` 中的哪一项；
- **哪些组没有 `gidNumber`**，以及它们改为发布成什么；
- **每个被丢弃的属性**，因为其条目的任何类都不允许它，以及
  哪些类会允许它；
- **每个未发布的条目**，以及模式检查所发现的每个问题；
- **谁有 NT 密钥却没有 `sambaSID`**，因而没有 `sambaNTPassword`。

从 v0.12.0 起，在第一行和各表格之间，会给出[站点模式]({{< relref "/authnd/schemas.md" >}})
添加了什么，以及各来源声明了什么：

- **加载的模式文件和 `schema` 块**，以及每一个添加了什么：
  `schema: etc/authnd/example.schema adds 3 object identifier macros, 2
  attribute types and 2 object classes`；
- **每个来源声明的类**：`users "sql" declares exampleStaff and
  exampleLockerHolder for its people`，并附上该声明的位置；
- **每个未加到某个人员或组上的类**，因为它缺少其来源所声明的某个类的
  MUST：`ben is published without exampleStaff, which its
  source declares: ben has no exampleEmployeeId, which exampleStaff
  requires`，以及在各属性行之后，随之一并丢失的那些属性；
- **两个来源为同一个组声明了不同的类**：发布第一个来源的列表，
  忽略第二个来源的列表。

无法构建的文件、重新定义，以及未定义、为 STRUCTURAL 或由 authnd
自行派生的已声明类，都会使 `check` 和服务器同样停止，并给出文件或
配置中的位置。

然后是关于绑定和搜索：

- **绑定携带什么**：*a password*，或者在有 [`mfa` 块]({{< relref "/authnd/mfa.md" >}})时是
  *a password with a 6-digit code after it*；在有 [`oidc` 块]({{< relref "/authnd/tokens.md" >}})时，
  则说明令牌来自何处、通过什么传递；
- **谁完全不能用密码绑定**：只以 NT
  哈希为人所知的人员——参见[人员]({{< relref "/authnd/people.md#written-in-the-configuration" >}})；
- **谁可以搜索**：各个 reader，或者 *no reader is declared: nothing may
  search, and binds are not affected*；
- **是否发布 `sambaNTPassword`**，以及通过什么传输——参见
  [`publish_nt_hash`]({{< relref "/authnd/tls.md#publish_nt_hash" >}})；
- 有 [`kerberos` 块]({{< relref "/authnd/kerberos.md" >}})时，说明域以及
  **谁可以、谁不可以获得票据**，并给出原因；
- 有 `mfa` 块时，说明**谁没有第二因素**，因而不能用
  密码绑定；若同时有 `oidc` 块，该行会补充说明 `amr` 指名两种因素的
  令牌仍然可以；
- **指名了任何来源中都没有的人员的组**。

最后一项会按原样发布——一个系统的前端
合理地带有另一个系统所拥有的名称——但会予以提示，因为
另一种解读是笔误。在 `posixGroup` 中，这个陌生人是 `memberUid`；在
`groupOfNames` 中，它是在此处没有对应条目的 `member` DN，
这里是 `member: uid=zoe,ou=people,dc=example,dc=org`，go-authn/directory 的
`ldapdir` 从 v0.14.0 起会将其映射到无人。这里数据库的 `team_members`
表中有一行属于 `zoe`，而 `zoe` 在此处并不存在：

```
GROUP      MEMBERS              PUBLISHED AS
engineers  dora, eli and zoe    groupOfNames
staff      alice, bob and dora  groupOfNames
[...]
engineers names zoe, who has no entry here: the group is published as it stands, and nothing here can prove them
```

（指名陌生人的 `group` *块*会被直接拒绝；参见
[人员]({{< relref "/authnd/people.md#written-in-the-configuration" >}})。）

自 v0.15.0 起，输出的第二行是 `limits:`：authnd 将使用的连接限制、操作期限和启动期限，包括默认值。
本页的记录由更早的版本打印，没有显示它。真实的例子见
[限制与期限]({{< relref "/authnd/operations.md#limits" >}})。

## 它拒绝什么 {#what-it-refuses}

下面每一项都会使 `check` 和服务器同样停止，退出状态为 1。它们
位于各自所属的页面上；下面是几个按原样输出的例子：

```
$ authnd check cases/nobody.hcl
authnd: there is nobody here: name a user, or a users block reading a database or a directory

$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear

$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks

$ authnd check empty
authnd: empty has no .hcl files in it

$ authnd
authnd: no configuration: give a .hcl file or a directory of them
```

## 证书、keytab，以及它无法发现的那一件事 {#the-certificate-the-keytab-and-the-one-thing-it-cannot-see}

无法加载的证书和没有 `krbtgt/REALM` 的 keytab 会被
`check` 拒绝，所用措辞与服务器相同：

```
$ authnd check cases/badcert
authnd: the certificate: open tls/missing.pem: no such file or directory

$ authnd check cases/nokrbtgt
authnd: kdc: the keytab has no krbtgt key for this realm: matching key not found in keytab. Looking for "krbtgt/EXAMPLE.ORG" realm: EXAMPLE.ORG kvno: 0 etype: 18
```

不监听就无法知道的是**端口是否
空闲**。同一 Kerberos 地址上的第二个服务器能通过 `check`，
却会在启动时被拒绝：

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

## 以服务账户运行 {#run-it-as-the-service-account}

```sh
sudo -u authnd authnd check /etc/authnd
```

这样，只有 root 才能读取的文件会在这里失败，而不是在重启时失败。升级之前
用**新的**二进制文件运行它；参见[安装]({{< relref "/authnd/install.md#upgrade-roll-back-remove" >}})。
