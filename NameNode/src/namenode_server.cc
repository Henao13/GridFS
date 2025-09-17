#include "namenode_server.h"

#include <iostream>
#include <algorithm>
#include <random>
#include <sstream>
#include <iomanip>
#include <functional>
#include <set>
#include <fstream>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

using grpc::ServerContext;
using grpc::Status;

// =============================================
// CONFIGURACIÓN DE REPLICACIÓN
// =============================================
static const int REPLICATION_FACTOR = 2;  // Número de réplicas por bloque

// =============================================
// HRW (Highest Random Weight) Implementation
// =============================================

/**
 * Calcula el peso HRW para un bloque en un DataNode específico.
 * Combina block_id y node_id usando hash para generar peso determinístico.
 */
uint64_t calculateHRW(const std::string& block_id, const std::string& node_id) {
    std::string combined = block_id + ":" + node_id;
    std::hash<std::string> hasher;
    return hasher(combined);
}

/**
 * Selecciona el DataNode con mayor peso HRW para un bloque específico.
 */
const griddfs::DataNodeInfo& selectDataNodeHRW(const std::string& block_id, 
                                               const std::vector<griddfs::DataNodeInfo>& datanodes) {
    uint64_t max_weight = 0;
    size_t best_idx = 0;
    
    for (size_t i = 0; i < datanodes.size(); ++i) {
        uint64_t weight = calculateHRW(block_id, datanodes[i].id());
        if (weight > max_weight) {
            max_weight = weight;
            best_idx = i;
        }
    }
    
    return datanodes[best_idx];
}

/**
 * Selecciona múltiples DataNodes para replicación usando HRW.
 * Retorna hasta 'count' DataNodes diferentes ordenados por peso HRW.
 */
std::vector<griddfs::DataNodeInfo> selectDataNodesForReplication(
    const std::string& block_id, 
    const std::vector<griddfs::DataNodeInfo>& datanodes,
    int count) {
    
    // Crear vector de pares (peso, índice) para ordenar
    std::vector<std::pair<uint64_t, size_t>> weights;
    weights.reserve(datanodes.size());
    for (size_t i = 0; i < datanodes.size(); ++i) {
        uint64_t weight = calculateHRW(block_id, datanodes[i].id());
        weights.push_back({weight, i});
    }
    
    // Ordenar por peso descendente
    std::sort(weights.begin(), weights.end(), 
              [](const auto& a, const auto& b) { return a.first > b.first; });
    
    // Seleccionar los primeros 'count' DataNodes
    std::vector<griddfs::DataNodeInfo> selected;
    int selected_count = std::min(count, static_cast<int>(datanodes.size()));
    selected.reserve(selected_count);
    for (int i = 0; i < selected_count; ++i) {
        selected.push_back(datanodes[weights[i].second]);
    }
    
    return selected;
}

// Constructor
NameNodeServiceImpl::NameNodeServiceImpl() {
    // registrar directorio raíz por defecto (opcional)
    directories_.insert("/");

    // inicializa meta_dir_ desde env (persistencia)
    if (const char* d = std::getenv("GRIDDFS_META_DIR")) {
        meta_dir_ = d;
    } else {
        meta_dir_ = "/var/lib/griddfs/meta";
    }
    ::mkdir(meta_dir_.c_str(), 0755);

    // Carga snapshot si existe
    std::lock_guard<std::mutex> lock(mu_);
    (void)LoadSnapshotUnlocked();
}

// =============================================
// MÉTODOS AUXILIARES DE AUTENTICACIÓN
// =============================================

std::string NameNodeServiceImpl::generateUserId() {
    // Genera un ID único simple usando timestamp + random
    auto now = std::chrono::system_clock::now();
    auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();
    
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> dis(1000, 9999);
    
    return "user_" + std::to_string(timestamp) + "_" + std::to_string(dis(gen));
}

std::string NameNodeServiceImpl::hashPassword(const std::string& password) {
    // Hash simple por ahora (en producción usar bcrypt/argon2)
    std::hash<std::string> hasher;
    size_t hash_value = hasher(password + "salt_griddfs");
    std::stringstream ss;
    ss << std::hex << hash_value;
    return ss.str();
}

bool NameNodeServiceImpl::verifyPassword(const std::string& password, const std::string& hash) {
    return hashPassword(password) == hash;
}

bool NameNodeServiceImpl::userExists(const std::string& username) {
    return users_.find(username) != users_.end();
}

bool NameNodeServiceImpl::isFileOwner(const std::string& filename, const std::string& user_id) {
    // Crear clave única por usuario: user_id + ":" + filename
    std::string file_key = user_id + ":" + filename;
    auto it = files_.find(file_key);
    if (it == files_.end()) return false;
    return it->second.owner_id == user_id;
}

bool NameNodeServiceImpl::isValidUser(const std::string& user_id) {
    return users_by_id_.find(user_id) != users_by_id_.end();
}

// =============================================
// SERVICIOS DE AUTENTICACIÓN
// =============================================

Status NameNodeServiceImpl::RegisterUser(ServerContext* /*ctx*/,
                                         const griddfs::RegisterUserRequest* request,
                                         griddfs::RegisterUserResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& username = request->username();
    const std::string& password = request->password();
    
    // Validar entrada
    if (username.empty() || password.empty()) {
        response->set_success(false);
        response->set_message("Usuario y contraseña no pueden estar vacíos");
        return Status::OK;
    }
    
    // Verificar si el usuario ya existe
    if (userExists(username)) {
        response->set_success(false);
        response->set_message("El usuario ya existe");
        return Status::OK;
    }
    
    // Crear nuevo usuario
    UserInfo user;
    user.user_id = generateUserId();
    user.username = username;
    user.password_hash = hashPassword(password);
    user.created_time = std::chrono::system_clock::now();
    
    // Guardar usuario
    users_[username] = user;
    users_by_id_[user.user_id] = user;
    
    response->set_success(true);
    response->set_user_id(user.user_id);
    response->set_message("Usuario registrado exitosamente");
    
    std::cout << "[RegisterUser] " << username << " -> " << user.user_id << std::endl;

    // >>> Persistencia
    (void)SaveSnapshotUnlocked();
    
    return Status::OK;
}

Status NameNodeServiceImpl::LoginUser(ServerContext* /*ctx*/,
                                     const griddfs::LoginRequest* request,
                                     griddfs::LoginResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& username = request->username();
    const std::string& password = request->password();
    
    // Buscar usuario
    auto it = users_.find(username);
    if (it == users_.end()) {
        response->set_success(false);
        response->set_message("Usuario no encontrado");
        return Status::OK;
    }
    
    // Verificar contraseña
    const UserInfo& user = it->second;
    if (!verifyPassword(password, user.password_hash)) {
        response->set_success(false);
        response->set_message("Contraseña incorrecta");
        return Status::OK;
    }
    
    // Login exitoso
    response->set_success(true);
    response->set_user_id(user.user_id);
    response->set_message("Login exitoso");
    
    std::cout << "[LoginUser] " << username << " -> " << user.user_id << std::endl;
    
    return Status::OK;
}

// =============================================
// SERVICIOS DE ARCHIVOS (MODIFICADOS CON AUTENTICACIÓN)
// =============================================

// CreateFile: el cliente solicita crear (planificar) un archivo -> devolvemos bloques asignados.
Status NameNodeServiceImpl::CreateFile(ServerContext* /*ctx*/,
                                       const griddfs::CreateFileRequest* request,
                                       griddfs::CreateFileResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& filename = request->filename();
    const int64_t filesize = request->filesize();
    const std::string& user_id = request->user_id();
    
    // Verificar que el usuario es válido
    if (!isValidUser(user_id)) {
        return Status(grpc::StatusCode::UNAUTHENTICATED, "Usuario no válido");
    }
    
    // Crear clave única por usuario: user_id + ":" + filename
    std::string file_key = user_id + ":" + filename;
    
    // Verificar si el archivo ya existe para este usuario
    if (files_.find(file_key) != files_.end()) {
        return Status(grpc::StatusCode::ALREADY_EXISTS, "El archivo ya existe");
    }

    if (datanodes_.empty()) {
        return Status(grpc::StatusCode::FAILED_PRECONDITION, "No hay DataNodes registrados");
    }

    // Construir vector de DataNodeInfo para HRW
    std::vector<griddfs::DataNodeInfo> dns;
    dns.reserve(datanodes_.size());
    for (const auto& kv : datanodes_) dns.push_back(kv.second);

    const int64_t block_size = DEFAULT_BLOCK_SIZE;
    int64_t nblocks = (filesize + block_size - 1) / block_size;
    if (nblocks <= 0) nblocks = 1; // manejar archivos con tamaño 0

    // Crear metadata del archivo
    FileMetadata file_meta;
    file_meta.filename = filename;  // Guardamos solo el nombre del archivo, no la clave
    file_meta.owner_id = user_id;
    file_meta.size = filesize;
    file_meta.created_time = std::chrono::system_clock::now();

    for (int64_t i = 0; i < nblocks; ++i) {
        griddfs::BlockInfo bi;
        // Block ID único: user_id + filename + bloque
        bi.set_block_id(user_id + "_" + filename + "_blk_" + std::to_string(i));
        int64_t this_size = (i == nblocks - 1) ? (filesize - i * block_size) : block_size;
        if (this_size < 0) this_size = 0;
        bi.set_size(this_size);

        // Asignar múltiples DataNodes para replicación usando HRW
        std::vector<griddfs::DataNodeInfo> replicas = selectDataNodesForReplication(
            bi.block_id(), dns, REPLICATION_FACTOR);
        
        // Añadir todas las réplicas al bloque
        for (const auto& replica : replicas) {
            griddfs::DataNodeInfo* dn_ptr = bi.add_datanodes();
            dn_ptr->CopyFrom(replica);
        }

        // Guardar en metadata del archivo
        file_meta.blocks.push_back(bi);

        // Añadir al response
        griddfs::BlockInfo* out_bi = const_cast<griddfs::CreateFileResponse*>(response)->add_blocks();
        out_bi->CopyFrom(bi);

        std::cout << "[CreateFile] " << filename << " (owner: " << user_id << ") -> block " << bi.block_id()
                  << " size=" << bi.size() << " assigned to " << replicas.size() << " DataNodes: ";
        for (size_t j = 0; j < replicas.size(); ++j) {
            std::cout << replicas[j].id();
            if (j < replicas.size() - 1) std::cout << ", ";
        }
        std::cout << " (HRW+Replication)" << "\n";
    }
    
    // Guardar metadata del archivo con clave única
    files_[file_key] = file_meta;

    // >>> Persistencia
    (void)SaveSnapshotUnlocked();

    return Status::OK;
}

// GetFileInfo: devolvemos la lista de BlockInfo guardada previamente
Status NameNodeServiceImpl::GetFileInfo(ServerContext* /*ctx*/,
                                        const griddfs::GetFileInfoRequest* request,
                                        griddfs::GetFileInfoResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& filename = request->filename();
    const std::string& user_id = request->user_id();
    
    // Verificar que el usuario es válido
    if (!isValidUser(user_id)) {
        return Status(grpc::StatusCode::UNAUTHENTICATED, "Usuario no válido");
    }
    
    // Crear clave única por usuario: user_id + ":" + filename
    std::string file_key = user_id + ":" + filename;
    
    auto it = files_.find(file_key);
    if (it == files_.end()) {
        return Status(grpc::StatusCode::NOT_FOUND, "Archivo no encontrado");
    }
    
    const FileMetadata& file_meta = it->second;
    
    // Añadir bloques al response
    for (const griddfs::BlockInfo& bi : file_meta.blocks) {
        griddfs::BlockInfo* out_bi = response->add_blocks();
        out_bi->CopyFrom(bi);
    }
    
    // Establecer propietario
    response->set_owner_id(file_meta.owner_id);

    std::cout << "[GetFileInfo] " << filename << " (owner: " << file_meta.owner_id << ") -> " 
              << file_meta.blocks.size() << " blocks\n";
    return Status::OK;
}

// ListFiles: listamos archivos con metadata de propietario
Status NameNodeServiceImpl::ListFiles(ServerContext* /*ctx*/,
                                      const griddfs::ListFilesRequest* request,
                                      griddfs::ListFilesResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& dir = request->directory();
    const std::string& user_id = request->user_id();
    
    // Verificar que el usuario es válido
    if (!isValidUser(user_id)) {
        return Status(grpc::StatusCode::UNAUTHENTICATED, "Usuario no válido");
    }

    // Primero recopilar directorios únicos del usuario basado en sus archivos
    std::set<std::string> user_directories;
    
    // 1. Agregar directorios creados explícitamente por el usuario
    std::string dir_prefix = user_id + ":";
    for (const auto& directory_key : directories_) {
        std::cout << "[DEBUG] Checking directory_key: '" << directory_key << "' against prefix: '" << dir_prefix << "'\n";
        if (starts_with(directory_key, dir_prefix)) {
            // Extraer el directorio real (sin el user_id)
            std::string actual_dir = directory_key.substr(dir_prefix.length());
            std::cout << "[DEBUG] Adding explicit directory: '" << actual_dir << "' to user_directories\n";
            user_directories.insert(actual_dir);
        }
    }
    
    // 2. Agregar directorios derivados de archivos del usuario
    for (const auto& kv : files_) {
        const std::string& dir_file_key = kv.first;
        
        // Verificar si el archivo pertenece al usuario actual
        std::string file_prefix = user_id + ":";
        if (!starts_with(dir_file_key, file_prefix)) {
            continue;
        }
        
        // Extraer el nombre del archivo real (sin el user_id)
        std::string dir_filename = dir_file_key.substr(file_prefix.length());
        
        // Extraer directorios de este archivo
        std::string current_path = dir_filename;
        while (current_path.find('/') != std::string::npos) {
            size_t last_slash = current_path.find_last_of('/');
            if (last_slash != std::string::npos) {
                current_path = current_path.substr(0, last_slash);
                if (!current_path.empty()) {
                    user_directories.insert(current_path);
                }
            }
        }
    }
    
    // Luego agregar directorios del usuario
    std::cout << "[DEBUG] user_directories contains " << user_directories.size() << " directories\n";
    for (const auto& directory : user_directories) {
        std::cout << "[DEBUG] Processing directory: '" << directory << "' for listing in '" << dir << "'\n";
        // Verificar si el directorio debería mostrarse en este nivel
        bool should_include_dir = false;
        std::string display_name;
        
        if (dir == "/") {
            // En directorio raíz, mostrar directorios de primer nivel
            if (directory.length() > 1 && directory[0] == '/') {
                // Es un directorio absoluto como "/fotos"
                std::string subdir = directory.substr(1); // quitar el "/" inicial
                if (subdir.find('/') == std::string::npos && !subdir.empty()) {
                    should_include_dir = true;
                    display_name = subdir;
                    std::cout << "[DEBUG] Will show directory '" << display_name << "' in root\n";
                }
            }
        } else {
            // En otros directorios, mostrar subdirectorios
            std::string prefix = dir + "/";
            if (starts_with(directory, prefix)) {
                std::string subdir = directory.substr(prefix.length());
                if (subdir.find('/') == std::string::npos && !subdir.empty()) {
                    should_include_dir = true;
                    display_name = subdir;
                }
            }
        }
        
        if (should_include_dir) {
            griddfs::FileMetadata* dir_info = response->add_files();
            dir_info->set_filename("📁 " + display_name);  // Marcar como directorio con emoji
            dir_info->set_owner_id(user_id);  // Los directorios pertenecen al usuario que los creó
            dir_info->set_size(0);  // Los directorios tienen tamaño 0
            dir_info->set_created_time(0);  // Por simplicidad, timestamp 0 para directorios
        }
    }

    // Luego agregar archivos
    for (const auto& kv : files_) {
        const std::string& file_key = kv.first;
        const FileMetadata& file_meta = kv.second;
        
        // Verificar si el archivo pertenece al usuario actual
        // El file_key tiene formato "user_id:filename"
        std::string prefix = user_id + ":";
        if (!starts_with(file_key, prefix)) {
            continue; // Este archivo no pertenece al usuario actual
        }
        
        // Extraer el nombre del archivo real (sin el user_id)
        std::string filename = file_key.substr(prefix.length());
        
        // Si el directorio es "/", mostrar todos los archivos que no contengan "/"
        // Si es otro directorio, usar starts_with normal
        bool should_include = false;
        if (dir == "/") {
            // Para directorio raíz, incluir archivos que empiecen con "/" y no tengan más "/"
            if (filename.length() > 1 && filename[0] == '/') {
                std::string name_without_slash = filename.substr(1); // quitar "/" inicial
                should_include = (name_without_slash.find('/') == std::string::npos);
            }
        } else {
            // Para otros directorios, verificar si el archivo está en este directorio
            std::string dir_prefix = dir + "/";
            if (starts_with(filename, dir_prefix)) {
                std::string relative_filename = filename.substr(dir_prefix.length());
                should_include = (relative_filename.find('/') == std::string::npos);
            }
        }
        
        if (should_include) {
            griddfs::FileMetadata* file_info = response->add_files();
            if (dir == "/") {
                // En raíz, mostrar nombre sin "/" inicial
                if (filename.length() > 1 && filename[0] == '/') {
                    file_info->set_filename(filename.substr(1));  // quitar "/" inicial
                } else {
                    file_info->set_filename(filename);
                }
            } else {
                // En subdirectorios, mostrar solo el nombre relativo
                std::string dir_prefix = dir + "/";
                std::string relative_filename = filename.substr(dir_prefix.length());
                file_info->set_filename(relative_filename);
            }
            file_info->set_owner_id(file_meta.owner_id);
            file_info->set_size(file_meta.size);
            
            // Convertir timestamp a epoch milliseconds
            auto epoch = file_meta.created_time.time_since_epoch();
            auto millis = std::chrono::duration_cast<std::chrono::milliseconds>(epoch).count();
            file_info->set_created_time(millis);
        }
    }

    std::cout << "[ListFiles] directory='" << dir << "' user=" << user_id 
              << " -> " << response->files_size() << " files\n";
    return Status::OK;
}

// DeleteFile: eliminamos archivo con verificación de propietario
Status NameNodeServiceImpl::DeleteFile(ServerContext* /*ctx*/,
                                       const griddfs::DeleteFileRequest* request,
                                       griddfs::DeleteFileResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& filename = request->filename();
    const std::string& user_id = request->user_id();
    
    // Verificar que el usuario es válido
    if (!isValidUser(user_id)) {
        response->set_success(false);
        response->set_message("Usuario no válido");
        return Status::OK;
    }
    
    // Crear clave única por usuario: user_id + ":" + filename
    std::string file_key = user_id + ":" + filename;
    
    auto it = files_.find(file_key);
    if (it == files_.end()) {
        response->set_success(false);
        response->set_message("Archivo no encontrado");
        return Status::OK;
    }
    
    // Eliminar archivo
    files_.erase(it);
    response->set_success(true);
    response->set_message("Archivo eliminado exitosamente");
    
    std::cout << "[DeleteFile] " << filename << " eliminado por " << user_id << std::endl;

    // >>> Persistencia
    (void)SaveSnapshotUnlocked();

    return Status::OK;
}

// CreateDirectory: versión con autenticación
Status NameNodeServiceImpl::CreateDirectory(ServerContext* /*ctx*/,
                                            const griddfs::CreateDirectoryRequest* request,
                                            griddfs::CreateDirectoryResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& dir = request->directory();
    const std::string& user_id = request->user_id();
    
    // Verificar que el usuario es válido
    if (!isValidUser(user_id)) {
        response->set_success(false);
        return Status(grpc::StatusCode::UNAUTHENTICATED, "Usuario no válido");
    }
    
    // Crear clave única por usuario para el directorio
    std::string dir_key = user_id + ":" + dir;
    std::cout << "[DEBUG] CreateDirectory storing key: '" << dir_key << "'\n";
    directories_.insert(dir_key);
    response->set_success(true);
    std::cout << "[CreateDirectory] " << dir << " creado por " << user_id << std::endl;

    // >>> Persistencia
    (void)SaveSnapshotUnlocked();

    return Status::OK;
}

// RemoveDirectory: eliminar directorio con autenticación
Status NameNodeServiceImpl::RemoveDirectory(ServerContext* /*ctx*/,
                                            const griddfs::RemoveDirectoryRequest* request,
                                            griddfs::RemoveDirectoryResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    
    const std::string& dir = request->directory();
    const std::string& user_id = request->user_id();
    
    // Verificar que el usuario es válido
    if (!isValidUser(user_id)) {
        response->set_success(false);
        return Status(grpc::StatusCode::UNAUTHENTICATED, "Usuario no válido");
    }
    
    // Crear clave única por usuario para el directorio
    std::string dir_key = user_id + ":" + dir;
    
    // Verificar que el directorio existe
    if (directories_.find(dir_key) == directories_.end()) {
        response->set_success(false);
        return Status(grpc::StatusCode::NOT_FOUND, "Directorio no encontrado");
    }
    
    directories_.erase(dir_key);
    response->set_success(true);
    std::cout << "[RemoveDirectory] " << dir << " eliminado por " << user_id << std::endl;

    // >>> Persistencia
    (void)SaveSnapshotUnlocked();

    return Status::OK;
}

// =============================================
// SERVICIOS DE DATANODE
// =============================================

// RegisterDataNode: añade/actualiza DataNode en la tabla (corrige localhost -> IP real)
Status NameNodeServiceImpl::RegisterDataNode(ServerContext* ctx,
                                             const griddfs::RegisterDataNodeRequest* request,
                                             griddfs::RegisterDataNodeResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);

    const griddfs::DataNodeInfo& in = request->datanode();
    std::string id = in.id();

    // IP real del peer que ve el servidor
    std::string peer_ip   = PeerIpFromContext(ctx);
    std::string fixed_addr = FixLocalhostAddr(in.address(), peer_ip);

    // Guarda el DN con la dirección corregida (no localhost)
    griddfs::DataNodeInfo dn = in;
    dn.set_address(fixed_addr);
    datanodes_[id] = dn;

    response->set_success(true);
    std::cout << "[RegisterDataNode] id=" << id
              << " addr=" << dn.address()
              << " capacity=" << dn.capacity()
              << " free=" << dn.free_space() << "\n";
    return Status::OK;
}

// Heartbeat: actualiza el free_space del DataNode y responde success
Status NameNodeServiceImpl::Heartbeat(ServerContext* /*ctx*/,
                                      const griddfs::HeartbeatRequest* request,
                                      griddfs::HeartbeatResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    const std::string id = request->datanode_id();
    auto it = datanodes_.find(id);
    if (it != datanodes_.end()) {
        // actualizar free_space si el DataNode ya estaba registrado
        it->second.set_free_space(request->free_space());
        response->set_success(true);
        std::cout << "[Heartbeat] from " << id << " free_space=" << request->free_space() << "\n";
        return Status::OK;
    } else {
        // No estaba registrado -> false (el cliente puede llamar RegisterDataNode primero)
        response->set_success(false);
        std::cout << "[Heartbeat] unknown DataNode " << id << "\n";
        return Status::OK;
    }
}

// BlockReport: DataNode reporta lista de block_ids que almacena
Status NameNodeServiceImpl::BlockReport(ServerContext* /*ctx*/,
                                        const griddfs::BlockReportRequest* request,
                                        griddfs::BlockReportResponse* response) {
    std::lock_guard<std::mutex> lock(mu_);
    const std::string id = request->datanode_id();
    auto it_dn = datanodes_.find(id);
    if (it_dn == datanodes_.end()) {
        response->set_success(false);
        std::cout << "[BlockReport] from unknown datanode " << id << "\n";
        return Status::OK;
    }

    const griddfs::DataNodeInfo& dn_info = it_dn->second;

    bool changed = false;

    // Para cada block_id reportado, intentamos asociar este DataNode al BlockInfo en files_
    for (const std::string& blk_id : request->block_ids()) {
        bool found = false;
        for (auto& kv : files_) {
            FileMetadata& file_meta = kv.second;
            for (auto& bi : file_meta.blocks) {
                if (bi.block_id() == blk_id) {
                    found = true;
                    // comprobar si ya existe el datanode en la lista
                    bool already = false;
                    for (const auto& existing_dn : bi.datanodes()) {
                        if (existing_dn.id() == id) {
                            already = true;
                            break;
                        }
                    }
                    if (!already) {
                        griddfs::DataNodeInfo* newdn = bi.add_datanodes();
                        newdn->CopyFrom(dn_info);
                        changed = true;
                        std::cout << "[BlockReport] asociando block " << blk_id << " -> datanode " << id << "\n";
                    }
                }
            }
            if (found) break;
        }
        if (!found) {
            std::cout << "[BlockReport] block " << blk_id << " no está en metadatos (ignorado)\n";
        }
    }

    if (changed) {
        // >>> Persistencia solo si hubo cambios reales
        (void)SaveSnapshotUnlocked();
    }

    response->set_success(true);
    return Status::OK;
}

// =============================================
// MÉTODOS AUXILIARES
// =============================================

// helper: starts_with
bool NameNodeServiceImpl::starts_with(const std::string& s, const std::string& prefix) const {
    if (prefix.empty()) return true;
    if (prefix.size() > s.size()) return false;
    return std::equal(prefix.begin(), prefix.end(), s.begin());
}

// ================================
// Persistencia (Snapshot plano)
// ================================
std::string NameNodeServiceImpl::MetaPath(const std::string& file) const {
    return meta_dir_.empty() ? ("/var/lib/griddfs/meta/" + file) : (meta_dir_ + "/" + file);
}

// Formato de fsimage.txt (líneas con '\t'):
// SEQ 1
// USER  <user_id>\t<username>\t<password_hash>\t<created_ms>
// DIR   <path>
// FILE  <file_key>\t<owner_id>\t<size>\t<created_ms>\t<filename>
// BLK   <file_key>\t<block_id>\t<idx>\t<size>
// LOC   <block_id>\t<datanode_id>\t<address>
bool NameNodeServiceImpl::SaveSnapshotUnlocked() {
    std::ostringstream out;

    out << "SEQ\t1\n";
    // USERS
    for (const auto& kv : users_) {
        const auto& u = kv.second;
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      u.created_time.time_since_epoch()).count();
        out << "USER\t" << u.user_id << "\t" << u.username << "\t"
            << u.password_hash << "\t" << ms << "\n";
    }

    // DIRS
    for (const auto& d : directories_) {
        out << "DIR\t" << d << "\n";
    }

    // FILES + BLOCKS + LOCATIONS
    for (const auto& kv : files_) {
        const std::string& file_key = kv.first;       // user_id:filename
        const FileMetadata& fm = kv.second;
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                      fm.created_time.time_since_epoch()).count();
        out << "FILE\t" << file_key << "\t" << fm.owner_id << "\t"
            << fm.size << "\t" << ms << "\t" << fm.filename << "\n";

        for (size_t idx = 0; idx < fm.blocks.size(); ++idx) {
            const auto& b = fm.blocks[idx];
            out << "BLK\t" << file_key << "\t" << b.block_id() << "\t"
                << idx << "\t" << b.size() << "\n";
            for (const auto& dn : b.datanodes()) {
                out << "LOC\t" << b.block_id() << "\t" << dn.id()
                    << "\t" << dn.address() << "\n";
            }
        }
    }

    // Escritura atómica a fsimage.txt
    const std::string path = MetaPath("fsimage.txt");
    const std::string tmp  = path + ".tmp";
    {
        std::ofstream ofs(tmp, std::ios::binary | std::ios::trunc);
        if (!ofs) return false;
        const auto s = out.str();
        ofs.write(s.data(), s.size());
        ofs.flush();
        int fd = ::open(tmp.c_str(), O_RDONLY);
        if (fd >= 0) { ::fsync(fd); ::close(fd); }
    }
    ::rename(tmp.c_str(), path.c_str());
    return true;
}

static std::vector<std::string> SplitTabs(const std::string& line) {
    std::vector<std::string> v;
    std::string cur;
    std::istringstream is(line);
    while (std::getline(is, cur, '\t')) v.push_back(cur);
    return v;
}

bool NameNodeServiceImpl::LoadSnapshotUnlocked() {
    const std::string path = MetaPath("fsimage.txt");
    std::ifstream ifs(path);
    if (!ifs) return false; // primera vez

    users_.clear(); users_by_id_.clear();
    files_.clear(); directories_.clear(); directories_.insert("/");

    // Para mapear block_id -> BlockInfo*
    std::unordered_map<std::string, griddfs::BlockInfo*> blk_index;
    // Para asegurar que FILE aparezca antes que BLK del mismo file_key
    std::unordered_map<std::string, FileMetadata*> file_index;

    std::string line;
    while (std::getline(ifs, line)) {
        if (line.empty()) continue;
        auto t = SplitTabs(line);
        if (t.empty()) continue;

        if (t[0] == "USER" && t.size() >= 5) {
            UserInfo u;
            u.user_id = t[1];
            u.username = t[2];
            u.password_hash = t[3];
            int64_t ms = std::stoll(t[4]);
            u.created_time = std::chrono::system_clock::time_point(std::chrono::milliseconds(ms));
            users_[u.username] = u;
            users_by_id_[u.user_id] = u;
        } else if (t[0] == "DIR" && t.size() >= 2) {
            directories_.insert(t[1]);
        } else if (t[0] == "FILE" && t.size() >= 6) {
            std::string file_key = t[1];
            FileMetadata fm;
            fm.owner_id = t[2];
            fm.size = static_cast<int64_t>(std::stoll(t[3]));
            int64_t ms = std::stoll(t[4]);
            fm.created_time = std::chrono::system_clock::time_point(std::chrono::milliseconds(ms));
            fm.filename = t[5]; // nombre “visible”
            files_[file_key] = fm;
            file_index[file_key] = &files_[file_key];
        } else if (t[0] == "BLK" && t.size() >= 5) {
            std::string file_key = t[1];
            std::string blk_id   = t[2];
            int idx = std::stoi(t[3]);
            int64_t sz = std::stoll(t[4]);
            auto it = file_index.find(file_key);
            if (it != file_index.end()) {
                griddfs::BlockInfo bi;
                bi.set_block_id(blk_id);
                bi.set_size(sz);
                it->second->blocks.push_back(bi);
                blk_index[blk_id] = &it->second->blocks.back();
            }
        } else if (t[0] == "LOC" && t.size() >= 4) {
            std::string blk_id = t[1];
            std::string dn_id  = t[2];
            std::string addr   = t[3];
            auto it = blk_index.find(blk_id);
            if (it != blk_index.end()) {
                auto* dni = it->second->add_datanodes();
                dni->set_id(dn_id);
                dni->set_address(addr);
            }
        }
    }
    return true;
}

// ================================
// Utilidades de red (ctx->peer())
// ================================
std::string NameNodeServiceImpl::PeerIpFromContext(grpc::ServerContext* ctx) const {
    // ctx->peer(): "ipv4:18.208.28.6:54321" o "ipv6:[::1]:puerto"
    std::string peer = ctx->peer();
    auto a = peer.find(':');              // después de "ipv4" / "ipv6"
    if (a == std::string::npos) return peer;
    auto b = peer.find(':', a + 1);       // separa IP y PORT
    if (b == std::string::npos) return peer;
    return peer.substr(a + 1, b - (a + 1));  // "18.208.28.6" o "[::1]"
}

bool NameNodeServiceImpl::IsLocalhost(const std::string& host) {
    return host == "localhost" || host.rfind("127.", 0) == 0 || host == "::1" || host == "[::1]";
}

std::string NameNodeServiceImpl::FixLocalhostAddr(const std::string& addr,
                                                  const std::string& peer_ip) {
    // addr tiene forma "host:port" (p.ej "localhost:50051")
    auto c = addr.rfind(':');
    std::string host = (c == std::string::npos) ? addr : addr.substr(0, c);
    std::string port = (c == std::string::npos) ? "50051" : addr.substr(c + 1);
    if (IsLocalhost(host)) return peer_ip + ":" + port;
    return addr;
}
