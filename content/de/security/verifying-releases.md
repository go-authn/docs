---
title: "Einen Download prüfen"
linkTitle: "Einen Download prüfen"
weight: 10
description: "Was jedes Release veröffentlicht, und die drei Prüfungen, die ein vom Release-Workflow gebautes Binary von allem anderen unterscheiden."
tags: [security, releases]
---

Jedes Release von authnd, authn-bridge, authn-revokd und sshcert veröffentlicht sechs
statische Binaries (`CGO_ENABLED=0`: linux, darwin und windows, auf amd64 und
arm64), eine Datei `SHA256SUMS` und eine Build-Provenienz-Attestierung für jedes
Binary. Die folgenden Beispiele verwenden authnd v0.9.6; die anderen Programme
funktionieren genauso, mit ihrem eigenen Repository und Namen.

```sh
gh release download v0.9.6 --repo go-authn/authnd
```

## 1. Die Prüfsumme {#1-the-checksum}

```sh
sha256sum -c SHA256SUMS --ignore-missing      # macOS: shasum -a 256 -c SHA256SUMS
```

```
authnd-linux-amd64: OK
```

Das belegt, dass die Datei diejenige ist, die das Release aufführt, und nichts weiter:
Wer ein Binary auf der Release-Seite ersetzen könnte, könnte auch `SHA256SUMS`
daneben ersetzen.

## 2. Die Provenienz {#2-the-provenance}

```sh
gh attestation verify authnd-linux-amd64 --repo go-authn/authnd
echo $?
```

Die Attestierung wird von GitHub für den Workflow-Lauf signiert, der die Datei gebaut
hat; sie nennt also das Repository und den Workflow, nicht einen Schlüssel, den jemand hält.

{{< callout type="warning" >}}
**Lesen Sie den Exit-Status, nicht die Ausgabe.** Ohne Terminal geben manche Versionen
von `gh` überhaupt nichts aus, wenn die Prüfung gelingt: Gemessen mit gh
2.65.0 ergab ein echtes Binary den Exit-Status 0 und eine leere Ausgabe. Ein Binary mit
einem angehängten Byte ergab den Exit-Status 1 und
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`,
weil für seinen Digest keine Attestierung existiert. Stille ist nicht der Fehlschlag;
ein Status ungleich null ist es.
{{< /callout >}}

## 3. Was das Binary über sich selbst sagt {#3-what-the-binary-says-about-itself}

```sh
go version -m authnd-linux-amd64
```

```
	path	github.com/go-authn/authnd
	mod	github.com/go-authn/authnd	v0.9.6
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=82da8e7ec3dff61e4e883a1bd03600aa550af48a
	build	vcs.modified=false
```

(auf die Zeilen gekürzt, auf die es ankommt). Die `mod`-Zeile muss genau der Tag sein,
und `vcs.modified` muss `false` sein: Ein Build aus einem Baum mit nicht committeten
Änderungen sagt `true`, und seine Version lautet `v0.9.6+dirty`. Der
Release-Workflow verweigert die Veröffentlichung, sofern nicht **jedes einzelne** der
sechs Binaries beide Prüfungen besteht und das Programm den Tag als letztes Wort seiner
Versionszeile ausgibt:

```
$ authnd --version
authnd version v0.9.6
$ authn-bridge --version
authn-bridge version v0.20.0
$ authn-revokd -version
authn-revokd v0.6.1
```

authnd und authn-bridge nehmen `--version`; authn-revokd nimmt `-version`, die
Standard-Flag-Syntax von Go. Ab v0.6.1 gibt es auf der Standardausgabe aus, wie die
beiden anderen, sodass `v=$(authn-revokd -version)` es erfasst.

## Welche Releases Binaries haben {#which-releases-have-binaries}

Binaries, Prüfsummen und Attestierungen werden ab authnd v0.9.2, authn-bridge
v0.19.3, authn-revokd v0.5.0 und sshcert v0.1.2 veröffentlicht. Das erste Release
jedes Programms baute seine Binaries innerhalb des Checkouts und meldete `+dirty`; das
wurde im nächsten behoben, und die Prüfung pro Binary kam danach. Frühere Tags
gibt es nur als Quellcode: Bauen Sie sie mit `go install …@<tag>`, das die Version
auf dieselbe Weise festhält.
