# crawl_workato_sdk.py
import os, time, json, hashlib
from urllib.parse import urljoin, urlparse, urldefrag
from collections import deque

import requests
from bs4 import BeautifulSoup
import trafilatura
from urllib import robotparser

START_URLS = [
    "https://docs.workato.com/en/developing-connectors/sdk.html",
    "https://docs.workato.com/developing-connectors/sdk.html",
    "https://docs.workato.com/developing-connectors/sdk/"
]
HOST = "docs.workato.com"
PREFIXES = ("/developing-connectors/sdk", "/en/developing-connectors/sdk")
UA = "DocIngestor/1.0 (+your-email-or-site)"
SLEEP = 0.5
MAX_PAGES = 300

def canonical(u): return urldefrag(u)[0]
def allowed(u, rp):
    p = urlparse(u)
    if p.netloc != HOST: return False
    if not any(p.path.startswith(pre) for pre in PREFIXES): return False
    if p.path.endswith((".png",".jpg",".gif",".svg",".pdf",".zip",".mp4")): return False
    try:
        return rp.can_fetch(UA, u)
    except Exception:
        return True

# robots.txt courtesy
rp = robotparser.RobotFileParser()
try:
    rp.set_url("https://docs.workato.com/robots.txt")
    rp.read()
except Exception:
    pass

os.makedirs("out-md", exist_ok=True)
visited, queue, records = set(), deque(START_URLS), []

headers = {"User-Agent": UA}
while queue and len(visited) < MAX_PAGES:
    url = canonical(queue.popleft())
    if url in visited or not allowed(url, rp): continue
    visited.add(url)
    try:
        r = requests.get(url, headers=headers, timeout=25)
        r.raise_for_status()
    except Exception as e:
        print("Fetch failed:", url, e); continue

    html = r.text
    md = trafilatura.extract(
        html, output_format="markdown", include_links=True,
        include_formatting=True, url=url
    )
    if not md: 
        print("Extract failed:", url); continue

    digest = hashlib.md5(url.encode()).hexdigest()[:6]
    path_slug = urlparse(url).path.strip("/").replace("/", "_") or "index"
    out_path = os.path.join("out-md", f"{path_slug}_{digest}.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(f"# Source: {url}\n\n{md}")
    records.append({"url": url, "path": out_path})

    # discover in-scope links
    soup = BeautifulSoup(html, "html.parser")
    for a in soup.find_all("a", href=True):
        nxt = canonical(urljoin(url, a["href"]))
        if nxt not in visited and allowed(nxt, rp):
            queue.append(nxt)

    time.sleep(SLEEP)

# Pack to JSONL for your indexer / fine‑tuner
with open("workato_sdk_docs.jsonl","w",encoding="utf-8") as out:
    for r in records:
        with open(r["path"], encoding="utf-8") as f:
            out.write(json.dumps({"id": r["path"], "url": r["url"], "text": f.read()}) + "\n")

print(f"Saved {len(records)} pages to out-md/ and workato_sdk_docs.jsonl")
