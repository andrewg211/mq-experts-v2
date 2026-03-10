//+------------------------------------------------------------------+
//|                                             SpreadHourDodger.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//
//  WARNING: This EA does NOT handle partial closes during spread hour.
//  In MT5, a partial close destroys the original ticket and creates a
//  new one. If a position is partially closed (by you or another EA)
//  while its SL is removed, the remaining portion will NOT have its
//  SL restored automatically. You must manage that manually.
//
//  WARNING: If the EA is restarted or crashes during spread hour,
//  stored SL data is lost (memory only). Affected positions will
//  remain without a stop loss until manually corrected.
//
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.01"

#include <Trade\Trade.mqh>
#include "Include\CommonUtils.mqh"

//--- input parameters
input string          SpreadHourStart   = "23:59";   // Spread hour start time (HH:MM)
input string          SpreadHourEndTime = "01:01";   // Spread hour end time (HH:MM)
input ENUM_SCOPE_MODE Scope             = Current;   // Scope
input bool            Enable            = false;     // Enable EA

//--- stored SL data
struct SLRecord
  {
   ulong             ticket;
   double            originalSL;
  };

SLRecord          g_records[];
bool              g_inSpreadHour    = false;
bool              g_slsRemoved      = false;
int               g_startMinutes    = 0;
int               g_endMinutes      = 0;
CTrade            g_trade;

//+------------------------------------------------------------------+
//| Find record index by ticket, -1 if not found                    |
//+------------------------------------------------------------------+
int FindRecord(ulong ticket)
  {
   for(int i = 0; i < ArraySize(g_records); i++)
      if(g_records[i].ticket == ticket)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Store SL and remove it from a single position                    |
//+------------------------------------------------------------------+
void StoreAndRemoveSL(ulong ticket)
  {
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;
   if(!SymbolMatchesScope(Scope, PositionGetString(POSITION_SYMBOL), _Symbol)) return;
   if(FindRecord(ticket) >= 0) return;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl == 0.0) return; // no SL to remove

   double tp  = PositionGetDouble(POSITION_TP);
   string sym = PositionGetString(POSITION_SYMBOL);

   if(g_trade.PositionModify(ticket, 0.0, tp))
     {
      int idx = ArraySize(g_records);
      ArrayResize(g_records, idx + 1);
      g_records[idx].ticket     = ticket;
      g_records[idx].originalSL = sl;
      Print("[SpreadHourDodger] Removed SL for position #", ticket, " (", sym, ") | Original SL: ", sl);
     }
   else
      Print("[SpreadHourDodger] FAILED to remove SL for position #", ticket,
            " | Retcode: ", g_trade.ResultRetcode(),
            " | ", g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Remove stop losses from all open positions                       |
//+------------------------------------------------------------------+
void StoreAndRemoveAllSLs()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      StoreAndRemoveSL(ticket);
     }
  }

//+------------------------------------------------------------------+
//| Spread hour ended - restore SLs or close breached positions      |
//+------------------------------------------------------------------+
void RestoreOrClose()
  {
   for(int i = ArraySize(g_records) - 1; i >= 0; i--)
     {
      SLRecord rec = g_records[i];

      if(PositionSelectByTicket(rec.ticket))
        {
         string sym  = PositionGetString(POSITION_SYMBOL);
         long   type = PositionGetInteger(POSITION_TYPE);
         double tp   = PositionGetDouble(POSITION_TP);
         double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask  = SymbolInfoDouble(sym, SYMBOL_ASK);

         // Price went past where the SL was - close the position
         bool shouldClose = false;
         if(type == POSITION_TYPE_BUY && bid <= rec.originalSL)
            shouldClose = true;
         if(type == POSITION_TYPE_SELL && ask >= rec.originalSL)
            shouldClose = true;

         if(shouldClose)
           {
            if(g_trade.PositionClose(rec.ticket))
               Print("[SpreadHourDodger] Closed position #", rec.ticket, " (", sym, ") | Price breached SL: ", rec.originalSL);
            else
               Print("[SpreadHourDodger] FAILED to close position #", rec.ticket,
                     " | Retcode: ", g_trade.ResultRetcode(),
                     " | ", g_trade.ResultRetcodeDescription());
           }
         // Price is fine - put the SL back
         else
           {
            if(g_trade.PositionModify(rec.ticket, rec.originalSL, tp))
               Print("[SpreadHourDodger] Restored SL for position #", rec.ticket, " (", sym, ") | SL: ", rec.originalSL);
            else
               Print("[SpreadHourDodger] FAILED to restore SL for position #", rec.ticket,
                     " | Retcode: ", g_trade.ResultRetcode(),
                     " | ", g_trade.ResultRetcodeDescription());
           }
        }
      else
         Print("[SpreadHourDodger] Position #", rec.ticket, " no longer exists, skipping.");
     }

   // Clear all tracked records
   ArrayResize(g_records, 0);
  }

//+------------------------------------------------------------------+
//| Update chart display                                             |
//+------------------------------------------------------------------+
void UpdateDisplay()
  {
   string line1, line2, line3;

   if(!Enable)
     {
      line1 = "SpreadHourDodger: INACTIVE";
      line2 = "Enable is OFF";
      line3 = "";
     }
   else if(g_inSpreadHour && g_slsRemoved)
     {
      int secs = SecondsUntil(g_endMinutes);
      line1 = "SpreadHourDodger: ACTIVE";
      line2 = "SPREAD HOUR - SLs REMOVED (" + IntegerToString(ArraySize(g_records)) + " tracked)";
      line3 = "Ends in: " + FormatCountdown(secs);
     }
   else
     {
      int secs = SecondsUntil(g_startMinutes);
      line1 = "SpreadHourDodger: ACTIVE";
      line2 = "Monitoring";
      line3 = "Spread hour in: " + FormatCountdown(secs);
     }

   Comment(line1 + "\n" + line2 + "\n" + line3);
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Parse time inputs
   g_startMinutes = TimeStringToMinutes(SpreadHourStart);
   g_endMinutes   = TimeStringToMinutes(SpreadHourEndTime);
   g_inSpreadHour = false;
   g_slsRemoved   = false;
   ArrayResize(g_records, 0);

   Print("[SpreadHourDodger] Initialized | Start: ", SpreadHourStart,
         " | End: ", SpreadHourEndTime,
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
//| Catch new positions opened during spread hour                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // Only care about deal additions (position opened/filled)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   // Only act during spread hour with SLs removed
   if(!g_slsRemoved)
      return;

   // A deal was added - check if it created/added to a position
   ulong posTicket = trans.position;
   if(posTicket == 0)
      return;

   // Small delay to let the position fully register
   Sleep(100);

   StoreAndRemoveSL(posTicket);
  }

//+------------------------------------------------------------------+
//| Core logic                                                       |
//+------------------------------------------------------------------+
void ProcessLogic()
  {
   // EA disabled - restore SLs if they were removed, then do nothing
   if(!Enable)
     {
      if(g_slsRemoved)
        {
         Print("[SpreadHourDodger] EA disabled during spread hour, restoring SLs.");
         RestoreOrClose();
         g_slsRemoved   = false;
         g_inSpreadHour = false;
        }
      UpdateDisplay();
      return;
     }

   int nowMin = CurrentMinutes();
   bool inWindow = IsInTimeWindow(nowMin, g_startMinutes, g_endMinutes);

   if(inWindow)
     {
      // Spread hour just started - remove all stop losses
      if(!g_inSpreadHour)
        {
         g_inSpreadHour = true;
         g_slsRemoved   = true;
         Print("[SpreadHourDodger] Spread hour started. Removing SLs...");
         StoreAndRemoveAllSLs();
        }
     }
   else
     {
      // Spread hour just ended - restore stops or close breached positions
      if(g_slsRemoved)
        {
         Print("[SpreadHourDodger] Spread hour ended. Restoring SLs / closing breached positions...");
         RestoreOrClose();
         g_slsRemoved = false;
        }
      g_inSpreadHour = false;
     }

   UpdateDisplay();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   ProcessLogic();
  }
//+------------------------------------------------------------------+
