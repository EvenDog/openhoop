#!/usr/bin/env python3
"""Adds a release to OpenHoop's update feed, website/appcast.xml, which the app's updater (Sparkle) reads.

Run it after making the release's DMG and before publishing the website:

    python3 scripts/add-to-appcast.py dist/OpenHoop-0.7.0.dmg release-notes.md

It reads the version from dist/OpenHoop.app, signs the DMG with the update key kept in your login keychain (made once
with Sparkle's generate_keys, under the account "openhoop"), turns the release notes (the same Markdown as the GitHub
release) into a little HTML for the update window, and puts the new entry first in the feed. The DMG must be the one
uploaded to the GitHub release: the feed links to it there.
"""
import html
import plistlib
import re
import subprocess
import sys
from email.utils import formatdate
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEED = ROOT / "website" / "appcast.xml"
SIGN_UPDATE = ROOT / ".build/artifacts/sparkle/Sparkle/bin/sign_update"   # comes with the Sparkle package
EMPTY_FEED = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>OpenHoop</title>
        <link>https://openhoop.app</link>
        <description>New versions of OpenHoop.</description>
        <language>en</language>
    </channel>
</rss>
"""


def inline(text):
    """Escapes a line of Markdown for HTML, keeping **bold** and `code`."""
    text = html.escape(text, quote=False)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    return re.sub(r"`(.+?)`", r"<code>\1</code>", text)


def notes_html(markdown):
    """The release notes as simple HTML: headings, bullet lists and paragraphs (all the notes use). The Install part
    is left out, since the updater installs the new version itself."""
    out, in_list, skipping = [], False, False
    for line in markdown.splitlines():
        heading = re.match(r"(#+)\s+(.*)", line)
        if heading:
            skipping = heading.group(2).strip().lower() == "install"
        if skipping:
            continue
        bullet = re.match(r"\s*[-*]\s+(.*)", line)
        if bullet and not in_list:
            out.append("<ul>"); in_list = True
        if not bullet and in_list:
            out.append("</ul>"); in_list = False
        if heading:
            level = min(len(heading.group(1)) + 1, 4)   # ## becomes h3: the update window's own title is bigger
            out.append(f"<h{level}>{inline(heading.group(2))}</h{level}>")
        elif bullet:
            out.append(f"<li>{inline(bullet.group(1))}</li>")
        elif line.strip() and not line.startswith("SHA-256"):
            out.append(f"<p>{inline(line.strip())}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    dmg, notes = Path(sys.argv[1]), Path(sys.argv[2])
    info = plistlib.loads((ROOT / "dist/OpenHoop.app/Contents/Info.plist").read_bytes())
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if dmg.name != f"OpenHoop-{version}.dmg":
        sys.exit(f"{dmg.name} doesn't match the built app's version, {version}.")
    # sign_update prints the enclosure's two attributes: sparkle:edSignature="…" length="…"
    signature = subprocess.run([str(SIGN_UPDATE), "--account", "openhoop", str(dmg)], check=True, capture_output=True, text=True).stdout.strip()
    if 'sparkle:edSignature="' not in signature:
        sys.exit(f"sign_update didn't sign it: {signature}")
    feed = FEED.read_text() if FEED.exists() else EMPTY_FEED
    if f"<sparkle:version>{build}</sparkle:version>" in feed:
        sys.exit(f"The feed already has build {build}.")
    item = f"""        <item>
            <title>OpenHoop {version}</title>
            <pubDate>{formatdate(usegmt=True)}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{info["LSMinimumSystemVersion"]}</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>https://github.com/EvenDog/openhoop/releases/tag/v{version}</sparkle:fullReleaseNotesLink>
            <description><![CDATA[
{notes_html(notes.read_text())}
            ]]></description>
            <enclosure url="https://github.com/EvenDog/openhoop/releases/download/v{version}/{dmg.name}" {signature} type="application/octet-stream"/>
        </item>
"""
    # The newest release goes first, right after the channel's own details.
    marker = "        <language>en</language>\n"
    FEED.write_text(feed.replace(marker, marker + item, 1))
    print(f"Added OpenHoop {version} (build {build}) to {FEED.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
