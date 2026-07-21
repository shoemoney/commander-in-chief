class_name GameMenu
extends Control
## Title + pause overlay (Modern Menus sprites). Lives on the HUD CanvasLayer;
## while visible, main.gd simply doesn't step the sim — the deterministic core
## knows nothing about menus. Keyboard (W/S + Enter, Esc) and pad
## (dpad + A, Start) navigation.

enum Mode { HIDDEN, TITLE, PAUSE, HALL, HOWTO, OPTS, SETUP, INFO, REBIND, DISP }

# 222 = 30px icon gutter + the widest pause label ("ASSIST (2-HIT): OFF") at
# 11px pixel-font + padding — 190 ellipsized toggle VALUES once the gutter landed.
# c4-04: THE unified button-plate size (222x36). Every column plate rect, hit-test, arrow box and
# row-pitch ceiling (GAP_CEIL below) derives x/width/height from BTN — one edit resizes every menu
# button and the rhythm that hangs off it, no per-screen 222/36 literals.
# c4-04 AUDIT (menu.gd + hud.gd): the layout magic numbers this item targeted are now single-sourced —
#   222/36 -> BTN ; the 156/118/120 first-row tops -> ONE formula, first_row_top(mode) (header
#     baseline + a compact-or-roomy clearance); the old TOP_PAUSE/TOP_OPTS/TOP_SUBHUB constants are gone ;
#   TITLE record plate HEIGHTS -> drawn font size + one shared TITLE_PLATE_PAD_V ; each plate TOP ->
#     the previous plate's bottom (the whole stack chains from TITLE_WORDMARK_TOP) ; the record text
#     baselines -> title_baseline() reading the live font descent (no TITLE_DESC_GAP_* literals) ;
#   HUD ry += 16 -> ROW_H ; pip +7 -> PIP_ADVANCE (PIP_CHIP_PAD+GAP) ; ICON-3 -> ROW_TEXT_BASELINE ;
#   design width 640 / 632 margin -> GameMenu.CANVAS_WIDTH / DESIGN_WIDTH - HUD_SAFE_MARGIN.
# No bare copies of those numbers remain in either file's draw/hit-test code (grep-verified).
# The unified first-row formula reproduces the old TOP_* values exactly (PAUSE 130 / OPTS 102 /
# SUBHUB 120) so no non-TITLE pixel moved; the TITLE header stack shifts a couple px as its plate
# heights become font-derived, still clearing every >=20px floor test_menu_layout pins.
const BTN := Vector2(222, 36)
# c1-12: ◄/► cycle-arrow layout — shared by _draw and the mouse hit-test via
# toggle_arrow_rects so the glyph and its click target can never drift apart.
const ARROW_SZ := 10.0        # arrow glyph box edge (px)
const ARROW_L_OFF := 23.0     # left arrow's far (outer) edge, left of the plate
const ARROW_R_GAP := 5.0      # right arrow's near edge, right of the plate
# c1-13: HALL rows per page. The board holds far more runs than fit on one screen,
# so _draw_hall pages HALL_PAGE_ROWS at a time and up/down turns the page.
const HALL_PAGE_ROWS := 8
# c1-13: recency messaging sits in a TOP band (under the tab underline @y72, above
# the column headers @y96), giving it a vertical region distinct from the paging
# counter (~y306) and the BACK plate (~y310) at the bottom — the four never overlap.
# y82 @size9 spans box [74,84] (PixelOperator ascent 8 / descent 2, measured): its
# bottom clears the y96 headers' box top (87) by 3px and the y72 underline by 2px, so
# the recency line and the headers never collide at the real font metrics (attempt 3
# put it at y85 — box [77,87] — which OVERLAPPED the old y92 headers' [83,94] by 4px).
const HALL_RECENCY_Y := 82.0
# c1-13: how many runs the board retains — the SINGLE SOURCE for the cap. main.gd's
# _record_run passes THIS const into _hall_capped, and the top status band states it on
# screen, so the retention limit the Hall enforces and the one it advertises can't drift.
# (The just-banked run is pinned even past it, so paging always reaches it.)
const HALL_KEEP := 40
# c2-06: the "1-8 OF N" total-count footer's color — one const so the empty ("0-0 OF 0"),
# single-page, and multi-page counters all read in the SAME warm gold and can't drift apart.
const HALL_COUNT_COL := Color(1.0, 0.85, 0.4)

var mode: int = Mode.TITLE
var sel := 0
var main: Node2D
var _confirm := -1   # index of a destructive item awaiting a 2nd press
var _hall_filter := 0   # Hall of Fame view: 0 = ALL, 1 = CAMPAIGN, 2 = ENDLESS
var _hall_page := 0     # c1-13: which page of HALL_PAGE_ROWS-run pages is shown (up/down pages)
var _hall_seen_hid := -1  # c1-13: hid of the latest run we've already auto-jumped to — once surfaced, reopening HALL keeps the player's chosen filter/page instead of snapping back
var _howto_page := 0    # c3-05/c4-06: which HOW-TO-PLAY tab (0 CONTROLS / 1 WAR CHEST / 2 ENEMIES / 3 ENDLESS); left/right/wheel or tab-click pages it
var _howto_endless_page := 0   # c4-06: sub-page WITHIN the single ENDLESS tab (0-based); the in-page chevrons / left-right step it — one clear roster pager instead of two ENDLESS tabs
var _howto_nav_hover := -1   # c4-06: which ENDLESS chevron the pointer is over (-1 none / 0 PREV / 1 NEXT) — lights its plate
const HOWTO_TABS := ["CONTROLS", "WAR CHEST", "ENEMIES", "ENDLESS"]  # c3-05/c4-06: HOW-TO-PLAY tabs — the old BASIC page crammed the verbs AND the War Chest economy together, so each owns a tab; c4-06 gives the seven ENDLESS threats ONE tab paged by in-page chevrons (was two ENDLESS I/II tabs + chevrons — a redundant, confusing double control) so each roster row still gets a big sprite/pitch
const HOWTO_ENDLESS_TAB := 3   # index of the ENDLESS tab in HOWTO_TABS (the only paged tab)
const REPLAY_PATH := "user://last_run.replay"  # WATCH LAST RUN's recording; existence gates the INFO menu row
# c3-10: the HOW TO PLAY shortcut's DEFAULT keycode — the live value is the "menu_help" menu
# binding (main.menu_bind, remappable via the save overlay); this const is only the fallback for
# the headless capture menu (main == null) and mirrors MENU_BIND_DEFAULTS["menu_help"]. Both the
# _unhandled_input handler and every footer/legend stamp read _help_code()/_help_keycap() off the
# SAME live binding, so re-pointing the shortcut updates the handler and the hints together.
const HELP_KEY := KEY_F1
var _sel_y := -1.0      # glided highlight y — the cursor slides between rows
var _sel_target := -1.0 # where the glide is headed (set by _draw's layout pass)
var _open_t := 0.0      # menu-open settle envelope (backdrop fade + row drop-in)
# Analog-stick nav latches — PER AXIS, so a diagonal push can't wedge the other
# axis, and a stick resting in the 0.45–0.55 deadband can't lock nav forever.
var _stick_x := 0       # -1/1 while pushed past 0.55, re-arms below 0.45
var _stick_y := 0
var _stick_rep := 0.0   # countdown to the next held-stick auto-repeat step
var _nav_frame := -1    # frame stamp: one stick nav per frame (diagonal guard)
var _confirm_t := 0.0   # armed destructive row disarms when this runs out
var _reset_flash := 0.0 # c1-09: "DEFAULTS RESTORED" success banner countdown after RESET DEFAULTS fires
var _seed_flash := 0.0  # c1-14: red-flash the CHALLENGE SEED hint after an empty-clipboard press (deny feedback)
var _seed_preview := -1 # c1-14: parsed seed the FOCUSED CHALLENGE SEED row is previewing (-1 = none valid / row not focused); activation commits THIS, not a re-read
var _seed_clip_raw := "" # c1-14: raw clipboard text the preview was parsed from — re-parse only when it changes, so the poll is refresh-on-change not per-frame
var _seed_armed := false # c1-14: the CHALLENGE SEED row has been pressed once (seed shown for verification) and awaits a confirming 2nd press to load
var _seed_armed_val := -1 # c1-14: the exact seed the arm is holding — a confirm loads THIS; a clipboard change to a different seed re-arms instead of launching blind
var _seed_armed_t := 0.0 # c1-14: arm auto-disarm window (mirrors _confirm_t) — a stale "press again" can't load a run minutes later
var _seed_poll_t := 0.0  # c1-14: throttle countdown — the focused row samples the clipboard ~5x/s, not every frame (activation still forces an immediate read)
var _reset_flash_anim := true   # c1-09: whether that banner fades — captured from the PRE-reset reduce-motion state (reset itself re-enables motion, so reading it live would never snap)
var _opts_parent := Mode.SETUP   # c2-04: which screen OPTIONS was opened from (the SETUP hub or PAUSE) — drives BACK
# c3-18: OPTIONS dirty-state. Every audio/haptics/a11y toggle used to write the settings file
# the instant it flipped, so merely BROWSING options (nudging a volume, peeking a toggle)
# persisted the change. Now those toggles apply LIVE (so the preview still works) but only STAGE
# the write: the first staged change snapshots the on-disk baseline into _opts_snapshot and raises
# _opts_dirty. Leaving via SAVE commits (_save_settings); leaving via BACK/DISCARD/Esc reverts the
# live fields to the snapshot and writes nothing. RESET DEFAULTS stays an explicit immediate commit.
var _opts_dirty := false
var _opts_snapshot: Dictionary = {}
var _rebind_action := ""   # c1-18: REBIND screen is capturing the next key/button for THIS verb ("" = idle, listing binds)
var _rebind_tab := 0       # c1-18: which REBIND category tab is shown (0 MOVE/AIM kb, 1 ACTIONS kb, 2 GAMEPAD, 3 MENUS) — keeps each page <=10 rows so plates stay >=20px
var _rebind_pad_dev := 0   # c1-18: which PLAYER's pad layout the GAMEPAD tab edits (0 = P1, 1 = P2) — the two are independent; ◄/► (or the P1|P2 header sub-tabs) switch it
var _rebind_msg := ""      # c1-18: transient swap/clear/reserved-key notice shown under the header
var _rebind_msg_t := 0.0   # c1-18: countdown that fades _rebind_msg (mirrors the settings-confirm timers)
var _filter_pulse := 0.0   # hall filter tab flash on change
var _rail_pulse := 0.0     # volume row bounced off a rail (0/MUTED or 10) — brief end-segment flash
var _rail_dir := 0         # which rail the bounce hit: -1 = muted floor, +1 = max ceiling
var _rail_row := -1        # sel index that bounced — the flash only lights its own row
var _set_pulse := 0.0      # c1-17: settings-change confirm halo — a real volume step or a toggle flip pulses its row so an APPLIED change reads visually, not just as a chime (players were unsure a toggle/volume step took effect without exiting the menu)
var _set_pulse_row := -1   # c1-17: sel index the confirm pulse lights — pinned to the row that changed, so the halo stays put even if focus moves before it fades
var _key_move := 0      # held up/down key direction (hold-repeat, mirrors stick)
var _key_rep := 0.0     # countdown to the next held-key auto-repeat step
var _key_hmove := 0     # held ◄/► key direction — auto-repeats the volume step (volume rows only)
var _key_hrep := 0.0    # countdown to the next held-◄/► auto-repeat step
var _lockout := 0.0     # post-disconnect confirm lockout (flailing pad guard)
var _has_replay := false   # cache: does user://last_run.replay exist — sampled on INFO open
var _tab_hover := -1    # hall filter tab under the mouse (-1 = none) — hover cue parity with rows
var _page_hover := -1   # hall PREV/NEXT button under the mouse (0 = prev, 1 = next, -1 = none) — pointer-owned
var _page_press := 0.0  # hall page-button press flash (decays in _process) — click feedback beyond dimming
var _page_press_side := -1  # which page button flashed (0 = prev, 1 = next); cleared when the flash fades
var _last_ptr := Vector2(-1.0, -1.0)  # last mouse position seen — lets a page/filter change re-evaluate the hover under a STILL cursor
# c2-09: a visible field changed since the last _draw — set at every mutation site (input handlers
# + the _process animators) and cleared in _draw; the _process gate turns it into the one
# queue_redraw(). Starts true so the first frame paints.
# c3-16: _dirty is a PLAIN redraw flag — a request to repaint, nothing more. It no longer
# side-effects the _menu_items cache: an animation frame that only needs a repaint (a draining
# confirm bar, a decaying flash, a breathing glow) sets _dirty = true WITHOUT throwing away rows that
# never changed. Cache invalidation is now an EXPLICIT call — _mark_dirty() — made only at the sites
# that actually change what the rows SAY (mode/sel, a settings toggle or volume step, the seed
# preview, the replay gate). Decoupling the two means a repaint no longer implies a rebuild: the old
# property setter dropped the memo on EVERY _dirty = true (including the per-frame animator writes),
# forcing a redundant intra-frame rebuild each time. (See _mark_dirty and _menu_items.)
var _dirty := true
# c3-16: once-per-frame memo for _menu_items(). It is read many times per frame — every _draw layout
# pass, the mouse hit-test, nav, and press — and each raw rebuild allocates fresh dicts/arrays; this
# holds one snapshot and reuses it until _mark_dirty() drops it. Engaged ONLY while in the scene tree
# (the live game): the headless layout tests poke mode/sel/main directly WITHOUT the _dirty signal and
# rely on _menu_items() staying a live query, so out of tree it always rebuilds (see _menu_items).
# _items_frame bounds the memo to the CURRENT frame as a belt-and-suspenders: even if some future
# mutation site forgot to _mark_dirty(), a stale snapshot can survive at most one frame (the frame
# stamp mismatches next frame and forces a rebuild) — never a persistent desync. So the cache leans on
# the _mark_dirty() contract for intra-frame freshness and on the frame stamp as the hard staleness ceiling.
var _items_cache: Array[Dictionary] = []
var _items_valid := false
var _items_frame := -1

# Row ids that flip on left/right without a confirm press.
# c1-19: DISPLAY is no longer a single overloaded ladder here — the OPTS "display" row
# OPENS a dedicated DISPLAY sub-screen (like CONTROLS opens REBIND). On that screen
# FULLSCREEN is a plain ON/OFF toggle (in this list) and WINDOW SCALE is a 1x..Nx stepper
# (handled separately, like the volume rows), so the two are never overloaded onto one control.
const _TOGGLES := ["coop", "hard", "sfx", "music", "motion", "colorblind", "rumble", "assist", "fullscreen"]
# c1-17: the exact persisted rows Reset Defaults reverts (main._reset_settings ->
# SETTINGS_DEFAULTS) -- the a11y + audio rows, NOT the coop/hard run-setup toggles,
# which reset never touches. The bulk confirm halo (_set_pulse_row == -2) lights ONLY
# these, so a reset never haloes a row it did not actually change.
const _RESET_ROWS := ["sfx", "music", "motion", "colorblind", "rumble", "assist", "display"]

# c1-08 destructive-row palette — the SINGLE source shared by _draw and the contrast
# test, so the two can't drift. Plates are DARK warm so the LIGHT warm labels over
# them clear AA-normal (4.5:1) contrast; a mid warm plate washed the label out. The
# armed flood is a deep red the near-white armed label reads on. (Alpha on the
# unselected plate rides the button texture; contrast is checked on rgb — the
# in-situ composite over the dark base only raises the ratio.)
const DESTR_PLATE_SEL := Color(0.64, 0.32, 0.22)          # pre-armed, selected
const DESTR_PLATE_UNSEL := Color(0.5, 0.26, 0.2, 0.9)     # pre-armed, unselected
const DESTR_TEXT_SEL := Color(1.0, 0.95, 0.9)
const DESTR_TEXT_UNSEL := Color(0.95, 0.85, 0.8)
const DESTR_ARMED_FLOOD := Color(0.8, 0.18, 0.09)         # red flood base (alpha applied at draw)
const DESTR_ARMED_TEXT := Color(1.0, 0.95, 0.88)
# The armed underplate sits BENEATH the near-opaque flood, so it is kept DARK red:
# a bright underplate would lighten the flood composite at the pulse trough and drop
# the label contrast below AA-normal. Dark under dark keeps the composite ~= flood.
const DESTR_ARMED_PLATE_SEL := Color(0.55, 0.14, 0.07)
const DESTR_ARMED_PLATE_UNSEL := Color(0.45, 0.12, 0.06)
# c2-15: armed-confirm affordance geometry/colors — a 2px bar was too subtle on the
# 360px canvas, so the arm now reads as a distinct ALERT: a thick amber frame, a bright
# top keyline, and a 4px countdown gauge over a dark track. Hoisted so _draw and any
# layout test share one source.
const DESTR_ARMED_FRAME := Color(1.0, 0.6, 0.2, 1.0)   # thick amber border ringing the armed row
const DESTR_ARMED_KEYLINE := Color(1.0, 0.82, 0.4)     # bright warning band across the plate top (alpha applied at draw)
const DESTR_ARMED_BAR_FILL := Color(1.0, 0.92, 0.55, 1.0)   # draining countdown gauge fill — a pale gold, hue-separated from the amber frame so the gauge reads as its own element
const DESTR_ARMED_BAR_TRACK := Color(0.15, 0.03, 0.02, 0.85)   # dark track the fill drains against
const DESTR_ARMED_BAR_H := 4.0   # countdown gauge height (was 2)
const DESTR_ARMED_FRAME_W := 4.0   # armed border thickness (was 2)

# c1-04: y (top) of the SELECT/BACK input-legend footer strip drawn on EVERY
# non-TITLE screen (PAUSE / OPTS / SETUP / HALL / HOWTO). One shared position so
# _footer_legend, _row_geometry's drop-in cap, and the layout test all agree the
# selected-row glow can never reach into it.
const FOOTER_Y := 341.0

# c2-08: Layout / Theme block — the single source for the geometry and plate colors
# that were previously scattered as bare 320s, per-mode `top` literals, and inline
# Color() plates. Centralizing them keeps submenu alignment and plate hues from
# drifting when PAUSE/OPTS/TITLE/SETUP layouts are edited. Organized as two sections:
# LAYOUT (geometry) then THEME (colors) — add to whichever section a value belongs to,
# never re-inline a bare literal into a draw path.

# ===== LAYOUT (geometry) =====
const CANVAS_WIDTH := 640.0     # design-space canvas size (the view scales this up)
const CANVAS_HEIGHT := 360.0
const CENTER_X := CANVAS_WIDTH / 2.0   # horizontal centre (button column + centred text)
# Per-mode y of the FIRST row plate (compute_geometry -> first_row_top). c3-02/c4-04: every top is
# DERIVED as (the baseline of the lowest header line that mode draws) + one of these two clearances,
# through the single first_row_top(mode) formula — no mode carries a bare top literal any more. The
# header baselines (PAUSE_FOOTNOTE_Y, OPTS_SUBLINE_Y, HUB_SUBTITLE_Y) live in mode_header_bottom;
# nudging one reflows that screen's row column with it instead of drifting off a hand-tuned number.
# Two clearances: the roomy HEADER_CLEAR for the sparse hubs/PAUSE, and the tighter
# HEADER_CLEAR_COMPACT for the DENSE paginated OPTS/REBIND pages — a full HEADER_CLEAR
# there would push their 10th plate below the >=20px readable floor (bounded by the
# plate floor, not taste).
const HEADER_CLEAR := 16.0         # gap a sparse column keeps below the header block it seats under
const HEADER_CLEAR_COMPACT := 8.0  # tighter clear for the dense <=10-row OPTS/REBIND pages
# c4-04: the per-mode first-row top is no longer a table of named offsets — every non-TITLE mode
# shares ONE formula, first_row_top(mode): the baseline of the lowest header line that mode draws
# (mode_header_bottom) + a common clearance (HEADER_CLEAR, or the tighter HEADER_CLEAR_COMPACT for
# the dense <=10-row OPTS/REBIND pages whose 10th plate would otherwise crush under 20px). The old
# TOP_PAUSE 130 / TOP_OPTS 102 / TOP_SUBHUB 120 constants are gone; the formula reproduces those
# exact values (PAUSE_FOOTNOTE_Y+16 / OPTS_SUBLINE_Y+8 / HUB_SUBTITLE_Y+16) from the header baselines,
# so nudging a header line reflows its column and no screen carries a bare top offset. TITLE is the
# outlier (derives its top from title_head_bottom). See mode_header_bottom / mode_is_compact /
# first_row_top near compute_geometry.
const TITLE_HEAD_MARGIN := 2.0     # TITLE seats its column this far below the drawn header block
# c4-04: TITLE record-header stack — ONE anchor (TITLE_WORDMARK_TOP) plus font-derived plate heights.
# Each plate HEIGHT is its drawn font size plus a single shared vertical pad, and each plate TOP below
# the wordmark is the previous plate's BOTTOM — so the whole stack chains from one number and one pad.
# title_head_bottom() DERIVES the column's header clearance from the same tops+heights. Before this the
# plate y's and title_head_bottom's 115/127/139 returns were hand-tuned literal sets nudged in lockstep
# by eye (the exact drift this item kills): a record line now moves only by editing its FONT SIZE or the
# shared pad, and the plates below it reflow with no overlap and no hand-copied y.
# ---- drawn font sizes (the size passed to _center_text; the heights below derive from these) ----
const TITLE_WORDMARK_FONT := 30
const TITLE_BYLINE_FONT := 8
const TITLE_TAGLINE_FONT := 10     # the taller of the two lines the shared record plate must seat
const TITLE_BEST_FONT := 9
const TITLE_CAREER_FONT := 8
# c4-04: ONE shared vertical plate padding — every TITLE header plate is its drawn font size plus this
# pad top AND bottom, so a font-size change resizes the plate with it (no hand-tuned per-plate height).
const TITLE_PLATE_PAD_V := 1.5
const TITLE_WORDMARK_H := TITLE_WORDMARK_FONT + 2.0 * TITLE_PLATE_PAD_V    # 33 — "SHOEMONEY SOLDIER" plate
const TITLE_BYLINE_H := TITLE_BYLINE_FONT + 2.0 * TITLE_PLATE_PAD_V        # 11 — studio byline plate
const TITLE_RECORD_PLATE_H := TITLE_TAGLINE_FONT + 2.0 * TITLE_PLATE_PAD_V # 13 — tagline & BEST share it (sized for the taller 10px tagline)
const TITLE_CAREER_PLATE_H := TITLE_CAREER_FONT + 2.0 * TITLE_PLATE_PAD_V  # 11 — CAREER whisper plate
const TITLE_WORDMARK_TOP := 60.0   # wordmark plate top — the stack's one anchor (10px horizontal pad, applied at draw)
# Each plate top below the wordmark is the previous plate's BOTTOM (top + height): resize any height
# and the plates below reflow with it, no overlap, no hand-copied y.
const TITLE_BYLINE_TOP := TITLE_WORDMARK_TOP + TITLE_WORDMARK_H    # studio byline plate top
const TITLE_TAGLINE_TOP := TITLE_BYLINE_TOP + TITLE_BYLINE_H       # tagline plate top
const TITLE_BEST_TOP := TITLE_TAGLINE_TOP + TITLE_RECORD_PLATE_H   # BEST-run plate top (abuts the tagline plate bottom)
const TITLE_CAREER_TOP := TITLE_BEST_TOP + TITLE_RECORD_PLATE_H    # CAREER whisper plate top (abuts the BEST plate bottom)
const TITLE_HEAD_SEAM := 1.0       # tagline-only column seats 1px below the tagline plate bottom
const BOTTOM_BOUND := 310.0        # y the last row / BACK plate clears (leaves the footer legend room)
const LEGEND_Y := 322.0            # TITLE input-legend plate top (the column band ends 4px above it)
const LEGEND_H := 34.0             # ...and its height
const ROW_INSET_TITLE := 2.0       # TITLE inter-row inset (reclaimed band => taller plates)
const ROW_INSET_DEFAULT := 3.0     # inter-row inset on every other screen
# c3-02: ONE row-pitch ceiling, derived from the plate height BTN.y so a button resize
# reflows the rhythm instead of drifting from a hand-tuned literal. A full-height plate
# plus ROW_BREATHING is the widest pitch worth drawing — past it a taller pitch only
# punches dead air between rows, so short lists clamp here rather than ballooning to the
# old 46, and dense lists no longer snap to a separate tighter ceiling at the 4->5 row
# boundary (the crushed-plate / dead-void discontinuity this item kills).
const ROW_BREATHING := 10.0        # dead band a full-height plate keeps above the next row
const GAP_CEIL := BTN.y + ROW_BREATHING   # 46 — the single row-pitch ceiling
# c3-03: extra vertical air TITLE inserts between the primary DEPLOY block (start verbs)
# and the secondary MORE block (SETUP / QUIT) — a real spatial gap, not just a 1px rule,
# so the two IA blocks read as distinct zones. Carried in the geometry dict (split_at /
# split_gap) and applied by row_rect, so every derived box (hit-test, arrows, glow) tracks
# it. Reserved out of the row band BEFORE the fit divide, so the DEPLOY plates never crush
# below the >=20px floor to pay for it (verified by test_title_states_all_clear...).
const TITLE_BLOCK_GAP := 9.0
# c3-03: the readable plate floor TITLE's row pitch is HARD-clamped to in compute_geometry.
# The 6-row cap plus the split gap must never crush a DEPLOY/MORE plate below this — an
# explicit runtime guard, not merely the row cap plus a test reference, so a future header
# nudge or a wider split gap holds the plate here instead of silently shrinking to an 8px
# speck (the exact regression this item exists to kill). 22px leaves margin over the 20px
# legibility minimum test_title_states_all_clear... pins.
const TITLE_MIN_PLATE := 22.0
# c3-02: the y a non-TITLE column's LAST plate BOTTOM aims for. Derived from the footer
# strip (not a bare 310) so the selected-row glow (+4.5) always clears FOOTER_Y with
# GLOW_CLEAR slack, and the gap math can divide the band by n — reserving that final
# plate's own height, exactly as TITLE already does against its legend.
const GLOW_CLEAR := 8.0            # slack the last plate's glow keeps above the footer strip
const COLUMN_BOTTOM := FOOTER_Y - GLOW_CLEAR   # 333 — last non-TITLE plate bottom aims here
const LEGEND_MARGIN := 4.0         # clearance the TITLE column keeps above LEGEND_Y
const FOOTER_H := 17.0             # height of the shared SELECT/BACK footer-legend plate
# c3-09: the two-line footer rises its top by this much for the extra description line; the bottom
# stays at FOOTER_Y + FOOTER_H. On the fullest OPTS list the last-row glow ends at y333.5, so the
# strip top (337) clears it by 3.5px. test_opts_footer_describes_focused_setting pins the clearance.
const FOOTER_HELP_RISE := 4.0
const BACK_H_RATIO := 0.7          # BACK plate is BTN scaled to this fraction of full row height
const REBIND_TAB_W := 96.0         # REBIND category-tab plate width
const REBIND_DEV_W := 52.0         # REBIND P1|P2 device sub-selector plate width
const REBIND_TAB_GAP := 6.0        # gap between REBIND tab / device plates
# Header text baselines shared across screens (kept here so a header-rhythm nudge
# lands in one place instead of per-screen literals in _draw). The INFO/DISP/SETUP
# hubs share one title+subtitle rhythm; HALL/HOWTO share one content-title baseline.
const HUB_HEADER_Y := 84.0         # INFO / DISP / SETUP header title baseline
const HUB_SUBTITLE_Y := 104.0      # ...and their subtitle line
const CONTENT_TITLE_Y := 38.0      # HALL / HOWTO content-screen title baseline
const TAB_BASELINE_Y := 66.0       # HALL filter / HOWTO page tab-label text baseline (plate top y54)
const FRAME_INNER_R := 612.0       # right edge of the chrome frame's interior (CANVAS_WIDTH 640 less the 28px border) — content clamps/right-aligns here
const TEXT_MID_10 := 4.0           # visual mid of a 10px cap-height glyph below its baseline (cap sits ~y-8..y); centers a sprite box on the text row
const PAUSE_HEADER_Y := 78.0       # PAUSED title baseline
const PAUSE_SUBTITLE_Y := 100.0    # PAUSE run-status subline
const PAUSE_FOOTNOTE_Y := 114.0    # PAUSE RUN# footnote — the lowest header line first_row_top(PAUSE) clears
const OPTS_TITLE_Y := 80.0         # OPTIONS title baseline
const OPTS_SUBLINE_Y := 94.0       # OPTIONS a11y-summary subline — the lowest header line first_row_top(OPTS) clears
# Horizontal half-padding of the small dark plates behind TITLE's byline / tagline /
# BEST / CAREER lines (a plate spans measured_text_w + 2x this).
const PLATE_PAD_SM := 4.0

# ===== THEME (colors) =====
# Shared plate colors. PLATE_BG is the dark warm backdrop behind header/footer
# captions; PLATE_SEL / PLATE_UNSEL are the focused / resting button-plate hues.
const PLATE_BG := Color(0.03, 0.05, 0.03, 0.55)
const PLATE_SEL := Color(1.0, 0.92, 0.55)
const PLATE_UNSEL := Color(0.55, 0.62, 0.45, 0.8)
const DISABLED_PLATE := Color(0.3, 0.34, 0.3, 0.7)   # c2-13: locked/unavailable row plate (dim, desaturated)
const DISABLED_TEXT := Color(0.55, 0.58, 0.52)       # c2-13: muted label on a locked row
const ARROW_UNSEL := Color(0.72, 0.77, 0.62, 0.85)   # resting submenu-chevron tint
const CAPTION_COL := Color(0.84, 0.9, 0.68, 0.95)    # c2-11: brighter so the section headers read as labels, not faint asides
const NOTICE_COL := Color(1.0, 0.85, 0.5)            # rebind swap/clear notice
const SCRIM_BASE := Color(0.02, 0.05, 0.02)          # full-screen dim scrim (alpha applied at draw)
const WELL_BASE := Color(0.035, 0.055, 0.05)         # content-well fill (alpha applied at draw)
# Group-separator rules drawn between labelled blocks (bright = primary split, dim = minor).
const DIVIDER_BRIGHT := Color(0.86, 0.82, 0.52, 0.8)
const DIVIDER_DIM := Color(0.62, 0.66, 0.5, 0.55)
# Header/subtitle text hues shared across screens.
const SUBTITLE_COL := Color(0.8, 0.85, 0.72)         # subline under a screen header (INFO/DISP/SETUP/OPTS/PAUSE)
# c3-09: the footer's row-description line reads as helper text, but NOT dim — dimming accessibility
# copy fights its own purpose, so it stays high-contrast (full alpha, near the SELECT/BACK legend's
# Color(0.82,0.87,0.77) luminance). The hairline rule under it, not a low-contrast hue, is what keeps
# it from reading as another actionable prompt.
const FOOTER_HELP_COL := Color(0.85, 0.88, 0.8, 1.0)
const HEADER_ACCENT := Color(1.0, 0.85, 0.3)         # warm title color for TITLE/HALL/HOWTO record headers
const BYLINE_COL := Color(0.85, 0.78, 0.55, 0.92)    # TITLE byline text
const CAREER_COL := Color(0.6, 0.72, 0.62, 0.7)      # TITLE career/record footnote text
# Large content-frame chrome tints (multiplied by _open_t at draw).
const FRAME_UNDER_TINT := Color(1, 1, 1, 0.9)        # ui_frame_lrg_under backing
const FRAME_TINT := Color(0.85, 0.9, 0.75)           # ui_frame_lrg overlay
const HEADER_COL := Color(0.95, 0.95, 0.85)          # lone screen-header title (INFO/DISP/SETUP/PAUSED/CONTROLS/OPTIONS)
const TAGLINE_COL := Color(0.85, 0.9, 0.8, 0.85)     # TITLE tagline line
const BEST_LINE_COL := Color(1.0, 0.92, 0.55, 1.0)   # TITLE best-run line
const RUN_FOOTNOTE_COL := Color(0.6, 0.66, 0.56, 0.75)  # PAUSE run-id footnote
const WARN_COL := Color(0.95, 0.72, 0.42)            # OPTS warning subline
const OVERFLOW_CHIP_COL := Color(0.0, 0.0, 0.0, 0.72)     # c2-14 truncation-flag backing chip
# c2-14: an overflow flag IS an "attention" cue, so its amber tracks the menu's shared
# WARN_COL palette (the OPTS warning subline) instead of a fresh hardcoded amber — a
# palette retint carries the chip with it rather than leaving one orphaned magic color.
const OVERFLOW_CHIP_BORDER := Color(WARN_COL, 0.55)      # c2-14 chip border (contrast on any row)
const OVERFLOW_DOT_COL := WARN_COL                       # c2-14 the three amber "clipped" dots
const OVERFLOW_CHIP_PAD := 3.0                           # c2-14 breathing room between text and the chip
# c3-13: CHALLENGE SEED sub-label palette. The at-rest "(FROM CLIPBOARD)" source tag rides
# INSIDE the plate as helper text (SEED_TAG_COL); a focused row with nothing usable on the
# clipboard gets a LEFT-EDGE red status stripe (a shape marker, deliberately UNLIKE the
# destructive armed FULL flood so an invalid paste never reads as an armed RESTART/QUIT) over a
# very faint veil, both brightening/widening on a denied press (via the decaying _seed_flash).
const ROW_LABEL_SIZE := 11                                # c3-13: the main row-label font size — one source shared by the label draw AND the seed sub-label's clearance/alignment math
const ROW_LABEL_BASELINE_DY := 4.0                        # c3-13: main row-label baseline offset below the row center (cy) — shared with the seed sub-label so the two never drift apart
const SEED_ROW_LABEL := "CHALLENGE SEED"                  # the CHALLENGE SEED row's base label — single-sourced so a rename/relocalize can't desync the sub-label's name-column measurement
const SEED_SOURCE_COPY := "(FROM CLIPBOARD)"              # the at-rest source sub-label copy — one source, used by both seed_hint_lines() and the in-plate tag draw (no coupling to hint-line param order)
const SEED_TAG_COL := Color(0.74, 0.8, 0.7, 0.62)        # in-plate source sub-label (helper text)
const SEED_TAG_SIZE := 7                                  # px; the ONE size seed sub-lines are measured AND drawn at
const SEED_DENY_RED := Color(0.62, 0.13, 0.08)           # red for the invalid-seed status stripe + faint veil
const SEED_DENY_VEIL_A := 0.09                            # faint full-plate tint (far below the destructive flood's ~0.82, so the two never read alike)
const SEED_DENY_BAR_W := 3.0                             # left-edge status-stripe width at rest (a denied press widens it)
const SEED_DENY_BAR_A := 0.75                            # status-stripe opacity (thin, so it marks without flooding)
const SEED_DENY_FLASH_BRIGHT := Color(1.0, 0.5, 0.3)     # a denied press lerps BOTH the left-edge stripe AND the in-plate error text toward this brighter red, so the pulse reads as one event
# c3-13: seed sub-label placement pads, derived from the row's own chrome so the tag stays inside
# the plate: SEED_SUB_PAD mirrors the main label's r.end.x-8 right bound; SEED_SUB_GAP is the gap
# kept after the name on the short-plate same-line path; SEED_SUB_MARGIN is the bottom breath.
const SEED_SUB_PAD := 8.0
const SEED_SUB_GAP := 6.0
const SEED_SUB_MARGIN := 2.0   # bottom breath so a stacked line's descenders never sit on the plate edge
# c3-03: DEPLOY backing-panel chrome (the raised cluster behind the start verbs) — hoisted
# out of _draw so the fill/border hues live with the rest of the THEME block, not as bare
# inline Color() literals. Alpha is scaled by _open_t at draw so the panel fades in with the column.
const PANEL_FILL := Color(0.10, 0.14, 0.09, 0.5)        # DEPLOY panel fill
const PANEL_BORDER := Color(HEADER_ACCENT, 0.3)         # DEPLOY panel accent keyline


func _ready() -> void:
	# Pad yanked mid-run = pause. The sim only steps while no menu is visible,
	# so opening PAUSE from here is the whole fix — no main.gd surgery.
	Input.joy_connection_changed.connect(_on_joy_changed)


func _notification(what: int) -> void:
	# c2-14: a theme or translation swap can change the active font (a re-themed
	# face, a localized glyph set). _cut_cache keys on the font INSTANCE id, and
	# Godot recycles freed instance ids — a new font reusing an old id would read
	# STALE shaped cuts; _row_fit_cache keys the same way and would return stale
	# overflow/ellipsis results. Drop both so they re-measure against the current font.
	# (No super call: Control._notification is a built-in virtual, not a script method,
	# and the engine still dispatches base handling for every notification regardless.)
	# Only the events that can actually change the active FONT invalidate the caches — a
	# plain reparent keeps the same font, so we don't flush a valid cache on every move.
	if what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_TRANSLATION_CHANGED:
		_cut_cache.clear()
		_row_fit_cache.clear()
		_items_valid = false   # c3-16: a translation swap can change row LABEL text, so drop the
		                       # cached rows too — the next read rebuilds them in the new language
	# c3-16: the once-per-frame _menu_items snapshot is only trusted while in-tree. Drop it on
	# EXIT_TREE so a menu that is removed and later re-added can never serve a snapshot built before
	# it left (state read from `main` may have moved while detached) — the re-add rebuilds from live.
	if what == NOTIFICATION_EXIT_TREE:
		_items_valid = false
		_items_cache = ([] as Array[Dictionary])


func _on_joy_changed(_device: int, connected: bool) -> void:
	if connected:
		return
	# A pad yanked while the stick is deflected emits no further motion events,
	# so the <0.45 re-arm can never fire — clear the latches or _process
	# auto-repeats _nav every 0.12s forever (endless scroll + sfx loop).
	_stick_x = 0
	_stick_y = 0
	_nav_frame = -1
	if mode == Mode.HIDDEN and main != null and main.sim != null:
		open(Mode.PAUSE)
		# A pad yanked mid-flail can spray phantom presses — ignore
		# confirm/activate for a beat so nothing destructive can fire.
		_lockout = 0.25


func _process(delta: float) -> void:
	if main == null:
		return   # c3-07: menu can outlive main during teardown; every branch below reads main._motion
	if mode != Mode.HIDDEN:
		# Armed RESTART/TITLE/QUIT rows disarm after 2.5 s — a stale confirm
		# must not end a run on a press that lands minutes later.
		if _confirm >= 0:
			_confirm_t -= delta
			_dirty = true   # the draining confirm-countdown bar
			if _confirm_t <= 0.0:
				_disarm_confirm()   # c2-09: clears index + countdown together
		# c1-09: the "DEFAULTS RESTORED" success banner fades after RESET DEFAULTS fires.
		if _reset_flash > 0.0:
			_reset_flash = maxf(0.0, _reset_flash - delta)
			_dirty = true
		if _seed_flash > 0.0:
			_seed_flash = maxf(0.0, _seed_flash - delta * 2.0)
			_dirty = true
		# c1-18: the REBIND swap/clear/reserved notice fades on its OWN timer, wholly
		# independent of _set_pulse — every frame the menu is open, so a "CANCELLED" or
		# "FIXED MENU KEY" notice always clears after ~2.5s (it can never persist forever).
		if _rebind_msg_t > 0.0:
			_rebind_msg_t = maxf(0.0, _rebind_msg_t - delta)
			_dirty = true
			if _rebind_msg_t <= 0.0:
				_rebind_msg = ""
		if _seed_armed:
			_seed_armed_t -= delta   # c1-14: a stale "PRESS AGAIN" arm auto-disarms (mirrors _confirm_t)
			if _seed_armed_t <= 0.0:
				_seed_armed = false
				_dirty = true   # the armed hint reverts to the plain preview — repaint it
		# c1-14: keep the CHALLENGE SEED preview fresh OFF the draw path, but THROTTLE
		# the clipboard sample to ~5x/s instead of once per frame (60x/s).
		_update_seed_preview(delta)
		if _lockout > 0.0:
			_lockout = maxf(0.0, _lockout - delta)
			_dirty = true
		# Tab flash is pure animation — reduce-motion snaps it off entirely.
		_filter_pulse = 0.0 if main._motion < 0.5 else maxf(0.0, _filter_pulse - delta * 3.0)
		# Page-button press flash decays like the tab pulse; reduce-motion snaps it off.
		_page_press = 0.0 if main._motion < 0.5 else maxf(0.0, _page_press - delta * 3.5)
		if _page_press <= 0.0:
			_page_press_side = -1
		_rail_pulse = 0.0 if main._motion < 0.5 else maxf(0.0, _rail_pulse - delta * 3.5)
		# c1-17: the settings-change confirm pulse decays even under Reduce Motion — it's
		# FEEDBACK, not decoration, so it can't snap off like the rail/tab flashes above;
		# reduce-motion just renders it as a static border (no grow) in _draw.
		# Slow decay (*2.0 ~= 0.5s visible) so the confirm holds long enough to catch,
		# not a ~0.29s blink a glancing player misses.
		if _set_pulse > 0.0:
			_set_pulse = maxf(0.0, _set_pulse - delta * 2.0)
			_dirty = true
		if _set_pulse <= 0.0:
			_set_pulse_row = -1
		# Held-stick auto-repeat: first step fired in _unhandled_input, then
		# after 0.35 s held it steps every 0.12 s (framerate-independent).
		if _stick_x != 0 or _stick_y != 0:
			_stick_rep -= delta
			if _stick_rep <= 0.0:
				_stick_rep = 0.12
				# Auto-repeat drives VERTICAL nav and HALL filter cycling only.
				# A held sideways stick used to machine-gun toggle activation ~8×/s
				# (buy sfx spam + bus mute flip + a settings disk-write every step);
				# the deliberate first flip still fires on the press edge in _unhandled_input.
				_nav(_stick_y, _stick_x if mode == Mode.HALL else 0)
		# Held up/down KEYS get the same repeat cadence as the stick.
		if _key_move != 0:
			_key_rep -= delta
			if _key_rep <= 0.0:
				_key_rep = 0.12
				_nav(_key_move, 0)
		# Held ◄/► KEYS auto-repeat, matching the held stick: in HALL it cycles the
		# filter (stick does the same at line ~95), on a volume row it steps the
		# level. Toggles get NO repeat — a held key would machine-gun the flip.
		if _key_hmove != 0:
			_key_hrep -= delta
			if _key_hrep <= 0.0:
				_key_hrep = 0.12
				if mode == Mode.HALL or _menu_items()[sel]["id"] in ["sfx", "music"]:
					_nav(0, _key_hmove)
				else:
					_key_hmove = 0   # not a HALL/volume context: drop the latch, no auto-repeat
		# Exp-decay easing: framerate-independent (per-frame lerpf ran ~2.4x
		# faster on a 144Hz display). Reduce-motion snaps both instantly.
		if main._motion < 0.5:
			# Reduce motion snaps both in one frame; mark dirty so that settling frame paints.
			if _open_t != 1.0:
				_open_t = 1.0
				_dirty = true
			if _sel_target >= 0.0 and _sel_y != _sel_target:
				_sel_y = _sel_target
				_dirty = true
		else:
			# Motion on: _menu_is_animating() is always true, so the gate paints every frame —
			# these eased values need no explicit marking.
			_open_t = lerpf(_open_t, 1.0, 1.0 - exp(-20.0 * delta))
			if _sel_target >= 0.0:
				_sel_y = lerpf(_sel_y, _sel_target, 1.0 - exp(-22.0 * delta))
				if absf(_sel_y - _sel_target) < 1.0:
					_sel_y = _sel_target   # snap: sub-pixel drift shimmers the pixel font
		# c2-09: the SOLE redraw request. _dirty was set above (and by every input handler) at
		# each mutation site whose pixels changed — covering the settling frame under reduce
		# motion; _menu_is_animating() adds the continuous case (the selection glow breathes
		# every frame while motion is on). A settled, reduce-motion menu marks neither and idles.
		if _dirty or _menu_is_animating():
			queue_redraw()


## c2-09: is CONTINUOUS animation live this frame? The _process gate ORs this with _dirty.
## With motion ON the selection glow (and an armed row's red flood) breathes every frame via
## Art.pulse, so a per-frame repaint is always needed. Under REDUCE MOTION nothing breathes and
## the glide/open envelope snap instantly, so this reports true only while a value is genuinely
## moving — the open/glide not yet settled, or a confirm countdown / flash / halo still draining.
## The rail/tab/page flashes are already 0 under reduce motion; listed anyway so the live-set is
## one auditable enumeration. _dirty (not this predicate) covers the discrete settling frame.
func _menu_is_animating() -> bool:
	if not is_active():
		return false   # c2-09: a hidden menu never animates — self-contained even if a caller forgets
	if main._motion >= 0.5:
		return true
	# 0.5px epsilon on the glide (not a bare !=): the snap path keeps _sel_y exact today, but a
	# sub-pixel residual would be visually settled anyway, so it must not keep requesting redraws.
	return _open_t < 1.0 or (_sel_target >= 0.0 and absf(_sel_y - _sel_target) > 0.5) \
			or _confirm_t > 0.0 or _reset_flash > 0.0 or _seed_flash > 0.0 \
			or _rebind_msg_t > 0.0 or _lockout > 0.0 or _set_pulse > 0.0 \
			or _rail_pulse > 0.0 or _filter_pulse > 0.0 or _page_press > 0.0


## c2-09: the ONE way a destructive-row confirm is disarmed — clears the index AND its
## countdown together, so `_confirm_t > 0` stays a reliable "countdown live" flag for the
## redraw gate no matter which path disarms (timeout / nav-away / activation / screen change).
func _disarm_confirm() -> void:
	_confirm = -1
	_confirm_t = 0.0


func is_active() -> bool:
	return mode != Mode.HIDDEN


func open(m: int, select_id := "") -> void:
	# Menu-to-menu keeps ~60% scrim — a full _open_t reset dipped the backdrop
	# to ~0 for a frame and flashed the live attract firefight between screens.
	# Only entering from gameplay replays the full fade + drop-in.
	_open_t = 0.0 if mode == Mode.HIDDEN else 0.6
	mode = m
	sel = 0
	# c3-16: the mode/sel just changed — drop the row memo NOW, before the select_id re-read below (or
	# any other same-frame caller) can serve a snapshot built for the OLD screen. _has_replay is set
	# just below, so the rebuild that follows already sees the fresh replay gate too.
	_items_valid = false
	# c3-16: sample the replay file's existence ONCE here, on the menu open — and ONLY for the screens
	# whose row list can surface WATCH LAST RUN (INFO builds that row; TITLE is its entry point). Every
	# such screen then reads the cached _has_replay bool, so no per-frame draw / hit-test / nav ever
	# calls FileAccess.file_exists and the disk micro-stutter is gone. Modes that never show the row
	# (PAUSE / OPTS / SETUP / HALL / HOWTO / DISP / REBIND) skip the stat entirely. Refreshed on each
	# such open, so a replay banked during the run is picked up next time (recomputed only on reopen).
	if m == Mode.TITLE or m == Mode.INFO:
		_has_replay = FileAccess.file_exists(REPLAY_PATH)
	# c3-18: entering OPTIONS CLEAN captures the pristine on-disk baseline BEFORE any row is
	# tweaked, so DISCARD/Esc revert to the real original values. Guarded on `not _opts_dirty` so a
	# round-trip out to the DISPLAY sub-screen and back (which re-opens OPTS while still dirty)
	# preserves the original baseline instead of re-snapshotting the mid-edit state.
	if m == Mode.OPTS and not _opts_dirty and main != null:
		_opts_snapshot = main._settings_snapshot()
	_disarm_confirm()   # c2-09: no armed row (nor its live countdown) carries into a fresh screen
	_rail_pulse = 0.0   # a fresh screen starts with no lingering rail-bounce flash
	_rail_row = -1
	_set_pulse = 0.0    # c1-17: nor a lingering settings-change confirm halo
	_set_pulse_row = -1
	_sel_y = -1.0   # highlight starts on the new menu's first row, no cross-menu glide
	_sel_target = -1.0
	_key_move = 0   # a key held across the transition must not auto-repeat here
	_key_hmove = 0  # nor a held ◄/► volume key
	# Same discipline for the stick: pausing via START with the move-stick
	# deflected (the normal mid-combat case) used to auto-scroll 0.35s later —
	# and the first step UP wrapped focus from RESUME straight onto a
	# destructive row. Mirrors the _on_joy_changed clear.
	_stick_x = 0
	_stick_y = 0
	_nav_frame = -1
	_tab_hover = -1   # stale hall-tab hover must not survive a menu hop
	_page_hover = -1  # ditto the PREV/NEXT hover — a menu hop must not leave a button lit
	# c1-14: a fresh screen starts with ALL CHALLENGE SEED interaction state cleared —
	# reopening TITLE must never preserve an armed seed (which a single press could then
	# launch) or a stale preview/flash. Focus re-reads the clipboard from scratch.
	_seed_preview = -1
	_seed_clip_raw = ""
	_seed_armed = false
	_seed_armed_val = -1
	_seed_armed_t = 0.0
	_seed_poll_t = 0.0
	_seed_flash = 0.0
	_rebind_action = ""   # c1-18: a fresh screen is never mid-capture (a stale listen would eat the first key)
	_rebind_tab = 0       # c1-18: reopen always lands on the first (MOVE/AIM) tab
	_rebind_pad_dev = 0   # c1-18: and on P1's pad layout
	_rebind_msg = ""      # c1-18: no stale swap/clear notice carries into a fresh screen
	_rebind_msg_t = 0.0
	if m == Mode.HALL:
		# Auto-jump to the run you just finished — but ONLY the first time the board
		# is opened after it was banked. Once surfaced (hid recorded), reopening HALL
		# preserves the filter/page the player last chose instead of yanking them back.
		var lr: Variant = main.get("hall_latest") if main != null else null
		var lh := -1
		if lr != null and not (lr as Dictionary).is_empty():
			lh = int((lr as Dictionary).get("hid", -1))
		if lh != -1 and lh != _hall_seen_hid:
			# A stale opposite-mode filter (e.g. CAMPAIGN) would hide an ENDLESS run —
			# widen to ALL ONLY when the current filter actually hides it; a filter
			# that already shows it is left alone, respecting the player's choice.
			if _hall_latest_index(_hall_rows()) < 0:
				_hall_filter = 0
			_hall_page = _hall_latest_page()
			_hall_seen_hid = lh
		else:
			# Already surfaced (or no fresh run): keep the player's place, only
			# clamping the page in case a filter change shrank the list underneath it.
			_hall_page = clampi(_hall_page, 0, _hall_pages(_hall_rows().size()) - 1)
	elif m == Mode.HOWTO:
		_howto_page = 0   # c3-05: always open the help on the CONTROLS page
		_howto_endless_page = 0   # c4-06: reset the ENDLESS roster to its first sub-page too
		_howto_nav_hover = -1   # c4-06: clear any stale chevron-hover so re-entry can't light a plate before the next motion event
		_tab_hover = -1   # c2-02: HOWTO shares _tab_hover with HALL — clear it so a hover index left on the OTHER screen's tab row can't light a HOWTO tab (open() clears it above too; explicit here for the shared-state contract)
	elif m == Mode.INFO:
		# c3-16: _has_replay (the WATCH LAST RUN gate) was already sampled at the top of open() —
		# the ONE disk touch, shared by every screen — so nothing is re-stat'd here.
		pass
	# Any menu opening freezes the sim mid-hold — cancel open supply wheels, or a
	# hold+pick released WHILE paused commits a stale buy on the first resumed
	# frame (the release the player meant as an abort).
	if main != null:
		for w in main._wheel:
			w["open"] = false
			w["sel"] = -1
	# Backing out of a submenu re-selects the row that opened it — landing on
	# CAMPAIGN after OPTIONS broke muscle memory (and risks a misfired start).
	if select_id != "":
		var mi := _menu_items()
		for k in mi.size():
			if mi[k]["id"] == select_id:
				sel = k
				break
	# c2-09: mark dirty so _process paints the freshly-opened screen's first frame. Under
	# REDUCE MOTION _menu_is_animating() goes false as soon as the open/glide envelope snaps,
	# so the gate alone would not paint — the dirty flag is what guarantees the initial frame.
	_mark_dirty()


func _bus_off(name: String) -> bool:
	# The single source of truth for "is this bus muted" — the row label, the
	# segment bar, and the volume stepper all read mute through here. Guards a
	# missing bus (index -1) instead of feeding it to is_bus_mute.
	var i := AudioServer.get_bus_index(name)
	return i >= 0 and AudioServer.is_bus_mute(i)


# c3-16: the ONE explicit "the rows changed" call — flag a repaint AND drop the once-per-frame
# _menu_items memo so the next read rebuilds. Call THIS (never a bare _dirty = true) at every site that
# changes what the rows SAY: mode/sel, a settings toggle or volume step, the seed preview, the replay
# gate. A pure animation repaint (a flash / countdown decay / breathing glow) stays a bare _dirty =
# true — it must NOT invalidate rows that did not change. Keeping the two separate is the whole point.
func _mark_dirty() -> void:
	_dirty = true
	_items_valid = false


# c3-16: the caching front door. In the live game the menu is always in the scene tree, so caching is
# on for every real read — it serves the memoized snapshot until _mark_dirty() drops it (or the frame
# turns), collapsing the ~10 rebuilds a frame down to one. The is_inside_tree() gate is a DELIBERATE
# contract, not an oversight: the memo's freshness rests on "every row-changing mutation calls
# _mark_dirty()", and the headless layout tests bypass that contract on purpose — they poke
# mode/sel/main directly to assert _menu_items() against arbitrary states, so for those out-of-tree
# callers the method stays a pure live query. Thus caching is uniform across all REAL (in-tree)
# callers, and the only path it steps aside for is the test harness that explicitly opts out.
# CONTRACT for in-tree callers: a caller that MUTATES row-affecting state (mode/sel/settings/seed/
# replay) and then re-reads _menu_items() in the SAME frame must _mark_dirty() BETWEEN the two, or the
# second read serves the pre-mutation snapshot. (open() does this: it _items_valid = false's the moment
# it flips mode, before its own select_id re-read below.) The frame stamp caps any slip at one frame.
# Callers treat the result read-only (the only per-call mutation, the TITLE seed label, lives INSIDE
# _rebuild and re-runs when sel changes).
func _menu_items() -> Array[Dictionary]:
	var frame := Engine.get_process_frames()
	if is_inside_tree() and _items_valid and _items_frame == frame:
		return _items_cache
	var built := _rebuild_menu_items()
	if is_inside_tree():
		_items_cache = built
		_items_valid = true
		_items_frame = frame
	return built


func _rebuild_menu_items() -> Array[Dictionary]:
	if main == null:
		# c3-07: most rows read live main state (main._two_players, main.daily_done, …).
		# Explicitly-typed empty so the Array[Dictionary] contract holds for every caller.
		var none: Array[Dictionary] = []
		return none
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return [{"id": "back", "label": "BACK", "destructive": false}]
	if mode == Mode.TITLE:
		# "grp" drives the divider rules in _draw: start-verbs / run-config
		# toggles / meta screens / quit each read as their own block.
		# c1-02: the 11-row crush is gone. RUN SETUP (a submenu holding CO-OP / NG+
		# HARD) sits right beside the start verbs it configures — a pre-run choice
		# stays one press from CAMPAIGN, not buried in settings. To hold TITLE at its
		# comfortable 8-row cap (>=20px plates, 16px icons), the meta screens moved
		# down a level: HALL OF FAME and HOW TO PLAY now live under the INFO screen. The
		# old list wedged config between the start verbs and the meta screens, driving bh
		# to ~11px with 8px speck icons and seating NG+/CO-OP right where a mis-nav
		# off CAMPAIGN landed.
		var titems: Array[Dictionary] = [
			{"id": "campaign", "label": "CAMPAIGN", "destructive": false, "grp": 0},
			{"id": "endless", "label": "ENDLESS WAR", "destructive": false, "grp": 0},
			# c2-13: once today's seed-of-the-day has been played the row locks — dim, a
			# right-aligned COMPLETED badge, and a deny buzz on press — instead of staying
			# fully active in appearance while silently re-running the same finished attempt.
			# The status is a separate right-aligned "badge" (not appended to the label) so
			# it never clips the label and stays scannable, mirroring the toggle-dot slot.
			{"id": "daily", "label": "DAILY RUN", "destructive": false, "grp": 0,
				"disabled": main.daily_done(), "badge": "COMPLETED" if main.daily_done() else ""},
			{"id": "paste_seed", "label": SEED_ROW_LABEL, "destructive": false, "grp": 0},
			# grp 1: run-config gets its own block (a divider splits it from the start
			# verbs above and the meta screens below). The row carries its own live
			# config tail — players and an EXPLICIT NORMAL/HARD difficulty — so a stale
			# CO-OP or NG+ choice can't ride hidden into the next deploy.
			{"id": "setup", "label": "SETUP: %s  %s" % ["2P" if main._two_players else "1P",
				"HARD" if main._hard else "NORMAL"], "destructive": false, "grp": 1, "submenu": true},
		]
		# c1-09: the meta block is two focused rows — OPTIONS (settings ONLY, no info
		# links) and INFO (HALL OF FAME / HOW TO PLAY / WATCH LAST RUN). Splitting them
		# lets OPTIONS be a genuinely dedicated settings screen while INFO gathers the
		# look-back screens. WATCH LAST RUN moved off TITLE onto INFO (it belongs with
		# the records), so the meta block is a CONSTANT two rows and TITLE holds at its
		# 8-row cap whether or not a replay exists.
		# c2-04: OPTIONS and INFO moved DOWN a level into the SETUP hub (below), so TITLE's
		# tail is a single SETUP row + QUIT. That holds TITLE at 6 full-height rows instead
		# of 8, keeping the four start verbs the visually dominant block.
		# c3-03: QUIT joins SETUP in grp 1 — the secondary "MORE" block. TITLE is now TWO
		# named IA blocks, not a flat column: grp 0 (CAMPAIGN / ENDLESS / DAILY / CHALLENGE
		# SEED) is the DEPLOY block; grp 1 (SETUP + QUIT) is everything that isn't starting a
		# run. One brightened divider (grp 0 -> grp 1) plus a DEPLOY/MORE caption pair mark the
		# split, and the DEPLOY block gets a backing panel in _draw so the start verbs read as
		# one dominant cluster, not the top of an undifferentiated phone list.
		titems.append({"id": "quit", "label": "QUIT", "destructive": true, "grp": 1})
		# c2-12: while the CHALLENGE SEED row is FOCUSED, rebuild its label here — in the
		# standard menu-item refresh flow every draw reads — to echo the raw clipboard text
		# the poll keeps fresh (_seed_clip_raw). This means the visible label tracks a
		# clipboard change LIVE (no refocus needed) and the player sees exactly what a press
		# will use; the right-margin hint (seed_hint_lines) says whether it parses.
		for i in titems.size():
			if titems[i]["id"] == "paste_seed":
				if sel == i:
					titems[i]["label"] = seed_row_label(titems[i]["label"], true,
						_seed_clip_raw, _seed_preview >= 0)
				break
		return titems
	if mode == Mode.SETUP:
		# c1-02: CO-OP / NG+ HARD live on their own labeled RUN SETUP screen (reached
		# from TITLE, beside the start verbs) so pre-run choices read as a distinct
		# step and never crowd the settings toggles. Two rows + BACK => big plates.
		# c2-04: SETUP is the hub for everything that used to crowd TITLE's tail. grp 0 is the
		# run config (CO-OP / NG+ HARD); grp 1 is the two secondary screens (OPTIONS / INFO)
		# demoted off TITLE. The grp 0->grp 1 divider (brightened in _draw) reads as the
		# "this run" vs "everything else" split.
		return [
			{"id": "coop", "label": "CO-OP: %s" % ("ON" if main._two_players else "OFF"), "destructive": false, "on": main._two_players, "grp": 0},
			{"id": "hard", "label": "NG+ HARD: %s" % ("ON" if main._hard else "OFF"), "destructive": false, "on": main._hard, "grp": 0},
			{"id": "options", "label": "OPTIONS", "destructive": false, "grp": 1, "submenu": true},
			{"id": "info", "label": "INFO", "destructive": false, "grp": 1, "submenu": true},
			{"id": "back", "label": "BACK", "destructive": false, "grp": 2},
		]
	if mode == Mode.INFO:
		# c1-09: the look-back screens, split off OPTIONS so settings stand alone. HALL
		# OF FAME + HOW TO PLAY + (when a replay exists) WATCH LAST RUN, then BACK. All
		# reached from TITLE's INFO row; each climbs back here.
		var iitems: Array[Dictionary] = [
			{"id": "hall", "label": "HALL OF FAME", "destructive": false, "grp": 0, "submenu": true},
			{"id": "howto", "label": "HOW TO PLAY", "destructive": false, "grp": 0, "submenu": true},
		]
		# c3-16: gate WATCH LAST RUN on the CACHED bool sampled once in open() — never a fresh
		# FileAccess.file_exists here, so rebuilding this list (even the pre-cache per-frame case)
		# is pure in-memory work and never touches the disk.
		if _has_replay:
			iitems.append({"id": "watch", "label": "WATCH LAST RUN", "destructive": false, "grp": 0})
		iitems.append({"id": "back", "label": "BACK", "destructive": false, "grp": 2})
		return iitems
	if mode == Mode.DISP:
		# c1-19: the dedicated DISPLAY sub-screen (reached from the OPTS DISPLAY row, climbs back
		# to it). TWO explicit controls, never overloaded onto one: FULLSCREEN is a plain ON/OFF
		# toggle (a SINGLE press reaches fullscreen, no ladder to climb), and WINDOW SCALE is an
		# independent 1x..Nx integer stepper. WINDOW SCALE stays a LIVE control in BOTH modes — no
		# dead, silently-ignored row: while windowed ◄/►/Enter resize the window live; while
		# fullscreen they edit the PREFERRED scale that applies the moment you drop back to windowed
		# (the label gains a "(WINDOWED)" tag and the subtitle spells out the deferral). While
		# fullscreen the row shows the raw stored preference (what will apply), not the monitor-
		# clamped effective; while windowed it shows the effective, live-applied scale.
		return [
			{"id": "fullscreen", "label": fullscreen_label(main._fullscreen), "destructive": false, "on": main._fullscreen, "grp": 0},
			# c3-09: "step" tags this as an integer-stepper value row (alongside "on" toggles / "vol"
			# bars). It's the single source that drives the help-footer's value-row test, _row_cycles
			# (this row shows ◄/► arrows) AND footer_cycle_segs (its hint reads ADJUST) — no id
			# special-case anywhere; a future stepper just sets "step": true.
			{"id": "winscale", "label": winscale_label(main._win_scale if main._fullscreen else main._win_scale_norm()), "destructive": false, "grp": 0, "step": true},
			{"id": "back", "label": "BACK", "destructive": false, "grp": 1},
		]
	if mode == Mode.OPTS:
		# c1-09: the ONE dedicated SETTINGS screen — nothing but settings now (HALL OF
		# FAME / HOW TO PLAY moved to the INFO screen). Reached from TITLE and from
		# PAUSE's single OPTIONS row. The settings sit in four labelled blocks — AUDIO
		# (grp 1) / HAPTICS (grp 2) / ACCESSIBILITY (grp 3) / DISPLAY (grp 4) — then
		# RESET DEFAULTS (grp 5, a two-press confirm that recovers a bad choice), then
		# BACK (grp 6). group_header() names each settings block.
		var oitems: Array[Dictionary] = _settings_rows()
		# RESET DEFAULTS is a focusable, destructive-styled row: Enter/A arms it, a
		# second press reverts every persisted setting — the recover path the screen
		# lacked (immediate writes with no rollback). Two-press guards a stray press.
		# c1-18: CONTROLS is a normal focusable row (grp 5, above RESET DEFAULTS) that opens
		# the dedicated key/button rebinding screen — a first-class OPTIONS entry, not a
		# hidden corner shortcut, so keyboard/pad reach it by simply focusing it and pressing.
		oitems.append({"id": "controls", "label": "CONTROLS (REBIND)", "destructive": false, "grp": 5})
		oitems.append({"id": "reset_defaults", "label": "RESET DEFAULTS", "destructive": true, "grp": 6})
		# c3-18: dirty-state exit. With unsaved staged changes the lone BACK splits into an explicit
		# SAVE (commit) and DISCARD (revert) pair, so the deferred write is a visible, deliberate
		# choice; a clean screen keeps the single BACK (nothing staged, so nothing to decide).
		if _opts_dirty:
			oitems.append({"id": "opts_save", "label": "SAVE", "destructive": false, "grp": 7})
			oitems.append({"id": "opts_discard", "label": "DISCARD", "destructive": false, "grp": 7})
		else:
			oitems.append({"id": "back", "label": "BACK", "destructive": false, "grp": 7})
		return oitems
	if mode == Mode.REBIND:
		# c1-18: one row per rebindable verb on the ACTIVE CATEGORY tab. The 14 keyboard
		# verbs are split MOVE/AIM (tab 0) + ACTIONS (tab 1) and the pad buttons are tab 2,
		# so no page ever exceeds 10 rows — every plate stays >=20px legible (vs the old flat
		# 16-row screen). Each row shows its current key/button (or "---" when UNBOUND); then
		# RESET CONTROLS + BACK. The focused-and-listening row shows a live "PRESS ..." prompt.
		var ritems: Array[Dictionary] = []
		var kb := _rebind_is_kb()
		for action in _rebind_tab_actions():
			var val: String
			if _rebind_action == action:
				val = "PRESS A KEY" if kb else "PRESS A BUTTON"
			elif kb:
				val = key_label(_kb_code(action))   # localized keycap for the player's layout
			else:
				var pb: int = main.pad_bind(action, _rebind_pad_dev)   # the row shows the ACTIVE player's bind
				val = pad_button_name(pb) if pb >= 0 else "UNBOUND"
			ritems.append({"id": action, "label": "%s: %s" % [rebind_label(action), val],
				"destructive": false, "grp": 0})
		# c1-18: the sticks aren't per-button rebindable, so the GAMEPAD tab carries SWAP STICKS
		# as an inline TOGGLE (not a capture row) — the accessible way a left-handed / adaptive-pad
		# player reassigns MOVE <-> AIM. It sits right where the "sticks are fixed" note is, so the
		# fixed-stick statement is no longer a dead end.
		if _rebind_tab == 2:
			var sw: bool = main._swap_sticks[_rebind_pad_dev]   # the ACTIVE player's own swap state
			ritems.append({"id": "swap_sticks",
				"label": "SWAP STICKS: %s" % ("ON" if sw else "OFF"),
				"destructive": false, "on": sw, "grp": 1})
		ritems.append({"id": "reset_controls", "label": "RESET CONTROLS", "destructive": true, "grp": 1})
		ritems.append({"id": "back", "label": "BACK", "destructive": false, "grp": 2})
		return ritems
	# c1-09: PAUSE no longer duplicates the settings rows — it fronts them through ONE
	# OPTIONS row that opens the dedicated screen (which then BACKs to PAUSE). RESUME /
	# OPTIONS / RESTART / QUIT TO TITLE, each its own group so the dividers separate them.
	# c3-14: the exit row reads "QUIT TO TITLE" — an explicit one-step exit VERB, so
	# leaving a run never means RESTART-then-TITLE or backing out. id stays "title" (the
	# _activate branch is keyed on it), only the label changes. Both cues resolve to the
	# id-derived "TITLE" identity when the plate is too tight for the full words: unarmed
	# degrades "QUIT TO TITLE  PRESS TWICE" to "TITLE PRESS TWICE" (never the misleading
	# "QUIT ..."); armed rides armed_verb "TITLE" (pinned by test_c3_08) to "TITLE  PRESS
	# AGAIN". So the confirm copy names the real destination in both states, never a bare
	# "QUIT" that reads like quit-to-desktop.
	# The two destructive actions get DISTINCT groups (2 / 3) so a divider actually splits
	# "restart this run" from "abandon it to the title" — they must never fuse into one slab.
	var pitems: Array[Dictionary] = [
		{"id": "resume", "label": "RESUME", "destructive": false, "grp": 0},
		{"id": "options", "label": "OPTIONS", "destructive": false, "grp": 1, "submenu": true},
	]
	pitems.append({"id": "restart", "label": "RESTART", "destructive": true, "grp": 2})
	pitems.append({"id": "title", "label": "QUIT TO TITLE", "destructive": true, "grp": 3})
	return pitems


# Pure, view-free helpers for the SFX/MUSIC volume model — one place the label,
# the segment bar, and both input paths agree on. A muted bus is level 0 no
# matter its stored volume_db; steps are clamped to 0..10 (0 == MUTED), so no
# input can ever wrap a nudge into an accidental mute. Extracted so the headless
# test can pin the mute-aware + boundary behavior without an AudioServer.
static func effective_vol(muted: bool, level: int) -> int:
	return 0 if muted else clampi(level, 0, 10)


static func vol_label(muted: bool, level: int) -> String:
	# 0 == MUTED is the whole contract, so a level of 0 reads MUTED even if the
	# mute flag hasn't been stamped yet (belt-and-suspenders with effective_vol).
	return "MUTED" if muted or level <= 0 else str(clampi(level, 0, 10))


static func step_level(cur: int, delta: int) -> int:
	return clampi(cur + delta, 0, 10)


# c1-18: the REBIND category tabs — labels + the verbs each shows. Tabs 0/1/3 are keyboard
# pages (kept <=8 rows so a plate stays >=20px); tab 2 is the gamepad buttons. Tab 3 (MENUS)
# rebinds the menu-navigation keys (additive over the immutable arrows/Enter/Esc fallback).
const REBIND_TABS := ["MOVE / AIM", "ACTIONS", "GAMEPAD", "MENUS"]
const REBIND_MOVE_AIM := ["move_up", "move_down", "move_left", "move_right",
	"aim_up", "aim_down", "aim_left", "aim_right"]
const REBIND_ACTIONS := ["fire", "grenade", "roll", "interact", "revive", "buy"]
const REBIND_MENUNAV := ["menu_up", "menu_down", "menu_left", "menu_right", "menu_confirm", "menu_cancel", "menu_help", "menu_next_tab"]


# c1-18: is the active tab a KEYBOARD page (true) or the GAMEPAD page (false)?
func _rebind_is_kb() -> bool:
	return _rebind_tab != 2


# c1-18: the ordered verbs shown on the active REBIND tab.
func _rebind_tab_actions() -> Array:
	match _rebind_tab:
		0: return REBIND_MOVE_AIM
		1: return REBIND_ACTIONS
		3: return REBIND_MENUNAV
	return main.PAD_DEFAULTS.keys()


# c1-18: the physical keycode a KEYBOARD-tab action currently holds — menu-nav actions read
# the menu-key map, gameplay verbs the gameplay map.
func _kb_code(action: String) -> int:
	return main.menu_bind(action) if action in REBIND_MENUNAV else main.bind(action)


# c1-18: apply a KEYBOARD-tab (re)bind to the right map and return the swapped verb (if any).
func _apply_kb_bind(action: String, code: int) -> String:
	if action in REBIND_MENUNAV:
		return main.rebind_menu_nav(action, code)
	return main.rebind(action, code)


# c1-18: the display label for a physical keycode — the keycap the player's CURRENT layout
# puts at that physical position (AZERTY 'A' reads "Q", etc.), so non-QWERTY users see their
# real key, not a QWERTY positional name. Falls back to the physical name when the display
# server can't map it (e.g. headless), and to "---" for UNBOUND.
static func key_label(physical: int) -> String:
	if physical == 0:
		return "UNBOUND"
	var logical := DisplayServer.keyboard_get_keycode_from_physical(physical)
	if logical != 0:
		return OS.get_keycode_string(logical)
	return OS.get_keycode_string(physical)


# c1-18: human-readable name for a rebindable verb — the REBIND row label prefix.
# Pure + static so the screen wording is single-sourced (and headless-assertable).
static func rebind_label(action: String) -> String:
	match action:
		"move_up": return "MOVE UP"
		"move_down": return "MOVE DOWN"
		"move_left": return "MOVE LEFT"
		"move_right": return "MOVE RIGHT"
		"aim_up": return "AIM UP"
		"aim_down": return "AIM DOWN"
		"aim_left": return "AIM LEFT"
		"aim_right": return "AIM RIGHT"
		"fire": return "FIRE"
		"grenade": return "GRENADE"
		"roll": return "ROLL"
		"interact": return "INTERACT"
		"revive": return "REVIVE"
		"buy": return "SUPPLY WHEEL"
		"menu_up": return "MENU UP"
		"menu_down": return "MENU DOWN"
		"menu_left": return "MENU LEFT"
		"menu_right": return "MENU RIGHT"
		"menu_confirm": return "MENU CONFIRM"
		"menu_cancel": return "MENU BACK"
		"menu_help": return "HOW TO PLAY"
		"menu_next_tab": return "SWITCH SECTION"
	return action.to_upper()


# c1-18: readable name for a JOY_BUTTON_* index — the GAMEPAD-tab row value. Pure + static
# so the screen wording is single-sourced (and headless-assertable). Uses generic
# face-button letters (portable across pads); the rebind screen's header names the layout.
static func pad_button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A: return "A / CROSS"
		JOY_BUTTON_B: return "B / CIRCLE"
		JOY_BUTTON_X: return "X / SQUARE"
		JOY_BUTTON_Y: return "Y / TRIANGLE"
		JOY_BUTTON_LEFT_SHOULDER: return "LB / L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB / R1"
		JOY_BUTTON_BACK: return "BACK / SELECT"
		JOY_BUTTON_START: return "START"
		JOY_BUTTON_LEFT_STICK: return "L-STICK"
		JOY_BUTTON_RIGHT_STICK: return "R-STICK"
		JOY_BUTTON_DPAD_UP: return "DPAD UP"
		JOY_BUTTON_DPAD_DOWN: return "DPAD DOWN"
		JOY_BUTTON_DPAD_LEFT: return "DPAD LEFT"
		JOY_BUTTON_DPAD_RIGHT: return "DPAD RIGHT"
	return "BUTTON %d" % button


func _settings_rows() -> Array[Dictionary]:
	# "on" drives the row's state dot (filled/hollow — position+shape carry it,
	# not hue alone) so toggle state reads without parsing the label tail.
	# SFX/MUSIC are stepped 0..10 levels (8-of-9 panel consensus), not mute
	# toggles: "vol" drives a 10-segment bar where the state dot would sit.
	# The row is mute-AWARE at the source of truth (AudioServer.is_bus_mute), not
	# inferred from the number: a muted bus reads "MUTED" with an EMPTY bar (vol 0)
	# even if its volume_db is still nonzero, so the surface can never show a full
	# green bar while the game is silent. Enter and ◄/► both move this one value.
	var sfx_muted: bool = _bus_off("SFX")
	var mus_muted: bool = _bus_off("Music")
	var sv: int = effective_vol(sfx_muted, main._bus_vol("SFX"))
	var mv: int = effective_vol(mus_muted, main._bus_vol("Music"))
	# c1-09: four labelled groups — AUDIO (grp 1), HAPTICS (grp 2), ACCESSIBILITY
	# (grp 3), DISPLAY (grp 4) — so the divider rules + group_header captions read as
	# sections. REDUCE MOTION and COLORBLIND carry their ON/OFF in the row label AND the
	# state dot, and are echoed in the header a11y summary, so their live state reads in
	# both places. DISPLAY is a real toggle row now (not F11-only): every persisted
	# setting can be reviewed AND changed from the dedicated screen.
	return [
		# c3-04: "muted" is carried EXPLICITLY (not inferred from vol == 0 downstream) so
		# the readout and the slashed-bar off marker key off the real bus-mute state, and
		# the label reads "SFX: MUTED" (never "SFX: 8") the instant the bus is off — the
		# numeric level can never contradict the off marker. Confirm/L/R only STEP this
		# level (see _step_vol); muting is stepping down to 0, never a surprise confirm-toggle.
		# c4-01: vol_label resolves the two-mental-models bug AT THE ROW ITSELF — a muted bus
		# reads the WORD "MUTED" in place of a level, so the old "SFX: 7 with a silent bus"
		# contradiction can't occur. This word is the primary cue; the icon/bar/footer reinforce it.
		{"id": "sfx", "label": "SFX: %s" % vol_label(sfx_muted, sv), "destructive": false, "vol": sv, "muted": sfx_muted, "grp": 1},
		{"id": "music", "label": "MUSIC: %s" % vol_label(mus_muted, mv), "destructive": false, "vol": mv, "muted": mus_muted, "grp": 1},
		{"id": "rumble", "label": "RUMBLE: %s" % ("ON" if main._rumble_on else "OFF"), "destructive": false, "on": main._rumble_on, "grp": 2},
		{"id": "motion", "label": "REDUCE MOTION: %s" % ("ON" if main._motion < 0.5 else "OFF"), "destructive": false, "on": main._motion < 0.5, "grp": 3},
		{"id": "colorblind", "label": "COLORBLIND: %s" % ("ON" if main.colorblind else "OFF"), "destructive": false, "on": main.colorblind, "grp": 3},
		{"id": "assist", "label": "ASSIST (2-HIT): %s" % ("ON" if main._assist else "OFF"), "destructive": false, "on": main._assist, "grp": 3},
		# c1-19: DISPLAY is a submenu OPENER (chevron), not an inline control — the OPTS screen is
		# at its 10-row legibility cap, so the two explicit DISPLAY controls (FULLSCREEN toggle +
		# WINDOW SCALE stepper) live on their own roomy sub-screen. The row still shows the LIVE
		# mode at a glance ("FULLSCREEN" / "WINDOWED 2x"), so nothing is hidden behind the opener.
		{"id": "display", "label": display_label(main._fullscreen, main._win_scale_norm()), "destructive": false, "grp": 4, "submenu": true},
	]


# c1-19: the OPTS DISPLAY-row summary — the LIVE mode shown on the opener row (and reused by the
# a11y readout wording): "FULLSCREEN" or "WINDOWED Nx". Pure + static so a label test can pin it.
static func display_label(fullscreen: bool, win_scale: int) -> String:
	return "FULLSCREEN" if fullscreen else "WINDOWED %dx" % win_scale


# c1-19: the two EXPLICIT DISPLAY controls, split apart so neither is overloaded — FULLSCREEN is a
# plain ON/OFF toggle (one press reaches fullscreen) and WINDOW SCALE is an independent 1x..Nx
# stepper. Pure + static so the sub-screen wording is single-sourced and headless-assertable.
static func fullscreen_label(on: bool) -> String:
	return "FULLSCREEN: %s" % ("ON" if on else "OFF")


static func winscale_label(scale: int) -> String:
	# Just the scale — short, never ellipsizes on the 640x360 plate (well under the widest toggle
	# "ASSIST (2-HIT): OFF" budget). Windowed it's the live effective scale; fullscreen it's the
	# stored preference. When that preference can't fit the current display, the honesty lives in the
	# DISPLAY subtitle ("LIMITED TO Nx ON THIS DISPLAY"), which has the full screen width for words.
	return "WINDOW SCALE: %dx" % scale


# c1-19: the DISPLAY sub-screen subtitle — the words that keep the short WINDOW SCALE label honest.
# Windowed: names both controls. Fullscreen: if the stored preference can't fit the current display
# (effective < pref) it states the limit in plain language ("LIMITED TO 3x ON THIS DISPLAY"), else it
# notes the scale applies on return to windowed. Full screen width for text, so it can be verbose
# where the plate label can't. Pure + static so every wording is headless-pinnable.
static func disp_subtitle(fullscreen: bool, pref := -1, effective := -1) -> String:
	if not fullscreen:
		return "FULLSCREEN & WINDOW SCALE"
	if pref >= 0 and effective >= 0 and effective != pref:
		return "LIMITED TO %dx ON THIS DISPLAY" % effective
	return "WINDOW SCALE APPLIES IN WINDOWED MODE"


func _items() -> Array[String]:
	var out: Array[String] = []
	for item in _menu_items():
		out.append(item["label"])
	return out


# Pause-menu indices that discard the run and need a confirm press.
func _is_destructive(i: int) -> bool:
	return _menu_items()[i]["destructive"]


# c1-08: the on-plate wording for a destructive (run-ending) row, chosen against
# the ACTUAL drawable width `avail` (px) so the cue can never ellipsize away on the
# ~190px plate. Pure + static so a layout test can pin the fit for every row.
#   pre-armed: "<NAME>  PRESS TWICE" — states the two-press contract up front and
#              keeps the action name (was a lone "!" that read like plain emphasis).
#   armed:     "<VERB>  PRESS AGAIN" where it fits — the verb keeps WHICH action is
#              one press from firing — degrading (single space -> "<VERB>: AGAIN" ->
#              bare "PRESS AGAIN") only as far as the plate forces.
# Each candidate is tried widest-first; the first that fits `avail` wins.
# c3-17: the canonical destructive warning cue — ONE source of truth shared by
# destructive_label (which appends it) and destructive_cue_tail (which preserves it under
# truncation), so the two can never drift and a wording/localization edit lands in one place.
const DESTR_CUE_ARMED := "PRESS AGAIN"
const DESTR_CUE_PREARMED := "PRESS TWICE"
const DESTR_CUE_ARMED_TIGHT := ": AGAIN"   # narrow-plate armed tier: "<VERB>: AGAIN"
const DESTR_CUE_MARK := "!"                 # minimal floor cue when no spelled-out cue fits


# c3-17: the load-bearing warning suffix of a destructive_label string — the part truncation
# must NEVER eat. Matches ONLY the cue phrases destructive_label itself appends, single-sourced
# in the DESTR_CUE_* constants (never a guessed trailing token), so a localized build whose cues
# live in those same constants keeps working with zero heuristics. Returns the cue WITH its
# leading separator (a space, or none before ": AGAIN") so a trimmed NAME reads "RES… PRESS AGAIN"
# (the ellipsis never butts the cue). Returns "" for a bare cue (label IS the cue — no separable
# head) or any unrecognized tail; the warn "!" floor in _ellipsize is the safety net that still
# marks those rows destructive.
static func destructive_cue_tail(label: String, armed: bool) -> String:
	# Pre-armed labels only ever end with "PRESS TWICE"; armed labels end with "PRESS AGAIN" or the
	# tightened ": AGAIN" tier — so only the armed set includes DESTR_CUE_ARMED_TIGHT.
	var cues: Array[String] = [DESTR_CUE_PREARMED]
	if armed:
		cues = [DESTR_CUE_ARMED, DESTR_CUE_ARMED_TIGHT]
	for cue in cues:
		if label.ends_with(cue) and label.length() > cue.length():
			var i := label.length() - cue.length()
			return label.substr(i - 1) if label[i - 1] == " " else label.substr(i)
	return ""


static func destructive_label(name: String, verb: String, armed: bool, font: Font, avail: float) -> String:
	# Candidates run widest -> narrowest; the first that FITS `avail` wins. Both the
	# action identity (name/verb, always LEADING) and the explicit two-press cue
	# ("PRESS TWICE" pre-armed / "PRESS AGAIN" armed) ride every tier until the plate
	# is too tight for both — and the CUE is the last thing dropped, so it is never
	# ellipsized to nonsense. The abbreviated tiers keep the tail genuinely fitting on
	# a narrow plate instead of returning an overflowing string. On the real ~190px
	# plate a name/verb + full-cue tier always wins (RESTART/TITLE/QUIT verified in
	# the layout test) — "PRESS TWICE" states the contract outright, unlike the old
	# lone "!" that read like emphasis and made the row look single-press.
	# The abbreviated pre-armed tier drops to the id-derived VERB identity, not the
	# label's leading word: for "QUIT TO TITLE" the label's first word ("QUIT") reads
	# like quit-to-desktop, while the verb ("TITLE") names the real destination and
	# matches the armed cue. For every other destructive row the verb's leading word
	# equals the label's (RESTART/QUIT/RESET), so this only sharpens QUIT TO TITLE.
	var short_name := verb.split(" ")[0]
	var forms: Array[String]
	if armed:
		# c3-08: the verb rides with the cue as long as it fits ("<VERB>: AGAIN" is terse
		# but unambiguous WITH the verb present) so the armed row never loses WHICH action
		# is one press from firing. If a multi-word verb won't fit, keep at least its leading
		# word before falling through - the identity (or its leading word) is dropped LAST,
		# only when the plate has no room, to the full "PRESS AGAIN" (never a bare "AGAIN",
		# which reads ambiguously). On the real 170px armed plate TITLE/QUIT keep the full
		# "<VERB>  PRESS AGAIN"; RESTART tightens to "RESTART: AGAIN"; the long RESET rows
		# fall to their leading word "RESET: AGAIN" - always a verb, never a bare cue. These
		# exact tiers are pinned per row in test_c3_08_* so a font/plate edit can't silently
		# strip the identity.
		var short_verb := verb.split(" ")[0]
		forms = ["%s  %s" % [verb, DESTR_CUE_ARMED], "%s %s" % [verb, DESTR_CUE_ARMED], "%s%s" % [verb, DESTR_CUE_ARMED_TIGHT]]
		if short_verb != verb:
			forms.append("%s%s" % [short_verb, DESTR_CUE_ARMED_TIGHT])
		forms.append(DESTR_CUE_ARMED)
	else:
		forms = ["%s  %s" % [name, DESTR_CUE_PREARMED], "%s %s" % [name, DESTR_CUE_PREARMED]]
		if short_name != name:
			forms.append("%s %s" % [short_name, DESTR_CUE_PREARMED])
		forms.append(DESTR_CUE_PREARMED)
	if font == null:
		return forms[0]
	for f in forms:
		if font.get_string_size(f, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x <= avail:
			return f
	# MINIMUM SUPPORTED WIDTH: the narrowest form is the bare cue ("PRESS TWICE" ~102px
	# / "PRESS AGAIN" ~99px at 11px). The only caller draws on the fixed BTN.x=222 plate
	# (avail 184 pre / 170 armed), so a fitting identity+cue tier ALWAYS wins there and
	# this floor is never reached in production. Below ~102px avail the cue is returned
	# as-is and _ellipsize would trim its tail — an unsupported, sub-word plate.
	return forms[forms.size() - 1]


# c3-08: the armed-row verb is derived from the row id, NOT a hand-authored "verb"
# field — every destructive row's id already uppercases to exactly the verb we want
# ("restart"->RESTART, "title"->TITLE, "quit"->QUIT, "reset_defaults"->RESET DEFAULTS,
# "reset_controls"->RESET CONTROLS), so a parallel field would only be a second source
# of truth to drift. One convention, one helper, shared by _draw and the layout test.
static func armed_verb(item: Dictionary) -> String:
	return String(item.get("id", "")).to_upper().replace("_", " ")


# Row id → Modern Menus icon key. Only clean matches — no icon beats a
# stretched metaphor. Sound toggles reflect their live bus state.
func _row_icon(id: String) -> String:
	match id:
		"resume", "campaign": return "mi_play"
		"hall": return "mi_trophy"
		"howto": return "mi_book"
		"setup": return "mi_settings"   # c2-04: gear cue signals the hub also holds OPTIONS/INFO, not just run config
		"hard": return "mi_combat"
		"coop": return "mi_controller"
		# c4-01: the row icon flips to the MUTED (slashed-speaker) variant off the SAME
		# AudioServer.is_bus_mute state the label + bar read, so the silent bus reinforces
		# across three channels at once — no icon can show "sound on" while the bus is muted.
		"sfx": return "mi_snd_off" if _bus_off("SFX") else "mi_snd_on"
		"music": return "mi_mus_off" if _bus_off("Music") else "mi_mus_on"
		"options": return "mi_settings"
		"controls": return "mi_controller"
		"reset_controls": return "mi_reload"
		"info": return "mi_book"
		"display", "fullscreen", "winscale": return "mi_camera"
		"restart", "reset_defaults": return "mi_reload"
		"title": return "mi_home"
		"rumble": return "mi_controller"
		"watch": return "mi_camera"
		"back": return "mi_back"
		"endless": return "mi_combat"
		"daily": return "mi_timer"
		"quit": return "mi_cancel"
	return ""


# c1-18: handle ONE input while capturing a bind for _rebind_action. Returns true if it
# consumed the event. While capturing it swallows EVERY press so nothing leaks to nav, and
# acts only on the ACTIVE tab's device: a key on a KEYBOARD tab, a pad button on the GAMEPAD
# tab. ESC / pad START cancels (keeps the old bind). CLEAR to UNBOUND has a path on BOTH
# devices: keyboard DELETE/BACKSPACE, or (gamepad-only) pressing the button the verb is
# ALREADY bound to. A collision with another verb SWAPS (see main.apply_bind) and reports it.
func _rebind_capture(ev: InputEvent) -> bool:
	var kb := _rebind_is_kb()
	var handled := false
	# c1-18: only the pad WHOSE sub-tab is open may edit it — every pad event is filtered by
	# ev.device against _rebind_pad_dev, so a P2 controller press can't rewrite P1's layout (or
	# vice versa) while P1's GAMEPAD sub-tab is showing. Keyboard events carry no meaningful
	# device, so they still edit whichever KEYBOARD tab is up.
	var pad_ev: bool = not kb and ev is InputEventJoypadButton and ev.pressed and ev.device == _rebind_pad_dev
	# CANCEL keeps the old bind. Keyboard ESC is the universal one; on the pad it is START — ONE
	# reserved button that reliably aborts a listen. (The old LB+RB chord was unusable: pressing
	# the first shoulder committed it as the bind before the second shoulder could arrive, so the
	# chord never formed. START never has that race.) START is therefore the only pad button NOT
	# bindable; the d-pad and every face/shoulder button are still free to bind.
	var pad_cancel: bool = pad_ev and ev.button_index == JOY_BUTTON_START
	if (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE) \
			or pad_cancel:
		_end_capture()
		main._sfx.play("deny", -8.0)
		_notice("CANCELLED")
		handled = true
	elif ev is InputEventKey and ev.pressed and not ev.echo \
			and (ev.keycode == KEY_DELETE or ev.keycode == KEY_BACKSPACE):
		var lbl := rebind_label(_rebind_action)
		if kb:
			_apply_kb_bind(_rebind_action, 0)
		else:
			main.rebind_pad(_rebind_action, -1, _rebind_pad_dev)
		_end_capture()
		main._sfx.play("buy", -8.0)
		_flash_setting()
		_notice("%s CLEARED" % lbl)
		handled = true
	elif kb and ev is InputEventKey and ev.pressed and not ev.echo:
		# Store the PHYSICAL keycode (fallback to logical) so gameplay's physical reads
		# honor it regardless of layout — the same basis _gather_inputs uses. Menu-nav
		# actions route to the menu-key map; everything else to the gameplay map.
		var pk: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		var role := _immutable_menu_role(pk)
		if _rebind_action in REBIND_MENUNAV and role != "" and role != _rebind_action:
			# REJECT: this key is an IMMUTABLE menu key for a DIFFERENT action, so binding it
			# here would fire two menu commands on one press (the fixed role AND this one).
			# Keep the old bind and tell the player why.
			_end_capture()
			main._sfx.play("deny", -8.0)
			_notice("%s IS A FIXED MENU KEY - PICK ANOTHER" % key_label(pk))
		else:
			var swapped: String = _apply_kb_bind(_rebind_action, pk)
			# A menu-nav rebind never needs the "also a menu key" heads-up (that IS the point).
			var note := "" if _rebind_action in REBIND_MENUNAV else _reserved_key_note(pk)
			_commit_capture(swapped, note)
		handled = true
	elif pad_ev:
		# Gamepad (re)bind on the ACTIVE player's layout (device already matched above). CLEAR is
		# an explicit gesture that frees the d-pad for binding: pressing the button the verb
		# ALREADY holds toggles it UNBOUND (keyboard DEL clears too). START never reaches here
		# (it is the cancel above). Any OTHER button (re)binds, swapping on collision within this
		# player's map only.
		if ev.button_index == main.pad_bind(_rebind_action, _rebind_pad_dev):
			var plbl := rebind_label(_rebind_action)
			main.rebind_pad(_rebind_action, -1, _rebind_pad_dev)
			_end_capture()
			main._sfx.play("buy", -8.0)
			_flash_setting()
			_notice("%s CLEARED" % plbl)
		else:
			var swapped_pad: String = main.rebind_pad(_rebind_action, ev.button_index, _rebind_pad_dev)
			_commit_capture(swapped_pad, "")
		handled = true
	# Swallow every press-type event while capturing — keys, pad buttons, AND mouse clicks —
	# so a stray press can never fall through to row/tab navigation mid-capture.
	if handled or (ev is InputEventKey and ev.pressed) \
			or (ev is InputEventJoypadButton and ev.pressed) \
			or (ev is InputEventMouseButton and ev.pressed):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		return true
	return false


func _end_capture() -> void:
	_rebind_action = ""
	_mark_dirty()


func _commit_capture(swapped: String, reserved: String) -> void:
	var verb := rebind_label(_rebind_action)
	_end_capture()
	main._sfx.play("buy", -8.0)
	_flash_setting()
	if swapped != "":
		_notice("SWAPPED WITH %s" % rebind_label(swapped))
	elif reserved != "":
		_notice(reserved)
	else:
		_notice("%s SET" % verb)


func _notice(msg: String) -> void:
	_rebind_msg = msg
	_rebind_msg_t = 2.5


# c1-18: keys the menus themselves use (confirm / nav) get a non-blocking heads-up when
# bound to a verb — the bind still applies (menu context and gameplay context never read
# at the same time), but the player is told there's an overlap. ESC can't reach here (it
# cancels capture), so it can never be stolen from the universal menu-cancel gesture.
func _reserved_key_note(pk: int) -> String:
	if pk in [KEY_ENTER, KEY_KP_ENTER, KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_W, KEY_S]:
		return "SET - NOTE: ALSO A MENU KEY"
	return ""


# c1-18: the IMMUTABLE menu-nav role a physical key always serves (or "" for none). A menu
# action may only be (re)bound to a key whose fixed role is empty or ITS OWN — otherwise one
# press would fire two menu commands (e.g. MENU CONFIRM on Down would navigate AND activate).
# Delegates to main's shared static so the capture reject and the post-swap sanitize agree.
func _immutable_menu_role(pk: int) -> String:
	return main.immutable_menu_role(pk)


func _unhandled_input(ev: InputEvent) -> void:
	# c1-18: F10 is the GLOBAL recovery gesture — from ANY menu screen (even mid-capture) it
	# reverts EVERY control (keyboard, both pads, menu keys) to ship defaults. This is the
	# documented escape hatch that makes the rest of the rebinding safe: no remap of the menu
	# keys, a swapped verb, or a pad bound into a corner can ever strand a player, because this
	# one hardcoded key is always waiting to hand them a clean slate. It is intentionally NOT
	# rebindable and NOT a gameplay key, so it can never be captured or shadowed.
	if mode != Mode.HIDDEN and ev is InputEventKey and ev.pressed and not ev.echo \
			and ev.keycode == KEY_F10:
		main.reset_binds()
		_end_capture()   # abort any listen in progress
		if mode == Mode.REBIND:
			_flash_all_settings()
		_notice("ALL CONTROLS RESET TO DEFAULT (F10)")
		main._sfx.play("buy", -6.0)
		var vpf := get_viewport()
		if vpf != null:
			vpf.set_input_as_handled()
		return
	# c1-18: while the REBIND screen is listening, the NEXT key/button IS the new bind —
	# it must not also navigate the menu. Consumed here, before nav. On the KEYBOARD tab a
	# key rebinds; on the GAMEPAD tab a pad button rebinds. ESC (or pad START) cancels
	# and keeps the old bind; DELETE (or pressing the button the verb already holds) clears it to
	# UNBOUND. Menu nav (arrows/WASD/Enter/Esc) is NEVER remapped and F10 always resets, so
	# capture can't strand a player without a way out.
	if mode == Mode.REBIND and _rebind_action != "":
		if _rebind_capture(ev):
			return
	# c3-10: F1 is the direct HOW TO PLAY shortcut — from any menu screen it jumps straight to
	# the help pages (the footer/legend advertises "F1 HOW TO"). Placed AFTER rebind capture so a
	# listen can still bind F1 and it never fires mid-capture; skipped if help is already open.
	if mode != Mode.HIDDEN and mode != Mode.HOWTO and ev is InputEventKey \
			and ev.pressed and not ev.echo \
			and (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode) == _help_code():
		open(Mode.HOWTO)
		main._sfx.play("pickup", -12.0)
		var vpf1 := get_viewport()
		if vpf1 != null:
			vpf1.set_input_as_handled()
		return
	# c1-18: on the GAMEPAD tab, ◄/► (keyboard A/D/arrows or pad d-pad L/R) switches which
	# PLAYER's layout is being edited (P1 <-> P2). The two pad maps are independent, so a
	# left-handed or differently-abled P2 remaps without touching P1. Handled before nav so the
	# horizontal press only swaps the player, never scrolls a row.
	if mode == Mode.REBIND and _rebind_action == "" and _rebind_tab == 2:
		var dev_step := 0
		var to_dev := -1
		if ev is InputEventKey and ev.pressed and not ev.echo:
			match (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode):
				KEY_A, KEY_LEFT: dev_step = -1
				KEY_D, KEY_RIGHT: dev_step = 1
		elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_DPAD_LEFT:
			dev_step = -1
		elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_DPAD_RIGHT:
			dev_step = 1
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			for pd in 2:
				if _rebind_pad_dev_rect(pd).has_point(ev.position):
					to_dev = pd
		if dev_step != 0 or (to_dev >= 0 and to_dev != _rebind_pad_dev):
			var vpd := get_viewport()
			if vpd != null:
				vpd.set_input_as_handled()
			_rebind_pad_dev = to_dev if to_dev >= 0 else wrapi(_rebind_pad_dev + dev_step, 0, 2)
			_rebind_msg = ""
			_rebind_msg_t = 0.0
			main._sfx.play("pickup", -14.0, 1.3)
			_mark_dirty()
			return
	# c1-18: the menu_next_tab key (kb, default TAB) or a shoulder (pad) cycles the MOVE/AIM ->
	# ACTIONS -> GAMEPAD category tabs while idle. Shoulders step both directions; the key cycles
	# forward. Handled before nav so the toggle can't also move the cursor. c3-10: matches the LIVE
	# menu_next_tab bind (physical), so a rebound section key drives the switch AND the footer stamp.
	if mode == Mode.REBIND and _rebind_action == "":
		var step := 0
		var to_tab := -1
		if ev is InputEventKey and ev.pressed and not ev.echo and main != null \
				and (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode) == main.menu_bind("menu_next_tab"):
			step = 1
		elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
		elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			for d in REBIND_TABS.size():
				if _rebind_tab_rect(d).has_point(ev.position):
					to_tab = d
		if step != 0 or (to_tab >= 0 and to_tab != _rebind_tab):
			var vpt := get_viewport()
			if vpt != null:
				vpt.set_input_as_handled()
			_rebind_tab = to_tab if to_tab >= 0 else wrapi(_rebind_tab + step, 0, REBIND_TABS.size())
			sel = 0   # different row set per tab — land on the first verb
			_rebind_msg = ""
			_rebind_msg_t = 0.0
			main._sfx.play("pickup", -14.0, 1.3)
			_mark_dirty()
			return
	var move := 0
	var hmove := 0
	var act := false
	var back := false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		# c1-18: match the PHYSICAL keycode (WASD position), not the logical one, so menu nav
		# lands on the same physical keys as gameplay and the stored menu binds — consistent
		# on AZERTY/QWERTZ. For arrows/Enter/Space/Esc physical == logical, so only the WASD
		# positions change (correctly) on non-QWERTY layouts.
		match (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode):
			KEY_W, KEY_UP:
				move = -1
				_key_move = -1
				_key_rep = 0.35   # same hold-repeat cadence as the stick
			KEY_S, KEY_DOWN:
				move = 1
				_key_move = 1
				_key_rep = 0.35
			# ◄/► (A/D or arrows) feed hmove -> _nav: on a SFX/MUSIC row it steps
			# the volume down/up, and in HALL it cycles the ALL/CAMPAIGN/ENDLESS
			# filter — full parity with the pad d-pad (keyboard moves the level and
			# the Hall filter, not just the cursor).
			KEY_A, KEY_LEFT:
				hmove = -1
				_key_hmove = -1
				_key_hrep = 0.35   # held left auto-repeats the step (volume rows only)
			KEY_D, KEY_RIGHT:
				hmove = 1
				_key_hmove = 1
				_key_hrep = 0.35
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: act = true   # numpad Enter redeploys from the debrief; menus must match
			KEY_ESCAPE: back = true
		# c1-18: ADDITIVE rebindable menu-nav — a player's remapped menu keys work ON TOP of
		# the immutable defaults above (which always work, so the menus can never be locked
		# out). Physical-key compared, matching how the binds are stored.
		if main != null:
			var pkm: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			if move == 0 and pkm == main.menu_bind("menu_up"):
				move = -1
				_key_move = -1
				_key_rep = 0.35
			elif move == 0 and pkm == main.menu_bind("menu_down"):
				move = 1
				_key_move = 1
				_key_rep = 0.35
			if hmove == 0 and pkm == main.menu_bind("menu_left"):
				hmove = -1
				_key_hmove = -1
				_key_hrep = 0.35
			elif hmove == 0 and pkm == main.menu_bind("menu_right"):
				hmove = 1
				_key_hmove = 1
				_key_hrep = 0.35
			if not act and pkm == main.menu_bind("menu_confirm"):
				act = true
			if not back and pkm == main.menu_bind("menu_cancel"):
				back = true
	elif ev is InputEventKey and not ev.pressed:
		# Release clears the hold-repeat latch (repeat itself runs in _process). Physical-
		# matched to mirror the press branch above.
		match (ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode):
			KEY_W, KEY_UP:
				if _key_move == -1:
					_key_move = 0
			KEY_S, KEY_DOWN:
				if _key_move == 1:
					_key_move = 0
			KEY_A, KEY_LEFT:
				if _key_hmove == -1:
					_key_hmove = 0
			KEY_D, KEY_RIGHT:
				if _key_hmove == 1:
					_key_hmove = 0
		# c1-18: a REBOUND menu-nav key must clear its own latch too, or one press of a
		# custom key auto-repeats forever (the press set the latch above). Physical-matched.
		if main != null:
			var pkr: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			if _key_move == -1 and pkr == main.menu_bind("menu_up"):
				_key_move = 0
			elif _key_move == 1 and pkr == main.menu_bind("menu_down"):
				_key_move = 0
			if _key_hmove == -1 and pkr == main.menu_bind("menu_left"):
				_key_hmove = 0
			elif _key_hmove == 1 and pkr == main.menu_bind("menu_right"):
				_key_hmove = 0
	elif ev is InputEventJoypadButton and ev.pressed:
		match ev.button_index:
			JOY_BUTTON_DPAD_UP: move = -1
			JOY_BUTTON_DPAD_DOWN: move = 1
			JOY_BUTTON_DPAD_LEFT: hmove = -1
			JOY_BUTTON_DPAD_RIGHT: hmove = 1
			JOY_BUTTON_A: act = true
			JOY_BUTTON_B:
				# Console convention: B = back/cancel — but ONLY inside menus.
				# In gameplay B is ROLL; letting it through here made every dodge
				# open the pause menu (mode==HIDDEN + back → PAUSE).
				if mode != Mode.HIDDEN:
					back = true
			JOY_BUTTON_START:
				# START confirms on the title (redeploy muscle memory from the
				# debrief); elsewhere it stays the pause/back toggle.
				if mode == Mode.TITLE:
					act = true
				else:
					back = true
	elif ev is InputEventJoypadMotion and (ev.axis == JOY_AXIS_LEFT_Y or ev.axis == JOY_AXIS_LEFT_X):
		# Analog-stick menu nav: fire ONE step when the axis crosses 0.55, re-arm
		# below 0.45 (a stick resting at 0.3–0.55 used to lock nav). Latch is
		# per-axis; the frame stamp keeps a diagonal from firing both axes at once.
		var v: float = ev.axis_value
		var dir := 1 if v > 0.55 else (-1 if v < -0.55 else 0)
		var vertical: bool = ev.axis == JOY_AXIS_LEFT_Y
		var latch := _stick_y if vertical else _stick_x
		if absf(v) < 0.45:
			latch = 0
		elif dir != 0 and latch == 0:
			latch = dir
			_stick_rep = 0.35
			if Engine.get_process_frames() != _nav_frame:
				_nav_frame = Engine.get_process_frames()
				if vertical:
					move = dir
				else:
					hmove = dir
		if vertical:
			_stick_y = latch
		else:
			_stick_x = latch
		# Both axes back in the deadband = fresh gesture: clear the one-nav-per-
		# frame stamp so a released-then-repushed diagonal can't wedge nav.
		if _stick_x == 0 and _stick_y == 0:
			_nav_frame = -1

	if mode == Mode.HIDDEN:
		if back:
			open(Mode.PAUSE)
			main._sfx.play("tank_board", -8.0)
		return
	# Mouse drives menus too: hover selects, LMB activates — mouse-aim players
	# shouldn't have to switch devices to press RESUME. Same geometry as _draw.
	if ev is InputEventMouseMotion:
		# Only REAL motion selects — a parked mouse must not fight pad/kb nav.
		# Gate on any nonzero delta, not length > 2: a parked pointer emits
		# zero-delta events (still ignored), but a slow deliberate drag moves
		# ~1px/event and used to be swallowed, locking a mouse-only player out of
		# selecting one row at a time.
		if ev.relative != Vector2.ZERO:
			# Hall filter tabs get hover feedback too — they were click-only,
			# the lone interactive surface with zero mouse cue (rows hover-select,
			# arrows pulse; the file's own parity invariant, line ~317).
			if mode == Mode.HALL:
				var ht := -1
				var tabs := _hall_tab_rects()
				for ti in tabs.size():
					if tabs[ti].has_point(ev.position):
						ht = ti
				if ht != _tab_hover:
					_tab_hover = ht
					_mark_dirty()
				# PREV/NEXT hover parity with the tabs (shared with _refresh_page_hover so a
				# page/filter change re-evaluates a still cursor the same way a move does).
				_last_ptr = ev.position
				var ph := _page_hover_at(ev.position)
				if ph != _page_hover:
					_page_hover = ph
					_mark_dirty()
			if mode == Mode.HOWTO:
				# c2-02: HOW-TO page tabs get the same hover cue as HALL's filter tabs
				# (they share _tab_hover — only one screen is live at a time).
				var ht := -1
				var htabs := _howto_tab_rects()
				for ti in htabs.size():
					if htabs[ti].has_point(ev.position):
						ht = ti
				if ht != _tab_hover:
					_tab_hover = ht
					_mark_dirty()
				# c4-06: hover cue for the ENDLESS PREV/NEXT chevrons — only a LIVE side
				# lights (a boundary chevron can't page, so it never previews as clickable).
				var nh := -1
				if _howto_page == HOWTO_ENDLESS_TAB and _endless_pages() > 1:
					var nvr := _howto_endless_nav_rects()
					var ep := _endless_page()
					for side in range(2):
						var live_side := ep > 0 if side == 0 else ep < _endless_pages() - 1
						if live_side and nvr[side].has_point(ev.position):
							nh = side
				if nh != _howto_nav_hover:
					_howto_nav_hover = nh
					_mark_dirty()
			var hrow := _row_at(ev.position)
			if hrow >= 0 and hrow != sel:
				# Full feedback parity: funnel the hover through _nav so it plays
				# the nav sfx, clears the rail pulse, and disarms an armed _confirm
				# audibly, exactly like pad/kb/wheel. The old inline sel = hrow
				# silently yanked selection and killed a QUIT/RESTART arm on a
				# bumped mouse, with no sound and no cue.
				_nav(hrow - sel, 0)
		return
	if ev is InputEventMouseButton:
		# Menus swallow EVERY click, hit or miss, press or release — a stray
		# click through an open menu must never bleed into gameplay. (Guarded so a
		# not-in-tree menu — the headless input tests — is a no-op here, not a crash.)
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
		if not ev.pressed:
			return
		_last_ptr = ev.position   # keep the pointer fresh so a click-driven page change refreshes hover correctly
		if ev.button_index == MOUSE_BUTTON_LEFT:
			# Hall filter tabs are clickable — they were the one visible control
			# a mouse-only player couldn't operate (every other surface has
			# hover/click/wheel parity).
			if mode == Mode.HALL:
				var tabs := _hall_tab_rects()
				for ti in tabs.size():
					if tabs[ti].has_point(ev.position):
						if ti != _hall_filter:
							_hall_filter = ti
							_hall_page = 0   # fresh filtered list ALWAYS lands on page 1 (the counter's "OF N" total then matches this tab)
							_filter_pulse = 0.0 if main._motion < 0.5 else 1.0
							_refresh_page_hover()   # page reset to 0 disables PREV under a still cursor
							main._sfx.play("pickup", -14.0, 1.3)
						_mark_dirty()
						return
			if mode == Mode.HOWTO:
				# c2-02: click a page tab to jump to it — mouse parity with left/right.
				var htabs := _howto_tab_rects()
				for ti in htabs.size():
					if htabs[ti].has_point(ev.position):
						if ti != _howto_page:
							_howto_page = ti
							_howto_endless_page = 0   # c4-06: clicking the ENDLESS tab always lands on its first roster page
							_howto_nav_hover = -1   # leaving/entering a tab drops any stale chevron hover
							main._sfx.play("pickup", -14.0, 1.3)
						_mark_dirty()
						return
				# c4-06: the in-page PREV/NEXT chevrons page the ENDLESS roster — the ONE
				# control for its two halves now that ENDLESS is a single tab (was a
				# confusing overlap of two ENDLESS tabs AND these chevrons). Live only on
				# the ENDLESS tab; mouse parity with left/right.
				if _howto_page == HOWTO_ENDLESS_TAB and _endless_pages() > 1:
					var nav := _howto_endless_nav_rects()
					for side in range(2):
						if nav[side].has_point(ev.position):
							var step := 1 if side == 1 else -1
							var np := clampi(_endless_page() + step, 0, _endless_pages() - 1)
							# Only a LIVE chevron (one that actually pages) consumes the
							# click; a disabled boundary chevron falls through so it can't
							# swallow input meant for whatever sits under it.
							if np != _howto_endless_page:
								_howto_endless_page = np
								main._sfx.play("pickup", -14.0, 1.3)
								_mark_dirty()
								return
			if mode == Mode.HALL and _hall_pages(_hall_rows().size()) > 1:
				# Prev/next page buttons: route through _nav so paging, sfx, and the
				# boundary clamp match the d-pad exactly. A click on a boundary-
				# disabled arrow lands in the clamp and no-ops (no page change).
				var pr := _hall_page_rects()
				if pr[0].has_point(ev.position):
					if _hall_page > 0:
						_page_press = 0.0 if main._motion < 0.5 else 1.0
						_page_press_side = 0
					_nav(-1, 0)
					return
				if pr[1].has_point(ev.position):
					if _hall_page < _hall_pages(_hall_rows().size()) - 1:
						_page_press = 0.0 if main._motion < 0.5 else 1.0
						_page_press_side = 1
					_nav(1, 0)
					return
			var crow := _row_at(ev.position)
			# c1-19: a click on the SELECTED row's ◄/► cycle affordance must step by SIDE (left =
			# down, right = up) — checked BEFORE the row-plate _press() so a directional row (WINDOW
			# SCALE, volume) can never fall through to _press()'s upward-only Enter step even if the
			# arrow hitbox overlaps the plate. The arrows draw OUTSIDE the plate, so without this a
			# mouse-only player would lose the ◄ (down) direction entirely.
			if mode != Mode.HALL and mode != Mode.HOWTO \
					and _row_cycles(_menu_items()[sel]):
				var g := _row_geometry()
				var arows := toggle_arrow_rects(g, sel)   # same source _draw renders from
				var la := arows[0].grow(3.0)
				var ra := arows[1].grow(3.0)
				if la.has_point(ev.position) or ra.has_point(ev.position):
					# Side matters: volume + WINDOW SCALE step down/up per arrow, so a mouse-only
					# player has BOTH directions (the ◄ arrow lowers). Plain toggles flip either way.
					_nav(0, -1 if la.has_point(ev.position) else 1)
					_mark_dirty()
					return
			if crow >= 0:
				sel = crow
				_press()
				_mark_dirty()
		elif ev.button_index == MOUSE_BUTTON_WHEEL_UP or ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var wdir := -1 if ev.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			if mode == Mode.HALL:
				_nav(wdir, 0)   # c3-06: HALL wheel SCROLLS the board — up/down turns the page so runs past row 8 are reachable by wheel, matching the PREV/NEXT buttons (filters still cycle on left/right)
			elif mode == Mode.HOWTO:
				_nav(0, wdir)   # HOWTO turns the page — its sections live on the horizontal axis, not a 1-row list
			else:
				_nav(wdir, 0)
		return
	if move != 0 or hmove != 0:
		_nav(move, hmove)
	elif act:
		_press()
	elif back and mode == Mode.PAUSE:
		mode = Mode.HIDDEN
	elif back and mode == Mode.OPTS:
		_exit_opts(false)   # c3-18: Esc/cancel out of OPTIONS DISCARDS any staged changes (no persist)
	elif back and not _parent(mode).is_empty():
		var d := _parent(mode)   # one level up; OPTIONS climbs to its opener (TITLE or PAUSE)
		open(d["mode"], d["sel"])
	if (move != 0 or hmove != 0 or act or back) and is_inside_tree():
		accept_event()   # is_inside_tree guard: a not-in-tree menu (headless tests) skips it
	_mark_dirty()


# One nav step — shared by key/dpad/stick presses, the held-stick auto-repeat,
# and the mouse wheel, so every device gets identical wrap/snap/sfx behavior.
func _nav(move: int, hmove: int) -> void:
	# Hall of Fame: left/right (keyboard A/D + arrows, pad d-pad/stick) cycles the mode
	# filter (ALL / CAMPAIGN / ENDLESS); up/down AND the mouse wheel (routed in as move,
	# c3-06) SCROLL the board a page at a time, so runs past row 8 are reachable on every
	# device. Every input funnels here so no class is locked out of either axis. Paging is
	# clamped and never wraps; _hall_pages floors at 1, so even an empty board clamps to
	# page 0 (pages - 1 == 0), never a negative page.
	if mode == Mode.HALL and move != 0:
		var pages := _hall_pages(_hall_rows().size())
		var np := clampi(_hall_page + move, 0, pages - 1)
		if np != _hall_page:
			_hall_page = np
			_refresh_page_hover()   # the new page may flip a boundary — re-light/dim under a still cursor
			main._sfx.play("pickup", -14.0, 1.3)
			_mark_dirty()
		return   # HALL vertical nav OWNS paging — always consume it, even at a boundary, so it never falls through to the 1-row list nav below
	if mode == Mode.HALL and hmove != 0:
		_hall_filter = wrapi(_hall_filter + hmove, 0, 3)
		_hall_page = 0   # a new filter is a fresh list — always start on page 1 (keeps the "OF N" counter honest)
		_refresh_page_hover()   # page reset to 0 disables PREV — drop a stale hover on it
		# _tab_hover is pointer-owned — leave it. It tracks where the cursor
		# physically rests (only mouse motion moves it), so cycling by kb/pad/wheel
		# must not wipe a hover cue while the pointer is still over a tab. If the
		# cursor sits on the tab we just selected, _draw_hall's `not on` gate hides
		# the hover automatically, so no double-treatment slips through either.
		_filter_pulse = 0.0 if main._motion < 0.5 else 1.0
		main._sfx.play("pickup", -14.0, 1.3)
		_mark_dirty()
		return
	# c2-02: HOW TO PLAY is paged on the HORIZONTAL axis — left/right (and the wheel,
	# routed in as hmove) turns the CONTROLS / WAR CHEST / ENEMIES / ENDLESS page, clamped (never
	# wraps), so each section owns a full screen instead of stacking rows onto the
	# next. Matches the footer's "L/R PAGE" hint exactly. Up/down is deliberately
	# NOT consumed here — it falls through to the 1-row list below and simply keeps
	# focus on the always-selected BACK row (footer already binds SELECT/BACK), so
	# the paging axis and the nav axis never fight over the same press.
	if mode == Mode.HOWTO and hmove != 0:
		# c4-06: on the ENDLESS tab, left/right first pages the roster's sub-pages (mouse
		# parity with the chevrons) — only a sub-page boundary spills over to the next tab,
		# so left/right walks the whole help linearly (CONTROLS..ENEMIES..ENDLESS 1/2..2/2)
		# without a redundant second ENDLESS tab.
		if _howto_page == HOWTO_ENDLESS_TAB:
			var ep := _howto_endless_page + hmove
			if ep >= 0 and ep < _endless_pages():
				_howto_endless_page = ep
				main._sfx.play("pickup", -14.0, 1.3)
				_mark_dirty()
				return
		var np := clampi(_howto_page + hmove, 0, HOWTO_TABS.size() - 1)
		if np != _howto_page:
			_howto_page = np
			if np == HOWTO_ENDLESS_TAB:
				_howto_endless_page = 0   # entering ENDLESS from ENEMIES lands on its first roster page
			_howto_nav_hover = -1   # left the ENDLESS tab (or arrived) — drop any stale chevron hover
			main._sfx.play("pickup", -14.0, 1.3)
			_mark_dirty()
		return
	# ◄/► on a volume row nudges the 0..10 level, clamped — the SAME shared stepper
	# Enter/click drives. 0 == MUTED, so mute is just the bottom of the one model.
	# c4-01: this is the ONLY mute path for SFX/Music — there is no _toggle_bus branch. ► off 0
	# raises the level, which _step_vol -> main._set_bus_vol turns into set_bus_mute(false), so the
	# right arrow / "UNMUTE" hint literally performs the unmute the strip advertises. ◄ down to 0
	# is the deliberate mute. Enter/click (_activate) funnels through the SAME _step_vol, so no input
	# can desync the level from the real bus-mute state.
	if hmove != 0 and mode != Mode.HALL and _menu_items()[sel]["id"] in ["sfx", "music"]:
		_step_vol("SFX" if _menu_items()[sel]["id"] == "sfx" else "Music", hmove)
		_mark_dirty()
		return
	# c1-19: ◄/► on WINDOW SCALE (the DISPLAY sub-screen) steps the integer scale one clean rung,
	# clamped (no wrap) — ◄ shrinks, ► grows, railing at the 1x floor and the Nx ceiling. It NEVER
	# flips fullscreen (that's the separate FULLSCREEN toggle row). Live in BOTH modes: windowed it
	# resizes now, fullscreen it moves the preference applied on return to windowed.
	if hmove != 0 and mode != Mode.HALL and _menu_items()[sel]["id"] == "winscale":
		_step_scale(hmove)
		_mark_dirty()
		return
	# Left/right on a toggle row flips it directly — no confirm press needed
	# (same activation path, so save/sfx behavior stays identical).
	if hmove != 0 and mode != Mode.HALL and _menu_items()[sel]["id"] in _TOGGLES:
		_activate()
		_mark_dirty()
		return
	if move == 0:
		return
	if _items().size() < 2:
		return   # 1-row menu (HOWTO's BACK): sel wraps 0→0 — no phantom nav sfx
	var prev := sel
	sel = wrapi(sel + move, 0, _items().size())
	if sel != prev:
		_rail_pulse = 0.0   # left the row that bounced — don't flash a rail we moved off
		_rail_row = -1
	if absi(sel - prev) > 1:
		_sel_y = -1.0   # wrap: snap to the far end instead of gliding the whole list
	_disarm_confirm()   # c2-09: moving off the armed row cancels the confirm (and its countdown)
	main._sfx.play("pickup", -14.0, 1.3)
	_mark_dirty()


func _press() -> void:
	if _lockout > 0.0:
		return   # disconnect just auto-paused — swallow phantom confirms
	# c2-13: a disabled/locked row (e.g. DAILY RUN already completed today) is drawn
	# dim and never acts — a deny buzz answers the press so it reads as intentionally
	# unavailable, not a dead button. Covers keyboard, pad, and mouse (all route here).
	if _menu_items()[sel].get("disabled", false):
		main._sfx.play("deny", -8.0)
		_mark_dirty()
		return
	# Destructive items need a second press (mis-press guard on a run).
	if _is_destructive(sel) and _confirm != sel:
		_confirm = sel
		_confirm_t = 2.5   # auto-disarm window (decremented in _process)
		main._sfx.play("deny", -8.0)
	else:
		_disarm_confirm()   # c2-09: clears index + countdown together
		_activate()
	# c2-09: mark dirty for the press result (row arming / toggle flip / value step). Input is
	# handled before _process in the same frame, so the gate flushes it to the screen this frame.
	_mark_dirty()


# c1-09: OPTIONS climbs BACK to whichever screen opened it — TITLE normally, but
# PAUSE when reached mid-run (so backing out of settings returns to the paused run,
# not the title). back_dest stays the single source for the fixed parents (HALL/
# HOWTO/SETUP); only OPTIONS has two possible openers, tracked in _opts_parent.
func _parent(m: int) -> Dictionary:
	# c2-04: OPTIONS has two possible openers (the SETUP hub or PAUSE), tracked in
	# _opts_parent, so BACK always returns to the row the player came through. Guard a
	# stale/unset value (only PAUSE or SETUP host an OPTIONS row) so BACK can never strand
	# the player on a screen with no matching row — default to the SETUP hub.
	if m == Mode.OPTS:
		var opener := _opts_parent if _opts_parent in [Mode.PAUSE, Mode.SETUP] else Mode.SETUP
		return {"mode": opener, "sel": "options"}
	return back_dest(m)


# c1-09: group caption for the OPTIONS settings block — the settings rows carry
# grp ids 1/2/3 (audio / haptics / accessibility) and the first row of each group
# draws this label in the left margin, so the screen reads as three labelled
# sections, not one flat list. Non-settings groups (meta/reset/back) have none.
static func group_header(grp: int) -> String:
	match grp:
		1: return "AUDIO"
		2: return "HAPTICS"
		3: return "ACCESSIBILITY"
		4: return "DISPLAY"
	return ""


# c3-03: TITLE's section captions — the primary/secondary IA split spelled out as
# NAMED blocks, not just a divider rule. grp 0 (CAMPAIGN / ENDLESS / DAILY /
# CHALLENGE SEED) is the DEPLOY block — the four ways to start a run, the screen's
# dominant verbs; grp 1+ (SETUP hub, QUIT) is the MORE block — everything that
# isn't starting a run. Reusing group_header's pill+rule machinery (via
# _emit_group_caption) means the start verbs stop reading as one undifferentiated
# phone list once SETUP/QUIT sit under them. Kept separate from group_header so the
# TITLE grp ids (which collide with OPTS's AUDIO/HAPTICS grp ids) can't cross-wire.
static func title_group_header(grp: int) -> String:
	match grp:
		0: return "DEPLOY"
		1: return "MORE"
	return ""


# c3-03: the DEPLOY backing-panel rect (start-verb cluster) — single source shared by
# _draw and the layout test. `plast` is the last grp-0 row; `head_b` is the record
# header's bottom baseline (title_head_bottom). The panel top is CLAMPED to head_b+1 so
# it can never ride up into the record-header block whatever record lines are present, and
# its box is bounded by the SHARED row_rect geometry so it tracks the split + drop-in.
const TITLE_PANEL_PAD := 5.0
static func title_deploy_panel(g: Dictionary, plast: int, head_b: float) -> Rect2:
	var ptop_r := row_rect(g, 0)
	var pbot_r := row_rect(g, plast)
	var pytop := maxf(ptop_r.position.y - TITLE_PANEL_PAD, head_b + 1.0)
	return Rect2(ptop_r.position.x - TITLE_PANEL_PAD, pytop,
		ptop_r.size.x + TITLE_PANEL_PAD * 2.0,
		(pbot_r.position.y + pbot_r.size.y + TITLE_PANEL_PAD) - pytop)


# c1-09: the single settings-state readout for the OPTIONS screen — DISPLAY mode
# first, then EVERY accessibility aid with its EXPLICIT ON/OFF state (not just the
# active ones) so a player reviews the COMPLETE configuration in one place at a
# glance — "MOTION OFF  COLORBLIND ON  ASSIST OFF  RUMBLE ON" — instead of inferring
# what's off from an omission. DISPLAY is ALWAYS shown (fullscreen has no on-screen
# toggle — it's F11 — so this is the only place its state reads), which is also what
# makes RESET DEFAULTS honest: it restores DISPLAY to WINDOWED as a VISIBLE change
# here, not a silent flip. Pure + static so a headless test can pin the wording alone.
static func a11y_summary(reduce_motion: bool, colorblind: bool, assist: bool, rumble: bool, fullscreen: bool) -> String:
	return "DISPLAY: %s   REDUCE MOTION %s  COLORBLIND %s  ASSIST %s  RUMBLE %s" % [
		"FULLSCREEN" if fullscreen else "WINDOWED",
		"ON" if reduce_motion else "OFF",
		"ON" if colorblind else "OFF",
		"ON" if assist else "OFF",
		"ON" if rumble else "OFF",
	]


# c3-09: one-line EFFECT + PERSISTENCE description per value-holding settings row, drawn as the top
# line of the two-line footer (see _footer_legend); openers/actions have no entry (no footer line).
# The persistence clause tracks the source of truth — rows in main.gd SETTINGS_DEFAULTS say "SAVED
# AUTOMATICALLY", run-config CO-OP / NG+ HARD say "APPLIES TO YOUR NEXT RUN". ASSIST names the exact
# board tag it earns ("*ASSIST", the same marker _draw_hall stamps on those runs) so the effect is
# concrete, not a vague "flagged". These English strings double as translation KEYS: setting_help()
# runs the lookup through TranslationServer.translate(), so a .po/.csv keyed on the English text
# localizes the footer with no code change. The mapping + persistence honesty are pinned by
# test_setting_help_mapping_and_persistence_contract.
const SETTING_HELP := {
	"sfx": "SFX: LOUDNESS OF WEAPON, HIT, AND EXPLOSION SOUNDS. SAVED AUTOMATICALLY.",
	"music": "MUSIC: LOUDNESS OF THE BACKGROUND SOUNDTRACK. SAVED AUTOMATICALLY.",
	"rumble": "RUMBLE: CONTROLLER VIBRATION ON HITS AND EXPLOSIONS. SAVED AUTOMATICALLY.",
	"motion": "REDUCE MOTION: HOLDS THE SCREEN STEADY - NO SHAKE, FLASH, OR SCROLL FX. SAVED AUTOMATICALLY.",
	"colorblind": "COLORBLIND: RECOLORS GREEN CUES TO BLUE AND ADDS SHAPES. SAVED AUTOMATICALLY.",
	"assist": "ASSIST: EACH LIFE TAKES TWO HITS, NOT ONE. RUNS ARE TAGGED *ASSIST. SAVED AUTOMATICALLY.",
	"fullscreen": "FULLSCREEN: FILL THE WHOLE DISPLAY INSTEAD OF A WINDOW. SAVED AUTOMATICALLY.",
	"winscale": "WINDOW SCALE: SIZE OF THE GAME WINDOW WHILE NOT FULLSCREEN. SAVED AUTOMATICALLY.",
	"coop": "CO-OP: ADD A SECOND LOCAL PLAYER. APPLIES TO YOUR NEXT RUN.",
	"hard": "NG+ HARD: A TOUGHER CAMPAIGN SPAWN CURVE. APPLIES TO YOUR NEXT RUN.",
}
static func setting_help(id: String) -> String:
	var src: String = SETTING_HELP.get(id, "")
	# Localize via the English source string as the translation key (static-safe, unlike tr()).
	# With no translation loaded translate() returns the source unchanged, so English is the default.
	return TranslationServer.translate(src) if src != "" else ""


# c4-04: the baseline of the LOWEST header line a non-TITLE mode draws — the one input the
# shared first-row-top formula keys off. PAUSE clears its PAUSED+status+RUN# stack, OPTS/REBIND
# their compact 2-line header, the SETUP/INFO/DISP hubs their lone subtitle. HIDDEN/HALL/HOWTO
# never draw this column (they return early with a lone BACK button), so they take the hub default.
static func mode_header_bottom(mode_id: int) -> float:
	match mode_id:
		Mode.PAUSE: return PAUSE_FOOTNOTE_Y
		Mode.OPTS, Mode.REBIND: return OPTS_SUBLINE_Y
		_: return HUB_SUBTITLE_Y
# c4-04: the compact flag — the dense <=10-row OPTS/REBIND pages take the tighter header clearance
# so their 10th plate stays above the >=20px readable floor; every sparse screen takes the roomy one.
static func mode_is_compact(mode_id: int) -> bool:
	return mode_id == Mode.OPTS or mode_id == Mode.REBIND
# c4-04: THE first-row top — ONE formula for every non-TITLE mode (header baseline + a common
# clearance, compact or roomy). No screen carries a bare top offset any more; move a header line
# and its column follows. TITLE overrides this off title_head_bottom() in compute_geometry.
static func first_row_top(mode_id: int) -> float:
	return mode_header_bottom(mode_id) + (HEADER_CLEAR_COMPACT if mode_is_compact(mode_id) else HEADER_CLEAR)


# c4-04: a TITLE record line's text baseline sits the FONT'S OWN descender depth up from its plate
# bottom, read from live font metrics (Art.font().get_descent) rather than a hand-copied
# TITLE_DESC_GAP_* constant — so swapping the font (a different descent at the same size) carries the
# baseline with it and the glyph tail always lands just inside the plate bottom.
static func title_baseline(plate_top: float, plate_h: float, font_size: int) -> float:
	return plate_top + plate_h - Art.font().get_descent(font_size)


# Pure, view-free layout math for the button column — extracted so a headless
# regression test can pin the decompressed TITLE geometry (>=20px plates, 16px
# icons, header/legend clearance) without standing up a Control, Art, or `main`.
# `head_bottom` is the y of the lowest header plate the caller actually drew
# (TITLE varies it by which BEST/CAREER lines are present); other modes pass -1.
static func compute_geometry(mode_id: int, n: int, head_bottom: float, split_at := -1, split_gap := 0.0) -> Dictionary:
	# c4-04: every non-TITLE column reads the ONE shared first-row-top formula (header baseline +
	# a compact-or-roomy clearance) — no per-screen top literal, no row-count branch (the modes that
	# would fall through, HIDDEN/HALL/HOWTO, return early without drawing this column). TITLE
	# overrides `top` below off its header stack.
	var top := first_row_top(mode_id)
	var gap: float
	if mode_id == Mode.TITLE:
		# top tracks whichever header lines are actually present (head_bottom) — a
		# fresh install (no BEST/CAREER) starts ~24px higher, so the list decompresses
		# into real height instead of a fixed 156 that crushed bh to ~11px + 8px specks.
		# c4-04: TITLE's first-row top is FULLY DERIVED from title_head_bottom() (the caller passes
		# it as head_bottom) + TITLE_HEAD_MARGIN — the old 156 literal is gone; move a record plate
		# top and this override, the column, and the hit-test all follow from the one source.
		top = head_bottom + TITLE_HEAD_MARGIN
		# Spread across the WHOLE band down to the y322 input legend. Dividing by
		# n (not n-1) reserves the final row's own height, so QUIT self-clears the
		# legend without the old hardcoded 296 bottom bound that left dead air.
		# c2-04: with TITLE trimmed to 6 rows (4 start verbs + SETUP + QUIT), this same
		# math seats ~30px full-height plates (bh caps at BTN.y=36) with 16px icons even
		# with the CAREER header line present — no per-count special case needed.
		# c3-02: GAP_CEIL never BINDS TITLE — its fit term (band/6 ~= 29px) is always the
		# smaller of the two, so raising GAP_CEIL (e.g. a BTN resize) can't crush TITLE; the
		# 6-row cap is what protects the >=20px plate, and test_menu_layout pins that floor.
		# c3-03: reserve the inter-block gap out of the band BEFORE the fit divide, so the
		# DEPLOY plates keep their full share and never crush below 20px to fund the split.
		gap = minf(GAP_CEIL, (LEGEND_Y - LEGEND_MARGIN - top - split_gap) / maxf(1.0, float(n)))
		# c3-03: HARD floor on the pitch — the split gap + 6-row cap can never crush the
		# plate below TITLE_MIN_PLATE. bh = gap - ROW_INSET_TITLE, so flooring the pitch at
		# MIN_PLATE + inset guarantees bh >= MIN_PLATE. In every real header/record state the
		# fit term already clears this (the clamp is inert), so it neither steals the fit's
		# breathing room nor pushes the last plate past the legend — it's the runtime backstop
		# that makes the >=20px promise structural, not just cap-plus-comment.
		gap = maxf(gap, TITLE_MIN_PLATE + ROW_INSET_TITLE)
	else:
		# c3-02: every non-TITLE column now shares TITLE's math — spread the band down to
		# COLUMN_BOTTOM, dividing by n (not n-1) so the last plate's own height is reserved
		# and its glow clears the footer. One GAP_CEIL for all counts: dense lists shrink
		# via the fit term (they never reach the ceiling), sparse lists clamp AT it, so the
		# plate height no longer jumps between the old 30 / 46 tiers at the 4->5 boundary.
		gap = minf(GAP_CEIL, (COLUMN_BOTTOM - top) / maxf(1.0, float(n)))
	# TITLE plates take a 2px inter-row inset (vs 3px elsewhere) so the reclaimed
	# band converts to taller clickable plates, not just wider dead gaps.
	var inset := ROW_INSET_TITLE if mode_id == Mode.TITLE else ROW_INSET_DEFAULT
	# bh is minf-capped at BTN.y so a taller GAP_CEIL (after a BTN resize) never grows a
	# plate past the button art — the pitch breathes, the plate stops at full height.
	# split_at/split_gap ride along so row_rect (the single geometry source) shifts the
	# secondary block down by the reserved gap; -1 disables it (every non-TITLE screen).
	return {"top": top, "gap": gap, "bh": floorf(minf(BTN.y, gap - inset)), "n": n,
		"split_at": split_at, "split_gap": split_gap}   # floored HERE so _draw and the mouse hit-test agree


# The lowest header-plate baseline TITLE draws, given which record lines show —
# single source shared by compute_geometry and _draw so the column top can't
# drift off the header block. Non-TITLE modes have no record header (returns -1).
static func title_head_bottom(has_best: bool, has_career: bool) -> float:
	# c4-04: DERIVED from the record-stack tops+heights the plates actually draw with, so the
	# column top can't drift off the header block (141 / 130 / 118 for career / best / tagline-only).
	if has_career:
		return TITLE_CAREER_TOP + TITLE_CAREER_PLATE_H   # CAREER whisper plate bottom (implies the whole stack)
	if has_best:
		return TITLE_BEST_TOP + TITLE_RECORD_PLATE_H     # BEST line plate bottom
	return TITLE_TAGLINE_TOP + TITLE_RECORD_PLATE_H + TITLE_HEAD_SEAM   # tagline plate bottom + seam (always drawn)


# Where BACK / Esc goes from each screen — one level up. HALL and HOW TO PLAY
# live under the INFO screen, so they climb to INFO; INFO, RUN SETUP and OPTIONS
# hang off TITLE. Pure + single-sourced so _unhandled_input and _activate can't
# drift their back-nav targets apart. Screens with no parent (TITLE/PAUSE/HIDDEN) => {}.
static func back_dest(mode_id: int) -> Dictionary:
	match mode_id:
		Mode.HOWTO: return {"mode": Mode.INFO, "sel": "howto"}
		Mode.HALL: return {"mode": Mode.INFO, "sel": "hall"}
		Mode.INFO: return {"mode": Mode.SETUP, "sel": "info"}   # c2-04: INFO now hangs off the SETUP hub
		Mode.SETUP: return {"mode": Mode.TITLE, "sel": "setup"}   # c2-04: SETUP hangs off TITLE's SETUP row
		Mode.OPTS: return {"mode": Mode.SETUP, "sel": "options"}   # c2-04: fallback opener; _parent overrides via _opts_parent
		Mode.REBIND: return {"mode": Mode.OPTS, "sel": "controls"}   # c1-18: rebind screen hangs off the OPTIONS CONTROLS row — BACK restores focus to that real row
		Mode.DISP: return {"mode": Mode.OPTS, "sel": "display"}   # c1-19: DISPLAY sub-screen hangs off the OPTIONS DISPLAY row — BACK restores focus to it
		_: return {}


# Open-settle drop-in: the whole column starts up to 12px LOW and rises to rest.
# CAP the push so that even mid-open (open_t -> 0) the last plate never dips past
# `max_bottom` — on TITLE that is the y322 input legend (the only screen that
# draws it), which the fullest state settles just ~5px clear of, so an uncapped
# +12 briefly overlapped it. Other screens have no legend, so `max_bottom` is the
# canvas floor and the full drop-in survives. Pure + testable.
static func settle_offset(g: Dictionary, open_t: float, motion: float, max_bottom: float) -> float:
	if motion < 0.5:
		return 0.0
	# c3-03: off row_rect so a split secondary block's lower last-row bottom is respected.
	var last := row_rect(g, int(g["n"]) - 1)
	var last_bottom := last.position.y + last.size.y
	return minf((1.0 - open_t) * 12.0, maxf(0.0, max_bottom - last_bottom))


func _row_geometry() -> Dictionary:
	# Single source of truth for the button column layout — _draw and the mouse
	# hit-test must agree or hover selects the wrong row.
	var head := title_head_bottom(main.best_score > 0, main._life_runs > 0)
	# c3-03: TITLE reserves a spatial gap between the primary DEPLOY block (grp 0) and the
	# secondary MORE block — split_at is the first non-primary row. Only TITLE splits; every
	# other screen passes split_at = -1 (no offset).
	var split_at := -1
	if mode == Mode.TITLE:
		var mi := _menu_items()
		for k in mi.size():
			if int(mi[k].get("grp", 0)) > 0:
				split_at = k
				break
	var g := compute_geometry(mode, _items().size(), head, split_at,
		TITLE_BLOCK_GAP if split_at >= 0 else 0.0)
	# Drop-in offset lives HERE (after the pure gap math it must not perturb) so a
	# click during the settle hits the same rows _draw renders. TITLE clears its
	# y322 legend; every other screen now carries the FOOTER_Y nav legend, so cap
	# the drop 5px above it — the selected-row glow (grow ~4.5) stays clear of the
	# footer even at the low point of the open animation, not just at rest.
	var floor_y := 321.0 if mode == Mode.TITLE else FOOTER_Y - 5.0
	g["top"] = float(g["top"]) + settle_offset(g, _open_t, main._motion, floor_y)
	return g


# Which row a point falls in, given a geometry dict — pure so the hit-test is
# unit-checkable. Each interior row's box runs from half-a-dead-band above its own
# plate down to half-a-dead-band above the NEXT plate, so the boxes are exactly
# CONTIGUOUS — a point can never fall into a between-plate gap and blink the
# highlight out. (The old symmetric +/-pad box left a sub-pixel dead strip whenever
# floorf rounding pushed two plate tops more than bh+2*pad apart — e.g. the c2-04
# 6-row TITLE.) The last row keeps the symmetric bottom pad (no plate follows it).
static func hit_row(g: Dictionary, y: float) -> int:
	var n := int(g["n"])
	var bh := float(g["bh"])
	var pad := maxf(0.0, (float(g["gap"]) - bh) / 2.0)
	for k in n:
		var ry := row_rect(g, k).position.y   # same source _draw / the arrow hit-test build from
		var bottom := (row_rect(g, k + 1).position.y - pad) if k < n - 1 else (ry + bh + pad)
		if y >= ry - pad and y < bottom:
			return k
	return -1


# c1-04: lowest pixel a selected row's breathing glow can touch — its last-row
# rect bottom plus the max grow (3.0 + Art.pulse*1.5, pulse<=1). Pure so the
# layout test can prove it never reaches FOOTER_Y on the fullest PAUSE/OPTS list.
static func max_glow_bottom(g: Dictionary) -> float:
	# c3-03: off row_rect so the last row's split offset (if any) is included.
	var last := row_rect(g, int(g["n"]) - 1)
	return last.position.y + last.size.y + 4.5


# c1-12: single source of truth for a row's plate rect — _draw and the mouse
# hit-test both build the toggle-arrow boxes off this, so the x/width/height a
# horizontal-layout change touches lives in ONE place, not re-hardcoded per call
# site. Same floorf snapping _draw has always used (crisp pixel-font seams).
static func row_rect(g: Dictionary, k: int) -> Rect2:
	# c3-03: rows at/after split_at sit split_gap lower — the DEPLOY/MORE block separation.
	# Every hit-test/arrow/glow box derives from here, so the gap can't drift off the pixels.
	var extra := float(g.get("split_gap", 0.0)) if int(g.get("split_at", -1)) >= 0 \
		and k >= int(g.get("split_at", -1)) else 0.0
	return Rect2(Vector2(CENTER_X - BTN.x / 2.0, floorf(float(g["top"]) + float(k) * float(g["gap"]) + extra)),
		Vector2(BTN.x, floorf(float(g["bh"]))))


# c1-12: single source of truth for the ◄/► cycle-arrow boxes on a toggle/volume
# row — _draw and the mouse hit-test both read this, so a layout tweak can't drift
# the visible arrow off its click target (same discipline as _row_geometry /
# _back_rect). Returns [left, right] as normalized visual rects (the left arrow is
# drawn flipped via a negative width, but its bounds are these). Takes the geometry
# dict + row index and derives EVERYTHING from it — the row rect via row_rect and
# the raw (unfloored) box height for the y-snap — so no caller can pass a bh that
# has drifted from the rect it belongs to.
static func toggle_arrow_rects(g: Dictionary, k: int) -> Array[Rect2]:
	var r := row_rect(g, k)
	var ay := floorf(r.position.y + float(g["bh"]) / 2.0) - ARROW_SZ / 2.0   # centered on cy, raw-bh snap == _draw
	var out: Array[Rect2] = [
		Rect2(r.position.x - ARROW_L_OFF, ay, ARROW_SZ, ARROW_SZ),
		Rect2(r.end.x + ARROW_R_GAP, ay, ARROW_SZ, ARROW_SZ),
	]
	return out


func _row_at(p: Vector2) -> int:
	if mode == Mode.HALL or mode == Mode.HOWTO:
		return 0 if _back_rect().has_point(p) else -1
	if absf(p.x - CENTER_X) > BTN.x / 2.0:
		return -1
	return hit_row(_row_geometry(), p.y)


## Single source of truth for the HALL/HOWTO back button geometry — _row_at and
## _draw_back_button both read it, so a tweak to one can't drift the click target
## off the pixels (same discipline as _row_geometry / panel_bottom()).
func _back_rect() -> Rect2:
	# 310 (was 320): pulled up so a real SELECT/BACK footer legend fits BELOW the
	# button (its glow bottom ~338, footer glyphs ~343). The HOWTO ENDLESS page's
	# threat-row pitch is DERIVED from this y (see _howto_page_endless); paging gives
	# it a full screen so it sits at a roomy 18px, well clear of BACK. The BACK plate
	# is shared by all three HOWTO pages. Bottom lands at 335. Draw + hit-test share.
	return Rect2(Vector2(CENTER_X - BTN.x / 2.0, BOTTOM_BOUND), BTN * Vector2(1, BACK_H_RATIO))


func _step_vol(bus: String, delta: int) -> void:
	# Single source for EVERY volume change: ◄/► AND Enter/click both flow through
	# here, so SFX/MUSIC share ONE model — a clamped 0..10 level where 0 == MUTED.
	# A muted bus counts as level 0 regardless of its stored volume_db (effective_
	# vol), so a step always lifts it off mute instead of sticking at a hidden 10.
	# _set_bus_vol maps 0 -> mute and keeps the UI+VO buses in lockstep (the old
	# direct mute-toggle only muted UI, leaving the radio VO blaring).
	var cur: int = effective_vol(_bus_off(bus), main._bus_vol(bus))
	var nv: int = step_level(cur, delta)
	if nv == cur:
		# Already at a rail (0/MUTED or 10). Not a silent no-op: flash the pinned
		# end segment so the press reads as "held at the limit," not "ignored." The
		# floor's own "deny" tick would be swallowed (SFX is muted there), so the
		# visual bounce is the reliable feedback — the top rail keeps its audible cue.
		_rail_dir = -1 if delta < 0 else 1
		_rail_row = sel
		_rail_pulse = 0.0 if main._motion < 0.5 else 1.0
		if delta > 0:
			main._sfx.play("deny", -16.0)   # top rail: SFX is audible, so a soft tick lands
		_mark_dirty()
		return
	_rail_pulse = 0.0   # a real step lands — clear any stale bounce flash
	_rail_row = -1
	main._set_bus_vol(bus, nv)
	_stage_opts()   # c3-18: the new level is live (you HEAR it), but the disk write waits for SAVE
	_flash_setting()   # c1-17: a real step applied — pulse the row so the change reads visually
	# The tick doubles as a live level demo — pitch rides the new step.
	main._sfx.play("pickup", -14.0, 0.8 + 0.05 * float(nv))


# c1-19: which rows show the ◄/► cycle affordances AND route sideways input to a step — the plain
# toggles plus WINDOW SCALE. WINDOW SCALE cycles in BOTH modes now (never a dead row): windowed it
# resizes live, fullscreen it edits the deferred preference — so the arrows always mean something.
# c3-09: takes the ROW, not a bare id, so the WINDOW SCALE stepper is recognized by its "step"
# schema flag (set in _settings_rows) rather than an id string special-case — the same flag the
# footer legend and the missing-copy dev guard key off. A future stepper just sets "step": true.
func _row_cycles(item: Dictionary) -> bool:
	return item.get("id", "") in _TOGGLES or item.has("step")


# c1-19: step the integer window scale one clean rung — ◄/► and Enter share this, so arrows and
# activation have IDENTICAL boundary behavior (no separate wrap model). A pure 1x..Nx stepper that
# NEVER touches the window MODE: FULLSCREEN is its own explicit ON/OFF toggle, so scale and mode are
# never overloaded onto one control (the old ladder's flaw). N is the largest integer scale the
# CURRENT monitor fits (main._max_win_scale, re-read every step so a display change can't wedge it).
# Windowed: route through main._set_win_scale (sizes + centers the window, persists) — the same path
# F11's windowed restore uses. Fullscreen: the row stays LIVE but only the PREFERENCE moves
# (main._set_win_scale_pref) — applied on return to windowed — so it's never a silently-ignored row.
func _step_scale(dir: int) -> void:
	var mx: int = main._max_win_scale()
	var cur: int = main._win_scale if main._fullscreen else main._win_scale_norm()
	var nxt: int
	if cur > mx:
		# An OVER-CEILING preference (carried from a bigger display, only visible while fullscreen
		# where the row shows the raw preference): ◄ must not rail — it JUMPS DOWN to the current
		# ceiling (a real move the user asked for), while ► rails (already past the fit). Without this
		# both directions railed at e.g. 7x on a 3x monitor, wedging the row. The preference is only
		# lowered here because the user explicitly pressed ◄ — never silently.
		if dir < 0:
			nxt = mx
		else:
			_display_rail(dir)
			return
	else:
		nxt = cur + dir
		if nxt < 1 or nxt > mx:
			_display_rail(dir)                         # at a rail (1x floor / Nx ceiling): bounce, no wrap
			return
	# c3-18: resize LIVE but defer the write — the DISPLAY screen shares the OPTIONS dirty session
	# (reached via its opener), so SAVE commits and DISCARD restores the baseline scale.
	var moved: bool = main._set_win_scale_pref(nxt, false) if main._fullscreen else main._set_win_scale(nxt, false)
	if moved:
		_stage_opts()
		_flash_setting()
		main._sfx.play("pickup", -14.0, 1.0)


# c1-19: a DISPLAY step that hit a rail (1x floor / fullscreen ceiling) — bounce the row like the
# volume rails and deny-chime, instead of a silent no-op.
func _display_rail(rail_dir: int) -> void:
	_rail_dir = rail_dir
	_rail_row = sel
	_rail_pulse = 0.0 if main._motion < 0.5 else 1.0
	main._sfx.play("deny", -16.0)


func _flash_setting() -> void:
	# c1-17: raise the settings-change confirm halo on the current row. Fired by a real
	# volume step and by every plain toggle flip, so an APPLIED setting change reads as a
	# distinct visual pulse — not only a chime. Persists (and draws static) under Reduce
	# Motion, since the whole point is confirming the change to a player still in the menu.
	_set_pulse = 1.0
	_set_pulse_row = sel


func _flash_all_settings() -> void:
	# c1-17: Reset Defaults rewrites every a11y/audio row at once, so pin the confirm to
	# the sentinel row -2 -- _draw haloes ALL visible setting rows -- giving a bulk reset
	# the same per-row APPLIED cue a single toggle gets, alongside the DEFAULTS RESTORED banner.
	_set_pulse = 1.0
	_set_pulse_row = -2



# c3-18: mark the OPTIONS screen dirty after a row applied its value LIVE (the preview still works);
# this only defers the disk write. The revert BASELINE is NOT captured here — the live field was
# already mutated by the time we reach this, so snapshotting now would record the tweaked value.
# The pristine on-disk baseline is captured on OPTS ENTRY (see open()), so DISCARD reverts to the
# real original. Raising dirty swaps the exit row into the SAVE / DISCARD pair.
# c3-18: flat field-by-field settings compare — version-agnostic (doesn't lean on Dictionary ==
# semantics) and the snapshot is a flat dict of primitives, so this is exact and cheap.
static func _settings_match(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or b[k] != a[k]:
			return false
	return true


func _stage_opts() -> void:
	# Recompute dirty STRUCTURALLY against the entry baseline: flipping a value and then flipping it
	# back to its original clears the dirty state (and drops the forced SAVE/DISCARD decision) instead
	# of latching a one-way boolean. The row was already applied LIVE; this only tracks the pending
	# write. Rebuild the item list only when dirty actually flips, so the exit row swaps BACK <->
	# SAVE/DISCARD the instant it changes.
	var was := _opts_dirty
	_opts_dirty = not _settings_match(_opts_snapshot, main._settings_snapshot())
	if _opts_dirty != was:
		_items_valid = false


# c3-18: leave the OPTIONS screen, committing or reverting the staged changes first. SAVE writes
# the (already-live) settings to disk once; anything else (BACK / DISCARD / Esc) re-applies the
# snapshot to undo the live preview and writes nothing. Either way the dirty flag clears and the
# screen climbs to whichever opener _parent resolves (TITLE/SETUP or PAUSE).
func _exit_opts(save: bool) -> void:
	if save:
		main._save_settings()
	elif _opts_dirty:
		# main._apply_settings re-applies the REAL state, not just the fields: it re-mutes/levels the
		# audio buses and calls DisplayServer.window_set_mode (+ windowed-scale fit + cursor rebake),
		# so a discarded fullscreen/scale preview physically returns the window to its baseline.
		main._apply_settings(_opts_snapshot)
	_opts_dirty = false
	var d := _parent(Mode.OPTS)
	open(d["mode"], d["sel"])


func _activate() -> void:
	# CHALLENGE SEED gates on the clipboard BEFORE the generic confirm chime so an
	# empty/invalid paste plays a deny (not a buy) and never falls silently through.
	if _is_seed_row():
		_activate_seed()
		return
	main._sfx.play("buy", -8.0)
	if mode == Mode.HALL or mode == Mode.HOWTO:
		# The lone BACK plate on the HALL/HOWTO content screens climbs to INFO.
		var d := _parent(mode)
		open(d["mode"], d["sel"])
		return
	var id: String = _menu_items()[sel]["id"]
	if mode == Mode.REBIND:
		# c1-18: BACK climbs to OPTIONS; RESET CONTROLS (two-press destructive) reverts
		# every verb to its ship key; any other row is a verb — arm the key-capture listen
		# so the NEXT key press (handled at the top of _unhandled_input) becomes its bind.
		# Each path returns immediately — open() switches `mode`, so falling through would
		# re-process the same id under the NEW screen.
		if id == "back":
			var d := _parent(mode)
			open(d["mode"], d["sel"])
			return
		if id == "reset_controls":
			# Reached only on the SECOND press — reset_controls is a destructive row, so the
			# first press just arms the confirm (see _press / _is_destructive), matching the
			# RESET DEFAULTS two-step. Revert every verb, halo the rows, and post an explicit
			# success notice so the bulk change is confirmed, not silent.
			main.reset_binds()
			_flash_all_settings()   # halo every rebind row — the bulk revert reads like a single change
			_notice("CONTROLS RESET TO DEFAULT")
			return
		if id == "swap_sticks":
			# c1-18: inline pad TOGGLE (not a key/button capture) — flip MOVE<->AIM sticks for
			# the ACTIVE player only (P1/P2 swap independently, like their button layouts).
			main._swap_sticks[_rebind_pad_dev] = not main._swap_sticks[_rebind_pad_dev]
			main._save_settings()
			_flash_setting()
			return
		_rebind_action = id
		return
	if mode == Mode.TITLE:
		match id:
			"campaign": main.start_game(false)
			"endless": main.start_game(true)
			"daily": main.start_daily()
			"watch": main.start_watch()
			"paste_seed": _activate_seed()   # gated above; here only defensively
			"setup": open(Mode.SETUP)   # c2-04: SETUP hub (run config + OPTIONS + INFO)
			"quit": get_tree().quit()
	else:
		match id:
			"resume": mode = Mode.HIDDEN
			"options":
				# c1-09: PAUSE fronts settings through ONE dedicated OPTIONS screen (the
				# six a11y/audio rows no longer live on the pause list). c2-04: SETUP now
				# also opens it. Either way BACK returns to the opener via _opts_parent.
				_opts_parent = mode
				open(Mode.OPTS)
			"info": open(Mode.INFO)   # c2-04: reached from the SETUP hub; BACK returns there
			"controls": open(Mode.REBIND)   # c1-18: CONTROLS row opens the rebind screen
			"back":
				if mode == Mode.OPTS and _opts_dirty:
					# c3-18: safety net — with staged changes the exit is normally SAVE/DISCARD, but a
					# stale cached BACK row must never silently leave live edits uncommitted; treat it as
					# a discard (same as Esc/cancel out of OPTIONS).
					_exit_opts(false)
					return   # _exit_opts already switched screens — never fall through onto the new one
				# BACK climbs one level: OPTIONS returns to its opener, SETUP to TITLE.
				var d := _parent(mode)
				open(d["mode"], d["sel"])
			"opts_save":
				_exit_opts(true)    # c3-18: commit the staged OPTIONS changes, then climb to the opener
				return              # _exit_opts switched screens — stop before any post-activation logic
			"opts_discard":
				_exit_opts(false)   # c3-18: revert the staged changes to the on-disk baseline, then climb
				return
			"hall": open(Mode.HALL)   # INFO screen link
			"watch": main.start_watch()   # WATCH LAST RUN lives on the INFO screen now
			"coop":
				main._two_players = not main._two_players   # run-setup toggle (SETUP); left/right + Enter share this path
				_flash_setting()   # c1-17: fired at the mutation itself, not a post-activation id allowlist
			"hard":
				main._hard = not main._hard
				_flash_setting()
			"howto": open(Mode.HOWTO)   # help screen under INFO; back returns here
			"sfx", "music":
				# c3-04: primary confirm STEPS the level up one (+1, rails at 10) -- the SAME
				# clamped 0..10 model ◄/► use, NOT a mute toggle. So Enter/click can never
				# surprise-mute a player who meant to nudge; deliberate mute is stepping ◄ down
				# to 0 (reads MUTED). _step_vol -> main._set_bus_vol maps 0<->bus-mute and
				# un-mutes on any raise, so the label, the bar and the actual audio never diverge.
				# c4-01: this is the SINGLE interaction model -- there is no separate Enter/_toggle_bus
				# mute path anymore; ◄/► (_nav) and Enter/click (here) both route through _step_vol, so a
				# muted row can only be un-muted by raising the level, never by an independent toggle that
				# would resurrect the old "SFX: 7 but silent" split. Stepping right off 0 always un-mutes.
				_step_vol("SFX" if id == "sfx" else "Music", 1)
			"motion":
				main._motion = 0.0 if main._motion >= 0.5 else 1.0
				_stage_opts()	# c3-18: apply live, defer the disk write to SAVE
				_flash_setting()
			"colorblind":
				main.colorblind = not main.colorblind
				_stage_opts()
				_flash_setting()
			"rumble":
				main._rumble_on = not main._rumble_on
				_stage_opts()
				_flash_setting()
			"assist":
				main._assist = not main._assist
				_stage_opts()
				_flash_setting()
			"display":
				# c1-19: DISPLAY opens its dedicated sub-screen (FULLSCREEN toggle + WINDOW SCALE
				# stepper) — BACK climbs back to this row.
				open(Mode.DISP)
			"fullscreen":
				# c1-19: a plain ON/OFF toggle — ONE press reaches fullscreen (and one press back).
				# ◄/► on this row route here too (it's in _TOGGLES), so arrows and Enter agree. Shares
				# the SAME main._toggle_fullscreen path as the F11/Alt+Enter hotkey (persist + cursor
				# rebake + windowed-scale restore included), so the on-screen toggle and the shortcut
				# can never diverge. The stored WINDOW SCALE is untouched by the mode flip.
				# c3-18: the mode flips LIVE (you see it) but the write is DEFERRED to SAVE — reached
				# via the OPTS DISPLAY opener, so it shares the same dirty session; DISCARD restores the
				# baseline (window mode included). The F11/Alt+Enter hotkey keeps its own immediate persist.
				main._toggle_fullscreen(false)
				_stage_opts()
				_flash_setting()
			"winscale":
				# c1-19: Enter steps the scale UP one rung — the SAME call ► uses, so activation and
				# the arrows behave identically (rails at the Nx ceiling, never wraps and never flips
				# fullscreen). Live in both modes: windowed it resizes now, fullscreen it moves the
				# preference applied on return to windowed.
				_step_scale(1)
			"reset_defaults":
				# c1-09: the two-press confirm already fired (destructive row → _press
				# arms, a second press lands here) — revert the shown settings to their
				# ship defaults and raise the "DEFAULTS RESTORED" banner as success feedback.
				# The rows below regenerate from state, so they show the restored values at once.
				# Snapshot reduce-motion BEFORE the reset (which re-enables motion): a
				# motion-sensitive player still gets a snapped, non-animated banner.
				_reset_flash_anim = main._motion >= 0.5
				main._reset_settings()   # applies SETTINGS_DEFAULTS AND persists (it calls _save_settings)
				# c3-18: RESET DEFAULTS is a deliberate two-press COMMIT — main._reset_settings already
				# wrote the defaults to disk, so they ARE the new baseline. Re-capture that baseline and
				# clear staged-dirty: a following tweak-and-DISCARD now reverts to the just-written
				# defaults, never a stale pre-reset snapshot (which would leave live state disagreeing
				# with disk).
				_opts_snapshot = main._settings_snapshot()
				_opts_dirty = false
				_items_valid = false   # dirty cleared -> the exit row reverts SAVE/DISCARD back to a single BACK now
				_reset_flash = 1.6
				_flash_all_settings()   # c1-17: halo every reset row, not just the banner
			"restart":
				main._reset()
				mode = Mode.HIDDEN
			"title":
				main._endless = false   # attract showcases the campaign
				main._reset()
				open(Mode.TITLE)


static func seed_hint_lines(selected: bool, preview: int, armed: bool, clip_empty: bool) -> PackedStringArray:
	# c1-14: the exact text line(s) the CHALLENGE SEED hint renders, single-sourced so a
	# test asserting these IS the render assertion. A VALID preview always wins — a
	# lingering empty-press deny flash (colour only) can never hide the shown seed.
	# Unselected names the source; an EMPTY clipboard reads "NO SEED - COPY ONE" while a
	# clipboard that holds text but no usable seed (malformed / overflow) reads "BAD SEED
	# - CHECK COPY" so the two failures are told apart; a valid seed shows "SEED N"; once
	# armed it adds a SECOND line "PRESS AGAIN" so the confirm stays fully textual.
	if not selected:
		return PackedStringArray([SEED_SOURCE_COPY])
	if preview < 0:
		return PackedStringArray(["NO SEED - COPY ONE"] if clip_empty else ["BAD SEED - CHECK COPY"])
	if armed:
		return PackedStringArray(["SEED %d" % preview, "PRESS AGAIN"])
	return PackedStringArray(["SEED %d" % preview])


static func seed_row_label(base: String, selected: bool, clip_raw: String, valid: bool) -> String:
	# c2-12: while the CHALLENGE SEED row is focused, echo the RAW clipboard text INTO the
	# row label itself (ellipsized downstream in _draw) so the player can SEE exactly what a
	# press will use — valid, malformed, or empty — before it commits, and carry an EXPLICIT
	# status tag in the label so the state is stated in the standard row flow, not only in
	# the right-margin hint. Unfocused keeps the bare "CHALLENGE SEED" label.
	# STANDARDIZED FORMAT (all selected states share one shape): "<base> (<TAG>)" plus, when
	# there is raw text to echo, ": <raw>". Single space before the tag, one colon+space
	# before the echo, parenthesised tag every time — so EMPTY / OK / INVALID read as one
	# consistent family, not three ad-hoc strings.
	#   empty  -> "CHALLENGE SEED (EMPTY)"
	#   valid  -> "CHALLENGE SEED (OK): 12345"
	#   bad    -> "CHALLENGE SEED (INVALID): garbage 1 2 3"
	# Newlines/tabs collapse to spaces so a multi-line clipboard (e.g. a share card) stays
	# one clean line before _ellipsize fits it to the button.
	# The status tag sits in the label PREFIX (before the raw echo) on purpose: the raw text
	# is what _ellipsize trims when it overflows the button, so a suffix marker would be the
	# first thing clipped off a long paste. Prefixing it keeps "(OK)"/"(INVALID)"/"(EMPTY)"
	# always visible; only the (redundant-with-the-hint) raw tail truncates.
	if not selected:
		return base
	var raw := clip_raw.strip_edges()
	if raw.is_empty():
		return "%s (EMPTY)" % base   # explicit EMPTY state in the row, not only the hint
	# Collapse every run of whitespace (spaces, CR/LF, tabs) to a single space so a pasted
	# share card or a CRLF clipboard stays one clean, evenly spaced line.
	raw = " ".join(raw.replace("\r", " ").replace("\n", " ").replace("\t", " ").split(" ", false))
	if valid:
		return "%s (OK): %s" % [base, raw]
	return "%s (INVALID): %s" % [base, raw]


func _is_seed_row() -> bool:
	# c1-14: safe "is the CHALLENGE SEED row focused?" — bounds-checks sel BEFORE indexing
	# _menu_items() so a transient/invalid selection can never throw out of range.
	if mode != Mode.TITLE:
		return false
	var items := _menu_items()
	return sel >= 0 and sel < items.size() and items[sel]["id"] == "paste_seed"


enum { SEED_SUB_NONE, SEED_SUB_STACKED, SEED_SUB_SAME_LINE }

func _seed_tag_stacks(r: Rect2, cy: float) -> bool:
	# c3-13: does the plate have vertical room to stack the seed sub-label as a true SECOND
	# line BELOW the row name? Single-sourced so the main label pass (which reserves a same-line
	# tag slot when it does NOT stack) and _draw_seed_subline (which places the tag) can never
	# disagree about which layout is in play. Uses the same ROW_LABEL_* geometry the name draws at.
	var f := Art.font()
	var label_bottom := cy + ROW_LABEL_BASELINE_DY + f.get_descent(ROW_LABEL_SIZE)
	return label_bottom + f.get_ascent(SEED_TAG_SIZE) + f.get_descent(SEED_TAG_SIZE) + SEED_SUB_MARGIN <= r.end.y


func _seed_flash_amt() -> float:
	# c3-13: denied-press flash intensity, shared by the plate stripe/veil AND the status hint.
	# Normal motion returns the smooth decaying _seed_flash. Under Reduce Motion it returns a
	# STEADY full-strength step (a single non-animated pulse) while the flash timer is live, so a
	# denied press still lands a distinct high-contrast error cue instead of vanishing when
	# animation is disabled — the persistent invalid marker alone gave the PRESS no feedback.
	if main._motion >= 0.5:
		return _seed_flash
	return 1.0 if _seed_flash > 0.0 else 0.0


func _draw_seed_subline(r: Rect2, cy: float, text: String, col: Color, allow_same_line: bool) -> int:
	# c3-13: place a short seed sub-label INSIDE the plate. Real TITLE seed-row plates run
	# ~24..36px; a full SEED_TAG_SIZE line only fits BELOW the name on the taller plates. It
	# derives the name's geometry from the SAME constants the main label draw uses (ROW_LABEL_SIZE
	# / ROW_LABEL_BASELINE_DY), so the two can't drift. Returns an explicit placement enum instead
	# of an ambiguous bool: SEED_SUB_STACKED = a true SECOND line under the name; SEED_SUB_SAME_LINE
	# = seated on the name's line (short plate, allow_same_line only — the resting tag, whose name
	# is the FIXED SEED_ROW_LABEL, right-aligned and clamped clear of it); SEED_SUB_NONE = nothing
	# drawn (short plate, same-line disallowed for focused rows whose label is the clipboard echo a
	# same-line tag could collide with — the caller then falls back to the right-margin hint).
	var f := Art.font()
	var lx := r.position.x + 30.0   # SAME left column the main label is drawn at
	var right := r.end.x - SEED_SUB_PAD   # inner right bound, mirrors the main label's r.end.x-8
	var name_baseline := cy + ROW_LABEL_BASELINE_DY
	# Route through the _emit_label seam (not raw Art.text) at SEED_TAG_SIZE with a max_w clamp,
	# so a draw-capture test can inspect these lines and they can never overdraw the plate border.
	_label_size = SEED_TAG_SIZE
	if _seed_tag_stacks(r, cy):
		_label_max_w = right - lx
		_emit_label(text, Vector2(lx, r.end.y - f.get_descent(SEED_TAG_SIZE) - SEED_SUB_MARGIN), col)
		_label_size = 8
		_label_max_w = 0.0
		return SEED_SUB_STACKED
	if allow_same_line:
		# c3-13: SHORT plate — no vertical room to stack. Ride the tag on the NAME's baseline,
		# RIGHT-ALIGNED in the slot the main label pass reserves for it (it narrows the name's
		# avail so the name ellipsizes clear). Right-aligning means we never measure the name
		# here, so the tag can't drift against the actual drawn (possibly ellipsized) label, AND
		# the helper is ALWAYS drawn — the name is clipped to make room for it, never the tag
		# omitted. maxf keeps the tag inside the icon gutter on a pathologically narrow plate.
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SEED_TAG_SIZE).x
		var tx := maxf(right - tw, lx)
		_label_max_w = right - tx
		_emit_label(text, Vector2(tx, name_baseline), col)
		_label_size = 8
		_label_max_w = 0.0
		return SEED_SUB_SAME_LINE
	_label_size = 8
	_label_max_w = 0.0
	return SEED_SUB_NONE


func _draw_seed_hint(r: Rect2, cy: float, selected: bool) -> void:
	# c1-14 / c3-13: the CHALLENGE SEED status hint. AT REST it is an in-plate sub-label
	# (c3-13, via _draw_seed_subline) rather than floating in the right margin. When FOCUSED it
	# shows live status: the invalid/empty error also rides in-plate; valid/armed use the
	# right-margin lines (drawn through the _emit_* seams so a draw-capture test can inspect them).
	var f := Art.font()
	if not selected:
		_draw_seed_subline(r, cy, SEED_SOURCE_COPY, SEED_TAG_COL, true)
		return
	# FOCUSED: live status in the right margin.
	var armed_here := _seed_preview >= 0 and _seed_armed and _seed_preview == _seed_armed_val
	# The deny flash only colours the hint while there is no valid seed to show — a lingering
	# flash can never hide a now-valid preview.
	var flash_here := _seed_flash > 0.0 and _seed_preview < 0
	var clip_empty := _seed_clip_raw.strip_edges().is_empty()
	var lines := seed_hint_lines(true, _seed_preview, armed_here, clip_empty)
	var deny_col := Color(1.0, 0.55, 0.4)   # resting invalid colour
	if _seed_preview < 0:
		# c3-13: co-locate the SPECIFIC error ("NO SEED - COPY ONE" / "BAD SEED - CHECK COPY")
		# IN the plate as the second line, next to the row's red status stripe — so the message
		# rides the BUTTON, not only the right margin. A denied flash brightens it. When the plate
		# is too short to stack the line, fall through to the right-margin hint below (no fallback
		# on the name's line here: the focused row's label is the clipboard ECHO, not the fixed
		# name, so a same-line tag could collide with it). The preview<0 branch of seed_hint_lines
		# is single-line by construction (the two-line case is armed+valid, never invalid), so
		# lines[0] IS the whole error copy — no dropped tail.
		var ecol := deny_col
		if flash_here:
			# SAME brighten target as the stripe. Under Reduce Motion _seed_flash_amt() steps
			# to a steady full-strength bright while the flash is live (no per-frame decay), so
			# the denied press still lands a high-contrast cue on the in-plate error copy too.
			ecol = deny_col.lerp(SEED_DENY_FLASH_BRIGHT, _seed_flash_amt())
		if _draw_seed_subline(r, cy, lines[0], ecol, false) == SEED_SUB_STACKED:
			return   # error copy now rides in-plate; skip the redundant right-margin hint
	var hcol := Color(0.84, 0.86, 0.78, 0.75)
	if flash_here:
		# a brief BRIGHTEN that settles cleanly back INTO the resting deny colour, so there
		# is no brightness pop when the flash ends. Reduce Motion holds a steady bright step
		# (via _seed_flash_amt) so the denied press still reads instead of snapping to resting.
		hcol = deny_col.lerp(Color(1.0, 0.78, 0.6), _seed_flash_amt())
	elif _seed_preview >= 0:
		hcol = Art.safe(Color(1.0, 0.88, 0.4)) if armed_here else Art.safe(Color(0.55, 0.95, 0.5))
	else:
		hcol = deny_col   # red = nothing usable to paste
	# Plate sized from the WIDEST line; a right-margin plate clamped inside the 20..620
	# chrome frame so no line runs off-screen or back over the button. A 2-line armed hint
	# stacks upward so its baseline row stays aligned with cy.
	var hw := 0.0
	for ln in lines:
		hw = maxf(hw, f.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x)
	var hx := seed_hint_x(r.end.x, hw)
	var line_h := f.get_ascent(8) + f.get_descent(8) + 2.0
	var n := lines.size()
	var hby := cy + 3.0 - float(n - 1) * line_h   # first baseline; extra lines drop below it
	var ptop := hby - f.get_ascent(8) - 1.0
	var ph := float(n) * line_h + 3.0
	_emit_rect(Rect2(hx - 4.0, ptop, hw + 8.0, ph), Color(0.03, 0.05, 0.03, 0.72))
	for li in n:
		_emit_label(lines[li], Vector2(hx, hby + float(li) * line_h), hcol)


static func seed_hint_x(row_end_x: float, hw: float) -> float:
	# c1-14: left x of the CHALLENGE SEED hint text. Sits just past the row's right
	# edge, but clamps so the plate (drawn hx-4 .. hx+hw+4) can't run off the 616px
	# chrome-frame right edge — even the longest valid int64 seed stays fully framed.
	return minf(row_end_x + 6.0, 616.0 - hw)


func _update_seed_preview(delta := 0.0, force := false) -> void:
	# c1-14: parse the clipboard OFF the draw path — sampled here while the CHALLENGE
	# SEED row is focused, THROTTLED to ~5x/s (a stale clipboard read every frame is
	# wasteful), re-parsed only when the raw text actually changes, and cleared the
	# instant focus leaves the row so activation can never commit a seed the player
	# didn't see. `force` (activation) takes an immediate read. _draw only reads.
	if _is_seed_row():
		_seed_poll_t -= delta
		if not force and _seed_poll_t > 0.0:
			return   # inside the throttle window — keep the last sampled preview
		_seed_poll_t = 0.2
		var raw: String = main._clipboard_text()
		if raw != _seed_clip_raw:
			_seed_clip_raw = raw
			_seed_preview = main._parse_seed_text(raw)
			if _seed_preview >= 0:
				_seed_flash = 0.0   # a valid seed is now shown — kill any stale deny flash so it can't hide it
			if _seed_preview != _seed_armed_val:
				_seed_armed = false   # the shown seed changed — a prior arm no longer applies
			_mark_dirty()   # the sampled preview changed — repaint even if the caller doesn't
	elif _seed_preview != -1 or not _seed_clip_raw.is_empty() or _seed_armed or _seed_poll_t != 0.0:
		_seed_preview = -1
		_seed_clip_raw = ""
		_seed_armed = false   # focus left the row — cancel the arm (no stale confirm)
		_seed_poll_t = 0.0    # re-arm the throttle so the next focus samples immediately


func _activate_seed() -> void:
	# c1-14: refresh SYNCHRONOUSLY first — a mouse/touch click can select AND activate
	# this row in one input event, before the next _process poll runs, so re-read the
	# clipboard here (this also disarms if the clipboard changed since arming). _process
	# keeps the preview fresh for the keyboard/pad path.
	_update_seed_preview(0.0, true)   # force an immediate read past the throttle
	# _seed_preview < 0 is an unambiguous "nothing valid was on show," so we deny (buzz
	# + red hint flash) instead of silently doing nothing — the old path looked
	# identical to a still-pending read.
	if _seed_preview < 0:
		main._sfx.play("deny", -8.0)
		_seed_flash = 1.0   # c3-13: drives the RED PLATE-WASH BRIGHTEN in _draw (on top of the
		                    # persistent invalid tint) so the denied press recoils the whole button
		_seed_armed = false
		_mark_dirty()
		# c2-12: the deny needs no center toast — the FOCUSED row already carries full inline
		# feedback: the label echoes the raw clipboard text (see seed_row_label) so the player
		# sees WHAT was read, and the right-margin hint says WHY it was rejected ("NO SEED -
		# COPY ONE" vs "BAD SEED - CHECK COPY"), alongside the red flash + deny buzz.
		return
	# Two-press verify: a run loads ONLY on a second press that confirms the SAME seed
	# the arm is already displaying ("SEED N  PRESS AGAIN"). This gives a genuine chance
	# to read the seed before it commits, and a clipboard that changed between the arm
	# and the confirm re-arms on the new value (shown first) instead of launching blind.
	if _seed_armed and _seed_preview == _seed_armed_val:
		main._sfx.play("buy", -8.0)   # confirm: the plate showed this exact seed
		main.start_seeded(_seed_armed_val)
		_seed_armed = false
		return
	_seed_armed = true
	_seed_armed_val = _seed_preview
	_seed_armed_t = 2.5   # auto-disarm window (decremented in _process)
	_seed_flash = 0.0     # arming shows the seed — a stale deny flash must not colour over it
	main._sfx.play("pickup", -10.0, 1.2)   # soft arm tick: the seed is now shown to confirm
	_mark_dirty()


static func _content_well(scrim_mode: int) -> bool:
	# a3-02: HALL/HOWTO are bordered CONTENT screens — they get a solid dark interior
	# well behind the chrome frame so the attract firefight can't bleed through the
	# frame texture's transparent regions. PAUSE recedes via scrim ALONE (no well), so
	# the frozen run stays faintly readable behind the settings list.
	return scrim_mode == Mode.HALL or scrim_mode == Mode.HOWTO


static func _content_well_rect() -> Rect2:
	# The interior fill, inset inside the Rect2(20,8,600,344) chrome frame so the frame's
	# decorative border still draws over its own edge (chrome is drawn AFTER the well).
	return Rect2(30, 17, 580, 326)


static func _scrim_alpha(scrim_mode: int, motion: float) -> float:
	# The backdrop scrim for each menu screen (before the _open_t settle envelope).
	# TITLE keeps the attract fight mostly visible; the title stack near-blacks under
	# REDUCE MOTION (the live scroll/tracers are the biggest motion source on the exact
	# screen hosting that toggle). PAUSE keeps its frozen run readable.
	var sa := 0.55 if scrim_mode == Mode.TITLE else 0.6
	if scrim_mode != Mode.PAUSE and motion < 0.5:
		sa = 0.92
	# a3-02: HALL/HOWTO are dedicated content screens, not the attract stage — at the
	# default 0.6 scrim the live firefight (enemies/tracers/bunker) bled through the
	# frame behind the score table & instructions. Seal them near-opaque regardless of
	# motion. PAUSE recedes its frozen field harder (0.6->0.74) so it reads as its own
	# space, but stays legible enough to still study your run behind the menu.
	if scrim_mode == Mode.HALL or scrim_mode == Mode.HOWTO:
		sa = maxf(sa, 0.9)
	elif scrim_mode == Mode.PAUSE:
		sa = maxf(sa, 0.74)
	return sa


func _draw() -> void:
	if mode == Mode.HIDDEN or main == null:
		return   # c3-07: nothing to draw without main (reads main._motion / _menu_items below)
	_dirty = false   # c2-09: this paint reflects the latest state; _process re-marks on change
	# Scrim ≥0.55: 8px text over a LIVE firefight; fades in over the open settle.
	# REDUCE MOTION near-blacks the TITLE backdrop — the live attract fight
	# (scroll + tracers + explosions) is the biggest motion source on the exact
	# screen where the setting is toggled, and it isn't _motion-gated itself.
	var sa := _scrim_alpha(mode, main._motion)
	draw_rect(Rect2(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT), Color(SCRIM_BASE, sa * _open_t))
	if _content_well(mode):
		# Plate the bare text on the Apocalypse frame, debrief-style (underlay
		# darkens the well, frame carries the chrome).
		var fr := Rect2(20, 8, 600, 344)
		# a3-02: a SOLID desaturating dark well seals the frame INTERIOR before the
		# chrome — the _under frame texture has transparent regions the firefight showed
		# through even at a high scrim. Cool-dark near-opaque fill; the frame draws on top.
		draw_rect(_content_well_rect(), Color(WELL_BASE, 0.92 * _open_t))
		draw_texture_rect(Art.tex("ui_frame_lrg_under"), fr, false, Color(FRAME_UNDER_TINT, FRAME_UNDER_TINT.a * _open_t))
		draw_texture_rect(Art.tex("ui_frame_lrg"), fr, false, Color(FRAME_TINT, _open_t))
		if mode == Mode.HALL:
			_draw_hall()
		else:
			_draw_howto()
		_draw_back_button()
		_footer_legend()   # c4-05: HALL / HOWTO carry the same device-aware bindings strip
		return
	if mode == Mode.TITLE:
		# a2-04 AD#3: the largest word was drawn BARE over the live attract firefight (a
		# red blast muddied the "I"); plate it like its tagline/BEST/CAREER siblings.
		var ttw := Art.font().get_string_size("SHOEMONEY SOLDIER", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_WORDMARK_FONT).x
		draw_rect(Rect2(CENTER_X - ttw / 2.0 - 10.0, TITLE_WORDMARK_TOP, ttw + 20.0, TITLE_WORDMARK_H), PLATE_BG)   # a2-04 r2: match sibling plate alpha
		_center_text("SHOEMONEY SOLDIER", title_baseline(TITLE_WORDMARK_TOP, TITLE_WORDMARK_H, TITLE_WORDMARK_FONT), TITLE_WORDMARK_FONT, HEADER_ACCENT)
		# Studio byline, plated like the tagline below it (small text loses to the live
		# attract firefight no matter the alpha — the codebase's thrice-cited lesson).
		var byl := "by SHOEMONEY GAME STUDIOS"
		var bylw := Art.font().get_string_size(byl, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_BYLINE_FONT).x
		draw_rect(Rect2(CENTER_X - bylw / 2.0 - PLATE_PAD_SM, TITLE_BYLINE_TOP, bylw + PLATE_PAD_SM * 2.0, TITLE_BYLINE_H), PLATE_BG)
		_center_text(byl, title_baseline(TITLE_BYLINE_TOP, TITLE_BYLINE_H, TITLE_BYLINE_FONT), TITLE_BYLINE_FONT, BYLINE_COL)
		# Tagline + BEST get the same measured dark plate as their CAREER/legend/
		# seed-hint siblings — small text straight on the live attract firefight
		# loses to bright terrain no matter the alpha (the codebase's own thrice-
		# cited lesson; a white explosion drops the gold line under 2:1 contrast).
		var tagline := "ONE HIT. ONE WAR CHEST. NO MERCY."
		var tgw := Art.font().get_string_size(tagline, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_TAGLINE_FONT).x
		# The tagline plate abuts the BEST plate below it (BEST top == tagline bottom),
		# derived from the shared TITLE_RECORD_PLATE_H so the seam can't double-darken.
		draw_rect(Rect2(CENTER_X - tgw / 2.0 - PLATE_PAD_SM, TITLE_TAGLINE_TOP, tgw + PLATE_PAD_SM * 2.0, TITLE_RECORD_PLATE_H),
			PLATE_BG)
		_center_text(tagline, title_baseline(TITLE_TAGLINE_TOP, TITLE_RECORD_PLATE_H, TITLE_TAGLINE_FONT), TITLE_TAGLINE_FONT, TAGLINE_COL)
		# Read order: title → tagline → BRIGHT record line → dim CAREER → menu.
		# c1-02: the record block is a tight two-line stack (BEST then CAREER) abutting the
		# tagline, freeing height so the button column starts higher and every TITLE state clears
		# a >=20px plate instead of the old crush. _row_geometry's TITLE top tracks title_head_bottom,
		# which derives from these same plate tops+heights, so the column follows the record stack.
		if main.best_score > 0:
			# a2-04 HUD#8: only show the record fields that are non-zero (via a testable
			# helper) — a fresh best reads as a real record, not "WAVE 0 · 0m" debug dump.
			var best_line := _best_line(main.best_score, main.best_wave, main.best_dist)
			var bw := Art.font().get_string_size(best_line, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_BEST_FONT).x
			draw_rect(Rect2(CENTER_X - bw / 2.0 - PLATE_PAD_SM, TITLE_BEST_TOP, bw + PLATE_PAD_SM * 2.0, TITLE_RECORD_PLATE_H),
				PLATE_BG)
			_center_text(best_line, title_baseline(TITLE_BEST_TOP, TITLE_RECORD_PLATE_H, TITLE_BEST_FONT), TITLE_BEST_FONT, BEST_LINE_COL)
		if main._life_runs > 0:
			var wpct: int = main._life_wins * 100 / main._life_runs
			var career := "CAREER — %d RUNS · %d KILLS · %d%% WON" % [main._life_runs,
				main._life_kills, wpct]
			# Plated like the input legend: 8px dim text straight on the live
			# attract firefight loses to bright terrain no matter the alpha.
			var cpw := Art.font().get_string_size(career, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_CAREER_FONT).x
			draw_rect(Rect2(CENTER_X - cpw / 2.0 - PLATE_PAD_SM, TITLE_CAREER_TOP, cpw + PLATE_PAD_SM * 2.0, TITLE_CAREER_PLATE_H),
				PLATE_BG)
			_center_text(career, title_baseline(TITLE_CAREER_TOP, TITLE_CAREER_PLATE_H, TITLE_CAREER_FONT), TITLE_CAREER_FONT, CAREER_COL)
	elif mode == Mode.OPTS:
		_draw_opts_header()
	elif mode == Mode.REBIND:
		_draw_rebind_header()
	elif mode == Mode.INFO:
		_center_text("INFO", HUB_HEADER_Y, 22, HEADER_COL)
		# The look-back screens: records, the field manual, and your last run.
		_center_text("RECORDS · HOW TO PLAY · REPLAY", HUB_SUBTITLE_Y, 8, SUBTITLE_COL)
	elif mode == Mode.DISP:
		_center_text("DISPLAY", HUB_HEADER_Y, 22, HEADER_COL)
		# c1-19: the subtitle NAMES the two controls while windowed, and while FULLSCREEN it EXPLAINS
		# that WINDOW SCALE applies on return to windowed — so the row's deferred behavior is spelled
		# out in words, matching the inline "(WINDOWED)" tag on the value label. The row itself stays
		# fully adjustable in both modes; nothing here is a dead, silently-ignored control.
		_center_text(disp_subtitle(main._fullscreen, main._win_scale, main._win_scale_norm()), HUB_SUBTITLE_Y, 8, SUBTITLE_COL)
	elif mode == Mode.SETUP:
		_center_text("SETUP", HUB_HEADER_Y, 22, HEADER_COL)
		# c2-04: the hub for everything demoted off TITLE — the run config toggles plus
		# the OPTIONS and INFO screens.
		_center_text("RUN CONFIG  ·  OPTIONS  ·  INFO", HUB_SUBTITLE_Y, 8,
			SUBTITLE_COL)
	else:
		_center_text("PAUSED", PAUSE_HEADER_Y, 22, HEADER_COL)
		# Pause doubles as a status check — the run so far.
		if main.sim != null:
			var s: SimWorld = main.sim
			var opened := 0
			for g in s.gates:
				if g["open"]:
					opened += 1
			var line := "WAVE %d" % s.wave if s.mode == "endless" \
				else "SECTOR %d/5  ·  %dm" % [mini(opened + 1, 5), -Fixed.to_int(s.camera_top) / 10]
			_center_text("SCORE %d  ·  CHEST %d  ·  %s" % [s.score, s.war_chest, line],
				PAUSE_SUBTITLE_Y, 10, SUBTITLE_COL)
			if main._current_seed > 0:
				_center_text("RUN #%d" % main._current_seed, PAUSE_FOOTNOTE_Y, 8, RUN_FOOTNOTE_COL)
	var mitems := _menu_items()   # dicts: label + destructive flag for pre-press tinting
	var items := _items()
	# Fit-to-height layout via the shared helper (the mouse hit-test reads the
	# SAME numbers — drift here means hover selects the wrong row).
	var g := _row_geometry()
	var gap: float = g["gap"]
	var bh: float = g["bh"]
	# Open settle: rows drop the last 12px into place as the scrim fades in (offset applied
	# inside _row_geometry so the mouse hit-test tracks it). Row y's come from row_rect(g, k)
	# now — the single geometry source — so the c3-03 split offset can't drift a plate off
	# its hit box.
	# c3-03: back the primary DEPLOY block (grp 0 start verbs) with a raised panel so the
	# four ways to start a run read as ONE dominant cluster — the screen's clear focus — not
	# the top of a flat column that bleeds into the secondary SETUP/QUIT rows. Pure paint
	# bounded by the SHARED row geometry (row_rect), so it tracks the drop-in settle and never
	# perturbs the hit-test. Drawn BEFORE the plates so they layer on top of the backing.
	if mode == Mode.TITLE:
		var plast := 0
		for k in mitems.size():
			if int(mitems[k].get("grp", 0)) == 0:
				plast = k
		# c3-03: panel rect via the shared pure helper so _draw and the layout test read
		# ONE geometry — the test can prove the panel never rides into the record header.
		var head_b := title_head_bottom(main.best_score > 0, main._life_runs > 0)
		var panel := title_deploy_panel(g, plast, head_b)
		draw_rect(panel, Color(PANEL_FILL, PANEL_FILL.a * _open_t))
		draw_rect(panel, Color(PANEL_BORDER, PANEL_BORDER.a * _open_t), false, 1.0)
	for k in items.size():
		# floorf: fractional row pitch (gap 19.25/17.11) put every plate and its
		# pixel-font label on half-pixels — soft seams on an otherwise crisp UI.
		var r := row_rect(g, k)
		# Whole-pixel row center: bh is odd on PAUSE (21) and 11-row TITLE (11), so
		# every bh/2-derived y (label baseline, state dot, arrows, confirm glyph)
		# landed on .5 — the exact sub-pixel shimmer _sel_y snapping guards against.
		var cy := floorf(r.position.y + bh / 2.0)
		# Group divider: a faint rule in the gap above each "grp" boundary —
		# RESUME/settings/destructive on PAUSE, starts/toggles/meta/quit on TITLE —
		# hierarchy cue without touching the shared row geometry/hit-test.
		if k > 0 and k < mitems.size() \
				and mitems[k].get("grp", 0) != mitems[k - 1].get("grp", 0):
			# c3-03: CENTER the rule in the ACTUAL gap above this row — derived from the two
			# plate edges (prev bottom -> this top) via row_rect, the single geometry source.
			# At the DEPLOY->MORE split that gap is enlarged by split_gap, so measuring the real
			# edges centers the rule in the WHOLE enlarged band; assuming the plain (gap - bh)
			# pitch left it riding split_gap/2 too low, hugging the secondary block.
			var this_top := row_rect(g, k).position.y
			var prev_bottom := row_rect(g, k - 1).position.y + bh
			var sy := this_top - floorf((this_top - prev_bottom) / 2.0)
			# c2-04: the "primary vs secondary" split gets a brighter, full-width rule so
			# it reads as the dominant boundary. On TITLE that is start-verbs (grp 0) ->
			# the SETUP hub (grp 1): the four start rows (CAMPAIGN / ENDLESS / DAILY /
			# SEED) stand apart as one block from SETUP / QUIT. On the SETUP screen the
			# same brightened rule marks run-config (grp 0) -> the OPTIONS/INFO screens
			# (grp 1). Every other boundary keeps the faint hierarchy rule. Geometry and
			# hit-test are untouched — this is a pure paint cue in the existing gap.
			if (mode == Mode.TITLE or mode == Mode.SETUP) \
					and int(mitems[k - 1].get("grp", 0)) == 0 \
					and int(mitems[k].get("grp", 0)) == 1:
				draw_rect(Rect2(CENTER_X - BTN.x / 2.0 + 6.0, sy, BTN.x - 12.0, 1.0),
					DIVIDER_BRIGHT)
			else:
				draw_rect(Rect2(CENTER_X - BTN.x / 2.0 + 12.0, sy, BTN.x - 24.0, 1.0),
					DIVIDER_DIM)
		# c3-03: OPTS labels its settings sections; TITLE labels its DEPLOY / MORE
		# IA blocks — both through the shared caption emitter, drawn at each group's
		# first row so the primary start verbs read as their own named block.
		if (mode == Mode.OPTS or mode == Mode.TITLE) \
				and (k == 0 or mitems[k].get("grp", 0) != mitems[k - 1].get("grp", 0)):
			_emit_group_caption(mitems, k, cy)
		var selected := k == sel
		var destr: bool = k < mitems.size() and mitems[k].get("destructive", false)
		var disabled: bool = k < mitems.size() and mitems[k].get("disabled", false)
		# armed REQUIRES destr: a stale/desynced _confirm landing on a non-destructive
		# row must never enter the armed render path (which reserves the confirm glyph
		# and floods red) — that would draw a null glyph. destr guarantees armed_glyph.
		var armed := destr and _confirm == k
		draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
		# Destructive rows (RESTART / TITLE / QUIT) tint the WHOLE plate warm, not
		# just the label — so they never read as a plain single-press action beside
		# CAMPAIGN / RESUME. The tint is DARK warm on purpose: light warm label text
		# over it clears an AA-normal (4.5:1) contrast target (a mid warm plate washed the
		# warm label out — see test_destructive_text_contrast). Arming floods red.
		var plate := PLATE_SEL if selected else PLATE_UNSEL
		if destr:
			if selected:
				plate = DESTR_ARMED_PLATE_SEL if armed else DESTR_PLATE_SEL
			else:
				plate = DESTR_ARMED_PLATE_UNSEL if armed else DESTR_PLATE_UNSEL
		elif disabled:
			plate = DISABLED_PLATE   # c2-13: dim, so a locked row can't read as actionable even while focused
		draw_texture_rect(Art.tex("ui_menu_button"), r, false, plate)
		if disabled:
			# c2-13: extra scrim over the plate interior so the icon + label read muted too —
			# the row is clearly "unavailable", not just a differently-tinted button.
			draw_rect(r.grow(-3), Color(0.02, 0.04, 0.02, 0.45))
		# c3-13: focused seed row with nothing usable on the clipboard gets a PERSISTENT red
		# validation marker — a thin left-edge stripe over a faint veil, deliberately UNLIKE the
		# destructive armed FULL flood so it can't be mistaken for an armed RESTART/QUIT. A denied
		# press widens/brightens it (via _seed_flash); Reduce Motion holds it steady. Drawn before
		# the icon/label so the light text stays on top, and the veil is far below the flood's
		# alpha so contrast holds. The specific NO SEED / BAD SEED copy rides in-plate via
		# _draw_seed_hint (right-margin hint is the short-plate fallback).
		if selected and mitems[k]["id"] == "paste_seed" and _seed_preview < 0:
			var dw := _seed_flash_amt()   # Reduce Motion: a steady bright/wide step, not a suppressed no-op
			var veil := SEED_DENY_RED
			veil.a = SEED_DENY_VEIL_A + 0.08 * dw
			draw_rect(r.grow(-3), veil)
			var bar := SEED_DENY_RED.lerp(SEED_DENY_FLASH_BRIGHT, dw)   # a denied press BRIGHTENS the stripe
			bar.a = SEED_DENY_BAR_A
			draw_rect(Rect2(r.position.x + 3.0, r.position.y + 3.0,
				SEED_DENY_BAR_W + 2.0 * dw, r.size.y - 6.0), bar)   # ...and WIDENS it
		if armed:
			# Armed red flood drawn FIRST — before the bracket, icon and selection
			# glow — so those cues layer ON TOP of the wash instead of being washed
			# out by it. A strong (near-opaque) fill: the old 0.4 wash over the whole
			# thing barely shifted the plate. Slow pulse pulls the eye; reduce-motion
			# snaps it steady. The countdown bar + confirm glyph land later, on top.
			# Alpha stays high across the pulse (0.82..0.98) so the near-white armed
			# label keeps its measured contrast over the flood at BOTH pulse extremes,
			# not just the trough — the underplate barely reads through either way.
			var apulse := 0.0 if main._motion < 0.5 else Art.pulse(0.25)
			var flood := DESTR_ARMED_FLOOD
			flood.a = 0.82 + 0.16 * apulse
			draw_rect(r.grow(-3), flood)
			# c2-15: a bright warning keyline banding the top edge of the flood — a
			# high-contrast plate cue so the armed row reads as an ALERT the instant it
			# arms, not merely a redder tint of its pre-armed self. Pulses with the flood.
			var kline := DESTR_ARMED_KEYLINE
			kline.a = 0.85 + 0.15 * apulse
			# Inset to the frame's inner edge (and snapped to whole pixels) so the amber
			# border rings it cleanly and the 2px band stays crisp on the 360px canvas.
			draw_rect(Rect2(roundf(r.position.x + DESTR_ARMED_FRAME_W), roundf(r.position.y + DESTR_ARMED_FRAME_W),
				roundf(r.size.x - 2.0 * DESTR_ARMED_FRAME_W), 2.0), kline)
		if destr:
			# A warm bracket outlines destructive rows even BEFORE arming — a shape
			# cue (not hue alone) that this row discards the run, unlike its
			# neighbors. It thickens and brightens once armed.
			# Pre-armed warm hairline bracket. The armed row instead gets a THICK amber
			# frame drawn in the armed-affordances block below, so it rings the row ON TOP
			# of the flood / keyline / countdown bar and dominates as the alert.
			if not armed:
				draw_rect(r.grow(-2), Color(1.0, 0.55, 0.35, 0.55), false, 1.0)
		# Modern Menus ortho icon where a row has a clean match (toggles swap
		# by live state) — rows without one just stay text.
		var icon := _row_icon(mitems[k]["id"])
		if icon != "":
			# Track the row: a taller decompressed row earns a bigger icon instead
			# of pinning to an 8px speck. bh-3 keeps a 1px breath each side; 9px
			# floor still centers cleanly in the worst-case 11px crush row.
			var isz := clampf(bh - 3.0, 9.0, 16.0)
			draw_texture_rect(Art.tex(icon), Rect2(Vector2(r.position.x + 9.0,
				r.position.y + (bh - isz) / 2.0), Vector2(isz, isz)), false,
				Color(1, 1, 1, 0.35 if disabled else (1.0 if selected else 0.7)))
		if selected:
			# Breathing selection glow that GLIDES between rows instead of teleporting
			# (the ease itself runs framerate-independent in _process). Stilled under
			# REDUCE MOTION — the pause menu is where a motion-sensitive player lives.
			# c3-03: off row_rect so the glide target tracks a split row's shifted y (an
			# un-split top+k*gap would leave the glow behind on the secondary block).
			var ty := row_rect(g, k).position.y
			_sel_target = ty
			if _sel_y < 0.0 or main._motion < 0.5:
				_sel_y = ty
			var gr := Rect2(Vector2(CENTER_X - BTN.x / 2.0, _sel_y), Vector2(BTN.x, bh))
			var mp := 0.0 if main._motion < 0.5 else Art.pulse(0.2)
			# Fade the glow while it's still catching up to the row — a lagging box
			# at full alpha reads as misplaced; dimming it makes the glide read as motion.
			var lag := clampf(absf(_sel_y - _sel_target) / 40.0, 0.0, 1.0)
			# Skip the AMBER glow while armed: the red flood + bright bracket already
			# mark the armed row hard, and the amber wash on top would fight (and dull)
			# the red danger treatment. Selection still tracked above for the glide.
			# c2-13: no amber "actionable" glow on a locked row — the crisp focus ring
			# (drawn below) still shows WHERE focus is without implying the row will act.
			if not armed and not disabled:
				draw_texture_rect(Art.tex("ui_menu_button_sel"), gr.grow(3.0 + mp * 1.5), false,
					Color(1.0, 0.9, 0.4, (0.7 + mp * 0.3) * (1.0 - 0.5 * lag)))
		var col := Color(1.0, 0.95, 0.75) if selected else Color(0.8, 0.84, 0.74)
		if disabled:
			col = DISABLED_TEXT   # c2-13: muted label completes the dim/locked read
		var label: String = items[k]
		var label_r := r.end.x - 8.0   # label right bound (shrinks for the confirm glyph)
		# c2-13: reserve the right-edge status-badge slot BEFORE the label is fit, so the
		# label ellipsizes clear of the badge and the two can never overlap (same discipline
		# as the submenu-chevron reservation below).
		var badge: String = String(mitems[k].get("badge", ""))
		var badge_w := 0.0
		if badge != "":
			badge_w = Art.font().get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			label_r = minf(label_r, r.end.x - badge_w - 12.0)
		var armed_glyph: Texture2D = null
		var cw := 0.0
		if destr:
			# LIGHT warm label so it stays legible on the dark warm plate (a warm-dim
			# label on a warm plate failed the contrast target). The dark plate + warm
			# label together read "danger" while staying readable.
			col = DESTR_TEXT_SEL if selected else DESTR_TEXT_UNSEL
			if armed:
				col = DESTR_ARMED_TEXT   # near-white reads over the red flood below
				# c3-08: DEVICE-CORRECT confirm glyph - Art.glyph_key("confirm") resolves to
				# Enter for the keyboard/mouse player and the pad's A/cross for a gamepad,
				# keyed off the LAST-USED device (Art.use_pad), so a keyboard player is never
				# prompted with a pad button they don't have. Reserve its right-edge slot
				# BEFORE choosing wording so the label is fit to the real drawable width.
				# minf so this composes with any earlier badge reservation instead of
				# clobbering it (destructive rows carry neither badge nor submenu chevron
				# today, so the glyph slot is the only right-edge claim in practice).
				armed_glyph = Art.tex(Art.glyph_key("confirm"))
				# Only reserve the glyph slot if the texture actually resolved; a missing
				# key leaves cw = 0 so the label keeps the FULL width and the row degrades to
				# a text-only "<VERB>  PRESS AGAIN" prompt instead of crashing on get_width().
				if armed_glyph:
					cw = 12.0 * float(armed_glyph.get_width()) / float(armed_glyph.get_height())
					label_r = minf(label_r, r.end.x - cw - 10.0)
			# c3-08: KEEP THE ACTION NAME on the armed row - never a bare, ambiguous
			# "PRESS AGAIN". The armed verb is derived from the row id via armed_verb()
			# (RESTART / TITLE / QUIT / RESET DEFAULTS / RESET CONTROLS) - one naming
			# convention shared with the layout test, not a parallel "verb" field that could
			# drift. destructive_label keeps this verb (or its leading word) as the plate
			# narrows, so the player always sees WHICH action is one press from firing. Pick
			# the widest wording that fits the plate (measured) so the cue never ellipsizes to
			# nonsense: "<NAME>  PRESS TWICE" pre-armed, "<VERB> PRESS AGAIN" armed, degrading
			# only as far as needed. See destructive_label.
			label = destructive_label(items[k], armed_verb(mitems[k]), armed, Art.font(),
				label_r - (r.position.x + 30.0))
		if armed:
			# The armed affordances that ride ON TOP of the red flood (drawn above):
			# a countdown bar draining along the bottom edge showing the disarm
			# window, and the device confirm glyph in its reserved right slot.
			# c2-15: a full-width DARK track under a THICK (4px) bright fill — 2px on a
			# 360px canvas was too easy to miss. The track makes the drained portion
			# read as a gauge (not a stray sliver), the height makes the arm unmissable.
			# Bar/track inset to the frame's inner edge (whole-pixel snapped) so the amber
			# border rings them cleanly instead of the fill painting over the bottom border.
			var bar_x := roundf(r.position.x + DESTR_ARMED_FRAME_W)
			var bar_w := roundf(r.size.x - 2.0 * DESTR_ARMED_FRAME_W)
			var bar_y := roundf(r.end.y - DESTR_ARMED_FRAME_W - DESTR_ARMED_BAR_H)
			draw_rect(Rect2(bar_x, bar_y, bar_w, DESTR_ARMED_BAR_H), DESTR_ARMED_BAR_TRACK)
			draw_rect(Rect2(bar_x, bar_y,
				roundf(bar_w * clampf(_confirm_t / 2.5, 0.0, 1.0)), DESTR_ARMED_BAR_H),
				DESTR_ARMED_BAR_FILL)
			# c2-15: the thick amber frame rings the row ON TOP of the flood / keyline /
			# countdown bar, so it dominates as the alert. Only the device confirm glyph
			# rides above it (below), landing crisp in its reserved inner slot.
			draw_rect(r.grow(-2), DESTR_ARMED_FRAME, false, DESTR_ARMED_FRAME_W)
			# c3-08: throb the DEVICE-CORRECT confirm glyph (Enter for keyboard/mouse, A for
			# pad - see Art.glyph_key above) so a hesitating player's eye lands on the exact
			# button that fires the armed verb (RESTART / TITLE / QUIT, kept in the label).
			# The pulse rides amber->white to read as "act now". Honors the REDUCE MOTION
			# accessibility setting (main._motion < 0.5) by holding the glyph steady + bright.
			# The confirm glyph is an ENHANCEMENT, not the only cue: the label already spells
			# out "PRESS AGAIN" in words, so a missing/unsupported glyph key degrades to a
			# fully textual prompt rather than a blank. Guard against a null texture anyway
			# (a desynced armed-on-non-destr row, or a glyph key with no registry entry).
			if armed_glyph:
				var reduce_motion: bool = main._motion < 0.5
				var gp := 1.0 if reduce_motion else Art.pulse(0.35)
				draw_texture_rect(armed_glyph, Rect2(r.end.x - cw - 6.0, cy - 6.0, cw, 12.0), false,
					Color(1.0, 0.85 + 0.15 * gp, 0.5 + 0.5 * gp, 0.7 + 0.3 * gp))
		# Rows that open a screen reserve a right-edge slot for the > chevron so a
		# long label ellipsizes clear of it instead of colliding.
		if mitems[k].get("submenu", false):
			label_r = minf(label_r, r.end.x - 20.0)
		# c3-13: at-rest seed row on a SHORT plate rides its "(FROM CLIPBOARD)" tag on the
		# name's line (see _draw_seed_subline). Reserve that right-aligned slot HERE — same
		# discipline as the badge/chevron reservations — so the name ellipsizes clear of the
		# tag instead of the tag being omitted when the name is too long. Only when NOT stacking
		# (tall plates keep the full name width and stack the tag below) and NOT focused (the
		# focused row shows live status via _draw_seed_hint, not the resting tag).
		if mitems[k]["id"] == "paste_seed" and not selected and not _seed_tag_stacks(r, cy):
			var seed_tag_w := Art.font().get_string_size(SEED_SOURCE_COPY, HORIZONTAL_ALIGNMENT_LEFT, -1, SEED_TAG_SIZE).x
			label_r = minf(label_r, r.end.x - SEED_SUB_PAD - seed_tag_w - SEED_SUB_GAP)
		# Fixed icon gutter: iconless rows indent the same, so every label
		# left-aligns to one column. Overlong labels ellipsize inside the button.
		var lx := r.position.x + 30.0
		var avail := label_r - lx
		# c2-14: overflow flag — when a label doesn't fit its column, mark it with a
		# clipped-tail badge at the right edge: a bordered dark chip carrying three bright
		# amber dots (an ellipsis mark) so an over-width row is spottable at a glance (QA +
		# players) on ANY background — the selected plate, the red armed flood — where a
		# thin amber underline would wash out. Three dots are deliberately NOT an arrow, so
		# the flag can't be misread as the submenu chevron (that outline arrow lives in its
		# own far-right slot). The truncation must never read as the real label. Measure
		# once to decide overflow, then ellipsize ONCE into the width that reserves the
		# chip's footprint (a clear gap before the chip) so the text is never covered.
		# Reserve the chip's footprint (its width from label_r, plus OVERFLOW_CHIP_PAD of
		# breathing room) DERIVED from the chip rect itself, so the reserved gap can't
		# drift out of sync with the chip geometry.
		var chip := _overflow_chip_rect(label_r, cy)
		var reserve := (label_r - chip.position.x) + OVERFLOW_CHIP_PAD
		# _row_fit memoizes the (overflow, shown, chip?) decision keyed on label+size+avail,
		# so a persistently-visible row is measured/ellipsized ONCE, not every _draw frame.
		# It also clamps: the chip only shows when it actually FITS (reserve < avail), so a
		# column narrower than the chip degrades to a bare ellipsized label with no negative
		# max_w and no chip overdrawing the text.
		# c3-17: for a destructive row, mark its warning cue as a load-bearing suffix so a
		# long/localized identity ellipsizes the NAME, never clipping the "PRESS TWICE/AGAIN"
		# warning off the tail. destructive_label already fits the plate; this is the safety net
		# for the floor/localized case where the label still overflows _row_fit's column.
		var keep_tail := destructive_cue_tail(label, armed) if destr else ""
		var fit := _row_fit(label, 11, avail, reserve, keep_tail, destr)
		var show_chip: bool = fit["show_chip"]
		# max_w hard-clips as a backstop for the degenerate case (even one glyph +
		# ellipsis wider than the column) so a floor label can never overdraw the slot.
		# Art.text's 6th param is max_w (default 0.0 = no clip) — see src/view/art.gd.
		Art.text(self, String(fit["shown"]), Vector2(lx, cy + ROW_LABEL_BASELINE_DY), ROW_LABEL_SIZE, col, avail)
		if show_chip:
			draw_rect(chip, OVERFLOW_CHIP_COL)
			draw_rect(chip, OVERFLOW_CHIP_BORDER, false, 1.0)
			# Dots inset 2px from the left border and end 2px before the right border,
			# so the 1px chip outline never touches a dot. Vertically centred.
			var dy := chip.position.y + chip.size.y / 2.0 - 1.0
			for di in 3:
				draw_rect(Rect2(chip.position.x + 2.0 + float(di) * 3.0, dy, 2.0, 2.0), OVERFLOW_DOT_COL)
		# Submenu affordance: a right-pointing chevron marks rows that OPEN a screen
		# (RUN SETUP / OPTIONS / INFO / HALL / HOW TO PLAY) so they don't read as a
		# direct action or an in-place toggle. mi_arrow already points right.
		if mitems[k].get("submenu", false):
			draw_texture_rect(Art.tex("mi_arrow"), Rect2(r.end.x - 17.0, cy - 5.0, 10.0, 10.0),
				false, PLATE_SEL if selected else ARROW_UNSEL)
		# Volume rows: a 10-step level bar where the toggle dot would sit —
		# level reads as fill COUNT (shape, not hue alone); 0 = all hollow.
		if mitems[k].has("vol"):
			var vv: int = mitems[k]["vol"]
			var row_muted: bool = mitems[k].get("muted", false)
			# c3-04: ONE source of truth for the bar geometry (seg count/pitch/width) so the
			# fill loop, mute slash, rail bounce and static rail cap all derive from the same
			# numbers -- no drifting 49 / 9*5+4 magic constants. Level 0..10 maps to SEG_N
			# cells; last-cell left edge = vlast, its right edge = vlast + SEG_W.
			var SEG_N := 10
			var SEG_PITCH := 5.0
			var SEG_W := 4.0
			var vbx := r.end.x - 8.0 - (float(SEG_N) * SEG_PITCH - 1.0)   # right-aligned with the dot slot
			var vlast := vbx + float(SEG_N - 1) * SEG_PITCH               # left edge of the final cell
			for sgi in SEG_N:
				var sr := Rect2(vbx + float(sgi) * SEG_PITCH, cy - 3.0, SEG_W, 6.0)
				if sgi < vv and not row_muted:   # c3-04: a muted row is ALL-hollow, no lit cell under the slash
					draw_rect(sr, Art.safe(Color(0.55, 0.95, 0.5, 1.0 if selected else 0.8)))
				else:
					# c4-01: a muted row's empty cells draw DIMMER than a merely-turned-down
					# bar, so the whole track reads as faded/off (under the amber slash) rather
					# than "low but live" — the dim + strike + MUTED label all say the same thing.
					draw_rect(sr, Color(0.55, 0.6, 0.5, 0.28 if row_muted else 0.6), false, 1.0)
			# c3-04: a MUTED bus is drawn as an all-hollow bar struck through with a
			# diagonal slash — an explicit OFF marker so the empty bar can't read as
			# merely "turned all the way down." Keyed off the row's explicit "muted" flag
			# (the real AudioServer.is_bus_mute state), not the level number, so the marker
			# stays truthful. Drawn UNconditionally (not selection-gated, unlike the amber
			# rail cap) so a muted SFX/MUSIC row reads as off at a glance anywhere in the
			# list, matching the "MUTED" label and the silent buses.
			if row_muted:
				# Endpoints derived from the SAME geometry the bar loop uses: first seg left =
				# vbx, last seg right = vlast + SEG_W, span top/bottom = cy-3 / cy+3 -- so the
				# strike always spans the full bar even if SEG_N/PITCH/WIDTH change.
				draw_line(Vector2(vbx, cy + 3.0), Vector2(vlast + SEG_W, cy - 3.0),
					Color(1.0, 0.72, 0.3, 0.85 if selected else 0.7), 1.5)
			# Rail bounce: a nudge past the limit (mute floor or max ceiling) flashes
			# the pinned end segment amber+wider so the press reads as "held at the
			# rail," not dropped. Decays in _process; reduce-motion snaps it off.
			if selected and k == _rail_row and _rail_pulse > 0.0:
				var rx := vlast if _rail_dir > 0 else vbx   # ceiling = last cell, floor = first
				var rr := Rect2(rx, cy - 3.0, SEG_W, 6.0).grow(_rail_pulse * 1.5)
				draw_rect(rr, Color(1.0, 0.72, 0.3, 0.85 * _rail_pulse), false, 1.0)
			# STATIC rail cap: whenever the selected row SITS at a limit (MUTED or 10),
			# bracket the pinned end segment. Non-animated, so it reads even with
			# Reduce Motion on — where the bounce above is snapped off, a further
			# press at the rail would otherwise be an invisible (and, at the muted
			# floor, silent) no-op. This makes "you're at the limit" always legible.
			if selected and (vv == 0 or vv == 10):
				var cx := vlast if vv == 10 else vbx
				draw_rect(Rect2(cx, cy - 4.0, SEG_W, 8.0),
					Color(1.0, 0.72, 0.3, 0.7), false, 1.0)
			# c4-01: draw crisp CHEVRON slider arrows flanking the bar on the focused row, so the
			# left/right step affordance lives ON THE ROW (the spec's slider arrows), not only in the
			# footer glyph. Vector chevrons (not a bitmap-font "<"/">"), so they stay pixel-aligned and
			# match the bar's line weight. Each arrow DIMS when the value is pinned against its rail: the
			# left dims at the mute floor (0), the right at the ceiling (10). A lit arrow always points
			# the way the level can still move -- so a MUTED row shows a lit right chevron that reads
			# "step right to bring the bus back," matching the UNMUTE hint and the helper prose.
			if selected:
				var arw_lit := Color(1.0, 0.72, 0.3, 0.95)
				var arw_dim := Color(0.55, 0.6, 0.5, 0.35)
				var lx0 := vbx - 4.0
				draw_polyline([Vector2(lx0, cy - 3.0), Vector2(lx0 - 3.0, cy), Vector2(lx0, cy + 3.0)],
					arw_dim if vv <= 0 else arw_lit, 1.5, true)
				var rx0 := vlast + SEG_W + 4.0
				draw_polyline([Vector2(rx0, cy - 3.0), Vector2(rx0 + 3.0, cy), Vector2(rx0, cy + 3.0)],
					arw_dim if vv >= 10 else arw_lit, 1.5, true)
		# Toggle state dot at the row's right edge: filled = ON, hollow = OFF —
		# shape+fill carry the state (hue alone fails protan players).
		if mitems[k].has("on"):
			var dc := Vector2(r.end.x - 10.0, cy)
			if mitems[k]["on"]:
				draw_circle(dc, 3.0, Art.safe(Color(0.55, 0.95, 0.5)))
			else:
				draw_arc(dc, 3.0, 0, TAU, 10, Color(0.55, 0.6, 0.5, 0.8), 1.2)
		# c2-13: right-aligned status badge (e.g. COMPLETED on a locked DAILY RUN row).
		# A separate scannable slot rather than text appended to the label, drawn in its
		# reserved width (badge_w, computed above) so it can never clip the label. Tinted
		# with the disabled palette so the status reads as a MUTED lock state, not a bright
		# actionable highlight.
		if badge != "":
			Art.text(self, badge, Vector2(r.end.x - 8.0 - badge_w, cy + 3.0), 9,
				DISABLED_TEXT if disabled else Color(1.0, 0.85, 0.5, 0.85))
		# Left/right cycle affordance on the selected toggle row — toggles flipped
		# silently and read identical to action rows. mi_arrow points RIGHT;
		# a negative rect width flips it for the left side.
		if selected and _row_cycles(mitems[k]):
			var fcol := Color(1.0, 0.92, 0.55, 0.55 + 0.45 * (0.0 if main._motion < 0.5 else Art.pulse(0.2)))
			var at := Art.tex("mi_arrow")
			var arows := toggle_arrow_rects(g, k)   # shared with the mouse hit-test
			var lft := arows[0]
			# left arrow drawn flipped: start at its right edge, negative width
			draw_texture_rect(at, Rect2(lft.position.x + lft.size.x, lft.position.y, -lft.size.x, lft.size.y), false, fcol)
			draw_texture_rect(at, arows[1], false, fcol)
		if mitems[k]["id"] == "paste_seed":
			# c3-13: runs for the seed row EVERY frame, selected or not — so the at-rest in-plate
			# "(FROM CLIPBOARD)" sub-label is live, not focus-only.
			_draw_seed_hint(r, cy, selected)
		# c1-17: settings-change confirm halo — a green ring that briefly haloes the row
		# whose toggle just flipped or whose volume just stepped, so the applied change
		# reads visually (green == "applied", distinct from the amber selection glow and
		# rail bounce). Grows+fades under normal motion; Reduce Motion draws it as a
		# static (but still fading) border. Art.safe keeps it distinct under colorblind.
		# Sentinel _set_pulse_row == -2 haloes every reset-affected row at once — the
		# bulk feedback for Reset Defaults, so a mass mutation confirms like a single one.
		var pulse_here: bool = _set_pulse > 0.0 and (k == _set_pulse_row \
			or (_set_pulse_row == -2 and mitems[k]["id"] in _RESET_ROWS) \
			or (_set_pulse_row == -2 and mode == Mode.REBIND and mitems[k].get("grp", 0) == 0))
		if pulse_here:
			var still: bool = main._motion < 0.5
			# Alpha fades with the pulse in BOTH modes -- the confirm reads as a
			# fading halo, never a hard snap-off. A 2px base grow seats the ring
			# OUTSIDE the 1px focus ring drawn below, so on the selected row the halo
			# is never overdrawn (Reduce Motion, which holds grow static, would
			# otherwise be fully hidden by that focus ring). Under normal motion it
			# ALSO expands outward as it fades: grow rides elapsed progress (1 - pulse),
			# swelling 2 -> 5px; Reduce Motion holds it static at the 2px seat.
			var pa: float = _set_pulse
			var pgrow: float = 2.0 if still else 2.0 + (1.0 - _set_pulse) * 3.0
			draw_rect(r.grow(pgrow), Art.safe(Color(0.55, 1.0, 0.6, pa)), false, 2.0)
		if selected:
			# 1px focus ring on the actual row rect — always crisp and present,
			# independent of the glow glide, for keyboard/pad a11y. c2-13: a disabled
			# row keeps the ring (so focus is still locatable) but dims it so the cue
			# reads "focused, unavailable" rather than "press me".
			draw_rect(r, DISABLED_TEXT if disabled else Color(1.0, 0.97, 0.88), false, 1.0)
	if mode == Mode.TITLE:
		# Legend adapts to the last-used device and draws the REAL prompt art
		# (stick/trigger/mouse glyphs from the registry) beside each verb —
		# "RT"/"LMB" as text made every new player parse an acronym first.
		# Near-opaque dark plate: 8px text straight on the live attract
		# firefight loses to bright terrain and particles no matter the alpha.
		draw_rect(Rect2(0, LEGEND_Y, CANVAS_WIDTH, LEGEND_H), PLATE_BG)
		var row1: Array
		if Art.use_pad:
			row1 = [{"tex": "glyph_stick_l", "label": "MOVE"},
				{"tex": "glyph_stick_r", "label": "AIM"},
				{"tex": "glyph_rt", "label": "FIRE"},
				{"tex": "glyph_lb", "label": "GRENADE"},
				{"act": "roll", "label": "ROLL"}]
		else:
			row1 = [{"stamp": "WASD", "label": "MOVE"},
				{"label": "MOUSE AIM"},
				{"tex": "glyph_mouse_l", "label": "FIRE"},
				{"tex": "glyph_mouse_r", "label": "GRENADE"},
				{"act": "roll", "label": "ROLL"}]
		var row2: Array = [{"act": "interact", "label": "INTERACT"},
			{"act": "revive", "label": "REVIVE"},
			{"act": "wheel", "label": "SUPPLY WHEEL"}]
		# c3-10: teach the two meta controls the gameplay legend never named — PAUSE and the
		# HOW TO PLAY shortcut. Keyboard-only players had no on-screen cue the run is pausable
		# at all, nor a direct key to the help. Device-aware: on a pad, START opens PAUSE (help
		# is reached through the menus); on keyboard, the PAUSE keycap is DERIVED from the live
		# menu_cancel binding (never a hardcoded "ESC" literal — a rebound cancel key teaches
		# THEIR key via _back_keycap), and F1 jumps straight to HOW TO PLAY. Both stamped keycaps
		# ride the wide blank (via _glyph_w's stamp default), same grammar as the SELECT/BACK footer.
		if Art.use_pad:
			row2.append({"tex": Art.glyph_key("start"), "label": "PAUSE"})
		else:
			row2.append(_keycap_seg(_back_keycap(), "PAUSE"))
			row2.append(_keycap_seg(_help_keycap(), "HOW TO"))
		# c2-13: only advertise SELECT when the focused row can actually be activated.
		# A locked row (e.g. DAILY RUN completed) draws NO confirm cue, so the legend
		# never contradicts the dim/COMPLETED state by promising a press that only buzzes.
		if not (sel < mitems.size() and mitems[sel].get("disabled", false)):
			row2.append({"tex": Art.glyph_key("confirm"), "label": "SELECT"})
		_legend_row(row1, 330.0, 1.0)
		_legend_row(row2, 346.0, 0.9)
	else:
		# c1-04 / c4-05: every non-TITLE menu that reaches here (PAUSE / OPTS / SETUP / DISP /
		# INFO / REBIND) draws the same device-aware bindings strip through the ONE canonical
		# _footer_legend seam (HALL/HOWTO route through it too, in the content-well branch that
		# returns above) — so no menu can silently ship without a legend.
		_footer_legend()


# c1-18: the REBIND screen header — a MOVE/AIM | ACTIONS | GAMEPAD category-tab strip (each
# page <=10 rows so plates stay >=20px), the CONTROLS title, one context subline, and — on
# the GAMEPAD tab — a fixed-input note so the DISPLAYED controls match actual gameplay (the
# analog stick/trigger inputs that are never rebindable). The subline is the live capture
# prompt while listening (device-specific), the transient swap/clear notice when one is up,
# else the how-to (which DOCUMENTS the immutable arrows/Enter/Esc menu-nav fallback).
# c1-18: rect for REBIND category tab `d` — shared by the header draw and the mouse hit-test.
func _rebind_tab_rect(d: int) -> Rect2:
	var tw := REBIND_TAB_W
	var gap := REBIND_TAB_GAP
	var n := REBIND_TABS.size()
	var x0 := CENTER_X - (float(n) * tw + float(n - 1) * gap) / 2.0
	return Rect2(x0 + float(d) * (tw + gap), 42.0, tw, 15.0)


# c1-18: rect for the P1|P2 player sub-selector shown on the GAMEPAD tab (d = 0 P1, 1 P2).
# Shared by the header draw and the mouse hit-test so the plate and its click target agree.
func _rebind_pad_dev_rect(d: int) -> Rect2:
	var w := REBIND_DEV_W
	var gap := REBIND_TAB_GAP
	var x0 := CENTER_X - (2.0 * w + gap) / 2.0
	return Rect2(x0 + float(d) * (w + gap), 88.0, w, 12.0)


func _draw_rebind_header() -> void:
	var pad := not _rebind_is_kb()
	# Category tabs: the active one is a lit plate, the others dim — TAB/shoulders cycle them,
	# a mouse can click them. Draw + hit-test share _rebind_tab_rect so they can't drift.
	for d in REBIND_TABS.size():
		var r := _rebind_tab_rect(d)
		var on := d == _rebind_tab
		draw_rect(r, Color(0.14, 0.3, 0.16, 0.95) if on else Color(0.07, 0.1, 0.06, 0.7))
		draw_rect(r, Color(0.9, 0.95, 0.6, 0.9) if on else Color(0.4, 0.45, 0.36, 0.6), false, 1.0)
		var col := Color(1.0, 1.0, 0.85) if on else Color(0.6, 0.65, 0.55)
		draw_string(Art.font(), Vector2(r.position.x + 6.0, r.position.y + 11.0),
			REBIND_TABS[d], HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 12.0, 8, col)
	_center_text("CONTROLS", 66, 13, HEADER_COL)
	var sub: String
	var scol: Color
	if _rebind_action != "":
		if pad:
			sub = "PRESS A BUTTON FOR %s (%s)   -   START CANCELS   -   PRESS IT AGAIN TO CLEAR" \
				% [rebind_label(_rebind_action), "P1" if _rebind_pad_dev == 0 else "P2"]
		else:
			sub = "PRESS A KEY FOR %s   -   ESC CANCEL   -   DEL CLEAR" % rebind_label(_rebind_action)
		scol = PLATE_SEL
	elif _rebind_msg != "":
		sub = _rebind_msg
		scol = NOTICE_COL
	elif pad:
		sub = "A/ENTER: REBIND   D-PAD L/R: PICK PLAYER   LB/RB: TAB   -   STICKS: USE SWAP STICKS"
		scol = SUBTITLE_COL
	elif _rebind_tab == 3:
		sub = "REBIND MENU KEYS - ARROWS/ENTER/ESC ALWAYS WORK TOO (EMERGENCY FALLBACK)"
		scol = SUBTITLE_COL
	else:
		sub = "ENTER: REBIND   TAB: SWITCH TAB   -   MENUS ALWAYS USE ARROWS/ENTER/ESC"
		scol = SUBTITLE_COL
	_center_text(sub, 78, 8, scol)
	# c1-18: on the GAMEPAD tab, the P1|P2 sub-selector — each player has an INDEPENDENT pad
	# layout, and this names+switches which one the rows below are editing. ◄/► or a click flips
	# it. Drawn only on the pad tab (the keyboard/menu maps aren't per-player).
	if pad:
		for pd in 2:
			var pr := _rebind_pad_dev_rect(pd)
			var pon := pd == _rebind_pad_dev
			draw_rect(pr, Color(0.14, 0.26, 0.3, 0.95) if pon else Color(0.07, 0.09, 0.1, 0.7))
			draw_rect(pr, Color(0.6, 0.9, 0.95, 0.9) if pon else Color(0.36, 0.42, 0.45, 0.6), false, 1.0)
			draw_string(Art.font(), Vector2(pr.position.x + 4.0, pr.position.y + 9.0),
				"PLAYER %d" % (pd + 1), HORIZONTAL_ALIGNMENT_CENTER, pr.size.x - 8.0, 7,
				Color(0.95, 1.0, 1.0) if pon else Color(0.55, 0.62, 0.65))
	# c1-18: a fixed-input footnote just above the SELECT/BACK legend — clarifies that the
	# always-on mouse (kb) / stick+trigger (pad) inputs are NOT rebindable here, so an
	# UNBOUND row means "no key/button on this device", NOT that the action is switched off.
	var note := "STICKS MOVE/AIM + RT FIRES (ALWAYS ON) - LEFT-HANDED? USE THE SWAP STICKS ROW BELOW" if pad \
		else "MOUSE ALSO AIMS + FIRES (ALWAYS ON) - 'UNBOUND' DROPS ONLY THAT KEY, NOT THE ACTION"
	_center_text(note, 324, 7, Color(0.62, 0.68, 0.55, 0.9))


func _draw_back_button() -> void:
	var r := _back_rect()
	draw_rect(r.grow(-3), Color(0.07, 0.1, 0.06, 0.85))
	draw_texture_rect(Art.tex("ui_menu_button_sel"), r.grow(3), false, Color(1.0, 0.9, 0.4, 0.95))
	draw_rect(r, Color(1.0, 0.97, 0.88), false, 1.0)   # focus ring (only row here)
	_center_text("BACK", r.position.y + 16.0, 11, Color(1.0, 0.95, 0.75))


# Pure per-tab visual treatment for the HALL filter row — text color plus whether
# a plate and an underline are drawn, and their colors/height. Selected = full cue
# (dark plate + 2px live underline), hover = dimmer plate + 1px preview underline +
# brightened text, idle = neither (transparent plate, 0 height). Single-sourced so
# _draw_hall and the render test can't drift; static + view-free so it runs headless.
static func hall_tab_style(on: bool, hov: bool, filter_pulse: float) -> Dictionary:
	var col := Color(1.0, 0.95, 0.65) if on else Color(0.6, 0.66, 0.56, 0.8)
	if on and filter_pulse > 0.0:
		col = col.lightened(filter_pulse * 0.45)
	elif hov and not on:
		col = Color(0.95, 0.98, 0.82)   # hover lifts text to near-selected brightness
	var out := {"text": col, "plate": Color(0, 0, 0, 0), "underline": Color(0, 0, 0, 0), "underline_h": 0.0}
	if on:
		out["plate"] = Color(0.05, 0.08, 0.04, 0.9)
		out["underline"] = Color(1.0, 0.9, 0.4, 0.9 + filter_pulse * 0.1)
		out["underline_h"] = 2.0
	elif hov:
		out["plate"] = Color(0.14, 0.19, 0.12, 0.7)   # dimmer echo of the selected plate
		out["underline"] = Color(0.9, 0.85, 0.5, 0.55)
		out["underline_h"] = 1.0
	return out


static func hall_rank_text(over_cap: bool, index: int) -> String:
	# The exact rank string _draw_hall stamps in the "#" column. A run pinned past
	# the cap (over_cap) has no exact rank — discarded runs may sit above it, and
	# under a mode filter a global "41+" would clash with the per-filter row numbers
	# — so it reads as an unranked dash, never a false slot. Pure so draw + test agree.
	return "--" if over_cap else str(index + 1)


static func hall_latest_dir(latest_idx: int, page: int, rows_per_page: int) -> int:
	# Which page-button leads toward the latest run when it's OFF the current page:
	# -1 = earlier page (PREV), +1 = later page (NEXT), 0 = on this page or no latest.
	# Drives the paged-away marker so the run you opened the board for is never lost —
	# once you page off it, an arrow points the way back. Pure so draw + test agree.
	if latest_idx < 0:
		return 0
	@warning_ignore("integer_division")
	var lp := latest_idx / rows_per_page
	return -1 if lp < page else (1 if lp > page else 0)


static func hall_latest_legend(over_cap: bool) -> String:
	# The exact recency-ribbon legend text. An over-cap run spells out OUTSIDE TOP 40
	# so its "--" rank reads as unranked, not blank. Single-sourced with the draw.
	return ("= YOUR LATEST RUN (OUTSIDE TOP %d)" % HALL_KEEP) if over_cap else "= YOUR LATEST RUN"


static func hall_page_window(page: int, total: int) -> Vector2i:
	# [start, stop) row indices _draw_hall draws on `page`. The final page is a
	# partial window — stop clamps to `total`. Single-sourced so the draw loop, the
	# latest-on-page legend gate, and the render test all read one windowing rule.
	var start := page * HALL_PAGE_ROWS
	return Vector2i(start, mini(start + HALL_PAGE_ROWS, total))


static func hall_page_rects() -> Array[Rect2]:
	# Clickable PREV/NEXT page targets flanking the centered "1-8 OF N" counter at
	# baseline y306. Static + view-free (fixed pixel geometry) so _draw_hall, the
	# click hit-test, and the render test all read ONE source and can't drift.
	# [prev, next], centers 225/415 — mirror-symmetric about the 320 counter axis so
	# the pair frames the count evenly. 74x16 targets whose INNER edges (262/378) sit
	# just OUTSIDE the widest counter span: "33-40 OF 240" is 106px centered on 320
	# (edges 267..373), so the label can never clip either hit rect (5px clearance each
	# side). The bottom edge (y306) clears the HALL BACK button's DRAWN plate (its
	# texture is _back_rect.grow(3), top y307), so the two clickable controls never overlap.
	return [Rect2(188.0, 290.0, 74.0, 16.0), Rect2(378.0, 290.0, 74.0, 16.0)]


static func hall_page_style(enabled: bool, hov: bool, press: float) -> Dictionary:
	# PREV/NEXT button visual state, single-sourced so _draw_hall and a headless test
	# read ONE truth (same idiom as hall_tab_style). A boundary button is dim with no
	# plate ("can't go further"); an enabled one carries a resting fill so it reads as a
	# real target, brightens on hover, and flashes on press.
	if not enabled:
		return {"text": Color(0.45, 0.47, 0.42, 0.55), "plate": Color(0, 0, 0, 0)}
	var text := Color(0.9, 0.86, 0.5)
	var plate := Color(0.14, 0.19, 0.12, 0.55)   # resting fill so the target reads as a button
	if press > 0.0:
		text = Color(1.0, 1.0, 0.88).lightened(press * 0.1)   # punchiest state — brightest text + plate
		plate = Color(0.3, 0.36, 0.18, 0.9)
	elif hov:
		text = Color(0.98, 0.98, 0.82)
		plate = Color(0.2, 0.26, 0.16, 0.78)
	return {"text": text, "plate": plate}


func _hall_page_rects() -> Array[Rect2]:
	return hall_page_rects()


func _page_hover_at(pos: Vector2) -> int:
	# Which page button (0 = PREV, 1 = NEXT, -1 = none) a pointer at `pos` hovers — only
	# when the board pages and only over an ENABLED button, so a boundary button never
	# lights. One source for the live motion hover AND the still-cursor refresh below.
	if mode != Mode.HALL:
		return -1
	var pages := _hall_pages(_hall_rows().size())
	if pages <= 1:
		return -1
	var prc := _hall_page_rects()
	if prc[0].has_point(pos) and _hall_page > 0:
		return 0
	if prc[1].has_point(pos) and _hall_page < pages - 1:
		return 1
	return -1


func _refresh_page_hover() -> void:
	# A page or filter change flips which buttons are boundary-disabled; re-evaluate the
	# hover against the LAST pointer position so a STILL cursor immediately gains the cue
	# on a button that just became enabled and loses it on one that just became a boundary
	# — without waiting for the next mouse move.
	var ph := _page_hover_at(_last_ptr)
	if ph != _page_hover:
		_page_hover = ph
		_mark_dirty()


func _hall_tab_rects() -> Array[Rect2]:
	# The same measured tab layout _draw_hall renders, as clickable rects —
	# keep the width math in lockstep with the loop below.
	return _tab_rects_for(["ALL", "CAMPAIGN", "ENDLESS"])


func _howto_tab_rects() -> Array[Rect2]:
	# c2-02: clickable rects for the HOW-TO page tabs, same centered layout the
	# HALL filter tabs use so both content screens read with one grammar.
	return _tab_rects_for(HOWTO_TABS)


func _tab_rects_for(names: Array) -> Array[Rect2]:
	# Shared centered tab-row geometry (10px labels, 22px gutters, plate at y52) —
	# HALL filters and HOW-TO pages both measure through here so draw + click agree.
	var f := Art.font()
	var tw: Array[float] = []
	var total := -22.0
	for n in names:
		var w := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		tw.append(w)
		total += w + 22.0
	var x := CENTER_X - total / 2.0
	var out: Array[Rect2] = []
	for i in names.size():
		out.append(Rect2(x - 4.0, 52.0, tw[i] + 8.0, 20.0))
		x += tw[i] + 22.0
	return out


func _draw_hall() -> void:
	var names := ["ALL", "CAMPAIGN", "ENDLESS"]
	_center_text("HALL OF FAME", CONTENT_TITLE_Y, 22, HEADER_ACCENT)
	# Persistent filter tab row — the old single "◄ NAME ►" line hid the other
	# two choices, so nobody knew left/right cycled anything. Selected tab is
	# underlined and flashes briefly on change (_filter_pulse). Geometry comes
	# from _hall_tab_rects — the SAME rects the click/hover tests use — so a
	# tab rename or padding tweak can't drift the targets off the pixels
	# (same discipline as _row_geometry).
	var f := Art.font()
	var tabs := _hall_tab_rects()
	for i in names.size():
		var tr := tabs[i]
		var on := i == _hall_filter
		var hov := not on and i == _tab_hover
		# Text color + plate/underline treatment come from ONE pure helper so the
		# selected/hover/idle cues are single-sourced and a headless test can pin
		# the hover plate+underline without a GL surface (same idiom as the pure
		# geometry statics above).
		var st := hall_tab_style(on, hov, _filter_pulse)
		var plate: Color = st["plate"]
		if plate.a > 0.0:
			# Filled plate under the live tab (the underline alone read as decoration,
			# not state) — a dimmer echo for the hover preview so the pointer's target
			# reads as a real button, not just tinted text.
			draw_rect(Rect2(tr.position.x, 54.0, tr.size.x, 16.0), plate)
		Art.text(self, names[i], Vector2(tr.position.x + 4.0, 66), 10, st["text"])
		var uh: float = st["underline_h"]
		if uh > 0.0:
			# Underline: 2px live rule for the selected tab, a fainter 1px preview on
			# hover so it clearly reads as "click to make this the live filter".
			draw_rect(Rect2(tr.position.x + 2.0, 70.0, tr.size.x - 4.0, uh), st["underline"])
	# The cycle affordance itself: dpad art on pad, arrow text on keyboard.
	var left := tabs[0].position.x + 4.0
	var right := tabs[tabs.size() - 1].end.x - 4.0
	if Art.use_pad:
		var t := Art.tex("glyph_dpad_lr")
		var gw := 13.0 * float(t.get_width()) / float(t.get_height())
		draw_texture_rect(t, Rect2(left - gw - 12.0, 56.0, gw, 13.0), false)
	else:
		# mi_arrow points RIGHT; negative rect width flips it for the left side.
		var at := Art.tex("mi_arrow")
		var acol := Color(0.84, 0.86, 0.78)
		draw_texture_rect(at, Rect2(left - 19.0, 56.0, -11.0, 11.0), false, acol)
		draw_texture_rect(at, Rect2(right + 8.0, 56.0, 11.0, 11.0), false, acol)
	# Filter to the selected mode (ALL shows everything), keeping score order.
	var rows := _hall_rows()
	# Measured column layout — Art.font() is proportional, so each column draws
	# at its own x. MODE/REACHED/STREAK x-starts come from the widest possible
	# header/cell at draw size + 14px gutters, after the right-aligned SCORE
	# column (right edge 214); hardcoded offsets drifted on every font change.
	var mode_w := f.get_string_size("MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	mode_w = maxf(mode_w, f.get_string_size("CAMPAIGN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	var reach_w := f.get_string_size("REACHED", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	for s in ["SECTOR 9", "VICTORY", "WAVE 99"]:
		reach_w = maxf(reach_w, f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	var streak_x := 214.0 + 14.0 + mode_w + 14.0 + reach_w + 14.0
	var col_x := [112.0, 148.0, 214.0 + 14.0, 214.0 + 14.0 + mode_w + 14.0, streak_x]
	var headers := ["#", "SCORE", "MODE", "REACHED", "STREAK"]
	# Headers at y96 (was y92): dropped 4px so the y82 recency band above clears them
	# at the real font metrics (see HALL_RECENCY_Y) — the two lines no longer collide.
	for c in headers.size():
		if c == 1:
			var hw := f.get_string_size(headers[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			Art.text(self, headers[c], Vector2(214.0 - hw, 96), 10, Color(1.0, 0.82, 0.4))
		else:
			Art.text(self, headers[c], Vector2(col_x[c], 96), 10, Color(1.0, 0.82, 0.4))
	# RANK header sits in the gap between the # and the right-aligned SCORE — drawn
	# outside the parallel header/col_x arrays so it doesn't reshuffle the columns.
	Art.text(self, "RANK", Vector2(130.0, 96), 10, Color(1.0, 0.82, 0.4))
	# Page the board: HALL_PAGE_ROWS rows per screen, up/down turns the page. Switching
	# the filter tab resets _hall_page to 0 (see the nav + click handlers); this clamp is
	# the belt-and-braces catch for a page stranded past the end after a filter shrank the
	# list, so the visible window and the "OF N" count below can never point off the board.
	var pages := _hall_pages(rows.size())
	_hall_page = clampi(_hall_page, 0, pages - 1)
	var win := hall_page_window(_hall_page, rows.size())
	var start: int = win.x
	var stop: int = win.y   # last page is a partial window (clamped to the row count)
	var latest_idx := _hall_latest_index(rows)   # which row (if any) is the just-banked run — hid-matched
	# Status band at the TOP (its own band, clear of the paging counter and BACK): it
	# both flags the just-banked run AND states the board's retention outright, so the
	# TOP-<HALL_KEEP> cutoff is exposed here rather than silently dropping older runs off
	# the bottom. Full width, so the long combined variants never clip. The bottom counter
	# has no room for the cap (it'd collide with the PREV/NEXT buttons), so it lives here.
	var keep_note := "KEEPS TOP %d" % HALL_KEEP
	if latest_idx >= 0:
		@warning_ignore("integer_division")
		var lpage := latest_idx / HALL_PAGE_ROWS
		if lpage == _hall_page:
			var over: bool = (rows[latest_idx] as Dictionary).get("over_cap", false)
			# The over-cap legend already spells out "(OUTSIDE TOP N)"; the in-cap one
			# doesn't, so pin the retention beside it either way.
			var msg := hall_latest_legend(over)
			if not over:
				msg += "   ·   " + keep_note
			_center_text(msg, HALL_RECENCY_Y, 9, Color(1.0, 0.86, 0.55))
		else:
			var dir := "<<" if lpage < _hall_page else ">>"
			_center_text("%s YOUR LATEST RUN IS ON PAGE %d %s   ·   %s" % [dir, lpage + 1, dir, keep_note],
				HALL_RECENCY_Y, 9, Color(1.0, 0.82, 0.4))
	else:
		# No fresh run to flag — the band states the retention rule so a returning player
		# still sees the cutoff (paging resolves hidden entries; it doesn't hide the cap).
		_center_text("BOARD KEEPS YOUR TOP %d RUNS" % HALL_KEEP, HALL_RECENCY_Y, 9,
			Color(0.82, 0.86, 0.72))
	# The header row and the retention status band above always draw, so an empty
	# filter reads as a laid-out board that simply has no entries yet rather than a
	# blank panel. Only the row list and its footer counter depend on there being runs.
	if rows.is_empty():
		# ALL is not an adjective ("NO ALL RUNS YET" reads wrong) — drop the qualifier for
		# it, keep the mode word for the CAMPAIGN/ENDLESS filters. Sits in the empty row
		# area; the window/count math below is skipped so it never renders a bare "1-0 OF 0".
		var empty_noun: String = "" if _hall_filter == 0 else str(names[_hall_filter]) + " "
		_center_text("NO %sRUNS YET \u2014 GO EARN YOUR PLACE" % empty_noun, 190, 11,
			Color(0.8, 0.84, 0.74))
		# The count indicator survives the empty state too \u2014 same y306 footer slot the
		# populated board uses, and the SAME "start-stop OF total" shape ("0-0 OF 0"), so the
		# counter never changes form when a filter has no runs. Same warm gold as the
		# populated counters (HALL_COUNT_COL) so the total reads identically in every state.
		_center_text("0-0 OF 0", 306, 11, HALL_COUNT_COL)
	else:
		for i in range(start, stop):
			var run: Dictionary = rows[i]
			var row := i - start   # 0..HALL_PAGE_ROWS-1 within this page (drives the y baseline)
			var is_latest := i == latest_idx
			var mode_s: String = "ENDLESS" if run.get("mode", "campaign") == "endless" else "CAMPAIGN"
			var reached: String = "WAVE %d" % run.get("wave", 0) if run.get("mode", "campaign") == "endless" \
				else ("VICTORY" if run.get("won", false) else "SECTOR %d" % run.get("sector", 0))
			var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.88, 0.9, 0.82)
			if is_latest:
				col = Color(1.0, 0.86, 0.5)   # the run you just finished — warm recency tint
			var tag: String = "  *DAILY" if run.get("daily", false) else ""
			if run.get("assist", false):
				tag += "  *ASSIST"   # 2-hit runs compete on the same board — say so
			var streak_s := "x%d%s" % [run.get("streak", 0), tag]
			if streak_x + f.get_string_size(streak_s, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x > 628.0:
				# Cell would run off the frame — abbreviate the tags for this row.
				tag = ("  *D" if run.get("daily", false) else "")
				if run.get("assist", false):
					tag += "  *A"
				streak_s = "x%d%s" % [run.get("streak", 0), tag]
			var y := 112 + row * 24   # rows stay at 112 (header @96 already clears row0's box top 102 by 4px); pushing them down crowds the 8th row's glow into the page buttons
			if is_latest:
				# Glow band + a warm ribbon down the left edge so the run you opened the
				# board for reads instantly, wherever it ranks. Drawn under the cells.
				draw_rect(Rect2(100.0, y - 12.0, 528.0, 20.0), Color(1.0, 0.7, 0.2, 0.15))
				draw_rect(Rect2(100.0, y - 12.0, 3.0, 20.0), Color(1.0, 0.75, 0.25, 0.95))
				# A right-pointing caret in the left gutter (x104..110, the gap before the #
				# column @112) — a SHAPE marker so the highlighted row is identifiable without
				# relying on the warm tint alone (the top-band "= YOUR LATEST RUN" legend reads
				# this same "=" idea), keeping the cue legible to color-blind players.
				draw_colored_polygon(PackedVector2Array([Vector2(104.0, y - 6.0),
					Vector2(110.0, y - 2.0), Vector2(104.0, y + 2.0)]),
					Color(1.0, 0.8, 0.35, 0.95))
			var rank_s := hall_rank_text(run.get("over_cap", false), i)
			var cells := [rank_s, Art.group_digits(int(run.get("score", 0))), mode_s, reached, streak_s]
			for c in cells.size():
				if c == 1:
					# Right-aligned numerals: a 6-digit endless score can't crowd MODE.
					var sw := Art.font().get_string_size(cells[c], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
					Art.text(self, cells[c], Vector2(214.0 - sw, y), 11, col)
				else:
					Art.text(self, cells[c], Vector2(col_x[c], y), 11, col)
			# Earned run grade (S/A/B/C/D), colored by tier. Old saves predate the key —
			# guard with .get and only draw when present so the board never crashes.
			var gr: String = run.get("grade", "")
			if gr != "":
				var gcol: Color = {"S": Color(1.0, 0.85, 0.3), "A": Color(0.55, 0.9, 1.0),
					"B": Color(0.6, 0.9, 0.5), "C": Color(0.85, 0.85, 0.8)}.get(gr, Color(0.7, 0.7, 0.7))
				Art.text(self, gr, Vector2(132.0, y), 11, gcol)
				# Tier medal beside the letter (D=1 … S=5) — sprite is white-with-alpha,
				# tinted to the tier color so medal and letter read as one badge.
				var med: int = {"D": 1, "C": 2, "B": 3, "A": 4, "S": 5}.get(gr, 0)
				if med > 0:
					draw_texture_rect(Art.tex("mi_medal_%d" % med),
						Rect2(142.0, y - 10.0, 12.0, 12.0), false, gcol)
		# Footer: a single compact counter row framed by the PREV/NEXT buttons when the
		# board spills past one page. The whole line sits on ONE row at y306 — clear of the
		# BACK plate (top y310) below it. The old second "UP/DOWN TO TURN THE PAGE" hint line
		# lived at y322, INSIDE the BACK plate band; the labeled PREV/NEXT buttons + the
		# counter now carry the affordance without a hint line that collided with the exit.
		# The counter states the visible WINDOW and the TOTAL ("1-8 OF N") rather than a bare
		# page number, so a player on page 1 can see more scores exist. rows.size() is the
		# filtered count (recomputed every draw), so the total tracks the active tab. Even a
		# single-page board states its count outright — the board's size is never hidden.
		if pages > 1:
			# Visible row window + filtered total, in the spec's compact "1-8 OF N" form (the
			# retention cap is stated in the top status band — it won't fit here without colliding
			# with the flanking PREV/NEXT buttons). Widest variant "33-40 OF 240" measures 106px in
			# Art.font() at 11px, centered on x320 (edges 267..373) — inside the PREV/NEXT gap
			# (prev right edge 238, next left edge 402) with ~29px of clearance on each side.
			_center_text("%d-%d OF %d" % [start + 1, stop, rows.size()], 306, 11, HALL_COUNT_COL)
			# Mouse-clickable page buttons flanking the counter — a second way to page for the
			# mouse (c3-06: the wheel now scrolls the board too). Each carries a VERTICAL arrow glyph, not just a
			# word: paging is bound to UP/DOWN (left/right is the filter), so a horizontal cue
			# would read as the wrong axis. UP = earlier page (0), DOWN = later page (1) — the
			# same mapping the keyboard/pad up/down nav uses. Symmetric plates frame the
			# counter; each carries a resting fill, brightens on hover, and flashes on press —
			# a boundary button stays dim and plate-less so it reads as "can't go further".
			var pr := _hall_page_rects()
			var pen := [_hall_page > 0, _hall_page < pages - 1]
			var plbl := ["PREV", "NEXT"]
			for pi in 2:
				var pst := hall_page_style(pen[pi], _page_hover == pi,
					_page_press if _page_press_side == pi else 0.0)
				var pcol: Color = pst["text"]
				var pplate: Color = pst["plate"]
				if pplate.a > 0.0:
					draw_rect(pr[pi], pplate)
				# Vertical arrow glyph + label, centered as a unit in the rect. The triangle
				# (up for PREV, down for NEXT) is the primary axis cue; the word confirms it.
				var lw := f.get_string_size(plbl[pi], HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				var gw := 7.0
				var bx := pr[pi].position.x + (pr[pi].size.x - lw - gw - 2.0) / 2.0
				var ay := 302.0
				var pts := PackedVector2Array()
				if pi == 0:   # up-triangle: apex at top
					pts = PackedVector2Array([Vector2(bx + gw / 2.0, ay - 6.0),
						Vector2(bx, ay - 1.0), Vector2(bx + gw, ay - 1.0)])
				else:         # down-triangle: apex at bottom
					pts = PackedVector2Array([Vector2(bx, ay - 6.0),
						Vector2(bx + gw, ay - 6.0), Vector2(bx + gw / 2.0, ay - 1.0)])
				draw_colored_polygon(pts, pcol)
				Art.text(self, plbl[pi], Vector2(bx + gw + 2.0, ay), 9, pcol)
				# Paged AWAY from your latest run: a warm dot on the button that leads back to
				# it (the top-band "ON PAGE n" cue names the page) so the run you opened the
				# board for is never simply gone — the recency payoff survives a full board.
				var ldir := hall_latest_dir(latest_idx, _hall_page, HALL_PAGE_ROWS)
				if ldir != 0 and pi == (0 if ldir < 0 else 1):
					draw_rect(Rect2(pr[pi].get_center().x - 2.0, pr[pi].position.y - 3.0, 4.0, 4.0),
						Color(1.0, 0.75, 0.25, 0.95))
		else:
			# One page: no paging chrome, but state the count in the SAME "1-N OF N" window
			# format AND the same warm gold (HALL_COUNT_COL) the paged footer uses, so the
			# indicator reads identically across every filter state (here start=0,
			# stop=rows.size(), so it renders "1-N OF N").
			_center_text("%d-%d OF %d" % [start + 1, stop, rows.size()], 306, 11, HALL_COUNT_COL)


func _hall_rows() -> Array:
	# The score-ordered runs visible under the current filter (ALL shows all). The
	# .get fallbacks guard old save rows that predate the "mode" key. Single-sourced
	# so paging math (_hall_pages / _nav) and _draw_hall can't disagree on the count.
	var rows: Array = []
	for run in main.hall:
		if _hall_filter == 1 and run.get("mode", "campaign") == "endless":
			continue
		if _hall_filter == 2 and run.get("mode", "campaign") != "endless":
			continue
		rows.append(run)
	return rows


func _hall_pages(n: int) -> int:
	return maxi(1, (n + HALL_PAGE_ROWS - 1) / HALL_PAGE_ROWS)


func _hall_latest_page() -> int:
	# Page index holding the run just banked into the Hall (main.hall_latest), so
	# opening the board lands on it. 0 when there's no fresh run or it's off-board.
	var idx := _hall_latest_index(_hall_rows())
	return idx / HALL_PAGE_ROWS if idx >= 0 else 0


func _hall_latest_index(rows: Array) -> int:
	# Index of the just-banked run within `rows`, or -1 when it isn't shown. Matched
	# by its unique "hid" — value-equal twins (same score/sector) are common on the
	# board, so deep-equality (`in` / Array.has) would highlight the wrong row; hid
	# pins the EXACT run. Falls back to reference identity for a pre-hid latest.
	# Object.get() (not `.`) so a headless stub without the field returns null,
	# not a crash — the guard short-circuits before reading rows.
	var latest: Variant = main.get("hall_latest") if main != null else null
	if latest == null or (latest as Dictionary).is_empty():
		return -1
	var ld: Dictionary = latest
	var has_hid: bool = ld.has("hid")
	for i in rows.size():
		var r: Dictionary = rows[i]
		if has_hid:
			if r.has("hid") and int(r["hid"]) == int(ld["hid"]):
				return i
		elif is_same(r, ld):
			return i
	return -1


func _draw_howto() -> void:
	# Title baseline y38 (size 22, ~4px descent -> bottom ~42) matched to HALL so both
	# content screens share one header rhythm; the tab plate top sits at y54, a clear
	# ~12px below, so the two never overlap regardless of font metrics.
	_center_text("HOW TO PLAY", CONTENT_TITLE_Y, 22, HEADER_ACCENT)
	# c2-02/c3-05/c4-06: the wall of ~17 lines is split into four TABS — CONTROLS / WAR
	# CHEST / ENEMIES / ENDLESS — each drawn on its own screen with a fresh top-of-screen y
	# cursor. Nothing stacks a section onto the next, so no row can land on the BACK plate,
	# and the two dense blocks the old BASIC page jammed together (the input verbs and the
	# War Chest economy) each get a tab and a roomy pitch. The seven ENDLESS threats live on
	# ONE tab paged by its in-page chevrons (2 sub-pages of 4 + 3) — a single roster pager,
	# not the old confusing ENDLESS I/II tabs layered on top of the same chevrons. Left/right
	# (or wheel) turns tabs, and pages the ENDLESS roster before spilling to the next tab.
	_draw_howto_tabs()
	match _howto_page:
		0: _howto_page_controls()
		1: _howto_page_warchest()
		2: _howto_page_enemies()
		3: _howto_page_endless(_endless_page())   # ENDLESS — one tab, paged by chevrons/left-right
		_: _howto_page_endless(_endless_page())   # safety fallback (tab is clamped 0..3)


# c3-05/c4-06: the CONTROLS/WAR CHEST/ENEMIES/ENDLESS tab row — same centered
# grammar and pure style helper the HALL filter tabs use, so both content screens read as
# one system. Everything iterates HOWTO_TABS so the four-tab row draws (and its click
# targets in _howto_tab_rects) stay in lockstep with the page count.
func _draw_howto_tabs() -> void:
	var tabs := _howto_tab_rects()
	for i in HOWTO_TABS.size():
		var tr := tabs[i]
		var on := i == _howto_page
		var hov := not on and i == _tab_hover
		var st := hall_tab_style(on, hov, 0.0)
		var plate: Color = st["plate"]
		if plate.a > 0.0:
			draw_rect(Rect2(tr.position.x, 54.0, tr.size.x, 16.0), plate)
		Art.text(self, HOWTO_TABS[i], Vector2(tr.position.x + 4.0, TAB_BASELINE_Y), 10, st["text"])
		var uh: float = st["underline_h"]
		if uh > 0.0:
			draw_rect(Rect2(tr.position.x + 2.0, 70.0, tr.size.x - 4.0, uh), st["underline"])
	# c3-05/c4-06: a "N / 4" counter, right-aligned at the frame edge on the tab baseline, so
	# a first-time player can see at a glance there are more pages than the one on
	# screen — the tabs alone read as a static header, and nobody paged through them.
	# The centered tab row (see _tab_rects_for) never reaches the frame edge, so the
	# counter can't collide with the rightmost (ENDLESS) tab.
	var pg := "%d / %d" % [_howto_page + 1, HOWTO_TABS.size()]
	var pw := Art.font().get_string_size(pg, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	Art.text(self, pg, Vector2(FRAME_INNER_R - pw, TAB_BASELINE_Y), 10, Color(0.7, 0.75, 0.7, 0.85))


# c3-05 page 1 — CONTROLS. The input verbs (grenade / roll / board / plant), one
# per line so each glyph reads against its own complete sentence instead of the old
# run-on "Bullets don't. ROLL... BOARD tanks..." line that packed two verbs into one
# row. Each carries its device-aware glyph inline (text-only verbs made players hunt
# the legend); every line is re-wrapped under ~64 chars so it can't clip at x=640.
func _howto_page_controls() -> void:
	var col := Color(0.9, 0.92, 0.8)
	var y := 100.0
	# Three buttons, four verbs: BOARD and PLANT are the SAME @interact button (context
	# picks which), shown by the repeated glyph below — so the header can't claim one
	# button per verb.
	Art.text(self, "THREE BUTTONS, FOUR VERBS:", Vector2(60, y), 10, Color(1.0, 0.7, 0.4))
	y += 30.0
	# Each text token after a glyph leads with a space so the word never glues to the
	# device art. Board and plant share the SAME button, so the two lines are parallel
	# imperatives (BOARD… / PLANT…) that read as complete commands, not fragments.
	_verb_line(["@grenade", " GRENADES crack armor — bunkers, bosses, the Colossus."], y, col)
	y += 30.0
	_verb_line(["@roll", " ROLL dodges bullets — armor never stops them."], y, col)
	y += 30.0
	_verb_line(["@interact", " BOARD a tank for its crush weight and its shells."], y, col)
	y += 30.0
	_verb_line(["@interact", " PLANT a claymore clear of any tank — it hurts BOTH sides."], y, col)


# c3-05 page 2 — WAR CHEST. The one-hit rule and the shared-coin economy, given their
# own page and complete sentences. The supply-wheel prompt is the DEVICE GLYPH drawn
# inline via _verb_line (was a lowercase fragment with the glyph spliced by hand into
# the middle of a wrapped line), so it reads as one plain sentence.
func _howto_page_warchest() -> void:
	var y := 100.0
	Art.text(self, "ONE HIT AND YOU DROP.", Vector2(60, y), 13, Color(1.0, 0.9, 0.6))
	y += 26.0
	Art.text(self, "No health bar, no second chance — use cover and keep moving.",
		Vector2(60, y), 11, Color(0.85, 0.9, 0.8), FRAME_INNER_R - 60.0)
	y += 40.0
	Art.text(self, "THE WAR CHEST — SHARED COIN FROM EVERY KILL:", Vector2(60, y), 11, Color(1.0, 0.9, 0.6))
	y += 26.0
	Art.text(self, "Spend it to REVIVE a fallen partner or BUY supplies.",
		Vector2(60, y), 11, Color(0.85, 0.9, 0.8), FRAME_INNER_R - 60.0)
	y += 30.0
	_verb_line(["Hold ", "@wheel", " to open the supply wheel. That's the choice."],
		y, Color(0.85, 0.9, 0.8))


# c3-05 page 3 — the standard red-team roster with live sprites, at a roomy pitch
# instead of the 18px it once crammed under the ranged block.
func _howto_page_enemies() -> void:
	var y := 100.0
	Art.text(self, "THE RED TEAM — WHO'S SHOOTING BACK:", Vector2(60, y), 10, Color(1.0, 0.7, 0.4))
	y += 22.0
	# sol-08: front the LIVE red-team sprites the player now sees (rusher/elite draw the pack enemy_* cel bakes).
	var roster := [["enemy_smg", "RUSHER — charges, touch kills"],
		["enemy_assault", "ELITE — keeps range, telegraphs one shot"],
		["frogman", "FROGMAN — lurks in water, grenades only"]]
	for r in roster:
		_draw_sprite_fit(r[0], Rect2(74, y - 22, 28, 26), Art.tint(r[0]))
		Art.text(self, r[1], Vector2(110, y - 6), 11, Color(0.9, 0.92, 0.82), FRAME_INNER_R - 110.0)
		y += 34.0


# c3-05 page 4 — the Endless War ranged specialists.
# c4-06: the seven ENDLESS ranged threats used to crowd ONE screen — even on their
# own c3-05 tab the pitch stayed capped at 24 to squeeze all seven in, so the sprites
# read small. They now span TWO sub-pages of the single ENDLESS tab (4 rows + 3 rows),
# turned by the in-page chevrons (or left/right/wheel). Fewer rows per
# page lets the derived pitch reach a roomier cap (30), so each threat silhouette draws
# bigger and the roster reads at a glance. `page` selects the half.
const ENDLESS_PER_PAGE := 4


# c4-06: baseline of the ENDLESS in-page PREV/NEXT chevron row — DERIVED from the BACK
# plate (its top less an 18px margin) rather than a hardcoded y, so the controls always
# clear BACK no matter the roster size / plate geometry (same discipline as the roster's
# derived pitch above).
func _howto_nav_y() -> float:
	return _back_rect().position.y - 18.0


# c4-06: the seven ENDLESS ranged specialists [sprite_key, tint, tip], single-sourced so
# the page draw and the page-count / chevron geometry can't drift. Each row fronts its LIVE
# sprite in its in-game tint (the top roster teaches silhouettes; this block used to teach
# only names, so a first-run player couldn't match "GHILLIE" to the shape that kills them).
# Built once and cached — the draw + input path queries the roster / page-count several
# times a frame, so rebuilding these dicts (and re-running Art.tint) every call is waste;
# the bakes and their tints are immutable at runtime (same idiom as _trim_cache).
static var _endless_cache: Array[Array] = []
func _endless_threats() -> Array[Array]:
	if _endless_cache.is_empty():
		_endless_cache = [
		["m_soldier2", Color(1.3, 1.1, 0.55), "GRENADIER — lobs a telegraphed blast on your spot. Keep moving."],
			["enemy_sniper", Art.tint("enemy_sniper"), "SNIPER — paints a laser line, then fires. Sidestep it."],   # sol-08: live red marksman
			["ghillie", Art.tint("ghillie"), "GHILLIE — hidden sniper; only its laser gives it away. Close in."],
			["sapper", Art.tint("sapper"), "SAPPER — seeds mines behind it. Don't chase over its trail."],
			["m_bombsuit", Color(0.85, 0.9, 1.0), "SHIELD — front blocks bullets. Flank it or grenade it."],
			["m_drone", Art.tint("m_drone"), "DRONE — flying spotter, calls mortars on your spot. Shoot it down."],
			["m_technical", Art.tint("m_technical"), "TECHNICAL — revs, then charges a LOCKED line. Step off it."]]
	return _endless_cache


# How many ENDLESS roster pages there are (7 threats / 4-per-page = 2).
func _endless_pages() -> int:
	return maxi(1, int(ceilf(_endless_threats().size() / float(ENDLESS_PER_PAGE))))


# Which ENDLESS roster sub-page is showing, clamped to the live page count (so a
# stale index can't point past a shrunk roster).
func _endless_page() -> int:
	return clampi(_howto_endless_page, 0, _endless_pages() - 1)


func _howto_page_endless(page: int = 0) -> void:
	var y := 100.0
	var special := _endless_threats()
	var pages := _endless_pages()
	page = clampi(page, 0, pages - 1)
	var rows := special.slice(page * ENDLESS_PER_PAGE, page * ENDLESS_PER_PAGE + ENDLESS_PER_PAGE)
	# Endless War fields ranged specialists (wave 3+) — teach their counters. The
	# "(1/2)" marker tells a paging player this roster continues on the next tab.
	Art.text(self, "ENDLESS WAR — RANGED THREATS (%d/%d):" % [page + 1, pages], Vector2(60, y), 10, Color(1.0, 0.7, 0.4))
	y += 20.0
	# Threat rows are the tight spot, so their pitch is DERIVED, not typed: fit
	# every row's text baseline between here (`y`) and the last baseline the BACK
	# plate allows. Pitch is the fit value capped and NEVER clamped upward, so the
	# last baseline lands at-or-below the limit for ANY page size — a grown roster
	# just tightens the pitch, it can never push a row into BACK. floorf keeps it
	# on whole pixels (a fractional pitch smears pixel-art rows). The box is sized
	# `pitch - 1`, so consecutive boxes always keep a >=1px gap. Sprites draw
	# cropped to their opaque bounds (see _draw_sprite_fit), so a tight box still
	# shows a full body instead of a speck.
	var last_max := _back_rect().position.y - 7.0
	var readable := 13.0   # 10px text needs ~3px leading to stay legible
	# c4-06: with the roster paginated at four-per-page, the pitch cap lifts 24 -> 30 —
	# each page holds fewer rows so the derived fit reaches the cap and the sprite boxes
	# (box == pitch - 1) grow past their ~26px source, so the silhouettes read as bodies.
	var pitch := 30.0
	if rows.size() > 1:
		pitch = floorf(minf(30.0, (last_max - y) / float(rows.size() - 1)))
	# c3-05: release-safe floor at the READABLE minimum (not a bare 1px). Readability
	# wins over the BACK-clearance invariant in the pathological overflow case — a legible
	# row grazing BACK beats an illegible one that clears it.
	pitch = maxf(readable, pitch)
	# Two invariants: the block never collides with BACK (pure fit, no upward clamp),
	# and it never teaches below a legible pitch.
	assert(y + float(rows.size() - 1) * pitch <= last_max)
	assert(pitch >= readable)
	# Box tracks the DERIVED pitch (never a fixed size): pitch - 1 guarantees a >=1px
	# gap between adjacent sprites at any page size, so they grow with the roomier
	# pitch yet can never overlap.
	var box := maxf(1.0, pitch - 1.0)
	# c2-02: each ENDLESS threat description is width-clamped to the frame interior
	# (text starts at x76, right edge FRAME_INNER_R) so a long or LOCALIZED tip clips with
	# an ellipsis instead of bleeding through the chrome past x=640 — the same overflow
	# guard the ENEMIES roster and the BASIC verb lines carry.
	var text_w := maxf(0.0, FRAME_INNER_R - 76.0)
	# c4-06: draw the threat NAME (always the first token) in the amber header accent
	# and trail the tip in the muted body color, so the rows scan by name at a glance
	# instead of reading as one grey block. The tip clamps to the width the name leaves
	# it (>=0), so the frame-interior overflow guard still ellipses a long/localized tip.
	var name_col := Color(1.0, 0.85, 0.45)
	var body_col := Color(0.88, 0.9, 0.8)
	var f := Art.font()
	for i in rows.size():
		var sy := y + i * pitch
		# c3-05: center the sprite box on the text's visual mid (10px cap-height sits
		# ~sy-8..sy, mid ~sy-4) instead of hanging it off the baseline, so the body and
		# its tip line up on one row.
		_draw_sprite_fit(rows[i][0], Rect2(50, sy - TEXT_MID_10 - box / 2.0, box, box), rows[i][1])
		var parts: PackedStringArray = String(rows[i][2]).split(" ", true, 1)
		var name := parts[0]
		var name_w := f.get_string_size(name + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		Art.text(self, name, Vector2(76, sy), 10, name_col, text_w)
		if parts.size() > 1:
			Art.text(self, parts[1], Vector2(76.0 + name_w, sy), 10, body_col, maxf(0.0, text_w - name_w))
	_draw_howto_endless_nav(page, pages)


# c4-06: explicit PREV/NEXT chevrons flanking a "1 / 2" counter, drawn on the ENDLESS
# roster pages themselves so the two-page split advertises its own navigation instead of
# leaning only on the tab row. Boundary chevrons dim (like HALL's page arrows); a live one
# reads as a real button. Geometry is single-sourced through _howto_endless_nav_rects so
# the draw and the click targets always agree.
func _draw_howto_endless_nav(page: int, pages: int) -> void:
	if pages <= 1:
		return
	var rects := _howto_endless_nav_rects()
	var ny := _howto_nav_y()
	var live := Color(0.9, 0.92, 0.82)
	var dim := Color(0.5, 0.53, 0.5)
	# A filled plate behind each live chevron so it reads as a real button, not decoration
	# (the tabs and HALL page arrows carry the same plate cue); a boundary chevron gets no
	# plate and dim text so it reads as disabled.
	var enabled := [page > 0, page < pages - 1]
	for side in range(2):
		if enabled[side]:
			# Brighter fill + border when the pointer hovers this chevron, so it reads
			# as a focusable button (parity with the tab/hover plates).
			var hot := side == _howto_nav_hover
			draw_rect(rects[side], Color(1, 1, 1, 0.22 if hot else 0.10))
			draw_rect(rects[side], Color(0.85, 0.9, 0.72, 0.6 if hot else 0.35), false)
	Art.text_center(self, "<", rects[0].get_center().x, ny, 12, live if enabled[0] else dim)
	Art.text_center(self, ">", rects[1].get_center().x, ny, 12, live if enabled[1] else dim)
	# Draw the SAME padded string the geometry measures (see _howto_endless_counter), so the
	# < / > sit exactly against the counter's footprint instead of drifting off a width the
	# counter never actually occupied. text_center centers it, so the pad stays symmetric.
	Art.text_center(self, _howto_endless_counter(), CENTER_X, ny, 12, Color(0.8, 0.82, 0.75))


# Shared geometry for the ENDLESS PREV/NEXT chevrons — a "<" rect left of the counter and
# a ">" rect right of it, centered on CENTER_X. Fed to both the draw and the mouse-click
# hit test so the target can't drift off the pixels (same discipline as the tab rects).
func _howto_endless_counter() -> String:
	# The "1 / 2" sub-page counter, padded so the flanking chevrons keep a small gutter.
	# Single-sourced so the draw and the click-target geometry render the identical string.
	return "  %d / %d  " % [_endless_page() + 1, _endless_pages()]


func _howto_endless_nav_rects() -> Array[Rect2]:
	var f := Art.font()
	var mid := _howto_endless_counter()
	var mw := f.get_string_size(mid, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var cw := f.get_string_size("<", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var x0 := CENTER_X - (cw + mw + cw) / 2.0
	var top := _howto_nav_y() - 12.0
	return [Rect2(x0 - 6.0, top, cw + 12.0, 20.0),
		Rect2(x0 + cw + mw - 6.0, top, cw + 12.0, 20.0)]


# The bakes carry huge transparent margins (a 64px sprite whose body is ~18px),
# so draw_texture_rect stretches mostly-empty texture into a box and the visible
# body collapses to a speck. Cache each sprite's opaque bounds once and draw
# ONLY that region, aspect-preserved and centered — a small box then shows a
# full body. Cache is keyed by sprite name (bakes are immutable at runtime).
static var _trim_cache := {}


func _visible_region(key: String) -> Rect2:
	if not _trim_cache.has(key):
		var t := Art.tex(key)
		var img := t.get_image() if t != null else null
		var full := Rect2(Vector2.ZERO, t.get_size()) if t != null else Rect2()
		if img != null:
			var used := img.get_used_rect()
			_trim_cache[key] = Rect2(used) if used.size.x > 0 and used.size.y > 0 else full
		else:
			_trim_cache[key] = full
	return _trim_cache[key]


# Draw a sprite's opaque region cropped and centered inside `box`, aspect kept.
func _draw_sprite_fit(key: String, box: Rect2, mod: Color) -> void:
	var t := Art.tex(key)
	if t == null:
		return
	var reg := _visible_region(key)
	var s := minf(box.size.x / reg.size.x, box.size.y / reg.size.y)
	# Snap size and position to whole pixels — fractional dst rects blur pixel art.
	var dst := (Vector2(reg.size.x, reg.size.y) * s).round()
	var pos := (box.position + (box.size - dst) / 2.0).round()
	draw_texture_rect_region(t, Rect2(pos, dst), reg, mod)


static func _best_line(score: int, wave: int, dist: int) -> String:
	# a2-04 HUD#8: the title BEST line drops zero fields so it never advertises
	# "WAVE 0 · 0m" (a debug-dump read) on a fresh score-only best.
	var s := "BEST — SCORE %s" % Art.group_digits(score)   # a4-17: thousands separators
	if wave > 0:
		s += " · WAVE %d" % wave
	if dist > 0:
		s += " · %dm" % dist
	return s


func _center_text(txt: String, y: float, size: int, col: Color) -> void:
	Art.text_center(self, txt, CENTER_X, y, size, col)


# c1-09: the OPTIONS screen header — a compact 2-line block (title y80 / summary y94)
# so the 8-row settings list seats at top=102 and still clears a >=20px plate. Extracted
# so a headless capture test can invoke the REAL header draw (through _center_text, which
# a test subclass records) and prove it renders, at what y, and with what text — not just
# that some string fits some width. Settings ONLY now: HALL OF FAME / HOW TO PLAY moved
# to the INFO screen, so this header is a plain "OPTIONS".
func _draw_opts_header() -> void:
	# c2-11: a gear icon crowns the title so OPTIONS gets a header cue like the other
	# screens instead of a lone word. It sits just left of the centered title, vertically
	# centered on the title's cap height. Routed through _emit_tex so the header capture
	# test stays headless-safe (and the draw is inspectable).
	var f := Art.font()
	# c3-18: a trailing "*" flags UNSAVED staged changes at a glance (the conventional dirty-doc cue),
	# alongside the SAVE / DISCARD exit rows the dirty state also surfaces — so pending edits read
	# before the player reaches the bottom of the list. Measured/drawn from the live title so the gear
	# stays seated on the actual (possibly wider) title box.
	var title := "OPTIONS *" if _opts_dirty else "OPTIONS"
	var titlew := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var isz := 16.0
	# c2-11: seat the gear on the title's CAP BOX, not the ascent-to-descent line. "OPTIONS"
	# is all-caps sitting on the y80 baseline; for PixelOperator8 the caps rise the full
	# cap height (measured 16px @18 — caps span y64..y79, ending 1px above the baseline).
	# Centering the icon on that box (top y64, bottom the baseline) aligns it pixel-perfect
	# with the caps instead of floating a hair high off the whole-line ascent metric.
	var cap_h := 16.0
	var cap_top := OPTS_TITLE_Y - cap_h
	var iy := cap_top + (cap_h - isz) / 2.0
	var ix := (CENTER_X - titlew / 2.0) - 6.0 - isz
	_emit_tex("mi_settings", Rect2(ix, iy, isz, isz), Color(1, 1, 1, 0.9))
	_center_text(title, OPTS_TITLE_Y, 18, HEADER_COL)
	# After RESET DEFAULTS fires, the summary line briefly becomes a success banner;
	# otherwise it's the single place to review live settings state — the DISPLAY mode
	# (no on-screen toggle) and EVERY accessibility aid's explicit ON/OFF state.
	if _reset_flash > 0.0:
		# A player who HAD reduce-motion on when they reset gets the banner at steady
		# full alpha (no fade ramp) — captured pre-reset, since the reset itself turns
		# motion back on. It still clears on its timer; only the animation is snapped.
		var ba := clampf(_reset_flash / 0.6, 0.0, 1.0) if _reset_flash_anim else 1.0
		_center_text("DEFAULTS RESTORED", OPTS_SUBLINE_Y, 9, Color(0.55, 0.95, 0.5, ba))
	elif _menu_items()[sel]["id"] == "reset_defaults":
		# When focus is on RESET DEFAULTS, the summary line names EXACTLY what the
		# two-press confirm will wipe — every settings group at once — so the player
		# knows the blast radius BEFORE the second press, not just "this is destructive".
		_center_text("RESET RESTORES AUDIO / HAPTICS / ACCESSIBILITY / DISPLAY TO DEFAULTS",
			OPTS_SUBLINE_Y, 8, WARN_COL)
	else:
		_center_text(a11y_summary(main._motion < 0.5, main.colorblind, main._assist,
			main._rumble_on, main._fullscreen), OPTS_SUBLINE_Y, 8, SUBTITLE_COL)


# Trim a label to max_w with a trailing ellipsis (raw clipping ate whole glyphs
# mid-character; dynamic labels like the seed row can outgrow the button).
func _ellipsize(txt: String, size: int, max_w: float, keep_tail := "", warn := false) -> String:
	var f := Art.font()
	if f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return txt
	var ell := "…" if f.has_char(0x2026) else "..."
	# c3-17: a destructive row's warning cue (" PRESS TWICE" / " PRESS AGAIN" — the thing
	# telling the player this row is one/two presses from wiping a run) must NEVER be the tail
	# that truncation eats. When the caller marks a suffix as load-bearing (keep_tail) and the
	# label ends with it, ellipsize only the NAME ahead of the cue and keep the cue INTACT —
	# "RESTART PRESS AGAIN" -> "RES… PRESS AGAIN", never "RESTART PRESS…". Only take this when
	# the "…<cue>" itself fits.
	var head := txt.substr(0, txt.length() - keep_tail.length()) if keep_tail != "" and txt.ends_with(keep_tail) else txt
	if keep_tail != "" and txt.ends_with(keep_tail) \
			and f.get_string_size(ell + keep_tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return _fit_prefix(f, head, ell + keep_tail, size, max_w) + ell + keep_tail
	# Plate too tight for the spelled-out cue (or a bare-cue label with no separable head):
	# for ANY destructive row (warn) DEGRADE to the minimal "!" marker rather than clipping the
	# danger signal away — "RES…!" still reads as destructive where a plain "RESTA…" would not.
	# Spacing is intentionally "…!" (no space before "!", unlike a resting " !" suffix): on a
	# floor-width plate every px is scarce and the ellipsis already separates name from mark.
	# If even "…!" is wider than the column (a plate narrower than two glyphs) fall through to
	# the plain trim below — the caller's Art.text max_w hard-clips that last-resort string, so
	# nothing overdraws the slot; there is simply no room left for any cue at that width.
	if warn:
		var mark := ell + DESTR_CUE_MARK
		if f.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return _fit_prefix(f, head, mark, size, max_w) + mark
	# c2-14: toggle/value rows read "NAME: STATE" (e.g. "ASSIST (2-HIT): OFF"). The
	# STATE tail IS the point of the row, so ellipsize the NAME and KEEP the tail
	# ("NAM…: OFF") rather than silently trimming the ON/OFF off the end. Only take
	# this path when the "…: STATE" tail itself fits; otherwise fall through to the
	# plain trim, which still flags the overflow with a trailing ellipsis. Trimming is
	# glyph-aware (whole-cluster cut points) so a wide label never splits a glyph.
	# Split on the FIRST ": " — that is the NAME/VALUE separator; any colon inside the
	# value (a time, a ratio) stays with the preserved tail.
	var sep := txt.find(": ")
	if sep > 0:
		var tail := txt.substr(sep)   # ": STATE"
		if f.get_string_size(ell + tail, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			return _fit_prefix(f, txt.substr(0, sep), ell + tail, size, max_w) + ell + tail
	return _fit_prefix(f, txt, ell, size, max_w) + ell


var _cut_cache := {}   # c2-14: memoized glyph cuts, keyed font+text+size; FIFO-capped
const _CUT_CACHE_MAX := 128

var _row_fit_cache := {}   # c2-14: memoized per-row overflow/ellipsis, keyed font+size+avail+label
const _ROW_FIT_CACHE_MAX := 128


# c2-14: decide, once per (label, size, column width), whether a menu row overflows its
# column and what to draw for it. Returns {overflow, show_chip, shown}. The _draw runs
# every frame, so without this a persistently-visible over-width row re-measures and
# re-binary-searches the same string 60x/s — this memoizes the result until label, size,
# or the column width (avail) changes (each is in the key, so a change is a fresh entry;
# stale entries FIFO-evict). `reserve` is the chip's footprint: the chip only shows when
# it actually fits (reserve < avail), otherwise the row degrades to a bare ellipsized
# label — never a negative ellipsize width or a chip drawn over the text.
func _row_fit(label: String, size: int, avail: float, reserve: float, keep_tail := "", warn := false) -> Dictionary:
	var f := Art.font()
	var key := "%d|%d|%.2f|%.2f|%d|%s|%s" % [f.get_instance_id(), size, avail, reserve, int(warn), keep_tail, label]
	if _row_fit_cache.has(key):
		return _row_fit_cache[key]
	var overflow := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > avail
	var show_chip := overflow and reserve < avail
	var shown := _ellipsize(label, size, avail - reserve if show_chip else avail, keep_tail, warn)
	var res := {"overflow": overflow, "show_chip": show_chip, "shown": shown}
	if _row_fit_cache.size() >= _ROW_FIT_CACHE_MAX:
		_row_fit_cache.erase(_row_fit_cache.keys()[0])
	_row_fit_cache[key] = res
	return res


# c2-14: string offsets where a whole glyph/grapheme begins, from the TextServer
# shaper. Cutting a label at these (instead of at raw code points via substr) never
# splits a combining mark or multi-codepoint cluster mid-glyph. Ends with the full
# length so the untrimmed prefix is a candidate too. Memoized — a persistently
# over-width row otherwise reshapes the same string every frame; the key includes the
# font instance so a re-themed/localized font can't return stale cuts. Godot 4's
# Dictionary GUARANTEES insertion order, so keys()[0] is deterministically the oldest
# entry — eviction is true oldest-first FIFO, and a full menu never re-shapes all.
func _glyph_cuts(f: Font, s: String, size: int) -> PackedInt32Array:
	var key := "%d|%d|%s" % [f.get_instance_id(), size, s]
	if _cut_cache.has(key):
		return _cut_cache[key]
	var ts := TextServerManager.get_primary_interface()
	var sh := ts.create_shaped_text()
	ts.shaped_text_add_string(sh, s, f.get_rids(), size)
	var cuts: PackedInt32Array = [0]
	for gl in ts.shaped_text_get_glyphs(sh):
		var st: int = gl["start"]
		if st > cuts[cuts.size() - 1]:
			cuts.append(st)
	ts.free_rid(sh)
	if cuts[cuts.size() - 1] < s.length():
		cuts.append(s.length())
	if _cut_cache.size() >= _CUT_CACHE_MAX:
		_cut_cache.erase(_cut_cache.keys()[0])
	_cut_cache[key] = cuts
	return cuts


# Returns ONLY the prefix: the largest leading run of WHOLE glyphs of `s` such that
# (prefix + suffix) fits max_w. Glyph-aware (see _glyph_cuts) — the returned length is
# always a glyph boundary, never mid-cluster. When even the empty prefix + suffix
# overflows (a column too narrow for the ellipsis/tail alone) it returns "", so
# "" + suffix STILL exceeds max_w — the degenerate case the caller's Art.text max_w
# hard-clip backstops. Width is monotonic in prefix length, so binary-search the cuts.
# Shared by _ellipsize's three tail-preserving paths (the ": STATE" toggle tail, the c3-17
# destructive cue, and its "!" floor marker): each trims the NAME while the suffix rides whole.
func _fit_prefix(f: Font, s: String, suffix: String, size: int, max_w: float) -> String:
	var cuts := _glyph_cuts(f, s, size)
	var lo := 0
	var hi := cuts.size() - 1
	var best := ""
	while lo <= hi:
		var mid := (lo + hi) / 2
		var prefix := s.substr(0, cuts[mid])
		if f.get_string_size(prefix + suffix, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
			best = prefix
			lo = mid + 1
		else:
			hi = mid - 1
	return best


# c2-14: the overflow-flag chip for an ellipsized row, spanning [label_r - 12, label_r]
# vertically centred on the row. Its right edge is exactly label_r, so it stays STRICTLY
# inside the label column and can never bleed into the right-edge dot/chevron slots.
# Extracted so the "chip clears the column" invariant is unit-testable without a _draw.
func _overflow_chip_rect(label_r: float, cy: float) -> Rect2:
	return Rect2(label_r - 12.0, cy - 5.0, 12.0, 14.0)


# One howto line at x=60: "@action" segments draw the device glyph inline,
# plain segments draw as text; x flows left to right (same measure-then-place
# pattern as the wheel line above).
func _verb_line(segs: Array, base_y: float, col: Color) -> void:
	var f := Art.font()
	var x := 60.0
	for seg: String in segs:
		if seg.begins_with("@"):
			var action := seg.substr(1)
			if action == "grenade" or action == "fire":
				# No Art.draw_glyph entry for these — use the device hint art
				# (mouse button / trigger sprite), aspect preserved.
				var t := Art.tex(Art.glyph_key(action))
				var gw := 12.0 * float(t.get_width()) / float(t.get_height())
				draw_texture_rect(t, Rect2(x, base_y - 10.0, gw, 12.0), false)
				x += gw + 4.0
			else:
				Art.draw_glyph(self, action, Vector2(x + 6.0, base_y - 4.0), 12.0)
				x += 16.0
		else:
			# c2-02: clamp each text segment to the frame interior (right edge 612) so
			# a long or localized verb line clips instead of bleeding past x=640 into
			# the chrome — same width guard the ENEMIES / ENDLESS pages use.
			Art.text(self, seg, Vector2(x, base_y), 11, col, maxf(0.0, 612.0 - x))
			x += f.get_string_size(seg, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x


const _LEG_H := 11.0   # legend glyph height (aspect preserved per sprite)
const LEG_GAP := 14.0        # c4-05: default inter-segment spacing on a legend/footer row
const LEG_MIN_GAP := 5.0     # c4-05: floor the gap compresses to (glyph+label never collide)
const LEG_SAFE_W := CANVAS_WIDTH - 16.0   # c4-05: legend must fit this band (8px safe margin/side)


# Legend glyph width for a segment: "tex" = registry sprite, "stamp" = letters
# on the wide keycap, "act" = Art.draw_glyph's square prompt, none = text-only.
# Static so the layout test can measure the ACTUAL device-dependent glyph widths.
static func _glyph_w(seg: Dictionary) -> float:
	if seg.has("act"):
		return _LEG_H
	var key: String = seg.get("tex", "glyph_key_wide" if seg.has("stamp") else "")
	if key == "":
		return 0.0
	var t := Art.tex(key)
	return _LEG_H * float(t.get_width()) / float(t.get_height())


# c1-04: pure geometry of a centered legend row — [left_x, total_width]. The SAME
# measure _legend_row's draw loop uses (single source), so a headless test can pin
# the ACTUAL on-screen footer/verb bounds — which depend on the last-used device,
# since pad button glyphs and keyboard keycaps differ in width — instead of a
# re-derived approximation.
static func legend_extent(segs: Array, gap := LEG_GAP, label_cap := 0.0) -> Array:
	var f := Art.font()
	var total := -gap   # segments separated by `gap` px; first one has no gap
	for seg in segs:
		var gw := _glyph_w(seg)
		var lw := f.get_string_size(seg.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		if label_cap > 0.0:
			lw = minf(lw, label_cap)   # c4-05: ellipsized labels measure at the cap (last-resort)
		total += gw + (3.0 if gw > 0.0 else 0.0) + lw + gap
	return [CENTER_X - total / 2.0, total]


# c4-05: the inter-segment gap the footer/legend strip compresses TO when its natural
# LEG_GAP-spaced width would overrun the canvas — so the fullest binding sets (PAUSE's
# verb+nav+HELP row, HALL's FILTER+PAGE+nav, or ANY row after a player rebinds cancel/
# help to a long-named key that widens its keycap) stay wholly on-screen instead of
# clipping a prompt off the edge. Derived so every remaining seg still fits the safe band.
static func legend_fit_gap(segs: Array) -> float:
	var n := segs.size()
	if n < 2:
		return LEG_GAP
	var natural: float = legend_extent(segs)[1]
	if natural <= LEG_SAFE_W:
		return LEG_GAP   # fits at the roomy default; leave it be
	# natural = content + LEG_GAP*(n-1); solve for the gap that lands the row on LEG_SAFE_W,
	# then floor it at LEG_MIN_GAP so glyph and label never collide when the set is huge.
	var content := natural - LEG_GAP * float(n - 1)
	return maxf(LEG_MIN_GAP, (LEG_SAFE_W - content) / float(n - 1))


# c4-05: the HARD ceiling behind the gap compression - the per-label width the row clamps every
# label to when even the floored LEG_MIN_GAP spacing still overruns the safe band (a pathological
# set: very many segments, or several long-rebind keycaps at once). Water-filled: budget/n, so a
# label already SHORTER than the cap stays whole while the long ones ellipsize, and the summed
# labels can never exceed the budget -> no binding EVER clips off-canvas. 0.0 means "no cap needed"
# (the compressed gap already fits), which is every real menu; this only arms in the extreme case.
static func legend_label_cap(segs: Array) -> float:
	var n := segs.size()
	if n < 2:
		return 0.0
	# The tightest the gap can go is LEG_MIN_GAP; if the row fits there, no label cap is needed.
	if legend_extent(segs, LEG_MIN_GAP)[1] <= LEG_SAFE_W:
		return 0.0
	var glyph_w := 0.0
	for seg in segs:
		var gw := _glyph_w(seg)
		glyph_w += gw + (3.0 if gw > 0.0 else 0.0)
	# Whatever the glyphs and the minimum gaps don't claim is the shared label budget.
	var budget := LEG_SAFE_W - glyph_w - LEG_MIN_GAP * float(n - 1)
	return maxf(1.0, budget / float(n))


# c1-04: the EXACT drawn boxes of a legend row — one entry per segment carrying its
# glyph rect (empty for text-only), its label text rect, and the source seg. This
# is the single list _legend_row iterates to draw, so it IS the actual render result
# (glyph AND rendered label/font footprints), not a re-derivation — a headless test
# reads these boxes to prove nothing clips 640x360 or overlaps, in either device
# mode. `y` is the glyph center; label baseline sits at y+3 (8px font, ~8px ascent).
static func legend_primitives(segs: Array, y: float, gap := LEG_GAP, label_cap := 0.0) -> Array:
	var f := Art.font()
	var ext := legend_extent(segs, gap, label_cap)
	var x: float = ext[0]
	var out: Array = []
	for seg in segs:
		var gw := _glyph_w(seg)
		var grect := Rect2()
		if gw > 0.0:
			grect = Rect2(x, y - _LEG_H / 2.0, gw, _LEG_H)
			x += gw + 3.0
		var lsz := f.get_string_size(seg.get("label", ""), HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		var lw: float = lsz.x
		if label_cap > 0.0:
			lw = minf(lw, label_cap)   # c4-05: last-resort ellipsis width so nothing clips off-canvas
		# Real font metrics (measured width + ascent/height), not a hard-coded 8/9px
		# box: Art.text places the baseline at y+3, so the ink spans up by the ascent.
		var lrect := Rect2(x, y + 3.0 - f.get_ascent(8), lw, lsz.y)
		out.append({"seg": seg, "glyph": grect, "label": lrect})
		x += lw + gap
	return out


# c1-04: draw seams — every native draw the footer/legend emits routes through one of
# these one-line indirections, so a headless test subclass can OVERRIDE them to CAPTURE
# the exact draw commands _footer_legend/_legend_row actually issue (proving they run,
# and with what geometry) without a live draw context. Default impls do the real draw.
# c2-11: font size the next _emit_label draw uses. Defaults to the 8px body size and is
# bumped transiently by _emit_group_caption so the section HEADERS render larger without
# changing the _emit_label signature (a headless capture-test subclass overrides that seam
# with the fixed 3-arg shape — its recorded box stays size-independent since the caption is
# right-aligned, so its clearance asserts hold regardless of the rendered size).
var _label_size := 8
# c3-13: optional width clamp the next _emit_label draw passes to Art.text (0 = no clip). Sits
# alongside _label_size as a transient stamp so the _emit_label SEAM keeps its fixed 3-arg shape
# (the capture-test subclass overrides it), while callers that need a max_w set this first.
var _label_max_w := 0.0
func _emit_rect(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
func _emit_tex(key: String, r: Rect2, c: Color) -> void:
	draw_texture_rect(Art.tex(key), r, false, c)
func _emit_glyph(act: String, center: Vector2, size: float, c: Color) -> void:
	Art.draw_glyph(self, act, center, size, c)
func _emit_stamp(txt: String, pos: Vector2, c: Color) -> void:
	draw_string(Art.font(), pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, c)
func _emit_label(txt: String, pos: Vector2, c: Color) -> void:
	Art.text(self, txt, pos, _label_size, c, _label_max_w)


# c1-09: OPTIONS settings groups get a named caption (AUDIO / HAPTICS / ACCESSIBILITY)
# at the first row of each group, right-aligned in the left margin — its right edge at
# plate_left-25, clear of the selected-row cycle arrow (drawn at plate_left-13) — so the
# screen reads as three labelled sections, not one flat list. Routed through _emit_label
# so a headless capture test can invoke this REAL caption draw and inspect the exact box.
func _emit_group_caption(mitems: Array, k: int, cy: float) -> void:
	# c3-03: TITLE names its two IA blocks (DEPLOY / MORE) through the same pill+rule
	# machinery OPTS uses for its settings sections; every other screen keeps the
	# settings-block headers. One shared draw path, two caption vocabularies.
	var ghdr := title_group_header(mitems[k].get("grp", 0)) if mode == Mode.TITLE \
		else group_header(mitems[k].get("grp", 0))
	if ghdr == "":
		return
	# c2-11: the section HEADERS (AUDIO / ASSIST / ACCESSIBILITY) read at size 10 — not the
	# 8px body size — so they scan as headers, not faint asides. Each sits on a subtle pill
	# capped by a warm accent rule spanning the pill's full width, so the settings blocks are
	# unmistakably delimited even at rest. Right-aligned in the left gutter, right edge at
	# plate_left-25, clear of the selected-row cycle arrow (drawn at plate_left-13). Routed
	# through _emit_label/_emit_rect so a headless capture test can inspect the exact boxes.
	var f := Art.font()
	var hsz := 10
	var gw := f.get_string_size(ghdr, HORIZONTAL_ALIGNMENT_LEFT, -1, hsz).x
	var gx := (CENTER_X - BTN.x / 2.0) - 25.0 - gw
	var by := cy + 3.0   # text baseline (kept level with the group's first row label)
	var padx := 4.0
	var pady := 2.0
	var ptop := by - f.get_ascent(hsz) - pady
	var ph := f.get_ascent(hsz) + f.get_descent(hsz) + pady * 2.0
	# The pill boxes the header so the block boundary is obvious without relying on the 1px
	# group rule alone; its full width also anchors the accent rule (no more short stub).
	_emit_rect(Rect2(gx - padx, ptop, gw + padx * 2.0, ph), Color(0.12, 0.16, 0.09, 0.6))
	_label_size = hsz
	_emit_label(ghdr, Vector2(gx, by), CAPTION_COL)
	_label_size = 8
	_emit_rect(Rect2(gx - padx, ptop + ph - 1.0, gw + padx * 2.0, 1.0), CAPTION_COL)


# One centered legend line of [glyph + verb] segments; y is the glyph center. Emits
# straight off legend_primitives (through the seams above) so the pixels land exactly
# where the test measures — and the capture test sees the real commands.
func _legend_row(segs: Array, y: float, a: float) -> void:
	var f := Art.font()
	# c4-05: two-stage no-clip guarantee. First shrink the inter-segment gap when the natural
	# spacing would push a prompt off-screen (the fullest PAUSE/HALL binding rows, or a row whose
	# keycap grew after a long rebind). If even the floored gap still can't fit, the HARD ceiling
	# arms: every label is capped and ellipsized (legend_label_cap) so no binding EVER clips.
	var cap := legend_label_cap(segs)
	for p in legend_primitives(segs, y, legend_fit_gap(segs), cap):
		var seg: Dictionary = p["seg"]
		var grect: Rect2 = p["glyph"]
		if grect.size.x > 0.0:
			if seg.has("act"):
				# Pass the row alpha so action glyphs fade with the texture glyphs and
				# labels (they used to draw at full opacity, off from the rest of the row).
				_emit_glyph(seg["act"], grect.get_center(), _LEG_H, Color(1, 1, 1, a))
			else:
				_emit_tex(seg.get("tex", "glyph_key_wide"), grect, Color(1, 1, 1, a))
				if seg.has("stamp"):
					var st: String = seg["stamp"]
					var sw := f.get_string_size(st, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x
					_emit_stamp(st, Vector2(grect.position.x + (grect.size.x - sw) / 2.0, y + 2.0),
						Color(0.15, 0.16, 0.12, a))
		# When the hard cap is armed, clamp the label draw to the SAME width the layout reserved
		# so Art.text ellipsizes to match its measured box (0.0 = no clip, the usual path).
		_label_max_w = p["label"].size.x if cap > 0.0 else 0.0
		_emit_label(seg.get("label", ""), Vector2(p["label"].position.x, y + 3.0),
			Color(0.82, 0.87, 0.77, a))
	_label_max_w = 0.0   # reset the transient clip stamp so it can't leak to the next draw


# c1-04: input legend BEYOND the TITLE screen. One SELECT/BACK footer on EVERY
# non-TITLE screen (PAUSE / OPTS / SETUP / HALL / HOWTO), drawn with the real
# device-aware prompt art (Enter/A, Esc/B) — so keyboard/pad players don't lose
# nav discovery after first launch. One shared strip position (FOOTER_Y), pinned
# clear of the selected-row glow (see _row_geometry's drop cap + the layout test).
# PAUSE additionally carries the PERMANENT ROLL/WHEEL/REVIVE reference (_footer_segs),
# so the in-run HUD reminder can stay purely transient without those bindings
# becoming unrecoverable mid-run.


# c3-09: the TOP line of the two-line settings footer — the focused row's description in high-contrast
# helper text (FOOTER_HELP_COL), with a hairline rule under it so the description never reads as
# another actionable prompt. Ellipsized to the same CANVAS_WIDTH - 24 budget the wording tests assert,
# a safety net so an edited/localized string can never overrun the canvas. Returns the y the
# SELECT/BACK legend sits at, one line below.
func _draw_footer_help(row_help: String, strip_top: float) -> float:
	# Description baseline strip_top+10 (glyphs y340..348 at 8px) — nudged 2px down from the strip top
	# so its ascenders clear the last-row glow by ~6.5px instead of crowding it. The returned legend
	# baseline strip_top+17 seats the legend's label (drawn at +3 inside _legend_row) at glyphs
	# y350..358 — flush with the strip bottom, no descender spill. The 1px rule sits at strip_top+12
	# (y349), cleanly in the gap between the two lines.
	# c3-17: the ONLY other _ellipsize caller — footer help text, which carries no destructive
	# cue (no keep_tail/warn needed). Every destructive-row label routes through _row_fit above,
	# so the cue-preserving path covers all destructive truncation.
	_center_text(_ellipsize(row_help, 8, CANVAS_WIDTH - 24.0), strip_top + 10.0, 8, FOOTER_HELP_COL)
	_emit_rect(Rect2(CENTER_X - BTN.x / 2.0, strip_top + 12.0, BTN.x, 1.0), DIVIDER_DIM)
	return strip_top + 17.0


# c3-09: dedupes the missing-copy dev warning so it fires once per id, not every frame.
static var _help_warned := {}


# c4-05: the per-menu binding hint the footer legend prepends ahead of the shared SELECT/BACK
# nav — the context controls each non-TITLE screen must teach so a player never has to guess
# how to filter, page, or adjust after backing into it (or after swapping input mid-session):
#   HALL  -> L/R = FILTER, plus UP/DN = PAGE once the board spills past one page
#   HOWTO -> L/R = PAGE (the field-manual tabs turn on the horizontal axis)
#   REBIND-> the SECTION tab-switch (TAB / shoulder button), device-aware
#   OPTS / SETUP / DISP (and any menu with a focused adjustable row) -> the row's ADJUST/TOGGLE
# Every other menu (PAUSE / INFO) returns [] and rides the plain SELECT/BACK (+ PAUSE verbs)
# nav. Pulled out of _footer_legend so the "which bindings on which menu" contract reads in one
# place and a headless test can assert each menu's hint without a live draw.
func _mode_hint_segs(focused: Dictionary) -> Array:
	match mode:
		Mode.HALL:
			var head: Array = footer_hall_filter_segs()
			if main != null and _hall_pages(_hall_rows().size()) > 1:
				head += footer_page_segs()   # UP/DN = PAGE only when the board actually pages
			return head
		Mode.HOWTO:
			return footer_howto_page_segs()
		Mode.REBIND:
			return _footer_rebind_tab_segs()
		_:
			# On the settings screens the focused row's ◄/► adjust it in place (toggle flip,
			# volume/scale step) — surface that bind whenever the focused row is an adjustable one.
			if not focused.is_empty() and _row_cycles(focused):
				return footer_cycle_segs(focused)
	return []


# c4-05: TRUE when the last-used input device changed enough to re-skin every legend glyph —
# either the keyboard<->pad flip (use_pad) OR a pad-brand swap (Xbox<->PlayStation<->Switch) that
# keeps use_pad true but repaints the A/B/X/Y button art. main.gd calls this on each _input to
# decide whether an idle menu (a settled Reduce-Motion screen repaints on nothing) must repaint so
# the strip never keeps teaching the OLD device's buttons after a mid-session swap. Pure/static so
# a headless test pins every transition (flip, brand-only, no-op) without an InputEvent or live Main.
static func device_glyphs_changed(was_pad: bool, was_brand: String, use_pad: bool, brand: String) -> bool:
	return use_pad != was_pad or brand != was_brand


func _footer_legend() -> void:
	# c4-05: THE single canonical input-legend seam. Every non-TITLE menu's _draw() routes here
	# (PAUSE / OPTS / SETUP / DISP / INFO / REBIND directly, HALL / HOWTO via the content-well
	# branch) — TITLE alone draws its own richer two-row control legend inline. So "does this menu
	# show its bindings?" has ONE answer and a newly-added menu can't silently ship without a strip.
	# c3-09: on a value-holding settings row the footer grows a SECOND line — the row's effect +
	# persistence description on top, the SELECT/BACK legend below (see _draw_footer_help). Shared by
	# OPTIONS / DISPLAY / RUN SETUP; other screens hold no such rows, so it stays one line. It sits
	# wholly below the list (glow clears FOOTER_Y), so the header keeps its a11y summary untouched.
	var items: Array[Dictionary] = _menu_items() if main != null else ([] as Array[Dictionary])
	var focused := items[sel] if sel >= 0 and sel < items.size() else {}
	var row_help: String = setting_help(focused.get("id", ""))
	# c4-01: when the focused volume row is MUTED, front-load the RECOVERY ACTION as prose (not a
	# second copy of the word "MUTED" — that already reads on the row label, the muted-speaker icon
	# and the slashed bar). The helper text is the only channel that spells out HOW to bring the bus
	# back, so it names the slider move that un-mutes; the L/R glyph hint below reads "UNMUTE" to match.
	if row_help != "" and focused.get("muted", false):
		row_help = "STEP THE SLIDER RIGHT TO UNMUTE. %s" % row_help
	# Dev guard: a row that HOLDS a value (on/vol/step) but has no description is missing copy — warn
	# once so it surfaces in-game, not only in the mapping test.
	if row_help == "" and (focused.has("on") or focused.has("vol") or focused.has("step")):
		var mid: String = focused.get("id", "")
		if not _help_warned.has(mid):
			_help_warned[mid] = true
			push_warning("setting_help missing for value row '%s'" % mid)
	var two_line := row_help != ""
	var strip_top := FOOTER_Y - FOOTER_HELP_RISE if two_line else FOOTER_Y
	var strip_h := FOOTER_H + FOOTER_HELP_RISE if two_line else FOOTER_H
	_emit_rect(Rect2(0, strip_top, CANVAS_WIDTH, strip_h), PLATE_BG)
	var legend_y := FOOTER_Y + 8.0
	if two_line:
		legend_y = _draw_footer_help(row_help, strip_top)
	# c4-05: prepend THIS menu's context bindings ahead of the shared SELECT/BACK nav — the
	# per-screen hint the strip would otherwise leave a device-swapped player to guess.
	var segs := _mode_hint_segs(focused) + _footer_segs()
	# c4-01: Enter/click on a volume row STEPS the level up (never a mute toggle), so the confirm
	# verb names that real action instead of the generic "SELECT": "UNMUTE" while the bus is silent
	# (a press lifts it off 0), "MAX" once it is pinned at the ceiling (a further press only rail-
	# bounces, so don't promise a raise that can't happen), and "VOL +" in between. The whole strip
	# now tells the SAME story -- ◄/► adjusts, Enter raises, a muted row spells out how to restore it.
	if focused.get("id", "") in ["sfx", "music"]:
		var verb := "UNMUTE" if focused.get("muted", false) else ("MAX" if int(focused.get("vol", 0)) >= 10 else "VOL +")
		for s in segs:
			if s is Dictionary and s.get("label", "") == "SELECT":
				s["label"] = verb
				break
	_legend_row(segs, legend_y, 0.9)


# c1-04: the SELECT / BACK footer segments, device-aware via Art.glyph_key (the
# same registry the TITLE SELECT glyph uses): Enter / Esc keycaps on keyboard
# (BACK stamped ESC, like the WASD/MOVE cap), A / B buttons on a pad. Pulled out
# so a headless test can prove the kb<->pad glyph swap without a Control or draw.
static func footer_nav_segs() -> Array:
	var nav: Array = [{"tex": Art.glyph_key("confirm"), "label": "SELECT"},
		{"tex": Art.glyph_key("back"), "label": "BACK"}]
	if not Art.use_pad:
		nav[1]["stamp"] = "ESC"   # kb back is a bare keycap; stamp it like WASD/MOVE
	return nav


# c1-04: the PERMANENT ROLL / WHEEL / REVIVE reference. The in-run HUD reminder is
# TRANSIENT now (it fades out so it never continuously overlays the playfield), so
# PAUSE — the one menu reachable mid-run — carries these bindings permanently: a
# player who forgot them pauses and re-reads them. "act" keys resolve device-aware
# through Art.draw_glyph, same as the TITLE legend's verb row.
static func footer_verb_segs() -> Array:
	return [{"act": "roll", "label": "ROLL"},
		{"act": "wheel", "label": "SUPPLY WHEEL"},
		{"act": "revive", "label": "REVIVE"}]


# c3-10: the keycap the footer/legend stamps for BACK & PAUSE, DERIVED from the LIVE
# menu_cancel binding (the one key that backs out of a menu AND opens PAUSE mid-run)
# instead of a hardcoded "ESC" literal — so a player who rebinds cancel is taught THEIR
# key. Uppercased to sit in the keycap; falls back to "ESC" when unbound or when the
# display server can't resolve a label (headless), matching footer_nav_segs's static default.
func _back_keycap() -> String:
	if main == null:
		return "ESC"
	var cap := key_label(main.menu_bind("menu_cancel")).to_upper()
	return cap if cap != "" and cap != "UNBOUND" else "ESC"


# c3-10: the LIVE HOW TO PLAY shortcut keycode — the "menu_help" menu binding (remappable),
# falling back to HELP_KEY only for the headless capture menu with no main. The input handler
# matches this and _help_keycap stamps it, so hint and handler can never disagree.
func _help_code() -> int:
	return main.menu_bind("menu_help") if main != null else HELP_KEY


# c3-10: the HOW TO PLAY shortcut's keycap, DERIVED from the live _help_code via key_label — so
# the stamp is never a stray 'F1' literal that could drift from the real bind. Uppercased.
func _help_keycap() -> String:
	return key_label(_help_code()).to_upper()


# c3-10: ONE builder for a stamped keycap segment, so the small-vs-wide blank choice is made in a
# SINGLE place and stays consistent across the gameplay legend row AND the menu footer. A label of
# 4+ chars (e.g. "ESCAPE") rides the wide keycap so the stamp never clips; up to 3 ("ESC"/"F1")
# sits on the compact blank.
func _keycap_seg(cap: String, label: String) -> Dictionary:
	return {"tex": "glyph_key_wide" if cap.length() > 3 else "ui_key_blank", "stamp": cap, "label": label}


# c3-10: instance wrapper over the static footer_nav_segs — on keyboard BOTH nav keycaps are
# swapped for their LIVE bindings so the drawn strip reflects a rebound cancel/confirm key: BACK
# takes the menu_cancel keycap (_back_keycap, never a hardcoded "ESC"), and SELECT keeps the
# dedicated Enter-key art for an Enter-family confirm but stamps its own keycap once confirm is
# rebound elsewhere. A label wider than the small blank keycap (e.g. "ESCAPE") rides the WIDE
# blank so the stamp never clips. Pad prompts are untouched (the static A/B buttons).
func _footer_nav_segs() -> Array:
	var nav := footer_nav_segs()
	if not Art.use_pad:
		nav[1] = _keycap_seg(_back_keycap(), "BACK")   # live menu_cancel keycap, never "ESC"
		if main != null:
			var ccode: int = main.menu_bind("menu_confirm")
			if ccode != KEY_ENTER and ccode != KEY_KP_ENTER and ccode != KEY_SPACE and ccode != 0:
				nav[0] = _keycap_seg(key_label(ccode).to_upper(), "SELECT")
	return nav


# c3-10: the full footer legend a screen draws — SELECT/BACK nav on every non-TITLE screen
# (with the LIVE keycaps), the gameplay-verb reference prepended on PAUSE (the mid-run recovery
# hub). On keyboard EVERY menu footer also advertises the F1 = HELP (HOW TO PLAY) shortcut so
# help is one keypress away and discoverable everywhere — except HOWTO itself, where it's
# already open. Pad reaches HOW TO through the menus (no F1), so the hint is keyboard-only.
func _footer_segs() -> Array:
	var segs: Array = footer_verb_segs() + _footer_nav_segs() if mode == Mode.PAUSE else _footer_nav_segs()
	if not Art.use_pad and mode != Mode.HOWTO:
		segs.append(_keycap_seg(_help_keycap(), "HELP"))
	return segs


# c1-13: the explicit paging key hint for the Hall footer — a wide keycap stamped with
# the up/down axis and a PAGE label. Both keyboard arrows and pad dpad page on up/down,
# so one axis-stamped cap reads on either device. Static so a headless test can pin it.
static func footer_page_segs() -> Array:
	return [{"tex": "glyph_key_wide", "stamp": "UP/DN", "label": "PAGE"}]


# c2-02: the HOW-TO paging hint — the pages turn on the horizontal axis, so the
# wide keycap is stamped L/R. Static so a headless test can pin it.
static func footer_howto_page_segs() -> Array:
	return [{"tex": "glyph_key_wide", "stamp": "L/R", "label": "PAGE"}]


# c3-10: the REBIND category-tab hint — the MOVE-AIM / ACTIONS / GAMEPAD sections switch on the
# menu_next_tab key (keyboard) or a shoulder button (pad). Device-aware via Art.use_pad: the
# left-shoulder glyph on a pad; on keyboard the keycap is DERIVED from the LIVE menu_next_tab bind
# (via _tab_keycap) so a rebound section key is taught truthfully, never a stray "TAB" literal.
func _footer_rebind_tab_segs() -> Array:
	if Art.use_pad:
		return [{"tex": "glyph_lb", "label": "SECTION"}]
	return [_keycap_seg(_tab_keycap(), "SECTION")]


# c3-10: the keycap the REBIND footer stamps for the section switch, DERIVED from the live
# menu_next_tab bind via key_label — so it follows a rebind and can't drift from the handler.
# Falls back to "TAB" when unbound or when the display server can't resolve a label (headless),
# matching the ship default (KEY_TAB).
func _tab_keycap() -> String:
	if main == null:
		return "TAB"
	var cap := key_label(main.menu_bind("menu_next_tab")).to_upper()
	return cap if cap != "" and cap != "UNBOUND" else "TAB"


# c2-03: the HALL filter hint — the ALL/CAMPAIGN/ENDLESS tabs cycle on the horizontal
# axis (A/D + arrows on keyboard, dpad/stick on pad), so one L/R-stamped wide keycap
# reads on either device, same grammar as the HOW-TO page hint. Static so a headless
# test can pin it without a Control or draw context.
static func footer_hall_filter_segs() -> Array:
	return [{"tex": "glyph_key_wide", "stamp": "L/R", "label": "FILTER"}]


# c2-03: the settings-row ◄/► hint for the footer strip — a wide keycap stamped L/R.
# The label names what the arrows do on the focused row, derived from the row's OWN
# shape so it can't drift from how the row behaves. Only ever called for rows
# _row_cycles() accepts, whose two families are: STEPPED value controls — a "vol" bar
# or a "step" stepper (e.g. WINDOW SCALE) — which read ADJUST, and boolean toggles
# (everything else _row_cycles takes, which flip in place) which read TOGGLE. Keying
# ADJUST off the explicit stepped shape (the "vol"/"step" schema flags, not "not has on")
# means a newly-added toggle that forgets an "on" field still reads TOGGLE — the safe
# default for a flip row — rather than mislabeling as ADJUST.
static func footer_cycle_segs(item: Dictionary) -> Array:
	var stepped: bool = item.has("vol") or item.has("step")
	var lbl := "ADJUST" if stepped else "TOGGLE"
	# c4-01: a MUTED volume row names the mute affordance in the L/R hint — any raise
	# lifts it off mute, so the arrows read "UNMUTE" (not the generic ADJUST) while it is
	# silent, telling the player exactly how to bring the bus back without exiting the menu.
	if stepped and item.get("muted", false):
		lbl = "UNMUTE"
	return [{"tex": "glyph_key_wide", "stamp": "L/R", "label": lbl}]
