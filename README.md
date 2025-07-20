# ServidorSi Manager

Un script completo en bash para gestionar servidores de Minecraft de forma sencilla y eficiente en Linux.

## 🚀 Características

### 🎮 Gestión del Servidor
- **Inicio automático** con copia de seguridad previa
- **Inicio rápido** sin copia de seguridad
- **Parada controlada** con cuenta regresiva para los jugadores
- **Reinicio automático** del servidor
- **Estado detallado** del servidor en tiempo real
- **Comandos personalizados** enviados directamente al servidor

### 💾 Sistema de Copias de Seguridad
- **Backup automático** antes de cada inicio
- **Copias manuales** de mundos únicamente
- **Copias completas** incluyendo configuración
- **Restauración** desde cualquier backup disponible
- **Listado** de todas las copias disponibles
- **Limpieza automática** de backups antiguos

### 👥 Gestión de Usuarios
- **Jugadores conectados** en tiempo real
- **Gestión de Whitelist** (añadir/remover jugadores)
- **Gestión de Operadores** (permisos de administrador)
- **Sistema de Baneos** (jugadores e IPs)

### ⚙️ Configuración y Sistema
- **Información del sistema** (uso de recursos, espacio en disco)
- **Reconfiguración de rutas** del servidor
- **Editor integrado** para server.properties
- **Verificación automática** de dependencias

## 📋 Requisitos

- **Sistema operativo**: Linux (Ubuntu/Debian recomendado)
- **Java 21**: `sudo apt install openjdk-21-jre`
- **Screen**: `sudo apt install screen`
- **Servidor Purpur**: Última versión disponible en [PurpurMC.org](https://purpurmc.org/downloads)
- **Permisos**: Lectura y escritura en el directorio del servidor

## 🛠️ Instalación

1. **Clona el repositorio**:
```bash
git clone https://github.com/tu-usuario/minecraft-server-manager.git
cd minecraft-server-manager
```

2. **Da permisos de ejecución**:
```bash
chmod +x minecraft_server_manager.sh
```

3. **Descarga el servidor Purpur**:
   - Ve a [PurpurMC.org](https://purpurmc.org/downloads)
   - Descarga la última versión para Minecraft 1.21.x
   - Coloca el archivo JAR en tu directorio del servidor

4. **Ejecuta el script**:
```bash
./minecraft_server_manager.sh
```

## 📁 Estructura Requerida del Servidor

El script espera que tu servidor de Minecraft tenga la siguiente estructura:
```
/ruta/a/tu/servidor/
├── purpur-1.21.x-xxxx.jar  # Última versión de Purpur
├── server.properties
├── world/
├── world_nether/
├── world_the_end/
├── whitelist.json
├── ops.json
├── banned-players.json
├── banned-ips.json
└── backups/  # (se crea automáticamente)
```

> **⚠️ Importante**: Este script está configurado para funcionar con **Purpur Server**. Asegúrate de usar la última versión disponible en [PurpurMC.org](https://purpurmc.org/downloads) para obtener el mejor rendimiento y las últimas características.

## 🎯 Uso

Al ejecutar el script, verás un menú interactivo con las siguientes opciones:

### Servidor
1. **Iniciar servidor** (con copia de seguridad automática)
2. **Iniciar servidor** (sin copia de seguridad)
3. **Detener servidor** (con aviso a jugadores)
4. **Reiniciar servidor**
5. **Ver estado detallado**
6. **Enviar comando personalizado**

### Copias de Seguridad
7. **Crear backup manual** (solo mundos)
8. **Crear backup completo** (mundos + configuración)
9. **Restaurar backup**
10. **Listar backups disponibles**
11. **Limpiar backups antiguos**

### Gestión de Usuarios
12. **Ver jugadores conectados**
13. **Gestión de Whitelist**
14. **Gestión de Operadores**
15. **Gestión de Baneos**

### Sistema
16. **Información del sistema**
17. **Reconfigurar rutas**
18. **Modificar server.properties**
19. **Salir**

## 🔧 Configuración Inicial

En la primera ejecución, el script te pedirá:
- **Ruta del servidor**: Directorio donde tienes instalado tu servidor de Minecraft

Esta configuración se guarda en `parametros.txt` y puede ser modificada posteriormente.

## 📝 Comandos Útiles de Screen

Una vez iniciado el servidor, puedes usar estos comandos:
- **Ver consola del servidor**: `screen -r minecraft_server`
- **Salir sin cerrar el servidor**: `Ctrl+A`, luego `D`
- **Listar sesiones activas**: `screen -list`

## 🗂️ Archivos Generados

- `parametros.txt`: Configuración del script
- `backups/`: Carpeta con todas las copias de seguridad
- `minecraft_server_log_YYYY-MM-DD_HH-MM-SS.txt`: Logs del servidor

## ⚠️ Consideraciones Importantes

- El script verifica automáticamente las dependencias necesarias
- **Requiere Purpur Server**: Asegúrate de tener la última versión de Purpur descargada
- De forma opcional, se crean backups automáticos antes de cada inicio
- Los logs del servidor se guardan con timestamp
- El servidor se detiene de forma controlada con aviso a los jugadores
- Se requieren permisos adecuados en el directorio del servidor
- El script está optimizado para **Java 21** y **Purpur 1.21.x**

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:
1. Haz fork del repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-caracteristica`)
3. Commit tus cambios (`git commit -am 'Añade nueva característica'`)
4. Push a la rama (`git push origin feature/nueva-caracteristica`)
5. Abre un Pull Request

## 📄 Licencia

Este proyecto está bajo la Licencia GPL-3.0. Echa un vistazo al archivo `LICENSE` para más detalles.

## 🐛 Reportar Problemas

Si encuentras algún problema o tienes sugerencias, por favor abre un [issue](https://github.com/tu-usuario/minecraft-server-manager/issues).
