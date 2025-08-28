import json, os, re
from typing import Iterable, List, Tuple

from src.config import JSONL_DIR, MAX_TOKENS, OVERLAP, MAX_CHUNK_CHARS, MIN_CHUNK_CHARS

# Optional tokenizer; fall back to char-count
try:
    import tiktoken
    _enc = tiktoken.get_encoding("cl100k_base")
    def _tok(s: str) -> List[int]: return _enc.encode(s)
    def _detok(toks: List[int]) -> str: return _enc.decode(toks)
except Exception:
    _enc = None
    def _tok(s: str) -> List[str]: return list(s)
    def _detok(toks: List[str]) -> str: return "".join(toks)

_CODE_FENCE_RE = re.compile(r"^```")

def _split_on_headers(md: str) -> List[str]:
    """Prefer splitting on headings to preserve section semantics."""
    parts, buf = [], []
    for line in md.splitlines(keepends=True):
        if line.startswith("#"):
            if buf:
                parts.append("".join(buf))
                buf = []
        buf.append(line)
    if buf: parts.append("".join(buf))
    return parts or [md]

def _chunk_tokens(text: str, max_tokens: int, overlap: int) -> List[str]:
    toks = _tok(text)
    chunks, i = [], 0
    while i < len(toks):
        j = min(i + max_tokens, len(toks))
        piece = _detok(toks[i:j])
        # try to not end inside a fenced code block
        if piece.count("```") % 2 == 1:
            # extend until fence closes or we hit end
            while j < len(toks):
                j += 50
                piece = _detok(toks[i:min(j,len(toks))])
                if piece.count("```") % 2 == 0:
                    break
        chunks.append(piece)
        if j >= len(toks): break
        i = j - overlap
        if i < 0: i = 0
    return chunks

def chunk_markdown(md: str, doc_id: str, url: str) -> List[dict]:
    """Return a list of chunk records with metadata."""
    if not md:
        return []
    sections = _split_on_headers(md)
    results = []
    for sec in sections:
        sec = sec.strip()
        if not sec:
            continue
        if _enc:
            pieces = _chunk_tokens(sec, MAX_TOKENS, OVERLAP)
        else:
            # fallback on characters
            pieces = [sec[i:i+MAX_CHUNK_CHARS] for i in range(0, len(sec), MAX_CHUNK_CHARS - int(0.2*MAX_CHUNK_CHARS))]
        for idx, piece in enumerate(pieces):
            if len(piece) < MIN_CHUNK_CHARS and len(pieces) > 1:
                continue
            results.append({
                "id": f"{doc_id}#{len(results)}",
                "url": url,
                "text": piece
            })
    return results

def build_chunks(pages_jsonl: str) -> str:
    chunks_out = os.path.join(JSONL_DIR, "workato_sdk_chunks.jsonl")
    cnt = 0
    with open(pages_jsonl, encoding="utf-8") as src, open(chunks_out, "w", encoding="utf-8") as dst:
        for line in src:
            rec = json.loads(line)
            for ch in chunk_markdown(rec["markdown"], rec["id"], rec["url"]):
                dst.write(json.dumps(ch, ensure_ascii=False) + "\n")
                cnt += 1
    print(f"Wrote {cnt} chunks -> {chunks_out}")
    return chunks_out
