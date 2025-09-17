# GridDFS – Guía de despliegue en AWS (sin volumen adicional)

Esta guía explica cómo desplegar **GridDFS** en AWS usando **solo el volumen raíz** de la instancia (sin EBS adicional), cómo **actualizar** desde GitHub y cómo **arrancar** cada componente (NameNode, DataNodes, Cliente) después de cada actualización o reinicio.

Repositorio: [https://github.com/Henao13/GridFS](https://github.com/Henao13/GridFS)

---

## 0) Prerrequisitos

- Cuenta AWS con permisos para EC2.
- Una **Elastic IP** asociada a la instancia del **NameNode**.
- Un **Security Group único** para **todas** las instancias.
- Sistema operativo recomendado: **Amazon Linux 2023** en EC2.

## 1) Security Group (único para todo)

**Inbound**

- **22/tcp (SSH)**: tu IP (o 0.0.0.0/0 para pruebas, menos seguro).
- **50050/tcp (NameNode gRPC)**: 0.0.0.0/0 si el cliente estará fuera de AWS.
- **50051–50060/tcp (DataNodes gRPC)**: 0.0.0.0/0 si el cliente externo necesita hablar con los DataNodes.
- **(opcional recomendado)**: **Custom TCP 0–65535** con **source = este mismo security group** para permitir tráfico interno entre instancias sin abrir a internet.

**Outbound**

- Allow all (por defecto).

> Nota: puedes restringir 5005x a tus IPs para más seguridad.

## 2) NameNode en AWS (sin volumen adicional)

### 2.1 Conectarse por SSH

```bash
ssh -i ~/key.pem ec2-user@18.208.28.6 \ namenode
ssh -i ~/key.pem ec2-user@107.23.153.229 \ dn1
ssh -i ~/key.pem ec2-user@50.19.3.35 \ dn2
ssh -i ~/key.pem ec2-user@98.87.63.13 \ dn3
```

### 2.2 Dependencias del sistema (una sola vez)

```bash
sudo dnf update -y
sudo dnf install -y git cmake gcc-c++ \
    grpc grpc-devel grpc-plugins \
    protobuf protobuf-compiler protobuf-devel \
    openssl-devel c-ares-devel re2 re2-devel zlib-devel
```

### 2.3 Código: clonar o actualizar

**Si ya existe ****************************`~/griddfs`****************************:**

```bash
cd ~/griddfs
git fetch origin
git pull || true
# ajusta según rama principal de tu repo
(git checkout main 2>/dev/null || git checkout -b main origin/main) || \
(git checkout master 2>/dev/null || git checkout -b master origin/master)
```

**Si es la primera vez:**

```bash
cd ~
git clone https://github.com/Henao13/GridFS.git griddfs
cd griddfs
```

### 2.4 Compilar el NameNode

```bash
cd ~/griddfs/NameNode/src
mkdir -p build && cd build
cmake ..
make -j2
```

### 2.5 Configurar persistencia (en el volumen raíz)

```bash
sudo mkdir -p /var/lib/griddfs/meta
sudo chown ec2-user:ec2-user /var/lib/griddfs/meta
```

### 2.6 Ejecutar el NameNode

**Primer plano (para ver logs):**

```bash
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
cd ~/griddfs/NameNode/src/build
./namenode
```

**Segundo plano (producción/pruebas):**

```bash
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
cd ~/griddfs/NameNode/src/build
nohup ./namenode > ~/namenode.log 2>&1 &
echo $! > ~/namenode.pid
```

**Verificación:**

```bash
ss -ltnp | grep 50050
 tail -n 50 ~/namenode.log
```

> El NameNode escribe la metadata en `GRIDDFS_META_DIR` (por ejemplo `/var/lib/griddfs/meta/fsimage.txt`).

## 3) DataNodes (3 instancias separadas)

### 3.1 Dependencias

```bash
sudo dnf update -y
sudo dnf install -y java-17-amazon-corretto-headless git
```

### 3.2 Código: clonar o actualizar

```bash
# si no existe
cd ~ && git clone https://github.com/Henao13/GridFS.git griddfs
# si ya existe
yes | true  # (no hace nada; placeholder)
cd ~/griddfs
git fetch origin
git pull || true
```

### 3.3 Construir DataNode (Maven Wrapper en el repo)

```bash
cd ~/griddfs/DataNode
./mvnw -q -DskipTests package   # o: mvn -q -DskipTests package
```

### 3.4 Arrancar cada DataNode

> Usa **la IP pública del NameNode** y el **puerto 50050**.

**DN1**

```bash
cd ~/griddfs/DataNode
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar \
  50051 /tmp/datanode1 datanode1 18.208.28.6 50050 &
```

**DN2**

```bash
cd ~/griddfs/DataNode
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar \
  50052 /tmp/datanode2 datanode2 18.208.28.6 50050 &
```

**DN3**

```bash
cd ~/griddfs/DataNode
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar \
  50053 /tmp/datanode3 datanode3 18.208.28.6 50050 &
```

**Notas**

- Si quieres persistir bloques en disco (opcional), crea rutas como `/var/lib/griddfs/blocks1`, `/blocks2`, `/blocks3` y cámbialas en los comandos en lugar de `/tmp/datanodeX`.
- El NameNode ya corrige registros `localhost` → IP real gracias al handler.

## 4) Cliente (tu PC)

Ejemplos (Windows PowerShell) desde `Proyecto 1/Cliente`:

```powershell
python -m src.cli --namenode 18.208.28.6:50050 register usuario1
python -m src.cli --namenode 18.208.28.6:50050 login usuario1
python -m src.cli --namenode 18.208.28.6:50050 mkdir /docs
python -m src.cli --namenode 18.208.28.6:50050 ls /
# subir/descargar
python -m src.cli --namenode 18.208.28.6:50050 put .\archivo.txt
python -m src.cli --namenode 18.208.28.6:50050 get /archivo.txt
```

> El CLI guarda sesión y directorio de trabajo en archivos `~/.griddfs_session_*` y `~/.griddfs_workdir_*`.

## 5) Actualizar desde GitHub + reconstruir

### 5.1 NameNode (redeploy)

```bash
cd ~/griddfs
git fetch origin
git pull || true
# Asegura rama principal (main o master)
(git checkout main 2>/dev/null || git checkout -b main origin/main) || \
(git checkout master 2>/dev/null || git checkout -b master origin/master)

cd NameNode/src/build
cmake ..
make -j2

# reiniciar proceso
pkill -f "/namenode" || true
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
nohup ./namenode > ~/namenode.log 2>&1 &
echo $! > ~/namenode.pid
ss -ltnp | grep 50050
```

**Script opcional (********`~/redeploy-nn.sh`********\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*):**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/griddfs
git fetch origin
git pull || true
(git checkout main 2>/dev/null || git checkout -b main origin/main) || \
(git checkout master 2>/dev/null || git checkout -b master origin/master)
cd NameNode/src/build
cmake ..
make -j2
pkill -f "/namenode" || true
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
nohup ./namenode > ~/namenode.log 2>&1 &
echo $! > ~/namenode.pid
sleep 1
ss -ltnp | grep 50050 || { echo "NN no levantó"; exit 1; }
echo "NameNode redeploy OK. PID=$(cat ~/namenode.pid)"
```

### 5.2 DataNodes (actualización)

En **cada** DN:

```bash
cd ~/griddfs
git fetch origin
git pull || true
cd DataNode
./mvnw -q -DskipTests package
# reinicia el proceso según tu preferencia (matar y arrancar de nuevo)
```

## 6) Arranque tras reinicio de instancias

### NameNode

```bash
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
cd ~/griddfs/NameNode/src/build
nohup ./namenode > ~/namenode.log 2>&1 &
```

### DataNodes

```bash
cd ~/griddfs/DataNode
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50051 /tmp/datanode1 datanode1 18.208.28.6 50050 &
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50052 /tmp/datanode2 datanode2 18.208.28.6 50050 &
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50053 /tmp/datanode3 datanode3 18.208.28.6 50050 &
```

## 7) Troubleshooting rápido

- **El cliente no lista nada / error de conexión**: verifica que el SG permita 50050/tcp y que el NN esté escuchando.
- **El NN muestra \*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*****`unknown DataNode`**: el DN no se ha registrado; revisa comandos y SG en puertos 50051–50053.
- **El NN registra \*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*****`addr=localhost:5005x`**: con el handler nuevo, se corrige a la IP del peer; asegúrate de usar la **IP pública del NN** en los comandos de los DN.
- **Errores de build**: verifica dependencias `grpc`, `protobuf`, `cmake`, etc. Repite `cmake .. && make -j2` en `NameNode/src/build`.
- **Persistencia**: confirma que exista `/var/lib/griddfs/meta/fsimage.txt` y que se actualice al crear usuarios/archivos/dirs.

## 8) Checklist de despliegue

-

---

**Listo.** Con esto tienes despliegue sin volumen adicional, actualización desde GitHub y comandos de arranque para cada componente.

