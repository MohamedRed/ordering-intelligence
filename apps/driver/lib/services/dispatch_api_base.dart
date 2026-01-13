import 'package:firebase_auth/firebase_auth.dart';

const dispatchBaseUrl = String.fromEnvironment(
  'DISPATCH_SERVICE_URL',
  defaultValue: 'https://dispatch-service-230152279015.us-central1.run.app',
);

Future<String> fetchDispatchToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw Exception('Not signed in');
  final token = await user.getIdToken();
  if (token == null || token.isEmpty) {
    throw Exception('Failed to fetch auth token');
  }
  return token;
}

Map<String, String> dispatchHeaders(String token) => {
  'Authorization': 'Bearer $token',
  'Content-Type': 'application/json',
};
