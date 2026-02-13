//+------------------------------------------------------------------+
//|                         GoldmineBlueprint_Silver.mq5               |
//|          Goldmine Blueprint – Silver (XAGUSD only)                 |
//|          Order Blocks, FVG, Trend Lines | BE/TP fixed 0.01 pip   |
//+------------------------------------------------------------------+
#property copyright "Goldmine Blueprint"
#property link      ""
#property version   "1.00"
#property description "Goldmine Blueprint – Silver. Attach to XAGUSD only. BE/TP 1 pip = 0.01."
#property description "Order Blocks, FVG, Market Structure - XAGUSD"

#define SMC_SYMBOL_SILVER

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
input double RiskPercent = 3.0;              // Risk per trade (%) - DEFAULT (used for scaling entries)
input double FirstTradeRisk = 5.0;           // Risk for FIRST trade (%) - Higher risk on initial entry
input double ScalingEntryRisk = 1.5;         // Risk for scaling entries (%) - Lower risk when adding to losing positions
input double MaxTotalRisk = 9.0;             // Maximum total risk for all trades (%) - Safety limit
#ifndef SMC_SYMBOL_SILVER
input double SL_Pips = 30.0;                 // Stop Loss (pips) - Base SL for Gold (normal entry; dynamic can expand)
#endif
input double SL_Pips_Silver = 35.0;          // Stop Loss (pips) - Base SL (dynamic can expand)
input bool UseDynamicSL = true;              // Enable dynamic SL (adapts to market structure)
input bool UseBreakEven = true;              // Enable break-even
input bool UseDynamicBE = true;              // BE at position's SL distance (dynamic); if false use fixed pips below
#ifndef SMC_SYMBOL_SILVER
input double BreakEvenPips = 30.0;           // Move to BE at this many pips (Gold) - min when UseDynamicBE, or fixed when off
#endif
input double BreakEvenPips_Silver = 30.0;     // Move to BE at this many pips (Silver) - min when UseDynamicBE; Nexus-aligned
input double BreakEvenCushionPips = 3.0;      // (Unused for SELL - SELL BE uses trigger level entry-bePips, e.g. 4860 when BE=30)

input group "=== Dynamic SL Settings ==="
#ifndef SMC_SYMBOL_SILVER
input bool DynamicSL_GoldOnly = false;       // Apply dynamic SL only to Gold (XAUUSD) - FALSE = Use for both
#endif
#ifndef SMC_SYMBOL_SILVER
input double DynamicSL_MinPips = 30.0;       // Minimum dynamic SL (pips) - Gold (never tighter than base)
#endif
input double DynamicSL_MinPips_Silver = 25.0; // Minimum dynamic SL (pips) - Silver: never smaller; Nexus-aligned
#ifndef SMC_SYMBOL_SILVER
input double DynamicSL_MaxPips = 80.0;       // Maximum dynamic SL (pips) - Gold (allows structure/spikes)
#endif
input double DynamicSL_MaxPips_Silver = 90.0; // Maximum dynamic SL (pips) - allows structure/spikes
input double DynamicSL_ZoneBuffer = 3.0;     // Buffer beyond zone (pips) - REDUCED from 5.0
input double DynamicSL_ATR_Multiplier = 1.0; // ATR multiplier for volatility-based SL - REDUCED from 1.5
input int DynamicSL_ATR_Period = 14;         // ATR period for dynamic SL
input bool DynamicSL_UseStructure = true;   // Place SL beyond swing high/low (structure-based)
input int DynamicSL_SwingLookback = 10;      // Bars to look back for swing high/low
input double DynamicSL_ConfluenceBonus = 5.0; // Additional pips per confluence factor - REDUCED from 10.0
input bool DynamicSL_SmartExpansion = true;  // Only expand SL when there's strong confluence (2+ factors)
#ifdef SMC_SYMBOL_SILVER
input double DynamicSL_BaseMultiplier = 1.0;  // Base SL multiplier (1.0 = use base SL pips; structure/spikes expand from there)
#else
input double DynamicSL_BaseMultiplier = 1.0;  // Base SL multiplier (1.0 = use base 30/35 pips; structure/spikes expand from there)
#endif
input bool UseWickProtection = true;          // Enable wick-based SL buffer (places SL beyond recent wicks)
input int WickProtection_Lookback = 5;        // Bars to check for wick extremes (5 = last 5 bars)
input double WickProtection_Buffer = 2.0;     // Buffer beyond wick (pips) - adds safety margin
input bool UseVolatilitySpikeExpansion = true; // Expand SL during recent volatility spikes
input int VolatilitySpike_Bars = 3;          // Bars to check for volatility spike (3 = last 3 bars)
input double VolatilitySpike_Multiplier = 1.5; // SL multiplier during volatility spike (1.5 = 50% wider)
input bool UseQuickRejectionCheck = false;    // Optional: 1-bar delay if large wick detected (false = immediate entry)
input double QuickRejection_WickSize = 3.0;   // Minimum wick size (pips) to trigger 1-bar delay

input group "=== Take Profit System ==="
#ifdef SMC_SYMBOL_SILVER
// TP/BE levels use 1 pip = 0.01 in price (applied internally).
#else
// All TP/BE levels below are used as-is (Gold 0.1/pip, Silver 0.01/pip applied internally)
#endif
input double TP1_Pips = 25.0;                // TP1 (pips) - Close 15%
input double TP1_Percent = 15.0;             // % to close at TP1
input double TP2_Pips = 50.0;                // TP2 (pips) - Close 15%
input double TP2_Percent = 15.0;             // % to close at TP2
input double TP3_Pips = 80.0;                // TP3 (pips) - Close 25%
input double TP3_Percent = 25.0;             // % to close at TP3
input double TP4_Pips = 150.0;               // TP4 (pips) - Close 25%, leave runner
input double TP4_Percent = 25.0;             // % to close at TP4 (at 150 pips)
input bool TP4_To1H_SR = true;               // TP4 alternate: remaining can also target 1H S/R
input double TP5_Pips = 300.0;               // TP5 (pips) - Close runner at this many pips (full close)
input double RunnerSizePercent = 15.0;       // % to keep as runner - DEFAULT: 15%
input bool RunnerTo1H_SR = true;             // Runner targets 1H support/resistance
input double MinPipsBeforeFullClose = 0;     // Min pips before ANY full-close (0 = use TP3/TP5 only; e.g. 80 = safety floor)
input bool UseTrailSL = true;                // Trail SL when profit reaches TrailStartPips
input double TrailStartPips = 100.0;         // Start trailing SL when profit >= this (pips)
input double TrailDistancePips = 20.0;       // Trail SL this many pips behind price
input bool UseDynamicTrail = false;           // Close on structure reversal – set true only if you want early exit on BOS/CHoCH
input double DynamicTrailMinPips = 80.0;    // Only close on reversal if profit >= this (avoids closing too early)
#ifndef SMC_SYMBOL_SILVER
enum ENUM_SYMBOL_FILTER { SYMBOL_BOTH = 0, SYMBOL_GOLD_ONLY = 1, SYMBOL_SILVER_ONLY = 2 };
input ENUM_SYMBOL_FILTER SymbolFilter = SYMBOL_BOTH; // Gold only / Silver only = one pair per chart (best for BE). Set Gold only on XAU chart, Silver only on XAG chart.
#endif

input group "=== Order Block Detection ==="
input int OB_Lookback = 20;                  // Bars to look back for OB (for volume/ATR calculation)
input int OB_HistoricalScan = 500;          // Bars to scan for historical order blocks (0 = current bar only, 500 = ~3-4 days on M15)
input double OB_VolumeMultiplier = 1.2;     // Volume multiplier for OB (lowered for more sensitivity)
input int OB_ATR_Period = 14;                // ATR period for OB
input double OB_ATR_Multiplier = 0.3;        // ATR multiplier for OB size (lowered for more sensitivity)

input group "=== FVG Detection ==="
input bool UseFVG = true;                    // Enable FVG trading
input double FVG_MinSize = 5.0;              // Minimum FVG size (pips)
input int FVG_Lookback = 50;                 // Bars to look back for FVG
input bool FVG_RequirePullback = true;        // TRUE = only BUY in lower half (fewer trades). FALSE = entry on any touch (more trades).

input group "=== Market Structure ==="
input bool UseMarketStructure = true;        // Enable BOS/CHoCH
input int MS_SwingLength = 5;                // Swing length for structure
input bool RequireBOS = false;               // Require BOS before entry

input group "=== Entry Settings ==="
input bool MultipleEntries = true;           // Allow multiple entries
input int MaxEntries = 4;                    // Maximum entries per direction
input bool AllowLayeredEntries = true;       // Allow multiple entries in SAME zone (layered entries)
input double MinEntryDistancePips = 5.0;     // Minimum distance (pips) between entries in same zone
input double EntryZonePips = 20.0;          // Entry zone size (pips)
input double EntryTouchTolerance = 5.0;     // Tolerance for zone touch (pips) - allows entries near zones
input bool WaitForConfirmation = false;      // Wait for candle close
input double MinOppositeDistancePips = 10.0; // Minimum distance from opposite trades (pips) - Set to 0 to disable - PREVENTS CONFLICTS
input bool AllowReentryAfterBE = true;       // Allow re-entry when position closed at BE (only if confluence still there)
input int ReentryMaxBarsAfterBE = 10;        // Max bars to look for re-entry after BE (then expires)

input group "=== Scaling Entries (Add to Losing Trades) ==="
input bool AllowScalingEntries = true;      // Allow scaling into losing positions with confluence
input double ScalingDrawdownPips = 10.0;     // Minimum drawdown (pips) before allowing scaling entry
input double BigSL_Threshold = 30.0;        // SL size (pips) to consider "big" for scaling
input int MaxScalingEntries = 2;            // Maximum scaling entries per position (in addition to MaxEntries)
input bool RequireConfluenceForScaling = true; // Require new confluence for scaling entry
input bool OnlyScaleOnDrawdown = true;       // Only allow scaling when trade is in drawdown (losing)

input group "=== High-Probability Reversal Setups ==="
input bool TradeCloseOnSupport = true;         // Trade when price CLOSES on support (M15) - HIGH PROBABILITY
input bool TradeCloseOnResistance = true;     // Trade when price CLOSES on resistance (M15) - HIGH PROBABILITY
input bool TradeFVG_Retest = true;            // Trade FVG retests (50% of FVG hit = reversal signal)
input double FVG_RetestPercent = 50.0;        // FVG retest percentage (50% = middle of FVG)
input double SR_TouchTolerance = 5.0;         // Tolerance for S/R touch detection (pips)

input group "=== Trend Line ==="
input bool UseTrendLines = true;              // Enable Trend Line (confluence + optional standalone)
input int TrendLine_Lookback = 100;           // Bars to look back for trend lines (Higher TF)
input int TrendLine_MinTouches = 2;           // Min swing touches for valid trend line
input double TrendLine_TouchTolerancePips = 5.0;  // Tolerance for price on trendline (pips)
input bool TradeTrendLineStandalone = true;   // Allow standalone TL entry (no OB/FVG) at reduced risk
input double TrendLine_StandaloneRiskPercent = 1.5; // Risk % for standalone trendline entries (smaller than normal)

input group "=== Breakout (catch big moves) ==="
input bool UseBreakoutEntries = true;         // Enter when price BREAKS last N-bar high/low
input double Breakout_SL_Pips = 30.0;         // SL (pips) beyond broken level (Silver)
input int Breakout_LookbackBars = 20;        // N bars for range high/low (break level)

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES PrimaryTF = PERIOD_M15; // Primary timeframe
input ENUM_TIMEFRAMES HigherTF = PERIOD_H1;   // Higher timeframe for structure
input bool UseMultiTimeframe = true;          // Multi-timeframe analysis
input bool UseM1_OB = true;                   // Detect order blocks on M1
input bool UseM3_OB = true;                   // Detect order blocks on M3
input bool UseM5_OB = true;                   // Detect order blocks on M5
input bool UseM15_OB = true;                  // Detect order blocks on M15
input bool UseM30_OB = true;                  // Detect order blocks on M30

input group "=== Order Block TP ==="
input bool UseOB_TP = true;                  // Use order block as TP
input double OB_TP_Distance = 300.0;         // Distance to OB TP (pips)
input int OB_TP_Lookback = 200;              // Lookback for OB TP

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
input int MagicNumber = 124002;              // Magic number (Blueprint Silver - unique per EA)
input string TradeComment = "Goldmine Blueprint – Silver";  // Trade comment
input int Slippage = 10;                     // Slippage in points
input group "=== Pip/Points (set for YOUR broker) ==="
#ifndef SMC_SYMBOL_SILVER
input int PointsPerPip_Gold = 100;           // Gold: 1 pip = how many points? (100 = 2-decimal, 1000 = 3-decimal)
#endif
input int PointsPerPip_Silver = 10;          // Points per pip (usually 10 for XAGUSD)

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
    ENUM_TIMEFRAMES tf; // Timeframe this OB was detected on
};

struct FVG {
    double top;
    double bottom;
    datetime time;
    bool isBullish;
    bool isActive;
    int barIndex;
};

struct TrendLine {
    double price1;   // Price at bar1
    double price2;   // Price at bar2
    int bar1;        // Older bar index (series)
    int bar2;        // Newer bar index (series)
    bool isSupport;  // true = support (from swing lows), false = resistance (from swing highs)
    bool isActive;
};

struct MarketStructure {
    double lastBOS;
    double lastCHoCH;
    int trend; // 1 = bullish, -1 = bearish
    datetime lastBOS_Time;
    datetime lastCHoCH_Time;
};

OrderBlock orderBlocks[];
FVG fvgs[];
TrendLine trendLines[];
MarketStructure marketStruct;

double point;
int symbolDigits;  // Renamed to avoid conflict with MQL5 library
double pipValue;
double accountBalance;
datetime lastBarTime = 0;
datetime lastBarTime_M1 = 0;
datetime lastBarTime_M3 = 0;
datetime lastBarTime_M5 = 0;
datetime lastBarTime_M15 = 0;
datetime lastBarTime_M30 = 0;
datetime lastBuyEntryTime = 0;
datetime lastSellEntryTime = 0;
int entryCooldownSeconds = 5; // Prevent opposite entries within 5 seconds
datetime initTime = 0; // EA initialization time - used for startup cooldown

// Position tracking for TP management
bool tp1Hit[];
bool tp2Hit[];
bool tp3Hit[];
bool tp4Hit[];
bool tp5Hit[];
double tp1HitPrice[];
int partialCloseLevel[]; // Track which partial close level we're at
double originalVolume[]; // Track original position size for accurate partial closes

// Track tickets to avoid collisions (ticket % 10000 was unsafe and can collide)
ulong trackedTickets[];

// Re-entry after BE: track position we moved to BE; when it closes at BE, allow one re-entry if confluence still there
ulong   beTrackedTicket = 0;
double  beTrackedEntry = 0;
int     beTrackedType = -1;       // 0=BUY, 1=SELL
bool    reentryAllowedBuy = false;
bool    reentryAllowedSell = false;
datetime reentryAllowedTime = 0;

// Returns a stable index for a position ticket, creating a new slot if needed.
int GetTicketIndex(ulong ticket) {
    int n = ArraySize(trackedTickets);
    for(int i = 0; i < n; i++) {
        if(trackedTickets[i] == ticket) return i;
    }

    // New ticket -> append
    int newIndex = n;
    ArrayResize(trackedTickets, newIndex + 1);
    trackedTickets[newIndex] = ticket;

    // Ensure all tracking arrays have matching size
    ArrayResize(tp1Hit, newIndex + 1);
    ArrayResize(tp2Hit, newIndex + 1);
    ArrayResize(tp3Hit, newIndex + 1);
    ArrayResize(tp4Hit, newIndex + 1);
    ArrayResize(tp5Hit, newIndex + 1);
    ArrayResize(tp1HitPrice, newIndex + 1);
    ArrayResize(partialCloseLevel, newIndex + 1);
    ArrayResize(originalVolume, newIndex + 1);

    // Initialize this slot
    tp1Hit[newIndex] = false;
    tp2Hit[newIndex] = false;
    tp3Hit[newIndex] = false;
    tp4Hit[newIndex] = false;
    tp5Hit[newIndex] = false;
    tp1HitPrice[newIndex] = 0;
    partialCloseLevel[newIndex] = 0;
    originalVolume[newIndex] = 0;

    return newIndex;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Validate License with Remote Server                              |
//+------------------------------------------------------------------+
// Remote license validation (optionally for a specific EA name).
bool ValidateLicenseRemote(string eaNameOverride = "") {
    if(StringLen(LicenseServerURL) == 0) {
        Print("ERROR: License Server URL not set!");
        return false;
    }
    
    long accountNumber = account.Login();
    string accountServer = account.Server();
    // Default to the new EA name, but allow override (for backward compatibility).
    string eaName = (StringLen(eaNameOverride) > 0 ? eaNameOverride : "Goldmine Blueprint - Silver");
    
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
    ArrayResize(post, ArraySize(data));
    ArrayCopy(post, data);
    
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
    
    // Ensure server parses the body as JSON reliably
    headers = "Content-Type: application/json\r\n";
    int timeout = LicenseCheckTimeout * 1000; // Convert to milliseconds
    int res = WebRequest("POST", url, NULL, NULL, timeout, post, 0, result, headers);
    
    if(res == -1) {
        int error = GetLastError();
        Print("ERROR: Failed to connect to license server. Error: ", error);
        if(error == 4060) {
            Print("ERROR: URL not allowed. Add '", url, "' to Tools -> Options -> Expert Advisors -> 'Allow WebRequest for listed URL'");
        }
        return false; // Server unreachable - fail secure
    }
    
    if(res != 200) {
        Print("ERROR: License server returned status: ", res);
        return false;
    }
    
    // Parse JSON response
    string response = CharArrayToString(result);
    Print("Server Response: ", response);
    
    // Simple JSON parsing (MQL5 doesn't have built-in JSON parser)
    if(StringFind(response, "\"valid\":true") >= 0) {
        Print("=== REMOTE LICENSE VALIDATION: SUCCESS ===");
        
        // Extract user name if present
        int userNamePos = StringFind(response, "\"userName\":\"");
        if(userNamePos >= 0) {
            int start = userNamePos + 12;
            int end = StringFind(response, "\"", start);
            if(end > start) {
                string serverUserName = StringSubstr(response, start, end - start);
                if(StringLen(serverUserName) > 0 && StringLen(UserName) == 0) {
                    Print("User Name from server: ", serverUserName);
                }
            }
        }
        
        // Extract expiry date if present
        int expiryPos = StringFind(response, "\"expiryDate\":\"");
        if(expiryPos >= 0) {
            int start = expiryPos + 14;
            int end = StringFind(response, "\"", start);
            if(end > start) {
                string expiryStr = StringSubstr(response, start, end - start);
                Print("License Expiry (from server): ", expiryStr);
            }
        }
        
        // Extract days remaining
        int daysPos = StringFind(response, "\"daysRemaining\":");
        if(daysPos >= 0) {
            int start = daysPos + 16;
            int end = StringFind(response, ",", start);
            if(end < 0) end = StringFind(response, "}", start);
            if(end > start) {
                string daysStr = StringSubstr(response, start, end - start);
                int days = (int)StringToInteger(daysStr);
                if(days > 0) {
                    Print("Days Remaining: ", days);
                }
            }
        }
        
        return true;
    } else {
        // Extract error message
        int errorPos = StringFind(response, "\"message\":\"");
        if(errorPos >= 0) {
            int start = errorPos + 11;
            int end = StringFind(response, "\"", start);
            if(end > start) {
                string errorMsg = StringSubstr(response, start, end - start);
                Print("ERROR: ", errorMsg);
                Alert("LICENSE ERROR: ", errorMsg);
            }
        }
        
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
        return true; // Allow if disabled
    }
    
    long accountNumber = account.Login();
    string accountServer = account.Server();
    datetime currentTime = TimeCurrent();
    
    Print("=== LICENSE CHECK ===");
    Print("Account Number: ", accountNumber);
    Print("Broker/Server: ", accountServer);
    Print("Current Time: ", TimeToString(currentTime, TIME_DATE|TIME_MINUTES));
    
    // REMOTE VALIDATION (MOST SECURE)
    if(UseRemoteValidation) {
        Print("Using REMOTE license server validation...");

        // Try new EA name first (retry on startup to avoid false alert after recompile/reload)
        int maxTries = 3;
        for(int tryCount = 1; tryCount <= maxTries; tryCount++) {
            if(ValidateLicenseRemote("Goldmine Blueprint - Silver")) {
                Print("=== LICENSE: VALID (Remote) ===");
                return true;
            }
            if(tryCount < maxTries) {
                Print("Remote check failed, retry ", tryCount, "/", maxTries, " in 2 sec...");
                Sleep(2000);
            }
        }
        Print("=== LICENSE: INVALID (Remote) after ", maxTries, " attempts ===");
        Print("Falling back to local validation...");
        // Fall through to local validation as backup
    }
    
    // LOCAL VALIDATION (Fallback)
    Print("Using LOCAL license validation (fallback)...");
    
    // Check 1: License Key (if provided)
    if(StringLen(LicenseKey) > 0) {
        // Simple key validation (you can make this more complex)
        string expectedKey = "GOLDMINE_" + IntegerToString(accountNumber) + "_2024";
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
    
    // Validate symbol - supports both Gold (XAUUSD) and Silver (XAGUSD)
    bool isValidSymbol = (_Symbol == "XAUUSD" || _Symbol == "GOLD" || 
                          _Symbol == "XAGUSD" || _Symbol == "SILVER" ||
                          _Symbol == "XAGUSD." || _Symbol == "XAUUSD.");
    
    if(!isValidSymbol) {
        Print("ERROR: This EA is designed for XAUUSD (Gold) and XAGUSD (Silver) only!");
        Print("Current symbol: ", _Symbol);
        return(INIT_FAILED);
    }
    
#ifndef SMC_SYMBOL_SILVER
    bool chartIsGold = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
    bool chartIsSilver = (StringFind(_Symbol, "XAG") >= 0 || StringFind(_Symbol, "SILVER") >= 0);
    if(SymbolFilter == SYMBOL_GOLD_ONLY && !chartIsGold) {
        Print("ERROR: SymbolFilter = Gold only. Attach this EA to XAUUSD (Gold) chart only!");
        return(INIT_FAILED);
    }
    if(SymbolFilter == SYMBOL_SILVER_ONLY && !chartIsSilver) {
        Print("ERROR: SymbolFilter = Silver only. Attach this EA to XAGUSD (Silver) chart only!");
        return(INIT_FAILED);
    }
#endif

    // Initialize trade settings
    trade.SetExpertMagicNumber(MagicNumber);
    trade.SetDeviationInPoints(Slippage);
    trade.SetTypeFilling(ORDER_FILLING_FOK);
    trade.SetAsyncMode(false);
    
    // Get symbol properties
    point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    symbolDigits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    
    // Pip value from broker-specific points-per-pip (user inputs)
    string symbolUpper = _Symbol;
    StringToUpper(symbolUpper);
    bool isGold = (StringFind(symbolUpper, "XAU") >= 0 || StringFind(symbolUpper, "GOLD") >= 0);
    bool isSilver = (StringFind(symbolUpper, "XAG") >= 0 || StringFind(symbolUpper, "SILVER") >= 0);
    
    int ptsPerPip = 100;
#ifdef SMC_SYMBOL_SILVER
    ptsPerPip = PointsPerPip_Silver;
    pipValue = (point >= 0.1) ? 0.1 : 0.01;
    Print("SILVER: 1 pip = ", pipValue, " price | 25 pips = ", (25.0 * pipValue), " | 50 pips = ", (50.0 * pipValue), (point >= 0.1 ? " (broker point=0.1)" : ""));
#else
    if(isGold) {
        ptsPerPip = PointsPerPip_Gold;
        pipValue = 0.1;
        Print("GOLD: 1 pip = ", pipValue, " in price | 30 pips = ", (30.0 * pipValue), " | 80 pips = ", (80.0 * pipValue));
    } else if(isSilver) {
        ptsPerPip = PointsPerPip_Silver;
        pipValue = (point >= 0.1) ? 0.1 : 0.01;
        Print("SILVER: 1 pip = ", pipValue, " price | 25 pips = ", (25.0 * pipValue), " | 50 pips = ", (50.0 * pipValue), (point >= 0.1 ? " (broker point=0.1)" : ""));
    } else {
        ptsPerPip = PointsPerPip_Gold;
        pipValue = (point >= 0.1) ? 0.1 : (point >= 0.01 ? 0.1 : 0.01);
        Print("WARNING: Unknown symbol, assuming GOLD. Symbol: ", _Symbol, " | 1 pip = ", pipValue, " in price");
    }
#endif
    
    Print("Point: ", point, " | Pip Value: ", pipValue, " | Digits: ", symbolDigits);
    Print("=== ORDER BLOCK DETECTION ===");
    Print("OB Lookback: ", OB_Lookback, " bars (for volume/ATR calculation)");
    Print("Historical Scan: ", OB_HistoricalScan, " bars (", (OB_HistoricalScan > 0 ? "ENABLED - will scan previous days" : "DISABLED - current bar only"), ")");
    Print("Volume Multiplier: ", OB_VolumeMultiplier, "x | ATR Multiplier: ", OB_ATR_Multiplier, "x");
    Print("=== NEWS FILTER ===");
    Print("Block trades during news: ", (BlockTradesDuringNews ? "YES" : "NO"));
    if(BlockTradesDuringNews) {
        Print("  - Block window: ", NewsBlockMinutesBefore, " min before + ", NewsBlockMinutesAfter, " min after news");
        Print("  - News times: 8:30 AM, 10:00 AM, 2:00 PM, 4:00 PM (broker time)");
    }
    
    // Initialize arrays
    ArrayResize(orderBlocks, 0);
    ArrayResize(fvgs, 0);
    ArrayResize(trendLines, 0);
    
    marketStruct.trend = 0;
    marketStruct.lastBOS = 0;
    marketStruct.lastCHoCH = 0;
    
    string symbolName = (_Symbol == "XAUUSD" || _Symbol == "GOLD" || _Symbol == "XAUUSD.") ? "Gold (XAUUSD)" : "Silver (XAGUSD)";
#ifdef SMC_SYMBOL_SILVER
    double bePipsForSymbol = BreakEvenPips_Silver;
    Print("Goldmine Blueprint - Silver EA initialized for ", symbolName, " (", _Symbol, ")");
#else
    bool isSilverSymbol = (StringFind(symbolUpper, "XAG") >= 0 || StringFind(symbolUpper, "SILVER") >= 0);
    double bePipsForSymbol = isSilverSymbol ? BreakEvenPips_Silver : BreakEvenPips;
    Print("Goldmine Blueprint - Silver EA initialized for ", symbolName, " (", _Symbol, ")");
#endif
    Print("Risk per trade: ", RiskPercent, "%");
#ifdef SMC_SYMBOL_SILVER
    Print("Break-Even: ", bePipsForSymbol, " pips (Silver)");
#else
    Print("Break-Even: ", bePipsForSymbol, " pips (", (isSilverSymbol ? "Silver" : "Gold"), ")");
#endif
    Print("Primary TF: ", EnumToString(PrimaryTF));
    
    // Set initialization time for startup cooldown (20 seconds)
    initTime = TimeCurrent();
    Print("Startup cooldown: 5 seconds - trades will be blocked until ", TimeToString(initTime + 5, TIME_DATE|TIME_SECONDS));
    
#ifdef SMC_SYMBOL_GOLD
    if(StringFind(symbolUpper, "XAU") < 0 && StringFind(symbolUpper, "GOLD") < 0) {
        Print("ERROR: Goldmine Blueprint – Gold must be attached to XAUUSD (Gold) chart only. Wrong chart: ", _Symbol);
        return(INIT_FAILED);
    }
    Print("Goldmine Blueprint – Gold: BE/TP use 1 pip = 0.1 (hardcoded).");
#endif
#ifdef SMC_SYMBOL_SILVER
    if(StringFind(symbolUpper, "XAG") < 0 && StringFind(symbolUpper, "SILVER") < 0) {
        Print("ERROR: Goldmine Blueprint – Silver must be attached to XAGUSD (Silver) chart only. Wrong chart: ", _Symbol);
        return(INIT_FAILED);
    }
    Print("Goldmine Blueprint – Silver: BE/TP use 1 pip = 0.01 (hardcoded).");
#endif
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("Goldmine Blueprint – Silver EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
    // HEARTBEAT: So you always see something in Experts tab (every 60 sec)
    static datetime lastHeartbeat = 0;
    if(TimeCurrent() - lastHeartbeat >= 60) {
        int buys = CountPositions(POSITION_TYPE_BUY);
        int sells = CountPositions(POSITION_TYPE_SELL);
        Print(">>> Blueprint Silver: RUNNING | BUY=", buys, " SELL=", sells, " | Entry check on new bar only <<<");
        lastHeartbeat = TimeCurrent();
    }
    
    // Periodic license check (every hour)
    static datetime lastLicenseCheck = 0;
    if(TimeCurrent() - lastLicenseCheck >= 3600) { // Check every hour
        if(!CheckLicense()) {
            Print("LICENSE CHECK FAILED - Stopping EA!");
            Alert("LICENSE ERROR: EA will stop trading. Contact developer.");
            ExpertRemove(); // Stop the EA
            return;
        }
        lastLicenseCheck = TimeCurrent();
    }
    
    // ALWAYS manage positions on every tick (critical for TP/SL management)
    ManagePositions();
    
    // Re-entry after BE: check if tracked position closed at BE; expire reentry flag after N bars
    CheckBEClosedAndAllowReentry();
    int barSeconds = (int)PeriodSeconds(PrimaryTF);
    if(reentryAllowedBuy && (TimeCurrent() - reentryAllowedTime) > ReentryMaxBarsAfterBE * barSeconds)
        reentryAllowedBuy = false;
    if(reentryAllowedSell && (TimeCurrent() - reentryAllowedTime) > ReentryMaxBarsAfterBE * barSeconds)
        reentryAllowedSell = false;
    
    // Check for new bar (for detection only)
    datetime currentBarTime = iTime(_Symbol, PrimaryTF, 0);
    if(currentBarTime == lastBarTime) {
        return; // Same bar, skip detection (but positions already managed above)
    }
    lastBarTime = currentBarTime;
    
    // Update account balance (use current balance for accurate risk calculation)
    accountBalance = account.Balance();
    
    // Update market structure
    if(UseMarketStructure) {
        UpdateMarketStructure();
    }
    
    // Detect order blocks on all enabled timeframes
    datetime t;
    
    if(UseM1_OB) {
        t = iTime(_Symbol, PERIOD_M1, 0);
        if(t != lastBarTime_M1) {
            lastBarTime_M1 = t;
            DetectOrderBlocksOnTF(PERIOD_M1);
        }
    }
    
    if(UseM3_OB) {
        t = iTime(_Symbol, PERIOD_M3, 0);
        if(t != lastBarTime_M3) {
            lastBarTime_M3 = t;
            DetectOrderBlocksOnTF(PERIOD_M3);
        }
    }
    
    if(UseM5_OB) {
        t = iTime(_Symbol, PERIOD_M5, 0);
        if(t != lastBarTime_M5) {
            lastBarTime_M5 = t;
            DetectOrderBlocksOnTF(PERIOD_M5);
        }
    }
    
    if(UseM15_OB) {
        t = iTime(_Symbol, PERIOD_M15, 0);
        if(t != lastBarTime_M15) {
            lastBarTime_M15 = t;
            DetectOrderBlocksOnTF(PERIOD_M15);
        }
    }
    
    if(UseM30_OB) {
        t = iTime(_Symbol, PERIOD_M30, 0);
        if(t != lastBarTime_M30) {
            lastBarTime_M30 = t;
            DetectOrderBlocksOnTF(PERIOD_M30);
        }
    }
    
    // Also detect on PrimaryTF (for backward compatibility)
    DetectOrderBlocks();
    
    // Detect FVG
    if(UseFVG) {
        DetectFVG();
    }
    
    // Detect trend lines (for confluence + standalone entries)
    if(UseTrendLines) {
        DetectTrendLines();
    }
    
    // Check for entry signals
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Check if Order Block Already Exists                              |
//+------------------------------------------------------------------+
bool OrderBlockExists(datetime obTime, double obTop, double obBottom) {
    int size = ArraySize(orderBlocks);
    double tolerance = 0.0001; // Small tolerance for price comparison
    
    for(int i = 0; i < size; i++) {
        // Check if same time and similar price zone
        if(MathAbs(orderBlocks[i].time - obTime) < 60 && // Within 1 minute
           MathAbs(orderBlocks[i].top - obTop) < tolerance &&
           MathAbs(orderBlocks[i].bottom - obBottom) < tolerance) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Detect Order Blocks                                              |
//+------------------------------------------------------------------+
void DetectOrderBlocks() {
    static bool historicalScanDone = false;
    int bars = iBars(_Symbol, PrimaryTF);
    if(bars < OB_Lookback + 5) return;
    
    // Determine how many bars to scan
    int scanBars = 1; // Default: only scan current bar
    if(!historicalScanDone && OB_HistoricalScan > 0) {
        // First time: do full historical scan
        scanBars = OB_HistoricalScan;
        if(scanBars > bars - 5) scanBars = bars - 5;
        historicalScanDone = true;
        Print("*** Performing initial historical order block scan: ", scanBars, " bars ***");
    }
    
    // Get ATR for all bars we'll scan
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(iATR(_Symbol, PrimaryTF, OB_ATR_Period), 0, 0, scanBars + OB_Lookback + 5, atr);
    
    // Get volume for all bars
    long volume[];
    ArraySetAsSeries(volume, true);
    CopyTickVolume(_Symbol, PrimaryTF, 0, scanBars + OB_Lookback + 5, volume);
    
    // Calculate average volume (using recent bars for comparison)
    double avgVolume = 0.0;
    for(int i = 1; i <= OB_Lookback; i++) {
        avgVolume += (double)volume[i];
    }
    avgVolume /= (double)OB_Lookback;
    
    // Get price data for all bars to scan
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, PrimaryTF, 0, scanBars + OB_Lookback + 5, high);
    CopyLow(_Symbol, PrimaryTF, 0, scanBars + OB_Lookback + 5, low);
    CopyClose(_Symbol, PrimaryTF, 0, scanBars + OB_Lookback + 5, close);
    CopyOpen(_Symbol, PrimaryTF, 0, scanBars + OB_Lookback + 5, open);
    
    // Scan through historical bars (from recent to old)
    int newOBsFound = 0;
    for(int bar = 0; bar < scanBars; bar++) {
        // Skip if we don't have enough bars for comparison
        if(bar + 1 >= ArraySize(low)) continue;
        
        // Check for bullish order block
        if(close[bar] > open[bar] && 
           volume[bar] > avgVolume * OB_VolumeMultiplier &&
           (close[bar] - open[bar]) > atr[bar] * OB_ATR_Multiplier &&
           low[bar] < low[bar + 1]) {
            
            datetime obTime = iTime(_Symbol, PrimaryTF, bar);
            
            // Check if this order block already exists
            if(!OrderBlockExists(obTime, high[bar], low[bar])) {
                OrderBlock ob;
                ob.top = high[bar];
                ob.bottom = low[bar];
                ob.time = obTime;
                ob.isBullish = true;
                ob.isActive = true;
                ob.barIndex = bars - 1 - bar;
                ob.tf = PrimaryTF;
                
                AddOrderBlock(ob);
                newOBsFound++;
            }
        }
        
        // Check for bearish order block
        if(close[bar] < open[bar] && 
           volume[bar] > avgVolume * OB_VolumeMultiplier &&
           (open[bar] - close[bar]) > atr[bar] * OB_ATR_Multiplier &&
           high[bar] > high[bar + 1]) {
            
            datetime obTime = iTime(_Symbol, PrimaryTF, bar);
            
            // Check if this order block already exists
            if(!OrderBlockExists(obTime, high[bar], low[bar])) {
                OrderBlock ob;
                ob.top = high[bar];
                ob.bottom = low[bar];
                ob.time = obTime;
                ob.isBullish = false;
                ob.isActive = true;
                ob.barIndex = bars - 1 - bar;
                ob.tf = PrimaryTF;
                
                AddOrderBlock(ob);
                newOBsFound++;
            }
        }
    }
    
    if(newOBsFound > 0) {
        Print("*** Historical Scan Complete: Found ", newOBsFound, " new order blocks ***");
    }
    
    // Clean up old/invalidated order blocks
    CleanOrderBlocks();
}

//+------------------------------------------------------------------+
//| Detect Order Blocks on Specific Timeframe                        |
//+------------------------------------------------------------------+
void DetectOrderBlocksOnTF(ENUM_TIMEFRAMES tf) {
    static bool historicalScanDone_M1 = false;
    static bool historicalScanDone_M3 = false;
    static bool historicalScanDone_M5 = false;
    static bool historicalScanDone_M15 = false;
    static bool historicalScanDone_M30 = false;
    
    // Get the correct historical scan flag for this timeframe
    bool historicalDone = false;
    if(tf == PERIOD_M1) {
        historicalDone = historicalScanDone_M1;
    } else if(tf == PERIOD_M3) {
        historicalDone = historicalScanDone_M3;
    } else if(tf == PERIOD_M5) {
        historicalDone = historicalScanDone_M5;
    } else if(tf == PERIOD_M15) {
        historicalDone = historicalScanDone_M15;
    } else {
        historicalDone = historicalScanDone_M30;
    }
    
    int bars = iBars(_Symbol, tf);
    if(bars < OB_Lookback + 5) return;
    
    // Determine how many bars to scan
    int scanBars = 1; // Default: only scan current bar
    if(!historicalDone && OB_HistoricalScan > 0) {
        // First time: do full historical scan
        scanBars = OB_HistoricalScan;
        if(scanBars > bars - 5) scanBars = bars - 5;
        
        // Update the correct static variable
        if(tf == PERIOD_M1) {
            historicalScanDone_M1 = true;
        } else if(tf == PERIOD_M3) {
            historicalScanDone_M3 = true;
        } else if(tf == PERIOD_M5) {
            historicalScanDone_M5 = true;
        } else if(tf == PERIOD_M15) {
            historicalScanDone_M15 = true;
        } else {
            historicalScanDone_M30 = true;
        }
        
        Print("*** Historical OB scan (", EnumToString(tf), "): ", scanBars, " bars ***");
    }
    
    // Get ATR for all bars we'll scan
    double atr[];
    ArraySetAsSeries(atr, true);
    CopyBuffer(iATR(_Symbol, tf, OB_ATR_Period), 0, 0, scanBars + OB_Lookback + 5, atr);
    
    // Get volume for all bars
    long volume[];
    ArraySetAsSeries(volume, true);
    CopyTickVolume(_Symbol, tf, 0, scanBars + OB_Lookback + 5, volume);
    
    // Calculate average volume (using recent bars for comparison)
    double avgVolume = 0.0;
    for(int i = 1; i <= OB_Lookback; i++) {
        avgVolume += (double)volume[i];
    }
    avgVolume /= (double)OB_Lookback;
    
    // Get price data for all bars to scan
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, tf, 0, scanBars + OB_Lookback + 5, high);
    CopyLow(_Symbol, tf, 0, scanBars + OB_Lookback + 5, low);
    CopyClose(_Symbol, tf, 0, scanBars + OB_Lookback + 5, close);
    CopyOpen(_Symbol, tf, 0, scanBars + OB_Lookback + 5, open);
    
    // Scan through historical bars (from recent to old)
    int newOBsFound = 0;
    for(int bar = 0; bar < scanBars; bar++) {
        // Skip if we don't have enough bars for comparison
        if(bar + 1 >= ArraySize(low)) continue;
        
        // Check for bullish order block
        // IMPROVED: More flexible detection - allow OB even if volume/ATR criteria are slightly off
        bool isBullishCandle = (close[bar] > open[bar]);
        bool hasVolume = (volume[bar] > avgVolume * OB_VolumeMultiplier);
        bool hasBodySize = ((close[bar] - open[bar]) > atr[bar] * OB_ATR_Multiplier);
        bool breaksPreviousLow = (low[bar] < low[bar + 1]);
        
        // Allow OB if it has strong volume OR strong body, and breaks structure
        bool qualifiesAsBullishOB = isBullishCandle && breaksPreviousLow && (hasVolume || hasBodySize);
        
        if(qualifiesAsBullishOB) {
            datetime obTime = iTime(_Symbol, tf, bar);
            
            // Check if this order block already exists
            if(!OrderBlockExists(obTime, high[bar], low[bar])) {
                OrderBlock ob;
                ob.top = high[bar];
                ob.bottom = low[bar];
                ob.time = obTime;
                ob.isBullish = true;
                ob.isActive = true;
                ob.barIndex = bars - 1 - bar;
                ob.tf = tf;
                
                AddOrderBlock(ob);
                newOBsFound++;
                
                // Log why this OB was detected
                if(bar < 10) { // Only log recent OBs to avoid spam
                    Print("  -> Bullish OB at ", ob.bottom, "-", ob.top, 
                          " | Volume: ", (hasVolume ? "YES" : "NO"), 
                          " | Body: ", (hasBodySize ? "YES" : "NO"),
                          " | Bar: ", bar);
                }
            }
        }
        
        // Check for bearish order block
        // IMPROVED: More flexible detection
        bool isBearishCandle = (close[bar] < open[bar]);
        bool hasVolumeBear = (volume[bar] > avgVolume * OB_VolumeMultiplier);
        bool hasBodySizeBear = ((open[bar] - close[bar]) > atr[bar] * OB_ATR_Multiplier);
        bool breaksPreviousHigh = (high[bar] > high[bar + 1]);
        
        // Allow OB if it has strong volume OR strong body, and breaks structure
        bool qualifiesAsBearishOB = isBearishCandle && breaksPreviousHigh && (hasVolumeBear || hasBodySizeBear);
        
        if(qualifiesAsBearishOB) {
            datetime obTime = iTime(_Symbol, tf, bar);
            
            // Check if this order block already exists
            if(!OrderBlockExists(obTime, high[bar], low[bar])) {
                OrderBlock ob;
                ob.top = high[bar];
                ob.bottom = low[bar];
                ob.time = obTime;
                ob.isBullish = false;
                ob.isActive = true;
                ob.barIndex = bars - 1 - bar;
                ob.tf = tf;
                
                AddOrderBlock(ob);
                newOBsFound++;
                
                // Log why this OB was detected
                if(bar < 10) { // Only log recent OBs to avoid spam
                    Print("  -> Bearish OB at ", ob.bottom, "-", ob.top, 
                          " | Volume: ", (hasVolumeBear ? "YES" : "NO"), 
                          " | Body: ", (hasBodySizeBear ? "YES" : "NO"),
                          " | Bar: ", bar);
                }
            }
        }
    }
    
    if(newOBsFound > 0) {
        Print("*** Found ", newOBsFound, " new OBs on ", EnumToString(tf), " ***");
    }
    
    // Clean up old/invalidated order blocks
    CleanOrderBlocks();
}

//+------------------------------------------------------------------+
//| Add Order Block to Array                                         |
//+------------------------------------------------------------------+
void AddOrderBlock(OrderBlock &ob) {
    int size = ArraySize(orderBlocks);
    ArrayResize(orderBlocks, size + 1);
    orderBlocks[size] = ob;
    
    // Calculate how old this order block is
    datetime currentTime = TimeCurrent();
    int ageMinutes = (int)((currentTime - ob.time) / 60);
    int ageHours = ageMinutes / 60;
    int ageDays = ageHours / 24;
    
    string ageStr = "";
    if(ageDays > 0) {
        ageStr = IntegerToString(ageDays) + " day(s) ago";
    } else if(ageHours > 0) {
        ageStr = IntegerToString(ageHours) + " hour(s) ago";
    } else {
        ageStr = IntegerToString(ageMinutes) + " minute(s) ago";
    }
    
    Print("*** NEW ORDER BLOCK DETECTED ***");
    Print("  Type: ", (ob.isBullish ? "BULLISH" : "BEARISH"));
    Print("  Zone: ", ob.bottom, " - ", ob.top);
    Print("  Timeframe: ", EnumToString(PrimaryTF));
    Print("  Formed: ", TimeToString(ob.time, TIME_DATE|TIME_MINUTES), " (", ageStr, ")");
    
    // Keep only last 50 order blocks
    if(size > 50) {
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
        
        // Check if order block is invalidated
        if(orderBlocks[i].isBullish) {
            // Bullish OB invalidated if price closes below bottom
            if(close[0] < orderBlocks[i].bottom) {
                Print("*** ORDER BLOCK INVALIDATED (BULLISH) ***");
                Print("  Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
                Print("  Price closed below: ", close[0], " < ", orderBlocks[i].bottom);
                orderBlocks[i].isActive = false;
            }
        } else {
            // Bearish OB invalidated if price closes above top
            if(close[0] > orderBlocks[i].top) {
                Print("*** ORDER BLOCK INVALIDATED (BEARISH) ***");
                Print("  Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
                Print("  Price closed above: ", close[0], " > ", orderBlocks[i].top);
                orderBlocks[i].isActive = false;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gaps                                           |
//+------------------------------------------------------------------+
void DetectFVG() {
    int bars = iBars(_Symbol, PrimaryTF);
    if(bars < 5) return;
    
    double high[], low[], close[], open[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    ArraySetAsSeries(open, true);
    CopyHigh(_Symbol, PrimaryTF, 0, 5, high);
    CopyLow(_Symbol, PrimaryTF, 0, 5, low);
    CopyClose(_Symbol, PrimaryTF, 0, 5, close);
    CopyOpen(_Symbol, PrimaryTF, 0, 5, open);
    
    // Bullish FVG: low[0] > high[2]
    if(low[0] > high[2] && close[1] > open[1]) {
        double fvgSize = (low[0] - high[2]) / pipValue;
        if(fvgSize >= FVG_MinSize) {
            FVG fvg;
            fvg.top = low[0];
            fvg.bottom = high[2];
            fvg.time = iTime(_Symbol, PrimaryTF, 0);
            fvg.isBullish = true;
            fvg.isActive = true;
            fvg.barIndex = bars - 1;
            
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
            fvg.time = iTime(_Symbol, PrimaryTF, 0);
            fvg.isBullish = false;
            fvg.isActive = true;
            fvg.barIndex = bars - 1;
            
            AddFVG(fvg);
        }
    }
    
    CleanFVG();
}

//+------------------------------------------------------------------+
//| Add FVG to Array                                                 |
//+------------------------------------------------------------------+
void AddFVG(FVG &fvg) {
    int size = ArraySize(fvgs);
    ArrayResize(fvgs, size + 1);
    fvgs[size] = fvg;
    
    // Keep only last 30 FVGs
    if(size > 30) {
        ArrayRemove(fvgs, 0, 1);
    }
}

//+------------------------------------------------------------------+
//| Clean Invalidated FVG                                            |
//+------------------------------------------------------------------+
void CleanFVG() {
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, PrimaryTF, 0, 10, close);
    
    int size = ArraySize(fvgs);
    for(int i = size - 1; i >= 0; i--) {
        if(!fvgs[i].isActive) continue;
        
        // FVG invalidated if price closes through it
        if(fvgs[i].isBullish && close[0] < fvgs[i].bottom) {
            fvgs[i].isActive = false;
        } else if(!fvgs[i].isBullish && close[0] > fvgs[i].top) {
            fvgs[i].isActive = false;
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Trend Lines (swing highs/lows on Higher TF)                |
//+------------------------------------------------------------------+
void DetectTrendLines() {
    int bars = iBars(_Symbol, HigherTF);
    if(bars < TrendLine_Lookback || TrendLine_Lookback < TrendLine_MinTouches + 5) return;
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    if(CopyHigh(_Symbol, HigherTF, 0, TrendLine_Lookback, high) < TrendLine_Lookback) return;
    if(CopyLow(_Symbol, HigherTF, 0, TrendLine_Lookback, low) < TrendLine_Lookback) return;
    
    // Find swing highs (pivot highs) and swing lows (pivot lows)
    int swingHighBars[], swingLowBars[];
    double swingHighPrices[], swingLowPrices[];
    ArrayResize(swingHighBars, 0);
    ArrayResize(swingLowBars, 0);
    ArrayResize(swingHighPrices, 0);
    ArrayResize(swingLowPrices, 0);
    
    int k = TrendLine_MinTouches;
    for(int i = k; i < TrendLine_Lookback - k; i++) {
        bool isSwingHigh = true;
        for(int j = 1; j <= k; j++) {
            if(high[i] <= high[i-j] || high[i] <= high[i+j]) { isSwingHigh = false; break; }
        }
        if(isSwingHigh) {
            int n = ArraySize(swingHighBars);
            ArrayResize(swingHighBars, n + 1);
            ArrayResize(swingHighPrices, n + 1);
            swingHighBars[n] = i;
            swingHighPrices[n] = high[i];
        }
        bool isSwingLow = true;
        for(int j = 1; j <= k; j++) {
            if(low[i] >= low[i-j] || low[i] >= low[i+j]) { isSwingLow = false; break; }
        }
        if(isSwingLow) {
            int n = ArraySize(swingLowBars);
            ArrayResize(swingLowBars, n + 1);
            ArrayResize(swingLowPrices, n + 1);
            swingLowBars[n] = i;
            swingLowPrices[n] = low[i];
        }
    }
    
    ArrayResize(trendLines, 0);
    double recentHigh = high[ArrayMaximum(high, 0, MathMin(50, TrendLine_Lookback))];
    double recentLow = low[ArrayMinimum(low, 0, MathMin(50, TrendLine_Lookback))];
    double rangeExtend = 200.0 * pipValue;
    
    // Support trendlines: connect pairs of swing lows; keep if projected level near recent range
    int nLow = ArraySize(swingLowBars);
    for(int a = 0; a < nLow; a++) {
        for(int b = a + 1; b < nLow; b++) {
            int bar1 = swingLowBars[a], bar2 = swingLowBars[b];
            if(bar2 - bar1 < 3) continue;
            double p1 = swingLowPrices[a], p2 = swingLowPrices[b];
            double slope = (p2 - p1) / (double)(bar2 - bar1);
            double levelAt0 = p1 + slope * (0 - bar1);
            if(levelAt0 < recentLow - rangeExtend || levelAt0 > recentHigh + rangeExtend) continue;
            int sz = ArraySize(trendLines);
            ArrayResize(trendLines, sz + 1);
            trendLines[sz].price1 = p1;
            trendLines[sz].price2 = p2;
            trendLines[sz].bar1 = bar1;
            trendLines[sz].bar2 = bar2;
            trendLines[sz].isSupport = true;
            trendLines[sz].isActive = true;
            if(sz >= 14) break;
        }
        if(ArraySize(trendLines) >= 15) break;
    }
    
    // Resistance trendlines: connect pairs of swing highs
    int nHigh = ArraySize(swingHighBars);
    for(int a = 0; a < nHigh; a++) {
        for(int b = a + 1; b < nHigh; b++) {
            int bar1 = swingHighBars[a], bar2 = swingHighBars[b];
            if(bar2 - bar1 < 3) continue;
            double p1 = swingHighPrices[a], p2 = swingHighPrices[b];
            double slope = (p2 - p1) / (double)(bar2 - bar1);
            double levelAt0 = p1 + slope * (0 - bar1);
            if(levelAt0 < recentLow - rangeExtend || levelAt0 > recentHigh + rangeExtend) continue;
            int sz = ArraySize(trendLines);
            ArrayResize(trendLines, sz + 1);
            trendLines[sz].price1 = p1;
            trendLines[sz].price2 = p2;
            trendLines[sz].bar1 = bar1;
            trendLines[sz].bar2 = bar2;
            trendLines[sz].isSupport = false;
            trendLines[sz].isActive = true;
            if(sz >= 14) break;
        }
        if(ArraySize(trendLines) >= 30) break;
    }
}

//+------------------------------------------------------------------+
//| Check if current price is on a trendline (within tolerance)      |
//+------------------------------------------------------------------+
bool PriceOnTrendline(double &levelOut, bool &isSupportOut) {
    levelOut = 0;
    isSupportOut = false;
    int size = ArraySize(trendLines);
    if(size == 0) return false;
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double tol = TrendLine_TouchTolerancePips * pipValue;
    for(int i = 0; i < size; i++) {
        if(!trendLines[i].isActive) continue;
        int b1 = trendLines[i].bar1, b2 = trendLines[i].bar2;
        if(b2 == b1) continue;
        double slope = (trendLines[i].price2 - trendLines[i].price1) / (double)(b2 - b1);
        double levelAt0 = trendLines[i].price1 + slope * (0 - b1);
        if(MathAbs(currentPrice - levelAt0) <= tol) {
            levelOut = levelAt0;
            isSupportOut = trendLines[i].isSupport;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Update Market Structure                                          |
//+------------------------------------------------------------------+
void UpdateMarketStructure() {
    int bars = iBars(_Symbol, HigherTF);
    if(bars < MS_SwingLength * 2 + 5) return;
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    CopyHigh(_Symbol, HigherTF, 0, MS_SwingLength * 2 + 5, high);
    CopyLow(_Symbol, HigherTF, 0, MS_SwingLength * 2 + 5, low);
    
    // Detect swing highs/lows
    double swingHigh = high[MS_SwingLength];
    double swingLow = low[MS_SwingLength];
    
    for(int i = 1; i <= MS_SwingLength; i++) {
        if(high[i] > swingHigh) {
            swingHigh = high[i];
        }
        if(low[i] < swingLow) {
            swingLow = low[i];
        }
    }
    
    // Check for BOS (Break of Structure)
    double currentHigh = high[0];
    double currentLow = low[0];
    
    if(marketStruct.trend == -1 && currentHigh > swingHigh) {
        // Bullish BOS
        marketStruct.lastBOS = currentHigh;
        marketStruct.lastBOS_Time = iTime(_Symbol, HigherTF, 0);
        marketStruct.trend = 1;
    } else if(marketStruct.trend == 1 && currentLow < swingLow) {
        // Bearish BOS
        marketStruct.lastCHoCH = currentLow;
        marketStruct.lastCHoCH_Time = iTime(_Symbol, HigherTF, 0);
        marketStruct.trend = -1;
    }
}

//+------------------------------------------------------------------+
//| Check if we're in a news event window                            |
//+------------------------------------------------------------------+
bool IsNewsEventActive() {
    if(!BlockTradesDuringNews) return false;
    
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    int hour = dt.hour;
    int minute = dt.min;
    int currentMinute = hour * 60 + minute;
    
    // High-impact news windows (in broker's local time - adjust as needed)
    // Common times: 8:30 AM, 10:00 AM, 2:00 PM, 4:00 PM (EST/EDT)
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
//| Check if opposite trade exists within minimum distance           |
//+------------------------------------------------------------------+
bool HasOppositeTradeNearby(bool isBuy, double entryPrice, double zoneBottom = 0, double zoneTop = 0) {
    // If set to 0, disable opposite trade prevention
    if(MinOppositeDistancePips <= 0) return false;
    
    double minDistance = MinOppositeDistancePips * pipValue;
    bool checkZone = (zoneBottom > 0 && zoneTop > 0 && zoneTop > zoneBottom);
    
    for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
        if(!position.SelectByIndex(pos)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        double posPrice = position.PriceOpen();
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type();
        
        // Check if opposite trade type
        bool isOpposite = false;
        if(isBuy && posType == POSITION_TYPE_SELL) {
            isOpposite = true;
        } else if(!isBuy && posType == POSITION_TYPE_BUY) {
            isOpposite = true;
        }
        
        if(isOpposite) {
            // Check 1: Is opposite trade in the same zone?
            if(checkZone && posPrice >= zoneBottom && posPrice <= zoneTop) {
                Print("Entry BLOCKED: Opposite trade in same zone (", posPrice, " in zone ", zoneBottom, "-", zoneTop, ")");
                return true;
            }
            
            // Check 2: Is entry price too close to opposite trade?
            double distance = MathAbs(entryPrice - posPrice);
            if(distance < minDistance) {
                Print("Entry BLOCKED: Opposite trade too close (distance: ", distance / pipValue, " pips = ", distance, " points, need ", MinOppositeDistancePips, " pips = ", minDistance, " points)");
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price Closed on Support/Resistance (M15)                |
//+------------------------------------------------------------------+
bool PriceClosedOnSupport_M15(double &supportLevel) {
    if(!TradeCloseOnSupport) return false;
    
    int bars = iBars(_Symbol, PERIOD_M15);
    if(bars < 2) return false;
    
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, PERIOD_M15, 0, 10, close);
    
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
            Print("*** PRICE CLOSED ON SUPPORT (M15) - HIGH PROBABILITY REVERSAL ***");
            Print("  Support Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
            Print("  Close Price: ", prevClose);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price Closed on Resistance (M15)                        |
//+------------------------------------------------------------------+
bool PriceClosedOnResistance_M15(double &resistanceLevel) {
    if(!TradeCloseOnResistance) return false;
    
    int bars = iBars(_Symbol, PERIOD_M15);
    if(bars < 2) return false;
    
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, PERIOD_M15, 0, 10, close);
    
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
            Print("*** PRICE CLOSED ON RESISTANCE (M15) - HIGH PROBABILITY REVERSAL ***");
            Print("  Resistance Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
            Print("  Close Price: ", prevClose);
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Price Hit FVG Retest (50% of FVG)                       |
//+------------------------------------------------------------------+
bool CheckFVG_Retest_M15(double &fvgTop, double &fvgBottom, bool &isBullishFVG) {
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
            
            Print("*** FVG RETEST DETECTED (", FVG_RetestPercent, "% hit) - HIGH PROBABILITY REVERSAL ***");
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
//| Check Entry Signals                                              |
//+------------------------------------------------------------------+
void CheckEntrySignals() {
    // STARTUP COOLDOWN: Block trades for 5 seconds (was 20 - reduced so you can trade sooner)
    if(initTime > 0 && TimeCurrent() - initTime < 5) {
        static datetime lastCooldownLog = 0;
        if(TimeCurrent() - lastCooldownLog >= 2) {
            int remainingSeconds = 5 - (int)(TimeCurrent() - initTime);
            Print("*** STARTUP COOLDOWN: ", remainingSeconds, " sec - trades blocked ***");
            lastCooldownLog = TimeCurrent();
        }
        return; // Exit early - no trades during cooldown
    }
    
    static datetime lastDebugLog = 0;
    static datetime lastSkipLog = 0; // For logging blocked entries
    static datetime lastTradeOpenTime = 0; // Track when last trade was opened
    static bool tradeOpenedThisTick = false; // Flag to prevent opposite trades in same tick
    bool shouldLogDebug = (TimeCurrent() - lastDebugLog >= 30); // Log every 30 seconds
    
    // Reset flag if new tick (different second)
    datetime currentTick = TimeCurrent();
    if(currentTick != lastTradeOpenTime) {
        tradeOpenedThisTick = false;
    }
    
    // Check for news events - block all entries during news
    if(IsNewsEventActive()) {
        static datetime lastNewsLog = 0;
        if(TimeCurrent() - lastNewsLog > 60) { // Log every minute
            Print("*** TRADING BLOCKED: High-impact news event window active ***");
            lastNewsLog = TimeCurrent();
        }
        return; // Exit early - no trades during news
    }
    
    double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Count current positions - CRITICAL: Count on EVERY tick to prevent same-price entries
    int buyPositions = CountPositions(POSITION_TYPE_BUY);
    int sellPositions = CountPositions(POSITION_TYPE_SELL);
    
    // CRITICAL: GLOBAL HARD BLOCK - If ANY opposite trade exists, BLOCK ALL opposite entries
    // This prevents same-price entries completely
    bool globalBlockBUY = (sellPositions > 0); // Block BUY if any SELL exists
    bool globalBlockSELL = (buyPositions > 0); // Block SELL if any BUY exists
    
    // ENHANCED: Also check if trades were just opened this tick
    if(tradeOpenedThisTick) {
        // If a trade was opened this tick, block opposite direction completely
        if(buyPositions > 0) globalBlockSELL = true;
        if(sellPositions > 0) globalBlockBUY = true;
    }
    
    if(globalBlockBUY || globalBlockSELL) {
        static datetime lastGlobalBlockLog = 0;
        if(TimeCurrent() - lastGlobalBlockLog > 5) {
            if(globalBlockBUY) Print("*** GLOBAL BLOCK: SELL positions exist (", sellPositions, ") - ALL BUY entries BLOCKED ***");
            if(globalBlockSELL) Print("*** GLOBAL BLOCK: BUY positions exist (", buyPositions, ") - ALL SELL entries BLOCKED ***");
            lastGlobalBlockLog = TimeCurrent();
        }
        // EXIT EARLY if global block is active - don't even check for entries
        return;
    }
    
    // DEBUG: Log detection status
    if(shouldLogDebug) {
        Print("=== ENTRY SIGNAL CHECK DEBUG ===");
        Print("Current Price: ", currentPrice, " | Ask: ", ask);
        Print("Open Positions: BUY=", buyPositions, " SELL=", sellPositions);
        Print("Market Structure: Trend=", marketStruct.trend, " (1=bullish, -1=bearish, 0=neutral)");
        Print("RequireBOS: ", RequireBOS ? "YES" : "NO");
        Print("MultipleEntries: ", MultipleEntries ? "YES" : "NO", " | MaxEntries: ", MaxEntries);
        Print("MinOppositeDistancePips: ", MinOppositeDistancePips);
    }
    
    // Note: Removed hard block - let zone-based and distance-based checks handle it
    // This allows more trades while still preventing conflicts
    
    // Check for high-probability reversal setups FIRST (these bypass restrictions)
    double supportLevel = 0, resistanceLevel = 0;
    bool closedOnSupport = PriceClosedOnSupport_M15(supportLevel);
    bool closedOnResistance = PriceClosedOnResistance_M15(resistanceLevel);
    double fvgTop = 0, fvgBottom = 0;
    bool isBullishFVG = false;
    bool fvgRetest = CheckFVG_Retest_M15(fvgTop, fvgBottom, isBullishFVG);
    // Trendline confluence: price on support TL = bullish confluence, on resistance TL = bearish
    double trendlineLevel = 0;
    bool trendlineIsSupport = false;
    bool onTrendline = UseTrendLines && PriceOnTrendline(trendlineLevel, trendlineIsSupport);
    bool isHighProbability = closedOnSupport || closedOnResistance || fvgRetest || onTrendline;
    
    if(isHighProbability) {
        Print("*** HIGH-PROBABILITY REVERSAL SETUP DETECTED - Bypassing strict requirements ***");
        if(closedOnSupport) Print("  -> Price closed on SUPPORT (M15)");
        if(closedOnResistance) Print("  -> Price closed on RESISTANCE (M15)");
        if(fvgRetest) Print("  -> FVG RETEST detected (", FVG_RetestPercent, "% hit)");
        if(onTrendline) Print("  -> Price on TRENDLINE (", (trendlineIsSupport ? "SUPPORT" : "RESISTANCE"), " @ ", trendlineLevel, ")");
    }
    
    // Check order block entries
    int size = ArraySize(orderBlocks);
    
    if(shouldLogDebug) {
        int activeCount = 0;
        for(int dbg = 0; dbg < size; dbg++) {
            if(orderBlocks[dbg].isActive) activeCount++;
        }
        Print("=== ACTIVE ORDER BLOCKS: ", activeCount, " total ===");
        
        // Show all active order blocks with distance to price
        for(int dbg = 0; dbg < size; dbg++) {
            if(!orderBlocks[dbg].isActive) continue;
            
            double zoneTop = orderBlocks[dbg].top;
            double zoneBottom = orderBlocks[dbg].bottom;
            bool priceInZone = (currentPrice >= zoneBottom && currentPrice <= zoneTop);
            double distance = 0;
            
            if(priceInZone) {
                distance = 0;
            } else if(currentPrice < zoneBottom) {
                distance = (zoneBottom - currentPrice) / pipValue; // Distance below zone
            } else {
                distance = (currentPrice - zoneTop) / pipValue; // Distance above zone
            }
            
            Print("  OB[", dbg, "]: ", (orderBlocks[dbg].isBullish ? "BULLISH" : "BEARISH"), 
                  " | Zone: ", zoneBottom, "-", zoneTop,
                  " | Price: ", currentPrice,
                  " | Status: ", (priceInZone ? "IN ZONE" : DoubleToString(distance, 1) + " pips away"),
                  " | Age: ", TimeToString(orderBlocks[dbg].time, TIME_DATE|TIME_MINUTES));
        }
        lastDebugLog = TimeCurrent();
    }
    // Calculate touch tolerance in points
    double touchTolerance = EntryTouchTolerance * pipValue;
    
    // Breakout entries (enter when price BREAKS last N-bar high/low - catch big moves)
    if(UseBreakoutEntries && CheckBreakoutEntries(ask, buyPositions, sellPositions, globalBlockBUY, globalBlockSELL)) {
        return;
    }
    
    for(int i = size - 1; i >= 0; i--) {
        if(!orderBlocks[i].isActive) continue;
        
        // Bullish order block entry - check if price is in zone OR near zone (with tolerance)
        if(orderBlocks[i].isBullish) {
            // Check if this is a high-probability setup (closed on support, FVG retest, or trendline confluence)
            bool isHighProbBullish = closedOnSupport || (fvgRetest && isBullishFVG) || (onTrendline && trendlineIsSupport);
            bool priceInZone = (currentPrice >= orderBlocks[i].bottom && currentPrice <= orderBlocks[i].top);
            bool priceNearZone = (currentPrice >= orderBlocks[i].bottom - touchTolerance && 
                                  currentPrice <= orderBlocks[i].top + touchTolerance);
            
            // For high-probability setups, expand the zone check
            if(isHighProbBullish && !priceInZone && !priceNearZone) {
                // Check if support level or FVG is near this order block
                if(closedOnSupport && MathAbs(supportLevel - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
                if(fvgRetest && isBullishFVG && MathAbs((fvgBottom + fvgTop) / 2.0 - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
                if(onTrendline && trendlineIsSupport && MathAbs(trendlineLevel - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
            }
            
            if(priceInZone || priceNearZone || isHighProbBullish) {
                // Log zone touch status
                static datetime lastTouchLog = 0;
                if(TimeCurrent() - lastTouchLog > 5) {
                    if(priceInZone) {
                        Print("*** PRICE IN BULLISH ORDER BLOCK ZONE ***");
                    } else {
                        Print("*** PRICE NEAR BULLISH ORDER BLOCK ZONE (within ", EntryTouchTolerance, " pips) ***");
                    }
                    Print("  Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
                    Print("  Current Price: ", currentPrice);
                    Print("  Distance to zone: ", (priceInZone ? "INSIDE" : DoubleToString((currentPrice < orderBlocks[i].bottom ? orderBlocks[i].bottom - currentPrice : currentPrice - orderBlocks[i].top) / pipValue, 2) + " pips"));
                    lastTouchLog = TimeCurrent();
                }
                
                // Check if we should enter
                bool shouldEnter = true;
                string blockReason = "";
                
                // High-probability setups bypass market structure requirement
                if(RequireBOS && marketStruct.trend != 1 && !isHighProbBullish) {
                    shouldEnter = false;
                    blockReason = "RequireBOS=true but trend=" + IntegerToString(marketStruct.trend) + " (need 1=bullish)";
                }
                
                // Check entry limit (allow multiple trades - just check max)
                if(MultipleEntries && buyPositions >= MaxEntries) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "Max entries reached: " + IntegerToString(buyPositions) + "/" + IntegerToString(MaxEntries);
                }
                
                // CRITICAL: Check for opposite trades nearby or in same zone
                double entryPrice = ask;
                if(HasOppositeTradeNearby(true, entryPrice, orderBlocks[i].bottom, orderBlocks[i].top)) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "Opposite trade too close or in same zone";
                }
                
                // Check for existing trades in same zone (for layered entries)
                if(shouldEnter && AllowLayeredEntries && buyPositions > 0) {
                    double minDistance = MinEntryDistancePips * pipValue;
                    bool hasTradeInSameZone = false;
                    
                    for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
                        if(!position.SelectByIndex(pos)) continue;
                        if(position.Symbol() != _Symbol) continue;
                        if(position.Magic() != MagicNumber) continue;
                        if(position.Type() != POSITION_TYPE_BUY) continue;
                        
                        double existingEntry = position.PriceOpen();
                        double distance = MathAbs(entryPrice - existingEntry);
                        
                        // Check if existing trade is in the same order block zone
                        bool inSameZone = (existingEntry >= orderBlocks[i].bottom && existingEntry <= orderBlocks[i].top);
                        
                        if(inSameZone && distance < minDistance) {
                            hasTradeInSameZone = true;
                            if(TimeCurrent() - lastSkipLog > 5) {
                                Print("BUY entry BLOCKED: Trade already exists in same zone (", DoubleToString(distance / pipValue, 1), " pips < ", MinEntryDistancePips, " pips minimum)");
                                lastSkipLog = TimeCurrent();
                            }
                            break;
                        }
                    }
                    
                    if(hasTradeInSameZone) {
                        shouldEnter = false;
                        if(blockReason != "") blockReason += " | ";
                        blockReason += "Trade too close in same zone (need " + DoubleToString(MinEntryDistancePips, 1) + " pips distance)";
                    }
                }
                
                // QUICK REJECTION CHECK: Optional 1-bar delay if large wick detected
                if(shouldEnter && UseQuickRejectionCheck && HasLargeWick(true)) {
                    // Large wick detected - wait 1 bar for rejection confirmation
                    static datetime lastRejectionWait = 0;
                    static bool waitingForRejection = false;
                    
                    if(!waitingForRejection) {
                        waitingForRejection = true;
                        lastRejectionWait = TimeCurrent();
                        Print("BUY entry DELAYED: Large wick detected (", QuickRejection_WickSize, "+ pips). Waiting 1 bar for rejection confirmation...");
                    } else {
                        // Check if we've waited at least 1 bar
                        datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
                        datetime previousBarTime = iTime(_Symbol, PERIOD_CURRENT, 1);
                        if(currentBarTime != previousBarTime) {
                            // New bar formed - proceed with entry
                            waitingForRejection = false;
                            Print("BUY entry PROCEEDING: Rejection confirmed after 1 bar wait");
                        } else {
                            // Still same bar - keep waiting
                            shouldEnter = false;
                            if(blockReason != "") blockReason += " | ";
                            blockReason += "Waiting for rejection confirmation (large wick detected)";
                        }
                    }
                } else if(shouldEnter && UseQuickRejectionCheck) {
                    // No large wick - reset waiting flag
                    static bool waitingForRejection = false;
                    waitingForRejection = false;
                }
                
                if(shouldEnter) {
                    // CRITICAL: Re-check position count BEFORE opening trade (prevents opening too many)
                    buyPositions = CountPositions(POSITION_TYPE_BUY);
                    
                    // Check for scaling entry opportunity (only if existing trade is in drawdown + confluence)
                    double scalingSL = 0;
                    double scalingSLPips = 0;
                    bool canScale = false;
                    bool isFirstTrade = (buyPositions == 0); // First trade if no positions exist
                    int confluenceCount = 1; // Count confluences for this entry
                    if((orderBlocks[i].top - orderBlocks[i].bottom) / pipValue < 10) {
                        confluenceCount = 2; // Tight zone suggests multiple confluences
                    }
                    
                    if(AllowScalingEntries && buyPositions > 0 && !isFirstTrade) {
                        // Find existing BUY position to check if it's in drawdown
                        bool foundLosingPosition = false;
                        double existingEntryPrice = 0;
                        double existingSL = 0;
                        
                        for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
                            if(!position.SelectByIndex(pos)) continue;
                            if(position.Symbol() != _Symbol) continue;
                            if(position.Magic() != MagicNumber) continue;
                            if(position.Type() != POSITION_TYPE_BUY) continue;
                            
                            existingEntryPrice = position.PriceOpen();
                            existingSL = position.StopLoss();
                            double currentBID = SymbolInfoDouble(_Symbol, SYMBOL_BID);
                            double currentProfitPips = (currentBID - existingEntryPrice) / pipValue;
                            
                            // Check if position is in drawdown (losing)
                            if(OnlyScaleOnDrawdown && currentProfitPips < -ScalingDrawdownPips) {
                                foundLosingPosition = true;
                                scalingSL = existingSL;
                                if(existingSL > 0) {
                                    scalingSLPips = (existingEntryPrice - existingSL) / pipValue;
                                }
                                break;
                            } else if(!OnlyScaleOnDrawdown) {
                                // If not requiring drawdown, check for big SL
                                if(existingSL > 0) {
                                    scalingSLPips = (existingEntryPrice - existingSL) / pipValue;
                                    if(scalingSLPips >= BigSL_Threshold) {
                                        foundLosingPosition = true;
                                        scalingSL = existingSL;
                                        break;
                                    }
                                }
                            }
                        }
                        
                        if(foundLosingPosition && scalingSL > 0) {
                            // Check if we haven't exceeded scaling limit
                            int scalingCount = CountScalingEntries(scalingSL);
                            if(scalingCount <= MaxScalingEntries) {
                                // Check if there's a new confluence (if required)
                                if(!RequireConfluenceForScaling || confluenceCount >= 2) {
                                    canScale = true;
                                    Print("*** SCALING ENTRY OPPORTUNITY DETECTED ***");
                                    Print("  Existing position in drawdown: ", (OnlyScaleOnDrawdown ? "YES (losing)" : "Big SL"), " | SL: ", scalingSLPips, " pips");
                                    Print("  Scaling entries so far: ", scalingCount, "/", MaxScalingEntries);
                                    Print("  New confluence detected: ", confluenceCount, " factors");
                                    Print("  Will use LOWER risk: ", ScalingEntryRisk, "% (vs ", FirstTradeRisk, "% for first trade)");
                                }
                            }
                        }
                    }
                    
                    // Check if we can enter (normal entry or scaling entry)
                    bool canEnter = false;
                    if(canScale) {
                        // Scaling entry - bypass MaxEntries check
                        canEnter = true;
                    } else if(MultipleEntries && buyPositions >= MaxEntries) {
                        if(TimeCurrent() - lastSkipLog > 5) {
                            Print("BUY entry BLOCKED: Max entries already reached (", buyPositions, "/", MaxEntries, ")");
                            lastSkipLog = TimeCurrent();
                        }
                        continue; // Skip this order block, check next one
                    } else {
                        canEnter = true;
                    }
                    
                    if(!canEnter) continue;
                    
                    // CRITICAL: Check total risk before opening new trade
                    double currentTotalRisk = CalculateTotalRisk();
                    double newTradeRisk = RiskPercent;
                    double totalRiskAfter = currentTotalRisk + newTradeRisk;
                    
                    if(totalRiskAfter > MaxTotalRisk) {
                        if(TimeCurrent() - lastSkipLog > 5) {
                            Print("BUY entry BLOCKED: Total risk would exceed limit (", DoubleToString(totalRiskAfter, 2), "% > ", MaxTotalRisk, "%)");
                            Print("  Current total risk: ", DoubleToString(currentTotalRisk, 2), "% | New trade risk: ", DoubleToString(newTradeRisk, 2), "%");
                            lastSkipLog = TimeCurrent();
                        }
                        continue; // Skip this order block
                    }
                    
                    Print("*** ENTERING BUY TRADE ***");
                    Print("  Order Block: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
                    Print("  Entry Price: ", ask);
                    Print("  Market Structure: ", marketStruct.trend);
                    Print("  Price Status: ", (priceInZone ? "IN ZONE" : "NEAR ZONE"));
                    Print("  Current BUY positions: ", buyPositions, "/", MaxEntries);
                    Print("  Entry Type: ", (isFirstTrade ? "FIRST TRADE" : (canScale ? "SCALING (losing position + confluence)" : "ADDITIONAL")));
                    Print("  Risk: ", newTradeRisk, "% (", (isFirstTrade ? "FirstTradeRisk" : (canScale ? "ScalingEntryRisk" : "RiskPercent")), ")");
                    
                    // Open order with scaling SL if available, and pass risk percentage
                    if(canScale) {
                        OpenBuyOrder(orderBlocks[i], scalingSL, ScalingEntryRisk);
                    } else {
                        OpenBuyOrder(orderBlocks[i], 0, newTradeRisk);
                    }
                    lastBuyEntryTime = TimeCurrent();
                    tradeOpenedThisTick = true; // Mark that a trade was opened this tick
                    
                    // IMMEDIATELY update position count and block opposite trades
                    buyPositions = CountPositions(POSITION_TYPE_BUY);
                    sellPositions = CountPositions(POSITION_TYPE_SELL);
                    globalBlockSELL = true; // Block all SELL entries after opening BUY
                    
                    Print("*** TRADE OPENED - Updated counts: BUY=", buyPositions, " SELL=", sellPositions, " - Blocking opposite entries ***");
                    
                    if(buyPositions >= MaxEntries) {
                        Print("*** MAX BUY ENTRIES REACHED (", buyPositions, "/", MaxEntries, ") - Stopping further BUY entries ***");
                        break; // Stop checking more order blocks once max is reached
                    }
                    
                    // CRITICAL: If we just opened a trade, exit immediately to prevent opposite trades in same tick
                    return;
                } else {
                    // Detailed logging for why entry is blocked
                    static datetime lastSkipLog = 0;
                    if(TimeCurrent() - lastSkipLog > 5) { // Log every 5 seconds max
                        Print("BUY entry BLOCKED - Reasons: ", blockReason);
                        lastSkipLog = TimeCurrent();
                    }
                }
            }
        }
        // Bearish order block entry - check if price is in zone OR near zone (with tolerance)
        else {
            // Check if this is a high-probability setup (closed on resistance or FVG retest)
            bool isHighProbBearish = closedOnResistance || (fvgRetest && !isBullishFVG) || (onTrendline && !trendlineIsSupport);
            bool priceInZone = (currentPrice <= orderBlocks[i].top && currentPrice >= orderBlocks[i].bottom);
            bool priceNearZone = (currentPrice <= orderBlocks[i].top + touchTolerance && 
                                  currentPrice >= orderBlocks[i].bottom - touchTolerance);
            
            // For high-probability setups, expand the zone check
            if(isHighProbBearish && !priceInZone && !priceNearZone) {
                // Check if resistance level or FVG is near this order block
                if(closedOnResistance && MathAbs(resistanceLevel - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
                if(fvgRetest && !isBullishFVG && MathAbs((fvgBottom + fvgTop) / 2.0 - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
                if(onTrendline && !trendlineIsSupport && MathAbs(trendlineLevel - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
            }
            
            if(priceInZone || priceNearZone || isHighProbBearish) {
                // Log zone touch status
                static datetime lastTouchLog = 0;
                if(TimeCurrent() - lastTouchLog > 5) {
                    if(priceInZone) {
                        Print("*** PRICE IN BEARISH ORDER BLOCK ZONE ***");
                    } else {
                        Print("*** PRICE NEAR BEARISH ORDER BLOCK ZONE (within ", EntryTouchTolerance, " pips) ***");
                    }
                    Print("  Zone: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
                    Print("  Current Price: ", currentPrice);
                    Print("  Distance to zone: ", (priceInZone ? "INSIDE" : DoubleToString((currentPrice > orderBlocks[i].top ? currentPrice - orderBlocks[i].top : orderBlocks[i].bottom - currentPrice) / pipValue, 2) + " pips"));
                    lastTouchLog = TimeCurrent();
                }
                
                bool shouldEnter = true;
                string blockReason = "";
                
                // High-probability setups bypass market structure requirement
                if(RequireBOS && marketStruct.trend != -1 && !isHighProbBearish) {
                    shouldEnter = false;
                    blockReason = "RequireBOS=true but trend=" + IntegerToString(marketStruct.trend) + " (need -1=bearish)";
                }
                
                // Check entry limit (allow multiple trades - just check max)
                if(MultipleEntries && sellPositions >= MaxEntries) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "Max entries reached: " + IntegerToString(sellPositions) + "/" + IntegerToString(MaxEntries);
                }
                
                // CRITICAL: Check for opposite trades nearby or in same zone
                double entryPrice = currentPrice;
                if(HasOppositeTradeNearby(false, entryPrice, orderBlocks[i].bottom, orderBlocks[i].top)) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "Opposite trade too close or in same zone";
                }
                
                // Check for existing trades in same zone (for layered entries)
                if(shouldEnter && AllowLayeredEntries && sellPositions > 0) {
                    double minDistance = MinEntryDistancePips * pipValue;
                    bool hasTradeInSameZone = false;
                    
                    for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
                        if(!position.SelectByIndex(pos)) continue;
                        if(position.Symbol() != _Symbol) continue;
                        if(position.Magic() != MagicNumber) continue;
                        if(position.Type() != POSITION_TYPE_SELL) continue;
                        
                        double existingEntry = position.PriceOpen();
                        double distance = MathAbs(entryPrice - existingEntry);
                        
                        // Check if existing trade is in the same order block zone
                        bool inSameZone = (existingEntry >= orderBlocks[i].bottom && existingEntry <= orderBlocks[i].top);
                        
                        if(inSameZone && distance < minDistance) {
                            hasTradeInSameZone = true;
                            if(TimeCurrent() - lastSkipLog > 5) {
                                Print("SELL entry BLOCKED: Trade already exists in same zone (", DoubleToString(distance / pipValue, 1), " pips < ", MinEntryDistancePips, " pips minimum)");
                                lastSkipLog = TimeCurrent();
                            }
                            break;
                        }
                    }
                    
                    if(hasTradeInSameZone) {
                        shouldEnter = false;
                        if(blockReason != "") blockReason += " | ";
                        blockReason += "Trade too close in same zone (need " + DoubleToString(MinEntryDistancePips, 1) + " pips distance)";
                    }
                }
                
                // QUICK REJECTION CHECK: Optional 1-bar delay if large wick detected
                if(shouldEnter && UseQuickRejectionCheck && HasLargeWick(false)) {
                    // Large wick detected - wait 1 bar for rejection confirmation
                    static datetime lastRejectionWait_SELL = 0;
                    static bool waitingForRejection_SELL = false;
                    
                    if(!waitingForRejection_SELL) {
                        waitingForRejection_SELL = true;
                        lastRejectionWait_SELL = TimeCurrent();
                        Print("SELL entry DELAYED: Large wick detected (", QuickRejection_WickSize, "+ pips). Waiting 1 bar for rejection confirmation...");
                    } else {
                        // Check if we've waited at least 1 bar
                        datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
                        datetime previousBarTime = iTime(_Symbol, PERIOD_CURRENT, 1);
                        if(currentBarTime != previousBarTime) {
                            // New bar formed - proceed with entry
                            waitingForRejection_SELL = false;
                            Print("SELL entry PROCEEDING: Rejection confirmed after 1 bar wait");
                        } else {
                            // Still same bar - keep waiting
                            shouldEnter = false;
                            if(blockReason != "") blockReason += " | ";
                            blockReason += "Waiting for rejection confirmation (large wick detected)";
                        }
                    }
                } else if(shouldEnter && UseQuickRejectionCheck) {
                    // No large wick - reset waiting flag
                    static bool waitingForRejection_SELL = false;
                    waitingForRejection_SELL = false;
                }
                
                if(shouldEnter) {
                    // CRITICAL: Re-check position count BEFORE opening trade (prevents opening too many)
                    sellPositions = CountPositions(POSITION_TYPE_SELL);
                    
                    // Check for scaling entry opportunity (only if existing trade is in drawdown + confluence)
                    double scalingSL = 0;
                    double scalingSLPips = 0;
                    bool canScale = false;
                    bool isFirstTrade = (sellPositions == 0); // First trade if no positions exist
                    int confluenceCount = 1; // Count confluences for this entry
                    if((orderBlocks[i].top - orderBlocks[i].bottom) / pipValue < 10) {
                        confluenceCount = 2; // Tight zone suggests multiple confluences
                    }
                    
                    if(AllowScalingEntries && sellPositions > 0 && !isFirstTrade) {
                        // Find existing SELL position to check if it's in drawdown
                        bool foundLosingPosition = false;
                        double existingEntryPrice = 0;
                        double existingSL = 0;
                        
                        for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
                            if(!position.SelectByIndex(pos)) continue;
                            if(position.Symbol() != _Symbol) continue;
                            if(position.Magic() != MagicNumber) continue;
                            if(position.Type() != POSITION_TYPE_SELL) continue;
                            
                            existingEntryPrice = position.PriceOpen();
                            existingSL = position.StopLoss();
                            double currentASK = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
                            double currentProfitPips = (existingEntryPrice - currentASK) / pipValue;
                            
                            // Check if position is in drawdown (losing)
                            if(OnlyScaleOnDrawdown && currentProfitPips < -ScalingDrawdownPips) {
                                foundLosingPosition = true;
                                scalingSL = existingSL;
                                if(existingSL > 0) {
                                    scalingSLPips = (existingSL - existingEntryPrice) / pipValue;
                                }
                                break;
                            } else if(!OnlyScaleOnDrawdown) {
                                // If not requiring drawdown, check for big SL
                                if(existingSL > 0) {
                                    scalingSLPips = (existingSL - existingEntryPrice) / pipValue;
                                    if(scalingSLPips >= BigSL_Threshold) {
                                        foundLosingPosition = true;
                                        scalingSL = existingSL;
                                        break;
                                    }
                                }
                            }
                        }
                        
                        if(foundLosingPosition && scalingSL > 0) {
                            // Check if we haven't exceeded scaling limit
                            int scalingCount = CountScalingEntries(scalingSL);
                            if(scalingCount <= MaxScalingEntries) {
                                // Check if there's a new confluence (if required)
                                if(!RequireConfluenceForScaling || confluenceCount >= 2) {
                                    canScale = true;
                                    Print("*** SCALING ENTRY OPPORTUNITY DETECTED ***");
                                    Print("  Existing position in drawdown: ", (OnlyScaleOnDrawdown ? "YES (losing)" : "Big SL"), " | SL: ", scalingSLPips, " pips");
                                    Print("  Scaling entries so far: ", scalingCount, "/", MaxScalingEntries);
                                    Print("  New confluence detected: ", confluenceCount, " factors");
                                    Print("  Will use LOWER risk: ", ScalingEntryRisk, "% (vs ", FirstTradeRisk, "% for first trade)");
                                }
                            }
                        }
                    }
                    
                    // Check if we can enter (normal entry or scaling entry)
                    bool canEnter = false;
                    if(canScale) {
                        // Scaling entry - bypass MaxEntries check
                        canEnter = true;
                    } else if(MultipleEntries && sellPositions >= MaxEntries) {
                        if(TimeCurrent() - lastSkipLog > 5) {
                            Print("SELL entry BLOCKED: Max entries already reached (", sellPositions, "/", MaxEntries, ")");
                            lastSkipLog = TimeCurrent();
                        }
                        continue; // Skip this order block, check next one
                    } else {
                        canEnter = true;
                    }
                    
                    if(!canEnter) continue;
                    
                    // CRITICAL: Check total risk before opening new trade
                    // Use FirstTradeRisk for first trade, ScalingEntryRisk for scaling entries
                    double currentTotalRisk = CalculateTotalRisk();
                    double newTradeRisk = isFirstTrade ? FirstTradeRisk : (canScale ? ScalingEntryRisk : RiskPercent);
                    double totalRiskAfter = currentTotalRisk + newTradeRisk;
                    
                    if(totalRiskAfter > MaxTotalRisk) {
                        if(TimeCurrent() - lastSkipLog > 5) {
                            Print("SELL entry BLOCKED: Total risk would exceed limit (", DoubleToString(totalRiskAfter, 2), "% > ", MaxTotalRisk, "%)");
                            Print("  Current total risk: ", DoubleToString(currentTotalRisk, 2), "% | New trade risk: ", DoubleToString(newTradeRisk, 2), "%");
                            lastSkipLog = TimeCurrent();
                        }
                        continue; // Skip this order block
                    }
                    
                    Print("*** ENTERING SELL TRADE ***");
                    Print("  Order Block: ", orderBlocks[i].bottom, " - ", orderBlocks[i].top);
                    Print("  Entry Price: ", currentPrice);
                    Print("  Market Structure: ", marketStruct.trend);
                    Print("  Price Status: ", (priceInZone ? "IN ZONE" : "NEAR ZONE"));
                    Print("  Current SELL positions: ", sellPositions, "/", MaxEntries);
                    Print("  Entry Type: ", (isFirstTrade ? "FIRST TRADE" : (canScale ? "SCALING (losing position + confluence)" : "ADDITIONAL")));
                    Print("  Risk: ", newTradeRisk, "% (", (isFirstTrade ? "FirstTradeRisk" : (canScale ? "ScalingEntryRisk" : "RiskPercent")), ")");
                    
                    // Open order with scaling SL if available, and pass risk percentage
                    if(canScale) {
                        OpenSellOrder(orderBlocks[i], scalingSL, ScalingEntryRisk);
                    } else {
                        OpenSellOrder(orderBlocks[i], 0, newTradeRisk);
                    }
                    lastSellEntryTime = TimeCurrent();
                    tradeOpenedThisTick = true; // Mark that a trade was opened this tick
                    
                    // IMMEDIATELY update position count and block opposite trades
                    buyPositions = CountPositions(POSITION_TYPE_BUY);
                    sellPositions = CountPositions(POSITION_TYPE_SELL);
                    globalBlockBUY = true; // Block all BUY entries after opening SELL
                    
                    Print("*** TRADE OPENED - Updated counts: BUY=", buyPositions, " SELL=", sellPositions, " - Blocking opposite entries ***");
                    
                    if(sellPositions >= MaxEntries) {
                        Print("*** MAX SELL ENTRIES REACHED (", sellPositions, "/", MaxEntries, ") - Stopping further SELL entries ***");
                        break; // Stop checking more order blocks once max is reached
                    }
                    
                    // CRITICAL: If we just opened a trade, exit immediately to prevent opposite trades in same tick
                    return;
                } else {
                    // Detailed logging for why entry is blocked
                    static datetime lastSkipLog = 0;
                    if(TimeCurrent() - lastSkipLog > 5) { // Log every 5 seconds max
                        Print("SELL entry BLOCKED - Reasons: ", blockReason);
                        lastSkipLog = TimeCurrent();
                    }
                }
            }
        }
    }
    
    // Check FVG entries (allow multiple trades)
    if(UseFVG) {
        int fvgSize = ArraySize(fvgs);
        for(int i = fvgSize - 1; i >= 0; i--) {
            if(!fvgs[i].isActive) continue;
            
            if(fvgs[i].isBullish && currentPrice >= fvgs[i].bottom && currentPrice <= fvgs[i].top) {
                double fvgMidBuy = (fvgs[i].bottom + fvgs[i].top) / 2.0;
                if(FVG_RequirePullback && currentPrice > fvgMidBuy) continue; // Wait for pullback into lower half
                // CRITICAL: Re-check position count BEFORE opening trade
                buyPositions = CountPositions(POSITION_TYPE_BUY);
                if(buyPositions >= MaxEntries) {
                    continue; // Skip this FVG, check next one
                }
                
                // CRITICAL: Check total risk before opening new trade
                // Use FirstTradeRisk for first trade, RiskPercent for additional
                bool isFirstTradeFVG = (buyPositions == 0);
                double currentTotalRisk = CalculateTotalRisk();
                double newTradeRisk = isFirstTradeFVG ? FirstTradeRisk : RiskPercent;
                double totalRiskAfter = currentTotalRisk + newTradeRisk;
                if(totalRiskAfter > MaxTotalRisk) {
                    continue; // Skip this FVG
                }
                
                // CRITICAL: GLOBAL HARD BLOCK - If ANY SELL exists, block ALL BUY entries
                if(globalBlockBUY) {
                    continue; // Skip this FVG - SELL position exists
                }
                
                // CRITICAL: Check for opposite trades nearby or in same zone
                double entryPrice = ask;
                if(!HasOppositeTradeNearby(true, entryPrice, fvgs[i].bottom, fvgs[i].top)) {
                    OpenBuyOrderFromFVG(fvgs[i], newTradeRisk);
                    lastBuyEntryTime = TimeCurrent();
                    
                    // IMMEDIATELY update position count and block opposite trades
                    buyPositions = CountPositions(POSITION_TYPE_BUY);
                    globalBlockSELL = true; // Block all SELL entries after opening BUY
                    if(buyPositions >= MaxEntries) {
                        Print("*** MAX BUY ENTRIES REACHED (", buyPositions, "/", MaxEntries, ") - Stopping further FVG BUY entries ***");
                        break;
                    }
                } else {
                    static datetime lastBlockLog = 0;
                    if(TimeCurrent() - lastBlockLog > 10) {
                        Print("BUY FVG entry BLOCKED: Opposite trade too close or in same zone");
                        lastBlockLog = TimeCurrent();
                    }
                }
            } else if(!fvgs[i].isBullish && currentPrice <= fvgs[i].top && currentPrice >= fvgs[i].bottom) {
                double fvgMidSell = (fvgs[i].bottom + fvgs[i].top) / 2.0;
                if(FVG_RequirePullback && currentPrice < fvgMidSell) continue; // Wait for pullback into upper half
                // CRITICAL: Re-check position count BEFORE opening trade
                sellPositions = CountPositions(POSITION_TYPE_SELL);
                if(sellPositions >= MaxEntries) {
                    continue; // Skip this FVG, check next one
                }
                
                // CRITICAL: Check total risk before opening new trade
                // Use FirstTradeRisk for first trade, RiskPercent for additional
                bool isFirstTradeFVG = (sellPositions == 0);
                double currentTotalRisk = CalculateTotalRisk();
                double newTradeRisk = isFirstTradeFVG ? FirstTradeRisk : RiskPercent;
                double totalRiskAfter = currentTotalRisk + newTradeRisk;
                if(totalRiskAfter > MaxTotalRisk) {
                    continue; // Skip this FVG
                }
                
                // CRITICAL: GLOBAL HARD BLOCK - If ANY BUY exists, block ALL SELL entries
                if(globalBlockSELL) {
                    continue; // Skip this FVG - BUY position exists
                }
                
                // CRITICAL: Check for opposite trades nearby or in same zone
                double entryPrice = currentPrice;
                if(!HasOppositeTradeNearby(false, entryPrice, fvgs[i].bottom, fvgs[i].top)) {
                    OpenSellOrderFromFVG(fvgs[i], newTradeRisk);
                    lastSellEntryTime = TimeCurrent();
                    
                    // IMMEDIATELY update position count and block opposite trades
                    sellPositions = CountPositions(POSITION_TYPE_SELL);
                    globalBlockBUY = true; // Block all BUY entries after opening SELL
                    if(sellPositions >= MaxEntries) {
                        Print("*** MAX SELL ENTRIES REACHED (", sellPositions, "/", MaxEntries, ") - Stopping further FVG SELL entries ***");
                        break;
                    }
                } else {
                    static datetime lastBlockLog = 0;
                    if(TimeCurrent() - lastBlockLog > 10) {
                        Print("SELL FVG entry BLOCKED: Opposite trade too close or in same zone");
                        lastBlockLog = TimeCurrent();
                    }
                }
            }
        }
    }
    
    // Standalone trendline entries (no OB/FVG) - reduced risk
    if(UseTrendLines && TradeTrendLineStandalone && buyPositions == 0 && sellPositions == 0 && trendlineLevel > 0) {
        double currentTotalRisk = CalculateTotalRisk();
        double tlRisk = MathMin(TrendLine_StandaloneRiskPercent, MathMax(0.5, TrendLine_StandaloneRiskPercent));
        if(currentTotalRisk + tlRisk <= MaxTotalRisk) {
            if(trendlineIsSupport && !globalBlockBUY) {
                if(!HasOppositeTradeNearby(true, ask, trendlineLevel - EntryZonePips * pipValue, trendlineLevel + EntryZonePips * pipValue)) {
                    OpenBuyOrderFromTrendline(trendlineLevel, tlRisk);
                }
            } else if(!trendlineIsSupport && !globalBlockSELL) {
                if(!HasOppositeTradeNearby(false, currentPrice, trendlineLevel - EntryZonePips * pipValue, trendlineLevel + EntryZonePips * pipValue)) {
                    OpenSellOrderFromTrendline(trendlineLevel, tlRisk);
                }
            }
        }
    }
    
    // Summary: Log if no trades were taken and why
    static datetime lastSummaryLog = 0;
    if(shouldLogDebug && TimeCurrent() - lastSummaryLog > 60) {
        int totalActiveOB = 0;
        int nearPriceOB = 0;
        for(int i = 0; i < size; i++) {
            if(!orderBlocks[i].isActive) continue;
            totalActiveOB++;
            
            double zoneTop = orderBlocks[i].top;
            double zoneBottom = orderBlocks[i].bottom;
            double tolerance = EntryTouchTolerance * pipValue;
            bool nearPrice = (currentPrice >= zoneBottom - tolerance && currentPrice <= zoneTop + tolerance);
            if(nearPrice) nearPriceOB++;
        }
        
        Print("=== ENTRY CHECK SUMMARY ===");
        Print("Total Active Order Blocks: ", totalActiveOB);
        Print("Order Blocks Near Price (within ", EntryTouchTolerance, " pips): ", nearPriceOB);
        Print("Current Positions: BUY=", buyPositions, " SELL=", sellPositions);
        Print("Market Structure Trend: ", marketStruct.trend, " | RequireBOS: ", RequireBOS);
        if(totalActiveOB == 0) {
            Print("WARNING: No active order blocks detected! Check detection settings.");
        } else if(nearPriceOB == 0) {
            Print("INFO: Order blocks exist but price is not near any zones.");
        } else {
            Print("INFO: ", nearPriceOB, " order block(s) near price but entry blocked (see reasons above).");
        }
        lastSummaryLog = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Breakout entries: enter when price BREAKS last N-bar high/low (catch big moves) |
//+------------------------------------------------------------------+
bool CheckBreakoutEntries(double ask, int buyPositions, int sellPositions, bool globalBlockBUY, bool globalBlockSELL) {
    if(!UseBreakoutEntries || (globalBlockBUY && globalBlockSELL)) return false;
    int N = MathMax(5, Breakout_LookbackBars);
    if(iBars(_Symbol, PrimaryTF) < N + 3) return false;
    double rangeHigh = iHigh(_Symbol, PrimaryTF, 2);
    double rangeLow = iLow(_Symbol, PrimaryTF, 2);
    for(int i = 3; i <= N + 1; i++) {
        rangeHigh = MathMax(rangeHigh, iHigh(_Symbol, PrimaryTF, i));
        rangeLow = MathMin(rangeLow, iLow(_Symbol, PrimaryTF, i));
    }
    double c1 = iClose(_Symbol, PrimaryTF, 1);
    double o1 = iOpen(_Symbol, PrimaryTF, 1);
    double h1 = iHigh(_Symbol, PrimaryTF, 1);
    double l1 = iLow(_Symbol, PrimaryTF, 1);
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime today = StructToTime(dt);
    static datetime lastBreakoutSellDate = 0;
    static datetime lastBreakoutBuyDate = 0;
    double buf = 3.0 * pipValue;
    if(!globalBlockSELL && sellPositions < MaxEntries && c1 < o1 && c1 < rangeLow && l1 <= rangeLow + buf && lastBreakoutSellDate != today) {
        double risk = (sellPositions == 0 ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk() + risk <= MaxTotalRisk) {
            double sl = NormalizeDouble(rangeLow + Breakout_SL_Pips * pipValue, symbolDigits);
            OrderBlock ob;
            ob.top = rangeLow + 10.0 * pipValue; ob.bottom = rangeLow - 10.0 * pipValue;
            ob.time = TimeCurrent(); ob.isBullish = false; ob.isActive = true; ob.barIndex = 0; ob.tf = PrimaryTF;
            OpenSellOrder(ob, sl, risk);
            lastBreakoutSellDate = today;
            Print("*** BREAKOUT SELL: Range low broken at ", rangeLow, " | SL ", sl, " ***");
            return true;
        }
    }
    if(!globalBlockBUY && buyPositions < MaxEntries && c1 > o1 && c1 > rangeHigh && h1 >= rangeHigh - buf && lastBreakoutBuyDate != today) {
        double risk = (buyPositions == 0 ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk() + risk <= MaxTotalRisk) {
            double sl = NormalizeDouble(rangeHigh - Breakout_SL_Pips * pipValue, symbolDigits);
            OrderBlock ob;
            ob.top = rangeHigh + 10.0 * pipValue; ob.bottom = rangeHigh - 10.0 * pipValue;
            ob.time = TimeCurrent(); ob.isBullish = true; ob.isActive = true; ob.barIndex = 0; ob.tf = PrimaryTF;
            OpenBuyOrder(ob, sl, risk);
            lastBreakoutBuyDate = today;
            Print("*** BREAKOUT BUY: Range high broken at ", rangeHigh, " | SL ", sl, " ***");
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder(OrderBlock &ob, double useSL = 0, double riskPercent = 0) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate entry zone
    double entryZoneTop = ob.top;
    double entryZoneBottom = ob.bottom;
    double entryPrice = ask; // Enter at current ask
    
    // Count confluences for dynamic SL
    int confluenceCount = 1; // Base: Order Block
    // Check for M1 wick rejection (if we can detect it)
    // Check for M5 FVG overlap
    // For now, assume 2 confluences if zone is tight (M1 wick + M5 OB/FVG)
    if((entryZoneTop - entryZoneBottom) / pipValue < 10) {
        confluenceCount = 2; // Tight zone suggests multiple confluences
    }
    
    // Calculate stop loss - Dynamic or Fixed (or use provided SL for scaling)
    double sl = 0;
    if(useSL > 0) {
        // Use provided SL (for scaling entries)
        sl = useSL;
        Print("*** USING PROVIDED SL FOR SCALING ENTRY: ", sl, " ***");
    } else {
        // Calculate new SL
        sl = CalculateDynamicSL(true, entryPrice, entryZoneBottom, entryZoneTop, confluenceCount);
    }
    
    // Calculate take profit - use order block 300 pips away (for reference only)
    // We don't set TP initially - we manage it manually to allow runner
    double tp = 0;
    if(UseOB_TP) {
        tp = FindOrderBlockTP(true, entryPrice);
    }
    
    if(tp == 0) {
        // Default TP if no OB found - set very far to prevent auto-close
        tp = entryPrice + (500 * pipValue); // Very far TP, we'll manage manually
    }
    
    // Calculate position size based on risk percentage (use provided risk or default)
    double actualRisk = (riskPercent > 0) ? riskPercent : RiskPercent;
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    // Normalize prices
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    // Debug: Verify SL calculation
    double slDistancePips = (entryPrice - sl) / pipValue;
    Print("=== BUY ORDER DEBUG ===");
    Print("Symbol: ", _Symbol, " | pipValue: ", pipValue);
    Print("Entry Price: ", entryPrice, " | SL: ", sl);
    Print("SL Distance: ", (entryPrice - sl), " price = ", slDistancePips, " pips (", (UseDynamicSL ? "DYNAMIC" : "FIXED"), ")");
    if(slDistancePips > 100) Print("*** WARNING: SL distance very large (", DoubleToString(slDistancePips, 1), " pips) - risk per trade may be higher than intended! Check PointsPerPip. ***");
    if(slDistancePips > 0 && slDistancePips < 3) Print("*** WARNING: SL distance very small (", DoubleToString(slDistancePips, 1), " pips) ***");
    Print("Lot Size: ", lotSize, " | Risk: ", actualRisk, "% (", (riskPercent > 0 ? "CUSTOM" : "DEFAULT"), ") | SL Type: ", (UseDynamicSL ? "Dynamic" : "Fixed"));
    
    // Build trade comment with user tracking
    string finalComment = TradeComment;
    if(StringLen(UserName) > 0) {
        finalComment = TradeComment + "|U:" + UserName;
    }
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    bool isReentryBE = AllowReentryAfterBE && reentryAllowedBuy && (TimeCurrent() - reentryAllowedTime) <= ReentryMaxBarsAfterBE * (int)PeriodSeconds(PrimaryTF);
    if(isReentryBE) finalComment = finalComment + "|REENTRY_BE";
    
    // Open order WITHOUT TP (set to 0) - we'll manage TPs manually
    if(trade.Buy(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
        if(isReentryBE) {
            reentryAllowedBuy = false;
            Print("*** RE-ENTRY AFTER BE: BUY opened (confluence still valid) ***");
        }
        Print("*** BUY ORDER OPENED SUCCESSFULLY ***");
        Print("Entry=", entryPrice, " SL=", sl, " TP=MANUAL Lots=", lotSize);
        
        // Verify SL was set correctly
        if(position.SelectByTicket(trade.ResultOrder())) {
            double actualSL = position.StopLoss();
            Print("VERIFICATION: Actual SL set: ", actualSL, " (Expected: ", sl, ")");
            if(MathAbs(actualSL - sl) > point) {
                Print("WARNING: SL mismatch! Expected: ", sl, " Got: ", actualSL);
            }
        }
    } else {
        Print("*** BUY ORDER FAILED ***");
        Print("Error: ", trade.ResultRetcodeDescription());
        Print("Retcode: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Open Sell Order                                                  |
//+------------------------------------------------------------------+
void OpenSellOrder(OrderBlock &ob, double useSL = 0, double riskPercent = 0) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double entryZoneTop = ob.top;
    double entryZoneBottom = ob.bottom;
    double entryPrice = bid;
    
    // Count confluences for dynamic SL
    int confluenceCount = 1; // Base: Order Block
    // Check for M1 wick rejection (if we can detect it)
    // Check for M5 FVG overlap
    // For now, assume 2 confluences if zone is tight (M1 wick + M5 OB/FVG)
    if((entryZoneTop - entryZoneBottom) / pipValue < 10) {
        confluenceCount = 2; // Tight zone suggests multiple confluences
    }
    
    // Calculate stop loss - Dynamic or Fixed (or use provided SL for scaling)
    double sl = 0;
    if(useSL > 0) {
        // Use provided SL (for scaling entries)
        sl = useSL;
        Print("*** USING PROVIDED SL FOR SCALING ENTRY: ", sl, " ***");
    } else {
        // Calculate new SL
        sl = CalculateDynamicSL(false, entryPrice, entryZoneBottom, entryZoneTop, confluenceCount);
    }
    
    double tp = 0;
    if(UseOB_TP) {
        tp = FindOrderBlockTP(false, entryPrice);
    }
    
    if(tp == 0) {
        tp = entryPrice - (500 * pipValue); // Very far TP, we'll manage manually
    }
    
    // Calculate position size based on risk percentage (use provided risk or default)
    double actualRisk = (riskPercent > 0) ? riskPercent : RiskPercent;
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double pvSell = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) ? 0.1 : pipValue;
    if(slDistance < 20.0 * pvSell) slDistance = 20.0 * pvSell;
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    // Debug: Verify SL calculation
    double slDistancePips = (sl - entryPrice) / pipValue;
    Print("=== SELL ORDER DEBUG ===");
    Print("Symbol: ", _Symbol, " | pipValue: ", pipValue);
    Print("Entry Price: ", entryPrice, " | SL: ", sl);
    Print("SL Distance: ", (sl - entryPrice), " price = ", slDistancePips, " pips (", (UseDynamicSL ? "DYNAMIC" : "FIXED"), ")");
    if(slDistancePips > 100) Print("*** WARNING: SL distance very large (", DoubleToString(slDistancePips, 1), " pips) - risk per trade may be higher than intended! Check PointsPerPip. ***");
    if(slDistancePips > 0 && slDistancePips < 3) Print("*** WARNING: SL distance very small (", DoubleToString(slDistancePips, 1), " pips) ***");
    Print("Lot Size: ", lotSize, " | Risk: ", actualRisk, "% (", (riskPercent > 0 ? "CUSTOM" : "DEFAULT"), ") | SL Type: ", (UseDynamicSL ? "Dynamic" : "Fixed"));
    
    // Build trade comment with user tracking
    string finalComment = TradeComment;
    if(StringLen(UserName) > 0) {
        finalComment = TradeComment + "|U:" + UserName;
    }
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    bool isReentryBE = AllowReentryAfterBE && reentryAllowedSell && (TimeCurrent() - reentryAllowedTime) <= ReentryMaxBarsAfterBE * (int)PeriodSeconds(PrimaryTF);
    if(isReentryBE) finalComment = finalComment + "|REENTRY_BE";
    
    // Open order WITHOUT TP (set to 0) - we'll manage TPs manually
    if(trade.Sell(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
        if(isReentryBE) {
            reentryAllowedSell = false;
            Print("*** RE-ENTRY AFTER BE: SELL opened (confluence still valid) ***");
        }
        Print("*** SELL ORDER OPENED SUCCESSFULLY ***");
        Print("Entry=", entryPrice, " SL=", sl, " TP=MANUAL Lots=", lotSize);
        
        // Verify SL was set correctly
        if(position.SelectByTicket(trade.ResultOrder())) {
            double actualSL = position.StopLoss();
            Print("VERIFICATION: Actual SL set: ", actualSL, " (Expected: ", sl, ")");
            if(MathAbs(actualSL - sl) > point) {
                Print("WARNING: SL mismatch! Expected: ", sl, " Got: ", actualSL);
            }
        }
    } else {
        Print("*** SELL ORDER FAILED ***");
        Print("Error: ", trade.ResultRetcodeDescription());
        Print("Retcode: ", trade.ResultRetcode());
    }
}

//+------------------------------------------------------------------+
//| Find Order Block TP (300 pips away)                              |
//+------------------------------------------------------------------+
double FindOrderBlockTP(bool isBuy, double entryPrice) {
    int size = ArraySize(orderBlocks);
    double bestTP = 0;
    double targetDistance = OB_TP_Distance * pipValue;
    double minDistance = targetDistance * 0.8; // 80% of target
    double maxDistance = targetDistance * 1.5; // 150% of target
    
    for(int i = 0; i < size; i++) {
        if(!orderBlocks[i].isActive) continue;
        
        if(isBuy) {
            // For buy, find bearish OB above entry (opposite order block)
            if(!orderBlocks[i].isBullish) {
                double distance = orderBlocks[i].bottom - entryPrice;
                if(distance >= minDistance && distance <= maxDistance) {
                    // Prefer closest to 300 pips
                    if(bestTP == 0) {
                        bestTP = orderBlocks[i].bottom;
                    } else {
                        double currentDistance = bestTP - entryPrice;
                        double newDistance = orderBlocks[i].bottom - entryPrice;
                        // Choose the one closer to target distance
                        if(MathAbs(newDistance - targetDistance) < MathAbs(currentDistance - targetDistance)) {
                            bestTP = orderBlocks[i].bottom;
                        }
                    }
                }
            }
        } else {
            // For sell, find bullish OB below entry (opposite order block)
            if(orderBlocks[i].isBullish) {
                double distance = entryPrice - orderBlocks[i].top;
                if(distance >= minDistance && distance <= maxDistance) {
                    if(bestTP == 0) {
                        bestTP = orderBlocks[i].top;
                    } else {
                        double currentDistance = entryPrice - bestTP;
                        double newDistance = entryPrice - orderBlocks[i].top;
                        if(MathAbs(newDistance - targetDistance) < MathAbs(currentDistance - targetDistance)) {
                            bestTP = orderBlocks[i].top;
                        }
                    }
                }
            }
        }
    }
    
    return bestTP;
}

//+------------------------------------------------------------------+
//| Calculate Dynamic Stop Loss                                       |
//+------------------------------------------------------------------+
double CalculateDynamicSL(bool isBuy, double entryPrice, double zoneBottom, double zoneTop, int confluenceCount = 1) {
    // Check if dynamic SL should be used
    bool isGold = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
    bool isSilver = (StringFind(_Symbol, "XAG") >= 0 || StringFind(_Symbol, "SILVER") >= 0);
    // Use symbol-specific pip value so SL is correct. Gold: always 0.1 per pip (30 pips = 3.0 price). Silver: 0.01 or 0.1.
    double symPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double pv;
    if(isGold)
        pv = 0.1;   // Gold: 1 pip = 0.1 price always (avoid 3-pip SL when broker point=0.001)
    else if(isSilver)
        pv = (symPoint >= 0.1) ? 0.1 : 0.01;
    else
        pv = 0.1;   // Default to Gold convention
    
    // If dynamic SL disabled OR (multi-symbol: Gold-only mode and this is Silver), use fixed SL
#ifdef SMC_SYMBOL_SILVER
    if(!UseDynamicSL) {
        double baseSL = SL_Pips_Silver;
        if(baseSL < 25.0) baseSL = 25.0;
        if(isBuy) return entryPrice - (baseSL * pv);
        else      return entryPrice + (baseSL * pv);
    }
    double baseSL = SL_Pips_Silver;
    double minPips = DynamicSL_MinPips_Silver;
    double maxPips = DynamicSL_MaxPips_Silver;
#else
    if(!UseDynamicSL || (DynamicSL_GoldOnly && isSilver)) {
        double baseSL = isSilver ? SL_Pips_Silver : SL_Pips;
        if(baseSL < 25.0) baseSL = 25.0;
        if(isBuy) return entryPrice - (baseSL * pv);
        else      return entryPrice + (baseSL * pv);
    }
    double baseSL = isSilver ? SL_Pips_Silver : SL_Pips;
    double minPips = isSilver ? DynamicSL_MinPips_Silver : DynamicSL_MinPips;
    double maxPips = isSilver ? DynamicSL_MaxPips_Silver : DynamicSL_MaxPips;
#endif
    double dynamicSL = 0;
    double slPips = baseSL * DynamicSL_BaseMultiplier;
    
    // Declare variables for logging (must be in function scope)
    double atrPips = 0;
    double confluenceBonus = 0;
    
    // SMART EXPANSION: Only expand SL if there's strong confluence (2+ factors) OR if structure/zone requires it
    bool shouldExpand = true;
    if(DynamicSL_SmartExpansion && confluenceCount < 2) {
        // Only use base SL if weak confluence
        shouldExpand = false;
        slPips = baseSL; // Use base SL, no expansion
    }
    
    if(shouldExpand) {
        // 1. Zone-based SL: Place SL outside the zone with buffer (ONLY if zone is significant)
        if(zoneBottom > 0 && zoneTop > 0 && zoneTop > zoneBottom) {
            double zoneSize = (zoneTop - zoneBottom) / pv; // Zone size in pips
            // Only expand if zone is significant (more than 5 pips)
            if(zoneSize > 5.0) {
                double zoneBasedSL = zoneSize + DynamicSL_ZoneBuffer; // Zone size + buffer
                if(zoneBasedSL > slPips && zoneBasedSL < maxPips) {
                    slPips = zoneBasedSL;
                }
            }
        }
        
        // 2. Structure-based SL: Place SL beyond swing high/low (ONLY if structure is clear)
        if(DynamicSL_UseStructure) {
            double structureSL = 0;
            if(isBuy) {
                // For BUY: Find swing low below entry
                double swingLow = FindSwingLow(DynamicSL_SwingLookback);
                if(swingLow > 0 && swingLow < entryPrice) {
                    double structureDistance = (entryPrice - swingLow) / pv;
                    // Only use structure SL if it's reasonable (not too far)
                    if(structureDistance > 0 && structureDistance < maxPips) {
                        structureDistance += DynamicSL_ZoneBuffer; // Add buffer beyond swing
                        if(structureDistance > slPips && structureDistance < maxPips) {
                            slPips = structureDistance;
                        }
                    }
                }
            } else {
                // For SELL: Find swing high above entry
                double swingHigh = FindSwingHigh(DynamicSL_SwingLookback);
                if(swingHigh > 0 && swingHigh > entryPrice) {
                    double structureDistance = (swingHigh - entryPrice) / pv;
                    // Only use structure SL if it's reasonable (not too far)
                    if(structureDistance > 0 && structureDistance < maxPips) {
                        structureDistance += DynamicSL_ZoneBuffer; // Add buffer beyond swing
                        if(structureDistance > slPips && structureDistance < maxPips) {
                            slPips = structureDistance;
                        }
                    }
                }
            }
        }
        
        // 3. ATR-based SL: Adjust for volatility (ONLY if volatility is high)
        atrPips = 0; // Reset to 0
        int atrHandle = iATR(_Symbol, PERIOD_CURRENT, DynamicSL_ATR_Period);
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(atrHandle, 0, 1, 1, atr) > 0) {
            double atrValue = atr[0];
            atrPips = (atrValue / pv) * DynamicSL_ATR_Multiplier;
            // For Silver, use slightly higher ATR multiplier (more volatile)
            if(isSilver) {
                atrPips *= 1.2; // Silver is 1.2x more volatile (reduced from 1.5x)
            }
            // Only use ATR SL if it's reasonable and not excessive
            if(atrPips > slPips && atrPips < maxPips) {
                slPips = atrPips;
            }
        }
        
        // 4. Confluence bonus: More confluences = bigger SL allowed (REDUCED bonus)
        if(confluenceCount >= 2) {
            confluenceBonus = DynamicSL_ConfluenceBonus * (confluenceCount - 1);
            if(confluenceBonus > 0) {
                double newSL = slPips + confluenceBonus;
                if(newSL < maxPips) {
                    slPips = newSL;
                } else {
                    slPips = maxPips; // Cap at max
                }
            }
        }
        
        // 5. WICK PROTECTION: Place SL beyond recent wicks (if enabled)
        if(UseWickProtection) {
            double wickBasedSL = 0;
            if(isBuy) {
                // For BUY: Find lowest wick low and place SL below it
                double recentWickLow = FindRecentWickLow(WickProtection_Lookback);
                if(recentWickLow > 0 && recentWickLow < entryPrice) {
                    double wickDistance = (entryPrice - recentWickLow) / pv;
                    wickBasedSL = wickDistance + WickProtection_Buffer; // Add buffer beyond wick
                    if(wickBasedSL > slPips && wickBasedSL < maxPips) {
                        slPips = wickBasedSL;
                        Print("  Wick-based SL applied: ", wickBasedSL, " pips (wick low: ", recentWickLow, ")");
                    }
                }
            } else {
                // For SELL: Find highest wick high and place SL above it
                double recentWickHigh = FindRecentWickHigh(WickProtection_Lookback);
                if(recentWickHigh > 0 && recentWickHigh > entryPrice) {
                    double wickDistance = (recentWickHigh - entryPrice) / pv;
                    wickBasedSL = wickDistance + WickProtection_Buffer; // Add buffer beyond wick
                    if(wickBasedSL > slPips && wickBasedSL < maxPips) {
                        slPips = wickBasedSL;
                        Print("  Wick-based SL applied: ", wickBasedSL, " pips (wick high: ", recentWickHigh, ")");
                    }
                }
            }
        }
        
        // 6. VOLATILITY SPIKE EXPANSION: Widen SL during recent volatility spikes
        if(UseVolatilitySpikeExpansion && IsVolatilitySpikeDetected()) {
            double expandedSL = slPips * VolatilitySpike_Multiplier;
            if(expandedSL < maxPips) {
                slPips = expandedSL;
                Print("  Volatility spike detected: SL expanded to ", slPips, " pips (", VolatilitySpike_Multiplier, "x)");
            } else {
                slPips = maxPips; // Cap at max
            }
        }
    }
    
    // 7. Apply min/max limits (Silver gets wider limits)
    if(slPips < minPips) {
        slPips = minPips;
    }
    if(slPips > maxPips) {
        slPips = maxPips;
    }
    
    // HARD FLOOR: Gold/Silver minimum 25 pips - never allow ~10 pip SL (stops getting taken out before move)
    const double ABSOLUTE_MIN_SL_PIPS_GOLD = 25.0;
    const double ABSOLUTE_MIN_SL_PIPS_SILVER = 25.0;
    double absoluteMin = isSilver ? ABSOLUTE_MIN_SL_PIPS_SILVER : ABSOLUTE_MIN_SL_PIPS_GOLD;
    if(slPips < absoluteMin) {
        Print("*** SL FLOOR: ", slPips, " pips < ", absoluteMin, " → using ", absoluteMin, " pips (min 20/25 required) ***");
        slPips = absoluteMin;
    }
    
    // Calculate final SL price
    if(isBuy) {
        dynamicSL = entryPrice - (slPips * pv);
    } else {
        dynamicSL = entryPrice + (slPips * pv);
    }
    
    Print("=== DYNAMIC SL CALCULATION ===");
    Print("Symbol: ", _Symbol, " | Entry: ", entryPrice, " | Type: ", (isBuy ? "BUY" : "SELL"));
    Print("Zone: ", zoneBottom, " - ", zoneTop, " | Confluences: ", confluenceCount);
    Print("Calculated SL: ", dynamicSL, " (", slPips, " pips)");
#ifdef SMC_SYMBOL_SILVER
    Print("  Base SL: ", SL_Pips_Silver, " pips");
#else
    Print("  Base SL: ", (isSilver ? SL_Pips_Silver : SL_Pips), " pips");
#endif
    Print("  Zone-based: ", ((zoneTop - zoneBottom) / pv + DynamicSL_ZoneBuffer), " pips");
    Print("  ATR-based: ", atrPips, " pips");
    Print("  Confluence bonus: ", confluenceBonus, " pips");
    if(UseWickProtection) Print("  Wick protection: ENABLED");
    if(UseVolatilitySpikeExpansion && IsVolatilitySpikeDetected()) Print("  Volatility spike: DETECTED");
    Print("  Min/Max: ", minPips, "/", maxPips, " pips");
    
    return dynamicSL;
}

//+------------------------------------------------------------------+
//| Get pip value for a symbol (for multi-symbol position management)  |
//+------------------------------------------------------------------+
double GetPipValueForSymbol(string sym) {
    string s = sym;
    StringToUpper(s);
    if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
    // Silver: 1 pip = 0.01 always (2-digit 81.44 or 3-digit 81.442 - second decimal is pip)
    if(StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0) return 0.01;
    return 0.1;
}

//+------------------------------------------------------------------+
//| Find Swing Low                                                    |
//+------------------------------------------------------------------+
double FindSwingLow(int lookback) {
    double lowest = 0;
    int lowestBar = 0;
    
    for(int i = 1; i <= lookback; i++) {
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        if(lowest == 0 || low < lowest) {
            lowest = low;
            lowestBar = i;
        }
    }
    
    // Verify it's actually a swing (lower than neighbors)
    if(lowestBar > 0 && lowestBar < lookback) {
        double prevLow = iLow(_Symbol, PERIOD_CURRENT, lowestBar + 1);
        double nextLow = iLow(_Symbol, PERIOD_CURRENT, lowestBar - 1);
        if(lowest < prevLow && lowest < nextLow) {
            return lowest;
        }
    }
    
    return lowest;
}

//+------------------------------------------------------------------+
//| Find Swing High                                                   |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookback) {
    double highest = 0;
    int highestBar = 0;
    
    for(int i = 1; i <= lookback; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        if(highest == 0 || high > highest) {
            highest = high;
            highestBar = i;
        }
    }
    
    // Verify it's actually a swing (higher than neighbors)
    if(highestBar > 0 && highestBar < lookback) {
        double prevHigh = iHigh(_Symbol, PERIOD_CURRENT, highestBar + 1);
        double nextHigh = iHigh(_Symbol, PERIOD_CURRENT, highestBar - 1);
        if(highest > prevHigh && highest > nextHigh) {
            return highest;
        }
    }
    
    return highest;
}

//+------------------------------------------------------------------+
//| Find Recent Wick Low (for BUY SL protection)                    |
//+------------------------------------------------------------------+
double FindRecentWickLow(int lookback) {
    double lowestWick = 0;
    
    for(int i = 1; i <= lookback; i++) {
        double low = iLow(_Symbol, PERIOD_CURRENT, i);
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        double open = iOpen(_Symbol, PERIOD_CURRENT, i);
        
        // Calculate wick size (lower wick for bearish, full wick for doji)
        double bodyBottom = MathMin(open, close);
        double wickSize = bodyBottom - low; // Lower wick in points
        
        // Track the lowest wick low
        if(lowestWick == 0 || low < lowestWick) {
            lowestWick = low;
        }
    }
    
    return lowestWick;
}

//+------------------------------------------------------------------+
//| Find Recent Wick High (for SELL SL protection)                  |
//+------------------------------------------------------------------+
double FindRecentWickHigh(int lookback) {
    double highestWick = 0;
    
    for(int i = 1; i <= lookback; i++) {
        double high = iHigh(_Symbol, PERIOD_CURRENT, i);
        double close = iClose(_Symbol, PERIOD_CURRENT, i);
        double open = iOpen(_Symbol, PERIOD_CURRENT, i);
        
        // Calculate wick size (upper wick for bullish, full wick for doji)
        double bodyTop = MathMax(open, close);
        double wickSize = high - bodyTop; // Upper wick in points
        
        // Track the highest wick high
        if(highestWick == 0 || high > highestWick) {
            highestWick = high;
        }
    }
    
    return highestWick;
}

//+------------------------------------------------------------------+
//| Check if Recent Volatility Spike Detected                       |
//+------------------------------------------------------------------+
bool IsVolatilitySpikeDetected() {
    if(!UseVolatilitySpikeExpansion) return false;
    
    int atrHandle = iATR(_Symbol, PERIOD_CURRENT, DynamicSL_ATR_Period);
    double atr[];
    ArraySetAsSeries(atr, true);
    
    // Need at least VolatilitySpike_Bars + 5 bars for comparison
    int barsNeeded = VolatilitySpike_Bars + 5;
    if(CopyBuffer(atrHandle, 0, 1, barsNeeded, atr) < barsNeeded) return false;
    
    // Calculate average ATR of recent bars (last VolatilitySpike_Bars)
    double recentATR = 0;
    for(int i = 0; i < VolatilitySpike_Bars; i++) {
        recentATR += atr[i];
    }
    recentATR /= VolatilitySpike_Bars;
    
    // Calculate average ATR of older bars (for comparison)
    double olderATR = 0;
    for(int i = VolatilitySpike_Bars; i < barsNeeded - 1; i++) {
        olderATR += atr[i];
    }
    olderATR /= (barsNeeded - VolatilitySpike_Bars - 1);
    
    // Check if recent ATR is significantly higher (spike detected)
    if(olderATR > 0) {
        double atrRatio = recentATR / olderATR;
        return (atrRatio >= 1.3); // 30% increase = spike
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if Large Wick Detected (for quick rejection check)        |
//+------------------------------------------------------------------+
bool HasLargeWick(bool isBuy) {
    if(!UseQuickRejectionCheck) return false;
    
    // Check current bar (bar 0) for large wick
    double open = iOpen(_Symbol, PERIOD_CURRENT, 0);
    double close = iClose(_Symbol, PERIOD_CURRENT, 0);
    double high = iHigh(_Symbol, PERIOD_CURRENT, 0);
    double low = iLow(_Symbol, PERIOD_CURRENT, 0);
    
    double bodyTop = MathMax(open, close);
    double bodyBottom = MathMin(open, close);
    
    if(isBuy) {
        // For BUY: Check lower wick (rejection from below)
        double lowerWick = bodyBottom - low;
        double lowerWickPips = lowerWick / pipValue;
        return (lowerWickPips >= QuickRejection_WickSize);
    } else {
        // For SELL: Check upper wick (rejection from above)
        double upperWick = high - bodyTop;
        double upperWickPips = upperWick / pipValue;
        return (upperWickPips >= QuickRejection_WickSize);
    }
}

//+------------------------------------------------------------------+
//| Check if position has big SL and return its SL level            |
//+------------------------------------------------------------------+
double GetPositionSL(bool isBuy, double &slPips) {
    slPips = 0;
    double positionSL = 0;
    bool foundBigSL = false;
    
    for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
        if(!position.SelectByIndex(pos)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type();
        bool isSameDirection = (isBuy && posType == POSITION_TYPE_BUY) || (!isBuy && posType == POSITION_TYPE_SELL);
        
        if(isSameDirection) {
            double entryPrice = position.PriceOpen();
            double sl = position.StopLoss();
            
            if(sl > 0) {
                double currentSLPips = 0;
                if(isBuy) {
                    currentSLPips = (entryPrice - sl) / pipValue;
                } else {
                    currentSLPips = (sl - entryPrice) / pipValue;
                }
                
                // Check if this SL is big enough and larger than any we've found
                if(currentSLPips >= BigSL_Threshold && currentSLPips > slPips) {
                    slPips = currentSLPips;
                    positionSL = sl;
                    foundBigSL = true;
                }
            }
        }
    }
    
    return positionSL;
}

//+------------------------------------------------------------------+
//| Count scaling entries for a position with big SL               |
//+------------------------------------------------------------------+
int CountScalingEntries(double referenceSL) {
    int count = 0;
    double tolerance = 10 * point; // 10 points tolerance for SL matching
    
    for(int pos = PositionsTotal() - 1; pos >= 0; pos--) {
        if(!position.SelectByIndex(pos)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        double sl = position.StopLoss();
        if(sl > 0 && MathAbs(sl - referenceSL) <= tolerance) {
            count++;
        }
    }
    
    return count;
}

//+------------------------------------------------------------------+
//| Calculate Total Risk of All Open Positions                       |
//+------------------------------------------------------------------+
double CalculateTotalRisk() {
    double totalRisk = 0.0;
    double currentBalance = account.Balance();
    if(currentBalance <= 0) return 0.0;
    
    // CRITICAL: Only count OPEN positions (PositionsTotal() already filters closed ones)
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        // Position is open, calculate its risk
        double openPrice = position.PriceOpen();
        double sl = position.StopLoss();
        double volume = position.Volume();
        
        if(sl > 0) {
            double slDistance = MathAbs(openPrice - sl);
            if(slDistance > 0) {
                double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                double riskAmount = (slDistance / tickSize) * tickValue * volume;
                double riskPercent = (riskAmount / currentBalance) * 100.0;
                totalRisk += riskPercent;
            }
        }
    }
    
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Open Buy from FVG                                                |
//+------------------------------------------------------------------+
void OpenBuyOrderFromFVG(FVG &fvg, double riskPercent = 0) {
    // Count confluences for dynamic SL
    int confluenceCount = 1; // Base: FVG
    // Check for M1 wick rejection (if we can detect it)
    // Check for M5 FVG overlap
    // For now, assume 2 confluences if zone is tight (M1 wick + M5 FVG)
    double zoneSize = (fvg.top - fvg.bottom) / pipValue;
    if(zoneSize < 10) {
        confluenceCount = 2; // Tight zone suggests multiple confluences
    }
    
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double entryPrice = ask;
    // Calculate SL - Dynamic or Fixed
    double sl = CalculateDynamicSL(true, entryPrice, fvg.bottom, fvg.top, confluenceCount);
    
    // Calculate position size based on risk percentage (use provided risk or default)
    double actualRisk = (riskPercent > 0) ? riskPercent : RiskPercent;
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    
    // Build trade comment with user tracking
    string finalComment = TradeComment + "_FVG";
    if(StringLen(UserName) > 0) {
        finalComment = finalComment + "|U:" + UserName;
    }
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    
    // Open without TP - manage manually
    double slDistancePips = (entryPrice - sl) / pipValue;
    if(trade.Buy(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
        Print("BUY FVG order opened: Entry=", entryPrice, " SL=", sl, " (", slDistancePips, " pips ", (UseDynamicSL ? "DYNAMIC" : "FIXED"), ") TP=MANUAL");
    } else {
        Print("BUY FVG order failed: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Open Sell from FVG                                               |
//+------------------------------------------------------------------+
void OpenSellOrderFromFVG(FVG &fvg, double riskPercent = 0) {
    // Count confluences for dynamic SL
    int confluenceCount = 1; // Base: FVG
    double zoneSize = (fvg.top - fvg.bottom) / pipValue;
    if(zoneSize < 10) {
        confluenceCount = 2; // Tight zone suggests multiple confluences
    }
    
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entryPrice = bid;
    // Calculate SL - Dynamic or Fixed
    double sl = CalculateDynamicSL(false, entryPrice, fvg.bottom, fvg.top, confluenceCount);
    
    // Calculate position size based on risk percentage (use provided risk or default)
    double actualRisk = (riskPercent > 0) ? riskPercent : RiskPercent;
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double pvSell = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) ? 0.1 : pipValue;
    if(slDistance < 20.0 * pvSell) slDistance = 20.0 * pvSell;
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    
    // Build trade comment with user tracking
    string finalComment = TradeComment + "_FVG";
    if(StringLen(UserName) > 0) {
        finalComment = finalComment + "|U:" + UserName;
    }
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    
    // Open without TP - manage manually
    double slDistancePips = (sl - entryPrice) / pipValue;
    if(trade.Sell(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
        Print("SELL FVG order opened: Entry=", entryPrice, " SL=", sl, " (", slDistancePips, " pips ", (UseDynamicSL ? "DYNAMIC" : "FIXED"), ") TP=MANUAL");
    } else {
        Print("SELL FVG order failed: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Open Buy from Trendline (standalone - reduced risk)               |
//+------------------------------------------------------------------+
void OpenBuyOrderFromTrendline(double trendlineLevel, double riskPercent) {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double entryPrice = ask;
    double zoneBottom = trendlineLevel - EntryZonePips * pipValue;
    double zoneTop = trendlineLevel + EntryZonePips * pipValue;
    int confluenceCount = 1;
    double sl = CalculateDynamicSL(true, entryPrice, zoneBottom, zoneTop, confluenceCount);
    double actualRisk = (riskPercent > 0) ? riskPercent : TrendLine_StandaloneRiskPercent;
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    string finalComment = TradeComment + "_TL";
    if(StringLen(UserName) > 0) finalComment = finalComment + "|U:" + UserName;
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    if(trade.Buy(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
        Print("*** BUY TRENDLINE (standalone) opened: Entry=", entryPrice, " SL=", sl, " Risk=", actualRisk, "% TP=MANUAL ***");
    } else {
        Print("BUY TRENDLINE order failed: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Open Sell from Trendline (standalone - reduced risk)             |
//+------------------------------------------------------------------+
void OpenSellOrderFromTrendline(double trendlineLevel, double riskPercent) {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entryPrice = bid;
    double zoneBottom = trendlineLevel - EntryZonePips * pipValue;
    double zoneTop = trendlineLevel + EntryZonePips * pipValue;
    int confluenceCount = 1;
    double sl = CalculateDynamicSL(false, entryPrice, zoneBottom, zoneTop, confluenceCount);
    double actualRisk = (riskPercent > 0) ? riskPercent : TrendLine_StandaloneRiskPercent;
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double pvSell = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) ? 0.1 : pipValue;
    if(slDistance < 20.0 * pvSell) slDistance = 20.0 * pvSell;
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    string finalComment = TradeComment + "_TL";
    if(StringLen(UserName) > 0) finalComment = finalComment + "|U:" + UserName;
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    if(trade.Sell(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
        Print("*** SELL TRENDLINE (standalone) opened: Entry=", entryPrice, " SL=", sl, " Risk=", actualRisk, "% TP=MANUAL ***");
    } else {
        Print("SELL TRENDLINE order failed: ", trade.ResultRetcodeDescription());
    }
}

//+------------------------------------------------------------------+
//| Calculate Lot Size Based on Risk                                 |
//| SAFETY: Cap so we never risk more than intended (broker tick value can be wrong for Gold) |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slDistance) {
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(slDistance <= 0 || tickSize <= 0) return minLot;
    
    double riskPerLot = (slDistance / tickSize) * tickValue;
    if(riskPerLot <= 0) return minLot;
    
    double lotSize = riskAmount / riskPerLot;
    
    // SAFETY CAP 1: Implied risk must not exceed 1.2x intended (tickValue can be wrong on some brokers for Gold)
    double impliedRisk = lotSize * riskPerLot;
    if(impliedRisk > riskAmount * 1.2) {
        lotSize = (riskAmount * 1.2) / riskPerLot;
        Print("*** LOT SIZE CAPPED: Implied risk ", DoubleToString(impliedRisk, 2), " > 1.2x intended ", DoubleToString(riskAmount, 2), " - reduced to respect risk ***");
    }
    
    // SAFETY CAP 2: Never risk more than 12% of balance on a single trade (hard cap)
    double balance = account.Balance();
    double maxRiskDollars = balance * 0.12;
    if(lotSize * riskPerLot > maxRiskDollars) {
        lotSize = maxRiskDollars / riskPerLot;
        Print("*** LOT SIZE CAPPED: Max 12% account risk per trade (", DoubleToString(maxRiskDollars, 2), ") ***");
    }
    
    // SAFETY CAP 3: Gold/Silver - cap by real $/pip per lot (broker tickValue is often wrong for XAU/XAG)
    // Use minimum 15 pips for cap so a wrongly tiny SL cannot allow huge lots (e.g. 22 lots)
    if(pipValue > 0) {
        double slPips = slDistance / pipValue;
        double slPipsEffective = MathMax(slPips, 15.0);
        string sym = _Symbol;
        bool isGold = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);
        bool isSilver = (StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0);
        double dollarsPerPipPerLot = 0;
        if(isGold) dollarsPerPipPerLot = 10.0;   // 1 standard lot XAUUSD ≈ $10/pip
        if(isSilver) dollarsPerPipPerLot = 5.0;  // 1 lot XAGUSD ≈ $5/pip (varies)
        if(dollarsPerPipPerLot > 0 && slPipsEffective >= 1.0) {
            double maxLotsByDollarRisk = (riskAmount * 1.2) / (slPipsEffective * dollarsPerPipPerLot);
            if(maxLotsByDollarRisk > 0 && lotSize > maxLotsByDollarRisk) {
                lotSize = maxLotsByDollarRisk;
                Print("*** LOT SIZE CAPPED (Gold/Silver $/pip): max ", DoubleToString(lotSize, 2), " lots (SL ", DoubleToString(slPips, 1), " pips, cap uses min 15 pips) ***");
            }
        }
    }
    
    // Normalize to lot step
    lotSize = MathFloor(lotSize / lotStep) * lotStep;
    
    // Clamp to min/max
    if(lotSize < minLot) lotSize = minLot;
    if(lotSize > maxLot) lotSize = maxLot;
    
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
        // Find nearest support (low)
        double nearestSupport = low[0];
        for(int i = 1; i < 20; i++) {
            if(low[i] < nearestSupport) {
                nearestSupport = low[i];
            }
        }
        return nearestSupport;
    } else {
        // Find nearest resistance (high)
        double nearestResistance = high[0];
        for(int i = 1; i < 20; i++) {
            if(high[i] > nearestResistance) {
                nearestResistance = high[i];
            }
        }
        return nearestResistance;
    }
}

//+------------------------------------------------------------------+
//| Check if tracked BE position closed at BE; if so, allow re-entry  |
//+------------------------------------------------------------------+
void CheckBEClosedAndAllowReentry() {
    if(!AllowReentryAfterBE || beTrackedTicket == 0) return;
    if(position.SelectByTicket(beTrackedTicket)) return; // Position still open
    // Position closed - check history for close at BE
    datetime from = TimeCurrent() - 3600;
    if(!HistorySelect(from, TimeCurrent())) return;
    int total = HistoryDealsTotal();
    for(int i = total - 1; i >= 0; i--) {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket == 0) continue;
        if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber) continue;
        if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) continue;
        if(HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) != beTrackedTicket) continue;
        double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
        double beTolerance = 2.0 * pipValue; // Within 2 pips of entry = BE
        if(MathAbs(closePrice - beTrackedEntry) <= beTolerance) {
            if(beTrackedType == 0) { reentryAllowedBuy = true; reentryAllowedTime = TimeCurrent(); }
            else if(beTrackedType == 1) { reentryAllowedSell = true; reentryAllowedTime = TimeCurrent(); }
            Print("*** RE-ENTRY ALLOWED: Position #", beTrackedTicket, " closed at BE (", closePrice, " ~ ", beTrackedEntry, "). Confluence still valid = re-entry allowed for ", ReentryMaxBarsAfterBE, " bars. ***");
        }
        break;
    }
    beTrackedTicket = 0;
    beTrackedEntry = 0;
    beTrackedType = -1;
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManagePositions() {
    static int lastLogTime = 0;
    int currentTime = (int)TimeCurrent();
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Magic() != MagicNumber) continue;
        string posSymbol = position.Symbol();
        string posSymbolUpper = posSymbol;
        StringToUpper(posSymbolUpper);
#ifndef SMC_SYMBOL_SILVER
        if(SymbolFilter != SYMBOL_BOTH && posSymbol != _Symbol) continue; // Gold only / Silver only: manage this chart's symbol only (BE like Goldmine Edge)
#endif
        if(StringFind(posSymbolUpper, "XAU") < 0 && StringFind(posSymbolUpper, "GOLD") < 0 &&
           StringFind(posSymbolUpper, "XAG") < 0 && StringFind(posSymbolUpper, "SILVER") < 0) continue;
#ifdef SMC_SYMBOL_GOLD
        if(StringFind(posSymbolUpper, "XAU") < 0 && StringFind(posSymbolUpper, "GOLD") < 0) continue; // This EA = Gold only
#endif
#ifdef SMC_SYMBOL_SILVER
        if(StringFind(posSymbolUpper, "XAG") < 0 && StringFind(posSymbolUpper, "SILVER") < 0) continue; // This EA = Silver only
#endif
        
        ulong ticket = position.Ticket();
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type(); // capture once so log/logic never use wrong type
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentTP = position.TakeProfit();
        double currentVolume = position.Volume();
        
        bool isSilver = (StringFind(posSymbolUpper, "XAG") >= 0 || StringFind(posSymbolUpper, "SILVER") >= 0);
        double posPipValue = GetPipValueForSymbol(posSymbol);
        double posPoint = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
        int posDigits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
        double posMinLot = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN);
        double posVolumeStep = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_STEP);
        if(posVolumeStep <= 0) posVolumeStep = 0.01;
        
        double currentBID = SymbolInfoDouble(posSymbol, SYMBOL_BID);
        double currentASK = SymbolInfoDouble(posSymbol, SYMBOL_ASK);
        
        double mt5ProfitUSD = position.Profit() + position.Swap() + position.Commission();
        double tickValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
        
        double currentProfitPips = 0;
        if(posType == POSITION_TYPE_BUY)
            currentProfitPips = (currentBID - openPrice) / posPipValue;
        else
            currentProfitPips = (openPrice - currentASK) / posPipValue;
        bool isGoldSym = (StringFind(posSymbolUpper, "XAU") >= 0 || StringFind(posSymbolUpper, "GOLD") >= 0);
        if(isGoldSym && posType == POSITION_TYPE_BUY)
            currentProfitPips = (currentBID - openPrice) / 0.1; // Gold BUY: 1 pip = 0.1 so BE/TP see correct pips
        // Silver: 1 pip = 0.01
        if(isSilver) {
            if(posType == POSITION_TYPE_BUY)
                currentProfitPips = (currentBID - openPrice) / 0.01;
            else
                currentProfitPips = (openPrice - currentASK) / 0.01;
        }
#ifdef SMC_SYMBOL_GOLD
        // SMC GOLD-ONLY: force pip = 0.1 and profit from price (no broker/symbol ambiguity) - like Goldmine Edge
        posPipValue = 0.1;
        isSilver = false;
        isGoldSym = true;
        currentProfitPips = (posType == POSITION_TYPE_BUY) ? (currentBID - openPrice) / 0.1 : (openPrice - currentASK) / 0.1;
#endif
#ifdef SMC_SYMBOL_SILVER
        // SMC SILVER-ONLY: force pip = 0.01 and profit from price (no broker/symbol ambiguity) - like Goldmine Edge
        posPipValue = 0.01;
        isSilver = true;
        isGoldSym = false;
        currentProfitPips = (posType == POSITION_TYPE_BUY) ? (currentBID - openPrice) / 0.01 : (openPrice - currentASK) / 0.01;
#endif
        // SELL profit: always use fixed pip size so BE/TP never fail (Silver=0.01, Gold=0.1)
        if(posType == POSITION_TYPE_SELL)
            currentProfitPips = (openPrice - currentASK) / (isSilver ? 0.01 : 0.1);
        
        double currentPrice = (posType == POSITION_TYPE_BUY) ? currentBID : currentASK;
        
        // Auto-correct position type if MT5 reports wrong type (e.g. SELL shown as BUY after broker/MT issue)
        double pipVal = isSilver ? 0.01 : 0.1;
        double profitIfBuy  = (currentBID - openPrice) / pipVal;
        double profitIfSell = (openPrice - currentASK) / pipVal;
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
        
        int ticketIndex = GetTicketIndex(ticket);
        
        // Log position status every 10 seconds - use posType (captured once) so SELL always shows SELL
        if(currentTime - lastLogTime >= 10) {
            Print("Position #", ticket, " | Type=", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                  " | Open=", openPrice, " | Current=", currentPrice, 
                  " | Profit=", currentProfitPips, " pips | SL=", currentSL, " | TP=", currentTP);
            lastLogTime = currentTime;
        }
        
        // DEBUG: Verify calculation for SELL trades with large profit/loss
        if(isSilver && posType == POSITION_TYPE_SELL && MathAbs(currentProfitPips) > 50) {
            static datetime lastSellProfitDebug = 0;
            if(TimeCurrent() - lastSellProfitDebug >= 2) {
                Print("=== SELL TRADE PROFIT DEBUG ===");
                Print("Entry (openPrice/BID): ", openPrice, " | Current BID: ", currentBID, " | Current ASK: ", currentASK);
                Print("Calculation: (", openPrice, " - ", currentASK, ") / ", posPipValue, " = ", currentProfitPips, " pips");
                Print("MT5 Profit USD: ", mt5ProfitUSD, " | Spread: ", (currentASK - currentBID), " | pipValue: ", posPipValue);
                lastSellProfitDebug = TimeCurrent();
            }
        }
        
        static bool pipConversionLogged = false;
        if(!pipConversionLogged) {
            Print("=== PIP CONVERSION (per position) ===");
            Print("Symbol: ", posSymbol, " | Point: ", posPoint, " | PipValue: ", posPipValue);
            pipConversionLogged = true;
        }
        
        double minLot = posMinLot;
        
        // Store original volume if not already stored
        if(originalVolume[ticketIndex] == 0) {
            originalVolume[ticketIndex] = currentVolume;
        }
        
        // Calculate runner size based on original volume
        double origVol = originalVolume[ticketIndex] > 0 ? originalVolume[ticketIndex] : currentVolume;
        double runnerSizePercent = RunnerSizePercent / 100.0;
        double runnerSize = NormalizeDouble(origVol * runnerSizePercent, 2);
        // Ensure runner is at least minimum lot size
        if(runnerSize < minLot) {
            runnerSize = minLot;
        }
        bool hasRunner = (currentVolume <= runnerSize + minLot * 0.1); // Already at runner size
        
        // TP: BE at 30 pips → TP1 (25p, 25%) → TP2 (50p, 25%) → TP3 (80p, 25%) → TP4 (150p, 10%) → TP5 (300p) or Runner@1H S/R
        
        bool hasTP4 = (partialCloseLevel[ticketIndex] == 3); // TP4 is active (after TP3)
        
        // Step 1: Move to BE - use dynamic (position's SL distance) or fixed pips
#ifdef SMC_SYMBOL_SILVER
        double bePips = BreakEvenPips_Silver;
        if(UseDynamicBE && currentSL > 0 && posPipValue > 0) {
            double slDistancePips = (posType == POSITION_TYPE_BUY)
                ? (openPrice - currentSL) / posPipValue
                : (currentSL - openPrice) / posPipValue;
            if(slDistancePips > 0) {
                double dynamicBE = MathMax(slDistancePips, bePips);
                double maxBEPips = MathMax(50.0, BreakEvenPips_Silver * 2.0);
                bePips = MathMin(dynamicBE, maxBEPips);
                bePips = MathMin(bePips, BreakEvenPips_Silver);
            }
        }
#else
        double bePips = isSilver ? BreakEvenPips_Silver : BreakEvenPips;
        if(UseDynamicBE && currentSL > 0 && posPipValue > 0) {
            double slDistancePips = (posType == POSITION_TYPE_BUY)
                ? (openPrice - currentSL) / posPipValue
                : (currentSL - openPrice) / posPipValue;
            if(slDistancePips > 0) {
                double dynamicBE = MathMax(slDistancePips, bePips);
                double maxBEPips = MathMax(50.0, (isSilver ? BreakEvenPips_Silver : BreakEvenPips) * 2.0);
                bePips = MathMin(dynamicBE, maxBEPips);
                if(isSilver) bePips = MathMin(bePips, BreakEvenPips_Silver);
            }
        }
#endif
        // Silver: BE must be at least BreakEvenPips_Silver (30) - Nexus-aligned
#ifdef SMC_SYMBOL_SILVER
        bePips = MathMax(bePips, BreakEvenPips_Silver);
#endif
        
        // CRITICAL: Silver SELL - always use price-based profit (1 pip = 0.01) so BE/TP never fail
#ifdef SMC_SYMBOL_SILVER
        if(posType == POSITION_TYPE_SELL) {
            double silverSellPipsNow = (openPrice - currentASK) / 0.01;
            if(silverSellPipsNow > currentProfitPips) currentProfitPips = silverSellPipsNow;
        }
#endif
        // GOLD SELL FIX: Force BE trigger from price distance (1 pip Gold = 0.1) so BE always fires regardless of pip conversion
        bool isGold = (StringFind(posSymbolUpper, "XAU") >= 0 || StringFind(posSymbolUpper, "GOLD") >= 0);
        if(isGold && posType == POSITION_TYPE_SELL) {
            double priceProfit = openPrice - currentASK;
            const double goldPipPrice = 0.1;
            double pipsFromPrice = priceProfit / goldPipPrice;
            if(pipsFromPrice >= bePips && pipsFromPrice > 0) {
                if(pipsFromPrice > currentProfitPips)
                    currentProfitPips = pipsFromPrice; // Use price-based pips so BE/TP logic sees correct value
            }
        }
        
        // SELL BE: Same as Goldmine Edge - one Modify(ticket, openPrice, 0). Try every tick until SL at BE.
        if(posType == POSITION_TYPE_SELL) {
            // Silver: always use 0.01 per pip so BE/TP never depend on broker point/digits
            double pipSize = isGold ? 0.1 : (isSilver ? 0.01 : posPipValue);
            double sellPips = (openPrice - currentASK) / pipSize;
            if(sellPips > currentProfitPips) currentProfitPips = sellPips;
            if(sellPips >= bePips && sellPips > 0) {
                if(!tp1Hit[ticketIndex]) { tp1Hit[ticketIndex] = true; tp1HitPrice[ticketIndex] = currentPrice; }
                if(posType == POSITION_TYPE_SELL)
                    Print("*** SELL BE FLAG (Silver): ", DoubleToString(sellPips, 1), " pips >= ", bePips, " | Ticket #", ticket, " → TP enabled ***");
                if(UseBreakEven) {
                    double newSL = openPrice;
                    bool needToModify = (currentSL == 0 || newSL < currentSL);
                    if(needToModify) {
                        if(trade.PositionModify(ticket, newSL, 0)) {
                            Print("*** SELL BE SET | Ticket #", ticket, " | ", DoubleToString(sellPips, 1), " pips ***");
                        } else if(isSilver) {
                            // Silver SELL: BE = entry. If broker rejects, try 1 pip in profit (SL slightly below entry)
                            double cushionSL = NormalizeDouble(openPrice - 0.01, posDigits);
                            if(trade.PositionModify(ticket, cushionSL, 0)) {
                                Print("*** SELL BE SET (cushion -1 pip) | Ticket #", ticket, " | ", DoubleToString(sellPips, 1), " pips ***");
                            } else if(posDigits >= 3) {
                                cushionSL = NormalizeDouble(openPrice, 2);
                                if(trade.PositionModify(ticket, cushionSL, 0)) {
                                    Print("*** SELL BE SET (2 decimals) | Ticket #", ticket, " ***");
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // CRITICAL FOR SELL: Mark BE as hit as soon as profit >= bePips so TP1/TP2/TP3 always run (don't depend on SL move)
        if(currentProfitPips >= bePips && currentProfitPips > 0 && !tp1Hit[ticketIndex]) {
            tp1Hit[ticketIndex] = true;
            tp1HitPrice[ticketIndex] = currentPrice;
            if(posType == POSITION_TYPE_SELL)
                Print("*** SELL BE FLAG SET: ", currentProfitPips, " pips >= ", bePips, " → TP1/TP2/TP3 enabled (will still try to move SL) ***");
        }
        // Silver SELL: if profit in price terms is large but pips show small, pip value may be wrong - log once
        if(isSilver && posType == POSITION_TYPE_SELL && currentProfitPips > 0 && currentProfitPips < 15.0) {
            double priceProfit = openPrice - currentASK;
            double impliedPipsFrom01 = priceProfit / 0.01;
            if(impliedPipsFrom01 >= 25.0) {
                static datetime lastSilverPipWarn = 0;
                if(TimeCurrent() - lastSilverPipWarn >= 10) {
                    Print("*** SILVER SELL: Price profit ", DoubleToString(priceProfit, 4), " = ", DoubleToString(impliedPipsFrom01, 1), " pips if 1 pip=0.01 | Current pipValue=", posPipValue, " → showing ", currentProfitPips, " pips. Check GetPipValueForSymbol. ***");
                    lastSilverPipWarn = TimeCurrent();
                }
            }
        }
        
        // Attempt to move SL to BE when profit >= bePips (tp1Hit already set above so TP runs regardless)
        bool shouldTriggerBE = (currentProfitPips >= bePips && currentProfitPips > 0);
        // Force BE trigger for Gold SELL from price (so BE always fires regardless of pip conversion)
        if(isGold && posType == POSITION_TYPE_SELL) {
            double priceProfit = openPrice - currentASK;
            double pipsFromPrice = priceProfit / 0.1;
            if(pipsFromPrice >= bePips && pipsFromPrice > 0) {
                currentProfitPips = pipsFromPrice;
                shouldTriggerBE = true;
            }
        }
        // Silver SELL: force BE from price (1 pip = 0.01) so e.g. 33 pips triggers BE
        if(isSilver && posType == POSITION_TYPE_SELL) {
            double silverSellPips = (openPrice - currentASK) / 0.01;
            if(silverSellPips >= bePips && silverSellPips > 0) {
                currentProfitPips = silverSellPips;
                shouldTriggerBE = true;
            }
        }
        
        // Log Silver SELL when in profit so we confirm the position is being managed
        if(isSilver && posType == POSITION_TYPE_SELL && currentProfitPips >= 15.0) {
            static datetime lastSilverSellLog = 0;
            if(TimeCurrent() - lastSilverSellLog >= 2) {
                Print(">>> SILVER SELL #", ticket, " | Profit ", DoubleToString(currentProfitPips, 1), " pips | BE=", bePips, " | tp1Hit=", tp1Hit[ticketIndex], " | shouldTriggerBE=", shouldTriggerBE, " <<<");
                lastSilverSellLog = TimeCurrent();
            }
        }
        
        // Silver: only block BE if profit in pips is clearly below trigger (avoid blocking due to wrong pip value)
        if(isSilver && shouldTriggerBE && posPipValue > 0 && currentProfitPips < bePips - 2.0) {
            shouldTriggerBE = false;
        }
        
        // CRITICAL FIX FOR SELL TRADES: Use fixed pip size so BE/TP never fail (never use posPipValue for SELL)
        if(posType == POSITION_TYPE_SELL) {
            double sellPipSize = isSilver ? 0.01 : 0.1;
            double sellProfitCheck = (openPrice - currentASK) / sellPipSize;
            if(sellProfitCheck != currentProfitPips) currentProfitPips = sellProfitCheck;
            if(!shouldTriggerBE && currentProfitPips >= bePips && !tp1Hit[ticketIndex]) {
                shouldTriggerBE = true;
            }
        }
        
        // ENHANCED LOGGING FOR SELL TRADES: Log every time profit is above 10 pips
        if(posType == POSITION_TYPE_SELL && currentProfitPips >= 10.0) {
            static datetime lastSellBELog = 0;
            if(TimeCurrent() - lastSellBELog >= 3) {
                Print("=== SELL TRADE BE STATUS CHECK ===");
                Print("Ticket: ", ticket, " | Entry: ", openPrice, " | Current ASK: ", currentASK, " | Current BID: ", currentBID);
                Print("Profit: ", currentProfitPips, " pips | BE Trigger: ", bePips, " pips | tp1Hit: ", tp1Hit[ticketIndex]);
                Print("shouldTriggerBE: ", shouldTriggerBE, " | UseBreakEven: ", UseBreakEven);
                Print("Current SL: ", currentSL, " | Entry: ", openPrice, " | SL Distance: ", (currentSL > 0 ? DoubleToString((currentSL - openPrice) / posPipValue, 2) : "N/A"), " pips");
                lastSellBELog = TimeCurrent();
            }
        }
        
        // Enhanced logging for Silver trades - log every 2 seconds when profit > 5 pips OR for SELL trades
        if(isSilver && (currentProfitPips > 5 || posType == POSITION_TYPE_SELL)) {
            static datetime lastSilverBELog = 0;
            if(TimeCurrent() - lastSilverBELog >= 2) {
                double bidPrice = SymbolInfoDouble(posSymbol, SYMBOL_BID);
                double askPrice = SymbolInfoDouble(posSymbol, SYMBOL_ASK);
                
                Print("=== SILVER TRADE DETAILED CHECK ===");
                Print("Ticket: ", ticket, " | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
                
                if(posType == POSITION_TYPE_BUY) {
                    Print("BUY Trade - Entry (ASK): ", openPrice, " | Current BID: ", bidPrice, " | Current ASK: ", askPrice);
                    Print("Price diff (BID - Entry): ", (bidPrice - openPrice), " | Profit: ", currentProfitPips, " pips");
                } else {
                    Print("SELL Trade - Entry (BID): ", openPrice, " | Current BID: ", bidPrice, " | Current ASK: ", askPrice);
                    Print("Price diff (Entry - ASK): ", (openPrice - askPrice), " | Profit: ", currentProfitPips, " pips");
                    Print("For SELL: Price going DOWN = profit, Price going UP = loss");
                }
                
                Print("Current SL: ", currentSL, " | pipValue: ", posPipValue, " | point: ", posPoint);
                Print("Profit: ", currentProfitPips, " pips | BE Trigger: ", bePips, " pips | tp1Hit: ", tp1Hit[ticketIndex]);
                Print("Should trigger BE: ", shouldTriggerBE, " | TP1: ", TP1_Pips, " | TP2: ", TP2_Pips, " | TP3: ", TP3_Pips);
                lastSilverBELog = TimeCurrent();
            }
        }
        
        // BUY only: main BE block. SELL is handled above by dedicated block (Goldmine Edge logic) - skip here to avoid any interference
        if(shouldTriggerBE && posType == POSITION_TYPE_BUY) {
            
            Print("*** ", bePips, " pips profit reached! Moving to BE *** Ticket #", ticket, 
                  " | Profit: ", currentProfitPips, " pips | Symbol: ", posSymbol, " | BE Trigger: ", bePips, " pips");
            Print("  Entry Price: ", openPrice, " | Current Price: ", currentPrice, " | Current SL: ", currentSL);
            Print("  Price Difference: ", (currentPrice - openPrice), " | pipValue: ", posPipValue, " | Calculated Pips: ", currentProfitPips);
            
            if(UseBreakEven) {
                double newSL;
                // BUY: BE at entry. SELL: BE at entry for BOTH Gold and Silver (SL must be above price; entry is valid when in profit)
                if(posType == POSITION_TYPE_BUY)
                    newSL = NormalizeDouble(openPrice, posDigits);
                else
                    // SELL (Gold + Silver): move SL to entry = break-even. Was wrong: openPrice - bePips (below entry) → broker rejects
                    newSL = NormalizeDouble(openPrice, posDigits);
                bool needToModify = false;

                int stopsLevelPts = (int)SymbolInfoInteger(posSymbol, SYMBOL_TRADE_STOPS_LEVEL);
                int freezeLevelPts = (int)SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
                int minLevelPts = (stopsLevelPts > freezeLevelPts ? stopsLevelPts : freezeLevelPts);
                double minLevelPrice = (double)minLevelPts * posPoint;

                // Stop/freeze: only delay BUY if BE would be above allowed. For SELL never skip - try BE and retry with cushion if broker rejects (like Goldmine Edge).
                if(minLevelPts > 0 && posType == POSITION_TYPE_BUY) {
                    double maxAllowedSL = NormalizeDouble(currentPrice - minLevelPrice, posDigits);
                    if(newSL > maxAllowedSL) {
                        Print("BE DELAYED: stop/freeze level too high. Need more profit.",
                              " | BE=", newSL, " | maxAllowedSL=", maxAllowedSL);
                        continue;
                    }
                }
                
                if(posType == POSITION_TYPE_BUY) {
                    // For BUY: newSL (BE) should be higher than current SL (or currentSL is 0)
                    if(newSL > currentSL || currentSL == 0) {
                        needToModify = true;
                    }
                } else {
                    // For SELL: always try to move to BE if SL is above entry (match Goldmine Edge - no skip)
                    double pvSELL = isGold ? 0.1 : posPipValue;
                    double slDistanceFromEntry = (currentSL > 0) ? (currentSL - openPrice) / pvSELL : 999.0;
                    bool alreadyAtBE = (currentSL > 0 && currentSL <= openPrice + 0.5 * pvSELL && currentSL >= openPrice - 0.5 * pvSELL);

                    if(alreadyAtBE) {
                        tp1Hit[ticketIndex] = true;
                        tp1HitPrice[ticketIndex] = currentPrice;
                        Print("*** SELL BE ALREADY SET: SL at ", currentSL, " (", DoubleToString(slDistanceFromEntry, 2), " pips from entry) ***");
                    } else if(newSL >= currentSL && currentSL > 0) {
                        tp1Hit[ticketIndex] = true;
                        tp1HitPrice[ticketIndex] = currentPrice;
                    } else {
                        // SL above entry or no SL - always attempt modify (like Goldmine Edge)
                        needToModify = true;
                        Print("*** SELL: Moving SL to BE at entry (current SL ", DoubleToString(slDistanceFromEntry, 1), " pips above) ***");
                    }
                }
                
                if(needToModify) {
                    Print("  Attempting to move SL to BE | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                          " | Current SL: ", currentSL, " | New SL: ", newSL, " | Entry: ", openPrice);
                    Print("  Profit: ", currentProfitPips, " pips | BE Trigger: ", bePips, " pips | Symbol: ", posSymbol);
                    Print("  pipValue: ", posPipValue, " | point: ", posPoint, " | isSilver: ", isSilver);
                    
                    // Try to modify SL - retry up to 8 times if it fails (broker stop level)
                    bool slMoved = false;
                    int maxRetries = 8;
                    for(int retry = 0; retry < maxRetries; retry++) {
                        if(!position.SelectByTicket(ticket)) break; // Position gone
                        double slToTry = newSL;
                        // SELL: try exact entry first (retry 0), then entry+1pip, +2pip... (like Goldmine Edge, then cushion if broker rejects)
                        if(posType == POSITION_TYPE_SELL) {
                            double pv = isGold ? 0.1 : posPipValue;
                            if(retry == 0)
                                slToTry = NormalizeDouble(openPrice, posDigits); // First try exact BE like Goldmine Edge
                            else
                                slToTry = NormalizeDouble(openPrice + (double)retry * pv, posDigits);
                        }
                        if(trade.PositionModify(ticket, slToTry, 0)) {
                            slMoved = true;
                            tp1Hit[ticketIndex] = true;
                            tp1HitPrice[ticketIndex] = currentPrice;
                            if(AllowReentryAfterBE) {
                                beTrackedTicket = ticket;
                                beTrackedEntry = openPrice;
                                beTrackedType = (posType == POSITION_TYPE_BUY) ? 0 : 1;
                            }
                            Print("*** SUCCESS: SL moved to break-even: ", slToTry, " ***");
                            Print("  Profit at BE: ", currentProfitPips, " pips | Symbol: ", posSymbol, " | BE Trigger: ", bePips, " pips");
                            break;
                        } else {
                            Print("  Retry ", (retry + 1), "/", maxRetries, ": Failed to move SL. Error: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
                            Print("  Ticket: ", ticket, " | Current SL: ", currentSL, " | Target SL: ", slToTry, " | Entry: ", openPrice);
                            if(retry < maxRetries - 1) Sleep(200);
                        }
                    }
                    
                    if(!slMoved) {
                        Print("*** ERROR: Failed to move SL to BE after ", maxRetries, " attempts! ***");
                        Print("  Ticket: ", ticket, " | Symbol: ", posSymbol, " | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"));
                        Print("  Current SL: ", currentSL, " | Target SL: ", newSL, " | Entry: ", openPrice);
                        Print("  Profit: ", currentProfitPips, " pips | BE Trigger: ", bePips, " pips");
                        Print("  stopsLevelPts=", stopsLevelPts, " freezeLevelPts=", freezeLevelPts);
                        Print("  pipValue=", posPipValue, " | point=", posPoint, " | isSilver=", isSilver);
                        
                        // CRITICAL FIX FOR SELL TRADES: Even if SL move failed, mark BE as hit so TP can proceed
                        // This prevents SELL trades from missing TP1/TP2/TP3 because BE wasn't set
                        if(posType == POSITION_TYPE_SELL && currentProfitPips >= bePips) {
                            tp1Hit[ticketIndex] = true;
                            tp1HitPrice[ticketIndex] = currentPrice;
                            Print("*** SELL TRADE: BE marked as hit despite SL move failure - TP system can now proceed ***");
                            Print("  This ensures TP1/TP2/TP3 will trigger even if BE SL couldn't be moved");
                        }
                    }
                } else {
                    // If SL already at/through BE, mark as hit so TP system can proceed.
                    tp1Hit[ticketIndex] = true;
                    tp1HitPrice[ticketIndex] = currentPrice;
                    Print("  BE already set (SL at or better than entry) | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"),
                          " | Current SL: ", currentSL, " | Entry: ", openPrice, " | BE: ", newSL);
                }
            } else {
                // BE disabled, but we still want to progress TP system.
                tp1Hit[ticketIndex] = true;
                tp1HitPrice[ticketIndex] = currentPrice;
            }
        }
        
        // Step 2: New TP System - all levels from inputs (TP1_Pips, TP2_Pips, etc.). BE from BreakEvenPips/BreakEvenPips_Silver.
        if(currentProfitPips > 0) {
            // When profit >= BE threshold, mark BE as hit so TP1 can run (TP1 requires tp1Hit). Do NOT close position here.
            if(!tp1Hit[ticketIndex] && currentProfitPips >= bePips) {
                tp1Hit[ticketIndex] = true;
                tp1HitPrice[ticketIndex] = currentPrice;
                if(posType == POSITION_TYPE_SELL) {
                    Print("*** SELL: BE marked at ", currentProfitPips, " pips - TP1/TP2/TP3 can now run ***");
                } else {
                    Print("*** BUY: BE marked at ", currentProfitPips, " pips - TP1/TP2/TP3 can now run ***");
                }
            }
            
            // CRITICAL: For Silver, log EVERY profitable trade to diagnose TP issues
            if(isSilver && currentProfitPips > 0) {
                static datetime lastSilverTPLog = 0;
                if(TimeCurrent() - lastSilverTPLog >= 2) {
                    Print("=== SILVER TP SYSTEM CHECK ===");
                    Print("Ticket: ", ticket, " | Profit: ", currentProfitPips, " pips | tp1Hit: ", tp1Hit[ticketIndex]);
                    Print("TP Levels: TP1=", TP1_Pips, " TP2=", TP2_Pips, " TP3=", TP3_Pips, " TP5=", TP5_Pips);
                    Print("Current Level: ", partialCloseLevel[ticketIndex], " | hasRunner: ", hasRunner, " | currentVolume: ", currentVolume);
                    Print("Conditions: TP1=", (currentProfitPips >= TP1_Pips && partialCloseLevel[ticketIndex] == 0 && tp1Hit[ticketIndex]),
                          " TP2=", (currentProfitPips >= TP2_Pips && partialCloseLevel[ticketIndex] == 1 && tp1Hit[ticketIndex]),
                          " TP3=", (currentProfitPips >= TP3_Pips && partialCloseLevel[ticketIndex] == 2 && tp1Hit[ticketIndex]));
                    lastSilverTPLog = TimeCurrent();
                }
            }
            
            // CRITICAL: Log high-profit trades that aren't triggering TP
            if(isSilver && currentProfitPips >= 20 && partialCloseLevel[ticketIndex] == 0) {
                static datetime lastHighProfitLog = 0;
                if(TimeCurrent() - lastHighProfitLog >= 3) {
                    Print("*** WARNING: High profit (", currentProfitPips, " pips) but TP1 (", TP1_Pips, " pips) not triggered! ***");
                    Print("  Ticket: ", ticket, " | tp1Hit: ", tp1Hit[ticketIndex], " | currentLevel: ", partialCloseLevel[ticketIndex]);
                    Print("  TP1_Pips: ", TP1_Pips, " | currentProfitPips: ", currentProfitPips, " | Condition: ", (currentProfitPips >= TP1_Pips));
                    Print("  hasRunner: ", hasRunner, " | currentVolume: ", currentVolume, " | origVol: ", origVol);
                    lastHighProfitLog = TimeCurrent();
                }
            }
            
            int currentLevel = partialCloseLevel[ticketIndex];
            
            // CRITICAL: Remove hasRunner check - TP should work even if we're at runner size
            // Only skip if we're actually at the minimum runner size (can't close more)
            bool canCloseMore = (currentVolume > runnerSize + minLot * 0.5);
            
            // TP1: 10 pips - Close 25%
            // CRITICAL: TP1 requires tp1Hit to be true (either BE was moved, or auto-marked)
            // FIXED: For SELL trades, ensure BE is marked even if SL move failed
            if(currentLevel == 0 && currentProfitPips >= TP1_Pips && tp1Hit[ticketIndex] && canCloseMore) {
                // TP1: close ONLY TP1_Percent at TP1_Pips (never more than designated %)
                double closeVolume = NormalizeDouble(origVol * (TP1_Percent / 100.0), 2);
                double maxByInput = origVol * (TP1_Percent / 100.0) * 1.01; // strict: never exceed input %
                if(closeVolume > maxByInput) closeVolume = maxByInput;
                
                // CRITICAL: Always ensure we leave at least the runner size
                double maxCloseVolume = currentVolume - runnerSize;
                if(closeVolume > maxCloseVolume) closeVolume = maxCloseVolume;
                
                if(closeVolume < minLot) closeVolume = minLot;
                if(origVol < 0.1) {
                    double safeClosePercent = MathMin(TP1_Percent, 20.0);
                    closeVolume = NormalizeDouble(origVol * (safeClosePercent / 100.0), 2);
                    if(closeVolume < minLot) closeVolume = minLot;
                }
                // Cap at designated % and at 50% of current (safety) - never take more than TP1_Percent
                double maxAllowedClose = MathMin(currentVolume * 0.50, maxByInput);
                if(closeVolume > maxAllowedClose) closeVolume = maxAllowedClose;
                double remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < runnerSize) {
                    closeVolume = currentVolume - runnerSize;
                    remainingVolume = runnerSize;
                }
                // NEVER partial-close if it would amount to full close (some brokers close full on round)
                double maxSafeClose = MathMin(currentVolume * 0.45, currentVolume - minLot * 2.0);
                if(closeVolume > maxSafeClose) closeVolume = maxSafeClose;
                if(closeVolume >= currentVolume - minLot) {
                    Print("*** TP1 SKIP: closeVolume would effectively full-close (currentVolume ", currentVolume, ") ***");
                    continue;
                }
                // Normalize to broker volume step (fix "invalid volume" error on partial close)
                closeVolume = MathRound(closeVolume / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(closeVolume, 2);
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume - minLot) closeVolume = MathFloor((currentVolume - minLot) / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2);
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < minLot) continue;
                // CRITICAL: Never full-close on "partial" - some brokers close full if closeVolume is too near currentVolume
                if(closeVolume >= currentVolume - posVolumeStep || remainingVolume < minLot * 2.0) {
                    Print("*** TP1 SKIP: closeVolume ", closeVolume, " would effectively full-close (currentVol ", currentVolume, " step ", posVolumeStep, ") - skip to avoid full TP at ~50 pips ***");
                    continue;
                }
                
                // EXTRA SAFETY: Log before closing to verify calculation
                if(posType == POSITION_TYPE_SELL) {
                    Print("*** SELL TP1 CLOSE CALCULATION ***");
                    Print("  Original Volume: ", origVol, " | Current Volume: ", currentVolume);
                    Print("  TP1_Percent: ", TP1_Percent, "% | Calculated Close: ", closeVolume);
                    Print("  Runner Size: ", runnerSize, " | Remaining: ", remainingVolume);
                    Print("  Profit: ", currentProfitPips, " pips | tp1Hit: ", tp1Hit[ticketIndex]);
                }
                
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    // CRITICAL: Verify position still exists before attempting to close
                    if(!position.SelectByTicket(ticket)) {
                        Print("*** TP1 SKIPPED: Position #", ticket, " no longer exists (already closed) ***");
                        continue; // Move to next position
                    }
                    
                    // Check if position is frozen
                    if(SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL) > 0) {
                        double freezeLevel = SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL) * posPoint;
                        double priceDistance = MathAbs(currentPrice - openPrice);
                        if(priceDistance <= freezeLevel) {
                            Print("*** TP1 SKIPPED: Position #", ticket, " is frozen (within freeze level) - will retry next tick ***");
                            continue; // Skip this tick, will retry next time
                        }
                    }
                    
                    // Retry up to 3 times if it fails
                    bool closed = false;
                    for(int retry = 0; retry < 3; retry++) {
                        // Re-check position exists before each retry
                        if(!position.SelectByTicket(ticket)) {
                            Print("*** TP1: Position #", ticket, " was closed during retry (retry ", (retry + 1), "/3) ***");
                            closed = true; // Position already closed, mark as success
                            break;
                        }
                        
                        if(trade.PositionClosePartial(ticket, closeVolume)) {
                            partialCloseLevel[ticketIndex] = 1;
                            Print("*** TP1 HIT: Closed ", closeVolume, " lots (", TP1_Percent, "% of ", origVol, " lots) at ", TP1_Pips, " pips profit | Remaining: ", remainingVolume, " lots ***");
                            closed = true;
                            break;
                        } else {
                            string errorDesc = trade.ResultRetcodeDescription();
                            Print("TP1 Close failed (retry ", (retry + 1), "/3): ", errorDesc);
                            
                            // If position is already closed or frozen, don't retry
                            if(StringFind(errorDesc, "position closed") >= 0 || StringFind(errorDesc, "closed") >= 0) {
                                Print("*** TP1: Position already closed - marking as success ***");
                                closed = true;
                                break;
                            }
                            if(StringFind(errorDesc, "frozen") >= 0) {
                                Print("*** TP1: Position frozen - will retry next tick ***");
                                break; // Don't mark as closed, will retry next tick
                            }
                            
                            if(retry < 2) Sleep(100);
                        }
                    }
                    if(!closed) {
                        Print("*** ERROR: TP1 failed to close after 3 attempts! Profit: ", currentProfitPips, " pips ***");
                    }
                } else {
                    Print("*** TP1 SKIPPED: closeVolume=", closeVolume, " minLot=", minLot, " remainingVolume=", remainingVolume, " currentVolume=", currentVolume);
                }
            }
            // TP2: 20 pips - Close 20%
            else if(currentLevel == 1 && currentProfitPips >= TP2_Pips && canCloseMore) {
                double closeVolume = NormalizeDouble(origVol * (TP2_Percent / 100.0), 2);
                double maxByInput = origVol * (TP2_Percent / 100.0) * 1.01;
                if(closeVolume > maxByInput) closeVolume = maxByInput;
                double remainingVolume = currentVolume - closeVolume;
                
                // CRITICAL: Always ensure we leave at least the runner size
                double maxCloseVolume = currentVolume - runnerSize;
                if(closeVolume > maxCloseVolume) {
                    closeVolume = maxCloseVolume; // Don't close more than we can (must leave runner)
                }
                
                // Ensure closeVolume is at least minLot; cap at 50% so we never full-close at 50 pips
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume * 0.5) closeVolume = NormalizeDouble(currentVolume * 0.5, 2);
                
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < runnerSize) {
                    closeVolume = currentVolume - runnerSize;
                    remainingVolume = runnerSize;
                }
                double maxSafeClose2 = MathMin(currentVolume * 0.45, currentVolume - minLot * 2.0);
                if(closeVolume > maxSafeClose2) closeVolume = maxSafeClose2;
                if(closeVolume >= currentVolume - minLot) {
                    Print("*** TP2 SKIP: would effectively full-close (currentVolume ", currentVolume, ") ***");
                    continue;
                }
                // Normalize to broker volume step (fix "invalid volume" error)
                closeVolume = MathRound(closeVolume / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(closeVolume, 2);
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume - minLot) closeVolume = MathFloor((currentVolume - minLot) / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2);
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < minLot) continue;
                if(closeVolume >= currentVolume - posVolumeStep || remainingVolume < minLot * 2.0) {
                    Print("*** TP2 SKIP: would effectively full-close (currentVol ", currentVolume, " step ", posVolumeStep, ") - skip ***");
                    continue;
                }
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    if(!position.SelectByTicket(ticket)) {
                        Print("*** TP2 SKIPPED: Position #", ticket, " no longer exists (already closed) ***");
                        continue; // Move to next position
                    }
                    
                    if(SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL) > 0) {
                        double freezeLevel = SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL) * posPoint;
                        double priceDistance = MathAbs(currentPrice - openPrice);
                        if(priceDistance <= freezeLevel) {
                            Print("*** TP2 SKIPPED: Position #", ticket, " is frozen - will retry next tick ***");
                            continue; // Skip this tick, will retry next time
                        }
                    }
                    
                    // Retry up to 3 times if it fails
                    bool closed = false;
                    for(int retry = 0; retry < 3; retry++) {
                        // Re-check position exists before each retry
                        if(!position.SelectByTicket(ticket)) {
                            Print("*** TP2: Position #", ticket, " was closed during retry (retry ", (retry + 1), "/3) ***");
                            closed = true; // Position already closed, mark as success
                            break;
                        }
                        
                        if(trade.PositionClosePartial(ticket, closeVolume)) {
                            partialCloseLevel[ticketIndex] = 2;
                            Print("*** TP2 HIT: Closed ", closeVolume, " lots (", TP2_Percent, "% of ", origVol, " lots) at ", TP2_Pips, " pips profit | Remaining: ", remainingVolume, " lots ***");
                            closed = true;
                            break;
                        } else {
                            string errorDesc = trade.ResultRetcodeDescription();
                            Print("TP2 Close failed (retry ", (retry + 1), "/3): ", errorDesc);
                            
                            // If position is already closed or frozen, don't retry
                            if(StringFind(errorDesc, "position closed") >= 0 || StringFind(errorDesc, "closed") >= 0) {
                                Print("*** TP2: Position already closed - marking as success ***");
                                closed = true;
                                break;
                            }
                            if(StringFind(errorDesc, "frozen") >= 0) {
                                Print("*** TP2: Position frozen - will retry next tick ***");
                                break; // Don't mark as closed, will retry next tick
                            }
                            
                            if(retry < 2) Sleep(100);
                        }
                    }
                    if(!closed) {
                        Print("*** ERROR: TP2 failed to close after 3 attempts! Profit: ", currentProfitPips, " pips ***");
                    }
                }
            }
            // TP3: at TP3_Pips - Close only TP3_Percent (designated %)
            else if(currentLevel == 2 && currentProfitPips >= TP3_Pips && canCloseMore) {
                double closeVolume = NormalizeDouble(origVol * (TP3_Percent / 100.0), 2);
                double maxByInput = origVol * (TP3_Percent / 100.0) * 1.01;
                if(closeVolume > maxByInput) closeVolume = maxByInput;
                double remainingVolume = currentVolume - closeVolume;
                
                double maxCloseVolume = currentVolume - runnerSize;
                if(closeVolume > maxCloseVolume) closeVolume = maxCloseVolume;
                
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume * 0.5) closeVolume = NormalizeDouble(currentVolume * 0.5, 2);
                
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < runnerSize) {
                    closeVolume = currentVolume - runnerSize;
                    remainingVolume = runnerSize;
                }
                double maxSafeClose3 = MathMin(currentVolume * 0.45, currentVolume - minLot * 2.0);
                if(closeVolume > maxSafeClose3) closeVolume = maxSafeClose3;
                if(closeVolume >= currentVolume - minLot) {
                    Print("*** TP3 SKIP: would effectively full-close (currentVolume ", currentVolume, ") ***");
                    continue;
                }
                // Normalize to broker volume step (fix "invalid volume" error)
                closeVolume = MathRound(closeVolume / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(closeVolume, 2);
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume - minLot) closeVolume = MathFloor((currentVolume - minLot) / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2);
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < minLot) continue;
                if(closeVolume >= currentVolume - posVolumeStep || remainingVolume < minLot * 2.0) {
                    Print("*** TP3 SKIP: would effectively full-close (currentVol ", currentVolume, " step ", posVolumeStep, ") - skip ***");
                    continue;
                }
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    if(!position.SelectByTicket(ticket)) {
                        Print("*** TP3 SKIPPED: Position #", ticket, " no longer exists (already closed) ***");
                        continue; // Move to next position
                    }
                    
                    if(SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL) > 0) {
                        double freezeLevel = SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL) * posPoint;
                        double priceDistance = MathAbs(currentPrice - openPrice);
                        if(priceDistance <= freezeLevel) {
                            Print("*** TP3 SKIPPED: Position #", ticket, " is frozen - will retry next tick ***");
                            continue; // Skip this tick, will retry next time
                        }
                    }
                    
                    // Retry up to 3 times if it fails
                    bool closed = false;
                    for(int retry = 0; retry < 3; retry++) {
                        // Re-check position exists before each retry
                        if(!position.SelectByTicket(ticket)) {
                            Print("*** TP3: Position #", ticket, " was closed during retry (retry ", (retry + 1), "/3) ***");
                            closed = true; // Position already closed, mark as success
                            break;
                        }
                        
                        if(trade.PositionClosePartial(ticket, closeVolume)) {
                            partialCloseLevel[ticketIndex] = 3;
                            Print("*** TP3 HIT: Closed ", closeVolume, " lots (", TP3_Percent, "% of ", origVol, " lots) at ", TP3_Pips, " pips profit | Remaining: ", remainingVolume, " lots ***");
                            closed = true;
                            break;
                        } else {
                            string errorDesc = trade.ResultRetcodeDescription();
                            Print("TP3 Close failed (retry ", (retry + 1), "/3): ", errorDesc);
                            
                            // If position is already closed or frozen, don't retry
                            if(StringFind(errorDesc, "position closed") >= 0 || StringFind(errorDesc, "closed") >= 0) {
                                Print("*** TP3: Position already closed - marking as success ***");
                                closed = true;
                                break;
                            }
                            if(StringFind(errorDesc, "frozen") >= 0) {
                                Print("*** TP3: Position frozen - will retry next tick ***");
                                break; // Don't mark as closed, will retry next tick
                            }
                            
                            if(retry < 2) Sleep(100);
                        }
                    }
                    if(!closed) {
                        Print("*** ERROR: TP3 failed to close after 3 attempts! Profit: ", currentProfitPips, " pips ***");
                    }
                }
            }
        }
        
        // Step 2b: TP4 - At 150 pips close 10%, leave runner (after TP1/TP2/TP3 taken)
        if(partialCloseLevel[ticketIndex] == 3 && currentProfitPips >= TP4_Pips && currentProfitPips > 0 && (currentVolume > runnerSize + minLot * 0.5)) {
            double closeVolume = NormalizeDouble(origVol * (TP4_Percent / 100.0), 2);
            if(closeVolume >= minLot && closeVolume <= currentVolume - minLot) {
                closeVolume = MathRound(closeVolume / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(closeVolume, 2);
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume - minLot) closeVolume = MathFloor((currentVolume - minLot) / posVolumeStep) * posVolumeStep;
                closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2);
                double remainingVolume = NormalizeDouble(currentVolume - closeVolume, 2);
                if(remainingVolume >= minLot) {
                    if(trade.PositionClosePartial(ticket, closeVolume)) {
                        partialCloseLevel[ticketIndex] = 4; // TP4 (150 pips) taken; runner remains
                        Print("*** TP4 HIT: Closed ", closeVolume, " lots (", TP4_Percent, "% of ", origVol, ") at ", TP4_Pips, " pips | Remaining runner (", RunnerSizePercent, "%): ", remainingVolume, " lots ***");
                    }
                }
            }
        }
        
        // Step 3: TP4 alternate - Remaining targets 1H S/R (after TP3, if enabled)
        if(hasTP4 && TP4_To1H_SR && !hasRunner && !tp5Hit[ticketIndex]) {
            double targetSR = Find1H_SupportResistance(posType == POSITION_TYPE_BUY);
            
            if(targetSR > 0) {
                bool reachedSR = false;
                if(posType == POSITION_TYPE_BUY) {
                    reachedSR = currentPrice >= targetSR - (5 * posPipValue);
                } else {
                    reachedSR = currentPrice <= targetSR + (5 * posPipValue);
                }
                
                if(reachedSR) {
                    double tp4Volume = NormalizeDouble(origVol * (TP4_Percent / 100.0), 2);
                    double closeVolume = NormalizeDouble(currentVolume - runnerSize, 2);
                    if(closeVolume >= minLot && (currentVolume - closeVolume) >= runnerSize) {
                        if(trade.PositionClosePartial(ticket, closeVolume)) {
                            Print("*** TP4 HIT at 1H S/R: Closed ", closeVolume, " lots | Remaining runner (", RunnerSizePercent, "%): ", (currentVolume - closeVolume), " lots ***");
                            partialCloseLevel[ticketIndex] = 4;
                        }
                    }
                }
            }
        }
        
        // Step 4: TP5 - Full close at user's TP5_Pips. Requires TP1/TP2/TP3 taken. Optional MinPipsBeforeFullClose floor.
        bool allowFullClose = (currentProfitPips >= TP5_Pips);
        if(MinPipsBeforeFullClose > 0 && currentProfitPips < MinPipsBeforeFullClose) allowFullClose = false;
        if(!tp5Hit[ticketIndex] && currentProfitPips >= TP5_Pips && currentProfitPips > 0 && partialCloseLevel[ticketIndex] >= 3 && allowFullClose) {
            if(trade.PositionClose(ticket)) {
                tp5Hit[ticketIndex] = true;
                partialCloseLevel[ticketIndex] = 5;
                Print("*** TP5 HIT at ", TP5_Pips, " pips: Closed runner | Full profit secured! ***");
            } else {
                Print("ERROR: Failed to close TP5 runner. Error: ", trade.ResultRetcodeDescription());
            }
        }
        
        // Step 5: Runner targets 1H S/R - full close when at runner, TP3 taken, profit >= TP3_Pips. Optional MinPipsBeforeFullClose.
        bool allowRunnerClose = (hasRunner && RunnerTo1H_SR && partialCloseLevel[ticketIndex] >= 3 && currentProfitPips >= TP3_Pips);
        if(MinPipsBeforeFullClose > 0 && currentProfitPips < MinPipsBeforeFullClose) allowRunnerClose = false;
        if(allowRunnerClose) {
            double targetSR = Find1H_SupportResistance(posType == POSITION_TYPE_BUY);
            if(targetSR > 0) {
                double pvForSR = isSilver ? 0.01 : (isGold ? 0.1 : posPipValue);
                bool reachedSR = (posType == POSITION_TYPE_BUY)
                    ? (currentPrice >= targetSR - (5 * pvForSR))
                    : (currentPrice <= targetSR + (5 * pvForSR));
                if(reachedSR) {
                    Print("*** Runner reached 1H S/R at ", targetSR, " (profit ", currentProfitPips, " pips) | Closing runner ***");
                    trade.PositionClose(ticket);
                }
            }
        }
        
        // Step 5a: Dynamic Trail - close on structure reversal only if profit already >= DynamicTrailMinPips (avoids early full close)
        if(UseDynamicTrail && UseMarketStructure && currentProfitPips >= DynamicTrailMinPips && currentProfitPips > 0 && posSymbol == _Symbol) {
            bool reversalAgainstBuy  = (posType == POSITION_TYPE_BUY  && marketStruct.trend == -1);
            bool reversalAgainstSell  = (posType == POSITION_TYPE_SELL && marketStruct.trend == 1);
            if(reversalAgainstBuy || reversalAgainstSell) {
                if(trade.PositionClose(ticket)) {
                    Print("*** Dynamic Trail: Structure reversal (trend=", marketStruct.trend, ") | Closed #", ticket, " with ", DoubleToString(currentProfitPips, 1), " pips profit ***");
                    continue;
                }
            }
        }
        
        // Step 5b: Trail SL from TrailStartPips, TrailDistancePips behind price
        if(UseTrailSL && currentProfitPips >= TrailStartPips && currentProfitPips > 0) {
            double trailPipValue = isSilver ? 0.01 : (isGold ? 0.1 : posPipValue);
            double newSL = 0;
            if(posType == POSITION_TYPE_BUY) {
                newSL = NormalizeDouble(currentPrice - TrailDistancePips * trailPipValue, posDigits);
                if(newSL > openPrice && (currentSL == 0 || newSL > currentSL)) {
                    if(trade.PositionModify(ticket, newSL, 0))
                        Print("*** Trail SL (BUY): ", DoubleToString(currentProfitPips, 1), " pips | SL moved to ", newSL, " (", TrailDistancePips, " pips behind) ***");
                }
            } else {
                newSL = NormalizeDouble(currentPrice + TrailDistancePips * trailPipValue, posDigits);
                if(newSL < openPrice && (currentSL == 0 || newSL < currentSL)) {
                    if(trade.PositionModify(ticket, newSL, 0))
                        Print("*** Trail SL (SELL): ", DoubleToString(currentProfitPips, 1), " pips | SL moved to ", newSL, " (", TrailDistancePips, " pips behind) ***");
                }
            }
        }
        
        // Step 6: Ensure SL closes immediately (verify it's set correctly)
        // SL should already be set on order open, but verify it's still active
        if(currentSL == 0) {
            Print("WARNING: Position #", ticket, " (", posSymbol, ") has no SL! Setting tight SL...");
#ifdef SMC_SYMBOL_SILVER
            double slPipsUse = SL_Pips_Silver;
#else
            double slPipsUse = isSilver ? SL_Pips_Silver : SL_Pips;
#endif
            double pvUse = posPipValue;
            double newSL = 0;
            if(posType == POSITION_TYPE_BUY) {
                newSL = NormalizeDouble(openPrice - (slPipsUse * pvUse), posDigits);
            } else {
                newSL = NormalizeDouble(openPrice + (slPipsUse * pvUse), posDigits);
            }
            trade.PositionModify(ticket, newSL, 0);
        }
    }
}

//+------------------------------------------------------------------+
