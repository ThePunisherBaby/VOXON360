package com.voxon.server;

import com.voxon.core.CoreGateway;
import com.voxon.core.VoxonCore;
import com.voxon.server.cloud.CloudLinkStore;
import com.voxon.server.cloud.CloudService;
import com.voxon.server.cloud.CloudSync;
import com.voxon.server.cloud.FirebaseClient;
import com.voxon.server.json.Json;
import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.SocketException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/** Arranca el servidor local: motor, API HTTP, eventos, descubrimiento en la red y, si se configuró, la nube. */
public final class Main {
    private static final Logger LOG = Logger.getLogger(Main.class.getName());

    private Main() {
    }

    public static void main(String[] args) {
        if (Arrays.asList(args).contains("--help")) {
            System.out.println(ServerConfig.USAGE);
            return;
        }
        ServerConfig config;
        try {
            config = ServerConfig.fromArgs(args, System.getenv());
        } catch (IllegalArgumentException e) {
            System.err.println(e.getMessage());
            System.err.println(ServerConfig.USAGE);
            System.exit(2);
            return;
        }
        try {
            start(config);
        } catch (Exception e) {
            LOG.log(Level.SEVERE, "No se pudo iniciar el servidor", e);
            System.exit(1);
        }
    }

    static void start(ServerConfig config) throws Exception {
        Path database = config.databasePath().toAbsolutePath();
        Files.createDirectories(database.getParent());
        VoxonCore.loadLibrary(config.coreLibrary());
        VoxonCore core = VoxonCore.open(database.toString(),
                Json.stringify(Json.object("pinIterations", (long) config.pinIterations())));

        CloudSync cloudSync = config.cloudEnabled() ? startCloudSync(config, core, database) : null;
        EventBus events = new EventBus(15);
        SessionStore sessions = new SessionStore(Duration.ofHours(12), Clock.systemUTC());
        ApiServer server = new ApiServer(core, sessions, events,
                new InetSocketAddress(config.bindAddress(), config.port()), config.webDir(), config.backupDir(),
                cloudSync != null ? cloudSync : CloudService.disabled());
        server.start();
        Discovery discovery = config.discovery()
                ? new Discovery(config.discoveryPort(), () -> discoveryReply(core, server.port()))
                : null;

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            if (discovery != null) {
                discovery.close();
            }
            if (cloudSync != null) {
                cloudSync.close();
            }
            server.close();
            events.close();
            core.close();
        }, "voxon-shutdown"));

        LOG.info(() -> "VOXON90 listo. Motor " + VoxonCore.version() + ", base de datos " + database);
        for (String address : lanAddresses()) {
            LOG.info("Abre en los equipos del negocio: http://" + address + ":" + server.port() + "/");
        }
    }

    /** Sincronización con la app del dueño. El vínculo se guarda junto a la base de datos. */
    private static CloudSync startCloudSync(ServerConfig config, CoreGateway core, Path database) {
        Clock clock = Clock.systemUTC();
        CloudSync sync = new CloudSync(core, new FirebaseClient(config.firebaseSettings(), clock),
                new CloudLinkStore(database.resolveSibling("vinculo-nube.json")), clock,
                Duration.ofSeconds(config.cloudIntervalSeconds()));
        sync.start();
        LOG.info(() -> "App del dueño: sincroniza con el proyecto de Firebase " + config.firebaseProjectId());
        return sync;
    }

    /** Respuesta al descubrimiento: nombre del negocio y puerto de la API. */
    static String discoveryReply(CoreGateway core, int port) {
        Map<String, Object> status = Json.parseObject(core.execute("{\"method\":\"business.status\"}"));
        Map<String, Object> business = Json.objectOrEmpty(Json.objectOrEmpty(status, "result"), "business");
        return Json.stringify(Json.object("service", "voxon90", "name", business.get("name"), "httpPort", (long) port,
                "version", VoxonCore.version()));
    }

    private static List<String> lanAddresses() {
        List<String> addresses = new ArrayList<>();
        try {
            for (NetworkInterface network : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!network.isUp() || network.isLoopback()) {
                    continue;
                }
                for (InetAddress address : Collections.list(network.getInetAddresses())) {
                    if (address instanceof Inet4Address) {
                        addresses.add(address.getHostAddress());
                    }
                }
            }
        } catch (SocketException e) {
            LOG.log(Level.FINE, "No se pudieron listar las interfaces de red", e);
        }
        if (addresses.isEmpty()) {
            addresses.add("localhost");
        }
        return addresses;
    }
}
