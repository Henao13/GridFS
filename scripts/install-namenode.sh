#!/bin/bash

# GridDFS NameNode Installation Script for Ubuntu 22.04 on AWS EC2
# Run with: curl -sSL https://raw.githubusercontent.com/tu-repo/install-namenode.sh | bash

set -e

echo "🏗️  Iniciando instalación de GridDFS NameNode..."

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Verificar que estamos en Ubuntu
if [ ! -f /etc/lsb-release ] || ! grep -q "Ubuntu" /etc/lsb-release; then
    log_error "Este script está diseñado para Ubuntu 22.04"
    exit 1
fi

# Variables de configuración
GRIDDFS_DIR="$HOME/griddfs"
NAMENODE_PORT=${NAMENODE_PORT:-50050}
REPO_URL=${REPO_URL:-""}  # El usuario debe proporcionar esto

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
    build-essential \
    cmake \
    git \
    curl \
    wget \
    unzip \
    pkg-config \
    autoconf \
    automake \
    libtool \
    g++ \
    make \
    ninja-build

# Instalar dependencias gRPC y Protobuf
log_info "Instalando dependencias gRPC y Protobuf..."
sudo apt install -y \
    libprotobuf-dev \
    protobuf-compiler \
    libgrpc-dev \
    libgrpc++-dev \
    protobuf-compiler-grpc \
    libabsl-dev \
    libre2-dev \
    libssl-dev \
    zlib1g-dev

# Verificar versiones
log_info "Verificando instalaciones..."
if command_exists protoc; then
    log_info "Protobuf versión: $(protoc --version)"
else
    log_error "Protobuf no se instaló correctamente"
    exit 1
fi

if command_exists cmake; then
    log_info "CMake versión: $(cmake --version | head -n 1)"
else
    log_error "CMake no se instaló correctamente"
    exit 1
fi

if command_exists g++; then
    log_info "G++ versión: $(g++ --version | head -n 1)"
else
    log_error "G++ no se instaló correctamente"
    exit 1
fi

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
    log_warning "Usa: scp -i tu-keypair.pem -r ./GridFS/* ubuntu@<IP_NAMENODE>:~/griddfs/"
fi

# Verificar que existe el directorio NameNode
if [ ! -d "$GRIDDFS_DIR/NameNode" ]; then
    log_error "No se encontró el directorio NameNode en $GRIDDFS_DIR"
    log_error "Asegúrate de subir los archivos del proyecto correctamente"
    exit 1
fi

# Compilar NameNode
log_info "Compilando NameNode..."
cd "$GRIDDFS_DIR/NameNode/src"

# Crear directorio build
mkdir -p build
cd build

# Configurar CMake
log_info "Ejecutando cmake..."
if ! cmake ..; then
    log_error "Error en configuración de CMake"
    log_error "Verifica que todos los archivos proto estén presentes"
    exit 1
fi

# Compilar
log_info "Compilando (usando $(($(nproc))) núcleos)..."
if ! make -j"$(nproc)"; then
    log_error "Error en compilación"
    exit 1
fi

# Verificar que se creó el ejecutable
if [ ! -f "namenode" ]; then
    log_error "El ejecutable namenode no se creó correctamente"
    exit 1
fi

log_info "✅ Compilación exitosa! Ejecutable creado en: $(pwd)/namenode"

# Crear archivo de servicio systemd
log_info "Configurando servicio systemd..."
sudo tee /etc/systemd/system/griddfs-namenode.service > /dev/null <<EOF
[Unit]
Description=GridDFS NameNode Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$GRIDDFS_DIR/NameNode/src/build
ExecStart=$GRIDDFS_DIR/NameNode/src/build/namenode
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd y habilitar servicio
sudo systemctl daemon-reload
sudo systemctl enable griddfs-namenode

log_info "Servicio configurado. Para iniciarlo usa:"
log_info "  sudo systemctl start griddfs-namenode"
log_info "Para ver logs usa:"
log_info "  sudo journalctl -u griddfs-namenode -f"

# Crear script de control
log_info "Creando scripts de control..."
tee "$HOME/namenode-control.sh" > /dev/null <<'EOF'
#!/bin/bash

case "$1" in
    start)
        echo "🚀 Iniciando NameNode..."
        sudo systemctl start griddfs-namenode
        ;;
    stop)
        echo "🛑 Deteniendo NameNode..."
        sudo systemctl stop griddfs-namenode
        ;;
    restart)
        echo "🔄 Reiniciando NameNode..."
        sudo systemctl restart griddfs-namenode
        ;;
    status)
        sudo systemctl status griddfs-namenode
        ;;
    logs)
        sudo journalctl -u griddfs-namenode -f
        ;;
    build)
        echo "🔨 Recompilando NameNode..."
        cd ~/griddfs/NameNode/src/build
        make -j$(nproc)
        if [ $? -eq 0 ]; then
            echo "✅ Compilación exitosa"
            if systemctl is-active --quiet griddfs-namenode; then
                echo "🔄 Reiniciando servicio..."
                sudo systemctl restart griddfs-namenode
            fi
        else
            echo "❌ Error en compilación"
        fi
        ;;
    *)
        echo "Uso: $0 {start|stop|restart|status|logs|build}"
        echo ""
        echo "Comandos disponibles:"
        echo "  start   - Iniciar el servicio NameNode"
        echo "  stop    - Detener el servicio NameNode"
        echo "  restart - Reiniciar el servicio NameNode"
        echo "  status  - Ver estado del servicio"
        echo "  logs    - Ver logs en tiempo real"
        echo "  build   - Recompilar y reiniciar si está corriendo"
        ;;
esac
EOF

chmod +x "$HOME/namenode-control.sh"

# Crear alias
echo 'alias namenode="~/namenode-control.sh"' >> ~/.bashrc

log_info "🎉 ¡Instalación de NameNode completada!"
echo ""
log_info "📋 Próximos pasos:"
log_info "1. Inicia el servicio: sudo systemctl start griddfs-namenode"
log_info "2. Verifica estado: sudo systemctl status griddfs-namenode"
log_info "3. Ve logs: sudo journalctl -u griddfs-namenode -f"
log_info "4. O usa el script: ~/namenode-control.sh start"
echo ""
log_info "🔧 Script de control disponible en: ~/namenode-control.sh"
log_info "📁 Código fuente en: $GRIDDFS_DIR"
log_info "🗂️  Ejecutable en: $GRIDDFS_DIR/NameNode/src/build/namenode"
echo ""
log_warning "⚠️  Recuerda abrir el puerto $NAMENODE_PORT en el Security Group de AWS"
log_warning "⚠️  El servicio escuchará en 0.0.0.0:$NAMENODE_PORT"

# Verificar si el puerto está disponible
if command_exists ss; then
    if ss -tlnp | grep ":$NAMENODE_PORT " > /dev/null; then
        log_warning "⚠️  El puerto $NAMENODE_PORT ya está en uso"
    fi
fi

echo ""
log_info "✨ Para recargar aliases: source ~/.bashrc"
log_info "✨ Luego puedes usar: namenode start, namenode status, etc."