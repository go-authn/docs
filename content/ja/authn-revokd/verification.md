---
title: "リストの検証方法"
linkTitle: "検証"
weight: 30
description: "authn-revokd がリストを保持する前に確認するもの: 署名、日付、そして保持しているリストより古くならないこと。再起動をまたいでも。"
tags: [authn-revokd, 失効, セキュリティ]
---

検証に通らないリストは、書き込まれることも、提供されることも、使われることもありません。
最後の正常なコピーが残ります。どんな理由であれ失敗した取得が、何も失効させない空の応答でそれを
置き換えることはありません。

## 署名 {#the-signature}

**KRL** は署名 `<url>.sig` とともに取得されます。ファイル全体に対する armored SSHSIG で、
`ssh_ca` として設定された **SSH CA 鍵**により、名前空間 `krl@go-authn.github.io` で署名されて
います。名前空間により、署名が他のものに流用されることを防ぎます。署名者は SHA-512 でハッシュ
しますが、SHA-256 も受け入れられます。PROTOCOL.sshsig が禁じている、SHA-1 形式の RSA 署名は
拒否されます。

KRL 自体は `sshd` が解析するのと同じように解析できなければならず、OpenSSH 自身の署名セクションを
含んではなりません。OpenSSH はそれを検証しないからです。

他の鍵で署名されたリストは拒否されます。

```
$ authn-revokd -config revokd-other.hcl -once
bridge-ssh: revocation: the KRL's signature does not verify by SHA256:xm8VDcZUh44N+RQSiPbroPInzkMhN/KCWI/TC+9HPNQ: public key does not match
bridge-x509: version 1791712224691, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
output sshd: wrote /tmp/authn/revokd/out/other.krl
output tls: wrote /tmp/authn/revokd/out/other.crl
authn-revokd: not current: bridge-ssh
```

ここでは `ssh_ca` が bridge のリストに署名していない鍵を指名しており、エラーはその鍵を名指し
します。検証に通らない署名は、二つのリクエストの間にリストが再発行されたことによる場合も
あるので、報告する前に両方をもう一度取得します。これはそのソースの最初の取得だったので、
保持すべき正常なコピーがなく、出力は直ちに
[フェイルクローズのリスト]({{< relref "/authn-revokd/lapse.md" >}})になります。(v0.6.2 より前は、
同じ失敗が上のメッセージの前に "the list changed between it and its signature" を付けて
おり、リストが再発行されたかのようでした。)

署名は `If-Match: <the list's ETag>` で取得されます。二つのリクエストの間にリストが再発行されると
`412` が返り、両方が再度取得されます。

**CRL** は `x509_ca` として設定された CA 証明書に対して検証されます。まず生のバイトに対する
署名を、残りを解析する**前に**確認するので、誰が署名した大きな CRL でも、解析ではなく署名確認の
コストで済みます。次に、その発行者がその証明書のサブジェクトでなければならず、CRL Number と
`thisUpdate` より後の `nextUpdate` を持たなければならず、デルタ CRL であってはならず、CRL Number
と Authority Key Identifier 以外のクリティカル拡張や、クリティカルなエントリ拡張を含んでは
なりません。

KRL は `expires@go-authn.github.io` 拡張で**有効期限を述べて**いなければなりません。述べていない
ものは、古いものと区別できないからです。

本文のサイズには上限があります。KRL は 32 MiB、その署名は 64 KiB、CRL は 64 MiB です。

## 日付 {#the-dates}

リストが現在のものであるのは、次の場合です。

- 現在が有効期限 (KRL の拡張、CRL の `nextUpdate`) より前である
- 五分を超えて未来に発行されていない: 時計がそれ以上進んでいる発行者は、年齢が分からないリストを
  書く
- `max_age` がある場合、それより前に発行されていない

現在のものでないリストは、取得時に拒否されます。`304 Not Modified` は新しい情報ではありません。
保持しているコピーはその後に期限切れになっているかもしれず、同期のたびに再度判断されます。

## 保持しているリストより古くならない {#never-older-than-the-list-held}

リストの位置は、その**バージョン** (KRL の `krl_version`、CRL Number)、次にその**発行時刻**
(KRL の生成日時、CRL の `thisUpdate`) です。リストが保持しているものを置き換えられるのは、より
高いバージョンを持つか、同じバージョンでより後に発行された場合だけです。同じ失効を新しい有効期限で
再発行したものです。それ以外はロールバックです。再生または復元された古いリストで、署名されていて
期限も切れていないものが、新しいリストが失効させたものを元に戻してしまいます。

### 再起動をまたいでも {#across-restarts-too}

保持しているリストは `state_dir` に、ソースごとに、リストとその署名を一緒に入れた一つのファイルと
して保持され、ディレクトリを同期した単一のリネームで書き込まれます。起動時に各コピーは
**再度検証され** (期限切れかどうかにかかわらず、次に来るものの順序を決めます)、検証に通らなく
なったコピーは、次のものの順序を決めるためにすら信頼されず、ログにそう記録されます。

ここでは、再起動後に、ソースを、以前の bridge プロセスが十九秒前に提供した、まだ署名されていて
期限も切れていないリストに向けます。

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: version 0, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
bridge-x509: version 1791712224691, issued 2026-10-11T09:50:24Z, expires 2026-10-11T10:50:24Z
$ authn-revokd -config revokd-old.hcl -once
bridge-ssh: file:///tmp/authn/revokd/old/bridge.krl: revocation: the list is older than the one held: version 0 issued at 2026-10-11T09:50:05Z, the copy held at 2026-10-11T09:50:24Z
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-11T10:50:24Z)
$ ssh-keygen -Q -l -f out/sshd.krl
# KRL version 0
# Generated at 20261011T115024
# Comment: authn-revokd sshd
```

最初の実行は出力を書き込みませんでした。ファイルがすでにそれらのリストを保持していたからです。
古いリストは拒否され、出力は新しいほうを保ちます。それを拒否したプロセスは新しいリストを
見たことがなく、`state_dir` から読み戻したのです。

状態こそがロールバックを検出可能にするものなので、ディレクトリは sshd の StrictModes ルールに
従います ([設定]({{< relref "/authn-revokd/configuration.md#what-is-refused-at-start" >}}))。
二回の書き込みの間にクラッシュしても、検証に通らない組が残ることはなく、それはロールバックの
ガードごと失うことになります。リストとその署名は一つのファイルだからです。

## `-once` が報告するもの {#what--once-reports}

`-once` は、ソースに現在のリストがないとき、**最後の取得が失敗した**とき、または出力が書き込めな
かったときに `1` で終了し、最後の行が最初の二つのうちどちらかを述べます。

| 最後の行 | ソース | その出力 |
|---|---|---|
| `not current: <source>` | 現在のリストがない: 一度も取得していない、期限切れ、または `max_age` 超過 | sshd 向けにフェイルクローズ |
| `not fetched: <source> (the list held is current until <T>)` | 取得は失敗したが、保持しているコピーはまだ現在のもの | そのコピーから、変更なしで `T` まで書き込まれる |

ここでは、保持している両方のリストがまだ現在のものである間に発行者が停止しています。

```
$ authn-revokd -config revokd.hcl -once
bridge-ssh: revocation: Get "http://127.0.0.1:28473/ssh/krl": dial tcp 127.0.0.1:28473: connect: connection refused
bridge-x509: revocation: Get "http://127.0.0.1:28473/x509/crl": dial tcp 127.0.0.1:28473: connect: connection refused
authn-revokd: not fetched: bridge-ssh (the list held is current until 2026-10-11T10:50:24Z), bridge-x509 (the list held is current until 2026-10-11T10:50:24Z)
```

その実行は `sshd.krl` をそのままにしました。保持しているリストが失効すると、同じソースは
`not current` と報告され、両方の種類が同じ行に並ぶことがあります。
[リストが失効したとき]({{< relref "/authn-revokd/lapse.md" >}})のとおりです。v0.6.2 より前は、
どちらの場合も `not current` と報告されていたため、取得が失敗しただけなのにリストが失効したと
述べていました。終了ステータスはそのときも `1` でした。

ミラーの `/healthz` は代わりに保持しているコピーで判断し、発行者が停止していてコピーがまだ
現在のものである間は `ok` を返しました。
