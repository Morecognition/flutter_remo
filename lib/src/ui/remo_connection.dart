import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_remo/flutter_remo.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock/wakelock.dart';

//attempt of connection to last device
/*import 'package:path_provider/path_provider.dart';
import 'dart:io';

String pathToLastDevice(){
  Future<Directory?> externalStorageDirectory = getExternalStorageDirectory();
  return externalStorageDirectory.toString() + '/remo_address.txt';
}

Future<String> lastDeviceConnected() async {
  try {
    final file = File(pathToLastDevice());
    // Read the file
    final contents = await file.readAsString();
    return contents;
  } catch (e) {
    // If encountering an error, return ''
    return '';
  }
}
void createLastDeviceFile(String newDeviceAddress){
  try {
    final file = File(pathToLastDevice());
    file.writeAsString(newDeviceAddress);
  } catch (e) {
    // If encountering an error, return ''
    return;
  }
}

//inside step 3:
String lastDevice = lastDeviceConnected().toString();
bool flag = false;
bluetoothState.deviceAddresses.forEach((discoveredAddress) {
  if(discoveredAddress == lastDevice){
    flag = true;}
    });
  if (flag){
    Navigator.push(
      context,
      MaterialPageRoute(
      builder: (context) => RemoConnectionStep(
      bluetoothAddress: lastDevice),
      ),
    );}
    //later
    if(!flag){
      createLastDeviceFile(bluetoothState.deviceAddresses[index]);
    }
*/

class WearRemoStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Wakelock.enable();
    return Scaffold(
      appBar: AppBar(
        title: Text("1/4"),
        actions: [
          IconButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              icon: Icon(Icons.close))
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text("Wear Remo and turn it on"),
              Container(
                padding: EdgeInsets.all(10),
                child: Image.asset(
                  'assets/wear_remo.png',
                  package: 'flutter_remo',
                ),
              ),
              SizedBox(height: 20),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TurnOnBluetoothStep(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).accentColor),
                child: Text('NEXT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TurnOnBluetoothStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    /*Future<PermissionStatus> mediaAccess =Permission.accessMediaLocation.request();*/
    return Scaffold(
      appBar: AppBar(
        title: Text("2/4"),
        actions: [
          IconButton(
              onPressed: () {
                int count = 0;
                Navigator.of(context).popUntil((route) => count++ == 2);
              },
              icon: Icon(Icons.close))
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Turn on bluetooth on your device'),
              Image.asset(
                'assets/bluetooth.png',
                package: 'flutter_remo',
              ),
              SizedBox(height: 20),
              TextButton(
                onPressed: () async {
                  if (await Permission.locationWhenInUse.request().isGranted &&
                      await Permission.bluetooth.request().isGranted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => BlocProvider(
                        create: (context) => BluetoothBloc(),
                        child: BluetoothStep(),
                      ),
                    ),
                  );
                }},
                style: TextButton.styleFrom(
                    backgroundColor: Theme.of(context).accentColor),
                child: Text('CONNECT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BluetoothStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    BlocProvider.of<BluetoothBloc>(context)
        .add(OnStartDiscovery());
    return Scaffold(
      appBar: AppBar(
        title: Text("3/4"),
        actions: [
          IconButton(
              onPressed: () {
                int count = 0;
                Navigator.of(context).popUntil((route) => count++ == 3);
              },
              icon: Icon(Icons.close))
        ],
      ),
      body: BlocBuilder<BluetoothBloc, BluetoothState>(
        builder: (context, bluetoothState) {
          late Widget _widget;
          if (bluetoothState is DiscoveredDevices) {
            _widget = RefreshIndicator(
              onRefresh: () async {
                // When the widget is scrolled down a refresh event is sent to the bloc.
                BlocProvider.of<BluetoothBloc>(context).add(OnStartDiscovery());
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children:
                    List.generate(bluetoothState.deviceNames.length, (index) {
                      return ListTile(
                    title: Text(bluetoothState.deviceNames[index]),
                    subtitle: Text(bluetoothState.deviceAddresses[index]),
                    onTap: () {
                      // When the text button is pressed, tell the block which device it has to connect to.
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RemoConnectionStep(
                              bluetoothAddress:
                                  bluetoothState.deviceAddresses[index]),
                        ),
                      );
                    },
                  );
                }),
              ),
            );
          } else if (bluetoothState is DiscoveringDevices) {
            _widget = const Center(child: CircularProgressIndicator());
          } else if (bluetoothState is DiscoveryError) {
            _widget = const Center(child: Text("Discovery error."));
          } else if (bluetoothState is BluetoothInitial) {
            _widget = Center(
              child: MaterialButton(
                color: Theme.of(context).accentColor,
                shape: CircleBorder(),
                child: Padding(
                  padding: EdgeInsets.all(30),
                  child: Text("Discover"),
                ),
                onPressed: () async {
                  if (await Permission.locationWhenInUse.request().isGranted &&
                      await Permission.bluetooth.request().isGranted) {
                    BlocProvider.of<BluetoothBloc>(context)
                        .add(OnStartDiscovery());
                  }
                },
              ),
            );
          }
          return _widget;
        },
      ),
    );
  }
}

class RemoConnectionStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    BlocProvider.of<RemoBloc>(context).add(
      OnConnectDevice(bluetoothAddress),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text('4/4'),
        actions: [
          IconButton(
            onPressed: () {
              int count = 0;
              Navigator.of(context).popUntil((route) => count++ == 4);
            },
            icon: Icon(Icons.close),
          ),
        ],
      ),
      body: BlocBuilder<RemoBloc, RemoState>(
        builder: (context, state) {
          if (state is Disconnected) {
            return Center(
              child: TextButton(
                  onPressed: () {
                    BlocProvider.of<RemoBloc>(context).add(
                      OnConnectDevice(bluetoothAddress),
                    );
                  },
                  style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).accentColor),
                  child: Text('Connect')),
            );
          } else if (state is Connecting) {
            return Center(child: CircularProgressIndicator());
          } else if (state is Connected) {
            return Center(
              child: TextButton(
                  onPressed: () {
                    int count = 0;
                    Navigator.of(context).popUntil((route) => count++ == 4);
                  },
                  style: TextButton.styleFrom(
                      backgroundColor: Theme.of(context).accentColor),
                  child: Text('Finish')),
            );
          } else if (state is ConnectionError) {
            return Center(
              child: Text('Connection error'),
            );
          } else if (state is Disconnecting) {
            return Center(child: CircularProgressIndicator());
          } else {
            return Text('Unhandled state: ' + state.runtimeType.toString());
          }
        },
      ),
    );
  }

  const RemoConnectionStep({Key? key, required this.bluetoothAddress})
      : super(key: key);
  final String bluetoothAddress;
}
