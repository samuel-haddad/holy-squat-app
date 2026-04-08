import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:holy_squat_app/core/user_state.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show File;

class SupabaseService {
  static final client = Supabase.instance.client;

  // Profile methods
  static Future<void> getProfile() async {
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final response = await client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();
      debugPrint("Fetched profile for ${user.email}: $response");
      if (response != null) {
        if (response['avatar_url'] != null)
          UserState.avatarUrl.value = response['avatar_url'];
        if (response['name'] != null) UserState.name.value = response['name'];
        if (response['email'] != null)
          UserState.email.value = response['email'];
        if (response['birthdate'] != null)
          UserState.birthdate.value = response['birthdate'];
        if (response['weight'] != null)
          UserState.weight.value = response['weight'].toString();
        if (response['weight_unit'] != null)
          UserState.weightUnit.value = response['weight_unit'];
        if (response['favorite_sport'] != null)
          UserState.sport.value = response['favorite_sport'];
        if (response['training_goal'] != null)
          UserState.goal.value = response['training_goal'];
        
        // New Skill & Training fields (defensive checks)
        if (response['anamnesis'] != null) UserState.anamnesis.value = response['anamnesis'];
        if (response['active_hours_value'] != null) UserState.activeHoursValue.value = (response['active_hours_value'] as num).toDouble();
        if (response['active_hours_unit'] != null) UserState.activeHoursUnit.value = response['active_hours_unit'];
        if (response['sessions_per_day'] != null) UserState.sessionsPerDay.value = response['sessions_per_day'];
        if (response['where_train'] != null) UserState.whereTrain.value = List<String>.from(response['where_train']);
        if (response['additional_info'] != null) UserState.additionalInfo.value = response['additional_info'];
        if (response['background_file_url'] != null) UserState.backgroundFileUrl.value = response['background_file_url'];

        UserState.stravaConnected.value = response['strava_athlete_id'] != null;
        // Profile is complete if birthdate is set (standard for our app)
        UserState.isProfileComplete.value = response['birthdate'] != null;
      } else {
        UserState.email.value = user.email ?? 'No email';
        UserState.stravaConnected.value = false;
        UserState.isProfileComplete.value = false;
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
      await client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
      finalAvatarUrl = client.storage.from('avatars').getPublicUrl(path);
      finalAvatarUrl =
          '$finalAvatarUrl?t=${DateTime.now().millisecondsSinceEpoch}';
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
      'anamnesis': UserState.anamnesis.value,
      'active_hours_value': UserState.activeHoursValue.value,
      'active_hours_unit': UserState.activeHoursUnit.value,
      'sessions_per_day': UserState.sessionsPerDay.value,
      'where_train': UserState.whereTrain.value,
      'additional_info': UserState.additionalInfo.value,
      'background_file_url': UserState.backgroundFileUrl.value,
    });
  }

  static Future<String?> uploadTrainingBackground(PlatformFile file) async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      // Very aggressive sanitization: remove EVERYTHING that is not a letter or number
      // We keep the extension by splitting it first
      final extension = file.extension ?? 'pdf';
      final baseName = file.name.split('.').first;
      String sanitizedName = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
      
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$sanitizedName.$extension';
      final path = '${user.id}/$fileName';
      
      debugPrint("Uploading storage file to path: backgrounds/$path");
      
      if (kIsWeb) {
        if (file.bytes != null) {
          await client.storage.from('backgrounds').uploadBinary(
            path, 
            file.bytes!,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
        } else {
          return null;
        }
      } else {
        // Native platform
        final fileToUpload = File(file.path!);
        await client.storage.from('backgrounds').upload(
          path, 
          fileToUpload,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );
      }

      final url = client.storage.from('backgrounds').getPublicUrl(path);
      UserState.backgroundFileUrl.value = url;
      return url;
    } catch (e) {
      debugPrint("Error uploading training background: $e");
      rethrow; // Rethrow so the UI can catch it and show the error message
    }
  }

  static Future<List<Map<String, dynamic>>> getAICoaches() async {
    try {
      final response = await client.from('ai_coach').select().order('ai_coach_name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint("Error fetching AI coaches: $e");
      return [];
    }
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

    final String? durationVal = duration.isEmpty ? null : duration;
    final String? pseVal = pse.isEmpty ? null : pse;
    final String? repsVal = reps.isEmpty ? null : reps;
    final String? annotationsVal = annotations.isEmpty ? null : annotations;

    await client.from('workouts_logs').upsert({
      'user_email': user.email,
      'wod_exercise_id': wodExerciseId,
      'workout_date': workoutDate.toIso8601String().split('T').first,
      'done': 1,
      if (durationVal != null) 'duration_done': durationVal,
      if (pseVal != null) 'pse': pseVal,
      if (repsVal != null) 'reps_done': repsVal,
      if (weight != null) 'weight': weight,
      if (weight != null) 'weight_unit': weightUnit,
      if (cardioResult != null) 'cardio_result': cardioResult,
      if (cardioResult != null) 'cardio_unit': cardioUnit,
      if (annotationsVal != null) 'annotations': annotationsVal,
    });
  }

  static Future<Map<String, dynamic>?> getWorkoutResult(
    String wodExerciseId,
  ) async {
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
        .limit(2000);
    debugPrint("Fetched ${response.length} sessions from Supabase");
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<List<Map<String, dynamic>>> getSessionsByDate(DateTime date) async {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    debugPrint("Querying sessions for date: '$dateStr'");
    final response = await client
        .from('sessions')
        .select('*, icons(img)')
        .eq('date', dateStr)
        .order('session', ascending: true);
    
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch all workouts for a specific session
  static Future<Map<String, List<Map<String, dynamic>>>> getWorkoutsForSession(
    String sessionKey,
  ) async {
    final user = client.auth.currentUser;
    final userEmail = user?.email ?? '';

    final response = await client
        .from('workouts')
        .select('*, workouts_logs(*)')
        .eq('date_session_sessiontype_key', sessionKey)
        .order('workout_idx', ascending: true);

    final List<Map<String, dynamic>> workoutsList =
        List<Map<String, dynamic>>.from(response);

    // Group workouts and filter logs by user email and done status
    final Map<String, List<Map<String, dynamic>>> groupedUnsorted = {};
    for (var workout in workoutsList) {
      // Safely handle workouts_logs which may come as a List or Map from Supabase join
      final rawLogs = workout['workouts_logs'];
      final List<dynamic> allLogs;
      if (rawLogs is List) {
        allLogs = rawLogs;
      } else if (rawLogs is Map) {
        allLogs = [rawLogs];
      } else {
        allLogs = [];
      }

      // Filter logs to only include records done by the current user
      final List<dynamic> logs = allLogs
          .where((log) =>
              log['user_email'] == userEmail &&
              (log['done'] == 1 || log['done'] == true || log['done'] == '1'))
          .toList();

      workout['filtered_logs'] = logs;

      final stage = workout['stage']?.toString().toUpperCase() ?? 'EXERCISE';
      if (!groupedUnsorted.containsKey(stage)) {
        groupedUnsorted[stage] = [];
      }
      groupedUnsorted[stage]!.add(workout);
    }

    // Sort according to canonical order
    const canonicalOrder = ['WARMUP', 'SKILL', 'STRENGTH', 'WORKOUT', 'COOLDOWN'];
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    
    // First, add stages in canonical order if they exist
    for (var stage in canonicalOrder) {
      if (groupedUnsorted.containsKey(stage)) {
        grouped[stage] = groupedUnsorted[stage]!;
      }
    }
    
    // Then, add any other stages that might exist
    groupedUnsorted.forEach((key, value) {
      if (!canonicalOrder.contains(key)) {
        grouped[key] = value;
      }
    });

    return grouped;
  }

  // Fetch all latest PRs by grouping pr_logs
  static Future<List<Map<String, dynamic>>> getLatestPrs() async {
    final response = await client
        .from('pr_log')
        .select()
        .order('id', ascending: false);

    final List<Map<String, dynamic>> logs = List<Map<String, dynamic>>.from(
      response,
    );
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
  static Future<List<Map<String, dynamic>>> getPrLogsForExercise(
    String exercise,
  ) async {
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

  static Future<void> updatePrLog(
    dynamic id,
    double pr,
    String unit,
    String date,
  ) async {
    await client
        .from('pr_log')
        .update({'pr': pr, 'pr_unit': unit, 'date': date})
        .eq('id', id);
  }

  static Future<void> insertPrLog(
    String exercise,
    double pr,
    String unit,
    String date,
  ) async {
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
  static Future<void> upsertBenchmarkLog(
    String exercise,
    double result,
    String? date,
  ) async {
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
    await client
        .from('benchmarks')
        .update({'result_unit': unit})
        .eq('bench_exercise', exercise);
  }

  // --- ANALYTICS ---
  // Returns a list of distinct active workout dates ('YYYY-MM-DD')
  static Future<List<String>> getActiveWorkoutDates() async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return [];

    // Supabase caps each request at 1000 rows server-side, regardless of .limit().
    // We paginate with .range() to collect ALL records across multiple requests.
    final Set<String> uniqueDates = {};
    const pageSize = 1000;
    int offset = 0;

    while (true) {
      final response = await client
          .from('workouts_logs')
          .select('workout_date')
          .eq('user_email', user.email!)
          .eq('done', 1)
          .not('workout_date', 'is', null)
          .order('workout_date', ascending: true)
          .range(offset, offset + pageSize - 1);

      for (var row in response) {
        final val = row['workout_date'];
        if (val != null) {
          // Normalize to 'YYYY-MM-DD' before dedup to handle timestamps
          final normalized = val.toString().split('T').first.split(' ').first;
          uniqueDates.add(normalized);
        }
      }

      if (response.length < pageSize) break; // Last page reached
      offset += pageSize;
    }

    debugPrint("Dashboard: ${uniqueDates.length} unique active dates found.");
    return uniqueDates.toList();
  }

  static Future<void> saveStravaTokens(
      String athleteId, String accessToken, String refreshToken) async {
    final user = client.auth.currentUser;
    if (user == null) return;

    await client.from('profiles').update({
      'strava_athlete_id': athleteId,
      'strava_access_token': accessToken,
      'strava_refresh_token': refreshToken,
      'strava_connected_at': DateTime.now().toIso8601String(),
    }).eq('id', user.id);

    UserState.stravaConnected.value = true;
  }

  static Future<void> disconnectStrava() async {
    final user = client.auth.currentUser;
    if (user == null) return;

    await client.from('profiles').update({
      'strava_athlete_id': null,
      'strava_access_token': null,
      'strava_refresh_token': null,
      'strava_connected_at': null,
    }).eq('id', user.id);

    UserState.stravaConnected.value = false;
  }

  static Future<Map<String, dynamic>?> fetchLatestTrainingPlan({String? aiCoachName}) async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    try {
      var query = client
          .from('training_plans')
          .select()
          .eq('user_id', user.id);
      
      if (aiCoachName != null) {
        query = query.eq('ai_coach_name', aiCoachName);
      } else {
        // Fallback para planos antigos sem coach
        query = query.eq('ai_coach_name', 'Human Coach');
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint("Error fetching latest training plan: $e");
      return null;
    }
  }

  static Future<String> saveTrainingPlan(Map<String, dynamic> planData, {String? aiCoachName}) async {
    final user = client.auth.currentUser;
    if (user == null) return '';

    try {
      final response = await client.from('training_plans').insert({
        ...planData,
        'user_id': user.id,
        'ai_coach_name': aiCoachName ?? 'Human Coach',
      }).select('id').single();
      return response['id'] as String;
    } catch (e) {
      debugPrint("Error saving training plan: $e");
      rethrow;
    }
  }

  static Future<void> updateTrainingPlan(String id, Map<String, dynamic> updates) async {
    try {
      await client.from('training_plans').update(updates).eq('id', id);
    } catch (e) {
      debugPrint("Error updating training plan: $e");
      rethrow;
    }
  }

  // --- EDIT PLAN METHODS ---

  static Future<List<Map<String, dynamic>>> getIcons() async {
    final response = await client.from('icons').select().order('session_type');
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<List<Map<String, dynamic>>> getSessionsWithFilters({
    required DateTime start,
    DateTime? end,
    required String coach,
  }) async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return [];

    var query = client
        .from('sessions')
        .select('*, icons(img)')
        .eq('user_email', user.email!)
        .eq('ai_coach_name', coach)
        .gte('date', DateFormat('yyyy-MM-dd').format(start));

    if (end != null) {
      query = query.lte('date', DateFormat('yyyy-MM-dd').format(end));
    }

    final response = await query.order('date', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  static Future<List<Map<String, dynamic>>> getWorkoutsWithFilters({
    required DateTime start,
    DateTime? end,
    required String coach,
  }) async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return [];

    var sessionQuery = client
        .from('sessions')
        .select('date_session_sessiontype_key')
        .eq('user_email', user.email!)
        .eq('ai_coach_name', coach)
        .gte('date', DateFormat('yyyy-MM-dd').format(start));

    if (end != null) {
      sessionQuery = sessionQuery.lte('date', DateFormat('yyyy-MM-dd').format(end));
    }

    final sessionResponse = await sessionQuery;
    final List<String> sessionKeys = (sessionResponse as List)
        .map((s) => s['date_session_sessiontype_key'] as String)
        .toList();

    if (sessionKeys.isEmpty) return [];

    final response = await client
        .from('workouts')
        .select()
        .inFilter('date_session_sessiontype_key', sessionKeys)
        .order('date', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  static Future<void> updateSessionsBatch({
    required Map<String, dynamic> originalAttributes,
    required Map<String, dynamic> updates,
    required DateTime start,
    DateTime? end,
    required String coach,
  }) async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return;

    var query = client
        .from('sessions')
        .update(updates)
        .eq('user_email', user.email!)
        .eq('ai_coach_name', coach)
        .eq('session_type', originalAttributes['session_type'])
        .eq('session', originalAttributes['session'])
        .gte('date', DateFormat('yyyy-MM-dd').format(start));

    if (end != null) {
      query = query.lte('date', DateFormat('yyyy-MM-dd').format(end));
    }

    await query;
  }

  static Future<void> updateWorkoutsBatch({
    required Map<String, dynamic> originalAttributes,
    required Map<String, dynamic> updates,
    required DateTime start,
    DateTime? end,
    required String coach,
  }) async {
    final user = client.auth.currentUser;
    if (user == null || user.email == null) return;

    var sessionQuery = client
        .from('sessions')
        .select('date_session_sessiontype_key')
        .eq('user_email', user.email!)
        .eq('ai_coach_name', coach)
        .gte('date', DateFormat('yyyy-MM-dd').format(start));

    if (end != null) {
      sessionQuery = sessionQuery.lte('date', DateFormat('yyyy-MM-dd').format(end));
    }

    final sessionResponse = await sessionQuery;
    final List<String> sessionKeys = (sessionResponse as List)
        .map((s) => s['date_session_sessiontype_key'] as String)
        .toList();

    if (sessionKeys.isEmpty) return;

    var finalQuery = client
        .from('workouts')
        .update(updates)
        .inFilter('date_session_sessiontype_key', sessionKeys);

    // Grouping fields for matching
    final List<String> groupFields = [
      'mesocycle', 'day', 'exercise', 'sets', 'details', 
      'time_exercise', 'ex_unit', 'rest', 'rest_unit', 'rest_round', 
      'rest_round_unit', 'total_time', 'location', 'stage'
    ];

    for (var field in groupFields) {
      if (originalAttributes[field] == null) {
        finalQuery = finalQuery.isFilter(field, null);
      } else {
        finalQuery = finalQuery.eq(field, originalAttributes[field]);
      }
    }

    await finalQuery;
  }
}

