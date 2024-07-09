#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

input int momentumPeriod = 2; 
input int numberOfCandles = 5;
input double lotSize = 0.01;
input double spreadThreshold = 0.00014;
input int maPeriod = 5; 
input double hedgeLossThreshold = -0.50;

datetime lastCloseTime = 0;
datetime lastRunTime = 0;
int hedgeCount = 0;

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

    double totalProfit = 0;
    int totalPositions = PositionsTotal();
    for (int i = 0; i < totalPositions; i++)
    {
        if (PositionGetTicket(i) != 0)
        {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
        }
    }
    Print("Total profit from all open positions: ", totalProfit);

    if (totalProfit >= 0.75 || totalProfit <= -3.00)
    {
        for (int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if (ticket != 0)
            {
              string symbol = PositionGetString(POSITION_SYMBOL);
              if (symbol == "EURUSD"){
                if (!trade.PositionClose(ticket))
                {
                    Print("Error closing position ", ticket, ": ", GetLastError());
                }
                }
            }
        }
        Print("All positions closed due to total profit reaching or exceeding 0.75");
        return;
    }

    MqlRates rates[];
    int copied = CopyRates("EURUSD", PERIOD_M1, 0, numberOfCandles, rates);
    if (copied < numberOfCandles)
    {
        Print("Error retrieving historical data");
        return;
    }

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
    int maHandle = iMA("EURUSD", PERIOD_M1, period, 0, MODE_SMA, PRICE_CLOSE);
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
    if (PositionSelect("EURUSD"))
    {
        double currentProfit = PositionGetDouble(POSITION_PROFIT);
        Print("## Posisi Sedang Berjalan ## Profit: ", currentProfit);

        if (currentProfit >= 0.75 && hedgeCount == 0)
        {
            if (trade.PositionClose("EURUSD"))
            {
                Print("Posisi ditutup karena profit lebih dari 0.75");
                hedgeCount = 0;
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

    double bid = SymbolInfoDouble("EURUSD", SYMBOL_BID);
    double ask = SymbolInfoDouble("EURUSD", SYMBOL_ASK);
    double spread = NormalizeDouble(ask - bid, _Digits);
    
    Print("Spread :",spread);
    
    if (spread > spreadThreshold)
    {
        Print("## Spread terlalu melebar ##");
        return;
    }

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

    double ma = CalculateMA(maPeriod);
    Print("MA: ", ma);
    Print("Rates close: ", rates[0].close);

    if (momentumSum > 0 && rates[0].close > ma)
    {
        if (PositionSelect("EURUSD"))
        {
            Print("## Posisi sudah terbuka, tidak membuka posisi baru ##");
            return;
        }
        if (trade.Buy(lotSize, "EURUSD"))
        {
            Print("Buka posisi BUY");
            hedgeCount = 0;
            Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
        else
        {
            Print("Error opening buy position: ", GetLastError());
        }
    }
    else if (momentumSum < -0 && rates[0].close < ma)
    {
        if (PositionSelect("EURUSD"))
        {
            Print("## Posisi sudah terbuka, tidak membuka posisi baru ##");
            return;
        }
        if (trade.Sell(lotSize, "EURUSD"))
        {
            Print("Buka posisi SELL");
            hedgeCount = 0;
            Print("Range High: ", highestHigh, " Range Low: ", lowestLow);
        }
        else
        {
            Print("Error opening sell position: ", GetLastError());
        }
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

    if (PositionSelect("EURUSD"))
    {
        double positionType = PositionGetInteger(POSITION_TYPE);
        double hedgeVolume = 0.03;

        if (positionType == POSITION_TYPE_BUY)
        {
            if (trade.Sell(hedgeVolume, "EURUSD"))
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
            if (trade.Buy(hedgeVolume, "EURUSD"))
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
