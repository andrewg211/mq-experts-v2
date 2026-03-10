//+------------------------------------------------------------------+
//|                                                  CommonUtils.mqh |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"

#ifndef COMMON_UTILS_MQH
#define COMMON_UTILS_MQH

//--- enums
enum ENUM_SCOPE_MODE
  {
   Current = 0,  // Current Symbol
   All     = 1   // All Symbols
  };

//+------------------------------------------------------------------+
//| Parse "HH:MM" string to minutes since midnight                   |
//+------------------------------------------------------------------+
int TimeStringToMinutes(string timeStr)
  {
   string parts[];
   StringSplit(timeStr, ':', parts);
   if(ArraySize(parts) < 2)
      return 0;
   return (int)StringToInteger(parts[0]) * 60 + (int)StringToInteger(parts[1]);
  }

//+------------------------------------------------------------------+
//| Get current server time as minutes since midnight                |
//+------------------------------------------------------------------+
int CurrentMinutes()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   return dt.hour * 60 + dt.min;
  }

//+------------------------------------------------------------------+
//| Check if a given minute is inside a time window                  |
//+------------------------------------------------------------------+
bool IsInTimeWindow(int nowMin, int startMin, int endMin)
  {
   if(startMin <= endMin)
      return (nowMin >= startMin && nowMin < endMin);
   else // wraps midnight
      return (nowMin >= startMin || nowMin < endMin);
  }

//+------------------------------------------------------------------+
//| Seconds until a target minute-of-day from now                    |
//+------------------------------------------------------------------+
int SecondsUntil(int targetMin)
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   int nowSec = dt.hour * 3600 + dt.min * 60 + dt.sec;
   int targetSec = targetMin * 60;
   int diff = targetSec - nowSec;
   if(diff <= 0)
      diff += 86400;
   return diff;
  }

//+------------------------------------------------------------------+
//| Format seconds to HH:MM:SS                                      |
//+------------------------------------------------------------------+
string FormatCountdown(int secs)
  {
   if(secs < 0) secs = 0;
   int h = secs / 3600;
   int m = (secs % 3600) / 60;
   int s = secs % 60;
   return StringFormat("%02d:%02d:%02d", h, m, s);
  }

//+------------------------------------------------------------------+
//| Check if symbol matches scope filter                             |
//+------------------------------------------------------------------+
bool SymbolMatchesScope(ENUM_SCOPE_MODE scope, string symbol, string currentSymbol)
  {
   if(scope == All)
      return true;
   return (symbol == currentSymbol);
  }

#endif
//+------------------------------------------------------------------+
