# Owner review — release fields and disclosures

None of these unchecked items has been answered or submitted on the owner's
behalf. A historical decision to ship does not supply missing provenance,
permission documents or platform approval.

## Asset records needing resolution

- [ ] Commander barks: `assets/vo/cmd/` contains 41 files. Commit
  `becbc9e4d09e277b2bffe8927c268e9bb22131f8` records voice cloning through fleet
  VoiceStudio. Collect the relevant source, model, license and permission records
  and obtain the appropriate review before making Steam's rights declarations.
- [ ] Intro narration: `assets/vo/intro_crawl.mp3` is attributed to the same
  character by commit `024ea55`; that commit does not name its generation service.
  Confirm its actual pipeline and applicable permissions. Do not label it verified
  ElevenLabs stock-voice output.
- [ ] Radio VO: 14 `vo_*.mp3` files. ElevenLabs is inferred from recorded voice
  names/format, not a logged generation request. Verify account/service records.
  The folder README also notes a voice-role versus caption discrepancy to review.
- [ ] Enemy audio: 27 death recordings and 61 spawn recordings in the current
  tree. Review actual audio, language meaning and captions, including political
  and religious shouts; confirm the inferred service and applicable terms.
- [ ] Thirty audition recordings under `assets/audio/ya_chants/` are marked
  development-only. Confirm they are absent from the actual uploaded build.
- [ ] Title logo, six vehicle/boss images and two intro images have incomplete
  generation records in `ASSETS.md`. Complete those records or replace the
  affected assets with a documented production process.
- [ ] Verify terms and reference inputs for the recorded AI troop, projectile,
  desert and promotional-art pipelines; retain the CC0 notices.
- [ ] Review recognizable likenesses, title/branding and all asset rights with
  qualified support. This checklist does not decide legal clearance.
- [ ] Review the actual build's entire mature-content inventory and AI use,
  including inaccessible packaged files. Approve the supplied disclosure drafts
  only after they match that build.
- [ ] Confirm AI assistance in player-consumed narrative, captions, localization
  and other text, and expand the disclosure accordingly; those pipelines have
  not received the same per-file provenance audit as the image/audio groups.

## Store/account fields still needed

- [ ] Intended Steam AppID and authorized publisher account.
- [ ] Confirm developer/publisher display names and legal entity. Project metadata
  says Big IT Game Studios, a ShoeMoney company; it is not account verification.
- [ ] Approved support contact, privacy/support URLs and website. No inferred
  personal email address or invented URL has been inserted into the copy.
- [ ] Price, currencies, release date and launch discount decision.
- [ ] Supported OS versions and measured minimum/recommended hardware.
- [ ] Supported language matrix: interface, subtitles and full audio separately.
- [ ] Steam feature checkboxes only after intended-app integration testing.
- [ ] Gameplay screenshot selection, trailer, localized art/text and storefront
  preview on desktop/narrow layouts.
- [ ] Production builds, signing/notarization as applicable, depot configuration,
  install/update/launch/uninstall checks and Steam review results.
- [ ] Newcomer/co-op observations and whole-campaign audio/visual acceptance.

## Suggested discovery labels for owner selection

Action, Indie, Top-Down Shooter, Twin Stick Shooter, Shoot 'Em Up, Local Co-Op,
Singleplayer, Arcade, 2D, Satire. These describe the implemented game, not a
prediction of store placement. Confirm available labels in the account editor;
no audience, commercial-performance or political endorsement claim is implied.

Do not advertise global synchronization for Daily Run: it uses the device's
local calendar. Do not advertise online co-op or Steam Deck verification.
