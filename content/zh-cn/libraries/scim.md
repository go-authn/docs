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
go get github.com/go-authn/scim@v0.1.0
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

## 它对照什么检查 {#what-it-is-checked-against}

**身份提供方实际发送的内容**，使用它们的载荷进行测试：Entra
ID 的 `"Replace"`、其字符串形式的布尔值（`"active": "False"`）、其按值列表
移除成员的方式、其创建电子邮件的带过滤器的添加；Okta 的不带
路径而重复 `id` 的 replace。过滤器、PATCH 和整个处理程序都经过模糊测试
（`FuzzFilter`、`FuzzPatch`、`FuzzServer`），覆盖率通道的下限是 92%。

## 参考 {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
