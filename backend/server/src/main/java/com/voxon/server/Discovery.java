package com.voxon.server;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.net.SocketException;
import java.nio.charset.StandardCharsets;
import java.util.function.Supplier;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Descubrimiento en la red local sin internet: un equipo envía por UDP el texto
 * {@value #REQUEST} (en difusión) y el servidor responde con un JSON que dice
 * cómo conectarse. Así nadie tiene que escribir la IP de la caja principal.
 */
public final class Discovery implements AutoCloseable {
    public static final int DEFAULT_PORT = 47800;
    public static final String REQUEST = "VOXON90_DISCOVER";

    private static final Logger LOG = Logger.getLogger(Discovery.class.getName());

    private final DatagramSocket socket;
    private final Supplier<String> reply;

    public Discovery(int port, Supplier<String> reply) throws SocketException {
        this.reply = reply;
        this.socket = new DatagramSocket(null);
        socket.setReuseAddress(true);
        socket.bind(new InetSocketAddress(port));
        Thread thread = new Thread(this::run, "voxon-discovery");
        thread.setDaemon(true);
        thread.start();
    }

    public int port() {
        return socket.getLocalPort();
    }

    private void run() {
        byte[] buffer = new byte[256];
        while (!socket.isClosed()) {
            DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
            try {
                socket.receive(packet);
                String message = new String(packet.getData(), 0, packet.getLength(), StandardCharsets.UTF_8).trim();
                if (REQUEST.equals(message)) {
                    byte[] answer = reply.get().getBytes(StandardCharsets.UTF_8);
                    socket.send(new DatagramPacket(answer, answer.length, packet.getSocketAddress()));
                }
            } catch (IOException | RuntimeException e) {
                if (socket.isClosed()) {
                    return;
                }
                LOG.log(Level.FINE, "Descubrimiento: solicitud ignorada", e);
            }
        }
    }

    @Override
    public void close() {
        socket.close();
    }
}
