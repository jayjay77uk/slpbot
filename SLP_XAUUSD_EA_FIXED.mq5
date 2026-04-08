//+------------------------------------------------------------------+
//| SLP_XAUUSD_EA_FIXED.mq5                                          |
//| Clean MT5-compilable base EA - 2025 edition                      |
//+------------------------------------------------------------------+
#property copyright "Fixed version"
#property link      ""
#property version   "1.11"
#property strict    // safe to keep, ignored in new builds

input double RiskPercent    = 10.0;
input double RR             = 5.0;
input int    MaxTradesPerDay = 2;
input int    MaxSLPerWeek   = 4;
input int    SL_Buffer_Pips = 5;
input string TradeSymbol    = "XAUUSD";

// Globals
int      tradesToday   = 0;
int      slThisWeek    = 0;
datetime lastTradeDay  = 0;
int      lastWeek      = -1;
datetime lastH1Bar     = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(_Symbol != TradeSymbol)
   {
      Print("EA designed for ", TradeSymbol, " only.");
      return(INIT_PARAMETERS_INCORRECT);
   }

   lastWeek = GetWeekOfYear(TimeCurrent());
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar(PERIOD_H1)) return;

   if(!IsTradingDay())      return;
   if(IsDailyLimitHit())    return;
   if(IsWeeklySLHit())      return;
   if(HasOpenPosition())    return;

   int bias = GetBiasH1();
   if(bias == 0) return;

   double entry = 0.0, sl = 0.0;
   if(!FindOrderBlock(bias, entry, sl)) return;

   double tp = entry + bias * RR * MathAbs(entry - sl);

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl,    _Digits);
   tp    = NormalizeDouble(tp,    _Digits);

   double lot = CalculateLot(entry, sl);
   if(lot <= 0.0) return;

   PlaceTrade(bias, lot, entry, sl, tp);
}

//+------------------------------------------------------------------+
//| Bias detection                                                   |
//+------------------------------------------------------------------+
int GetBiasH1()
{
   double h1 = iHigh(NULL, PERIOD_H1, 1);
   double h2 = iHigh(NULL, PERIOD_H1, 2);
   double l1 = iLow(NULL, PERIOD_H1, 1);
   double l2 = iLow(NULL, PERIOD_H1, 2);

   if(h1 > h2 && l1 > l2) return 1;
   if(h1 < h2 && l1 < l2) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Order Block search                                               |
//+------------------------------------------------------------------+
bool FindOrderBlock(int bias, double &entry, double &sl)
{
   double pip = 10.0 * _Point;   // XAUUSD typical

   for(int i = 2; i < 50; i++)
   {
      double o = iOpen(NULL, PERIOD_M15, i);
      double c = iClose(NULL, PERIOD_M15, i);
      double h = iHigh(NULL, PERIOD_M15, i);
      double l = iLow(NULL, PERIOD_M15, i);

      if(bias == 1 && c < o)
      {
         entry = o;
         sl    = l - SL_Buffer_Pips * pip;
         return true;
      }
      if(bias == -1 && c > o)
      {
         entry = o;
         sl    = h + SL_Buffer_Pips * pip;
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Position check                                                   |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Lot calculation with safety                                      |
//+------------------------------------------------------------------+
double CalculateLot(double entry, double sl)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * RiskPercent / 100.0;
   double slDist    = MathAbs(entry - sl);

   if(slDist < _Point * 10) return 0.0;

   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize == 0 || tickValue == 0) return 0.0;

   double points    = slDist / tickSize;
   double lossPerLot = points * tickValue;

   if(lossPerLot <= 0) return 0.0;

   double lots = riskMoney / lossPerLot;

   double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volMin  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   lots = MathRound(lots / volStep) * volStep;
   lots = MathMax(volMin, MathMin(volMax, lots));

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Place pending order                                              |
//+------------------------------------------------------------------+
void PlaceTrade(int bias, double lot, double entry, double sl, double tp)
{
   MqlTradeRequest request={};
   MqlTradeResult result={};

   request.action    = TRADE_ACTION_PENDING;
   request.symbol    = _Symbol;
   request.volume    = lot;
   request.price     = entry;
   request.sl        = sl;
   request.tp        = tp;
   request.magic     = 202601;
   request.type      = (bias > 0) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   request.type_filling = ORDER_FILLING_RETURN;   // required for pending orders

   if(!OrderSend(request, result))
   {
      PrintFormat("OrderSend failed: retcode=%u  comment=%s", result.retcode, result.comment);
      return;
   }

   if(result.retcode == 10009 || result.retcode == 10008)   // done / placed
   {
      tradesToday++;
      lastTradeDay = TimeCurrent();
      Print("Order placed OK → ticket ", result.order);
   }
}

//+------------------------------------------------------------------+
//| Trading day (Mon-Wed)                                            |
//+------------------------------------------------------------------+
bool IsTradingDay()
{
   MqlDateTime tm;
   TimeToStruct(TimeCurrent(), tm);
   return (tm.day_of_week >= 1 && tm.day_of_week <= 3);
}

//+------------------------------------------------------------------+
//| Daily trade limit                                                |
//+------------------------------------------------------------------+
bool IsDailyLimitHit()
{
   datetime now = TimeCurrent();
   MqlDateTime t1, t2;
   TimeToStruct(now, t1);
   TimeToStruct(lastTradeDay, t2);

   if(t1.day != t2.day || t1.mon != t2.mon || t1.year != t2.year)
   {
      tradesToday = 0;
      lastTradeDay = now;
   }

   return tradesToday >= MaxTradesPerDay;
}

//+------------------------------------------------------------------+
//| Weekly SL limit                                                  |
//+------------------------------------------------------------------+
bool IsWeeklySLHit()
{
   int currentWeek = GetWeekOfYear(TimeCurrent());
   if(currentWeek != lastWeek)
   {
      slThisWeek = 0;
      lastWeek = currentWeek;
   }
   return slThisWeek >= MaxSLPerWeek;
}

//+------------------------------------------------------------------+
//| Track SL hits                                                    |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(HistoryDealSelect(trans.deal))
      {
         long reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
         long entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
         long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

         if(magic == 202601 && reason == DEAL_REASON_SL && entryType == DEAL_ENTRY_OUT)
         {
            slThisWeek++;
            Print("SL detected → count = ", slThisWeek);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Custom week number                                               |
//+------------------------------------------------------------------+
int GetWeekOfYear(datetime dt)
{
   MqlDateTime timeStruct;
   TimeToStruct(dt, timeStruct);

   datetime firstDay = StringToTime(StringFormat("%04d.01.04", timeStruct.year)); // Thursday rule approximation
   MqlDateTime first;
   TimeToStruct(firstDay, first);

   int offset = (first.day_of_week + 3) % 7; // adjust to Monday start
   int days = (int)((dt - firstDay) / 86400) + offset;

   return (days / 7) + 1;
}

//+------------------------------------------------------------------+
//| New bar detector                                                 |
//+------------------------------------------------------------------+
bool IsNewBar(ENUM_TIMEFRAMES timeframe)
{
   datetime current = iTime(_Symbol, timeframe, 0);
   if(current != lastH1Bar)
   {
      lastH1Bar = current;
      return true;
   }
   return false;
}
//+------------------------------------------------------------------+
