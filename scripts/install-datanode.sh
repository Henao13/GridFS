#!/bin/bash

# GridDFS DataNode Installation Script for Ubuntu 22.04 on AWS EC2
# Run with: curl -sSL https://raw.githubusercontent.com/tu-repo/install-datanode.sh | bash

set -e

echo "📦 Iniciando instalación de GridDFS DataNode..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_input() {
    echo -e "${BLUE}[INPUT]${NC} $1"
}

# Verificar que estamos en Ubuntu
if [ ! -f /etc/lsb-release ] || ! grep -q "Ubuntu" /etc/lsb-release; then
    log_error "Este script está diseñado para Ubuntu 22.04"
    exit 1
fi

# Variables de configuración
GRIDDFS_DIR="$HOME/griddfs"
DATANODE_PORT=${DATANODE_PORT:-50051}
STORAGE_PATH=${STORAGE_PATH:-"/home/$USER/griddfs-storage"}
REPO_URL=${REPO_URL:-""}

# Solicitar configuración interactiva si no está definida
if [ -z "$NAMENODE_HOST" ]; then
    log_input "Ingresa la IP privada del NameNode (ej: 172.31.x.x):"
    read -r NAMENODE_HOST
fi

if [ -z "$NAMENODE_PORT" ]; then
    NAMENODE_PORT="50050"
fi

DATANODE_ID=${DATANODE_ID:-"datanode-$(hostname)"}

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Actualizar sistema
log_info "Actualizando sistema..."
sudo apt update
sudo apt upgrade -y

# Instalar dependencias básicas
log_info "Instalando dependencias básicas..."
sudo apt install -y \
    curl \
    wget \
    git \
    unzip \
    build-essential

# Instalar OpenJDK 17
log_info "Instalando OpenJDK 17..."
sudo apt install -y openjdk-17-jdk openjdk-17-jre

# Instalar Maven
log_info "Instalando Apache Maven..."
sudo apt install -y maven

# Configurar JAVA_HOME
log_info "Configurando JAVA_HOME..."
JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
echo "export JAVA_HOME=$JAVA_HOME" >> ~/.bashrc
echo "export PATH=\$JAVA_HOME/bin:\$PATH" >> ~/.bashrc

# Aplicar cambios inmediatamente
export JAVA_HOME="$JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

# Verificar instalaciones
log_info "Verificando instalaciones..."
if command_exists java; then
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    log_info "Java versión: $JAVA_VERSION"
else
    log_error "Java no se instaló correctamente"
    exit 1
fi

if command_exists mvn; then
    MVN_VERSION=$(mvn -version | head -n 1)
    log_info "Maven versión: $MVN_VERSION"
else
    log_error "Maven no se instaló correctamente"
    exit 1
fi

log_info "JAVA_HOME configurado en: $JAVA_HOME"

# Crear directorio de trabajo
log_info "Creando directorio de trabajo en $GRIDDFS_DIR..."
mkdir -p "$GRIDDFS_DIR"
cd "$GRIDDFS_DIR"

# Si se proporcionó URL del repositorio, clonar
if [ -n "$REPO_URL" ]; then
    log_info "Clonando repositorio desde $REPO_URL..."
    git clone "$REPO_URL" .
else
    log_warning "No se proporcionó URL del repositorio."
    log_warning "Debes subir manualmente los archivos del proyecto a $GRIDDFS_DIR"
    log_warning "Usa: scp -i tu-keypair.pem -r ./GridFS/* ubuntu@<IP_DATANODE>:~/griddfs/"
fi

# Verificar que existe el directorio DataNode
if [ ! -d "$GRIDDFS_DIR/DataNode" ]; then
    log_error "No se encontró el directorio DataNode en $GRIDDFS_DIR"
    log_error "Asegúrate de subir los archivos del proyecto correctamente"
    exit 1
fi

# Compilar DataNode
log_info "Compilando DataNode..."
cd "$GRIDDFS_DIR/DataNode"

# Limpiar y compilar
log_info "Ejecutando Maven clean compile..."
if ! mvn clean compile; then
    log_error "Error en compilación con Maven"
    exit 1
fi

log_info "Ejecutando Maven package..."
if ! mvn clean package; then
    log_error "Error en empaquetado con Maven"
    exit 1
fi

# Verificar que se creó el JAR
JAR_FILE="target/datanode-1.0-SNAPSHOT.jar"
if [ ! -f "$JAR_FILE" ]; then
    log_error "El archivo JAR no se creó correctamente: $JAR_FILE"
    exit 1
fi

log_info "✅ Compilación exitosa! JAR creado en: $(pwd)/$JAR_FILE"

# Crear directorio de almacenamiento
log_info "Creando directorio de almacenamiento en $STORAGE_PATH..."
mkdir -p "$STORAGE_PATH"

# Crear archivo de configuración
log_info "Creando archivo de configuración..."
tee "$GRIDDFS_DIR/DataNode/datanode.env" > /dev/null <<EOF
# Configuración DataNode GridDFS
NAMENODE_HOST=$NAMENODE_HOST
NAMENODE_PORT=$NAMENODE_PORT
DATANODE_PORT=$DATANODE_PORT
DATANODE_ID=$DATANODE_ID
DATANODE_STORAGE_PATH=$STORAGE_PATH
JAVA_HOME=$JAVA_HOME
EOF

log_info "Configuración guardada en: $GRIDDFS_DIR/DataNode/datanode.env"

# Crear archivo de servicio systemd
log_info "Configurando servicio systemd..."
sudo tee /etc/systemd/system/griddfs-datanode.service > /dev/null <<EOF
[Unit]
Description=GridDFS DataNode Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$GRIDDFS_DIR/DataNode
EnvironmentFile=$GRIDDFS_DIR/DataNode/datanode.env
ExecStart=$JAVA_HOME/bin/java -jar target/datanode-1.0-SNAPSHOT.jar
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar servicio
sudo systemctl daemon-reload
sudo systemctl enable griddfs-datanode

log_info "Servicio configurado. Para iniciarlo usa:"
log_info "  sudo systemctl start griddfs-datanode"
log_info "Para ver logs usa:"
log_info "  sudo journalctl -u griddfs-datanode -f"

# Crear script de control
log_info "Creando scripts de control..."
tee "$HOME/datanode-control.sh" > /dev/null <<'EOF'
#!/bin/bash

GRIDDFS_DIR="$HOME/griddfs"

case "$1" in
    start)
        echo "🚀 Iniciando DataNode..."
        sudo systemctl start griddfs-datanode
        ;;
    stop)
        echo "🛑 Deteniendo DataNode..."
        sudo systemctl stop griddfs-datanode
        ;;
    restart)
        echo "🔄 Reiniciando DataNode..."
        sudo systemctl restart griddfs-datanode
        ;;
    status)
        sudo systemctl status griddfs-datanode
        ;;
    logs)
        sudo journalctl -u griddfs-datanode -f
        ;;
    build)
        echo "🔨 Recompilando DataNode..."
        cd "$GRIDDFS_DIR/DataNode"
        mvn clean compile
        mvn clean package
        if [ $? -eq 0 ]; then
            echo "✅ Compilación exitosa"
            if systemctl is-active --quiet griddfs-datanode; then
                echo "🔄 Reiniciando servicio..."
                sudo systemctl restart griddfs-datanode
            fi
        else
            echo "❌ Error en compilación"
        fi
        ;;
    storage)
        echo "📁 Contenido del directorio de almacenamiento:"
        source "$GRIDDFS_DIR/DataNode/datanode.env"
        ls -la "$DATANODE_STORAGE_PATH"
        ;;
    config)
        echo "⚙️  Configuración actual:"
        cat "$GRIDDFS_DIR/DataNode/datanode.env"
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|status|logs|build|storage|config}"
        echo ""
        echo "Comandos disponibles:"
        echo "  start   - Iniciar el servicio DataNode"
        echo "  stop    - Detener el servicio DataNode"
        echo "  restart - Reiniciar el servicio DataNode"
        echo "  status  - Ver estado del servicio"
        echo "  logs    - Ver logs en tiempo real"
        echo "  build   - Recompilar y reiniciar si está corriendo"
        echo "  storage - Ver contenido del directorio de almacenamiento"
        echo "  config  - Ver configuración actual"
        ;;
esac
EOF

chmod +x "$HOME/datanode-control.sh"

# Crear alias
echo 'alias datanode="~/datanode-control.sh"' >> ~/.bashrc

log_info "🎉 ¡Instalación de DataNode completada!"
echo ""
log_info "📋 Configuración:"
log_info "  NameNode: $NAMENODE_HOST:$NAMENODE_PORT"
log_info "  DataNode Port: $DATANODE_PORT"
log_info "  DataNode ID: $DATANODE_ID"
log_info "  Storage Path: $STORAGE_PATH"
echo ""
log_info "📋 Próximos pasos:"
log_info "1. Asegúrate de que el NameNode esté corriendo en $NAMENODE_HOST:$NAMENODE_PORT"
log_info "2. Inicia el servicio: sudo systemctl start griddfs-datanode"
log_info "3. Verifica estado: sudo systemctl status griddfs-datanode"
log_info "4. Ve logs: sudo journalctl -u griddfs-datanode -f"
log_info "5. O usa el script: ~/datanode-control.sh start"
echo ""
log_info "🔧 Script de control disponible en: ~/datanode-control.sh"
log_info "📁 Código fuente en: $GRIDDFS_DIR"
log_info "🗂️  JAR ejecutable en: $GRIDDFS_DIR/DataNode/target/datanode-1.0-SNAPSHOT.jar"
log_info "⚙️  Configuración en: $GRIDDFS_DIR/DataNode/datanode.env"
echo ""
log_warning "⚠️  Recuerda abrir el puerto $DATANODE_PORT en el Security Group de AWS"
log_warning "⚠️  El servicio escuchará en 0.0.0.0:$DATANODE_PORT"

# Verificar conectividad con NameNode
log_info "🔍 Verificando conectividad con NameNode..."
if command_exists telnet; then
    if timeout 5 telnet "$NAMENODE_HOST" "$NAMENODE_PORT" </dev/null 2>/dev/null | grep -q "Connected"; then
        log_info "✅ Conectividad con NameNode OK"
    else
        log_warning "⚠️  No se pudo conectar al NameNode en $NAMENODE_HOST:$NAMENODE_PORT"
        log_warning "   Verifica que el NameNode esté corriendo y los puertos estén abiertos"
    fi
else
    sudo apt install -y telnet
fi

echo ""
log_info "✨ Para recargar aliases: source ~/.bashrc"
log_info "✨ Luego puedes usar: datanode start, datanode status, etc."