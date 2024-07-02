#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#include <Trade\Trade.mqh>
CTrade trade;

input int momentumPeriod = 2; 
input int numberOfCandles = 5;
input double lotSize = 0.01;
input double spreadThreshold = 0.40;
input int maPeriod = 5; 
input double hedgeLossThreshold = -1.20;
input double totalProfitThreshold = 2.00; // New input for total profit threshold

datetime lastCloseTime = 0;
datetime lastRunTime = 0;
int openPositions = 0; // Variabel untuk melacak jumlah posisi terbuka

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

    // Check if a new 5-minute candle has closed
    if (rates[0].time != lastCloseTime)
    {
        lastCloseTime = rates[0].time;
        Bot(rates);
    }

    // Check and close positions one by one
    CheckAndClosePositions();
}

void CheckAndClosePositions()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if (PositionSelect(i))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double profit = PositionGetDouble(POSITION_PROFIT);
            
            // Close position if profit meets threshold
            if (profit >= totalProfitThreshold)
            {
                ulong ticket = PositionGetInteger(POSITION_TICKET);
                Print("## Menutup posisi ", ticket, " karena profit mencapai ", totalProfitThreshold);
                trade.PositionClose(ticket);
                openPositions--; // Kurangi jumlah posisi terbuka
            }
        }
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
    openPositions = GetOpenPositionsCount("XAUUSD");
    if (PositionSelect("XAUUSD"))
    {
        double currentProfit = PositionGetDouble(POSITION_PROFIT);
        Print("## Posisi Sedang Berjalan ## Profit: ", currentProfit);

        // Check for hedging condition
        if (currentProfit <= hedgeLossThreshold)
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
        if (openPositions >= 3)
        {
            Print("## Mencapai batas maksimum posisi terbuka ##");
            return;
        }

        if (trade.Buy(lotSize, "XAUUSD"))
        {
            openPositions++; // Tambah posisi terbuka
            Print("Buka posisi BUY");
        }
        else
            Print("Error opening buy position: ", GetLastError());
    }
    else if (momentumSum < -1 && rates[0].close < ma)
    {
        if (openPositions >= 3)
        {
            Print("## Mencapai batas maksimum posisi terbuka ##");
            return;
        }

        if (trade.Sell(lotSize, "XAUUSD"))
        {
            openPositions++; // Tambah posisi terbuka
            Print("Buka posisi SELL");
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
    if (PositionSelect("XAUUSD"))
    {
        double positionType = PositionGetInteger(POSITION_TYPE);
        double volume = PositionGetDouble(POSITION_VOLUME);
        
        if (positionType == POSITION_TYPE_BUY)
        {
            // Open Sell position
            if (trade.Sell(volume, "XAUUSD"))
            {
                openPositions--; // Kurangi posisi terbuka setelah hedging
                Print("Hedging dengan posisi SELL");
            }
            else
            {
                Print("Error membuka posisi sell untuk hedging: ", GetLastError());
            }
        }
        else if (positionType == POSITION_TYPE_SELL)
        {
            // Open Buy position
            if (trade.Buy(volume, "XAUUSD"))
            {
                openPositions--; // Kurangi posisi terbuka setelah hedging
                Print("Hedging dengan posisi BUY");
            }
            else
            {
                Print("Error membuka posisi buy untuk hedging: ", GetLastError());
            }
        }
    }
}

int GetOpenPositionsCount(string symbol)
{
    int count = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (PositionSelect(i) && PositionGetString(POSITION_SYMBOL) == symbol)
            count++;
    }
    return count;
}
