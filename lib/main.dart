import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart' as xml;
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FMTCObjectBoxBackend().initialise();
  await FMTCStore('mapStore').manage.create();

  runApp(MyApp());
}

String convertLocationInfo(Position position) {
  String lat = _convertToDMS(position.latitude, "latitude");
  String lon = _convertToDMS(position.longitude, "longitude");

  String altitude =
      "${position.altitude.toStringAsFixed(2)} ± ${position.altitudeAccuracy.toStringAsFixed(2)} m";

  String horizontalAccuracy = "± ${position.accuracy.toStringAsFixed(2)} m";

  String heading = _getHeadingDirection(position.heading) +
      " (${position.heading.toStringAsFixed(2)}°)";

  String speed = "${position.speed.toStringAsFixed(2)} m/s";

  return 'Latitude (Y): $lat\nLongitude (X): $lon\nAltitude (Z): $altitude\nHorizontal Accuracy: $horizontalAccuracy\nHeading: $heading\nSpeed: $speed';
}

String _convertToDMS(double coordinate, String type) {
  // Convert coordinate to degree, minute, second format
  String direction = coordinate >= 0
      ? (type == "latitude" ? "N" : "E")
      : (type == "latitude" ? "S" : "W");
  double absolute = coordinate.abs();
  int degrees = absolute.toInt();
  double minutes = (absolute - degrees) * 60;
  int minutesInt = minutes.toInt();
  double seconds = (minutes - minutesInt) * 60;
  return '$degrees° $minutesInt\' ${seconds.toStringAsFixed(2)}\" $direction';
}

String _getHeadingDirection(double heading) {
  // Convert heading angle to cardinal direction
  if (heading == null || heading.isNaN) return "N/A";
  List<String> directions = [
    "North",
    "North East",
    "East",
    "South East",
    "South",
    "South West",
    "West",
    "North West"
  ];
  if (heading > 0) {
    int index = ((heading / 45) % 8).round();
    return directions[index];
  } else {
    return "N/A";
  }
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Tracker',
      home: LocationTrackerScreen(),
    );
  }
}

class LocationTrackerScreen extends StatefulWidget {
  @override
  _LocationTrackerScreenState createState() => _LocationTrackerScreenState();
}

class _LocationTrackerScreenState extends State<LocationTrackerScreen> {
  Position? _currentPosition;
  String _locationInfo = 'Loading location...';
  bool _isTracking = false;
  bool _isLoading = true;
  bool _isGpxFileSaved = false;
  List<LatLng> _locationPoints = [];
  List<Position> _recordedPositions = [];

  @override
  void initState() {
    super.initState();
    _getLastKnownLocation();
  }

  Future<void> _getLastKnownLocation() async {
    try {
      final position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        setState(() {
          _currentPosition = position;
          _updateLocationInfo();
          _isLoading = false;
        });
      } else {
        _requestPermissionAndGetLocation();
      }
    } catch (e) {
      print('Error getting last known location: $e');
      _requestPermissionAndGetLocation();
    }
  }

  Future<void> _requestPermissionAndGetLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationInfo = 'Location permissions are denied';
          _isLoading = false;
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationInfo =
            'Location permissions are permanently denied, we cannot request permissions.';
        _isLoading = false;
      });
      return;
    }

    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      setState(() {
        _currentPosition = position;
        _updateLocationInfo(navigate: true);
        _isLoading = false;
      });
    } catch (e) {
      print('Error getting current location: $e');
      setState(() {
        _locationInfo = 'Error getting location';
        _isLoading = false;
      });
    }
  }

  Future<void> _startTracking() async {
    setState(() {
      _isTracking = true;
      _isLoading = true;
      _recordedPositions.clear(); // Clear the previous recorded positions
    });

    final positionStream = Geolocator.getPositionStream();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('Tracking started. Tap "Finish Track" to save the GPX file.'),
        duration: Duration(seconds: 3),
      ),
    );
    await for (Position position in positionStream) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          _updateLocationInfo();
          _isLoading = false;
          if (_isTracking) {
            _recordedPositions.add(position);
          }
        });
      }
    }
  }

  Future<void> _saveGpxFile() async {
    print("Saving gpx file");
    await _writeGpxFile(_recordedPositions);
  }

  void _stopTracking() {
    setState(() {
      _isTracking = false;
    });
    // _saveGpxFile();
  }

  Future<String> getAppDirectory() async {
    // Get the home directory
    final String homeDirectory =
        (await getApplicationDocumentsDirectory()).path;

    // Create the directory for your app inside the home directory
    final String appName = 'GISTracker';
    final String appDirectoryPath = '$homeDirectory/$appName';
    final Directory appDirectory = Directory(appDirectoryPath);
    if (!(await appDirectory.exists())) {
      await appDirectory.create(recursive: true);
    }

    return appDirectoryPath;
  }

  Future<void> _writeGpxFile(List<Position> positions) async {
    final directory = await getAppDirectory();
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
    final formattedDateTime = formatter.format(now);
    final filePath = '${directory}/track_$formattedDateTime.gpx';
    final builder = xml.XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="no"');
    builder.element('gpx', namespaces: {
      '': 'http://www.topografix.com/GPX/1/1',
    }, attributes: {
      'creator': 'GIS Tracker',
      'version': '1.1',
    }, nest: () {
      builder.element('trk', nest: () {
        builder.element('trkseg', nest: () {
          for (var position in positions) {
            builder.element('trkpt', nest: () {
              builder.element('lat', nest: position.latitude.toString());
              builder.element('lon', nest: position.longitude.toString());
              builder.element('ele', nest: position.altitude.toString());
            });
          }
        });
      });
    });

    final xmlDoc = builder.buildDocument();

    final file = File(filePath);
    await file.writeAsString((xmlDoc.toXmlString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPX file saved successfully at $filePath'),
        duration: Duration(seconds: 3),
      ),
    );
    setState(() {
      _isGpxFileSaved = true;
    });
  }

  void _updateLocationInfo({bool navigate = false}) {
    if (_currentPosition == null) {
      _locationInfo = 'Location information will be displayed here.';
    } else {
      _locationInfo = convertLocationInfo(_currentPosition!);
      if (navigate || _isTracking) {
        final newPoint =
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
        if (navigate) {
          _mapController.move(newPoint, 20.0);
        }
        if (_isTracking) {
          _locationPoints.add(newPoint);
        }
      }
    }
  }

  MapController _mapController = MapController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Location Tracker'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: _requestPermissionAndGetLocation,
                        child: Text('Request Location'),
                      ),
                      SizedBox(height: 20),
                      Text(_locationInfo),
                      SizedBox(height: 20),
                      if (_isTracking)
                        ElevatedButton(
                          onPressed: _stopTracking,
                          child: Text('Stop Tracking'),
                        ),
                      if (!_isTracking && !_isGpxFileSaved)
                        ElevatedButton(
                          onPressed: _startTracking,
                          child: Text('Start Tracking'),
                        ),
                      if (!_isTracking && _isGpxFileSaved)
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isGpxFileSaved = false;
                              _recordedPositions.clear();
                              _locationPoints.clear();
                            });
                            _startTracking();
                          },
                          child: Text('Start New Track'),
                        ),
                      if (_isTracking && !_isGpxFileSaved)
                        ElevatedButton(
                          onPressed: _saveGpxFile,
                          child: Text('Finish Track'),
                        ),
                      if (_isTracking)
                        Text('Recorded Points: ${_recordedPositions.length}'),
                    ],
                  ),
          ),
          SizedBox(height: 10),
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition != null
                    ? LatLng(
                        _currentPosition!.latitude, _currentPosition!.longitude)
                    : LatLng(0, 0),
                initialZoom: 19.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  tileProvider: FMTCStore('mapStore').getTileProvider(),
                ),
                CurrentLocationLayer(),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _locationPoints,
                      color: Colors.blue,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
