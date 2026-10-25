---
title: "セキュリティ"
linkTitle: "セキュリティ"
weight: 55
description: "各プログラムが拒否するもの、失効がプロバイダーからすべてのサーバーにどう伝わるか、そして本物のバイナリとそれ以外を見分ける方法。"
tags: [セキュリティ]
---

go-authn は人々を証明するよう求められるので、その拒否は例外ではなく設計そのものです。この節では、
プログラムの境界をまたぐものをまとめています。各プログラム自身が何を拒否するかは、それぞれの
ページにあります。

## 最も重要な拒否 {#the-refusals-that-matter-most}

| | 拒否されるもの | 理由 |
|---|---|---|
| authnd | 宣言された `reader` 以外による検索 | バインドは誰かが誰であるかを証明するもので、全員を列挙する許可ではない |
| authnd | ソースにパスワードがない人への Kerberos チケット | KDC にはパスワードから導出した鍵が必要で、NT ハッシュやパスワードの検証では生成できない ([理由]({{< relref "/authnd/kerberos.md" >}})) |
| authnd | `mfa` ブロックと並んだ `kerberos` ブロック | kinit が運ぶのはパスワードだけなので、`mfa` ブロックが二要素を必要とする人々に、レルムが一要素でチケットを発行してしまう |
| authn-bridge | 誰も署名していないアサーション、機関自身のスコープの外にある識別子 | フェデレーションのすべてのメンバーが信頼されるので、各メンバーはそれ自身の人々に縛られなければならない。そうでなければ、どの機関も誰の名前でも名乗れてしまう |
| authn-revokd | 署名のない、期限切れの、または保持しているものより古いリスト | 間にあるミラーはリストを遅らせられても、偽造したりロールバックしたりはできない |
| authn-revokd | 失効したリストを信頼すること | CA 自体を失効させるリストを書き込むので、sshd は古いリストを信頼せずに拒否する |
| sshcert-authorize | ドメイン許可がこのホストを指していない証明書 | フェデレーションの CA が発行した証明書は、それだけではその CA を信頼するすべてのホストに対する許可ではない |

## 失効の一部始終 {#a-revocation-end-to-end}

1. [authn-bridge]({{< relref "/authn-bridge/_index.md" >}}) は、KRL (SSH 証明書用) と CRL
   (X.509 クライアント証明書用) に署名して日付を付け、公開します。
2. [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) は各リストを取得し、署名と日付を
   検証し、保持しているリストより古いもの (再起動をまたいでも) を拒否し、その後で初めてサーバーが
   読む場所に書き込みます。
3. sshd (`RevokedKeys`)、go-fileshare、その他のものは、すでに検証されたファイルを読みます。

プロバイダーの Shared Signals トランスミッターを通じた CAEP の `session-revoked` イベントは、
どのリストも名指しできないもの、つまりある時点より前にある人に発行されたすべてを無効にします。
受信側は go-fileshare のドキュメントが説明しています:
[失効リスト](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)、
[Shared Signals](https://go-fileshare.github.io/docs/latest/security/shared-signals/)。

## リリース {#releases}

すべてのバイナリは、タグ付けされたコミットからリリースワークフローによってビルドされ、三つの方法で
確認できます: [ダウンロードの検証]({{< relref "/security/verifying-releases.md" >}})。
