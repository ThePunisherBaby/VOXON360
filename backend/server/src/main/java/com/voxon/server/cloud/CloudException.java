package com.voxon.server.cloud;

/** Error del servicio en la nube con un código estable, como los del motor. */
public final class CloudException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    /** Sin internet, Firebase no responde o se agotó la cuota: se reintenta más tarde. */
    public static final String OFFLINE = "cloud_offline";

    private final String code;

    public CloudException(String code, String message) {
        super(message);
        this.code = code;
    }

    public CloudException(String code, String message, Throwable cause) {
        super(message, cause);
        this.code = code;
    }

    public String code() {
        return code;
    }

    public boolean isOffline() {
        return OFFLINE.equals(code);
    }
}
