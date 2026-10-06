#!/usr/bin/env python3
"""Build docs/manifest.json by scanning all markdown files in docs/.

Extracts frontmatter metadata and auto-generates keywords from content.
No external dependencies — uses only Python stdlib.

Usage:
    python3 scripts/build-manifest.py
    python3 scripts/build-manifest.py --docs-dir /path/to/docs
"""

import json
import re
import sys
from collections import Counter
from pathlib import Path

# Words to exclude from keyword extraction
STOP_WORDS = frozenset({
    "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "is", "it", "as", "be", "was", "are",
    "been", "being", "have", "has", "had", "do", "does", "did", "will",
    "would", "could", "should", "may", "might", "shall", "can", "this",
    "that", "these", "those", "not", "no", "if", "then", "else", "when",
    "where", "how", "what", "which", "who", "whom", "why", "all", "each",
    "every", "both", "few", "more", "most", "other", "some", "such", "only",
    "own", "same", "so", "than", "too", "very", "just", "also", "into",
    "over", "after", "before", "between", "under", "about", "up", "out",
    "off", "down", "through", "during", "until", "while", "above", "below",
    "any", "its", "our", "their", "your", "my", "his", "her", "we", "they",
    "you", "he", "she", "me", "us", "them", "i", "yet", "still", "here",
    "there", "new", "one", "two", "use", "using", "used", "make", "see",
    "get", "set", "run", "per", "via", "etc", "e.g", "i.e",
})

# Minimum word length for keywords
MIN_WORD_LEN = 3
# Number of keywords to extract per doc
MAX_KEYWORDS = 15
# Minimum occurrences for a word to be a keyword
MIN_OCCURRENCES = 2


def parse_frontmatter(text: str) -> dict:
    """Parse YAML frontmatter from markdown text. Handles simple key: value pairs."""
    match = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
    if not match:
        return {}

    fm = {}
    for line in match.group(1).strip().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        colon_idx = line.find(":")
        if colon_idx == -1:
            continue
        key = line[:colon_idx].strip()
        value = line[colon_idx + 1 :].strip()
        # Strip quotes
        if (value.startswith('"') and value.endswith('"')) or (
            value.startswith("'") and value.endswith("'")
        ):
            value = value[1:-1]
        # Parse simple lists like [a, b, c]
        if value.startswith("[") and value.endswith("]"):
            value = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        fm[key] = value
    return fm


def extract_headings(text: str) -> list[str]:
    """Extract H1 and H2 headings from markdown."""
    headings = []
    for match in re.finditer(r"^#{1,2}\s+(.+)$", text, re.MULTILINE):
        heading = match.group(1).strip()
        # Remove markdown formatting
        heading = re.sub(r"[*_`\[\]()]", "", heading)
        if heading:
            headings.append(heading)
    return headings


def extract_keywords(text: str, headings: list[str]) -> list[str]:
    """Auto-extract keywords from document content and headings."""
    # Combine headings (weighted 3x) with body text
    headings_text = " ".join(headings)
    weighted_text = ((headings_text + " ") * 3) + text

    # Extract words: alphanumeric + hyphens, lowercased
    words = re.findall(r"[a-zA-Z][a-zA-Z0-9-]{2,}", weighted_text.lower())

    # Filter stop words and short words
    filtered = [w for w in words if w not in STOP_WORDS and len(w) >= MIN_WORD_LEN]

    # Count and rank
    counts = Counter(filtered)

    # Filter by minimum occurrences
    keywords = [
        word
        for word, count in counts.most_common(MAX_KEYWORDS * 2)
        if count >= MIN_OCCURRENCES
    ]

    return keywords[:MAX_KEYWORDS]


def get_title(text: str) -> str:
    """Extract the first H1 heading as the document title."""
    match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if match:
        title = match.group(1).strip()
        return re.sub(r"[*_`]", "", title)
    return ""


def scan_doc(filepath: Path, docs_root: Path) -> dict | None:
    """Scan a single markdown file and return its manifest entry."""
    try:
        text = filepath.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None

    fm = parse_frontmatter(text)
    headings = extract_headings(text)
    title = get_title(text)
    keywords = extract_keywords(text, headings)
    rel_path = str(filepath.relative_to(docs_root))

    # Derive domain from path (first directory under docs/)
    parts = Path(rel_path).parts
    domain = parts[0] if len(parts) > 1 else "root"

    return {
        "path": rel_path,
        "title": title,
        "type": fm.get("type", ""),
        "topic": fm.get("topic", ""),
        "date": fm.get("date", ""),
        "domain": domain,
        "headings": headings[:10],
        "keywords": keywords,
    }


def build_manifest(docs_dir: Path) -> dict:
    """Scan all docs and build the manifest."""
    entries = []
    errors = []

    for filepath in sorted(docs_dir.rglob("*.md")):
        # Skip INDEX.md itself and manifest
        if filepath.name in ("INDEX.md", "manifest.json"):
            continue

        entry = scan_doc(filepath, docs_dir)
        if entry:
            entries.append(entry)
        else:
            errors.append(str(filepath.relative_to(docs_dir)))

    manifest = {
        "version": 1,
        "doc_count": len(entries),
        "domains": sorted(set(e["domain"] for e in entries)),
        "types": sorted(set(e["type"] for e in entries if e["type"])),
        "entries": entries,
    }

    if errors:
        manifest["scan_errors"] = errors

    return manifest


def main():
    docs_dir = Path(__file__).resolve().parent.parent / "docs"

    # Allow override via CLI arg
    if len(sys.argv) > 2 and sys.argv[1] == "--docs-dir":
        docs_dir = Path(sys.argv[2])

    if not docs_dir.is_dir():
        print(f"Error: docs directory not found: {docs_dir}", file=sys.stderr)
        sys.exit(1)

    manifest = build_manifest(docs_dir)

    output_path = docs_dir / "manifest.json"
    output_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    print(f"Manifest built: {manifest['doc_count']} docs across {len(manifest['domains'])} domains")
    print(f"Types: {', '.join(manifest['types'])}")
    print(f"Written to: {output_path}")


if __name__ == "__main__":
    main()
