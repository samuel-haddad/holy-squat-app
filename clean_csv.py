import csv
import re
import os

def clean_date(date_str):
    if not date_str: return date_str
    date_str = date_str.strip()
    if re.match(r'^\d{4}-\d{2}-\d{2}$', date_str): return date_str
    if '/' in date_str:
        date_part = date_str.split(',')[0].split(' ')[0].strip()
        parts = date_part.split('/')
        if len(parts) == 3:
            p0 = int(parts[0])
            p1 = int(parts[1])
            y = int(parts[2])
            m, d = p0, p1
            if p0 > 12: d, m = p0, p1
            return f"{y:04d}-{m:02d}-{d:02d}"
    return date_str

def clean_int(val):
    if not val: return val
    val = val.strip()
    if val.isdigit() or (val.startswith('-') and val[1:].isdigit()):
        return val
    nums = re.findall(r'-?\d+', val)
    if nums:
        return nums[0]
    return "1"

def clean_numeric(val):
    if not val: return val
    val = val.strip().replace(',', '.')
    nums = re.findall(r'-?\d+(?:\.\d+)?', val)
    if nums:
        return nums[0]
    return ""

def process_file(in_path, out_path, date_cols, int_cols, pk_col=None, drop_cols=None, dedup_pk=True, rename_cols=None, add_cols=None, num_cols=None):
    if not os.path.exists(in_path):
        print(f"File not found: {in_path}")
        return
        
    with open(in_path, 'r', encoding='utf-8-sig', errors='ignore') as fin, \
         open(out_path, 'w', encoding='utf-8', newline='') as fout:
        reader = csv.DictReader(fin)
        
        if drop_cols:
            valid_fields = [f for f in (reader.fieldnames or []) if f not in drop_cols]
        else:
            valid_fields = list(reader.fieldnames or [])
            
        if rename_cols:
            valid_fields = [rename_cols.get(f, f) for f in valid_fields]
            
        if add_cols:
            for k in add_cols:
                if k not in valid_fields:
                    valid_fields.append(k)
            
        writer = csv.DictWriter(fout, fieldnames=valid_fields, extrasaction='ignore')
        writer.writeheader()
        
        row_count = 0
        skipped_count = 0
        seen_pks = set()
        
        for row in reader:
            pk = row.get(pk_col) if pk_col else None
            if pk_col and (not pk or not pk.strip()):
                skipped_count += 1
                continue
                
            if pk_col and dedup_pk:
                if pk in seen_pks:
                    skipped_count += 1
                    continue
                seen_pks.add(pk)
                
            row_count += 1
            
            if rename_cols:
                for old_k, new_k in rename_cols.items():
                    if old_k in row:
                        row[new_k] = row.pop(old_k)
                        
            if add_cols:
                for k, v in add_cols.items():
                    row[k] = v
                    
            for col in date_cols:
                if col in row and row[col]:
                    row[col] = clean_date(row[col])
            for col in int_cols:
                if col in row and row[col]:
                    row[col] = clean_int(row[col])
            if num_cols:
                for col in num_cols:
                    if col in row and row[col]:
                        row[col] = clean_numeric(row[col])
                    
            writer.writerow(row)
            
    print(f"Processed {os.path.basename(in_path)} -> {os.path.basename(out_path)}")
    print(f" - Valid Rows: {row_count}")
    if skipped_count > 0:
        print(f" - Skipped: {skipped_count} empty ghost rows (No '{pk_col}')")

if __name__ == '__main__':
    base = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "holy-squat", "sources"))
    print(f"Starting data cleaning... (Path: {base})\n")
    
    sessions_ints = ['week', 'session']
    process_file(
        f"{base}/sessions_bkup.csv", 
        f"{base}/sessions_cleaned.csv", 
        ['date'], 
        sessions_ints, 
        pk_col='date_session_sessiontype_key', 
        dedup_pk=True,
        add_cols={'user_email': 'samuelhsm@gmail.com'}
    )
    
    workouts_ints = ['week', 'session', 'duration', 'workout_idx', 'sets', 'time_exercise', 'rest', 'rest_round', 'total_time', 'done', 'reps_done', 'duration_done', 'PSE']
    workouts_drop = ['', 'done', 'workout_date', 'PSE', 'reps_done', 'weight', 'weight_unit', 'duration_done', 'cardio_result', 'cardio_unit', 'annotations']
    process_file(
        f"{base}/workouts_bkup.csv", 
        f"{base}/workouts_cleaned.csv", 
        ['date', 'workout_date'], 
        workouts_ints, 
        pk_col='wod_exercise_id', 
        drop_cols=workouts_drop, 
        dedup_pk=True,
        add_cols={'user_email': 'samuelhsm@gmail.com'}
    )
    
    logs_ints = ['done', 'reps_done', 'duration_done', 'pse', 'PSE']
    process_file(
        f"{base}/workouts_bkup_logs.csv", 
        f"{base}/workouts_logs_cleaned.csv", 
        ['workout_date'], 
        logs_ints, 
        pk_col='wod_exercise_id', 
        dedup_pk=True,
        rename_cols={'PSE': 'pse'},
        add_cols={'user_email': 'samuelhsm@gmail.com'},
        num_cols=['weight', 'cardio_result']
    )
    
    print("\nDone! The '_cleaned.csv' files are robustly sanitized for Supabase.")
