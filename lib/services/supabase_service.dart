import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:flutter/foundation.dart';

class SupabaseService {
  static final client = Supabase.instance.client;

  // Profile methods
  static Future<void> getProfile() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final response = await client.from('profiles').select().eq('id', user.id).maybeSingle();
      if (response != null) {
        if (response['avatar_url'] != null) UserState.avatarUrl.value = response['avatar_url'];
        if (response['name'] != null) UserState.name.value = response['name'];
        if (response['email'] != null) UserState.email.value = response['email'];
        if (response['birthdate'] != null) UserState.birthdate.value = response['birthdate'];
        if (response['weight'] != null) UserState.weight.value = response['weight'].toString();
        if (response['weight_unit'] != null) UserState.weightUnit.value = response['weight_unit'];
        if (response['favorite_sport'] != null) UserState.sport.value = response['favorite_sport'];
        if (response['training_goal'] != null) UserState.goal.value = response['training_goal'];
      } else {
        UserState.email.value = user.email ?? 'No email';
      }
    } catch (e) {
      debugPrint("Error fetching profile: $e");
    }
  }

  static Future<void> upsertProfile() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    
    String? finalAvatarUrl = UserState.avatarUrl.value;
    
    if (UserState.avatarBytes.value != null) {
      final bytes = UserState.avatarBytes.value!;
      final path = '${user.id}/avatar.jpg';
      await client.storage.from('avatars').uploadBinary(
        path, 
        bytes, 
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      finalAvatarUrl = client.storage.from('avatars').getPublicUrl(path);
      finalAvatarUrl = '$finalAvatarUrl?t=${DateTime.now().millisecondsSinceEpoch}';
      UserState.avatarUrl.value = finalAvatarUrl;
    }

    String? bdStr = UserState.birthdate.value;
    if (bdStr != null && bdStr.contains('/')) {
       final spl = bdStr.split('/');
       if (spl.length == 3) {
          bdStr = '${spl[2]}-${spl[1]}-${spl[0]}';
       }
    }

    await client.from('profiles').upsert({
      'id': user.id,
      'avatar_url': finalAvatarUrl,
      'name': UserState.name.value,
      'email': UserState.email.value,
      'birthdate': bdStr,
      'weight': double.tryParse(UserState.weight.value) ?? 0,
      'weight_unit': UserState.weightUnit.value,
      'favorite_sport': UserState.sport.value,
      'training_goal': UserState.goal.value,
    });
  }

  static Future<void> saveWorkoutResult({
    required String wodExerciseId,
    required DateTime workoutDate,
    required String location, // Ignored logic for now to match CSV
    required String duration,
    required String pse,
    required String reps,
    required double? weight,
    required String weightUnit,
    required double? cardioResult,
    required String cardioUnit,
    required String annotations,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) return;
    
    await client.from('workouts_logs').upsert({
      'user_email': user.email,
      'wod_exercise_id': wodExerciseId,
      'workout_date': workoutDate.toIso8601String().split('T').first,
      'done': 1,
      'duration_done': duration,
      'pse': pse,
      'reps_done': reps,
      'weight': weight,
      'weight_unit': weightUnit,
      'cardio_result': cardioResult,
      'cardio_unit': cardioUnit,
      'annotations': annotations,
    });
  }

  static Future<Map<String, dynamic>?> getWorkoutResult(String wodExerciseId) async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return null;
    
    final response = await client
        .from('workouts_logs')
        .select()
        .eq('wod_exercise_id', wodExerciseId)
        .eq('user_email', user.email!)
        .maybeSingle();
        
    return response;
  }

  // Fetch all sessions with their respective icons
  static Future<List<Map<String, dynamic>>> getSessions() async {
    final response = await client
        .from('sessions')
        .select('*, icons(img)')
        .order('date', ascending: false)
        .limit(50);
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch all workouts for a specific session
  static Future<Map<String, List<Map<String, dynamic>>>> getWorkoutsForSession(String sessionKey) async {
    final response = await client
        .from('workouts')
        .select('*, workouts_logs(*)')
        .eq('date_session_sessiontype_key', sessionKey)
        .order('workout_idx', ascending: true);
        
    final List<Map<String, dynamic>> workoutsList = List<Map<String, dynamic>>.from(response);
    
  // Group workouts by 'stage' (e.g. WARMUP, EXERCISE, COOLDOWN)
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var workout in workoutsList) {
      final stage = workout['stage']?.toString().toUpperCase() ?? 'EXERCISE';
      if (!grouped.containsKey(stage)) {
        grouped[stage] = [];
      }
      grouped[stage]!.add(workout);
    }
    
    return grouped;
  }

  // Fetch all latest PRs by grouping pr_logs
  static Future<List<Map<String, dynamic>>> getLatestPrs() async {
    final response = await client
        .from('pr_log')
        .select()
        .order('id', ascending: false);
    
    final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(response);
    final Map<String, Map<String, dynamic>> latestPrs = {};

    for (var log in logs) {
      final ex = log['exercise'] as String;
      if (!latestPrs.containsKey(ex)) {
        latestPrs[ex] = log;
      }
    }
    
    return latestPrs.values.toList();
  }

  // Fetch PR logs for a specific exercise (for the chart)
  static Future<List<Map<String, dynamic>>> getPrLogsForExercise(String exercise) async {
    final response = await client
        .from('pr_log')
        .select()
        .eq('exercise', exercise)
        .order('date', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> deletePrLog(dynamic id) async {
    await client.from('pr_log').delete().eq('id', id);
  }

  static Future<void> updatePrLog(dynamic id, double pr, String unit, String date) async {
    await client.from('pr_log').update({
      'pr': pr,
      'pr_unit': unit,
      'date': date,
    }).eq('id', id);
  }

  static Future<void> insertPrLog(String exercise, double pr, String unit, String date) async {
    await client.from('pr_log').insert({
      'exercise': exercise,
      'pr': pr,
      'pr_unit': unit,
      'date': date,
    });
  }

  // Fetch all benchmarks
  static Future<List<Map<String, dynamic>>> getBenchmarks() async {
    final response = await client
        .from('benchmarks')
        .select('*, benchmarks_logs(*)');
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch benchmark log for specific exercise
  static Future<Map<String, dynamic>?> getBenchmarkLog(String exercise) async {
    final response = await client
        .from('benchmarks_logs')
        .select()
        .eq('bench_exercise', exercise)
        .maybeSingle();
    return response;
  }

  // Upsert benchmark log
  static Future<void> upsertBenchmarkLog(String exercise, double result, String? date) async {
    final user = client.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    await client.from('benchmarks_logs').upsert({
      'bench_exercise': exercise,
      'result': result,
      if (date != null) 'date': date,
    });
  }

  // Update benchmark global unit
  static Future<void> updateBenchmarkUnit(String exercise, String unit) async {
    await client.from('benchmarks').update({
      'result_unit': unit,
    }).eq('bench_exercise', exercise);
  }

  // --- ANALYTICS ---
  // Returns a list of distinct active workout dates ('YYYY-MM-DD')
  static Future<List<String>> getActiveWorkoutDates() async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return [];
    
    final response = await client
        .from('workouts_logs')
        .select('workout_date, done')
        .eq('user_email', user.email!);
    
    // Extract strings and use a Set to uniquely count active days
    final Set<String> uniqueDates = {};
    for (var row in response) {
      final doneVal = row['done'];
      bool isDone = false;
      if (doneVal == true || doneVal == 1 || doneVal == '1' || doneVal == 'true') isDone = true;
      
      if (!isDone) continue;

      final val = row['workout_date'];
      if (val != null) {
        uniqueDates.add(val.toString());
      }
    }
    return uniqueDates.toList();
  }
}
