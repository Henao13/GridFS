cmake_minimum_required(VERSION 3.14)
project(NameNode LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Busca protobuf y gRPC
find_package(Protobuf REQUIRED)
find_package(gRPC REQUIRED)

# Directorio donde están los stubs .pb.* generados (en el mismo src)
set(PROTO_GEN_DIR ${CMAKE_SOURCE_DIR})

# Includes
include_directories(${Protobuf_INCLUDE_DIRS} ${PROTO_GEN_DIR} ${CMAKE_SOURCE_DIR}/third_party)

# Fuentes
set(SRC_MAIN
    main.cc
    namenode_server.cc
    ${PROTO_GEN_DIR}/griddfs.pb.cc
    ${PROTO_GEN_DIR}/griddfs.grpc.pb.cc
)

add_executable(namenode ${SRC_MAIN})

# Librerías básicas
set(EXTRA_LIBS
    gRPC::grpc++
    protobuf::libprotobuf
    pthread
    dl
)

# Detecta si existe utf8_range y lo agrega
find_library(UTF8_RANGE_LIB utf8_range HINTS /usr/local/lib /usr/lib /lib)
if (UTF8_RANGE_LIB)
    message(STATUS "Found utf8_range: ${UTF8_RANGE_LIB}")
    list(APPEND EXTRA_LIBS ${UTF8_RANGE_LIB})
else()
    message(WARNING "utf8_range not found, protobuf may fail to link if required.")
endif()

# Detecta si existe utf8_validity y lo agrega
find_library(UTF8_VALIDITY_LIB utf8_validity HINTS /usr/local/lib /usr/lib /lib)
if (UTF8_VALIDITY_LIB)
    message(STATUS "Found utf8_validity: ${UTF8_VALIDITY_LIB}")
    list(APPEND EXTRA_LIBS ${UTF8_VALIDITY_LIB})
else()
    message(WARNING "utf8_validity not found, protobuf may fail to link if required.")
endif()

# Vincular con todo
target_link_libraries(namenode PRIVATE ${EXTRA_LIBS})
