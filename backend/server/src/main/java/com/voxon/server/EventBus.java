package com.voxon.server;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Eventos en vivo (Server-Sent Events) para los equipos conectados: la pantalla
 * de cocina, las cajas y los teléfonos de los meseros se actualizan solos.
 */
public final class EventBus implements AutoCloseable {
    /** Un equipo suscrito. El hilo de su conexión espera hasta que se desconecte. */
    public static final class Subscriber {
        private final OutputStream out;
        private final CountDownLatch closed = new CountDownLatch(1);

        private Subscriber(OutputStream out) {
            this.out = out;
        }

        private synchronized void send(String text) throws IOException {
            out.write(text.getBytes(StandardCharsets.UTF_8));
            out.flush();
        }

        /** Bloquea hasta que la conexión se cierre. */
        public void awaitClose() throws InterruptedException {
            closed.await();
        }
    }

    private final Set<Subscriber> subscribers = ConcurrentHashMap.newKeySet();
    private final ScheduledExecutorService heartbeat = Executors.newSingleThreadScheduledExecutor(runnable -> {
        Thread thread = new Thread(runnable, "voxon-sse-heartbeat");
        thread.setDaemon(true);
        return thread;
    });

    public EventBus(long heartbeatSeconds) {
        // Un comentario periódico mantiene viva la conexión y detecta equipos desconectados.
        heartbeat.scheduleAtFixedRate(() -> broadcast(": ping\n\n"), heartbeatSeconds, heartbeatSeconds,
                TimeUnit.SECONDS);
    }

    public Subscriber subscribe(OutputStream out) {
        Subscriber subscriber = new Subscriber(out);
        subscribers.add(subscriber);
        deliver(subscriber, ": conectado\n\n");
        return subscriber;
    }

    /** Envía un evento con datos JSON a todos los equipos conectados. */
    public void publish(String event, String dataJson) {
        broadcast("event: " + event + "\ndata: " + dataJson + "\n\n");
    }

    public int subscriberCount() {
        return subscribers.size();
    }

    @Override
    public void close() {
        heartbeat.shutdownNow();
        for (Subscriber subscriber : subscribers) {
            drop(subscriber);
        }
    }

    private void broadcast(String text) {
        for (Subscriber subscriber : subscribers) {
            deliver(subscriber, text);
        }
    }

    private void deliver(Subscriber subscriber, String text) {
        try {
            subscriber.send(text);
        } catch (IOException e) {
            drop(subscriber);
        }
    }

    // Solo despierta al hilo de la conexión: él cierra el intercambio HTTP.
    // Cerrarlo desde otro hilo rompe el estado interno del servidor HTTP del JDK.
    private void drop(Subscriber subscriber) {
        if (subscribers.remove(subscriber)) {
            subscriber.closed.countDown();
        }
    }
}
