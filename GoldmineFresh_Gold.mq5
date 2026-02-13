//+------------------------------------------------------------------+
//|                                              GoldmineFresh_Gold.mq5 |
//|     Goldmine Fresh - Gold. Same entry model: OB, session, TL, FVG. |
//|     Setup-dependent TP (BOS, session open, next OB). 1 pip = 0.1.   |
//+------------------------------------------------------------------+
#property copyright "Goldmine Fresh"
#property version   "3.01"
#property description "Multi-TF OB, session breakout, M1 TL, BOS/ChoCH. 1 pip = 0.1. Tester: use for ENTRIES only; validate BE/TP on real or demo."

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CPositionInfo position;
CAccountInfo account;

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== License ==="
input bool   EnableLicenseCheck = true;
input string LicenseServerURL   = "https://mt5-license-server-production.up.railway.app";
input string LicenseKey         = "";
input string UserName           = "";
input int    LicenseCheckTimeout = 5;
input int    MagicNumber        = 124010;
input string TradeComment       = "Goldmine Fresh - Gold";

input group "=== Risk ==="
input double RiskPercent   = 1.0;   // Risk per trade (%)
input double SL_Pips       = 25.0;  // Stop loss (pips)
input int    MaxPositionsPerSide = 2; // Max BUY and max SELL
input int    MaxTotalPositions = 8;   // Hard cap total open (stops margin blowout from many entries)

input group "=== Break-even & Take profit ==="
input bool   UseBreakEven  = true;  // Set BE at BreakEvenPips (turn off for pure reversal style)
input double BreakEvenPips = 25.0;  // BE at this many pips (when UseBreakEven)
input double TP1_Pips      = 30.0;  // TP1 – first partial (take profit early so we don’t give it back)
input double TP2_Pips      = 50.0;  // TP2
input double TP3_Pips      = 70.0;  // TP3
input double TP4_Pips      = 120.0; // TP4 – remainder
input bool   UseSetupBasedTP = true; // TP: _SS/_DC/_REV/_TL_BR/_HK→London open; _TL_OB→nearest OB; else TP1–TP4
input double MaxSetupTargetPips = 150.0; // Cap setup-based target (close full by here so we lock profit)
input bool   UseForceCloseAtCap = false; // If true: force-close full at cap. If false: hold runner (partials + trail only)

input group "=== Trailing (optional) ==="
input bool   UseTrailSL    = true;
input double TrailStartPips = 100.0;
input double TrailDistancePips = 20.0;

input group "=== Session / Fix levels (server time) ==="
input bool   UseSessionLevels = true;   // Track Asia/London/NY/Sydney open and HK aftermarket close
input int    Session_AsiaStart = 0;      // Asia start hour (0-8)
input int    Session_LondonStart = 8;   // London start hour (8-16)
input int    Session_NYStart = 14;      // NY start hour (14-22)
input int    HK_AftermarketCloseHour = 9; // HK aftermarket close hour (server) – magnet level

input group "=== Order block (multi-TF + historical) ==="
input bool   UseM1_OB = true;              // Detect OB on M1
input bool   UseM5_OB = true;              // Detect OB on M5
input bool   UseM15_OB = true;             // Detect OB on M15
input bool   UseM30_OB = true;             // Detect OB on M30
input bool   UseH1_OB = true;              // Detect OB on H1
input int    OB_Lookback   = 50;           // Bars lookback per TF
input int    OB_HistoricalScan = 500;      // Bars to scan on start (previous weeks; 500 M15 ≈ 5 days)
input int    OB_MaxStored = 150;           // Max OBs to keep (higher = more HTF retained)
input double OB_ZonePips  = 15.0;
input double OB_TouchPips = 10.0;
input bool   RequireEngulfing = true;
input bool   OB_RequireHTFAlignment = false; // Only use OB when zone aligns with HTF support/resistance
input double OB_HTFAlignmentPips = 25.0;  // Pips tolerance for OB vs HTF level

input group "=== Entry models (same entry model – enable which to use) ==="
input bool   UseEntry_OB = true;              // OB touch + optional engulfing
input bool   UseEntry_SessionSweep = true;    // London low/high rejection sweep + retest + engulfing
input bool   UseEntry_SessionBreakout = true;  // Break above session high / below session low then retest + engulfing
input bool   Breakout_UseRangeWhenNoLondon = true;  // Use last N-bar range when London high/low not set
input int    Breakout_LookbackBars = 20;      // Bars (M15) for range high/low when London not available
input double Breakout_SL_Pips = 20.0;        // SL (pips) beyond broken level for _BO trades
input double Breakout_RetestPips = 15.0;      // Pips tolerance for retest of broken level
input bool   UseEntry_TL_BreakRetest = true;  // Trend line resistance break then retest (long)
input bool   UseEntry_TL_OB = true;           // Trend line tap at OB/breaker – target nearest OB
input bool   UseEntry_Reversal = true;        // FVG zone + engulfing; up to 4 entries 5 pips apart
input int    REV_MaxEntries = 4;               // Max FVG/reversal entries per side
input double REV_EntrySpacingPips = 5.0;      // Min pips between FVG entries
input bool   REV_SLBelowFVG = true;            // SL below FVG (long) / above FVG (short)
input double REV_SLBufferPips = 5.0;          // Pips beyond FVG edge for SL
input double REV_BEPips = 50.0;               // BE at this many pips for _REV (when UseBreakEven)
input bool   Reversal_RequireM5Rejection = false; // Reversal: M5 last close above low (BUY) / below high (SELL)
input bool   UseEntry_DoubleConfluence = true; // Trend line tap + OB (e.g. Asia open support) – target London open
input bool   UseEntry_HKCloseRetest = false;   // HK aftermarket close retest + engulfing (magnet level)
input bool   DC_RequireAsiaOpen = false;      // Double confluence: require price at Asia open (support/resistance)
input double TL_TouchPips = 15.0;            // Pips tolerance for trend line touch/retest
input int    TL_SwingBars = 5;               // Bars for swing high/low (trend line)
input bool   UseM1_TL_Confluence = true;      // M1 trend line as added confluence (like you showed)
input int    FVG_Lookback = 30;              // Bars for FVG detection
input group "=== BOS / ChoCH (market structure) ==="
input bool   UseMarketStructure = true;      // Enable BOS/ChoCH
input bool   RequireBOS = false;             // Require BOS in direction before entry (stricter)
input ENUM_TIMEFRAMES MS_HigherTF = PERIOD_M15; // TF for structure (M15 or H1)
input int    MS_SwingLength = 5;             // Bars for swing high/low on structure TF
input double FVG_MinPips = 5.0;              // Min FVG size (pips)

//--- Globals
double point, pipValue;
int    symbolDigits;
double accountBalance;
struct OrderBlock { double top; double bottom; datetime time; bool isBullish; bool isActive; ENUM_TIMEFRAMES tf; };
OrderBlock g_obList[];
#define OB_MAX 200
datetime   lastBarTime;
datetime   lastBarTime_M1, lastBarTime_M5, lastBarTime_M15, lastBarTime_M30, lastBarTime_H1;
bool       historicalScanDone_M1, historicalScanDone_M5, historicalScanDone_M15, historicalScanDone_M30, historicalScanDone_H1;
bool       tp1Hit[], tp2Hit[], tp3Hit[], tp4Hit[];
double     origVolume[];
int        partialLevel[];

// Session levels (server time: Asia 0-8, London 8-16, NY 14-22)
double asiaHigh, asiaLow, londonHigh, londonLow, nyHigh, nyLow;
double asiaOpenPrice, londonOpenPrice, nyOpenPrice, sydneyOpenPrice; // price at session open
double hkClosePrice;   // price at HK aftermarket close hour
bool   londonLowSwept, londonHighSwept;
static datetime lastLondonBar = 0;

// FVG
struct FVG { double top; double bottom; datetime time; bool isBullish; bool isActive; ENUM_TIMEFRAMES tf; };
FVG g_fvgs[];
#define FVG_MAX 40

// Trend line M15 (from swing highs = resistance; swing lows = support)
double g_tlResistPrice;  // trend line value at current bar (resistance)
double g_tlSupportPrice; // support trend line at current bar
bool   g_tlBrokenAbove, g_tlBrokenBelow;
int    g_swingHighBar1, g_swingHighBar2, g_swingLowBar1, g_swingLowBar2;
// Trend line M1 (added confluence)
double g_tlResistPriceM1, g_tlSupportPriceM1;

// HTF sweep levels for OB alignment (H1, H4, D1)
double htfSweepHigh_H1, htfSweepLow_H1, htfSweepHigh_H4, htfSweepLow_H4, htfSweepHigh_D1, htfSweepLow_D1;
static datetime lastHTFSweep_H1 = 0, lastHTFSweep_H4 = 0, lastHTFSweep_D1 = 0;

// BOS/ChoCH market structure
struct MarketStructure { int trend; double lastBOS; double lastCHoCH; };
MarketStructure marketStruct;

//+------------------------------------------------------------------+
//| License validation (remote)                                      |
//+------------------------------------------------------------------+
bool ValidateLicenseRemote() {
    if(StringLen(LicenseServerURL) == 0) return false;
    long acc = account.Login();
    string srv = account.Server();
    string json = "{\"accountNumber\":\"" + IntegerToString(acc) + "\",\"broker\":\"" + srv + "\",\"eaName\":\"Goldmine Fresh - Gold\"";
    if(StringLen(LicenseKey) > 0) json += ",\"licenseKey\":\"" + LicenseKey + "\"";
    json += "}";
    string url = LicenseServerURL;
    if(StringFind(url, "http") != 0) url = "https://" + url;
    if(StringFind(url, "/validate") < 0) {
        if(StringLen(url) > 0 && StringFind(url, "/", StringLen(url)-1) != StringLen(url)-1) url += "/";
        url += "validate";
    }
    char post[], result[];
    string headers = "Content-Type: application/json\r\n";
    ArrayResize(post, (int)StringLen(json) + 1);
    StringToCharArray(json, post, 0, WHOLE_ARRAY);
    int res = WebRequest("POST", url, NULL, NULL, LicenseCheckTimeout * 1000, post, (int)StringLen(json), result, headers);
    if(res == -1) { Print("License: WebRequest error ", GetLastError()); return false; }
    if(res != 200) { Print("License: HTTP ", res); return false; }
    string resp = CharArrayToString(result);
    if(StringFind(resp, "\"valid\":true") >= 0) { Print("License: valid"); return true; }
    Print("License: invalid");
    return false;
}

bool CheckLicense() {
    if(MQLInfoInteger(MQL_TESTER)) return true;   // Skip license in Strategy Tester (WebRequest not allowed / error 4014)
    if(!EnableLicenseCheck) return true;
    for(int t = 0; t < 3; t++) {
        if(ValidateLicenseRemote()) return true;
        Sleep(500);
    }
    Alert("Goldmine Fresh: License check failed.");
    return false;
}

//+------------------------------------------------------------------+
//| Update session high/low and session open prices (server time)     |
//+------------------------------------------------------------------+
void UpdateSessionLevels() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int h = dt.hour;
    static int lastH = -1;
    double openPrice = iOpen(_Symbol, PERIOD_M15, 0);
    double high0 = iHigh(_Symbol, PERIOD_M15, 0), low0 = iLow(_Symbol, PERIOD_M15, 0);
    if(h == 0 && lastH != 0) { asiaHigh = 0; asiaLow = 0; }
    if(h == Session_LondonStart && lastH < Session_LondonStart) { londonHigh = 0; londonLow = 0; londonLowSwept = false; londonHighSwept = false; lastLondonBar = 0; londonOpenPrice = openPrice; }
    if(h == Session_NYStart && lastH < Session_NYStart) { nyHigh = 0; nyLow = 0; nyOpenPrice = openPrice; }
    if(h == 0) sydneyOpenPrice = openPrice;
    if(h == HK_AftermarketCloseHour) hkClosePrice = openPrice;
    lastH = h;
    if(h >= 0 && h < 8) {
        if(asiaHigh == 0 || asiaLow == 0) { asiaHigh = high0; asiaLow = low0; asiaOpenPrice = openPrice; }
        else { asiaHigh = MathMax(asiaHigh, high0); asiaLow = MathMin(asiaLow, low0); }
    } else if(h >= Session_LondonStart && h < 16) {
        datetime bar0Time = iTime(_Symbol, PERIOD_M15, 0);
        if(bar0Time != lastLondonBar) {
            lastLondonBar = bar0Time;
            double high1 = iHigh(_Symbol, PERIOD_M15, 1), low1 = iLow(_Symbol, PERIOD_M15, 1), close1 = iClose(_Symbol, PERIOD_M15, 1);
            if(londonHigh == 0 || londonLow == 0) { londonHigh = high1; londonLow = low1; }
            else {
                if(londonLow > 0 && low1 < londonLow && close1 > londonLow) londonLowSwept = true;
                if(londonHigh > 0 && high1 > londonHigh && close1 < londonHigh) londonHighSwept = true;
                londonHigh = MathMax(londonHigh, high1); londonLow = MathMin(londonLow, low1);
            }
        }
    } else if(h >= Session_NYStart && h < 22) {
        if(nyHigh == 0 || nyLow == 0) { nyHigh = high0; nyLow = low0; }
        else { nyHigh = MathMax(nyHigh, high0); nyLow = MathMin(nyLow, low0); }
    }
}

//+------------------------------------------------------------------+
//| HTF sweep levels (H1, H4, D1) for OB alignment                    |
//+------------------------------------------------------------------+
void UpdateHTFSweepLevels() {
    int swingBars = 5;
    datetime t = iTime(_Symbol, PERIOD_H1, 0);
    if(t != lastHTFSweep_H1) {
        lastHTFSweep_H1 = t;
        int bars = iBars(_Symbol, PERIOD_H1);
        if(bars >= swingBars * 2) {
            double h = iHigh(_Symbol, PERIOD_H1, swingBars), l = iLow(_Symbol, PERIOD_H1, swingBars);
            for(int i = 1; i <= swingBars; i++) { h = MathMax(h, iHigh(_Symbol, PERIOD_H1, swingBars - i)); l = MathMin(l, iLow(_Symbol, PERIOD_H1, swingBars - i)); }
            htfSweepHigh_H1 = h; htfSweepLow_H1 = l;
        }
    }
    t = iTime(_Symbol, PERIOD_H4, 0);
    if(t != lastHTFSweep_H4) {
        lastHTFSweep_H4 = t;
        int bars = iBars(_Symbol, PERIOD_H4);
        if(bars >= swingBars * 2) {
            double h = iHigh(_Symbol, PERIOD_H4, swingBars), l = iLow(_Symbol, PERIOD_H4, swingBars);
            for(int i = 1; i <= swingBars; i++) { h = MathMax(h, iHigh(_Symbol, PERIOD_H4, swingBars - i)); l = MathMin(l, iLow(_Symbol, PERIOD_H4, swingBars - i)); }
            htfSweepHigh_H4 = h; htfSweepLow_H4 = l;
        }
    }
    t = iTime(_Symbol, PERIOD_D1, 0);
    if(t != lastHTFSweep_D1) {
        lastHTFSweep_D1 = t;
        int bars = iBars(_Symbol, PERIOD_D1);
        if(bars >= swingBars * 2) {
            double h = iHigh(_Symbol, PERIOD_D1, swingBars), l = iLow(_Symbol, PERIOD_D1, swingBars);
            for(int i = 1; i <= swingBars; i++) { h = MathMax(h, iHigh(_Symbol, PERIOD_D1, swingBars - i)); l = MathMin(l, iLow(_Symbol, PERIOD_D1, swingBars - i)); }
            htfSweepHigh_D1 = h; htfSweepLow_D1 = l;
        }
    }
}
bool OrderBlockAlignsWithHTFSupport(double zoneBottom, double zoneTop) {
    double tol = OB_HTFAlignmentPips * pipValue;
    double zoneMid = (zoneBottom + zoneTop) * 0.5;
    if(htfSweepLow_H1 > 0 && MathAbs(zoneMid - htfSweepLow_H1) <= tol) return true;
    if(htfSweepLow_H4 > 0 && MathAbs(zoneMid - htfSweepLow_H4) <= tol) return true;
    if(htfSweepLow_D1 > 0 && MathAbs(zoneMid - htfSweepLow_D1) <= tol) return true;
    if(asiaLow > 0 && MathAbs(zoneMid - asiaLow) <= tol) return true;
    if(londonLow > 0 && MathAbs(zoneMid - londonLow) <= tol) return true;
    return false;
}
bool OrderBlockAlignsWithHTFResistance(double zoneBottom, double zoneTop) {
    double tol = OB_HTFAlignmentPips * pipValue;
    double zoneMid = (zoneBottom + zoneTop) * 0.5;
    if(htfSweepHigh_H1 > 0 && MathAbs(zoneMid - htfSweepHigh_H1) <= tol) return true;
    if(htfSweepHigh_H4 > 0 && MathAbs(zoneMid - htfSweepHigh_H4) <= tol) return true;
    if(htfSweepHigh_D1 > 0 && MathAbs(zoneMid - htfSweepHigh_D1) <= tol) return true;
    if(asiaHigh > 0 && MathAbs(zoneMid - asiaHigh) <= tol) return true;
    if(londonHigh > 0 && MathAbs(zoneMid - londonHigh) <= tol) return true;
    return false;
}

//+------------------------------------------------------------------+
//| BOS/ChoCH market structure                                        |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
    int bars = iBars(_Symbol, MS_HigherTF);
    if(bars < MS_SwingLength * 2 + 5) return;
    double high[], low[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
    if(CopyHigh(_Symbol, MS_HigherTF, 0, MS_SwingLength * 2 + 5, high) < MS_SwingLength + 2) return;
    CopyLow(_Symbol, MS_HigherTF, 0, MS_SwingLength * 2 + 5, low);
    double swingHigh = high[MS_SwingLength], swingLow = low[MS_SwingLength];
    for(int i = 1; i <= MS_SwingLength; i++) {
        if(high[i] > swingHigh) swingHigh = high[i];
        if(low[i] < swingLow) swingLow = low[i];
    }
    double currentHigh = high[0], currentLow = low[0];
    if(marketStruct.trend == -1 && currentHigh > swingHigh) {
        marketStruct.lastBOS = currentHigh; marketStruct.trend = 1;
    } else if(marketStruct.trend == 1 && currentLow < swingLow) {
        marketStruct.lastCHoCH = currentLow; marketStruct.trend = -1;
    }
}

//+------------------------------------------------------------------+
//| Swing high/low and trend line (resistance from 2 swing highs)     |
//+------------------------------------------------------------------+
void UpdateTrendLine() {
    int bars = iBars(_Symbol, PERIOD_M15);
    if(bars < TL_SwingBars * 3) return;
    double high[], low[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
    if(CopyHigh(_Symbol, PERIOD_M15, 0, bars, high) < bars || CopyLow(_Symbol, PERIOD_M15, 0, bars, low) < bars) return;
    g_swingHighBar1 = -1; g_swingHighBar2 = -1; g_swingLowBar1 = -1; g_swingLowBar2 = -1;
    for(int i = TL_SwingBars; i < bars - TL_SwingBars && (g_swingHighBar2 < 0 || g_swingLowBar2 < 0); i++) {
        bool isSwingHigh = true, isSwingLow = true;
        for(int j = 1; j <= TL_SwingBars; j++) {
            if(high[i] <= high[i-j] || high[i] <= high[i+j]) isSwingHigh = false;
            if(low[i] >= low[i-j] || low[i] >= low[i+j]) isSwingLow = false;
        }
        if(isSwingHigh && g_swingHighBar1 < 0) g_swingHighBar1 = i;
        else if(isSwingHigh && g_swingHighBar1 >= 0 && g_swingHighBar2 < 0) { g_swingHighBar2 = i; break; }
        if(isSwingLow && g_swingLowBar1 < 0) g_swingLowBar1 = i;
        else if(isSwingLow && g_swingLowBar1 >= 0 && g_swingLowBar2 < 0) { g_swingLowBar2 = i; break; }
    }
    if(g_swingHighBar1 >= 0 && g_swingHighBar2 >= 0) {
        double slope = (high[g_swingHighBar1] - high[g_swingHighBar2]) / (double)(g_swingHighBar2 - g_swingHighBar1);
        g_tlResistPrice = high[g_swingHighBar1] + slope * (0 - g_swingHighBar1);
    } else g_tlResistPrice = 0;
    if(g_swingLowBar1 >= 0 && g_swingLowBar2 >= 0) {
        double slope = (low[g_swingLowBar1] - low[g_swingLowBar2]) / (double)(g_swingLowBar2 - g_swingLowBar1);
        g_tlSupportPrice = low[g_swingLowBar1] + slope * (0 - g_swingLowBar1);
    } else g_tlSupportPrice = 0;
}

//+------------------------------------------------------------------+
//| M1 trend line (added confluence like you showed)                  |
//+------------------------------------------------------------------+
void UpdateTrendLineM1() {
    int bars = iBars(_Symbol, PERIOD_M1);
    if(bars < TL_SwingBars * 3) return;
    double high[], low[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true);
    if(CopyHigh(_Symbol, PERIOD_M1, 0, bars, high) < bars || CopyLow(_Symbol, PERIOD_M1, 0, bars, low) < bars) return;
    int sh1 = -1, sh2 = -1, sl1 = -1, sl2 = -1;
    for(int i = TL_SwingBars; i < bars - TL_SwingBars; i++) {
        bool isSH = true, isSL = true;
        for(int j = 1; j <= TL_SwingBars; j++) {
            if(high[i] <= high[i-j] || high[i] <= high[i+j]) isSH = false;
            if(low[i] >= low[i-j] || low[i] >= low[i+j]) isSL = false;
        }
        if(isSH && sh1 < 0) sh1 = i; else if(isSH && sh1 >= 0 && sh2 < 0) { sh2 = i; }
        if(isSL && sl1 < 0) sl1 = i; else if(isSL && sl1 >= 0 && sl2 < 0) { sl2 = i; }
        if(sh2 >= 0 && sl2 >= 0) break;
    }
    if(sh1 >= 0 && sh2 >= 0) {
        double slope = (high[sh1] - high[sh2]) / (double)(sh2 - sh1);
        g_tlResistPriceM1 = high[sh1] + slope * (0 - sh1);
    } else g_tlResistPriceM1 = 0;
    if(sl1 >= 0 && sl2 >= 0) {
        double slope = (low[sl1] - low[sl2]) / (double)(sl2 - sl1);
        g_tlSupportPriceM1 = low[sl1] + slope * (0 - sl1);
    } else g_tlSupportPriceM1 = 0;
}

//+------------------------------------------------------------------+
//| Detect FVG on M5/M15                                              |
//+------------------------------------------------------------------+
void DetectFVG() {
    ArrayResize(g_fvgs, 0);
    for(int tf = 0; tf <= 1; tf++) {
        ENUM_TIMEFRAMES T = (tf == 0) ? PERIOD_M5 : PERIOD_M15;
        double high[], low[], open[], close[];
        ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(open, true); ArraySetAsSeries(close, true);
        int copied = CopyHigh(_Symbol, T, 0, FVG_Lookback, high);
        if(copied < 5) continue;
        CopyLow(_Symbol, T, 0, FVG_Lookback, low);
        CopyOpen(_Symbol, T, 0, FVG_Lookback, open);
        CopyClose(_Symbol, T, 0, FVG_Lookback, close);
        for(int i = 0; i < copied - 3 && ArraySize(g_fvgs) < FVG_MAX; i++) {
            if(low[i] > high[i+2] && close[i+1] > open[i+1]) {
                double sz = (low[i] - high[i+2]) / pipValue;
                if(sz >= FVG_MinPips) {
                    int n = ArraySize(g_fvgs); ArrayResize(g_fvgs, n + 1);
                    g_fvgs[n].top = low[i]; g_fvgs[n].bottom = high[i+2]; g_fvgs[n].time = iTime(_Symbol, T, i); g_fvgs[n].isBullish = true; g_fvgs[n].isActive = true; g_fvgs[n].tf = T;
                }
            }
            if(high[i] < low[i+2] && close[i+1] < open[i+1]) {
                double sz = (low[i+2] - high[i]) / pipValue;
                if(sz >= FVG_MinPips) {
                    int n = ArraySize(g_fvgs); ArrayResize(g_fvgs, n + 1);
                    g_fvgs[n].top = low[i+2]; g_fvgs[n].bottom = high[i]; g_fvgs[n].time = iTime(_Symbol, T, i); g_fvgs[n].isBullish = false; g_fvgs[n].isActive = true; g_fvgs[n].tf = T;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Engulfing M1/M3/M5                                                |
//+------------------------------------------------------------------+
bool IsBullishEngulfingTF(ENUM_TIMEFRAMES tf) {
    double o0 = iOpen(_Symbol, tf, 1), c0 = iClose(_Symbol, tf, 1), o1 = iOpen(_Symbol, tf, 2), c1 = iClose(_Symbol, tf, 2);
    return (c0 > o0 && o1 > c1 && o0 <= c1 && c0 >= o1);
}
bool IsBearishEngulfingTF(ENUM_TIMEFRAMES tf) {
    double o0 = iOpen(_Symbol, tf, 1), c0 = iClose(_Symbol, tf, 1), o1 = iOpen(_Symbol, tf, 2), c1 = iClose(_Symbol, tf, 2);
    return (c0 < o0 && c1 > o1 && o0 >= c1 && c0 <= o1);
}
bool SessionSweepHasBullishEngulfing() {
    return IsBullishEngulfingTF(PERIOD_M15) || IsBullishEngulfingTF(PERIOD_M5) || IsBullishEngulfingTF(PERIOD_M3) || IsBullishEngulfingTF(PERIOD_M1);
}
bool SessionSweepHasBearishEngulfing() {
    return IsBearishEngulfingTF(PERIOD_M15) || IsBearishEngulfingTF(PERIOD_M5) || IsBearishEngulfingTF(PERIOD_M3) || IsBearishEngulfingTF(PERIOD_M1);
}

// M5 rejection: last closed bar closed above its low (bullish) or below its high (bearish)
bool M5BullishRejectionCandle() {
    double c = iClose(_Symbol, PERIOD_M5, 1), l = iLow(_Symbol, PERIOD_M5, 1);
    return (c > l + point);
}
bool M5BearishRejectionCandle() {
    double c = iClose(_Symbol, PERIOD_M5, 1), h = iHigh(_Symbol, PERIOD_M5, 1);
    return (c < h - point);
}

//+------------------------------------------------------------------+
//| Nearest OB target: BUY → nearest bearish OB above (bottom); SELL → nearest bullish OB below (top) |
//+------------------------------------------------------------------+
double GetNearestOBTarget(double openPrice, bool isBuy) {
    double tol = OB_ZonePips * pipValue;
    double best = 0;
    for(int i = 0; i < ArraySize(g_obList); i++) {
        if(!g_obList[i].isActive) continue;
        if(isBuy && !g_obList[i].isBullish && g_obList[i].bottom > openPrice + tol) {
            if(best <= 0 || g_obList[i].bottom < best) best = g_obList[i].bottom;
        }
        if(!isBuy && g_obList[i].isBullish && g_obList[i].top < openPrice - tol) {
            if(best <= 0 || g_obList[i].top > best) best = g_obList[i].top;
        }
    }
    return best;
}

//+------------------------------------------------------------------+
//| Lot size from risk % and SL distance                              |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slDistancePrice) {
    double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if(slDistancePrice <= 0) return minLot;
    double lots = riskAmount / (slDistancePrice / tickSz * tickVal);
    lots = MathFloor(lots / step) * step;
    if(lots < minLot) lots = minLot;
    if(lots > maxLot) lots = maxLot;
    return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Count positions (this symbol, magic, type)                        |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type) {
    int n = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol || position.Magic() != MagicNumber || (ENUM_POSITION_TYPE)position.Type() != type) continue;
        n++;
    }
    return n;
}

//+------------------------------------------------------------------+
//| _REV positions: count and min distance from open prices (for FVG multi-entry spacing) |
//+------------------------------------------------------------------+
int CountRevPositions(bool isBuy) {
    ENUM_POSITION_TYPE type = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
    int n = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol || position.Magic() != MagicNumber || (ENUM_POSITION_TYPE)position.Type() != type) continue;
        if(StringFind(position.Comment(), "_REV") >= 0) n++;
    }
    return n;
}
double MinPipsFromRevOpens(double price, bool isBuy) {
    ENUM_POSITION_TYPE type = isBuy ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
    double minPips = 9999;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol || position.Magic() != MagicNumber || (ENUM_POSITION_TYPE)position.Type() != type) continue;
        if(StringFind(position.Comment(), "_REV") < 0) continue;
        double op = position.PriceOpen();
        double pips = MathAbs(price - op) / pipValue;
        if(pips < minPips) minPips = pips;
    }
    return (minPips >= 9999) ? 999 : minPips;
}

//+------------------------------------------------------------------+
//| Ensure tracking arrays have slot for ticket                       |
//+------------------------------------------------------------------+
int GetOrCreateTicketIndex(ulong ticket) {
    for(int i = 0; i < ArraySize(tp1Hit); i++) {
        if(position.SelectByTicket(ticket)) {
            // Match by ticket: we need to store ticket in a parallel array; for simplicity match by iterating positions
            // Actually we key by position index in the loop. So we need a map ticket -> index. Simpler: grow arrays and use ticket as key via a separate array.
            // Easiest: store tickets in array, find index by ticket.
        }
    }
    // We'll use a simpler approach: in ManagePositions we iterate and for each position we get ticket; we need to find or create slot. So keep array of tickets.
    static ulong s_tickets[];
    int idx = -1;
    for(int j = 0; j < ArraySize(s_tickets); j++) {
        if(s_tickets[j] == ticket) { idx = j; break; }
    }
    if(idx < 0) {
        idx = ArraySize(s_tickets);
        ArrayResize(s_tickets, idx + 1);
        s_tickets[idx] = ticket;
        ArrayResize(tp1Hit, idx + 1);
        ArrayResize(tp2Hit, idx + 1);
        ArrayResize(tp3Hit, idx + 1);
        ArrayResize(tp4Hit, idx + 1);
        ArrayResize(origVolume, idx + 1);
        ArrayResize(partialLevel, idx + 1);
        tp1Hit[idx] = tp2Hit[idx] = tp3Hit[idx] = tp4Hit[idx] = false;
        partialLevel[idx] = 0;
        origVolume[idx] = 0;
    }
    return idx;
}

// We need to key by ticket. So when we loop positions we have ticket; we call GetOrCreateTicketIndex(ticket) and get back index for tp1Hit etc. But GetOrCreateTicketIndex needs to store tickets. So static ulong s_tickets[] and resize. When we get a new ticket we append. When position is closed we could leave slot (no cleanup for simplicity). Good.
// Fix: GetOrCreateTicketIndex must find by ticket. So we need to pass ticket and have a static array of tickets. When not found, append ticket and return new index. Done above.

//+------------------------------------------------------------------+
//| Helpers for multi-TF OB                                           |
//+------------------------------------------------------------------+
bool OrderBlockExists(datetime obTime, double obTop, double obBottom, ENUM_TIMEFRAMES tf) {
    for(int i = 0; i < ArraySize(g_obList); i++)
        if(g_obList[i].time == obTime && MathAbs(g_obList[i].top - obTop) < point && MathAbs(g_obList[i].bottom - obBottom) < point && g_obList[i].tf == tf)
            return true;
    return false;
}
void AddOrderBlock(OrderBlock &ob) {
    int n = ArraySize(g_obList);
    ArrayResize(g_obList, n + 1);
    g_obList[n] = ob;
    int maxOB = (OB_MaxStored > 0) ? OB_MaxStored : OB_MAX;
    if(ArraySize(g_obList) > maxOB) ArrayRemove(g_obList, 0, 1);
}
void CleanOrderBlocks() {
    double close0 = iClose(_Symbol, PERIOD_M15, 0);
    for(int i = ArraySize(g_obList) - 1; i >= 0; i--) {
        if(!g_obList[i].isActive) continue;
        if(g_obList[i].isBullish && close0 < g_obList[i].bottom) g_obList[i].isActive = false;
        else if(!g_obList[i].isBullish && close0 > g_obList[i].top) g_obList[i].isActive = false;
    }
}
void DetectOrderBlocksOnTF(ENUM_TIMEFRAMES tf) {
    int bars = iBars(_Symbol, tf);
    if(bars < OB_Lookback + 5) return;
    int scanBars = OB_Lookback;
    bool doHistorical = false;
    if(tf == PERIOD_M1  && !historicalScanDone_M1  && OB_HistoricalScan > 0) { scanBars = MathMin(OB_HistoricalScan, bars - 5); doHistorical = true; historicalScanDone_M1 = true; }
    if(tf == PERIOD_M5  && !historicalScanDone_M5  && OB_HistoricalScan > 0) { scanBars = MathMin(OB_HistoricalScan, bars - 5); doHistorical = true; historicalScanDone_M5 = true; }
    if(tf == PERIOD_M15 && !historicalScanDone_M15 && OB_HistoricalScan > 0) { scanBars = MathMin(OB_HistoricalScan, bars - 5); doHistorical = true; historicalScanDone_M15 = true; }
    if(tf == PERIOD_M30 && !historicalScanDone_M30 && OB_HistoricalScan > 0) { scanBars = MathMin(OB_HistoricalScan, bars - 5); doHistorical = true; historicalScanDone_M30 = true; }
    if(tf == PERIOD_H1  && !historicalScanDone_H1  && OB_HistoricalScan > 0) { scanBars = MathMin(OB_HistoricalScan, bars - 5); doHistorical = true; historicalScanDone_H1 = true; }
    double high[], low[], open[], close[];
    ArraySetAsSeries(high, true); ArraySetAsSeries(low, true); ArraySetAsSeries(open, true); ArraySetAsSeries(close, true);
    int total = scanBars + OB_Lookback + 5;
    if(CopyHigh(_Symbol, tf, 0, total, high) < total) return;
    CopyLow(_Symbol, tf, 0, total, low); CopyOpen(_Symbol, tf, 0, total, open); CopyClose(_Symbol, tf, 0, total, close);
    double zonePips = OB_ZonePips * pipValue;
    for(int i = 2; i < scanBars - 2 && i < ArraySize(high) - 3; i++) {
        if(close[i] < open[i]) {
            double obTop = high[i], obBot = low[i];
            if(obTop <= obBot) continue;
            bool moveUp = (close[i-1] > high[i] && close[i-2] > close[i]);
            if(moveUp && !OrderBlockExists(iTime(_Symbol, tf, i), obTop, obBot, tf)) {
                OrderBlock ob;
                ob.top = obTop + zonePips; ob.bottom = obBot - zonePips; ob.time = iTime(_Symbol, tf, i); ob.isBullish = true; ob.isActive = true; ob.tf = tf;
                AddOrderBlock(ob);
            }
        }
        if(close[i] > open[i]) {
            double obTop = high[i], obBot = low[i];
            if(obTop <= obBot) continue;
            bool moveDn = (close[i-1] < low[i] && close[i-2] < close[i]);
            if(moveDn && !OrderBlockExists(iTime(_Symbol, tf, i), obTop, obBot, tf)) {
                OrderBlock ob;
                ob.top = obTop + zonePips; ob.bottom = obBot - zonePips; ob.time = iTime(_Symbol, tf, i); ob.isBullish = false; ob.isActive = true; ob.tf = tf;
                AddOrderBlock(ob);
            }
        }
    }
    CleanOrderBlocks();
}
void DetectOrderBlocks() {
    if(UseM1_OB)  DetectOrderBlocksOnTF(PERIOD_M1);
    if(UseM5_OB)  DetectOrderBlocksOnTF(PERIOD_M5);
    if(UseM15_OB) DetectOrderBlocksOnTF(PERIOD_M15);
    if(UseM30_OB) DetectOrderBlocksOnTF(PERIOD_M30);
    if(UseH1_OB)  DetectOrderBlocksOnTF(PERIOD_H1);
}

//+------------------------------------------------------------------+
//| Engulfing on OB timeframe (current bar)                           |
//+------------------------------------------------------------------+
bool IsBullishEngulfing() {
    double o0 = iOpen(_Symbol, PERIOD_M15, 1), c0 = iClose(_Symbol, PERIOD_M15, 1);
    double o1 = iOpen(_Symbol, PERIOD_M15, 2), c1 = iClose(_Symbol, PERIOD_M15, 2);
    return (c0 > o0 && o1 > c1 && o0 <= c1 && c0 >= o1);
}
bool IsBearishEngulfing() {
    double o0 = iOpen(_Symbol, PERIOD_M15, 1), c0 = iClose(_Symbol, PERIOD_M15, 1);
    double o1 = iOpen(_Symbol, PERIOD_M15, 2), c1 = iClose(_Symbol, PERIOD_M15, 2);
    return (c0 < o0 && c1 > o1 && o0 >= c1 && c0 <= o1);
}

//+------------------------------------------------------------------+
//| Open BUY with optional setup comment (e.g. _OB, _SS, _TL_BR, _TL_OB, _REV, _DC) |
//+------------------------------------------------------------------+
bool OpenBuyEx(double slPrice, string setupSuffix) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double sl  = (slPrice > 0) ? NormalizeDouble(slPrice, symbolDigits) : NormalizeDouble(ask - SL_Pips * pipValue, symbolDigits);
    long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stopsLevel > 0) {
        double minDist = (double)stopsLevel * point;
        if(ask - sl < minDist) sl = NormalizeDouble(ask - minDist, symbolDigits);
    }
    double riskAmt = accountBalance * (RiskPercent / 100.0);
    double lot     = CalculateLotSize(riskAmt, ask - sl);
    string cmt = TradeComment + setupSuffix;
    if(StringLen(UserName) > 0) cmt += "|U:" + UserName;
    if(trade.Buy(lot, _Symbol, ask, sl, 0, cmt)) {
        Print("Fresh BUY ", setupSuffix, " @ ", ask, " SL ", sl, " lots ", lot);
        return true;
    }
    return false;
}

bool OpenSellEx(double slPrice, string setupSuffix) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl  = (slPrice > 0) ? NormalizeDouble(slPrice, symbolDigits) : NormalizeDouble(bid + SL_Pips * pipValue, symbolDigits);
    long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stopsLevel > 0) {
        double minDist = (double)stopsLevel * point;
        if(sl - bid < minDist) sl = NormalizeDouble(bid + minDist, symbolDigits);
    }
    double riskAmt = accountBalance * (RiskPercent / 100.0);
    double lot     = CalculateLotSize(riskAmt, sl - bid);
    string cmt = TradeComment + setupSuffix;
    if(StringLen(UserName) > 0) cmt += "|U:" + UserName;
    if(trade.Sell(lot, _Symbol, bid, sl, 0, cmt)) {
        Print("Fresh SELL ", setupSuffix, " @ ", bid, " SL ", sl, " lots ", lot);
        return true;
    }
    return false;
}

void OpenBuy(OrderBlock &ob) { OpenBuyEx(0, "_OB"); }
void OpenSell(OrderBlock &ob) { OpenSellEx(0, "_OB"); }

//+------------------------------------------------------------------+
//| Try all entry models (same entry model – order of priority)       |
//+------------------------------------------------------------------+
void TryEntries() {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double touch = OB_TouchPips * pipValue;
    double tlTouch = TL_TouchPips * pipValue;
    int buys  = CountPositions(POSITION_TYPE_BUY);
    int sells = CountPositions(POSITION_TYPE_SELL);
    int total = buys + sells;
    if(total >= MaxTotalPositions) return;   // Hard cap so we don’t max out margin
    if(buys >= MaxPositionsPerSide && sells >= MaxPositionsPerSide) return;

    if(UseEntry_TL_BreakRetest || UseEntry_TL_OB || UseEntry_DoubleConfluence) {
        UpdateTrendLine();
        if(UseM1_TL_Confluence) UpdateTrendLineM1();
    }
    static bool s_tlWasAbove = false;
    bool nearTLResist = (g_tlResistPrice > 0 && ask >= g_tlResistPrice - tlTouch && ask <= g_tlResistPrice + tlTouch);
    bool nearTLSupport = (g_tlSupportPrice > 0 && bid >= g_tlSupportPrice - tlTouch && bid <= g_tlSupportPrice + tlTouch);
    bool nearTLResistM1 = (g_tlResistPriceM1 > 0 && bid <= g_tlResistPriceM1 + tlTouch && bid >= g_tlResistPriceM1 - tlTouch);
    bool nearTLSupportM1 = (g_tlSupportPriceM1 > 0 && ask >= g_tlSupportPriceM1 - tlTouch && ask <= g_tlSupportPriceM1 + tlTouch);
    if(g_tlResistPrice > 0 && ask > g_tlResistPrice + tlTouch) s_tlWasAbove = true;
    if(g_tlResistPrice > 0 && ask < g_tlResistPrice - tlTouch && s_tlWasAbove) { /* retest zone */ }

    bool bosOkBuy  = !UseMarketStructure || !RequireBOS || marketStruct.trend == 1;
    bool bosOkSell = !UseMarketStructure || !RequireBOS || marketStruct.trend == -1;
    bool dcM1OkBuy  = !UseM1_TL_Confluence || nearTLSupportM1;
    bool dcM1OkSell = !UseM1_TL_Confluence || nearTLResistM1;

    // 1) Double confluence: trend line tap + OB touch (optional: at Asia open, optional M1 TL) → target London open
    double dcTol = OB_TouchPips * pipValue;
    bool atAsiaSupport = (!DC_RequireAsiaOpen || asiaOpenPrice <= 0) || (ask >= asiaOpenPrice - dcTol && ask <= asiaOpenPrice + dcTol);
    bool atAsiaResist  = (!DC_RequireAsiaOpen || asiaOpenPrice <= 0) || (bid >= asiaOpenPrice - dcTol && bid <= asiaOpenPrice + dcTol);
    if(UseEntry_DoubleConfluence && UseSessionLevels && buys < MaxPositionsPerSide && londonOpenPrice > 0 &&
       bosOkBuy && nearTLSupport && dcM1OkBuy && atAsiaSupport && SessionSweepHasBullishEngulfing()) {
        for(int i = 0; i < ArraySize(g_obList); i++) {
            if(!g_obList[i].isActive || !g_obList[i].isBullish) continue;
            if(OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFSupport(g_obList[i].bottom, g_obList[i].top)) continue;
            bool atOB = (ask >= g_obList[i].bottom - touch && ask <= g_obList[i].top + touch);
            if(atOB && OpenBuyEx(0, "_DC")) return;
        }
    }
    if(UseEntry_DoubleConfluence && UseSessionLevels && sells < MaxPositionsPerSide && londonOpenPrice > 0 &&
       bosOkSell && nearTLResist && dcM1OkSell && atAsiaResist && SessionSweepHasBearishEngulfing()) {
        for(int i = 0; i < ArraySize(g_obList); i++) {
            if(!g_obList[i].isActive || g_obList[i].isBullish) continue;
            if(OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFResistance(g_obList[i].bottom, g_obList[i].top)) continue;
            bool atOB = (bid >= g_obList[i].bottom - touch && bid <= g_obList[i].top + touch);
            if(atOB && OpenSellEx(0, "_DC")) return;
        }
    }

    // 2a) HK aftermarket close retest (magnet level) + engulfing → target London open
    if(UseEntry_HKCloseRetest && UseSessionLevels && hkClosePrice > 0) {
        double hkTol = OB_TouchPips * pipValue;
        if(buys < MaxPositionsPerSide && bosOkBuy && MathAbs(ask - hkClosePrice) <= hkTol && SessionSweepHasBullishEngulfing()) {
            if(OpenBuyEx(0, "_HK")) return;
        }
        if(sells < MaxPositionsPerSide && bosOkSell && MathAbs(bid - hkClosePrice) <= hkTol && SessionSweepHasBearishEngulfing()) {
            if(OpenSellEx(0, "_HK")) return;
        }
    }

    // 2b) Session sweep: London low/high rejection sweep + retest + engulfing
    if(UseEntry_SessionSweep && UseSessionLevels && londonLow > 0 && londonHigh > 0) {
        double tol = OB_TouchPips * pipValue;
        if(buys < MaxPositionsPerSide && bosOkBuy && londonLowSwept && MathAbs(ask - londonLow) <= tol && SessionSweepHasBullishEngulfing()) {
            if(OpenBuyEx(NormalizeDouble(ask - SL_Pips * pipValue, symbolDigits), "_SS")) return;
        }
        if(sells < MaxPositionsPerSide && bosOkSell && londonHighSwept && MathAbs(bid - londonHigh) <= tol && SessionSweepHasBearishEngulfing()) {
            if(OpenSellEx(NormalizeDouble(bid + SL_Pips * pipValue, symbolDigits), "_SS")) return;
        }
    }

    // 2c) Session/range breakout: break above high or below low, then retest + engulfing → _BO (target London open)
    if(UseEntry_SessionBreakout && UseSessionLevels) {
        double breakoutHigh = (londonHigh > 0) ? londonHigh : 0;
        double breakoutLow  = (londonLow > 0)  ? londonLow  : 0;
        if(Breakout_UseRangeWhenNoLondon && Breakout_LookbackBars >= 2) {
            double rh = 0, rl = 0;
            int n = MathMin(Breakout_LookbackBars, 500);
            for(int i = 1; i <= n; i++) {
                double hi = iHigh(_Symbol, PERIOD_M15, i), lo = iLow(_Symbol, PERIOD_M15, i);
                if(rh == 0) rh = hi; else if(hi > rh) rh = hi;
                if(rl == 0) rl = lo; else if(lo < rl) rl = lo;
            }
            if(breakoutHigh <= 0) breakoutHigh = rh;
            if(breakoutLow <= 0)  breakoutLow  = rl;
        }
        double retestTol = Breakout_RetestPips * pipValue;
        double slBeyond  = Breakout_SL_Pips * pipValue;
        static bool brokeAboveSession = false, brokeBelowSession = false;
        if(breakoutHigh > 0 && ask > breakoutHigh + retestTol) brokeAboveSession = true;
        if(breakoutLow > 0 && bid < breakoutLow - retestTol) brokeBelowSession = true;
        if(breakoutHigh > 0 && buys < MaxPositionsPerSide && bosOkBuy && brokeAboveSession &&
           ask >= breakoutHigh - retestTol && ask <= breakoutHigh + retestTol && SessionSweepHasBullishEngulfing()) {
            double sl = NormalizeDouble(breakoutHigh - slBeyond, symbolDigits);
            if(OpenBuyEx(sl, "_BO")) { brokeAboveSession = false; return; }
        }
        if(breakoutLow > 0 && sells < MaxPositionsPerSide && bosOkSell && brokeBelowSession &&
           bid >= breakoutLow - retestTol && bid <= breakoutLow + retestTol && SessionSweepHasBearishEngulfing()) {
            double sl = NormalizeDouble(breakoutLow + slBeyond, symbolDigits);
            if(OpenSellEx(sl, "_BO")) { brokeBelowSession = false; return; }
        }
        if(breakoutHigh > 0 && ask < breakoutHigh - retestTol * 2) brokeAboveSession = false;
        if(breakoutLow > 0 && bid > breakoutLow + retestTol * 2) brokeBelowSession = false;
    }

    // 3) Trend line resistance break then retest → BUY
    if(UseEntry_TL_BreakRetest && g_tlResistPrice > 0 && buys < MaxPositionsPerSide && bosOkBuy) {
        static bool brokeAbove = false;
        if(ask > g_tlResistPrice + tlTouch) brokeAbove = true;
        if(brokeAbove && nearTLResist && SessionSweepHasBullishEngulfing()) {
            if(OpenBuyEx(0, "_TL_BR")) { brokeAbove = false; return; }
        }
        if(ask < g_tlResistPrice - tlTouch * 2) brokeAbove = false;
    }
    if(UseEntry_TL_BreakRetest && g_tlSupportPrice > 0 && sells < MaxPositionsPerSide && bosOkSell) {
        static bool brokeBelow = false;
        if(bid < g_tlSupportPrice - tlTouch) brokeBelow = true;
        if(brokeBelow && nearTLSupport && SessionSweepHasBearishEngulfing()) {
            if(OpenSellEx(0, "_TL_BR")) { brokeBelow = false; return; }
        }
        if(bid > g_tlSupportPrice + tlTouch * 2) brokeBelow = false;
    }

    // 4) Trend line tap at OB (optional M1 TL confluence); target nearest OB
    bool tlObM1Buy  = !UseM1_TL_Confluence || nearTLSupportM1;
    bool tlObM1Sell = !UseM1_TL_Confluence || nearTLResistM1;
    if(UseEntry_TL_OB && buys < MaxPositionsPerSide && bosOkBuy && nearTLSupport && tlObM1Buy && SessionSweepHasBullishEngulfing()) {
        for(int i = 0; i < ArraySize(g_obList); i++) {
            if(!g_obList[i].isActive || !g_obList[i].isBullish) continue;
            if(OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFSupport(g_obList[i].bottom, g_obList[i].top)) continue;
            if(ask >= g_obList[i].bottom - touch && ask <= g_obList[i].top + touch && OpenBuyEx(0, "_TL_OB")) return;
        }
    }
    if(UseEntry_TL_OB && sells < MaxPositionsPerSide && bosOkSell && nearTLResist && tlObM1Sell && SessionSweepHasBearishEngulfing()) {
        for(int i = 0; i < ArraySize(g_obList); i++) {
            if(!g_obList[i].isActive || g_obList[i].isBullish) continue;
            if(OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFResistance(g_obList[i].bottom, g_obList[i].top)) continue;
            if(bid >= g_obList[i].bottom - touch && bid <= g_obList[i].top + touch && OpenSellEx(0, "_TL_OB")) return;
        }
    }

    // 5) Reversal: FVG zone + engulfing; up to REV_MaxEntries, REV_EntrySpacingPips apart; SL below/above FVG
    if(UseEntry_Reversal) {
        DetectFVG();
        bool revBuyOk = (!Reversal_RequireM5Rejection || M5BullishRejectionCandle()) && bosOkBuy;
        bool revSellOk = (!Reversal_RequireM5Rejection || M5BearishRejectionCandle()) && bosOkSell;
        int revBuys = CountRevPositions(true), revSells = CountRevPositions(false);
        double revSpacing = REV_EntrySpacingPips * pipValue;
        double revBuffer = REV_SLBufferPips * pipValue;
        for(int f = 0; f < ArraySize(g_fvgs); f++) {
            if(!g_fvgs[f].isActive) continue;
            if(g_fvgs[f].isBullish && buys < MaxPositionsPerSide && revBuys < REV_MaxEntries && revBuyOk &&
               (revBuys == 0 || MinPipsFromRevOpens(ask, true) >= REV_EntrySpacingPips) &&
               ask >= g_fvgs[f].bottom && ask <= g_fvgs[f].top && SessionSweepHasBullishEngulfing()) {
                double slRev = REV_SLBelowFVG ? NormalizeDouble(g_fvgs[f].bottom - revBuffer, symbolDigits) : 0;
                if(OpenBuyEx(slRev, "_REV")) return;
            }
            if(!g_fvgs[f].isBullish && sells < MaxPositionsPerSide && revSells < REV_MaxEntries && revSellOk &&
               (revSells == 0 || MinPipsFromRevOpens(bid, false) >= REV_EntrySpacingPips) &&
               bid >= g_fvgs[f].bottom && bid <= g_fvgs[f].top && SessionSweepHasBearishEngulfing()) {
                double slRev = REV_SLBelowFVG ? NormalizeDouble(g_fvgs[f].top + revBuffer, symbolDigits) : 0;
                if(OpenSellEx(slRev, "_REV")) return;
            }
        }
    }

    // 6) OB (original) – multi-TF, optional HTF alignment
    if(UseEntry_OB) {
        for(int i = 0; i < ArraySize(g_obList); i++) {
            if(!g_obList[i].isActive) continue;
            if(g_obList[i].isBullish && buys < MaxPositionsPerSide && bosOkBuy) {
                if(OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFSupport(g_obList[i].bottom, g_obList[i].top)) continue;
                bool inZone = (ask >= g_obList[i].bottom && ask <= g_obList[i].top);
                bool nearZone = (ask < g_obList[i].bottom && g_obList[i].bottom - ask <= touch) || (ask > g_obList[i].top && ask - g_obList[i].top <= touch);
                if((inZone || nearZone) && (!RequireEngulfing || IsBullishEngulfing())) {
                    OpenBuy(g_obList[i]);
                    return;
                }
            }
            if(!g_obList[i].isBullish && sells < MaxPositionsPerSide && bosOkSell) {
                if(OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFResistance(g_obList[i].bottom, g_obList[i].top)) continue;
                bool inZone = (bid >= g_obList[i].bottom && bid <= g_obList[i].top);
                bool nearZone = (bid < g_obList[i].bottom && g_obList[i].bottom - bid <= touch) || (bid > g_obList[i].top && bid - g_obList[i].top <= touch);
                if((inZone || nearZone) && (!RequireEngulfing || IsBearishEngulfing())) {
                    OpenSell(g_obList[i]);
                    return;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage open positions: BE, TP1–TP4, trail                         |
//+------------------------------------------------------------------+
void ManagePositions() {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol || position.Magic() != MagicNumber) continue;
        ulong ticket = position.Ticket();
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentVol = position.Volume();
        bool isBuy = (position.Type() == (long)POSITION_TYPE_BUY);
        double currentPrice = isBuy ? bid : ask;
        double profitPips = isBuy ? (currentPrice - openPrice) / pipValue : (openPrice - currentPrice) / pipValue;
        int idx = GetOrCreateTicketIndex(ticket);
        if(idx >= ArraySize(origVolume) || origVolume[idx] <= 0) origVolume[idx] = currentVol;
        double origVol = origVolume[idx];
        int level = partialLevel[idx];

        // --- BE (optional; _REV uses REV_BEPips, others use BreakEvenPips) ---
        if(UseBreakEven && profitPips > 0) {
            double bePips = (StringFind(position.Comment(), "_REV") >= 0) ? REV_BEPips : BreakEvenPips;
            if(bePips > 0 && profitPips >= bePips) {
                double newSL = NormalizeDouble(openPrice, symbolDigits);
                if(isBuy && (currentSL < newSL - point || currentSL == 0)) {
                    if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
                        Print("Fresh BE set BUY #", ticket);
                }
                if(!isBuy && (currentSL > newSL + point || currentSL == 0)) {
                    if(trade.PositionModify(ticket, newSL, position.TakeProfit()))
                        Print("Fresh BE set SELL #", ticket);
                }
            }
        }

        // --- GUARANTEED: close ANY position at cap (so reversals/sweeps don’t give back 1000 pips; breakouts already work) ---
        if(UseForceCloseAtCap) {
            double capPips = (MaxSetupTargetPips > 0) ? MaxSetupTargetPips : 200.0;
            if(profitPips >= capPips * 0.95) {
                if(trade.PositionClose(ticket)) {
                    Print("Fresh TP cap #", ticket, " ", profitPips, " pips");
                    continue;
                }
                Print("Fresh TP cap FAILED #", ticket, " profitPips=", profitPips, " cap=", capPips);
            }
        }

        // --- Setup-based TP: _SS/_DC/_REV/_TL_BR → London open; _TL_OB → nearest OB or London open ---
        string cmt = position.Comment();
        if(UseSetupBasedTP) {
            double targetPrice = 0;
            bool useLondon = (londonOpenPrice > 0 && (StringFind(cmt, "_SS") >= 0 || StringFind(cmt, "_DC") >= 0 || StringFind(cmt, "_REV") >= 0 || StringFind(cmt, "_TL_BR") >= 0 || StringFind(cmt, "_HK") >= 0 || StringFind(cmt, "_BO") >= 0));
            if(StringFind(cmt, "_TL_OB") >= 0) {
                double obTarget = GetNearestOBTarget(openPrice, isBuy);
                if(obTarget > 0) targetPrice = obTarget;
                else if(londonOpenPrice > 0) targetPrice = londonOpenPrice;
            } else if(useLondon) targetPrice = londonOpenPrice;
            if(targetPrice > 0) {
                double targetPips = (targetPrice - openPrice) / pipValue;
                if(!isBuy) targetPips = (openPrice - targetPrice) / pipValue;
                if(targetPips > 5) {
                    double effectiveTarget = (MaxSetupTargetPips > 0 && targetPips > MaxSetupTargetPips) ? MaxSetupTargetPips : targetPips;
                    if(profitPips >= effectiveTarget * 0.95) {
                        if(trade.PositionClose(ticket))
                            Print("Fresh setup-based TP #", ticket, " ", profitPips, " pips (cap ", effectiveTarget, ")");
                        continue;
                    }
                }
            }
        }

        // --- TP1–TP4 partials: unlock as soon as profit >= TP1_Pips (don't require BE first) ---
        if(profitPips <= 0) continue;
        if(level == 0 && profitPips >= TP1_Pips) { tp1Hit[idx] = true; }
        if(!tp1Hit[idx]) continue;

        double closeVol = 0;
        if(level == 0 && profitPips >= TP1_Pips) {
            closeVol = MathFloor(origVol * 0.25 / lotStep) * lotStep;
            if(closeVol < minLot) closeVol = minLot;
            if(closeVol >= currentVol - minLot*0.5) closeVol = currentVol - minLot;
        } else if(level == 1 && profitPips >= TP2_Pips) {
            closeVol = MathFloor(origVol * 0.25 / lotStep) * lotStep;
            if(closeVol < minLot) closeVol = minLot;
            if(closeVol >= currentVol - minLot*0.5) closeVol = currentVol - minLot;
        } else if(level == 2 && profitPips >= TP3_Pips) {
            closeVol = MathFloor(origVol * 0.25 / lotStep) * lotStep;
            if(closeVol < minLot) closeVol = minLot;
            if(closeVol >= currentVol - minLot*0.5) closeVol = currentVol - minLot;
        } else         if(level == 3 && profitPips >= TP4_Pips) {
            closeVol = currentVol;
        }
        if(closeVol >= minLot && closeVol <= currentVol) {
            if(closeVol >= currentVol - lotStep*0.5) {
                if(trade.PositionClose(ticket)) {
                    partialLevel[idx]++; tp4Hit[idx] = true;
                    Print("Fresh TP4 full close #", ticket);
                }
            } else if(trade.PositionClosePartial(ticket, closeVol)) {
                partialLevel[idx]++;
                if(level == 3) tp4Hit[idx] = true;
                Print("Fresh TP", (level+1), " closed ", closeVol, " #", ticket);
            } else {
                // Tester/some brokers: partial close can fail – fallback full close so we still take profit
                if(trade.PositionClose(ticket)) {
                    partialLevel[idx]++; tp4Hit[idx] = true;
                    Print("Fresh TP", (level+1), " full close (partial failed) #", ticket);
                }
            }
            continue;
        }

        // --- Trail ---
        if(UseTrailSL && profitPips >= TrailStartPips) {
            double trailDist = TrailDistancePips * pipValue;
            double newSL = 0;
            if(isBuy) newSL = NormalizeDouble(bid - trailDist, symbolDigits);
            else      newSL = NormalizeDouble(ask + trailDist, symbolDigits);
            bool improve = isBuy ? (newSL > currentSL && newSL < bid) : (newSL < currentSL && newSL > ask);
            if(improve && trade.PositionModify(ticket, newSL, position.TakeProfit()))
                Print("Fresh trail updated #", ticket, " SL ", newSL);
        }
    }
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit() {
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    pipValue = 0.1;
    accountBalance = account.Balance();
    trade.SetExpertMagicNumber(MagicNumber);
    lastBarTime = 0;
    marketStruct.trend = 0;
    marketStruct.lastBOS = 0;
    marketStruct.lastCHoCH = 0;
    if(!CheckLicense()) return INIT_FAILED;
    Print("Goldmine Fresh v3: BE=", UseBreakEven, " BE@", BreakEvenPips, " TP1-4 ", TP1_Pips, "/", TP2_Pips, "/", TP3_Pips, "/", TP4_Pips, " Cap=", MaxSetupTargetPips, " pips. Risk ", RiskPercent, "%");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick() {
    if(!CheckLicense()) return;
    accountBalance = account.Balance();
    if(UseSessionLevels) UpdateSessionLevels();
    if(OB_RequireHTFAlignment) UpdateHTFSweepLevels();
    if(UseMarketStructure) UpdateMarketStructure();
    datetime t = iTime(_Symbol, PERIOD_M15, 0);
    if(t != lastBarTime) {
        lastBarTime = t;
        DetectOrderBlocks();
    }
    ManagePositions();
    TryEntries();
}
