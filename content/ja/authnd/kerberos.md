---
title: "同じ人々のための Kerberos レルム"
linkTitle: "Kerberos レルム"
weight: 60
description: "kerberos ブロック、チケットへの署名に使うキータブ、チケットを発行できる人と決して発行できない人がいる理由、そして mfa ブロックと併用できない理由。"
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

`kerberos` ブロックは、[go-authn/kdc]({{< relref "/libraries/_index.md" >}}) を通じて、authnd を
ディレクトリであると同時に KDC にします。同じ人々が、参照されるだけでなくチケットを
発行されます。UDP と TCP の両方で同じアドレスで応答し、暗号化タイムスタンプによる事前認証を
要求し、`aes256-cts-hmac-sha1-96` のチケットのみを発行します。`lifetime` は Go の期間
(`"10h"`、`"90m"`) です。ディレクトリとレルムは対等です。どちらかが止まれば
プロセスが止まります。KDC が死んだ後も LDAP に応答し続けるサーバーは、Kerberos を話さない
すべてのものにとって健全に見えてしまうからです。

起動時に拒否されるもの:

```
$ authnd check cases/realm-lower.hcl
authnd: kerberos: realm "example.org" is not upper case: clients uppercase the realm they derive from a domain, and would then ask for a realm this server does not answer for
```

名前のないレルム、キータブのないレルム、解析できないアドレス、Go が読めない `lifetime`、
そして `mfa` ブロックと並んだ `kerberos` ブロック (後述) も同様です。

## キータブ {#the-keytab}

キータブには、authnd が自分のチケットに署名する鍵 (`krbtgt/REALM@REALM`) と、チケットを
発行するサービスごとの鍵が一つずつ入っています。これらのサービスが読むのと同じファイルです。
krbtgt のパスワードは二度と入力されないので、ランダムにしてください。MIT の `ktutil`
(Debian と Ubuntu ではパッケージ `krb5-user`) を使う場合です。この手順は
`docs/install.md` にあるものと同じで、これらのページのために実行したものではありません。

```sh
printf 'addent -password -p krbtgt/EXAMPLE.ORG@EXAMPLE.ORG -k 1 -e aes256-cts-hmac-sha1-96\n%s\nwkt /tmp/krb5.keytab\nquit\n' \
  "$(head -c 32 /dev/urandom | base64)" | ktutil
sudo install -o root -g authnd -m 0640 /tmp/krb5.keytab /etc/authnd/krb5.keytab
rm /tmp/krb5.keytab
```

サービスの鍵も同じ方法で追加し (`-p nfs/files.example.org@EXAMPLE.ORG`)、そのサービスに、
自身のキータブで同じ鍵を渡してください。macOS では、Heimdal の
`ktutil -k <file> add -r -p <principal> -V 1 -e aes256-cts-hmac-sha1-96`
がパスワードなしでランダムな鍵を書き込みます。どちらの場合も、起動する前にキータブを
読み戻してください (MIT なら `klist -k`、Heimdal なら `ktutil -k <file> list`)。

```
$ ktutil -k etc/authnd/krb5.keytab list
etc/authnd/krb5.keytab:

Vno  Type                     Principal                       Aliases
  1  aes256-cts-hmac-sha1-96  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG  
```

`krbtgt/REALM` のないキータブは、`check` と起動時に拒否されます。
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}})を参照してください。
キータブは起動時に一度だけ読み込まれます。置き換えるには再起動が必要です。

## チケットを発行できる人 {#who-can-be-issued-a-ticket}

KDC は、クライアントの事前認証を、その人の長期鍵で**復号**しなければならないので、
その人の**パスワード**が必要です。パスワードを検証する手段があるだけでは足りません。
`check` は、誰が発行でき、誰が発行できないかを、理由とともに示します。

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

| ソースが持つもの | チケット |
|---|---|
| パスワード (`password`、`password_file`、SQL のパスワード列) | 可 |
| NT ハッシュのみ | **不可**: それは RC4-HMAC 鍵であり、このレルムは AES のみを発行する |
| パスワードの検証のみ (この背後にある `users "ldap"` ディレクトリ) | **不可**: パスワードを検証するだけのソースは、鍵を生成できない |

このディレクトリの背後にあるディレクトリの場合、レルム部分の最後の行は
*alice, bob, dora and eli: the source only verifies a password, so it cannot
produce any key* となります。これは設定の問題ではなく構造上のことであり、
`check` で見つけるほうが、正しいパスワードが間違いだと `kinit` に言われた人から
知らされるよりもずっとましです。

## kinit で試す {#kinit-against-it}

この KDC を指定する `krb5.conf` です。⛔ MIT Kerberos では、波括弧を独立した行に置いてください。
そのパーサーは、一行で書かれたレルムを黙って無視します。

```ini
[libdefaults]
    default_realm = EXAMPLE.ORG
    dns_lookup_kdc = false
[realms]
    EXAMPLE.ORG = {
        kdc = 127.0.0.1:18388
    }
```

同じ設定を提供し、macOS の Heimdal `kinit` で問い合わせた結果です
(`--password-file` はファイルからパスワードを読み込みます)。

```
$ authnd --config realm
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
realm EXAMPLE.ORG on 127.0.0.1:18388 (udp and tcp)

$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
$ klist
Credentials cache: FILE:ccache
        Principal: alice@EXAMPLE.ORG

  Issued                Expires               Principal
Oct 18 16:10:19 2026  Oct 19 02:10:19 2026  krbtgt/EXAMPLE.ORG@EXAMPLE.ORG

$ kinit --password-file=wrong.pwin alice@EXAMPLE.ORG
kinit: Password incorrect

$ kinit --password-file=bob.pwin bob@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: this realm holds no Kerberos key for that principal

$ kinit --password-file=dora.pwin zed@EXAMPLE.ORG
kinit: krb5_get_init_creds: Error from KDC: no such principal in this realm
```

チケットの有効期間は既定の十時間です。bob は NT ハッシュの元になったパスワードを入力しましたが、
それでも拒否されます。レルムには bob の鍵がないからです。KDC は、拒否したものを Kerberos の
エラーコードとともに出力に書き出します。

```
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication required (code 25)
kerberos: the timestamp does not decrypt (client etype 18, our key type 18): error decrypting: integrity verification failed
kerberos: refused krbtgt/EXAMPLE.ORG: pre-authentication does not decrypt (code 24)
kerberos: refused krbtgt/EXAMPLE.ORG: this realm holds no Kerberos key for that principal (code 9)
kerberos: refused krbtgt/EXAMPLE.ORG: no such principal in this realm (code 6)
```

*Pre-authentication required* は `kinit` の通常の最初のやり取りです。クライアントは事前認証なしで
要求し、それが必要だと告げられ、その後事前認証を付けてもう一度要求します。alice の成功した
`kinit` が残すのは、その行だけです。

{{< callout type="info" >}}
**どの名前が存在するかはレルムが教え、ディレクトリは教えない**

誰も持っていない名前に対する LDAP バインドには `invalidCredentials` が返ります。間違った
パスワードの場合と同じです。KDC は、Kerberos の KDC がそうするように、
*no such principal in this realm* (`KDC_ERR_C_PRINCIPAL_UNKNOWN`、コード 6) を返します。
他者が到達できるアドレスに `kerberos` ブロックを置くと、名前の一覧は、どの KDC でもそう
であるのと同程度に推測可能になります。`listen` の既定値はループバックです。
{{< /callout >}}

## LDAP で変更されたパスワード {#a-password-changed-over-ldap}

KDC はディレクトリが提供するのと同じ人々を読むので、
[LDAP で変更されたパスワード]({{< relref "/authnd/passwords.md" >}})は直ちにレルムに
反映されます。古いパスワードは、バインドで使えなくなった瞬間に `kinit` でも使えなくなります。

```
$ ldappasswd -x -H ldap://127.0.0.1:3893 -D uid=alice,ou=people,dc=example,dc=org -y alice.pwin -t alice.pwin -T alice.new
$ kinit --password-file=alice.pwin alice@EXAMPLE.ORG
kinit: Password incorrect
$ kinit --password-file=alice.new alice@EXAMPLE.ORG
$
```

## `mfa` ブロックと併用できない {#not-beside-an-mfa-block}

```
$ authnd check cases/krb-mfa.hcl
authnd: kerberos and mfa together: the mfa block asks every bind for a password AND a code, and a kinit carries only the password -- this KDC has no second-factor pre-authentication, so a realm here would accept one factor where the mfa block demands two. Remove one of the blocks
```

RFC 4120 の暗号化タイムスタンプによる事前認証は、パスワードのみを鍵とします。第二要素には、
FAST (RFC 6113) 内の OTP 事前認証 (RFC 6560) が必要ですが、この KDC はそれを実装していません。
ここにレルムがあると、[`mfa` ブロック]({{< relref "/authnd/mfa.md" >}})が二要素を必要と
している人々に、一要素でチケットを配ってしまいます。チケットはバインドが開くものすべてを開く
ので、選択は閉じる側に倒されています。どちらか一方だけです。

## ポート {#ports}

88 は特権ポートです。パッケージ付属のユニットでは `CAP_NET_BIND_SERVICE` がそれを賄います。
通常のユーザーとして実行するサーバーには、上記のように高いポートと、それを指定する
`krb5.conf` が必要です。
