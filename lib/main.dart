import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:gpx/gpx.dart';
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
      home: GISTrackerScreen(),
    );
  }
}

class GISTrackerScreen extends StatefulWidget {
  @override
  _GISTrackerScreenState createState() => _GISTrackerScreenState();
}

class _GISTrackerScreenState extends State<GISTrackerScreen> {
  Position? _currentPosition;
  String _locationInfo = 'Loading location...';
  bool _isTracking = false;
  bool _isLoading = true;
  bool _isGpxFileSaved = false;
  bool _isTrackingPaused = false;
  int _distanceFilter = 4;

  String _gpxFilename = '';
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
        desiredAccuracy: LocationAccuracy.high,
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

  Future<void> _resumeTracking() async {
    setState(() {
      _isTrackingPaused = false;
      _isTracking = true;
    });
    await _startTracking(setFilename: false);
  }

  Future<void> _startTracking({bool setFilename = true}) async {
    if (setFilename) {
      final now = DateTime.now();
      final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
      final formattedDateTime = formatter.format(now);
      setState(() {
        _gpxFilename = 'track_$formattedDateTime';
      });
    }

    setState(() {
      _isTracking = true;
      _isLoading = true;
      _recordedPositions.clear(); // Clear the previous recorded positions
    });
    // final LocationSettings locationSettings = LocationSettings(
    //   accuracy: LocationAccuracy.high,
    //   // distanceFilter: _distanceFilter,
    // );

    final positionStream = Geolocator.getPositionStream();

    await for (Position position in positionStream) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
          bool isIndistance = false;
          if (_isTracking) {
            if (_recordedPositions.isNotEmpty) {
              double lastLat = _recordedPositions.last.latitude;
              double lastLng = _recordedPositions.last.longitude;

              double distance = Geolocator.distanceBetween(
                  position.latitude, position.longitude, lastLat, lastLng);

              if (distance > _distanceFilter) {
                isIndistance = true;
                _recordedPositions.add(position);
              }
            } else {
              _recordedPositions.add(position);
            }
          }
          _updateLocationInfo(isIndistance: isIndistance);
          _isLoading = false;
        });
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Tracking initiated. Tap "Finish Track" to save the GPX file.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _saveGpxFile() async {
    print("Saving gpx file");
    await _writeGpxFile(_recordedPositions);
    setState(() {
      _isTracking = false;
      _isTrackingPaused = false;
      _recordedPositions.clear();
      _locationPoints.clear();
    });
  }

  void _pauseTracking() {
    setState(() {
      _isTracking = false;
      _isTrackingPaused = true;
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
    final gpxFilePath = '${directory}/${_gpxFilename}.gpx';
    final kmlFilePath = '${directory}/${_gpxFilename}.kml';

    final gpx = Gpx();
    gpx.version = '1.1';
    gpx.creator = 'GIS Tracker';
    gpx.metadata = Metadata();
    gpx.metadata?.name = 'Location Track';
    gpx.metadata?.desc = 'Track of user location';
    gpx.metadata?.time = DateTime.now();

    final trkpt = Trk();
    final trkSeg = Trkseg();
    for (final position in positions) {
      trkSeg.trkpts.add(
        Wpt(
          lat: position.latitude,
          lon: position.longitude,
          ele: position.altitude,
        ),
      );
    }
    trkpt.trksegs.add(trkSeg);
    gpx.trks.add(trkpt);

    final gpxString = GpxWriter().asString(gpx, pretty: true);
    final kmlString = KmlWriter(altitudeMode: AltitudeMode.clampToGround)
        .asString(gpx, pretty: true);

    final gpxFile = File(gpxFilePath);
    final kmlFile = File(kmlFilePath);

    await gpxFile.writeAsString(gpxString);
    await kmlFile.writeAsString(kmlString);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPX and KML files saved successfully'),
        duration: Duration(seconds: 3),
      ),
    );

    setState(() {
      _isGpxFileSaved = true;
    });
  }

  void _updateLocationInfo({bool navigate = false, bool isIndistance = false}) {
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
        if (_isTracking && isIndistance) {
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
        title: Text('GIS Tracker'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 1,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _isLoading
                    ? Center(child: CircularProgressIndicator())
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _requestPermissionAndGetLocation,
                            child: Text('Request Location'),
                          ),
                          SizedBox(height: 10),
                          Text(
                            _locationInfo,
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 10),
                          TextField(
                            decoration: InputDecoration(
                              labelText: 'Distance Filter (m)',
                              hintText: 'Enter distance threshold',
                              helperText:
                                  "Before adding next point on your track how much distance threshold you want to apply ?",
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(
                                text: _distanceFilter.toString()),
                            onChanged: (value) {
                              setState(() {
                                _distanceFilter = int.tryParse(value) ?? 4;
                              });
                            },
                          ),
                          SizedBox(height: 10),
                          if (_isTracking)
                            ElevatedButton(
                              onPressed: _pauseTracking,
                              child: Text('Pause Tracking'),
                            ),
                          if (!_isTracking &&
                              !_isGpxFileSaved &&
                              !_isTrackingPaused)
                            ElevatedButton(
                              onPressed: _startTracking,
                              child: Text('Start Tracking'),
                            ),
                          SizedBox(height: 10),
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
                          if (!_isTracking && _isTrackingPaused)
                            ElevatedButton(
                              onPressed: _resumeTracking,
                              child: Text('Resume Tracking'),
                            ),
                          if (_isTracking && !_isGpxFileSaved)
                            Column(
                              children: [
                                SizedBox(height: 10),
                                TextFormField(
                                  onChanged: (value) {
                                    setState(() {
                                      _gpxFilename = value;
                                    });
                                  },
                                  controller:
                                      TextEditingController(text: _gpxFilename),
                                  decoration: InputDecoration(
                                    labelText: 'File Name',
                                    hintText:
                                        'Enter file name for your track , By default : Timestamp',
                                  ),
                                ),
                                SizedBox(height: 10),
                                ElevatedButton(
                                  onPressed: _saveGpxFile,
                                  child: Text('Finish Track'),
                                ),
                              ],
                            ),
                          if (_isTracking && !_isGpxFileSaved)
                            Text(
                                'Track - Waypoints : ${_recordedPositions.length}'),
                        ],
                      ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentPosition != null
                    ? LatLng(
                        _currentPosition!.latitude, _currentPosition!.longitude)
                    : LatLng(0, 0),
                initialZoom: 18.0,
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
