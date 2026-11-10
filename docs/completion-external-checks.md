# Launch evidence still requiring accounts, hardware or observers

Run these checks against the frozen candidate identified in the completion handoff. Record the artifact hash, platform, input device, settings, observed result and retained evidence. An unchecked item remains open.

## Steam account and intended app

- [ ] Confirm the AppID, publisher authority, depot and build branch.
- [ ] Install the exact candidate through Steam; test update, launch and uninstall.
- [ ] Exercise achievements, leaderboard submissions, rich presence and Steam Input against that AppID.
- [ ] Exercise user-specific Cloud saves, conflicts and account switching using the documented save boundaries.
- [ ] Complete build and store review, disclosure fields and narrow/desktop page previews.

See [owner-review.md](steam-store/owner-review.md) for the unanswered support, price/date, language, system-requirement and rights fields. The local mock facade and binding reflection do not establish these results.

## Platform and device matrix

- [ ] Windows 10 and 11 on NVIDIA, AMD and Intel graphics.
- [ ] macOS arm64 and Intel, including distribution launch and signing/notarization where applicable.
- [ ] Linux native and Proton.
- [ ] Steam Deck LCD and OLED: controls, frame budget, suspend/resume and a long session.
- [ ] Xbox, DualSense, DS4, Switch Pro and 8BitDo: connect, disconnect, reconnect, rebind, seat stability and local co-op.
- [ ] Minimum display: a physical 1280×720 viewport. When the usable desktop cannot fit a readable window and its chrome, verify the automatic fullscreen fallback and restoration of the saved window preference on a larger display.

Source execution on a hosted runner proves only the tested runner configuration. Universal binary slices and cross-exports do not establish hardware execution.

## Player and content acceptance

- [ ] Complete the ten unfamiliar-player sessions and paired co-op observations in [ten-item-acceptance.md](ten-item-acceptance.md).
- [ ] Record controller-in-hand feel review, death comprehension, shared-spend arguments and the production plan's external wishlist criterion.
- [ ] Complete whole-campaign visual/audio review, including captions, speaker roles and enemy shout meanings.
- [ ] Complete localization review for the approved interface/subtitle/audio language matrix. Three synchronized translation files do not prove twelve reviewed languages.
- [ ] Record real Playtest session and crash evidence for the alpha/beta exit criteria.
- [ ] Resolve generation, source, service-license and permission records before making rights declarations.

## Service and release operations

- [ ] Reconcile the server-side replay validation and authenticated submission requirement. Local deterministic score verification does not authenticate a submitting player or provide a live validation service.
- [ ] Confirm demo content and branch, day-one patch candidate and the support/review response owner.
- [ ] Confirm the planned market and release conditions, Deck review submission and platform acceptance.

The owner-managed IP, legal, pricing, marketing, funding and awards decisions stay with the owner. No participant result, permission record, account state or platform approval is inferred from an automated test.

Observation record:

```csv
candidate_sha256,revision,platform,device,settings,check,result,evidence,observer,notes
```
