//+------------------------------------------------------------------+
//|                                                      myBot.mq5   |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\Trade.mqh>
CTrade trade;

// Define parameters
input int momentumPeriod = 3;
input int numberOfCandles = 10;
input double lotSize = 0.01;
input double spreadThreshold = 0.40;
input double tpFactor = 1;
input double slFactor = 0.5;

datetime lastCloseTime = 0;
int OnInit()
  {
   return(INIT_SUCCEEDED);
  }
void OnTick()
  {
   // Retrieve historical candles
   MqlRates rates[];
   int copied = CopyRates("XAUUSD", PERIOD_M1, 0, numberOfCandles, rates);
   if(copied < numberOfCandles)
     {
      Print("Error retrieving historical data");
      return;
     }
   
   // Check if a new 1-minute candle has closed
   if(rates[0].time != lastCloseTime)
     {
      lastCloseTime = rates[0].time;
      Bot();
     }
  }
//+------------------------------------------------------------------+
//| Calculate Momentum                                               |
//+------------------------------------------------------------------+
double CalculateMomentum(double &data[], int period)
  {
   if(ArraySize(data) < period)
      return 0;
   return data[ArraySize(data)-1] - data[ArraySize(data)-1-period];
  }
//+------------------------------------------------------------------+
//| Main Bot Function                                                |
//+------------------------------------------------------------------+
void Bot()
  {
   // Check for open positions
   if(PositionSelect("XAUUSD"))
     {
      Print("## Posisi Sedang Berjalan ##");
      return;
     }

   // Retrieve current price
   double bid = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
   double ask = SymbolInfoDouble("XAUUSD", SYMBOL_ASK);
   double spread = NormalizeDouble(ask - bid, _Digits);

   // Check spread condition
   if(spread > spreadThreshold)
     {
      Print("## Spread terlalu melebar ##");
      return;
     }

   // Retrieve historical candles
   MqlRates rates[];
   int copied = CopyRates("XAUUSD", PERIOD_M1, 0, numberOfCandles, rates);
   if(copied < numberOfCandles)
     {
      Print("Error retrieving historical data");
      return;
     }

   // Calculate momentum
   double momentumSum = 0;
   double highestHigh = 0;
   double lowestLow = 999999;
   for(int i = momentumPeriod; i < copied; i++)
     {
      momentumSum += rates[i].close - rates[i-momentumPeriod].close;
      if(rates[i].high > highestHigh)
        highestHigh = rates[i].high;
      if(rates[i].low < lowestLow)
        lowestLow = rates[i].low;
     }

   Print("Sum of Momentum Oscillator Values: ", momentumSum);
   Print("Highest High in Historical Data: ", highestHigh);
   Print("Lowest Low in Historical Data: ", lowestLow);

   // Check trading conditions
   if(momentumSum > 1)
     {
      double tp = bid + (highestHigh-lowestLow);
      double sl = ask - (1);
      double roundedTP = NormalizeDouble(tp, _Digits);
      double roundedSL = NormalizeDouble(sl, _Digits);
      if(trade.Buy(lotSize, "XAUUSD"))
        {
         trade.PositionModify("XAUUSD", roundedSL, roundedTP);
         Print("Buka posisi BUY");
         Print("TP: ", roundedTP, " SL: ", roundedSL);
         Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
      else
         Print("Error opening buy position: ", GetLastError());
     }
   else if(momentumSum < -1)
     {
      double tp = ask - (highestHigh-lowestLow);
      double sl = bid + (1);
      double roundedTP = NormalizeDouble(tp, _Digits);
      double roundedSL = NormalizeDouble(sl, _Digits);
      if(trade.Sell(lotSize, "XAUUSD"))
        {
         trade.PositionModify("XAUUSD", roundedSL, roundedTP);
         Print("Buka posisi SELL");
         Print("TP: ", roundedTP, " SL: ", roundedSL);
         Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
      else
         Print("Error opening sell position: ", GetLastError());
     }
   else
     {
      Print("## Kondisi entri tidak terpenuhi ##");
     }
  }
//+------------------------------------------------------------------+
