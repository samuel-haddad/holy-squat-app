import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main() async {
  final envFile = File('env.json');
  final env = jsonDecode(await envFile.readAsString());
  
  final anonKey = env['SUPABASE_ANON_KEY'];
  final baseUrl = env['SUPABASE_URL'] + '/rest/v1/';
  
  final tables = ['benchmarks', 'benchmarks_logs'];
  
  for (var table in tables) {
    print('--- Checking "$table" table structure ---');
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$table?select=*&limit=1'),
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
    print('');
  }
}
