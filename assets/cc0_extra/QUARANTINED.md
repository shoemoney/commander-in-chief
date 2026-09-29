# QUARANTINED — assets that must never be imported

`tools/fetch_cc0.py` refuses to extract anything it cannot prove is CC0 from a
licence file **inside the artefact itself**. Two archives in the shared library
(`/Users/shoemoney/gameassets/source/downloads/`) fail that test and are listed
here permanently, with the evidence, so a later reader cannot "helpfully"
re-add them. `fetch_cc0.py --check` re-asserts that no claimed file's name
matches either archive.

This is a licence-failure record, not a quality judgement. Either archive could
become importable if a licence were obtained and written into it, and then this
file should be deleted rather than edited around.

---

## 1. `oga_16-toon-muzzle-flash.zip`

| | |
|---|---|
| Path | `source/downloads/oga_16-toon-muzzle-flash.zip` |
| Size | 1,128,801 bytes |
| Contents | 16 PNGs (`muzzle_flashs/m_1.png` … `m_16.png`) + the directory entry |
| Verdict | **NO LICENCE — never import** |

**Evidence.**

```
$ unzip -l oga_16-toon-muzzle-flash.zip
        64349  08-05-2017 14:00   muzzle_flashs/m_1.png
        ... (m_2 … m_16)
---------                     -------
      1128801                     17 files
```

The central directory holds exactly 17 entries: 16 PNGs and one directory
record. Searching every entry name for
`licen|readme|\.txt|\.md|\.pdf|credit` returns **zero** matches. There is no
licence text anywhere in the artefact, so the submitting page's licence cannot
be verified from the artefact and a downstream redistributor has nothing to
rely on.

## 2. `oga_stone-tower-game-assets.zip`

| | |
|---|---|
| Path | `source/downloads/oga_stone-tower-game-assets.zip` |
| Size | 2,858,799 bytes |
| Contents | 4 Flash `.fla` sources, 63 PNGs, and one 52-byte text file |
| Verdict | **TEXT FILE IS NOT A LICENCE — never import** |

**Evidence.** The archive's only non-artwork file is `TXT/readme.txt`, 52
bytes. Its complete content is:

```
$ unzip -p oga_stone-tower-game-assets.zip TXT/readme.txt | od -c
0000000    C   h   i   s   e   l       M   a   r   k  \r  \n   h   t   t
0000020    p   s   :   /   /   w   w   w   .   d   a   f   o   n   t   .
0000040    c   o   m   /   c   h   i   s   e   l   -   m   a   r   k   -
0000060    f   o   n   t
0000064
```

That is `Chisel Mark` + a `dafont.com` URL — attribution for the font the
author used in Flash Animate. It grants nothing. There is no CC0, CC-BY, or any
other licence statement in the artefact.

---

## Not quarantine, but also never import: the CraftPix library

`/Users/shoemoney/gameassets/source/downloads/craftpix-10-year-anniversary/`
(775 packs, ~38 GB) is **unusable in this repository under any circumstance**,
and is not a licence question that a later audit should re-open:

- **§1.1.3** — "Distribution of source files is NOT permitted." This repository
  is public and MIT, so no CraftPix source file may be copied into it.
- **§1.1.4** — "You can sell and distribute games with our assets." A finished
  *build* is fine; the **sources** are not, and a public repo ships sources.
- **§3.1** — assets may not be used "for the purposes of training, fine-tuning,
  developing, testing, validating, or improving any AI… system." So no CraftPix
  image may be fed to an image model for any reason, including "just to
  prototype a look".

Terms: <https://craftpix.net/file-licenses/>

The three OpenGameArt/CraftPix-adjacent libraries in the same tree
(`AntVo-Phaser-Tower-Defense`, `source/itch/`, `source/originals/`) were not
evaluated for this harvest and are **not** cleared by anything in this file.
