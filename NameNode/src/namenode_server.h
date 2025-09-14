#ifndef NAMENODE_SERVER_H
#define NAMENODE_SERVER_H

#include <grpcpp/grpcpp.h>
#include "griddfs.grpc.pb.h"

#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>
#include <set>
#include <chrono>

// Estructura para almacenar información de usuario
struct UserInfo {
    std::string user_id;      
    std::string username;     
    std::string password_hash; 
    std::chrono::system_clock::time_point created_time;
};

// Estructura para metadata de archivos con información de propietario
struct FileMetadata {
    std::string filename;
    std::string owner_id;     
    int64_t size;
    std::chrono::system_clock::time_point created_time;
    std::vector<griddfs::BlockInfo> blocks;
};

class NameNodeServiceImpl final : public griddfs::NameNodeService::Service {
public:
    NameNodeServiceImpl();
    ~NameNodeServiceImpl() override = default;

    // Servicios de autenticación
    grpc::Status LoginUser(grpc::ServerContext* context,
                          const griddfs::LoginRequest* request,
                          griddfs::LoginResponse* response) override;

    grpc::Status RegisterUser(grpc::ServerContext* context,
                             const griddfs::RegisterUserRequest* request,
                             griddfs::RegisterUserResponse* response) override;


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

    grpc::Status RemoveDirectory(grpc::ServerContext* context,
                                 const griddfs::RemoveDirectoryRequest* request,
                                 griddfs::RemoveDirectoryResponse* response) override;

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
    // sincronización y estructuras internas
    std::mutex mu_;
    
    // Estructuras de autenticación
    std::unordered_map<std::string, UserInfo> users_;           // username -> UserInfo
    std::unordered_map<std::string, UserInfo> users_by_id_;     // user_id -> UserInfo
    std::unordered_map<std::string, FileMetadata> files_;       // filename -> FileMetadata
    
    // Estructuras originales para DataNodes
    std::unordered_map<std::string, griddfs::DataNodeInfo> datanodes_;
    std::set<std::string> directories_;

    static constexpr int64_t DEFAULT_BLOCK_SIZE = 64LL * 1024LL * 1024LL; // 64 MiB

    // Métodos auxiliares de autenticación
    std::string generateUserId();
    std::string hashPassword(const std::string& password);
    bool verifyPassword(const std::string& password, const std::string& hash);
    bool userExists(const std::string& username);
    bool isFileOwner(const std::string& filename, const std::string& user_id);
    bool isValidUser(const std::string& user_id);

    // helper original
    bool starts_with(const std::string& s, const std::string& prefix) const;
};

#endif // NAMENODE_SERVER_H
