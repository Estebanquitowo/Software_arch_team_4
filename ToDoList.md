# TODO List

# Lista de Tareas: Assignment 3 - Caching & Search

## 1. Implementación de Caché
- [x] Integrar un sistema de caché (Redis, Memcached, etc.) en la aplicación [cite: 1].
- [x] Configurar la aplicación para que funcione de manera opcional con o sin el caché [cite: 1].
- [x] Almacenar en caché la tabla de resumen de autores (número de libros publicados, puntuación media, ventas totales) [cite: 1].
- [x] Almacenar en caché las tablas de los 10 libros mejor valorados y los 50 libros más vendidos [cite: 1].
- [x] Almacenar en caché la puntuación media de las reseñas de un libro [cite: 1].
- [x] Implementar una lógica donde, si hay un fallo en el caché (miss), la lectura recurra a la base de datos y llene el caché [cite: 1].
- [x] Implementar la invalidación del caché al crear, editar o eliminar una reseña (afecta la puntuación media, el top 10 y el resumen del autor) [cite: 1].
- [x] Implementar la invalidación del caché al crear, editar o eliminar una venta (afecta el top 50 y las ventas totales del autor) [cite: 1].
- [x] Implementar la invalidación del caché al editar un libro o autor (afecta el resumen del autor) [cite: 1].

## 2. Motor de Búsqueda (Search Engine)
- [x] Integrar un motor de búsqueda de texto (OpenSearch, Elasticsearch, Lucene, etc.) [cite: 1].
- [x] Configurar la aplicación para que el motor de búsqueda sea opcional, recurriendo a una consulta de base de datos (LIKE en el resumen) si está ausente [cite: 1].
- [x] Indexar el nombre y el resumen de cada libro [cite: 1].
- [x] Indexar el texto de cada reseña [cite: 1].
- [x] Modificar la ventana de búsqueda (del Assignment 1) para que consulte el motor y devuelva una lista paginada y clasificada por relevancia [cite: 1].
- [x] Sincronizar el índice: actualizar el documento correspondiente cuando se añada, elimine o modifique un libro o reseña [cite: 1].

## 3. Entregables (Infraestructura)
- [x] Crear archivos `docker-compose` para las siguientes configuraciones [cite: 1]:
  - [x] Aplicación + Base de Datos [cite: 1].
  - [x] Aplicación + Base de Datos + Caché [cite: 1].
  - [x] Aplicación + Base de Datos + Motor de Búsqueda [cite: 1].
  - [x] Aplicación + Base de Datos + Caché + Motor de Búsqueda [cite: 1].
- [x] Desplegar la configuración completa (App + DB + Caché + Search Engine) en un clúster local de Kubernetes (minikube / k3d) [cite: 1].
- [x] Añadir un Deployment y un Service en Kubernetes tanto para el caché como para el motor de búsqueda [cite: 1].

## 4. Pruebas de Correctitud
- [ ] Demostrar el correcto funcionamiento de la lógica de invalidación y sincronización leyendo un ítem para que sea cacheado/indexado [cite: 1].
- [ ] Modificar, añadir y eliminar ítems a través de la aplicación [cite: 1].
- [ ] Comprobar que una lectura posterior devuelve el valor actualizado y que la búsqueda refleja los cambios [cite: 1].
- [ ] Documentar cualquier caso en el que se obtengan datos desactualizados (stale data) y cómo se solucionó (o justificar por qué es aceptable) [cite: 1].