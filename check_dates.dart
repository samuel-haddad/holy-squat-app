import 'dart:io';

void checkDates(String filePath, List<String> colNames) {
  print('--- \$filePath ---');
  try {
    final file = File(filePath);
    final lines = file.readAsLinesSync();
    if (lines.isEmpty) return;
    
    final headerStr = lines.first;
    // Simple split for header
    final headers = headerStr.split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*\$)')).map((e) => e.trim().replaceAll('"', '')).toList();
    
    final Map<String, int> colIndices = {};
    for (var col in colNames) {
      final idx = headers.indexOf(col);
      if (idx != -1) {
        colIndices[col] = idx;
      }
    }
    
    final Map<String, Set<String>> uniqueVals = { for (var item in colNames) item : <String>{} };
    
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      
      final parts = line.split(RegExp(r',(?=(?:[^"]*"[^"]*")*[^"]*\$)')).map((e) => e.trim().replaceAll('"', '')).toList();
      for (var col in colNames) {
        if (colIndices.containsKey(col)) {
          final idx = colIndices[col]!;
          if (idx < parts.length) {
            final val = parts[idx];
            if (val.isNotEmpty) {
              uniqueVals[col]!.add(val);
            }
          }
        }
      }
    }
    
    for (var col in colNames) {
      final vals = uniqueVals[col]!.toList();
      print('\$col - Total unique: \${vals.length}');
      print('Samples: \${vals.take(15).toList()}');
    }
    print('Total Rows: \${lines.length - 1}');
  } catch (e) {
    print('Error: \$e');
  }
}

void main() {
  checkDates(r'D:\OneDrive\Desktop\samuel-haddad\holy-squat\sources\sessions_bkup.csv', ['date']);
  checkDates(r'D:\OneDrive\Desktop\samuel-haddad\holy-squat\sources\workouts_bkup.csv', ['date', 'workout_date']);
  checkDates(r'D:\OneDrive\Desktop\samuel-haddad\holy-squat\sources\workouts_bkup_logs.csv', ['workout_date']);
}
