import os
from dotenv import load_dotenv

load_dotenv()

# Crawl scope
START_URLS = [u.strip() for u in os.getenv("START_URLS","").split(",") if u.strip()]
HOST = "docs.workato.com"
PREFIXES = ("/developing-connectors/sdk", "/en/developing-connectors/sdk")

# Storage
DATA_DIR = os.getenv("DATA_DIR", "./data")
RAW_DIR = os.path.join(DATA_DIR, "raw_html")
MD_DIR = os.path.join(DATA_DIR, "md")
JSONL_DIR = os.path.join(DATA_DIR, "jsonl")
INDEX_DIR = os.path.join(DATA_DIR, "index")

os.makedirs(RAW_DIR, exist_ok=True)
os.makedirs(MD_DIR, exist_ok=True)
os.makedirs(JSONL_DIR, exist_ok=True)
os.makedirs(INDEX_DIR, exist_ok=True)

# Crawl politeness
USER_AGENT = "WorkatoDocIngestor/1.0 (+your-email-or-site)"
REQUEST_TIMEOUT = 25
SLEEP_SECS = 0.6
MAX_PAGES = 500  # ample for the section

# Embeddings
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "BAAI/bge-small-en-v1.5")

# Chunking
MAX_TOKENS = 1200
OVERLAP = 150
MAX_CHUNK_CHARS = 6000  # upper bound safety if no tokenizer
MIN_CHUNK_CHARS = 600   # avoid tiny fragments

# Retrieval
TOP_K = 40          # retrieve from FAISS
RERANK = os.getenv("RERANK","true").lower() == "true"
FINAL_K = 8         # top contexts fed to the LLM

# LLM
LLM_PROVIDER = os.getenv("LLM_PROVIDER", "openai")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_BASE_URL = os.getenv("OPENAI_BASE_URL", "").strip() or None
