import 'dart:async';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:flutter_remo/src/bloc/bluetooth/bluetooth.dart';
import 'package:vector_math/vector_math.dart';

part 'remo_event.dart';
part 'remo_state.dart';

/// Allows the pairing and connection with a Remo device
class RemoBloc extends Bloc<RemoEvent, RemoState> {
  RemoBloc() : super(Disconnected()) {
    on<OnConnectDevice>((event, emit) => _startConnecting(event));
    on<OnDisconnectDevice>((event, emit) => _startDisconnecting(event));
    on<OnStartTransmission>((event, emit) => _startTransmission());
    on<OnStopTransmission>((event, emit) => _stopTransmission());
    on<OnResetTransmission>((event, emit) => _resetTransmission());
    on<OnSwitchTransmissionMode>((event, emit) => _switchTransmissionMode());
  }

  _switchTransmissionMode() {
    switch (transmissionMode) {
      case TransmissionMode.rms:
        transmissionMode = TransmissionMode.rawImu;
        break;
      case TransmissionMode.rawImu:
        transmissionMode = TransmissionMode.rms;
        break;
    }
  }

  /// Connects to a specific devices. The name is given by the select device event.
  Stream<RemoState> _startConnecting(OnConnectDevice event) async* {
    yield Connecting();
    try {
      await for (ConnectionStates state
          in _bluetooth.startConnection(event.address)) {
        switch (state) {
          case ConnectionStates.disconnected:
            yield Disconnected();
            break;
          case ConnectionStates.connected:
            // TODO: these 2 messages should eventually go to the start transmission function, if the device firmware will be updated.
            late int acquisitionMode;
            switch (transmissionMode) {
              case TransmissionMode.rms:
                acquisitionMode = 50;
                break;
              case TransmissionMode.rawImu:
                acquisitionMode = 51;
                break;
            }
            // Message to set acquisition mode.
            Uint8List message = Uint8List.fromList([
              65, // A
              84, // T
              83, // S
              49, // 1 for acquisition mode
              61, // = for write
              acquisitionMode, // 2 for RMS
              13, // CR
              10, // LF
            ]);
            _bluetooth.sendMessage(message);

            // Message to set operating mode.
            Uint8List message2 = Uint8List.fromList([
              65, // A
              84, // T
              83, // S
              50, // 2 for operating mode
              61, // = for write
              50, // 2 transmission mode
              13, // CR
              10, // LF
            ]);
            _bluetooth.sendMessage(message2);

            remoDataStream = _bluetooth.getInputStream()!;

            yield Connected();
            break;
          case ConnectionStates.connecting:
            yield Connecting();
            break;
          case ConnectionStates.disconnecting:
            Disconnecting();
            break;
          case ConnectionStates.error:
            yield ConnectionError();
            break;
        }
      }
    } on Exception {
      // TODO: check what specific exceptions can occur.
      yield ConnectionError();
    }
  }

  /// Disconnects the device.
  Stream<RemoState> _startDisconnecting(OnDisconnectDevice event) async* {
    yield Disconnecting();
    try {
      await for (ConnectionStates state in _bluetooth.startDisconnection()) {
        switch (state) {
          case ConnectionStates.disconnected:
            yield Disconnected();
            break;
          case ConnectionStates.connected:
            yield Connected();
            break;
          case ConnectionStates.connecting:
            yield Connecting();
            break;
          case ConnectionStates.disconnecting:
            Disconnecting();
            break;
          case ConnectionStates.error:
            yield ConnectionError();
            break;
        }
      }
    } on ArgumentError {
      yield ConnectionError();
    }
  }

  Stream<RemoState> _startTransmission() async* {
    yield StartingTransmission();

    // Getting data from Remo.
    remoStreamSubscription = remoDataStream.listen(
      (dataBytes) {
        if (isTransmissionEnabled && dataBytes.length == 41) {
          ByteData byteArray = dataBytes.buffer.asByteData();
          // Converting the data coming from Remo.
          //// EMG.
          List<double> emg = List.filled(channels, 0);
          for (int byteIndex = 8, emgIndex = 0;
              emgIndex < channels;
              byteIndex += 2, ++emgIndex) {
            switch (transmissionMode) {
              case TransmissionMode.rms:
                emg[emgIndex] = byteArray.getUint16(byteIndex) / 1000;
                break;
              case TransmissionMode.rawImu:
                emg[emgIndex] = byteArray.getInt16(byteIndex) / 1000;
                break;
            }
          }
          //// Accelerometer.
          //// Gyroscope.
          //// Magnetometer.
          // Number 3 is because we are considering accelerations in the 3 dimensions of space.
          List<double> acceleration = List.filled(3, 0);
          List<double> angularVelocity = List.filled(3, 0);
          List<double> magneticField = List.filled(3, 0);
          for (int byteIndex = 24, index = 0;
              index < 3;
              byteIndex += 2, ++index) {
            acceleration[index] = byteArray.getInt16(byteIndex) / 100;
            angularVelocity[index] = byteArray.getInt16(byteIndex + 6) / 100;
            magneticField[index] = byteArray.getInt16(byteIndex + 12) / 100;
          }

          /// Finally.
          dataController.add(
            RemoData(
              emg: emg,
              acceleration: Vector3(
                acceleration[0],
                acceleration[1],
                acceleration[2],
              ),
              angularVelocity: Vector3(
                angularVelocity[0],
                angularVelocity[1],
                angularVelocity[2],
              ),
              magneticField: Vector3(
                magneticField[0],
                magneticField[1],
                magneticField[2],
              ),
            ),
          );
        }
      },
      onDone: () {
        dataController.close();
      },
    );

    isTransmissionEnabled = true;
    yield TransmissionStarted(dataStream);
  }

  Stream<RemoState> _stopTransmission() async* {
    yield StoppingTransmission();
    isTransmissionEnabled = false;
    remoStreamSubscription.cancel();
    yield TransmissionStopped();
  }

  Stream<RemoState> _resetTransmission() async* {
    if (await _bluetooth.isDeviceConnected()) {
      yield Connected();
    } else {
      yield Disconnected();
    }
  }

  // Remo's emg channels.
  static const int channels = 8;

  // Stream subscription handler.
  late StreamSubscription<Uint8List> remoStreamSubscription;
  // The controller for the stream to pass to the UI.
  StreamController<RemoData> dataController = StreamController<RemoData>();
  // The stream to pass to the UI.
  late Stream<RemoData> dataStream = dataController.stream.asBroadcastStream();

  /// All the actual bluetooth actions are handled here.
  final Bluetooth _bluetooth = Bluetooth();

  /// The stream of data coming directly from the Remo device.
  late final Stream<Uint8List> remoDataStream;

  /// Flag to enable/disable the stream of parsed data.
  bool isTransmissionEnabled = false;

  TransmissionMode transmissionMode = TransmissionMode.rms;
}

enum TransmissionMode {
  rms,
  rawImu,
}

class RemoData {
  //final Uint32 timestamp;
  final List<double> emg;
  final Vector3 acceleration;
  final Vector3 angularVelocity;
  final Vector3 magneticField;

  RemoData({
    //required this.timestamp,
    required this.emg,
    required this.acceleration,
    required this.angularVelocity,
    required this.magneticField,
  });

  String toCsvString() {
    return "${emg[0]},${emg[1]},${emg[2]},${emg[3]},${emg[4]},${emg[5]},${emg[6]},${emg[7]},${acceleration.x},${acceleration.y},${acceleration.z},${angularVelocity.x},${angularVelocity.y},${angularVelocity.z},${magneticField.x},${magneticField.y},${magneticField.z}\n";
  }
}
