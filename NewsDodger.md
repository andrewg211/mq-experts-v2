# NewsDodger

This EA closes all open positions at a specified time, intended for use
before high-impact news events. It fires once at the target minute, then
stops until the EA is restarted or settings are changed.

## Inputs

- **CloseOrdersTime**: Time to close positions (HH:MM, server time)
- **Scope**: Current symbol only, or all symbols
- **Enable**: On/off toggle

## Behaviour

- At the target minute, all matching open positions are closed at market
- The EA only fires once per session. To reuse, change settings or
  restart the EA
- Uses exact minute comparison, so the symbol must receive at least one
  tick during that minute. This is expected for forex pairs but may be
  unreliable on low-liquidity symbols
- Pending orders are not affected — only open positions are closed
