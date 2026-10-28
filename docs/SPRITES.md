# Making your own Koderkatins pet with ChatGPT

This guide takes you from nothing to a fully animated pet using ChatGPT's image generator
(GPT‑4o / `gpt-image` in ChatGPT, or the same model through the OpenAI API). It takes about
15 minutes and five image generations.

```
1. character sheet   → one consistent design
2. idle.png          ┐
3. working.png       │ one image per animation, each a 3 × 2 grid of 6 frames
4. attention.png     │
5. worried.png       │
6. done.png          ┘
7. python3 tools/import_sprites.py …   → pets/<name>/spritesheet.webp + pet.json
```

The importer finds the frames even when they're slightly uneven, removes the background,
scales every frame of every animation by the **same** factor, lines their feet up on one
baseline and writes a petdex-compatible sheet. You don't need to edit anything in Photoshop.

---

## Ground rules (why the prompts look the way they do)

Image models are good at drawing characters but poor at hitting exact pixel grids and at
staying consistent between images. The prompts deal with this by:

- **Doing all generations in ONE chat.** Each prompt refers back to "the character sheet
  above". Starting a new chat loses the design.
- **Asking for a loose 3 × 2 grid with wide empty gutters.** The importer cuts at empty space,
  so the frames don't need to be perfectly centred, but they must not touch.
- **Asking for a transparent background.** ChatGPT supports it. If you get a solid colour
  instead, that's fine: the importer removes a flat background it samples from the corners.
  This is why the fallback colour is a flat chroma green that never appears on the cat.
- **Repeating the full style block in every prompt**, because the model forgets details
  silently.
- **Describing motion as small, specific changes per frame.** Vague requests like "make it
  animate" produce six unrelated poses.

If a result is bad, regenerate just that image. Don't change the character sheet after you've
started on the animations.

---

## Prompt 0: the style block (pasted into every prompt below)

Copy this block exactly. Change only the parts in **[brackets]** to design your own cat. The
two example values are the default orange tabby and a second "midnight" cat.

```
STYLE BLOCK — keep identical in every image:
Character: a small, round, friendly cartoon kitten mascot for a coding app.
Fur: [warm orange tabby with three darker orange stripes on the forehead and a cream belly and muzzle]
  (alternative: [deep charcoal-black fur with a white chest blaze and white sock paws])
Eyes: [large round emerald-green eyes] with one small white highlight in the upper left of each eye.
Nose: tiny pink triangle. Mouth: small "w" shape. Three thin dark whiskers each side.
Ears: large, upright, triangular, pink inner ear.
Tail: long, thick, same colour as the body, tip slightly darker.
Proportions: chibi — head is about 45% of total height, short body, stubby legs, 4 visible paws.
Accessory: [a tiny teal bandana around the neck] (must appear in every frame, same colour, same knot side).
Art style: clean modern 2D vector cartoon / sticker style, thick consistent dark-brown outline (about 3% of character height),
  flat colours with ONE soft cel-shade tone per colour, no gradients, no texture, no painterly brushwork,
  no drop shadow under the character, no glow, no background scenery, no ground line, no text, no signature, no watermark.
Lighting: soft, from the top-left, identical in every frame.
View: three-quarter front view facing slightly to the viewer's right, identical camera angle and zoom in every frame.
Background: fully TRANSPARENT (PNG alpha). If transparency is impossible, use one perfectly flat solid #00FF00 green with no
  shading, no vignette and no noise, and never use any green on the character itself.
```

---

## Prompt 1: character sheet (reference only, not imported)

```
Create a character reference sheet for a desktop pet mascot.

[PASTE STYLE BLOCK]

Layout: landscape 1536×1024. Three full-body views of the SAME kitten side by side, evenly spaced, each about 70% of the
image height, standing on four paws, tail curled up behind, calm smile:
  1) three-quarter front view (this is the master pose for all future images),
  2) straight front view,
  3) side view facing right.
Leave at least 120 px of empty space between the figures and around the edges.
No labels, no arrows, no colour swatches, no text.
```

Check: three clearly identical cats, outline thickness, accessory visible. Regenerate until
you love it, because every later image copies this one.

---

## Shared layout paragraph (used by prompts 2–6)

```
LAYOUT — very important:
Image size: landscape 1536×1024.
Draw exactly SIX animation frames of the SAME kitten from the character sheet above, arranged in a grid of
3 columns × 2 rows, read left-to-right, top row first (frame 1 top-left, frame 6 bottom-right).
Each frame occupies its own invisible 512×512 cell. The kitten is centred in its cell and is about 330 px tall
(including ears and tail), with its paws/feet on the same baseline about 60 px above the bottom of the cell.
Same size, same zoom, same camera angle, same outline thickness in all six frames — only the pose changes.
Nothing may cross into a neighbouring cell. Keep at least 90 px of completely empty space between neighbouring kittens.
No grid lines, no borders, no frame numbers, no text, no background, no floor, no shadows.
The six frames must loop smoothly: frame 6 flows naturally back into frame 1.
```

---

## Prompt 2: `idle.png`, relaxed and waiting

```
Using the exact kitten from the character sheet above.

[PASTE STYLE BLOCK]

[PASTE LAYOUT]

ANIMATION: "idle" — the kitten sits calmly, gently breathing, a slow tail swish and one blink.
Frame 1: sitting upright, front paws together, eyes open, tail curled to the right on the ground.
Frame 2: body very slightly taller (inhale, +2%), tail tip lifted a little.
Frame 3: back to frame-1 height, tail tip swings left.
Frame 4: eyes fully closed in a happy blink (curved lines), everything else like frame 3.
Frame 5: eyes open, tail tip swings back to the right, ears twitch: left ear tilted outward slightly.
Frame 6: almost identical to frame 1 (so the loop is seamless), ears back to normal.
Mood: content, cosy. Movements are SUBTLE — the silhouette should barely change.
```

## Prompt 3: `working.png`, typing on a laptop (shown while Claude Code is working)

```
Using the exact kitten from the character sheet above.

[PASTE STYLE BLOCK]

[PASTE LAYOUT]

ANIMATION: "working" — the kitten sits behind a tiny open laptop and types furiously, focused.
Prop: a small dark-grey laptop seen from the back-three-quarter angle, in front of the kitten's lower body, screen glowing
soft cyan, the same size and position in every frame. The laptop is part of the frame (inside the same cell) and does not touch other cells.
The kitten looks down at the screen with determined half-closed eyes and a tiny tongue tip poking out.
Frame 1: left front paw raised above the keyboard, right paw pressing a key.
Frame 2: right paw raised, left paw pressing; a tiny cyan "{" symbol pops above the screen.
Frame 3: like frame 1, ears tilted forward in concentration.
Frame 4: like frame 2, a tiny cyan "}" symbol pops above the screen on the other side.
Frame 5: like frame 1, tail tip flicks upward.
Frame 6: like frame 2, no symbols (so the loop is seamless).
Paws move clearly between frames; head and body stay almost still (slight 1–2% bob only).
The only allowed "text" is the single small curly-brace symbol described in frames 2 and 4.
```

## Prompt 4: `attention.png`, "your turn / needs input"

```
Using the exact kitten from the character sheet above.

[PASTE STYLE BLOCK]

[PASTE LAYOUT]

ANIMATION: "attention" — the kitten wants the user's attention: it waves one paw towards the viewer and calls out.
Frame 1: standing on hind legs, right front paw raised to shoulder height, mouth open in a small "mew", eyes wide and bright.
Frame 2: right paw high above the head, palm (pink paw pads visible) facing the viewer.
Frame 3: right paw tilted to the left (waving motion), head tilted slightly right, ears perked.
Frame 4: right paw tilted to the right, a small yellow exclamation-mark-shaped sparkle (not a letter, a simple drawn icon) above the head.
Frame 5: right paw high again, mouth closed in a smile.
Frame 6: paw coming down to shoulder height, like frame 1 (so the loop is seamless).
Energetic but friendly. Tail held up straight like a question mark.
```

## Prompt 5: `worried.png`, close to a usage limit

```
Using the exact kitten from the character sheet above.

[PASTE STYLE BLOCK]

[PASTE LAYOUT]

ANIMATION: "worried" — the kitten is nervous because it is running out of energy (close to a usage limit).
Frame 1: sitting, ears flattened sideways, eyebrows raised in worry, eyes wide, small wobbly frown, one light-blue sweat drop at the temple.
Frame 2: body shifted 2% to the left (nervous jitter), sweat drop slides slightly down.
Frame 3: body shifted 2% to the right, paws clutched together at the chest.
Frame 4: glances to the side at an imaginary clock, sweat drop near the cheek.
Frame 5: body shifted 2% to the left, a second tiny sweat drop appears on the other side.
Frame 6: like frame 1 (so the loop is seamless).
Tail low and puffed up a little. Keep it cute and comedic, not sad or scary. No red, no clocks drawn, no text.
```

## Prompt 6: `done.png`, turn finished (optional)

```
Using the exact kitten from the character sheet above.

[PASTE STYLE BLOCK]

[PASTE LAYOUT]

ANIMATION: "done" — a small happy celebration hop when a task finishes.
Frame 1: crouched low, ready to jump, eyes happy closed arcs.
Frame 2: springing upward, paws stretched, body 5% higher in its cell.
Frame 3: at the top of the hop, 10% higher, both front paws raised in a cheer, three tiny yellow star sparkles around it.
Frame 4: coming down, 5% higher, sparkles fading.
Frame 5: landed, small squash (2% wider, 2% shorter).
Frame 6: standing normally with a big smile, like the start of frame 1 (so the loop is seamless).
Keep the paws on the shared baseline in frames 1, 5 and 6 — only frames 2–4 lift off.
```

---

## Import

### A. One image per animation (the prompts above)

Download each image as PNG (not a screenshot), then run:

```sh
python3 tools/import_sprites.py --name "Midnight" \
    --idle idle.png --working working.png \
    --attention attention.png --worried worried.png --done done.png \
    --out pets/midnight
```

Then either:

- **bundle it** into the app: pets in `pets/*/spritesheet.webp` are copied into every build by `./build.sh`, or
- **add it to your installed app**: menu bar 🐾 → **Pets → Open Pets Folder…**, and drop the `midnight` folder
  into `~/Library/Application Support/Koderkatins/Pets/`. It appears in the Pets menu straight away.

The importer prints how many frames it found per animation and writes `pets/<name>/preview.png`
(every animation on a dark background), so you can check the result before you build.

Only `--idle` is required. Any animation you leave out falls back to idle.

### B. Everything in one image (a sheet with one animation per row)

ChatGPT sometimes puts every animation into one square image, one row per animation. That's
fine too. This is how the Koderkatis mascot was made: rows idle, typing, thinking, celebrating, puzzled, sleepy.
Tell the importer the grid and what each row is, top to bottom (names: idle, working, thinking, done, attention, worried, sleepy; use `-` to skip a row):

```sh
python3 tools/import_sprites.py --name "Koderkatis" --sheet all.png \
    --grid 6x6 --rows idle,working,thinking,done,attention,sleepy --out pets/koderkatis
```

Rows are split at empty lines. Columns are cut at the least-inked line near each expected
boundary, so frames that slightly touch are still separated. Check `preview.png` afterwards.
If a row looks wrong, change the order in `--rows`.

If you'd rather ask for this layout on purpose, use this prompt after the character sheet:

```
Using the exact kitten from the character sheet above.

[PASTE STYLE BLOCK]

Image size: square 1254×1254. A sprite sheet with 6 rows × 6 columns of equal invisible cells (about 209×209 px each).
Every row is one looping 6-frame animation of the same kitten, read left to right:
  row 1 idle (prompt 2), row 2 working (prompt 3), row 3 attention (prompt 4),
  row 4 worried (prompt 5), row 5 done (prompt 6), row 6 leave completely empty.
The kitten is about 170 px tall, centred in its cell, feet on a shared baseline 15 px above the bottom of the cell.
Leave at least 16 px of empty space between neighbouring kittens and between rows. Nothing may cross into another cell.
Same size, zoom, angle and outline in every cell. No grid lines, no labels, no text, transparent background.
```

The per-animation route (A) gives bigger, cleaner frames because each image spends all its
pixels on one animation. Use B when you want everything in one go.

### Troubleshooting

| Symptom | Fix |
| --- | --- |
| `found 5 frames, expected 6` | Two kittens touch, or a sparkle sits between them. Regenerate, or pass `--min-gap 4` to cut at narrower gaps. |
| `found 9 frames` | Detached sparkles or drops were counted as frames. The importer merges small pieces automatically; raise `--min-area 0.02` if it still happens. |
| Green or white fringe around the cat | The background wasn't flat. Pass `--tolerance 60`, or ask ChatGPT for "fully transparent background" again. |
| The cat jumps around between frames | One frame is a different size. Regenerate that animation and stress "same size, same zoom in all six frames". |
| A different-looking cat in one animation | You started a new chat. Paste the character sheet image back in and say "use exactly this kitten". |

## Sprite sheet format (for developers)

Koderkatins uses the [petdex](https://github.com/crafter-station/petdex) layout, so petdex pets work too:

- 8 columns × 9 rows, each frame **192 × 208 px**, transparent PNG/WebP, frames left-aligned, empty frames fully transparent
- rows used by Koderkatins: **0 idle · 3 attention · 4 done · 5 worried · 6 thinking · 7 working · 8 sleepy**
- missing rows fall back: worried → sleepy → idle, thinking → working → idle, everything else → idle
- `pet.json`: `{"id": "...", "displayName": "...", "spritesheetPath": "spritesheet.webp"}`

Only share pets you have the rights to. Artwork you generate yourself is yours to license.
Petdex pets belong to their submitters.
