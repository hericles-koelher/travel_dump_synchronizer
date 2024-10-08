import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

Future<void> synchronize({
  required String travelJsonPath,
  required String coordinatesJsonPath,
  required username,
  required password,
}) async {
  print('Checking username and password...');

  final bearerToken = await _getBearerToken(username, password);

  if (bearerToken == null) {
    return;
  }

  print('username and password are correct!');

  final travelJson =
      (jsonDecode(await _getFileContent(travelJsonPath))['objects'] as List)
          .cast<Map<String, dynamic>>();

  final coordinatesJson =
      (jsonDecode(await _getFileContent(coordinatesJsonPath))['objects']
              as List)
          .cast<Map<String, dynamic>>();

  // (ID, TRAVEL, COORDINATES)
  final travelsWithCoordinates =
      <(String, Map<String, dynamic>, List<Map<String, dynamic>>)>[];

  print('Pairing travels and coordinates...');

  for (final travel in travelJson) {
    final travelId = travel['dbId'] as String;

    final coordinates = coordinatesJson
        .where((coordinates) => coordinates['travelId'] == travelId)
        .toList();

    travelsWithCoordinates.add((travelId, travel, coordinates));
  }

  print('Synchronizing travels...');
  for (final travelWithCoordinates in travelsWithCoordinates) {
    print(
      '------------- Synchronizing travel ${travelWithCoordinates.$1} -------------',
    );

    final travel = travelWithCoordinates.$2;
    final coordinates = travelWithCoordinates.$3;

    await _synchronizeTravel(
      travel: travel,
      coordinates: coordinates,
      username: username,
      password: password,
    );

    print(
      '------------- Travel ${travelWithCoordinates.$1} synchronized successfully! -------------',
    );

    sleep(Duration(seconds: 5));
  }
}

Future<String> _getFileContent(String filePath) async {
  print('Reading file content...');
  print('File path: $filePath');

  try {
    final file = File(filePath);

    print('File size: ${await file.length()} bytes');

    return file.readAsString();
  } catch (e) {
    print('Error: $e');

    return '';
  }
}

Future<String?> _getBearerToken(String user, String password) async {
  final response = await http.post(
      Uri.parse('https://rsp.motora.ai/api/auth/local'),
      body: jsonEncode({'username': user, 'password': password}),
      headers: {'Content-Type': 'application/json'});

  if (response.statusCode >= 200 && response.statusCode < 300) {
    final responseBody = jsonDecode(response.body);

    return responseBody['token'];
  } else {
    print('Error getting bearer token!');
    print('Status code: ${response.statusCode}');
    print('Response body: ${response.body}');

    return null;
  }
}

Future<void> _synchronizeTravel({
  required dynamic travel,
  required List<dynamic> coordinates,
  required username,
  required password,
}) async {
  var bearerToken = await _getBearerToken(username, password);

  var travelWasCreated = travel['isCreatedInAPI'];

  while (!travelWasCreated) {
    print('Creating travel...');

    final requestBody = jsonEncode(
      {
        'inicio': travel['timestamp'],
        'placa': travel['plate'],
        'cpf': travel['cpf'],
        'app_version': travel['appVersion'],
        'phone_imei': travel['imei'],
        'phone_model': travel['phoneModelName'],
      },
    );

    final response = await http.post(
      Uri.parse('https://rsp.motora.ai/api/travels'),
      body: requestBody,
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Content-Type': 'application/json'
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Travel created successfully!');

      final responseBody = jsonDecode(response.body);

      travel['id'] = responseBody['id'];

      travelWasCreated = true;
    } else {
      print('Error creating travel!');
      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');
      print('Trying again in 10 seconds');

      sleep(Duration(seconds: 10));
    }
  }

  print('Updating travel ${travel['id']}...');

  final totalCoordinates = coordinates.length;
  var coordinatesSent = 0;

  while (coordinates.isNotEmpty) {
    final coordinatesToSend = coordinates.take(200);

    final requestBody = jsonEncode(
      coordinatesToSend
          .map((coordinate) => {
                'fk_travel': travel['id'],
                'timestamp': coordinate['timestamp'],
                'lat': coordinate['latitude'],
                'lng': coordinate['longitude'],
                'speed': coordinate['speed'],
                'course': coordinate['course'],
                'accuracy': coordinate['accuracy'],
                'battery_level': coordinate['batteryLevel'],
                'acum_distance': coordinate['totalDistanceTraveled'],
              })
          .toList(),
    );

    final response = await http.post(
      Uri.parse('https://rsp.motora.ai/api/coordinates'),
      body: requestBody,
      headers: {
        'Authorization': 'Bearer $bearerToken',
        'Content-Type': 'application/json'
      },
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Coordinates updated successfully!');

      // print('Coordinates sent: ${coordinatesToSend.length}');

      coordinatesSent += coordinatesToSend.length;

      print(
        'Total coordinates sent until now: $coordinatesSent/$totalCoordinates',
      );

      coordinates.removeRange(0, coordinatesToSend.length);
    } else if (response.statusCode == 401) {
      print('Updating bearer token...');

      bearerToken = await _getBearerToken(username, password);

      print('Bearer token updated successfully!');
    } else {
      print('Error updating coordinates!');
      print('Status code: ${response.statusCode}');
      print('Response body: ${response.body}');
      print('Trying again in 10 seconds');

      sleep(Duration(seconds: 10));
    }
  }
}
