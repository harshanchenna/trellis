#!/usr/bin/env python3
"""Read Reddit through its public Atom feeds. Read-only, no key, stdlib only.

  reddit.py feed <sub> [--sort hot|new|top|rising] [--t hour|day|week|month|year|all] [--limit N]
  reddit.py search <sub> <query> [--sort relevance|top|new|comments] [--t ...] [--limit N]
  reddit.py thread <url-or-post-id> [--sort confidence|new|top|old|controversial] [--limit N]

All commands take --max-chars N to trim each body (default 1500).

Prints JSON. Feeds carry no scores and comments come back flat.
Reddit allows about one feed request per rate-limit window (up to ~60s). Calls
share a lock and wait out the window instead of failing, and responses are
cached for 15 minutes.
"""
import argparse
import fcntl
import hashlib
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

UA = "linux:trellis-reddit-reader:0.1 (read-only)"
BASE = "https://www.reddit.com"
CACHE_DIR = os.path.expanduser("~/.cache/trellis-reddit")
CACHE_TTL = 15 * 60
MAX_TRIES = 4
ATOM = {"a": "http://www.w3.org/2005/Atom"}


def _state_path():
    return os.path.join(CACHE_DIR, "not_before")


def _is_feed(body):
    try:
        return ET.fromstring(body).tag == f"{{{ATOM['a']}}}feed"
    except ET.ParseError:
        return False


def _cached(url):
    path = os.path.join(CACHE_DIR, hashlib.sha256(url.encode()).hexdigest() + ".xml")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < CACHE_TTL:
        with open(path, "rb") as f:
            body = f.read()
        if _is_feed(body):
            return path, body
    return path, None


def fetch(url):
    os.makedirs(CACHE_DIR, exist_ok=True)
    path, body = _cached(url)
    if body is not None:
        return body
    with open(os.path.join(CACHE_DIR, "lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path, body = _cached(url)  # another process may have fetched it while we waited
        if body is not None:
            return body
        last_error = ""
        for _ in range(MAX_TRIES):
            try:
                with open(_state_path()) as f:
                    wait = float(f.read() or 0) - time.time()
            except (FileNotFoundError, ValueError):
                wait = 0
            if wait > 0:
                print(f"reddit: rate limit, waiting {wait:.0f}s", file=sys.stderr)
                time.sleep(wait)
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            try:
                with urllib.request.urlopen(req, timeout=30) as resp:
                    body, headers, status = resp.read(), resp.headers, resp.status
            except urllib.error.HTTPError as e:
                body, headers, status = b"", e.headers, e.code
            except (urllib.error.URLError, TimeoutError) as e:
                last_error = f"network error: {e}"
                time.sleep(5)
                continue
            remaining = float(headers.get("x-ratelimit-remaining") or 1)
            reset = float(headers.get("x-ratelimit-reset") or 0)
            if status == 429 or remaining < 1:
                with open(_state_path(), "w") as f:
                    f.write(str(time.time() + max(reset, 5) + 1))
            if status == 200:
                if not _is_feed(body):
                    sys.exit(f"reddit: response was not a feed (bot check or error page?): {url}")
                tmp = f"{path}.{os.getpid()}.tmp"
                with open(tmp, "wb") as f:
                    f.write(body)
                os.replace(tmp, path)  # atomic, so a concurrent reader never sees a partial file
                return body
            if status != 429:
                sys.exit(f"reddit: HTTP {status} for {url}")
            last_error = "rate limited (429)"
        sys.exit(f"reddit: gave up after {MAX_TRIES} tries ({last_error}): {url}")


def _text(content, max_chars):
    text = html.unescape(re.sub(r"<[^>]+>", " ", content or ""))
    text = re.sub(r"\s*submitted by\s+/u/\S+\s*\[link\]\s*\[comments\]\s*$", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text if len(text) <= max_chars else text[:max_chars] + " [...]"


def entries(xml_bytes, max_chars):
    out = []
    for e in ET.fromstring(xml_bytes).findall("a:entry", ATOM):
        link = e.find("a:link", ATOM)
        author = e.find("a:author/a:name", ATOM)
        content = e.findtext("a:content", "", ATOM)
        target = re.search(r'<a href="([^"]+)">\[link\]</a>', html.unescape(content or ""))
        item = {
            "id": (e.findtext("a:id", "", ATOM) or "").split("_")[-1],
            "title": e.findtext("a:title", "", ATOM),
            "author": author.text.removeprefix("/u/") if author is not None and author.text else None,
            "published": e.findtext("a:published", None, ATOM) or e.findtext("a:updated", None, ATOM),
            "url": link.get("href") if link is not None else None,
            "body": _text(content, max_chars),
        }
        # image and link posts: where the post points, when that isn't the thread itself
        if target and target.group(1) != item["url"]:
            item["link"] = target.group(1)
        out.append(item)
    return out


def thread_url(ref):
    if ref.startswith("http"):
        parts = urllib.parse.urlsplit(ref)
        return f"{BASE}{parts.path.rstrip('/')}/.rss"
    return f"{BASE}/comments/{ref.removeprefix('t3_')}/.rss"


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("feed")
    f.add_argument("sub")
    f.add_argument("--sort", default="hot", choices=["hot", "new", "top", "rising"])
    s = sub.add_parser("search")
    s.add_argument("sub")
    s.add_argument("query")
    s.add_argument("--sort", default="relevance", choices=["relevance", "top", "new", "comments"])
    for sp in (f, s):
        sp.add_argument("--t", default="week", choices=["hour", "day", "week", "month", "year", "all"])
    t = sub.add_parser("thread")
    t.add_argument("ref", help="thread URL or post id")
    t.add_argument("--sort", default="confidence", choices=["confidence", "new", "top", "old", "controversial"],
                   help="comment order; confidence is Reddit's default 'best', replies flattened after their parent")
    for sp in (f, s, t):
        sp.add_argument("--limit", type=int, default=25)
        sp.add_argument("--max-chars", type=int, default=1500, help="trim each body to this length")
    a = p.parse_args()

    limit = max(1, min(a.limit, 100))
    if a.cmd == "feed":
        q = {"limit": limit}
        if a.sort == "top":
            q["t"] = a.t
        url = f"{BASE}/r/{a.sub}/{a.sort}/.rss?{urllib.parse.urlencode(q)}"
        result = entries(fetch(url), a.max_chars)
    elif a.cmd == "search":
        q = {"q": a.query, "restrict_sr": "on", "sort": a.sort, "t": a.t, "limit": limit}
        url = f"{BASE}/r/{a.sub}/search.rss?{urllib.parse.urlencode(q)}"
        result = entries(fetch(url), a.max_chars)
    else:
        url = thread_url(a.ref) + "?" + urllib.parse.urlencode({"limit": limit, "sort": a.sort})
        items = entries(fetch(url), a.max_chars)
        result = {"post": items[0] if items else None, "comments": items[1:]}
    json.dump(result, sys.stdout, ensure_ascii=False, indent=1)
    print()


if __name__ == "__main__":
    main()
