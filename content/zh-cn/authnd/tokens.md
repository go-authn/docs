---
title: "绑定时使用令牌，放在密码之外的字段中"
linkTitle: "令牌（OIDC）"
weight: 75
description: "oidc 块：在 SASL OAUTHBEARER 绑定中携带的 OpenID Connect 令牌、它算作多少个因素，以及哪些会被拒绝。"
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}})将令牌验证为一个
身份。把令牌带给 LDAP 服务器的显而易见的方法是密码
字段，它能用一次，然后就不行了：密码字段正是
[`mfa` 块]({{< relref "/authnd/mfa.md" >}})从末尾取走代码的地方，
而令牌不可能同时兼顾两者。

因此令牌放在协议为它预留的位置。**SASL** 绑定的
凭据是一个具有该机制自身形态的八位字节串，而 RFC 7628 的
`OAUTHBEARER` 形态是一个 GS2 头，后面跟着键/值对，其中之一
是 `auth=Bearer <token>`：

```
n,,^Aauth=Bearer eyJ…^A^A
```

密码字段保持不动。在同一个监听器上，同一时间，
有人可以输入末尾带代码的密码，另一人可以发送
令牌。

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer` 和 `audience` 是必需的。没有 `username_claim` 时，名称取
`preferred_username`，然后是 `email`（当 `email_verified` 为 true 时），然后是 `sub`。
有了该块，根 DSE 会通告该机制：

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

没有它时，每个 SASL 绑定都会得到 `authMethodNotSupported` 的答复——*不是这种
方式*，这会把客户端引向与*密码错误*不同的地方。

## 发现在启动时进行 {#discovery-happens-at-startup}

提供方的发现文档和密钥在服务器启动时读取，
`check` 也会读取。无法连接的提供方会在有人关注的时候使服务器停止，
而不是在之后拒绝每个绑定：

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

不是 `https` 的签发方会被拒绝，环回地址除外：

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## 令牌算几个因素？ {#how-many-factors-is-a-token}

**签发方声称检查过什么就算什么，不多也不少。** 令牌携带
RFC 8176 的 `amr`，即提供方所使用的方法。这是仅有的
证据，因此 `mfa` 策略**按种类**对其计数：

| `amr` 方法 | 种类 |
|---|---|
| `pwd`、`pin`、`kba`、`mca` | 知识 |
| `otp`、`hwk`、`swk`、`sms`、`tel`、`sc`、`pop`、`user`、`wia`、`mfa` | 持有 |
| `fpt`、`face`、`iris`、`retina`、`vbm`、`geo` | 固有 |
| 其他任何值 | 未知，永远不能满足 `distinct_kinds` |
| 完全没有 `amr` | 一个因素，持有——即令牌本身 |

同一种类的两种方法算一个因素。否则就等于此服务器
凭空捏造了一个无人执行过的第二因素；而一个相信
签发方关于*此人是谁*的服务器，没有单独的理由
不相信它关于*如何检查*的说法。

有 `mfa` 块时，`check` 会这样说明：

```
$ authnd check sasl
ldaps://127.0.0.1:3636, base dc=example,dc=org

USER   FROM                    CAN PROVE                              PUBLISHED AS        WITH
alice  the configuration file  a password                             account, uidObject  uid
tess   the configuration file  a password and a one-time-code secret  account, uidObject  uid

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
tess has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject

a bind carries a password with a 6-digit code after it, of two different kinds
or a token from http://127.0.0.1:18481, over SASL OAUTHBEARER over TLS
  a token counts for the factors its amr claim names, so one with no amr is refused by this policy
alice has no second factor here, so a password cannot satisfy this policy; a token whose amr names two kinds still can
no reader is declared: nothing may search, and binds are not affected
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

alice 没有 `totp_secret`，因此带代码的密码对她永远不够；
而 `amr` 指名两种种类的令牌可以，如下面的第一个绑定
所示。

## 绑定是什么样子 {#what-the-binds-look-like}

这里的签发方是环回地址上的一个小型测试提供方，而 `oidctool` 是为这些页面编写的测试
客户端：它为给定的名称签署一个令牌，带上给定的
`amr`，将其放在 `OAUTHBEARER` 绑定中发送（当第五个参数指名了
`authzid` 时则带上它），并输出绑定的结果代码和
服务器的 SASL 凭据。这些记录以及下面的服务器输出行由 v0.10.0 发布的二进制文件输出，因为 `oidctool` 不属于任何发布版本，所以没有重新运行。针对上述配置，通过 `ldaps://`：

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 0, serverSaslCreds 

$ ./oidctool alice '' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","kba"]' 127.0.0.1:3636 tls
bind result 49

$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3636 tls tess
bind result 14, serverSaslCreds {"status":"insufficient_scope","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}

$ ./oidctool zed '["pwd","otp"]' 127.0.0.1:3636 tls
bind result 14, serverSaslCreds {"status":"invalid_token","openid-configuration":"http://127.0.0.1:18481/.well-known/openid-configuration"}
```

0 表示成功，49 是 `invalidCredentials`，14 是 `saslBindInProgress`。
`["pwd","kba"]` 令牌指名同一种类的两种方法，因此只算一次。而对于
没有 `cert_file` 和 `key_file` 的同一配置，在明文
监听器上：

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13 是 `confidentialityRequired`：不会通过未加密的
连接接受令牌。

对于通过 `ldaps://` 被拒绝的四个绑定，服务器写出的内容：

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

以及明文那一个：

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

成功的 `OAUTHBEARER` 绑定会使连接绑定为
`uid=<name>,ou=people,<base_dn>`，写法与其他每个条目相同。

## 它拒绝什么 {#what-it-refuses}

- **明文传输的令牌。** 持有者令牌不需要另一半：任何从线路上
  读到它的人，在它过期之前就是那个人。`allow_plaintext = true`
  适用于在此进程之前终止 TLS 的部署，而
  `check` 此时会提示 *a token may cross this socket in the clear*。
- **冒充他人的请求。** GS2 头可以指名 `authzid`。alice 的
  令牌如果带有以 tess 身份行事的请求，会被拒绝，而不是悄悄地
  当作其中任何一个处理。
- **为任何来源都未发布的人员签发的令牌。** 客户端只会得到
  `invalid_token`；哪些名称存在，不应当
  一次猜一个地透露出去。原因在服务器的输出中。
- **通道绑定。** 带有 `p=` 的 GS2 头——客户端坚持要求
  通道绑定——会被拒绝：此服务器不支持它，而接受
  该头却不绑定任何内容，会让客户端误以为通道已经
  被检查。
- **此服务器不支持的机制**，返回 `authMethodNotSupported`。

对令牌本身的拒绝遵循 RFC 7628 §3.2.3：一个携带
`openid-configuration` 的 JSON 错误，以 `saslBindInProgress` 返回，使客户端可以
发送结束该交换的 `^A`。通过验证但不满足
`mfa` 策略的令牌，则直接得到 `invalidCredentials` 的答复，如上面的
第二和第三个绑定所示。

{{< callout type="info" >}}
**令牌不会设置密码**

只用令牌登录过的人员，不能利用该会话为自己
设置第一个密码，而已有密码的人员更改密码时仍然必须
发送旧密码。参见[更改密码]({{< relref "/authnd/passwords.md" >}})。
{{< /callout >}}
