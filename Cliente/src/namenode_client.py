import grpc
from .griddfs import griddfs_pb2 as pb2
from .griddfs import griddfs_pb2_grpc as pb2_grpc


class NameNodeClient:
    def __init__(self, host="localhost", port=50050):
        channel = grpc.insecure_channel(f"{host}:{port}")
        self.stub = pb2_grpc.NameNodeServiceStub(channel)
        self.user_id = None  # Se establece después del login

    def login(self, username, password):
        """Autentica al usuario y establece user_id"""
        req = pb2.LoginRequest(username=username, password=password)
        resp = self.stub.LoginUser(req)
        if resp.success:
            self.user_id = resp.user_id
        return resp

    def register_user(self, username, password):
        """Registra un nuevo usuario"""
        req = pb2.RegisterUserRequest(username=username, password=password)
        return self.stub.RegisterUser(req)

    def create_file(self, filename, filesize):
        if not self.user_id:
            raise Exception("Usuario no autenticado. Debe hacer login primero.")
        req = pb2.CreateFileRequest(filename=filename, filesize=filesize, user_id=self.user_id)
        return self.stub.CreateFile(req)

    def get_file_info(self, filename):
        if not self.user_id:
            raise Exception("Usuario no autenticado. Debe hacer login primero.")
        req = pb2.GetFileInfoRequest(filename=filename, user_id=self.user_id)
        return self.stub.GetFileInfo(req)

    def list_files(self, directory):
        if not self.user_id:
            raise Exception("Usuario no autenticado. Debe hacer login primero.")
        req = pb2.ListFilesRequest(directory=directory, user_id=self.user_id)
        return self.stub.ListFiles(req)

    def delete_file(self, filename):
        if not self.user_id:
            raise Exception("Usuario no autenticado. Debe hacer login primero.")
        req = pb2.DeleteFileRequest(filename=filename, user_id=self.user_id)
        return self.stub.DeleteFile(req)

    def create_directory(self, directory):
        if not self.user_id:
            raise Exception("Usuario no autenticado. Debe hacer login primero.")
        req = pb2.CreateDirectoryRequest(directory=directory, user_id=self.user_id)
        return self.stub.CreateDirectory(req)

    def remove_directory(self, directory):
        if not self.user_id:
            raise Exception("Usuario no autenticado. Debe hacer login primero.")
        req = pb2.RemoveDirectoryRequest(directory=directory, user_id=self.user_id)
        return self.stub.RemoveDirectory(req)
