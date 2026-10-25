---
title: "フィールドが一つしかないプロトコルでの第二要素"
linkTitle: "第二要素"
weight: 70
description: "mfa ブロック: パスワードの末尾に付けるワンタイムコード、その分割と検証の方法、誰に対して何が数えられるか、そしてこの下でバインドできない人。"
tags: [authnd, mfa, totp]
---

LDAP の単純バインドが運ぶのは名前とパスワードだけです。コードの置き場所も、それを尋ねる
往復もなく、LDAP を話すクライアントがそれを覚えることもありません。そこでコードを
パスワードの**末尾**に付けます。これはそうした機器が行っていることで、人々がすでに入力の
仕方を知っているやり方です。

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

| キー | 既定値 | |
|---|---|---|
| `factors` | 2 | 1 は拒否されます (*a password and nothing else: remove the block, or ask for 2*)。2 を超える値も拒否されます。バインドが運ぶのはパスワードとコードであり、三つ目のものはないためです |
| `distinct_kinds` | `false` | 要素は異なる種類でなければなりません。「二要素」が通常意味するものです |
| `digits` | 6 | 6 から 10 (RFC 4226) |
| `period` | 30 | 一つのコードが有効な秒数 |
| `window` | 1 | 時計のずれに備えて、現在の前後それぞれ何ステップまで受け入れるか。各ステップは他人が推測できる時間のステップでもあるので、意図して設定してください |
| `readers` | `false` | [reader]({{< relref "/authnd/_index.md#who-may-bind-and-who-may-read" >}})もコードを持つかどうか。サービスアカウントには電話がありません。持つものには `reader` ブロックに `totp_secret` を与えます |

シークレットは、データベースの列 (五番目) や LDAP 属性 (`totp_attribute`) から渡すこともできます。
[人々]({{< relref "/authnd/people.md" >}})を参照してください。`user` または `reader` ブロックの
`totp_secret` が 128 ビット (RFC 4226 R6) に満たない場合は、後でその人のログインがすべて失敗する
のではなく、その人の名前を挙げてサーバーが止まります。

```
$ authnd check cases/shorttotp.hcl
authnd: user "alice": totp_secret is 80 bits, and RFC 4226 requires at least 128: enrol again with a longer secret
```

## この下でバインドできない人 {#who-cannot-bind-under-it}

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

これが、ブロックを有効にする前に問うべきことです。

## バインドの実際 {#what-the-binds-look-like}

同じ設定を提供し、tess のコードをバインドの瞬間にそのシークレットから計算した結果です。

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

`tess.only` はコードなしの tess のパスワード、`tess.both` は同じパスワードと現在のコードで、
二回送っています。`tess.badcode` はそのパスワードと `000000`、`alice.code` は alice のパスワードと
六桁の数字です。クライアントに告げられるのは、どちらの半分が間違っていても一つのことだけ、
つまり *invalid credentials* です。どちらが間違っていたかはアカウントに関する事実であり、
何も証明していない人にそれを告げると、次の推測の範囲が狭まってしまいます。サーバー自身の
出力はどちらかを示します。

```
tess was refused: mfa: 2 factor(s) needed, 0 answered: your password (knowledge): directory: wrong password; your authenticator app (possession): not looked at, since the password in front of it was wrong
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code has already been used
tess was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): totp: that code is not right
alice was refused: mfa: 2 factor(s) needed, 1 answered: your authenticator app (possession): not available
  your authenticator app: mfa: this factor cannot be asked here: totp: nobody enrolled an authenticator for this person
```

## 一つのフィールドから導かれること {#what-follows-from-the-one-field}

- **分割は長さで行います。** 末尾の `digits` 文字がコードです。数字で終わるパスワードでも
  問題ありません。tess のパスワードだけが、間違ったパスワードにコードが続いたものとして
  読まれたのはそのためです。コード*以下*の長さのフィールドは、推測せずに拒否されます。
  短いパスワードは、コードと区別できないためです。
- **両方の半分が常に検証されます。** 間違ったパスワードで早期に返ると、かかった時間から
  どちらの半分が間違っていたかが分かってしまいます。
- **コードは一度しか使えません。** コードは一ステップ全体の間有効なので、二度受け入れる
  サーバーはリプレイを受け入れることになります。最後に受け入れられたステップまでのすべての
  ステップが、同じものだけでなく拒否されます。
- **推測は名前ごとに制限されます。** go-authn/totp の既定値に従い、連続して五回間違ったコードを
  入力すると、その人は十五分間拒否されます。正しいコードも含めてです。百回間違えると、authnd が
  再起動するまでロックアウトされます。カウントはプロセスごとにメモリ上で保持されます。
- **正しいパスワードの背後にあるコードだけが数えられます。** そうでなければ、名前を知っている
  誰でも、五回のバインドでその持ち主を凍結できてしまいます。間違ったパスワードの背後でも
  コードは計算されますが、何も記憶しないものに対して行われます。上の出力の一行目、
  *not looked at* がそれです。
- **reader は、設定が綴ったとおりの DN の下で数えられます。** そのため `CN=Reader` に
  新たな予算が与えられることはありません。
- **誰も登録していないことは、間違ったコードではありません。** シークレットのない人は、
  間違って答えたのではなく、何も答えていないのであり、サーバーの出力は
  *nobody enrolled an authenticator for this person* と述べます。

## レルムとは併用できない {#not-with-a-realm}

一つの設定に `kerberos` ブロックと `mfa` ブロックがあると拒否されます。`kinit` が証明するのは
パスワードだけで、この KDC には第二要素の事前認証がないためです。
[レルム]({{< relref "/authnd/kerberos.md#not-beside-an-mfa-block" >}})を参照してください。

## 同じポリシーの下でのトークン {#tokens-under-the-same-policy}

[`oidc` ブロック]({{< relref "/authnd/tokens.md" >}})によるバインド時のトークンは、発行者が
確認したと述べるもの、つまり `amr` クレームによって数えられます。`amr` のないトークンは
一要素であり、このポリシーはそれを拒否します。
