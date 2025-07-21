#!/bin/bash

# Nombre del archivo de parámetros
PARAM_FILE="parametros.txt"

# Nombre base para el archivo de log del servidor
LOG_BASE_NAME="minecraft_server_log"

# Lista de carpetas de mundos a respaldar
WORLD_FOLDERS=("world" "world_nether" "world_the_end")

# Carpeta de backups relativa al directorio del servidor
BACKUP_FOLDER="backups"

# Archivos de configuración importantes
CONFIG_FILES=("server.properties" "whitelist.json" "ops.json" "banned-players.json" "banned-ips.json")

# --- Detectar sistema operativo ---
detect_os() {
    unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)     
            OS_TYPE=Linux
            if ! command -v apt-get &>/dev/null; then
                echo "[!] Este script está optimizado para sistemas basados en Debian/Ubuntu."
                echo "    Algunas funciones podrían no funcionar correctamente."
            fi
            ;;
        Darwin*)    
            OS_TYPE=Mac
            ;;
        *)          
            OS_TYPE="UNKNOWN:${unameOut}"
            ;;
    esac
    echo "[*] Sistema operativo detectado: $OS_TYPE"
}

# Función nueva para verificar compatibilidad
check_system_compatibility() {
    case "$OS_TYPE" in
        Mac)
            # Verificar Homebrew en Mac
            if ! command -v brew &>/dev/null; then
                echo "[!] Homebrew no está instalado. Es necesario para gestionar dependencias."
                echo "    Instálalo desde: https://brew.sh"
                exit 1
            fi
            # Verificar comandos específicos de Mac
            for cmd in screen java sed awk grep; do
                if ! command -v "$cmd" &>/dev/null; then
                    echo "[!] Comando '$cmd' no encontrado. Instalando..."
                    brew install "$cmd" || exit 1
                fi
            done
            # Ajustar permisos en Mac
            if [ ! -w "$(dirname "$PARAM_FILE")" ]; then
                echo "[!] Error: No tienes permisos de escritura en el directorio actual."
                echo "    Ejecuta: sudo chown -R $(whoami) ."
                exit 1
            fi
            ;;
        Linux)
            # Verificar comandos específicos de Linux
            for cmd in screen java sed awk grep; do
                if ! command -v "$cmd" &>/dev/null; then
                    echo "[!] Comando '$cmd' no encontrado. Instalando..."
                    sudo apt-get update && sudo apt-get install -y "$cmd" || exit 1
                fi
            done
            ;;
        *)
            echo "[!] Sistema operativo no soportado: $OS_TYPE"
            exit 1
            ;;
    esac
    echo "[+] Sistema verificado y compatible."
}

# --- Verificar dependencias ---
check_dependencies() {
    echo "[*] Verificando dependencias..."

    # Verificar si java está instalado
    if ! command -v java &> /dev/null; then
        if [ "$OS_TYPE" = "Mac" ]; then
            echo "[!] Error: 'java' no está instalado. Instálalo con: brew install openjdk@21"
        else
            echo "[!] Error: 'java' no está instalado. Instálalo con: sudo apt install default-jre"
        fi
        exit 1
    fi

    # Verificar versión de Java según el sistema operativo
    if [ "$OS_TYPE" = "Mac" ]; then
        # En Mac, intentamos diferentes métodos para obtener la versión
        JAVA_VERSION=$(/usr/libexec/java_home -V 2>&1 | grep -o "21\.[0-9]*\.[0-9]*" || java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        if [[ ! "$JAVA_VERSION" =~ ^21 ]]; then
            echo "[!] Error: Se requiere Java 21. Versión detectada: $JAVA_VERSION"
            echo "Instala Java 21 con: brew install openjdk@21"
            echo "Luego ejecuta: sudo ln -sfn $(brew --prefix)/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk"
            exit 1
        fi
    else
        # En Linux mantener la detección original
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        if [[ "$JAVA_VERSION" != 21* ]]; then
            echo "[!] Error: Se requiere Java 21. Versión detectada: $JAVA_VERSION"
            echo "Instala Java 21 con: sudo apt install openjdk-21-jre"
            exit 1
        fi
    fi

    echo "[+] Todas las dependencias están instaladas."
}

# --- Verificar permisos de la ruta del servidor ---
check_server_path_permissions() {
    if [ ! -r "$MINECRAFT_SERVER_PATH" ] || [ ! -w "$MINECRAFT_SERVER_PATH" ]; then
        echo "[!] Error: No tienes permisos de lectura/escritura en '$MINECRAFT_SERVER_PATH'."
        echo "Asegúrate de que tu usuario tenga los permisos adecuados ejecutando:"
        echo "sudo chown -R $(whoami):$(whoami) '$MINECRAFT_SERVER_PATH'"
        exit 1
    fi
}

# --- Función para obtener y guardar parámetros ---
get_and_save_params() {
    while true; do
        read -p "Introduce la ruta completa donde está instalado tu servidor de Minecraft (ej: /home/tu_usuario/minecraft_server): " MINECRAFT_SERVER_PATH
        
        if [ -d "$MINECRAFT_SERVER_PATH" ]; then
            echo "MINECRAFT_SERVER_PATH=$MINECRAFT_SERVER_PATH" > "$PARAM_FILE"
            echo "Parámetros guardados en $PARAM_FILE."
            break
        else
            echo "[!] La ruta ingresada no existe. Por favor, inténtalo de nuevo."
        fi
    done
}

# --- Función para leer parámetros ---
load_params() {
    if [ -f "$PARAM_FILE" ]; then
        source "$PARAM_FILE"
        BACKUP_PATH="$MINECRAFT_SERVER_PATH/$BACKUP_FOLDER"
        echo "Parámetros cargados desde $PARAM_FILE."
    else
        echo "Archivo de parámetros no encontrado. Iniciando configuración inicial..."
        get_and_save_params
        # Cargar los parámetros recién guardados
        source "$PARAM_FILE"
        BACKUP_PATH="$MINECRAFT_SERVER_PATH/$BACKUP_FOLDER"
    fi
}

# --- Función para crear directorios con manejo de errores ---
create_directory_if_not_exists() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        mkdir -p "$dir_path" 2>/dev/null
        if [ $? -ne 0 ]; then
            echo "[!] Error: No se pudo crear el directorio '$dir_path'. Verifica los permisos."
            exit 1
        fi
    fi
}

# --- Función para crear backup automático ---
auto_backup_before_start() {
    echo "[*] Creando backup automático antes de iniciar el servidor..."
    
    # Verificar que existe al menos una carpeta de mundo
    local has_worlds=false
    for folder in "${WORLD_FOLDERS[@]}"; do
        if [ -d "$MINECRAFT_SERVER_PATH/$folder" ]; then
            has_worlds=true
            break
        fi
    done
    
    if [ "$has_worlds" = false ]; then
        echo "[i] No se encontraron mundos existentes. Saltando backup automático."
        return 0
    fi
    
    create_directory_if_not_exists "$BACKUP_PATH"

    BACKUP_NAME="auto_backup_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz"
    
    # Crear lista de carpetas existentes
    existing_folders=()
    for folder in "${WORLD_FOLDERS[@]}"; do
        if [ -d "$MINECRAFT_SERVER_PATH/$folder" ]; then
            existing_folders+=("$folder")
        fi
    done
    
    if [ ${#existing_folders[@]} -gt 0 ]; then
        tar -czf "$BACKUP_PATH/$BACKUP_NAME" -C "$MINECRAFT_SERVER_PATH" "${existing_folders[@]}" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            backup_size=$(du -h "$BACKUP_PATH/$BACKUP_NAME" | cut -f1)
            echo "[+] Backup automático creado: $BACKUP_NAME ($backup_size)"
        else
            echo "[!] Error creando backup automático, pero continuando con el inicio del servidor."
        fi
    fi
}

# --- Función para iniciar el servidor de Minecraft ---
start_minecraft_server() {
    load_params

    # Verifica si la ruta del servidor existe
    if [ ! -d "$MINECRAFT_SERVER_PATH" ]; then
        echo "[!] Error: La ruta del servidor de Minecraft '$MINECRAFT_SERVER_PATH' no existe."
        echo "Por favor, edita '$PARAM_FILE' o borra el archivo para reconfigurar."
        return 1
    fi

    # Verificar permisos de la ruta del servidor
    check_server_path_permissions

    # Verificar si el servidor ya está activo
    if screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor ya está activo."
        echo "Para conectar: screen -r minecraft_server"
        return 1
    fi

    # Crear backup automático antes de iniciar
    auto_backup_before_start

    # Define el nombre del archivo de log con fecha y hora
    CURRENT_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
    LOG_FILE="$MINECRAFT_SERVER_PATH/${LOG_BASE_NAME}_${CURRENT_DATETIME}.txt"

    echo ""
    echo "[*] Iniciando servidor de Minecraft..."
    echo "[*] Log: $LOG_FILE"

    # Inicia el servidor en una sesión de screen y redirige la salida a un archivo de log
    screen -dmS minecraft_server bash -c "cd $MINECRAFT_SERVER_PATH && java -Xms512M -Xmx1400M -jar folia-1.21.6-6.jar nogui 2>&1 | tee $LOG_FILE"

    sleep 2
    if screen -list | grep -q "minecraft_server"; then
        echo "[+] Servidor de Minecraft iniciado correctamente."
        echo "-----------------------------------------------"
        echo "[*] Para ver la consola: screen -r minecraft_server"
        echo "[*] Para salir sin cerrar: CTRL+A, luego D"
        echo "-----------------------------------------------"
    else
        echo "[!] Error: No se pudo iniciar el servidor."
        return 1
    fi
}

# --- Función para iniciar el servidor sin copia de seguridad ---
start_minecraft_server_no_backup() {
    load_params

    # Verifica si la ruta del servidor existe
    if [ ! -d "$MINECRAFT_SERVER_PATH" ]; then
        echo "[!] Error: La ruta del servidor de Minecraft '$MINECRAFT_SERVER_PATH' no existe."
        echo "Por favor, edita '$PARAM_FILE' o borra el archivo para reconfigurar."
        return 1
    fi

    # Verificar permisos de la ruta del servidor
    check_server_path_permissions

    # Verificar si el servidor ya está activo
    if screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor ya está activo."
        echo "Para conectar: screen -r minecraft_server"
        return 1
    fi

    # Define el nombre del archivo de log con fecha y hora
    CURRENT_DATETIME=$(date +"%Y-%m-%d_%H-%M-%S")
    LOG_FILE="$MINECRAFT_SERVER_PATH/${LOG_BASE_NAME}_${CURRENT_DATETIME}.txt"

    echo ""
    echo "[*] Iniciando servidor de Minecraft sin copia de seguridad..."
    echo "[*] Log: $LOG_FILE"

    # Inicia el servidor en una sesión de screen y redirige la salida a un archivo de log
    screen -dmS minecraft_server bash -c "cd $MINECRAFT_SERVER_PATH && java -Xms512M -Xmx1400M -jar folia-1.21.6-6.jar nogui 2>&1 | tee $LOG_FILE"

    sleep 2
    if screen -list | grep -q "minecraft_server"; then
        echo "[+] Servidor de Minecraft iniciado correctamente."
        echo "-----------------------------------------------"
        echo "[*] Para ver la consola: screen -r minecraft_server"
        echo "[*] Para salir sin cerrar: CTRL+A, luego D"
        echo "-----------------------------------------------"
    else
        echo "[!] Error: No se pudo iniciar el servidor."
        return 1
    fi
}

# --- Función para detener el servidor ---
stop_minecraft_server() {
    if ! screen -list | grep -q "minecraft_server"; then
        echo "[i] El servidor no está activo."
        return 0
    fi

    echo "[*] Deteniendo servidor de Minecraft..."
    screen -S minecraft_server -X stuff "say Servidor se apagará en 10 segundos...^M"
    sleep 3
    screen -S minecraft_server -X stuff "say 5...^M"
    sleep 1
    screen -S minecraft_server -X stuff "say 4...^M"
    sleep 1
    screen -S minecraft_server -X stuff "say 3...^M"
    sleep 1
    screen -S minecraft_server -X stuff "say 2...^M"
    sleep 1
    screen -S minecraft_server -X stuff "say 1...^M"
    sleep 1
    screen -S minecraft_server -X stuff "stop^M"

    echo "[*] Esperando a que el servidor se detenga..."
    timeout=30
    while screen -list | grep -q "minecraft_server" && [ $timeout -gt 0 ]; do
        sleep 1
        timeout=$((timeout-1))
        printf "."
    done
    echo ""

    if screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor no se detuvo completamente. Forzando cierre..."
        screen -S minecraft_server -X quit
    fi
    
    echo "[+] Servidor detenido."
}

# --- Función para reiniciar el servidor ---
restart_minecraft_server() {
    echo "[*] Reiniciando servidor de Minecraft..."
    stop_minecraft_server
    sleep 5
    start_minecraft_server
}

# --- Función para mostrar el estado detallado del servidor ---
server_status() {
    load_params
    echo "-----------------------------------------------"
    echo "[*] Estado detallado del servidor:"
    if screen -list | grep -q "minecraft_server"; then
        echo "[+] El servidor está ACTIVO."
        # Mostrar uso de memoria y jugadores conectados si es posible
        if [ -f "$MINECRAFT_SERVER_PATH/server.properties" ]; then
            echo "[*] Propiedades del servidor:"
            grep -E '^(motd|max-players|difficulty|level-name)=' "$MINECRAFT_SERVER_PATH/server.properties"
        fi
        # Intentar mostrar jugadores conectados
        list_online_players
    else
        echo "[-] El servidor está INACTIVO."
    fi
}

# --- Función para enviar un comando personalizado a la consola del servidor ---
send_custom_command() {
    if ! screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor no está activo."
        return 1
    fi
    read -p "Introduce el comando a enviar: " custom_cmd
    screen -S minecraft_server -X stuff "$custom_cmd^M"
    echo "[*] Comando enviado: $custom_cmd"
}

# --- Función para limpiar copias de seguridad antiguas ---
cleanup_backups() {
    load_params
    if [ ! -d "$BACKUP_PATH" ]; then
        echo "[!] No existe la carpeta de backups."
        return 1
    fi
    read -p "¿Cuántos backups más recientes deseas conservar? [por defecto: 5]: " keep
    keep=${keep:-5}
    total=$(ls -1t "$BACKUP_PATH"/*.tar.gz 2>/dev/null | wc -l)
    if [ "$total" -le "$keep" ]; then
        echo "[*] No hay copias antiguas para eliminar."
        return 0
    fi
    to_delete=$(ls -1t "$BACKUP_PATH"/*.tar.gz 2>/dev/null | tail -n +$((keep+1)))
    echo "[*] Se eliminarán las siguientes copias:"
    echo "$to_delete"
    read -p "¿Confirmar eliminación? (s/N): " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        echo "$to_delete" | xargs rm -f
        echo "[+] Copias antiguas eliminadas."
    else
        echo "[*] Operación cancelada."
    fi
}

# --- Función para editar server.properties ---
edit_server_properties() {
    load_params
    local properties_file="$MINECRAFT_SERVER_PATH/server.properties"
    
    if [ ! -f "$properties_file" ]; then
        echo "[!] No se encontró el archivo server.properties"
        read -p "¿Deseas crear uno nuevo con valores predeterminados? (s/N): " create_new
        if [[ "$create_new" =~ ^[sS]$ ]]; then
            echo "[*] Creando archivo server.properties con valores predeterminados..."
            cat > "$properties_file" <<EOL
#Minecraft server properties
#$(date)
enable-jmx-monitoring=false
rcon.port=25575
gamemode=survival
enable-command-block=false
enable-query=false
level-name=world
motd=Un Servidor de Minecraft
query.port=25565
pvp=true
difficulty=easy
network-compression-threshold=256
require-resource-pack=false
max-tick-time=60000
use-native-transport=true
max-players=20
online-mode=true
enable-status=true
allow-flight=false
initial-disabled-packs=
broadcast-rcon-to-ops=true
view-distance=10
server-ip=
resource-pack-prompt=
allow-nether=true
server-port=25565
enable-rcon=false
sync-chunk-writes=true
op-permission-level=4
prevent-proxy-connections=false
hide-online-players=false
resource-pack=
entity-broadcast-range-percentage=100
simulation-distance=10
rcon.password=
player-idle-timeout=0
force-gamemode=false
rate-limit=0
hardcore=false
white-list=false
broadcast-console-to-ops=true
spawn-npcs=true
spawn-animals=true
function-permission-level=2
level-type=minecraft\:normal
text-filtering-config=
spawn-monsters=true
enforce-whitelist=false
spawn-protection=16
resource-pack-sha1=
max-world-size=29999984
EOL
            echo "[+] Archivo server.properties creado con éxito."
        else
            echo "[*] Operación cancelada."
            return 1
        fi
    fi

    while true; do
        clear
        echo "-----------------------------------------------"
        echo "        EDITOR DE SERVER.PROPERTIES"
        echo "-----------------------------------------------"
        echo "Propiedades actuales:"
        echo ""
        grep -E '^(motd|difficulty|gamemode|max-players|pvp|spawn-protection|level-name|level-seed|enable-command-block)=' "$properties_file" | nl
        echo ""
        echo "1) Modificar una propiedad"
        echo "2) Volver al menú principal"
        echo ""
        
        read -p "Selecciona una opción [1-2]: " option
        case $option in
            1)
                echo ""
                read -p "Introduce el nombre de la propiedad a modificar: " property
                read -p "Introduce el nuevo valor: " value
                
                if grep -q "^$property=" "$properties_file"; then
                    sed -i "s/^$property=.*/$property=$value/" "$properties_file"
                    echo "[+] Propiedad actualizada. Reinicia el servidor para aplicar los cambios."
                else
                    echo "[!] La propiedad no existe en el archivo."
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                return 0
                ;;
            *)
                echo "[!] Opción inválida"
                read -p "Presiona Enter para continuar..."
                ;;
        esac
    done
}

# --- Función para crear copia de seguridad manual ---
create_backup() {
    load_params
    echo "[*] Creando copia de seguridad manual..."
    create_directory_if_not_exists "$BACKUP_PATH"
    BACKUP_NAME="manual_backup_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz"
    
    tar -czf "$BACKUP_PATH/$BACKUP_NAME" -C "$MINECRAFT_SERVER_PATH" "${WORLD_FOLDERS[@]}" 2>/dev/null
    if [ $? -eq 0 ]; then
        backup_size=$(du -h "$BACKUP_PATH/$BACKUP_NAME" | cut -f1)
        echo "[+] Backup creado: $BACKUP_NAME ($backup_size)"
    else
        echo "[!] Error al crear el backup."
    fi
}

# --- Función para crear copia de seguridad completa ---
create_complete_backup() {
    load_params
    echo "[*] Creando copia de seguridad completa..."
    create_directory_if_not_exists "$BACKUP_PATH"
    BACKUP_NAME="complete_backup_$(date +"%Y-%m-%d_%H-%M-%S").tar.gz"
    
    tar -czf "$BACKUP_PATH/$BACKUP_NAME" -C "$MINECRAFT_SERVER_PATH" "${WORLD_FOLDERS[@]}" "${CONFIG_FILES[@]}" 2>/dev/null
    if [ $? -eq 0 ]; then
        backup_size=$(du -h "$BACKUP_PATH/$BACKUP_NAME" | cut -f1)
        echo "[+] Backup completo creado: $BACKUP_NAME ($backup_size)"
    else
        echo "[!] Error al crear el backup completo."
    fi
}

# --- Función para restaurar copia de seguridad ---
restore_backup() {
    load_params
    if [ ! -d "$BACKUP_PATH" ]; then
        echo "[!] No existe la carpeta de backups."
        return 1
    fi

    # Listar backups disponibles
    echo "Backups disponibles:"
    ls -1t "$BACKUP_PATH"/*.tar.gz 2>/dev/null | nl
    
    read -p "Selecciona el número del backup a restaurar (0 para cancelar): " backup_num
    [ "$backup_num" -eq 0 ] && return 0
    
    backup_file=$(ls -1t "$BACKUP_PATH"/*.tar.gz 2>/dev/null | sed -n "${backup_num}p")
    if [ -f "$backup_file" ]; then
        echo "[!] ADVERTENCIA: La restauración sobrescribirá los archivos existentes."
        read -p "¿Continuar? (s/N): " confirm
        if [[ "$confirm" =~ ^[sS]$ ]]; then
            tar -xzf "$backup_file" -C "$MINECRAFT_SERVER_PATH"
            echo "[+] Backup restaurado."
        else
            echo "[*] Restauración cancelada."
        fi
    else
        echo "[!] Backup no válido."
    fi
}

# --- Función para listar copias de seguridad ---
list_backups() {
    load_params
    if [ ! -d "$BACKUP_PATH" ]; then
        echo "[!] No existe la carpeta de backups."
        return 1
    fi

    echo "Listado de copias de seguridad:"
    echo "----------------------------------------"
    for backup in "$BACKUP_PATH"/*.tar.gz; do
        if [ -f "$backup" ]; then
            size=$(du -h "$backup" | cut -f1)
            if [ "$OS_TYPE" = "Mac" ]; then
                date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$backup")
            else
                date=$(stat -c %y "$backup" | cut -d. -f1)
            fi
            echo "$(basename "$backup") ($size) - $date"
        fi
    done
}

# --- Función para listar jugadores conectados ---
list_online_players() {
    if ! screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor no está activo."
        return 1
    fi
    echo "[*] Obteniendo lista de jugadores..."
    screen -S minecraft_server -X stuff "list^M"
    echo "[*] Comando enviado. Los jugadores conectados aparecerán en la consola del servidor."
    echo "[*] Usa 'screen -r minecraft_server' para ver la lista completa."
}

# --- Función para gestionar whitelist ---
manage_whitelist() {
    if ! screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor no está activo."
        return 1
    fi
    while true; do
        clear
        echo "-----------------------------------------------"
        echo "        GESTIÓN DE WHITELIST"
        echo "-----------------------------------------------"
        echo "1) Ver whitelist"
        echo "2) Añadir jugador"
        echo "3) Eliminar jugador"
        echo "4) Volver al menú principal"
        
        read -p "Selecciona una opción [1-4]: " option
        case $option in
            1) screen -S minecraft_server -X stuff "whitelist list^M" ;;
            2)
                read -p "Nombre del jugador: " player
                screen -S minecraft_server -X stuff "whitelist add $player^M"
                ;;
            3)
                read -p "Nombre del jugador: " player
                screen -S minecraft_server -X stuff "whitelist remove $player^M"
                ;;
            4) return 0 ;;
            *) echo "[!] Opción inválida" ;;
        esac
        sleep 1
        read -p "Presiona Enter para continuar..."
    done
}

# --- Función para gestionar operadores ---
manage_ops() {
    load_params
    local ops_file="$MINECRAFT_SERVER_PATH/ops.json"

    while true; do
        clear
        echo "-----------------------------------------------"
        echo "        GESTIÓN DE OPERADORES"
        echo "-----------------------------------------------"
        echo "1) Ver operadores"
        echo "2) Añadir operador"
        echo "3) Eliminar operador"
        echo "4) Volver al menú principal"
        
        read -p "Selecciona una opción [1-4]: " option
        case $option in
            1)  
                if [ -f "$ops_file" ]; then
                    echo ""
                    echo "Lista de operadores:"
                    echo "-------------------"
                    if [ -s "$ops_file" ]; then
                        # Verificar si jq está instalado
                        if command -v jq &>/dev/null; then
                            jq -r '.[].name' "$ops_file" 2>/dev/null || cat "$ops_file"
                        else
                            # Fallback a grep si jq no está instalado
                            grep -o '"name":[[:space:]]*"[^"]*"' "$ops_file" | cut -d'"' -f4
                        fi
                    else
                        echo "No hay operadores registrados"
                    fi
                else
                    echo "El archivo ops.json no existe"
                fi
                ;;
            2)
                if ! screen -list | grep -q "minecraft_server"; then
                    echo "[!] El servidor debe estar activo para añadir operadores"
                else
                    read -p "Nombre del jugador: " player
                    screen -S minecraft_server -X stuff "op $player^M"
                fi
                ;;
            3)
                if ! screen -list | grep -q "minecraft_server"; then
                    echo "[!] El servidor debe estar activo para eliminar operadores"
                else
                    read -p "Nombre del jugador: " player
                    screen -S minecraft_server -X stuff "deop $player^M"
                fi
                ;;
            4) return 0 ;;
            *) echo "[!] Opción inválida" ;;
        esac
        sleep 1
        read -p "Presiona Enter para continuar..."
    done
}

# --- Función para gestionar baneos ---
manage_bans() {
    if ! screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor no está activo."
        return 1
    fi
    while true; do
        clear
        echo "-----------------------------------------------"
        echo "        GESTIÓN DE BANEOS"
        echo "-----------------------------------------------"
        echo "1) Ver jugadores baneados"
        echo "2) Banear jugador"
        echo "3) Desbanear jugador"
        echo "4) Ver IPs baneadas"
        echo "5) Banear IP"
        echo "6) Desbanear IP"
        echo "7) Volver al menú principal"
        
        read -p "Selecciona una opción [1-7]: " option
        case $option in
            1) screen -S minecraft_server -X stuff "banlist players^M" ;;
            2)
                read -p "Nombre del jugador: " player
                read -p "Razón del baneo: " reason
                screen -S minecraft_server -X stuff "ban $player $reason^M"
                ;;
            3)
                read -p "Nombre del jugador: " player
                screen -S minecraft_server -X stuff "pardon $player^M"
                ;;
            4) screen -S minecraft_server -X stuff "banlist ips^M" ;;
            5)
                read -p "IP a banear: " ip
                read -p "Razón del baneo: " reason
                screen -S minecraft_server -X stuff "ban-ip $ip $reason^M"
                ;;
            6)
                read -p "IP a desbanear: " ip
                screen -S minecraft_server -X stuff "pardon-ip $ip^M"
                ;;
            7) return 0 ;;
            *) echo "[!] Opción inválida" ;;
        esac
        sleep 1
        read -p "Presiona Enter para continuar..."
    done
}

# --- Función para mostrar información del sistema ---
system_info() {
    load_params
    clear
    echo "-----------------------------------------------"
    echo "        INFORMACIÓN DEL SISTEMA"
    echo "-----------------------------------------------"
    
    # OS Info
    echo "[*] Sistema Operativo:"
    if [ "$OS_TYPE" = "Mac" ]; then
        echo "    MacOS: $(sw_vers -productVersion)"
        echo "    Kernel: $(uname -r)"
        echo "    Arquitectura: $(uname -m)"
    else
        if [ -f /etc/os-release ]; then
            source /etc/os-release
            echo "    Distribución: $PRETTY_NAME"
            if command -v lsb_release &>/dev/null; then
                echo "    Versión: $(lsb_release -d 2>/dev/null | cut -f2- || echo 'N/A')"
            fi
        fi
        echo "    Kernel: $(uname -r)"
        if command -v dpkg &>/dev/null; then
            echo "    Arquitectura: $(dpkg --print-architecture 2>/dev/null || uname -m)"
        else
            echo "    Arquitectura: $(uname -m)"
        fi
    fi
    echo ""
    
    # Hardware Info
    echo "[*] Hardware:"
    if [ "$OS_TYPE" = "Mac" ]; then
        cpu_model=$(sysctl -n machdep.cpu.brand_string)
        cpu_cores=$(sysctl -n hw.ncpu)
        cpu_freq=$(sysctl -n hw.cpufrequency | awk '{printf "%.2fGHz", $1/1000000000}')
        echo "    CPU: $cpu_model"
        echo "    Núcleos: $cpu_cores"
        echo "    Frecuencia: $cpu_freq"
    else
        if [ -f /proc/cpuinfo ]; then
            cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//')
            cpu_cores=$(grep -c "processor" /proc/cpuinfo)
            cpu_freq=$(grep "cpu MHz" /proc/cpuinfo | head -n1 | cut -d: -f2 | sed 's/^[ \t]*//' | cut -d. -f1)
            echo "    CPU: $cpu_model"
            echo "    Núcleos: $cpu_cores"
            echo "    Frecuencia: ${cpu_freq}MHz"
        fi
    fi
    echo ""
    
    # Memory Info
    echo "[*] Memoria RAM:"
    if [ "$OS_TYPE" = "Mac" ]; then
        total_mem=$(sysctl -n hw.memsize | awk '{printf "%.1fGB", $1/1024/1024/1024}')
        used_mem=$(vm_stat | awk '/Pages active/ {active=$3} /Pages wired down/ {wired=$4} END {printf "%.1fGB", (active+wired)*4096/1024/1024/1024}')
        free_mem=$(vm_stat | awk '/Pages free/ {free=$3} END {printf "%.1fGB", free*4096/1024/1024/1024}')
        echo "    Total: $total_mem"
        echo "    En uso: $used_mem"
        echo "    Disponible: $free_mem"
        echo "    SWAP: N/A"
    else
        if [ -f /proc/meminfo ]; then
            total_mem=$(grep MemTotal /proc/meminfo | awk '{printf "%.1fGB", $2/1024/1024}')
            free_mem=$(grep MemAvailable /proc/meminfo | awk '{printf "%.1fGB", $2/1024/1024}')
            used_mem=$(grep MemTotal /proc/meminfo | awk -v free="$free_mem" '{printf "%.1fGB", $2/1024/1024 - free}')
            echo "    Total: $total_mem"
            echo "    En uso: $used_mem"
            echo "    Disponible: $free_mem"
            echo "    SWAP: $(grep SwapTotal /proc/meminfo | awk '{printf "%.1fGB", $2/1024/1024}')"
        fi
    fi
    echo ""
    
    # Disk Info
    echo "[*] Almacenamiento:"
    echo "    Partición del servidor (${MINECRAFT_SERVER_PATH}):"
    if [ "$OS_TYPE" = "Mac" ]; then
        df -h "$MINECRAFT_SERVER_PATH" | tail -n1 | awk '{printf "    Total: %s\n    Usado: %s (%s)\n    Libre: %s\n", $2, $3, $5, $4}'
    else
        if df "$MINECRAFT_SERVER_PATH" &>/dev/null; then
            df -h "$MINECRAFT_SERVER_PATH" | tail -n1 | awk '{printf "    Total: %s\n    Usado: %s (%s)\n    Libre: %s\n", $2, $3, $5, $4}'
        fi
    fi
    echo ""
    
    # Network Info
    echo "[*] Red:"
    echo "    Hostname: $(hostname -f 2>/dev/null || hostname)"
    if [ "$OS_TYPE" = "Mac" ]; then
        echo "    Interfaces:"
        if command -v ifconfig &>/dev/null; then
            ifconfig | grep 'flags=' | cut -d: -f1 | grep -v '^lo' | while read -r iface; do
                ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
                [ ! -z "$ip" ] && echo "        $iface: $ip"
            done
        fi
    else
        if ip addr &>/dev/null; then
            echo "    Interfaces:"
            ip -br addr | grep -v '^lo' | while read -r line; do
                if [[ $line =~ ^[[:alnum:]]+ ]]; then
                    iface=${BASH_REMATCH[0]}
                    ip=$(echo "$line" | grep -oP '(\d{1,3}\.){3}\d{1,3}' | head -n1)
                    [ ! -z "$ip" ] && echo "        $iface: $ip"
                fi
            done
        fi
    fi
    echo ""

    # Process Info
    echo "[*] Procesos:"
    echo "    Carga del sistema: $(uptime | grep -oE 'load averages?:.*' | sed 's/load averages\?: //')"
    echo "    Procesos totales: $(ps aux | wc -l)"
    if screen -list | grep -q "minecraft_server"; then
        pid=$(screen -list | grep minecraft_server | grep -o '[0-9]*')
        if [ "$OS_TYPE" = "Mac" ]; then
            echo "    PID del servidor: $pid"
            echo "    Uso de CPU: $(ps -p $pid -o %cpu | tail -n1)%"
            echo "    Uso de memoria: $(ps -p $pid -o %mem | tail -n1)%"
        else
            echo "    PID del servidor: $pid"
            echo "    Uso de CPU: $(ps -p $pid -o %cpu | tail -n1)%"
            echo "    Uso de memoria: $(ps -p $pid -o %mem | tail -n1)%"
        fi
    fi
    echo ""

    # Uptime
    echo "[*] Tiempo de actividad:"
    if [ "$OS_TYPE" = "Mac" ]; then
        uptime | awk -F'(up |, [0-9]+ users?,)' '{print $2}'
    else
        uptime -p
    fi
    echo ""
}

# --- Función para reconfigurar rutas ---
reconfigure_paths() {
    echo "[*] Reconfigurando rutas..."
    rm -f "$PARAM_FILE"
    get_and_save_params
    echo "[+] Configuración completada."
}

# --- Función para conectar a la consola del servidor ---
connect_to_console() {
    if ! screen -list | grep -q "minecraft_server"; then
        echo "[!] El servidor no está activo."
        return 1
    fi
    echo "[*] Conectando a la consola del servidor..."
    echo "[i] Para desconectarte usa: CTRL+A, luego D"
    echo "[i] Presiona Enter para continuar..."
    read
    screen -r minecraft_server
}

# --- Función principal del menú ---
show_menu() {
    clear
    check_dependencies
    echo "-----------------------------------------------"
    echo "           [*] GESTOR DE MINECRAFT SERVER       "
    echo "-----------------------------------------------"
    echo ""

    # Obtener y mostrar IP pública y DNS
    echo "[*] Información de conexión:"
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null)
    if [ ! -z "$PUBLIC_IP" ]; then
        echo "    IP Pública: $PUBLIC_IP"
        # Intentar obtener el nombre de dominio reverso
        DNS_NAME=$(dig +short -x $PUBLIC_IP 2>/dev/null || host $PUBLIC_IP 2>/dev/null || echo "No disponible")
        echo "    Dominio: $DNS_NAME"
    else
        echo "    [!] No se pudo obtener la IP pública"
    fi

    # --- Detección del tipo de servidor ---
    SERVER_TYPE="Desconocido"
    load_params
    if [ -f "$MINECRAFT_SERVER_PATH/purpur-"*.jar ]; then
        SERVER_TYPE="Purpur"
    elif [ -f "$MINECRAFT_SERVER_PATH/folia-"*.jar ]; then
        SERVER_TYPE="Folia"
    elif [ -f "$MINECRAFT_SERVER_PATH/paper-"*.jar ]; then
        SERVER_TYPE="Paper"
    elif [ -f "$MINECRAFT_SERVER_PATH/server.jar" ]; then
        SERVER_TYPE="Vanilla"
    fi
    echo "    Tipo de servidor: $SERVER_TYPE"
    echo ""

    # Mostrar estado actual del servidor de forma compacta
    if screen -list | grep -q "minecraft_server"; then
        echo "[+] Servidor: ACTIVO"
    else
        echo "[-] Servidor: INACTIVO"
    fi
    
    load_params
    if [ -d "$BACKUP_PATH" ]; then
        backup_count=$(ls "$BACKUP_PATH"/*.tar.gz 2>/dev/null | wc -l)
        echo "[*] Backups disponibles: $backup_count"
    fi
    echo ""

    echo "-----------------------------------------------"
    echo " SERVIDOR"
    echo "-----------------------------------------------"
    echo "1)  [*] Iniciar servidor (con copia de seguridad)"
    echo "2)  [*] Iniciar servidor (sin copia de seguridad)"
    echo "3)  [*] Detener servidor"
    echo "4)  [*] Reiniciar servidor"
    echo "5)  [*] Ver estado detallado del servidor"
    echo "6)  [*] Enviar comando personalizado"
    if screen -list | grep -q "minecraft_server"; then
        echo "7)  [*] Conectar a la consola del servidor"
    fi
    echo ""

    echo "-----------------------------------------------"
    echo " COPIAS DE SEGURIDAD"
    echo "-----------------------------------------------"
    echo "8)  [*] Crear copia de seguridad manual (solo mundos)"
    echo "9)  [*] Crear copia de seguridad completa (mundos + configuración)"
    echo "10) [*] Restaurar copia de seguridad"
    echo "11) [*] Listar copias de seguridad"
    echo "12) [*] Limpiar copias de seguridad antiguas"
    echo ""

    echo "-----------------------------------------------"
    echo " GESTIÓN DE USUARIOS"
    echo "-----------------------------------------------"
    echo "13) [*] Ver jugadores conectados"
    echo "14) [*] Gestión de Whitelist"
    echo "15) [*] Gestión de Operadores"
    echo "16) [*] Gestión de Baneos"
    echo ""

    echo "-----------------------------------------------"
    echo " CONFIGURACIÓN Y SISTEMA"
    echo "-----------------------------------------------"
    echo "17) [*] Información del sistema"
    echo "18) [*] Reconfigurar rutas"
    echo "19) [*] Modificar server.properties"
    echo "20) [*] Salir"
    echo ""
}

# --- Loop principal ---
while true; do
    show_menu
    read -p "Elige una opción [1-20]: " choice
    echo ""

    case $choice in
        1)
            start_minecraft_server
            ;;
        2)
            start_minecraft_server_no_backup
            ;;
        3)
            stop_minecraft_server
            ;;
        4)
            restart_minecraft_server
            ;;
        5)
            server_status
            ;;
        6)
            send_custom_command
            ;;
        7)
            if screen -list | grep -q "minecraft_server"; then
                connect_to_console
            else
                create_backup
            fi
            ;;
        8)
            create_backup
            ;;
        9)
            create_complete_backup
            ;;
        10)
            restore_backup
            ;;
        11)
            list_backups
            ;;
        12)
            cleanup_backups
            ;;
        13)
            list_online_players
            ;;
        14)
            manage_whitelist
            ;;
        15)
            manage_ops
            ;;
        16)
            manage_bans
            ;;
        17)
            system_info
            ;;
        18)
            reconfigure_paths
            ;;
        19)
            edit_server_properties
            ;;
        20)
            echo "[*] ¡Hasta luego!"
            exit 0
            ;;
        *)
            echo "[!] Opción inválida. Por favor, elige un número del 1 al 20."
            ;;
    esac
    
    echo ""
    read -p "Presiona Enter para continuar..."