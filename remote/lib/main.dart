import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:udp/udp.dart';

var logger = Logger(
  printer: PrettyPrinter(),
  level:
      Platform.environment.containsKey('FLUTTER_TEST')
          ? Level.error
          : Level.debug,
);

enum ControlMode { bluetooth, wifi }

void main() {
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ModeSelectionUI());
  }
}

class ModeSelectionUI extends StatelessWidget {
  const ModeSelectionUI({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Control')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ControllerUI(controlMode: ControlMode.bluetooth),
                  ),
                );
              },
              icon: Icon(Icons.bluetooth),
              label: Text('Bluetooth'),
              style: ElevatedButton.styleFrom(minimumSize: Size(160, 40)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ControllerUI(controlMode: ControlMode.wifi),
                  ),
                );
              },
              icon: Icon(Icons.wifi),
              label: Text('WiFi'),
              style: ElevatedButton.styleFrom(minimumSize: Size(160, 40)),
            ),
          ],
        ),
      ),
    );
  }
}

class ControllerUI extends StatefulWidget {
  final ControlMode controlMode;

  const ControllerUI({super.key, required this.controlMode});

  @override
  State<ControllerUI> createState() => _ControllerUIState();
}

class _ControllerUIState extends State<ControllerUI> {
  double _leftValue = 0.0;
  double _rightValue = 0.0;
  late BleController _bleController;
  late WifiController _wifiController;
  bool _isConnected = false;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();

    if (widget.controlMode == ControlMode.bluetooth) {
      _bleController = BleController(deviceName: 'Untitled USV');

      // If the connection is lost, update the connections state.
      _bleController.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _isConnected = false;
            _isConnecting = false;
          });
        }
      });

      _tryConnectBluetooth();
    } else if (widget.controlMode == ControlMode.wifi) {
      _wifiController = WifiController();

      _tryConnectWifi();
    }
  }

  @override
  void dispose() {
    if (widget.controlMode == ControlMode.bluetooth) {
      _bleController.disconnect();
    }
    else {
      _wifiController.disconnect();
    }
    super.dispose();
  }

  /// Try to connect to the USV by Bluetooth.
  ///
  /// The connection will be attempted for 10 seconds before the user can retry.
  Future<void> _tryConnectBluetooth() async {
    setState(() {
      _isConnecting = true;
    });

    final timeoutTimer = Timer(const Duration(seconds: 10), () {
      if (mounted && _isConnecting) {
        setState(() {
          _isConnecting = false;
        });
      }
    });

    try {
      await _bleController.connectToDevice();
      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
    } finally {
      timeoutTimer.cancel();
    }
  }

  /// Try to connect to the USV by WiFi. 
  /// 
  /// The UDP sender is initialized here.
  Future<void> _tryConnectWifi() async {
    _wifiController.initUdpSender();

    setState(() {
      _isConnected = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Remote Control')),
      body: Center(
        child:
            _isConnected
                ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    VerticalSlider(
                      value: _leftValue,
                      maxValue: (widget.controlMode == ControlMode.bluetooth) ? 5 : 100,
                      divisions: (widget.controlMode == ControlMode.bluetooth) ? 10 : 50,
                      isReversed: true,
                      onChanged: (value) {
                        if (widget.controlMode == ControlMode.bluetooth) {
                          setState(() {
                            _leftValue = value;
                            _bleController.updateValues(_leftValue, _rightValue);
                          });
                        } else {
                          setState(() {
                            _leftValue = value;
                            _wifiController.updateValues(_leftValue, _rightValue);
                          });
                        }
                      },
                    ),
                    VerticalSlider(
                      value: _rightValue,
                      maxValue: (widget.controlMode == ControlMode.bluetooth) ? 5 : 100,
                      divisions: (widget.controlMode == ControlMode.bluetooth) ? 10 : 50,
                      isReversed: false,
                      onChanged: (value) {
                        if (widget.controlMode == ControlMode.bluetooth) {
                          setState(() {
                            _rightValue = value;
                            _bleController.updateValues(_leftValue, _rightValue);
                          });
                        } else {
                          setState(() {
                            _rightValue = value;
                            _wifiController.updateValues(_leftValue, _rightValue);
                          });
                        }
                      },
                    ),
                  ],
                )
                : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isConnecting ? null : _tryConnectBluetooth,
                      child: Text('Connect'),
                    ),
                  ],
                ),
      ),
    );
  }
}

class BleController {
  final String deviceName;
  final Guid serviceUuid = Guid('1eba326c-dfb5-4107-b052-97e6e8ffec90');
  final Guid lPropCharacteristicUuid = Guid('a4d40b3b-3a0a-403a-8eb5-eae4ce620bd4');
  final Guid rPropCharacteristicUuid = Guid('dbe2a780-0658-4bec-a2e3-fa0581b36d20');

  BluetoothDevice? _device;
  BluetoothCharacteristic? _lPropCharacteristic;
  BluetoothCharacteristic? _rPropCharacteristic;

  final _connectionStateController = StreamController<BluetoothConnectionState>();
  Stream<BluetoothConnectionState> get connectionState => _connectionStateController.stream;

  BleController({required this.deviceName});

  /// Connect to the USV by Bluetooth.
  ///
  /// Automatically scan for Bluetooth USV device by name and connect to the vehicle.
  Future<void> connectToDevice() async {
    // Request permissions.
    try {
      await Permission.bluetooth.request();
      await Permission.bluetoothConnect.request();
      await Permission.bluetoothScan.request();
    } catch (e) {
      logger.e('Error: $e.');
    }

    // Scan for devices.
    await FlutterBluePlus.turnOn();
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 10));
    final Completer<BluetoothDevice> deviceCompleter =
        Completer<BluetoothDevice>();
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
    }, onError: (e) => logger.e('Error: $e. '));

    // Connect to device.
    try {
      _device = await deviceCompleter.future;
      await _device!.connect();
      logger.i('Connected to Bluetooth device: ${_device!.platformName}. ');

      final services = await _device!.discoverServices();
      final service = services.firstWhere((s) => s.uuid == serviceUuid);

      final characteristics = service.characteristics;
      _lPropCharacteristic = characteristics.firstWhere(
        (c) => c.uuid == lPropCharacteristicUuid,
      );
      _rPropCharacteristic = characteristics.firstWhere(
        (c) => c.uuid == rPropCharacteristicUuid,
      );

      _device!.connectionState.listen((state) {
        _connectionStateController.add(state);
      });
    } catch (e) {
      logger.e('Error: $e. ');
      _connectionStateController.add(BluetoothConnectionState.disconnected);
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

    logger.i('Left: $left, Right: $right. ');
  }

  /// Disconnect from the Bluetooth device.
  ///
  /// Call this function on disposition.
  void disconnect() {
    _device?.disconnect();
  }
}

class WifiController {
  final String esp32Ip = '192.168.4.1';
  final int esp32Port = 4210;
  UDP? _udpSender;

  WifiController();

  /// Initialize the UDP sender.
  ///
  /// Bind to any available port.
  void initUdpSender() async {
    _udpSender = await UDP.bind(Endpoint.any());
    
    // Send values periodically.
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      updateValues(_lastLeft, _lastRight);
    });
    logger.i('Connected to WiFi device. ');
  }

  double _lastLeft = 0.0;
  double _lastRight = 0.0;
  Timer? _updateTimer;

  Future<void> updateValues(double left, double right) async {
    _lastLeft = left;
    _lastRight = right;

    int lPropValue = left.toInt();
    int rPropValue = right.toInt();

    final ByteData byteData = ByteData(4);

    byteData.setInt16(0, lPropValue);
    byteData.setInt16(2, rPropValue);

    final Uint8List data = byteData.buffer.asUint8List();

    try {
      await _udpSender?.send(
        data,
        Endpoint.unicast(InternetAddress(esp32Ip), port: Port(esp32Port)),
      );
      logger.i('Left: $lPropValue, Right: $rPropValue');
    } catch (e) {
      logger.e('Error: $e');
    }
  }

  /// Disconnect from the WiFi device.
  ///
  /// Call this function on disposition.
  void disconnect() {
    _udpSender?.close();
    _updateTimer?.cancel();
  }
}

class VerticalSlider extends StatelessWidget {
  final double value;
  final double maxValue;
  final int divisions;
  final bool isReversed;
  final Function(double) onChanged;

  const VerticalSlider({
    super.key,
    required this.value,
    required this.maxValue,
    required this.divisions,
    required this.isReversed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.flip(
            flipX: true,
            child: RotatedBox(
              quarterTurns: -1,
              child: Slider(
                min: -maxValue,
                max: maxValue,
                divisions: divisions,
                label: value.toInt().toString(),
                value: value,
                onChanged: onChanged,
              ),
            ),
          )
        ],
      ),
    );
  }
}
