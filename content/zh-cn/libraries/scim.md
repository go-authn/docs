---
title: "scim — 从身份提供方开通人员和组"
linkTitle: "scim"
weight: 140
description: "go-authn/scim 是 SCIM 2.0 服务提供方（RFC 7643、RFC 7644）：基于你编写的 Backend 提供 Users 和 Groups，并已用 Entra ID 和 Okta 的载荷测试。仅依赖标准库。"
tags: [库, scim, 账户开通]
---

**身份提供方刚刚创建、更改或删除了谁？**
身份提供方（Entra ID、Okta、Keycloak 等）通过 HTTP 在你的应用程序中创建、更新和删除
人员和组；本包就是这个 HTTP
端点，面向 Users 和 Groups（RFC 7643、RFC 7644），基于你
编写的 `Backend`。纯 Go，`CGO_ENABLED=0`，仅依赖标准库。

```sh
go get github.com/go-authn/scim@v0.2.0
```

## 示例 {#example}

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

Server 分配 id、时间戳和版本，验证输入并应用
PATCH；`Backend` 保存其收到的内容，并强制执行只有它才能看到的约束：
已被占用的 `userName` 返回 `ErrConflict`（409 `uniqueness`），不存在的成员
返回 `InvalidValue`（400 `invalidValue`），所存储的版本
不是所读取的版本时返回 `ErrPrecondition`。`NewMemory()` 是参考
实现。

它提供 `/Users` 和 `/Groups`（带 `filter`、`startIndex`、`count`、
`attributes`、`excludedAttributes` 的列表；创建；按
id 的 get、`PUT`、`PATCH` 和 `DELETE`，带 `ETag` 和 `If-Match`）、`/Users/.search` 和 `/Groups/.search`，以及
发现端点 `/ServiceProviderConfig`、`/ResourceTypes` 和 `/Schemas`。
过滤器涵盖 RFC 7644 §3.4.2.2 的完整语法；PATCH 是原子的：失败的
操作会使资源保持原样。

## 它拒绝什么，以及原因 {#what-it-refuses-and-why}

这里的一切都来自外部，因此限制是 API 的一部分：

| | |
|---|---|
| 超过 `MaxBodyBytes`（1 MiB）的请求体、操作数超过 `MaxOperations`（100）的 PATCH，或使资源超出请求体限制的 PATCH | 413 |
| 成员数超过 `MaxMembers`（10 000）的组 | 400 `invalidValue` |
| 超过 4 KiB、嵌套深于 32、使用未知运算符，或对布尔值使用 `gt` 的过滤器 | 400 `invalidFilter` |
| 对 `id`、`meta`、`schemas` 或用户的 `groups` 的写入 | 400 `mutability` |
| 没有其核心模式的资源、为空、超过 256 字节或含有控制字符的 `userName`、两个主要电子邮件 | 400 |
| 缺失或错误的持有者令牌（`BearerAuth`，常量时间；空令牌不放行任何人） | 401 |
| 不属于哨兵值的任何 Backend 错误 | 500，响应体不透露任何信息；错误写入 `ErrorLog` |

**不支持：** 批量操作、排序、密码更改、`/Me`
（已在 `/ServiceProviderConfig` 中如此声明）。

## v0.2.0 改变了什么 {#v020}

经过审计、模糊测试和混沌测试以及性能改进。调用方能看到的：

- **`Server.ReadTimeout`**（新增，默认 30 秒）：到达时间过长的请求体会被以 400 切断。它对该请求取代 `http.Server`
  自己的 `ReadTimeout`；负值则保持 `http.Server` 的设置不变。
- **`ConditionalDeleter`**：`Backend` 可以实现的新的可选接口（`DeleteUserIf`、`DeleteGroupIf`），`Memory` 已实现。
  带 `If-Match` 的 `DELETE` 过去先检查版本再分两步删除，所以在两步之间落地的写入会在未被看到的情况下被删除。
- **输掉的竞争会被重做。** 没有 `If-Match` 的 `PATCH` 或 `PUT` 在与另一个写入者的竞争中失败时，即使客户端没有要求
  任何前置条件，也会收到 412；现在它会在较新的版本上重做，最多 32 次。有 `If-Match` 时答复仍是 412。24 个没有
  `If-Match` 的并发 PATCH，过去有 9 个以 412 失败，现在为 0 个。
- 通过一个不匹配任何内容的过滤器移除成员（或任何元素）会成功；过去是 400 `noTarget`（RFC 7644 §3.5.2.2）。
- 没有路径的 PATCH 按排序顺序应用其键；过去使用映射的顺序，所以同一对象中的 `name` 和 `name.givenName`
  每次运行得到不同的资源。
- `BearerAuth` 接受任意大小写的方案名（`bearer <token>`，RFC 7235 §2.1）。
- `startIndex` 和 `count` 无论 `int` 的大小都会被限定：超出的值过去在 32 位目标上是 400，在 64 位目标上是被限定的页面。
- `Filter.Equality()` 把解码后的字符串交给 `Backend`。它是数据：作为参数传给数据库，绝不要拼接进查询。

批量操作、排序和密码更改仍不受支持。

在 `Memory` 上，针对 10,000 个用户和 200 个组的一次列表请求的**分配**，精确，来自 `go test -bench`，Apple M4 Max：

| 列表请求 | 之前 | 之后 |
|---|---|---|
| 100 条的一页 | 789,417 次分配，47.7 MB | 14,952 次分配，6.0 MB |
| `userName eq` | 797,979 次分配，47.7 MB | 90 次分配，12.6 KB |
| 扫描每个用户的过滤器（`name.givenName eq` 和 `emails[...]`） | 818,847 次分配，48 MB | 361,098 次分配，29.7 MB |

没有测量挂钟时间：负载为 65，而规则要求低于 9。嘈杂的单次运行（扫描过滤器约 1.7 秒对 0.06 秒）不算结果。
`FuzzPatchPath`、`FuzzPatchThenDecode`、`FuzzFilter` 和 `FuzzServer` 各运行 45 秒，16 个工作线程，130 万到 240 万次执行，
没有发现失败。

## 它对照什么检查 {#what-it-is-checked-against}

**身份提供方实际发送的内容**，使用它们的载荷进行测试：Entra
ID 的 `"Replace"`、其字符串形式的布尔值（`"active": "False"`）、其按值列表
移除成员的方式、其创建电子邮件的带过滤器的添加；Okta 的不带
路径而重复 `id` 的 replace。过滤器、PATCH 和整个处理程序都经过模糊测试
（`FuzzFilter`、`FuzzPatch`、`FuzzServer`），覆盖率通道的下限是 92%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.2.0](https://pkg.go.dev/github.com/go-authn/scim@v0.2.0)
