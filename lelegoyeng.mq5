#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

input int momentumPeriod = 2; 
input int numberOfCandles = 5;
input double lotSize = 0.01;
input double spreadThreshold = 0.35;
input int maPeriod = 5; 
input double hedgeLossThreshold = -1.5;

datetime lastCloseTime = 0;
datetime lastRunTime = 0;
int hedgeCount = 0;  // Variabel untuk melacak jumlah posisi hedging

int OnInit()
{
    return(INIT_SUCCEEDED);
}

void OnTick()
{
    datetime now = TimeCurrent();
    if (now - lastRunTime < PeriodSeconds(PERIOD_M1))
        return; 

    lastRunTime = now;

    // Retrieve historical candles
    MqlRates rates[];
    int copied = CopyRates("XAUUSD", PERIOD_M1, 0, numberOfCandles, rates);
    if (copied < numberOfCandles)
    {
        Print("Error retrieving historical data");
        return;
    }

    // Check if a new 1-minute candle has closed
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

double CalculateMA(int period)
{
    double ma[];
    int maHandle = iMA("XAUUSD", PERIOD_M1, period, 0, MODE_SMA, PRICE_CLOSE);
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
        double currentProfit = PositionGetDouble(POSITION_PROFIT);
        Print("## Posisi Sedang Berjalan ## Profit: ", currentProfit);

        // Check for profit close condition
        if (currentProfit >= 1.5)
        {
            if (trade.PositionClose("XAUUSD"))
            {
                Print("Posisi ditutup karena profit lebih dari 1.5");
                hedgeCount = 0;  // Reset hedge count setelah posisi ditutup dengan profit
            }
            else
            {
                Print("Error menutup posisi: ", GetLastError());
            }
        }
        else if (currentProfit <= hedgeLossThreshold)
        {
            Print("## Memasuki Hedging ##");
            HedgePosition();
        }

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

    // Calculate MA
    double ma = CalculateMA(maPeriod);
    Print("MA: ", ma);
    Print("Rates close: ", rates[0].close);

    // Check trading conditions
    if (momentumSum > 1 && rates[0].close > ma)
    {
        if (trade.Buy(lotSize, "XAUUSD"))
        {
            Print("Buka posisi BUY");
            hedgeCount = 0;  // Reset hedge count setelah posisi baru dibuka
            Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
        else
            Print("Error opening buy position: ", GetLastError());
    }
    else if (momentumSum < -1 && rates[0].close < ma)
    {
        if (trade.Sell(lotSize, "XAUUSD"))
        {
            Print("Buka posisi SELL");
            hedgeCount = 0;  // Reset hedge count setelah posisi baru dibuka
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

void HedgePosition()
{
    if (hedgeCount >= 1)
    {
        Print("## Batas Hedging Tercapai ##");
        return;
    }

    if (PositionSelect("XAUUSD"))
    {
        double positionType = PositionGetInteger(POSITION_TYPE);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double hedgeVolume = volume * 2;  // Dua kali lipat lot size

        if (positionType == POSITION_TYPE_BUY)
        {
            // Open Sell position
            if (trade.Sell(hedgeVolume, "XAUUSD"))
            {
                Print("Hedging dengan posisi SELL dengan volume ", hedgeVolume);
                hedgeCount++;
            }
            else
            {
                Print("Error membuka posisi sell untuk hedging: ", GetLastError());
            }
        }
        else if (positionType == POSITION_TYPE_SELL)
        {
            // Open Buy position
            if (trade.Buy(hedgeVolume, "XAUUSD"))
            {
                Print("Hedging dengan posisi BUY dengan volume ", hedgeVolume);
                hedgeCount++;
            }
            else
            {
                Print("Error membuka posisi buy untuk hedging: ", GetLastError());
            }
        }
    }
}
