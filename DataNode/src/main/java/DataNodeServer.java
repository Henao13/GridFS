import io.grpc.Server;
import io.grpc.ServerBuilder;
import io.grpc.stub.StreamObserver;
import io.grpc.ManagedChannel;
import io.grpc.ManagedChannelBuilder;

import griddfs.DataNodeServiceGrpc;
import griddfs.WriteBlockRequest;
import griddfs.WriteBlockResponse;
import griddfs.ReadBlockRequest;
import griddfs.ReadBlockResponse;
import griddfs.DeleteBlockRequest;
import griddfs.DeleteBlockResponse;

import griddfs.NameNodeServiceGrpc;
import griddfs.DataNodeInfo;
import griddfs.RegisterDataNodeRequest;
import griddfs.RegisterDataNodeResponse;
import griddfs.HeartbeatRequest;
import griddfs.HeartbeatResponse;

import java.io.IOException;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.TimeUnit;

public class DataNodeServer {
    private final int port;
    private final Server server;
    private final BlockStorage storage;

    private final String datanodeId;
    private final String namenodeHost;
    private final int namenodePort;

    private ManagedChannel namenodeChannel;
    private NameNodeServiceGrpc.NameNodeServiceBlockingStub namenodeStub;
    private volatile boolean registered = false;
    private Timer heartbeatTimer;

    public DataNodeServer(int port, String storageDir, String datanodeId,
                          String namenodeHost, int namenodePort) throws IOException {
        this.port = port;
        this.datanodeId = datanodeId;
        this.namenodeHost = namenodeHost;
        this.namenodePort = namenodePort;

        this.storage = new BlockStorage(storageDir);
        this.server = ServerBuilder.forPort(port)
                .addService(new DataNodeServiceImpl(storage))
                .build();
    }

    public void start() throws IOException {
        server.start();
        System.out.println("DataNode [" + datanodeId + "] listening on port " + port);

        // Conectar con NameNode con reintentos
        connectToNameNode();

        // Intentar registro inicial (no bloquea si falla)
        tryRegisterWithNameNode();

        // Heartbeat cada 5s
        startHeartbeatTimer();

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.err.println("Shutting down DataNode server...");
            DataNodeServer.this.stop();
        }));
    }

    private void connectToNameNode() {
        if (namenodeChannel != null) {
            namenodeChannel.shutdown();
        }
        
        namenodeChannel = io.grpc.netty.shaded.io.grpc.netty.NettyChannelBuilder
                .forAddress(namenodeHost, namenodePort)
                .usePlaintext()
                .keepAliveTime(30, TimeUnit.SECONDS)
                .keepAliveTimeout(5, TimeUnit.SECONDS)
                .keepAliveWithoutCalls(true)
                .maxInboundMessageSize(4 * 1024 * 1024)
                .build();
        namenodeStub = NameNodeServiceGrpc.newBlockingStub(namenodeChannel);
    }

    private void tryRegisterWithNameNode() {
        new Thread(() -> {
            int retryCount = 0;
            int maxRetries = 10;
            long baseDelay = 1000; // 1 segundo
            
            while (!registered && retryCount < maxRetries) {
                try {
                    RegisterDataNodeRequest req = RegisterDataNodeRequest.newBuilder()
                            .setDatanode(DataNodeInfo.newBuilder()
                                    .setId(datanodeId)
                                    .setAddress("localhost:" + port)
                                    .setCapacity(10_000_000_000L)
                                    .setFreeSpace(10_000_000_000L)
                                    .build())
                            .build();

                    RegisterDataNodeResponse resp = namenodeStub.registerDataNode(req);
                    if (resp.getSuccess()) {
                        registered = true;
                        System.out.println("✓ Registro exitoso en NameNode");
                        return;
                    } else {
                        System.err.println("✗ Registro rechazado por NameNode");
                    }
                } catch (Exception e) {
                    retryCount++;
                    long delay = Math.min(baseDelay * (1L << Math.min(retryCount - 1, 6)), 30000); // max 30s
                    System.err.println("Error conectando con NameNode (intento " + retryCount + "/" + maxRetries + "): " + e.getMessage());
                    
                    if (retryCount < maxRetries) {
                        System.out.println("Reintentando en " + (delay / 1000) + " segundos...");
                        try {
                            Thread.sleep(delay);
                        } catch (InterruptedException ie) {
                            Thread.currentThread().interrupt();
                            return;
                        }
                    }
                }
            }
            
            if (!registered) {
                System.err.println("⚠ No se pudo registrar con NameNode después de " + maxRetries + " intentos. Continuando sin registro...");
                System.err.println("  El DataNode seguirá intentando conectarse via heartbeat.");
            }
        }).start();
    }

    private void startHeartbeatTimer() {
        heartbeatTimer = new Timer(true);
        heartbeatTimer.scheduleAtFixedRate(new TimerTask() {
            @Override
            public void run() {
                try {
                    HeartbeatRequest hbReq = HeartbeatRequest.newBuilder()
                            .setDatanodeId(datanodeId)
                            .setFreeSpace(storage.getFreeSpace())
                            .build();
                    HeartbeatResponse hbResp = namenodeStub.heartbeat(hbReq);
                    
                    if (hbResp.getSuccess()) {
                        if (!registered) {
                            registered = true;
                            System.out.println("✓ Reconectado con NameNode via heartbeat");
                        }
                    } else {
                        System.err.println("✗ Heartbeat rechazado - DataNode no reconocido");
                        handleHeartbeatFailure();
                    }
                } catch (Exception e) {
                    System.err.println("✗ Error en heartbeat: " + e.getMessage());
                    handleHeartbeatFailure();
                }
            }
        }, 0, 5000);
    }

    private void handleHeartbeatFailure() {
        if (registered) {
            System.err.println("⚠ Perdida conexión con NameNode. Intentando reconectar...");
            registered = false;
        }
        
        // Intentar reconectar y re-registrar
        new Thread(() -> {
            try {
                connectToNameNode();
                Thread.sleep(1000); // Esperar un poco antes de intentar registrarse
                tryRegisterWithNameNode();
            } catch (Exception e) {
                System.err.println("Error en reconexión: " + e.getMessage());
            }
        }).start();
    }

    public void stop() {
        registered = false;
        
        if (heartbeatTimer != null) {
            heartbeatTimer.cancel();
        }
        
        if (server != null) {
            server.shutdown();
        }
        
        if (namenodeChannel != null) {
            namenodeChannel.shutdown();
            try {
                if (!namenodeChannel.awaitTermination(5, TimeUnit.SECONDS)) {
                    namenodeChannel.shutdownNow();
                }
            } catch (InterruptedException e) {
                namenodeChannel.shutdownNow();
                Thread.currentThread().interrupt();
            }
        }
    }

    public void blockUntilShutdown() throws InterruptedException {
        if (server != null) {
            server.awaitTermination();
        }
    }

    // =======================
    // Implementación servicio
    // =======================
    static class DataNodeServiceImpl extends DataNodeServiceGrpc.DataNodeServiceImplBase {
        private final BlockStorage storage;

        DataNodeServiceImpl(BlockStorage storage) {
            this.storage = storage;
        }

        @Override
        public StreamObserver<WriteBlockRequest> writeBlock(
                StreamObserver<WriteBlockResponse> responseObserver) {
            return new StreamObserver<>() {
                private String blockId = null;
                private final java.io.ByteArrayOutputStream buffer = new java.io.ByteArrayOutputStream();

                @Override
                public void onNext(WriteBlockRequest req) {
                    if (blockId == null) {
                        blockId = req.getBlockId();
                    }
                    try {
                        buffer.write(req.getData().toByteArray());
                    } catch (IOException e) {
                        responseObserver.onError(e);
                    }
                }

                @Override
                public void onError(Throwable t) {
                    System.err.println("[WriteBlock ERROR] " + t.getMessage());
                }

                @Override
                public void onCompleted() {
                    boolean ok = storage.writeBlock(blockId, buffer.toByteArray());
                    WriteBlockResponse resp = WriteBlockResponse.newBuilder()
                            .setSuccess(ok)
                            .build();
                    responseObserver.onNext(resp);
                    responseObserver.onCompleted();
                    System.out.println("[WriteBlock] " + blockId + " (" + buffer.size() + " bytes)");
                }
            };
        }

        @Override
        public void readBlock(ReadBlockRequest req,
                              StreamObserver<ReadBlockResponse> responseObserver) {
            String blockId = req.getBlockId();
            byte[] data = storage.readBlock(blockId);
            if (data == null) {
                responseObserver.onError(new RuntimeException("Block not found: " + blockId));
                return;
            }
            int chunkSize = 128 * 1024;
            for (int i = 0; i < data.length; i += chunkSize) {
                int end = Math.min(i + chunkSize, data.length);
                byte[] chunk = java.util.Arrays.copyOfRange(data, i, end);
                ReadBlockResponse resp = ReadBlockResponse.newBuilder()
                        .setData(com.google.protobuf.ByteString.copyFrom(chunk))
                        .build();
                responseObserver.onNext(resp);
            }
            responseObserver.onCompleted();
            System.out.println("[ReadBlock] " + blockId + " (" + data.length + " bytes)");
        }

        @Override
        public void deleteBlock(DeleteBlockRequest req,
                                StreamObserver<DeleteBlockResponse> responseObserver) {
            boolean ok = storage.deleteBlock(req.getBlockId());
            DeleteBlockResponse resp = DeleteBlockResponse.newBuilder()
                    .setSuccess(ok)
                    .build();
            responseObserver.onNext(resp);
            responseObserver.onCompleted();
            System.out.println("[DeleteBlock] " + req.getBlockId() + " -> " + ok);
        }
    }

    // =======================
    // Main
    // =======================
    public static void main(String[] args) throws IOException, InterruptedException {
        int port = args.length > 0 ? Integer.parseInt(args[0]) : 50051;
        String storageDir = args.length > 1 ? args[1] : "/tmp/datanode";
        String datanodeId = args.length > 2 ? args[2] : "datanode1";
        String namenodeHost = args.length > 3 ? args[3] : "localhost";
        int namenodePort = args.length > 4 ? Integer.parseInt(args[4]) : 50070;

        DataNodeServer server = new DataNodeServer(port, storageDir, datanodeId, namenodeHost, namenodePort);
        server.start();
        server.blockUntilShutdown();
    }
}
