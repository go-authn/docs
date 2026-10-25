---
title: "验证下载"
linkTitle: "验证下载"
weight: 10
description: "每个版本发布什么，以及用来分辨发布工作流构建的二进制文件与其他文件的三项检查。"
tags: [安全, 发布版本]
---

authnd、authn-bridge、authn-revokd 和 sshcert 的每个版本都发布六个
静态二进制文件（`CGO_ENABLED=0`：linux、darwin 和 windows，各有 amd64 与
arm64），一个 `SHA256SUMS` 文件，以及针对每个
二进制文件的构建溯源证明。下面的示例使用 authn-bridge v0.23.3；其他程序
的做法相同，只需换成各自的仓库和名称。

```sh
gh release download v0.23.3 --repo go-authn/bridge
```

## 1. 校验和 {#1-the-checksum}

```sh
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```
authn-bridge-darwin-amd64: OK
authn-bridge-darwin-arm64: OK
authn-bridge-linux-amd64: OK
authn-bridge-linux-arm64: OK
authn-bridge-windows-amd64.exe: OK
authn-bridge-windows-arm64.exe: OK
```

这只能证明该文件就是版本发布所列出的那个，仅此而已：能够
替换发布页面上二进制文件的人，同样可以替换其旁边的 `SHA256SUMS`。

## 2. 溯源 {#2-the-provenance}

```sh
gh attestation verify authn-bridge-linux-amd64 --repo go-authn/bridge
echo $?
```

该证明由 GitHub 针对构建该文件的工作流运行签名，
因此它指明的是仓库和工作流，而不是某人持有的密钥。

{{< callout type="warning" >}}
**请看退出状态，而不是输出。** 在没有终端时，某些版本的
`gh` 在验证成功时什么也不输出：在 authnd 上用 gh
2.65.0 测得，真正的二进制文件给出退出状态 0 和空输出。末尾多了
一个字节的二进制文件给出退出状态 1 以及
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`，
因为其摘要没有对应的证明。沉默不是失败；非零状态才是。
{{< /callout >}}

## 3. 二进制文件自述的内容 {#3-what-the-binary-says-about-itself}

```sh
go version -m authn-bridge-linux-amd64
```

```
authn-bridge-linux-amd64: go1.27.3
	path	github.com/go-authn/bridge/cmd/authn-bridge
	mod	github.com/go-authn/bridge	v0.23.3	
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=b04769c43c24f684df9e0b5a0d1cb6997ee90d95
	build	vcs.modified=false
```

（已精简为重要的几行；第一行是构建该二进制文件的 Go 工具链。）`mod` 行必须与标签完全一致，且 `vcs.modified` 必须为 `false`：
从含有未提交更改的目录树构建的程序会显示 `true`，其版本读作 `v0.23.3+dirty`。
除非六个二进制文件中的**每一个**都通过这两项检查，并且程序在其
版本行的最后一个词中打印出标签，否则发布工作流拒绝发布：

```
$ authnd --version
authnd version v0.12.0
$ authn-bridge --version
authn-bridge version v0.23.3
$ authn-revokd -version
authn-revokd v0.6.5
```

authnd 和 authn-bridge 接受 `--version`；authn-revokd 接受 `-version`，即 Go 的
标准 flag 语法。从 v0.6.1 起，它像另外两个一样输出到标准输出，
因此 `v=$(authn-revokd -version)` 可以捕获它。

## 哪些版本带有二进制文件 {#which-releases-have-binaries}

二进制文件、校验和与证明从 authnd v0.9.2、authn-bridge
v0.19.3、authn-revokd v0.5.0 和 sshcert v0.1.2 开始发布。各程序的第一个版本
在检出目录内构建其二进制文件，并报告 `+dirty`；这在
下一个版本中修复，逐个二进制文件的检查则在此之后加入。更早的标签
只有源代码：用 `go install …@<tag>` 构建它们，这会将标签记录在
`go version -m` 所读取的构建信息中。程序自己输出的内容并不总是如此：在
v0.1.5 之前，sshcert-authorize 对 `go install` 构建输出 `dev`，而
revokd 在 v0.5.0 之前没有 `-version`。
