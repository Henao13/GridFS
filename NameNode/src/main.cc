#include <iostream>
#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>

#include "namenode_server.h"
#include "griddfs.grpc.pb.h" 


int main(int argc, char** argv) {
    std::string server_address = "0.0.0.0:50050";
    NameNodeServiceImpl service;

    grpc::ServerBuilder builder;
    // Escuchar en la dirección
    builder.AddListeningPort(server_address, grpc::InsecureServerCredentials());
    // Registrar servicio
    builder.RegisterService(&service);

    std::unique_ptr<grpc::Server> server(builder.BuildAndStart());
    if (!server) {
        std::cerr << "Fallo al iniciar el servidor gRPC\n";
        return 1;
    }

    std::cout << "NameNode escuchando en " << server_address << std::endl;
    server->Wait();
    return 0;
}
