package com.voxon.server.cloud;

import com.voxon.server.json.Json;
import java.util.Map;

/** Lo que la API local necesita del servicio en la nube (Firebase). */
public interface CloudService {
    /** Estado para mostrar en ajustes. No lanza. */
    Map<String, Object> status();

    /** Vincula este negocio con el código que muestra la app del dueño. */
    Map<String, Object> link(String code, String ownerUserId);

    /** Deja de sincronizar y quita este equipo del negocio en Firebase si hay conexión. */
    Map<String, Object> unlink();

    /** Hubo cambios locales: sincronizar pronto. */
    void markDirty();

    /** Servicio apagado: no se configuró un proyecto de Firebase al arrancar el servidor. */
    static CloudService disabled() {
        return new CloudService() {
            @Override
            public Map<String, Object> status() {
                return Json.object("configured", false, "linked", false);
            }

            @Override
            public Map<String, Object> link(String code, String ownerUserId) {
                throw notConfigured();
            }

            @Override
            public Map<String, Object> unlink() {
                throw notConfigured();
            }

            @Override
            public void markDirty() {
                // Nada que sincronizar.
            }
        };
    }

    private static CloudException notConfigured() {
        return new CloudException("cloud_not_configured",
                "El servidor arrancó sin proyecto de Firebase (--firebase-project y --firebase-api-key)");
    }
}
