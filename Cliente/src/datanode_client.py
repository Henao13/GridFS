import grpc
from .griddfs import griddfs_pb2 as pb2
from .griddfs import griddfs_pb2_grpc as pb2_grpc


class DataNodeClient:
    def __init__(self, host="localhost", port=50051):
        channel = grpc.insecure_channel(f"{host}:{port}")
        self.stub = pb2_grpc.DataNodeServiceStub(channel)

    def write_block(self, block_id, data, chunk_size=64*1024):
        def request_generator():
            for i in range(0, len(data), chunk_size):
                yield pb2.WriteBlockRequest(
                    block_id=block_id,
                    data=data[i:i+chunk_size]
                )
        return self.stub.WriteBlock(request_generator())

    def read_block(self, block_id):
        req = pb2.ReadBlockRequest(block_id=block_id)
        chunks = []
        for resp in self.stub.ReadBlock(req):
            chunks.append(resp.data)
        return b"".join(chunks)

    def delete_block(self, block_id):
        req = pb2.DeleteBlockRequest(block_id=block_id)
        return self.stub.DeleteBlock(req)
