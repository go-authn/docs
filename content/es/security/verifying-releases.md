---
title: "Verificar una descarga"
linkTitle: "Verificar una descarga"
weight: 10
description: "Qué publica cada versión, y las tres comprobaciones que distinguen un binario compilado por el flujo de publicación de cualquier otro."
tags: [security, releases]
---

Cada versión de authnd, authn-bridge, authn-revokd y sshcert publica seis
binarios estáticos (`CGO_ENABLED=0`: linux, darwin y windows, en amd64 y arm64),
un archivo `SHA256SUMS` y una atestación de procedencia de compilación para cada
binario. Los ejemplos siguientes usan authn-bridge v0.20.1; los demás programas funcionan
igual, con su propio repositorio y su propio nombre.

```sh
gh release download v0.20.1 --repo go-authn/bridge
```

## 1. La suma de comprobación {#1-the-checksum}

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

Esto prueba que el archivo es el que lista la versión, y nada más: quien pudiera
sustituir un binario en la página de la versión podría sustituir también el
`SHA256SUMS` que lo acompaña.

## 2. La procedencia {#2-the-provenance}

```sh
gh attestation verify authn-bridge-linux-amd64 --repo go-authn/bridge
echo $?
```

La atestación la firma GitHub para la ejecución del flujo que compiló el archivo,
así que nombra el repositorio y el flujo, no una clave que alguien posee.

{{< callout type="warning" >}}
**Lea el código de salida, no la salida.** Sin un terminal, algunas versiones de
`gh` no muestran nada en absoluto cuando la verificación tiene éxito: medido con gh
2.65.0 sobre authnd, un binario auténtico dio el código de salida 0 y una salida vacía. Un binario
con un byte añadido al final dio el código de salida 1 y
`Error: failed to fetch attestations from go-authn/authnd: HTTP 404: Not Found`,
porque no existe ninguna atestación para su resumen. El silencio no es el fallo; un
código distinto de cero sí lo es.
{{< /callout >}}

## 3. Lo que el binario dice de sí mismo {#3-what-the-binary-says-about-itself}

```sh
go version -m authn-bridge-linux-amd64
```

```
	path	github.com/go-authn/bridge/cmd/authn-bridge
	mod	github.com/go-authn/bridge	v0.20.1	
	build	-trimpath=true
	build	CGO_ENABLED=0
	build	vcs.revision=d30d3b52b644c7db74c431c2a07b8d1aaeb1c0ff
	build	vcs.modified=false
```

(líneas reducidas a las que importan). La línea `mod` debe ser exactamente la
etiqueta, y `vcs.modified` debe ser `false`: una compilación a partir de un árbol con
cambios sin confirmar indica `true`, y su versión se lee `v0.20.1+dirty`. El flujo de
publicación se niega a publicar salvo que **todos y cada uno** de los seis binarios
superen ambas comprobaciones, y salvo que el programa muestre la etiqueta como
última palabra de su línea de versión:

```
$ authnd --version
authnd version v0.10.1
$ authn-bridge --version
authn-bridge version v0.20.1
$ authn-revokd -version
authn-revokd v0.6.2
```

authnd y authn-bridge aceptan `--version`; authn-revokd acepta `-version`, la
sintaxis de opciones estándar de Go. Desde la v0.6.1 escribe en la salida estándar,
como los otros dos, de modo que `v=$(authn-revokd -version)` la captura.

## Qué versiones tienen binarios {#which-releases-have-binaries}

Se publican binarios, sumas y atestaciones desde authnd v0.9.2, authn-bridge
v0.19.3, authn-revokd v0.5.0 y sshcert v0.1.2. La primera versión de cada uno
compiló sus binarios dentro de la copia de trabajo e indicaba `+dirty`; eso se
corrigió en la siguiente, y la comprobación binario por binario llegó después. Las
etiquetas anteriores son solo de código fuente: compílelas con `go install …@<tag>`,
que registra la etiqueta en la información de compilación que lee `go version -m`.
Lo que muestra el programa no siempre es eso: sshcert-authorize mostraba `dev` para una
compilación con `go install` hasta v0.1.5, y revokd no tiene `-version` antes de v0.5.0.
