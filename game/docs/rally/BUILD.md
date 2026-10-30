# Compilar Rally en Windows

Desde la raíz del repositorio:

```powershell
.\scripts\run_build.ps1
```

El script localiza Godot mediante `-GodotPath`, `GODOT_BIN`, la instalación
local o PATH. Requiere Godot 4.7 estable y su plantilla Windows debug x86_64.
No necesita Rust, C# ni compilador C++; SQLite utiliza la DLL del repositorio.

La compilación importa los recursos, comprueba todos los GDScript, valida los
perfiles y hashes mediante el lanzador y exporta el proyecto Rally aislado.
No ejecuta tests ni abre una sesión de conducción.

Salida: `dist/rally_windows/FordEscortRS2000Rally.exe`, su DLL de SQLite y
`rally_export_manifest.json`. Para trasladar el juego, copiar toda la carpeta
`dist/rally_windows`, no solo el EXE. Los JSON y recursos se empaquetan en el
ejecutable. Los bucles de audio incluyen copias RIFF sin modificar con sufijo
`.wav.pcm`, necesarias para el lector PCM; los eventos conservan sus recursos
de audio importados.

El staging y la distribución anterior se regeneran. Los logs de compilación
se guardan en `build/logs`; el manifiesto de exportación registra los hashes
de los archivos preparados. Los resultados generados están ignorados por Git.

Para preparar únicamente el proyecto que usa el lanzador, sin exportar EXE:

```powershell
.\scripts\run_build.ps1 -ImportOnly
.\scripts\run_rally.ps1
```

Para seleccionar otra instalación compatible:

```powershell
.\scripts\run_build.ps1 -GodotPath 'C:\ruta\Godot_console.exe'
```

Este build genera Windows debug, que coincide con las plantillas instaladas.
El modo debug no ejecuta el editor; la distribución se inicia directamente.
