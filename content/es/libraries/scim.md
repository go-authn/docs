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
go get github.com/go-authn/scim@v0.2.0
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

## Qué cambió la v0.2.0 {#v020}

Tras una auditoría, una pasada de fuzzing y caos y una pasada de rendimiento. Lo que un
llamante puede ver:

- **`Server.ReadTimeout`**, nuevo, 30 s por defecto: un cuerpo de petición que tarda más en
  llegar se corta con un 400. Sustituye al `ReadTimeout` propio del `http.Server` para la
  petición; un valor negativo deja el del `http.Server`.
- **`ConditionalDeleter`**, una nueva interfaz opcional que un `Backend` puede implementar
  (`DeleteUserIf`, `DeleteGroupIf`), lo que hace `Memory`. `DELETE` con `If-Match`
  comprobaba la versión y borraba en dos pasos, de modo que una escritura que llegaba entre
  medias se borraba sin verse.
- **Una carrera perdida se rehace.** Un `PATCH` o `PUT` sin `If-Match` que perdía una carrera
  con otro escritor se respondía con 412 aunque el cliente no pidiera ninguna precondición;
  ahora se rehace sobre la versión más nueva, como máximo 32 veces. Con `If-Match` la
  respuesta sigue siendo 412. De 24 PATCH concurrentes sin `If-Match`, 9 fallaban con 412
  antes y ninguno ahora.
- Quitar un miembro, o cualquier elemento, mediante un filtro que no coincide con nada
  tiene éxito; era un 400 `noTarget` (RFC 7644 §3.5.2.2).
- Un PATCH sin ruta aplica sus claves en orden ordenado; usaba el orden del mapa, de modo
  que `name` y `name.givenName` en un mismo objeto daban un recurso distinto de una
  ejecución a otra.
- `BearerAuth` acepta el nombre del esquema en cualquier caso (`bearer <token>`, RFC 7235
  §2.1).
- `startIndex` y `count` se acotan sea cual sea el tamaño de un `int`: un valor por encima
  era un 400 en destinos de 32 bits y una página acotada en los de 64 bits.
- Un `Filter.Equality()` entrega a un `Backend` la cadena decodificada. Es un dato: páselo a
  la base de datos como parámetro y nunca lo inserte en una consulta.

Las operaciones en bloque, la ordenación y los cambios de contraseña siguen sin
soportarse.

**Asignaciones** de una petición de lista sobre 10 000 usuarios y 200 grupos con `Memory`,
exactas, de `go test -bench`, Apple M4 Max:

| petición de lista | antes | después |
|---|---|---|
| una página de 100 | 789 417 asignaciones, 47,7 MB | 14 952 asignaciones, 6,0 MB |
| `userName eq` | 797 979 asignaciones, 47,7 MB | 90 asignaciones, 12,6 KB |
| un filtro que recorre todos los usuarios (`name.givenName eq` y `emails[...]`) | 818 847 asignaciones, 48 MB | 361 098 asignaciones, 29,7 MB |

No se midió el tiempo de reloj: la carga era de 65, y la regla es menos de 9. Las ejecuciones
sueltas ruidosas (unos 1,7 s a 0,06 s para el filtro que recorre) no son un resultado.
`FuzzPatchPath`, `FuzzPatchThenDecode`, `FuzzFilter` y `FuzzServer` corrieron 45 s cada uno
con 16 trabajadores, de 1,3 a 2,4 millones de ejecuciones, y no encontraron ningún fallo.

## Contra qué se comprueba {#what-it-is-checked-against}

**Lo que los proveedores de identidad envían de verdad**, probado con sus
cargas útiles: el `"Replace"` de Entra ID, sus booleanos como cadenas
(`"active": "False"`), su retirada de miembros por lista de valores, su adición
filtrada que crea un correo; el reemplazo sin ruta de Okta que repite el `id`.
El filtro, PATCH y todo el manejador se prueban con fuzzing (`FuzzFilter`,
`FuzzPatch`, `FuzzServer`), y el umbral de la vía de cobertura es del 92 %.

## Referencia {#reference}

[pkg.go.dev/github.com/go-authn/scim@v0.2.0](https://pkg.go.dev/github.com/go-authn/scim@v0.2.0)
