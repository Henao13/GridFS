# 🚀 Guía Rápida: Usar tu Instancia EC2 Existente para GridFS

## 📊 **Tu Configuración Actual**
- **AMI**: Amazon Linux 2023 (`ami-0b09ffb6d8b58ca91`)
- **Tipo**: t3.micro (1 vCPU, 1 GB RAM)
- **Storage**: 8 GiB
- **Security Group**: Nuevo (necesita configuración)

## 🎯 **Opciones de Uso**

### **Opción 1: Cliente GridFS (Recomendado para t3.micro)**
Tu instancia t3.micro es perfecta para ser un **cliente** que se conecte a otros componentes:

```bash
# 1. Conectar a tu instancia
ssh -i tu-keypair.pem ec2-user@<TU_IP_PUBLICA>

# 2. Instalar GridFS Client
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-base.sh | bash

# 3. Instalar cliente específico  
NAMENODE_HOST=<IP_NAMENODE> curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-client.sh | bash

# 4. Usar el cliente
griddfs register usuario password
griddfs put archivo.txt /archivo.txt
```

### **Opción 2: DataNode Ligero**
También puedes usarla como DataNode (con limitaciones de RAM):

```bash
# 1. Conectar
ssh -i tu-keypair.pem ec2-user@<TU_IP_PUBLICA>

# 2. Instalar base
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-base.sh | bash

# 3. Instalar DataNode
NAMENODE_HOST=<IP_NAMENODE> curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-datanode.sh | bash
```

### **Opción 3: Sistema Completo en Una Sola Instancia (Demo)**
Para pruebas rápidas, puedes instalar todo en una instancia:

```bash
# 1. Conectar
ssh -i tu-keypair.pem ec2-user@<TU_IP_PUBLICA>

# 2. Instalar todo
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-base.sh | bash

# 3. Instalar NameNode
curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-namenode.sh | bash

# 4. Instalar DataNode (en segundo plano)
NAMENODE_HOST=127.0.0.1 curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-datanode.sh | bash

# 5. Instalar Cliente
NAMENODE_HOST=127.0.0.1 curl -sSL https://raw.githubusercontent.com/Henao13/GridFS/main/scripts/install-client.sh | bash
```

## 🔧 **Configurar Security Group**

Tu instancia necesita estos puertos abiertos:

```bash
# Obtener tu Security Group ID
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
SG_ID=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[].Instances[].SecurityGroups[].GroupId' --output text)

# Agregar reglas necesarias
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 50050 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 50051 --cidr 0.0.0.0/0
```

## ⚠️ **Limitaciones con t3.micro**

- **RAM**: 1 GB puede ser limitado para NameNode con muchos archivos
- **CPU**: 1 vCPU puede ser lento para compilación
- **Storage**: 8 GB puede llenarse rápido con archivos

## 🚀 **Recomendación**

1. **Usa tu instancia actual como Cliente**
2. **Crea instancias adicionales** para NameNode y DataNodes:
   ```bash
   # Script automático para crear sistema completo
   ./scripts/deploy-griddfs-aws.sh -k tu-keypair -n 2
   ```

## 📋 **Comandos Útiles para Amazon Linux**

```bash
# Ver recursos del sistema
free -h                    # Memoria disponible
df -h                      # Espacio en disco
htop                       # Monitor de procesos

# Gestionar servicios
sudo systemctl status griddfs-namenode
sudo systemctl status griddfs-datanode
sudo journalctl -u griddfs-namenode -f

# Usuario por defecto
whoami                     # Debería mostrar: ec2-user
```

¿Qué opción prefieres para tu instancia actual?