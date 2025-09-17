¡De una! Aquí tienes **todo el paso a paso en AWS** considerando la **persistencia del NameNode**, el **git pull** y la **reconstrucción**.

# 1) Infraestructura en AWS (resumen rápido)

* **Instancias**: 1×NameNode (Amazon Linux 2023) + 3×DataNode (Amazon Linux 2023).
* **Elastic IP (EIP)**: así tu NameNode mantiene IP pública estable.
* **Volumen EBS extra** en el **NameNode** para persistir la metadata (`/var/lib/griddfs/meta`).
* **Security Group único** para **todas** las instancias:

  * **Inbound**

    * 22/tcp: desde tu IP (o 0.0.0.0/0 si quieres “cualquiera”, *menos seguro*).
    * 50050/tcp (NameNode): 0.0.0.0/0 si quieres acceso público al NN (o solo tus IPs).
    * 50051-50060/tcp (DataNodes): 0.0.0.0/0 si el cliente externo necesita llegar a DNs (tu cliente se conecta a DNs). Alternativa más segura: tus IPs + “desde este SG” para tráfico entre nodos.
  * **Outbound**: “All traffic” permitido (por defecto).

> Consejo: agrega una regla **Custom TCP 0-65535, source: “este security group”** para permitir que las instancias hablen entre sí sin preocuparte por puertos internos.

---

# 2) Elastic IP (para el NameNode)

**Consola**: EC2 → Elastic IPs → “Allocate Elastic IP” → “Associate” y eliges tu instancia del NameNode.
**CLI (opcional)**:

```bash
aws ec2 allocate-address --domain vpc
aws ec2 associate-address --instance-id i-XXXXXXXX --allocation-id eipalloc-YYYYYYYY
```

---

# 3) Volumen EBS para persistencia (NameNode)

1. **Crea un EBS** (8–20 GB está bien) en la misma **AZ** que la instancia NN y **adjúntalo** (por consola).
2. En la instancia NN:

```bash
# Verifica dispositivo (suele ser /dev/xvdf, /dev/nvme1n1, etc.)
lsblk

# Formatea (ej. en /dev/xvdf)
sudo mkfs.ext4 /dev/xvdf

# Crea punto de montaje y monta
sudo mkdir -p /var/lib/griddfs/meta
sudo mount /dev/xvdf /var/lib/griddfs/meta
sudo chown -R ec2-user:ec2-user /var/lib/griddfs/meta

# Montaje persistente en /etc/fstab (usa UUID real de tu volumen)
sudo blkid /dev/xvdf
# Supón que devuelve: UUID="abcd-1234"
echo 'UUID=abcd-1234  /var/lib/griddfs/meta  ext4  defaults,nofail  0  2' | sudo tee -a /etc/fstab
# prueba
sudo mount -a
```

> El volumen EBS **persiste** si apagas/enciendes. Si **terminas** la instancia, asegúrate de marcar el volumen como “no borrar al terminar” o **desasócialo** antes.

---

# 4) Preparar el NameNode (paquetes y build)

En el **NameNode** (Amazon Linux 2023), instala dependencias (si no las tienes):

```bash
sudo dnf update -y
sudo dnf install -y git cmake gcc-c++ \
    grpc grpc-devel grpc-plugins \
    protobuf protobuf-compiler protobuf-devel \
    openssl-devel c-ares-devel re2 re2-devel zlib-devel
```

---

# 5) Obtener/actualizar el código (git pull)

Si ya clonaste antes en `~/griddfs`, actualiza; si no, clona.

**Opción A: ya existe `~/griddfs`**

```bash
cd ~/griddfs
git remote -v
# si hiciste cambios locales y quieres guardarlos:
git stash push -u -m "backup-local"
# trae últimos cambios
git fetch origin
# elige rama remota principal
git branch -r         # mira si es origin/main u origin/master
git checkout main 2>/dev/null || git checkout -b main origin/main || git checkout -b master origin/master
git pull
```

**Opción B: clonar de cero**

```bash
cd ~
git clone https://github.com/Henao13/GridFS.git griddfs
cd griddfs
```

---

# 6) Rebuild del NameNode

```bash
cd ~/griddfs/NameNode/src
mkdir -p build && cd build
cmake ..
make -j2
```

> Si tocaste el `.proto` (no es tu caso ahora), regenera los stubs C++ desde `~/griddfs/Proto`:

```bash
cd ~/griddfs/NameNode/src
protoc -I ../../Proto --cpp_out=. ../../Proto/griddfs.proto
protoc -I ../../Proto --grpc_out=. --plugin=protoc-gen-grpc=$(which grpc_cpp_plugin) ../../Proto/griddfs.proto
# y recompila
cd build && cmake .. && make -j2
```

---

# 7) Arranque del NameNode con persistencia

```bash
# Asegúrate que el EIP ya está asociado y el SG permite 50050/tcp
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
cd ~/griddfs/NameNode/src/build

# en primer plano (útil para ver logs):
./namenode

# o en background:
nohup ./namenode > ~/namenode.log 2>&1 &
echo $! > ~/namenode.pid
```

Verifica que escucha:

```bash
ss -ltnp | grep 50050
tail -f ~/namenode.log
```

**Comportamiento esperado:**

* Al **registrar usuarios, crear directorios, crear/eliminar archivos, o asociar réplicas**, se reescribe **/var/lib/griddfs/meta/fsimage.txt**.
* Si reinicias el proceso o la instancia, el NN **recupera** usuarios/árbol de archivos desde `fsimage.txt`.

---

# 8) DataNodes (recordatorio corto)

En **cada** DataNode (con el mismo SG):

```bash
# Java (si no lo tienes)
sudo dnf install -y java-17-amazon-corretto-headless

# Código DNs
cd ~
[ -d griddfs ] || git clone https://github.com/Henao13/GridFS.git griddfs
cd ~/griddfs/DataNode
./mvnw -q -DskipTests package   # o 'mvn -q -DskipTests package'

# Ejecuta cada uno con su puerto y carpeta local
# (usa la IP pública del NameNode para el 5º argumento)
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50051 /tmp/datanode1 datanode1 <IP_PUBLICA_NN> 50050 &
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50052 /tmp/datanode2 datanode2 <IP_PUBLICA_NN> 50050 &
java -Xms128m -Xmx512m -jar target/datanode-1.0-SNAPSHOT.jar 50053 /tmp/datanode3 datanode3 <IP_PUBLICA_NN> 50050 &
```

> Si quieres persistir **bloques** también, usa un EBS parecido al del NN y monta, por ejemplo, `/var/lib/griddfs/blocksX` en lugar de `/tmp/datanodeX`.

---

# 9) Cliente (tu PC)

Ya lo tienes funcionando. Ejemplos:

```powershell
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 register usuario1
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 login usuario1
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 mkdir /docs
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 put .\archivo.txt
python -m src.cli --namenode <IP_PUBLICA_NN>:50050 ls /
```

---

## Tip rápido: script “redeploy” del NN

Crea `~/redeploy-nn.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd ~/griddfs
git fetch origin
git pull || true
cd NameNode/src/build
cmake ..
make -j2
pkill -f "/namenode" || true
export GRIDDFS_META_DIR=/var/lib/griddfs/meta
nohup ./namenode > ~/namenode.log 2>&1 &
echo $! > ~/namenode.pid
sleep 1
ss -ltnp | grep 50050 || (echo "NN no levantó" && exit 1)
echo "NameNode redeploy OK. PID=$(cat ~/namenode.pid)"
```

```bash
chmod +x ~/redeploy-nn.sh
./redeploy-nn.sh
```

---

¿Quieres que lo dejemos **más seguro** (bloquear puertos a “solo mis IPs”) o **más abierto** para pruebas (0.0.0.0/0)? Te dejo ambos perfiles si lo necesitas.
