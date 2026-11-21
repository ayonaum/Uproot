# Uproot

**Encuentra todo lo que una aplicación, un juego o un plugin dejó en tu Mac y elimínalo de una vez.**

[English](README.md) · [Русский](README.ru.md) · [Español](README.es.md) · [Українська](README.uk.md)

![Plataforma](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Swift](https://img.shields.io/badge/swift-6.0-orange)
![Licencia](https://img.shields.io/badge/license-Unlicense-green)

Uproot es una aplicación nativa para macOS que hace un trabajo que Finder no hace. Cuando arrastras una aplicación a la Papelera, sus preferencias, cachés, contenedores, agentes de inicio, plugins de audio, recibos del instalador y carpetas del desarrollador se quedan en el disco. Uproot lo encuentra todo, agrupa lo que encuentra, explica por qué está ahí cada elemento y elimina lo que marques.

Sustituye el ciclo manual de `mdfind` → `find` → `grep -v` → `sudo rm -rf` → `pkgutil --forget` → comprobar otra vez.

> La interfaz está actualmente en ruso. La búsqueda no depende del idioma: compara nombres, identificadores de paquete y rutas tal como están en el disco.

## Por qué existe

Desinstalar una aplicación de Mac rara vez es un solo arrastre. Un plugin puede dejar un VST3 y un Audio Unit, una carpeta de contenido compartida, presets en tu carpeta personal, una caché, un archivo de preferencias, varios recibos del instalador, un agente de inicio y una imagen de instalación montada. Parte lleva el nombre del producto, parte solo el del fabricante y parte solo un identificador como `com.vendor.product`.

Hacerlo a mano supone varias búsquedas, leer rutas, decidir qué carpeta `terrain` pertenece al plugin y cuál a un juego, y acordarse de olvidar los recibos. Uproot hace ese recorrido por ti y deja la decisión en tus manos.

## Funciones

- **Dos modos de búsqueda.** Busca un programa y todo lo que dejó, o busca cualquier archivo o carpeta por nombre.
- **Más que nombres de archivo.** Uproot sigue identificadores de paquete, recibos del instalador, agentes y demonios de inicio, enlaces simbólicos de la línea de comandos, procesos en ejecución, imágenes de instalación montadas, programas de Windows en botellas de CrossOver/Wine y la base de datos de plugins de FL Studio.
- **Búsqueda por fabricante.** Añade el desarrollador o editor y Uproot también encuentra las carpetas con el nombre de la empresa y lo que hay dentro.
- **Preselección prudente.** Solo se marcan los elementos de los que Uproot está seguro. Todo lo dudoso queda sin marcar y con una explicación.
- **Una sola petición de contraseña.** Todo lo que necesita permisos de administrador se reúne en un único script y se ejecuta una vez.
- **Papelera por defecto.** Los elementos van a la Papelera, o se pueden borrar definitivamente si lo eliges.
- **Verificación después de eliminar.** Uproot vuelve a buscar e indica qué queda.
- **Diario de eliminaciones.** Cada operación queda registrada, y lo que está en la Papelera se puede devolver desde el diario, salvo lo movido con permisos de administrador, que hay que restaurar a mano desde la Papelera.
- **Sin acceso a la red.** La aplicación no se conecta a ningún sitio; todo ocurre en tu Mac.

## Requisitos

- macOS 14 Sonoma o posterior, en Apple Silicon o Intel.
- **Acceso total al disco** para Uproot. Sin él la búsqueda funciona, pero algunas carpetas quedarán sin leer, macOS pedirá acceso a Documentos, Descargas y otras carpetas una por una, y la eliminación de archivos de otras aplicaciones en `/Applications` puede ser rechazada.
- Para compilar desde el código fuente: Xcode 26 o posterior y Swift 6.

## Instalación

1. Descarga el último `.dmg` desde la página de [Releases](../../releases).
2. Abre la imagen y arrastra **Uproot** a la carpeta **Aplicaciones**.
3. La aplicación no está notarizada por Apple, así que el primer inicio hay que aprobarlo a mano:
   - **macOS 15 o posterior:** abre Uproot desde Aplicaciones, pulsa **Hecho** en el aviso y ve a **Ajustes del Sistema → Privacidad y seguridad**; baja hasta la línea de Uproot y pulsa **Abrir de todos modos**.
   - **macOS 14:** haz clic derecho en Uproot dentro de Aplicaciones → **Abrir** → **Abrir**.
4. Concede **Acceso total al disco**: **Ajustes del Sistema → Privacidad y seguridad → Acceso total al disco**, activa Uproot y reinícialo. La ventana de la aplicación tiene botones para ambos pasos.

Solo hay que hacerlo una vez. Si compilas la aplicación tú mismo, consulta la sección de compilación más abajo.

## Inicio rápido

1. Escribe el nombre de una aplicación, un juego o un plugin. Para varios nombres, sepáralos con comas.
2. Si quieres, añade la empresa que lo desarrolla.
3. Pulsa **Intro**.
4. Revisa la lista. Los elementos marcados son aquellos de los que Uproot está seguro; desmarca lo que quieras conservar.
5. Pulsa **Eliminar…** («Удалить…»), elige **A la Papelera** («В Корзину») o **Eliminar definitivamente** («Удалить навсегда») y confirma.
6. Uproot elimina la selección, vuelve a buscar y muestra lo que queda.

## Dos modos de búsqueda

### Un programa y sus rastros

El modo principal. Introduce el nombre del producto y, si quieres, el fabricante. Además de los nombres en el disco, Uproot comprueba:

- los **identificadores de paquete** de los programas encontrados (`com.vendor.app`): así encuentra preferencias, cachés y contenedores cuyos nombres no contienen el del producto;
- los **recibos del instalador** (`pkgutil`) y los archivos que instalaron esos paquetes;
- los **agentes y demonios de inicio** que arrancan lo encontrado;
- los **enlaces simbólicos** en `/usr/local/bin`, `/opt/homebrew/bin`, `~/bin` y `~/.local/bin`;
- los **procesos en ejecución** iniciados desde los archivos encontrados;
- las **imágenes de instalación montadas** que quedaron tras la instalación;
- los **programas de Windows** dentro de botellas de CrossOver y Wine;
- la **base de datos de plugins de FL Studio**.

### Archivos y carpetas

Una búsqueda normal por nombre o parte del nombre. Se muestran todas las coincidencias, incluidos tus documentos personales, y no se marca nada de antemano.

### Opciones

En **Opciones** («Параметры») puedes:

- excluir rutas que contengan ciertas palabras;
- buscar dentro de los paquetes de otras aplicaciones y plugins (`.app`, `.vst3` y similares): tarda más, y casi todo lo encontrado será parte de otros programas;
- revisar discos externos, no solo el disco de arranque.

## Cómo leer los resultados

| En la lista | Significado |
| --- | --- |
| Casilla marcada | Uproot está seguro: el nombre coincide y el elemento está donde se instala el software |
| Etiqueta «проверьте» (revisar), sin marcar | Probablemente relacionado, pero decides tú: descargas, carpeta de otro fabricante, nombre parecido |
| Sección «Сомнительные совпадения» (coincidencias dudosas) | El nombre se parece, pero lo más probable es que sea parte de otro programa o uno de tus documentos |
| Etiqueta roja «внутри ещё N объектов» (hay N objetos más dentro) | La carpeta contiene más de lo encontrado; si la marcas, se elimina todo su contenido |
| Candado | Para eliminarlo hará falta la contraseña de administrador |

La lista se puede agrupar por tipo o por carpeta, filtrar por texto y plegar por secciones.

- **Espacio** marca o desmarca las filas seleccionadas.
- **Doble clic** muestra el elemento en Finder.
- El **menú contextual** ofrece Vista rápida, copiar la ruta y **Quitar de los resultados**. Quitar un elemento no lo elimina, y tampoco se elimina con su carpeta padre: la carpeta se desmarca y el resto de su contenido sigue marcado.

## Lo que Uproot nunca toca

Hay cosas que nunca se ofrecen, se escriba como se escriba la búsqueda:

- las carpetas estándar sobre las que se construye macOS: `~/Library/Preferences`, `/Library/Audio/Plug-Ins/VST3`, `~/Documents` y similares. Una búsqueda de «Audio» mira dentro de esas carpetas, pero no propone la carpeta en sí;
- las carpetas donde las aplicaciones integradas guardan tus datos: `~/Library/Mail`, `~/Library/Messages`, `~/Library/Safari`, `~/Library/Calendars`, `~/Library/Accounts` y otras;
- los elementos que macOS marca como no eliminables y las rutas que la aplicación considera protegidas. Aunque uno llegue a la lista mediante una búsqueda de archivos, la eliminación se rechaza.

Los objetos cuyos nombres pertenecen a macOS o a Apple (`com.apple.Notes`, por ejemplo) se muestran con la etiqueta «проверьте» y sin casilla, salvo que lo que estés eliminando sea el propio programa de Apple, como Xcode.

## Cómo funciona

```mermaid
flowchart LR
    A[Recorrer el disco] --> B[Comparar nombres]
    B --> C[Leer identificadores]
    C --> D[Revisar recibos]
    D --> E[Servicios, enlaces, volúmenes, procesos]
    E --> F[Puntuar y agrupar]
    F --> G[Eliminar]
    G --> H[Buscar de nuevo]
```

1. **Recorrido.** Un recorredor paralelo lee la carpeta personal, `/Applications`, `/Library`, `/Users/Shared`, `/usr/local`, `/opt`, partes de `/private/etc` y `/private/var`, y las carpetas temporales y de caché del usuario. Se salta `.git`, `node_modules`, la Papelera, los índices de Spotlight y las carpetas de datos de las aplicaciones integradas. No entra en otros volúmenes salvo que se lo pidas, y no descarga marcadores de iCloud solo para leer sus nombres.
2. **Comparación de nombres.** Los nombres se reducen a letras minúsculas y dígitos: se quitan separadores y acentos y se guardan las fronteras entre palabras. `Safe_Exam Browser-3.7.dmg` se convierte en `safeexambrowser37dmg`, así que un solo término encuentra cualquier forma de escribir el nombre. Los términos cortos (hasta cuatro caracteres) solo coinciden con palabras completas, para que «SEB» no encuentre «Sebastian».
3. **Identificadores.** Uproot lee el `Info.plist` de los programas encontrados y busca sus identificadores en `Preferences`, `Caches`, `Containers`, `Application Support`, `Saved Application State`, `LaunchAgents` y carpetas similares.
4. **Recibos.** Los recibos de `pkgutil` que coinciden con el producto se listan, y se añaden los archivos instalados por esos paquetes aunque sus propios nombres no digan nada.
5. **Elementos relacionados.** Servicios de inicio, enlaces de la línea de comandos, imágenes montadas, procesos, programas de CrossOver/Wine y entradas de la base de datos de FL Studio.
6. **Puntuación y agrupación.** El veredicto depende de dos cosas: cuánto coincide el nombre y dónde está el elemento. Una coincidencia fuerte en un lugar de instalación se considera fiable. La misma coincidencia en lo profundo de los archivos de otro programa se muestra, pero sin marcar. Nunca se preselecciona nada de tus documentos personales.
7. **Eliminación.** Todo lo que puede hacer el usuario actual se hace directamente. El resto se reúne en un único script de shell y se ejecuta con permisos de administrador, así que la contraseña se pide una sola vez. Primero se detienen los procesos, luego se expulsan los volúmenes, los archivos van a la Papelera o se borran y los recibos se olvidan. Los servicios se descargan con `launchctl bootout`; tras eliminar un Audio Unit se reinicia `AudioComponentRegistrar`.
8. **Verificación.** Uproot vuelve a buscar e indica qué queda. Si algo reaparece, el programa o plugin sigue en ejecución, a menudo cargado en un DAW. Ciérralo y repite.

Las reglas de coincidencia están en [`RelevanceScorer.swift`](Packages/UprootCore/Sources/UprootCore/Classify/RelevanceScorer.swift), y la disposición estándar de carpetas de macOS en [`Placement.swift`](Packages/UprootCore/Sources/UprootCore/Classify/Placement.swift).

## Pruébalo sin riesgo

`Tools/make-fixture.sh` crea un pequeño «Mac falso» en una carpeta, con los escenarios para los que se escribió esta aplicación. En este modo Uproot nunca sale de la carpeta ni toca registros reales del sistema.

```sh
Tools/make-fixture.sh /tmp/uproot-playground
open /Applications/Uproot.app --args --fixture /tmp/uproot-playground \
    --name Terrain --name "Terrain FX" --vendor "Waves Crate" --scan
```

La carpeta debe indicarse con la ruta completa y debe contener `Users/tester`. Con un valor vacío, `/` o una errata en la ruta, la aplicación no arranca en lugar de trabajar en silencio sobre el disco real.

## Línea de comandos

`uproot-scan` es un front-end de solo lectura del escáner. Nunca elimina nada.

```sh
cd Packages/UprootCore
swift run -c release uproot-scan Terrain "Terrain FX" --vendor "Waves Crate"
swift run -c release uproot-scan --files invoice
```

```text
usage: uproot-scan <name>... [--vendor <company>]... [--exclude <text>]...
                   [--files] [--inside-bundles] [--external] [--all]
```

La aplicación también acepta argumentos de inicio:

| Argumento | Efecto |
| --- | --- |
| `--name <text>` | Nombre de programa o archivo; se puede repetir |
| `--vendor <text>` | Nombre de empresa; se puede repetir |
| `--files` | Buscar archivos por nombre en lugar de un programa |
| `--scan` | Empezar a buscar de inmediato |
| `--fixture <path>` | Tratar `<path>` como raíz del disco y `<path>/Users/tester` como carpeta personal |
| `--show <what>` | Abrir `confirm`, `history`, `options` o `doubtful` al estar listo |
| `--filter <text>` | Abrir la lista ya filtrada |
| `--window <WxH>` | Abrir la ventana con este tamaño, en puntos |
| `--remove` | Solo con `--fixture`: eliminar lo preseleccionado sin preguntar |

## Compilar desde el código fuente

Necesitas Xcode 26 o posterior.

```sh
Tools/build.sh             # compila dist/Uproot.app y firma con un certificado si existe
Tools/build.sh --adhoc     # solo firma local ad-hoc
cd Packages/UprootCore && swift test
```

Para entregar la aplicación a otro Mac, crea una imagen de disco:

```sh
Tools/make-dmg.sh          # dist/Uproot-<versión>.dmg: la app, un acceso a Aplicaciones y notas de instalación
```

La aplicación se compila con **Hardened Runtime**, y `Tools/build.sh` comprueba que la compilación final lo tenga. Sin él, cualquier programa podría cargar su propio código en Uproot y aprovechar su acceso total al disco.

macOS vincula el Acceso total al disco con la firma. Con un certificado, el permiso sobrevive a las recompilaciones; con una firma ad-hoc hay que activarlo de nuevo después de cada compilación. La primera vez que firmes con un certificado, el llavero pedirá la contraseña: elige **Permitir siempre**.

## Estructura del proyecto

```text
Packages/UprootCore/        lógica sin interfaz, cubierta por pruebas
  Matching/                 reducción de nombres y comparación con la consulta
  Scan/                     recorrido paralelo del disco, recogida y puntuación
  Classify/                 dónde está cada cosa en macOS y cuánto fiarse de una coincidencia
  Sources/                  paquetes del instalador, launchd, procesos, volúmenes, Info.plist
  Removal/                  eliminación y script para permisos de administrador
  Model/, History/          modelo de resultados con casillas, diario
Uproot/                     la aplicación SwiftUI
  App/                      estado de la ventana, inicio, permisos de administrador
  Views/                    pantallas
Tools/                      compilación, imagen de disco, icono, disco de prueba
```

## Limitaciones conocidas

- La ejecución del script de administrador como root tras la petición de contraseña no se ha verificado en un sistema real. La petición funciona y el script está cubierto por pruebas sin elevación.
- Los elementos enviados a la Papelera con permisos de administrador solo se pueden devolver a mano desde la Papelera.
- Los elementos de inicio añadidos en **Ajustes del Sistema → General → Ítems de inicio** no se muestran: macOS no los expone sin root.
- Los nombres cortos (hasta cuatro letras) solo coinciden con palabras completas, para que «SEB» no encuentre «Sebastian». Los dígitos y guiones dentro de ese nombre se consideran parte de él: «Pro-Q» encuentra «FabFilter Pro-Q 3» y «C1» encuentra «C1 comp».
- Una palabra genérica en lugar de un nombre («Helper», «Agent», «Preferences») coincidirá con archivos de muchos programas y algunos se marcarán. Lee la lista antes de eliminar y añade el fabricante a la búsqueda.
- La petición de contraseña desde una compilación con Hardened Runtime no se ha verificado en un sistema real. El mecanismo (`do shell script` en un proceso protegido) está probado sin elevación.
- La interfaz está actualmente solo en ruso.

## Preguntas frecuentes

**La aplicación no se abre.** Es lo esperado: la compilación no está notarizada. Apruébala una vez en **Ajustes del Sistema → Privacidad y seguridad → Abrir de todos modos**.

**macOS no deja de pedir acceso a carpetas.** No está activado el Acceso total al disco, o la aplicación no se ha reiniciado desde que lo activaste.

**Algo volvió a aparecer después de eliminarlo.** El programa o plugin sigue en ejecución, a menudo cargado en un DAW o en el navegador. Ciérralo y repite la eliminación.

**¿Hay que pagar algo?** No. La aplicación es gratuita, de código abierto y liberada al dominio público.

**¿Uproot envía datos a algún sitio?** No. No hace ninguna petición de red.

## Licencia

Liberado al dominio público bajo la [Unlicense](LICENSE). Puedes usar, copiar, modificar y distribuir este software para cualquier propósito, con o sin atribución.
