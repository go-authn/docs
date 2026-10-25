---
title: "sshcert"
linkTitle: "sshcert"
weight: 40
description: "SSH ユーザー証明書の GÉANT / EuroHPC ドメイン許可拡張と、証明書がこのホスト向けかどうかを sshd が問い合わせるフェイルクローズのコマンド sshcert-authorize。"
tags: [sshcert, ssh, eurohpc]
---

**フェデレーションの CA が発行した証明書は、それだけではその CA を信頼するすべてのホストに対する
許可ではありません。** EuroHPC Federation Platform の SSH CA は、証明書の宛先となるホストを
拡張 `ssh-domain-grant@core.aai.geant.org` に書き込みますが、`sshd` はそれを無視します。
go-authn/sshcert はその拡張を読み書きし、そのコマンド `sshcert-authorize` が、それを強制するために
`sshd` が実行するものです。純粋な Go、`CGO_ENABLED=0`。これらのページは v0.1.7 を説明しています。

```
$ go install github.com/go-authn/sshcert/cmd/sshcert-authorize@v0.1.7
$ sshcert-authorize -version
sshcert-authorize v0.1.7
```

| | |
|---|---|
| [sshcert-authorize]({{< relref "/sshcert/authorize.md" >}}) | `AuthorizedPrincipalsCommand`: 何を確認し、何を拒否し、sshd がどう呼び出すか |

## 拡張 {#the-extension}

そのデータは、ホストパターンのコンパクトな JSON 配列、`["login.example.org"]` です。`*` は単一の
ラベル内の**一文字以上**に一致し、名前は大文字小文字を区別せずに比較されます。

| パターン | 一致するもの | 一致しないもの |
|---|---|---|
| `login.example.org` | `login.example.org`、`LOGIN.example.org` | `www.login.example.org` |
| `*.example.org` | `a.example.org` | `example.org`、`a.b.example.org` |
| `prod-*.example.org` | `prod-1.example.org` | `prod-.example.org` |
| `*.*.example.org` | `a.b.example.org` | `a.example.org` |

読み取りは厳格で、エンコーダーが書くものだけが受け入れられます。空白なし、`]` の後に何もなし、
JSON エスケープなし、重複なし、パターンは最大 64 個、それぞれ英字、数字、ハイフン、`*` からなり、
ラベルは 1 から 63 バイト、全体で最大 253 バイトで、**一番右のラベルに `*` は置けません**。`null`、
オブジェクト、数値、入れ子の配列は拒否されます。`[]` は受け入れられ、どのホストも許可しません。

存在するが不正な形式の許可は、決して不在として報告されません。この違いがこのコマンドの
要点のすべてです。

## 誰が使うか {#who-uses-it}

- **[authn-bridge]({{< relref "/authn-bridge/certificates.md#the-eurohpc-ssh-ca-profile" >}})** は、
  クライアントの `ssh_domain_grants` のために拡張を書き込みます。その前に、このパッケージの
  `ValidatePattern` で各パターンを確認します。
- **go-fileshare** の SFTP サーバーは `ssh_domains` でそれを読み、許可のない証明書は
  `ssh_accept_ungranted` が設定されていない限り拒否します。
- **sshcert-authorize** は、通常の `sshd` のための同じチェックです。

## ライセンス {#licence}

BSD-3-Clause。
