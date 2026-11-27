#!/usr/bin/env python3
"""Render website/legal/*.md into static HTML pages (no JS required at runtime)."""

from __future__ import annotations

import re
from pathlib import Path

import markdown
from markdown.extensions.tables import TableExtension

ROOT = Path(__file__).resolve().parents[1]
LEGAL = ROOT / "legal"
DOMAIN = "flofilecaptions.com"
DATE = "November 26, 2026"

# Numbers that already make sense — strip brackets only.
NUMBER_PLACEHOLDERS = {
    "[30]": "30",
    "[90]": "90",
    "[7]": "7",
    "[2]": "2",
}

PAGE_META = {
    "terms": {
        "title": "Terms of Service — FloFile Captions",
        "description": "Terms of Service for FloFile Captions, including subscriptions, licences, and use of the Service.",
        "nav_label": "Terms of Service",
        "canonical": f"https://{DOMAIN}/terms",
        "md": "terms.md",
        "out": "terms.html",
    },
    "refunds": {
        "title": "Refund Policy — FloFile Captions",
        "description": "Refund Policy for FloFile Captions. Full refund within 14 days of any purchase, for any reason.",
        "nav_label": "Refund Policy",
        "canonical": f"https://{DOMAIN}/refunds",
        "md": "refunds.md",
        "out": "refunds.html",
    },
    "privacy": {
        "title": "Privacy Notice — FloFile Captions",
        "description": "Privacy Notice for FloFile Captions: what personal information we collect, why, and how to contact us.",
        "nav_label": "Privacy Notice",
        "canonical": f"https://{DOMAIN}/privacy",
        "md": "privacy.md",
        "out": "privacy.html",
    },
}


def fill_placeholders(text: str) -> str:
    text = text.replace("[domain]", DOMAIN)
    text = text.replace("[date]", DATE)
    for bracketed, plain in NUMBER_PLACEHOLDERS.items():
        text = text.replace(bracketed, plain)
    return text


def enhance_links(html: str) -> str:
    """Add target/rel to external http(s) links; leave relative/mailto alone."""

    def repl(match: re.Match[str]) -> str:
        tag = match.group(0)
        href = match.group(1)
        if href.startswith(("http://", "https://")) and DOMAIN not in href:
            if "target=" not in tag:
                tag = tag[:-1] + ' target="_blank" rel="noopener noreferrer">'
            elif "rel=" not in tag:
                tag = tag[:-1] + ' rel="noopener noreferrer">'
        return tag

    return re.sub(r'<a\s+[^>]*href="([^"]+)"[^>]*>', repl, html)


def page_shell(meta: dict, body_html: str) -> str:
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{meta["title"]}</title>
  <meta name="description" content="{meta["description"]}">
  <meta name="theme-color" content="#10141B">
  <link rel="canonical" href="{meta["canonical"]}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="FloFile Captions">
  <meta property="og:title" content="{meta["title"]}">
  <meta property="og:description" content="{meta["description"]}">
  <meta property="og:url" content="{meta["canonical"]}">
  <meta property="og:image" content="https://{DOMAIN}/images/og-default.svg">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{meta["title"]}">
  <meta name="twitter:description" content="{meta["description"]}">
  <meta name="twitter:image" content="https://{DOMAIN}/images/og-default.svg">
  <link rel="icon" href="/favicon.svg" type="image/svg+xml">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/css/styles.css?v=paddle-legal">
</head>
<body>
  <a class="skip-link" href="#main">Skip to content</a>
  <div class="page-bg">
    <header class="site-header">
      <div class="wrap header-inner">
        <a class="brand" href="/">
          <span class="brand-mark" aria-hidden="true"></span>
          FloFile Captions
        </a>
        <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-nav">Menu</button>
        <nav id="site-nav" class="nav" aria-label="Primary">
          <a href="/#features">Features</a>
          <a href="/pricing">Pricing</a>
          <a href="/about.html">About</a>
          <a href="/download.html">Download</a>
          <a href="/contact.html">Contact</a>
          <a class="nav-cta-outline" href="/admin/">Sign in</a>
          <a class="nav-cta" href="/download.html">Get the app</a>
        </nav>
      </div>
    </header>

    <main id="main" class="section">
      <article class="wrap prose legal-prose">
{body_html.rstrip()}
      </article>
    </main>

    <footer class="site-footer">
      <div class="wrap footer-stack">
        <div class="footer-inner">
          <div class="footer-brand">
            FloFile Captions
            <span>IPTC captioning for professional sports photographers.</span>
          </div>
          <nav class="footer-nav" aria-label="Footer">
            <a href="/pricing">Pricing</a>
            <a href="/terms">Terms of Service</a>
            <a href="/refunds">Refund Policy</a>
            <a href="/privacy">Privacy Notice</a>
            <a href="/contact.html">Contact</a>
          </nav>
        </div>
        <p class="footer-support">Support: [support email] · [support phone]</p>
        <p class="footer-legal">© <span class="footer-year">2026</span> 1001746423 Ontario Inc., operating as FloFile</p>
      </div>
    </footer>
  </div>
  <script src="/js/main.js"></script>
</body>
</html>
"""


def render_one(key: str) -> None:
    meta = PAGE_META[key]
    raw = (LEGAL / meta["md"]).read_text(encoding="utf-8")
    filled = fill_placeholders(raw)
    body = markdown.markdown(
        filled,
        extensions=["extra", TableExtension()],
        output_format="html5",
    )
    body = enhance_links(body)
    # Wrap tables for horizontal scroll on narrow screens.
    body = body.replace("<table>", '<div class="table-scroll"><table>').replace(
        "</table>", "</table></div>"
    )
    # Indent body for readability inside the article.
    indented = "\n".join(("        " + line if line else "") for line in body.splitlines())
    html = page_shell(meta, indented)
    (ROOT / meta["out"]).write_text(html, encoding="utf-8")
    print(f"Wrote {meta['out']}")


def main() -> None:
    for key in PAGE_META:
        render_one(key)


if __name__ == "__main__":
    main()
