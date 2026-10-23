---
title: "scim — aprovisionar personas y grupos desde un proveedor de identidad"
linkTitle: "scim"
weight: 140
description: "go-authn/scim es un proveedor de servicio SCIM 2.0 (RFC 7643, RFC 7644): Users y Groups sobre un Backend que usted escribe, con las cargas útiles de Entra ID y Okta probadas. Solo biblioteca estándar."
tags: [bibliotecas, scim, aprovisionamiento]
---

**¿A quién acaba de crear, cambiar o eliminar el proveedor de identidad?**
Un proveedor de identidad (Entra ID, Okta, Keycloak, …) crea, actualiza y
elimina personas y grupos en su aplicación por HTTP; este paquete es ese punto
de acceso HTTP, para Users y Groups (RFC 7643, RFC 7644), sobre un `Backend`
que usted escribe. Go puro, `CGO_ENABLED=0`, solo biblioteca estándar.

```sh
go get github.com/go-authn/scim@v0.1.0
```

## Ejemplo {#example}

```go
srv := &scim.Server{
	Backend: scim.NewMemory(),                     // or your database
	BaseURL: "https://app.example.org/scim/v2",    // for meta.location
}
mux.Handle("/scim/v2/", http.StripPrefix("/scim/v2", scim.BearerAuth(token, srv)))
```

El Server asigna identificadores, marcas de tiempo y versiones, valida la
entrada y aplica PATCH; el `Backend` guarda lo que se le da e impone lo que solo
él puede ver: `ErrConflict` para un `userName` ya usado (409 `uniqueness`),
`InvalidValue` para un miembro que no existe (400 `invalidValue`),
`ErrPrecondition` cuando la versión almacenada no es la que se leyó.
`NewMemory()` es la implementación de referencia.

Sirve `/Users` y `/Groups` (lista con `filter`, `startIndex`, `count`,
`attributes`, `excludedAttributes`; creación; lectura, `PUT`, `PATCH` y
`DELETE` por identificador con `ETag` e `If-Match`), `/Users/.search` y
`/Groups/.search`, y los puntos de descubrimiento `/ServiceProviderConfig`,
`/ResourceTypes` y `/Schemas`. Los filtros cubren toda la gramática de la
RFC 7644 §3.4.2.2; PATCH es atómico: una operación que falla deja el recurso
como estaba.

## Qué rechaza, y por qué {#what-it-refuses-and-why}

Todo lo de aquí viene de fuera, así que los límites son parte de la API:

| | |
|---|---|
| un cuerpo de más de `MaxBodyBytes` (1 MiB), un PATCH con más de `MaxOperations` (100), o uno que hace crecer el recurso más allá del límite del cuerpo | 413 |
| un grupo con más de `MaxMembers` (10 000) | 400 `invalidValue` |
| un filtro de más de 4 KiB, anidado a más de 32 niveles, con un operador desconocido, o `gt` sobre un booleano | 400 `invalidFilter` |
| escrituras en `id`, `meta`, `schemas` o los `groups` de un usuario | 400 `mutability` |
| un recurso sin su esquema base, un `userName` vacío, de más de 256 bytes o con caracteres de control, dos correos principales | 400 |
| un token de portador ausente o incorrecto (`BearerAuth`, en tiempo constante; un token vacío no admite a nadie) | 401 |
| cualquier error del Backend que no sea uno de los centinelas | 500 con un cuerpo que no dice nada; el error va a `ErrorLog` |

**No admitido**: operaciones en bloque (bulk), ordenación, cambios de
contraseña, `/Me` (anunciado como tal en `/ServiceProviderConfig`).

## Contra qué se comprueba {#what-it-is-checked-against}

**Lo que los proveedores de identidad envían de verdad**, probado con sus
cargas útiles: el `"Replace"` de Entra ID, sus booleanos como cadenas
(`"active": "False"`), su retirada de miembros por lista de valores, su adición
filtrada que crea un correo; el reemplazo sin ruta de Okta que repite el `id`.
El filtro, PATCH y todo el manejador se prueban con fuzzing (`FuzzFilter`,
`FuzzPatch`, `FuzzServer`), y el umbral de la vía de cobertura es del 92 %.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.1.0](https://pkg.go.dev/github.com/go-authn/scim@v0.1.0)
