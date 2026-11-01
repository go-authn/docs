---
title: "運用: シグナル、再起動、出力される内容"
linkTitle: "運用"
weight: 80
description: "authnd が一度だけ読み込むもの、SIGHUP でリロードされない理由、停止の仕方、出力に書き出す内容、そして稼働しているかの確認方法。"
tags: [authnd, 運用, シグナル, systemd]
---

## すべてを一度だけ読み込む {#it-reads-everything-once}

設定ファイルとキータブは**起動時に**読み込まれます。
これらのリロードはなく、パッケージ付属のユニットにも `ExecReload=` はありません。どちらかを
変更した後は:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

TLS 証明書は v0.15.0 から例外です。authnd は `cert_file` と `key_file` をもう一度確認するので、
更新に再起動は不要です。[証明書の更新]({{< relref "/authnd/tls.md#renewal" >}})を参照してください。

ソース (後述) を除き、実行中に反映される唯一のものは、
[人が authnd を通じて変更したパスワード]({{< relref "/authnd/passwords.md" >}})で、
`user` ブロックだけを再読み込みし、他は何も読みません。

ソースは「一度だけ読み込む」の例外です。人とグループは `refresh` ごと
(既定は 60 秒。`refresh = "0"` で無効) に、応答経路の外で組み立てた新しいスナップショットへ
読み直され、アトミックに入れ替えられます。そのため、削除された人やグループのメンバーは
再起動なしで 1 周期以内に消えます。(v0.13.4 は一度だけ読み込み、グループの変更には再起動が
必要でした。)失敗した更新は最後に正常だったデータを保ち、失敗が続く間に 1 回だけ、
ソース名を添えてログに記録されます。失効が重要な環境では `max_age` (例: `"10m"`) を設定して
ください。データがそれより古くなると、検索、人のバインド、パスワード変更は、古いデータの
代わりに `unavailable` (52) を返します。起動時に読み込めない
ソース(実行できないグループクエリや、複数のデータベースのうち 1 つの停止など)は、
ソースとグループの名前を挙げて起動と `check` を拒否します。1 つの LDAP メッセージに
収まらない大きさのエントリ(約 3 MiB。10 MB の属性値が 1 つあれば届きます)は
公開されず、スキーマに適合しないエントリと同様に、起動時と `check` で通知されます。

## シグナル {#signals}

| シグナル | 動作 |
|---|---|
| `SIGTERM`、`SIGINT` | `stopping` を出力し、リスナーと**確立済みのすべての接続**を閉じ、レルムを停止し、ソースを閉じ、サーバーが実際に終了した時点で 0 で終了します |
| `SIGHUP` | 捕捉されてログに記録され、authnd は**稼働し続けます**。TLS 証明書はすぐに読み直します (v0.15.0)。設定とキータブはリロードされません |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 1 person from the configuration file
hangup: authnd does not reload its configuration or keytab; restart it to apply those (the TLS certificate is read again)
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

これは v0.15.0 のバイナリの一回の実行です。`kill -HUP` が一回、パスワード変更の試行が二回 (最初は拒否され、
二回目は受け入れられました)、そして `kill -TERM` です。`SIGHUP` の後もプロセスは残っていました。

かつて `SIGHUP` は authnd を**終了させて**いました。誰も処理しないシグナルに対する Go の既定の
動作です。systemd は `SIGHUP` による終了を正常終了と数えるため、`Restart=on-failure` では
再起動されませんでした。一度の `kill -HUP` や、一度の logrotate の `postrotate` で、ディレクトリが
そのまま落ちたのです。今では捕捉されるので、その習慣は無害であり、ログの行が代わりに何をすべきか
を伝えます。

リスナーだけでなく確立済みの接続も閉じるのは意図的です。受け付けを止めても開いている接続に
応答し続けるサーバーは、止まったように見えても止まっておらず、それは反映されない再起動に
なってしまいます。

## 出力される内容 {#what-it-writes}

すべては標準出力に出力され、systemd の下ではジャーナルになります
(`journalctl -u authnd`)。

- 起動時に、待ち受け先と提供対象 — `ldap on …`、`ldaps on …`、`ldap+starttls on …`。
  `kerberos` ブロックがある場合は続けて `realm EXAMPLE.ORG on … (udp and tcp)`
- `mfa` ブロックの下で拒否されたすべてのバインド、拒否されたすべてのトークン、拒否または
  完了したすべてのパスワード変更を、**理由とともに**。クライアントには決して告げられません。
  [第二要素]({{< relref "/authnd/mfa.md#what-the-binds-look-like" >}})と
  [トークン]({{< relref "/authnd/tokens.md#what-the-binds-look-like" >}})を参照
- KDC が拒否したすべての要求を、`kerberos:` を前置し、Kerberos のエラーコードとともに。
  [レルム]({{< relref "/authnd/kerberos.md#kinit-against-it" >}})を参照
- LDAP ライブラリ自身のログを、`slog` のテキスト形式で、info レベルで

`mfa` ブロックがない単純バインドでの単なる間違ったパスワードには `invalidCredentials` が
返され、authnd 自身はログに記録しません。

## 制限と期限 {#limits}

v0.15.0 から、authnd はクライアント、遅いソース、大量の接続が自分に保持させられるものに上限を設けます。
設定の最上位に置く、省略可能な四つのキーです。

| キー | 既定値 | 意味 |
|---|---|---|
| `max_connections` | `4096` (以前は無制限) | 同時に開く接続の最大数。`0` は無制限 |
| `max_connections_per_ip` | なし | 一つのアドレスからの最大数。`max_connections` を超えられません |
| `operation_timeout` | `30s` (以前はなし) | 一つの LDAP 操作に許される最長時間。`"0"` はなし、それ以外は `100ms` 以上 |
| `startup_timeout` | `60s` | すべてのソースを開いて最初に読み込むのに許される最長時間。`"0"` はなし |

上限を超えた接続には、切断通知 (notice of disconnection) で `busy` (51) が送られて閉じられ、待ち行列に
入れられることはありません (RFC 4511 4.4.1)。`operation_timeout` の時点でまだ実行中の操作には
`timeLimitExceeded` (3) が返されます。**ハンドラーがブロックして期限を無視していても同じです**。遅れて届いた結果は
捨てられます。起動時にソースが応答しないと、authnd は `startup_timeout` の後に起動を拒否し、
そのエラーは段階とソースを名指しします。負の数や、読み取れない期間は、起動時と `check` で拒否されます。
v0.14 の動作に戻すには `max_connections = 0` と `operation_timeout = "0"` を設定します。

`check` は、これから使う制限を表示します。既定値で動かしていることに気づかないままにならないようにするためです。

```
$ authnd check etc2/authnd
ldap://127.0.0.1:3893, base dc=example,dc=org
limits: 200 connections, 20 per address; an operation may take 10s; startup may take no limit

USER   FROM                    CAN PROVE   PUBLISHED AS        WITH
alice  the configuration file  a password  account, uidObject  uid

GROUP  MEMBERS  PUBLISHED AS
staff  alice    groupOfNames

alice has no uidNumber, gidNumber or homeDirectory: not a posixAccount, published as account, uidObject
group staff has no gidNumber: not a posixGroup, published as a groupOfNames (member DNs, no memberUid)

a bind carries a password
cn=reader,dc=example,dc=org may search; every other bound client may not
sambaNTPassword is not published, so nothing here can authenticate an SMB session (NTLMv2 needs the password or its MD4, and a bind cannot answer it)

this configuration can be served
```

この設定は `max_connections = 200`、`max_connections_per_ip = 20`、`operation_timeout = "10s"`、
`startup_timeout = "0"` としています。この四つのキーがなければ、行は
`limits: 4096 connections, no limit per address; an operation may take 30s; startup may take 1m0s`
となり、同じバイナリがこれも表示しました。

### 障害は間違ったパスワードではない {#outage}

人々を別のディレクトリ (`ldap` ソース) に対して確認していて、そのディレクトリに問い合わせられないとき、
つまり接続が拒否またはリセットされた、`busy`・`unavailable`・`other` が返った、`operation_timeout` 内に
応答がなかった場合、authnd は LDAP `unavailable` (52) を返し、`invalidCredentials` (49) は**決して**返しません。
これは単純バインド、パスワード変更の古いパスワード、`mfa` バインドのパスワード要素に当てはまります。
v0.15.0 より前は間違ったパスワードとして報告されていたため、ディレクトリが落ちている間にログインフォームが
パスワードが間違っていると本人に伝えていました。間違ったパスワードは今も 49 です。原因はクライアントに伝わる
内容ではなくログに残り、障害は失敗した推測として数えられません。

## 起動しないとき {#when-it-does-not-start}

拒否は、標準エラーへの `authnd:` で始まる一行と、終了ステータス 1 です。ユニットの下では
`Restart=on-failure` が五秒ごとに再試行し、その行は毎回ジャーナルに残ります。`check` が拒否する
ものはここでもすべて拒否され、サーバーだけが見つけるのは、待ち受けられないアドレスです。
[`check`]({{< relref "/authnd/check.md#the-certificate-the-keytab-and-the-one-thing-it-cannot-see" >}})を
参照してください。LDAP リスナー、証明書、レルムはいずれも最初の行が出力される前に開かれるので、
起動できないサーバーは拒否のメッセージだけを出力します。ここでは二つ目のインスタンスが、
一つ目の Kerberos ポートにぶつかっています。

```
$ authnd --config cases/realm2
authnd: kerberos udp 127.0.0.1:18388: listen udp 127.0.0.1:18388: bind: address already in use
```

`ldap on …` の行と、その後の `realm … on …` は、両方の半分が待ち受けていることを意味します。

## 稼働の確認 {#telling-that-it-is-up}

ヘルスエンドポイントもメトリクスもありません。あるのは次のものです。

- **プロセスとその終了ステータス** — systemd の下では `systemctl is-active
  authnd`。LDAP リスナーまたはレルムが自ら停止した場合、そのエラーとともにプロセス全体が
  終了するので、生きているプロセスとは、二つの半分がどちらも応答するものです
- **ルート DSE**。匿名のクライアントに応答し、どのバージョンと話しているかを示します。

```
$ ldapsearch -x -LLL -H ldap://127.0.0.1:3893 -s base -b '' '+' '*'
dn:
objectClass: top
objectClass: OpenLDAProotDSE
supportedLDAPVersion: 3
namingContexts: dc=example,dc=org
supportedExtension: 1.3.6.1.4.1.4203.1.11.3
supportedExtension: 1.3.6.1.4.1.4203.1.11.1
supportedControl: 1.2.840.113556.1.4.319
supportedControl: 1.3.6.1.1.13.1
supportedControl: 1.3.6.1.1.13.2
supportedFeatures: 1.3.6.1.4.1.4203.1.5.1
supportedFeatures: 1.3.6.1.4.1.4203.1.5.3
subschemaSubentry: cn=Subschema
vendorName: go-authn/authnd
vendorVersion: v0.13.0
```

[StartTLS リスナー]({{< relref "/authnd/tls.md#starttls-which-refuses-until-it-is-asked-for" >}})では、
このクエリに `-ZZ` が必要です。より多くを証明するプローブ、つまりソースがまだ応答することの
確認は、そのために用意した人または reader としてのバインドです。`users "ldap"` ブロックがある
場合、そのバインドはこの背後にあるディレクトリに到達します。

## 何がどこにあり、再起動で何が失われるか {#what-lives-where-and-what-a-restart-loses}

| | |
|---|---|
| 設定、パスワード、DSN、証明書、キータブ | 設定が指名するファイル。何もコピーされません |
| SQLite データベース | DSN が指す場所。ユニットの下では `/var/lib/authnd` |
| 第二要素のカウントとロックアウト | メモリ上のみ: **再起動で忘れられます**。百回間違えてロックアウトされた人も含みます |
| 使用済みのワンタイムコード | メモリ上のみ |
