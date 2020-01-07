import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:opentrickler/appstate.dart';
import 'package:opentrickler/globals.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

class PairedDevices extends StatefulWidget {
  final Function setIndex;

  PairedDevices({Key key, this.setIndex});

  @override
  _PairedDevicesState createState() => _PairedDevicesState();
}

class _PairedDevicesState extends State<PairedDevices> {
  void _addADevice() {
    widget.setIndex(1);
  }

  void _connectToDevice(BluetoothDevice device, AppState appState) async {
    print('Connecting to ${device.name}...');
    // Note: Devices fails to connect twice in a row.
    // Possible solution is re-scan and add the same devices on disconnect.
    appState.connectedDevice = device;
    bool errored = false;
    try {
      appState.isConnecting = true;
      await device.connect(autoConnect: false).timeout(Duration(seconds: 5));
      appState.isConnecting = false;
      print('Connected to ${device.name}');
    } on TimeoutException {
      print('Timed out while attempting to connect to ${device.name}');
      _disconnectFromDevice(appState);
      errored = true;
    } catch (err) {
      print('Failed to connect to ${device.name}');
      print(err.toString());
      _disconnectFromDevice(appState);
      errored = true;
    }
    if (!errored) {
      _discoverTricklerService(appState);
    }
  }

  void _discoverTricklerService(AppState appState) async {
    print('Discovering services on ${appState.connectedDevice.name}...');
    try {
      List<BluetoothService> services = await appState.connectedDevice.discoverServices();
      BluetoothService tricklerService = services.singleWhere((s) => s.uuid.toString() == TRICKLER_SERVICE_UUID, orElse: () => null);
      if (tricklerService != null) {
        print('Found Trickler Service!');
        appState.tricklerService = tricklerService;
      } else {
        print('Unable to find Trickler Service.');
        _disconnectFromDevice(appState);
      }
    } catch (err) {
      print(err.toString());
    }
  }

  void _disconnectFromDevice(AppState appState) {
    print('Disconnecting from ${appState.connectedDevice.name}...');
    appState.connectedDevice.disconnect();
    appState.connectedDevice = null;
  }

  void _handleTap(BluetoothDevice device, AppState appState) {
    if (appState.connectedDevice == device) {
      _disconnectFromDevice(appState);
    } else {
      _connectToDevice(device, appState);
    }
  }

  String _getConnectionState(dev, connectedDevice, isConnecting) {
    if (connectedDevice == dev) {
      return isConnecting ? 'Connecting...' : 'Connected';
    }
    return 'Disconnected';
  }

  List<Widget> _buildDevices(AppState appState) {
    List<Widget> devWidgets = [];
    appState.devices.forEach((dev) {
      devWidgets.add(Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: () => _handleTap(dev, appState),
          child: Card(
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 100,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(dev.name),
                    Text(_getConnectionState(dev, appState.connectedDevice, appState.isConnecting),
                      style: TextStyle(
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
    });
    return devWidgets;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) =>
        Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(0, 15, 0, 30),
              child: Text('Paired Devices',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold
                )
              ),
            ),
          ] + _buildDevices(appState) + [
            RaisedButton(
              onPressed: _addADevice,
              padding: EdgeInsets.symmetric(horizontal: 80, vertical: 10),
              child: Text('Add a Device')
            ),
          ],
        ),  
    );
  }
}

class FindDevices extends StatefulWidget {
  final Function setIndex;

  FindDevices({Key key, this.setIndex});

  @override
  _FindDevicesState createState() => _FindDevicesState();
}

class _FindDevicesState extends State<FindDevices> {
  FlutterBlue _flutterBlue = FlutterBlue.instance;
  List<ScanResult> _scanResults = [];
  RefreshController _refreshController = RefreshController(initialRefresh: true);
  var _sub;

  Future _scanDevices() async {
    _sub = _flutterBlue.scanResults.listen((scanResults) {
        scanResults.forEach((sr) {
          if (sr.device.name.length > 0 && _scanResults.indexOf(sr) == -1) { // this check is causing a bug that allows for a device to show up multiple times if it has a different RSSI value the second time
            print('Found: ${sr.device.name}, rssi: ${sr.rssi}');
            setState(() {
              _scanResults.add(sr);
            });
          }
        });
    });

    print('Start Scanning...');
    await _flutterBlue.startScan(timeout: Duration(seconds: 4));
    print('Stop Scanning...');
    _flutterBlue.stopScan();
    _sub.cancel();
    _sub = null;
    return;
  }

  void _onRefresh() async {
    print('Refreshing...');
    await _scanDevices();
    _refreshController.refreshCompleted();
  }

  void _addDevice(BluetoothDevice device, AppState appState, Function callback) {
    if (appState.devices.indexOf(device) == -1) {
      appState.devices.add(device);
      callback();
    }
  }

  Widget _buildResults(BuildContext ctxt, int i, AppState appState, Function setIndex) {
    return i == 0 ?
      Padding(
        padding: EdgeInsets.fromLTRB(0, 15, 0, 30),
        child: Text('Available Devices',
        textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold
          )
        ),
      ) : Padding(
        padding: EdgeInsets.symmetric(horizontal: 30),
        child: GestureDetector(
          onTap: () => _addDevice(_scanResults[i - 1].device, appState, () => setIndex(0)),
          child: Card(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_scanResults[i - 1].device.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                    ),
                  ),
                  Text("RSSI: ${_scanResults[i - 1].rssi}, Paired: ${appState.devices.indexOf(_scanResults[i - 1].device) == -1 ? 'FALSE' : 'TRUE'}",
                    style: TextStyle(
                      color: Colors.black38,
                    ),
                  ),
                ],
              )
            ),
          ),
        )
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, appState, _) =>
        SmartRefresher(
          enablePullDown: true,
          controller: _refreshController,
          onRefresh: _onRefresh,
          child: ListView.builder(
            itemCount: _scanResults.length + 1,
            itemBuilder: (c, i) => _buildResults(c, i, appState, widget.setIndex),
          ),
        ),
    );
  }
  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

class DevicesTab extends StatefulWidget {
  @override
  _DevicesTabState createState() => _DevicesTabState();
}

class _DevicesTabState extends State<DevicesTab> {
  int _screenIndex = 0;

  void _setScreenIndex(int i) {
      setState(() {
        _screenIndex = i;
      });
  }

  Widget _getScreen(Function setIndex,) {
    final List<Widget> _screens = [
      PairedDevices(setIndex: setIndex),
      FindDevices(setIndex: setIndex),
    ];
    return _screens[_screenIndex];
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _getScreen((int i) => _setScreenIndex(i))
    );
  }
}