import os
import requests
from dotenv import load_dotenv

load_dotenv()
res = requests.get(
    f"{os.environ['SUPABASE_URL']}/rest/v1/icons?select=name,id",
    headers={"apikey": os.environ['SUPABASE_KEY'], "Authorization": f"Bearer {os.environ['SUPABASE_KEY']}"}
)
print(res.json())
