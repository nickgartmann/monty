# Monty

**A visual spreadsheet for uncertainty, built as one Phoenix LiveView application.**

Monty rebuilds the core modeling workflow of
[guesstimate-app](https://github.com/getguesstimate/guesstimate-app) and
[guesstimate-server](https://github.com/getguesstimate/guesstimate-server).
There is no separate React application, Rails API, Auth0/NextAuth integration,
or Algolia account. LiveView owns the UI; Elixir owns simulation and
authorization; SQLite stores accounts and models and provides FTS5 search.

## Run locally

Requires Elixir 1.17+ and a compatible Erlang/OTP installation.

```sh
mix setup
mix phx.server
```

Open [localhost:4000](http://localhost:4000). `PORT=4100 mix phx.server` uses
another port. No database service, Node development server, or service keys
are needed. `mix setup` creates the SQLite database, migrates it, builds the
assets, and seeds three original public examples. Seeds are idempotent and
never reset existing models.

Try `/try` without an account. Sandbox changes are held in the LiveView
session and are lost on reload unless you export or save a private copy.

### Accounts

Authentication was generated using:

```sh
mix phx.gen.auth Accounts User users --live
```

Register with an email address, open the confirmation message in
[/dev/mailbox](http://localhost:4000/dev/mailbox), and confirm the link.
Login supports one-time email links. After confirming an account, set an
optional password in account settings. Password hashing, signed sessions,
remember-me cookies, email-change confirmation, and sensitive-action
reauthentication use the generated Phoenix code.

## Modeling

- Model details and controls live in a stationary card at the canvas's upper-right.
  Use its chevron to collapse it to the model title or expand it again. The card
  stays in place while panning; settings scroll inside it.
- Add, Undo, and Guide are icon buttons beside the card and stay available when it is
  collapsed. Guide opens a separate modal without changing the card's state.
- Add, rename, drag, or keyboard-position metric cards.
- Click a card's name or formula to edit it in place; results update as you type.
- For valid ranges, choose normal, lognormal, or uniform from the compact
  dropdown beside the formula. Range cards show the selected distribution's icon.
- Hover the note icon beside a card's reference to read its assumptions;
  click it to edit the note in a modal.
- Preview correlated Monte Carlo histograms, means, and 5th/95th percentiles.
- Save models, undo the last 20 metric edits in the current session, and
  reopen saved assumptions. Cmd+Z or Ctrl+Z triggers model undo when not editing
  a text field or using a modal.
- Duplicate readable models into your own private workspace.
- Export and import versioned Monty JSON (up to 2.5 MB / 100 metrics).
- Explore public models with SQLite full-text prefix search over titles
  and descriptions; search your own library separately.

### Canvas movement

Cards snap to the background dots in **20px increments** on both axes.
Compact cards are 240 × 120px, with a small histogram and the estimate/formula
still visible, including when selected. New presets and added
cards use spacing based on these dimensions; existing model positions are not rearranged.
Double-click empty canvas space to add a metric centered at that point, snapped
to the dot grid. The new card is selected for editing. Double-clicking an existing
card does not add another, and shared read-only models cannot create cards.
Drag from a card's displayed value, histogram, or padding: it follows the pointer
without a browser ghost, while a subtle shadow previews the snapped drop position. Releasing
preserves your grab offset and snaps to the nearest dot; Escape cancels a drag.
Arrow keys on a focused card move one dot at a time;
Shift + arrow moves five dots. Mouse, pen, and touch use the same interaction.
Inputs, dropdowns, and note controls retain their own pointer and keyboard behavior.
The background scrolls with the cards, and dependency lines follow the cards
while moving. A shadow turns red if its origin is already occupied.

Saved coordinates are fine-grid indices, not card-sized cells. New exports use
Monty format v2; v1 imports convert older layouts to the nearest dot. Run
`mix ecto.migrate` when upgrading an existing database to convert its saved
positions and invalidate stale editor saves. The layout migration is one-way:
back up the database before applying it if you need to return to the old canvas.

#### Canvas diagnostics

After loading the current assets, enable local tracing in the browser console:

```js
window.montyCanvasDebug.enable()
```

Filter the console by `[monty:canvas]`. Events include gesture decisions and
cancellation reasons, pointer capture, drop/acknowledgement, camera coordinates,
LiveView disconnect/reconnect/patch, and page lifecycle. Entries are snapshots,
not live references. Raw pointer-move samples are optional because logging them
can affect timing:

```js
window.montyCanvasDebug.enable({moves: true})
```

Tracing is off by default. The opt-in and last 500 entries survive reloads in
the same tab using session storage, when available. The trace contains no model
content, form values, model IDs, URLs, or authentication/session payloads, and
is not sent to a server. In Chrome DevTools, copy the retained sequence with:

```js
copy(JSON.stringify(window.montyCanvasDebug.events(), null, 2))
```

Use `window.montyCanvasDebug.clear()` before a reproduction, `.dump()` to view the
buffer, and `.disable()` when finished. Disabling stops recording; clearing
removes the retained entries.

### Estimate syntax

| Input | Interpretation |
| --- | --- |
| `42`, `1,000`, `1e3` | Point estimate |
| `5%` | `0.05` |
| `10 to 20` + Normal | 90% confidence interval (not hard bounds) |
| `10 to 20` + Lognormal | Positive, skewed 90% interval |
| `10 to 20` + Uniform | Full lower and upper bounds |
| `=A * B` | Multiply the sampled values of two metrics |
| `=max(A - B, 0)` | A safe, allowlisted function |
| `=normal(100, 15)` | Normal draw with mean 100 and standard deviation 15 |
| `=lognormal(0, 1)` | Lognormal draw with log-space mean 0 and standard deviation 1 |
| `=uniform(10, 20)` | Uniform draw between hard bounds |
| `=pert(10, 15, 30)` | Beta-PERT draw with minimum 10, mode 15, and maximum 30 |
| `=normal(A, B) + C` | Distribution parameters and arithmetic using sampled metrics |

Formulas support `+ - * / ^`, parentheses, and `min`, `max`, `abs`,
`sqrt`, `log`, `exp`, `sum`, `mean`, `sin`, `cos`, `tan`, `floor`, `ceil`,
and `round`. Normal and lognormal calls require a non-negative standard
deviation; zero produces a point value. Uniform requires lower < upper.
PERT takes exactly three parameters: minimum, most likely value (mode), and
maximum. It uses standard beta-PERT with fixed weighting 4, stays within
the entered bounds, and has theoretical mean `(minimum + 4 * mode + maximum) / 6`.
Minimum must be less than maximum; the mode can be anywhere between them,
including either endpoint. Parameters can reference cards (`=pert(A, B, C)`)
or contain arithmetic.
The range selector affects only `lower to upper` inputs, not formula calls.
Metric letter references are
permanent even when names change. A formula referencing a deleted metric
shows an error; new cards do not take a key that is still referenced.
Cycles, unknown references, invalid distributions, and numeric errors are
shown on the affected cards. [Abacus](https://github.com/narrowtux/abacus)
compiles formulas once per run. Monty translates the result to a bounded,
allowlisted numeric expression tree; it never executes the generated Elixir
code. Scripts, collections, property access, and arbitrary function calls
are not supported. Existing commas, scientific notation, percentages, and
unary signs retain their meaning.
Put spaces after argument-separating commas to distinguish them from
thousands separators: `=pert(0, 100, 200)` versus the number `100,200`.

The editor computes 1,000 correlated draws using a fixed seed, so comparing
edits is stable. Repeated references use the same sampled value within each
draw (`=A - A` is always zero), including when A is defined by a distribution
call. Separate calls inside a formula make independent draws, so
`=normal(0, 1) - normal(0, 1)` is not always zero. Formula draws use the same
explicit seeded RNG as ranges, without changing the caller's random state.
Normal draws can fall outside the entered
90% interval, including below zero. These simulations are approximate
decision aids, not guarantees.

Edits preview immediately, but are persisted only with **Save model** or
by pressing Enter in the inline name/formula editor. Applying a note updates
the draft; save the model to persist it. The status indicator shows unsaved changes.
Saving is owner-only and checks `lock_version`; stale sessions cannot
silently overwrite another save. If a conflict occurs, export your draft
before reloading.

### Visibility

- **Private** (default): readable and editable only by the owner.
- **Unlisted**: readable by anyone with the model URL, but absent from
  public discovery. An unlisted URL is **not** a revocable secret token.
- **Public**: readable by everyone and searchable in Explore.

Only owners can save or delete models, regardless of visibility. Copies
and imports are always private. Account emails are not published on
discovery cards.

## Implementation map

- `Monty.Accounts`, `Monty.Accounts.Scope`, `MontyWeb.UserAuth`: generated auth.
- `Monty.Models`: scope-based model persistence and access rules.
- `Monty.Models.Model`: model and bounded metric-map validation.
- `Monty.Canvas`: shared dot-grid spacing, bounds, card dimensions, and layout conversion.
- `Monty.Simulation.Parser`: Abacus-backed formula parsing and numeric AST allowlisting.
- `Monty.Simulation`: dependency resolution, seeded distribution draws, and Monte Carlo computation.
- `MontyWeb.ModelLive`: canvas, editor, simulation display, and save workflow.
- `MontyWeb.ModelLibraryLive`: streamed catalog and library search.
- `Monty.ModelFile`, `MontyWeb.ModelImportLive`: versioned JSON round-tripping.
- `priv/repo/migrations`: auth schema, models, FTS5 table and sync triggers.

Public LiveViews are in the generated `:current_user` session with
`:mount_current_scope`; creation, import, library, and account settings use
`:require_authenticated_user`. Context functions recheck persisted
ownership on every write; hiding buttons is not the authorization boundary.
Metrics are stored as validated JSON maps in their model, while samples are
derived in memory rather than persisted.

## Verification

```sh
mix precommit
mix assets.build
```

Client-side snapping tests use Node's built-in runner, without npm dependencies:

```sh
node --test assets/js/*.test.mjs
```

Tests cover generated accounts, ownership/visibility, FTS synchronization,
malicious search input, simulation semantics and errors, editor interactions,
stale saves, and JSON round-tripping.

## Deployment and remaining scope

This is a working core rebuild, **not complete feature parity or a drop-in
legacy replacement**. Organization memberships and reusable facts, tokenized
private sharing, checkpoint history, multi-user live collaboration, sensitivity
analysis, empirical-data/general beta distributions, billing, and migration of existing
Guesstimate databases are not implemented. Monty imports its own versioned
exports, not legacy graph JSON or arbitrary Math.js expressions.

Before deploying:

1. Set `DATABASE_PATH` to a persistent writable SQLite file, and configure
   backups (including SQLite WAL considerations).
2. Set `SECRET_KEY_BASE`, `PHX_HOST=monty.sufficient.software`, and
   `PHX_SERVER=true` (the release `bin/server` script sets the latter). Terminate
   HTTPS at the proxy and forward `X-Forwarded-Proto: https`; production already
   uses this header for SSL redirects and HSTS. Only trusted proxies should be
   able to reach the application port.
3. Set `POSTMARK_API_KEY` to your Postmark **server API token** (on Fly, use a
   Fly secret). Production sends email through Postmark using `Swoosh.ApiClient.Req`
   and requires this secret at startup. Verify `nick@sufficient.software` or the
   `sufficient.software` domain in Postmark; emails come from
   `Monty <nick@sufficient.software>`. Development still uses `/dev/mailbox`, and
   tests use Swoosh's test adapter. Keep credentials out of version control.
4. Add signup/login/email rate limiting and operational monitoring before
   exposing authentication to the public internet.
5. Run migrations and `mix assets.deploy`; keep SQLite on a single writable
   application host or explicitly design a replication strategy.

### Custom domain on Fly.io

`fly.toml` keeps the Fly app name `montie`, but sets the public host to
`monty.sufficient.software`. Production defaults to this domain even outside Fly.
Generated URLs use HTTPS on port 443. LiveView WebSocket and long-poll origin
checks allow only `https://monty.sufficient.software`; HTTP origins, other ports,
subdomains, and `https://montie.fly.dev` are intentionally not allowed. Overriding
`PHX_HOST` changes both the public URL and the allowed HTTPS origin together.
Use a bare hostname, without a scheme, port, or path. Development is unchanged.

Before switching traffic:

1. Add a Fly certificate with `fly certs add monty.sufficient.software -a montie`.
2. Create the DNS records Fly specifies, and verify certificate readiness with
   `fly certs check monty.sufficient.software -a montie`.
3. Deploy with `fly deploy`, ensuring no existing `PHX_HOST` secret overrides
   the value in `fly.toml`.
4. Open `https://monty.sufficient.software/try` and confirm the LiveView WebSocket
   connects and editing works without origin-check errors. Use the custom domain,
   not the old Fly hostname, for application links.

The upstream repositories report MIT licenses. This implementation uses
original code, examples, and visuals rather than copying their source or
branding. Any future upstream code/assets imported here must preserve the
applicable license notices.

See the [Phoenix deployment guide](https://phoenix.hexdocs.pm/deployment.html).
