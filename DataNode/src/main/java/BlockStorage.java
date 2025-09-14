import java.io.File;
import java.io.FileOutputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;

public class BlockStorage {
    private final String storageDir;

    public BlockStorage(String storageDir) throws IOException {
        this.storageDir = storageDir;
        Files.createDirectories(Paths.get(storageDir));
    }

    public synchronized boolean writeBlock(String blockId, byte[] data) {
        try {
            File blockFile = new File(storageDir, blockId);
            // Crear directorio padre si no existe
            File parentDir = blockFile.getParentFile();
            if (parentDir != null && !parentDir.exists()) {
                parentDir.mkdirs();
            }
            
            try (FileOutputStream fos = new FileOutputStream(blockFile)) {
                fos.write(data);
                return true;
            }
        } catch (IOException e) {
            e.printStackTrace();
            return false;
        }
    }

    public synchronized long getFreeSpace() {
        File dir = new File(storageDir);
        return dir.getUsableSpace();
    }


    public synchronized byte[] readBlock(String blockId) {
        File f = new File(storageDir, blockId);
        if (!f.exists()) return null;
        try (FileInputStream fis = new FileInputStream(f)) {
            return fis.readAllBytes();
        } catch (IOException e) {
            e.printStackTrace();
            return null;
        }
    }

    public synchronized boolean deleteBlock(String blockId) {
        File f = new File(storageDir, blockId);
        return f.delete();
    }
}
