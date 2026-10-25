---
title: "第二因素：基于只有一个字段的协议"
linkTitle: "第二因素"
weight: 70
description: "mfa 块：附在密码末尾的一次性代码、它如何被拆分和检查、对谁计数，以及谁在它之下无法绑定。"
tags: [authnd, mfa, totp]
---

LDAP 的简单绑定携带名称和密码，别无其他——没有
放置代码的位置，没有索要代码的往返，而使用 LDAP 的客户端也不会
学会输入代码。因此代码放在密码的**末尾**，这是
同类设备的做法，也是人们已经知道如何输入的方式：

```
password:  hunter2314159
           ^^^^^^^ ^^^^^^
           password  the six digits on their phone
```

```hcl
mfa {
  factors        = 2
  distinct_kinds = true     # two things they KNOW are not two factors
  # digits = 6, period = 30 (seconds) and window = 1 are the defaults
}

user "tess" {
  password_file = "/etc/authnd/passwords/tess.pw"
  totp_secret   = "JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"   # ⛔ this IS the second factor
}
```

| 键 | 默认值 | |
|---|---|---|
| `factors` | 2 | 1 会被拒绝（*只有密码而别无其他：请移除该块，或要求 2*）；大于 2 也会被拒绝，因为绑定携带密码和一个代码，没有第三样东西 |
| `distinct_kinds` | `false` | 各因素必须属于不同的种类——这是“双因素”通常被理解的含义 |
| `digits` | 6 | 6 到 10（RFC 4226） |
| `period` | 30 | 一个代码有效的秒数 |
| `window` | 1 | 当前时刻前后所接受的步数，用于时钟不一致的情况。每一步都是别人多出的一步猜测时间：请有意识地设置它 |
| `readers` | `false` | [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})是否也携带代码。服务账户没有手机；有手机的服务账户会在其 `reader` 块中获得一个 `totp_secret` |

密钥同样可以来自数据库列（第五列）或 LDAP
属性（`totp_attribute`）；参见[人员]({{< relref "/authnd/people.md" >}})。
`user` 或 `reader` 块中不足 128 位的 `totp_secret`（RFC 4226 R6）
会使服务器停止，并指名相关人员，而不是在之后让此人的
每次登录都失败：

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## 谁在它之下无法绑定 {#who-cannot-bind-under-it}

```
$ authnd check mfa
ldap://127.0.0.1:3893, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS        WITH
alice  the configuration file  a password                             account, uidObject  uid
tess   the configuration file  a password and a one-time-code secret  account, uidObject  uid

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
tess has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject

a bind carries a password with a 6-digit code after it, of two different kinds
alice has no second factor here, and cannot bind while one is required
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

这是在启用该块之前应当提出的问题。

## 绑定是什么样子 {#what-the-binds-look-like}

运行同一配置，tess 的代码在绑定的那一刻由其密钥
计算得出：

```
$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.only
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
dn:uid=tess,ou=people,dc=example,dc=org

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.both
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=tess,ou=people,dc=example,dc=org -y tess.badcode
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.code
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D cn=reader,dc=example,dc=org -y reader.pwin
dn:cn=reader,dc=example,dc=org
```

`tess.only` 是 tess 的密码而不带代码；`tess.both` 是同一密码加
当前代码，发送了两次；`tess.badcode` 是该密码加 `000000`；
`alice.code` 是 alice 的密码加六位数字。无论哪一半有误，客户端
得到的都只有一个答复——*invalid credentials*：具体是哪一半有误是
关于账户的事实，把它告诉一个什么也没有证明的人，会缩小其下一次的
猜测范围。服务器自己的输出会说明是哪一半：

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## 单一字段带来的后果 {#what-follows-from-the-one-field}

- **按长度拆分。** 最后 `digits` 个字符是代码。以数字结尾的
  密码没有问题——这就是为什么 tess 单独的密码会被
  读作错误密码后接一个代码。*不长于*
  一个代码的字段会被拒绝而不是猜测，因为短密码
  与代码无法区分。
- **两半始终都会检查。** 一旦密码错误就提前返回，
  就会通过耗时说明是哪一半有误。
- **代码只能使用一次。** 它在整个步长内都有效，因此接受
  同一个代码两次的服务器就接受了重放；直到最后一个被接受的代码
  为止的每一步都会被拒绝，而不仅仅是同一步。
- **按名称限制猜测**，采用 go-authn/totp 的默认值：连续五次
  错误代码之后，此人会被拒绝十五分钟，包括正确的
  代码在内，一百次之后则会被锁定，直到 authnd
  重启。计数保存在内存中，按进程计。
- **只有位于正确密码之后的代码才会计数**：否则任何
  知道某个名称的人，只需五次绑定就能冻结其所有者。位于错误密码之后的
  代码仍然会被计算，只是对照的是不留记忆的对象——也就是上面输出的第一
  行，*not looked at*。
- **reader 按配置所写的 DN 计数**，因此
  `CN=Reader` 不会得到自己的新额度。
- **没有登记不等于代码错误。** 没有密钥的人
  是未作回答，而不是回答错误，服务器的输出
  会说明 *nobody enrolled an authenticator for this person*。

## 不能与域并存 {#not-with-a-realm}

同一配置中的 `kerberos` 块和 `mfa` 块会被拒绝：
`kinit` 只证明密码而别无其他，而此 KDC 没有
第二因素预认证。参见
[域]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}})。

## 令牌，遵循同一策略 {#tokens-under-the-same-policy}

绑定时使用的令牌（配合 [`oidc` 块]({{< relref "/authnd/tokens.md" >}})），
按其签发方声称检查过的内容——`amr` 声明——来计数。没有 `amr` 的令牌
算一个因素，而此策略会拒绝它。
