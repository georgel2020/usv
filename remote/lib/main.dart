import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

var logger = Logger(
  printer: PrettyPrinter(),
  level:
      Platform.environment.containsKey('FLUTTER_TEST')
          ? Level.error
          : Level.debug,
);

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ControllerUI());
  }
}

class BleController {
  final String deviceName;
  final Guid serviceUuid = Guid("1eba326c-dfb5-4107-b052-97e6e8ffec90");
  final Guid lPropCharacteristicUuid = Guid("a4d40b3b-3a0a-403a-8eb5-eae4ce620bd4");
  final Guid rPropCharacteristicUuid = Guid("dbe2a780-0658-4bec-a2e3-fa0581b36d20");

  BluetoothDevice? _device;
  BluetoothCharacteristic? _lPropCharacteristic;
  BluetoothCharacteristic? _rPropCharacteristic;

  late Timer _updateTimer;

  BleController({required this.deviceName});

  /// Connect to the USV.
  /// 
  /// Automatically scan for Bluetooth USV device by name and connect to the vehicle.
  Future<void> connectToDevice() async {
    // Request permissions.
    try {
      await Permission.bluetooth.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetoothScan.request();
    } catch (e) {
      logger.e("Error: $e.");
    }

    // Scan for devices.
    await FlutterBluePlus.turnOn();
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
    final Completer<BluetoothDevice> deviceCompleter = Completer<BluetoothDevice>();
    late StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.onScanResults.listen((
      List<ScanResult> results,
    ) {
      if (results.isNotEmpty) {
        for (ScanResult r in results) {
          if (r.advertisementData.advName == deviceName) {
            logger.i('Device "${r.advertisementData.advName}" found! ');
            subscription.cancel();
            deviceCompleter.complete(r.device);
            return;
          }
        }
      }
    }, onError: (e) => logger.e("Error: $e. "));

    // Connect to device.
    try {
      _device = await deviceCompleter.future;
      await _device!.connect();
      logger.i("Connected to device: ${_device!.platformName}. ");

      final services = await _device!.discoverServices();
      final service = services.firstWhere((s) => s.uuid == serviceUuid);

      final characteristics = service.characteristics;
      _lPropCharacteristic = characteristics.firstWhere((c) => c.uuid == lPropCharacteristicUuid);
      _rPropCharacteristic = characteristics.firstWhere((c) => c.uuid == rPropCharacteristicUuid);
    } catch (e) {
      logger.e("Error: $e. ");
    }
  }

  /// Update prop characteristics.
  /// 
  /// Send [left] and [right] prop speed to the vehicle.
  /// This function should not be called regularly, because too many callbacks will increase latency of control.
  void updateValues(double left, double right) {
    final leftData = <int>[left.toInt()];
    final rightData = <int>[right.toInt()];

    _lPropCharacteristic?.write(leftData);
    _rPropCharacteristic?.write(rightData);

    logger.i("Left: $left, Right: $right. ");
  }

  /// Disconnect from the USV device.
  /// 
  /// Call this function on disposition.
  void disconnect() {
    _updateTimer.cancel();
    _device?.disconnect();
  }
}

class ControllerUI extends StatefulWidget {
  const ControllerUI({super.key});

  @override
  State<ControllerUI> createState() => _ControllerUIState();
}

class _ControllerUIState extends State<ControllerUI> {
  double _leftValue = 0.0;
  double _rightValue = 0.0;
  late BleController _bleController;

  @override
  void initState() {
    super.initState();
    _bleController = BleController(deviceName: "Untitled USV");
    _bleController.connectToDevice();
  }

  @override
  void dispose() {
    _bleController.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Control')),
      body: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            VerticalSlider(
              value: _leftValue,
              onChanged: (value) {
                setState(() {
                  _leftValue = value;
                  _bleController.updateValues(_leftValue, _rightValue);
                });
              },
            ),
            VerticalSlider(
              value: _rightValue,
              onChanged: (value) {
                setState(() {
                  _rightValue = value;
                  _bleController.updateValues(_leftValue, _rightValue);
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}

class VerticalSlider extends StatelessWidget {
  final double value;
  final Function(double) onChanged;

  const VerticalSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotatedBox(
            quarterTurns: -1,
            child: Slider(
              min: -5,
              max: 5,
              divisions: 10,
              label: null,
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
