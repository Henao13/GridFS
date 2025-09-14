/*
 * EJEMPLO DE IMPLEMENTACIÓN DE AUTENTICACIÓN PARA NAMENODE
 * 
 * Este archivo muestra cómo extender namenode_server.h y namenode_server.cc
 * para agregar funcionalidad de autenticación de usuarios.
 * 
 * PASOS PARA IMPLEMENTAR:
 * 1. Regenerar archivos protobuf: ./regenerate_proto.sh
 * 2. Agregar estas estructuras y métodos a namenode_server.h
 * 3. Implementar los métodos en namenode_server.cc
 * 4. Recompilar: cd build && cmake .. && make
 */

#ifndef NAMENODE_SERVER_AUTH_H
#define NAMENODE_SERVER_AUTH_H

#include <string>
#include <unordered_map>
#include <chrono>

// Estructura para almacenar información de usuario
struct UserInfo {
    std::string user_id;      // UUID único del usuario
    std::string username;     // Nombre de usuario
    std::string password_hash; // Hash de la contraseña (usar bcrypt o similar)
    std::string email;        // Email opcional
    std::chrono::system_clock::time_point created_time; // Timestamp de creación
};

// Estructura para metadata de archivos con información de propietario
struct FileMetadata {
    std::string filename;
    std::string owner_id;     // ID del usuario propietario
    int64_t size;
    std::chrono::system_clock::time_point created_time;
    std::vector<griddfs::BlockInfo> blocks; // Bloques del archivo
};

class NameNodeServiceImpl final : public griddfs::NameNodeService::Service {
public:
    NameNodeServiceImpl();
    ~NameNodeServiceImpl() override = default;

    // MÉTODOS DE AUTENTICACIÓN (NUEVOS)
    grpc::Status LoginUser(grpc::ServerContext* context,
                          const griddfs::LoginRequest* request,
                          griddfs::LoginResponse* response) override;

    grpc::Status RegisterUser(grpc::ServerContext* context,
                             const griddfs::RegisterUserRequest* request,
                             griddfs::RegisterUserResponse* response) override;

    // MÉTODOS EXISTENTES (MODIFICADOS PARA INCLUIR AUTENTICACIÓN)
    grpc::Status CreateFile(grpc::ServerContext* context,
                           const griddfs::CreateFileRequest* request,
                           griddfs::CreateFileResponse* response) override;

    grpc::Status GetFileInfo(grpc::ServerContext* context,
                            const griddfs::GetFileInfoRequest* request,
                            griddfs::GetFileInfoResponse* response) override;

    grpc::Status ListFiles(grpc::ServerContext* context,
                          const griddfs::ListFilesRequest* request,
                          griddfs::ListFilesResponse* response) override;

    grpc::Status DeleteFile(grpc::ServerContext* context,
                           const griddfs::DeleteFileRequest* request,
                           griddfs::DeleteFileResponse* response) override;

    grpc::Status CreateDirectory(grpc::ServerContext* context,
                                const griddfs::CreateDirectoryRequest* request,
                                griddfs::CreateDirectoryResponse* response) override;

    // MÉTODOS DE DATANODE (SIN CAMBIOS)
    grpc::Status RegisterDataNode(grpc::ServerContext* context,
                                 const griddfs::RegisterDataNodeRequest* request,
                                 griddfs::RegisterDataNodeResponse* response) override;

    grpc::Status Heartbeat(grpc::ServerContext* context,
                          const griddfs::HeartbeatRequest* request,
                          griddfs::HeartbeatResponse* response) override;

    grpc::Status BlockReport(grpc::ServerContext* context,
                            const griddfs::BlockReportRequest* request,
                            griddfs::BlockReportResponse* response) override;

private:
    // ESTRUCTURAS EXISTENTES
    std::mutex mu_;
    std::unordered_map<std::string, griddfs::DataNodeInfo> datanodes_;
    std::set<std::string> directories_;
    static constexpr int64_t DEFAULT_BLOCK_SIZE = 64LL * 1024LL * 1024LL;

    // NUEVAS ESTRUCTURAS PARA AUTENTICACIÓN
    std::unordered_map<std::string, UserInfo> users_;           // username -> UserInfo
    std::unordered_map<std::string, UserInfo> users_by_id_;     // user_id -> UserInfo
    std::unordered_map<std::string, FileMetadata> files_;       // filename -> FileMetadata

    // MÉTODOS AUXILIARES NUEVOS
    std::string generateUserId();                               // Genera UUID único
    std::string hashPassword(const std::string& password);     // Hash seguro de contraseña
    bool verifyPassword(const std::string& password, const std::string& hash); // Verifica contraseña
    bool userExists(const std::string& username);              // Verifica si usuario existe
    bool isFileOwner(const std::string& filename, const std::string& user_id); // Verifica propiedad
    
    // MÉTODOS AUXILIARES EXISTENTES
    bool starts_with(const std::string& s, const std::string& prefix) const;
};

#endif // NAMENODE_SERVER_AUTH_H

/*
 * EJEMPLO DE IMPLEMENTACIÓN DE ALGUNOS MÉTODOS:
 * 
 * grpc::Status NameNodeServiceImpl::RegisterUser(grpc::ServerContext* context,
 *                                                const griddfs::RegisterUserRequest* request,
 *                                                griddfs::RegisterUserResponse* response) {
 *     std::lock_guard<std::mutex> lock(mu_);
 *     
 *     // Verificar si el usuario ya existe
 *     if (userExists(request->username())) {
 *         response->set_success(false);
 *         response->set_message("Usuario ya existe");
 *         return grpc::Status::OK;
 *     }
 *     
 *     // Crear nuevo usuario
 *     UserInfo user;
 *     user.user_id = generateUserId();
 *     user.username = request->username();
 *     user.password_hash = hashPassword(request->password());
 *     user.email = request->email();
 *     user.created_time = std::chrono::system_clock::now();
 *     
 *     // Guardar usuario
 *     users_[request->username()] = user;
 *     users_by_id_[user.user_id] = user;
 *     
 *     response->set_success(true);
 *     response->set_user_id(user.user_id);
 *     response->set_message("Usuario registrado exitosamente");
 *     
 *     return grpc::Status::OK;
 * }
 * 
 * grpc::Status NameNodeServiceImpl::CreateFile(grpc::ServerContext* context,
 *                                              const griddfs::CreateFileRequest* request,
 *                                              griddfs::CreateFileResponse* response) {
 *     std::lock_guard<std::mutex> lock(mu_);
 *     
 *     // Verificar que el usuario existe
 *     if (users_by_id_.find(request->user_id()) == users_by_id_.end()) {
 *         return grpc::Status(grpc::StatusCode::UNAUTHENTICATED, "Usuario no válido");
 *     }
 *     
 *     // Verificar si el archivo ya existe
 *     if (files_.find(request->filename()) != files_.end()) {
 *         return grpc::Status(grpc::StatusCode::ALREADY_EXISTS, "Archivo ya existe");
 *     }
 *     
 *     // Crear metadata del archivo
 *     FileMetadata file_meta;
 *     file_meta.filename = request->filename();
 *     file_meta.owner_id = request->user_id();
 *     file_meta.size = request->filesize();
 *     file_meta.created_time = std::chrono::system_clock::now();
 *     
 *     // ... resto de la lógica de creación de bloques ...
 *     
 *     files_[request->filename()] = file_meta;
 *     
 *     return grpc::Status::OK;
 * }
 */
