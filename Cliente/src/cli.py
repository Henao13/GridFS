import argparse
import getpass
import os
import json
from .namenode_client import NameNodeClient
from .datanode_client import DataNodeClient

# Archivo para guardar sesión de usuario
import os
import sys
import argparse
import getpass
import json

# Usar variable de entorno GRIDDFS_TERMINAL o PID del shell
terminal_id = os.environ.get('GRIDDFS_TERMINAL', str(os.getppid()))
SESSION_FILE = os.path.expanduser(f"~/.griddfs_session_{terminal_id}")
WORKDIR_FILE = os.path.expanduser(f"~/.griddfs_workdir_{terminal_id}")

def save_session(user_id, username):
    """Guarda la sesión del usuario"""
    session_data = {"user_id": user_id, "username": username}
    with open(SESSION_FILE, "w") as f:
        json.dump(session_data, f)

def load_session():
    """Carga la sesión del usuario si existe"""
    if os.path.exists(SESSION_FILE):
        try:
            with open(SESSION_FILE, "r") as f:
                return json.load(f)
        except:
            return None
    return None

def clear_session():
    """Elimina la sesión del usuario"""
    if os.path.exists(SESSION_FILE):
        os.remove(SESSION_FILE)

def save_working_directory(directory):
    """Guarda el directorio de trabajo actual"""
    with open(WORKDIR_FILE, "w") as f:
        f.write(directory)

def load_working_directory():
    """Carga el directorio de trabajo actual"""
    if os.path.exists(WORKDIR_FILE):
        try:
            with open(WORKDIR_FILE, "r") as f:
                return f.read().strip()
        except:
            return "/"
    return "/"

def clear_working_directory():
    """Elimina el directorio de trabajo"""
    if os.path.exists(WORKDIR_FILE):
        os.remove(WORKDIR_FILE)

def resolve_path(path, current_dir="/"):
    """Resuelve una ruta relativa a absoluta"""
    if path.startswith("/"):
        return path  # Ya es absoluta
    elif path == "..":
        # Subir un nivel
        if current_dir == "/":
            return "/"
        parts = current_dir.rstrip("/").split("/")
        if len(parts) > 1:
            return "/".join(parts[:-1]) or "/"
        return "/"
    elif path == ".":
        return current_dir
    else:
        # Ruta relativa
        if current_dir == "/":
            return "/" + path
        else:
            return current_dir.rstrip("/") + "/" + path

def get_authenticated_client():
    """Obtiene un cliente autenticado"""
    session = load_session()
    namenode = NameNodeClient()
    
    if session:
        namenode.user_id = session["user_id"]
        current_dir = load_working_directory()
        print(f"Sesión activa: {session['username']} ({session['user_id']}) en {current_dir}")
        return namenode
    else:
        print("No hay sesión activa. Use 'login' para autenticarse.")
        return None


def main():
    parser = argparse.ArgumentParser(description="GridDFS CLI")
    subparsers = parser.add_subparsers(dest="command")

    # login
    login_parser = subparsers.add_parser("login", help="Iniciar sesión")
    login_parser.add_argument("username", help="Nombre de usuario")

    # register
    register_parser = subparsers.add_parser("register", help="Registrar nuevo usuario")
    register_parser.add_argument("username", help="Nombre de usuario")

    # logout
    logout_parser = subparsers.add_parser("logout", help="Cerrar sesión")

    # whoami
    whoami_parser = subparsers.add_parser("whoami", help="Mostrar usuario actual")

    # put
    put_parser = subparsers.add_parser("put", help="Subir archivo")
    put_parser.add_argument("filename")

    # get
    get_parser = subparsers.add_parser("get", help="Descargar archivo")
    get_parser.add_argument("filename")

    # ls
    ls_parser = subparsers.add_parser("ls", help="Listar archivos")
    ls_parser.add_argument("directory", nargs="?", default="/")

    # rm
    rm_parser = subparsers.add_parser("rm", help="Eliminar archivo")
    rm_parser.add_argument("filename")

    # mkdir
    mkdir_parser = subparsers.add_parser("mkdir", help="Crear directorio")
    mkdir_parser.add_argument("directory")

    # rmdir
    rmdir_parser = subparsers.add_parser("rmdir", help="Eliminar directorio")
    rmdir_parser.add_argument("directory")

    # cd
    cd_parser = subparsers.add_parser("cd", help="Cambiar directorio de trabajo")
    cd_parser.add_argument("directory")

    # pwd
    pwd_parser = subparsers.add_parser("pwd", help="Mostrar directorio actual")

    args = parser.parse_args()

    if args.command == "login":
        password = getpass.getpass("Contraseña: ")
        namenode = NameNodeClient()
        resp = namenode.login(args.username, password)
        if resp.success:
            save_session(resp.user_id, args.username)
            save_working_directory("/")  # Iniciar en directorio raíz
            print(f"✓ Login exitoso como {args.username}")
        else:
            print(f"✗ Error: {resp.message}")

    elif args.command == "register":
        password = getpass.getpass("Contraseña: ")
        namenode = NameNodeClient()
        resp = namenode.register_user(args.username, password)
        if resp.success:
            print(f"✓ Usuario {args.username} registrado exitosamente")
            print(f"ID de usuario: {resp.user_id}")
        else:
            print(f"✗ Error: {resp.message}")

    elif args.command == "logout":
        clear_session()
        clear_working_directory()
        print("✓ Sesión cerrada")

    elif args.command == "whoami":
        session = load_session()
        if session:
            print(f"Usuario: {session['username']}")
            print(f"ID: {session['user_id']}")
        else:
            print("No hay sesión activa")

    elif args.command == "put":
        namenode = get_authenticated_client()
        if not namenode:
            return
        
        try:
            with open(args.filename, "rb") as f:
                data = f.read()
            
            # Resolver la ruta del archivo usando el directorio actual
            current_dir = load_working_directory()
            full_filename = resolve_path(args.filename, current_dir)
            
            resp = namenode.create_file(full_filename, len(data))
            
            # PARTICIONAMIENTO EN EL CLIENTE: dividir archivo en bloques
            block_size = 1024 * 1024  # 1MB por bloque (debe coincidir con NameNode)
            offset = 0
            
            for i, block in enumerate(resp.blocks):
                block_id = block.block_id
                
                # Calcular el chunk de datos para este bloque
                chunk_size = min(block_size, len(data) - offset)
                chunk_data = data[offset:offset + chunk_size]
                offset += chunk_size
                
                # Enviar el chunk a TODAS las réplicas
                successful_replicas = 0
                failed_replicas = 0
                
                for j, dn in enumerate(block.datanodes):
                    try:
                        dn_client = DataNodeClient(dn.address.split(":")[0], int(dn.address.split(":")[1]))
                        result = dn_client.write_block(block_id, chunk_data)
                        if result.success:
                            successful_replicas += 1
                        else:
                            failed_replicas += 1
                            print(f"  ⚠️ Réplica {j} falló en DataNode {dn.id}")
                    except Exception as e:
                        failed_replicas += 1
                        print(f"  ⚠️ Error en réplica {j} (DataNode {dn.id}): {e}")
                
                print(f"✓ Bloque {i} ({block_id}) subido -> {successful_replicas}/{len(block.datanodes)} réplicas exitosas (tamaño: {len(chunk_data)} bytes)")
                
                # Si no hay réplicas exitosas, fallar
                if successful_replicas == 0:
                    raise Exception(f"No se pudo subir el bloque {i} a ningún DataNode")
            
            print(f"✓ Archivo {full_filename} subido exitosamente ({len(data)} bytes en {len(resp.blocks)} bloques)")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "get":
        namenode = get_authenticated_client()
        if not namenode:
            return
            
        try:
            # Resolver ruta relativa al directorio de trabajo actual
            target_file = resolve_path(args.filename, load_working_directory())
            
            info = namenode.get_file_info(target_file)
            content = b""
            for i, block in enumerate(info.blocks):
                block_data = None
                
                # Intentar leer el bloque de cada réplica hasta conseguir una exitosa
                for j, dn in enumerate(block.datanodes):
                    try:
                        dn_client = DataNodeClient(dn.address.split(":")[0], int(dn.address.split(":")[1]))
                        block_data = dn_client.read_block(block.block_id)
                        print(f"✓ Bloque {i} leído desde réplica {j} (DataNode {dn.id})")
                        break  # Éxito, salir del loop de réplicas
                    except Exception as e:
                        print(f"  ⚠️ Error leyendo bloque {i} desde réplica {j} (DataNode {dn.id}): {e}")
                        continue  # Intentar con la siguiente réplica
                
                # Si no se pudo leer de ninguna réplica, fallar
                if block_data is None:
                    raise Exception(f"No se pudo leer el bloque {i} desde ninguna réplica")
                    
                content += block_data
            
            # Usar solo el nombre del archivo sin ruta para el archivo descargado
            filename_only = args.filename.split('/')[-1]
            output_filename = f"downloaded_{filename_only}"
            with open(output_filename, "wb") as f:
                f.write(content)
            print(f"✓ Archivo descargado como {output_filename}")
            if hasattr(info, 'owner_id'):
                print(f"  Propietario: {info.owner_id}")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "ls":
        namenode = get_authenticated_client()
        if not namenode:
            return
            
        try:
            # Usar directorio actual si no se especifica uno
            if hasattr(args, 'directory') and args.directory and args.directory != "/":
                target_dir = resolve_path(args.directory, load_working_directory())
            else:
                target_dir = load_working_directory()
                
            resp = namenode.list_files(target_dir)
            if hasattr(resp, 'files') and resp.files:
                print(f"Contenido de {target_dir}:")
                for file_meta in resp.files:
                    if hasattr(file_meta, 'filename'):  # Nuevo formato con metadata
                        if file_meta.filename.endswith('/'):
                            # Es un directorio
                            print(f"  📁 {file_meta.filename}")
                        else:
                            # Es un archivo
                            print(f"  📄 {file_meta.filename} (propietario: {file_meta.owner_id}, tamaño: {file_meta.size} bytes)")
                    else:  # Formato antiguo por compatibilidad
                        print(f"  {file_meta}")
            else:
                print(f"El directorio {target_dir} está vacío")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "rm":
        namenode = get_authenticated_client()
        if not namenode:
            return
            
        try:
            # Resolver ruta relativa al directorio de trabajo actual
            target_file = resolve_path(args.filename, load_working_directory())
            
            resp = namenode.delete_file(target_file)
            if resp.success:
                print(f"✓ Archivo {args.filename} eliminado")
            else:
                print(f"✗ Error: {resp.message}")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "mkdir":
        namenode = get_authenticated_client()
        if not namenode:
            return
            
        try:
            # Resolver la ruta del directorio usando el directorio actual
            current_dir = load_working_directory()
            full_dirname = resolve_path(args.directory, current_dir)
            
            resp = namenode.create_directory(full_dirname)
            if resp.success:
                print(f"✓ Directorio {full_dirname} creado")
            else:
                print(f"✗ Error al crear directorio {full_dirname}")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "rmdir":
        namenode = get_authenticated_client()
        if not namenode:
            return
            
        try:
            # Resolver la ruta del directorio usando el directorio actual
            current_dir = load_working_directory()
            full_dirname = resolve_path(args.directory, current_dir)
            
            resp = namenode.remove_directory(full_dirname)
            if resp.success:
                print(f"✓ Directorio {full_dirname} eliminado")
            else:
                print(f"✗ Error: {resp.message}")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "cd":
        session = load_session()
        if not session:
            print("No hay sesión activa. Use 'login' para autenticarse.")
            return
            
        try:
            current_dir = load_working_directory()
            new_dir = resolve_path(args.directory, current_dir)
            
            # Normalizar la ruta (quitar dobles slashes, etc.)
            if new_dir != "/":
                new_dir = new_dir.rstrip("/")
            
            save_working_directory(new_dir)
            print(f"✓ Directorio cambiado a {new_dir}")
        except Exception as e:
            print(f"✗ Error: {e}")

    elif args.command == "pwd":
        session = load_session()
        if not session:
            print("No hay sesión activa. Use 'login' para autenticarse.")
            return
            
        current_dir = load_working_directory()
        print(current_dir)

    else:
        parser.print_help()


if __name__ == "__main__":
    main()
