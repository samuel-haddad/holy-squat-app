import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'dart:async';

void main() async {
  // We need to load .env from the root
  final envFile = File('.env');
  if (!await envFile.exists()) {
    print('Error: .env file not found');
    return;
  }

  final lines = await envFile.readAsLines();
  String? url;
  String? key;

  for (var line in lines) {
    if (line.startsWith('SUPABASE_URL=')) {
      url = line.substring('SUPABASE_URL='.length);
    } else if (line.startsWith('SUPABASE_ANON_KEY=')) {
      key = line.substring('SUPABASE_ANON_KEY='.length);
    }
  }

  if (url == null || key == null) {
    print('Error: SUPABASE_URL or SUPABASE_ANON_KEY not found in .env');
    return;
  }

  print('Connecting to $url...');
  
  // Use a simple HTTP client or initialize Supabase without Flutter
  // Since we are in a script, it's better to use pure HTTP for simplicity if we don't want to mess with supabase_flutter's requirement for WidgetsBinding
  
  /* 
  Actually, let's just use the Supabase HTTP API via dart:io
  */
  
  final client = HttpClient();
  try {
    final uri = Uri.parse('$url/rest/v1/sessions?ai_coach_name=is.null');
    final request = await client.patchUrl(uri);
    
    request.headers.add('apikey', key);
    request.headers.add('Authorization', 'Bearer $key');
    request.headers.add('Content-Type', 'application/json');
    request.headers.add('Prefer', 'return=representation');
    
    request.write('{"ai_coach_name": "Human Coach"}');
    
    final response = await request.close();
    final responseBody = await response.transform(StreamTransformer.fromHandlers(handleData: (data, sink) => sink.add(String.fromCharCodes(data)))).join();
    
    print('Response status: ${response.statusCode}');
    print('Response body: $responseBody');
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      print('Migration successful!');
    } else {
      print('Migration failed.');
    }
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
