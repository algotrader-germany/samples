//+------------------------------------------------------------------+
//|                                                     donchian.mq5 |
//|                        Copyright 2020, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2020, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include<Trade\Trade.mqh>

input    double   fixedLots              = 0.0;
input    double   accountBalancePerLot   = 2000.0;
input    double   trailingStopPercent    = 0.2;
input    double   initialStopPercent     = 0.6;
input    bool     profitLockIn           = true;
input    bool     useSARForExit          = false;
input    double   sarStep                = 0.02;
input    double   sarMax                 = 0.2;
input    double   takeProfitPercent      = 5.0;
input    int      period                 = 250;
input    int      loglevel               = 0; 
input    int      myMagic                = 20201229;

datetime lastCandleOpenTime = NULL;

CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   string methodname = "OnInit";
   printlog(0, methodname, "EA 'donchian' initialized.");
//---
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//---
   string methodname = "OnTick()";
   if (iTime(_Symbol, PERIOD_CURRENT, 0) == lastCandleOpenTime) return;
   lastCandleOpenTime=iTime(_Symbol, PERIOD_CURRENT, 0);
   
   printlog(2,methodname, "processing new candle");   

   double highest = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, period, 0));
   double lowest  = iLow (_Symbol, PERIOD_CURRENT, iLowest (_Symbol, PERIOD_CURRENT, MODE_LOW,  period, 0));
   
   printlog(2,methodname, StringFormat("highest: %.f, lowest: %.5f", highest, lowest));
   
   double lots = fixedLots;
   if (accountBalancePerLot > 0.0) {
      lots = NormalizeDouble(AccountInfoDouble(ACCOUNT_BALANCE) / accountBalancePerLot, MathAbs(MathLog10(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))));
      if (lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) {
         lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      }
      if (lots > SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)) {
         lots = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      }
      printlog(1, methodname, StringFormat("adjusting lots for balance %.2f to %.2f", AccountInfoDouble(ACCOUNT_BALANCE),SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP) ));
   }
   
   int openLongPositions = countOpenPositions(POSITION_TYPE_BUY);
   trailLong();      
   
   if (openLongPositions == 0 || zeroRisk(POSITION_TYPE_BUY)) {
      double sl = NormalizeDouble( (100 - initialStopPercent)/100 * highest, _Digits);
      double tp = NormalizeDouble( (100 + takeProfitPercent)/100 * highest, _Digits);
      ulong pendingLongTicket = getPendingTicket(ORDER_TYPE_BUY_STOP);
            
      if (pendingLongTicket == 0) {
         trade.BuyStop(lots, highest, _Symbol, sl, tp, ORDER_TIME_GTC, 0.0, "pro-cyclic-long");
      } else {
         bool modify = (sl != OrderGetDouble(ORDER_SL));
         modify = modify || (tp != OrderGetDouble(ORDER_TP));
         modify = modify || (highest != OrderGetDouble(ORDER_PRICE_OPEN));
         if (modify) {
            printlog(2, methodname, StringFormat("modifying pending order because of difference in (old vs. new) SL %.5f vs %.5f, TP %.5f vs %.5f, price %.5f vs %.5f",
              OrderGetDouble(ORDER_SL), sl, OrderGetDouble(ORDER_TP), tp, OrderGetDouble(ORDER_PRICE_OPEN), highest));
            trade.OrderModify(pendingLongTicket, highest, sl, tp, ORDER_TIME_GTC, 0.0, 0.0);
         }
      }
   }
   
   int openShortPositions = countOpenPositions(POSITION_TYPE_SELL);
   trailShort();
      
   if (openShortPositions == 0 || zeroRisk(POSITION_TYPE_SELL)) {
      double sl = NormalizeDouble( (100 + initialStopPercent)/100 * lowest, _Digits);    
      double tp = NormalizeDouble( (100 - takeProfitPercent)/100 * lowest, _Digits);
      ulong pendingShortTicket = getPendingTicket(ORDER_TYPE_SELL_STOP);
      
      if (pendingShortTicket == 0) {
         trade.SellStop(lots, lowest, _Symbol, sl, tp, ORDER_TIME_GTC, 0.0, "pro-cyclic-short");
      } else {
         bool modify = (sl != OrderGetDouble(ORDER_SL));
         modify = modify || (tp != OrderGetDouble(ORDER_TP));
         modify = modify || (lowest != OrderGetDouble(ORDER_PRICE_OPEN));
         if (modify) {
            printlog(2, methodname, StringFormat("modifying pending order because of difference in (old vs. new) SL %.5f vs %.5f, TP %.5f vs %.5f, price %.5f vs %.5f",
              OrderGetDouble(ORDER_SL), sl, OrderGetDouble(ORDER_TP), tp, OrderGetDouble(ORDER_PRICE_OPEN), lowest));
            trade.OrderModify(pendingShortTicket, lowest, sl, tp, ORDER_TIME_GTC, 0.0, 0.0);
         }         
      }
   }   
   
  }
//+------------------------------------------------------------------+

void printlog(int level, string methodname, string message) {
   if (level <= loglevel) {
      PrintFormat("%i %s %s", level, methodname, message);
   }
}

bool zeroRisk(ENUM_POSITION_TYPE type) {
   string methodname = "zeroRisk";
   bool norisk = true;
   for (int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (type             == PositionGetInteger(POSITION_TYPE)) {
            double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl         = PositionGetDouble(POSITION_SL);
            double current    = PositionGetDouble(POSITION_PRICE_CURRENT);
            
            if (type == POSITION_TYPE_BUY) {
               if (!profitLockIn && sl < openPrice) {
                  norisk = false;
                  printlog(1, methodname, "exiting LONG with norisk=false");
                  break;  
               }
               
               if (profitLockIn) {
                  double minSlLong  = NormalizeDouble( (100 + initialStopPercent)/100*openPrice,_Digits);
                  printlog(2, methodname, StringFormat("with profitLockIn=true, a new long position can only be opened if the current sl %.5f is at least %.2f percent higher than this long position's open price %.5f, that is higher than %.5f",
                     sl, initialStopPercent, openPrice, minSlLong));
                  if (minSlLong > sl) { //lock in: next positions stop can lose at most current profit
                     norisk = false;
                     printlog(1, methodname, "exiting LONG with norisk=false");
                     break;
                  }
               }
               
            }
            
            if (type == POSITION_TYPE_SELL) {
               if (profitLockIn && sl > openPrice) {
                  norisk = false;
                  printlog(1, methodname, "exiting SHORT with norisk=false");
                  break;
               }
               if (profitLockIn) {
                  double minSlShort = NormalizeDouble( (100 - initialStopPercent)/100*openPrice,_Digits);
                  printlog(2, methodname, StringFormat("with profitLockIn=true, a new short position can only be opened if the current sl %.5f is at least %.2f percent lower than this short position's open price %.5f, that is lower than %.5f",
                     sl, initialStopPercent, openPrice, minSlShort));
                  if (sl > minSlShort) { //lock in: next positions stop can lose at most current profit
                     norisk = false;
                     printlog(1, methodname, "exiting LONG with norisk=false");
                     break;
                  }
               }
               
            }
         }
      }
   }
   printlog(1, methodname, StringFormat("exiting %s with norisk=true", type));
   return norisk;
}

double calculateRiskShort() {
   string methodname = "calculateRiskShort";
   double risk = 0.0;
   for (int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (POSITION_TYPE_SELL == PositionGetInteger(POSITION_TYPE)) {
            double size      = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl        = PositionGetDouble(POSITION_SL);
            double cost      = PositionGetDouble(POSITION_SWAP);
            double posRisk   = size * (sl - openPrice);
            posRisk         += cost; //consider cost as lost
            printlog(2, methodname, StringFormat("considering risk of position with ticket: %i, size: %.2f, open: %.5f, sl: %.5f, cost: %.5f, total: %.5f",
               ticket, size, openPrice, sl, cost, posRisk));
            risk += posRisk;
         }
      }
   }
   printlog(1, methodname, StringFormat("exiting risk: %.5f ", risk));
   return risk;
}

int countOpenPositions(ENUM_POSITION_TYPE type) {
   string methodname = "countOpenPositions";
   int    count      = 0;
   for (int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (type == PositionGetInteger(POSITION_TYPE)) {
           count++;
         }
      }
   }   
   printlog(1, methodname, StringFormat("exiting count: %i", count));
   return count;   
}

ulong getPendingTicket(ENUM_ORDER_TYPE type){
   string methodname = "getPendingTicket";
   ulong  ticket     = 0;
   
   printlog(1, methodname, StringFormat("entering for type: %s, OrdersTotal(): %i", type, OrdersTotal()));
   
   for (int i=OrdersTotal()-1; i>=0; i--) {
      ulong orderticket = OrderGetTicket(i);
      printlog(2, methodname, StringFormat("inspecting ticket %i", orderticket));
      printlog(2, methodname, StringFormat("ticket symbol %s, compare with current symbol %s", OrderGetString(ORDER_SYMBOL) , _Symbol));
      if (OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      printlog(2, methodname, StringFormat("ticket magic %i, compare with current magic %i", OrderGetInteger(ORDER_MAGIC) , myMagic));
      if (OrderGetInteger(ORDER_TYPE)  != type)    continue;
      ticket = orderticket;
      break;
   }
   printlog(1, methodname, StringFormat("exiting ticket: %i", ticket));
   return ticket;   
}

void trailLong() {
   string methodname = "trailLong";
   double sar = 0.0;
   if (useSARForExit) {
      double sarSeries[];
      int sarDefinition = iSAR(_Symbol, PERIOD_CURRENT, sarStep, sarMax);
      ArraySetAsSeries(sarSeries,true);
      CopyBuffer(sarDefinition,0,0,3,sarSeries);
      
      sar = NormalizeDouble(sarSeries[1], _Digits);
   }
   
   for (int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY) continue;
         double positionSL = PositionGetDouble(POSITION_SL);
         double positionTP = PositionGetDouble(POSITION_TP);
         double positionOpen = PositionGetDouble(POSITION_PRICE_OPEN);
         double positionCurrent = PositionGetDouble(POSITION_PRICE_CURRENT);
         double trailingStop = NormalizeDouble(positionCurrent * (100 - trailingStopPercent)/100, _Digits);
         
         if (useSARForExit) {
            trailingStop = sar;
            printlog(2, methodname, StringFormat("trailing to sar=%.5f", sar));
         }
         
         printlog(2, methodname, StringFormat("trailing or keeping ... ticket %i, open %.5f, current %.5f sl %.5f, tp %.5f, new trailing sl %.5f", 
            ticket, positionOpen, positionCurrent, positionSL, positionTP, trailingStop));         
         if (positionOpen < trailingStop && positionSL < trailingStop) {
            trade.PositionModify(ticket, trailingStop, positionTP);
         }
      }      
   }
   printlog(1, methodname, "exiting");
}

void trailShort() {
   string methodname = "trailShort";
   double sar = 0.0;
   if (useSARForExit) {
      double sarSeries[];
      int sarDefinition = iSAR(_Symbol, PERIOD_CURRENT, sarStep, sarMax);
      ArraySetAsSeries(sarSeries,true);
      CopyBuffer(sarDefinition,0,0,3,sarSeries);
      
      sar = NormalizeDouble(sarSeries[1], _Digits);
   }
   for (int i=PositionsTotal()-1; i>=0; i--) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
         if (PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL) continue;
         double positionSL = PositionGetDouble(POSITION_SL);
         double positionTP = PositionGetDouble(POSITION_TP);
         double positionOpen = PositionGetDouble(POSITION_PRICE_OPEN);
         double positionCurrent = PositionGetDouble(POSITION_PRICE_CURRENT);
         double trailingStop = NormalizeDouble(positionCurrent * (100 + trailingStopPercent)/100, _Digits);
         if (useSARForExit) {
            trailingStop = sar;
         }
         printlog(2, methodname, StringFormat("trailing or keeping ... ticket %i, open %.5f, current: %.5f, sl %.5f, tp %.5f, new trailing sl %.5f", 
            ticket, positionOpen, positionCurrent, positionSL, positionTP, trailingStop));         
         if (positionOpen > trailingStop && positionSL > trailingStop) {
            trade.PositionModify(ticket, trailingStop, positionTP);
         }
      }      
   }
   printlog(1, methodname, "exiting");
}