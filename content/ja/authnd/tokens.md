---
title: "パスワードではないフィールドで運ぶ、バインド時のトークン"
linkTitle: "トークン (OIDC)"
weight: 75
description: "oidc ブロック: SASL OAUTHBEARER バインドで運ばれる OpenID Connect トークン、それが何要素として数えられるか、そして何が拒否されるか。"
tags: [authnd, oidc, oauthbearer, sasl]
---

[go-authn/oidc]({{< relref "/libraries/_index.md" >}}) は、トークンを検証して ID にします。LDAP
サーバーにトークンを届けるための明白な方法はパスワードフィールドで、一度は動きますが、その後
動かなくなります。パスワードフィールドは、[`mfa` ブロック]({{< relref "/authnd/mfa.md" >}})が
末尾からコードを取り出す場所であり、トークンがその両方になることはできないからです。

そこでトークンは、プロトコルがそのための場所を持つところに載せます。**SASL** バインドの
認証情報は、メカニズム固有の形をしたオクテット列で、RFC 7628 の `OAUTHBEARER` の形は、GS2
ヘッダーに続くキー/値のペアで、そのうちの一つが `auth=Bearer <token>` です。

```
n,,^Aauth=Bearer eyJ…^A^A
```

パスワードフィールドには触れません。一つのリスナーで、同時に、ある人は末尾にコードを付けた
パスワードを入力し、別の人はトークンを送れます。

```hcl
oidc {
  issuer   = "https://login.example.org/realms/staff"   # the "iss" a token must carry, and where discovery starts
  audience = "ldap"                                     # this server's client id at the provider

  # username_claim = "preferred_username"   which claim names the person here
  # jwks_url       = "…"                    skips discovery, for a provider that does not publish it
  # allow_plaintext = true                  only when TLS is terminated in front of this process
}
```

`issuer` と `audience` は必須です。`username_claim` がなければ、名前は `preferred_username`、
次に `email_verified` が true の場合の `email`、次に `sub` です。このブロックがあると、
ルート DSE がメカニズムを通知します。

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' supportedSASLMechanisms
dn:
supportedSASLMechanisms: OAUTHBEARER
```

ブロックがなければ、すべての SASL バインドに `authMethodNotSupported` が返ります。
*この方法ではない*という意味で、クライアントを*間違ったパスワード*とは別のところへ向かわせます。

## ディスカバリーは起動時に行われる {#discovery-happens-at-startup}

プロバイダーのディスカバリードキュメントと鍵は、サーバーの起動時と `check` で読み込まれます。
到達できないプロバイダーがあれば、後になってすべてのバインドを拒否するのではなく、
誰かが見ている場でサーバーが止まります。

```
$ authnd check cases/oidc.hcl
authnd: oidc "https://127.0.0.1:1/realms/staff": oidc: reading https://127.0.0.1:1/realms/staff/.well-known/openid-configuration: Get "https://127.0.0.1:1/realms/staff/.well-known/openid-configuration": dial tcp 127.0.0.1:1: connect: connection refused
```

`https` でない発行者は、ループバックを除いて拒否されます。

```
$ authnd check cases/oidc-http.hcl
authnd: oidc "http://login.example.org/realms/staff": oidc: http://login.example.org/realms/staff is not https: the key set decides every signature, and over cleartext so does anybody on the way
```

## トークンは何要素か {#how-many-factors-is-a-token}

**発行者が確認したと述べるものであり、それ以上ではありません。** トークンは RFC 8176 の `amr`、
つまりプロバイダーが使った方法を運びます。それが存在する唯一の証拠なので、`mfa` ポリシーが
**種類ごとに**数えるのはそれです。

| `amr` の方法 | 種類 |
|---|---|
| `pwd`, `pin`, `kba`, `mca` | 知識 |
| `otp`, `hwk`, `swk`, `sms`, `tel`, `sc`, `pop`, `user`, `wia`, `mfa` | 所持 |
| `fpt`, `face`, `iris`, `retina`, `vbm`, `geo` | 生体 |
| それ以外 | 不明。`distinct_kinds` を満たすことは決してない |
| `amr` がまったくない | 一要素、所持 — トークンそのもの |

同じ種類の二つの方法は、一要素です。そうしなければ、このサーバーが誰も行っていない第二要素を
でっち上げることになります。そして、*誰*であるかについて発行者を信じるサーバーには、
*どのように*確認したかについて発行者を疑う別個の根拠がありません。

`mfa` ブロックがある場合、`check` はそれを述べます。

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

alice には `totp_secret` がないので、コード付きのパスワードでは決して足りません。`amr` が二つの
種類を示すトークンなら足ります。次の最初のバインドがそれを示しています。

## バインドの実際 {#what-the-binds-look-like}

ここでの発行者はループバック上の小さなテスト用プロバイダーで、`oidctool` はこれらのページの
ために書かれたテスト用クライアントです。指定された名前と指定された `amr` でトークンに署名し、
`OAUTHBEARER` バインドで送り (五番目の引数で指定すれば `authzid` 付き)、バインドの結果コードと
サーバーの SASL 認証情報を出力します。上記の設定に対して、`ldaps://` 経由で:

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

0 は成功、49 は `invalidCredentials`、14 は `saslBindInProgress` です。`["pwd","kba"]` の
トークンは同じ種類の二つの方法を示すので、一度として数えられます。そして `cert_file` と
`key_file` のない同じ設定の、平文リスナーに対しては:

```
$ ./oidctool alice '["pwd","otp"]' 127.0.0.1:3893 clear
bind result 13
```

13 は `confidentialityRequired` です。トークンは、暗号化されていない接続では受け付けられません。

`ldaps://` 経由で拒否された四つのバインドについて、サーバーが書いたもの:

```
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: mfa: the policy needs 2 factor(s) and 1 were offered
alice was refused: the token is for "alice" and asks to act as "tess"; this server does not delegate
zed was refused: the token verified, and no source here publishes anybody by that name
```

そして平文のものについて:

```
a token was refused: OAUTHBEARER was offered over a connection that is not encrypted, and allow_plaintext is not set
```

`OAUTHBEARER` バインドが成功すると、接続は `uid=<name>,ou=people,<base_dn>` としてバインドされた
状態になり、綴りは他のすべてのエントリと同じです。

## 拒否されるもの {#what-it-refuses}

- **平文のトークン。** ベアラートークンには相方がいりません。回線上でそれを読んだ者は、期限が
  切れるまでその人です。`allow_plaintext = true` は、このプロセスの手前で TLS を終端する
  デプロイのためにあり、その場合 `check` は *a token may cross this socket in the clear* と
  述べます。
- **他人になりすます要求。** GS2 ヘッダーは `authzid` を指名できます。alice のトークンが tess
  として動作する要求を伴っている場合は、どちらかとして静かに扱われることなく拒否されます。
- **ここのどのソースも公開していない人のトークン。** クライアントに告げられるのは
  `invalid_token` だけです。どの名前が存在するかは、一回の推測ごとに渡してよい情報ではありません。
  理由はサーバーの出力にあります。
- **チャネルバインディング。** `p=` を伴う GS2 ヘッダー、つまりクライアントがチャネルバインディングを
  主張するものは拒否されます。このサーバーはそれを行いません。何も束縛せずにヘッダーを受け入れると、
  クライアントがチャネルが検証されたと信じてしまいます。
- **このサーバーが話さないメカニズム**。`authMethodNotSupported` で拒否されます。

トークン自体の拒否は RFC 7628 §3.2.3 のもので、`openid-configuration` を含む JSON エラーが
`saslBindInProgress` として返され、クライアントは交換を終える `^A` を送れます。検証には
通ったが `mfa` ポリシーを満たさないトークンには、上の二番目と三番目のバインドが示すとおり、
単に `invalidCredentials` が返ります。

{{< callout type="info" >}}
**トークンはパスワードを設定しない**

トークンでしかサインインしたことのない人は、そのセッションを使って自分に最初のパスワードを
与えることはできず、パスワードを持っている人も、変更するにはそれを送らなければなりません。
[パスワードの変更]({{< relref "/authnd/passwords.md" >}})を参照してください。
{{< /callout >}}
