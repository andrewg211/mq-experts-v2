//+------------------------------------------------------------------+
//|                                                   NewsDodger.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//
//  NOTE: Time matching uses exact minute comparison (==). This assumes
//  the symbol receives at least one tick per minute, which is expected
//  for forex pairs. If attached to a low-liquidity symbol, the EA may
//  miss the target minute entirely.
//
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include "Include\CommonUtils.mqh"

//--- input parameters
input string          CloseOrdersTime = "14:30";    // Close orders time (HH:MM)
input ENUM_SCOPE_MODE Scope           = Current;    // Scope
input bool            Enable          = false;      // Enable EA

//--- state
bool   g_fired         = false;
int    g_targetMinutes = 0;
CTrade g_trade;

//+------------------------------------------------------------------+
//| Close all matching open positions                                |
//+------------------------------------------------------------------+
void ClosePositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      if(!SymbolMatchesScope(Scope, sym, _Symbol)) continue;

      if(g_trade.PositionClose(ticket))
         Print("[NewsDodger] Closed position #", ticket, " (", sym, ")");
      else
         Print("[NewsDodger] FAILED to close position #", ticket, " (", sym, ") | Error: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| Update chart display                                             |
//+------------------------------------------------------------------+
void UpdateDisplay()
  {
   string line1, line2;

   if(!Enable)
     {
      line1 = "NewsDodger: INACTIVE";
      line2 = "Enable is OFF";
     }
   else if(g_fired)
     {
      line1 = "NewsDodger: ACTIVE";
      line2 = "Done - positions closed";
     }
   else
     {
      int secs = SecondsUntil(g_targetMinutes);
      line1 = "NewsDodger: ACTIVE";
      line2 = "Closing in: " + FormatCountdown(secs);
     }

   Comment(line1 + "\n" + line2);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_targetMinutes = TimeStringToMinutes(CloseOrdersTime);
   g_fired = false;

   Print("[NewsDodger] Initialized | CloseOrdersTime: ", CloseOrdersTime,
         " | Scope: ", EnumToString(Scope),
         " | Enabled: ", Enable);

   UpdateDisplay();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(!Enable)
     {
      UpdateDisplay();
      return;
     }

   // Is it time? Close positions.
   if(!g_fired && CurrentMinutes() == g_targetMinutes)
     {
      Print("[NewsDodger] CloseOrdersTime reached (", CloseOrdersTime, "). Closing positions...");
      ClosePositions();
      g_fired = true;
     }
   UpdateDisplay();
  }
//+------------------------------------------------------------------+
