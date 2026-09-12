package com.voxon.server.cloud;

import com.voxon.server.json.Json;
import com.voxon.server.json.JsonException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.Map;
import java.util.Optional;
import java.util.logging.Level;
import java.util.logging.Logger;

/** Vínculo de este negocio con Firebase, guardado en un archivo junto a la base de datos. */
public final class CloudLinkStore {
    private static final Logger LOG = Logger.getLogger(CloudLinkStore.class.getName());

    /**
     * Datos del vínculo. {@code refreshToken} es un secreto: el archivo queda legible solo por el usuario
     * del sistema que corre el servidor.
     */
    public record CloudLink(String businessId, String deviceUid, String refreshToken, String ownerUserId,
            String linkedAt) {
    }

    private final Path file;

    public CloudLinkStore(Path file) {
        this.file = file;
    }

    public synchronized Optional<CloudLink> load() {
        if (!Files.isRegularFile(file)) {
            return Optional.empty();
        }
        try {
            Map<String, Object> json = Json.parseObject(Files.readString(file, StandardCharsets.UTF_8));
            CloudLink link = new CloudLink(Json.stringOrNull(json, "businessId"), Json.stringOrNull(json, "deviceUid"),
                    Json.stringOrNull(json, "refreshToken"), Json.stringOrNull(json, "ownerUserId"),
                    Json.stringOrNull(json, "linkedAt"));
            if (link.businessId() == null || link.deviceUid() == null || link.refreshToken() == null
                    || link.ownerUserId() == null) {
                LOG.warning("El vínculo con la nube está incompleto; se ignora: " + file);
                return Optional.empty();
            }
            return Optional.of(link);
        } catch (IOException | JsonException e) {
            LOG.log(Level.WARNING, "No se pudo leer el vínculo con la nube: " + file, e);
            return Optional.empty();
        }
    }

    public synchronized void save(CloudLink link) {
        try {
            Path directory = file.toAbsolutePath().getParent();
            if (directory != null) {
                Files.createDirectories(directory);
            }
            Path temp = file.resolveSibling(file.getFileName() + ".tmp");
            Files.writeString(temp, Json.stringify(Json.object(
                    "businessId", link.businessId(),
                    "deviceUid", link.deviceUid(),
                    "refreshToken", link.refreshToken(),
                    "ownerUserId", link.ownerUserId(),
                    "linkedAt", link.linkedAt())), StandardCharsets.UTF_8);
            restrictToOwner(temp);
            try {
                Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
            } catch (AtomicMoveNotSupportedException e) {
                Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING);
            }
        } catch (IOException e) {
            throw new CloudException("cloud_link_unwritable", "No se pudo guardar el vínculo con la nube", e);
        }
    }

    public synchronized void delete() {
        try {
            Files.deleteIfExists(file);
        } catch (IOException e) {
            throw new CloudException("cloud_link_unwritable", "No se pudo borrar el vínculo con la nube", e);
        }
    }

    private static void restrictToOwner(Path path) {
        try {
            Files.setPosixFilePermissions(path, PosixFilePermissions.fromString("rw-------"));
        } catch (UnsupportedOperationException | IOException e) {
            // Windows: el archivo hereda los permisos de la carpeta del usuario.
            LOG.log(Level.FINE, "Sin permisos POSIX para " + path, e);
        }
    }
}
