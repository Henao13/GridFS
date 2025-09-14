# 🗂️ GridFS - Sistema de Archivos Distribuido

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Language: C++](https://img.shields.io/badge/Language-C++-blue.svg)](https://isocpp.org/)
[![Language: Java](https://img.shields.io/badge/Language-Java-orange.svg)](https://www.java.com/)
[![Language: Python](https://img.shields.io/badge/Language-Python-green.svg)](https://www.python.org/)
[![gRPC](https://img.shields.io/badge/RPC-gRPC-lightblue.svg)](https://grpc.io/)

Un sistema de archivos distribuido implementado con **gRPC**, inspirado en **HDFS**, que permite almacenamiento distribuido de archivos con autenticación de usuarios y control de permisos.

## 🏗️ **Arquitectura del Sistema**

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  NameNode   │    │  DataNode 1 │    │  DataNode 2 │
│   (C++)     │◄──►│   (Java)    │    │   (Java)    │
│   Puerto    │    │   Puerto    │    │   Puerto    │
│   50050     │    │   50051     │    │   50051     │
└─────────────┘    └─────────────┘    └─────────────┘
       ▲                   ▲                   ▲
       │                   │                   │
       └───────────────────┼───────────────────┘
                           │
                  ┌─────────────┐
                  │   Cliente   │
                  │  (Python)   │
                  │     CLI     │
                  └─────────────┘
```

## 🚀 **Características Principales**

- 🔐 **Autenticación completa**: Sistema de registro y login de usuarios
- 👤 **Propiedad de archivos**: Control de acceso basado en propietario
- 🛡️ **Control de permisos**: Solo el propietario puede eliminar archivos
- 🔄 **DataNode resiliente**: Reconexión automática ante fallos
- 💾 **Sesiones persistentes**: Manejo de sesiones de usuario
- 📊 **Metadata rica**: Información completa de archivos (propietario, tamaño, fecha)
- ⚖️ **Balanceador de carga**: Distribución equitativa entre DataNodes
- 🔗 **Replicación**: Soporte para múltiples copias de archivos

## 📁 **Estructura del Proyecto**

```
GridFS/
├── Proto/
│   └── griddfs.proto                 # Definición de protocolos gRPC
├── NameNode/                         # Servidor de metadatos (C++)
│   └── src/
│       ├── main.cc                   # Punto de entrada
│       ├── namenode_server.h         # Headers del servidor
│       ├── namenode_server.cc        # Implementación del servidor
│       └── build/                    # Directorio de compilación
├── DataNode/                         # Servidores de almacenamiento (Java)
│   ├── src/main/java/
│   │   ├── DataNodeServer.java       # Servidor principal
│   │   └── BlockStorage.java         # Gestión de almacenamiento
│   └── pom.xml                       # Configuración Maven
├── Cliente/                          # Interfaz de usuario (Python)
│   └── src/
│       ├── cli.py                    # CLI principal
│       ├── namenode_client.py        # Cliente NameNode
│       └── datanode_client.py        # Cliente DataNode
├── scripts/                          # Scripts de despliegue automático
│   ├── install-namenode.sh          # Instalación NameNode
│   ├── install-datanode.sh          # Instalación DataNode
│   ├── install-client.sh            # Instalación Cliente
│   └── deploy-griddfs-aws.sh         # Despliegue completo en AWS
└── GUIA_DESPLIEGUE_AWS_EC2.md        # Guía completa de despliegue
```

## 🛠️ **Tecnologías Utilizadas**

- **NameNode**: C++17, gRPC, Protocol Buffers, CMake
- **DataNode**: Java 17, Maven, gRPC-Java
- **Cliente**: Python 3.8+, grpcio, click
- **Protocolo**: gRPC con Protocol Buffers
- **Despliegue**: Docker, AWS EC2, systemd

## 📋 **Prerrequisitos**

### NameNode (C++)
- g++ 11+
- CMake 3.16+
- Protocol Buffers 3.21+
- gRPC 1.60+

### DataNode (Java)
- OpenJDK 17+
- Maven 3.8+
- gRPC-Java 1.63+

### Cliente (Python)
- Python 3.8+
- grpcio
- protobuf

## 🚀 **Instalación Rápida**

### Opción 1: Scripts Automatizados (AWS EC2)
```bash
# Despliegue completo en AWS
chmod +x scripts/deploy-griddfs-aws.sh
./scripts/deploy-griddfs-aws.sh -k tu-keypair -r https://github.com/tu-usuario/GridFS.git

# O instalar componentes individualmente
curl -sSL https://raw.githubusercontent.com/tu-usuario/GridFS/main/scripts/install-namenode.sh | bash
curl -sSL https://raw.githubusercontent.com/tu-usuario/GridFS/main/scripts/install-datanode.sh | bash
curl -sSL https://raw.githubusercontent.com/tu-usuario/GridFS/main/scripts/install-client.sh | bash
```

### Opción 2: Instalación Manual

#### 1. Clonar el repositorio
```bash
git clone https://github.com/tu-usuario/GridFS.git
cd GridFS
```

#### 2. Compilar NameNode
```bash
cd NameNode/src
mkdir -p build && cd build
cmake ..
make -j$(nproc)
./namenode
```

#### 3. Compilar DataNode
```bash
cd DataNode
mvn clean compile
mvn clean package
java -jar target/datanode-1.0-SNAPSHOT.jar
```

#### 4. Configurar Cliente
```bash
cd Cliente/src
python3 -m venv venv
source venv/bin/activate
pip install grpcio grpcio-tools protobuf
python3 cli.py --help
```

## 📖 **Uso Básico**

### Comandos del Cliente
```bash
# Registrar nuevo usuario
python3 cli.py register usuario password

# Iniciar sesión
python3 cli.py login usuario password

# Subir archivo
python3 cli.py put archivo_local.txt /ruta/remota.txt

# Listar archivos
python3 cli.py list /

# Descargar archivo
python3 cli.py get /ruta/remota.txt archivo_descargado.txt

# Eliminar archivo (solo propietario)
python3 cli.py delete /ruta/remota.txt

# Crear directorio
python3 cli.py mkdir /nueva/carpeta
```

### Ejemplos de Uso
```bash
# Workflow completo
python3 cli.py register alice secreto123
python3 cli.py login alice secreto123
echo "Hola GridFS!" > saludo.txt
python3 cli.py put saludo.txt /docs/saludo.txt
python3 cli.py list /docs/
python3 cli.py get /docs/saludo.txt descargado.txt
cat descargado.txt  # Output: Hola GridFS!
```

## � **Despliegue en AWS EC2**

Ver la [**Guía Completa de Despliegue**](GUIA_DESPLIEGUE_AWS_EC2.md) para instrucciones detalladas de despliegue en AWS EC2, incluyendo:

- 🖥️ Configuración de instancias EC2
- � Security Groups y redes
- 🤖 Scripts de automatización
- 🔍 Monitoreo y troubleshooting
- 💰 Optimización de costos

## 🔧 **Desarrollo**

### Regenerar archivos Protocol Buffers
```bash
# Para C++
protoc --cpp_out=NameNode/src --grpc_out=NameNode/src --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` Proto/griddfs.proto

# Para Java
protoc --java_out=DataNode/src/main/java --grpc-java_out=DataNode/src/main/java --plugin=protoc-gen-grpc-java=`which protoc-gen-grpc-java` Proto/griddfs.proto

# Para Python
python3 -m grpc_tools.protoc --python_out=Cliente/src --grpc_python_out=Cliente/src --proto_path=Proto griddfs.proto
```

### Estructura de Puertos
- **NameNode**: Puerto 50050 (gRPC)
- **DataNode**: Puerto 50051 (gRPC)
- **Comunicación**: Interna entre componentes

## 🧪 **Testing**

```bash
# Probar conectividad
telnet localhost 50050  # NameNode
telnet localhost 50051  # DataNode

# Logs del sistema
journalctl -u griddfs-namenode -f   # NameNode logs
journalctl -u griddfs-datanode -f   # DataNode logs

# Verificar archivos almacenados
ls -la ~/griddfs-storage/           # DataNode storage
```

## 🤝 **Contribuir**

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
3. Commit tus cambios (`git commit -am 'Agregar nueva funcionalidad'`)
4. Push a la rama (`git push origin feature/nueva-funcionalidad`)
5. Abre un Pull Request

## 📄 **Licencia**

Este proyecto está bajo la Licencia MIT. Ver el archivo [LICENSE](LICENSE) para más detalles.

## 👨‍� **Autores**

- **Santiago** - Desarrollo principal - [@tu-usuario](https://github.com/tu-usuario)

## 🔗 **Enlaces Útiles**

- [gRPC Documentation](https://grpc.io/docs/)
- [Protocol Buffers](https://developers.google.com/protocol-buffers)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)

## ⭐ **Apoya el Proyecto**

Si este proyecto te ha sido útil, ¡dale una estrella en GitHub! ⭐

### **Para Usar:**
```bash
# 1. Compilar NameNode
cd NameNode/build && cmake .. && make

# 2. Compilar DataNode  
cd DataNode && mvn clean package

# 3. Usar cliente
cd Cliente
source /home/juanpa/venvs/grpc/bin/activate
python3 -m src.cli register juan
python3 -m src.cli register velez
python3 -m src.cli login juan
python3 -m src.cli login velez
python3 -m src.cli put archivo.txt
python3 -m src.cli ls
```

## 🎉 **PROYECTO LISTO PARA PRODUCCIÓN**

El sistema está **completo, limpio y optimizado** con:
- ✅ Código bien organizado
- ✅ Sin archivos obsoletos
- ✅ Documentación actualizada
- ✅ Funcionalidad completa de autenticación
- ✅ Sistema resiliente y robusto
