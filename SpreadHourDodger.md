# SpreadHourDodger

This EA protects positions from false stop-loss hits caused by spreads
widening during "spread hour" (typically the midnight rollover, when the
ask jumps up and/or the bid drops). It offers two modes, chosen with the
`Mode` input.

- **Remove SL (simple)** — strips the stop loss off entirely for the
  duration of spread hour, then restores it when the window ends.
- **Pad SL (advanced)** — leaves the stop loss in place but pushes it
  further from price by the pair's recorded max spread, then restores the
  original when the window ends. The stop is never removed.

In both modes, `OnTradeTransaction` catches any new position opened during
spread hour and applies the same treatment to it. When spread hour ends,
if price has moved past where the original SL was, the EA closes the
position at market rather than restoring the SL onto the wrong side.

> **WARNING:** Do not change EA settings during spread hour. Changing
> settings restarts the EA, which clears all stored SL data from memory.
> Any position whose SL was removed or widened will not have its original
> SL restored.

> **WARNING:** This EA does **not** handle partial closes during spread
> hour. In MT5 a partial close destroys the original ticket and creates a
> new one. If a position is partially closed (by you or another EA) while
> its SL is modified, the remaining portion will **not** have its original
> SL restored automatically — you must fix it manually.

## Which mode should I use?

Remove SL is simpler but dangerous: if the EA is stopped or crashes while
SLs are removed, those positions are left completely naked until you
intervene. Pad SL is the safer default — a crash leaves a *widened* stop,
not no stop at all. Pad SL is recommended for anything you can't babysit.

## Inputs

### Top level

- **Mode**: `RemoveSL` (simple) or `PadSL` (advanced).

### Timing & On/Off

- **SpreadHourStart**: Spread hour start time (HH:MM, server time).
- **SpreadHourEndTime**: Spread hour end time (HH:MM, server time).
- **Enable**: On/off toggle.

### Simple Mode (Remove SL)

- **Scope**: Current symbol only, or all symbols. *Only used in RemoveSL
  mode — ignored in PadSL mode.*

### Advanced Mode (Pad SL)

- **PairsList**: Comma-separated list of symbols to manage (typically ~25
  FX pairs). This is the authority in PadSL mode: a symbol **not** in this
  list is ignored completely, regardless of `Scope`.
- **SpreadFile**: CSV history filename, stored in the terminal's
  `MQL5\Files\` folder.
- **FileMode**: `ReadWrite` (read the history and append each session's
  observed max) or `ReadOnly` (read the history to size the pads, but never
  write — and skip the per-tick spread sampling entirely, so there is no
  ongoing cost. Use this when you curate the spread values by hand).
- **Multiplier**: Multiplies the recorded max spread when sizing the SL
  move. `0.5` assumes spread widens roughly half on each side, `1.0` uses
  the full recorded spread, `1.2` pads cautiously.
- **Failover**: What to do when a listed pair has **no history yet** in the
  CSV (in points):
  - `<= 0` — do nothing, leave the SL as-is (default `0`).
  - `> 0` — treat this number as the minimum required distance and pad to
    it. The multiplier is **not** applied to the failover value.

## How Pad SL works

At the **start** of spread hour, for each open position on a listed pair:

1. The EA reads the whole CSV and takes the **largest** `max_spread` ever
   recorded for that pair.
2. `required = recorded_max × Multiplier` (in points). If the pair has no
   history, the `Failover` rule above applies instead.
3. It measures the current distance from price to the SL, on the side that
   can trigger it (bid for buys, ask for sells).
4. It moves the SL outward by `max(0, required − current_distance)`. If the
   SL is already at least `required` points away, it is left unchanged.

**Example:** SL is 20 points from price, recorded max spread is 30,
multiplier is 1.0 → required is 30 → the SL is pushed out by 10 points.

In `ReadWrite` mode the EA samples each listed pair's live spread on every
tick throughout spread hour and keeps the running maximum in memory (cheap
— no per-tick disk writes). At the **end** of spread hour it appends one row
per pair to the CSV and restores the original stops. In `ReadOnly` mode this
sampling is skipped — the CSV is only read once at the start to size the
pads, and the original stops are still restored at the end.

## The spread history CSV

Append-only; each session adds one row per pair so you keep a full record
for tracing and analysis. A calm day never lowers the stored protection,
because padding always uses the largest value across all rows.

```
date,pair,max_spread
2026-07-19,EURUSD,34
2026-07-20,EURUSD,28
```

On first run (or for a pair you've just added) there is no history, so the
`Failover` rule decides what happens until enough sessions have been logged.

## Limit Orders

During spread hour, spreads widen — typically with ask moving up and/or
bid moving down.

A buy limit fills when ask falls to or below your limit price. During
spread hour, ask goes up, making it unlikely to fill. If it does fill,
your SL sits below the entry and is triggered by bid. While bid may dip
during spread widening, the distance between the entry price and SL
makes it very unlikely that bid will reach the SL before
OnTradeTransaction handles it.

Vice versa for sell limits: a sell limit fills when bid rises to or above
your limit price. During spread hour, bid drops, making it unlikely to
fill. If it does fill, your SL sits above the entry and is triggered by
ask. While ask may spike during spread widening, the distance between
the entry price and SL makes it very unlikely that ask will reach the SL
before OnTradeTransaction handles it.

## Stop Orders - NOT RECOMMENDED

A buy stop fills when ask rises to your stop price. During spread hour,
ask spikes up. Your buy stop is
likely to get filled at a bad price due to the inflated ask. This is a
fill quality problem the EA cannot protect against. You are likely to
enter a position at an artificially high price.

Vice versa for sell stops: a sell stop fills when bid drops to your stop
price. Bid often drops during spread widening, making a false fill
likely. Your sell stop is likely to get filled at a bad price due to the
deflated bid. Additionally, once filled, the sell's SL is
triggered by ask, which is the inflated side during spread hour —
creating risk of the SL being hit in the split second before
OnTradeTransaction handles it.

**Recommendation:** Do not use stop orders on symbols affected by spread
hour widening. Use limit orders instead where possible.
