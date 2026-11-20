---
title: "kdcd — 一つのレルムのための Kerberos KDC デーモン"
linkTitle: "kdcd"
weight: 81
description: "go-authn/kdcd は kdc ライブラリの上に作られたプログラム: UDP と TCP の AS と TGS、HCL ファイル一つ、秘密はすべてファイル、そしてパスワードのない人のために TGT を発行する任意の相互 TLS リスナー。"
tags: [ライブラリ, kerberos, ディレクトリ, kdcd]
---

**[kdc]({{< relref "/libraries/kdc.md" >}}) ライブラリはどうサービスとして動かすか。**
`kdcd` は、ライブラリ [go-authn/kdc](https://github.com/go-authn/kdc) の上に作られた、
一つのレルムのための Kerberos KDC デーモンです。AS と TGS のリクエストを UDP と TCP で
受け付け、任意で、別の場所で本人確認を済ませた人(
[go-authn/bridge](https://github.com/go-authn/bridge) でのパスキーによるログイン)のために、
相互 TLS で **TGT を発行(mint)** します。プロトコルはライブラリが持ち、このプログラムは
ソケットと設定と秘密の扱いの規則を持ちます。

```
kdcd check --config /etc/kdcd/kdcd.hcl
kdcd       --config /etc/kdcd/kdcd.hcl
```

インストール(バイナリは `kdcd`。MIT の KDC は `krb5kdc`、Heimdal の KDC は `kdc`):

```
go install github.com/go-authn/kdcd/cmd/kdcd@latest
```

純粋な Go で `CGO_ENABLED=0`。リリースにはバイナリごとに `SHA256SUMS` マニフェストと
ビルドの来歴証明が付きます。サービスとして: `packaging/systemd/`(ユニットと sysusers
ファイル。[実行する](#running-it)を参照)。

## ディレクトリが保持すべきもの {#what-the-directory-must-hold}

KDC はクライアントの事前認証をその人の長期鍵で復号するので、**AS-REQ** に応答できるのは、
ソースが**パスワード**を保持する人だけです。つまり `password_file` を持つ `user` ブロック、
またはパスワードを返す `users "sql"` ブロックです。パスワードを*検証*することしかできない
ソース(他人の LDAP へのバインド、ハッシュ)は、「これはパスワードか」にどれほどうまく
答えても、AS-REQ には応答できません。これは Kerberos の性質であり、
[ライブラリのドキュメント](https://github.com/go-authn/kdc#readme)と
[kdc のページ]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}})で説明しています。

パスキー時代のレルムには、そのどれも要りません。**パスワードのない**人(`user "alice" {}`
ブロック、または任意の `users` ブロックの一行)はディレクトリにいて、鍵を持たず、AS-REQ は
`KDC_ERR_NULL_KEY` で拒否されます。TGT を得られるのは、その人を認証した呼び出し元からの
**mint リスナー**経由だけです。`kdcd` は独自のパスワード経路を加えません。フラグも、
環境変数も、インライン値もありません。`password_file` があるのは、ライブラリの AS 経路が
それを必要とするからです。

## 設定 {#configuration}

HCL ファイル一つ。中に秘密はなく、秘密はすべてファイルです。

```hcl
realm       = "POC.TEST"                 # a DNS name in capitals
keytab_file = "/etc/kdcd/kdc.keytab"     # krbtgt/POC.TEST + the services below
services    = ["cifs/fs.poc.test"]       # optional: refuse to start without these keys
lifetime    = "10h"                      # optional, 1m to 24h (default 10h)
max_skew    = "5m"                       # optional, 1s to 15m (default 5m)

listen {
  address = "127.0.0.1:88"               # IP:port, UDP and TCP; the default
  # allow_wildcard = true                # needed for 0.0.0.0 or [::]
}

mint {                                    # optional: absent, there is no second listener
  address        = "127.0.0.1:8443"      # an interface, never the wildcard
  cert_file      = "/etc/kdcd/mint.pem"  # this listener's certificate
  key_file       = "/etc/kdcd/mint.key"
  client_ca_file = "/etc/kdcd/callers-ca.pem"
  callers        = ["https://login.poc.test"]   # URI subjectAltNames, matched exactly
}

# The directory: any number of these, in any mix.
user "alice" {}                           # a person with no password: mint only
user "bob" { password_file = "/etc/kdcd/bob.pw" }

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"
  users    = "select login, password from staff"
}
users "ldap" {
  url                = "ldaps://ldap.example.org"
  base_dn            = "ou=people,dc=example,dc=org"
  bind_dn            = "cn=reader,dc=example,dc=org"
  bind_password_file = "/etc/kdcd/bind.pw"
}
```

`users` ブロックは [go-authn/directory/hcldir](https://github.com/go-authn/directory) のものを
そのまま使います。LDAP サーバーへのバインドのように、パスワードを検証することしかできない
ソースは、mint の呼び出し元がプリンシパルを照合するためのディレクトリを提供しますが、
AS-REQ には応答できません。

`kdcd check --config FILE` は、デーモンが構築するものをすべて読み込んで構築し、ディレクトリを
開き、どこにも listen せずに、提供する内容を表示します。レルム、アドレス、キータブの
プリンシパル(名前、kvno、etype。鍵は決して表示しない)、ディレクトリが保持する人数、
mint の呼び出し元です。終了ステータス 0 で最後の行が `ok`、またはその最初の拒否です。

### 起動を拒否するもの {#what-it-refuses-to-start-with}

| 拒否されるもの | 理由 |
| --- | --- |
| **グループまたは他者が読み書きできる**、あるいは root かデーモン以外の uid が所有するキータブ、mint 鍵、パスワードファイル、DSN、バインドパスワード | 他のアカウントが読めるコピーは、レルムのすべての人のチケットを偽造する |
| インラインで書かれた秘密(`password = "..."` は引数ではない) | 秘密はファイルにあり、設定にも、そのバックアップにも、ログにも置かない |
| グループまたは他者が書き込める設定ファイル | それを書く人が mint の呼び出し元を選ぶ |
| `krbtgt/REALM` の鍵がない、または列挙したサービスが欠けているキータブ。**aes256-cts-hmac-sha1-96 で**(ライブラリが発行する唯一のタイプ) | 起動はしても、最初の `kinit` で失敗する |
| `listen` のワイルドカードまたはホスト名(IP リテラルが必須)、および `mint` の**あらゆる**ワイルドカード | KDC と mint リスナーは、誰かが選んだインターフェース上にある |
| 呼び出し元がない、証明書がない、または期限切れの `mint` ブロック | ライブラリは呼び出し元なしを「mint オフ」と読む。これは黙って何も発行しない代わりに、そう告げる |
| `start_tls` なしで別のマシンへの `ldap://` | すべてのパスワードが入力されたままネットワークを流れる |

秘密ファイルは**一度だけ**開かれ、開いたファイルが検査されます(通常ファイル、モード、
所有者)。したがって検査が一つのファイルについてで、読み取りが別のファイルについて、
ということは起こりません(手本は go-fileshare の `readKeytab`)。`dsn_file` と
`bind_password_file` は、同じ検査を済ませた後に `hcldir` が名前で読みます。

## mint の信頼モデル {#the-mint-trust-model}

`POST https://<mint address>/mint` に `{"principal": "alice", "lifetime_seconds": 36000}` を
送ると、`alice` の TGT を収めた KRB-CRED(RFC 4120 5.8)が返ります。呼び出し元はそれを
本人のマシンに渡します([go-authn/kinit](https://github.com/go-authn/kinit) が Windows の
ログオンセッションに読み込みます)。それを縛るもの:

- **呼び出し元は TLS クライアント証明書**で、リスナーが `client_ca_file` に対して検証します
  (TLS 1.3、`RequireAndVerifyClientCert`)。証明書がない、または CA が署名していない
  接続は、HTTP が読まれる前にハンドシェイクで失敗します。検証された証明書は次に、
  **URI subjectAltName** で `callers` と厳密に照合されます。検証は通るが列挙されていない
  証明書は `403` です。ヘッダーにもボディにも、呼び出し元を名指すものはありません。
- **`callers` にいる者は、ディレクトリ内の任意のプリンシパルの TGT を取得できます**
  (サービスは決して、ディレクトリにない名前も決して)。その人の鍵なしで、です。
  レルムが信頼するのは呼び出し元によるその人の認証なので、呼び出し元は KDC のキータブと
  同じだけ信頼されます。ID プロバイダーごとに一つ列挙し、それぞれに専用の証明書を与え、
  `client_ca_file` は他に何も署名しない CA にしてください。
- チケットは `INITIAL | PRE-AUTHENT` で、更新可能・転送可能・代理可能には決してなりません。
  有効期間は、リクエスト、`lifetime`、10 時間のうち最小のものです。
- セッション鍵は `crypto/rand` から作られ、応答の中で一度だけプロセスを離れ、ログには
  決して書かれません。応答は `Cache-Control: no-store` です。KRB-CRED は鍵を平文で
  運ぶので、**TLS チャネルが暗号化そのもの**です。リスナーは内部インターフェースに置いてください。
- 提供されるのは `/mint` だけで、タイムアウトとヘッダー上限があります。すべての mint と
  すべての拒否は、呼び出し元の URI と要求されたプリンシパルとともにログに記録されます。

完全な脅威モデルはライブラリのプルリクエスト
[go-authn/kdc#38](https://github.com/go-authn/kdc/pull/38) のもので、ライブラリの README の
[発行の節](https://github.com/go-authn/kdc#a-tgt-for-a-person-with-no-key-minting)と
[監査ノート](https://github.com/go-authn/kdc#what-an-unauthenticated-peer-can-and-cannot-do-v045-audit)が
付きます。ここではそのどれも繰り返さず、弱めもしません。
[go-authn/bridge](https://github.com/go-authn/bridge) の `kerberos` ブロックが呼び出し元の側です。
その `kdc_url` は `https://<mint address>/mint`、その `ca_file` が上の `cert_file` に署名し、
そのクライアント証明書の URI 名が `callers` の項目になります。

## 実行する {#running-it}

`packaging/systemd/kdcd.service` は、`packaging/sysusers.d/kdcd.conf` のシステムユーザーとして、
[authn-bridge](https://github.com/go-authn/bridge) のユニットと同じ堅牢化を施して実行します。
ポート 88 は特権ポートなので、ユニットは `CAP_NET_BIND_SERVICE` だけを、他には何も与えません。

```
install -d -m 0750 -o root -g kdcd /etc/kdcd
install -m 0640 -o root -g kdcd kdcd.hcl /etc/kdcd/       # no secret in it
install -m 0600 -o kdcd -g kdcd kdc.keytab mint.key /etc/kdcd/
systemctl enable --now kdcd
```

秘密は `kdcd`(または root)の所有でモード 0600 にします。グループ `kdcd` の 0640 は
意図的に拒否されます。設定の変更は `systemctl restart kdcd` です(デーモンは再読み込みを
せず、クライアントは拒否された接続を再試行します)。

Windows ではモードビットは意味を持たず、検査されません。サービスを実行するアカウントだけが
読める場所にファイルを置いてください。

## ここにないもの {#not-here}

クロスレルム、PKINIT、FAST、更新可能または後日付のチケット、kadmin プロトコル、
aes256-cts-hmac-sha1-96 以外のあらゆる暗号化タイプは、ライブラリ自身の制限です
([go-authn/kdc](https://github.com/go-authn/kdc#readme))。`kdcd` にはまだ再読み込みも
メトリクスのエンドポイントもありません。

## リファレンス {#reference}

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd)、v0.1.0。
