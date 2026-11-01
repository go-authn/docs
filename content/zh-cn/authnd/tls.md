---
title: "TLS：ldaps:// 或 StartTLS，而不是同时使用"
linkTitle: "TLS"
weight: 40
description: "用文件中的证书通过 TLS 提供 LDAP 服务、ldaps:// 与 StartTLS 之间的选择，以及为什么 sambaNTPassword 只在其中一种方式上发布。"
tags: [authnd, tls, starttls, ldaps]
---

```hcl
listen    = "0.0.0.0:636"
cert_file = "/etc/authnd/cert.pem"   # the chain, leaf first
key_file  = "/etc/authnd/key.pem"
```

`cert_file` 和 `key_file` 一起启用 TLS；只有其一会被
拒绝（*one without the other serves nothing*）。TLS 1.2 是最低版本。
authnd 没有 ACME 客户端：这两个文件由其他程序写入——
[go-authn/servercert]({{< relref "/libraries/servercert.md" >}})、certbot、
站点自己的 CA——并且自 v0.15.0 起，这些文件一有变化 authnd 就会重新读取，无需重启：
参见[续期证书](#renewal)。直到 v0.14.1，证书只在监听器打开时读取一次，
所以每次续期之后都要**重启** authnd。

## 两种方式，各用一个监听器 {#two-ways-one-listener-each}

| | `starttls` | 监听器 | `check` 的输出 |
|---|---|---|---|
| **ldaps://** | 未设置 | 在说出任何一个字节的 LDAP 之前先进行 TLS 握手 | `ldaps://…` |
| **StartTLS** | `starttls = true` | 明文，在客户端请求时升级（RFC 4511 §4.14） | `ldap+starttls://…` |

二者只能择一，也必须如此：监听器不可能既要求握手，
又等待看是否有人请求握手。站点想要哪一种取决于其**客户端**：
636 上的 `ldaps://` 是大多数客户端所配置的方式，而 StartTLS 则是指向 389 并勾选
“使用 TLS”的客户端会请求的方式。两者都需要的站点运行两个实例，
各自使用自己的 `--config`。没有证书的 `starttls = true` 会被拒绝：

```
$ authnd check cases/starttls-nocert.hcl
authnd: starttls needs cert_file and key_file: there is nothing to upgrade a connection WITH
```

### ldaps:// {#ldaps}

服务器、为 `127.0.0.1` 签发的 CA 签名证书，以及由
并非本程序的客户端验证的证书链：

```
$ authnd --config ldaps
ldaps on 127.0.0.1:3636, serving 3 people from the configuration file
uid=carol,ou=people,dc=example,dc=org is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

$ openssl s_client -connect 127.0.0.1:3636 -CAfile tls/ca.pem -verify_return_error -verify_ip 127.0.0.1 </dev/null 2>&1 | grep -E 'Verify return|Protocol|subject=|issuer='
subject=CN=localhost
issuer=CN=docs test CA
Protocol: TLSv1.3
Verify return code: 0 (ok)
    Protocol  : TLSv1.3
    Verify return code: 0 (ok)
```

### StartTLS：未被请求就拒绝 {#starttls-which-refuses-until-it-is-asked-for}

StartTLS 由**客户端**请求，因此仅仅提供它并不能保证
什么：从不请求的客户端会以明文绑定。因此，带有
`starttls = true` 的监听器会拒绝每个绑定和每个搜索，直到
连接升级为止，返回 `confidentialityRequired`：

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
ldap_bind: Confidentiality required (13)
	additional info: this listener requires TLS, and nothing asked for it

$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=bob)'
dn: uid=bob,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: sambaSamAccount
objectClass: uidObject
uid: bob
cn: bob
sambaSID: S-1-5-21-1004336348-1177238915-682003330-1104
sambaNTPassword: 8846F7EAEE8FB117AD06BDD830B7586C
```

（`-ZZ` 表示“StartTLS，失败则报错”。之所以有 `LDAPTLS_REQCERT=never`，
是因为 macOS 自带的 `ldapsearch` 信任系统证书库，无法
指示它信任这个测试 CA；证书链是另外用
`openssl s_client -starttls ldap -CAfile tls/ca.pem -verify_return_error` 检查的，
结果为 `Verify return code: 0 (ok)`。）

正是这种拒绝使 `cert_file` 成为保证而不只是一个选项——也是
`publish_nt_hash` 所依赖的。它也包括 `ldapsearch -x` 在读取根 DSE 之前
发送的匿名绑定，因此在 StartTLS 监听器上，
那个发现查询同样需要 `-ZZ`。

## 续期证书 {#renewal}

自 v0.15.0 起，续期后的证书无需重启。authnd 会在距上次查看 5 秒之后的第一次 TLS 握手时，以及在收到 `SIGHUP`
（`kill -HUP`，或 `systemctl kill -s HUP authnd`）时立即，将 `cert_file` 和 `key_file` 与它正在提供的内容比较。
文件的标识是其内容的 SHA-256，因此，把新文件重命名覆盖旧文件的续期工具，和就地重写文件的续期工具，都能被发现，
同一个时间戳刻度内写入的相同大小的一对文件也不会被误认为旧的。

无法加载的新证书对（写了一半、密钥与证书不匹配、损坏的文件）不会改变任何东西：authnd 继续提供它已有的证书，
针对文件的这种状态只记录**一次**失败，并在文件再次变化时重试。在 v0.15.0 之前，夜里过期的证书会让所有客户端
不再信任，直到有人重启 authnd。配置和 keytab 仍然只在启动时读取。

## `publish_nt_hash` {#publish_nt_hash}

`sambaNTPassword` 使 Samba 或其他 SMB 服务器能够通过此目录
对人员进行认证，而它**不是**登录表单所说的那种
密码哈希：持有 `MD4(UTF16LE(password))` 的人
就能通过 NTLMv2 以该人员身份认证，而无需知道
密码。因此它只在被要求时才发布，并且自 v0.11.0 起，
还要附带人员 SID 所属的域：

```hcl
publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"   # `net getlocalsid` on the SMB server
}
```

除非监听器具有 TLS，或者是环回地址
（`127.0.0.0/8`、`::1`、`localhost`），因而完全不经过网络，否则请求它会被拒绝：

```
$ authnd check cases/nthash-clear.hcl
authnd: publish_nt_hash needs cert_file and key_file: an NT hash IS the credential, and 0.0.0.0:3893 is not loopback, so it would cross a network in the clear
```

### `samba` 块 {#the-samba-block}

`sambaNTPassword` 属于 Samba 的 `sambaSamAccount`，其 MUST 是 `uid`
和 `sambaSID`，没有其他类允许它。authnd 发布的每个条目都要通过
[它所提供的模式]({{< relref "/authnd/entries.md" >}})，因此该
属性只会发布在 `sambaSamAccount` 上，而这需要 SID：

| 键 | |
|---|---|
| `domain_sid` | 必需：SMB 服务器的域 SID，`S-1-5-21-…`，即 `net getlocalsid` 所输出的 |
| `algorithmic_rid_base` | 可选，默认 `1000`，即 Samba 的默认值。奇数或小于 1000 的值会被拒绝：Samba 会悄悄地改用另一个值 |

当来源给出人员自己的 `sambaSID` 属性时，人员的 `sambaSID` 就是它
（[属性]({{< relref "/authnd/entries.md#adding-attributes" >}})）。
否则它是 `domain_sid-RID`，其中 RID = 2 × `uidNumber` +
`algorithmic_rid_base`：即 Samba 的算法映射（smb.conf(5)，
*algorithmic rid base*）。具有 NT 密钥却两者皆无的人员，发布时
**不带** `sambaNTPassword`，`check` 和启动日志会说明是谁。
Samba 的定义只有在存在该块时才会加入 `cn=Subschema` 处提供的模式；
它们依据 Samba 公布的 OID、名称和语法编写，而不是从其 GPL-3.0 的
`samba.schema` 复制而来。

{{< callout type="error" >}}
**对 v0.10.x 配置的破坏性变更：没有 `samba` 块的 `publish_nt_hash` 无法启动**

v0.10.x 允许单独使用 `publish_nt_hash = true`。自 v0.11.0 起，该
配置在启动时和 `check` 中会被拒绝，并说明需要添加什么：

```
$ authnd check cases/nthash.hcl
authnd: publish_nt_hash needs a samba block: sambaNTPassword belongs to Samba's sambaSamAccount, whose MUST is uid and sambaSID, and a SID needs the domain's. Add

  samba {
    domain_sid = "S-1-5-21-..."   # the SMB server's: `net getlocalsid` prints it
  }

and each person's sambaSID is their own sambaSID attribute, or domain_sid-(2 x uidNumber + 1000), Samba's algorithmic mapping; `authnd check` lists who has neither
```

升级之前请用新的二进制文件运行 `check`。拒绝是有意的：
v0.10.x 的条目无法通过模式，而两种安静的替代做法——
丢弃该属性（这会让所有人都无法使用 SMB），或丢弃
该条目（这会让该人员消失）——都会在控制台没有任何提示的情况下发生。
{{< /callout >}}

没有 `publish_nt_hash` 的 `samba` 块同样会被拒绝，因为它
什么也不会发布：

```
$ authnd check cases/samba-alone.hcl
authnd: a samba block without publish_nt_hash publishes nothing: it is the domain of the sambaSID that sambaNTPassword needs. Remove it, or set publish_nt_hash = true
```

### `check` 的输出 {#what-check-says}

`ldaps://` 监听器上的三个人员：alice 有密码和 POSIX
三元组，因此其 SID 是推导出来的（2 × 1000 + 1000）；bob 只有 NT 哈希和
他自己的 `sambaSID`；carol 有密码，但两者皆无。

```hcl
listen    = "127.0.0.1:3636"
base_dn   = "dc=example,dc=org"
cert_file = "tls/cert.pem"
key_file  = "tls/key.pem"

publish_nt_hash = true
samba {
  domain_sid = "S-1-5-21-1004336348-1177238915-682003330"
}

reader "cn=reader,dc=example,dc=org" { password_file = "etc/authnd/reader.pw" }

user "alice" {
  password_file = "etc/authnd/alice.pw"
  attributes    = { uidNumber = "1000", gidNumber = "1000", homeDirectory = "/home/alice" }
}

user "bob" {
  nt_hash    = "8846F7EAEE8FB117AD06BDD830B7586C"
  attributes = { sambaSID = "S-1-5-21-1004336348-1177238915-682003330-1104" }
}

user "carol" { password = "carol-pw" }
```

```
$ authnd check ldaps
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS                                       WITH
alice  the configuration file  a password  account, posixAccount, sambaSamAccount, uidObject  uid, cn, gidNumber, homeDirectory, uidNumber, sambaSID and sambaNTPassword
bob    the configuration file  an NT hash  account, sambaSamAccount, uidObject                uid, cn, sambaSID and sambaNTPassword
carol  the configuration file  a password  account, uidObject                                 uid

bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, sambaSamAccount, uidObject
carol has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
carol is published without sambaNTPassword: no sambaSID and no uidNumber to derive one from

a bind carries a password
bob cannot bind with a password: the source holds only what an SMB server needs (an NT hash), which a bind cannot be checked against
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is published over TLS: it IS the credential, and whoever reads it authenticates as that person over NTLMv2
  in sambaSamAccount, with sambaSIDs in S-1-5-21-1004336348-1177238915-682003330 (a person's own sambaSID, or RID 2 x uidNumber + 1000)

this configuration can be served
```

而对于 StartTLS 监听器，则是 *sambaNTPassword is published over TLS, once
StartTLS has been asked for*。alice 没有写下 NT 哈希；她的哈希
由她所持有的密码推导而来。bob 的哈希会发布供 SMB
服务器使用，而 `check` 同时也说明 bob 无法绑定到 authnd 本身。
carol 的条目发布时不带该属性，在某个来源给她一个 `uidNumber`
或 `sambaSID` 之前，SMB 服务器无法为 carol 提供服务。

同样这批人员，在 StartTLS 监听器上 reader 得到的内容：

```
$ LDAPTLS_REQCERT=never ldapsearch -ZZ -x -LLL -H ldap://127.0.0.1:3389 -D cn=reader,dc=example,dc=org -y reader.pwin -b ou=people,dc=example,dc=org '(uid=alice)'
dn: uid=alice,ou=people,dc=example,dc=org
objectClass: top
objectClass: account
objectClass: posixAccount
objectClass: sambaSamAccount
objectClass: uidObject
uid: alice
cn: alice
gidNumber: 1000
homeDirectory: /home/alice
uidNumber: 1000
sambaSID: S-1-5-21-1004336348-1177238915-682003330-3000
sambaNTPassword: D061EF15E9494B458016FA760CECDD63
```

只有 [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})
可以搜索，因此只有 reader 能看到该属性。谁可以读取它，
因此就等同于谁持有 reader 的密码。

{{< callout type="warning" >}}
**NTLMv2 需要密码或其 MD4，别无他法**

向 authnd 查询某人的文件服务器，只有在
*来源*持有足够的内容时才能通过 SMB 为其提供服务：密码，或哈希。来自
只校验密码的目录的人员——`check` 中的 *a password check*——
无论 authnd 在中间做什么，都永远无法获得 `sambaNTPassword`。没有 `publish_nt_hash` 时，
任何人都不能：`check` 会提示
*sambaNTPassword is not published, so nothing here can authenticate an SMB
session*。
{{< /callout >}}

## 令牌也需要它 {#tokens-need-it-too}

[`oidc` 块]({{< relref "/authnd/tokens.md" >}})会拒绝来自未加密
连接的令牌，除非 `allow_plaintext = true` 表明
TLS 在此进程之前终止。
