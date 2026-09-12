import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxon_data/voxon_data.dart';
import 'package:voxon_domain/voxon_domain.dart';

void main() {
  group('QR de vinculación', () {
    const pairingId = 'Ab3xY9kLmN0pQrStUvWx';
    const token = 'k8J2-mZ_q0aB7cD9eF1gH3iJ5kL7mN9oP1qR3sT5uV7';

    test('lee el QR que genera startPairing', () {
      final qr = PairingQr.tryParse(' voxon://pair?p=$pairingId&t=$token ');
      expect(qr, isNotNull);
      expect(qr!.pairingId, pairingId);
      expect(qr.qrToken, token);
      expect(PairingQr.tryParse(qr.uri)!.pairingId, pairingId);
    });

    test('rechaza lo que no es un QR de vinculación de VOXON', () {
      for (final raw in [
        'https://voxon.do/pair?p=$pairingId&t=$token',
        'voxon://otro?p=$pairingId&t=$token',
        'voxon://pair?p=corto&t=$token',
        'voxon://pair?p=$pairingId&t=token-corto',
        'voxon://pair?p=$pairingId',
        'cualquier texto',
      ]) {
        expect(PairingQr.tryParse(raw), isNull, reason: raw);
      }
    });

    test('los códigos de 6 números se limpian y se agrupan', () {
      expect(cleanPairingCode(' 482-913 '), '482913');
      expect(formatPairingCode('482913'), '482 913');
      expect(formatPairingCode('4829'), '4829');
    });
  });

  group('estado de la vinculación', () {
    test('lee los pasos que escribe el servidor', () {
      expect(PairingStatus.parse('waiting'), PairingStatus.waiting);
      expect(
        PairingStatus.parse('device_confirmed'),
        PairingStatus.deviceConfirmed,
      );
      expect(PairingStatus.parse('algo raro'), PairingStatus.expired);
      expect(PairingStatus.linked.isFinished, isTrue);
      expect(PairingStatus.claimed.isFinished, isFalse);
    });

    test('una vinculación sin terminar vence; una terminada no', () {
      final now = DateTime(2026, 9, 12, 15);
      final late = {
        'status': 'claimed',
        'instanceName': 'La Fonda',
        'expiresAt': Timestamp.fromDate(
          now.subtract(const Duration(minutes: 1)),
        ),
      };
      expect(
        PairingState.fromMap('p1', late, now: now).status,
        PairingStatus.expired,
      );
      expect(
        PairingState.fromMap('p1', {
          ...late,
          'status': 'linked',
        }, now: now).status,
        PairingStatus.linked,
      );
      final onTime = PairingState.fromMap('p1', {
        ...late,
        'expiresAt': Timestamp.fromDate(now.add(const Duration(minutes: 9))),
      }, now: now);
      expect(onTime.status, PairingStatus.claimed);
      expect(onTime.instanceName, 'La Fonda');
      expect(PairingState.fromMap('p1', null).status, PairingStatus.expired);
    });

    test('lee lo que devuelven las funciones', () {
      final ticket = PairingTicket.fromMap({
        'pairingId': 'Ab3xY9kLmN0pQrStUvWx',
        'qrToken': 'token',
        'qr': 'voxon://pair?p=Ab3xY9kLmN0pQrStUvWx&t=token',
        'expiresAt': '2026-09-12T15:10:00.000Z',
      });
      expect(ticket.expiresAt, DateTime.utc(2026, 9, 12, 15, 10));

      final linked = LinkedDevice.fromMap({
        'instanceId': 'i1',
        'instanceName': 'La Fonda',
        'mode': 'restaurant',
        'deviceName': 'Caja bar',
        'deviceNumber': 2,
      });
      expect(linked.deviceNumber, 2);

      final code = DeviceCode.fromMap({
        'code': 'ABCD2345',
        'expiresAt': '2026-09-13T15:00:00.000Z',
        'instanceName': 'La Fonda',
        'deviceName': 'Caja 1',
      });
      expect(code.formatted, 'ABCD-2345');
    });
  });

  group('negocio', () {
    test('puestos y lo que pueden hacer', () {
      expect(StaffRole.parse('cashier').canSell, isTrue);
      expect(StaffRole.parse('waiter').canSell, isFalse);
      expect(StaffRole.parse('manager').canManage, isTrue);
      expect(StaffRole.parse(null), StaffRole.locked);
      expect(StaffRole.assignable, isNot(contains(StaffRole.locked)));
      expect(StaffRole.kitchen.label, 'Cocina');
    });

    test('la marca vuelve al verde de VOXON si el color no sirve', () {
      final branding = Branding.fromMap({
        'displayName': 'La Fonda',
        'primaryColor': 'rojo',
      });
      expect(branding.displayName, 'La Fonda');
      expect(branding.primaryColorValue, 0xFF1B5E20);
      expect(
        Branding.fromMap({'primaryColor': '#C62828'}).primaryColorValue,
        0xFFC62828,
      );
      expect(Branding.fromMap(null).displayName, 'VOXON POS');
    });

    test('la instancia trae su modo y sus reglas fiscales', () {
      final instance = InstanceSummary.fromMap('i1', {
        'name': 'La Fonda',
        'mode': 'restaurant',
        'accountId': 'c1',
        'modules': ['tables', 'kitchen', 'legalTip'],
        'fiscal': {'priceMode': 'tax_excluded', 'legalTip': true},
        'active': true,
      });
      expect(instance.priceMode, PriceMode.taxExcluded);
      expect(instance.legalTip, isTrue);
      expect(instance.uses('kitchen'), isTrue);
      expect(instance.uses('scale'), isFalse);
      expect(instance.businessMode!.name, 'Restaurante');
    });

    test('empleados y cajas', () {
      expect(
        StaffMember.fromMap('s1', {
          'name': 'luis  pérez',
          'role': 'cashier',
          'active': true,
        }).initials,
        'LP',
      );
      final device = DeviceInfo.fromMap('u1', {
        'name': 'Caja 1',
        'platform': 'windows',
        'number': 1,
        'status': 'active',
        'enrolledWith': 'qr',
        'lastSeenAt': Timestamp.fromDate(DateTime(2026, 9, 12)),
      });
      expect(device.isActive, isTrue);
      expect(device.lastSeenAt, DateTime(2026, 9, 12));
      expect(DeviceInfo.fromMap('u2', {}).isActive, isFalse);
    });
  });

  test('la lista de negocios de cada persona trae su puesto y su modo', () {
    final instance = MyInstance.fromMap('i1', {
      'accountId': 'c1',
      'name': 'La Fonda',
      'mode': 'restaurant',
      'role': 'manager',
    });
    expect(instance.name, 'La Fonda');
    expect(instance.role, StaffRole.manager);
    expect(instance.businessMode?.id, 'restaurant');

    final broken = MyInstance.fromMap('i2', const {'mode': 'no-existe'});
    expect(broken.role, StaffRole.locked);
    expect(broken.businessMode, isNull);
  });

  test('los errores de Firebase se muestran en español', () {
    expect(
      authMessage('invalid-credential'),
      'Correo o contraseña incorrectos',
    );
    expect(
      const VoxonException('unavailable', 'Sin internet').isOffline,
      isTrue,
    );
  });
}
