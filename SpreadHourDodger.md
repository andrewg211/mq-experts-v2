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

During spread hour, spreads widen — typically with ask moving up and/or
bid moving down.

A buy limit fills when ask falls to or below your limit price. During
spread hour, ask goes up, making it unlikely to fill. If it does fill,
your SL sits below the entry and is triggered by bid. While bid may dip
during spread widening, the distance between the entry price and SL
makes it very unlikely that bid will reach the SL before
OnTradeTransaction removes it.

Vice versa for sell limits: a sell limit fills when bid rises to or above
your limit price. During spread hour, bid drops, making it unlikely to
fill. If it does fill, your SL sits above the entry and is triggered by
ask. While ask may spike during spread widening, the distance between
the entry price and SL makes it very unlikely that ask will reach the SL
before OnTradeTransaction removes it.

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
OnTradeTransaction removes it.

**Recommendation:** Do not use stop orders on symbols affected by spread
hour widening. Use limit orders instead where possible.
