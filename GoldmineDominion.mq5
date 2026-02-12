//+------------------------------------------------------------------+
//|                                         GoldmineDominion.mq5     |
//|     Goldmine Dominion – One EA for Gold or Silver                 |
//|     Reversal + OB + FVG + session sweeps | Layered TP, BE 25/30  |
//|     SELL BE capped. Close at S/R (M5/M15/M30) + tap & reverse.   |
//+------------------------------------------------------------------+
#property copyright "Goldmine Dominion"
#property link      ""
#property version   "1.00"
#property description "Goldmine Dominion. Attach to ONE chart per symbol (e.g. XAUUSD M5 only) to avoid double BUY+SELL."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CPositionInfo position;
CAccountInfo account;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Risk ==="
input double RiskPercent = 5.0;              // Risk per trade (%) – default 5%
input double MaxTotalRisk = 5.0;             // Max total risk (%)
input bool UseBreakEven = true;               // Enable break-even
input double BreakEvenPips = 25.0;            // BE trigger (pips) – Gold
input double BreakEvenPips_Silver = 25.0;    // BE trigger (pips) – Silver
input double SELL_BE_CapPips = 30.0;         // SELL BE capped at (pips) – never move BE beyond this for SELL

input group "=== Take Profit (same as Blueprint/Nexus) ==="
input double TP1_Pips = 25.0;                // TP1 (pips) – Close 15%
input double TP1_Percent = 15.0;             // % at TP1
input double TP2_Pips = 50.0;                // TP2 (pips) – Close 15%
input double TP2_Percent = 15.0;             // % at TP2
input double TP3_Pips = 80.0;                // TP3 (pips) – Close 25%
input double TP3_Percent = 25.0;             // % at TP3
input double TP4_Pips = 150.0;               // TP4 (pips) – Close 25%, leave runner
input double TP4_Percent = 25.0;             // % at TP4
input double TP5_Pips = 300.0;               // TP5 (pips) – Full close runner
input double RunnerSizePercent = 15.0;       // % runner

input group "=== Reversal: Close at S/R (M5, M15, M30) ==="
input bool UseM5_SR = true;                  // Use M5 for close-at-S/R
input bool UseM15_SR = true;                  // Use M15 for close-at-S/R
input bool UseM30_SR = true;                  // Use M30 for close-at-S/R
input int SR_SwingBars = 10;                  // Swing lookback (bars) per TF
input double SR_CloseTolerancePips = 5.0;    // Candle "closed at" S/R within (pips)
input double KeyCandleMinBodyPips = 3.0;    // Key reversal candle min body (pips)
input double TapZoneTolerancePips = 8.0;     // Tap-and-reverse: zone tolerance (pips)
input bool RequireTapAndReverse = true;      // Require tap-again then reverse (recommended)
input bool RequireCloseAtLevel = true;       // Entry only when candle CLOSED at/through level (not wick)
input bool RequireEngulfing = false;         // Require engulfing candle for reversal (stronger confirmation)

input group "=== BOS / ChoCH (closure-based structure) ==="
input bool UseBOS_ChoCH = true;              // Use Break of Structure / Change of Character
input int StructureSwingBars = 8;            // Swing lookback for BOS/ChoCH (M15)
input bool RequireChoCHForReversal = false;   // false = never block (take all setups); true = only after ChoCH
input int ChoCH_MaxBarsAgo = 30;             // ChoCH valid for N bars (M15) then allow any

input group "=== Session open/close retest (Dominion-only) ==="
input bool UseSessionRetest = true;          // Trade retests of Asia/London/NY open or close levels
input bool UseAsiaOpenClose = true;          // Asia session open (00) / close (08) levels
input bool UseHongKongOpen = true;           // Hong Kong open (~01 server) level
input bool UseLondonOpenClose = true;        // London open (08) / close (16) levels
input bool UseNYOpenClose = true;            // NY open (14) / close (22) levels
input double SessionRetestTolerancePips = 8.0; // Price within (pips) of session level to count as retest
input int SessionHourOffset = 0;             // Server hour offset (0=GMT; 2=GMT+2 for some brokers)
input bool UseSessionHighLowRetest = true;   // Also retest session high/low (not just open/close price)

input group "=== Trend Lines (work with reversal) ==="
input bool UseTrendLines = true;             // Detect trend lines (swing highs/lows) and add as zones
input ENUM_TIMEFRAMES TrendLine_TF = PERIOD_H1;  // Main timeframe for trend line detection
input int TrendLine_Lookback = 100;          // Bars to look back for swing pivots (main TF)
input bool UseM1_TrendLine = true;           // Also detect M1 trend line (liquidity reversal off 1M TL)
input int TrendLine_M1_Lookback = 80;       // Bars for M1 trend line (recent structure)
input int TrendLine_MinTouches = 2;          // Min touches for valid trend line (pivot left/right)
input double TrendLine_TouchTolerancePips = 5.0; // Price within (pips) of TL to count as at level

input group "=== Higher-TF Range (pinpoint range high/low) ==="
input bool UseHTFRange = true;              // Pinpoint range on higher TF (range high = resistance, low = support)
input ENUM_TIMEFRAMES Range_TF = PERIOD_H1;  // Timeframe for range (H1 or H4)
input int Range_SwingBars = 20;              // Swing lookback for range high/low
input double Range_ZoneTolerancePips = 10.0;  // Zone width at range boundary (pips)

input group "=== Order Block / FVG (work with reversal + session) ==="
input bool UseOB = true;                     // Detect order blocks (M5/M15/M30) as reversal zones
input bool UseFVG = true;                    // Detect FVG (M5/M15/M30) as reversal zones
input int OB_Lookback = 20;                  // OB lookback (bars)
input double OB_VolumeMultiplier = 1.2;      // OB: volume above average
input int OB_ATR_Period = 14;                // OB: ATR period
input double OB_ATR_Multiplier = 0.3;        // OB: min body size (ATR mult)
input double FVG_MinSizePips = 5.0;         // FVG min size (pips)
input int FVG_Lookback = 50;                 // FVG bars to scan per TF
input bool FVG_FirstIsStrongest = true;     // First FVG in move = main direction; higher/lower = 50% rejection

input group "=== Stops ==="
input double SL_Pips_Gold = 25.0;            // SL (pips) – Gold
input double SL_Pips_Silver = 35.0;          // SL (pips) – Silver

input group "=== License ==="
input bool EnableLicenseCheck = true;
input string LicenseServerURL = "https://mt5-license-server-production.up.railway.app";
input string LicenseKey = "";
input bool UseRemoteValidation = true;
input int LicenseCheckTimeout = 5;
input string UserName = "";

input group "=== General ==="
input int MagicNumber = 124005;              // Dominion – unique
input string TradeComment = "Goldmine Dominion";
input int Slippage = 15;

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
double pipValue = 0.1;                       // Set in OnInit (0.1 Gold, 0.01 Silver)
int symbolDigits = 2;
datetime lastBarTime = 0;
datetime lastBarTimeM15 = 0;
datetime initTime = 0;

// Reversal zones: level, time first seen, key-candle time, isSupport
struct ReversalZone {
    double level;
    double bottom;   // zone bottom (level - tolerance)
    double top;      // zone top (level + tolerance)
    datetime timeFirst;
    datetime timeKeyCandle;
    bool isSupport;
    bool keyCandleSet;
    ENUM_TIMEFRAMES tf;
};
ReversalZone reversalZones[];
int reversalZonesMax = 50;

// Tracking arrays (same pattern as Nexus)
bool tp1Hit[]; bool tp2Hit[]; bool tp3Hit[]; bool tp4Hit[]; bool tp5Hit[];
double tp1HitPrice[];
int partialCloseLevel[];
double originalVolume[];

// Session open/close levels (Dominion distinctive) – server hour
double sessionAsiaOpenPrice = 0, sessionAsiaClosePrice = 0;
double sessionHongKongOpenPrice = 0;
double sessionLondonOpenPrice = 0, sessionLondonClosePrice = 0;
double sessionNYOpenPrice = 0, sessionNYClosePrice = 0;
double sessionAsiaHigh = 0, sessionAsiaLow = 0;
double sessionLondonHigh = 0, sessionLondonLow = 0;
double sessionNYHigh = 0, sessionNYLow = 0;
int lastSessionHour = -1;

// BOS/ChoCH – closure-based structure (Dominion)
double lastSwingHigh_M15 = 0, lastSwingLow_M15 = 0;
int trend_M15 = 0;           // 1=bullish, -1=bearish, 0=range
int barsSinceChoCH_Bull = 999; // bars since last ChoCH bullish (close above structure)
int barsSinceChoCH_Bear = 999;

// Trend lines (HTF + M1 swing highs/lows – support/resistance lines)
struct TrendLine {
    double price1, price2;
    int bar1, bar2;
    bool isSupport;
    bool isActive;
    ENUM_TIMEFRAMES tf;
};
TrendLine trendLines[];
int trendLinesMax = 40;

// Higher-TF range (pinpoint range boundaries)
double rangeHigh_HTF = 0, rangeLow_HTF = 0;
datetime lastRangeBarTime = 0;

//+------------------------------------------------------------------+
//| License (same as Nexus)                                          |
//+------------------------------------------------------------------+
bool ValidateLicenseRemote(string eaName) {
    if(StringLen(LicenseServerURL) == 0) return false;
    long accountNumber = account.Login();
    string json = "{\"accountNumber\":\"" + IntegerToString(accountNumber) + "\",";
    json += "\"broker\":\"" + account.Server() + "\",";
    json += "\"eaName\":\"" + eaName + "\"";
    if(StringLen(LicenseKey) > 0) json += ",\"licenseKey\":\"" + LicenseKey + "\"";
    json += "}";
    char post[]; char result[]; char data[];
    StringToCharArray(json, data, 0, StringLen(json));
    ArrayResize(post, ArraySize(data)); ArrayCopy(post, data);
    string url = LicenseServerURL;
    if(StringFind(url, "http") != 0) url = "https://" + url;
    if(StringFind(url, "/validate") < 0) url += (StringFind(url, "/", StringLen(url)-1) < 0 ? "/" : "") + "validate";
    string headers = "Content-Type: application/json\r\n";
    int res = WebRequest("POST", url, NULL, NULL, LicenseCheckTimeout*1000, post, 0, result, headers);
    if(res != 200) return false;
    return (StringFind(CharArrayToString(result), "\"valid\":true") >= 0);
}
bool CheckLicense() {
    if(!EnableLicenseCheck) return true;
    if(UseRemoteValidation && ValidateLicenseRemote("Goldmine Dominion")) return true;
    if(StringLen(LicenseKey) > 0) return true;
    return false;
}

//+------------------------------------------------------------------+
//| Pip value for symbol                                             |
//+------------------------------------------------------------------+
double GetPipValue(string sym) {
    string u; StringToUpper(sym); u = sym;
    if(StringFind(u, "XAG") >= 0 || StringFind(u, "SILVER") >= 0) return 0.01;
    return 0.1;
}

//+------------------------------------------------------------------+
//| Update session open/close levels (Asia, HK, London, NY) – server hour |
//+------------------------------------------------------------------+
void UpdateSessionOpenCloseLevels() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int h = (dt.hour + SessionHourOffset + 24) % 24;
    double closePrev = iClose(_Symbol, PERIOD_M15, 1);
    double high0 = iHigh(_Symbol, PERIOD_M15, 0);
    double low0 = iLow(_Symbol, PERIOD_M15, 0);

    if(h != lastSessionHour) {
        if(h == 0) {
            if(UseAsiaOpenClose) sessionAsiaOpenPrice = closePrev;
            sessionAsiaHigh = 0; sessionAsiaLow = 0;
        }
        if(h == 1 && UseHongKongOpen) sessionHongKongOpenPrice = closePrev;
        if(h == 8) {
            if(UseAsiaOpenClose) sessionAsiaClosePrice = closePrev;
            if(UseLondonOpenClose) sessionLondonOpenPrice = closePrev;
            sessionLondonHigh = 0; sessionLondonLow = 0;
        }
        if(h == 16 && UseLondonOpenClose) sessionLondonClosePrice = closePrev;
        if(h == 14) {
            if(UseNYOpenClose) sessionNYOpenPrice = closePrev;
            sessionNYHigh = 0; sessionNYLow = 0;
        }
        if(h == 22 && UseNYOpenClose) sessionNYClosePrice = closePrev;
        lastSessionHour = h;
    }
    if(UseSessionHighLowRetest) {
        if(h >= 0 && h < 8) {
            if(sessionAsiaHigh == 0) { sessionAsiaHigh = high0; sessionAsiaLow = low0; }
            else { sessionAsiaHigh = MathMax(sessionAsiaHigh, high0); sessionAsiaLow = MathMin(sessionAsiaLow, low0); }
        } else if(h >= 8 && h < 16) {
            if(sessionLondonHigh == 0) { sessionLondonHigh = high0; sessionLondonLow = low0; }
            else { sessionLondonHigh = MathMax(sessionLondonHigh, high0); sessionLondonLow = MathMin(sessionLondonLow, low0); }
        } else if(h >= 14 && h < 22) {
            if(sessionNYHigh == 0) { sessionNYHigh = high0; sessionNYLow = low0; }
            else { sessionNYHigh = MathMax(sessionNYHigh, high0); sessionNYLow = MathMin(sessionNYLow, low0); }
        }
    }
}

//+------------------------------------------------------------------+
//| Check session retest entry (price at session open/close or high/low + reversal candle) |
//+------------------------------------------------------------------+
bool CheckSessionRetestEntry(bool &isBuy) {
    if(!UseSessionRetest) return false;
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double tol = SessionRetestTolerancePips * pipValue;
    double close[]; double open[];
    ArraySetAsSeries(close, true); ArraySetAsSeries(open, true);
    if(CopyClose(_Symbol, PERIOD_M5, 1, 3, close) < 3 || CopyOpen(_Symbol, PERIOD_M5, 1, 3, open) < 3) return false;
    bool bullishCandle = (close[0] > open[0]);
    bool bearishCandle = (close[0] < open[0]);
    if(RequireEngulfing) {
        bullishCandle = bullishCandle && (close[0] > open[1] && open[0] < close[1]);
        bearishCandle = bearishCandle && (close[0] < open[1] && open[0] > close[1]);
    }
    // Closure at level: BUY only if candle closed at/above support; SELL only if closed at/below resistance
    bool choCHOkBuy = (!RequireChoCHForReversal) || (barsSinceChoCH_Bull <= ChoCH_MaxBarsAgo);
    bool choCHOkSell = (!RequireChoCHForReversal) || (barsSinceChoCH_Bear <= ChoCH_MaxBarsAgo);

    if(UseSessionHighLowRetest) {
        if(sessionAsiaLow > 0 && MathAbs(bid - sessionAsiaLow) <= tol && bullishCandle && choCHOkBuy) {
            if(RequireCloseAtLevel && close[0] < sessionAsiaLow - tol) return false;
            isBuy = true; Print("*** DOMINION: Session retest BUY at Asia Low (close at level) ", sessionAsiaLow, " ***"); return true;
        }
        if(sessionAsiaHigh > 0 && MathAbs(bid - sessionAsiaHigh) <= tol && bearishCandle && choCHOkSell) {
            if(RequireCloseAtLevel && close[0] > sessionAsiaHigh + tol) return false;
            isBuy = false; Print("*** DOMINION: Session retest SELL at Asia High (close at level) ", sessionAsiaHigh, " ***"); return true;
        }
        if(sessionLondonLow > 0 && MathAbs(bid - sessionLondonLow) <= tol && bullishCandle && choCHOkBuy) {
            if(RequireCloseAtLevel && close[0] < sessionLondonLow - tol) return false;
            isBuy = true; Print("*** DOMINION: Session retest BUY at London Low (close at level) ", sessionLondonLow, " ***"); return true;
        }
        if(sessionLondonHigh > 0 && MathAbs(bid - sessionLondonHigh) <= tol && bearishCandle && choCHOkSell) {
            if(RequireCloseAtLevel && close[0] > sessionLondonHigh + tol) return false;
            isBuy = false; Print("*** DOMINION: Session retest SELL at London High (close at level) ", sessionLondonHigh, " ***"); return true;
        }
        if(sessionNYLow > 0 && MathAbs(bid - sessionNYLow) <= tol && bullishCandle && choCHOkBuy) {
            if(RequireCloseAtLevel && close[0] < sessionNYLow - tol) return false;
            isBuy = true; Print("*** DOMINION: Session retest BUY at NY Low (close at level) ", sessionNYLow, " ***"); return true;
        }
        if(sessionNYHigh > 0 && MathAbs(bid - sessionNYHigh) <= tol && bearishCandle && choCHOkSell) {
            if(RequireCloseAtLevel && close[0] > sessionNYHigh + tol) return false;
            isBuy = false; Print("*** DOMINION: Session retest SELL at NY High (close at level) ", sessionNYHigh, " ***"); return true;
        }
    }
    if(UseAsiaOpenClose) {
        if(sessionAsiaOpenPrice > 0 && MathAbs(bid - sessionAsiaOpenPrice) <= tol) {
            if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionAsiaOpenPrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at Asia Open (close at level) ***"); return true; }
            if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionAsiaOpenPrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at Asia Open (close at level) ***"); return true; }
        }
        if(sessionAsiaClosePrice > 0 && MathAbs(bid - sessionAsiaClosePrice) <= tol) {
            if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionAsiaClosePrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at Asia Close (close at level) ***"); return true; }
            if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionAsiaClosePrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at Asia Close (close at level) ***"); return true; }
        }
    }
    if(UseHongKongOpen && sessionHongKongOpenPrice > 0 && MathAbs(bid - sessionHongKongOpenPrice) <= tol) {
        if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionHongKongOpenPrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at HK Open (close at level) ***"); return true; }
        if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionHongKongOpenPrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at HK Open (close at level) ***"); return true; }
    }
    if(UseLondonOpenClose) {
        if(sessionLondonOpenPrice > 0 && MathAbs(bid - sessionLondonOpenPrice) <= tol) {
            if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionLondonOpenPrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at London Open (close at level) ***"); return true; }
            if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionLondonOpenPrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at London Open (close at level) ***"); return true; }
        }
        if(sessionLondonClosePrice > 0 && MathAbs(bid - sessionLondonClosePrice) <= tol) {
            if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionLondonClosePrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at London Close (close at level) ***"); return true; }
            if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionLondonClosePrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at London Close (close at level) ***"); return true; }
        }
    }
    if(UseNYOpenClose) {
        if(sessionNYOpenPrice > 0 && MathAbs(bid - sessionNYOpenPrice) <= tol) {
            if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionNYOpenPrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at NY Open (close at level) ***"); return true; }
            if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionNYOpenPrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at NY Open (close at level) ***"); return true; }
        }
        if(sessionNYClosePrice > 0 && MathAbs(bid - sessionNYClosePrice) <= tol) {
            if(bullishCandle && choCHOkBuy && (!RequireCloseAtLevel || close[0] >= sessionNYClosePrice - tol)) { isBuy = true; Print("*** DOMINION: Session retest BUY at NY Close (close at level) ***"); return true; }
            if(bearishCandle && choCHOkSell && (!RequireCloseAtLevel || close[0] <= sessionNYClosePrice + tol)) { isBuy = false; Print("*** DOMINION: Session retest SELL at NY Close (close at level) ***"); return true; }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| BOS/ChoCH – update structure from M15 closures (where closures are) |
//+------------------------------------------------------------------+
void UpdateBOS_ChoCH() {
    if(!UseBOS_ChoCH) return;
    int lb = StructureSwingBars;
    int bars = iBars(_Symbol, PERIOD_M15);
    if(bars < lb + 3) return;
    double high[]; double low[]; double close[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(close, true);
    if(CopyHigh(_Symbol, PERIOD_M15, 2, lb, high) < lb || CopyLow(_Symbol, PERIOD_M15, 2, lb, low) < lb || CopyClose(_Symbol, PERIOD_M15, 1, 2, close) < 2) return;
    double swingHigh = high[0], swingLow = low[0];
    for(int i = 1; i < lb; i++) {
        if(high[i] > swingHigh) swingHigh = high[i];
        if(low[i] < swingLow) swingLow = low[i];
    }
    double c1 = close[0];  // last closed M15 candle (index 0 = most recent)
    if(lastSwingHigh_M15 > 0 && lastSwingLow_M15 > 0) {
        if(c1 > lastSwingHigh_M15) {
            if(trend_M15 <= 0) {
                trend_M15 = 1;
                barsSinceChoCH_Bull = 0;
                barsSinceChoCH_Bear = 999;
                Print("*** DOMINION: ChoCH BULLISH (close above structure ", lastSwingHigh_M15, ") ***");
            }
        } else if(c1 < lastSwingLow_M15) {
            if(trend_M15 >= 0) {
                trend_M15 = -1;
                barsSinceChoCH_Bear = 0;
                barsSinceChoCH_Bull = 999;
                Print("*** DOMINION: ChoCH BEARISH (close below structure ", lastSwingLow_M15, ") ***");
            }
        }
    }
    lastSwingHigh_M15 = swingHigh;
    lastSwingLow_M15 = swingLow;
    if(barsSinceChoCH_Bull < 999) barsSinceChoCH_Bull++;
    if(barsSinceChoCH_Bear < 999) barsSinceChoCH_Bear++;
}

//+------------------------------------------------------------------+
//| Get swing low (support) on TF                                     |
//+------------------------------------------------------------------+
double GetSwingLow(ENUM_TIMEFRAMES tf, int barIdx, int lookback) {
    double low[]; ArraySetAsSeries(low, true);
    if(CopyLow(_Symbol, tf, barIdx, lookback, low) < lookback) return 0;
    int minIdx = 0;
    for(int i = 1; i < lookback; i++)
        if(low[i] < low[minIdx]) minIdx = i;
    return low[minIdx];
}
double GetSwingHigh(ENUM_TIMEFRAMES tf, int barIdx, int lookback) {
    double high[]; ArraySetAsSeries(high, true);
    if(CopyHigh(_Symbol, tf, barIdx, lookback, high) < lookback) return 0;
    int maxIdx = 0;
    for(int i = 1; i < lookback; i++)
        if(high[i] > high[maxIdx]) maxIdx = i;
    return high[maxIdx];
}

//+------------------------------------------------------------------+
//| Check if bar closed at level (within tolerance)                   |
//+------------------------------------------------------------------+
bool BarClosedAtLevel(ENUM_TIMEFRAMES tf, int barIdx, double level, double tolerance) {
    double close[]; ArraySetAsSeries(close, true);
    if(CopyClose(_Symbol, tf, barIdx, 2, close) < 2) return false;
    return (MathAbs(close[0] - level) <= tolerance);
}

//+------------------------------------------------------------------+
//| Engulfing: last closed M5 candle body engulfs previous candle body |
//+------------------------------------------------------------------+
bool IsEngulfingM5(bool wantBullish) {
    double close[], open[];
    ArraySetAsSeries(close, true); ArraySetAsSeries(open, true);
    if(CopyClose(_Symbol, PERIOD_M5, 1, 3, close) < 3 || CopyOpen(_Symbol, PERIOD_M5, 1, 3, open) < 3) return false;
    if(wantBullish)
        return (close[0] > open[0] && close[0] > open[1] && open[0] < close[1]);
    return (close[0] < open[0] && close[0] < open[1] && open[0] > close[1]);
}

//+------------------------------------------------------------------+
//| Key candle: first strong reversal candle (e.g. bullish off support) |
//+------------------------------------------------------------------+
bool IsKeyReversalCandle(ENUM_TIMEFRAMES tf, int barIdx, bool wantBullish, double minBodyPips) {
    double o[], h[], l[], c[];
    ArraySetAsSeries(o, true); ArraySetAsSeries(h, true); ArraySetAsSeries(l, true); ArraySetAsSeries(c, true);
    if(CopyOpen(_Symbol, tf, barIdx, 2, o) < 2 || CopyHigh(_Symbol, tf, barIdx, 2, h) < 2 ||
       CopyLow(_Symbol, tf, barIdx, 2, l) < 2 || CopyClose(_Symbol, tf, barIdx, 2, c) < 2) return false;
    double body = MathAbs(c[1] - o[1]);
    if(body < minBodyPips * pipValue) return false;
    if(wantBullish) return (c[1] > o[1]);
    return (c[1] < o[1]);
}

//+------------------------------------------------------------------+
//| Detect trend lines on a given TF (connect swing highs/lows, project to now) |
//+------------------------------------------------------------------+
void DetectTrendLinesOnTF(ENUM_TIMEFRAMES tf, int lookback, bool clearFirst) {
    if(clearFirst) ArrayResize(trendLines, 0);
    int bars = iBars(_Symbol, tf);
    if(bars < lookback || lookback < TrendLine_MinTouches + 5) return;
    double high[], low[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
    if(CopyHigh(_Symbol, tf, 0, lookback, high) < lookback) return;
    if(CopyLow(_Symbol, tf, 0, lookback, low) < lookback) return;

    int swingHighBars[], swingLowBars[];
    double swingHighPrices[], swingLowPrices[];
    ArrayResize(swingHighBars, 0); ArrayResize(swingLowBars, 0);
    ArrayResize(swingHighPrices, 0); ArrayResize(swingLowPrices, 0);
    int k = TrendLine_MinTouches;
    for(int i = k; i < lookback - k; i++) {
        bool isSwingHigh = true;
        for(int j = 1; j <= k; j++) {
            if(high[i] <= high[i-j] || high[i] <= high[i+j]) { isSwingHigh = false; break; }
        }
        if(isSwingHigh) {
            int n = ArraySize(swingHighBars);
            ArrayResize(swingHighBars, n+1); ArrayResize(swingHighPrices, n+1);
            swingHighBars[n] = i; swingHighPrices[n] = high[i];
        }
        bool isSwingLow = true;
        for(int j = 1; j <= k; j++) {
            if(low[i] >= low[i-j] || low[i] >= low[i+j]) { isSwingLow = false; break; }
        }
        if(isSwingLow) {
            int n = ArraySize(swingLowBars);
            ArrayResize(swingLowBars, n+1); ArrayResize(swingLowPrices, n+1);
            swingLowBars[n] = i; swingLowPrices[n] = low[i];
        }
    }
    int recentBars = MathMin(50, lookback);
    double recentHigh = high[ArrayMaximum(high, 0, recentBars)];
    double recentLow = low[ArrayMinimum(low, 0, recentBars)];
    double rangeExtend = 200.0 * pipValue;

    int nLow = ArraySize(swingLowBars);
    for(int a = 0; a < nLow && ArraySize(trendLines) < trendLinesMax; a++) {
        for(int b = a + 1; b < nLow; b++) {
            int bar1 = swingLowBars[a], bar2 = swingLowBars[b];
            if(bar2 - bar1 < 3) continue;
            double p1 = swingLowPrices[a], p2 = swingLowPrices[b];
            double slope = (p2 - p1) / (double)(bar2 - bar1);
            double levelAt0 = p1 + slope * (0 - bar1);
            if(levelAt0 < recentLow - rangeExtend || levelAt0 > recentHigh + rangeExtend) continue;
            int sz = ArraySize(trendLines);
            ArrayResize(trendLines, sz+1);
            trendLines[sz].price1 = p1; trendLines[sz].price2 = p2;
            trendLines[sz].bar1 = bar1; trendLines[sz].bar2 = bar2;
            trendLines[sz].isSupport = true; trendLines[sz].isActive = true;
            trendLines[sz].tf = tf;
            if(sz >= 14) break;
        }
    }
    int nHigh = ArraySize(swingHighBars);
    for(int a = 0; a < nHigh && ArraySize(trendLines) < trendLinesMax; a++) {
        for(int b = a + 1; b < nHigh; b++) {
            int bar1 = swingHighBars[a], bar2 = swingHighBars[b];
            if(bar2 - bar1 < 3) continue;
            double p1 = swingHighPrices[a], p2 = swingHighPrices[b];
            double slope = (p2 - p1) / (double)(bar2 - bar1);
            double levelAt0 = p1 + slope * (0 - bar1);
            if(levelAt0 < recentLow - rangeExtend || levelAt0 > recentHigh + rangeExtend) continue;
            int sz = ArraySize(trendLines);
            ArrayResize(trendLines, sz+1);
            trendLines[sz].price1 = p1; trendLines[sz].price2 = p2;
            trendLines[sz].bar1 = bar1; trendLines[sz].bar2 = bar2;
            trendLines[sz].isSupport = false; trendLines[sz].isActive = true;
            trendLines[sz].tf = tf;
            if(sz >= 14) break;
        }
    }
}

//+------------------------------------------------------------------+
//| Detect trend lines (main TF + M1 for liquidity reversal)         |
//+------------------------------------------------------------------+
void DetectTrendLines() {
    DetectTrendLinesOnTF(TrendLine_TF, TrendLine_Lookback, true);
    if(UseM1_TrendLine)
        DetectTrendLinesOnTF(PERIOD_M1, TrendLine_M1_Lookback, false);
}

//+------------------------------------------------------------------+
//| Add trend line levels as reversal zones (tap-and-reverse at TL)  |
//+------------------------------------------------------------------+
void AddTrendLineZones() {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double tol = TrendLine_TouchTolerancePips * pipValue;
    for(int i = 0; i < ArraySize(trendLines); i++) {
        if(!trendLines[i].isActive) continue;
        int b1 = trendLines[i].bar1, b2 = trendLines[i].bar2;
        if(b2 == b1) continue;
        double slope = (trendLines[i].price2 - trendLines[i].price1) / (double)(b2 - b1);
        double levelAt0 = trendLines[i].price1 + slope * (0 - b1);
        if(MathAbs(bid - levelAt0) <= tol * 2)
            AddOrUpdateZone(levelAt0, trendLines[i].isSupport, trendLines[i].tf, true);
    }
}

//+------------------------------------------------------------------+
//| Higher-TF range: pinpoint swing high (resistance) / swing low (support) |
//+------------------------------------------------------------------+
void UpdateHTFRange() {
    int bars = iBars(_Symbol, Range_TF);
    if(bars < Range_SwingBars + 2) return;
    double high[], low[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
    if(CopyHigh(_Symbol, Range_TF, 1, Range_SwingBars + 2, high) < Range_SwingBars + 2) return;
    if(CopyLow(_Symbol, Range_TF, 1, Range_SwingBars + 2, low) < Range_SwingBars + 2) return;
    double sh = high[0], sl = low[0];
    for(int i = 1; i < Range_SwingBars; i++) {
        if(high[i] > sh) sh = high[i];
        if(low[i] < sl) sl = low[i];
    }
    rangeHigh_HTF = sh;
    rangeLow_HTF = sl;
}

//+------------------------------------------------------------------+
//| Add range high/low as reversal zones                              |
//+------------------------------------------------------------------+
void AddRangeZones() {
    if(rangeHigh_HTF <= 0 || rangeLow_HTF <= 0 || rangeHigh_HTF <= rangeLow_HTF) return;
    double zoneWid = Range_ZoneTolerancePips * pipValue;
    AddOrUpdateZoneEx(rangeLow_HTF - zoneWid, rangeLow_HTF + zoneWid, true, Range_TF, true);
    AddOrUpdateZoneEx(rangeHigh_HTF - zoneWid, rangeHigh_HTF + zoneWid, false, Range_TF, true);
}

//+------------------------------------------------------------------+
//| Order blocks: detect on M5/M15/M30, add as reversal zones       |
//+------------------------------------------------------------------+
void UpdateOrderBlocks() {
    if(!UseOB) return;
    ENUM_TIMEFRAMES tfs[];
    int nTf = 0;
    if(UseM5_SR)  { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M5;  }
    if(UseM15_SR) { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M15; }
    if(UseM30_SR) { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M30; }
    int scanBars = 5;
    for(int t = 0; t < nTf; t++) {
        ENUM_TIMEFRAMES tf = tfs[t];
        int bars = iBars(_Symbol, tf);
        if(bars < OB_Lookback + scanBars + 2) continue;
        double high[], low[], close[], open[];
        ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
        ArraySetAsSeries(close, true); ArraySetAsSeries(open, true);
        if(CopyHigh(_Symbol, tf, 1, scanBars + OB_Lookback + 2, high) < scanBars + OB_Lookback + 2) continue;
        if(CopyLow(_Symbol, tf, 1, scanBars + OB_Lookback + 2, low) < scanBars + OB_Lookback + 2) continue;
        if(CopyClose(_Symbol, tf, 1, scanBars + OB_Lookback + 2, close) < scanBars + OB_Lookback + 2) continue;
        if(CopyOpen(_Symbol, tf, 1, scanBars + OB_Lookback + 2, open) < scanBars + OB_Lookback + 2) continue;
        long vol[];
        ArraySetAsSeries(vol, true);
        if(CopyTickVolume(_Symbol, tf, 1, scanBars + OB_Lookback + 2, vol) < scanBars + OB_Lookback + 2) continue;
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(iATR(_Symbol, tf, OB_ATR_Period), 0, 1, scanBars + OB_Lookback + 2, atr) < scanBars + OB_Lookback + 2) continue;
        double avgVol = 0;
        for(int i = 1; i <= OB_Lookback; i++) avgVol += (double)vol[i];
        avgVol /= (double)OB_Lookback;
        if(avgVol <= 0) continue;
        for(int bar = 0; bar < scanBars; bar++) {
            int b = bar + 1;
            if(b + 1 >= ArraySize(low)) continue;
            bool isBull = (close[bar] > open[bar]);
            bool hasVol = ((double)vol[bar] > avgVol * OB_VolumeMultiplier);
            bool hasBody = isBull ? ((close[bar]-open[bar]) > atr[bar]*OB_ATR_Multiplier) : ((open[bar]-close[bar]) > atr[bar]*OB_ATR_Multiplier);
            bool breaksLow = (low[bar] < low[b]);
            bool breaksHigh = (high[bar] > high[b]);
            if(isBull && breaksLow && (hasVol || hasBody))
                AddOrUpdateZoneEx(low[bar], high[bar], true, tf, true);
            if(!isBull && breaksHigh && (hasVol || hasBody))
                AddOrUpdateZoneEx(low[bar], high[bar], false, tf, true);
        }
    }
}

// FVG zone for first-vs-rejection logic
struct FVGZone { double bottom; double top; ENUM_TIMEFRAMES tf; };

//+------------------------------------------------------------------+
//| FVG: first in move = strongest (buy/sell); higher/lower = 50% rejection (opposite) |
//+------------------------------------------------------------------+
void UpdateFVGs() {
    if(!UseFVG) return;
    ENUM_TIMEFRAMES tfs[];
    int nTf = 0;
    if(UseM5_SR)  { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M5;  }
    if(UseM15_SR) { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M15; }
    if(UseM30_SR) { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M30; }
    double minSize = FVG_MinSizePips * pipValue;
    FVGZone bullList[], bearList[];
    ArrayResize(bullList, 0);
    ArrayResize(bearList, 0);

    for(int t = 0; t < nTf; t++) {
        ENUM_TIMEFRAMES tf = tfs[t];
        int bars = iBars(_Symbol, tf);
        if(bars < 5) continue;
        double high[], low[], close[], open[];
        ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
        ArraySetAsSeries(close, true); ArraySetAsSeries(open, true);
        if(CopyHigh(_Symbol, tf, 0, 5, high) < 5 || CopyLow(_Symbol, tf, 0, 5, low) < 5) continue;
        if(CopyClose(_Symbol, tf, 0, 5, close) < 5 || CopyOpen(_Symbol, tf, 0, 5, open) < 5) continue;
        if(low[0] > high[2] && close[1] > open[1] && (low[0] - high[2]) >= minSize) {
            int n = ArraySize(bullList);
            ArrayResize(bullList, n+1);
            bullList[n].bottom = high[2];
            bullList[n].top = low[0];
            bullList[n].tf = tf;
        }
        if(high[0] < low[2] && close[1] < open[1] && (low[2] - high[0]) >= minSize) {
            int n = ArraySize(bearList);
            ArrayResize(bearList, n+1);
            bearList[n].bottom = high[0];
            bearList[n].top = low[2];
            bearList[n].tf = tf;
        }
    }

    if(!FVG_FirstIsStrongest) {
        for(int i = 0; i < ArraySize(bullList); i++)
            AddOrUpdateZoneEx(bullList[i].bottom, bullList[i].top, true, bullList[i].tf, true);
        for(int i = 0; i < ArraySize(bearList); i++)
            AddOrUpdateZoneEx(bearList[i].bottom, bearList[i].top, false, bearList[i].tf, true);
        return;
    }

    // Bullish FVG: first (lowest bottom) = most powerful for BUY; higher FVGs = rejection (SELL at 50%)
    int nb = ArraySize(bullList);
    if(nb > 0) {
        int firstIdx = 0;
        for(int i = 1; i < nb; i++)
            if(bullList[i].bottom < bullList[firstIdx].bottom) firstIdx = i;
        AddOrUpdateZoneEx(bullList[firstIdx].bottom, bullList[firstIdx].top, true, bullList[firstIdx].tf, true);
        for(int i = 0; i < nb; i++) {
            if(i == firstIdx) continue;
            double mid = (bullList[i].bottom + bullList[i].top) * 0.5;
            AddOrUpdateZoneEx(bullList[i].bottom, mid, false, bullList[i].tf, true);
        }
    }
    // Bearish FVG: first (highest top) = most powerful for SELL; lower FVGs = rejection (BUY at 50%)
    int nBear = ArraySize(bearList);
    if(nBear > 0) {
        int firstIdx = 0;
        for(int i = 1; i < nBear; i++)
            if(bearList[i].top > bearList[firstIdx].top) firstIdx = i;
        AddOrUpdateZoneEx(bearList[firstIdx].bottom, bearList[firstIdx].top, false, bearList[firstIdx].tf, true);
        for(int i = 0; i < nBear; i++) {
            if(i == firstIdx) continue;
            double mid = (bearList[i].bottom + bearList[i].top) * 0.5;
            AddOrUpdateZoneEx(mid, bearList[i].top, true, bearList[i].tf, true);
        }
    }
}

//+------------------------------------------------------------------+
//| Update reversal zones: close at S/R on M5/M15/M30 + OB + FVG     |
//+------------------------------------------------------------------+
void UpdateReversalZones() {
    double tolerance = SR_CloseTolerancePips * pipValue;
    double zoneWid = TapZoneTolerancePips * pipValue;
    ENUM_TIMEFRAMES tfs[];
    int nTf = 0;
    if(UseM5_SR)  { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M5;  }
    if(UseM15_SR) { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M15; }
    if(UseM30_SR) { ArrayResize(tfs, nTf+1); tfs[nTf++] = PERIOD_M30; }

    for(int t = 0; t < nTf; t++) {
        ENUM_TIMEFRAMES tf = tfs[t];
        int bars = iBars(_Symbol, tf);
        if(bars < SR_SwingBars + 2) continue;

        // Swing low = support (bar 1 = last closed bar)
        double swingLow = GetSwingLow(tf, 1, SR_SwingBars);
        if(swingLow > 0 && BarClosedAtLevel(tf, 1, swingLow, tolerance)) {
            if(IsKeyReversalCandle(tf, 1, true, KeyCandleMinBodyPips))
                AddOrUpdateZone(swingLow, true, tf, true);
            else
                AddOrUpdateZone(swingLow, true, tf, false);
        }
        // Swing high = resistance
        double swingHigh = GetSwingHigh(tf, 1, SR_SwingBars);
        if(swingHigh > 0 && BarClosedAtLevel(tf, 1, swingHigh, tolerance)) {
            if(IsKeyReversalCandle(tf, 1, false, KeyCandleMinBodyPips))
                AddOrUpdateZone(swingHigh, false, tf, true);
            else
                AddOrUpdateZone(swingHigh, false, tf, false);
        }
    }
    UpdateOrderBlocks();
    UpdateFVGs();
    if(UseTrendLines) { DetectTrendLines(); AddTrendLineZones(); }
    if(UseHTFRange)   { UpdateHTFRange();   AddRangeZones();   }
}
void AddOrUpdateZone(double level, bool isSupport, ENUM_TIMEFRAMES tf, bool keySet) {
    double zoneWid = TapZoneTolerancePips * pipValue;
    double bottom = level - zoneWid, top = level + zoneWid;
    int n = ArraySize(reversalZones);
    for(int i = 0; i < n; i++) {
        if(MathAbs(reversalZones[i].level - level) < zoneWid*2) {
            reversalZones[i].level = level;
            reversalZones[i].bottom = bottom; reversalZones[i].top = top;
            if(keySet) { reversalZones[i].keyCandleSet = true; reversalZones[i].timeKeyCandle = TimeCurrent(); }
            return;
        }
    }
    if(n >= reversalZonesMax) return;
    ArrayResize(reversalZones, n+1);
    reversalZones[n].level = level; reversalZones[n].bottom = bottom; reversalZones[n].top = top;
    reversalZones[n].isSupport = isSupport; reversalZones[n].tf = tf;
    reversalZones[n].timeFirst = TimeCurrent();
    reversalZones[n].keyCandleSet = keySet;
    if(keySet) reversalZones[n].timeKeyCandle = TimeCurrent();
}

// Add zone with explicit range (for OB / FVG) – same tap-and-reverse + close-at-level logic
void AddOrUpdateZoneEx(double zoneBottom, double zoneTop, bool isSupport, ENUM_TIMEFRAMES tf, bool keySet) {
    double level = (zoneBottom + zoneTop) * 0.5;
    double tol = TapZoneTolerancePips * pipValue;
    int n = ArraySize(reversalZones);
    for(int i = 0; i < n; i++) {
        if(zoneBottom < reversalZones[i].top + tol && zoneTop > reversalZones[i].bottom - tol) {
            reversalZones[i].level = level;
            reversalZones[i].bottom = zoneBottom; reversalZones[i].top = zoneTop;
            if(keySet) { reversalZones[i].keyCandleSet = true; reversalZones[i].timeKeyCandle = TimeCurrent(); }
            return;
        }
    }
    if(n >= reversalZonesMax) return;
    ArrayResize(reversalZones, n+1);
    reversalZones[n].level = level; reversalZones[n].bottom = zoneBottom; reversalZones[n].top = zoneTop;
    reversalZones[n].isSupport = isSupport; reversalZones[n].tf = tf;
    reversalZones[n].timeFirst = TimeCurrent();
    reversalZones[n].keyCandleSet = keySet;
    if(keySet) reversalZones[n].timeKeyCandle = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Tap-and-reverse-again: price in zone and new close in direction  |
//+------------------------------------------------------------------+
bool CheckTapAndReverseEntry(bool &isBuy) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, PERIOD_M5, 1, 3, close);
    if(ArraySize(close) < 2) return false;
    bool choCHOkBuy = (!RequireChoCHForReversal) || (barsSinceChoCH_Bull <= ChoCH_MaxBarsAgo);
    bool choCHOkSell = (!RequireChoCHForReversal) || (barsSinceChoCH_Bear <= ChoCH_MaxBarsAgo);

    int n = ArraySize(reversalZones);
    for(int i = 0; i < n; i++) {
        if(RequireTapAndReverse && !reversalZones[i].keyCandleSet) continue;
        double zoneBottom = reversalZones[i].bottom, zoneTop = reversalZones[i].top;
        bool inZone = (bid >= zoneBottom && bid <= zoneTop) || (close[0] >= zoneBottom && close[0] <= zoneTop);
        if(!inZone) continue;
        if(RequireCloseAtLevel && (close[0] < zoneBottom || close[0] > zoneTop)) continue;

        if(reversalZones[i].isSupport) {
            if(!choCHOkBuy) continue;
            double o[]; ArraySetAsSeries(o, true);
            CopyOpen(_Symbol, PERIOD_M5, 1, 3, o);
            if(ArraySize(o) < 2) continue;
            bool bullishConfirm = (close[0] > o[0]);
            if(RequireEngulfing) bullishConfirm = IsEngulfingM5(true);
            if(bullishConfirm) {
                isBuy = true;
                Print("*** DOMINION: Tap-and-reverse BUY at support ", reversalZones[i].level, (RequireEngulfing ? " (engulfing)" : ""), " ***");
                return true;
            }
        } else {
            if(!choCHOkSell) continue;
            double o[]; ArraySetAsSeries(o, true);
            CopyOpen(_Symbol, PERIOD_M5, 1, 3, o);
            if(ArraySize(o) < 2) continue;
            bool bearishConfirm = (close[0] < o[0]);
            if(RequireEngulfing) bearishConfirm = IsEngulfingM5(false);
            if(bearishConfirm) {
                isBuy = false;
                Print("*** DOMINION: Tap-and-reverse SELL at resistance ", reversalZones[i].level, (RequireEngulfing ? " (engulfing)" : ""), " ***");
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Open position (one direction per symbol; block same-symbol hedge) |
//+------------------------------------------------------------------+
void OpenOrder(bool isBuy) {
    if(CountPositions(POSITION_TYPE_BUY) + CountPositions(POSITION_TYPE_SELL) > 0) return;
    string gvName = "Dominion_Open_" + _Symbol;
    if(GlobalVariableCheck(gvName) && (TimeCurrent() - (datetime)GlobalVariableGet(gvName) < 3)) return;
    GlobalVariableSet(gvName, (double)TimeCurrent());

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = isBuy ? ask : bid;
    double slPips = (pipValue == 0.01) ? SL_Pips_Silver : SL_Pips_Gold;
    double slDist = slPips * pipValue;
    double sl = isBuy ? NormalizeDouble(price - slDist, symbolDigits) : NormalizeDouble(price + slDist, symbolDigits);
    double equity = account.Equity();
    double riskAmount = equity * (RiskPercent / 100.0);
    double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tickSize <= 0) return;
    double lotSize = riskAmount / (slDist / tickSize * tickVal);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if(step <= 0) step = 0.01;
    lotSize = MathFloor(lotSize / step) * step;
    lotSize = MathMax(minLot, MathMin(lotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
    lotSize = NormalizeDouble(lotSize, 2);

    string comment = TradeComment;
    if(StringLen(UserName) > 0) comment += "|U:" + UserName;
    comment += "|A:" + IntegerToString(account.Login());

    if(isBuy) {
        if(trade.Buy(lotSize, _Symbol, price, sl, 0, comment))
            Print("*** DOMINION BUY opened ", lotSize, " @ ", price, " SL ", sl);
    } else {
        if(trade.Sell(lotSize, _Symbol, price, sl, 0, comment))
            Print("*** DOMINION SELL opened ", lotSize, " @ ", price, " SL ", sl);
    }
}

//+------------------------------------------------------------------+
//| Ticket index                                                     |
//+------------------------------------------------------------------+
int GetTicketIndex(ulong ticket) {
    return (int)(ticket % 10000);
}
void EnsureArrays(int index) {
    int sz = ArraySize(tp1Hit);
    if(index >= sz) {
        int newSz = index + 20;
        ArrayResize(tp1Hit, newSz); ArrayResize(tp2Hit, newSz); ArrayResize(tp3Hit, newSz);
        ArrayResize(tp4Hit, newSz); ArrayResize(tp5Hit, newSz);
        ArrayResize(tp1HitPrice, newSz); ArrayResize(partialCloseLevel, newSz); ArrayResize(originalVolume, newSz);
        for(int j = sz; j < newSz; j++) {
            tp1Hit[j]=false; tp2Hit[j]=false; tp3Hit[j]=false; tp4Hit[j]=false; tp5Hit[j]=false;
            tp1HitPrice[j]=0; partialCloseLevel[j]=0; originalVolume[j]=0;
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Positions – posType + type auto-correct, BE (SELL capped), TP ladder |
//+------------------------------------------------------------------+
void ManagePositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;
        ulong ticket = position.Ticket();
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentVolume = position.Volume();
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type();
        bool isSilver = (GetPipValue(_Symbol) == 0.01);
        double pv = isSilver ? 0.01 : 0.1;
        double currentBID = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double currentASK = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double currentProfitPips = (posType == POSITION_TYPE_BUY) ? (currentBID - openPrice) / pv : (openPrice - currentASK) / pv;
        double currentPrice = (posType == POSITION_TYPE_BUY) ? currentBID : currentASK;

        // Type auto-correct: only when broker profit disagrees with reported type (don't flip real BUY in drawdown)
        double profitIfBuy  = (currentBID - openPrice) / pv;
        double profitIfSell = (openPrice - currentASK) / pv;
        double posProfit = position.Profit() + position.Swap();
        if(posType == POSITION_TYPE_BUY && profitIfBuy < -5.0 && profitIfSell > 5.0 && posProfit > 0) {
            posType = POSITION_TYPE_SELL; currentProfitPips = profitIfSell; currentPrice = currentASK;
            Print("*** TYPE AUTO-CORRECT: #", ticket, " → SELL (broker profit disagreed) ***");
        } else if(posType == POSITION_TYPE_SELL && profitIfSell < -5.0 && profitIfBuy > 5.0 && posProfit > 0) {
            posType = POSITION_TYPE_BUY; currentProfitPips = profitIfBuy; currentPrice = currentBID;
            Print("*** TYPE AUTO-CORRECT: #", ticket, " → BUY (broker profit disagreed) ***");
        }

        int ticketIndex = GetTicketIndex(ticket);
        EnsureArrays(ticketIndex);
        if(ticketIndex < 0 || ticketIndex >= ArraySize(tp1Hit)) continue;
        if(originalVolume[ticketIndex] == 0) originalVolume[ticketIndex] = currentVolume;
        double origVol = originalVolume[ticketIndex];
        double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double runnerSize = MathMax(minLot, NormalizeDouble(origVol * (RunnerSizePercent/100.0), 2));
        bool hasRunner = (currentVolume <= runnerSize + minLot*0.5);

        // BE – SELL BE capped
        double bePips = isSilver ? BreakEvenPips_Silver : BreakEvenPips;
        if(posType == POSITION_TYPE_SELL && bePips > SELL_BE_CapPips) bePips = SELL_BE_CapPips;
        if(!tp1Hit[ticketIndex] && currentProfitPips >= bePips && currentProfitPips > 0) {
            tp1Hit[ticketIndex] = true;
            if(UseBreakEven) {
                double newSL = NormalizeDouble(openPrice, symbolDigits);
                bool need = (posType == POSITION_TYPE_BUY) ? (newSL > currentSL || currentSL == 0) : (currentSL == 0 || newSL < currentSL);
                if(need && trade.PositionModify(ticket, newSL, 0))
                    Print("*** BE set #", ticket, " ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), " @ ", bePips, " pips ***");
            }
        }

        // TP1–TP4 partials + TP5 full close (same structure as Blueprint)
        if(!tp1Hit[ticketIndex]) continue;
        int level = partialCloseLevel[ticketIndex];
        double minPip = isSilver ? 0.01 : 0.1;

        if(level == 0 && currentProfitPips >= TP1_Pips && currentVolume > runnerSize + minLot) {
            double closeVol = NormalizeDouble(origVol * (TP1_Percent/100.0), 2);
            if(closeVol < minLot) closeVol = minLot;
            if(currentVolume - closeVol >= runnerSize && trade.PositionClosePartial(ticket, closeVol)) {
                partialCloseLevel[ticketIndex] = 1;
                Print("*** TP1 #", ticket, " ", closeVol, " lots ***");
            }
        } else if(level == 1 && currentProfitPips >= TP2_Pips && currentVolume > runnerSize + minLot) {
            double closeVol = NormalizeDouble(origVol * (TP2_Percent/100.0), 2);
            if(closeVol < minLot) closeVol = minLot;
            if(currentVolume - closeVol >= runnerSize && trade.PositionClosePartial(ticket, closeVol)) {
                partialCloseLevel[ticketIndex] = 2;
                Print("*** TP2 #", ticket, " ***");
            }
        } else if(level == 2 && currentProfitPips >= TP3_Pips && currentVolume > runnerSize + minLot) {
            double closeVol = NormalizeDouble(origVol * (TP3_Percent/100.0), 2);
            if(closeVol < minLot) closeVol = minLot;
            if(currentVolume - closeVol >= runnerSize && trade.PositionClosePartial(ticket, closeVol)) {
                partialCloseLevel[ticketIndex] = 3;
                Print("*** TP3 #", ticket, " ***");
            }
        } else if(level == 3 && currentProfitPips >= TP4_Pips && currentVolume > runnerSize + minLot) {
            double closeVol = NormalizeDouble(origVol * (TP4_Percent/100.0), 2);
            if(closeVol < minLot) closeVol = minLot;
            if(currentVolume - closeVol >= runnerSize && trade.PositionClosePartial(ticket, closeVol)) {
                partialCloseLevel[ticketIndex] = 4;
                Print("*** TP4 #", ticket, " ***");
            }
        } else if(level >= 3 && currentProfitPips >= TP5_Pips && !tp5Hit[ticketIndex]) {
            if(trade.PositionClose(ticket)) {
                tp5Hit[ticketIndex] = true;
                Print("*** TP5 full close #", ticket, " ***");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
    initTime = TimeCurrent();
    pipValue = GetPipValue(_Symbol);
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    ArrayResize(reversalZones, 0);
    ArrayResize(tp1Hit, 100); ArrayResize(tp2Hit, 100); ArrayResize(tp3Hit, 100);
    ArrayResize(tp4Hit, 100); ArrayResize(tp5Hit, 100);
    ArrayResize(tp1HitPrice, 100); ArrayResize(partialCloseLevel, 100); ArrayResize(originalVolume, 100);
    for(int j = 0; j < 100; j++) {
        tp1Hit[j]=false; tp2Hit[j]=false; tp3Hit[j]=false; tp4Hit[j]=false; tp5Hit[j]=false;
        partialCloseLevel[j]=0; originalVolume[j]=0;
    }
    if(!CheckLicense()) {
        Print("DOMINION: License check failed.");
        return INIT_FAILED;
    }
    Print("Goldmine Dominion initialized. Symbol: ", _Symbol, " PipValue: ", pipValue);
    return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) {
    Print("Goldmine Dominion deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick() {
    static datetime lastLicense = 0;
    if(TimeCurrent() - lastLicense >= 3600) {
        if(!CheckLicense()) { ExpertRemove(); return; }
        lastLicense = TimeCurrent();
    }
    ManagePositions();

    datetime barTime = iTime(_Symbol, PERIOD_M5, 0);
    static bool openedThisBar = false;
    if(barTime != lastBarTime) {
        lastBarTime = barTime;
        openedThisBar = false;
    }
    if(openedThisBar) return;

    UpdateSessionOpenCloseLevels();
    datetime barTimeM15 = iTime(_Symbol, PERIOD_M15, 0);
    if(barTimeM15 != lastBarTimeM15) { lastBarTimeM15 = barTimeM15; UpdateBOS_ChoCH(); }
    UpdateReversalZones();
    if(CountPositions(POSITION_TYPE_BUY) + CountPositions(POSITION_TYPE_SELL) > 0) return;
    bool isBuy = false;
    if(CheckSessionRetestEntry(isBuy)) {
        OpenOrder(isBuy);
        openedThisBar = true;
    } else if(CheckTapAndReverseEntry(isBuy)) {
        OpenOrder(isBuy);
        openedThisBar = true;
    }
}
int CountPositions(ENUM_POSITION_TYPE type) {
    int c = 0;
    for(int i = PositionsTotal()-1; i >= 0; i--) {
        if(position.SelectByIndex(i) && position.Symbol() == _Symbol && position.Magic() == MagicNumber && position.Type() == type)
            c++;
    }
    return c;
}

//+------------------------------------------------------------------+
