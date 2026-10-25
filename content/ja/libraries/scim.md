---
title: "scim — ID プロバイダーからの人とグループのプロビジョニング"
linkTitle: "scim"
weight: 140
description: "go-authn/scim は SCIM 2.0 サービスプロバイダー (RFC 7643、RFC 7644): あなたが書く Backend 上の Users と Groups。Entra ID と Okta のペイロードでテスト済み。標準ライブラリのみ。"
tags: [ライブラリ, scim, プロビジョニング]
---

**ID プロバイダーが作成、変更、削除したのは誰か。**
ID プロバイダー (Entra ID、Okta、Keycloak、…) は、あなたのアプリケーションの人々とグループを HTTP
経由で作成、更新、削除します。このパッケージはその HTTP エンドポイントで、Users と Groups
(RFC 7643、RFC 7644) を、あなたが書く `Backend` の上で扱います。純粋な Go、`CGO_ENABLED=0`、
標準ライブラリのみ。

```sh
go get github.com/go-authn/scim@v0.1.0
```

## 例 {#example}

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

Server は ID、タイムスタンプ、バージョンを割り当て、入力を検証し、PATCH を適用します。`Backend` は
与えられたものを保持し、自分だけが見られることを強制します。取られている `userName` には
`ErrConflict` (409 `uniqueness`)、存在しないメンバーには `InvalidValue` (400 `invalidValue`)、保存された
バージョンが読んだものと異なる場合は `ErrPrecondition` です。`NewMemory()` はリファレンス実装です。

`/Users` と `/Groups` (`filter`、`startIndex`、`count`、`attributes`、`excludedAttributes` を伴う一覧、
作成、`ETag` と `If-Match` を伴う ID による取得、`PUT`、`PATCH`、`DELETE`)、`/Users/.search` と
`/Groups/.search`、そしてディスカバリーエンドポイント `/ServiceProviderConfig`、`/ResourceTypes`、
`/Schemas` を提供します。フィルターは RFC 7644 §3.4.2.2 の文法全体をカバーし、PATCH はアトミックです。
失敗した操作は、リソースを元のままにします。

## 拒否するものと、その理由 {#what-it-refuses-and-why}

ここにあるものはすべて外から来るので、上限は API の一部です。

| | |
|---|---|
| `MaxBodyBytes` (1 MiB) を超える本文、`MaxOperations` (100) を超える PATCH、またはリソースを本文の上限を超えて大きくするもの | 413 |
| `MaxMembers` (10 000) を超えるグループ | 400 `invalidValue` |
| 4 KiB を超える、32 より深く入れ子になった、未知の演算子を持つ、またはブール値に `gt` を使うフィルター | 400 `invalidFilter` |
| `id`、`meta`、`schemas`、またはユーザーの `groups` への書き込み | 400 `mutability` |
| コアスキーマのないリソース、空の、256 バイトを超える、または制御文字を含む `userName`、二つのプライマリメール | 400 |
| ベアラートークンがない、または間違っている (`BearerAuth`。一定時間。空のトークンは誰も通さない) | 401 |
| 番兵エラーのいずれでもない Backend のエラー | 何も述べない本文を伴う 500。エラーは `ErrorLog` に行く |

**サポートしないもの**: 一括操作、並べ替え、パスワード変更、`/Me`
(`/ServiceProviderConfig` でそう通知される)。

## 何に対して検証されているか {#what-it-is-checked-against}

**ID プロバイダーが実際に送るもの**を、そのペイロードでテストしています。Entra ID の `"Replace"`、
文字列のブール値 (`"active": "False"`)、値リストによるメンバーの削除、メールを作成するフィルター付きの
追加。Okta の、`id` を繰り返すパスなしの置換。フィルター、PATCH、ハンドラー全体はファジングされ
(`FuzzFilter`、`FuzzPatch`、`FuzzServer`)、カバレッジレーンの下限は 92% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
