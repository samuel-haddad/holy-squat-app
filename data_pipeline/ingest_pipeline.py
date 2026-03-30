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
# 1. Configurações e Credenciais
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
            print(f"      [!] Falha na rede ou API: {e}")
            print(f"      [Zzz] Retentando em {espera}s...")
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
    print(f"\n⚡ Iniciando processamento turbo: {source_identifier}")
    limpar_dados_parciais(source_identifier)
    
    try:
        pages = loader.load()
        chunks = text_splitter.split_documents(pages)
        total_chunks = len(chunks)
        print(f"-> Dividido em {total_chunks} blocos semânticos.")
        
        batch_size = 100 
        
        for i in range(0, total_chunks, batch_size):
            lote_chunks = chunks[i : i + batch_size]
            textos_do_lote = [sanitizar_texto_para_banco(chunk.page_content) for chunk in lote_chunks]
            
            vetores = get_gemini_embeddings_batch(textos_do_lote)
            
            if not vetores or len(vetores) != len(textos_do_lote):
                print(f"Falha irrecuperável. Abortando {source_identifier}.")
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
            print(f"-> Inseridos {len(records_to_insert)} blocos ({min(i + batch_size, total_chunks)}/{total_chunks}).")

        print(f"-> ✅ {source_identifier} concluído com sucesso!")
        return True
        
    except Exception as e:
        print(f"Erro ao processar conteúdo de {source_identifier}: {e}")
        return False

def get_loader_for_url(url: str):
    url_lower = url.lower()
    
    # Adiciona https:// caso o link venha quebrado (Ex: www.aim7.com)
    if not url_lower.startswith("http://") and not url_lower.startswith("https://"):
        url = "https://" + url
        url_lower = url.lower()

    if "youtube.com" in url_lower or "youtu.be" in url_lower:
        print("   [Roteador] Detetado link do YouTube.")
        return YoutubeLoader.from_youtube_url(url, add_video_info=True, language=["pt", "en", "es"])
    
    elif url_lower.endswith(".pdf"):
        print("   [Roteador] Detetado PDF web.")
        # Usamos cabeçalhos para fingir ser um Chrome e evitar o erro 406
        headers = {"User-Agent": os.environ["USER_AGENT"]}
        return PyPDFLoader(url, headers=headers)
    
    else:
        print("   [Roteador] Detetado site padrão.")
        # O requests_kwargs={'verify': False} ignora erros de certificado SSL (Erro do DOI)
        return WebBaseLoader(url, requests_kwargs={'verify': False})

# ==========================================
# 3. Execução do Pipeline
# ==========================================
if __name__ == "__main__":
    
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning) # Esconde os avisos vermelhos de SSL no terminal

    if os.path.exists(RAW_PDF_DIR):
        print("=== INICIANDO INGESTÃO DE PDFs (MODO TURBO) ===")
        for filename in os.listdir(RAW_PDF_DIR):
            if filename.endswith(".pdf"):
                full_path = os.path.join(RAW_PDF_DIR, filename)
                try:
                    loader = PyPDFLoader(full_path)
                    sucesso = process_and_upload(loader, filename)
                    if sucesso:
                        shutil.move(full_path, os.path.join(DONE_PDF_DIR, filename))
                    else:
                        print("-> ❌ Falha. Arquivo mantido na fila.")
                except Exception as e:
                    print(f"❌ Falha fatal ao tentar abrir o ficheiro local {filename}: {e}")
    
    # --- PROCESSAMENTO DE URLs ---
    URLS_DEAD_FILE = "./raw_data/urls_mortas.txt" # O cemitério de links

    if os.path.exists(URLS_FILE):
        print("\n=== INICIANDO INGESTÃO DE LINKS WEB ===")
        
        urls_ja_concluidas = set()
        if os.path.exists(URLS_DONE_FILE):
            with open(URLS_DONE_FILE, "r") as f_done:
                urls_ja_concluidas = set(line.strip() for line in f_done.readlines())
                
        # Carrega também as URLs mortas para não tentar de novo
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
                    print(f"✅ Saltando URL já processada: {url}")
                    continue
                    
                if url in urls_mortas:
                    print(f"💀 Saltando URL morta/sem legendas: {url}")
                    continue

                try:
                    loader = get_loader_for_url(url)
                    sucesso = process_and_upload(loader, url)
                    
                    if sucesso:
                        with open(URLS_DONE_FILE, "a") as f_done:
                            f_done.write(url + "\n")
                    else:
                        print(f"-> ❌ Falha no processamento. Movendo para a lista de mortos: {url}")
                        with open(URLS_DEAD_FILE, "a") as f_dead:
                            f_dead.write(url + "\n")
                            
                except Exception as e:
                    print(f"❌ Falha fatal de ligação com a URL {url}: {e}")
                    print("-> Movendo para a lista de mortos.")
                    with open(URLS_DEAD_FILE, "a") as f_dead:
                        f_dead.write(url + "\n")
                    
    print("\n🚀 Pipeline de Ingestão Finalizado!")