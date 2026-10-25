---
title: "運用: シグナル、再起動、出力される内容"
linkTitle: "運用"
weight: 80
description: "authnd が一度だけ読み込むもの、SIGHUP でリロードされない理由、停止の仕方、出力に書き出す内容、そして稼働しているかの確認方法。"
tags: [authnd, 運用, シグナル, systemd]
---

## すべてを一度だけ読み込む {#it-reads-everything-once}

設定ファイル、その背後にあるすべてのソース、TLS 証明書、キータブは**起動時に**読み込まれます。
リロードはなく、パッケージ付属のユニットにも `ExecReload=` はありません。これらのいずれかを
変更した後は:

```sh
sudo -u authnd authnd check /etc/authnd
sudo systemctl restart authnd
```

実行中に反映される唯一のものは、
[人が authnd を通じて変更したパスワード]({{< relref "/authnd/passwords.md" >}})で、
`user` ブロックだけを再読み込みし、他は何も読みません。

## シグナル {#signals}

| シグナル | 動作 |
|---|---|
| `SIGTERM`、`SIGINT` | `stopping` を出力し、リスナーと**確立済みのすべての接続**を閉じ、レルムを停止し、ソースを閉じ、サーバーが実際に終了した時点で 0 で終了します |
| `SIGHUP` | 捕捉されてログに記録され、authnd は何もリロードせずに**稼働し続けます** |

```
$ authnd --config etc/authnd
ldap on 127.0.0.1:3893, serving 4 people from the configuration file, then a sqlite database
hangup: authnd does not reload; restart it to apply a changed configuration, certificate or keytab
alice's password change was refused: the old password did not verify: directory: wrong password
alice changed their own password

stopping
```

これは一回の実行です。`kill -HUP` が一回、パスワード変更の試行が二回 (最初は拒否され、
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
vendorVersion: v0.12.0
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
