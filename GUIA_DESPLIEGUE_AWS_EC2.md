# 🚀 Guía Completa de Despliegue GridDFS en AWS EC2

## 📋 Índice
1. [Arquitectura del Sistema](#arquitectura-del-sistema)
2. [Configuración de Instancias EC2](#configuración-de-instancias-ec2)
3. [Configuración de Security Groups](#configuración-de-security-groups)
4. [Instalación NameNode (C++)](#instalación-namenode-c)
5. [Instalación DataNode (Java)](#instalación-datanode-java)
6. [Instalación Cliente (Python)](#instalación-cliente-python)
7. [Scripts de Automatización]# Verificar funcionamiento
```bash
# Activar entorno virtual
source ~/griddfs-client/bin/activate

# Navegar al directorio correcto
cd ~/griddfs/Cliente/src

# Probar conexión al NameNode
python3 cli.py --help

# Intentar listar archivos (debe conectar sin errores)
python3 cli.py list /
```

---

## 🤖 Scripts de Automatización

He creado scripts automatizados para facilitar la instalación. Estos scripts están disponibles en el directorio `scripts/` del proyecto.

### Script de Instalación NameNode
```bash
# En la instancia NameNode
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-namenode.sh | bash

# O descarga y ejecuta localmente
wget https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-namenode.sh
chmod +x install-namenode.sh
./install-namenode.sh
```

### Script de Instalación DataNode
```bash
# En cada instancia DataNode
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-datanode.sh | bash

# O con configuración personalizada
NAMENODE_HOST=172.31.x.x curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-datanode.sh | bash
```

### Script de Instalación Cliente
```bash
# En la instancia cliente
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-client.sh | bash

# O con configuración personalizada
NAMENODE_HOST=ip-publica-namenode DATANODE_HOST=ip-publica-datanode curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-client.sh | bash
```

### Instalación Manual (Alternativa)

Si prefieres subir los archivos manualmente, puedes usar `scp`:

```bash
# Desde tu máquina local, subir archivos al servidor
scp -i tu-keypair.pem -r ./Proyecto\ 1/* ubuntu@<IP_INSTANCIA>:~/griddfs/

# Luego ejecutar los scripts localmente en cada instancia
```

---

## 🌐 Configuración de Red y Comunicación

### IPs y Puertos

#### IPs Privadas vs Públicas
- **IPs Privadas**: Para comunicación interna entre componentes del sistema
- **IPs Públicas**: Para acceso desde internet (cliente externo)

```
NameNode:
  - IP Privada: 172.31.x.x (comunicación interna)
  - IP Pública: x.x.x.x (acceso cliente)
  - Puerto: 50050

DataNodes:
  - IP Privada: 172.31.y.y (comunicación interna)
  - IP Pública: y.y.y.y (acceso cliente)
  - Puerto: 50051
```

### Configuración de Direcciones

#### En el Código del DataNode
El DataNode necesita conocer la IP **privada** del NameNode:
```bash
# En datanode.env
NAMENODE_HOST=172.31.x.x  # IP PRIVADA del NameNode
NAMENODE_PORT=50050
```

#### En el Cliente
El cliente puede usar IPs **públicas** para acceso externo:
```bash
# En client.env
NAMENODE_HOST=54.x.x.x    # IP PÚBLICA del NameNode
DATANODE_HOST=54.y.y.y    # IP PÚBLICA de un DataNode
```

### Tabla de Puertos

| Componente | Puerto | Protocolo | Propósito |
|------------|--------|-----------|-----------|
| NameNode | 50050 | gRPC/TCP | API de metadatos |
| DataNode | 50051 | gRPC/TCP | API de almacenamiento |
| SSH | 22 | TCP | Administración |

### Security Groups Detallados

#### Regla para Comunicación Interna (Mismo VPC)
```bash
# NameNode hacia DataNodes
Source: sg-griddfs (puerto 50051)

# DataNodes hacia NameNode  
Source: sg-griddfs (puerto 50050)

# SSH para administración
Source: 0.0.0.0/0 (puerto 22)
```

#### Regla para Clientes Externos
```bash
# Clientes hacia NameNode
Source: Tu_IP/32 (puerto 50050)

# Clientes hacia DataNodes  
Source: Tu_IP/32 (puerto 50051)
```

### Comando para Obtener IPs

```bash
# IP Privada (dentro de la instancia)
curl http://169.254.169.254/latest/meta-data/local-ipv4

# IP Pública (dentro de la instancia)
curl http://169.254.169.254/latest/meta-data/public-ipv4

# Desde AWS CLI (externo)
aws ec2 describe-instances --filters "Name=tag:Name,Values=griddfs-namenode" --query 'Reservations[*].Instances[*].[PublicIpAddress,PrivateIpAddress]' --output table
```

---

## 🚀 Guía de Despliegue Completo

### Orden de Despliegue

1. **NameNode** (primero)
2. **DataNodes** (después del NameNode)
3. **Cliente** (último)

### Paso a Paso Completo

#### 1. Crear Instancias EC2

```bash
# Crear NameNode
aws ec2 run-instances \
    --image-id ami-0c02fb55956c7d316 \
    --count 1 \
    --instance-type t3.small \
    --key-name tu-keypair \
    --security-groups griddfs-sg \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=griddfs-namenode}]'

# Crear DataNodes (repetir para cada uno)
aws ec2 run-instances \
    --image-id ami-0c02fb55956c7d316 \
    --count 2 \
    --instance-type t3.medium \
    --key-name tu-keypair \
    --security-groups griddfs-sg \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=griddfs-datanode}]'

# Crear Cliente (opcional)
aws ec2 run-instances \
    --image-id ami-0c02fb55956c7d316 \
    --count 1 \
    --instance-type t3.micro \
    --key-name tu-keypair \
    --security-groups griddfs-sg \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=griddfs-client}]'
```

#### 2. Configurar NameNode (Instancia Principal)

```bash
# Conectar a NameNode
ssh -i tu-keypair.pem ubuntu@<IP_NAMENODE>

# Instalar usando el script automatizado
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-namenode.sh | bash

# O subir archivos manualmente
# scp -i tu-keypair.pem -r ./Proyecto\ 1/* ubuntu@<IP_NAMENODE>:~/griddfs/

# Iniciar servicio
sudo systemctl start griddfs-namenode

# Verificar
sudo systemctl status griddfs-namenode
sudo journalctl -u griddfs-namenode -f
```

#### 3. Configurar DataNodes

Para cada DataNode:

```bash
# Obtener IP privada del NameNode
NAMENODE_PRIVATE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=griddfs-namenode" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)

# Conectar a DataNode
ssh -i tu-keypair.pem ubuntu@<IP_DATANODE>

# Instalar con configuración
NAMENODE_HOST=$NAMENODE_PRIVATE_IP curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-datanode.sh | bash

# Iniciar servicio
sudo systemctl start griddfs-datanode

# Verificar
sudo systemctl status griddfs-datanode
sudo journalctl -u griddfs-datanode -f
```

#### 4. Configurar Cliente

```bash
# Obtener IPs públicas
NAMENODE_PUBLIC_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=griddfs-namenode" --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)
DATANODE_PUBLIC_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=griddfs-datanode" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# Conectar a Cliente
ssh -i tu-keypair.pem ubuntu@<IP_CLIENTE>

# Instalar con configuración
NAMENODE_HOST=$NAMENODE_PUBLIC_IP DATANODE_HOST=$DATANODE_PUBLIC_IP curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-client.sh | bash
```

### Verificación del Sistema Completo

#### 1. Verificar NameNode
```bash
# En la instancia NameNode
sudo systemctl status griddfs-namenode
ss -tlnp | grep 50050
```

#### 2. Verificar DataNodes
```bash
# En cada instancia DataNode
sudo systemctl status griddfs-datanode
ss -tlnp | grep 50051
```

#### 3. Verificar Conectividad
```bash
# Desde cliente
griddfs-control test

# Desde cualquier instancia
telnet <IP_NAMENODE> 50050
telnet <IP_DATANODE> 50051
```

#### 4. Pruebas Funcionales
```bash
# En el cliente
source ~/.bashrc

# Registrar usuario
griddfs register testuser testpass

# Iniciar sesión
griddfs login testuser testpass

# Crear archivo de prueba
echo "Hola GridDFS" > test.txt

# Subir archivo
griddfs put test.txt /test.txt

# Listar archivos
griddfs list /

# Descargar archivo
griddfs get /test.txt downloaded.txt

# Verificar contenido
cat downloaded.txt
```

### Monitoreo y Logs

#### NameNode
```bash
# Ver logs
sudo journalctl -u griddfs-namenode -f

# Ver procesos
ps aux | grep namenode

# Ver conexiones
ss -tlnp | grep 50050
```

#### DataNode
```bash
# Ver logs
sudo journalctl -u griddfs-datanode -f

# Ver procesos
ps aux | grep java

# Ver almacenamiento
ls -la ~/griddfs-storage/
```

---

## 🔧 Troubleshooting

### Problemas Comunes

#### 1. NameNode no inicia
```bash
# Verificar logs
sudo journalctl -u griddfs-namenode -n 50

# Verificar ejecutable
ls -la ~/griddfs/NameNode/src/build/namenode

# Recompilar si es necesario
cd ~/griddfs/NameNode/src/build
make -j$(nproc)
```

#### 2. DataNode no se conecta al NameNode
```bash
# Verificar configuración
cat ~/griddfs/DataNode/datanode.env

# Probar conectividad
telnet $NAMENODE_HOST $NAMENODE_PORT

# Verificar Security Groups
# - Puerto 50050 debe estar abierto entre DataNode y NameNode
```

#### 3. Cliente no puede conectar
```bash
# Verificar configuración
griddfs-control config

# Probar conectividad
griddfs-control test

# Verificar IPs públicas
curl http://checkip.amazonaws.com
```

#### 4. Errores de compilación

**NameNode (C++)**:
```bash
# Verificar dependencias
protoc --version
cmake --version
g++ --version

# Limpiar y recompilar
cd ~/griddfs/NameNode/src/build
rm -rf *
cmake ..
make -j$(nproc)
```

**DataNode (Java)**:
```bash
# Verificar Java
java -version
mvn -version

# Limpiar y recompilar
cd ~/griddfs/DataNode
mvn clean compile
mvn clean package
```

#### 5. Problemas de permisos
```bash
# Dar permisos a directorios
sudo chown -R $USER:$USER ~/griddfs
chmod +x ~/griddfs/NameNode/src/build/namenode

# Permisos de almacenamiento
sudo chown -R $USER:$USER ~/griddfs-storage
```

### Comandos de Diagnóstico

```bash
# Ver todos los procesos GridDFS
ps aux | grep -E "(namenode|datanode|cli.py)"

# Ver puertos abiertos
ss -tlnp | grep -E "(50050|50051)"

# Ver conexiones activas
netstat -an | grep -E "(50050|50051)"

# Ver espacio en disco
df -h

# Ver logs del sistema
dmesg | tail -20

# Ver estado de servicios
systemctl status griddfs-namenode
systemctl status griddfs-datanode
```

### Reinicio Completo del Sistema

```bash
# En NameNode
sudo systemctl restart griddfs-namenode

# En cada DataNode
sudo systemctl restart griddfs-datanode

# Verificar orden de inicio (NameNode primero, luego DataNodes)
sleep 10 && sudo systemctl status griddfs-namenode
sleep 5 && sudo systemctl status griddfs-datanode
```

---

## 🎯 Resumen y Próximos Pasos

### ✅ Lo que hemos logrado:

1. **Configuración completa de AWS EC2** con Security Groups
2. **Scripts de instalación automatizada** para cada componente
3. **Servicios systemd** para gestión automática
4. **Scripts de control** para operaciones comunes
5. **Configuración de red** optimizada para AWS
6. **Guía de troubleshooting** completa

### 📚 Documentación adicional:

- Todos los scripts están en `/scripts/`
- Configuración en archivos `.env`
- Logs disponibles con `journalctl`
- Scripts de control con aliases amigables

### 🚀 Para empezar:

1. Sigue el orden: NameNode → DataNodes → Cliente
2. Usa los scripts de automatización
3. Verifica cada paso antes de continuar
4. Monitorea los logs durante el despliegue

### 📞 Soporte:

- Revisa la sección de Troubleshooting
- Usa los comandos de diagnóstico
- Verifica Security Groups y conectividad
- Consulta los logs de systemd

¡Tu sistema GridDFS debería estar funcionando completamente en AWS EC2! 🎉utomatización)
8. [Despliegue y Verificación](#despliegue-y-verificación)
9. [Troubleshooting](#troubleshooting)

---

## 🏗️ Arquitectura del Sistema

### Componentes
- **1 NameNode**: Servidor de metadatos (C++/gRPC) - Puerto 50050
- **N DataNodes**: Servidores de almacenamiento (Java/gRPC) - Puerto 50051
- **Clientes**: Interfaces de acceso (Python) - Conecta a ambos tipos de servidor

### Distribución Recomendada
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   NameNode      │    │   DataNode 1    │    │   DataNode 2    │
│   Ubuntu 22.04  │    │   Ubuntu 22.04  │    │   Ubuntu 22.04  │
│   t3.small      │    │   t3.medium     │    │   t3.medium     │
│   Port: 50050   │    │   Port: 50051   │    │   Port: 50051   │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   Cliente       │
                    │   Ubuntu 22.04  │
                    │   t3.micro      │
                    └─────────────────┘
```

---

## 🖥️ Configuración de Instancias EC2

### Especificaciones por Componente

#### NameNode (Servidor de Metadatos)
- **AMI**: Ubuntu Server 22.04 LTS
- **Tipo de Instancia**: t3.small (2 vCPU, 2 GB RAM)
- **Almacenamiento**: 20 GB GP3
- **Nombre sugerido**: `griddfs-namenode`

#### DataNode (Servidores de Almacenamiento)
- **AMI**: Ubuntu Server 22.04 LTS
- **Tipo de Instancia**: t3.medium (2 vCPU, 4 GB RAM)
- **Almacenamiento**: 50 GB GP3 (para datos del sistema de archivos)
- **Nombre sugerido**: `griddfs-datanode-1`, `griddfs-datanode-2`, etc.

#### Cliente (Opcional - para pruebas)
- **AMI**: Ubuntu Server 22.04 LTS
- **Tipo de Instancia**: t3.micro (1 vCPU, 1 GB RAM)
- **Almacenamiento**: 15 GB GP3
- **Nombre sugerido**: `griddfs-client`

### Pasos para Crear las Instancias

1. **Accede a la Consola AWS EC2**
   ```bash
   https://console.aws.amazon.com/ec2/
   ```

2. **Launch Instance**
   - Application and OS Images: Ubuntu Server 22.04 LTS (HVM)
   - Architecture: 64-bit (x86)

3. **Key Pair**
   - Crear o seleccionar un key pair existente
   - Descargar el archivo .pem y guardarlo seguro

4. **Network Settings**
   - Crear un nuevo Security Group o usar el que crearemos a continuación

---

## 🔒 Configuración de Security Groups

### Security Group: `griddfs-sg`

#### Reglas de Entrada (Inbound Rules)

| Type | Protocol | Port Range | Source | Descripción |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | 0.0.0.0/0 | Acceso SSH desde cualquier lugar |
| Custom TCP | TCP | 50050 | sg-xxxxx (mismo SG) | NameNode gRPC (interno) |
| Custom TCP | TCP | 50051 | sg-xxxxx (mismo SG) | DataNode gRPC (interno) |
| Custom TCP | TCP | 50050 | Tu IP/32 | NameNode acceso desde tu IP |
| Custom TCP | TCP | 50051 | Tu IP/32 | DataNode acceso desde tu IP |

#### Reglas de Salida (Outbound Rules)
- **All traffic** a **0.0.0.0/0** (mantener la regla por defecto)

### Comandos AWS CLI (Opcional)
```bash
# Crear Security Group
aws ec2 create-security-group \
    --group-name griddfs-sg \
    --description "Security group for GridDFS distributed file system"

# Obtener tu IP pública
MY_IP=$(curl -s http://checkip.amazonaws.com)/32

# Agregar reglas SSH
aws ec2 authorize-security-group-ingress \
    --group-name griddfs-sg \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Agregar reglas gRPC internas
aws ec2 authorize-security-group-ingress \
    --group-name griddfs-sg \
    --protocol tcp \
    --port 50050 \
    --source-group griddfs-sg

aws ec2 authorize-security-group-ingress \
    --group-name griddfs-sg \
    --protocol tcp \
    --port 50051 \
    --source-group griddfs-sg

# Agregar reglas de acceso externo
aws ec2 authorize-security-group-ingress \
    --group-name griddfs-sg \
    --protocol tcp \
    --port 50050 \
    --cidr $MY_IP

aws ec2 authorize-security-group-ingress \
    --group-name griddfs-sg \
    --protocol tcp \
    --port 50051 \
    --cidr $MY_IP
```

---

## ⚙️ Instalación Base (Todas las Instancias)

### Conectar a las Instancias
```bash
# Cambiar permisos del key pair
chmod 400 tu-keypair.pem

# Conectar via SSH
ssh -i tu-keypair.pem ubuntu@<IP_PUBLICA_INSTANCIA>
```

### Actualizar Sistema
```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y curl wget git build-essential
```

### Instalación de Dependencias Comunes
```bash
# Herramientas de desarrollo
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
    libtool

# Protobuf y gRPC dependencies
sudo apt install -y \
    libprotobuf-dev \
    protobuf-compiler \
    libgrpc-dev \
    libgrpc++-dev \
    protobuf-compiler-grpc
```

---

## 🏢 Instalación NameNode (C++)

### En la Instancia NameNode

#### 1. Instalar Dependencias Específicas de C++
```bash
# Compilador C++ y herramientas de desarrollo
sudo apt install -y \
    g++ \
    cmake \
    make \
    ninja-build

# Dependencias gRPC para C++ (instalación desde fuente si es necesaria)
sudo apt install -y \
    libabsl-dev \
    libre2-dev \
    libssl-dev \
    zlib1g-dev

# Verificar instalación
protoc --version  # Debe mostrar libprotoc 3.x.x
cmake --version   # Debe mostrar cmake 3.x.x
g++ --version     # Debe mostrar g++ 11.x.x o superior
```

#### 2. Clonar y Configurar el Proyecto
```bash
# Crear directorio de trabajo
mkdir -p ~/griddfs
cd ~/griddfs

# Clonar tu repositorio (reemplaza con tu repo)
git clone https://github.com/Henao13/GridFS.git .

# O subir archivos manualmente
# scp -i tu-keypair.pem -r ./GridFS/* ubuntu@<IP_NAMENODE>:~/griddfs/
```

#### 3. Compilar NameNode
```bash
cd ~/griddfs/NameNode/src

# Crear directorio build si no existe
mkdir -p build
cd build

# Configurar cmake
cmake ..

# Compilar
make -j$(nproc)

# Verificar que se creó el ejecutable
ls -la namenode
```

#### 4. Configurar NameNode como Servicio
```bash
# Crear archivo de servicio
sudo tee /etc/systemd/system/griddfs-namenode.service > /dev/null <<EOF
[Unit]
Description=GridDFS NameNode Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/griddfs/NameNode/src/build
ExecStart=/home/ubuntu/griddfs/NameNode/src/build/namenode
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Habilitar y comenzar el servicio
sudo systemctl daemon-reload
sudo systemctl enable griddfs-namenode
sudo systemctl start griddfs-namenode

# Verificar estado
sudo systemctl status griddfs-namenode
```

#### 5. Verificar Funcionamiento
```bash
# Ver logs del servicio
sudo journalctl -u griddfs-namenode -f

# Verificar que está escuchando en el puerto
ss -tlnp | grep 50050

# Test básico de conectividad
telnet localhost 50050
```

---

## ☕ Instalación DataNode (Java)

### En cada Instancia DataNode

#### 1. Instalar Java y Maven
```bash
# Instalar OpenJDK 17
sudo apt install -y openjdk-17-jdk openjdk-17-jre

# Instalar Maven
sudo apt install -y maven

# Configurar JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Verificar instalación
java -version    # Debe mostrar openjdk 17.x.x
mvn -version     # Debe mostrar Apache Maven 3.x.x
echo $JAVA_HOME  # Debe mostrar /usr/lib/jvm/java-17-openjdk-amd64
```

#### 2. Clonar y Configurar el Proyecto
```bash
# Crear directorio de trabajo
mkdir -p ~/griddfs
cd ~/griddfs

# Clonar tu repositorio
git clone https://github.com/Henao13/GridFS.git .

# O subir archivos manualmente
# scp -i tu-keypair.pem -r ./GridFS/* ubuntu@<IP_DATANODE>:~/griddfs/
```

#### 3. Compilar DataNode
```bash
cd ~/griddfs/DataNode

# Limpiar y compilar
mvn clean compile
mvn clean package

# Verificar que se creó el JAR
ls -la target/datanode-1.0-SNAPSHOT.jar
```

#### 4. Configurar Variables de Entorno
```bash
# Crear archivo de configuración
tee ~/griddfs/DataNode/datanode.env > /dev/null <<EOF
# Configuración DataNode
NAMENODE_HOST=<IP_PRIVADA_NAMENODE>
NAMENODE_PORT=50050
DATANODE_PORT=50051
DATANODE_ID=datanode-$(hostname)
DATANODE_STORAGE_PATH=/home/ubuntu/griddfs-storage
EOF

# Crear directorio de almacenamiento
mkdir -p /home/ubuntu/griddfs-storage
```

#### 5. Configurar DataNode como Servicio
```bash
# Crear archivo de servicio
sudo tee /etc/systemd/system/griddfs-datanode.service > /dev/null <<EOF
[Unit]
Description=GridDFS DataNode Server
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/griddfs/DataNode
EnvironmentFile=/home/ubuntu/griddfs/DataNode/datanode.env
ExecStart=/usr/bin/java -jar target/datanode-1.0-SNAPSHOT.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Habilitar y comenzar el servicio
sudo systemctl daemon-reload
sudo systemctl enable griddfs-datanode
sudo systemctl start griddfs-datanode

# Verificar estado
sudo systemctl status griddfs-datanode
```

#### 6. Verificar Funcionamiento
```bash
# Ver logs del servicio
sudo journalctl -u griddfs-datanode -f

# Verificar que está escuchando en el puerto
ss -tlnp | grep 50051

# Verificar archivos de almacenamiento
ls -la /home/ubuntu/griddfs-storage/
```

---

## 🐍 Instalación Cliente (Python)

### En la Instancia Cliente (o tu máquina local)

#### 1. Instalar Python y Dependencias
```bash
# Instalar Python 3 y pip
sudo apt install -y python3 python3-pip python3-venv

# Crear entorno virtual
python3 -m venv ~/griddfs-client
source ~/griddfs-client/bin/activate

# Actualizar pip
pip install --upgrade pip
```

#### 2. Instalar Dependencias Python
```bash
# Instalar dependencias gRPC para Python
pip install \
    grpcio \
    grpcio-tools \
    protobuf

# Otras dependencias que puedas necesitar
pip install \
    requests \
    click \
    colorama
```

#### 3. Configurar Cliente
```bash
# Crear directorio de trabajo
mkdir -p ~/griddfs
cd ~/griddfs

# Clonar tu repositorio
git clone https://github.com/Henao13/GridFS.git .

# Navegar al directorio del cliente
cd ~/griddfs/Cliente/src

# Verificar que los archivos proto están generados
ls -la griddfs/
```

#### 4. Configurar Variables de Conexión
```bash
# Crear archivo de configuración
tee ~/griddfs/Cliente/client.env > /dev/null <<EOF
# Configuración Cliente GridDFS
NAMENODE_HOST=<IP_PUBLICA_NAMENODE>
NAMENODE_PORT=50050
DEFAULT_DATANODE_HOST=<IP_PUBLICA_DATANODE1>
DEFAULT_DATANODE_PORT=50051
EOF

# Cargar variables
source ~/griddfs/Cliente/client.env
```

#### 5. Crear Script de Ejecución
```bash
# Crear script ejecutable
tee ~/griddfs/Cliente/run_client.sh > /dev/null <<'EOF'
#!/bin/bash

# Activar entorno virtual
source ~/griddfs-client/bin/activate

# Cargar configuración
source ~/griddfs/Cliente/client.env

# Ejecutar cliente
cd ~/griddfs/Cliente/src
python3 cli.py "$@"
EOF

# Hacer ejecutable
chmod +x ~/griddfs/Cliente/run_client.sh

# Crear alias para facilidad de uso
echo 'alias griddfs="~/griddfs/Cliente/run_client.sh"' >> ~/.bashrc
source ~/.bashrc
```

#### 6. Verificar Funcionamiento
```bash
# Activar entorno virtual
source ~/griddfs-client/bin/activate

# Navegar al directorio correcto
cd ~/griddfs/Cliente/src

# Probar conexión al NameNode
python3 cli.py --help

# Intentar listar archivos (debe conectar sin errores)
python3 cli.py list /
```
```
