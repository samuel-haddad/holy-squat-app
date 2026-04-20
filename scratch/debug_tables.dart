import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:io';

void main() async {
  final envFile = File('env.json');
  final env = jsonDecode(await envFile.readAsString());
  
  await Supabase.initialize(
    url: env['SUPABASE_URL'],
    anonKey: env['SUPABASE_ANON_KEY'],
  );
  
  final client = Supabase.instance.client;
  
  print('--- Checking "pr" table ---');
  try {
    final resPr = await client.from('pr').select().limit(1);
    print('Table "pr" row: $resPr');
  } catch (e) {
    print('Error checking "pr" table: $e');
  }
  
  print('\n--- Checking "pr_log" table ---');
  try {
    final resLog = await client.from('pr_log').select().limit(1);
    print('Table "pr_log" row: $resLog');
  } catch (e) {
    print('Error checking "pr_log" table: $e');
  }
  
  exit(0);
}
