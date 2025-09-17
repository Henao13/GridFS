# Guion de Video: GridDFS – Arquitectura, Autenticación y Demo en AWS (8–10 min)

## 0: Hook (0:00–0:20)
- Visual: Pantalla partida con un archivo subiendo y replicándose en 2 DataNodes y el NameNode mostrando logs.
- Narración: "¿Cómo construir tu propio sistema de archivos distribuido tipo HDFS con NameNode en C++, DataNodes en Java, y un cliente en Python, autenticación incluida y desplegado en AWS? Hoy te lo muestro, de punta a punta."

## 1: Qué problema resuelve (0:20–0:50)
- Visual: Diagrama simple de un solo servidor saturado vs clúster con múltiples DataNodes.
- Narración: "Necesitamos almacenar archivos grandes de forma confiable y escalable. Con GridDFS distribuimos bloques en varios DataNodes, replicamos para tolerancia a fallos y centralizamos el control en un NameNode."

## 2: Arquitectura general (0:50–2:00)
- Visual: Diagrama con componentes:
  - NameNode (C++/gRPC) – metadata, autenticación, planificación de bloques.
  - DataNodes (Java/Maven/gRPC) – almacenamiento de bloques, streaming.
  - Cliente (Python) – CLI para put/get/ls/mkdir/rm, manejo de sesión.
  - Proto gRPC común (griddfs.proto).
- Callouts: Puertos (50050 NameNode, 50051/50052 DataNodes), replicación por factor configurable, HRW para selección de nodos.
- Narración: "El NameNode no guarda datos; mantiene metadata y decide dónde van los bloques. El cliente habla con el NameNode para planificar y luego escribe/lee directamente de los DataNodes."

## 3: Autenticación y sesiones (2:00–2:50)
- Visual: Flujo Login (username/password) → token de sesión → peticiones con token.
- Narración: "Antes de cualquier operación, el usuario se autentica. El NameNode valida credenciales, emite un token y lo usa para autorizar operaciones como put, get y delete, además de asociar propiedad de archivos."
- Overlay: Comandos CLI: `register`, `login`, `logout`, `whoami`.

## 4: Flujo PUT/GET y replicación HRW (2:50–4:30)
- Visual: Secuencia animada.
  - PUT: Cliente → NameNode (CreateFile) → recibe lista de bloques con DataNodes destino → Cliente hace streaming a cada DataNode.
  - HRW: selección determinística de réplicas por bloque (hash pesos) → equilibrio y estabilidad al escalar.
  - GET: Cliente → NameNode (GetFileInfo) → descarga desde uno de los DataNodes.
- Callouts: Tamaño de bloque, número de bloques, factor de replicación, reintentos si falla una réplica.

## 5: Despliegue en AWS (4:30–5:30)
- Visual: Mapa con EC2 para NameNode y varios DataNodes + cliente local.
- Narración: "Usamos EC2: NameNode en C++ (CMake/gRPC), DataNodes en Java (Maven) y el cliente desde tu máquina. Solo abrimos 50050 para el NameNode y los puertos de DataNodes entre nodos."
- Overlay rápido: scripts/instalación o comandos mínimos.

## 6: Demo práctica en vivo (5:30–8:30)
- Visual: 4 terminales: NameNode, dn1, dn2, Cliente.

1) NameNode (EC2)
```bash
cd ~/griddfs/NameNode/src/build
./namenode
```

2) DataNodes (EC2)
```bash
cd ~/griddfs/DataNode
mvn clean package
java -jar target/datanode-1.0-SNAPSHOT.jar 50051 /tmp/datanode datanode1 <NAMENODE_IP> 50050
java -jar target/datanode-1.0-SNAPSHOT.jar 50052 /tmp/datanode datanode2 <NAMENODE_IP> 50050
```

3) Cliente (local)
```powershell
cd Cliente
python -m src.cli --namenode <NAMENODE_IP>:50050 register usuario1
# (ingresa contraseña cuando la pida)
python -m src.cli --namenode <NAMENODE_IP>:50050 login usuario1
python -m src.cli --namenode <NAMENODE_IP>:50050 mkdir doc
python -m src.cli --namenode <NAMENODE_IP>:50050 put ejemplo.txt doc/ejemplo.txt
python -m src.cli --namenode <NAMENODE_IP>:50050 ls doc
python -m src.cli --namenode <NAMENODE_IP>:50050 get doc/ejemplo.txt
```

- Mensajes esperados: réplicas 2/2 exitosas; `ls` mostrando propietario y tamaño.
- Tip: si falla una réplica, se informa en consola y se reintenta con otra cuando aplique.

## 7: Cierre y próximos pasos (8:30–10:00)
- Visual: Diagrama final y resultados de demo.
- Narración: "Logramos un sistema distribuido con autenticación, replicación y escalabilidad. Próximos pasos: monitoreo, re-replicación automática ante fallos y balanceo dinámico de capacidad. El repo tiene scripts para que lo despliegues en minutos."
- CTA: "Dale estrella al repo y cuéntame qué te gustaría ver en la siguiente versión."
