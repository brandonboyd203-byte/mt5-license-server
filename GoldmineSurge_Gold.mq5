//+------------------------------------------------------------------+
//|                                    GoldmineSurge_Gold.mq5        |
//|     Goldmine Surge – Gold | Breakout Channels + Volume OBs        |
//|                    Aggressive Scalping with Smart Money Concepts |
//|                                                                   |
//| Features:                                                        |
//| - Breakout Channel Detection (Normalized Price + Volatility)     |
//| - Volume Order Blocks (EMA Crossover Based)                      |
//| - Engulfing Candle Detection (Bullish/Bearish)                   |
//| - Aggressive Scalping (Quick Entries/Exits)                      |
//| - Volume Analysis Integration                                    |
//| - Gold (XAUUSD) – BE/TP 1 pip = 0.1                             |
//|                                                                   |
//| IMPORTANT: Pip to Points Conversion (MT5 uses points, not pips!) |
//| FOR GOLD (XAUUSD): 1 pip = 100 points, 20 pips = 2000 points    |
//+------------------------------------------------------------------+
#property copyright "Goldmine Surge"
#property link      ""
#property version   "1.00"
#property description "Goldmine Surge – Gold. Breakout Channels + Volume OBs. XAUUSD."
#property description "Aggressive scalping with smart money concepts"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CPositionInfo position;
CAccountInfo account;

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double RiskPerTrade = 1.5;             // Risk per trade (% of equity) - DEFAULT: 1.5%
input bool UseEquity = true;                  // Use Equity (true) or Balance (false)
input int AccountLeverage = 999999;           // Account leverage (999999 = unlimited)

input group "=== Stop Loss & Take Profit ==="
input double SL_Pips = 15.0;                 // Stop Loss (pips) - Base SL
input double TP_Pips = 30.0;                // Take Profit (pips) - Quick scalping
input bool UseDynamicSL = true;              // Use ATR-based dynamic SL (wider in volatile markets)
input double DynamicSL_ATR_Multiplier = 1.5; // ATR multiplier for dynamic SL (1.5 = 1.5x ATR)
input int DynamicSL_ATR_Period = 14;        // ATR period for dynamic SL
input double DynamicSL_MinPips = 12.0;      // Minimum SL (pips) even if ATR is smaller
input double DynamicSL_MaxPips = 25.0;      // Maximum SL (pips) even if ATR is larger
input double MinRR_Ratio = 1.5;             // Minimum Risk:Reward ratio (1.5 = 1.5:1, 0 = disabled)
input bool UseBreakEven = true;              // Enable break-even
input double BreakEvenPips = 10.0;           // Move to BE at this many pips profit
input bool UsePartialClose = true;           // Enable partial profit taking
input double PartialClosePips = 20.0;        // Partial close at this many pips
input double PartialClosePercent = 50.0;     // % to close at partial TP
input double RunnerPercent = 10.0;           // % to keep as runner

input group "=== Breakout Channel Settings ==="
input bool UseBreakoutChannels = true;       // Enable breakout channel trading
input int NormalizationLength = 100;         // Bars for price normalization
input int ChannelDetectionLength = 14;       // Bars for channel detection
input bool StrongClosesOnly = true;           // Require >50% candle body outside channel
input double ChannelMinDuration = 10;       // Minimum channel duration (bars)

input group "=== Volume Order Block Settings ==="
input bool UseVolumeOB = true;               // Enable volume order block trading
input int FastEMA = 5;                       // Fast EMA period
input int SlowEMA = 18;                      // Slow EMA period (Fast + 13)
input double OB_ATR_Multiplier = 2.0;        // ATR multiplier for OB size
input int OB_ATR_Period = 200;               // ATR period for OB sizing
input double OB_MinVolumePercent = 1.0;      // Minimum volume % to trade OB (lower = more aggressive)
input bool UseFallbackOBScan = true;         // Fallback: detect OBs from volume spikes (recommended)
input int OB_FallbackScanBars = 150;         // Bars to scan for fallback OBs (on PrimaryTF)
input int OB_VolumeAvgPeriod = 30;           // Avg volume period for spike detection
input double OB_VolumeSpikeMult = 1.5;       // Volume spike multiplier (lower = more OBs)
input double OB_MinBodyPips = 2.0;           // Minimum candle body size (pips) for fallback OB

input group "=== Entry Settings ==="
input bool TradeBreakouts = true;            // Trade channel breakouts
input bool TradeOB_Retests = true;           // Trade order block retests
input bool WaitForConfirmation = false;      // Wait for candle close
input double EntryZonePips = 10.0;           // Entry zone size (pips) - wider = more opportunities
input int MaxEntries = 5;                    // Maximum entries per direction (more aggressive)
input int MinConfluenceFactors = 3;          // Minimum confluence factors required (1=OB only, 2=OB+Engulfing, 3=stricter)
input bool RequireMomentum = true;            // Require strong price momentum before entry
input double MomentumMinPips = 3.0;          // Minimum price movement (pips) in last 2 bars for momentum
input double MaxSpreadPips = 2.0;            // Maximum spread (pips) to allow trading (0 = disabled)
input bool UseVolatilityFilter = true;       // Block trades during extreme volatility
input double VolatilityATR_Multiplier = 2.5; // ATR multiplier for volatility filter (2.5 = very volatile)
input bool RequireTrendFilter = true;         // Only trade with trend (EMA-based)
input int TrendEMA_Period = 50;              // EMA period for trend detection
input int MaxDailyTrades = 20;               // Maximum trades per day (0 = unlimited)
input double MinWinRatePercent = 40.0;       // Minimum win rate (%) to continue trading (0 = disabled)
input int WinRateLookbackTrades = 10;        // Number of recent trades to calculate win rate
input bool RequireVolumeConfirmation = true;  // Require increasing volume for entry
input int VolumeConfirmationBars = 3;         // Bars to check for volume increase
input bool RequireConfluence = true;          // Require multiple confirmations (OB + Engulfing or Channel + Volume)
input int MinConfluenceFactors = 2;          // Minimum confluence factors required (1=OB only, 2=OB+Engulfing, etc.)

input group "=== Loss Protection ==="
input bool UseLossStreakProtection = true;    // Pause trading after consecutive losses
input int MaxConsecutiveLosses = 3;          // Maximum consecutive losses before pause
input int LossStreakPauseMinutes = 30;       // Minutes to pause after loss streak
input double MaxDailyLossPercent = 5.0;      // Maximum daily loss (%) before stopping
input bool ResetDailyLossAtMidnight = true;  // Reset daily loss counter at midnight

input group "=== Time Filters ==="
input bool UseTimeFilter = true;              // Enable time-based trading filter
input int StartHour = 0;                     // Start trading hour (0-23)
input int EndHour = 23;                      // End trading hour (0-23)
input bool AvoidLowLiquidity = true;         // Avoid trading during low liquidity hours
input int LowLiquidityStart = 22;            // Low liquidity start hour (22 = 10 PM)
input int LowLiquidityEnd = 2;              // Low liquidity end hour (2 = 2 AM)

input group "=== Engulfing Candle Detection ==="
input bool UseEngulfingCandles = true;       // Enable engulfing candle detection
input bool RequireEngulfingForEntry = false; // Require engulfing for entry (false = confluence only)
input bool EngulfingWithTrend = false;       // Only bullish in uptrend, bearish in downtrend
input int EngulfingTrendPeriod = 50;        // SMA period for trend detection (0 = no trend filter)

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES PrimaryTF = PERIOD_M5; // Primary timeframe
input ENUM_TIMEFRAMES VolumeTF = PERIOD_M1;  // Volume analysis timeframe
input bool UseM1_OB = true;                  // Detect/trade OBs from M1
input bool UseM3_OB = true;                  // Detect/trade OBs from M3
input bool UseM5_OB = true;                  // Detect/trade OBs from M5

input group "=== News Filter ==="
input bool BlockTradesDuringNews = true;     // Block trades during news
input int NewsBlockMinutesBefore = 5;        // Minutes before news
input int NewsBlockMinutesAfter = 15;        // Minutes after news

input group "=== License Protection ==="
input bool EnableLicenseCheck = true;         // Enable license protection
input string LicenseServerURL = "https://mt5-license-server-production.up.railway.app"; // License Server URL
input string LicenseKey = "";                 // License Key (optional)
input string AllowedAccounts = "";           // Allowed Account Numbers (fallback)
input string AllowedBrokers = "";            // Allowed Brokers/Servers (fallback)
input datetime LicenseExpiry = 0;            // License Expiry Date (fallback - 0 = no expiry)
input string UserName = "";                  // User Name (for tracking)
input bool UseRemoteValidation = true;        // Use remote server validation
input int LicenseCheckTimeout = 5;            // License check timeout (seconds)

input group "=== General ==="
input int MagicNumber = 123458;              // Magic number
input string TradeComment = "Goldmine Surge – Gold";  // Trade comment
input int Slippage = 10;                     // Slippage in points

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
struct BreakoutChannel {
    double top;
    double bottom;
    double midline;
    datetime startTime;
    int startBar;
    bool isActive;
    double volume;
};

struct VolumeOrderBlock {
    double top;
    double bottom;
    double mid;
    datetime time;
    int barIndex;
    bool isBullish;
    bool isActive;
    double volume;
    double volumePercent;
    ENUM_TIMEFRAMES tf;
};

BreakoutChannel channels[];
VolumeOrderBlock orderBlocks[];

double point;
int symbolDigits;
int recentTradesHistory[];                   // Track recent trades for win rate
double recentTradesProfit[];                // Track recent trade profits
double pipValue;
datetime lastBarTime = 0;

// Per-timeframe tracking so we can scalp on M1/M3/M5 all day
datetime lastBarTime_M1 = 0;
datetime lastBarTime_M3 = 0;

// Loss protection tracking
int consecutiveLosses = 0;
datetime lossStreakPauseUntil = 0;
double dailyLossAmount = 0;
datetime lastDailyReset = 0;
int totalTradesToday = 0;
int winningTradesToday = 0;
datetime lastBarTime_M5 = 0;
datetime lastFallbackScanBarTime_M1 = 0;
datetime lastFallbackScanBarTime_M3 = 0;
datetime lastFallbackScanBarTime_M5 = 0;

//+------------------------------------------------------------------+
//| Helper: prevent duplicate OB zones                               |
//+------------------------------------------------------------------+
bool OBExists(double top, double bottom, bool isBullish, ENUM_TIMEFRAMES tf) {
    double tol = 1.0 * pipValue; // 1 pip tolerance
    for(int i=0;i<ArraySize(orderBlocks);i++) {
        if(!orderBlocks[i].isActive) continue;
        if(orderBlocks[i].isBullish != isBullish) continue;
        if(orderBlocks[i].tf != tf) continue;
        if(MathAbs(orderBlocks[i].top - top) <= tol && MathAbs(orderBlocks[i].bottom - bottom) <= tol) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Detect Volume Order Blocks on a specific timeframe                |
//+------------------------------------------------------------------+
void DetectVolumeOrderBlocksOnTF(ENUM_TIMEFRAMES tf, datetime &lastFallbackScanBarTimeRef) {
    int bars = iBars(_Symbol, tf);
    if(bars < SlowEMA + OB_ATR_Period) return;

    double emaFast[], emaSlow[];
    ArraySetAsSeries(emaFast, true);
    ArraySetAsSeries(emaSlow, true);
    CopyBuffer(iMA(_Symbol, tf, FastEMA, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 50, emaFast);
    CopyBuffer(iMA(_Symbol, tf, SlowEMA, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 50, emaSlow);

    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(iATR(_Symbol, tf, OB_ATR_Period), 0, 0, 50, atr);

    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, tf, 0, SlowEMA + 10, high);
    CopyLow(_Symbol, tf, 0, SlowEMA + 10, low);
    CopyClose(_Symbol, tf, 0, SlowEMA + 10, close);
    CopyOpen(_Symbol, tf, 0, SlowEMA + 10, open);

    // Detect EMA crossovers (per-tf)
    static bool prevCrossUp_M1=false, prevCrossDn_M1=false;
    static bool prevCrossUp_M3=false, prevCrossDn_M3=false;
    static bool prevCrossUp_M5=false, prevCrossDn_M5=false;

    bool prevUp = false;
    bool prevDn = false;
    if(tf == PERIOD_M1) { prevUp = prevCrossUp_M1; prevDn = prevCrossDn_M1; }
    else if(tf == PERIOD_M3) { prevUp = prevCrossUp_M3; prevDn = prevCrossDn_M3; }
    else { prevUp = prevCrossUp_M5; prevDn = prevCrossDn_M5; }

    bool crossUp = (emaFast[1] <= emaSlow[1] && emaFast[0] > emaSlow[0]);
    bool crossDn = (emaFast[1] >= emaSlow[1] && emaFast[0] < emaSlow[0]);

    if(crossUp && !prevUp) {
        double lowest = low[0];
        int lowestBar = 0;
        for(int i = 1; i <= SlowEMA; i++) {
            if(low[i] < lowest) { lowest = low[i]; lowestBar = i; }
        }
        long volume[];
        ArraySetAsSeries(volume, true);
        CopyTickVolume(_Symbol, tf, 0, lowestBar + 1, volume);
        double obVolume = 0;
        for(int i = 0; i <= lowestBar; i++) obVolume += (double)volume[i];

        double atrValue = atr[0] * OB_ATR_Multiplier;
        double obTop = MathMax(open[lowestBar], close[lowestBar]);
        if((obTop - lowest) < atrValue * 0.5) obTop = lowest + atrValue * 0.5;
        double obMid = (obTop + lowest) / 2.0;

        if(!OBExists(obTop, lowest, true, tf)) {
            VolumeOrderBlock ob;
            ob.top = obTop; ob.bottom = lowest; ob.mid = obMid;
            ob.time = iTime(_Symbol, tf, lowestBar);
            ob.barIndex = bars - 1 - lowestBar;
            ob.isBullish = true; ob.isActive = true;
            ob.volume = obVolume; ob.volumePercent = 0;
            ob.tf = tf;
            int size = ArraySize(orderBlocks);
            ArrayResize(orderBlocks, size + 1);
            orderBlocks[size] = ob;
            Print("*** BULLISH VOLUME OB DETECTED (", EnumToString(tf), ") *** Top: ", obTop, " Bottom: ", lowest);
        }
    }

    if(crossDn && !prevDn) {
        double highest = high[0];
        int highestBar = 0;
        for(int i = 1; i <= SlowEMA; i++) {
            if(high[i] > highest) { highest = high[i]; highestBar = i; }
        }
        long volume[];
        ArraySetAsSeries(volume, true);
        CopyTickVolume(_Symbol, tf, 0, highestBar + 1, volume);
        double obVolume = 0;
        for(int i = 0; i <= highestBar; i++) obVolume += (double)volume[i];

        double atrValue = atr[0] * OB_ATR_Multiplier;
        double obBottom = MathMin(open[highestBar], close[highestBar]);
        if((highest - obBottom) < atrValue * 0.5) obBottom = highest - atrValue * 0.5;
        double obMid = (highest + obBottom) / 2.0;

        if(!OBExists(highest, obBottom, false, tf)) {
            VolumeOrderBlock ob;
            ob.top = highest; ob.bottom = obBottom; ob.mid = obMid;
            ob.time = iTime(_Symbol, tf, highestBar);
            ob.barIndex = bars - 1 - highestBar;
            ob.isBullish = false; ob.isActive = true;
            ob.volume = obVolume; ob.volumePercent = 0;
            ob.tf = tf;
            int size = ArraySize(orderBlocks);
            ArrayResize(orderBlocks, size + 1);
            orderBlocks[size] = ob;
            Print("*** BEARISH VOLUME OB DETECTED (", EnumToString(tf), ") *** Top: ", highest, " Bottom: ", obBottom);
        }
    }

    // Persist crossover state back to the correct TF bucket
    if(tf == PERIOD_M1) { prevCrossUp_M1 = crossUp; prevCrossDn_M1 = crossDn; }
    else if(tf == PERIOD_M3) { prevCrossUp_M3 = crossUp; prevCrossDn_M3 = crossDn; }
    else { prevCrossUp_M5 = crossUp; prevCrossDn_M5 = crossDn; }

    // Fallback scan per timeframe
    if(UseFallbackOBScan) {
        datetime barTime = iTime(_Symbol, tf, 0);
        if(barTime != lastFallbackScanBarTimeRef) {
            lastFallbackScanBarTimeRef = barTime;

            int scanBars = OB_FallbackScanBars;
            if(scanBars > bars-5) scanBars = bars-5;
            if(scanBars < OB_VolumeAvgPeriod+5) scanBars = OB_VolumeAvgPeriod+5;

            long volArr[];
            ArraySetAsSeries(volArr, true);
            CopyTickVolume(_Symbol, tf, 0, scanBars+5, volArr);

            double o[], c[], h[], l[];
            ArraySetAsSeries(o,true); ArraySetAsSeries(c,true); ArraySetAsSeries(h,true); ArraySetAsSeries(l,true);
            CopyOpen(_Symbol, tf, 0, scanBars+5, o);
            CopyClose(_Symbol, tf, 0, scanBars+5, c);
            CopyHigh(_Symbol, tf, 0, scanBars+5, h);
            CopyLow(_Symbol, tf, 0, scanBars+5, l);

            double avgVol = 0;
            for(int i=1;i<=OB_VolumeAvgPeriod;i++) avgVol += (double)volArr[i];
            avgVol /= (double)OB_VolumeAvgPeriod;

            int bestBull = -1, bestBear = -1;
            double bestBullVol = 0, bestBearVol = 0;
            for(int i=1;i<=scanBars;i++) {
                double bodyPips = MathAbs(c[i]-o[i]) / pipValue;
                if(bodyPips < OB_MinBodyPips) continue;
                double v = (double)volArr[i];
                if(avgVol > 0 && v < avgVol * OB_VolumeSpikeMult) continue;
                bool bull = (c[i] > o[i]);
                if(bull) { if(v > bestBullVol) { bestBullVol=v; bestBull=i; } }
                else { if(v > bestBearVol) { bestBearVol=v; bestBear=i; } }
            }

            double atrValue = atr[0] * OB_ATR_Multiplier;
            if(bestBull > 0) {
                double bottom = l[bestBull];
                double top = MathMax(o[bestBull], c[bestBull]);
                if((top-bottom) < atrValue*0.5) top = bottom + atrValue*0.5;
                double mid = (top+bottom)/2.0;
                if(!OBExists(top,bottom,true,tf)) {
                    VolumeOrderBlock ob;
                    ob.top=top; ob.bottom=bottom; ob.mid=mid;
                    ob.time=iTime(_Symbol, tf, bestBull);
                    ob.barIndex=bars-1-bestBull;
                    ob.isBullish=true; ob.isActive=true;
                    ob.volume=bestBullVol; ob.volumePercent=0; ob.tf=tf;
                    int sz=ArraySize(orderBlocks); ArrayResize(orderBlocks, sz+1); orderBlocks[sz]=ob;
                    Print("*** FALLBACK BULLISH OB (", EnumToString(tf), ") *** Top: ", top, " Bottom: ", bottom);
                }
            }
            if(bestBear > 0) {
                double top = h[bestBear];
                double bottom = MathMin(o[bestBear], c[bestBear]);
                if((top-bottom) < atrValue*0.5) bottom = top - atrValue*0.5;
                double mid = (top+bottom)/2.0;
                if(!OBExists(top,bottom,false,tf)) {
                    VolumeOrderBlock ob;
                    ob.top=top; ob.bottom=bottom; ob.mid=mid;
                    ob.time=iTime(_Symbol, tf, bestBear);
                    ob.barIndex=bars-1-bestBear;
                    ob.isBullish=false; ob.isActive=true;
                    ob.volume=bestBearVol; ob.volumePercent=0; ob.tf=tf;
                    int sz=ArraySize(orderBlocks); ArrayResize(orderBlocks, sz+1); orderBlocks[sz]=ob;
                    Print("*** FALLBACK BEARISH OB (", EnumToString(tf), ") *** Top: ", top, " Bottom: ", bottom);
                }
            }
        }
    }
}

// Position tracking
bool beHit[];
double originalVolume[];
int partialCloseHit[];

//+------------------------------------------------------------------+
//| Validate License with Remote Server                              |
//+------------------------------------------------------------------+
bool ValidateLicenseRemote() {
    if(StringLen(LicenseServerURL) == 0) {
        Print("ERROR: License Server URL not set!");
        return false;
    }
    
    long accountNumber = account.Login();
    string accountServer = account.Server();
    string eaName = "Goldmine Surge – Gold";
    
    // Build JSON request
    string json = "{";
    json += "\"accountNumber\":\"" + IntegerToString(accountNumber) + "\",";
    json += "\"broker\":\"" + accountServer + "\",";
    json += "\"eaName\":\"" + eaName + "\"";
    if(StringLen(LicenseKey) > 0) {
        json += ",\"licenseKey\":\"" + LicenseKey + "\"";
    }
    json += "}";
    
    // Prepare headers
    char post[];
    char result[];
    string headers;
    char data[];
    
    StringToCharArray(json, data, 0, StringLen(json));
    ArrayResize(post, StringLen(json));
    ArrayCopy(post, data);
    
    headers = "Content-Type: application/json\r\n";
    
    // Make HTTP request
    string url = LicenseServerURL;
    if(StringFind(url, "http://") != 0 && StringFind(url, "https://") != 0) {
        url = "https://" + url;
    }
    if(StringFind(url, "/validate") < 0) {
        if(StringFind(url, "/", StringLen(url) - 1) < 0) {
            url += "/";
        }
        url += "validate";
    }
    
    Print("Connecting to license server: ", url);
    Print("Sending JSON: ", json);
    
    int timeout = LicenseCheckTimeout * 1000;
    int res = WebRequest("POST", url, NULL, NULL, timeout, post, 0, result, headers);
    
    if(res == -1) {
        int error = GetLastError();
        Print("ERROR: Failed to connect to license server. Error: ", error);
        if(error == 4060) {
            Print("ERROR: URL not allowed. Add '", url, "' to Tools -> Options -> Expert Advisors -> 'Allow WebRequest for listed URL'");
        }
        return false;
    }
    
    if(res != 200) {
        Print("ERROR: License server returned status: ", res);
        string response = CharArrayToString(result);
        Print("Server Response: ", response);
        Print("Request JSON was: ", json);
        Print("Request URL was: ", url);
        return false;
    }
    
    string response = CharArrayToString(result);
    Print("Server Response: ", response);
    
    if(StringFind(response, "\"valid\":true") >= 0) {
        Print("=== REMOTE LICENSE VALIDATION: SUCCESS ===");
        return true;
    } else {
        Print("=== REMOTE LICENSE VALIDATION: FAILED ===");
        return false;
    }
}

//+------------------------------------------------------------------+
//| License Check Function                                           |
//+------------------------------------------------------------------+
bool CheckLicense() {
    if(!EnableLicenseCheck) {
        Print("WARNING: License check is DISABLED - EA is running in test mode!");
        return true;
    }
    
    // REMOTE VALIDATION FIRST (if enabled)
    if(UseRemoteValidation) {
        Print("Attempting remote license validation...");
        if(ValidateLicenseRemote()) {
            Print("=== LICENSE: VALID (Remote Server) ===");
            return true;
        } else {
            Print("WARNING: Remote validation failed, falling back to local checks");
        }
    }
    
    long accountNumber = account.Login();
    string accountServer = account.Server();
    datetime currentTime = TimeCurrent();
    
    Print("=== LICENSE CHECK (Local Fallback) ===");
    Print("Account Number: ", accountNumber);
    Print("Broker/Server: ", accountServer);
    
    // Check allowed accounts
    if(StringLen(AllowedAccounts) > 0) {
        bool accountAllowed = false;
        string accounts[];
        int accountCount = StringSplit(AllowedAccounts, ',', accounts);
        for(int i = 0; i < accountCount; i++) {
            StringTrimLeft(accounts[i]);
            StringTrimRight(accounts[i]);
            if(IntegerToString(accountNumber) == accounts[i]) {
                accountAllowed = true;
                break;
            }
        }
        if(!accountAllowed) {
            Print("ERROR: Account not authorized!");
            Alert("LICENSE ERROR: Account not authorized!");
            return false;
        }
    }
    
    // Check allowed brokers
    if(StringLen(AllowedBrokers) > 0) {
        bool brokerAllowed = false;
        string brokers[];
        int brokerCount = StringSplit(AllowedBrokers, ',', brokers);
        for(int i = 0; i < brokerCount; i++) {
            StringTrimLeft(brokers[i]);
            StringTrimRight(brokers[i]);
            if(StringFind(accountServer, brokers[i]) >= 0) {
                brokerAllowed = true;
                break;
            }
        }
        if(!brokerAllowed) {
            Print("ERROR: Broker not authorized!");
            Alert("LICENSE ERROR: Broker not authorized!");
            return false;
        }
    }
    
    // Check expiry
    if(LicenseExpiry > 0 && currentTime > LicenseExpiry) {
        Print("ERROR: License expired!");
        Alert("LICENSE ERROR: License expired!");
        return false;
    }
    
    Print("=== LICENSE: VALID (Local Fallback) ===");
    return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // LICENSE CHECK FIRST
    if(!CheckLicense()) {
        Print("EA initialization FAILED due to license check failure!");
        Alert("EA FAILED TO START: License validation failed.");
        return(INIT_FAILED);
    }
    
    // Validate symbol
    string symbolUpper = _Symbol;
    StringToUpper(symbolUpper);
    bool isGold = (StringFind(symbolUpper, "XAU") >= 0 || StringFind(symbolUpper, "GOLD") >= 0);
    bool isSilver = (StringFind(symbolUpper, "XAG") >= 0 || StringFind(symbolUpper, "SILVER") >= 0);
    
    if(!isGold && !isSilver) {
        Print("ERROR: This EA is designed for XAUUSD (Gold) and XAGUSD (Silver) only!");
        return(INIT_FAILED);
    }
    
    // Initialize trade settings
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);
    
    // Get symbol properties
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Calculate pip value
    if(isGold) {
        pipValue = point * 100;  // Gold: 1 pip = 100 points
        Print("GOLD detected: 1 pip = 100 points | 20 pips = 2000 points");
    } else {
        pipValue = point * 10;   // Silver: 1 pip = 10 points
        Print("SILVER detected: 1 pip = 10 points | 20 pips = 200 points");
    }
    
    Print("========================================");
    Print("=== Goldmine Surge – Gold EA Initialized ===");
    Print("========================================");
    Print("Symbol: ", _Symbol, " | ", isGold ? "GOLD" : "SILVER");
    Print("Risk per trade: ", RiskPerTrade, "%");
    Print("SL: ", SL_Pips, " pips | TP: ", TP_Pips, " pips");
    Print("Breakout Channels: ", UseBreakoutChannels ? "ON" : "OFF");
    Print("Volume Order Blocks: ", UseVolumeOB ? "ON" : "OFF");
    Print("Engulfing Candles: ", UseEngulfingCandles ? "ON" : "OFF");
    if(UseEngulfingCandles) {
        Print("  - Require for entry: ", RequireEngulfingForEntry ? "YES" : "NO (confluence only)");
        Print("  - With trend filter: ", EngulfingWithTrend ? "YES" : "NO");
    }
    Print("========================================");
    
    // Initialize loss protection tracking
    consecutiveLosses = 0;
    lossStreakPauseUntil = 0;
    dailyLossAmount = 0;
    lastDailyReset = TimeCurrent();
    totalTradesToday = 0;
    winningTradesToday = 0;
    
    // Initialize arrays
    ArrayResize(channels, 0);
    ArrayResize(orderBlocks, 0);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("Goldmine Surge – Gold EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
    // Manage positions on every tick
    ManagePositions();
    
    // Check for new bars (multi-timeframe OB detection for all-day scalping)
    datetime currentBarTime = iTime(_Symbol, PrimaryTF, 0);
    bool isNewBar = (currentBarTime != lastBarTime);

    // Keep existing primary timeframe behavior (channels)
    if(isNewBar) {
        lastBarTime = currentBarTime;
        if(UseBreakoutChannels) {
            DetectBreakoutChannels();
            Print("DEBUG: Active channels: ", ArraySize(channels));
        }
    }

    // OB detection on M1/M3/M5 (independent new-bar checks)
    if(UseVolumeOB) {
        if(UseM1_OB) {
            datetime t = iTime(_Symbol, PERIOD_M1, 0);
            if(t != lastBarTime_M1) { lastBarTime_M1 = t; DetectVolumeOrderBlocksOnTF(PERIOD_M1, lastFallbackScanBarTime_M1); }
        }
        if(UseM3_OB) {
            datetime t = iTime(_Symbol, PERIOD_M3, 0);
            if(t != lastBarTime_M3) { lastBarTime_M3 = t; DetectVolumeOrderBlocksOnTF(PERIOD_M3, lastFallbackScanBarTime_M3); }
        }
        if(UseM5_OB) {
            datetime t = iTime(_Symbol, PERIOD_M5, 0);
            if(t != lastBarTime_M5) { lastBarTime_M5 = t; DetectVolumeOrderBlocksOnTF(PERIOD_M5, lastFallbackScanBarTime_M5); }
        }
        if(isNewBar) {
            Print("DEBUG: Active order blocks (all TF): ", ArraySize(orderBlocks));
        }
    }
    
    // Check for entries on every tick (aggressive scalping)
    static datetime lastEntryCheck = 0;
    datetime now = TimeCurrent();
    
    // Check entries every 5 seconds (not every tick to reduce spam)
    if(now - lastEntryCheck >= 5) {
        lastEntryCheck = now;
        
        // Check if trading is allowed (loss protection + time filter)
        if(!IsTradingAllowed()) {
            return; // Exit early if trading is blocked
        }
        
        if(IsNewsEventActive()) {
            Print("DEBUG: Entry check BLOCKED - News event active");
        } else {
            int buyPos = CountPositions(POSITION_TYPE_BUY);
            int sellPos = CountPositions(POSITION_TYPE_SELL);
            Print("DEBUG: Entry check - BUY: ", buyPos, " | SELL: ", sellPos, " | Max: ", MaxEntries);
            Print("DEBUG: Loss streak: ", consecutiveLosses, "/", MaxConsecutiveLosses, " | Daily loss: ", DoubleToString((dailyLossAmount / (UseEquity ? account.Equity() : account.Balance())) * 100.0, 2), "%");
            
            if(UseBreakoutChannels && TradeBreakouts) {
                Print("DEBUG: Checking breakout entries...");
                CheckBreakoutEntries();
            }
            if(UseVolumeOB && TradeOB_Retests) {
                Print("DEBUG: Checking OB retest entries...");
                CheckOB_RetestEntries();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Breakout Channels                                         |
//+------------------------------------------------------------------+
void DetectBreakoutChannels() {
    int bars = iBars(_Symbol, PrimaryTF);
    if(bars < NormalizationLength + ChannelDetectionLength) return;
    
    // Get price data
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, PrimaryTF, 0, NormalizationLength + ChannelDetectionLength + 10, high);
    CopyLow(_Symbol, PrimaryTF, 0, NormalizationLength + ChannelDetectionLength + 10, low);
    CopyClose(_Symbol, PrimaryTF, 0, NormalizationLength + ChannelDetectionLength + 10, close);
    CopyOpen(_Symbol, PrimaryTF, 0, NormalizationLength + ChannelDetectionLength + 10, open);
    
    // Calculate normalized price
    double lowestLow = low[NormalizationLength];
    double highestHigh = high[NormalizationLength];
    for(int i = 0; i < NormalizationLength; i++) {
        if(low[i] < lowestLow) lowestLow = low[i];
        if(high[i] > highestHigh) highestHigh = high[i];
    }
    
    if(highestHigh == lowestLow) return; // No price range
    
    // Calculate normalized price volatility
    double normalizedPrice[];
    ArrayResize(normalizedPrice, NormalizationLength);
    ArraySetAsSeries(normalizedPrice, true);
    
    for(int i = 0; i < NormalizationLength; i++) {
        normalizedPrice[i] = (close[i] - lowestLow) / (highestHigh - lowestLow);
    }
    
    // Calculate volatility (standard deviation of normalized price)
    double vol = 0;
    double avgNorm = 0;
    for(int i = 0; i < 14; i++) {
        avgNorm += normalizedPrice[i];
    }
    avgNorm /= 14;
    
    for(int i = 0; i < 14; i++) {
        vol += MathPow(normalizedPrice[i] - avgNorm, 2);
    }
    vol = MathSqrt(vol / 14);
    
    // Find volatility extremes (simplified from Pine Script logic)
    double volHigh = vol;
    double volLow = vol;
    for(int i = 1; i <= ChannelDetectionLength; i++) {
        double volI = 0;
        double avgNormI = 0;
        for(int j = i; j < i + 14 && j < NormalizationLength; j++) {
            avgNormI += normalizedPrice[j];
        }
        if(i + 14 <= NormalizationLength) {
            avgNormI /= 14;
            for(int j = i; j < i + 14 && j < NormalizationLength; j++) {
                volI += MathPow(normalizedPrice[j] - avgNormI, 2);
            }
            volI = MathSqrt(volI / 14);
            if(volI > volHigh) volHigh = volI;
            if(volI < volLow) volLow = volI;
        }
    }
    
    // Detect channel formation (when upper crosses lower)
    // Simplified: detect when volatility pattern suggests channel
    static double prevVol = 0;
    bool channelFormed = false;
    
    if(prevVol > 0 && vol < prevVol * 0.8) { // Volatility decreasing = channel forming
        // Find highest high and lowest low in recent period
        int lookback = (int)ChannelMinDuration;
        double channelHigh = high[0];
        double channelLow = low[0];
        
        for(int i = 0; i < lookback && i < bars; i++) {
            if(high[i] > channelHigh) channelHigh = high[i];
            if(low[i] < channelLow) channelLow = low[i];
        }
        
        // Check if we can create this channel (no overlap if needed)
        bool canCreate = true;
        if(ArraySize(channels) > 0) {
            for(int i = 0; i < ArraySize(channels); i++) {
                if(channels[i].isActive) {
                    // Check overlap
                    if(channelHigh > channels[i].bottom && channelLow < channels[i].top) {
                        canCreate = false;
                        break;
                    }
                }
            }
        }
        
        if(canCreate && channelHigh > channelLow) {
            BreakoutChannel channel;
            channel.top = channelHigh;
            channel.bottom = channelLow;
            channel.midline = (channelHigh + channelLow) / 2.0;
            channel.startTime = iTime(_Symbol, PrimaryTF, lookback);
            channel.startBar = bars - lookback;
            channel.isActive = true;
            channel.volume = 0;
            
            // Calculate average volume in channel
            long volume[];
            ArraySetAsSeries(volume, true);
            CopyTickVolume(_Symbol, PrimaryTF, 0, lookback, volume);
            for(int i = 0; i < lookback; i++) {
                channel.volume += (double)volume[i];
            }
            channel.volume /= lookback;
            
            int size = ArraySize(channels);
            ArrayResize(channels, size + 1);
            channels[size] = channel;
            
            Print("*** BREAKOUT CHANNEL DETECTED ***");
            Print("Top: ", channel.top, " | Bottom: ", channel.bottom, " | Midline: ", channel.midline);
            
            channelFormed = true;
        }
    }
    
    prevVol = vol;
    
    // Clean invalidated channels
    CleanChannels();
}

//+------------------------------------------------------------------+
//| Clean Invalidated Channels                                       |
//+------------------------------------------------------------------+
void CleanChannels() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    for(int i = ArraySize(channels) - 1; i >= 0; i--) {
        if(!channels[i].isActive) continue;
        
        // Check if price broke out (invalidate channel)
        if(StrongClosesOnly) {
            double closePrice = iClose(_Symbol, PrimaryTF, 1);
            double openPrice = iOpen(_Symbol, PrimaryTF, 1);
            double avgPrice = (closePrice + openPrice) / 2.0;
            
            if(avgPrice > channels[i].top || avgPrice < channels[i].bottom) {
                channels[i].isActive = false;
                Print("Channel invalidated by breakout");
            }
        } else {
            if(currentPrice > channels[i].top || currentPrice < channels[i].bottom) {
                channels[i].isActive = false;
                Print("Channel invalidated by breakout");
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Volume Order Blocks                                        |
//+------------------------------------------------------------------+
void DetectVolumeOrderBlocks() {
    // Legacy wrapper kept for compatibility; PrimaryTF logic is now handled by DetectVolumeOrderBlocksOnTF()
    DetectVolumeOrderBlocksOnTF(PrimaryTF, lastFallbackScanBarTime_M5);
    CalculateOB_VolumePercentages();
    CleanOrderBlocks();
}

//+------------------------------------------------------------------+
//| Calculate OB Volume Percentages                                   |
//+------------------------------------------------------------------+
void CalculateOB_VolumePercentages() {
    double totalBullishVol = 0;
    double totalBearishVol = 0;
    
    // Sum volumes
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(!orderBlocks[i].isActive) continue;
        if(orderBlocks[i].isBullish) {
            totalBullishVol += orderBlocks[i].volume;
        } else {
            totalBearishVol += orderBlocks[i].volume;
        }
    }
    
    // Calculate percentages
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(!orderBlocks[i].isActive) continue;
        if(orderBlocks[i].isBullish && totalBullishVol > 0) {
            orderBlocks[i].volumePercent = (orderBlocks[i].volume / totalBullishVol) * 100.0;
        } else if(!orderBlocks[i].isBullish && totalBearishVol > 0) {
            orderBlocks[i].volumePercent = (orderBlocks[i].volume / totalBearishVol) * 100.0;
        }
    }
}

//+------------------------------------------------------------------+
//| Clean Invalidated Order Blocks                                   |
//+------------------------------------------------------------------+
void CleanOrderBlocks() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(iATR(_Symbol, PrimaryTF, OB_ATR_Period), 0, 0, 1, atr);
    double atrValue = atr[0] * 3.0; // ATR * 3 for overlap detection
    
    for(int i = ArraySize(orderBlocks) - 1; i >= 0; i--) {
        if(!orderBlocks[i].isActive) continue;
        
        // Remove if price crossed through (with buffer so zones survive noise / keep trading all day)
        double buffer = EntryZonePips * pipValue;
        if(orderBlocks[i].isBullish && currentPrice < (orderBlocks[i].bottom - buffer)) {
            orderBlocks[i].isActive = false;
            Print("Bullish OB invalidated");
        } else if(!orderBlocks[i].isBullish && currentPrice > (orderBlocks[i].top + buffer)) {
            orderBlocks[i].isActive = false;
            Print("Bearish OB invalidated");
        }
        
        // Remove overlaps (simplified)
        if(i > 0) {
            for(int j = i - 1; j >= 0; j--) {
                if(!orderBlocks[j].isActive) continue;
                if(orderBlocks[i].isBullish == orderBlocks[j].isBullish) {
                    double midDiff = MathAbs(orderBlocks[i].mid - orderBlocks[j].mid);
                    if(midDiff < atrValue) {
                        // Keep the one with higher volume
                        if(orderBlocks[i].volume < orderBlocks[j].volume) {
                            orderBlocks[i].isActive = false;
                        } else {
                            orderBlocks[j].isActive = false;
                        }
                    }
                }
            }
        }
    }
    
    // Limit array size
    if(ArraySize(orderBlocks) > 15) {
        // Remove oldest inactive ones
        int removed = 0;
        for(int i = ArraySize(orderBlocks) - 1; i >= 0 && removed < 5; i--) {
            if(!orderBlocks[i].isActive) {
                ArrayRemove(orderBlocks, i, 1);
                removed++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Bullish Engulfing Candle                                  |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(tf == PERIOD_CURRENT) tf = PrimaryTF;
    
    double openCurrent = iOpen(_Symbol, tf, 0);
    double closeCurrent = iClose(_Symbol, tf, 0);
    double openPrevious = iOpen(_Symbol, tf, 1);
    double closePrevious = iClose(_Symbol, tf, 1);
    
    // Bullish engulfing: current bar open <= previous close AND
    // current bar open < previous open AND current bar close > previous open
    bool bullishEngulfing = (openCurrent <= closePrevious) && 
                            (openCurrent < openPrevious) && 
                            (closeCurrent > openPrevious);
    
    // Optional: Check trend (only bullish engulfing in downtrend)
    if(EngulfingWithTrend && EngulfingTrendPeriod > 0) {
        double sma[];
        ArraySetAsSeries(sma, true);
        CopyBuffer(iMA(_Symbol, tf, EngulfingTrendPeriod, 0, MODE_SMA, PRICE_CLOSE), 0, 0, 2, sma);
        double currentPrice = closeCurrent;
        bool inDowntrend = (currentPrice < sma[0]);
        if(!inDowntrend) return false; // Only bullish engulfing in downtrend
    }
    
    return bullishEngulfing;
}

//+------------------------------------------------------------------+
//| Detect Bearish Engulfing Candle                                  |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(tf == PERIOD_CURRENT) tf = PrimaryTF;
    
    double openCurrent = iOpen(_Symbol, tf, 0);
    double closeCurrent = iClose(_Symbol, tf, 0);
    double openPrevious = iOpen(_Symbol, tf, 1);
    double closePrevious = iClose(_Symbol, tf, 1);
    
    // Bearish engulfing: current bar open >= previous close AND
    // current bar open > previous open AND current bar close < previous open
    bool bearishEngulfing = (openCurrent >= closePrevious) && 
                           (openCurrent > openPrevious) && 
                           (closeCurrent < openPrevious);
    
    // Optional: Check trend (only bearish engulfing in uptrend)
    if(EngulfingWithTrend && EngulfingTrendPeriod > 0) {
        double sma[];
        ArraySetAsSeries(sma, true);
        CopyBuffer(iMA(_Symbol, tf, EngulfingTrendPeriod, 0, MODE_SMA, PRICE_CLOSE), 0, 0, 2, sma);
        double currentPrice = closeCurrent;
        bool inUptrend = (currentPrice > sma[0]);
        if(!inUptrend) return false; // Only bearish engulfing in uptrend
    }
    
    return bearishEngulfing;
}

//+------------------------------------------------------------------+
//| Check Breakout Entries                                            |
//+------------------------------------------------------------------+
void CheckBreakoutEntries() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int buyPositions = CountPositions(POSITION_TYPE_BUY);
    int sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    if(buyPositions + sellPositions >= MaxEntries * 2) return; // Max total positions
    
    for(int i = 0; i < ArraySize(channels); i++) {
        if(!channels[i].isActive) continue;
        
        // Check for bullish breakout
        bool bullishBreakout = false;
        if(StrongClosesOnly) {
            double closePrice = iClose(_Symbol, PrimaryTF, 1);
            double openPrice = iOpen(_Symbol, PrimaryTF, 1);
            double avgPrice = (closePrice + openPrice) / 2.0;
            bullishBreakout = (avgPrice > channels[i].top);
        } else {
            bullishBreakout = (currentPrice > channels[i].top);
        }
        
        if(bullishBreakout && buyPositions < MaxEntries) {
            // Check opposite trade distance
            if(HasOppositeTradeNearby(true, currentPrice)) {
                continue; // Skip this channel
            }
            
            // Check trend filter
            int trend = GetTrendDirection();
            if(RequireTrendFilter && trend == -1) {
                Print("BULLISH BREAKOUT BLOCKED: Counter-trend (downtrend detected)");
                continue;
            }
            
            // Check engulfing candle requirement
            bool canEnter = true;
            bool hasEngulfing = false;
            if(UseEngulfingCandles && RequireEngulfingForEntry) {
                hasEngulfing = IsBullishEngulfing(PrimaryTF);
                canEnter = hasEngulfing;
                if(!canEnter) {
                    Print("BULLISH BREAKOUT BLOCKED: No bullish engulfing candle");
                }
            } else if(UseEngulfingCandles && !RequireEngulfingForEntry) {
                hasEngulfing = IsBullishEngulfing(PrimaryTF);
                if(hasEngulfing) {
                    Print("BULLISH BREAKOUT: Engulfing candle detected (confluence)");
                }
            }
            
            // Check confluence requirement
            if(RequireConfluence) {
                int confluence = CountConfluenceFactors(true, "Channel_Breakout", hasEngulfing);
                if(confluence < MinConfluenceFactors) {
                    Print("BULLISH BREAKOUT BLOCKED: Insufficient confluence (", confluence, " < ", MinConfluenceFactors, " factors)");
                    canEnter = false;
                }
            }
            
            // Check volume confirmation
            if(RequireVolumeConfirmation && !IsVolumeIncreasing(PrimaryTF)) {
                Print("BULLISH BREAKOUT BLOCKED: Volume not increasing");
                canEnter = false;
            }
            
            // Check momentum
            if(RequireMomentum && !HasMomentum(true)) {
                Print("BULLISH BREAKOUT BLOCKED: Insufficient momentum");
                canEnter = false;
            }
            
            if(canEnter) {
                OpenBuyOrder("Channel_Breakout", channels[i].top);
                channels[i].isActive = false; // Channel used
                Print("*** BULLISH BREAKOUT ENTRY ***");
                break;
            }
        }
        
        // Check for bearish breakout
        bool bearishBreakout = false;
        if(StrongClosesOnly) {
            double closePrice = iClose(_Symbol, PrimaryTF, 1);
            double openPrice = iOpen(_Symbol, PrimaryTF, 1);
            double avgPrice = (closePrice + openPrice) / 2.0;
            bearishBreakout = (avgPrice < channels[i].bottom);
        } else {
            bearishBreakout = (currentPrice < channels[i].bottom);
        }
        
        if(bearishBreakout && sellPositions < MaxEntries) {
            // Check opposite trade distance
            if(HasOppositeTradeNearby(false, currentPrice)) {
                continue; // Skip this channel
            }
            
            // Check trend filter
            int trend = GetTrendDirection();
            if(RequireTrendFilter && trend == 1) {
                Print("BEARISH BREAKOUT BLOCKED: Counter-trend (uptrend detected)");
                continue;
            }
            
            // Check engulfing candle requirement
            bool canEnter = true;
            bool hasEngulfing = false;
            if(UseEngulfingCandles && RequireEngulfingForEntry) {
                hasEngulfing = IsBearishEngulfing(PrimaryTF);
                canEnter = hasEngulfing;
                if(!canEnter) {
                    Print("BEARISH BREAKOUT BLOCKED: No bearish engulfing candle");
                }
            } else if(UseEngulfingCandles && !RequireEngulfingForEntry) {
                hasEngulfing = IsBearishEngulfing(PrimaryTF);
                if(hasEngulfing) {
                    Print("BEARISH BREAKOUT: Engulfing candle detected (confluence)");
                }
            }
            
            // Check confluence requirement
            if(RequireConfluence) {
                int confluence = CountConfluenceFactors(false, "Channel_Breakout", hasEngulfing);
                if(confluence < MinConfluenceFactors) {
                    Print("BEARISH BREAKOUT BLOCKED: Insufficient confluence (", confluence, " < ", MinConfluenceFactors, " factors)");
                    canEnter = false;
                }
            }
            
            // Check volume confirmation
            if(RequireVolumeConfirmation && !IsVolumeIncreasing(PrimaryTF)) {
                Print("BEARISH BREAKOUT BLOCKED: Volume not increasing");
                canEnter = false;
            }
            
            // Check momentum
            if(RequireMomentum && !HasMomentum(false)) {
                Print("BEARISH BREAKOUT BLOCKED: Insufficient momentum");
                canEnter = false;
            }
            
            if(canEnter) {
                OpenSellOrder("Channel_Breakout", channels[i].bottom);
                channels[i].isActive = false; // Channel used
                Print("*** BEARISH BREAKOUT ENTRY ***");
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check OB Retest Entries                                           |
//+------------------------------------------------------------------+
void CheckOB_RetestEntries() {
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int buyPositions = CountPositions(POSITION_TYPE_BUY);
    int sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    if(buyPositions + sellPositions >= MaxEntries * 2) {
        Print("DEBUG OB: Max positions reached (", buyPositions + sellPositions, "/", MaxEntries * 2, ")");
        return;
    }
    
    double entryZone = EntryZonePips * pipValue;
    Print("DEBUG OB: Checking ", ArraySize(orderBlocks), " order blocks | Entry zone: ", EntryZonePips, " pips");
    
    for(int i = 0; i < ArraySize(orderBlocks); i++) {
        if(!orderBlocks[i].isActive) {
            Print("DEBUG OB: Block ", i, " is inactive");
            continue;
        }
        
        // Check volume threshold
        if(orderBlocks[i].volumePercent < OB_MinVolumePercent) {
            Print("DEBUG OB: Block ", i, " volume too low (", orderBlocks[i].volumePercent, "% < ", OB_MinVolumePercent, "%)");
            continue;
        }
        
        // Check for bullish OB retest
        if(orderBlocks[i].isBullish) {
            double distanceToBottom = currentPrice - orderBlocks[i].bottom;
            double distanceToTop = orderBlocks[i].top - currentPrice;
            bool inZone = (currentPrice >= orderBlocks[i].bottom - entryZone && 
                          currentPrice <= orderBlocks[i].top + entryZone);
            
            Print("DEBUG OB: Bullish OB ", i, " | Price: ", currentPrice, " | OB: ", orderBlocks[i].bottom, "-", orderBlocks[i].top, 
                  " | In zone: ", inZone ? "YES" : "NO", " | Distance: ", distanceToBottom, " pips");
            
            if(inZone && buyPositions < MaxEntries) {
                // Check opposite trade distance
                if(HasOppositeTradeNearby(true, currentPrice)) {
                    continue; // Skip this OB
                }
                
                // Check trend filter
                int trend = GetTrendDirection();
                if(RequireTrendFilter && trend == -1) {
                    Print("BULLISH OB RETEST BLOCKED: Counter-trend (downtrend detected)");
                    continue;
                }
                
                // Check engulfing candle requirement
                bool canEnter = true;
                bool hasEngulfing = false;
                if(UseEngulfingCandles && RequireEngulfingForEntry) {
                    hasEngulfing = IsBullishEngulfing(PrimaryTF);
                    canEnter = hasEngulfing;
                    if(!canEnter) {
                        Print("BULLISH OB RETEST BLOCKED: No bullish engulfing candle");
                    }
                } else if(UseEngulfingCandles && !RequireEngulfingForEntry) {
                    hasEngulfing = IsBullishEngulfing(PrimaryTF);
                    if(hasEngulfing) {
                        Print("BULLISH OB RETEST: Engulfing candle detected (confluence)");
                    }
                }
                
                // Check confluence requirement
                if(RequireConfluence) {
                    int confluence = CountConfluenceFactors(true, "OB_Retest", hasEngulfing);
                    if(confluence < MinConfluenceFactors) {
                        Print("BULLISH OB RETEST BLOCKED: Insufficient confluence (", confluence, " < ", MinConfluenceFactors, " factors)");
                        canEnter = false;
                    }
                }
                
                // Check volume confirmation
                if(RequireVolumeConfirmation && !IsVolumeIncreasing(PrimaryTF)) {
                    Print("BULLISH OB RETEST BLOCKED: Volume not increasing");
                    canEnter = false;
                }
                
                if(canEnter) {
                    OpenBuyOrder("OB_Retest", orderBlocks[i].mid);
                    Print("*** BULLISH OB RETEST ENTRY ***");
                    Print("OB: ", orderBlocks[i].bottom, "-", orderBlocks[i].top, " | Volume: ", orderBlocks[i].volumePercent, "%");
                    break;
                }
            }
        }
        
        // Check for bearish OB retest
        if(!orderBlocks[i].isBullish) {
            double distanceToBottom = currentPrice - orderBlocks[i].bottom;
            double distanceToTop = orderBlocks[i].top - currentPrice;
            bool inZone = (currentPrice >= orderBlocks[i].bottom - entryZone && 
                          currentPrice <= orderBlocks[i].top + entryZone);
            
            Print("DEBUG OB: Bearish OB ", i, " | Price: ", currentPrice, " | OB: ", orderBlocks[i].bottom, "-", orderBlocks[i].top, 
                  " | In zone: ", inZone ? "YES" : "NO", " | Distance: ", distanceToTop, " pips");
            
            if(inZone && sellPositions < MaxEntries) {
                // Check opposite trade distance
                if(HasOppositeTradeNearby(false, currentPrice)) {
                    continue; // Skip this OB
                }
                
                // Check trend filter
                int trend = GetTrendDirection();
                if(RequireTrendFilter && trend == 1) {
                    Print("BEARISH OB RETEST BLOCKED: Counter-trend (uptrend detected)");
                    continue;
                }
                
                // Check engulfing candle requirement
                bool canEnter = true;
                bool hasEngulfing = false;
                if(UseEngulfingCandles && RequireEngulfingForEntry) {
                    hasEngulfing = IsBearishEngulfing(PrimaryTF);
                    canEnter = hasEngulfing;
                    if(!canEnter) {
                        Print("BEARISH OB RETEST BLOCKED: No bearish engulfing candle");
                    }
                } else if(UseEngulfingCandles && !RequireEngulfingForEntry) {
                    hasEngulfing = IsBearishEngulfing(PrimaryTF);
                    if(hasEngulfing) {
                        Print("BEARISH OB RETEST: Engulfing candle detected (confluence)");
                    }
                }
                
                // Check confluence requirement
                if(RequireConfluence) {
                    int confluence = CountConfluenceFactors(false, "OB_Retest", hasEngulfing);
                    if(confluence < MinConfluenceFactors) {
                        Print("BEARISH OB RETEST BLOCKED: Insufficient confluence (", confluence, " < ", MinConfluenceFactors, " factors)");
                        canEnter = false;
                    }
                }
                
                // Check volume confirmation
                if(RequireVolumeConfirmation && !IsVolumeIncreasing(PrimaryTF)) {
                    Print("BEARISH OB RETEST BLOCKED: Volume not increasing");
                    canEnter = false;
                }
                
    double entryPrice = ask;
    
    // Calculate dynamic SL
    double sl = CalculateDynamicSL(entryPrice, true);
    double tp = entryPrice + (TP_Pips * pipValue);
    
    // Check Risk:Reward ratio
    double slDistance = MathAbs(entryPrice - sl) / pipValue;
    double tpDistance = MathAbs(tp - entryPrice) / pipValue;
    double rrRatio = (tpDistance > 0) ? (tpDistance / slDistance) : 0;
    
    if(MinRR_Ratio > 0                 if(canEnter) {                if(canEnter) { rrRatio < MinRR_Ratio) {
        Print("BUY ORDER BLOCKED: R:R ratio too low (", DoubleToString(rrRatio, 2), " < ", MinRR_Ratio, ")");
        return;
    }
                    OpenSellOrder("OB_Retest", orderBlocks[i].mid);
                    Print("*** BEARISH OB RETEST ENTRY ***");
                    Print("OB: ", orderBlocks[i].bottom, "-", orderBlocks[i].top, " | Volume: ", orderBlocks[i].volumePercent, "%");
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                    |
//+------------------------------------------------------------------+
void OpenBuyOrder(string reason, double entryZone) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double entryPrice = ask;
    
    // Calculate dynamic SL
    double sl = CalculateDynamicSL(entryPrice, true);
    double tp = entryPrice + (TP_Pips * pipValue);
    
    // Check Risk:Reward ratio
    double slDistancePips = MathAbs(entryPrice - sl) / pipValue;
    double tpDistancePips = MathAbs(tp - entryPrice) / pipValue;
    double rrRatio = (tpDistancePips > 0) ? (tpDistancePips / slDistancePips) : 0;
    
    if(MinRR_Ratio > 0 && rrRatio < MinRR_Ratio) {
        Print("BUY ORDER BLOCKED: R:R ratio too low (", DoubleToString(rrRatio, 2), " < ", MinRR_Ratio, ")");
        return;
    }
    
    // Calculate lot size
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double riskAmount = accountValue * (RiskPerTrade / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    string comment = TradeComment + "_" + reason;
    
    if(trade.Buy(lotSize, _Symbol, entryPrice, sl, 0, comment)) {
        ulong ticket = trade.ResultOrder();
    double entryPrice = bid;
    
    // Calculate dynamic SL
    double sl = CalculateDynamicSL(entryPrice, false);
    double tp = entryPrice - (TP_Pips * pipValue);
    
    // Check Risk:Reward ratio
    double slDistance = MathAbs(sl - entryPrice) / pipValue;
    double tpDistance = MathAbs(entryPrice - tp) / pipValue;
    double rrRatio = (tpDistance > 0) ? (tpDistance / slDistance) : 0;
    
    if(MinRR_Ratio > 0         Print("*** BUY ORDER OPENED ***");        Print("*** BUY ORDER OPENED ***"); rrRatio < MinRR_Ratio) {
        Print("SELL ORDER BLOCKED: R:R ratio too low (", DoubleToString(rrRatio, 2), " < ", MinRR_Ratio, ")");
        return;
    }
        Print("Entry: ", entryPrice, " | SL: ", sl, " | TP: ", tp, " | Reason: ", reason);
        Print("Lots: ", lotSize, " | Risk: ", RiskPerTrade, "%");
        
        // Initialize tracking
        int ticketIndex = (int)(ticket % 10000);
        if(ticketIndex >= ArraySize(beHit)) {
            int newSize = ticketIndex + 10;
            ArrayResize(beHit, newSize);
            ArrayResize(originalVolume, newSize);
            ArrayResize(partialCloseHit, newSize);
            for(int j = ArraySize(beHit) - 10; j < newSize; j++) {
                beHit[j] = false;
                originalVolume[j] = 0;
                partialCloseHit[j] = 0;
            }
        }
        
        if(position.SelectByTicket(ticket)) {
            originalVolume[ticketIndex] = position.Volume();
        }
    }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                   |
//+------------------------------------------------------------------+
void OpenSellOrder(string reason, double entryZone) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entryPrice = bid;
    
    // Calculate dynamic SL
    double sl = CalculateDynamicSL(entryPrice, false);
    double tp = entryPrice - (TP_Pips * pipValue);
    
    // Check Risk:Reward ratio
    double slDistancePips = MathAbs(sl - entryPrice) / pipValue;
    double tpDistancePips = MathAbs(entryPrice - tp) / pipValue;
    double rrRatio = (tpDistancePips > 0) ? (tpDistancePips / slDistancePips) : 0;
    
    if(MinRR_Ratio > 0 && rrRatio < MinRR_Ratio) {
        Print("SELL ORDER BLOCKED: R:R ratio too low (", DoubleToString(rrRatio, 2), " < ", MinRR_Ratio, ")");
        return;
    }
    
    // Calculate lot size
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double riskAmount = accountValue * (RiskPerTrade / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    string comment = TradeComment + "_" + reason;
    
    if(trade.Sell(lotSize, _Symbol, entryPrice, sl, 0, comment)) {
        ulong ticket = trade.ResultOrder();
        Print("*** SELL ORDER OPENED ***");
        Print("Entry: ", entryPrice, " | SL: ", sl, " | TP: ", tp, " | Reason: ", reason);
        Print("Lots: ", lotSize, " | Risk: ", RiskPerTrade, "%");
        
        // Initialize tracking
        int ticketIndex = (int)(ticket % 10000);
        if(ticketIndex >= ArraySize(beHit)) {
            int newSize = ticketIndex + 10;
            ArrayResize(beHit, newSize);
            ArrayResize(originalVolume, newSize);
            ArrayResize(partialCloseHit, newSize);
            for(int j = ArraySize(beHit) - 10; j < newSize; j++) {
                beHit[j] = false;
                originalVolume[j] = 0;
                partialCloseHit[j] = 0;
            }
        }
        
        if(position.SelectByTicket(ticket)) {
            originalVolume[ticketIndex] = position.Volume();
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size                                                |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slDistance) {
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(slDistance == 0) return minLot;
    
    double lotSize = riskAmount / (slDistance / tickSize * tickValue);
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
    // Check margin
    double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double marginRequired = 0;
    
    if(AccountLeverage > 0 && AccountLeverage < 999999) {
        marginRequired = (contractSize * currentPrice) / AccountLeverage;
    } else {
        marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
    }
    
    double freeMargin = account.FreeMargin();
    double maxLotByMargin = (freeMargin * 0.8) / marginRequired;
    
    if(maxLotByMargin > 0 && lotSize > maxLotByMargin) {
        lotSize = MathFloor(maxLotByMargin / lotStep) * lotStep;
        if(lotSize < minLot) lotSize = minLot;
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Count Positions                                                   |
//+------------------------------------------------------------------+
int CountPositions(ENUM_POSITION_TYPE type) {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(position.SelectByIndex(i)) {
            if(position.Symbol() == _Symbol && 
               position.Magic() == MagicNumber &&
               position.Type() == type) {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Manage Positions                                                  |
//+------------------------------------------------------------------+
void ManagePositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        ulong ticket = position.Ticket();
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentTP = position.TakeProfit();
        double currentVolume = position.Volume();
        double currentPrice = (position.Type() == POSITION_TYPE_BUY) ? 
                             SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                             SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        
        // Calculate profit in pips
        double profitPips = 0;
        if(position.Type() == POSITION_TYPE_BUY) {
            profitPips = (currentPrice - openPrice) / pipValue;
        } else {
            profitPips = (openPrice - currentPrice) / pipValue;
        }
        
        // Initialize tracking
        int ticketIndex = (int)(ticket % 10000);
        if(ticketIndex >= ArraySize(beHit)) {
            int newSize = ticketIndex + 10;
            ArrayResize(beHit, newSize);
            ArrayResize(originalVolume, newSize);
            ArrayResize(partialCloseHit, newSize);
            for(int j = ArraySize(beHit) - 10; j < newSize; j++) {
                beHit[j] = false;
                originalVolume[j] = 0;
                partialCloseHit[j] = 0;
            }
        }
        
        if(originalVolume[ticketIndex] == 0) {
            originalVolume[ticketIndex] = currentVolume;
        }
        
        double origVol = originalVolume[ticketIndex];
        double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double runnerSize = NormalizeDouble(origVol * (RunnerPercent / 100.0), 2);
        bool hasRunner = (currentVolume <= runnerSize + minLot * 0.1);
        
        // Break-even
        if(!beHit[ticketIndex] && profitPips >= BreakEvenPips && profitPips > 0 && UseBreakEven) {
            beHit[ticketIndex] = true;
            double newSL = openPrice;
            
            if(trade.PositionModify(ticket, newSL, 0)) {
                Print("*** BREAK-EVEN SET at ", BreakEvenPips, " pips profit | Ticket #", ticket);
            }
        }
        
        // Partial close
        if(beHit[ticketIndex] && profitPips >= PartialClosePips && !hasRunner && UsePartialClose && partialCloseHit[ticketIndex] == 0) {
            double closeVolume = NormalizeDouble(origVol * (PartialClosePercent / 100.0), 2);
            double remainingVolume = currentVolume - closeVolume;
            
            if(closeVolume >= minLot && remainingVolume >= runnerSize) {
                if(trade.PositionClosePartial(ticket, closeVolume)) {
                    partialCloseHit[ticketIndex] = 1;
                    Print("*** PARTIAL CLOSE: ", closeVolume, " lots (", PartialClosePercent, "%) at ", PartialClosePips, " pips | Remaining: ", remainingVolume, " lots ***");
                }
            }
        }
        
        // Set TP for runner (if not already set)
        if(hasRunner && currentTP == 0) {
            double tp = 0;
            if(position.Type() == POSITION_TYPE_BUY) {
                tp = openPrice + (TP_Pips * pipValue);
            } else {
                tp = openPrice - (TP_Pips * pipValue);
            }
            trade.PositionModify(ticket, currentSL, tp);
        }
        
        // Ensure SL is set
        if(currentSL == 0) {
            double newSL = 0;
            if(position.Type() == POSITION_TYPE_BUY) {
                newSL = openPrice - (SL_Pips * pipValue);
            } else {

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss (ATR-based)                         |
//+------------------------------------------------------------------+
double CalculateDynamicSL(double entryPrice, bool isBuy) {
    if(!UseDynamicSL) {
        return isBuy ? (entryPrice - (SL_Pips * pipValue)) : (entryPrice + (SL_Pips * pipValue));
    }
    
    double atr[];
    ArraySetAsSeries(atr, true);
    int atrHandle = iATR(_Symbol, PrimaryTF, DynamicSL_ATR_Period);
    if(CopyBuffer(atrHandle, 0, 0, 1, atr) < 1) {
        // Fallback to base SL if ATR fails
        return isBuy ? (entryPrice - (SL_Pips * pipValue)) : (entryPrice + (SL_Pips * pipValue));
    }
    
    double atrPips = (atr[0] / pipValue) * DynamicSL_ATR_Multiplier;
    double dynamicSL_Pips = MathMax(DynamicSL_MinPips, MathMin(DynamicSL_MaxPips, atrPips));
    
    if(isBuy) {
        return entryPrice - (dynamicSL_Pips * pipValue);
    } else {
        return entryPrice + (dynamicSL_Pips * pipValue);
    }
}

//+------------------------------------------------------------------+
//| Check if Price Has Momentum                                      |
//+------------------------------------------------------------------+
bool HasMomentum(bool isBuy) {
    if(!RequireMomentum) return true;
    
    double close0 = iClose(_Symbol, PrimaryTF, 0);
    double close1 = iClose(_Symbol, PrimaryTF, 1);
    double close2 = iClose(_Symbol, PrimaryTF, 2);
    
    double movement = 0;
    if(isBuy) {
        movement = (close0 - close2) / pipValue; // Price moved up
    } else {
        movement = (close2 - close0) / pipValue; // Price moved down
    }
    
    return (movement >= MomentumMinPips);
}

//+------------------------------------------------------------------+
//| Get Win Rate from Recent Trades                                  |
//+------------------------------------------------------------------+
double GetWinRate() {
    if(ArraySize(recentTradesHistory) < WinRateLookbackTrades) return 100.0; // Not enough data, allow trading
    
    int wins = 0;
    for(int i = 0; i < ArraySize(recentTradesHistory) && i < WinRateLookbackTrades; i++) {
        if(recentTradesHistory[i] == 1) wins++; // 1 = win, 0 = loss
    }
    
    return (wins / (double)MathMin(ArraySize(recentTradesHistory), WinRateLookbackTrades)) * 100.0;
}

//+------------------------------------------------------------------+
//| Check if Volatility is Too High                                  |
//+------------------------------------------------------------------+
bool IsVolatilityTooHigh() {
    if(!UseVolatilityFilter) return false;
    
    double atr[];
    ArraySetAsSeries(atr, true);
    int atrHandle = iATR(_Symbol, PrimaryTF, 14);
    if(CopyBuffer(atrHandle, 0, 0, 20, atr) < 20) return false;
    
    // Calculate average ATR
    double avgATR = 0;
    for(int i = 0; i < 20; i++) {
        avgATR += atr[i];
    }
    avgATR /= 20.0;
    
    // Current ATR vs average
    double currentATR = atr[0];
    double atrRatio = currentATR / avgATR;
    
    return (atrRatio >= VolatilityATR_Multiplier);
}

//+------------------------------------------------------------------+
//| Check Spread                                                      |
    
    // Check spread filter
    if(!IsSpreadAcceptable()) {
        static datetime lastSpreadLog = 0;
        if(TimeCurrent() - lastSpreadLog > 300) {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double spread = (ask - bid) / pipValue;
            Print("TRADING BLOCKED: Spread too high (", DoubleToString(spread, 2), " pips > ", MaxSpreadPips, " pips)");
            lastSpreadLog = TimeCurrent();
        }
        return false;
    }
    
    // Check volatility filter
    if(IsVolatilityTooHigh()) {
        static datetime lastVolatilityLog = 0;
        if(TimeCurrent() - lastVolatilityLog > 300) {
            Print("TRADING BLOCKED: Volatility too high (extreme market conditions)");
            lastVolatilityLog = TimeCurrent();
        }
        return false;
    }
    
    // Check maximum daily trades
    if(MaxDailyTrades > 0 && totalTradesToday >= MaxDailyTrades) {
        static datetime lastMaxTradesLog = 0;
        if(TimeCurrent() - lastMaxTradesLog > 300) {
            Print("TRADING BLOCKED: Maximum daily trades reached (", totalTradesToday, "/", MaxDailyTrades, ")");
            lastMaxTradesLog = TimeCurrent();
        }
        return false;
    }
    
    // Check win rate filter
    if(MinWinRatePercent > 0) {
        double winRate = GetWinRate();
        if(winRate < MinWinRatePercent && ArraySize(recentTradesHistory) >= WinRateLookbackTrades) {
            static datetime lastWinRateLog = 0;
            if(TimeCurrent() - lastWinRateLog > 300) {
                Print("TRADING BLOCKED: Win rate too low (", DoubleToString(winRate, 1), "% < ", MinWinRatePercent, "%)");
                lastWinRateLog = TimeCurrent();
            }
            return false;
        }
    }
//+------------------------------------------------------------------+
bool IsSpreadAcceptable() {
    if(MaxSpreadPips <= 0) return true; // Disabled
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double spread = (ask - bid) / pipValue;
    
    return (spread <= MaxSpreadPips);
}

                newSL = openPrice + (SL_Pips * pipValue);
            }
            trade.PositionModify(ticket, newSL, 0);
        }
    }
}

//+------------------------------------------------------------------+
//| Check if Trading is Allowed (Loss Protection + Time Filter)      |
//+------------------------------------------------------------------+
bool IsTradingAllowed() {
    // Check loss streak protection
    if(UseLossStreakProtection) {
        if(TimeCurrent() < lossStreakPauseUntil) {
            static datetime lastPauseLog = 0;
            if(TimeCurrent() - lastPauseLog > 60) {
                Print("TRADING PAUSED: Loss streak protection active. Resumes at: ", TimeToString(lossStreakPauseUntil));
                lastPauseLog = TimeCurrent();
            }
            return false;
        }
        
        if(consecutiveLosses >= MaxConsecutiveLosses) {
            lossStreakPauseUntil = TimeCurrent() + (LossStreakPauseMinutes * 60);
            Print("*** LOSS STREAK DETECTED: ", consecutiveLosses, " consecutive losses. Pausing for ", LossStreakPauseMinutes, " minutes ***");
            return false;
        }
    }
    
    // Check daily loss limit
    if(MaxDailyLossPercent > 0) {
        // Reset daily loss at midnight if enabled
        if(ResetDailyLossAtMidnight) {
            MqlDateTime dt;
            TimeToStruct(TimeCurrent(), dt);
            MqlDateTime lastReset;
            TimeToStruct(lastDailyReset, lastReset);
            
            if(dt.day != lastReset.day || dt.mon != lastReset.mon || dt.year != lastReset.year) {
                dailyLossAmount = 0;
                totalTradesToday = 0;
                winningTradesToday = 0;
                lastDailyReset = TimeCurrent();
                Print("Daily loss counter reset at midnight");
            }
        }
        
        double accountValue = UseEquity ? account.Equity() : account.Balance();
        double dailyLossPercent = (dailyLossAmount / accountValue) * 100.0;
        
        if(dailyLossPercent >= MaxDailyLossPercent) {
            static datetime lastDailyLossLog = 0;
            if(TimeCurrent() - lastDailyLossLog > 300) {
                Print("TRADING BLOCKED: Daily loss limit reached (", DoubleToString(dailyLossPercent, 2), "% >= ", MaxDailyLossPercent, "%)");
                lastDailyLossLog = TimeCurrent();
            }
            return false;
        }
    }
    
    // Check time filter
    if(UseTimeFilter) {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        int currentHour = dt.hour;
        
        // Check if within trading hours
        bool inTradingHours = false;
        if(StartHour <= EndHour) {
            inTradingHours = (currentHour >= StartHour && currentHour <= EndHour);
        } else {
            // Overnight hours (e.g., 22-2)
            inTradingHours = (currentHour >= StartHour || currentHour <= EndHour);
        }
        
        if(!inTradingHours) {
            static datetime lastTimeLog = 0;
            if(TimeCurrent() - lastTimeLog > 300) {
                Print("TRADING BLOCKED: Outside trading hours (", StartHour, ":00 - ", EndHour, ":00)");
                lastTimeLog = TimeCurrent();
            }
            return false;
        }
        
        // Check low liquidity hours
        if(AvoidLowLiquidity) {
            bool inLowLiquidity = false;
            if(LowLiquidityStart > LowLiquidityEnd) {
                // Overnight low liquidity (e.g., 22-2)
                inLowLiquidity = (currentHour >= LowLiquidityStart || currentHour <= LowLiquidityEnd);
            } else {
                inLowLiquidity = (currentHour >= LowLiquidityStart && currentHour <= LowLiquidityEnd);
            }
            
            if(inLowLiquidity) {
                static datetime lastLiquidityLog = 0;
                if(TimeCurrent() - lastLiquidityLog > 300) {
                    Print("TRADING BLOCKED: Low liquidity hours (", LowLiquidityStart, ":00 - ", LowLiquidityEnd, ":00)");
                    lastLiquidityLog = TimeCurrent();
                }
                return false;
            }
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Trend Direction (EMA-based)                                |
//+------------------------------------------------------------------+
int GetTrendDirection() {
    if(!RequireTrendFilter) return 0; // Neutral if filter disabled
    
    double ema[];
    ArraySetAsSeries(ema, true);
    int emaHandle = iMA(_Symbol, PrimaryTF, TrendEMA_Period, 0, MODE_EMA, PRICE_CLOSE);
    if(CopyBuffer(emaHandle, 0, 0, 2, ema) < 2) return 0;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    if(currentPrice > ema[0]) return 1;  // Uptrend
    if(currentPrice < ema[0]) return -1; // Downtrend
    return 0; // Neutral
}

//+------------------------------------------------------------------+
//| Check Volume Confirmation (Increasing Volume)                    |
//+------------------------------------------------------------------+
bool IsVolumeIncreasing(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
    if(!RequireVolumeConfirmation) return true; // Pass if filter disabled
    if(tf == PERIOD_CURRENT) tf = PrimaryTF;
    
    long volume[];
    ArraySetAsSeries(volume, true);
    int bars = VolumeConfirmationBars + 1;
    if(CopyTickVolume(_Symbol, tf, 0, bars, volume) < bars) return false;
    
    // Check if recent volume is higher than average
    double recentAvg = 0;
    double olderAvg = 0;
    
    int recentBars = MathMin(VolumeConfirmationBars, 3);
    int olderBars = VolumeConfirmationBars;
    
    for(int i = 0; i < recentBars; i++) {
        recentAvg += (double)volume[i];
    }
    recentAvg /= recentBars;
    
    for(int i = recentBars; i < olderBars && i < ArraySize(volume); i++) {
        olderAvg += (double)volume[i];
    }
    if(olderBars > recentBars) olderAvg /= (olderBars - recentBars);
    
    return (recentAvg > olderAvg * 1.1); // 10% increase
}

//+------------------------------------------------------------------+
//| Check if Opposite Trade is Too Close                             |
//+------------------------------------------------------------------+
bool HasOppositeTradeNearby(bool isBuy, double entryPrice) {
    double minDistance = MinOppositeDistancePips * pipValue;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type();
        if(isBuy && posType == POSITION_TYPE_SELL) {
            double distance = MathAbs(entryPrice - position.PriceOpen());
            if(distance < minDistance) {
                Print("ENTRY BLOCKED: Opposite SELL trade too close (", DoubleToString(distance / pipValue, 1), " pips < ", MinOppositeDistancePips, " pips)");
                return true;
            }
        } else if(!isBuy && posType == POSITION_TYPE_BUY) {
            double distance = MathAbs(entryPrice - position.PriceOpen());
            if(distance < minDistance) {
                Print("ENTRY BLOCKED: Opposite BUY trade too close (", DoubleToString(distance / pipValue, 1), " pips < ", MinOppositeDistancePips, " pips)");
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Count Confluence Factors                                          |
//+------------------------------------------------------------------+
int CountConfluenceFactors(bool isBuy, string reason, bool hasEngulfing) {
    int factors = 0;
    
    // Base factor: OB or Channel
    if(StringFind(reason, "OB") >= 0 || StringFind(reason, "Channel") >= 0) {
        factors++;
    }
    
    // Engulfing candle
    if(hasEngulfing) {
        factors++;
    }
    
    // Volume confirmation
    if(IsVolumeIncreasing(PrimaryTF)) {
        factors++;
    }
    
    // Trend alignment
    int trend = GetTrendDirection();
    if((isBuy && trend == 1) || (!isBuy && trend == -1)) {
        factors++;
    }
    
    return factors;
}

//+------------------------------------------------------------------+
//| Trade Transaction Handler (Track Losses)                          |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                       const MqlTradeRequest& request,
                       const MqlTradeResult& result) {
    // Only process deal additions (position closures)
    if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
    
    // Get deal details
    ulong dealTicket = trans.deal;
    if(dealTicket == 0) return;
    
    if(!HistoryDealSelect(dealTicket)) return;
    
    // Check if this is our EA's deal
    if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) return;
    if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) return;
    
    // Check if position was closed (DEAL_ENTRY_OUT)
    ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
    if(dealEntry != DEAL_ENTRY_OUT) return;
    
    // Get deal profit
    double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
    double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
    
    // Update tracking
    totalTradesToday++;
    
    if(dealProfit < 0) {
        // Loss
        consecutiveLosses++;
                
                // Track in recent trades history
                int size = ArraySize(recentTradesHistory);
                ArrayResize(recentTradesHistory, size + 1);
                ArrayResize(recentTradesProfit, size + 1);
                recentTradesHistory[size] = 0; // 0 = loss
                recentTradesProfit[size] = dealProfit;
                
                // Keep only last WinRateLookbackTrades * 2
                if(ArraySize(recentTradesHistory) > WinRateLookbackTrades * 2) {
                    ArrayRemove(recentTradesHistory, 0, 1);
                    ArrayRemove(recentTradesProfit, 0, 1);
                }
        dailyLossAmount += MathAbs(dealProfit);
        Print("*** LOSS DETECTED *** Ticket: ", dealTicket, " | Loss: $", DoubleToString(MathAbs(dealProfit), 2), " | Consecutive losses: ", consecutiveLosses);
        
        if(UseLossStreakProtection && consecutiveLosses >= MaxConsecutiveLosses) {
            lossStreakPauseUntil = TimeCurrent() + (LossStreakPauseMinutes * 60);
            Print("*** LOSS STREAK TRIGGERED: Pausing trading for ", LossStreakPauseMinutes, " minutes ***");
        }
    } else {
        // Win - reset consecutive losses
        consecutiveLosses = 0;
        winningTradesToday++;
        Print("*** WIN DETECTED *** Ticket: ", dealTicket, " | Profit: $", DoubleToString(dealProfit, 2), " | Consecutive losses reset to 0");
    }
    
    // Check daily loss limit
    if(MaxDailyLossPercent > 0) {
        double accountValue = UseEquity ? account.Equity() : account.Balance();
        double dailyLossPercent = (dailyLossAmount / accountValue) * 100.0;
        
        if(dailyLossPercent >= MaxDailyLossPercent) {
            Print("*** DAILY LOSS LIMIT REACHED: ", DoubleToString(dailyLossPercent, 2), "% >= ", MaxDailyLossPercent, "% ***");
            Print("Total trades today: ", totalTradesToday, " | Wins: ", winningTradesToday, " | Losses: ", (totalTradesToday - winningTradesToday));
        }
    }
}

//+------------------------------------------------------------------+
//| Check if News Event is Active                                     |
//+------------------------------------------------------------------+
bool IsNewsEventActive() {
    if(!BlockTradesDuringNews) return false;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int hour = dt.hour;
    int minute = dt.min;
    int currentMinute = hour * 60 + minute;
    
    int newsTimes[4];
    newsTimes[0] = 8*60 + 30;  // 8:30 AM
    newsTimes[1] = 10*60 + 0;  // 10:00 AM
    newsTimes[2] = 14*60 + 0;  // 2:00 PM
    newsTimes[3] = 16*60 + 0;  // 4:00 PM
    
    for(int i = 0; i < 4; i++) {
        int windowStart = newsTimes[i] - NewsBlockMinutesBefore;
        int windowEnd = newsTimes[i] + NewsBlockMinutesAfter;
        
        if(currentMinute >= windowStart && currentMinute <= windowEnd) {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
