import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// VLGEO2 BLE notify TX：NUS（整檔／部分 PHGF）與 Haglof 自訂服務。
class BleUartDiscovery {
  BleUartDiscovery._();

  static const haglofServiceUuid = '9E000000-F685-4EA5-B58A-85287CB04965';
  static const haglofTxUuid = '9E010000-F685-4EA5-B58A-85287CB04965';
  static const nusServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const nusTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  static BluetoothCharacteristic? findNotifyTx(
    List<BluetoothService> services, {
    bool preferNus = true,
  }) {
    final order = preferNus
        ? [
            [nusServiceUuid, nusTxUuid],
            [haglofServiceUuid, haglofTxUuid],
          ]
        : [
            [haglofServiceUuid, haglofTxUuid],
            [nusServiceUuid, nusTxUuid],
          ];

    for (final pair in order) {
      final found = _findInServices(services, pair[0], pair[1]);
      if (found != null) return found;
    }
    return null;
  }

  static BluetoothCharacteristic? _findInServices(
    List<BluetoothService> services,
    String serviceUuid,
    String txUuid,
  ) {
    for (final service in services) {
      if (service.uuid.toString().toUpperCase() != serviceUuid) continue;
      for (final c in service.characteristics) {
        if (c.uuid.toString().toUpperCase() == txUuid && c.properties.notify) {
          return c;
        }
      }
    }
    return null;
  }
}
