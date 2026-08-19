# Claude Room Scanner

[![Flutter](https://img.shields.io/badge/Flutter-3.27.0-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.0.0-0175C2?logo=dart)](https://dart.dev/)
[![Android and iOS CI](https://github.com/BetOarg/Claude-Room-Scanner/actions/workflows/ci.yml/badge.svg)](https://github.com/BetOarg/Claude-Room-Scanner/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Aplicación Flutter para relevar viviendas, medir ambientes y aberturas, ensamblar planos 2D multiambiente y exportar la información técnica del proyecto.

Claude Room Scanner selecciona automáticamente la mejor experiencia disponible en cada dispositivo: escaneo con ARCore o ARKit cuando existe soporte, escaneo asistido por cámara cuando no hay realidad aumentada y un aviso seguro cuando el dispositivo no dispone de capacidades suficientes.

> [!IMPORTANT]
> El proyecto se encuentra en desarrollo activo. Las mediciones realizadas con sensores móviles deben validarse físicamente antes de utilizarlas en documentación constructiva, presupuestos o decisiones profesionales.

## Estado actual

- Android y iOS verificados mediante GitHub Actions.
- ARCore configurado como capacidad opcional en Android.
- Escáner básico disponible en dispositivos con cámara y sin realidad aumentada.
- Persistencia local de proyectos mediante Isar.
- Autenticación y sincronización remota mediante Supabase.
- Plano 2D editable con ambientes, paredes, puertas, ventanas y cotas.
- Exportación a archivos JSON y documentos PDF.
- Interfaz localizada en español e inglés.
- Sistema métrico e imperial con preferencia persistente.

La versión declarada actualmente en `pubspec.yaml` es **2.6.1+3**.

## Selección automática del escáner

| Capacidades detectadas | Experiencia seleccionada |
|---|---|
| ARCore en Android o ARKit en iOS | `ARScannerScreen` |
| Cámara disponible sin ARCore/ARKit | `BasicScannerScreen` |
| Cámara o inicialización insuficiente | Aviso de compatibilidad y salida segura |

La ausencia de ARCore o ARKit no impide instalar ni abrir la aplicación. En Android, tanto la cámara AR como ARCore están declarados como opcionales en el manifiesto.

## Funcionalidades

### Relevamiento de ambientes

- Captura de contornos cerrados como ambientes independientes.
- Medición manual por distancia y dirección.
- Entrada decimal con punto o coma según el flujo de medición.
- Validación previa de cada nuevo punto.
- Prevención de puntos duplicados.
- Cierre inteligente cerca del punto inicial.
- Ajuste exacto del último tramo al punto de inicio.
- Selección de tipo y nombre personalizado del ambiente.
- Cálculo de superficie y perímetro.
- Recuperación frente a cambios del ciclo de vida de la aplicación.
- Tiempo máximo de inicialización, reintento y recuperación de la cámara básica.

### Tipos de ambiente

El modelo admite los siguientes identificadores:

| Identificador | Tipo mostrado |
|---|---|
| `living` | Living |
| `cocina` | Cocina |
| `bano` | Baño |
| `dormitorio` | Dormitorio |
| `lavadero` | Lavadero |
| `pasillo` | Pasillo |
| `comedor` | Comedor |
| `comedorDiario` | Comedor diario |
| `patio` | Patio |
| `hall` | Hall |
| `balcon` | Balcón |
| `terraza` | Terraza |
| `cochera` | Cochera |
| `playroom` | Playroom |

Los tipos históricos conservan su posición original para mantener la compatibilidad con proyectos guardados en Isar.

### Puertas y ventanas

- Medición desde el escáner AR y desde el escáner básico.
- Ajuste automático de la abertura a una pared.
- Selección explícita de la pared de cierre.
- Prevención de superposiciones entre aberturas.
- Edición del ancho y de la posición respecto de la esquina inicial.
- Edición de la altura de puertas y ventanas.
- Edición de la altura desde el piso para ventanas.
- Reubicación de las aberturas cuando cambia la geometría del ambiente.
- Sincronización de copias que comparten el mismo identificador.
- Puertas con interrupción de pared, hoja y arco de apertura de 90 grados.
- Selección del extremo de bisagra y del sentido de giro.
- Elección de apertura hacia el interior o hacia el exterior.
- Ventanas con doble línea, jambas y clasificación horizontal o vertical.

Los valores retrocompatibles utilizados cuando un proyecto antiguo no incluye medidas verticales son:

| Abertura | Altura | Altura desde el piso |
|---|---:|---:|
| Puerta | 2,10 m | 0,00 m |
| Ventana | 1,20 m | 0,90 m |

### Continuación entre habitaciones

- Selección de una puerta o ventana directamente desde el plano 2D.
- Acción para continuar el relevamiento desde la abertura seleccionada.
- Elección del lado hacia el que continúa la vivienda.
- Conservación de un único identificador para la abertura compartida.
- Transformación entre coordenadas locales y globales.
- Integración semitransparente del plano anterior en el escáner básico.
- Referencia verde independiente del contorno del nuevo ambiente.
- Inicio desde la primera esquina real y cierre sobre esa misma esquina.
- Conservación del ancho, altura, antepecho y orientación de la abertura compartida.

En una nueva sesión AR, la referencia global queda disponible para realinear la abertura con los extremos medidos en el espacio físico.

### Plano 2D y editor geométrico

- Visualización del proyecto completo y de cada ambiente.
- Nombres, tipos, superficies y perímetros.
- Longitudes de paredes.
- Cotas de puertas y ventanas.
- Distancias desde cada abertura hasta ambos extremos de su pared.
- Altura de aberturas y antepecho de ventanas.
- Movimiento y rotación de ambientes.
- Transformación rígida de grupos conectados mediante aberturas.
- Deshacer y rehacer movimientos y rotaciones.
- Alineación con la pared paralela más cercana.
- Rechazo de alineaciones que provocarían solapamientos interiores.
- Detección automática de paredes compartidas completas o parciales.
- Representación diferenciada de paredes compartidas.
- Eliminación visual del tramo duplicado cuando dos paredes coinciden.
- Organización automática sin modificar la geometría interna de cada ambiente.

### Unidades

Todas las coordenadas se almacenan internamente en metros. La interfaz permite trabajar con:

- Metros y metros cuadrados.
- Pies, pulgadas y pies cuadrados.

La preferencia global se conserva mediante `SharedPreferences` y se aplica al escáner básico, al escáner AR, al editor de medidas, al plano 2D y a las exportaciones.

### Persistencia y nube

- Proyectos y ambientes almacenados localmente con Isar.
- Actualización completa del proyecto sin acumular copias de ambientes.
- Carga, selección y eliminación de proyectos guardados.
- Autenticación de usuarios con Supabase Auth.
- Sincronización remota en segundo plano.
- Funcionamiento local preservado cuando la sincronización remota falla.

### Exportación e importación

#### JSON

- Archivo `.json` real con nombre derivado del proyecto.
- `formatVersion: 2`.
- Unidad interna declarada como `meters`.
- Ambientes, puntos, puertas, ventanas y conexiones.
- Bisagra, giro y apertura interior/exterior de puertas.
- Altura y antepecho de aberturas.
- Importación mediante selector de archivos en Android e iOS.
- Valores predeterminados para campos ausentes en proyectos anteriores.

#### PDF

- Plano geométrico vectorial del proyecto.
- Ambientes, nombres, tipos y superficies.
- Paredes, puertas y ventanas con simbología.
- Cotas de paredes y aberturas.
- Superficie y perímetro por ambiente.
- Altura y antepecho de aberturas.
- Informe técnico por habitación.
- Unidades métricas o imperiales.
- Etiquetas en español o inglés según el idioma del dispositivo.
- Vista previa, impresión, guardado y uso del menú nativo para compartir.

## Arquitectura

```text
lib/
├── config/                  # Configuración por entorno
├── l10n/                    # Recursos de localización
├── models/                  # Dominio, geometría e Isar
├── providers/               # Estado y persistencia coordinada
├── scanner/
│   ├── adapters/            # Adaptadores AR y cámara básica
│   ├── engine/              # Resolución y ejecución del modo de escaneo
│   ├── models/              # Estado y puntos del scanner
│   └── services/            # Capacidades, permisos y sensores
├── screens/                 # Pantallas de la aplicación
├── services/                # Geometría, exportación, base local y nube
├── utils/                   # Unidades, estabilidad y validación
└── main.dart                # Inicialización y composición principal
```

### Componentes principales

| Componente | Responsabilidad |
|---|---|
| `DeviceCapabilitiesService` | Detectar cámara, ARCore y ARKit |
| `ArCheckService` | Abrir el mejor escáner compatible |
| `ScannerProvider` | Estado del relevamiento activo |
| `FloorPlanProvider` | Proyecto abierto, edición y transformaciones |
| `ProjectProvider` | Persistencia local y sincronización |
| `SharedWallService` | Detectar tramos compartidos entre ambientes |
| `GeometryService` | Área, perímetro y operaciones geométricas |
| `ImportExportService` | JSON, PDF, impresión y uso compartido |

## Tecnologías

| Tecnología | Uso |
|---|---|
| Flutter y Dart | Aplicación multiplataforma |
| Provider | Gestión de estado |
| `ar_flutter_plugin_2` | Integración ARCore/ARKit |
| Camera | Escáner básico sin realidad aumentada |
| Sensors Plus | Acelerómetro, giroscopio y magnetómetro |
| Vector Math | Operaciones espaciales y vectoriales |
| Isar | Persistencia local |
| Supabase | Autenticación y sincronización remota |
| Shared Preferences | Preferencia global de unidades |
| PDF y Printing | Documento técnico, vista previa e impresión |
| Share Plus | Compartir archivos reales |
| File Picker | Importar proyectos JSON |

## Requisitos de desarrollo

### Herramientas

- Flutter 3.27.0, utilizado por los workflows actuales.
- Dart `>=3.0.0 <4.0.0`.
- Java 17.
- CocoaPods para compilar iOS.
- Un proyecto Supabase para autenticación y sincronización.

### Android

- `minSdkVersion 28`.
- `compileSdkVersion 34`.
- `targetSdkVersion 34`.
- ARCore 1.54.0 como dependencia de detección opcional.
- Cámara recomendada para el escáner básico.

### iOS

- iOS 13.0 o superior.
- Cámara recomendada para el escáner básico.
- Dispositivo compatible con ARKit para el modo AR.

Para validar ARCore, ARKit, cámara y sensores se recomienda utilizar dispositivos físicos.

## Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/BetOarg/Claude-Room-Scanner.git
cd Claude-Room-Scanner
```

### 2. Instalar dependencias

```bash
flutter pub get
```

### 3. Generar localizaciones

```bash
flutter gen-l10n
```

### 4. Generar modelos de Isar

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 5. Configurar Supabase

La aplicación lee la configuración mediante `--dart-define`. No guardes credenciales privadas en el repositorio.

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu-anon-key
```

Sin valores reales, la aplicación puede inicializarse con los placeholders incluidos, pero las operaciones de autenticación y sincronización no funcionarán.

## Verificación

### Análisis estático

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

### Pruebas

```bash
flutter test
```

La suite cubre, entre otros casos:

- Conversión de unidades y preferencias.
- Persistencia de opciones de puertas y ventanas.
- Compatibilidad con aberturas antiguas.
- Edición geométrica y prevención de superposiciones.
- Transformación, alineación, deshacer y rehacer.
- Rechazo de alineaciones que invaden otro ambiente.
- Detección de paredes compartidas completas y parciales.
- Estructura y contenido de exportaciones.

### Prueba de integración

```bash
flutter test integration_test/app_test.dart
```

## Compilación

### Android

```bash
flutter build apk --debug \
  --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu-anon-key
```

### iOS sin firma

```bash
flutter build ios --no-codesign --debug \
  --dart-define=SUPABASE_URL=https://tu-proyecto.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=tu-anon-key
```

## Integración continua

El workflow `.github/workflows/ci.yml` se ejecuta en cada `push` y `pull_request` sobre `main` o `master`.

### Android

1. Configura Java 17 y Flutter 3.27.0.
2. Instala dependencias.
3. Genera localizaciones e Isar.
4. Ejecuta el análisis estático.
5. Ejecuta las pruebas.
6. Compila un APK de depuración.

### iOS

1. Configura Flutter 3.27.0 en macOS.
2. Instala dependencias.
3. Genera localizaciones e Isar.
4. Verifica CocoaPods y la configuración iOS.
5. Ejecuta una compilación de configuración sin firma.

El workflow manual `.github/workflows/build_apk.yml` genera un APK de prueba versionado, verifica su firma y lo publica como artefacto temporal de GitHub Actions.

## Permisos

La aplicación solicita solamente los permisos necesarios para las capacidades utilizadas:

- Cámara para escaneo AR y escaneo básico.
- Ubicación para asociar coordenadas geográficas al proyecto cuando corresponda.

La disponibilidad de una capacidad se comprueba en tiempo de ejecución y los fallos de inicialización se manejan mediante recuperación o salida segura.

## Limitaciones conocidas y trabajo pendiente

- Validación física completa en diferentes dispositivos ARCore y ARKit.
- Validación visual de cotas en ambientes muy pequeños.
- Pruebas físicas del flujo completo después de editar una abertura compartida.
- Realineación física precisa de una continuación en cada nueva sesión AR.
- Corrección automática adicional de pequeños errores geométricos entre ambientes.
- Herramientas avanzadas para unir y ajustar manualmente distribuciones complejas.

## Seguridad

- No publiques claves privadas, contraseñas ni archivos de firma de producción.
- La clave anónima de Supabase debe inyectarse por entorno para permitir su rotación.
- El keystore incluido en el workflow de APK es exclusivamente para compilaciones de prueba.
- Para distribuir una versión de producción configura una firma propia y protege sus secretos mediante GitHub Actions Secrets.

## Contribuciones

Antes de proponer un cambio:

1. Conservá la compatibilidad con proyectos guardados anteriormente.
2. No cambies el orden de enumeraciones persistidas por Isar.
3. Agregá pruebas para conversiones, geometría o persistencia afectadas.
4. Ejecutá generación de localizaciones y modelos.
5. Confirmá Android e iOS en verde.

## Licencia

Este proyecto se distribuye bajo la [licencia MIT](LICENSE).

Copyright © 2024 BetOarg.
