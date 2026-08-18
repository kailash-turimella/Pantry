# Pantry

A personal iOS app for tracking what's in my kitchen, so food stops quietly
expiring at the back of the fridge.

Native SwiftUI + SwiftData, local storage only. No accounts, no backend, no
sync. Calls the Claude API for the bits that need judgement: reading photos of
groceries, estimating shelf life, and pulling recipes out of pasted text or
Instagram reels.

## Running it

```bash
open Pantry.xcodeproj
```

Build and run on a simulator or device (iOS 18+), then add an Anthropic API key
in the **Settings tab → Add key**.

It's stored in the iOS keychain as a generic password, with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — so it's unreadable while the
phone is locked, never syncs to iCloud Keychain, and won't come back from a
backup restored onto a different device. There is deliberately no copy on disk
or bundled in the app: a key sitting in a plist inside the `.app` is readable by
anyone holding the bundle, no jailbreak required.

For development, `ANTHROPIC_API_KEY` in the Xcode scheme's environment also
works, so wiping the simulator doesn't mean retyping the key. The keychain wins
if both are present.

Everything except the AI features works without a key.

```bash
xcodebuild test -scheme Pantry -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## How it works

Four tabs:

- **Inventory** — what you have. A "use soon" section pins whatever is closest
  to expiring. Add items by hand, or photograph your shopping and let Claude
  fill in the fields.
- **Recipes** — your recipes, ranked by how much expiring food they'd use up.
  Add them by hand, by pasting text, or from an Instagram reel link.
- **Shopping** — split into what you need to buy and what you already own, by
  cross-referencing the pantry. Populated from a recipe's missing ingredients,
  or typed in.
- **Settings** — API key, per-task model choice, notification timing, rough spend tracker.

### The ranking

`RecipeRanker` doesn't just check whether a recipe contains an expiring
ingredient. Each matched pantry item contributes an urgency weight (expiring
today ≫ expiring in a week ≫ shelf-stable), those are summed, and the total is
scaled by how much of the recipe you can actually make. So a recipe using three
things that expire tomorrow beats one using a single urgent item, and a recipe
you're missing eight ingredients for sinks even if it would use something
urgent. Expired food contributes nothing — you shouldn't cook with it.

### The matching

`IngredientMatcher` decides whether "2 finely chopped large ripe tomatoes" and
"tomato" are the same thing. It strips prep and size words, singularizes, and
then allows a subset match so "chicken breast" satisfies "chicken".

The part worth knowing about is `formTokens`: words like *paste*, *butter*,
*milk*, *stock*, and *flour* mark a different product rather than a variation.
That's what stops "peanut" matching "peanut butter", or "chicken" matching
"chicken stock". Rule-based rather than an API call, because it runs on every
list refresh and needs to be instant, offline, and predictable.

### Expiry estimation

Three tiers, cheapest first:

1. `ShelfLifeRules` — an offline table of ~150 common groceries. Instant, free,
   works on a plane, and deterministic (milk is always 7 days).
2. A cached previous answer for the same item.
3. Claude, for the long tail — gochujang, burrata, kefir.

**A rules table alongside the API call is worth it**, and not only for cost. It
makes the common path deterministic and offline-capable, and it means a flaky
network never blocks saving an item. Claude only sees the ~10% of items the
table doesn't know. Numbers lean conservative on purpose: warning you a day
early is much cheaper than a day late.

Estimated dates are labelled as such throughout the UI, so an estimate is never
mistaken for something printed on the packaging.

## Claude integration

No official Anthropic SDK for Swift, so `ClaudeClient` talks raw HTTP to
`POST /v1/messages` via `URLSession`.

- **Model**: chosen per task in Settings (see below). Thinking is on by default
  on these models, so no `thinking` block is sent; `output_config.effort`
  (`low` for extraction) is the dial that keeps calls quick and cheap.
- **Structured outputs**: every call uses `output_config.format` with a JSON
  Schema, so replies decode straight into Swift types instead of being scraped
  out of prose. Schemas are built with the small `Schema` helpers in
  `JSONValue.swift` and are unit-tested for encoding.
- **Error handling**: typed `ClaudeError`; retries with jittered exponential
  backoff on 429/5xx (honouring `retry-after`); no retry on 4xx.
  `stop_reason: "refusal"` is checked *before* reading content — Opus 5 ships
  elevated safety classifiers, and a decline arrives as a successful HTTP 200.
  `max_tokens` truncation is surfaced rather than silently returning half a
  recipe.
- **Images**: downsized to 1568px long edge before sending. Opus 5 accepts up to
  2576px, but groceries are big obvious objects — this costs roughly a third as
  many image tokens for no practical accuracy loss.

### One model per task

The four jobs aren't the same difficulty, so each picks its own model in
Settings. Defaults, with the reasoning shown in-app next to each choice:

| Task | Default | Why |
|---|---|---|
| Estimating shelf life | **Haiku 4.5** | A short factual answer with one number in it. The one task where paying more changes almost nothing — and the rules table already handles common items with no API call at all. |
| Reading photos | **Sonnet 5** | Vision work, but groceries are obvious objects and you check every result before it saves. |
| Parsing pasted recipes | **Sonnet 5** | Pasted recipes are usually already structured; mostly reformatting, with small judgement calls on splitting quantity from prep note. |
| Extracting reel recipes | **Opus 5** | Much the hardest. Captions are emoji, hashtags, and engagement bait; ingredients are implied; the method is often missing entirely. The model has to infer structure *and* be honest about what wasn't there instead of inventing a method. |

Each is overridable to any of the three, and the estimated per-use cost is shown
against each option. Settings also keeps a rough running spend total, priced at
whichever model actually ran.

### Nothing AI-generated is saved without review

Photo add and both recipe importers end at an editable confirm screen. The photo
flow lets you fix names, quantities, units, categories, and dates, and untick
anything you don't want. Both recipe importers funnel into `RecipeEditorView` in
`.confirm` mode — the same editor used for writing a recipe by hand. Claude also
returns a confidence level and a `missing_information` note, which the confirm
screen surfaces as a banner.

## Instagram import — read this bit

**This is the fragile part of the app.** Instagram has no supported API for
reading a public reel, so `InstagramFetcher` tries three unofficial routes in
order and falls back to asking you to paste the caption:

1. **oEmbed** (`/api/v1/oembed/`) — unauthenticated, returns the caption,
   author, and a thumbnail URL. Verified working against public posts at the
   time of writing. This is the good path.
2. **Embed page** (`/reel/{code}/embed/captioned/`) — scrapes the caption out of
   the embedded JSON.
3. **`og:description`** on the canonical page — usually truncated, better than
   nothing.
4. **Manual paste** — always available, and offered automatically when the other
   three fail.

Known limitations, in rough order of how often they'll bite:

- **Only the caption and cover frame are available.** If the recipe is *spoken*
  in the video, or shown as on-screen text mid-video, it won't come through. The
  extractor is told to say so via `missing_information` rather than inventing a
  method, and the confirm screen shows that warning. Transcribing the audio would
  need the video file, which means signed CDN URLs that aren't exposed here —
  deliberately out of scope.
- **The oEmbed endpoint is undocumented.** It works today; Meta can gate or
  remove it whenever they like. That's exactly why the manual-paste path exists
  and isn't hidden away.
- **Private, deleted, and age-restricted reels return nothing.**
- **Rate limiting.** Datacenter IPs get throttled; a phone on a home connection
  is much less likely to hit this, but it's not impossible.

If Instagram ever locks this down completely, the app degrades to "paste the
caption in" — which still works fine, because the Claude extraction step is
independent of how the text was obtained.

## Notifications

Local notifications only — no server, no push certificates. Scheduled on-device
against each item's expiry date, with configurable lead time (default 2 days at
9am). Items expiring on the same day are grouped into one notification so a big
shop doesn't produce a wall of alerts. Capped at 48 pending, under iOS's 64
limit. The in-app "use soon" list works regardless of notification permission.

## Layout

```
Pantry/
├── Models/          SwiftData models + expiry/unit/category value types
├── Services/
│   ├── Claude/      HTTP client, wire types, JSON Schema builders, key storage,
│   │                per-task model preferences
│   ├── IngredientMatcher.swift    name matching
│   ├── RecipeRanker.swift         expiry-weighted ranking
│   ├── ShelfLifeRules.swift       offline shelf-life table
│   ├── ShelfLifeEstimator.swift   rules → cache → Claude
│   ├── InstagramFetcher.swift     reel scraping, with fallbacks
│   └── ...
├── Views/           one folder per tab, plus shared components
└── Support/         image downsizing
PantryTests/         matcher, ranker, shelf-life, expiry, schema encoding,
                     model preferences
```

## Known rough edges

- Ingredient matching is heuristic. It errs toward matching, since the cost of a
  wrong match (an item on the shopping list you didn't need) is lower than a
  missed one (buying a second jar of something).
- Quantities aren't reconciled — the app knows you have *flour*, not whether you
  have *enough* flour.
- The API key sits on the device. Fine for a single-user app on your own phone;
  it's the reason this isn't something to hand to anyone else.
