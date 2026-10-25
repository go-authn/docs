---
title: "何を失効させ、サーバーがそれをどう知るか"
linkTitle: "失効"
weight: 60
description: "失効させた証明書について authn-bridge が公開する、署名付きで日付入りの KRL と CRL、そしてどのリストも名指しできないものに届く Shared Signals トランスミッター。"
tags: [authn-bridge, 失効, krl, crl, 共有シグナル]
---

人や機関の無効化 ([管理 API]({{< relref "/authn-bridge/admin.md" >}})) は、プロバイダーに戻ってくる
すべてを終了させます。リフレッシュトークン、`/userinfo`、新しい証明書、アプリケーション
パスワードです。すでに渡したものは別の場所で、鍵に対して検証され、それに届く仕組みは三つ
あります。

| 認証情報 | 取り消す手段 |
|---|---|
| この CA が署名した SSH 証明書 | **KRL**、`GET /ssh/krl`。その署名は `/ssh/krl.sig` |
| X.509 クライアント証明書 | **CRL**、`GET /x509/crl` |
| アクセストークン、opkssh 証明書、サーバーが単独で検証するもの | **Shared Signals** の `session-revoked` イベント |

失効は恒久的です。人を再び有効にしても、その証明書は戻りません。新しいものを得ます。失効を
取り除けるリストは、管理 API に到達できる誰かが編集できるリストだからです。

## リスト {#the-lists}

どちらも go-authn/revocation のプロトコルが述べるとおりに発行されるので、何を経由しても
(ミラー、平文の HTTP、ファイル) 運ばれ、それを読む誰もが検証できます。

| | KRL | CRL |
|---|---|---|
| 形式 | OpenSSH の `PROTOCOL.krl`。go-authn/krl が書く。`sshd` の `RevokedKeys` と `ssh-keygen -Q` が読むもの | DER、RFC 5280 |
| 署名 | SSH CA 鍵による分離 SSHSIG、名前空間 `krl@go-authn.github.io` | 証明書に署名する CA による |
| 有効期限 | その `expires@go-authn.github.io` 拡張 (sshd は無視する) | その `nextUpdate` |
| 順序付け | `krl_version`、次に生成日時 | CRL Number、次に `thisUpdate` |

各リストは、発行から**一時間**後に有効でなくなると述べます。リストは、その半分に達するか、
何かが失効されるまで、保持されて変更なしで提供され、その後のリクエストは新しい発行を得ます。
発行は、時計が巻き戻っても、置き換えるものより前の日付にはなりません。読み手は、同じバージョンの
より前の発行をロールバックとして拒否するためです。CRL Number は発行ごとに増加します。

何も失効していないテスト用プロバイダーの KRL:

```
$ curl -s -D - -o var/bridge.krl http://127.0.0.1:28473/ssh/krl
HTTP/1.1 200 OK
Cache-Control: max-age=60
Content-Type: application/octet-stream
Etag: "db5b4e920d2da3911da51a8f70db8c4f"
Date: Sun, 11 Oct 2026 09:48:14 GMT
Content-Length: 130

$ ssh-keygen -Q -l -f var/bridge.krl
# KRL version 0
# Generated at 20261011T114814
# Comment: go-authn/bridge http://127.0.0.1:28473
```

**ETag は内容のものです。** 読み手は `If-None-Match` でポーリングし、保持している発行がまだ
提供されているものと同じなら `304` を得ます。内容は少なくとも三十分ごとに変わるので、
ポーリングする読み手が有効期限を過ぎたコピーを保持し続けることはありません。

```
$ curl -s -o /dev/null -H 'If-None-Match: "db5b4e920d2da3911da51a8f70db8c4f"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl
304
```

**署名は、リストの ETag を `If-Match` に指定して取得します。** その間にリストが再発行されて
いれば、一致しない署名ではなく `412` が返ります。

```
$ curl -s -o var/bridge.krl.sig -H 'If-Match: "db5b4e920d2da3911da51a8f70db8c4f"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
200
$ curl -s -o /dev/null -H 'If-Match: "stale"' -w '%{http_code}\n' http://127.0.0.1:28473/ssh/krl.sig
412
```

`ssh-keygen` は署名を検証し、他の名前空間のものは拒否します。

```
$ ssh-keygen -Y verify -f allowed -I bridge -n krl@go-authn.github.io -s bridge.krl.sig < bridge.krl
Good "krl@go-authn.github.io" signature for bridge with ED25519 key SHA256:Fpa/Ku2Wv1EDCR+KSsqZ2eECTM1zftiBWj01Lr+NO2Q
```

ここで `allowed` は次の行です。
`bridge namespaces="krl@go-authn.github.io" <the CA key from /ssh/config>`。

十五秒後に発行された CRL:

```
$ openssl crl -inform DER -in var/bridge.crl -noout -text
Certificate Revocation List (CRL):
    Version 2 (0x1)
    Signature Algorithm: ecdsa-with-SHA256
    Issuer: CN=go-authn bridge NFS client CA
    Last Update: Oct 11 09:48:29 2026 GMT
    Next Update: Oct 11 10:48:29 2026 GMT
    CRL extensions:
        X509v3 Authority Key Identifier: 
            2A:90:7A:50:FF:65:52:BA:70:4E:E1:F8:70:EE:7A:FC:B1:8B:FE:4E
        X509v3 CRL Number: 
            1791712109993
No Revoked Certificates.
    Signature Algorithm: ecdsa-with-SHA256
    Signature Value:
        30:44:02:20:37:90:14:6f:c1:f2:ea:98:29:04:61:88:a8:17:
        88:e3:f6:84:9d:46:a7:fc:2b:ac:81:26:47:9d:ac:84:23:38:
        02:20:0a:a6:93:cb:7d:2d:81:e4:59:d4:0d:a0:fd:f4:6e:75:
        c9:0d:53:e7:92:49:ac:a1:31:a8:90:09:91:d1:87:b6
```

証明書は、期限が切れるまでリストに残ります。期限切れの証明書は、リストになくてもどこでも
拒否されます。

### 誰がそれを読むか {#who-reads-them}

- 通常の `sshd`、あるいは nginx などの TLS サーバー:
  [authn-revokd]({{< relref "/authn-revokd/_index.md" >}}) がリストを取得し、検証に通ったものだけを
  保持し、サーバーが読む場所に書き込み、リストが失効したときは sshd 向けにフェイルクローズします。
- [go-fileshare](https://go-fileshare.github.io/docs/latest/security/revocation-lists/)
  は自身でそれらを取得して検証し、現在のリストを保持していない間はプロバイダーの証明書を
  拒否します。

## Shared Signals {#shared-signals}

アクセストークンや opkssh 証明書は使われる場所で検証され、どのリストもそれを名指しできません。
そこでプロバイダーは OpenID Shared Signals のトランスミッターになります。`DisablePerson`、
`RevokePerson`、`DisableIdP` のとき、要求したすべてのレシーバーに向けて CAEP の
**`session-revoked`** イベント (このサブジェクト宛てにイベント時刻より前に発行されたすべては
無効) をキューに入れます。

```hcl
state { ... }            # required: a queue a restart empties loses revocations
ssf {}                   # event_retention = "192h" by default

client "fileshare-ssf" { # a receiver: client credentials, scope ssf
  secret_file  = "/etc/authn-bridge/fileshare-ssf.secret"
  ssf_receiver = true
  audience     = ["fileshare"]
}
```

```
$ curl -s http://127.0.0.1:28473/.well-known/ssf-configuration | jq .
{
  "issuer": "http://127.0.0.1:28473",
  "jwks_uri": "http://127.0.0.1:28473/jwks",
  "delivery_methods_supported": [
    "urn:ietf:rfc:8936"
  ],
  "configuration_endpoint": "http://127.0.0.1:28473/ssf/streams",
  "status_endpoint": "http://127.0.0.1:28473/ssf/streams/status",
  "add_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:add",
  "remove_subject_endpoint": "http://127.0.0.1:28473/ssf/streams/subjects:remove",
  "verification_endpoint": "http://127.0.0.1:28473/ssf/streams/verify",
  "spec_version": "1_0",
  "authorization_schemes": [
    {
      "spec_urn": "urn:ietf:rfc:6749"
    }
  ]
}
```

- **ポーリング配信のみ** (RFC 8936): レシーバーが問い合わせ、ここから外へ発信することはありません。
- レシーバーは、シークレットを持つ `ssf_receiver` クライアントの、スコープ `ssf` での
  **クライアントクレデンシャル**グラントによるアクセストークンで認証します。見えるのは
  自分自身のストリームだけで、最大十個です。
- イベントは SET (RFC 8417) で、ID トークンの鍵で署名され、`exp` も `sub` もありません。
  サブジェクトは既定では**アカウント**、`acct:<username>` です。`sub` はクライアントごとに一つの
  ペアワイズである場合があるためです。`ssf_subject_format = "iss_sub"` と設定されたレシーバーは、
  代わりに発行者とパブリックな `sub` を得ます。
- 機関の無効化は、プロバイダーがそこに痕跡を持つ人ごとに一つのイベントと、**テナント**、つまり
  その機関のエンティティ ID をサブジェクトとし、そのスコープを伴う一つのイベントになります。
  後者は、プロバイダーが忘れてしまった人々をカバーします。
- ストリームと未配信のイベントは、確認応答されるか `event_retention` が過ぎるまで、`state`
  データベースに保持されます。レシーバーがエラーと報告したイベントは、最大十回まで再度渡されます。

SSF ブロックは `state` ブロックなしでは拒否されます。

```
authn-bridge: ssf: needs a state block: a queue a restart empties loses revocations
```
