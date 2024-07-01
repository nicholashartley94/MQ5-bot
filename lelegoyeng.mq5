#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\Trade.mqh>
CTrade trade;

input int momentumPeriod = 2; 
input int numberOfCandles = 5;
input double lotSize = 0.01;
input double spreadThreshold = 0.40;
input double tpFactor = 1;
input double slFactor = 0.5;
input int rsiPeriod = 5;      
input double rsiOverbought = 66;
input double rsiOversold = 36; 
input int maPeriod = 5; 

datetime lastCloseTime = 0;
datetime lastRunTime = 0;

int OnInit()
{
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    datetime now = TimeCurrent();
    if (now - lastRunTime < PeriodSeconds(PERIOD_M5))
        return; 

    lastRunTime = now;

    // Retrieve historical candles
    MqlRates rates[];
    int copied = CopyRates("XAUUSD", PERIOD_M5, 0, numberOfCandles, rates);
    if (copied < numberOfCandles)
    {
        Print("Error retrieving historical data");
        return;
    }

    // Check if a new 5-minute candle has closed
    if (rates[0].time != lastCloseTime)
    {
        lastCloseTime = rates[0].time;
        Bot(rates);
    }
}

double CalculateMomentum(double &data[], int period)
{
    if (ArraySize(data) < period)
        return 0;
    return data[ArraySize(data)-1] - data[ArraySize(data)-1-period];
}

double CalculateRSI(int period)
{
    double rsi[];
    int rsiHandle = iRSI("XAUUSD", PERIOD_M5, period, PRICE_CLOSE);
    if (rsiHandle < 0)
    {
        Print("Error creating RSI handle");
        return 0;
    }
    if (CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 0)
    {
        Print("Error retrieving RSI data");
        return 0;
    }
    double result = rsi[1];
    IndicatorRelease(rsiHandle);
    return result;
}

double CalculateMA(int period)
{
    double ma[];
    int maHandle = iMA("XAUUSD", PERIOD_M5, period, 0, MODE_SMA, PRICE_CLOSE);
    if (maHandle < 0)
    {
        Print("Error creating MA handle");
        return 0;
    }
    if (CopyBuffer(maHandle, 0, 0, 3, ma) < 0)
    {
        Print("Error retrieving MA data");
        return 0;
    }
    double result = ma[1];
    IndicatorRelease(maHandle);
    return result;
}

void Bot(const MqlRates &rates[])
{
    // Check for open positions
    if (PositionSelect("XAUUSD"))
    {
        Print("## Posisi Sedang Berjalan ##");
        return;
    }

    // Retrieve current price
    double bid = SymbolInfoDouble("XAUUSD", SYMBOL_BID);
    double ask = SymbolInfoDouble("XAUUSD", SYMBOL_ASK);
    double spread = NormalizeDouble(ask - bid, _Digits);

    // Check spread condition
    if (spread > spreadThreshold)
    {
        Print("## Spread terlalu melebar ##");
        return;
    }

    // Calculate momentum
    double momentumSum = 0;
    double highestHigh = 0;
    double lowestLow = 999999;
    for (int i = momentumPeriod; i < numberOfCandles; i++)
    {
        momentumSum += rates[i].close - rates[i-momentumPeriod].close;
        if (rates[i].high > highestHigh)
            highestHigh = rates[i].high;
        if (rates[i].low < lowestLow)
            lowestLow = rates[i].low;
    }

    Print("Sum of Momentum Oscillator Values: ", momentumSum);
    Print("Highest High in Historical Data: ", highestHigh);
    Print("Lowest Low in Historical Data: ", lowestLow);

    // Calculate RSI and MA
    double rsi = CalculateRSI(rsiPeriod);
    double ma = CalculateMA(maPeriod);
    Print("RSI: ", rsi, " MA: ", ma);
    Print("RSI Oversold: ", rsiOversold, "RSI OverBought: ",rsiOverbought, " Rates close: ", rates[0].close);

    // Check trading conditions
    if (momentumSum > 1 && rsi < rsiOversold && rates[0].close > ma)
    {
        double tp = bid + (highestHigh - lowestLow);
        double sl = bid - (highestHigh - lowestLow);
        double roundedTP = NormalizeDouble(tp, _Digits);
        double roundedSL = NormalizeDouble(sl, _Digits);
        if (trade.Buy(lotSize, "XAUUSD"))
        {
            trade.PositionModify("XAUUSD", roundedSL, roundedTP);
            Print("Buka posisi BUY");
            Print("TP: ", roundedTP, " SL: ", roundedSL);
            Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
        else
            Print("Error opening buy position: ", GetLastError());
    }
    else if (momentumSum < -1 && rsi > rsiOverbought && rates[0].close < ma)
    {
        double tp = ask - (highestHigh - lowestLow);
        double sl = ask + (highestHigh - lowestLow);
        double roundedTP = NormalizeDouble(tp, _Digits);
        double roundedSL = NormalizeDouble(sl, _Digits);
        if (trade.Sell(lotSize, "XAUUSD"))
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
