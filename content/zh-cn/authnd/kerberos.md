---
title: "面向同一批人员的 Kerberos 域"
linkTitle: "Kerberos 域"
weight: 60
description: "kerberos 块、它用来为票据签名的 keytab、谁可以获得票据以及为什么有些人永远不能，还有它为什么不能与 mfa 块并存。"
tags: [authnd, kerberos, kdc]
---

```hcl
kerberos {
  realm    = "EXAMPLE.ORG"               # required, upper case
  keytab   = "/etc/authnd/krb5.keytab"   # required; must hold krbtgt/EXAMPLE.ORG
  listen   = "127.0.0.1:88"              # the default; UDP and TCP both
  lifetime = "10h"                       # the default, MIT's
}
```

`kerberos` 块通过
[go-authn/kdc]({{< relref "/libraries/_index.md" >}})使 authnd 在作为目录之外还成为 KDC：同一批人员
可以获得票据，而不只是被查询。它在同一地址上同时通过 UDP 和 TCP 应答，
要求加密时间戳预认证，并且只签发
`aes256-cts-hmac-sha1-96` 票据。`lifetime` 是 Go 的时间长度
（`"10h"`、`"90m"`）。目录与域地位平等：任何一方停止，
进程就会停止，因为 KDC 已经终止而服务器仍继续应答 LDAP，
对于所有不使用 Kerberos 的程序来说，它看起来仍然是健康的。

启动时被拒绝：

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

同样被拒绝的还有：没有名称的域、没有 keytab、无法解析的地址、
Go 无法读取的 `lifetime`，以及与 `mfa` 块并存的 `kerberos` 块
（见下文）。

## keytab {#the-keytab}

keytab 保存 authnd 为自己的票据签名所用的密钥——
`krbtgt/REALM@REALM`——以及它为之签发票据的每个服务各一把密钥。它
就是那些服务所读取的同一个文件。krbtgt 的密码
不会再被键入，因此请使其随机。使用 MIT 的 `ktutil`
（Debian 和 Ubuntu 上的 `krb5-user` 包；这个方法就是
`docs/install.md` 所给出的，在编写这些页面时并未运行过）：

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

以同样的方式添加服务的密钥（`-p nfs/files.example.org@EXAMPLE.ORG`），并
在该服务自己的 keytab 中放入同一把密钥。在 macOS 上，Heimdal 的
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96`
写入随机密钥，完全不需要密码。无论哪种方式，启动前都要回读 keytab
（MIT 用 `klist -k`，Heimdal 用 `ktutil -k <file> list`）：

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

没有 `krbtgt/REALM` 的 keytab 会被 `check` 和启动过程拒绝；参见
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}})。
keytab 只在启动时读取一次：更换它需要重启。

## 谁可以获得票据 {#who-can-be-issued-a-ticket}

KDC 必须用该用户的长期密钥**解密**客户端的预认证，
因此它需要此人的**密码**，而不只是
校验密码的手段。`check` 会说明谁可以、谁不可以，并给出原因：

```
$ authnd check realm
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid
bob    the configuration file  an NT hash  account, uidObject  uid
dora   a sqlite database       a password  account, uidObject  uid
eli    a sqlite database       an NT hash  account, uidObject  uid

GROUP  MEMBERS        PUBLISHED AS
staff  alice and bob  groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
bob has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
dora has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
eli has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp), keytab etc/authnd/krb5.keytab
  can be issued a ticket: alice and dora
  CANNOT, whatever they type: bob and eli
  a KDC must decrypt the pre-authentication with the person's key
  bob and eli: an NT hash is only the RC4-HMAC key (RFC 4757), and this realm issues aes256-cts-hmac-sha1-96 alone, whose key is derived from the password itself

a bind carries a password
bob and eli cannot bind with a password: their sources hold only what an SMB server needs (an NT hash), which a bind cannot be checked against
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

| 来源具有 | 票据 |
|---|---|
| 密码（`password`、`password_file`、SQL 密码列） | 可以 |
| 仅有 NT 哈希 | **不可以**：它是 RC4-HMAC 密钥，而该域只签发 AES |
| 仅有密码校验（位于此目录之后的 `users "ldap"` 目录） | **不可以**：只验证密码的来源无法产生任何密钥 |

对于位于此目录之后的目录，域部分的最后一行为
*alice, bob, dora and eli: the source only verifies a password, so it cannot
produce any key*。这是结构性的，而不是配置问题，
在 `check` 中发现它，胜过从某个 `kinit` 提示
其正确密码有误的人那里发现。

## 用 kinit 访问它 {#kinit-against-it}

一个指明此 KDC 的 `krb5.conf`。⛔ 对于 MIT Kerberos，花括号要各占
一行：它的解析器会悄悄忽略写在一行里的域。

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

运行同一配置，并由 macOS 的 Heimdal `kinit` 访问
（`--password-file` 从文件读取密码）：

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 26 12:42:50 2026  Oct 26 22:42:50 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

票据的有效期为默认的十小时。bob 输入了其 NT 哈希
所由计算的密码，却仍被拒绝：该域没有他的密钥。
KDC 将其拒绝的内容连同 Kerberos 错误代码写到输出中：

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required* 是 `kinit` 正常的第一轮交互：
客户端不带预认证发出请求，被告知需要预认证，然后带着预认证
再次请求。alice 成功的 `kinit` 只留下这一行。

{{< callout type="info" >}}
**域会说明哪些名称存在；目录不会**

对无人使用的名称发起的 LDAP 绑定，得到的答复是 `invalidCredentials`，
与密码错误时相同。KDC 则回答 *no such principal in this realm*
（`KDC_ERR_C_PRINCIPAL_UNKNOWN`，代码 6），Kerberos KDC 都是如此。当
`kerberos` 块位于他人可以访问的地址上时，名称列表
因而与从任何 KDC 获取时一样容易被猜出；`listen` 默认为
环回地址。
{{< /callout >}}

## 通过 LDAP 更改的密码 {#a-password-changed-over-ldap}

KDC 读取的与目录所提供的是同一批人员，因此
[通过 LDAP 更改的密码]({{< relref "/authnd/passwords.md" >}})会立即到达
该域——旧密码对 `kinit` 失效的时刻，就是它对绑定失效的时刻：

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## 不能与 `mfa` 块并存 {#not-beside-an-mfa-block}

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

RFC 4120 的加密时间戳预认证仅由密码派生密钥。
第二因素需要 FAST（RFC 6113）内部的 OTP 预认证
（RFC 6560），而此 KDC 没有实现它。此处的域会对 [`mfa` 块]({{< relref "/authnd/mfa.md" >}})
要求两个因素的人员只凭一个因素签发票据，而票据能打开绑定所能打开的一切——
因此选择采用故障即拒绝的方式：二者择一。

## 端口 {#ports}

88 是特权端口。在打包提供的单元下，`CAP_NET_BIND_SERVICE` 涵盖了它；
以普通用户运行的服务器需要一个高端口，如上文所示，并需要一个指明该端口的
`krb5.conf`。
