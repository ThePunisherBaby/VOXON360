import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/core/backend/server_discovery.dart';

void main() {
  test('encuentra la caja principal que responde en la red', () async {
    final responder = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    responder.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = responder.receive();
      if (datagram == null) return;
      if (utf8.decode(datagram.data) != ServerDiscovery.request) return;
      responder.send(
        utf8.encode(
          jsonEncode({
            'service': 'voxon90',
            'name': 'Colmado La Esquina',
            'httpPort': 8090,
            'version': '0.1.0',
          }),
        ),
        datagram.address,
        datagram.port,
      );
    });
    addTearDown(responder.close);

    final servers = await ServerDiscovery.find(
      wait: const Duration(milliseconds: 500),
      port: responder.port,
      target: InternetAddress.loopbackIPv4,
    );

    expect(servers, hasLength(1));
    expect(servers.single.name, 'Colmado La Esquina');
    expect(servers.single.baseUri.toString(), 'http://127.0.0.1:8090');
  });

  test('ignora respuestas que no son de VOXON90', () async {
    final responder = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    responder.listen((event) {
      final datagram = responder.receive();
      if (datagram == null) return;
      responder.send(utf8.encode('hola'), datagram.address, datagram.port);
    });
    addTearDown(responder.close);

    final servers = await ServerDiscovery.find(
      wait: const Duration(milliseconds: 300),
      port: responder.port,
      target: InternetAddress.loopbackIPv4,
    );

    expect(servers, isEmpty);
  });
}
