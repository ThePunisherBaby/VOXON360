import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90/core/backend/backend_providers.dart';
import 'package:voxon90/core/core_providers.dart';
import 'package:voxon90/core/storage/key_value_store.dart';

void main() {
  group('parseServerAddress', () {
    test('acepta IP con o sin puerto y con esquema', () {
      expect(
        parseServerAddress('192.168.1.10').toString(),
        'http://192.168.1.10:8090',
      );
      expect(
        parseServerAddress(' 192.168.1.10:9000 ').toString(),
        'http://192.168.1.10:9000',
      );
      expect(
        parseServerAddress('http://caja.local:8090/').toString(),
        'http://caja.local:8090',
      );
    });

    test('rechaza direcciones inválidas', () {
      expect(parseServerAddress(''), isNull);
      expect(parseServerAddress('ftp://192.168.1.10'), isNull);
      expect(parseServerAddress('http://'), isNull);
    });
  });

  test('la caja principal elegida se recuerda y se puede olvidar', () async {
    final store = InMemoryKeyValueStore();
    ProviderContainer open() => ProviderContainer.test(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );

    final container = open();
    expect(container.read(serverUriProvider), isNull);
    expect(container.read(voxonClientProvider), isNull);

    await container
        .read(serverUriProvider.notifier)
        .select(Uri.parse('http://192.168.1.10:8090'));
    expect(container.read(voxonClientProvider)?.baseUri.host, '192.168.1.10');

    final reopened = open();
    expect(
      reopened.read(serverUriProvider).toString(),
      'http://192.168.1.10:8090',
    );

    await reopened.read(serverUriProvider.notifier).forget();
    expect(open().read(serverUriProvider), isNull);
  });

  test('sin caja principal el login explica qué falta', () async {
    final container = ProviderContainer.test(
      overrides: [
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
      ],
    );
    await expectLater(
      container.read(sessionProvider.notifier).login('1111'),
      throwsA(
        isA<Object>().having(
          (error) => error.toString(),
          'mensaje',
          'Primero elige la caja principal',
        ),
      ),
    );
  });
}
