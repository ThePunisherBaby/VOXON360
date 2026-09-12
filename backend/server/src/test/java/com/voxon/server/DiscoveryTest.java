package com.voxon.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

class DiscoveryTest {
    private static final String REPLY = "{\"service\":\"voxon90\",\"httpPort\":8090}";

    private static void send(DatagramSocket socket, String text, int port) throws Exception {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        socket.send(new DatagramPacket(bytes, bytes.length, InetAddress.getLoopbackAddress(), port));
    }

    @Test
    void respondeALaBusquedaEnLaRedLocal() throws Exception {
        try (Discovery discovery = new Discovery(0, () -> REPLY); DatagramSocket client = new DatagramSocket()) {
            client.setSoTimeout(3000);
            send(client, Discovery.REQUEST, discovery.port());

            DatagramPacket reply = new DatagramPacket(new byte[512], 512);
            client.receive(reply);
            assertEquals(REPLY, new String(reply.getData(), 0, reply.getLength(), StandardCharsets.UTF_8));
        }
    }

    @Test
    void ignoraMensajesDesconocidos() throws Exception {
        try (Discovery discovery = new Discovery(0, () -> REPLY); DatagramSocket client = new DatagramSocket()) {
            client.setSoTimeout(300);
            send(client, "HOLA", discovery.port());
            assertThrows(SocketTimeoutException.class, () -> client.receive(new DatagramPacket(new byte[512], 512)));
        }
    }
}
