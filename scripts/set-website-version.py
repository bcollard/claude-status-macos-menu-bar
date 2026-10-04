#!/usr/bin/env python3
"""Set the release shown next to the GitHub link in the website's top bar.

    /usr/bin/python3 scripts/set-website-version.py            # version from Bundler.toml
    /usr/bin/python3 scripts/set-website-version.py v0.2.4

Static on purpose (same as marina-website): no GitHub API call from
visitors' browsers (rate limits, a third-party request on every page view,
and a blank badge when it fails). Idempotent.
"""
import glob
import os
import re
import sys

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

if len(sys.argv) == 2:
    version = sys.argv[1]
elif len(sys.argv) == 1:
    toml = open(os.path.join(root, "Bundler.toml"), encoding="utf-8").read()
    version = "v" + re.search(r'^version = "([^"]+)"', toml, re.M).group(1)
else:
    sys.exit("usage: set-website-version.py [vX.Y.Z]")
if not re.fullmatch(r"v\d+\.\d+\.\d+", version):
    sys.exit(f"not a vX.Y.Z version: {version}")

repo = "https://github.com/bcollard/claude-status-macos-menu-bar"
badge = (f'<a href="{repo}/releases/tag/{version}" class="nav-version" '
         f'target="_blank" rel="noopener" title="Latest release">{version}</a>')

github = re.compile(r'(<a href="' + re.escape(repo) + r'" class="nav-github"[^>]*>.*?</a>)'
                    r'(\s*<a [^>]*class="nav-version"[^>]*>[^<]*</a>)?', re.S)
# Stamp the stylesheet with the release too: HTML and CSS are served with a
# 10-minute cache, so a deploy that changes both can otherwise pair new markup
# with the old stylesheet for a while.
css = re.compile(r'href="/styles\.css(\?v=[^"]*)?"')

changed = 0
for path in sorted(glob.glob(os.path.join(root, "website", "*.html"))):
    src = open(path, encoding="utf-8").read()
    out, _ = github.subn(lambda m: m.group(1) + "\n    " + badge, src, count=1)
    out = css.sub(f'href="/styles.css?v={version}"', out)
    if out != src:
        open(path, "w", encoding="utf-8").write(out)
        changed += 1
print(f"{version}: updated {changed} page(s)")
