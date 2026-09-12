package com.voxon.server.cloud;

/** Proyecto de Firebase y direcciones de sus API REST: producción o emuladores locales. */
public record FirebaseSettings(
        String projectId,
        String apiKey,
        String identityToolkitUrl,
        String secureTokenUrl,
        String firestoreUrl) {

    public static FirebaseSettings production(String projectId, String apiKey) {
        return new FirebaseSettings(projectId, apiKey, "https://identitytoolkit.googleapis.com/v1",
                "https://securetoken.googleapis.com/v1", "https://firestore.googleapis.com/v1");
    }

    /** Emuladores de Firebase en {@code host}: Auth en el puerto 9099 y Firestore en el 8080. */
    public static FirebaseSettings emulator(String host, String projectId) {
        String base = "http://" + host;
        return new FirebaseSettings(projectId, "emulador", base + ":9099/identitytoolkit.googleapis.com/v1",
                base + ":9099/securetoken.googleapis.com/v1", base + ":8080/v1");
    }

    /** Raíz de los documentos: {@code projects/<id>/databases/(default)/documents}. */
    public String documentsRoot() {
        return "projects/" + projectId + "/databases/(default)/documents";
    }
}
