---
title: "リストが失効したとき"
linkTitle: "リストの失効"
weight: 40
description: "CA から現在のリストを得られないとき authn-revokd が sshd 向けに書き込むもの: CA 鍵自体を失効させる KRL。その CA のすべての証明書が拒否される。"
tags: [authn-revokd, 失効, フェイルクローズ, sshd]
---

リストを得られないときにすべてを通してしまう失効チェックは、リストを妨害できる攻撃者に
破られるものです。そのため authn-revokd がソースから現在のリストを得ていないとき、そのソースの
リストが守るものは、現在のリストが再び届くまで**拒否されます**。

| 出力 | ソースに現在のリストがない間 |
|---|---|
| `sshd` 向けの KRL | authn-revokd は、**ソースの CA 鍵を失効させる** KRL を書き込む |
| TLS サーバー向けの CRL | 期限切れの CRL がそのまま残される。OpenSSL が期限切れの CRL を自ら拒否する |

## sshd 向け: CA 自体を失効させる {#for-sshd-revoking-the-ca-itself}

`sshd` にはリストの有効期限という概念がなく、最後に書き込まれたファイルを永遠に読み続けます。
しかしすべての証明書の **CA 鍵**を `RevokedKeys` と照合します。そのため authn-revokd は、保証できない
リストの代わりに、CA 自身の鍵を出力に入れ、その CA が署名したすべての証明書が拒否され、
他には何も影響しません。

ここでは発行者が停止しており、KRL ソースには `max_age = "30s"` があるため、保持しているコピーは
一時間ではなく一分以内に失効します。CRL ソースには `max_age` がなく、そのコピーはまだ現在の
ものです。

```
$ authn-revokd -config revokd-maxage.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
output sshd: wrote /tmp/authn/revokd/out/sshd.krl
authn-revokd: not current: bridge-ssh; not fetched: bridge-x509 (the list held is current until 2026-10-11T10:50:24Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 19700101T010000
# Comment: authn-revokd sshd: FAIL CLOSED, every certificate refused from bridge-ssh

hash: SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q # ssh-ed25519
$ ssh-keygen -Q -f out/sshd.krl ca-ssh.pub
ca-ssh.pub (go-authn/bridge SSH CA): REVOKED
```

`bridge-ssh` は `not current` で、その出力はフェイルクローズされています。`bridge-x509` は
`not fetched` にすぎず、その CRL はそのまま残されています
([`-once` が報告するもの]({{< relref "/authn-revokd/verification.md#what--once-reports" >}}))。
`SHA256:Fpa/...` は bridge の SSH CA です。それが署名した証明書は、ファイルを読むものにとっては
失効済みとなります。上のコマンドは `out/` がある `revokd` ディレクトリで実行しました。次のものは
その隣の、テスト用証明書を保持するディレクトリで実行します。
[sshcert-authorize のページ]({{< relref "/sshcert/authorize.md#krl" >}})と同じなので、同じファイルは
`../revokd/out/sshd.krl` です。

```
$ ssh-keygen -Q -f ../revokd/out/sshd.krl alice-cert.pub
alice-cert.pub (alice): REVOKED
```

コメントは `FAIL CLOSED` と述べてソースを名指しするので、`ssh-keygen -Q -l` を読む人は理由が
分かります。すべてのソースが失効した場合、ファイルの日付は 1970 年になります。出力は、同期が
気づいた**直後に**書き込まれます。デーモンでは次の `refresh`、タイマーでは次のティックです。
現在のリストが再び届くと、次の同期が CA の鍵の代わりにそれを書き込み、その CA の証明書は
再び受け入れられます。

**最初のリストの前**にも同じことが起きます。一度も取得されていないソースには現在のものが何もなく、
その CA は最初の書き込みから失効しています。新規のインストールは、最初のリストが検証に通る
まで、CA の証明書を無検証で受け入れるのではなく、拒否します。

### 各 CA は自分自身について {#each-ca-for-itself}

複数のソースをマージする出力では、失効したソースの CA だけが失効されます。他のものは
リストを保持します。マージできないリスト (go-authn/krl が保持するシリアル範囲を超えるもの) は
自身の CA についてのみフェイルクローズし、`/healthz` がそれを名指しします。リストが単独では
マージできるのに一緒にはできない場合にのみ、出力のすべての CA が失効され、コメントがそう述べます
(`FAIL CLOSED, the output could not be rendered`)。代わりに古いファイルを保持すると、後の失効が
見過ごされてしまいます。

## TLS サーバー向け: CRL 自体 {#for-a-tls-server-the-crl-itself}

CRL はすでに有効でなくなる時刻を述べており、OpenSSL は `nextUpdate` を過ぎたものを拒否します
("CRL has expired")。そのため authn-revokd は最後に検証した CRL をそのまま残し、TLS サーバーが
自らフェイルクローズします。CRL 出力に供給するソースで `max_age` が拒否されるのもそのためです。
CRL を読み込んだサーバーは、authn-revokd が何を書き込もうと、`nextUpdate` までそれを保持します。

## 有効期限を自分で確認する読み手 {#readers-that-check-the-expiry-themselves}

マージされた KRL は、現在の入力のうち最も早いものの有効期限を運びます。それを確認する読み手、
たとえば go-fileshare の `ssh_krl_file` や
[`sshcert-authorize --krl`]({{< relref "/sshcert/authorize.md#krl" >}})は、発行者が停止したのと
同じように、authn-revokd が停止したことが分かります。

{{< callout type="warning" >}}
**これは authn-revokd が動いている間にのみ機能する**

ファイルは authn-revokd によってフェイルクローズされます。それが停止している間、sshd は最後に
書き込まれたファイルを、現在のものであろうとなかろうと読み続けます。そのためデーモンには
`Restart=always` があり、ユニット、タイマー、または `/healthz` を監視します。
{{< /callout >}}
