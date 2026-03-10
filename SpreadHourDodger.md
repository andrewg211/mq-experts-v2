# SpreadHourDodger

This EA removes stop losses during spread hour to prevent false SL hits
caused by widened spreads (typically around midnight rollover). It uses
OnTradeTransaction to catch any new positions opened during spread hour
and immediately removes their SL too. When spread hour ends, if price
has moved past where the SL was, the EA closes the position at market
price rather than restoring the SL.

> **WARNING:** Do not change EA settings during spread hour. Changing settings
> restarts the EA, which clears all stored SL data from memory. Any
> positions with removed stop losses will not have them restored.

## Inputs

- **SpreadHourStart**: Spread hour start time (HH:MM, server time)
- **SpreadHourEndTime**: Spread hour end time (HH:MM, server time)
- **Scope**: Current symbol only, or all symbols
- **Enable**: On/off toggle

## Limit Orders

A buy limit fills when ask DROPS to your limit price. During spread hour,
ask goes UP (spread widens), making it unlikely to fill. If it does fill,
your SL sits below price and is triggered by bid. Bid is not the side
inflated by spread widening, so it is unlikely to hit your SL in the
split second before OnTradeTransaction removes it.

Vice versa for sell limits: a sell limit fills when bid RISES to your
limit price. During spread hour, bid stays flat or drops, making it
unlikely to fill. If it does fill, your SL sits above price and is
triggered by ask. While ask is the inflated side, the fill itself is
unlikely, and OnTradeTransaction catches it near-instantly.

## Stop Orders - NOT RECOMMENDED

A buy stop fills when ask RISES to your stop price. During spread hour,
ask spikes up — this is exactly the side that widens. Your buy stop is
likely to get filled at a bad price due to the inflated ask. This is a
fill quality problem the EA cannot protect against. You are likely to
enter a position at an artificially high price.

Vice versa for sell stops: a sell stop fills when bid DROPS to your stop
price. If bid drops during spread hour, you are likely to get filled at
an artificially low price. Additionally, once filled, the sell's SL is
triggered by ask, which IS the inflated side during spread hour —
creating risk of the SL being hit in the split second before
OnTradeTransaction removes it.

**Recommendation:** Do not use stop orders on symbols affected by spread
hour widening. Use limit orders instead where possible.
