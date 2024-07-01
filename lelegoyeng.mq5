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
input double rsiOverbought = 68;
input double rsiOversold = 32; 
input int maPeriod = 5; 
input string symbol1 = "XAUUSD";
input string symbol2 = "EURUSD";
input string symbol3 = "USDJPY";
input string symbol4 = "EURJPY";

string symbols[] = {symbol1, symbol2, symbol3, symbol4};

datetime lastCloseTime[];
datetime lastRunTime[];

int OnInit()
{
    ArrayResize(lastCloseTime, ArraySize(symbols));
    ArrayResize(lastRunTime, ArraySize(symbols));
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    datetime now = TimeCurrent();

    for (int i = 0; i < ArraySize(symbols); i++)
    {
        if (now - lastRunTime[i] < PeriodSeconds(PERIOD_M5))
            continue;

        lastRunTime[i] = now;

        // Retrieve historical candles
        MqlRates rates[];
        int copied = CopyRates(symbols[i], PERIOD_M5, 0, numberOfCandles, rates);
        if (copied < numberOfCandles)
        {
            Print("Error retrieving historical data for ", symbols[i]);
            continue;
        }

        // Check if a new 5-minute candle has closed
        if (rates[0].time != lastCloseTime[i])
        {
            lastCloseTime[i] = rates[0].time;
            Bot(symbols[i], rates);
        }
    }
}

double CalculateMomentum(double &data[], int period)
{
    if (ArraySize(data) < period)
        return 0;
    return data[ArraySize(data)-1] - data[ArraySize(data)-1-period];
}

double CalculateRSI(string symbol, int period)
{
    double rsi[];
    int rsiHandle = iRSI(symbol, PERIOD_M5, period, PRICE_CLOSE);
    if (rsiHandle < 0)
    {
        Print("Error creating RSI handle for ", symbol);
        return 0;
    }
    if (CopyBuffer(rsiHandle, 0, 0, 3, rsi) < 0)
    {
        Print("Error retrieving RSI data for ", symbol);
        return 0;
    }
    double result = rsi[1];
    IndicatorRelease(rsiHandle);
    return result;
}

double CalculateMA(string symbol, int period)
{
    double ma[];
    int maHandle = iMA(symbol, PERIOD_M5, period, 0, MODE_SMA, PRICE_CLOSE);
    if (maHandle < 0)
    {
        Print("Error creating MA handle for ", symbol);
        return 0;
    }
    if (CopyBuffer(maHandle, 0, 0, 3, ma) < 0)
    {
        Print("Error retrieving MA data for ", symbol);
        return 0;
    }
    double result = ma[1];
    IndicatorRelease(maHandle);
    return result;
}

void Bot(string symbol, const MqlRates &rates[])
{
    // Check for open positions
    if (PositionSelect(symbol))
    {
        Print("## Posisi Sedang Berjalan untuk ", symbol, " ##");
        return;
    }

    // Retrieve current price
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double spread = NormalizeDouble(ask - bid, _Digits);

    // Check spread condition
    if (spread > spreadThreshold)
    {
        Print("## Spread terlalu melebar untuk ", symbol, " ##");
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

    Print("Sum of Momentum Oscillator Values for ", symbol, ": ", momentumSum);
    Print("Highest High in Historical Data for ", symbol, ": ", highestHigh);
    Print("Lowest Low in Historical Data for ", symbol, ": ", lowestLow);

    // Calculate RSI and MA
    double rsi = CalculateRSI(symbol, rsiPeriod);
    double ma = CalculateMA(symbol, maPeriod);
    Print("RSI for ", symbol, ": ", rsi, " MA: ", ma);
    Print("RSI Oversold: ", rsiOversold, " RSI OverBought: ", rsiOverbought, " Rates close for ", symbol, ": ", rates[0].close);

    // Check trading conditions
    if (momentumSum > 1 && rsi < rsiOversold && rates[0].close > ma)
    {
        double tp = bid + (highestHigh - lowestLow);
        double sl = bid - (highestHigh - lowestLow);
        double roundedTP = NormalizeDouble(tp, _Digits);
        double roundedSL = NormalizeDouble(sl, _Digits);
        if (trade.Buy(lotSize, symbol))
        {
            trade.PositionModify(symbol, roundedSL, roundedTP);
            Print("Buka posisi BUY untuk ", symbol);
            Print("TP: ", roundedTP, " SL: ", roundedSL);
            Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
        else
            Print("Error opening buy position for ", symbol, ": ", GetLastError());
    }
    else if (momentumSum < -1 && rsi > rsiOverbought && rates[0].close < ma)
    {
        double tp = ask - (highestHigh - lowestLow);
        double sl = ask + (highestHigh - lowestLow);
        double roundedTP = NormalizeDouble(tp, _Digits);
        double roundedSL = NormalizeDouble(sl, _Digits);
        if (trade.Sell(lotSize, symbol))
        {
            trade.PositionModify(symbol, roundedSL, roundedTP);
            Print("Buka posisi SELL untuk ", symbol);
            Print("TP: ", roundedTP, " SL: ", roundedSL);
            Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
        else
            Print("Error opening sell position for ", symbol, ": ", GetLastError());
    }
    else
    {
        Print("## Kondisi entri tidak terpenuhi untuk ", symbol, " ##");
    }
}
