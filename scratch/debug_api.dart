import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final envFile = File('env.json');
  final env = jsonDecode(await envFile.readAsString());
  
  final url = env['SUPABASE_URL'] + '/rest/v1/pr?select=*&limit=1';
  final anonKey = env['SUPABASE_ANON_KEY'];
  
  print('--- Checking "pr" table via REST API ---');
  try {
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
  
  final urlLog = env['SUPABASE_URL'] + '/rest/v1/pr_log?select=*&limit=1';
  print('\n--- Checking "pr_log" table via REST API ---');
  try {
    final response = await http.get(
      Uri.parse(urlLog),
      headers: {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
      },
    );
    print('Status: ${response.statusCode}');
    print('Body: ${response.body}');
  } catch (e) {
    print('Error: $e');
  }
}
