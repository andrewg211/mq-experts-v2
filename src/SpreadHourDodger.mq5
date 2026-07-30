//+------------------------------------------------------------------+
//|                                             SpreadHourDodger.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
//
//  Two modes of protection against false SL hits during spread hour:
//
//   RemoveSL (simple) - strips the SL off entirely for the duration of
//              spread hour, then restores it (or closes if price breached
//              the original SL). Simple but dangerous: if the EA dies
//              while SLs are removed, positions are left naked.
//
//   PadSL (advanced) - safer. Leaves the SL in place but pushes it
//              further from price by the pair's recorded max spread
//              (x a multiplier), then restores the original at spread-hour
//              end. The SL is never removed, so a crash leaves a widened
//              stop, not a naked position. Max spread is read from / logged
//              to a CSV history file.
//
//  WARNING: This EA does NOT handle partial closes during spread hour.
//  In MT5, a partial close destroys the original ticket and creates a
//  new one. If a position is partially closed (by you or another EA)
//  while its SL is modified, the remaining portion will NOT have its
//  SL restored automatically. You must manage that manually.
//
//  WARNING: If the EA is restarted or crashes during spread hour,
//  stored SL data is lost (memory only). Affected positions will keep
//  their modified SL (removed, or widened) until manually corrected.
//
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.02"

#include <Trade\Trade.mqh>
#include "Include\CommonUtils.mqh"

//--- mode enums
enum ENUM_SL_MODE
  {
   RemoveSL = 0,  // Remove SL during spread hour
   PadSL    = 1   // Pad SL by recorded max spread
  };

enum ENUM_FILE_MODE
  {
   ReadOnly  = 0, // Read only (never writes the CSV)
   ReadWrite = 1  // Read and update the CSV
  };

//--- top-level mode switch
input ENUM_SL_MODE    Mode              = RemoveSL;   // SL handling mode

//--- timing & on/off
input group "Timing & On/Off"
input string          SpreadHourStart   = "23:59";    // Spread hour start time (HH:MM)
input string          SpreadHourEndTime = "01:01";    // Spread hour end time (HH:MM)
input bool            Enable            = false;       // Enable EA

//--- simple mode inputs
input group "Simple Mode (Remove SL)"
input ENUM_SCOPE_MODE Scope             = Current;     // Scope

//--- advanced mode inputs
input group "Advanced Mode (Pad SL)"
input string          PairsList         = "EURUSD,GBPUSD,USDJPY,USDCHF,USDCAD,AUDUSD,NZDUSD,EURGBP,EURJPY,EURCHF,EURCAD,EURAUD,EURNZD,GBPJPY,GBPCHF,GBPCAD,GBPAUD,GBPNZD,AUDJPY,AUDCAD,AUDCHF,AUDNZD,NZDJPY,CADJPY,CHFJPY"; // Pairs
input string          SpreadFile        = "broker-spread.csv"; // Spread history CSV
input ENUM_FILE_MODE  FileMode          = ReadWrite;   // CSV access
input double          Multiplier        = 1.0;         // Spread multiplier
input int             Failover          = 0;           // Failover (points)

//--- stored SL data
struct SLRecord
  {
   ulong             ticket;
   double            originalSL;
  };

SLRecord          g_records[];
bool              g_inSpreadHour    = false;
bool              g_slsModified     = false;
int               g_startMinutes    = 0;
int               g_endMinutes      = 0;
CTrade            g_trade;

//--- PadSL state
string            g_pairs[];        // managed pairs (parsed from PairsList)
int               g_todayMax[];     // running max spread (points) seen this session, per pair
string            g_histSym[];      // pairs found in the CSV history
double            g_histMax[];      // biggest recorded spread (points) per history pair

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
//| Index of a symbol in the managed pairs list, -1 if not present   |
//+------------------------------------------------------------------+
int PairIndex(string sym)
  {
   for(int i = 0; i < ArraySize(g_pairs); i++)
      if(g_pairs[i] == sym)
         return i;
   return -1;
  }

//+------------------------------------------------------------------+
//| Parse the comma-separated PairsList into g_pairs / g_todayMax    |
//+------------------------------------------------------------------+
void ParsePairs()
  {
   ArrayResize(g_pairs, 0);
   ArrayResize(g_todayMax, 0);

   string parts[];
   int n = StringSplit(PairsList, ',', parts);
   for(int i = 0; i < n; i++)
     {
      string s = parts[i];
      StringTrimLeft(s);
      StringTrimRight(s);
      if(s == "")
         continue;
      if(PairIndex(s) >= 0)
         continue; // dedupe

      int idx = ArraySize(g_pairs);
      ArrayResize(g_pairs, idx + 1);
      ArrayResize(g_todayMax, idx + 1);
      g_pairs[idx]    = s;
      g_todayMax[idx] = 0;
      SymbolSelect(s, true); // ensure quotes are available in Market Watch
     }
  }

//+------------------------------------------------------------------+
//| Reset the per-session running max for all managed pairs          |
//+------------------------------------------------------------------+
void ResetTodayMax()
  {
   for(int i = 0; i < ArraySize(g_todayMax); i++)
      g_todayMax[i] = 0;
  }

//+------------------------------------------------------------------+
//| Sample current spread of every managed pair, update session max  |
//+------------------------------------------------------------------+
void SampleSpreads()
  {
   for(int i = 0; i < ArraySize(g_pairs); i++)
     {
      string sym   = g_pairs[i];
      double point = SymbolInfoDouble(sym, SYMBOL_POINT);
      if(point <= 0.0)
         continue;
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
         continue;

      int spread = (int)MathRound((ask - bid) / point);
      if(spread > g_todayMax[i])
         g_todayMax[i] = spread;
     }
  }

//+------------------------------------------------------------------+
//| Record a pair's spread into the in-memory history (keep max)     |
//+------------------------------------------------------------------+
void UpdateHistMax(string pair, double spread)
  {
   for(int i = 0; i < ArraySize(g_histSym); i++)
      if(g_histSym[i] == pair)
        {
         if(spread > g_histMax[i])
            g_histMax[i] = spread;
         return;
        }
   int idx = ArraySize(g_histSym);
   ArrayResize(g_histSym, idx + 1);
   ArrayResize(g_histMax, idx + 1);
   g_histSym[idx] = pair;
   g_histMax[idx] = spread;
  }

//+------------------------------------------------------------------+
//| Biggest recorded spread for a pair, -1 if not in history         |
//+------------------------------------------------------------------+
double LookupHistMax(string sym)
  {
   for(int i = 0; i < ArraySize(g_histSym); i++)
      if(g_histSym[i] == sym)
         return g_histMax[i];
   return -1.0;
  }

//+------------------------------------------------------------------+
//| Load the full spread history from the CSV (max per pair)         |
//+------------------------------------------------------------------+
void LoadHistory()
  {
   ArrayResize(g_histSym, 0);
   ArrayResize(g_histMax, 0);

   if(!FileIsExist(SpreadFile))
     {
      Print("[SpreadHourDodger] Spread file not found: ", SpreadFile, " (failover will apply)");
      return;
     }

   int h = FileOpen(SpreadFile, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
     {
      Print("[SpreadHourDodger] FAILED to open CSV for reading: ", SpreadFile, " | err ", GetLastError());
      return;
     }

   int rows = 0;
   while(!FileIsEnding(h))
     {
      string date      = FileReadString(h);
      string pair      = FileReadString(h);
      string spreadStr = FileReadString(h);

      if(pair == "")
         continue;                       // blank / malformed line
      if(date == "date" || pair == "pair")
         continue;                       // header row

      UpdateHistMax(pair, StringToDouble(spreadStr));
      rows++;
     }
   FileClose(h);

   Print("[SpreadHourDodger] Loaded spread history: ", rows, " row(s), ",
         ArraySize(g_histSym), " pair(s) from ", SpreadFile);
  }

//+------------------------------------------------------------------+
//| Append this session's max spread per pair to the CSV             |
//+------------------------------------------------------------------+
void FlushSpreadsToFile()
  {
   if(FileMode == ReadOnly)
      return;

   bool exists = FileIsExist(SpreadFile);
   int  h = FileOpen(SpreadFile, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
     {
      Print("[SpreadHourDodger] FAILED to open CSV for writing: ", SpreadFile, " | err ", GetLastError());
      return;
     }

   if(!exists)
      FileWrite(h, "date", "pair", "max_spread"); // header on a brand-new file
   FileSeek(h, 0, SEEK_END);

   MqlDateTime dt;
   TimeCurrent(dt);
   string date = StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);

   int written = 0;
   for(int i = 0; i < ArraySize(g_pairs); i++)
     {
      if(g_todayMax[i] <= 0)
         continue; // never observed a spread for this pair this session
      FileWrite(h, date, g_pairs[i], g_todayMax[i]);
      written++;
     }
   FileClose(h);

   Print("[SpreadHourDodger] Appended ", written, " spread record(s) to ", SpreadFile);
  }

//+------------------------------------------------------------------+
//| Decide the new SL for a position in PadSL mode.                  |
//| Returns false to leave the position untouched. On true, newSL    |
//| holds the target (0.0 means remove the SL as a failover).        |
//+------------------------------------------------------------------+
bool ComputePaddedSL(ulong ticket, string sym, double sl, double &newSL)
  {
   double histMax = LookupHistMax(sym);
   double required;

   if(histMax >= 0.0)
     {
      required = histMax * Multiplier;         // recorded max x multiplier
     }
   else
     {
      // pair is managed but has no history yet -> failover
      if(Failover <= 0)
        {
         Print("[SpreadHourDodger] #", ticket, " (", sym,
               ") no history, Failover<=0 -> leaving SL unchanged.");
         return false;                          // do nothing
        }
      required = Failover;                       // multiplier NOT applied to failover
     }

   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   int  digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   long type   = PositionGetInteger(POSITION_TYPE);
   double bid  = SymbolInfoDouble(sym, SYMBOL_BID);
   double ask  = SymbolInfoDouble(sym, SYMBOL_ASK);

   // current distance from the triggering price to the SL (points)
   double curDist;
   if(type == POSITION_TYPE_BUY)
      curDist = (bid - sl) / point;      // buy SL is hit by bid
   else
      curDist = (sl - ask) / point;      // sell SL is hit by ask

   double moveBy = required - curDist;
   if(moveBy <= 0.0)
     {
      Print("[SpreadHourDodger] #", ticket, " (", sym, ") SL already ",
            DoubleToString(curDist, 1), "pts away (need ", DoubleToString(required, 1),
            ") - no change.");
      return false;
     }

   if(type == POSITION_TYPE_BUY)
      newSL = sl - moveBy * point;       // push SL down, away from price
   else
      newSL = sl + moveBy * point;       // push SL up, away from price

   newSL = NormalizeDouble(newSL, digits);
   return true;
  }

//+------------------------------------------------------------------+
//| Modify one position's SL per the active mode, storing original   |
//+------------------------------------------------------------------+
void ManagePosition(ulong ticket)
  {
   if(ticket == 0) return;
   if(!PositionSelectByTicket(ticket)) return;

   string sym = PositionGetString(POSITION_SYMBOL);

   // scope / eligibility differs by mode
   if(Mode == RemoveSL)
     {
      if(!SymbolMatchesScope(Scope, sym, _Symbol)) return;
     }
   else // PadSL: PairsList is the authority, Scope ignored
     {
      if(PairIndex(sym) < 0) return; // not listed -> ignore 100%
     }

   if(FindRecord(ticket) >= 0) return;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl == 0.0) return; // no SL to manage

   double tp = PositionGetDouble(POSITION_TP);

   double newSL;
   if(Mode == RemoveSL)
      newSL = 0.0;
   else if(!ComputePaddedSL(ticket, sym, sl, newSL))
      return; // padding decided to leave it alone

   if(g_trade.PositionModify(ticket, newSL, tp))
     {
      int idx = ArraySize(g_records);
      ArrayResize(g_records, idx + 1);
      g_records[idx].ticket     = ticket;
      g_records[idx].originalSL = sl;
      if(newSL == 0.0)
         Print("[SpreadHourDodger] Removed SL for position #", ticket, " (", sym, ") | Original SL: ", sl);
      else
         Print("[SpreadHourDodger] Padded SL for position #", ticket, " (", sym,
               ") | ", sl, " -> ", newSL);
     }
   else
      Print("[SpreadHourDodger] FAILED to modify SL for position #", ticket,
            " | Retcode: ", g_trade.ResultRetcode(),
            " | ", g_trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Apply the active mode to all open positions                      |
//+------------------------------------------------------------------+
void ManageAllPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      ManagePosition(ticket);
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
   string verb = (Mode == RemoveSL) ? "REMOVED" : "PADDED";

   if(!Enable)
     {
      line1 = "SpreadHourDodger: INACTIVE";
      line2 = "Enable is OFF";
      line3 = "";
     }
   else if(g_inSpreadHour && g_slsModified)
     {
      int secs = SecondsUntil(g_endMinutes);
      line1 = "SpreadHourDodger: ACTIVE (" + EnumToString(Mode) + ")";
      line2 = "SPREAD HOUR - SLs " + verb + " (" + IntegerToString(ArraySize(g_records)) + " tracked)";
      line3 = "Ends in: " + FormatCountdown(secs);
     }
   else
     {
      int secs = SecondsUntil(g_startMinutes);
      line1 = "SpreadHourDodger: ACTIVE (" + EnumToString(Mode) + ")";
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
   g_slsModified  = false;
   ArrayResize(g_records, 0);

   if(Mode == PadSL)
      ParsePairs();

   Print("[SpreadHourDodger] Initialized | Mode: ", EnumToString(Mode),
         " | Start: ", SpreadHourStart,
         " | End: ", SpreadHourEndTime,
         " | Scope: ", EnumToString(Scope),
         " | Pairs: ", ArraySize(g_pairs),
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

   // Only act during spread hour with SLs modified
   if(!g_slsModified)
      return;

   // A deal was added - check if it created/added to a position
   ulong posTicket = trans.position;
   if(posTicket == 0)
      return;

   // Small delay to let the position fully register
   Sleep(100);

   ManagePosition(posTicket);
  }

//+------------------------------------------------------------------+
//| Core logic                                                       |
//+------------------------------------------------------------------+
void ProcessLogic()
  {
   // EA disabled - restore SLs if they were modified, then do nothing
   if(!Enable)
     {
      if(g_slsModified)
        {
         Print("[SpreadHourDodger] EA disabled during spread hour, restoring SLs.");
         if(Mode == PadSL)
            FlushSpreadsToFile();
         RestoreOrClose();
         g_slsModified  = false;
         g_inSpreadHour = false;
        }
      UpdateDisplay();
      return;
     }

   int nowMin = CurrentMinutes();
   bool inWindow = IsInTimeWindow(nowMin, g_startMinutes, g_endMinutes);

   if(inWindow)
     {
      // Spread hour just started - modify all stop losses
      if(!g_inSpreadHour)
        {
         g_inSpreadHour = true;
         g_slsModified  = true;
         Print("[SpreadHourDodger] Spread hour started. Modifying SLs (", EnumToString(Mode), ")...");
         if(Mode == PadSL)
           {
            ResetTodayMax();
            LoadHistory();   // read recorded maxes BEFORE padding
           }
         ManageAllPositions();
        }

      // Track spread through the whole window (PadSL + ReadWrite only;
      // in ReadOnly there is nothing to write, so skip the per-tick work)
      if(Mode == PadSL && FileMode == ReadWrite)
         SampleSpreads();
     }
   else
     {
      // Spread hour just ended - restore stops or close breached positions
      if(g_slsModified)
        {
         Print("[SpreadHourDodger] Spread hour ended. Restoring SLs / closing breached positions...");
         if(Mode == PadSL)
            FlushSpreadsToFile();
         RestoreOrClose();
         g_slsModified = false;
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
