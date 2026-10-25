---
title: "本人による自分のパスワードの変更"
linkTitle: "パスワードの変更"
weight: 50
description: "authnd が受け付ける唯一の書き込み: 本人自身のパスワード。RFC 3062 または RFC 4511 の modify を使い、必ず古いパスワードを伴い、その人を宣言しているファイルに書き戻される。"
tags: [authnd, パスワード, ldappasswd]
---

人は、RFC 3062 のパスワード変更操作 (`ldappasswd` が送るもの) または RFC 4511 の modify を
通じて、**自分自身の**パスワードを、他の誰のものでもなく変更できます。どちらの場合も、
**接続が何でバインドしたかにかかわらず、現在のパスワードを新しいパスワードと一緒に
送らなければなりません**。[OAUTHBEARER トークン]({{< relref "/authnd/tokens.md" >}})でバインド
したセッションは、短命で、場合によっては一要素ですが、そうでなければ、それを `kinit` でも使える
恒久的なパスワードに変えられてしまうからです。

これは `pwdSafeModify` を設定した OpenLDAP の ppolicy の動作で、その `ppolicy.c` が返す
結果コードを返します。RFC 3062 §3 はこれを認めています。"If oldPasswd is
not present, the server MAY use other policy to determine whether or not to
change the password."

## `ldappasswd` で {#with-ldappasswd}

`-t` は古いパスワードを入れたファイル、`-T` は新しいパスワードを入れたファイルです。
`-A` と `-S` は代わりにプロンプトで尋ねます。

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -T alice.new
Result: Insufficient access (50)
Additional info: a password change must send the old password with the new one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t wrong.pwin -T alice.new
Result: Server is unwilling to perform (53)
Additional info: the old password sent is not the current one

$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin
ldap_bind: Invalid credentials (49)

$ ldapwhoami -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.new
dn:uid=alice,ou=people,dc=example,dc=org
```

古いパスワードは直ちに使えなくなります。バインドでも、[レルム]({{< relref "/authnd/kerberos.md#a-password-changed-over-ldap" >}})が
あれば `kinit` でもです。サーバーは出力でそのことを述べます。

```
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password
```

authnd はパスワードを生成しません。新しいパスワードのない要求は `unwillingToPerform` で拒否されます
(*this server does not generate passwords: send the
one you want*)。生成したパスワードは接続越しに送り返さなければならず、そのパスワードが
確実にたどり着く場所は、端末のスクロールバックです。

## `ldapmodify` で {#with-ldapmodify}

変更は、**古い値の削除に続けて新しい値を追加する、一回の要求**です。RFC 4511 §4.6 は modify の
変更を順番に、アトミックに適用するので、削除される値が保持している値でなければ、削除が、
したがって要求全体が失敗します。

```
dn: uid=alice,ou=people,dc=example,dc=org
changetype: modify
delete: userPassword
userPassword: alice-test-pw
-
add: userPassword
userPassword: alice-new-pw
-
```

単なる `replace` は何も証明せず、`userPassword` 以外はこのサーバーが変更するものではありません。

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f replace.ldif
ldap_modify: Insufficient access (50)
	additional info: a password change must send the old password with the new one
modifying entry "uid=alice,ou=people,dc=example,dc=org"

$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f other.ldif
ldap_modify: Server is unwilling to perform (53)
	additional info: this server changes userPassword and nothing else, not cn
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

パスワード**と**それ以外を求める modify は、全体が拒否されます。modify はアトミックであり、
その半分だけを受け入れると、誰も求めていないことについて成功を報告してしまうからです。

## 誰が何を変更できるか {#who-can-change-what}

| 要求 | 応答 |
|---|---|
| 古いパスワードがない、または単なる `replace: userPassword` | `insufficientAccessRights` |
| 現在のものではない古いパスワード | `unwillingToPerform` |
| 他人のエントリ | `insufficientAccessRights`、*a password may be changed only by the person it belongs to* |
| 匿名の接続 | `insufficientAccessRights`、*an anonymous connection has not said who it is* |
| パスワードをまったく持たない人 — トークンでしかバインドできていない場合 | `unwillingToPerform`: ベアラートークンはパスワードではなく、最初のパスワードを設定しません。管理者が設定で設定します |
| `users` ブロックから提供されている人 | `unwillingToPerform`: authnd はそれらのソースを読むだけで書き込みません |
| ファイルに書き込めない | `other` (80)、*the password could not be written*。理由はサーバーの出力にあります |

最後から二番目の例を、SQLite データベース由来の dora について、リリースバイナリから示します。

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=dora,ou=people,dc=example,dc=org -y dora.pwin -t dora.pwin -T dora.new
Result: Server is unwilling to perform (53)
Additional info: dora is served from a sqlite database, which this server reads and does not write
```

人は**DN ではなく ID で**照合されます。セッション自身の名前が対象の名前とバイト単位で
完全に一致しなければならないので、`uid=Backup` としてバインドしたセッションは、二つの DN が
等しいと比較されても `backup` のパスワードを変更できません。これと、
[大文字小文字だけが異なる名前の拒否]({{< relref "/authnd/people.md#order-and-the-one-exception" >}})は、
互いに依存しない二つの統制です。

## 新しいパスワードの書き込み先 {#where-the-new-password-is-written}

**その人を宣言しているファイル**に書き戻され、他のどこにも書かれません。

- `password_file` を持つ `user` ブロックでは、**そのファイル**が書き換えられます。
  プロセスに可能な範囲で所有者とグループが保たれ、モードは最大でも 0600 に狭められます。
  広げられることはありません。
- `password` をインラインで持つ `user` ブロックでは、設定ファイルが新しい値で書き換えられ、
  コメント、順序、モードは保たれます。
- `nt_hash` だけを持つ `user` ブロックには、パスワードは与えられません。それはその人を
  証明するものを変えることになり、設定の変更だからです。

すべての書き込みは、**同じディレクトリ内**の一時ファイルに対して行われ、その後リネームされます。
そのため、ディスクが満杯になったりクラッシュしたりしても、空のファイルではなく古いパスワードが
残ります。そのためにはディレクトリへの書き込み権限が必要です。パッケージ付属のユニットでは
`ProtectSystem=strict` がそれを取り上げており、変更は次のように拒否されます。

```
$ ldapmodify -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -f safe.ldif
ldap_modify: Other (e.g., implementation specific) error (80)
	additional info: the password could not be written
modifying entry "uid=alice,ou=people,dc=example,dc=org"
```

理由はサーバーの出力にあります。

```
changing the password for alice: etc/authnd/passwords/alice.pw: open etc/authnd/passwords/.hcldir-863420940: permission denied
```

そのため、パスワードはサービスが書き込める専用のディレクトリに置き、設定はサービスに対して
読み取り専用にしてください。
[`ReadWritePaths=` ドロップイン]({{< relref "/authnd/install.md#the-configuration-directory" >}})
です。パスワードがインラインで書かれている人には `/etc/authnd` 自体が書き込み可能である必要が
あり、それではサービスが自分自身の設定を書き換えられるようにもなってしまいます。

書き込みに成功すると、設定ファイルは**`user` ブロックについてだけ**再度読み込まれます。
ディスク上で待機している無関係な編集が、誰かのパスワード変更のせいで中途半端に有効になる
ことはありません。それ以外のすべては引き続き再起動を待ちます。ただしファイルは全体が読まれる
ため、そのうちの一つがもう読み込めなくなっていれば、パスワードは書き込まれ、クライアントには
*the password was written but this server did not reload it* と告げられます。稼働中のサーバーは、
再起動されるまで古いものを保持します。
