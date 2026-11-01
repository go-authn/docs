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
go get github.com/go-authn/scim@v0.2.0
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

## v0.2.0 で変わったこと {#v020}

監査、ファジングとカオス、性能の実施を経て。呼び出し側に見えるもの:

- **`Server.ReadTimeout`** (新規、既定 30 秒): 到着に時間がかかりすぎるリクエストボディは 400 で打ち切られます。
  そのリクエストについて `http.Server` 自身の `ReadTimeout` を置き換えます。負の値なら `http.Server` のものがそのまま
  使われます。
- **`ConditionalDeleter`**: `Backend` が実装できる新しい省略可能なインターフェース (`DeleteUserIf`、`DeleteGroupIf`)。
  `Memory` は実装しています。`If-Match` 付きの `DELETE` はバージョンを確認してから二段階で削除していたため、その間に
  入った書き込みが見られずに削除されました。
- **負けた競合はやり直されます。** `If-Match` なしの `PATCH` や `PUT` が別の書き込み側との競合に負けると、クライアントは
  前提条件を求めていないのに 412 が返っていました。今は新しいバージョンでやり直され、最大 32 回です。`If-Match` が
  あれば応答は今も 412 です。`If-Match` なしの 24 並行 PATCH のうち、以前は 9 件が 412 で失敗し、今は 0 件です。
- 何にも一致しないフィルターでメンバー (や任意の要素) を削除すると成功します。以前は 400 `noTarget` でした
  (RFC 7644 §3.5.2.2)。
- パスなしの PATCH は、キーをソート順に適用します。以前はマップの順序だったため、一つのオブジェクトの `name` と
  `name.givenName` が実行のたびに異なるリソースになりました。
- `BearerAuth` はスキーム名を大文字小文字を問わず受け入れます (`bearer <token>`、RFC 7235 §2.1)。
- `startIndex` と `count` は `int` の大きさにかかわらず上限に丸められます。以前は 32 ビットのターゲットでは 400、
  64 ビットでは丸められたページでした。
- `Filter.Equality()` は `Backend` にデコード済みの文字列を渡します。これはデータです。パラメーターとしてデータベースに
  渡し、決してクエリに埋め込まないでください。

バルク操作、ソート、パスワード変更は引き続きサポートされません。

`Memory` での、10,000 ユーザーと 200 グループに対する一回のリスト要求の**アロケーション**。`go test -bench` による正確な値、
Apple M4 Max:

| リスト要求 | 以前 | 以後 |
|---|---|---|
| 100 件のページ | 789,417 回、47.7 MB | 14,952 回、6.0 MB |
| `userName eq` | 797,979 回、47.7 MB | 90 回、12.6 KB |
| すべてのユーザーを走査するフィルター (`name.givenName eq` と `emails[...]`) | 818,847 回、48 MB | 361,098 回、29.7 MB |

実時間は測定していません。負荷が 65 で、規則は 9 未満です。ノイズの多い単発の実行 (走査するフィルターで約 1.7 秒から
0.06 秒) は結果ではありません。`FuzzPatchPath`、`FuzzPatchThenDecode`、`FuzzFilter`、`FuzzServer` をそれぞれ 45 秒、
16 ワーカーで実行し、130 万から 240 万回の実行で失敗は見つかりませんでした。

## 何に対して検証されているか {#what-it-is-checked-against}

**ID プロバイダーが実際に送るもの**を、そのペイロードでテストしています。Entra ID の `"Replace"`、
文字列のブール値 (`"active": "False"`)、値リストによるメンバーの削除、メールを作成するフィルター付きの
追加。Okta の、`id` を繰り返すパスなしの置換。フィルター、PATCH、ハンドラー全体はファジングされ
(`FuzzFilter`、`FuzzPatch`、`FuzzServer`)、カバレッジレーンの下限は 92% です。

## リファレンス {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.2.0](https://pkg.go.dev/github.com/go-authn/scim@v0.2.0)
