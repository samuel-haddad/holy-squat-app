import csv
def check_dates(file_path, col_names):
    print(f"--- {file_path} ---")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            unique_vals = {col: set() for col in col_names}
            row_count = 0
            for row in reader:
                row_count += 1
                for col in col_names:
                    if col in row and row[col]:
                        val = row[col].strip()
                        if val:
                            unique_vals[col].add(val)
                            
            for col in col_names:
                vals = list(unique_vals[col])
                print(f"{col} - Total unique: {len(vals)}")
                print(f"Samples: {vals[:15]}")
            print(f"Total Rows: {row_count}")
    except Exception as e:
        print(f"Error: {e}")

check_dates('/mnt/d/OneDrive/Desktop/samuel-haddad/holy-squat/sources/sessions_bkup.csv', ['date'])
check_dates('/mnt/d/OneDrive/Desktop/samuel-haddad/holy-squat/sources/workouts_bkup.csv', ['date', 'workout_date'])
check_dates('/mnt/d/OneDrive/Desktop/samuel-haddad/holy-squat/sources/workouts_bkup_logs.csv', ['workout_date'])
