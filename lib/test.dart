import 'dart:io';
import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

void main() {
  runApp(gistrackerApp());
}

class gistrackerApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'gistracker',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _projectManager = ProjectManager();
  Project? _currentProject;
  Track? _currentTrack;
  LocationData? _currentLocation;

  @override
  void initState() {
    super.initState();
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final Location location = Location();
    final PermissionStatus permissionStatus = await location.hasPermission();
    if (permissionStatus == PermissionStatus.denied) {
      await location.requestPermission();
    } else {
      _listenToLocationChanges(location);
    }
  }

  void _listenToLocationChanges(Location location) {
    location.onLocationChanged.listen((LocationData currentLocation) {
      setState(() {
        _currentLocation = currentLocation;
        if (_currentTrack != null) {
          _currentTrack!.lineString
              .add([currentLocation.latitude!, currentLocation.longitude!]);
        }
      });
    });
  }

  void _startNewProject() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ProjectCreationDialog(
          onProjectCreated: (project) {
            setState(() {
              _currentProject = project;
            });
          },
        );
      },
    );
  }

  void _startNewTrack() {
    setState(() {
      _currentTrack = Track(lineString: []);
      _currentProject!.tracks.add(_currentTrack!);
    });
  }

  void _addPoint() {
    if (_currentLocation != null && _currentTrack != null) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return PointCreationDialog(
            project: _currentProject!,
            onPointAdded: (point) {
              setState(() {
                _currentTrack!.points.add(point);
              });
            },
            initialCoordinate: [
              _currentLocation!.latitude!,
              _currentLocation!.longitude!
            ],
          );
        },
      );
    }
  }

  Future<void> _exportToGeoJSON() async {
    final Directory appDirectory = await getApplicationDocumentsDirectory();
    final File file = File('${appDirectory.path}/track.geojson');
    final String geoJSON =
        jsonEncode(_projectManager.toGeoJSON(_currentProject!));
    await file.writeAsString(geoJSON);
    print('GeoJSON file saved to: ${file.path}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('gistracker'),
      ),
      body: _currentProject == null
          ? Center(
              child: ElevatedButton(
                child: Text('Start New Project'),
                onPressed: _startNewProject,
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Container(
                    // Display the map here
                    color: Colors.grey,
                    child: Center(
                      child: Text('Map View'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        child: Text('New Track'),
                        onPressed: _startNewTrack,
                      ),
                      ElevatedButton(
                        child: Text('Add Point'),
                        onPressed: _addPoint,
                      ),
                      ElevatedButton(
                        child: Text('Export'),
                        onPressed: _exportToGeoJSON,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class ProjectManager {
  List<Project> projects = [];

  void addProject(Project project) {
    projects.add(project);
  }

  Map<String, dynamic> toGeoJSON(Project project) {
    List<Map<String, dynamic>> features = [];
    for (Track track in project.tracks) {
      features.add({
        'type': 'Feature',
        'geometry': {
          'type': 'LineString',
          'coordinates': track.lineString,
        },
        'properties': {},
      });
      for (Point point in track.points) {
        features.add({
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': point.coordinate,
          },
          'properties': point.properties,
        });
      }
    }
    return {
      'type': 'FeatureCollection',
      'features': features,
    };
  }
}

class Project {
  final String name;
  final List<Track> tracks;
  final List<String> automaticProperties;

  Project({
    required this.name,
    required this.tracks,
    required this.automaticProperties,
  });
}

class Track {
  final List<List<double>> lineString;
  final List<Point> points;

  Track({required this.lineString, this.points = const []});
}

class Point {
  final List<double> coordinate;
  final Map<String, dynamic> properties;

  Point({required this.coordinate, required this.properties});
}

class ProjectCreationDialog extends StatefulWidget {
  final void Function(Project) onProjectCreated;

  const ProjectCreationDialog({
    Key? key,
    required this.onProjectCreated,
  }) : super(key: key);

  @override
  _ProjectCreationDialogState createState() => _ProjectCreationDialogState();
}

class _ProjectCreationDialogState extends State<ProjectCreationDialog> {
  String _projectName = '';
  List<String> _automaticProperties = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('New Project'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            onChanged: (value) {
              _projectName = value;
            },
            decoration: InputDecoration(
              hintText: 'Enter project name',
            ),
          ),
          SizedBox(height: 16),
          Text('Automatic Properties'),
          TextField(
            onChanged: (value) {
              _automaticProperties = value.split(',');
            },
            decoration: InputDecoration(
              hintText: 'Enter property keys (comma-separated)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text('Create'),
          onPressed: () {
            final project = Project(
              name: _projectName,
              tracks: [],
              automaticProperties: _automaticProperties,
            );
            widget.onProjectCreated(project);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

class PointCreationDialog extends StatefulWidget {
  final Project project;
  final void Function(Point) onPointAdded;
  final List<double> initialCoordinate;

  const PointCreationDialog({
    Key? key,
    required this.project,
    required this.onPointAdded,
    required this.initialCoordinate,
  }) : super(key: key);

  @override
  _PointCreationDialogState createState() => _PointCreationDialogState();
}

class _PointCreationDialogState extends State<PointCreationDialog> {
  final Map<String, dynamic> _properties = {};

  @override
  void initState() {
    super.initState();
    for (String key in widget.project.automaticProperties) {
      _properties[key] = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Point'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...widget.project.automaticProperties.map((key) => TextField(
                onChanged: (value) {
                  _properties[key] = value;
                },
                decoration: InputDecoration(
                  hintText: 'Enter value for $key',
                ),
              )),
          SizedBox(height: 16),
          Text('Additional Properties'),
          ..._properties.keys
              .where((key) => !widget.project.automaticProperties.contains(key))
              .map((key) => TextField(
                    onChanged: (value) {
                      _properties[key] = value;
                    },
                    decoration: InputDecoration(
                      hintText: 'Enter value for $key',
                    ),
                  )),
          TextField(
            onChanged: (value) {
              if (value.isNotEmpty) {
                List<String> keys = value.split(':');
                if (keys.length == 2) {
                  _properties[keys[0]] = keys[1];
                }
              }
            },
            decoration: InputDecoration(
              hintText: 'Add new property (key:value)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          child: Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(
          child: Text('Add'),
          onPressed: () {
            final point = Point(
              coordinate: widget.initialCoordinate,
              properties: _properties,
            );
            widget.onPointAdded(point);
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}
