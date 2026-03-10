# mq-experts-v2

Utility Expert Advisors for MetaTrader 5, built to manage positions around spread widening and news events.

---

## Expert Advisors

| EA | Description |
|----|-------------|
| [SpreadHourDodger](SpreadHourDodger.md) | Removes stop losses during spread hour to prevent false SL hits from widened spreads |
| [NewsDodger](NewsDodger.md) | Closes open positions at a specified time before high-impact news events |

---

## Project Structure

```
v2/
├── bin/          # Compiled .ex5 binaries
├── src/               # Source code
│   ├── Include/       # Shared utilities
│   ├── SpreadHourDodger.mq5
│   └── NewsDodger.mq5
├── SpreadHourDodger.md
├── NewsDodger.md
└── README.md
```

---

## Disclaimer

These Expert Advisors are provided for **research and development purposes only**.
They are not financial advice and come with no guarantees of performance or reliability.
Use entirely at your own risk. The author accepts no responsibility for any financial
losses incurred through the use of these tools. Always test thoroughly on a demo
account before considering any live deployment.
