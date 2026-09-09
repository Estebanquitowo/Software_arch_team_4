# Assignment 3: tests de regresión (fase roja)

No se modificó producción ni la suite original. Se utiliza Minitest/Rails.

## Ejecutar de forma aislada

Desde la raíz, con Docker Desktop funcionando:

```sh
docker compose -p a3-regression -f test/compose.yml up --build --attach tests --abort-on-container-exit --exit-code-from tests
```

El código de salida **1 es esperado** mientras existan los fallos. El comando
detiene solo este proyecto de tests al terminar. No utiliza containers, puertos,
volúmenes o datos del Compose habitual. MongoDB escribe en tmpfs y Redis tiene
persistencia deshabilitada. La copia del repositorio se monta read-only y se
ejecuta una copia temporal: Bundler no puede modificar el Gemfile.lock del host.

Para ejecutar archivos concretos/otro orden:

```sh
docker compose -p a3-regression -f test/compose.yml run --rm tests sh /source/test/support/run-suite.sh test/integration/search_failure_test.rb --seed 12345
docker compose -p a3-regression -f test/compose.yml stop
```

Sin Docker: se necesitan las gems del lockfile, MongoDB de tests y un Redis
exclusivo de tests. Establecer `MONGODB_TEST_URI`, `REGRESSION_REDIS_URL`,
`CACHE_ENABLED=false`, `SEARCH_ENABLED=false`, `PARALLEL_WORKERS=1` y ejecutar
`bin/rails test`. No usar URLs de servicios/datos normales.

## Diseño y límites

- Los tests originales permanecen intactos. El comando fija un worker: la suite
  preexistente usa `delete_all` y no asigna bases MongoDB por worker.
- Los casos de arranque, recarga y búsqueda arrancan Rails en un **subproceso
  development**. No se recarga la aplicación del proceso Minitest. Cada escenario
  genera un nombre de base aleatorio terminado en `_test`, comprueba el nombre
  efectivo antes de escribir y elimina únicamente esa base al terminar.
- Cada escenario tiene un timeout de 60 segundos; excederlo es un error del
  harness/backend, no un skip ni un fallo que se interprete como bug demostrado.
- Redis es **real**. Un proxy TCP local transmite los bytes del cliente real y
  corta conexiones nuevas y existentes bajo un mutex. `online!`/`offline!`
  controlan el orden; no se mata el container, no hay sleeps ni stubs de cache.
  Un observador independiente lee las claves reales. Un namespace aleatorio
  evita mezclar entradas; no se usa FLUSHDB/FLUSHALL.
- Meilisearch no necesita un servidor real para estos dos casos: un endpoint
  HTTP local devuelve 503 al SDK real. Se comprueba que recibió peticiones.
  Los fixtures se insertan directamente, después de validarlos, para representar
  libros existentes cuando cae el índice. La modificación que se prueba pasa
  por PATCH del controlador y por todos los callbacks reales.
  Esto cubre indisponibilidad HTTP, no indexación exitosa, restauración del
  índice, DNS, timeouts ni todos los modos de fallo de un cluster Meilisearch.
- Las carreras usan dos instancias independientes con asociaciones precargadas:
  A lee vacío → B lee vacío → A guarda → B guarda con su snapshot antiguo.
  Se relee desde MongoDB y se comprueban tanto los embebidos como el agregado.
  Es un interleaving determinista, no una prueba de carga con threads.
- Los cambios de ENV y Rails.cache del test de promedio se restauran en teardown.

## Contrato propuesto para el promedio individual

`Book#average_review_score` es una **API propuesta**, todavía inexistente. Sería
un lector público del dominio consumido por las vistas/services y delegado a
`CacheService` para la política read-through. No sustituye ni renombra el campo
persistido `avg_score`.

Los tres tests fallan actualmente en `assert_respond_to`: expresan funcionalidad
faltante, no inventan un método dentro del test para aparentar que existe.
El resto del contrato queda escrito para cuando se implemente: miss que escribe
el valor, key identificando al libro, hit desde otra instancia, aislamiento entre
libros e invalidación/refill al crear, modificar y borrar reviews. Esas assertions
posteriores **todavía no se alcanzan** con el código actual.

## Resultados comprobados

Antes de agregar archivos: **17 runs, 45 assertions, 0 failures, 0 errors**.

Suite ampliada: **28 runs, 88 assertions, 10 failures, 0 errors, 0 skips**.

| Caso | Archivo | Resultado actual |
|---|---|---|
| Flag false realmente deshabilita | services/cache_service_test.rb | FAIL: enabled=true, valores [1,1], resultado retenido |
| Redis se recupera tras fallo al arrancar | services/cache_service_test.rb | FAIL: MemoryStore permanente, ninguna entrada nueva en Redis |
| Invalidación tras reload | integration/cache_invalidation_test.rb | FAIL: MongoDB nuevo / respuesta vieja |
| Invalidación perdida durante outage | integration/cache_invalidation_test.rb | FAIL: Redis y respuesta viejos tras recuperar conexión |
| Promedio con dos snapshots | models/review_concurrency_test.rb | FAIL: reviews [5,1], promedio 1 en vez de 3 |
| Ventas con dos snapshots | models/sale_concurrency_test.rb | FAIL: ventas [10,20], total 20 en vez de 30 |
| PATCH con buscador caído | integration/search_failure_test.rb | FAIL: cambio persistido pero HTTP 500 en vez de 303 |
| Fallback de búsqueda | integration/search_failure_test.rb | PASS: HTTP 200, engine meilisearch_error, coincidencia solo por summary |
| Cache individual: create/update/destroy | services/book_average_cache_test.rb | 3 FAIL: API read-through inexistente |

Los 17 tests originales siguen pasando. Los fallos nuevos no se han convertido
en skips, ni se han relajado expectativas para aceptar comportamiento incorrecto.
