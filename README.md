# GridDFS

Sistema de archivos distribuido (NameNode C++, DataNodes Java, Cliente Python) con autenticación, replicación y distribución de bloques. Este README ha sido simplificado para dejar solo los pasos esenciales de despliegue y uso.

## Arquitectura (visión rápida)

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  NameNode   │    │  DataNode 1 │    │  DataNode 2 │
│   (C++)     │◄──►│   (Java)    │    │   (Java)    │
│   Puerto    │    │   Puerto    │    │   Puerto    │
│   50050     │    │   50051     │    │   50052     │
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

## Características básicas

- Autenticación (registro / login / sesiones persistentes)
- Propiedad y control de eliminación por dueño
- Replicación de bloques y selección de DataNodes (HRW)
- CLI simple para operaciones de archivos

## Estructura

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

## Prerrequisitos mínimos

NameNode: g++/clang, cmake, protobuf, gRPC
DataNode: Java 17 + Maven (o wrapper ./mvnw)
Cliente: Python 3 + grpcio + protobuf

## Despliegue esencial (AWS sin volumen extra)

### NameNode (EC2 Amazon Linux)
```bash
sudo dnf install -y git cmake gcc-c++ grpc grpc-devel grpc-plugins \
       protobuf protobuf-compiler protobuf-devel openssl-devel c-ares-devel re2 re2-devel zlib-devel
git clone https://github.com/Henao13/GridFS.git griddfs || (cd griddfs && git pull)
cd ~/griddfs/NameNode/src && mkdir -p build && cd build && cmake .. && make -j2
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
sudo mkdir -p "$GRIDDFS_META_DIR" && sudo chown $USER:$USER "$GRIDDFS_META_DIR"
./namenode
```

### DataNode (cada instancia)
```bash
sudo dnf install -y java-17-amazon-corretto-headless git
git clone https://github.com/Henao13/GridFS.git griddfs || (cd griddfs && git pull)
cd ~/griddfs/DataNode && ./mvnw -q -DskipTests package
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50051 /tmp/dn1 datanode1 <IP_PUBLICA_NN> 50050 &
```

Para más nodos cambia el primer puerto, carpeta y nombre:
```bash
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50052 /tmp/dn2 datanode2 <IP_PUBLICA_NN> 50050 &
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50053 /tmp/dn3 datanode3 <IP_PUBLICA_NN> 50050 &
```

### Cliente (tu máquina)
```bash
cd Cliente
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 register usuario1
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 login usuario1
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 mkdir /docs
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 put ejemplo.txt /docs/ejemplo.txt
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 ls /docs
```

## Uso rápido (resumen CLI)
```bash
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 register usuario
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 login usuario
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 put archivo.txt /archivo.txt
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 mkdir /carpeta
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 ls /carpeta
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 get /archivo.txt
```

## Actualizar versión (redeploy rápido NameNode)
```bash
cd ~/griddfs && git pull || true
cd NameNode/src/build && cmake .. && make -j2
pkill -f /namenode || true
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
nohup ./namenode > ~/namenode.log 2>&1 &
```

## Regenerar proto (si cambia)
```bash
# C++
protoc --cpp_out=NameNode/src --grpc_out=NameNode/src --plugin=protoc-gen-grpc=`which grpc_cpp_plugin` Proto/griddfs.proto
# Java
protoc --java_out=DataNode/src/main/java --grpc-java_out=DataNode/src/main/java --plugin=protoc-gen-grpc-java=`which protoc-gen-grpc-java` Proto/griddfs.proto
# Python
python -m grpc_tools.protoc --python_out=Cliente/src --grpc_python_out=Cliente/src --proto_path=Proto griddfs.proto
```

### Estructura de Puertos
- **NameNode**: Puerto 50050 (gRPC)
- **DataNode**: Puerto 50051 (gRPC)
- **Comunicación**: Interna entre componentes

## Verificación rápida
```bash
ss -ltnp | grep 50050   # NameNode
ss -ltnp | grep 5005    # DataNodes
tail -n 50 ~/namenode.log
```

## Autores:
- Santiago Henao, Juan Pablo Jiménez, Santiago Vélez


