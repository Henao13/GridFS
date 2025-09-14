#!/bin/bash

# GridDFS Installation Script for Amazon Linux 2023
# Supports both Ubuntu 22.04 and Amazon Linux 2023
# Auto-detects the OS and installs appropriate packages

set -e

echo "🚀 GridDFS Installation - OS Auto-Detection"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detectar sistema operativo
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        log_error "No se pudo detectar el sistema operativo"
        exit 1
    fi
    
    log_info "Sistema detectado: $OS $VER"
}

# Instalación para Ubuntu 22.04
install_ubuntu() {
    log_info "Configurando para Ubuntu 22.04..."
    
    # Actualizar sistema
    sudo apt update
    sudo apt upgrade -y
    
    # Dependencias básicas
    sudo apt install -y \
        curl wget git unzip \
        build-essential cmake pkg-config \
        python3 python3-pip python3-venv \
        openjdk-17-jdk maven \
        libprotobuf-dev protobuf-compiler \
        libgrpc-dev libgrpc++-dev protobuf-compiler-grpc
}

# Instalación para Amazon Linux 2023
install_amazon_linux() {
    log_info "Configurando para Amazon Linux 2023..."
    
    # Actualizar sistema
    sudo dnf update -y
    
    # Habilitar repositorios adicionales
    sudo dnf install -y epel-release
    sudo dnf config-manager --set-enabled crb || true
    
    # Dependencias básicas
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y \
        curl wget git unzip \
        cmake gcc-c++ pkgconfig \
        python3 python3-pip \
        java-17-openjdk java-17-openjdk-devel maven \
        protobuf-devel protobuf-compiler \
        grpc-devel grpc-plugins
    
    # Configurar JAVA_HOME para Amazon Linux
    echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk' >> ~/.bashrc
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
}

# Instalación común para ambos sistemas
install_common() {
    log_info "Instalando dependencias Python comunes..."
    
    # Crear entorno virtual Python
    python3 -m venv ~/griddfs-env
    source ~/griddfs-env/bin/activate
    
    # Instalar dependencias Python
    pip install --upgrade pip
    pip install grpcio grpcio-tools protobuf click colorama
    
    log_info "Verificando instalaciones..."
    
    # Verificar Java
    java -version
    mvn -version
    
    # Verificar Python
    python3 --version
    
    # Verificar herramientas de compilación
    cmake --version || log_warning "CMake no disponible"
    protoc --version || log_warning "Protoc no disponible"
    
    log_info "✅ Instalación base completada"
}

# Función principal
main() {
    detect_os
    
    case "$OS" in
        *Ubuntu*)
            if [[ "$VER" == "22.04" ]]; then
                install_ubuntu
            else
                log_warning "Versión de Ubuntu no probada: $VER. Intentando instalación estándar..."
                install_ubuntu
            fi
            ;;
        *Amazon*Linux*)
            install_amazon_linux
            ;;
        *)
            log_error "Sistema operativo no soportado: $OS"
            log_error "Sistemas soportados: Ubuntu 22.04, Amazon Linux 2023"
            exit 1
            ;;
    esac
    
    install_common
    
    echo ""
    log_info "🎉 ¡Instalación base completada!"
    log_info "📋 Próximos pasos:"
    log_info "1. Clonar el repositorio: git clone https://github.com/Henao13/GridFS.git"
    log_info "2. Seguir las instrucciones específicas para cada componente"
    echo ""
}

# Ejecutar función principal
main "$@"