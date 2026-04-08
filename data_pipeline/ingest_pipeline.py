import os
import time
import shutil
from dotenv import load_dotenv

os.environ["USER_AGENT"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

from supabase import create_client, Client
from google import genai
from google.genai import types
from langchain_text_splitters import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import PyPDFLoader, WebBaseLoader, YoutubeLoader

load_dotenv()

# ==========================================
# 1. Configs and Credentials
# ==========================================
SUPABASE_URL = os.environ.get("SUPABASE_URL")
SUPABASE_KEY = os.environ.get("SUPABASE_KEY")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY")

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
gemini_client = genai.Client(api_key=GEMINI_API_KEY)
EMBEDDING_MODEL = 'gemini-embedding-001'

RAW_PDF_DIR = "./raw_data/pdfs"
DONE_PDF_DIR = "./raw_data/concluidos"
URLS_FILE = "./raw_data/urls.txt"
URLS_DONE_FILE = "./raw_data/urls_concluidas.txt"
os.makedirs(DONE_PDF_DIR, exist_ok=True)

text_splitter = RecursiveCharacterTextSplitter(
    chunk_size=1000,
    chunk_overlap=200,
    length_function=len,
    is_separator_regex=False,
)

def get_gemini_embeddings_batch(texts: list[str]) -> list[list[float]]:
    max_retries = 3
    espera = 5
    for tentativa in range(max_retries):
        try:
            response = gemini_client.models.embed_content(
                model=EMBEDDING_MODEL,
                contents=texts,
                config=types.EmbedContentConfig(
                    task_type="RETRIEVAL_DOCUMENT",
                    title="Crossfit and Rehab Literature",
                    output_dimensionality=768
                )
            )
            return [emb.values for emb in response.embeddings]
        except Exception as e:
            print(f"      [!] Network or API failure: {e}")
            print(f"      [Zzz] Retrying in {espera}s...")
            time.sleep(espera)
            espera += 10 
    return []

def limpar_dados_parciais(source_identifier: str):
    try:
        supabase.table("knowledge_base").delete().contains("metadata", {"file_id": source_identifier}).execute()
    except Exception:
        pass 

def sanitizar_texto_para_banco(texto: str) -> str:
    if not texto:
        return ""
    return texto.replace('\x00', '').replace('\u0000', '')

def process_and_upload(loader, source_identifier: str):
    print(f"\n⚡ Starting turbo processing: {source_identifier}")
    limpar_dados_parciais(source_identifier)
    
    try:
        pages = loader.load()
        chunks = text_splitter.split_documents(pages)
        total_chunks = len(chunks)
        print(f"-> Divided into {total_chunks} semantic blocks.")
        
        batch_size = 100 
        
        for i in range(0, total_chunks, batch_size):
            lote_chunks = chunks[i : i + batch_size]
            textos_do_lote = [sanitizar_texto_para_banco(chunk.page_content) for chunk in lote_chunks]
            
            vetores = get_gemini_embeddings_batch(textos_do_lote)
            
            if not vetores or len(vetores) != len(textos_do_lote):
                print(f"Unrecoverable failure. Aborting {source_identifier}.")
                return False
            
            records_to_insert = []
            for j, vetor in enumerate(vetores):
                metadados_enriquecidos = lote_chunks[j].metadata
                metadados_enriquecidos["file_id"] = source_identifier
                
                records_to_insert.append({
                    "content": textos_do_lote[j], 
                    "metadata": metadados_enriquecidos,
                    "embedding": vetor
                })
            
            supabase.table("knowledge_base").insert(records_to_insert).execute()
            print(f"-> Inserted {len(records_to_insert)} blocks ({min(i + batch_size, total_chunks)}/{total_chunks}).")

        print(f"-> ✅ {source_identifier} completed successfully!")
        return True
        
    except Exception as e:
        print(f"Error processing content from {source_identifier}: {e}")
        return False

def get_loader_for_url(url: str):
    url_lower = url.lower()
    
    # Adds https:// if the link is broken (Ex: www.aim7.com)
    if not url_lower.startswith("http://") and not url_lower.startswith("https://"):
        url = "https://" + url
        url_lower = url.lower()

    if "youtube.com" in url_lower or "youtu.be" in url_lower:
        print("   [Router] YouTube link detected.")
        return YoutubeLoader.from_youtube_url(url, add_video_info=True, language=["pt", "en", "es"])
    
    elif url_lower.endswith(".pdf"):
        print("   [Router] Web PDF detected.")
        # We use headers to pretend to be a Chrome browser and avoid a 406 error
        headers = {"User-Agent": os.environ["USER_AGENT"]}
        return PyPDFLoader(url, headers=headers)
    
    else:
        print("   [Router] Standard website detected.")
        # requests_kwargs={'verify': False} ignores SSL certificate errors (DOI error)
        return WebBaseLoader(url, requests_kwargs={'verify': False})

# ==========================================
# 3. Pipeline Execution
# ==========================================
if __name__ == "__main__":
    
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning) # Hides red SSL warnings in the terminal

    if os.path.exists(RAW_PDF_DIR):
        print("=== STARTING PDF INGESTION (TURBO MODE) ===")
        for filename in os.listdir(RAW_PDF_DIR):
            if filename.endswith(".pdf"):
                full_path = os.path.join(RAW_PDF_DIR, filename)
                try:
                    loader = PyPDFLoader(full_path)
                    sucesso = process_and_upload(loader, filename)
                    if sucesso:
                        shutil.move(full_path, os.path.join(DONE_PDF_DIR, filename))
                    else:
                        print("-> ❌ Failure. File kept in queue.")
                except Exception as e:
                    print(f"❌ Fatal failure when trying to open the local file {filename}: {e}")
    
    # --- PROCESSAMENTO DE URLs ---
    URLS_DEAD_FILE = "./raw_data/urls_mortas.txt" # The graveyard of links

    if os.path.exists(URLS_FILE):
        print("\n=== STARTING WEB LINKS INGESTION ===")
        
        urls_ja_concluidas = set()
        if os.path.exists(URLS_DONE_FILE):
            with open(URLS_DONE_FILE, "r") as f_done:
                urls_ja_concluidas = set(line.strip() for line in f_done.readlines())
                
        # Also loads dead URLs so we do not try again
        urls_mortas = set()
        if os.path.exists(URLS_DEAD_FILE):
            with open(URLS_DEAD_FILE, "r") as f_dead:
                urls_mortas = set(line.strip() for line in f_dead.readlines())

        with open(URLS_FILE, "r") as file:
            urls = file.readlines()
            for url in urls:
                url = url.strip()
                if not url:
                    continue
                    
                if url in urls_ja_concluidas:
                    print(f"✅ Skipping already processed URL: {url}")
                    continue
                    
                if url in urls_mortas:
                    print(f"💀 Skipping dead/no-subtitle URL: {url}")
                    continue

                try:
                    loader = get_loader_for_url(url)
                    sucesso = process_and_upload(loader, url)
                    
                    if sucesso:
                        with open(URLS_DONE_FILE, "a") as f_done:
                            f_done.write(url + "\n")
                    else:
                        print(f"-> ❌ Processing failure. Moving to dead links list: {url}")
                        with open(URLS_DEAD_FILE, "a") as f_dead:
                            f_dead.write(url + "\n")
                            
                except Exception as e:
                    print(f"❌ Connection fatal failure with URL {url}: {e}")
                    print("-> Moving to dead links list.")
                    with open(URLS_DEAD_FILE, "a") as f_dead:
                        f_dead.write(url + "\n")
                    
    print("\n🚀 Ingestion Pipeline Finished!")