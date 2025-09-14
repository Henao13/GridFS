#!/bin/bash

# GridDFS Client Installation Script for Ubuntu 22.04 on AWS EC2
# Run with: curl -sSL https://raw.githubusercontent.com/tu-repo/install-client.sh | bash

set -e

echo "🐍 Iniciando instalación de GridDFS Cliente..."

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
VENV_DIR="$HOME/griddfs-client"
NAMENODE_PORT=${NAMENODE_PORT:-50050}
DATANODE_PORT=${DATANODE_PORT:-50051}
REPO_URL=${REPO_URL:-""}

# Solicitar configuración interactiva si no está definida
if [ -z "$NAMENODE_HOST" ]; then
    log_input "Ingresa la IP pública del NameNode:"
    read -r NAMENODE_HOST
fi

if [ -z "$DATANODE_HOST" ]; then
    log_input "Ingresa la IP pública de un DataNode (para pruebas):"
    read -r DATANODE_HOST
fi

# Función para verificar si un comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Actualizar sistema
log_info "Actualizando sistema..."
sudo apt update
sudo apt upgrade -y

# Instalar Python y dependencias
log_info "Instalando Python 3 y herramientas..."
sudo apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    build-essential \
    curl \
    wget \
    git

# Verificar instalación de Python
if command_exists python3; then
    PYTHON_VERSION=$(python3 --version)
    log_info "Python instalado: $PYTHON_VERSION"
else
    log_error "Python 3 no se instaló correctamente"
    exit 1
fi

# Crear entorno virtual
log_info "Creando entorno virtual en $VENV_DIR..."
python3 -m venv "$VENV_DIR"

# Activar entorno virtual
log_info "Activando entorno virtual..."
source "$VENV_DIR/bin/activate"

# Actualizar pip
log_info "Actualizando pip..."
pip install --upgrade pip

# Instalar dependencias gRPC para Python
log_info "Instalando dependencias gRPC..."
pip install \
    grpcio \
    grpcio-tools \
    protobuf

# Instalar dependencias adicionales
log_info "Instalando dependencias adicionales..."
pip install \
    requests \
    click \
    colorama \
    tabulate

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
    log_warning "Usa: scp -i tu-keypair.pem -r ./Proyecto\\ 1/* ubuntu@<IP_CLIENT>:~/griddfs/"
fi

# Verificar que existe el directorio Cliente
if [ ! -d "$GRIDDFS_DIR/Cliente" ]; then
    log_error "No se encontró el directorio Cliente en $GRIDDFS_DIR"
    log_error "Asegúrate de subir los archivos del proyecto correctamente"
    exit 1
fi

# Verificar que existen los archivos proto generados
if [ ! -d "$GRIDDFS_DIR/Cliente/src/griddfs" ]; then
    log_error "No se encontró el directorio griddfs con archivos proto en Cliente/src/"
    log_error "Asegúrate de que los archivos proto estén generados correctamente"
    exit 1
fi

log_info "✅ Archivos proto encontrados en Cliente/src/griddfs/"

# Crear archivo de configuración
log_info "Creando archivo de configuración..."
tee "$GRIDDFS_DIR/Cliente/client.env" > /dev/null <<EOF
# Configuración Cliente GridDFS
NAMENODE_HOST=$NAMENODE_HOST
NAMENODE_PORT=$NAMENODE_PORT
DEFAULT_DATANODE_HOST=$DATANODE_HOST
DEFAULT_DATANODE_PORT=$DATANODE_PORT
GRIDDFS_VENV=$VENV_DIR
EOF

log_info "Configuración guardada en: $GRIDDFS_DIR/Cliente/client.env"

# Crear script de ejecución principal
log_info "Creando script de ejecución..."
tee "$HOME/griddfs-client.sh" > /dev/null <<'EOF'
#!/bin/bash

# Script principal para ejecutar el cliente GridDFS

GRIDDFS_DIR="$HOME/griddfs"
CLIENT_ENV="$GRIDDFS_DIR/Cliente/client.env"

# Verificar que existe la configuración
if [ ! -f "$CLIENT_ENV" ]; then
    echo "❌ Error: No se encontró el archivo de configuración en $CLIENT_ENV"
    echo "   Ejecuta primero el script de instalación"
    exit 1
fi

# Cargar configuración
source "$CLIENT_ENV"

# Verificar que existe el entorno virtual
if [ ! -d "$GRIDDFS_VENV" ]; then
    echo "❌ Error: No se encontró el entorno virtual en $GRIDDFS_VENV"
    exit 1
fi

# Activar entorno virtual
source "$GRIDDFS_VENV/bin/activate"

# Navegar al directorio del cliente
cd "$GRIDDFS_DIR/Cliente/src"

# Verificar que existen los archivos necesarios
if [ ! -f "cli.py" ]; then
    echo "❌ Error: No se encontró cli.py en $(pwd)"
    exit 1
fi

# Ejecutar cliente con todos los argumentos pasados
python3 cli.py "$@"
EOF

chmod +x "$HOME/griddfs-client.sh"

# Crear scripts de utilidad
log_info "Creando scripts de utilidad..."

# Script de control del cliente
tee "$HOME/client-control.sh" > /dev/null <<'EOF'
#!/bin/bash

GRIDDFS_DIR="$HOME/griddfs"
CLIENT_ENV="$GRIDDFS_DIR/Cliente/client.env"

case "$1" in
    config)
        echo "⚙️  Configuración actual:"
        if [ -f "$CLIENT_ENV" ]; then
            cat "$CLIENT_ENV"
        else
            echo "❌ No se encontró el archivo de configuración"
        fi
        ;;
    test)
        echo "🧪 Probando conectividad con NameNode..."
        source "$CLIENT_ENV"
        if command -v telnet >/dev/null 2>&1; then
            if timeout 5 telnet "$NAMENODE_HOST" "$NAMENODE_PORT" </dev/null 2>/dev/null | grep -q "Connected"; then
                echo "✅ Conectividad con NameNode OK ($NAMENODE_HOST:$NAMENODE_PORT)"
            else
                echo "❌ No se pudo conectar al NameNode en $NAMENODE_HOST:$NAMENODE_PORT"
            fi
        else
            echo "⚠️  telnet no está instalado, instalando..."
            sudo apt install -y telnet
        fi
        ;;
    env)
        echo "🔧 Información del entorno:"
        source "$CLIENT_ENV"
        source "$GRIDDFS_VENV/bin/activate"
        echo "Python: $(python3 --version)"
        echo "Pip: $(pip --version)"
        echo "Entorno virtual: $GRIDDFS_VENV"
        echo "Paquetes instalados:"
        pip list | grep -E "(grpc|protobuf)"
        ;;
    shell)
        echo "🐚 Iniciando shell con entorno activado..."
        source "$CLIENT_ENV"
        cd "$GRIDDFS_DIR/Cliente/src"
        exec bash --init-file <(echo "source $GRIDDFS_VENV/bin/activate; echo '✅ Entorno GridDFS activado. Directorio: $(pwd)'")
        ;;
    *)
        echo "Uso: $0 {config|test|env|shell}"
        echo ""
        echo "Comandos disponibles:"
        echo "  config - Ver configuración actual"
        echo "  test   - Probar conectividad con NameNode"
        echo "  env    - Ver información del entorno Python"
        echo "  shell  - Iniciar shell con entorno activado"
        echo ""
        echo "Para usar el cliente:"
        echo "  ~/griddfs-client.sh --help"
        echo "  ~/griddfs-client.sh list /"
        echo "  ~/griddfs-client.sh put archivo.txt /archivo.txt"
        ;;
esac
EOF

chmod +x "$HOME/client-control.sh"

# Crear aliases
log_info "Configurando aliases..."
echo '' >> ~/.bashrc
echo '# GridDFS Aliases' >> ~/.bashrc
echo 'alias griddfs="~/griddfs-client.sh"' >> ~/.bashrc
echo 'alias griddfs-control="~/client-control.sh"' >> ~/.bashrc
echo 'alias griddfs-shell="~/client-control.sh shell"' >> ~/.bashrc

# Crear archivo de prueba
log_info "Creando archivo de prueba..."
echo "¡Hola desde GridDFS! Archivo de prueba creado el $(date)" > "$HOME/test-file.txt"

log_info "🎉 ¡Instalación del Cliente GridDFS completada!"
echo ""
log_info "📋 Configuración:"
log_info "  NameNode: $NAMENODE_HOST:$NAMENODE_PORT"
log_info "  DataNode: $DATANODE_HOST:$DATANODE_PORT"
log_info "  Entorno virtual: $VENV_DIR"
echo ""
log_info "📋 Scripts disponibles:"
log_info "  ~/griddfs-client.sh     - Cliente principal"
log_info "  ~/client-control.sh     - Utilidades de control"
echo ""
log_info "📋 Próximos pasos:"
log_info "1. Recarga los aliases: source ~/.bashrc"
log_info "2. Prueba conectividad: griddfs-control test"
log_info "3. Ve la ayuda: griddfs --help"
log_info "4. Lista archivos: griddfs list /"
echo ""
log_info "📋 Comandos de ejemplo:"
log_info "  griddfs register usuario password        # Registrar usuario"
log_info "  griddfs login usuario password           # Iniciar sesión"
log_info "  griddfs put ~/test-file.txt /test.txt    # Subir archivo"
log_info "  griddfs list /                           # Listar archivos"
log_info "  griddfs get /test.txt ~/downloaded.txt   # Descargar archivo"
echo ""
log_warning "⚠️  Asegúrate de que el NameNode y al menos un DataNode estén corriendo"
log_warning "⚠️  Los puertos $NAMENODE_PORT y $DATANODE_PORT deben estar abiertos en AWS"

# Probar conectividad inicial
log_info "🔍 Probando conectividad inicial..."
if command_exists telnet; then
    if timeout 5 telnet "$NAMENODE_HOST" "$NAMENODE_PORT" </dev/null 2>/dev/null | grep -q "Connected"; then
        log_info "✅ Conectividad con NameNode OK"
    else
        log_warning "⚠️  No se pudo conectar al NameNode"
        log_warning "   Verifica que esté corriendo en $NAMENODE_HOST:$NAMENODE_PORT"
    fi
fi

echo ""
log_info "✨ Para empezar usa: source ~/.bashrc && griddfs --help"