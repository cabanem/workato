# chunk_jsonl.py
import json
try:
    import tiktoken
    enc = tiktoken.get_encoding("cl100k_base")
    def tokenize(s): return enc.encode(s)
    def detokenize(t): return enc.decode(t)
except Exception:
    enc = None
    def tokenize(s): return list(s)
    def detokenize(t): return "".join(t)

MAX_TOKENS, OVERLAP = 1500, 200
def chunks(text):
    toks = tokenize(text)
    i = 0
    while i < len(toks):
        yield detokenize(toks[i:i+MAX_TOKENS])
        i += MAX_TOKENS - OVERLAP

with open("workato_sdk_docs.jsonl", encoding="utf-8") as src, \
     open("workato_sdk_chunks.jsonl","w",encoding="utf-8") as dst:
    for line in src:
        rec = json.loads(line)
        for j, piece in enumerate(chunks(rec["text"])):
            dst.write(json.dumps({
                "id": f"{rec['id']}#{j}", "url": rec["url"], "text": piece
            }) + "\n")
print("Wrote workato_sdk_chunks.jsonl")
