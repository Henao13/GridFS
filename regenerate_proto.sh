#!/bin/bash

echo "🔄 Regenerando archivos protobuf..."

# Activar entorno virtual de Python
cd Cliente
source ../venvs/grpc/bin/activate

# Regenerar protobuf para Python
echo "📁 Regenerando protobuf para Python..."
python -m grpc_tools.protoc \
    --proto_path=../Proto \
    --python_out=src/griddfs \
    --grpc_python_out=src/griddfs \
    ../Proto/griddfs.proto

echo "✓ Protobuf para Python regenerado"

# Regenerar protobuf para Java
echo "📁 Regenerando protobuf para Java..."
cd ../DataNode

# Crear directorio para los archivos generados si no existe
mkdir -p src/main/java

# Regenerar con protoc
protoc --proto_path=../Proto \
       --java_out=src/main/java \
       --grpc-java_out=src/main/java \
       --plugin=protoc-gen-grpc-java=/usr/local/bin/protoc-gen-grpc-java \
       ../Proto/griddfs.proto

echo "✓ Protobuf para Java regenerado"

# Regenerar protobuf para C++
echo "📁 Regenerando protobuf para C++..."
cd ../NameNode

# Crear directorio para los archivos generados si no existe
mkdir -p generated

# Regenerar con protoc
protoc --proto_path=../Proto \
       --cpp_out=generated \
       --grpc_out=generated \
       --plugin=protoc-gen-grpc=/usr/local/bin/grpc_cpp_plugin \
       ../Proto/griddfs.proto

echo "✓ Protobuf para C++ regenerado"

echo ""
echo "🎉 Todos los archivos protobuf han sido regenerados"
echo ""
echo "📋 Próximos pasos:"
echo "   1. Implementar servicios de autenticación en NameNode (C++)"
echo "   2. Recompilar DataNode: cd DataNode && mvn clean package"
echo "   3. Recompilar NameNode: cd NameNode/build && cmake .. && make"
echo "   4. Probar comandos de autenticación en Cliente"
