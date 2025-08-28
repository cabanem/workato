import hashlib, json, os, time
from collections import deque
from urllib import robotparser
from urllib.parse import urljoin, urlparse, urldefrag

import requests
from bs4 import BeautifulSoup
import trafilatura

from src.config import (START_URLS, HOST, PREFIXES, RAW_DIR, MD_DIR, JSONL_DIR,
                        USER_AGENT, REQUEST_TIMEOUT, SLEEP_SECS, MAX_PAGES)

HEADERS = {"User-Agent": USER_AGENT}

def _canonical(u: str) -> str:
    return urldefrag(u)[0]

def _allowed(u: str, rp: robotparser.RobotFileParser) -> bool:
    p = urlparse(u)
    if p.netloc != HOST:
        return False
    if not any(p.path.startswith(pre) for pre in PREFIXES):
        return False
    if p.path.endswith((".png",".jpg",".jpeg",".gif",".svg",".pdf",".zip",".mp4",".webm",".ico")):
        return False
    try:
        return rp.can_fetch(USER_AGENT, u)
    except Exception:
        return True

def _slug_for_url(u: str) -> str:
    p = urlparse(u)
    slug = p.path.strip("/").replace("/", "_") or "index"
    h = hashlib.md5(u.encode()).hexdigest()[:8]
    return f"{slug}_{h}"

def _save(path: str, text: str):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

def crawl_and_extract() -> str:
    """
    Crawls the Workato Connector SDK docs section, extracts main Markdown,
    and writes page-level JSONL with {id,url,title,markdown}.
    Returns the path to the page-level JSONL.
    """
    # robots.txt
    rp = robotparser.RobotFileParser()
    try:
        rp.set_url("https://docs.workato.com/robots.txt")
        rp.read()
    except Exception:
        pass

    visited = set()
    q = deque(START_URLS)
    page_records = []

    # Conditional GET cache
    cache_path = os.path.join(JSONL_DIR, "http_cache.json")
    try:
        cond_cache = json.load(open(cache_path, encoding="utf-8"))
    except Exception:
        cond_cache = {}

    def cond_headers(u: str):
        hd = {"User-Agent": USER_AGENT}
        meta = cond_cache.get(u, {})
        if "etag" in meta:
            hd["If-None-Match"] = meta["etag"]
        if "last_modified" in meta:
            hd["If-Modified-Since"] = meta["last_modified"]
        return hd

    n = 0
    while q and n < MAX_PAGES:
        url = _canonical(q.popleft())
        if url in visited or not _allowed(url, rp):
            continue
        visited.add(url)

        try:
            r = requests.get(url, headers=cond_headers(url), timeout=REQUEST_TIMEOUT, allow_redirects=True)
        except Exception as e:
            print("Fetch failed:", url, e); continue

        if r.status_code == 304:
            # unchanged—load existing artifacts if any
            print("Unchanged:", url)
            n += 1
            continue
        if r.status_code >= 400:
            print("Bad status:", r.status_code, url); continue

        # Update cache keys
        cond_cache[url] = {
            "etag": r.headers.get("ETag", ""),
            "last_modified": r.headers.get("Last-Modified", "")
        }

        html = r.text

        # Persist raw HTML
        slug = _slug_for_url(url)
        raw_path = os.path.join(RAW_DIR, f"{slug}.html")
        _save(raw_path, html)

        # Extract main content to Markdown
        md = trafilatura.extract(
            html, output_format="markdown", include_links=True,
            include_formatting=True, url=url
        )
        if not md:
            print("Extract failed:", url)
            md = ""

        md_path = os.path.join(MD_DIR, f"{slug}.md")
        _save(md_path, f"# Source: {url}\n\n{md}")

        # Title from HTML <title>
        soup = BeautifulSoup(html, "html.parser")
        title = (soup.title.text.strip() if soup.title else "")

        page_records.append({
            "id": slug,
            "url": url,
            "title": title,
            "markdown": md
        })
        n += 1
        print(f"[{n}] {url}")

        # Discover in-scope links
        for a in soup.find_all("a", href=True):
            nxt = _canonical(urljoin(url, a["href"]))
            if nxt not in visited and _allowed(nxt, rp):
                q.append(nxt)

        time.sleep(SLEEP_SECS)

    # Write page-level JSONL
    out_path = os.path.join(JSONL_DIR, "workato_sdk_pages.jsonl")
    with open(out_path, "w", encoding="utf-8") as out:
        for rec in page_records:
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")

    # Save conditional cache
    with open(cache_path, "w", encoding="utf-8") as f:
        json.dump(cond_cache, f)

    print(f"Saved {len(page_records)} pages -> {out_path}")
    return out_path
