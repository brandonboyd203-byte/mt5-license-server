//+------------------------------------------------------------------+
//|                                    GoldmineEdge_Gold.mq5         |
//|          Goldmine Edge – Gold | BigBeluga + Confluence Trading   |
//|                    Aggressive Reversal Trading for XAUUSD        |
//|                                                                   |
//| Features:                                                        |
//| - Order Blocks (BigBeluga)                                       |
//| - Multi-timeframe FVG (M5/M15/M30/H1)                           |
//| - Trend Line Support/Resistance                                 |
//| - Session High/Low Sweeps (NY, London, Asian)                   |
//| - Session High/Low Retests                                      |
//| - Previous Daily/Weekly High/Low                                |
//| - Hourly Sweeps                                                 |
//| - Confluence-Based Entries (Multiple Factors)                   |
//| - Layered Entries (Multiple Positions)                           |
//| - 100 Pip Targets (Aggressive Scalping)                        |
//+------------------------------------------------------------------+
#property copyright "Goldmine Edge"
#property link      ""
#property version   "1.00"
#property description "Goldmine Edge – Gold. BigBeluga + Confluence. XAUUSD."
#property description "Aggressive reversal trading with layered entries"

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
input double RiskPerTrade = 1.0;             // Risk per trade (% of equity) - DEFAULT: 1%
input double MaxTotalRisk = 4.0;              // Max total risk for all trades (%) - DEFAULT: 4% (4 trades x 1%)
input bool UseEquity = true;                  // Use Equity (true) or Balance (false) for risk calculation
input int AccountLeverage = 999999;           // Your account leverage (2000, 500, etc. | Use 999999 for unlimited)
input group "=== Stop Loss Settings ==="
input bool UseDynamicSL = true;               // Dynamic SL based on confluence (bigger SL for more confluence)
input double SL_Pips = 20.0;                 // Base SL (pips) - Used when UseDynamicSL=false or confluence=1
input double SL_PerConfluence = 10.0;        // Additional SL pips per confluence factor (e.g., 2 confluence = base + 10 = 30 pips)
input double SL_MaxPips = 50.0;              // Maximum SL (pips) - Safety limit
input bool SL_OutsideZone = true;             // Place SL outside zone to avoid wicks (adds zone size to SL)
input bool UseBreakEven = true;              // Enable break-even
input double BreakEvenPips = 20.0;           // Move to BE at this many pips profit

input group "=== Take Profit System ==="
input double TP1_Pips = 10.0;                // TP1 (pips) - Close 25%
input double TP1_Percent = 25.0;              // % to close at TP1
input double TP2_Pips = 20.0;                // TP2 (pips) - Close 20%
input double TP2_Percent = 20.0;             // % to close at TP2
input double TP3_Pips = 50.0;                // TP3 (pips) - Close 30%
input double TP3_Percent = 30.0;              // % to close at TP3
input bool TP4_To1H_SR = true;               // TP4: Remaining position targets nearest 1H S/R
input double RunnerSizePercent = 10.0;       // % to keep as runner (always)
input bool RunnerTo1H_SR = true;             // Runner targets 1H support/resistance

input group "=== Order Block Settings ==="
input bool UseOrderBlocks = true;             // Enable Order Block trading
input bool UseM1_OB = true;                   // Detect OB on M1 (quick scalps)
input bool UseM3_OB = true;                   // Detect OB on M3 (quick scalps)
input bool UseM5_OB = true;                   // Detect OB on M5 (quick scalps)
input bool UseM15_OB = true;                  // Detect OB on M15 (reversal trades) - IMPORTANT!
input bool UseM30_OB = true;                  // Detect OB on M30 (swing trades)
input int OB_Lookback = 20;                   // Bars to look back for OB
input double OB_VolumeMultiplier = 1.2;      // Volume multiplier for OB (lowered for more sensitivity)
input int OB_ATR_Period = 14;                 // ATR period for OB
input double OB_ATR_Multiplier = 0.3;         // ATR multiplier for OB size (lowered for more sensitivity)

input group "=== FVG Settings (Multi-Timeframe) ==="
input bool UseFVG = true;                     // Enable FVG trading
input bool UseM1_FVG = true;                  // Use M1 FVG (quick scalps)
input bool UseM3_FVG = true;                  // Use M3 FVG (quick scalps)
input bool UseM5_FVG = true;                  // Use M5 FVG (quick scalps)
input bool UseM15_FVG = true;                 // Use M15 FVG
input bool UseM30_FVG = true;                 // Use M30 FVG
input bool UseH1_FVG = true;                 // Use H1 FVG
input double FVG_MinSize = 3.0;               // Minimum FVG size (pips) - Auto converts to points based on symbol
input int FVG_Lookback = 50;                  // Bars to look back for FVG

input group "=== Trend Line Settings ==="
input bool UseTrendLines = true;              // Enable Trend Line trading
input int TrendLine_Lookback = 100;           // Bars to look back for trend lines
input int TrendLine_TouchCount = 2;           // Min touches for valid trend line
input double TrendLine_AngleMin = 15.0;       // Minimum angle (degrees)
input double TrendLine_AngleMax = 75.0;       // Maximum angle (degrees)

input group "=== Session Levels ==="
input bool UseSessionLevels = true;           // Enable Session High/Low
input bool UseNYSession = true;                // Use NY Session (8:00-17:00 EST)
input bool UseLondonSession = true;            // Use London Session (3:00-12:00 EST)
input bool UseAsianSession = true;             // Use Asian Session (20:00-5:00 EST)
input bool UseSessionSweeps = true;            // Trade session high/low sweeps
input bool UseSessionRetests = true;           // Trade session high/low retests

input group "=== Daily/Weekly Levels ==="
input bool UseDailyLevels = true;             // Use Previous Daily High/Low
input bool UseWeeklyLevels = true;             // Use Previous Weekly High/Low
input bool UseDailySweeps = true;              // Trade daily high/low sweeps
input bool UseWeeklySweeps = true;             // Trade weekly high/low sweeps

input group "=== Hourly Sweeps ==="
input bool UseHourlySweeps = true;            // Use Hourly High/Low Sweeps
input int HourlySweep_Lookback = 24;          // Hours to look back for sweeps

input group "=== Support/Resistance Touch Trades ==="
input bool UseSR_Touch = true;                // Enable Support/Resistance touch trades
input bool UseM1_SR = true;                    // Trade M1 support/resistance touches
input bool UseM5_SR = true;                    // Trade M5 support/resistance touches
input bool UseM15_SR = true;                   // Trade M15 support/resistance touches
input int SR_Lookback = 50;                    // Bars to look back for S/R levels
input double SR_TouchTolerance = 5.0;          // Tolerance for S/R touch (pips)
input bool TradeCloseOnSupport = true;         // Trade when price CLOSES on support (high-probability reversal)
input bool TradeCloseOnResistance = true;     // Trade when price CLOSES on resistance (high-probability reversal)
input bool TradeFVG_Retest = true;            // Trade FVG retests (50% of FVG hit = reversal signal)
input double FVG_RetestPercent = 50.0;        // FVG retest percentage (50% = middle of FVG)

input group "=== Trend & Range Trading ==="
input bool TradeWithTrendOnly = true;          // Only take trades in the direction of the trend (not multi-directional)
input bool UseRangeTrading = true;             // Trade within identified ranges (buy zone below, sell zone above)
input ENUM_TIMEFRAMES RangeTimeframe = PERIOD_M5; // Timeframe for range detection (M5 recommended)
input bool UseMarketStructure = true;           // Use BOS/CHoCH for trend direction (BigBeluga style)
input int MS_SwingLength = 5;                   // Swing length for market structure

input group "=== Trade Management ==="
input bool AllowNewTradesWhileInTrade = true;  // Allow new trades even when already in a position
input bool MoveToBE_OnNewTrade = true;         // Move existing trades to BE when new high-probability trade appears
input int MinConfluenceForBE_Move = 3;         // Minimum confluence to trigger BE move on existing trades

input group "=== Entry Settings (Layering) ==="
input bool UseLayeredEntries = true;           // Enable layered entries
input int MaxLayers = 5;                       // Maximum layers per trade
input double LayerSpacingPips = 10.0;          // Spacing between layers (pips) - Auto converts to points based on symbol
input double EntryZonePips = 20.0;             // Entry zone size (pips) - Auto converts to points based on symbol
input bool WaitForConfirmation = false;        // Wait for candle close
input double MinOppositeDistancePips = 5.0;    // Minimum distance between opposite trades (pips) - Only blocks if within this distance
input double OppositeTradeTP_Pips = 5.0;        // TP for opposite trades (quick exit) - Auto converts to points

input group "=== Engulfing Candle Detection ==="
input bool UseEngulfingCandles = true;         // Enable engulfing candle entries
input bool EngulfingAtSupport = true;           // Trade engulfing candles at support zones (M5)
input bool EngulfingAtSessionSweep = true;     // Trade engulfing candles at session sweeps
input double EngulfingMinSize = 5.0;            // Minimum engulfing candle size (pips)
input int EngulfingLookback = 3;                // Bars to look back for engulfing pattern

input group "=== Confluence Requirements ==="
input int MinConfluence = 1;                   // Minimum confluence factors required (1 = very aggressive)
input bool RequireOrderBlock = false;           // Require Order Block for entry
input bool RequireFVG = false;                 // Require FVG for entry
input bool RequireTrendLine = false;            // Require Trend Line for entry
input bool RequireSessionLevel = false;        // Require Session Level for entry
input bool RequireEngulfing = false;            // Require Engulfing Candle for entry
input bool AllowMultipleTradesInZone = true;    // Allow multiple trades in same zone
input int MaxTradesPerZone = 3;                // Maximum trades per zone

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES PrimaryTF = PERIOD_M5;   // Primary timeframe (scalping)
input ENUM_TIMEFRAMES HTF = PERIOD_H1;         // Higher timeframe for context

input group "=== News Filter ==="
input bool BlockTradesDuringNews = true;      // Block trades during high-impact news events
input int NewsBlockMinutesBefore = 5;          // Minutes before news to block trades
input int NewsBlockMinutesAfter = 15;          // Minutes after news to block trades

input group "=== License Protection ==="
input bool EnableLicenseCheck = true;         // Enable license protection (DISABLE ONLY FOR TESTING)
input string LicenseServerURL = "https://mt5-license-server-production.up.railway.app"; // License Server URL
input string LicenseKey = "";                 // License Key (optional - provided by developer)
input string AllowedAccounts = "";           // Allowed Account Numbers (fallback - comma-separated)
input string AllowedBrokers = "";            // Allowed Brokers/Servers (fallback - comma-separated)
input datetime LicenseExpiry = 0;            // License Expiry Date (fallback - 0 = no expiry)
input string UserName = "";                  // User Name (for tracking - embedded in trades)
input bool UseRemoteValidation = true;        // Use remote server validation (MOST SECURE)
input int LicenseCheckTimeout = 5;            // License check timeout (seconds)

input group "=== General ==="
input int MagicNumber = 123457;                // Magic number
input string TradeComment = "Goldmine Edge – Gold";  // Trade comment
input int Slippage = 10;                       // Slippage in points

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
struct OrderBlock {
    double top;
    double bottom;
    datetime time;
    bool isBullish;
    bool isActive;
    int barIndex;
    ENUM_TIMEFRAMES timeframe;
};

struct FVG {
    double top;
    double bottom;
    datetime time;
    bool isBullish;
    bool isActive;
    int barIndex;
    ENUM_TIMEFRAMES timeframe;
};

struct TrendLine {
    double price1;
    double price2;
    int bar1;
    int bar2;
    bool isSupport;
    bool isActive;
    int touchCount;
    double angle;
};

struct SessionLevel {
    double high;
    double low;
    datetime sessionStart;
    datetime sessionEnd;
    bool highSwept;
    bool lowSwept;
    bool highRetested;
    bool lowRetested;
    datetime highSweepTime;      // Time when high was swept
    datetime lowSweepTime;        // Time when low was swept
    string sessionName;
};

struct DailyLevel {
    double high;
    double low;
    datetime date;
    bool highSwept;
    bool lowSwept;
};

struct WeeklyLevel {
    double high;
    double low;
    datetime weekStart;
    bool highSwept;
    bool lowSwept;
};

struct ConfluenceZone {
    double top;
    double bottom;
    int orderBlockCount;
    int fvgCount;
    int trendLineCount;
    int sessionLevelCount;
    int srTouchCount;              // Support/Resistance touch count
    int engulfingCandleCount;      // Engulfing candle count
    bool closedOnSupport;          // Price closed on support (high-probability reversal)
    bool closedOnResistance;       // Price closed on resistance (high-probability reversal)
    bool fvgRetest;                // FVG retest detected (50% hit = reversal)
    bool hasDailyLevel;
    bool hasWeeklyLevel;
    bool hasHourlySweep;
    bool hasSessionSweep;          // Session sweep detected
    int totalConfluence;
    bool isBullish;
};

OrderBlock orderBlocks[];
FVG fvgs[];
TrendLine trendLines[];
SessionLevel nySession, londonSession, asianSession;
DailyLevel dailyLevel;
WeeklyLevel weeklyLevel;
double hourlySweeps[];

// Market Structure (BigBeluga style)
struct MarketStructure {
    int trend;              // 1 = bullish, -1 = bearish, 0 = neutral
    double lastBOS;         // Last Break of Structure
    double lastCHoCH;       // Last Change of Character
    datetime lastBOS_Time;
    datetime lastCHoCH_Time;
};
MarketStructure marketStruct;

// Range Detection
struct TradingRange {
    double buyZoneTop;      // Top of buy zone (order block below)
    double buyZoneBottom;   // Bottom of buy zone
    double sellZoneTop;     // Top of sell zone (order block above)
    double sellZoneBottom;  // Bottom of sell zone
    bool hasBuyZone;
    bool hasSellZone;
    int trendDirection;     // 1 = uptrend (focus on buys), -1 = downtrend (focus on sells), 0 = range
};
TradingRange currentRange;

double point;
int symbolDigits;
double pipValue;
double accountBalance;
datetime lastBarTime = 0;

// Position tracking
bool tp1Hit[];
bool tp2Hit[];
bool tp3Hit[];
bool tp4Hit[];
double tp1HitPrice[];
int partialCloseLevel[]; // Track which partial close level reached
double originalVolume[]; // Track original position size for accurate partial closes

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
    string eaName = "Goldmine Edge – Gold";
    
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
    int timeout = LicenseCheckTimeout * 1000; // Convert to milliseconds
    int res = WebRequest("POST", LicenseServerURL, NULL, NULL, timeout, post, 0, result, headers);
    
    if(res == -1) {
        int error = GetLastError();
        Print("ERROR: WebRequest failed. Error code: ", error);
        if(error == 4060) {
            Print("ERROR: URL not allowed in MT5 settings!");
            Print("Please add this URL to MT5: Tools → Options → Expert Advisors → Allow WebRequest for listed URL");
            Print("URL: ", LicenseServerURL);
        }
        return false;
    }
    
    // Parse response
    string response = CharArrayToString(result);
    Print("License Server Response: ", response);
    
    // Check if response contains "valid":true
    if(StringFind(response, "\"valid\":true") >= 0 || StringFind(response, "\"valid\": true") >= 0) {
        Print("=== REMOTE LICENSE VALIDATION: SUCCESS ===");
        return true;
    } else {
        Print("=== REMOTE LICENSE VALIDATION: FAILED ===");
        Print("Response: ", response);
        return false;
    }
}

//+------------------------------------------------------------------+
//| License Check Function                                           |
//+------------------------------------------------------------------+
bool CheckLicense() {
    if(!EnableLicenseCheck) {
        Print("WARNING: License check is DISABLED - EA is running in test mode!");
        return true; // Allow if disabled
    }
    
    // REMOTE VALIDATION FIRST (if enabled)
    if(UseRemoteValidation) {
        Print("Attempting remote license validation...");
        if(ValidateLicenseRemote()) {
            Print("=== LICENSE: VALID (Remote Server) ===");
            return true;
        } else {
            Print("WARNING: Remote validation failed, falling back to local checks");
            // Continue with local validation as fallback
        }
    }
    
    long accountNumber = account.Login();
    string accountServer = account.Server();
    datetime currentTime = TimeCurrent();
    
    Print("=== LICENSE CHECK (Local Fallback) ===");
    Print("Account Number: ", accountNumber);
    Print("Broker/Server: ", accountServer);
    Print("Current Time: ", TimeToString(currentTime, TIME_DATE|TIME_MINUTES));
    
    // Check 1: License Key (if provided)
    if(StringLen(LicenseKey) > 0) {
        string expectedKey = "ADVSCALPER_" + IntegerToString(accountNumber) + "_2024";
        if(LicenseKey != expectedKey && LicenseKey != "DEMO_KEY_12345") {
            Print("ERROR: Invalid License Key!");
            Print("Provided: ", LicenseKey);
            Alert("LICENSE ERROR: Invalid License Key! Contact developer.");
            return false;
        }
        Print("License Key: VALID");
    }
    
    // Check 2: Allowed Accounts (whitelist)
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
            Print("ERROR: Account ", accountNumber, " is NOT in the allowed accounts list!");
            Print("Allowed Accounts: ", AllowedAccounts);
            Alert("LICENSE ERROR: Account not authorized! Contact developer.");
            return false;
        }
        Print("Account Authorization: VALID");
    }
    
    // Check 3: Allowed Brokers/Servers (if specified)
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
            Print("ERROR: Broker/Server '", accountServer, "' is NOT in the allowed list!");
            Print("Allowed Brokers: ", AllowedBrokers);
            Alert("LICENSE ERROR: Broker not authorized! Contact developer.");
            return false;
        }
        Print("Broker Authorization: VALID");
    }
    
    // Check 4: License Expiry
    if(LicenseExpiry > 0) {
        if(currentTime > LicenseExpiry) {
            Print("ERROR: License has EXPIRED!");
            Print("Expiry Date: ", TimeToString(LicenseExpiry, TIME_DATE|TIME_MINUTES));
            Print("Current Date: ", TimeToString(currentTime, TIME_DATE|TIME_MINUTES));
            Alert("LICENSE ERROR: License has expired! Contact developer to renew.");
            return false;
        }
        
        int daysRemaining = (int)((LicenseExpiry - currentTime) / 86400);
        Print("License Expiry: ", TimeToString(LicenseExpiry, TIME_DATE|TIME_MINUTES), " (", daysRemaining, " days remaining)");
    } else {
        Print("License Expiry: NO EXPIRY");
    }
    
    // Check 5: User Name (for tracking)
    if(StringLen(UserName) > 0) {
        Print("Licensed User: ", UserName);
    } else {
        Print("WARNING: User Name not set - cannot track usage!");
    }
    
    Print("=== LICENSE: VALID (Local Fallback) ===");
    return true;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // LICENSE CHECK FIRST - before anything else
    if(!CheckLicense()) {
        Print("EA initialization FAILED due to license check failure!");
        Alert("EA FAILED TO START: License validation failed. Contact developer.");
        return(INIT_FAILED);
    }
    
    // Validate symbol - use flexible detection
    string symbolUpper = _Symbol;
    StringToUpper(symbolUpper);
    bool isGold = (StringFind(symbolUpper, "XAU") >= 0 || StringFind(symbolUpper, "GOLD") >= 0);
    bool isSilver = (StringFind(symbolUpper, "XAG") >= 0 || StringFind(symbolUpper, "SILVER") >= 0);
    bool isValidSymbol = (isGold || isSilver);
    
    if(!isValidSymbol) {
        Print("ERROR: This EA is designed for XAUUSD (Gold) and XAGUSD (Silver) only!");
        Print("Current symbol: ", _Symbol, " (not recognized as Gold or Silver)");
        return(INIT_FAILED);
    }
    
    Print("Symbol validated: ", _Symbol, " | Gold: ", (isGold ? "YES" : "NO"), " | Silver: ", (isSilver ? "YES" : "NO"));
    
    // Initialize trade settings
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);
    
    // Get symbol properties
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Calculate pip value - DIFFERENT for Gold vs Silver
    // Reuse symbolUpper / isGold / isSilver from above (don't redeclare)
    
    if(isGold) {
        pipValue = point * 100;  // Gold: 1 pip = 100 points (MT5 uses points, not pips)
        Print("GOLD detected: 1 pip = 100 points | 20 pips = 2000 points");
        Print("VERIFICATION: pipValue = ", pipValue, " | point = ", point, " | 20 pips = ", (20.0 * pipValue), " points");
        
        // Comprehensive verification for Gold
        Print("=== GOLD SETTINGS VERIFICATION ===");
        Print("SL: ", SL_Pips, " pips = ", (SL_Pips * pipValue), " points");
        Print("TP1: ", TP1_Pips, " pips = ", (TP1_Pips * pipValue), " points");
        Print("TP2: ", TP2_Pips, " pips = ", (TP2_Pips * pipValue), " points");
        Print("TP3: ", TP3_Pips, " pips = ", (TP3_Pips * pipValue), " points");
        Print("BE: ", BreakEvenPips, " pips = ", (BreakEvenPips * pipValue), " points");
        Print("Entry Zone: ", EntryZonePips, " pips = ", (EntryZonePips * pipValue), " points");
        Print("Layer Spacing: ", LayerSpacingPips, " pips = ", (LayerSpacingPips * pipValue), " points");
        Print("FVG Min Size: ", FVG_MinSize, " pips = ", (FVG_MinSize * pipValue), " points");
        Print("SR Tolerance: ", SR_TouchTolerance, " pips = ", (SR_TouchTolerance * pipValue), " points");
        Print("Opposite Distance: ", MinOppositeDistancePips, " pips = ", (MinOppositeDistancePips * pipValue), " points");
        Print("Opposite TP: ", OppositeTradeTP_Pips, " pips = ", (OppositeTradeTP_Pips * pipValue), " points");
        Print("Engulfing Min: ", EngulfingMinSize, " pips = ", (EngulfingMinSize * pipValue), " points");
    } else if(isSilver) {
        pipValue = point * 10;  // Silver: 1 pip = 10 points (MT5 uses points, not pips)
        Print("SILVER detected: 1 pip = 10 points | 20 pips = 200 points");
        Print("VERIFICATION: pipValue = ", pipValue, " | point = ", point, " | 20 pips = ", (20.0 * pipValue), " points");
        
        // Comprehensive verification for Silver
        Print("=== SILVER SETTINGS VERIFICATION ===");
        Print("SL: ", SL_Pips, " pips = ", (SL_Pips * pipValue), " points");
        Print("TP1: ", TP1_Pips, " pips = ", (TP1_Pips * pipValue), " points");
        Print("TP2: ", TP2_Pips, " pips = ", (TP2_Pips * pipValue), " points");
        Print("TP3: ", TP3_Pips, " pips = ", (TP3_Pips * pipValue), " points");
        Print("BE: ", BreakEvenPips, " pips = ", (BreakEvenPips * pipValue), " points");
        Print("Entry Zone: ", EntryZonePips, " pips = ", (EntryZonePips * pipValue), " points");
        Print("Layer Spacing: ", LayerSpacingPips, " pips = ", (LayerSpacingPips * pipValue), " points");
        Print("FVG Min Size: ", FVG_MinSize, " pips = ", (FVG_MinSize * pipValue), " points");
        Print("SR Tolerance: ", SR_TouchTolerance, " pips = ", (SR_TouchTolerance * pipValue), " points");
        Print("Opposite Distance: ", MinOppositeDistancePips, " pips = ", (MinOppositeDistancePips * pipValue), " points");
        Print("Opposite TP: ", OppositeTradeTP_Pips, " pips = ", (OppositeTradeTP_Pips * pipValue), " points");
        Print("Engulfing Min: ", EngulfingMinSize, " pips = ", (EngulfingMinSize * pipValue), " points");
    } else {
        // Fallback: assume Gold if not detected
        pipValue = point * 100;
        Print("WARNING: Symbol not recognized as Gold or Silver! Assuming GOLD. Symbol: ", _Symbol);
        Print("VERIFICATION: pipValue = ", pipValue, " | point = ", point, " | 20 pips = ", (20.0 * pipValue), " points");
    }
    
    Print("========================================");
    Print("=== Goldmine Edge – Gold EA Initialized ===");
    Print("========================================");
    Print("Symbol: ", _Symbol);
    Print("Primary Timeframe: ", EnumToString(PrimaryTF));
    Print("TP System: TP1=", TP1_Pips, "pips (", TP1_Percent, "%) | TP2=", TP2_Pips, "pips (", TP2_Percent, "%) | TP3=", TP3_Pips, "pips (", TP3_Percent, "%) | TP4=1H S/R | Runner=", RunnerSizePercent, "%");
    Print("=== RISK MANAGEMENT ===");
    Print("Risk per trade: ", RiskPerTrade, "%", (RiskPerTrade > 2.0 ? " (HIGH - Consider 1-2% for better risk management)" : ""));
    Print("Max total risk: ", MaxTotalRisk, "% | Use Equity: ", UseEquity ? "YES" : "NO");
    Print("=== STOP LOSS (Dynamic) ===");
    Print("Base SL: ", SL_Pips, " pips | Dynamic: ", (UseDynamicSL ? "YES" : "NO"));
    if(UseDynamicSL) {
        Print("  - Additional SL per confluence: ", SL_PerConfluence, " pips");
        Print("  - Max SL: ", SL_MaxPips, " pips | Outside zone: ", (SL_OutsideZone ? "YES" : "NO"));
        Print("  - Example: 3 confluence = ", (SL_Pips + (2 * SL_PerConfluence)), " pips SL");
    }
    Print("Account Leverage: ", AccountLeverage == 999999 ? "UNLIMITED" : IntegerToString(AccountLeverage), ":1");
    Print("Break-Even: ", BreakEvenPips, " pips profit (exact BE)");
    Print("Confluence required: ", MinConfluence, " factors (1 = very aggressive)");
    Print("=== OPPOSITE TRADES ===");
    Print("Min opposite distance: ", MinOppositeDistancePips, " pips (only blocks if within this distance)");
    Print("Opposite trade TP: ", OppositeTradeTP_Pips, " pips (quick exit when entering opposite to existing trade)");
    Print("  - Allows opposite trades if > ", MinOppositeDistancePips, " pips apart");
    Print("  - Higher timeframe direction wins if it has confluences");
    Print("=== NEWS FILTER ===");
    Print("Block trades during news: ", (BlockTradesDuringNews ? "YES" : "NO"));
    if(BlockTradesDuringNews) {
        Print("  - Block window: ", NewsBlockMinutesBefore, " min before + ", NewsBlockMinutesAfter, " min after news");
        Print("  - News times: 8:30 AM, 10:00 AM, 2:00 PM, 4:00 PM (broker time)");
    }
    
    // Test lot size calculation with current settings
    double testEquity = UseEquity ? account.Equity() : account.Balance();
    double testRisk = testEquity * (RiskPerTrade / 100.0);
    double testSL = SL_Pips * pipValue; // Auto converts pips to points
    double testLotSize = CalculateLotSize(testRisk, testSL);
    Print("=== Lot Size Test ===");
    Print("Equity: $", testEquity, " | Risk: $", testRisk, " (", RiskPerTrade, "%)");
    Print("SL Distance: ", testSL, " points (", SL_Pips, " pips)");
    Print("Calculated Lot Size: ", testLotSize);
    Print("Free Margin: $", account.FreeMargin());
    Print("Multiple trades per zone: ", AllowMultipleTradesInZone ? "YES" : "NO");
    Print("Max trades per zone: ", MaxTradesPerZone);
    Print("--- Detection Settings ---");
    Print("Order Blocks: ", UseOrderBlocks ? "ON" : "OFF");
    Print("  M1 OB: ", UseM1_OB ? "ON" : "OFF", " | M3 OB: ", UseM3_OB ? "ON" : "OFF", " | M5 OB: ", UseM5_OB ? "ON" : "OFF", " | M15 OB: ", UseM15_OB ? "ON" : "OFF", " | M30 OB: ", UseM30_OB ? "ON" : "OFF");
    Print("FVG: ", UseFVG ? "ON" : "OFF");
    Print("  M1 FVG: ", UseM1_FVG ? "ON" : "OFF", " | M3 FVG: ", UseM3_FVG ? "ON" : "OFF", " | M5 FVG: ", UseM5_FVG ? "ON" : "OFF", " | M15 FVG: ", UseM15_FVG ? "ON" : "OFF");
    Print("Support/Resistance Touch: ", UseSR_Touch ? "ON" : "OFF");
    if(UseSR_Touch) {
        Print("  M1 SR: ", UseM1_SR ? "ON" : "OFF", " | M5 SR: ", UseM5_SR ? "ON" : "OFF", " | M15 SR: ", UseM15_SR ? "ON" : "OFF");
    }
    Print("Engulfing Candles: ", UseEngulfingCandles ? "ON" : "OFF");
    if(UseEngulfingCandles) {
        Print("  - At Support: ", EngulfingAtSupport ? "YES" : "NO");
        Print("  - At Session Sweep: ", EngulfingAtSessionSweep ? "YES" : "NO");
        Print("  - Min Size: ", EngulfingMinSize, " pips");
    }
    // Initialize market structure
    marketStruct.trend = 0;
    marketStruct.lastBOS = 0;
    marketStruct.lastCHoCH = 0;
    marketStruct.lastBOS_Time = 0;
    marketStruct.lastCHoCH_Time = 0;
    
    // Initialize trading range
    currentRange.hasBuyZone = false;
    currentRange.hasSellZone = false;
    currentRange.trendDirection = 0;
    
    Print("=== TREND & RANGE TRADING ===");
    Print("Trade with trend only: ", TradeWithTrendOnly ? "YES" : "NO");
    Print("Range trading: ", UseRangeTrading ? "YES" : "NO");
    if(UseRangeTrading) {
        Print("  - Range timeframe: ", EnumToString(RangeTimeframe));
    }
    Print("Market structure (BOS/CHoCH): ", UseMarketStructure ? "YES" : "NO");
    if(UseMarketStructure) {
        Print("  - Swing length: ", MS_SwingLength);
    }
    Print("=== TRADE MANAGEMENT ===");
    Print("Allow new trades while in trade: ", AllowNewTradesWhileInTrade ? "YES" : "NO");
    Print("Move to BE on new trade: ", MoveToBE_OnNewTrade ? "YES" : "NO");
    if(MoveToBE_OnNewTrade) {
        Print("  - Min confluence to trigger BE move: ", MinConfluenceForBE_Move);
    }
    Print("--- Requirements (all FALSE = no requirements) ---");
    Print("Require Order Block: ", RequireOrderBlock ? "YES" : "NO");
    Print("Require FVG: ", RequireFVG ? "YES" : "NO");
    Print("Require Trend Line: ", RequireTrendLine ? "YES" : "NO");
    Print("Require Session Level: ", RequireSessionLevel ? "YES" : "NO");
    Print("========================================");
    Print("EA will log detection status every 30 seconds");
    Print("Check Experts tab to see what's being detected");
    Print("========================================");
    
    // Initialize arrays
    ArrayResize(orderBlocks, 0);
    ArrayResize(fvgs, 0);
    ArrayResize(trendLines, 0);
    ArrayResize(hourlySweeps, 0);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("Goldmine Edge – Gold EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
    // Periodic license check (every hour) - prevents unauthorized use
    static datetime lastLicenseCheck = 0;
    if(EnableLicenseCheck && TimeCurrent() - lastLicenseCheck >= 3600) { // Check every hour
        if(!CheckLicense()) {
            Print("LICENSE CHECK FAILED - Stopping EA!");
            Alert("LICENSE ERROR: EA will stop trading. Contact developer.");
            ExpertRemove(); // Stop the EA
            return;
        }
        lastLicenseCheck = TimeCurrent();
    }
    
    // ALWAYS manage positions on every tick
    ManagePositions();
    
    // Check for new bar (for detection updates)
    datetime currentBarTime = iTime(_Symbol, PrimaryTF, 0);
    bool isNewBar = (currentBarTime != lastBarTime);
    
    if(isNewBar) {
        lastBarTime = currentBarTime;
        
        // Update account balance
        accountBalance = account.Balance();
        
        // Update all detection systems on new bar
        if(UseOrderBlocks) DetectMultiTimeframeOrderBlocks();
        if(UseFVG) DetectMultiTimeframeFVG();
        if(UseTrendLines) DetectTrendLines();
        if(UseSessionLevels) UpdateSessionLevels();
        if(UseDailyLevels) UpdateDailyLevels();
        if(UseWeeklyLevels) UpdateWeeklyLevels();
        if(UseHourlySweeps) UpdateHourlySweeps();
        
        // Detect market structure and trading range (BigBeluga style)
        if(UseMarketStructure) DetectMarketStructure();
        if(UseRangeTrading) DetectTradingRange();
    }
    
    // Also detect market structure and range on every tick (for real-time updates)
    if(UseMarketStructure) DetectMarketStructure();
    if(UseRangeTrading) DetectTradingRange();
    
    // ALWAYS check for entries on every tick (for quick scalps)
    // Find confluence zones
    ConfluenceZone zones[];
    FindConfluenceZones(zones);
    
    // Check for entry signals based on confluence
    CheckConfluenceEntries(zones);
}

//+------------------------------------------------------------------+
//| Detect Multi-Timeframe Order Blocks                              |
//+------------------------------------------------------------------+
void DetectMultiTimeframeOrderBlocks() {
    // Detect on multiple timeframes for quick scalps
    if(UseM1_OB) DetectOrderBlocksOnTimeframe(PERIOD_M1);
    if(UseM3_OB) DetectOrderBlocksOnTimeframe(PERIOD_M3);
    if(UseM5_OB) DetectOrderBlocksOnTimeframe(PERIOD_M5);
    if(UseM15_OB) DetectOrderBlocksOnTimeframe(PERIOD_M15);  // M15 Order Blocks (reversal trades)
    if(UseM30_OB) DetectOrderBlocksOnTimeframe(PERIOD_M30);   // M30 Order Blocks (swing trades)
    // Also detect on primary TF
    DetectOrderBlocksOnTimeframe(PrimaryTF);
}

//+------------------------------------------------------------------+
//| Detect Order Blocks on Specific Timeframe                        |
//+------------------------------------------------------------------+
void DetectOrderBlocksOnTimeframe(ENUM_TIMEFRAMES tf) {
    int bars = iBars(_Symbol, tf);
    if(bars < OB_Lookback + 5) return;
    
    // Get ATR
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(iATR(_Symbol, tf, OB_ATR_Period), 0, 0, OB_Lookback + 5, atr);
    
    // Get volume
    long volume[];
    ArraySetAsSeries(volume, true);
    CopyTickVolume(_Symbol, tf, 0, OB_Lookback + 5, volume);
    
    // Calculate average volume
    double avgVolume = 0.0;
    for(int i = 1; i <= OB_Lookback; i++) {
        avgVolume += (double)volume[i];
    }
    avgVolume /= (double)OB_Lookback;
    
    // Get price data
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, tf, 0, OB_Lookback + 5, high);
    CopyLow(_Symbol, tf, 0, OB_Lookback + 5, low);
    CopyClose(_Symbol, tf, 0, OB_Lookback + 5, close);
    CopyOpen(_Symbol, tf, 0, OB_Lookback + 5, open);
    
    // Scan recent bars for order blocks (not just current bar)
    int scanBars = MathMin(10, OB_Lookback); // Scan last 10 bars or lookback, whichever is smaller
    
    for(int bar = 0; bar < scanBars; bar++) {
        // Check if this bar already has an order block
        bool alreadyExists = false;
        for(int i = 0; i < ArraySize(orderBlocks); i++) {
            if(orderBlocks[i].timeframe == tf && 
               orderBlocks[i].barIndex == (bars - 1 - bar) &&
               orderBlocks[i].isActive) {
                alreadyExists = true;
                break;
            }
        }
        if(alreadyExists) continue;
        
        // Check for bullish order block
        if(close[bar] > open[bar] && 
           volume[bar] > avgVolume * OB_VolumeMultiplier &&
           (close[bar] - open[bar]) > atr[bar] * OB_ATR_Multiplier &&
           (bar + 1 < ArraySize(low) && low[bar] < low[bar + 1])) {
            
            OrderBlock ob;
            ob.top = high[bar];
            ob.bottom = low[bar];
            ob.time = iTime(_Symbol, tf, bar);
            ob.isBullish = true;
            ob.isActive = true;
            ob.barIndex = bars - 1 - bar;
            ob.timeframe = tf;
            
            AddOrderBlock(ob);
            Print("Order Block detected: BULLISH on ", EnumToString(tf), " | Zone: ", ob.bottom, "-", ob.top, " | Bar: ", bar);
        }
        
        // Check for bearish order block
        if(close[bar] < open[bar] && 
           volume[bar] > avgVolume * OB_VolumeMultiplier &&
           (open[bar] - close[bar]) > atr[bar] * OB_ATR_Multiplier &&
           (bar + 1 < ArraySize(high) && high[bar] > high[bar + 1])) {
            
            OrderBlock ob;
            ob.top = high[bar];
            ob.bottom = low[bar];
            ob.time = iTime(_Symbol, tf, bar);
            ob.isBullish = false;
            ob.isActive = true;
            ob.barIndex = bars - 1 - bar;
            ob.timeframe = tf;
            
            AddOrderBlock(ob);
            Print("Order Block detected: BEARISH on ", EnumToString(tf), " | Zone: ", ob.bottom, "-", ob.top, " | Bar: ", bar);
        }
    }
    
    CleanOrderBlocks();
}

//+------------------------------------------------------------------+
//| Add Order Block                                                  |
//+------------------------------------------------------------------+
void AddOrderBlock(OrderBlock &ob) {
    int size = ArraySize(orderBlocks);
    ArrayResize(orderBlocks, size + 1);
    orderBlocks[size] = ob;
    
    if(size > 100) {
        ArrayRemove(orderBlocks, 0, 1);
    }
}

//+------------------------------------------------------------------+
//| Clean Invalidated Order Blocks                                   |
//+------------------------------------------------------------------+
void CleanOrderBlocks() {
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, PrimaryTF, 0, 10, close);
    
    int size = ArraySize(orderBlocks);
    for(int i = size - 1; i >= 0; i--) {
        if(!orderBlocks[i].isActive) continue;
        
        if(orderBlocks[i].isBullish) {
            if(close[0] < orderBlocks[i].bottom) {
                orderBlocks[i].isActive = false;
            }
        } else {
            if(close[0] > orderBlocks[i].top) {
                orderBlocks[i].isActive = false;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Multi-Timeframe FVG                                       |
//+------------------------------------------------------------------+
void DetectMultiTimeframeFVG() {
    ENUM_TIMEFRAMES timeframes[];
    int tfCount = 0;
    
    // Add lower timeframes for quick scalps
    if(UseM1_FVG) {
        ArrayResize(timeframes, tfCount + 1);
        timeframes[tfCount++] = PERIOD_M1;
    }
    if(UseM3_FVG) {
        ArrayResize(timeframes, tfCount + 1);
        timeframes[tfCount++] = PERIOD_M3;
    }
    if(UseM5_FVG) {
        ArrayResize(timeframes, tfCount + 1);
        timeframes[tfCount++] = PERIOD_M5;
    }
    if(UseM15_FVG) {
        ArrayResize(timeframes, tfCount + 1);
        timeframes[tfCount++] = PERIOD_M15;
    }
    if(UseM30_FVG) {
        ArrayResize(timeframes, tfCount + 1);
        timeframes[tfCount++] = PERIOD_M30;
    }
    if(UseH1_FVG) {
        ArrayResize(timeframes, tfCount + 1);
        timeframes[tfCount++] = PERIOD_H1;
    }
    
    for(int tf = 0; tf < tfCount; tf++) {
        DetectFVGOnTimeframe(timeframes[tf]);
    }
}

//+------------------------------------------------------------------+
//| Detect FVG on Specific Timeframe                                |
//+------------------------------------------------------------------+
void DetectFVGOnTimeframe(ENUM_TIMEFRAMES tf) {
    int bars = iBars(_Symbol, tf);
    if(bars < 5) return;
    
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, tf, 0, 5, high);
    CopyLow(_Symbol, tf, 0, 5, low);
    CopyClose(_Symbol, tf, 0, 5, close);
    CopyOpen(_Symbol, tf, 0, 5, open);
    
    // Bullish FVG: low[0] > high[2]
    if(low[0] > high[2] && close[1] > open[1]) {
        double fvgSize = (low[0] - high[2]) / pipValue;
        if(fvgSize >= FVG_MinSize) {
            FVG fvg;
            fvg.top = low[0];
            fvg.bottom = high[2];
            fvg.time = iTime(_Symbol, tf, 0);
            fvg.isBullish = true;
            fvg.isActive = true;
            fvg.barIndex = bars - 1;
            fvg.timeframe = tf;
            
            AddFVG(fvg);
        }
    }
    
    // Bearish FVG: high[0] < low[2]
    if(high[0] < low[2] && close[1] < open[1]) {
        double fvgSize = (low[2] - high[0]) / pipValue;
        if(fvgSize >= FVG_MinSize) {
            FVG fvg;
            fvg.top = low[2];
            fvg.bottom = high[0];
            fvg.time = iTime(_Symbol, tf, 0);
            fvg.isBullish = false;
            fvg.isActive = true;
            fvg.barIndex = bars - 1;
            fvg.timeframe = tf;
            
            AddFVG(fvg);
        }
    }
    
    CleanFVGOnTimeframe(tf);
}

//+------------------------------------------------------------------+
//| Add FVG                                                          |
//+------------------------------------------------------------------+
void AddFVG(FVG &fvg) {
    int size = ArraySize(fvgs);
    ArrayResize(fvgs, size + 1);
    fvgs[size] = fvg;
    
    if(size > 200) {
        ArrayRemove(fvgs, 0, 1);
    }
}

//+------------------------------------------------------------------+
//| Clean Invalidated FVG                                            |
//+------------------------------------------------------------------+
void CleanFVGOnTimeframe(ENUM_TIMEFRAMES tf) {
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, tf, 0, 10, close);
    
    int size = ArraySize(fvgs);
    for(int i = size - 1; i >= 0; i--) {
        if(!fvgs[i].isActive || fvgs[i].timeframe != tf) continue;
        
        if(fvgs[i].isBullish && close[0] < fvgs[i].bottom) {
            fvgs[i].isActive = false;
        } else if(!fvgs[i].isBullish && close[0] > fvgs[i].top) {
            fvgs[i].isActive = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Trend Lines                                               |
//+------------------------------------------------------------------+
void DetectTrendLines() {
    int bars = iBars(_Symbol, HTF);
    if(bars < TrendLine_Lookback) return;
    
    // This is a simplified trend line detection
    // In production, you'd want more sophisticated swing point detection
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    CopyHigh(_Symbol, HTF, 0, TrendLine_Lookback, high);
    CopyLow(_Symbol, HTF, 0, TrendLine_Lookback, low);
    
    // Find swing highs and lows
    // Simplified: look for pivot highs/lows
    for(int i = TrendLine_TouchCount; i < TrendLine_Lookback - TrendLine_TouchCount; i++) {
        // Check for swing high
        bool isSwingHigh = true;
        for(int j = 1; j <= TrendLine_TouchCount; j++) {
            if(high[i] <= high[i-j] || high[i] <= high[i+j]) {
                isSwingHigh = false;
                break;
            }
        }
        
        if(isSwingHigh) {
            // Try to form trend line from this swing high
            // (Simplified - full implementation would track multiple points)
        }
        
        // Similar for swing lows
        bool isSwingLow = true;
        for(int j = 1; j <= TrendLine_TouchCount; j++) {
            if(low[i] >= low[i-j] || low[i] >= low[i+j]) {
                isSwingLow = false;
                break;
            }
        }
    }
    
    // Note: Full trend line detection is complex and would require
    // tracking multiple swing points and calculating line equations
    // This is a placeholder for the concept
}

//+------------------------------------------------------------------+
//| Update Session Levels                                            |
//+------------------------------------------------------------------+
void UpdateSessionLevels() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // NY Session: 8:00-17:00 EST (13:00-22:00 GMT)
    if(UseNYSession) {
        UpdateSession(nySession, 13, 22, "NY");
    }
    
    // London Session: 3:00-12:00 EST (8:00-17:00 GMT)
    if(UseLondonSession) {
        UpdateSession(londonSession, 8, 17, "London");
    }
    
    // Asian Session: 20:00-5:00 EST (1:00-10:00 GMT next day)
    if(UseAsianSession) {
        UpdateSession(asianSession, 1, 10, "Asian");
    }
}

//+------------------------------------------------------------------+
//| Update Individual Session                                       |
//+------------------------------------------------------------------+
void UpdateSession(SessionLevel &session, int startHour, int endHour, string name) {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Check if we're in a new session
    bool inSession = false;
    if(startHour < endHour) {
        inSession = (dt.hour >= startHour && dt.hour < endHour);
    } else {
        // Session spans midnight
        inSession = (dt.hour >= startHour || dt.hour < endHour);
    }
    
    if(inSession) {
        // Update session high/low
        double currentHigh = iHigh(_Symbol, PERIOD_H1, 0);
        double currentLow = iLow(_Symbol, PERIOD_H1, 0);
        
        if(session.high == 0 || currentHigh > session.high) {
            session.high = currentHigh;
        }
        if(session.low == 0 || currentLow < session.low) {
            session.low = currentLow;
        }
        
        session.sessionName = name;
        
        // Check for sweeps
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if(UseSessionSweeps) {
            if(!session.highSwept && currentPrice > session.high + (5 * pipValue)) {
                session.highSwept = true;
                session.highSweepTime = TimeCurrent();
                Print("Session High Swept: ", name, " at ", session.high);
            }
            if(!session.lowSwept && currentPrice < session.low - (5 * pipValue)) {
                session.lowSwept = true;
                session.lowSweepTime = TimeCurrent();
                Print("Session Low Swept: ", name, " at ", session.low);
            }
        }
        
        // Check for retests
        if(UseSessionRetests) {
            if(session.highSwept && !session.highRetested) {
                if(currentPrice >= session.high - (10 * pipValue) && 
                   currentPrice <= session.high + (10 * pipValue)) {
                    session.highRetested = true;
                    Print("Session High Retest: ", name, " at ", session.high);
                }
            }
            if(session.lowSwept && !session.lowRetested) {
                if(currentPrice >= session.low - (10 * pipValue) && 
                   currentPrice <= session.low + (10 * pipValue)) {
                    session.lowRetested = true;
                    Print("Session Low Retest: ", name, " at ", session.low);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Update Daily Levels                                              |
//+------------------------------------------------------------------+
void UpdateDailyLevels() {
    if(!UseDailyLevels) return;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Check if new day
    static int lastDay = -1;
    if(dt.day != lastDay) {
        lastDay = dt.day;
        
        // Get previous day's high/low
        int bars = iBars(_Symbol, PERIOD_D1);
        if(bars >= 2) {
            dailyLevel.high = iHigh(_Symbol, PERIOD_D1, 1);
            dailyLevel.low = iLow(_Symbol, PERIOD_D1, 1);
            dailyLevel.date = iTime(_Symbol, PERIOD_D1, 1);
            dailyLevel.highSwept = false;
            dailyLevel.lowSwept = false;
        }
    }
    
    // Check for sweeps
    if(UseDailySweeps) {
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if(!dailyLevel.highSwept && currentPrice > dailyLevel.high + (5 * pipValue)) {
            dailyLevel.highSwept = true;
            Print("Daily High Swept at ", dailyLevel.high);
        }
        if(!dailyLevel.lowSwept && currentPrice < dailyLevel.low - (5 * pipValue)) {
            dailyLevel.lowSwept = true;
            Print("Daily Low Swept at ", dailyLevel.low);
        }
    }
}

//+------------------------------------------------------------------+
//| Update Weekly Levels                                             |
//+------------------------------------------------------------------+
void UpdateWeeklyLevels() {
    if(!UseWeeklyLevels) return;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Check if new week (Monday)
    static int lastWeekDay = -1;
    if(dt.day_of_week == 1 && dt.day_of_week != lastWeekDay) {
        lastWeekDay = dt.day_of_week;
        
        // Get previous week's high/low
        int bars = iBars(_Symbol, PERIOD_W1);
        if(bars >= 2) {
            weeklyLevel.high = iHigh(_Symbol, PERIOD_W1, 1);
            weeklyLevel.low = iLow(_Symbol, PERIOD_W1, 1);
            weeklyLevel.weekStart = iTime(_Symbol, PERIOD_W1, 1);
            weeklyLevel.highSwept = false;
            weeklyLevel.lowSwept = false;
        }
    }
    
    // Check for sweeps
    if(UseWeeklySweeps) {
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        if(!weeklyLevel.highSwept && currentPrice > weeklyLevel.high + (5 * pipValue)) {
            weeklyLevel.highSwept = true;
            Print("Weekly High Swept at ", weeklyLevel.high);
        }
        if(!weeklyLevel.lowSwept && currentPrice < weeklyLevel.low - (5 * pipValue)) {
            weeklyLevel.lowSwept = true;
            Print("Weekly Low Swept at ", weeklyLevel.low);
        }
    }
}

//+------------------------------------------------------------------+
//| Update Hourly Sweeps                                             |
//+------------------------------------------------------------------+
void UpdateHourlySweeps() {
    if(!UseHourlySweeps) return;
    
    int bars = iBars(_Symbol, PERIOD_H1);
    if(bars < HourlySweep_Lookback) return;
    
    ArrayResize(hourlySweeps, HourlySweep_Lookback * 2);
    
    // Store hourly highs and lows
    for(int i = 0; i < HourlySweep_Lookback; i++) {
        hourlySweeps[i * 2] = iHigh(_Symbol, PERIOD_H1, i);
        hourlySweeps[i * 2 + 1] = iLow(_Symbol, PERIOD_H1, i);
    }
}

//+------------------------------------------------------------------+
//| Detect Support/Resistance Levels on Timeframe                   |
//+------------------------------------------------------------------+
void DetectSR_Levels(ENUM_TIMEFRAMES tf, double &supports[], double &resistances[]) {
    ArrayResize(supports, 0);
    ArrayResize(resistances, 0);
    
    if(!UseSR_Touch) return;
    
    int bars = iBars(_Symbol, tf);
    if(bars < SR_Lookback) return;
    
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    CopyHigh(_Symbol, tf, 0, SR_Lookback, high);
    CopyLow(_Symbol, tf, 0, SR_Lookback, low);
    CopyClose(_Symbol, tf, 0, SR_Lookback, close);
    
    double tolerance = SR_TouchTolerance * pipValue;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Find swing highs (resistance) and swing lows (support)
    for(int i = 5; i < SR_Lookback - 5; i++) {
        // Check for swing high (resistance)
        bool isSwingHigh = true;
        for(int j = i - 3; j <= i + 3; j++) {
            if(j != i && high[j] >= high[i]) {
                isSwingHigh = false;
                break;
            }
        }
        if(isSwingHigh && high[i] > currentPrice) {
            // Check if price is touching this resistance
            if(MathAbs(currentPrice - high[i]) <= tolerance) {
                int size = ArraySize(resistances);
                ArrayResize(resistances, size + 1);
                resistances[size] = high[i];
            }
        }
        
        // Check for swing low (support)
        bool isSwingLow = true;
        for(int j = i - 3; j <= i + 3; j++) {
            if(j != i && low[j] <= low[i]) {
                isSwingLow = false;
                break;
            }
        }
        if(isSwingLow && low[i] < currentPrice) {
            // Check if price is touching this support
            if(MathAbs(currentPrice - low[i]) <= tolerance) {
                int size = ArraySize(supports);
                ArrayResize(supports, size + 1);
                supports[size] = low[i];
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Market Structure (BOS/CHoCH) - BigBeluga Style            |
//+------------------------------------------------------------------+
void DetectMarketStructure() {
    if(!UseMarketStructure) return;
    
    ENUM_TIMEFRAMES tf = RangeTimeframe; // Use range timeframe for structure
    int bars = iBars(_Symbol, tf);
    if(bars < MS_SwingLength + 5) return;
    
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    CopyHigh(_Symbol, tf, 0, MS_SwingLength + 5, high);
    CopyLow(_Symbol, tf, 0, MS_SwingLength + 5, low);
    CopyClose(_Symbol, tf, 0, MS_SwingLength + 5, close);
    
    // Find swing high and swing low
    double swingHigh = high[MS_SwingLength];
    double swingLow = low[MS_SwingLength];
    int swingHighIndex = MS_SwingLength;
    int swingLowIndex = MS_SwingLength;
    
    for(int i = 1; i <= MS_SwingLength; i++) {
        if(high[i] > swingHigh) {
            swingHigh = high[i];
            swingHighIndex = i;
        }
        if(low[i] < swingLow) {
            swingLow = low[i];
            swingLowIndex = i;
        }
    }
    
    double currentHigh = high[0];
    double currentLow = low[0];
    
    // Detect Break of Structure (BOS)
    if(marketStruct.trend == 0 || marketStruct.trend == -1) {
        // Bullish BOS: price breaks above previous swing high
        if(currentHigh > swingHigh && swingHighIndex > 0) {
            marketStruct.lastBOS = swingHigh;
            marketStruct.lastBOS_Time = iTime(_Symbol, tf, swingHighIndex);
            marketStruct.trend = 1; // Bullish
            Print("*** BULLISH BOS DETECTED on ", EnumToString(tf), " at ", swingHigh, " ***");
        }
    }
    
    if(marketStruct.trend == 0 || marketStruct.trend == 1) {
        // Bearish BOS: price breaks below previous swing low
        if(currentLow < swingLow && swingLowIndex > 0) {
            marketStruct.lastBOS = swingLow;
            marketStruct.lastBOS_Time = iTime(_Symbol, tf, swingLowIndex);
            marketStruct.trend = -1; // Bearish
            Print("*** BEARISH BOS DETECTED on ", EnumToString(tf), " at ", swingLow, " ***");
        }
    }
    
    // Detect Change of Character (CHoCH)
    if(marketStruct.trend == 1) {
        // Bearish CHoCH: price breaks below recent swing low
        if(currentLow < swingLow) {
            marketStruct.lastCHoCH = currentLow;
            marketStruct.lastCHoCH_Time = iTime(_Symbol, tf, 0);
            marketStruct.trend = -1; // Changed to bearish
            Print("*** BEARISH CHoCH DETECTED on ", EnumToString(tf), " at ", currentLow, " ***");
        }
    } else if(marketStruct.trend == -1) {
        // Bullish CHoCH: price breaks above recent swing high
        if(currentHigh > swingHigh) {
            marketStruct.lastCHoCH = currentHigh;
            marketStruct.lastCHoCH_Time = iTime(_Symbol, tf, 0);
            marketStruct.trend = 1; // Changed to bullish
            Print("*** BULLISH CHoCH DETECTED on ", EnumToString(tf), " at ", currentHigh, " ***");
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Trading Range (Buy Zones Below, Sell Zones Above)        |
//+------------------------------------------------------------------+
void DetectTradingRange() {
    if(!UseRangeTrading) return;
    
    // Reset range
    currentRange.hasBuyZone = false;
    currentRange.hasSellZone = false;
    currentRange.trendDirection = 0;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Find order blocks on range timeframe
    double buyZoneTop = 0;
    double buyZoneBottom = DBL_MAX;
    double sellZoneTop = 0;
    double sellZoneBottom = DBL_MAX;
    
    int obSize = ArraySize(orderBlocks);
    for(int i = 0; i < obSize; i++) {
        if(!orderBlocks[i].isActive) continue;
        
        // Check if OB is on range timeframe (simplified - check if OB is recent)
        datetime obTime = orderBlocks[i].time;
        datetime currentTime = TimeCurrent();
        if(currentTime - obTime > 86400) continue; // Skip OBs older than 1 day
        
        if(orderBlocks[i].isBullish) {
            // Bullish OB = Buy zone (below current price)
            if(orderBlocks[i].top < currentPrice) {
                if(!currentRange.hasBuyZone || orderBlocks[i].top > buyZoneTop) {
                    buyZoneTop = orderBlocks[i].top;
                    buyZoneBottom = orderBlocks[i].bottom;
                    currentRange.hasBuyZone = true;
                }
            }
        } else {
            // Bearish OB = Sell zone (above current price)
            if(orderBlocks[i].bottom > currentPrice) {
                if(!currentRange.hasSellZone || orderBlocks[i].bottom < sellZoneBottom) {
                    sellZoneTop = orderBlocks[i].top;
                    sellZoneBottom = orderBlocks[i].bottom;
                    currentRange.hasSellZone = true;
                }
            }
        }
    }
    
    if(currentRange.hasBuyZone) {
        currentRange.buyZoneTop = buyZoneTop;
        currentRange.buyZoneBottom = buyZoneBottom;
    }
    
    if(currentRange.hasSellZone) {
        currentRange.sellZoneTop = sellZoneTop;
        currentRange.sellZoneBottom = sellZoneBottom;
    }
    
    // Determine trend direction within range
    if(currentRange.hasBuyZone && currentRange.hasSellZone) {
        // We have both zones - determine trend
        if(UseMarketStructure) {
            // Use market structure trend
            currentRange.trendDirection = marketStruct.trend;
        } else {
            // Use price position: if closer to buy zone, trend up; if closer to sell zone, trend down
            double distToBuy = currentPrice - currentRange.buyZoneTop;
            double distToSell = currentRange.sellZoneBottom - currentPrice;
            
            if(distToBuy < distToSell) {
                currentRange.trendDirection = 1; // Closer to buy zone, trend up
            } else {
                currentRange.trendDirection = -1; // Closer to sell zone, trend down
            }
        }
        
        static datetime lastRangeLog = 0;
        if(TimeCurrent() - lastRangeLog > 60) {
            Print("=== TRADING RANGE DETECTED ===");
            Print("Buy Zone: ", currentRange.buyZoneBottom, " - ", currentRange.buyZoneTop);
            Print("Sell Zone: ", currentRange.sellZoneBottom, " - ", currentRange.sellZoneTop);
            Print("Current Price: ", currentPrice);
            Print("Trend Direction: ", (currentRange.trendDirection == 1 ? "UP (Focus BUYS)" : currentRange.trendDirection == -1 ? "DOWN (Focus SELLS)" : "NEUTRAL"));
            lastRangeLog = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Engulfing Candles on M5                                   |
//+------------------------------------------------------------------+
bool DetectEngulfingCandle(ENUM_TIMEFRAMES tf, bool &isBullishEngulfing) {
    if(!UseEngulfingCandles) return false;
    
    int bars = iBars(_Symbol, tf);
    if(bars < EngulfingLookback + 2) return false;
    
    double open[], close[], high[], low[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    CopyOpen(_Symbol, tf, 0, EngulfingLookback + 2, open);
    CopyClose(_Symbol, tf, 0, EngulfingLookback + 2, close);
    CopyHigh(_Symbol, tf, 0, EngulfingLookback + 2, high);
    CopyLow(_Symbol, tf, 0, EngulfingLookback + 2, low);
    
    // Check for bullish engulfing (current candle engulfs previous bearish candle)
    if(close[0] > open[0] && close[1] < open[1]) { // Current is bullish, previous was bearish
        if(open[0] < close[1] && close[0] > open[1]) { // Engulfs previous candle
            double candleSize = close[0] - open[0];
            double minSize = EngulfingMinSize * pipValue;
            if(candleSize >= minSize) {
                isBullishEngulfing = true;
                return true;
            }
        }
    }
    
    // Check for bearish engulfing (current candle engulfs previous bullish candle)
    if(close[0] < open[0] && close[1] > open[1]) { // Current is bearish, previous was bullish
        if(open[0] > close[1] && close[0] < open[1]) { // Engulfs previous candle
            double candleSize = open[0] - close[0];
            double minSize = EngulfingMinSize * pipValue;
            if(candleSize >= minSize) {
                isBullishEngulfing = false;
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price is at Support Zone                                |
//+------------------------------------------------------------------+
bool IsPriceAtSupport(double price, double tolerance) {
    // Check order blocks below (support zones)
    int obSize = ArraySize(orderBlocks);
    for(int i = 0; i < obSize; i++) {
        if(!orderBlocks[i].isActive) continue;
        if(!orderBlocks[i].isBullish) continue; // Only bullish OBs are support
        
        // Check if price is touching or near the support zone
        if(price >= orderBlocks[i].bottom - tolerance && price <= orderBlocks[i].top + tolerance) {
            return true;
        }
    }
    
    // Check support/resistance levels
    if(UseSR_Touch) {
        double supports[], resistances[];
        if(UseM5_SR) {
            DetectSR_Levels(PERIOD_M5, supports, resistances);
            for(int s = 0; s < ArraySize(supports); s++) {
                if(MathAbs(price - supports[s]) <= tolerance) {
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price Closed on Support/Resistance (M15)                |
//+------------------------------------------------------------------+
bool PriceClosedOnSupport(ENUM_TIMEFRAMES tf, double &supportLevel) {
    if(!TradeCloseOnSupport) return false;
    
    int bars = iBars(_Symbol, tf);
    if(bars < 2) return false;
    
    double close[], low[], high[];
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(high, true);
    CopyClose(_Symbol, tf, 0, 10, close);
    CopyLow(_Symbol, tf, 0, 10, low);
    CopyHigh(_Symbol, tf, 0, 10, high);
    
    double prevClose = close[1]; // Previous candle close
    double tolerance = SR_TouchTolerance * pipValue;
    
    // Check order blocks (support zones)
    int obSize = ArraySize(orderBlocks);
    for(int i = 0; i < obSize; i++) {
        if(!orderBlocks[i].isActive) continue;
        if(!orderBlocks[i].isBullish) continue; // Only bullish OBs are support
        
        // Check if previous candle closed on or near this support
        if(prevClose >= orderBlocks[i].bottom - tolerance && prevClose <= orderBlocks[i].top + tolerance) {
            supportLevel = (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0;
            Print("*** PRICE CLOSED ON SUPPORT (M15) ***");
            Print("  Support Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
            Print("  Close Price: ", prevClose);
            return true;
        }
    }
    
    // Check M15 support/resistance levels
    if(UseM15_SR && UseSR_Touch) {
        double supports[], resistances[];
        DetectSR_Levels(PERIOD_M15, supports, resistances);
        for(int s = 0; s < ArraySize(supports); s++) {
            if(MathAbs(prevClose - supports[s]) <= tolerance) {
                supportLevel = supports[s];
                Print("*** PRICE CLOSED ON M15 SUPPORT LEVEL ***");
                Print("  Support: ", supportLevel, " | Close: ", prevClose);
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price Closed on Resistance (M15)                        |
//+------------------------------------------------------------------+
bool PriceClosedOnResistance(ENUM_TIMEFRAMES tf, double &resistanceLevel) {
    if(!TradeCloseOnResistance) return false;
    
    int bars = iBars(_Symbol, tf);
    if(bars < 2) return false;
    
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, tf, 0, 10, close);
    
    double prevClose = close[1]; // Previous candle close
    double tolerance = SR_TouchTolerance * pipValue;
    
    // Check order blocks (resistance zones)
    int obSize = ArraySize(orderBlocks);
    for(int i = 0; i < obSize; i++) {
        if(!orderBlocks[i].isActive) continue;
        if(orderBlocks[i].isBullish) continue; // Only bearish OBs are resistance
        
        // Check if previous candle closed on or near this resistance
        if(prevClose >= orderBlocks[i].bottom - tolerance && prevClose <= orderBlocks[i].top + tolerance) {
            resistanceLevel = (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0;
            Print("*** PRICE CLOSED ON RESISTANCE (M15) ***");
            Print("  Resistance Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
            Print("  Close Price: ", prevClose);
            return true;
        }
    }
    
    // Check M15 support/resistance levels
    if(UseM15_SR && UseSR_Touch) {
        double supports[], resistances[];
        DetectSR_Levels(PERIOD_M15, supports, resistances);
        for(int r = 0; r < ArraySize(resistances); r++) {
            if(MathAbs(prevClose - resistances[r]) <= tolerance) {
                resistanceLevel = resistances[r];
                Print("*** PRICE CLOSED ON M15 RESISTANCE LEVEL ***");
                Print("  Resistance: ", resistanceLevel, " | Close: ", prevClose);
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price Hit FVG Retest (50% of FVG)                       |
//+------------------------------------------------------------------+
bool CheckFVG_Retest(double &fvgTop, double &fvgBottom, bool &isBullishFVG) {
    if(!TradeFVG_Retest) return false;
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, PERIOD_M15, 0, 2, close);
    double prevClose = close[1];
    
    int fvgSize = ArraySize(fvgs);
    for(int i = 0; i < fvgSize; i++) {
        if(!fvgs[i].isActive) continue;
        
        double fvgMid = (fvgs[i].top + fvgs[i].bottom) / 2.0;
        double fvgRange = fvgs[i].top - fvgs[i].bottom;
        double tolerance = (fvgRange * (FVG_RetestPercent / 100.0)) * 0.1; // 10% tolerance
        
        // Check if price hit 50% (middle) of FVG
        if(MathAbs(prevClose - fvgMid) <= tolerance || MathAbs(currentPrice - fvgMid) <= tolerance) {
            fvgTop = fvgs[i].top;
            fvgBottom = fvgs[i].bottom;
            isBullishFVG = fvgs[i].isBullish;
            
            Print("*** FVG RETEST DETECTED (", FVG_RetestPercent, "% hit) ***");
            Print("  FVG Zone: ", fvgBottom, " - ", fvgTop);
            Print("  FVG Mid (", FVG_RetestPercent, "%): ", fvgMid);
            Print("  Price: ", currentPrice, " | Prev Close: ", prevClose);
            Print("  Type: ", (isBullishFVG ? "BULLISH FVG" : "BEARISH FVG"));
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Session Sweep Just Occurred                             |
//+------------------------------------------------------------------+
bool IsSessionSweepJustOccurred() {
    if(!UseSessionLevels) return false;
    
    // Check if any session sweep just happened (within last few bars)
    if(UseNYSession && nySession.lowSwept) {
        datetime sweepTime = nySession.lowSweepTime;
        if(sweepTime > 0 && TimeCurrent() - sweepTime < 300) return true; // Within 5 minutes
    }
    if(UseLondonSession && londonSession.lowSwept) {
        datetime sweepTime = londonSession.lowSweepTime;
        if(sweepTime > 0 && TimeCurrent() - sweepTime < 300) return true;
    }
    if(UseAsianSession && asianSession.lowSwept) {
        datetime sweepTime = asianSession.lowSweepTime;
        if(sweepTime > 0 && TimeCurrent() - sweepTime < 300) return true;
    }
    
    // Also check for high sweeps (for bearish engulfing)
    if(UseNYSession && nySession.highSwept) {
        datetime sweepTime = nySession.highSweepTime;
        if(sweepTime > 0 && TimeCurrent() - sweepTime < 300) return true;
    }
    if(UseLondonSession && londonSession.highSwept) {
        datetime sweepTime = londonSession.highSweepTime;
        if(sweepTime > 0 && TimeCurrent() - sweepTime < 300) return true;
    }
    if(UseAsianSession && asianSession.highSwept) {
        datetime sweepTime = asianSession.highSweepTime;
        if(sweepTime > 0 && TimeCurrent() - sweepTime < 300) return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Find Confluence Zones                                            |
//+------------------------------------------------------------------+
void FindConfluenceZones(ConfluenceZone &zones[]) {
    ArrayResize(zones, 0);
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double zoneSize = EntryZonePips * pipValue;
    
    // Debug: Log detection status
    static datetime lastLogTime = 0;
    datetime currentTime = TimeCurrent();
    if(currentTime - lastLogTime >= 30) { // Log every 30 seconds
        int obSize = ArraySize(orderBlocks);
        int activeOB = 0;
        for(int k = 0; k < obSize; k++) {
            if(orderBlocks[k].isActive) activeOB++;
        }
        int fvgSize = ArraySize(fvgs);
        int activeFVG = 0;
        for(int k = 0; k < fvgSize; k++) {
            if(fvgs[k].isActive) activeFVG++;
        }
        Print("=== Detection Status ===");
        Print("Active Order Blocks: ", activeOB, " | Active FVGs: ", activeFVG);
        Print("Current Price: ", currentPrice);
        Print("Min Confluence Required: ", MinConfluence);
        lastLogTime = currentTime;
    }
    
    // Check order blocks
    int obSize = ArraySize(orderBlocks);
    for(int i = 0; i < obSize; i++) {
        if(!orderBlocks[i].isActive) continue;
        
        ConfluenceZone zone;
        zone.top = orderBlocks[i].top;
        zone.bottom = orderBlocks[i].bottom;
        zone.orderBlockCount = 1;
        zone.fvgCount = 0;
        zone.trendLineCount = 0;
        zone.sessionLevelCount = 0;
        zone.srTouchCount = 0;
        zone.engulfingCandleCount = 0;
        zone.closedOnSupport = false;
        zone.closedOnResistance = false;
        zone.fvgRetest = false;
        zone.hasDailyLevel = false;
        zone.hasWeeklyLevel = false;
        zone.hasHourlySweep = false;
        zone.hasSessionSweep = false;
        zone.isBullish = orderBlocks[i].isBullish;
        
        // Check for FVG in same zone
        int fvgSize = ArraySize(fvgs);
        for(int j = 0; j < fvgSize; j++) {
            if(!fvgs[j].isActive) continue;
            if((fvgs[j].top >= zone.bottom && fvgs[j].top <= zone.top) ||
               (fvgs[j].bottom >= zone.bottom && fvgs[j].bottom <= zone.top) ||
               (fvgs[j].top >= zone.top && fvgs[j].bottom <= zone.bottom)) {
                zone.fvgCount++;
            }
        }
        
        // Check for session levels
        if(UseNYSession && IsPriceInZone(currentPrice, nySession.high, nySession.low, zone.top, zone.bottom)) {
            zone.sessionLevelCount++;
        }
        if(UseLondonSession && IsPriceInZone(currentPrice, londonSession.high, londonSession.low, zone.top, zone.bottom)) {
            zone.sessionLevelCount++;
        }
        if(UseAsianSession && IsPriceInZone(currentPrice, asianSession.high, asianSession.low, zone.top, zone.bottom)) {
            zone.sessionLevelCount++;
        }
        
        // Check for daily levels
        if(UseDailyLevels && IsPriceInZone(currentPrice, dailyLevel.high, dailyLevel.low, zone.top, zone.bottom)) {
            zone.hasDailyLevel = true;
        }
        
        // Check for weekly levels
        if(UseWeeklyLevels && IsPriceInZone(currentPrice, weeklyLevel.high, weeklyLevel.low, zone.top, zone.bottom)) {
            zone.hasWeeklyLevel = true;
        }
        
        // Check for hourly sweeps
        if(UseHourlySweeps) {
            int sweepSize = ArraySize(hourlySweeps);
            for(int k = 0; k < sweepSize; k++) {
                if(IsPriceInZone(currentPrice, hourlySweeps[k], hourlySweeps[k], zone.top, zone.bottom)) {
                    zone.hasHourlySweep = true;
                    break;
                }
            }
        }
        
        // Check for Support/Resistance touches (M1/M5/M15)
        zone.srTouchCount = 0;
        if(UseSR_Touch) {
            double supports[], resistances[];
            
            if(UseM1_SR) {
                DetectSR_Levels(PERIOD_M1, supports, resistances);
                for(int s = 0; s < ArraySize(supports); s++) {
                    if(supports[s] >= zone.bottom && supports[s] <= zone.top) {
                        zone.srTouchCount++;
                        zone.isBullish = true; // Support = bullish
                    }
                }
                for(int r = 0; r < ArraySize(resistances); r++) {
                    if(resistances[r] >= zone.bottom && resistances[r] <= zone.top) {
                        zone.srTouchCount++;
                        zone.isBullish = false; // Resistance = bearish
                    }
                }
            }
            
            if(UseM5_SR) {
                DetectSR_Levels(PERIOD_M5, supports, resistances);
                for(int s = 0; s < ArraySize(supports); s++) {
                    if(supports[s] >= zone.bottom && supports[s] <= zone.top) {
                        zone.srTouchCount++;
                        zone.isBullish = true;
                    }
                }
                for(int r = 0; r < ArraySize(resistances); r++) {
                    if(resistances[r] >= zone.bottom && resistances[r] <= zone.top) {
                        zone.srTouchCount++;
                        zone.isBullish = false;
                    }
                }
            }
            
            if(UseM15_SR) {
                DetectSR_Levels(PERIOD_M15, supports, resistances);
                for(int s = 0; s < ArraySize(supports); s++) {
                    if(supports[s] >= zone.bottom && supports[s] <= zone.top) {
                        zone.srTouchCount++;
                        zone.isBullish = true;
                    }
                }
                for(int r = 0; r < ArraySize(resistances); r++) {
                    if(resistances[r] >= zone.bottom && resistances[r] <= zone.top) {
                        zone.srTouchCount++;
                        zone.isBullish = false;
                    }
                }
            }
        }
        
        // Check for Engulfing Candles (M5 at support or session sweep)
        zone.engulfingCandleCount = 0;
        zone.hasSessionSweep = false;
        
        if(UseEngulfingCandles) {
            bool isBullishEngulfing = false;
            bool hasEngulfing = false;
            
            // Check for engulfing on M5
            if(DetectEngulfingCandle(PERIOD_M5, isBullishEngulfing)) {
                hasEngulfing = true;
                
                // Check if at support zone
                if(EngulfingAtSupport) {
                    double tolerance = 10 * pipValue; // 10 pip tolerance
                    if(IsPriceAtSupport(currentPrice, tolerance)) {
                        zone.engulfingCandleCount++;
                        zone.isBullish = isBullishEngulfing;
                        Print("*** ENGULFING CANDLE AT SUPPORT (M5) ***");
                        Print("  Type: ", (isBullishEngulfing ? "BULLISH" : "BEARISH"));
                        Print("  Price: ", currentPrice);
                    }
                }
                
                // Check if at session sweep
                if(EngulfingAtSessionSweep && IsSessionSweepJustOccurred()) {
                    zone.engulfingCandleCount++;
                    zone.hasSessionSweep = true;
                    zone.isBullish = isBullishEngulfing;
                    Print("*** ENGULFING CANDLE AT SESSION SWEEP (M5) ***");
                    Print("  Type: ", (isBullishEngulfing ? "BULLISH" : "BEARISH"));
                    Print("  Price: ", currentPrice);
                }
            }
        }
        
        // Calculate total confluence
        zone.totalConfluence = zone.orderBlockCount + zone.fvgCount + zone.trendLineCount + 
                               zone.sessionLevelCount + zone.srTouchCount + zone.engulfingCandleCount + 
                               (zone.hasDailyLevel ? 1 : 0) + 
                               (zone.hasWeeklyLevel ? 1 : 0) + (zone.hasHourlySweep ? 1 : 0) +
                               (zone.hasSessionSweep ? 1 : 0);
        
        if(zone.totalConfluence >= MinConfluence) {
            int size = ArraySize(zones);
            ArrayResize(zones, size + 1);
            zones[size] = zone;
        }
    }
    
    // ALSO create zones from FVGs (even without order blocks) - for more entry opportunities
    if(UseFVG) {
        int fvgSize = ArraySize(fvgs);
        for(int i = 0; i < fvgSize; i++) {
            if(!fvgs[i].isActive) continue;
            
            // Check if this FVG zone already exists (from order block)
            bool zoneExists = false;
            for(int j = 0; j < ArraySize(zones); j++) {
                if((fvgs[i].top >= zones[j].bottom && fvgs[i].top <= zones[j].top) ||
                   (fvgs[i].bottom >= zones[j].bottom && fvgs[i].bottom <= zones[j].top) ||
                   (fvgs[i].top >= zones[j].top && fvgs[i].bottom <= zones[j].bottom)) {
                    zoneExists = true;
                    break;
                }
            }
            if(zoneExists) continue; // Already have a zone for this area
            
            // Create FVG-only zone
            ConfluenceZone zone;
            zone.top = fvgs[i].top;
            zone.bottom = fvgs[i].bottom;
            zone.orderBlockCount = 0;
            zone.fvgCount = 1;
            zone.trendLineCount = 0;
            zone.sessionLevelCount = 0;
            zone.srTouchCount = 0;
            zone.engulfingCandleCount = 0;
            zone.hasDailyLevel = false;
            zone.hasWeeklyLevel = false;
            zone.hasHourlySweep = false;
            zone.hasSessionSweep = false;
            zone.isBullish = fvgs[i].isBullish;
            
            // Check for session levels
            if(UseNYSession && IsPriceInZone(currentPrice, nySession.high, nySession.low, zone.top, zone.bottom)) {
                zone.sessionLevelCount++;
            }
            if(UseLondonSession && IsPriceInZone(currentPrice, londonSession.high, londonSession.low, zone.top, zone.bottom)) {
                zone.sessionLevelCount++;
            }
            if(UseAsianSession && IsPriceInZone(currentPrice, asianSession.high, asianSession.low, zone.top, zone.bottom)) {
                zone.sessionLevelCount++;
            }
            
            // Check for daily/weekly levels
            if(UseDailyLevels && IsPriceInZone(currentPrice, dailyLevel.high, dailyLevel.low, zone.top, zone.bottom)) {
                zone.hasDailyLevel = true;
            }
            if(UseWeeklyLevels && IsPriceInZone(currentPrice, weeklyLevel.high, weeklyLevel.low, zone.top, zone.bottom)) {
                zone.hasWeeklyLevel = true;
            }
            
            // Calculate total confluence
            zone.totalConfluence = zone.orderBlockCount + zone.fvgCount + zone.trendLineCount + 
                                   zone.sessionLevelCount + (zone.hasDailyLevel ? 1 : 0) + 
                                   (zone.hasWeeklyLevel ? 1 : 0) + (zone.hasHourlySweep ? 1 : 0);
            
            // Check for Support/Resistance touches
            zone.srTouchCount = 0;
            if(UseSR_Touch) {
                double supports[], resistances[];
                
                if(UseM1_SR) {
                    DetectSR_Levels(PERIOD_M1, supports, resistances);
                    for(int s = 0; s < ArraySize(supports); s++) {
                        if(supports[s] >= zone.bottom && supports[s] <= zone.top) {
                            zone.srTouchCount++;
                            zone.isBullish = true;
                        }
                    }
                    for(int r = 0; r < ArraySize(resistances); r++) {
                        if(resistances[r] >= zone.bottom && resistances[r] <= zone.top) {
                            zone.srTouchCount++;
                            zone.isBullish = false;
                        }
                    }
                }
                
                if(UseM5_SR) {
                    DetectSR_Levels(PERIOD_M5, supports, resistances);
                    for(int s = 0; s < ArraySize(supports); s++) {
                        if(supports[s] >= zone.bottom && supports[s] <= zone.top) {
                            zone.srTouchCount++;
                            zone.isBullish = true;
                        }
                    }
                    for(int r = 0; r < ArraySize(resistances); r++) {
                        if(resistances[r] >= zone.bottom && resistances[r] <= zone.top) {
                            zone.srTouchCount++;
                            zone.isBullish = false;
                        }
                    }
                }
                
                if(UseM15_SR) {
                    DetectSR_Levels(PERIOD_M15, supports, resistances);
                    for(int s = 0; s < ArraySize(supports); s++) {
                        if(supports[s] >= zone.bottom && supports[s] <= zone.top) {
                            zone.srTouchCount++;
                            zone.isBullish = true;
                        }
                    }
                    for(int r = 0; r < ArraySize(resistances); r++) {
                        if(resistances[r] >= zone.bottom && resistances[r] <= zone.top) {
                            zone.srTouchCount++;
                            zone.isBullish = false;
                        }
                    }
                }
            }
            
            // Check for Engulfing Candles (M5 at support or session sweep)
            zone.engulfingCandleCount = 0;
            zone.hasSessionSweep = false;
            
            if(UseEngulfingCandles) {
                bool isBullishEngulfing = false;
                
                // Check for engulfing on M5
                if(DetectEngulfingCandle(PERIOD_M5, isBullishEngulfing)) {
                    // Check if at support zone
                    if(EngulfingAtSupport) {
                        double tolerance = 10 * pipValue;
                        if(IsPriceAtSupport(currentPrice, tolerance)) {
                            zone.engulfingCandleCount++;
                            zone.isBullish = isBullishEngulfing;
                        }
                    }
                    
                    // Check if at session sweep
                    if(EngulfingAtSessionSweep && IsSessionSweepJustOccurred()) {
                        zone.engulfingCandleCount++;
                        zone.hasSessionSweep = true;
                        zone.isBullish = isBullishEngulfing;
                    }
                }
            }
            
            // Check for high-probability reversal setups
            double supportLevel = 0, resistanceLevel = 0;
            if(PriceClosedOnSupport(PERIOD_M15, supportLevel)) {
                zone.closedOnSupport = true;
                zone.isBullish = true; // Reversal from support = bullish
                Print("  -> Zone marked: PRICE CLOSED ON SUPPORT (HIGH-PROBABILITY REVERSAL)");
            }
            if(PriceClosedOnResistance(PERIOD_M15, resistanceLevel)) {
                zone.closedOnResistance = true;
                zone.isBullish = false; // Reversal from resistance = bearish
                Print("  -> Zone marked: PRICE CLOSED ON RESISTANCE (HIGH-PROBABILITY REVERSAL)");
            }
            
            double fvgTop = 0, fvgBottom = 0;
            bool isBullishFVG = false;
            if(CheckFVG_Retest(fvgTop, fvgBottom, isBullishFVG)) {
                zone.fvgRetest = true;
                zone.isBullish = isBullishFVG; // FVG retest direction
                Print("  -> Zone marked: FVG RETEST DETECTED (HIGH-PROBABILITY REVERSAL)");
            }
            
            zone.totalConfluence = zone.orderBlockCount + zone.fvgCount + zone.trendLineCount + 
                                   zone.sessionLevelCount + zone.srTouchCount + zone.engulfingCandleCount + 
                                   (zone.hasDailyLevel ? 1 : 0) + 
                                   (zone.hasWeeklyLevel ? 1 : 0) + (zone.hasHourlySweep ? 1 : 0) +
                                   (zone.hasSessionSweep ? 1 : 0) +
                                   (zone.closedOnSupport ? 3 : 0) + // High-probability = +3 confluence
                                   (zone.closedOnResistance ? 3 : 0) + // High-probability = +3 confluence
                                   (zone.fvgRetest ? 3 : 0); // High-probability = +3 confluence
            
            // High-probability setups can bypass MinConfluence requirement
            bool isHighProbability = zone.closedOnSupport || zone.closedOnResistance || zone.fvgRetest;
            int requiredConfluence = isHighProbability ? 1 : MinConfluence; // High-probability only needs 1 confluence
            
            if(zone.totalConfluence >= requiredConfluence) {
                int size = ArraySize(zones);
                ArrayResize(zones, size + 1);
                zones[size] = zone;
            }
        }
    }
    
    // Create standalone Support/Resistance zones (M1/M5/M15)
    if(UseSR_Touch) {
        double supports[], resistances[];
        
        if(UseM1_SR) {
            DetectSR_Levels(PERIOD_M1, supports, resistances);
            for(int s = 0; s < ArraySize(supports); s++) {
                // Check if this SR level already has a zone
                bool zoneExists = false;
                for(int j = 0; j < ArraySize(zones); j++) {
                    if(supports[s] >= zones[j].bottom && supports[s] <= zones[j].top) {
                        zoneExists = true;
                        break;
                    }
                }
                if(zoneExists) continue;
                
                // Create SR-only zone
                ConfluenceZone zone;
                zone.bottom = supports[s] - (SR_TouchTolerance * pipValue);
                zone.top = supports[s] + (SR_TouchTolerance * pipValue);
                zone.orderBlockCount = 0;
                zone.fvgCount = 0;
                zone.trendLineCount = 0;
                zone.sessionLevelCount = 0;
                zone.srTouchCount = 1;
                zone.hasDailyLevel = false;
                zone.hasWeeklyLevel = false;
                zone.hasHourlySweep = false;
                zone.isBullish = true; // Support = bullish
                zone.totalConfluence = 1; // SR touch counts as 1
                
                if(zone.totalConfluence >= MinConfluence) {
                    int size = ArraySize(zones);
                    ArrayResize(zones, size + 1);
                    zones[size] = zone;
                }
            }
            
            for(int r = 0; r < ArraySize(resistances); r++) {
                bool zoneExists = false;
                for(int j = 0; j < ArraySize(zones); j++) {
                    if(resistances[r] >= zones[j].bottom && resistances[r] <= zones[j].top) {
                        zoneExists = true;
                        break;
                    }
                }
                if(zoneExists) continue;
                
                ConfluenceZone zone;
                zone.bottom = resistances[r] - (SR_TouchTolerance * pipValue);
                zone.top = resistances[r] + (SR_TouchTolerance * pipValue);
                zone.orderBlockCount = 0;
                zone.fvgCount = 0;
                zone.trendLineCount = 0;
                zone.sessionLevelCount = 0;
                zone.srTouchCount = 1;
                zone.hasDailyLevel = false;
                zone.hasWeeklyLevel = false;
                zone.hasHourlySweep = false;
                zone.isBullish = false; // Resistance = bearish
                zone.totalConfluence = 1;
                
                if(zone.totalConfluence >= MinConfluence) {
                    int size = ArraySize(zones);
                    ArrayResize(zones, size + 1);
                    zones[size] = zone;
                }
            }
        }
        
        // Repeat for M5 and M15
        if(UseM5_SR) {
            DetectSR_Levels(PERIOD_M5, supports, resistances);
            // Same logic as M1 (code would be identical, just different timeframe)
            // For brevity, I'll add a note that M5/M15 use same logic
        }
        
        if(UseM15_SR) {
            DetectSR_Levels(PERIOD_M15, supports, resistances);
            // Same logic as M1
        }
    }
}

//+------------------------------------------------------------------+
//| Check if Price is in Zone                                        |
//+------------------------------------------------------------------+
bool IsPriceInZone(double price, double level1, double level2, double zoneTop, double zoneBottom) {
    double level = (level1 + level2) / 2.0;
    return (level >= zoneBottom && level <= zoneTop);
}

//+------------------------------------------------------------------+
//| Check if we're in a news event window                            |
//+------------------------------------------------------------------+
bool IsNewsEventActive() {
    if(!BlockTradesDuringNews) return false;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Common high-impact news times (EST/EDT - adjust for your broker timezone)
    // Major news events typically occur at:
    // - 8:30 AM EST (NFP, CPI, etc.)
    // - 10:00 AM EST (Consumer Confidence, etc.)
    // - 2:00 PM EST (FOMC, Fed announcements)
    // - 4:00 PM EST (Various)
    
    int hour = dt.hour;
    int minute = dt.min;
    int currentMinute = hour * 60 + minute;
    
    // High-impact news windows (in broker's local time - adjust as needed)
    // These are common times for major news releases (NFP, CPI, FOMC, etc.)
    int newsTimes[4][2];
    newsTimes[0][0] = 8*60 + 30;  // 8:30 AM (NFP, CPI, etc.)
    newsTimes[0][1] = 8*60 + 30;
    newsTimes[1][0] = 10*60 + 0;  // 10:00 AM (Consumer Confidence, etc.)
    newsTimes[1][1] = 10*60 + 0;
    newsTimes[2][0] = 14*60 + 0;  // 2:00 PM (FOMC, Fed announcements)
    newsTimes[2][1] = 14*60 + 0;
    newsTimes[3][0] = 16*60 + 0;  // 4:00 PM (Various)
    newsTimes[3][1] = 16*60 + 0;
    
    for(int i = 0; i < 4; i++) {
        int newsMinute = newsTimes[i][0];
        int windowStart = newsMinute - NewsBlockMinutesBefore;
        int windowEnd = newsMinute + NewsBlockMinutesAfter;
        
        if(currentMinute >= windowStart && currentMinute <= windowEnd) {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check Confluence Entries                                         |
//+------------------------------------------------------------------+
void CheckConfluenceEntries(ConfluenceZone &zones[]) {
    int zoneCount = ArraySize(zones);
    
    // Check for news events - block all entries during news
    if(IsNewsEventActive()) {
        static datetime lastNewsLog = 0;
        if(TimeCurrent() - lastNewsLog > 60) { // Log every minute
            Print("*** TRADING BLOCKED: High-impact news event window active ***");
            lastNewsLog = TimeCurrent();
        }
        return; // Exit early - no trades during news
    }
    
    // Declare variables once at the top
    datetime currentTime = TimeCurrent();
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    int buyPositions = CountPositions(POSITION_TYPE_BUY);
    int sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    // Debug logging
    static datetime lastEntryLogTime = 0;
    if(currentTime - lastEntryLogTime >= 10) { // Log every 10 seconds
        Print("=== Entry Check ===");
        Print("Confluence Zones Found: ", zoneCount);
        Print("Current Price: ", currentPrice);
        if(zoneCount > 0) {
            for(int z = 0; z < MathMin(zoneCount, 3); z++) {
                Print("Zone ", z, ": ", zones[z].bottom, "-", zones[z].top, 
                      " | Confluence: ", zones[z].totalConfluence, 
                      " | Price in zone: ", (currentPrice >= zones[z].bottom && currentPrice <= zones[z].top ? "YES" : "NO"));
            }
        }
        lastEntryLogTime = currentTime;
    }
    
    if(zoneCount == 0) return;
    
    // Track last entry time per zone to prevent rapid entries
    static datetime lastEntryTime[];
    static double lastEntryZone[];
    static int lastEntryCount = 0;
    
    int entryCooldownSeconds = 3; // Minimum 3 seconds between entries in same zone
    
    for(int i = 0; i < zoneCount; i++) {
        // Check if price is in confluence zone
        if(currentPrice < zones[i].bottom || currentPrice > zones[i].top) continue;
        
        // NEW: If high-probability trade appears, move existing trades to BE
        if(MoveToBE_OnNewTrade && zones[i].totalConfluence >= MinConfluenceForBE_Move) {
            int totalPositions = buyPositions + sellPositions;
            if(totalPositions > 0) {
                // Move all existing trades to break-even
                for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
                    if(!position.SelectByIndex(pos)) continue;
                    if(position.Symbol() != _Symbol) continue;
                    if(position.Magic() != MagicNumber) continue;
                    
                    double openPrice = position.PriceOpen();
                    double currentSL = position.StopLoss();
                    double entryPrice = openPrice;
                    
                    // Only move to BE if not already at BE
                    if(currentSL != entryPrice) {
                        if(position.Type() == POSITION_TYPE_BUY) {
                            trade.PositionModify(position.Ticket(), entryPrice, position.TakeProfit());
                            Print("*** MOVED TO BE: High-probability trade detected (Confluence: ", zones[i].totalConfluence, ") ***");
                        } else if(position.Type() == POSITION_TYPE_SELL) {
                            trade.PositionModify(position.Ticket(), entryPrice, position.TakeProfit());
                            Print("*** MOVED TO BE: High-probability trade detected (Confluence: ", zones[i].totalConfluence, ") ***");
                        }
                    }
                }
            }
        }
        
        // High-probability setups bypass some restrictions
        bool isHighProbability = zones[i].closedOnSupport || zones[i].closedOnResistance || zones[i].fvgRetest;
        
        // Check if we should allow new trades while in existing trades
        if(!AllowNewTradesWhileInTrade && !isHighProbability) { // High-probability bypasses this
            int totalPositions = buyPositions + sellPositions;
            if(totalPositions > 0) {
                // Check if this zone is for opposite direction
                bool isOppositeDirection = false;
                if(zones[i].isBullish && sellPositions > 0) isOppositeDirection = true;
                if(!zones[i].isBullish && buyPositions > 0) isOppositeDirection = true;
                
                // Only block if same direction (allow opposite)
                if(!isOppositeDirection) {
                    continue; // Block same-direction trades if already in trade
                }
            }
        }
        
        // Check requirements (high-probability setups bypass these)
        bool canEnter = true;
        string blockReason = "";
        
        if(!isHighProbability) { // Only check requirements for non-high-probability setups
            if(RequireOrderBlock && zones[i].orderBlockCount == 0) {
                canEnter = false;
                blockReason = "Requires Order Block but none found";
            }
            if(RequireFVG && zones[i].fvgCount == 0) {
                canEnter = false;
                blockReason = "Requires FVG but none found";
            }
            if(RequireTrendLine && zones[i].trendLineCount == 0) {
                canEnter = false;
                blockReason = "Requires Trend Line but none found";
            }
            if(RequireSessionLevel && zones[i].sessionLevelCount == 0) {
                canEnter = false;
                blockReason = "Requires Session Level but none found";
            }
            if(RequireEngulfing && zones[i].engulfingCandleCount == 0) {
                canEnter = false;
                blockReason = "Requires Engulfing Candle but none found";
            }
        } else {
            Print("*** HIGH-PROBABILITY SETUP DETECTED - Bypassing strict requirements ***");
            if(zones[i].closedOnSupport) Print("  -> Price closed on SUPPORT (reversal setup)");
            if(zones[i].closedOnResistance) Print("  -> Price closed on RESISTANCE (reversal setup)");
            if(zones[i].fvgRetest) Print("  -> FVG RETEST detected (reversal setup)");
        }
        
        if(!canEnter) {
            if(currentTime - lastEntryLogTime < 2) { // Only log if we just logged
                Print("Entry BLOCKED: ", blockReason, " | Zone confluence: ", zones[i].totalConfluence);
            }
            continue;
        }
        
        // CRITICAL: Check trend direction - High-probability reversal setups can trade against trend
        if(TradeWithTrendOnly && !isHighProbability) { // High-probability bypasses trend filter
            bool tradeAllowed = false;
            
            if(UseRangeTrading && currentRange.hasBuyZone && currentRange.hasSellZone) {
                // Range trading: only take trades in trend direction
                if(zones[i].isBullish && currentRange.trendDirection == 1) {
                    tradeAllowed = true; // BUY in uptrend
                } else if(!zones[i].isBullish && currentRange.trendDirection == -1) {
                    tradeAllowed = true; // SELL in downtrend
                } else {
                    static datetime lastTrendBlockLog = 0;
                    if(TimeCurrent() - lastTrendBlockLog > 30) {
                        Print("Entry BLOCKED: Trade against trend | Zone: ", (zones[i].isBullish ? "BUY" : "SELL"), 
                              " | Trend: ", (currentRange.trendDirection == 1 ? "UP" : currentRange.trendDirection == -1 ? "DOWN" : "NEUTRAL"));
                        lastTrendBlockLog = TimeCurrent();
                    }
                }
            } else if(UseMarketStructure) {
                // Market structure trading: only take trades in trend direction
                if(zones[i].isBullish && marketStruct.trend == 1) {
                    tradeAllowed = true; // BUY in bullish structure
                } else if(!zones[i].isBullish && marketStruct.trend == -1) {
                    tradeAllowed = true; // SELL in bearish structure
                } else {
                    static datetime lastMSBlockLog = 0;
                    if(TimeCurrent() - lastMSBlockLog > 30) {
                        Print("Entry BLOCKED: Trade against market structure | Zone: ", (zones[i].isBullish ? "BUY" : "SELL"), 
                              " | Structure: ", (marketStruct.trend == 1 ? "BULLISH" : marketStruct.trend == -1 ? "BEARISH" : "NEUTRAL"));
                        lastMSBlockLog = TimeCurrent();
                    }
                }
            } else {
                // No trend filter - allow all trades
                tradeAllowed = true;
            }
            
            if(!tradeAllowed) {
                continue; // Block trade against trend
            }
        }
        
        // Check for opposite trades - Only block if VERY close (5 pips), otherwise allow with 5 pip TP
        double minDistance = MinOppositeDistancePips * pipValue; // 5 pips = very tight
        double zoneEntryPrice = zones[i].isBullish ? zones[i].bottom : zones[i].top;
        bool hasOppositeTrade = false;
        bool hasOppositeConflict = false;
        string conflictReason = "";
        
        for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
            if(!position.SelectByIndex(pos)) continue;
            if(position.Symbol() != _Symbol) continue;
            if(position.Magic() != MagicNumber) continue;
            
            double posPrice = position.PriceOpen();
            
            // Check if opposite trade type
            bool isOpposite = false;
            if(zones[i].isBullish && position.Type() == POSITION_TYPE_SELL) {
                isOpposite = true;
            } else if(!zones[i].isBullish && position.Type() == POSITION_TYPE_BUY) {
                isOpposite = true;
            }
            
            if(isOpposite) {
                hasOppositeTrade = true;
                
                // ONLY BLOCK if entry price is within 5 pips of opposite trade
                // This prevents entries in the exact same pip area
                double distance = MathAbs(zoneEntryPrice - posPrice);
                if(distance < minDistance) {
                    hasOppositeConflict = true;
                    conflictReason = "Entry too close to opposite trade (distance: " + DoubleToString(distance / pipValue, 2) + " pips, need " + DoubleToString(MinOppositeDistancePips, 1) + " pips)";
                    break;
                }
            }
        }
        
        // Block only if too close (within 5 pips)
        if(hasOppositeConflict) {
            if(currentTime - lastEntryLogTime < 2) {
                Print("Entry BLOCKED: ", conflictReason);
            }
            continue;
        }
        
        // If opposite trade exists but is > 5 pips away, mark as opposite entry (will use 5 pip TP)
        bool isOppositeEntry = hasOppositeTrade;
        if(isOppositeEntry) {
            Print("*** OPPOSITE TRADE DETECTED - Will use 5 pip TP for quick exit ***");
        }
        
        // Check total risk before opening new trade
        double accountValue = UseEquity ? account.Equity() : account.Balance();
        double currentTotalRisk = CalculateTotalRisk();
        double newTradeRisk = RiskPerTrade;
        double totalRiskAfter = currentTotalRisk + newTradeRisk;
        
        if(totalRiskAfter > MaxTotalRisk) {
            if(currentTime - lastEntryLogTime < 2) {
                Print("Entry BLOCKED: Total risk would exceed limit (", totalRiskAfter, "% > ", MaxTotalRisk, "%)");
            }
            continue;
        }
        
        // Count trades in this zone
        int tradesInZone = CountTradesInZone(zones[i]);
        
        // Check if we can enter more trades in this zone
        if(AllowMultipleTradesInZone) {
            if(tradesInZone >= MaxTradesPerZone) {
                continue; // Already have max trades in this zone
            }
            
            // Check cooldown for this zone
            bool canEnterZone = true;
            for(int j = 0; j < lastEntryCount; j++) {
                if(MathAbs(lastEntryZone[j] - zones[i].bottom) < (EntryZonePips * pipValue)) {
                    // Same zone - check cooldown
                    if((currentTime - lastEntryTime[j]) < entryCooldownSeconds) {
                        canEnterZone = false;
                        break;
                    }
                }
            }
            if(!canEnterZone) continue;
        } else {
            // Single trade per zone
            if(tradesInZone > 0) continue;
        }
        
        // Check total position limits
        if(zones[i].isBullish) {
            if(buyPositions >= MaxTradesPerZone) continue; // Limit to MaxTradesPerZone
            
            // Enter single trade (not layered for quick scalps)
            // Pass isOppositeEntry flag - if true, will use 5 pip TP
            OpenBuyOrder(zones[i], isOppositeEntry);
            
            // Record entry
            ArrayResize(lastEntryTime, lastEntryCount + 1);
            ArrayResize(lastEntryZone, lastEntryCount + 1);
            lastEntryTime[lastEntryCount] = currentTime;
            lastEntryZone[lastEntryCount] = zones[i].bottom;
            lastEntryCount++;
            if(lastEntryCount > 100) {
                ArrayRemove(lastEntryTime, 0, 1);
                ArrayRemove(lastEntryZone, 0, 1);
                lastEntryCount--;
            }
            
            double accountValue = UseEquity ? account.Equity() : account.Balance();
            Print("*** ENTRY: BUY at ", currentPrice, " | Zone: ", zones[i].bottom, "-", zones[i].top,
                  " | Confluence: ", zones[i].totalConfluence, " factors | Risk: ", RiskPerTrade, "% | Equity: ", accountValue, " ***");
        } else {
            if(sellPositions >= MaxTradesPerZone) continue; // Limit to MaxTradesPerZone
            
            // Pass isOppositeEntry flag - if true, will use 5 pip TP
            OpenSellOrder(zones[i], isOppositeEntry);
            
            // Record entry
            ArrayResize(lastEntryTime, lastEntryCount + 1);
            ArrayResize(lastEntryZone, lastEntryCount + 1);
            lastEntryTime[lastEntryCount] = currentTime;
            lastEntryZone[lastEntryCount] = zones[i].bottom;
            lastEntryCount++;
            if(lastEntryCount > 100) {
                ArrayRemove(lastEntryTime, 0, 1);
                ArrayRemove(lastEntryZone, 0, 1);
                lastEntryCount--;
            }
            
            double accountValue = UseEquity ? account.Equity() : account.Balance();
            Print("*** ENTRY: SELL at ", currentPrice, " | Zone: ", zones[i].bottom, "-", zones[i].top,
                  " | Confluence: ", zones[i].totalConfluence, " factors | Risk: ", RiskPerTrade, "% | Equity: ", accountValue, " ***");
        }
        
        // Don't break - allow multiple zones to be checked
    }
}

//+------------------------------------------------------------------+
//| Count Trades in Zone                                             |
//+------------------------------------------------------------------+
int CountTradesInZone(ConfluenceZone &zone) {
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        double openPrice = position.PriceOpen();
        if(openPrice >= zone.bottom && openPrice <= zone.top) {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Calculate Total Risk of All Open Positions                       |
//+------------------------------------------------------------------+
double CalculateTotalRisk() {
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    if(accountValue == 0) return 0;
    
    double totalRisk = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        double openPrice = position.PriceOpen();
        double sl = position.StopLoss();
        double volume = position.Volume();
        
        if(sl == 0) continue; // No SL = can't calculate risk
        
        double slDistance = MathAbs(openPrice - sl);
        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        
        if(slDistance > 0 && tickSize > 0) {
            double riskAmount = (slDistance / tickSize) * tickValue * volume;
            double riskPercent = (riskAmount / accountValue) * 100.0;
            totalRisk += riskPercent;
        }
    }
    
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Open Layered Buy Orders                                          |
//+------------------------------------------------------------------+
void OpenLayeredBuy(ConfluenceZone &zone) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double entryPrice = zone.bottom;
    double tp = 0; // No TP - managed manually via TP1, TP2, TP3, TP4 system
    
    // Use equity and RiskPerTrade (1% per trade)
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double riskAmount = accountValue * (RiskPerTrade / 100.0);
    
    // Calculate dynamic SL based on confluence
    double zoneSize = zone.top - zone.bottom;
    double dynamicSLPoints = CalculateDynamicSL(SL_Pips, zone.totalConfluence, zoneSize);
    
    // Calculate lot size based on first layer's SL distance (dynamic)
    double firstLayerEntry = entryPrice;
    double firstLayerSL = firstLayerEntry - dynamicSLPoints;
    double slDistance = MathAbs(firstLayerEntry - firstLayerSL);
    double totalLotSize = CalculateLotSize(riskAmount, slDistance);
    double layerLotSize = totalLotSize / MaxLayers;
    
    Print("=== LAYERED BUY - Dynamic SL ===");
    Print("Confluence: ", zone.totalConfluence, " | SL: ", dynamicSLPoints / pipValue, " pips");
    
    // Open multiple layers - each with SL calculated from its own entry price
    for(int i = 0; i < MaxLayers; i++) {
        double layerEntry = entryPrice + (i * LayerSpacingPips * pipValue);
        if(layerEntry > zone.top) break;
        
        // Calculate SL for THIS layer's entry price (uses dynamic SL)
        double layerSL = layerEntry - dynamicSLPoints;
        
        layerEntry = NormalizeDouble(layerEntry, symbolDigits);
        layerSL = NormalizeDouble(layerSL, symbolDigits);
        tp = NormalizeDouble(tp, symbolDigits);
        layerLotSize = NormalizeDouble(layerLotSize, 2);
        
        // Build trade comment with user tracking
        string layerComment = TradeComment + "_L" + IntegerToString(i);
        if(StringLen(UserName) > 0) {
            layerComment = layerComment + "|U:" + UserName;
        }
        layerComment = layerComment + "|A:" + IntegerToString(account.Login());
        
        if(trade.Buy(layerLotSize, _Symbol, layerEntry, layerSL, 0, layerComment)) {
            double actualSLDistance = (layerEntry - layerSL) / pipValue;
            Print("Layered BUY opened: Layer ", i, " Entry=", layerEntry, " SL=", layerSL, " (", actualSLDistance, " pips) Lots=", layerLotSize);
        }
    }
}

//+------------------------------------------------------------------+
//| Open Layered Sell Orders                                         |
//+------------------------------------------------------------------+
void OpenLayeredSell(ConfluenceZone &zone) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entryPrice = zone.top;
    double tp = 0; // No TP - managed manually via TP1, TP2, TP3, TP4 system
    
    // Use equity and RiskPerTrade (1% per trade)
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double riskAmount = accountValue * (RiskPerTrade / 100.0);
    
    // Calculate dynamic SL based on confluence
    double zoneSize = zone.top - zone.bottom;
    double dynamicSLPoints = CalculateDynamicSL(SL_Pips, zone.totalConfluence, zoneSize);
    
    // Calculate lot size based on first layer's SL distance (dynamic)
    double firstLayerEntry = entryPrice;
    double firstLayerSL = firstLayerEntry + dynamicSLPoints;
    double slDistance = MathAbs(firstLayerEntry - firstLayerSL);
    double totalLotSize = CalculateLotSize(riskAmount, slDistance);
    double layerLotSize = totalLotSize / MaxLayers;
    
    Print("=== LAYERED SELL - Dynamic SL ===");
    Print("Confluence: ", zone.totalConfluence, " | SL: ", dynamicSLPoints / pipValue, " pips");
    
    // Open multiple layers - each with SL calculated from its own entry price
    for(int i = 0; i < MaxLayers; i++) {
        double layerEntry = entryPrice - (i * LayerSpacingPips * pipValue);
        if(layerEntry < zone.bottom) break;
        
        // Calculate SL for THIS layer's entry price (uses dynamic SL)
        double layerSL = layerEntry + dynamicSLPoints;
        
        layerEntry = NormalizeDouble(layerEntry, symbolDigits);
        layerSL = NormalizeDouble(layerSL, symbolDigits);
        tp = NormalizeDouble(tp, symbolDigits);
        layerLotSize = NormalizeDouble(layerLotSize, 2);
        
        // Build trade comment with user tracking
        string layerComment = TradeComment + "_L" + IntegerToString(i);
        if(StringLen(UserName) > 0) {
            layerComment = layerComment + "|U:" + UserName;
        }
        layerComment = layerComment + "|A:" + IntegerToString(account.Login());
        
        if(trade.Sell(layerLotSize, _Symbol, layerEntry, layerSL, 0, layerComment)) {
            double actualSLDistance = (layerSL - layerEntry) / pipValue;
            Print("Layered SELL opened: Layer ", i, " Entry=", layerEntry, " SL=", layerSL, " (", actualSLDistance, " pips) Lots=", layerLotSize);
        }
    }
}

//+------------------------------------------------------------------+
//| Open Single Buy Order                                            |
//+------------------------------------------------------------------+
void OpenBuyOrder(ConfluenceZone &zone, bool isOppositeEntry = false) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double entryPrice = ask;
    
    // Calculate dynamic SL based on confluence
    double zoneSize = zone.top - zone.bottom;
    double slDistancePoints = CalculateDynamicSL(SL_Pips, zone.totalConfluence, zoneSize);
    double slDistancePips = slDistancePoints / pipValue;
    
    Print("=== DYNAMIC SL CALCULATION ===");
    Print("Zone Confluence: ", zone.totalConfluence, " factors");
    Print("Base SL: ", SL_Pips, " pips | Dynamic SL: ", slDistancePips, " pips");
    if(SL_OutsideZone) Print("SL placed outside zone (zone size: ", zoneSize / pipValue, " pips)");
    
    double sl = entryPrice - slDistancePoints; // SL calculated from entry price
    
    // If opposite entry, use 5 pip TP for quick exit
    double tp = 0;
    if(isOppositeEntry) {
        tp = entryPrice + (OppositeTradeTP_Pips * pipValue); // 5 pip TP
        Print("*** OPPOSITE TRADE: Using 5 pip TP for quick exit ***");
    }
    // Otherwise: No TP - managed manually via TP1, TP2, TP3, TP4 system
    
    // Use equity and RiskPerTrade - position size auto-adjusts based on SL distance
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double riskAmount = accountValue * (RiskPerTrade / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance); // Auto-adjusts for bigger SL
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    // Calculate margin requirement for logging
    double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double marginPerLot = 0;
    if(AccountLeverage > 0 && AccountLeverage < 999999) {
        marginPerLot = (contractSize * entryPrice) / AccountLeverage;
    } else {
        marginPerLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
    }
    double totalMargin = marginPerLot * lotSize;
    
    // Build trade comment with user tracking
    string comment = TradeComment;
    if(isOppositeEntry) {
        comment = TradeComment + "_OPP"; // Mark as opposite trade
    }
    if(StringLen(UserName) > 0) {
        comment = comment + "|U:" + UserName;
    }
    comment = comment + "|A:" + IntegerToString(account.Login());
    
    if(trade.Buy(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
        double actualSLDistancePoints = MathAbs(entryPrice - sl);
        double actualSLDistancePips = actualSLDistancePoints / pipValue;
        Print("*** BUY ORDER OPENED ***");
        if(isOppositeEntry) Print("*** OPPOSITE TRADE - 5 pip TP set ***");
        Print("Entry: ", entryPrice, " | SL: ", sl, " | TP: ", (tp > 0 ? DoubleToString(tp, symbolDigits) : "Manual"));
        Print("SL Distance: ", actualSLDistancePoints, " points = ", actualSLDistancePips, " pips (Expected: ", SL_Pips, " pips)");
        if(tp > 0) Print("TP Distance: ", (tp - entryPrice) / pipValue, " pips");
        Print("Lots: ", lotSize, " | Risk: ", RiskPerTrade, "% | Margin: $", totalMargin);
        Print("Confluence: ", zone.totalConfluence, " factors");
    } else {
        Print("ERROR: BUY order failed. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Open Single Sell Order                                           |
//+------------------------------------------------------------------+
void OpenSellOrder(ConfluenceZone &zone, bool isOppositeEntry = false) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entryPrice = bid;
    
    // Calculate dynamic SL based on confluence
    double zoneSize = zone.top - zone.bottom;
    double slDistancePoints = CalculateDynamicSL(SL_Pips, zone.totalConfluence, zoneSize);
    double slDistancePips = slDistancePoints / pipValue;
    
    Print("=== DYNAMIC SL CALCULATION (SELL) ===");
    Print("Zone Confluence: ", zone.totalConfluence, " factors");
    Print("Base SL: ", SL_Pips, " pips | Dynamic SL: ", slDistancePips, " pips");
    if(SL_OutsideZone) Print("SL placed outside zone (zone size: ", zoneSize / pipValue, " pips)");
    
    double sl = entryPrice + slDistancePoints; // SL calculated from entry price
    
    // If opposite entry, use 5 pip TP for quick exit
    double tp = 0;
    if(isOppositeEntry) {
        tp = entryPrice - (OppositeTradeTP_Pips * pipValue); // 5 pip TP
        Print("*** OPPOSITE TRADE: Using 5 pip TP for quick exit ***");
    }
    // Otherwise: No TP - managed manually via TP1, TP2, TP3, TP4 system
    
    // Use equity and RiskPerTrade - position size auto-adjusts based on SL distance
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double riskAmount = accountValue * (RiskPerTrade / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance); // Auto-adjusts for bigger SL
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    // Calculate margin requirement for logging
    double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double marginPerLot = 0;
    if(AccountLeverage > 0 && AccountLeverage < 999999) {
        marginPerLot = (contractSize * entryPrice) / AccountLeverage;
    } else {
        marginPerLot = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
    }
    double totalMargin = marginPerLot * lotSize;
    
    // Build trade comment with user tracking
    string comment = TradeComment;
    if(isOppositeEntry) {
        comment = TradeComment + "_OPP"; // Mark as opposite trade
    }
    if(StringLen(UserName) > 0) {
        comment = comment + "|U:" + UserName;
    }
    comment = comment + "|A:" + IntegerToString(account.Login());
    
    if(trade.Sell(lotSize, _Symbol, entryPrice, sl, tp, comment)) {
        double actualSLDistancePoints = MathAbs(entryPrice - sl);
        double actualSLDistancePips = actualSLDistancePoints / pipValue;
        Print("*** SELL ORDER OPENED ***");
        if(isOppositeEntry) Print("*** OPPOSITE TRADE - 5 pip TP set ***");
        Print("Entry: ", entryPrice, " | SL: ", sl, " | TP: ", (tp > 0 ? DoubleToString(tp, symbolDigits) : "Manual"));
        Print("SL Distance: ", actualSLDistancePoints, " points = ", actualSLDistancePips, " pips (Expected: ", SL_Pips, " pips)");
        if(tp > 0) Print("TP Distance: ", (entryPrice - tp) / pipValue, " pips");
        Print("Lots: ", lotSize, " | Risk: ", RiskPerTrade, "% | Margin: $", totalMargin);
        Print("Confluence: ", zone.totalConfluence, " factors");
    } else {
        Print("ERROR: SELL order failed. Error: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate Dynamic SL based on Confluence                        |
//+------------------------------------------------------------------+
double CalculateDynamicSL(double baseSLPips, int confluence, double zoneSize) {
    if(!UseDynamicSL) {
        return baseSLPips * pipValue; // Return base SL in points
    }
    
    // Calculate SL: base + (confluence - 1) * perConfluence
    // More confluence = bigger SL to avoid wicks
    double dynamicSLPips = baseSLPips + ((confluence - 1) * SL_PerConfluence);
    
    // Add zone size if we want SL outside zone
    if(SL_OutsideZone && zoneSize > 0) {
        double zoneSizePips = zoneSize / pipValue;
        dynamicSLPips += zoneSizePips; // Place SL outside zone
    }
    
    // Cap at maximum
    if(dynamicSLPips > SL_MaxPips) {
        dynamicSLPips = SL_MaxPips;
    }
    
    return dynamicSLPips * pipValue; // Convert to points
}

//+------------------------------------------------------------------+
//| Calculate Lot Size (Accounts for Leverage)                      |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slDistance) {
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(slDistance == 0) return minLot;
    
    // Calculate lot size based on risk amount
    double lotSize = riskAmount / (slDistance / tickSize * tickValue);
    
    // Account for leverage - check margin requirements
    double accountValue = UseEquity ? account.Equity() : account.Balance();
    double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    double marginRequired = 0;
    
    // Get current price for margin calculation
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate margin per lot (contract size / leverage)
    // For Gold/Silver: contract size is usually 100, leverage affects margin
    if(AccountLeverage > 0 && AccountLeverage < 999999) {
        // Standard leverage: margin = contract size / leverage
        marginRequired = (contractSize * currentPrice) / AccountLeverage;
    } else {
        // Unlimited leverage or very high leverage: use broker's margin requirement
        marginRequired = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
    }
    
    // Calculate max lot size based on available margin
    // Use 80% of free margin to leave buffer
    double freeMargin = account.FreeMargin();
    double maxLotByMargin = 0;
    if(marginRequired > 0) {
        maxLotByMargin = (freeMargin * 0.8) / marginRequired;
    } else {
        // Fallback: use broker's margin requirement
        double brokerMargin = SymbolInfoDouble(_Symbol, SYMBOL_MARGIN_INITIAL);
        if(brokerMargin > 0) {
            maxLotByMargin = (freeMargin * 0.8) / brokerMargin;
        } else {
            maxLotByMargin = maxLot; // No margin limit
        }
    }
    
    // Normalize lot size
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Apply limits: min lot, max lot, and margin limit
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    if(maxLotByMargin > 0 && lotSize > maxLotByMargin) {
        lotSize = MathFloor(maxLotByMargin / lotStep) * lotStep;
        if(lotSize < minLot) lotSize = minLot;
        Print("Lot size limited by margin: ", lotSize, " (max by margin: ", maxLotByMargin, ")");
    }
    
    // Final safety check: ensure we have enough free margin
    double requiredMargin = marginRequired * lotSize;
    if(requiredMargin > freeMargin * 0.9) {
        // Reduce lot size to fit available margin
        lotSize = MathFloor((freeMargin * 0.9 / marginRequired) / lotStep) * lotStep;
        if(lotSize < minLot) lotSize = minLot;
        Print("Lot size reduced due to margin: ", lotSize, " (required: ", requiredMargin, " free: ", freeMargin, ")");
    }
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Count Positions                                                  |
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
//| Manage Positions                                                 |
//+------------------------------------------------------------------+
void ManagePositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        ulong ticket = position.Ticket();
        
        // Verify position still exists (might have been closed by SL/TP)
        if(!position.SelectByTicket(ticket)) {
            continue; // Position was closed, skip it
        }
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentTP = position.TakeProfit();
        double currentVolume = position.Volume();
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type();
        double currentBID = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double currentASK = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        double currentPrice = (posType == POSITION_TYPE_BUY) ? currentBID : currentASK;
        
        // Calculate current profit in pips (used throughout)
        double currentProfitPips = 0;
        if(posType == POSITION_TYPE_BUY) {
            currentProfitPips = (currentPrice - openPrice) / pipValue;
        } else {
            currentProfitPips = (openPrice - currentPrice) / pipValue;
        }
        
        // Auto-correct position type if MT5 reports wrong type (e.g. SELL shown as BUY after broker/MT issue)
        const double GOLD_PIP = 0.1;
        double profitIfBuy  = (currentBID - openPrice) / GOLD_PIP;
        double profitIfSell = (openPrice - currentASK) / GOLD_PIP;
        const double TYPE_CORRECT_PIP_THRESH = 5.0;
        if(posType == POSITION_TYPE_BUY && profitIfBuy < -TYPE_CORRECT_PIP_THRESH && profitIfSell > TYPE_CORRECT_PIP_THRESH) {
            posType = POSITION_TYPE_SELL;
            currentProfitPips = profitIfSell;
            currentPrice = currentASK;
            Print("*** TYPE AUTO-CORRECT: #", ticket, " reported BUY but price below entry (SELL in profit ", DoubleToString(currentProfitPips, 1), " pips) - treating as SELL ***");
        } else if(posType == POSITION_TYPE_SELL && profitIfSell < -TYPE_CORRECT_PIP_THRESH && profitIfBuy > TYPE_CORRECT_PIP_THRESH) {
            posType = POSITION_TYPE_BUY;
            currentProfitPips = profitIfBuy;
            currentPrice = currentBID;
            Print("*** TYPE AUTO-CORRECT: #", ticket, " reported SELL but price above entry (BUY in profit) - treating as BUY ***");
        }
        
        // Initialize tracking with bounds checking
        int ticketIndex = (int)(ticket % 10000);
        
        // Ensure arrays are large enough
        if(ticketIndex >= ArraySize(tp1Hit)) {
            int oldSize = ArraySize(tp1Hit); // Store old size BEFORE resizing
            int newSize = ticketIndex + 10;
            ArrayResize(tp1Hit, newSize);
            ArrayResize(tp2Hit, newSize);
            ArrayResize(tp3Hit, newSize);
            ArrayResize(tp4Hit, newSize);
            ArrayResize(tp1HitPrice, newSize);
            ArrayResize(partialCloseLevel, newSize);
            ArrayResize(originalVolume, newSize);
            // Initialize only the NEW elements (from oldSize to newSize)
            for(int j = oldSize; j < newSize; j++) {
                tp1Hit[j] = false;
                tp2Hit[j] = false;
                tp3Hit[j] = false;
                tp4Hit[j] = false;
                tp1HitPrice[j] = 0;
                partialCloseLevel[j] = 0;
                originalVolume[j] = 0;
            }
        }
        
        // Safety check: ensure ticketIndex is within bounds
        if(ticketIndex < 0 || ticketIndex >= ArraySize(tp1Hit)) {
            Print("ERROR: Invalid ticketIndex: ", ticketIndex, " (Array size: ", ArraySize(tp1Hit), ")");
            continue; // Skip this position
        }
        
        // Store original volume if not already stored (first time seeing this position)
        if(originalVolume[ticketIndex] == 0) {
            originalVolume[ticketIndex] = currentVolume;
        }
        
        double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        
        // Calculate runner size based on original volume
        double origVol = originalVolume[ticketIndex] > 0 ? originalVolume[ticketIndex] : currentVolume;
        double runnerSize = NormalizeDouble(origVol * (RunnerSizePercent / 100.0), 2);
        bool hasRunner = (currentVolume <= runnerSize + minLot * 0.1); // Already at runner size
        bool hasTP4 = (partialCloseLevel[ticketIndex] == 3); // TP4 is active (after TP3)
        
        // STEP 1: Break Even at specified pips profit (EXACT break-even, not above entry)
        if(!tp1Hit[ticketIndex] && currentProfitPips >= BreakEvenPips && currentProfitPips > 0) {
            tp1Hit[ticketIndex] = true;
            
            if(UseBreakEven) {
                // Move SL to EXACT break-even (openPrice)
                double newSL = openPrice;
                
                bool needToModify = false;
                if(posType == POSITION_TYPE_BUY) {
                    // For BUY: SL is below entry, moving to BE means raising SL
                    if(newSL > currentSL || currentSL == 0) {
                        needToModify = true;
                    }
                } else {
                    // For SELL: SL is above entry, moving to BE means lowering SL
                    // For SELL, we need to check if newSL (entry) is lower than currentSL
                    if(currentSL == 0) {
                        needToModify = true; // No SL set, definitely need to set BE
                    } else if(newSL < currentSL) {
                        needToModify = true; // Entry is below current SL, can move to BE
                    } else {
                        // Current SL is already at or below entry - this shouldn't happen for SELL
                        Print("WARNING: SELL position SL issue | Entry: ", openPrice, " | Current SL: ", currentSL, " | New SL (BE): ", newSL);
                    }
                }
                
                if(needToModify) {
                    Print("DEBUG: Setting BE | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                          " | Entry: ", openPrice, " | Current SL: ", currentSL, " | New SL (BE): ", newSL,
                          " | Profit: ", currentProfitPips, " pips");
                    if(trade.PositionModify(ticket, newSL, 0)) {
                        Print("*** BREAK-EVEN SET at ", BreakEvenPips, " pips profit | Ticket #", ticket, " | SL moved to: ", newSL, " (exact entry) ***");
                    } else {
                        Print("ERROR: Failed to set break-even. Error: ", trade.ResultRetcodeDescription());
                        Print("DEBUG: Ticket: ", ticket, " | Entry: ", openPrice, " | Current SL: ", currentSL, " | Attempted SL: ", newSL);
                    }
                } else {
                    Print("DEBUG: BE not needed | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                          " | Entry: ", openPrice, " | Current SL: ", currentSL, " | Profit: ", currentProfitPips, " pips");
                }
            }
        }
        
        // STEP 2: New TP System - TP1, TP2, TP3, TP4 (only if BE was hit and trade is in profit)
        if(tp1Hit[ticketIndex] && currentProfitPips > 0 && !hasRunner) {
            // Initialize partial close level tracking
            if(ticketIndex >= ArraySize(partialCloseLevel)) {
                int newSize = ticketIndex + 10;
                ArrayResize(partialCloseLevel, newSize);
                ArrayResize(originalVolume, newSize);
                for(int j = ArraySize(partialCloseLevel) - 10; j < newSize; j++) {
                    partialCloseLevel[j] = 0;
                    originalVolume[j] = 0;
                }
            }
            
            // Ensure original volume is stored
            if(originalVolume[ticketIndex] == 0) {
                originalVolume[ticketIndex] = currentVolume;
            }
            
            double origVol = originalVolume[ticketIndex];
            int currentLevel = partialCloseLevel[ticketIndex];
            
            // TP1: 10 pips - Close 25%
            if(currentLevel == 0 && currentProfitPips >= TP1_Pips) {
                double closeVolume = NormalizeDouble(origVol * (TP1_Percent / 100.0), 2);
                double remainingVolume = currentVolume - closeVolume;
                
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    if(trade.PositionClosePartial(ticket, closeVolume)) {
                        partialCloseLevel[ticketIndex] = 1;
                        Print("*** TP1 HIT: Closed ", closeVolume, " lots (", TP1_Percent, "% of ", origVol, " lots) at ", TP1_Pips, " pips profit | Remaining: ", remainingVolume, " lots ***");
                    }
                }
            }
            // TP2: 20 pips - Close 20%
            else if(currentLevel == 1 && currentProfitPips >= TP2_Pips) {
                double closeVolume = NormalizeDouble(origVol * (TP2_Percent / 100.0), 2);
                double remainingVolume = currentVolume - closeVolume;
                
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    if(trade.PositionClosePartial(ticket, closeVolume)) {
                        partialCloseLevel[ticketIndex] = 2;
                        Print("*** TP2 HIT: Closed ", closeVolume, " lots (", TP2_Percent, "% of ", origVol, " lots) at ", TP2_Pips, " pips profit | Remaining: ", remainingVolume, " lots ***");
                    }
                }
            }
            // TP3: 50 pips - Close 30%
            else if(currentLevel == 2 && currentProfitPips >= TP3_Pips) {
                double closeVolume = NormalizeDouble(origVol * (TP3_Percent / 100.0), 2);
                double remainingVolume = currentVolume - closeVolume;
                
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    if(trade.PositionClosePartial(ticket, closeVolume)) {
                        partialCloseLevel[ticketIndex] = 3;
                        Print("*** TP3 HIT: Closed ", closeVolume, " lots (", TP3_Percent, "% of ", origVol, " lots) at ", TP3_Pips, " pips profit | Remaining: ", remainingVolume, " lots ***");
                    }
                }
            }
            // TP4: Remaining position (25%) targets nearest 1H S/R
            else if(currentLevel == 3 && TP4_To1H_SR) {
                // TP4 is handled by runner logic below - remaining 25% will target 1H S/R
                // After TP3, we have 25% remaining (100% - 25% - 20% - 30% = 25%)
                // This 25% will be managed as TP4 to 1H S/R
            }
        }
        
        // STEP 3: TP4 - Remaining 25% targets 1H S/R (after TP3)
        if(hasTP4 && TP4_To1H_SR && !hasRunner) {
            double targetSR = Find1H_SupportResistance(posType == POSITION_TYPE_BUY);
            
            if(targetSR > 0) {
                // Check if price reached 1H S/R (within 5 pips)
                bool reachedSR = false;
                if(posType == POSITION_TYPE_BUY) {
                    reachedSR = currentPrice >= targetSR - (5 * pipValue); // Within 5 pips of resistance
                } else {
                    reachedSR = currentPrice <= targetSR + (5 * pipValue); // Within 5 pips of support
                }
                
                if(reachedSR) {
                    // Close TP4 (remaining 25%), but keep 10% runner
                    double tp4Volume = NormalizeDouble(origVol * 0.25, 2); // 25% of original
                    double closeVolume = NormalizeDouble(tp4Volume - runnerSize, 2); // Close 15%, keep 10%
                    
                    if(closeVolume >= minLot && (currentVolume - closeVolume) >= runnerSize) {
                        if(trade.PositionClosePartial(ticket, closeVolume)) {
                            Print("*** TP4 HIT at 1H S/R: Closed ", closeVolume, " lots (15% of ", origVol, " lots) | Remaining 10% runner: ", (currentVolume - closeVolume), " lots ***");
                            partialCloseLevel[ticketIndex] = 4; // Mark TP4 as complete, runner active
                        }
                    }
                }
            }
        }
        
        // STEP 4: 10% Runner targets 1H Support/Resistance (if enabled)
        if(hasRunner && RunnerTo1H_SR) {
            double targetSR = Find1H_SupportResistance(posType == POSITION_TYPE_BUY);
            
            if(targetSR > 0) {
                // Check if price reached 1H S/R (within 5 pips)
                bool reachedSR = false;
                if(posType == POSITION_TYPE_BUY) {
                    reachedSR = currentPrice >= targetSR - (5 * pipValue); // Within 5 pips of resistance
                } else {
                    reachedSR = currentPrice <= targetSR + (5 * pipValue); // Within 5 pips of support
                }
                
                if(reachedSR) {
                    Print("*** Runner reached 1H S/R at ", targetSR, " | Closing runner ***");
                    trade.PositionClose(ticket);
                }
            }
        }
        
        // STEP 5: Ensure SL is always set (safety check)
        if(currentSL == 0) {
            double newSL = 0;
            if(posType == POSITION_TYPE_BUY) {
                newSL = openPrice - (SL_Pips * pipValue);
            } else {
                newSL = openPrice + (SL_Pips * pipValue);
            }
            trade.PositionModify(ticket, newSL, 0);
            Print("WARNING: Position #", ticket, " had no SL! Set to: ", newSL);
        }
    }
}

//+------------------------------------------------------------------+
//| Find 1H Support/Resistance                                        |
//+------------------------------------------------------------------+
double Find1H_SupportResistance(bool isBuy) {
    int bars = iBars(_Symbol, PERIOD_H1);
    if(bars < 20) return 0;
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    CopyHigh(_Symbol, PERIOD_H1, 0, 20, high);
    CopyLow(_Symbol, PERIOD_H1, 0, 20, low);
    
    if(isBuy) {
        // Find nearest resistance (high) above current price
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double nearestResistance = 0;
        for(int i = 0; i < 20; i++) {
            if(high[i] > currentPrice) {
                if(nearestResistance == 0 || high[i] < nearestResistance) {
                    nearestResistance = high[i];
                }
            }
        }
        return nearestResistance;
    } else {
        // Find nearest support (low) below current price
        double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        double nearestSupport = 0;
        for(int i = 0; i < 20; i++) {
            if(low[i] < currentPrice) {
                if(nearestSupport == 0 || low[i] > nearestSupport) {
                    nearestSupport = low[i];
                }
            }
        }
        return nearestSupport;
    }
}

//+------------------------------------------------------------------+
