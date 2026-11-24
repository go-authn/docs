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

## パスワードなし {#no-passwords}

`kdcd` はライブラリの `AllowPasswordDerivedAS`（kdc v0.11.0 以降は既定で無効）を
決して有効にせず、有効にするオプションもありません。

**`kdcd` にはパスワード経路がなく、有効にすることもできません**(v0.2.0 で削除。
v0.1.0 には `password_file` がありました)。ここでは人は長期鍵を持たないので、人に対する
**AS-REQ** は、クライアントが何を送っても、設計上 `KDC_ERR_NULL_KEY` で応答されます。
人が TGT を得られるのは、パスキー(go-authn/bridge)でその人を認証した呼び出し元からの
**mint リスナー**経由だけです。

- ディレクトリは**誰が存在するか、そしてそのグループ**を述べます。ソースが運ぶもののうち、
  名前以外は KDC に届きません。すべての ID は、ライブラリが目にする前に名前だけで再構築
  されるので(`nameOnly`)、ソースが公開したパスワードでさえ鍵を導出しません。以下のロード時の
  拒否は理由を告げるためにあり、唯一の防御ではありません。
- サービスと `krbtgt/REALM` は鍵をキータブに保持します。**ランダムな鍵**で、パスワードから
  導出されることは決してありません(たとえば、キータブのツールで `/dev/urandom` の 32 バイトから
  生成してください)。
- `password_file`、パスワードまたは NT ハッシュの列を指す `users` のクエリや属性、
  `bind_password_file`、`bind_dn`(単純バインドはパスワードです)、パスワードを含む DSN:
  ロード時に、削除とバージョンを示して拒否されます。
- `ldap` ソースは**匿名で**読み取られます。クライアント証明書または SASL EXTERNAL による
  サービスバインドは、`go-authn/directory` の `hcldir.Block` にそのためのフィールドが
  ないため、まだ使えません。それができるまで、`bind_dn` は拒否されます。

ライブラリ側の説明は [kdc のページ]({{< relref "/libraries/kdc.md#only-a-source-holding-the-password-can-back-a-realm" >}})にあります。

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

# The directory: who exists. Any number of these, in any mix.
user "alice@poc.test" {}                  # a name; a TGT only through mint

users "sql" {                             # go-authn/directory hcldir blocks
  driver   = "postgres"                   # sqlite, postgres or mysql
  dsn_file = "/etc/kdcd/dsn"              # no password in it: a client certificate or a socket
  users    = "select login as name from staff"
}
users "ldap" {                            # read anonymously
  url      = "ldaps://ldap.example.org"
  base_dn  = "ou=people,dc=example,dc=org"
}
```

`users` ブロックは [go-authn/directory/hcldir](https://github.com/go-authn/directory) のものです。
kdcd は、そのうちパスワードを運ぶ部分を拒否します(上を参照)。

**シークレット: ファイルか参照か。** `keytab_file` と `key_file`（`mint` 内）はファイルを指し、後述のとおり検査されます。代わりに `keytab_from` と `key_from` には secretsource の参照、たとえば `systemd-creds:kdc-keytab` を書けます。これは systemd がサービスのために復号するクレデンシャルです（`LoadCredentialEncrypted=`、`systemd-creds encrypt --with-key=host+tpm2` で封印。`--tpm2-pcrs=7` だけは使わない）。どちらか一方だけを指定します。`_from` キーでは `file:` は拒否されます。`keytab_file` は残り、非推奨ではありません。keytab と鍵はバイナリで、`file:` は末尾の改行を 1 つ取り除くため（末尾がバイト 0x0a の鍵が壊れます）、また参照は最大 4096 バイトなので、それより大きい keytab は `keytab_file` に置きます。secretsource v0.9.0 以降、`file:` はシンボリックリンクと他の uid が所有するファイルも拒否します。`dsn_file` はパスワードを含まないので `_from` はありません。

`kdcd check --config FILE` は、デーモンが構築するものをすべて読み込んで構築し、ディレクトリを
開き、どこにも listen せずに、提供する内容を表示します。レルム、アドレス、キータブの
プリンシパル(名前、kvno、etype。鍵は決して表示しない)、ディレクトリが保持する人数、
mint の呼び出し元です。終了ステータス 0 で最後の行が `ok`、またはその最初の拒否です。

### 起動を拒否するもの {#what-it-refuses-to-start-with}

| 拒否されるもの | 理由 |
| --- | --- |
| **グループまたは他者が読み書きできる**、あるいは root かデーモン以外の uid が所有するキータブ、mint 鍵、DSN ファイル | 他のアカウントが読めるコピーは、レルムのすべての人のチケットを偽造する |
| **あらゆるパスワード経路**: `password_file`(空でも)、`bind_password_file`、`bind_dn`、`password`、`passwd`、`nt_hash`、`userPassword`... を指す `users`/`groups` のクエリや属性、パスワードを含む DSN | v0.2.0 で削除: ここでは誰も鍵を持たない。メッセージがそう告げる。クエリと DSN の検査はベストエフォートで、取りこぼしは `nameOnly` が受け止める |
| インラインで書かれた秘密(`password = "..."` は引数ではない) | 秘密はファイルにあり、設定にも、そのバックアップにも、ログにも置かない |
| グループまたは他者が書き込める設定ファイル | それを書く人が mint の呼び出し元を選ぶ |
| `krbtgt/REALM` の鍵がない、または列挙したサービスが欠けているキータブ。**aes256-cts-hmac-sha1-96 で**(ライブラリが発行する唯一のタイプ) | 起動はしても、最初の `kinit` で失敗する |
| `listen` のワイルドカードまたはホスト名(IP リテラルが必須)、および `mint` の**あらゆる**ワイルドカード | KDC と mint リスナーは、誰かが選んだインターフェース上にある |
| 呼び出し元がない、証明書がない、または期限切れの `mint` ブロック | ライブラリは呼び出し元なしを「mint オフ」と読む。これは黙って何も発行しない代わりに、そう告げる |
| `start_tls` なしで別のマシンへの `ldap://` | すべてのパスワードが入力されたままネットワークを流れる |

秘密ファイルは**一度だけ**開かれ、開いたファイルが検査されます(通常ファイル、モード、
所有者)。したがって検査が一つのファイルについてで、読み取りが別のファイルについて、
ということは起こりません(手本は go-fileshare の `readKeytab`)。`dsn_file` は、
同じ検査を済ませた後に `hcldir` が名前で読みます。

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

[github.com/go-authn/kdcd](https://github.com/go-authn/kdcd)、v0.2.0。
