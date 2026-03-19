from __future__ import annotations

import hashlib
import math
import re
from pathlib import PurePosixPath
from typing import Any

import yaml

from app.models import VaultNoteInput

WIKILINK_PATTERN = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]")
TAG_PATTERN = re.compile(r"(?<!\w)#([A-Za-z0-9_\-/]+)")
FRONTMATTER_PATTERN = re.compile(r"^---\n(.*?)\n---\n?", re.DOTALL)


class ObsidianParser:
    def parse_notes(self, notes: list[VaultNoteInput]) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, Any]]]:
        parsed_notes: list[dict[str, Any]] = []
        pending_links: list[dict[str, Any]] = []
        pending_chunks: list[dict[str, Any]] = []

        for note in notes:
            parsed = self._parse_single(note)
            parsed_notes.append(parsed["note"])
            pending_links.extend(parsed["links"])
            pending_chunks.extend(parsed["chunks"])

        return parsed_notes, pending_links, pending_chunks

    def _parse_single(self, note: VaultNoteInput) -> dict[str, Any]:
        raw_markdown = note.content_markdown or ""
        frontmatter, markdown = self._extract_frontmatter(raw_markdown)
        merged_frontmatter = {**frontmatter, **note.frontmatter}
        path = self._normalize_path(note.path)
        title = note.title or merged_frontmatter.get("title") or self._title_from_path(path)
        tags = self._merge_tags(note.tags, merged_frontmatter, markdown)
        links = self._extract_links(path, markdown)
        chunks = self._chunk_markdown(markdown)
        word_count = len([word for word in markdown.split() if word])
        token_estimate = max(1, math.ceil(word_count * 1.33)) if word_count else 0

        note_row = {
            "path": path,
            "slug": self._slugify(path),
            "title": title,
            "folder_path": str(PurePosixPath(path).parent) if "/" in path else None,
            "note_type": note.note_type,
            "tags": tags,
            "frontmatter": merged_frontmatter,
            "outbound_link_paths": [link["target_path"] for link in links],
            "content_markdown": markdown,
            "source_hash": hashlib.sha256(raw_markdown.encode("utf-8")).hexdigest(),
            "word_count": word_count,
            "token_estimate": token_estimate,
        }

        chunk_rows = []
        for index, chunk_text in enumerate(chunks):
            chunk_rows.append(
                {
                    "path": path,
                    "chunk_index": index,
                    "content": chunk_text,
                    "token_estimate": max(1, math.ceil(len(chunk_text.split()) * 1.33)) if chunk_text.strip() else 0,
                    "metadata": {"path": path, "title": title, "tags": tags},
                }
            )

        return {"note": note_row, "links": links, "chunks": chunk_rows}

    def _extract_frontmatter(self, markdown: str) -> tuple[dict[str, Any], str]:
        match = FRONTMATTER_PATTERN.match(markdown)
        if not match:
            return {}, markdown
        block = match.group(1)
        try:
            data = yaml.safe_load(block) or {}
        except yaml.YAMLError:
            data = {}
        if not isinstance(data, dict):
            data = {}
        stripped = markdown[match.end():]
        return data, stripped

    def _merge_tags(self, explicit_tags: list[str], frontmatter: dict[str, Any], markdown: str) -> list[str]:
        tags = set(tag.strip() for tag in explicit_tags if tag.strip())
        fm_tags = frontmatter.get("tags")
        if isinstance(fm_tags, str):
            tags.add(fm_tags.strip())
        elif isinstance(fm_tags, list):
            for tag in fm_tags:
                if isinstance(tag, str) and tag.strip():
                    tags.add(tag.strip())

        for match in TAG_PATTERN.findall(markdown):
            normalized = match.strip()
            if normalized:
                tags.add(normalized)

        return sorted(tags)

    def _extract_links(self, source_path: str, markdown: str) -> list[dict[str, Any]]:
        links: list[dict[str, Any]] = []
        for target, alias in WIKILINK_PATTERN.findall(markdown):
            cleaned_target = self._normalize_path(target)
            links.append(
                {
                    "source_path": source_path,
                    "target_path": cleaned_target,
                    "link_text": alias or self._title_from_path(cleaned_target),
                }
            )
        return links

    def _chunk_markdown(self, markdown: str, chunk_size: int = 1200, overlap: int = 150) -> list[str]:
        text = markdown.strip()
        if not text:
            return []
        if len(text) <= chunk_size:
            return [text]

        chunks: list[str] = []
        start = 0
        while start < len(text):
            end = min(len(text), start + chunk_size)
            chunks.append(text[start:end].strip())
            if end >= len(text):
                break
            start = max(end - overlap, start + 1)
        return [chunk for chunk in chunks if chunk]

    def _normalize_path(self, value: str) -> str:
        path = value.strip().replace("\\", "/")
        path = path.lstrip("./")
        if not path.endswith(".md"):
            path = f"{path}.md"
        return path

    def _title_from_path(self, path: str) -> str:
        return PurePosixPath(path).stem.replace("-", " ").replace("_", " ").strip() or "Untitled"

    def _slugify(self, path: str) -> str:
        return PurePosixPath(path).stem.lower().replace(" ", "-").replace("_", "-")
