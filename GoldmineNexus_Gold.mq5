//+------------------------------------------------------------------+
//|                            GoldmineNexus_Gold.mq5                  |
//|          Goldmine Nexus - Gold (XAUUSD only)                      |
//|     FVG + OB + Session sweeps + BOS/CHoCH | BE/TP fixed 0.1 pip    |
//+------------------------------------------------------------------+
#property copyright "Goldmine Nexus"
#property link      ""
#property version   "1.00"
#property description "Goldmine Nexus - Gold. Attach to XAUUSD only. BE/TP 1 pip = 0.1."

#define PLUG_SYMBOL_GOLD

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
input double TotalLayeredRiskPercent = 5.0;  // Total risk (%) for layered trade (split across layers) - LOWERED for safety
input double RiskPercent = 2.5;               // Risk per trade (%) - fallback when not layering
input double FirstTradeRisk = 3.5;           // Risk for FIRST trade (%) - fallback
input double ScalingEntryRisk = 1.0;         // Risk for scaling entries (%) - Lower risk when adding to losing positions
input double MaxTotalRisk = 6.0;             // Maximum total risk for all trades (%) - Safety limit - LOWERED
input bool UseEquityForRiskLimit = true;     // Use Equity (not Balance) for risk % - blocks new trades when equity drops
input double PauseNewTradesIfDrawdownPercent = 5.0; // Pause new trades if drawdown > this % of balance (0 = disabled)
input bool UseDecreasingRiskPerLayer = true;  // First layer risks more, next layers less (2% then 1.5%,1.5%,1%,1%)
input double SL_Pips = 20.0;                 // Stop Loss (pips) - Base SL (dynamic can expand)
#ifndef PLUG_SYMBOL_GOLD
input double SL_Pips_Silver = 35.0;           // Stop Loss (pips) - Base SL for Silver
#endif
input bool UseDynamicSL = true;              // Enable dynamic SL (adapts to market structure)
input bool UseBreakEven = true;              // Enable break-even
input bool UseDynamicBE = true;              // BE at position's SL distance (dynamic); if false use fixed pips below
input double BreakEvenPips = 25.0;            // Move to BE at this many pips - min when UseDynamicBE, or fixed when off
#ifndef PLUG_SYMBOL_GOLD
input double BreakEvenPips_Silver = 30.0;    // Move to BE at this many pips (Silver)
#endif
input double BE_FVG_Pips = 30.0;             // BE pips for FVG entries
input double BE_OB_Pips = 30.0;              // BE pips for Order Block entries
input double BE_SR_Pips = 30.0;              // BE pips for Support/Resistance tap & bounce
input double BE_Session_Pips = 15.0;         // BE pips for Session sweep entries (tighter)

input group "=== Dynamic SL Settings ==="
#ifndef PLUG_SYMBOL_GOLD
input bool DynamicSL_GoldOnly = false;       // Apply dynamic SL only to Gold (XAUUSD) - FALSE = Use for both
#endif
input double DynamicSL_MinPips = 25.0;       // Minimum dynamic SL (pips) - Gold: never smaller (was 15; 14 too tight)
#ifndef PLUG_SYMBOL_GOLD
input double DynamicSL_MinPips_Silver = 30.0; // Minimum dynamic SL (pips) - Silver
#endif
input double DynamicSL_MaxPips = 80.0;       // Maximum dynamic SL (pips) - allows structure/spikes
input double MaxSL_Pips_Gold = 80.0;         // Hard cap: Gold SL never exceeds this (stops 100+ pip SL; broker min may still widen slightly)
#ifndef PLUG_SYMBOL_GOLD
input double DynamicSL_MaxPips_Silver = 60.0; // Maximum dynamic SL (pips) - Silver
#endif
input double DynamicSL_ZoneBuffer = 3.0;     // Buffer beyond zone (pips) - REDUCED from 5.0
input double DynamicSL_ATR_Multiplier = 1.0; // ATR multiplier for volatility-based SL - REDUCED from 1.5
input int DynamicSL_ATR_Period = 14;         // ATR period for dynamic SL
input bool DynamicSL_UseStructure = true;   // Place SL beyond swing high/low (structure-based)
input int DynamicSL_SwingLookback = 10;      // Bars to look back for swing high/low
input double DynamicSL_ConfluenceBonus = 5.0; // Additional pips per confluence factor - REDUCED from 10.0
input bool DynamicSL_SmartExpansion = true;  // Only expand SL when there's strong confluence (2+ factors)
input double DynamicSL_BaseMultiplier = 1.2;  // Base SL multiplier (1.2 = 20% larger than fixed SL)
input bool UseWickProtection = true;          // Enable wick-based SL buffer (places SL beyond recent wicks)
input int WickProtection_Lookback = 5;        // Bars to check for wick extremes (5 = last 5 bars)
input double WickProtection_Buffer = 2.0;     // Buffer beyond wick (pips) - adds safety margin
input bool UseVolatilitySpikeExpansion = true; // Expand SL during recent volatility spikes
input int VolatilitySpike_Bars = 3;          // Bars to check for volatility spike (3 = last 3 bars)
input double VolatilitySpike_Multiplier = 1.5; // SL multiplier during volatility spike (1.5 = 50% wider)
input bool UseQuickRejectionCheck = false;    // Optional: 1-bar delay if large wick detected (false = immediate entry)
input double QuickRejection_WickSize = 3.0;   // Minimum wick size (pips) to trigger 1-bar delay

input group "=== Take Profit System ==="
#ifdef PLUG_SYMBOL_GOLD
// TP/BE levels use 1 pip = 0.1 in price (applied internally).
#else
// All TP/BE levels below are used as-is (Gold 0.1/pip, Silver 0.01/pip applied internally)
#endif
input double TP1_Pips = 50.0;                // TP1 (pips) - Close 15% (same Gold & Silver, Buys & Sells)
input double TP1_Percent = 15.0;            // % to close at TP1
input double TP2_Pips = 70.0;                // TP2 (pips) - Close 15%
input double TP2_Percent = 15.0;            // % to close at TP2
input double TP3_Pips = 90.0;                // TP3 (pips) - Close 25%
input double TP3_Percent = 25.0;            // % to close at TP3
input double TP4_Pips = 150.0;               // TP4 (pips) - Close 25%, leave runner
input double TP4_Percent = 25.0;            // % to close at TP4 (at 150 pips)
input bool TP4_To1H_SR = true;               // TP4 alternate: remaining can also target 1H S/R
input double TP5_Pips = 150.0;              // TP5 (pips) - Secure at 150 (reduce to runner)
input double TP6_Pips = 300.0;               // TP6 (pips) - Close runner at 300 pips
input double RunnerSizePercent = 15.0;       // % to keep as runner - DEFAULT: 15%
input bool RunnerTo1H_SR = true;             // Runner targets 1H support/resistance
input bool UseTrailSL = true;                // Trail SL when profit >= TrailStartPips (Gold & Silver)
input double TrailStartPips = 100.0;         // Start trailing when profit >= this (pips)
input double TrailDistancePips = 20.0;      // Trail SL this many pips behind price
input bool UseDynamicTrail = true;            // Close on structure reversal (BOS/CHoCH) to exit with a win
#ifndef PLUG_SYMBOL_GOLD
enum ENUM_SYMBOL_FILTER_PLUG { SYMBOL_BOTH_P = 0, SYMBOL_GOLD_ONLY_P = 1, SYMBOL_SILVER_ONLY_P = 2 };
input ENUM_SYMBOL_FILTER_PLUG SymbolFilter = SYMBOL_BOTH_P; // Gold only / Silver only = one pair per chart (best for BE). Set Gold only on XAU chart, Silver only on XAG chart.
#endif

input group "=== Order Block Detection (Big Beluga style - all TFs) ==="
input int OB_Lookback = 20;                  // Bars to look back for OB (for volume/ATR calculation)
input int OB_HistoricalScan = 2000;         // Bars to scan per TF (far back - catch every OB; 2000 = ~33h M1, ~20d M15, ~1y H4)
input double OB_VolumeMultiplier = 1.2;     // Volume multiplier for OB (lowered for more sensitivity)
input int OB_ATR_Period = 14;                // ATR period for OB
input double OB_ATR_Multiplier = 0.3;        // ATR multiplier for OB size (lowered for more sensitivity)
input int OB_MaxStored = 200;                // Max OBs to keep (higher = more HTF OBs retained)

input group "=== Order Block Timeframes (1M, 3M, 5M, 12M, 15M, 30M, 1H, 4H, Daily) ==="
input bool UseM1_OB = true;                   // Detect order blocks on M1
input bool UseM3_OB = true;                   // Detect order blocks on M3
input bool UseM5_OB = true;                   // Detect order blocks on M5
input bool UseM12_OB = true;                  // Detect order blocks on M12
input bool UseM15_OB = true;                  // Detect order blocks on M15
input bool UseM30_OB = true;                  // Detect order blocks on M30
input bool UseH1_OB = true;                  // Detect order blocks on H1
input bool UseH4_OB = true;                  // Detect order blocks on H4
input bool UseD1_OB = true;                  // Detect order blocks on Daily

input group "=== FVG Detection (Goldmine Nexus: All TFs) ==="
input bool UseFVG = true;                    // Enable FVG trading
input double FVG_MinSize = 5.0;              // Minimum FVG size (pips)
input int FVG_Lookback = 50;                 // Bars to look back for FVG
input bool FVG_EntryOnTouch = true;           // Entry when price TOUCHES FVG zone
input bool FVG_RequirePullback = true;        // TRUE = only BUY in lower half of bullish FVG, SELL in upper half of bearish (no entry at high/low)
input bool FVG_EntryOn50Percent = true;      // Entry when price hits 50% of FVG (retest) - used with CheckFVG_Retest for OB
input bool UseFVG_M1 = true;                 // FVG on M1
input bool UseFVG_M3 = true;                 // FVG on M3
input bool UseFVG_M5 = true;                 // FVG on M5
input bool UseFVG_M15 = true;                // FVG on M15
input bool UseFVG_M30 = true;                // FVG on M30
input bool UseFVG_H1 = true;                 // FVG on H1
input bool UseFVG_H4 = true;                 // FVG on H4
input bool UseFVG_D1 = true;                 // FVG on Daily

input group "=== Market Structure ==="
input bool UseMarketStructure = true;        // Enable BOS/CHoCH
input int MS_SwingLength = 5;                // Swing length for structure
input bool RequireBOS = false;               // Require BOS before entry

input group "=== Entry Settings ==="
input bool MultipleEntries = true;           // Allow multiple entries
input int MaxEntries = 4;                    // Maximum layered entries per direction (4 = safer, 5 = more aggressive)
input bool AllowLayeredEntries = true;       // Allow multiple entries in SAME zone (layered entries)
input bool CloseSmallestFirstAtTP = true;   // At TP1/TP2/TP3 close smallest positions first (layered mode)
input double MinEntryDistancePips = 5.0;     // Minimum distance (pips) between entries in same zone
input double EntryZonePips = 20.0;          // Entry zone size (pips)
input double EntryTouchTolerance = 5.0;     // Tolerance for zone touch (pips) - allows entries near zones
input bool WaitForConfirmation = false;      // Wait for candle close
input double MinOppositeDistancePips = 10.0; // Minimum distance from opposite trades (pips) - Set to 0 to disable - PREVENTS CONFLICTS

input group "=== Scaling Entries (Add to Losing Trades) ==="
input bool AllowScalingEntries = true;      // Allow scaling into losing positions with confluence
input double ScalingDrawdownPips = 10.0;     // Minimum drawdown (pips) before allowing scaling entry
input double BigSL_Threshold = 30.0;        // SL size (pips) to consider "big" for scaling
input int MaxScalingEntries = 2;            // Maximum scaling entries per position (in addition to MaxEntries)
input bool RequireConfluenceForScaling = true; // Require new confluence for scaling entry
input bool OnlyScaleOnDrawdown = true;       // Only allow scaling when trade is in drawdown (losing)

input group "=== Order Block Entry (Big Beluga style) ==="
input bool RequireEngulfingForOB = true;       // Require 1M or 3M engulfing before OB entry
input bool OB_Engulfing_M1 = true;             // Check M1 for engulfing confirmation
input bool OB_Engulfing_M3 = true;             // Check M3 for engulfing confirmation
input bool OB_RequireHTFAlignment = false;     // Only enter OB when zone lines up with HTF support/resistance
input double OB_HTFAlignmentPips = 25.0;      // Pips tolerance for OB zone vs HTF level

input group "=== High-Probability Reversal Setups (Goldmine Nexus) ==="
input bool TradeCloseOnSupport = true;         // Trade when price CLOSES on support - wait for rejection
input bool TradeCloseOnResistance = true;     // Trade when price CLOSES on resistance
input bool RequireEngulfingAtSupport = true;   // Require engulfing candle at S/D zone (your style)
input bool TradeFVG_Retest = true;            // Trade FVG retests (50% of FVG hit)
input double FVG_RetestPercent = 50.0;        // FVG retest percentage (50% = middle of FVG)
input double SR_TouchTolerance = 5.0;         // Tolerance for S/R touch detection (pips)
input bool UseSessionSweeps = true;           // Session high/low sweeps (Asia, London, NY) with confluence
input double SessionSweep_SL_Pips = 15.0;   // SL (pips) for session sweep entries (tighter - no big SL)
input bool UseHTFSweeps = true;               // H1/H4/Daily/Weekly/Monthly sweep highs/lows for entries
input int SessionSweepLookbackBars = 50;      // Bars to find session high/low
input double FVG_SLBuffer_Pips = 2.0;        // Buffer (pips) below/above FVG for SL (FVG SL = zone + buffer)

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES PrimaryTF = PERIOD_M15; // Primary timeframe
input ENUM_TIMEFRAMES HigherTF = PERIOD_H1;   // Higher timeframe for structure
input bool UseMultiTimeframe = true;          // Multi-timeframe analysis

input group "=== Order Block TP ==="
input bool UseOB_TP = true;                  // Use order block as TP
input double OB_TP_Distance = 300.0;         // Distance to OB TP (pips)
input int OB_TP_Lookback = 200;              // Lookback for OB TP

input group "=== News Filter ==="
input bool SuspendTradesDuringNews = true;    // Suspend new trades around high-impact news
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
input int MagicNumber = 124003;              // Magic number (Nexus Gold - unique per EA)
input string TradeComment = "Goldmine Nexus - Gold";  // Trade comment
input int Slippage = 10;                     // Slippage in points
input group "=== Pip/Points (set for YOUR broker) ==="
input int PointsPerPip_Gold = 100;           // Points per pip (Gold: usually 100 = 2-decimal, 1000 = 3-decimal)
#ifndef PLUG_SYMBOL_GOLD
input int PointsPerPip_Silver = 10;          // Silver: points per pip (usually 10)
#endif

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
    ENUM_TIMEFRAMES tf;  // Timeframe FVG was detected on (multi-TF Goldmine Nexus)
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
MarketStructure marketStruct;

double point;
int symbolDigits;  // Renamed to avoid conflict with MQL5 library
double pipValue;
double accountBalance;
datetime lastBarTime = 0;
datetime lastBarTime_M1 = 0;
datetime lastBarTime_M3 = 0;
datetime lastBarTime_M5 = 0;
datetime lastBarTime_M12 = 0;
datetime lastBarTime_M15 = 0;
datetime lastBarTime_M30 = 0;
datetime lastBarTime_H1 = 0;
datetime lastBarTime_H4 = 0;
datetime lastBarTime_D1 = 0;
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
bool tp6Hit[];
double tp1HitPrice[];
int partialCloseLevel[]; // Track which partial close level we're at
double originalVolume[]; // Track original position size for accurate partial closes

// Session sweep levels (Asia, London, NY) - Goldmine Nexus style
double asiaHigh = 0, asiaLow = 0, londonHigh = 0, londonLow = 0, nyHigh = 0, nyLow = 0;
datetime lastSessionDate = 0;

// HTF sweep levels (H1, H4, D1, W1, MN1) - recent swing high/low per TF
double htfSweepHigh_H1 = 0, htfSweepLow_H1 = 0, htfSweepHigh_H4 = 0, htfSweepLow_H4 = 0;
double htfSweepHigh_D1 = 0, htfSweepLow_D1 = 0, htfSweepHigh_W1 = 0, htfSweepLow_W1 = 0;
double htfSweepHigh_MN1 = 0, htfSweepLow_MN1 = 0;
datetime lastHTFSweep_H1 = 0, lastHTFSweep_H4 = 0, lastHTFSweep_D1 = 0, lastHTFSweep_W1 = 0, lastHTFSweep_MN1 = 0;

// Track tickets to avoid collisions (ticket % 10000 was unsafe and can collide)
ulong trackedTickets[];

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
    ArrayResize(tp6Hit, newIndex + 1);
    ArrayResize(tp1HitPrice, newIndex + 1);
    ArrayResize(partialCloseLevel, newIndex + 1);
    ArrayResize(originalVolume, newIndex + 1);

    // Initialize this slot
    tp1Hit[newIndex] = false;
    tp2Hit[newIndex] = false;
    tp3Hit[newIndex] = false;
    tp4Hit[newIndex] = false;
    tp5Hit[newIndex] = false;
    tp6Hit[newIndex] = false;
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
    string eaName = (StringLen(eaNameOverride) > 0 ? eaNameOverride : "Goldmine Nexus - Gold");
    
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
    
    // REMOTE VALIDATION (MOST SECURE) - retry on startup to avoid false alert after recompile/reload
    if(UseRemoteValidation) {
        Print("Using REMOTE license server validation...");
        int maxTries = 3;
        for(int tryCount = 1; tryCount <= maxTries; tryCount++) {
            if(ValidateLicenseRemote("Goldmine Nexus - Gold")) {
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
    
#ifndef PLUG_SYMBOL_GOLD
    bool chartIsGold = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0);
    bool chartIsSilver = (StringFind(_Symbol, "XAG") >= 0 || StringFind(_Symbol, "SILVER") >= 0);
    if(SymbolFilter == SYMBOL_GOLD_ONLY_P && !chartIsGold) {
        Print("ERROR: SymbolFilter = Gold only. Attach this EA to XAUUSD (Gold) chart only!");
        return(INIT_FAILED);
    }
    if(SymbolFilter == SYMBOL_SILVER_ONLY_P && !chartIsSilver) {
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
    
#ifdef PLUG_SYMBOL_GOLD
    pipValue = 0.1;
    Print("GOLD: 1 pip = ", pipValue, " in price | 20 pips = ", (20.0 * pipValue), " | 80 pips = ", (80.0 * pipValue));
#else
#ifdef PLUG_SYMBOL_SILVER
    pipValue = (point >= 0.1) ? 0.1 : 0.01;
    Print("SILVER: 1 pip = ", pipValue, " price | 25 pips = ", (25.0 * pipValue), " | 50 pips = ", (50.0 * pipValue), (point >= 0.1 ? " (broker point=0.1)" : ""));
#else
    if(isGold) {
        pipValue = point * (double)PointsPerPip_Gold;
        Print("GOLD: 1 pip = ", PointsPerPip_Gold, " points (your broker) | 20 pips = ", (20 * PointsPerPip_Gold), " points");
    } else if(isSilver) {
        pipValue = (point >= 0.1) ? 0.1 : 0.01;
        Print("SILVER: 1 pip = ", pipValue, " price | 25 pips = ", (25.0 * pipValue), " | 50 pips = ", (50.0 * pipValue), (point >= 0.1 ? " (broker point=0.1)" : ""));
    } else {
        pipValue = point * (double)PointsPerPip_Gold;
        Print("WARNING: Unknown symbol, assuming GOLD. Symbol: ", _Symbol, " | 1 pip = ", PointsPerPip_Gold, " points");
    }
#endif
#endif
    
    Print("Point: ", point, " | Pip Value: ", pipValue, " | Digits: ", symbolDigits);
    Print("=== ORDER BLOCK DETECTION (Big Beluga style - all TFs) ===");
    Print("OB Lookback: ", OB_Lookback, " | Historical Scan: ", OB_HistoricalScan, " bars per TF (far back)");
    Print("OB TFs: M1=", UseM1_OB, " M3=", UseM3_OB, " M5=", UseM5_OB, " M12=", UseM12_OB, " M15=", UseM15_OB, " M30=", UseM30_OB, " H1=", UseH1_OB, " H4=", UseH4_OB, " D1=", UseD1_OB);
    Print("OB Entry: Require M1/M3 engulfing=", RequireEngulfingForOB, " (M1=", OB_Engulfing_M1, " M3=", OB_Engulfing_M3, ") | Require HTF alignment=", OB_RequireHTFAlignment, " (", OB_HTFAlignmentPips, " pips)");
    Print("Volume Multiplier: ", OB_VolumeMultiplier, "x | ATR Multiplier: ", OB_ATR_Multiplier, "x | Max stored: ", OB_MaxStored);
    Print("=== NEWS FILTER ===");
    Print("Suspend trades during news: ", (SuspendTradesDuringNews ? "YES" : "NO"));
    if(SuspendTradesDuringNews) {
        Print("  - Suspend window: ", NewsBlockMinutesBefore, " min before + ", NewsBlockMinutesAfter, " min after news");
        Print("  - News times: 8:30 AM, 10:00 AM, 2:00 PM, 4:00 PM (broker time)");
    }
    
    // Initialize arrays
    ArrayResize(orderBlocks, 0);
    ArrayResize(fvgs, 0);
    
    marketStruct.trend = 0;
    marketStruct.lastBOS = 0;
    marketStruct.lastCHoCH = 0;
    
    string symbolName = (_Symbol == "XAUUSD" || _Symbol == "GOLD" || _Symbol == "XAUUSD.") ? "Gold (XAUUSD)" : "Silver (XAGUSD)";
#ifdef PLUG_SYMBOL_GOLD
    double bePipsForSymbol = BreakEvenPips;
    Print("Goldmine Nexus - Gold EA initialized for ", symbolName, " (", _Symbol, ")");
    Print("Risk per trade: ", RiskPercent, "%");
    Print("Break-Even: ", bePipsForSymbol, " pips (Gold)");
#else
#ifdef PLUG_SYMBOL_SILVER
    double bePipsForSymbol = BreakEvenPips_Silver;
    Print("Goldmine Nexus - Silver EA initialized for ", symbolName, " (", _Symbol, ")");
    Print("Risk per trade: ", RiskPercent, "%");
    Print("Break-Even: ", bePipsForSymbol, " pips (Silver)");
#else
    bool isSilverSymbol = (StringFind(symbolUpper, "XAG") >= 0 || StringFind(symbolUpper, "SILVER") >= 0);
    double bePipsForSymbol = isSilverSymbol ? BreakEvenPips_Silver : BreakEvenPips;
    Print("Goldmine Nexus EA initialized for ", symbolName, " (", _Symbol, ")");
    Print("Risk per trade: ", RiskPercent, "%");
    Print("Break-Even: ", bePipsForSymbol, " pips (", (isSilverSymbol ? "Silver" : "Gold"), ")");
#endif
#endif
    Print("Primary TF: ", EnumToString(PrimaryTF));
    
    // Set initialization time for startup cooldown (20 seconds)
    initTime = TimeCurrent();
    Print("Startup cooldown: 20 seconds - trades will be blocked until ", TimeToString(initTime + 20, TIME_DATE|TIME_SECONDS));
    
#ifdef PLUG_SYMBOL_GOLD
    if(StringFind(symbolUpper, "XAU") < 0 && StringFind(symbolUpper, "GOLD") < 0) {
        Print("ERROR: Goldmine Nexus - Gold must be attached to XAUUSD (Gold) chart only. Wrong chart: ", _Symbol);
        return(INIT_FAILED);
    }
    Print("Goldmine Nexus - Gold: BE/TP use 1 pip = 0.1 (hardcoded).");
#endif
#ifdef PLUG_SYMBOL_SILVER
    if(StringFind(symbolUpper, "XAG") < 0 && StringFind(symbolUpper, "SILVER") < 0) {
        Print("ERROR: Goldmine Nexus - Silver must be attached to XAGUSD (Silver) chart only. Wrong chart: ", _Symbol);
        return(INIT_FAILED);
    }
    Print("Goldmine Nexus - Silver: BE/TP use 1 pip = 0.01 (hardcoded).");
#endif
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("Goldmine Nexus - Gold EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                            |
//+------------------------------------------------------------------+
void OnTick() {
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
    
    if(UseM12_OB) {
        t = iTime(_Symbol, PERIOD_M12, 0);
        if(t != lastBarTime_M12) {
            lastBarTime_M12 = t;
            DetectOrderBlocksOnTF(PERIOD_M12);
        }
    }
    
    if(UseM30_OB) {
        t = iTime(_Symbol, PERIOD_M30, 0);
        if(t != lastBarTime_M30) {
            lastBarTime_M30 = t;
            DetectOrderBlocksOnTF(PERIOD_M30);
        }
    }
    
    if(UseH1_OB) {
        t = iTime(_Symbol, PERIOD_H1, 0);
        if(t != lastBarTime_H1) {
            lastBarTime_H1 = t;
            DetectOrderBlocksOnTF(PERIOD_H1);
        }
    }
    
    if(UseH4_OB) {
        t = iTime(_Symbol, PERIOD_H4, 0);
        if(t != lastBarTime_H4) {
            lastBarTime_H4 = t;
            DetectOrderBlocksOnTF(PERIOD_H4);
        }
    }
    
    if(UseD1_OB) {
        t = iTime(_Symbol, PERIOD_D1, 0);
        if(t != lastBarTime_D1) {
            lastBarTime_D1 = t;
            DetectOrderBlocksOnTF(PERIOD_D1);
        }
    }
    
    // Also detect on PrimaryTF (for backward compatibility)
    DetectOrderBlocks();
    
    // Detect FVG on all enabled timeframes (Goldmine Nexus style)
    if(UseFVG) {
        if(UseFVG_M1)  DetectFVGOnTF(PERIOD_M1);
        if(UseFVG_M3)  DetectFVGOnTF(PERIOD_M3);
        if(UseFVG_M5)  DetectFVGOnTF(PERIOD_M5);
        if(UseFVG_M15) DetectFVGOnTF(PERIOD_M15);
        if(UseFVG_M30) DetectFVGOnTF(PERIOD_M30);
        if(UseFVG_H1)  DetectFVGOnTF(PERIOD_H1);
        if(UseFVG_H4)  DetectFVGOnTF(PERIOD_H4);
        if(UseFVG_D1)  DetectFVGOnTF(PERIOD_D1);
    }
    
    // Update session levels (Asia, London, NY) and HTF sweeps - Goldmine Nexus style
    if(UseSessionSweeps) UpdateSessionLevels();
    if(UseHTFSweeps) UpdateHTFSweepLevels();
    
    // Check for entry signals
    CheckEntrySignals();
}

//+------------------------------------------------------------------+
//| Update Session High/Low (Asia 0-8, London 8-16, NY 14-22 server) |
//+------------------------------------------------------------------+
void UpdateSessionLevels() {
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int h = dt.hour;
    static int lastSessionHour = -1;
    
    double high0 = iHigh(_Symbol, PERIOD_M15, 0);
    double low0 = iLow(_Symbol, PERIOD_M15, 0);
    
    if(h == 0 && lastSessionHour != 0) { asiaHigh = 0; asiaLow = 0; }
    if(h == 8 && lastSessionHour < 8) { londonHigh = 0; londonLow = 0; }
    if(h == 14 && lastSessionHour < 14) { nyHigh = 0; nyLow = 0; }
    lastSessionHour = h;
    
    if(h >= 0 && h < 8) {
        if(asiaHigh == 0 || asiaLow == 0) { asiaHigh = high0; asiaLow = low0; }
        else { asiaHigh = MathMax(asiaHigh, high0); asiaLow = MathMin(asiaLow, low0); }
    } else if(h >= 8 && h < 16) {
        if(londonHigh == 0 || londonLow == 0) { londonHigh = high0; londonLow = low0; }
        else { londonHigh = MathMax(londonHigh, high0); londonLow = MathMin(londonLow, low0); }
    } else if(h >= 14 && h < 22) {
        if(nyHigh == 0 || nyLow == 0) { nyHigh = high0; nyLow = low0; }
        else { nyHigh = MathMax(nyHigh, high0); nyLow = MathMin(nyLow, low0); }
    }
}

//+------------------------------------------------------------------+
//| Update HTF sweep levels (swing high/low on H1, H4, D1, W1, MN1)   |
//+------------------------------------------------------------------+
void UpdateHTFSweepLevels() {
    int swingBars = 5;
    datetime t;
    
    t = iTime(_Symbol, PERIOD_H1, 0);
    if(t != lastHTFSweep_H1) {
        lastHTFSweep_H1 = t;
        int bars = iBars(_Symbol, PERIOD_H1);
        if(bars >= swingBars * 2) {
            double h = iHigh(_Symbol, PERIOD_H1, swingBars);
            double l = iLow(_Symbol, PERIOD_H1, swingBars);
            for(int i = 1; i <= swingBars; i++) {
                h = MathMax(h, iHigh(_Symbol, PERIOD_H1, swingBars - i));
                l = MathMin(l, iLow(_Symbol, PERIOD_H1, swingBars - i));
            }
            htfSweepHigh_H1 = h; htfSweepLow_H1 = l;
        }
    }
    t = iTime(_Symbol, PERIOD_H4, 0);
    if(t != lastHTFSweep_H4) {
        lastHTFSweep_H4 = t;
        int bars = iBars(_Symbol, PERIOD_H4);
        if(bars >= swingBars * 2) {
            double h = iHigh(_Symbol, PERIOD_H4, swingBars);
            double l = iLow(_Symbol, PERIOD_H4, swingBars);
            for(int i = 1; i <= swingBars; i++) {
                h = MathMax(h, iHigh(_Symbol, PERIOD_H4, swingBars - i));
                l = MathMin(l, iLow(_Symbol, PERIOD_H4, swingBars - i));
            }
            htfSweepHigh_H4 = h; htfSweepLow_H4 = l;
        }
    }
    t = iTime(_Symbol, PERIOD_D1, 0);
    if(t != lastHTFSweep_D1) {
        lastHTFSweep_D1 = t;
        int bars = iBars(_Symbol, PERIOD_D1);
        if(bars >= swingBars * 2) {
            double h = iHigh(_Symbol, PERIOD_D1, swingBars);
            double l = iLow(_Symbol, PERIOD_D1, swingBars);
            for(int i = 1; i <= swingBars; i++) {
                h = MathMax(h, iHigh(_Symbol, PERIOD_D1, swingBars - i));
                l = MathMin(l, iLow(_Symbol, PERIOD_D1, swingBars - i));
            }
            htfSweepHigh_D1 = h; htfSweepLow_D1 = l;
        }
    }
    t = iTime(_Symbol, PERIOD_W1, 0);
    if(t != lastHTFSweep_W1) {
        lastHTFSweep_W1 = t;
        int bars = iBars(_Symbol, PERIOD_W1);
        if(bars >= 3) {
            double h = iHigh(_Symbol, PERIOD_W1, 1);
            double l = iLow(_Symbol, PERIOD_W1, 1);
            htfSweepHigh_W1 = h; htfSweepLow_W1 = l;
        }
    }
    t = iTime(_Symbol, PERIOD_MN1, 0);
    if(t != lastHTFSweep_MN1) {
        lastHTFSweep_MN1 = t;
        int bars = iBars(_Symbol, PERIOD_MN1);
        if(bars >= 3) {
            double h = iHigh(_Symbol, PERIOD_MN1, 1);
            double l = iLow(_Symbol, PERIOD_MN1, 1);
            htfSweepHigh_MN1 = h; htfSweepLow_MN1 = l;
        }
    }
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
    static bool historicalScanDone_M12 = false;
    static bool historicalScanDone_M15 = false;
    static bool historicalScanDone_M30 = false;
    static bool historicalScanDone_H1 = false;
    static bool historicalScanDone_H4 = false;
    static bool historicalScanDone_D1 = false;
    
    bool historicalDone = false;
    if(tf == PERIOD_M1)  historicalDone = historicalScanDone_M1;
    else if(tf == PERIOD_M3)  historicalDone = historicalScanDone_M3;
    else if(tf == PERIOD_M5)  historicalDone = historicalScanDone_M5;
    else if(tf == PERIOD_M12) historicalDone = historicalScanDone_M12;
    else if(tf == PERIOD_M15) historicalDone = historicalScanDone_M15;
    else if(tf == PERIOD_M30) historicalDone = historicalScanDone_M30;
    else if(tf == PERIOD_H1)  historicalDone = historicalScanDone_H1;
    else if(tf == PERIOD_H4)  historicalDone = historicalScanDone_H4;
    else if(tf == PERIOD_D1)  historicalDone = historicalScanDone_D1;
    else historicalDone = true; // unknown TF, skip historical
    
    int bars = iBars(_Symbol, tf);
    if(bars < OB_Lookback + 5) return;
    
    // Determine how many bars to scan
    int scanBars = 1; // Default: only scan current bar
    if(!historicalDone && OB_HistoricalScan > 0) {
        // First time: do full historical scan
        scanBars = OB_HistoricalScan;
        if(scanBars > bars - 5) scanBars = bars - 5;
        
        if(tf == PERIOD_M1)  historicalScanDone_M1 = true;
        else if(tf == PERIOD_M3)  historicalScanDone_M3 = true;
        else if(tf == PERIOD_M5)  historicalScanDone_M5 = true;
        else if(tf == PERIOD_M12) historicalScanDone_M12 = true;
        else if(tf == PERIOD_M15) historicalScanDone_M15 = true;
        else if(tf == PERIOD_M30) historicalScanDone_M30 = true;
        else if(tf == PERIOD_H1)  historicalScanDone_H1 = true;
        else if(tf == PERIOD_H4)  historicalScanDone_H4 = true;
        else if(tf == PERIOD_D1)  historicalScanDone_D1 = true;
        
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
    Print("  Timeframe: ", EnumToString(ob.tf));
    Print("  Formed: ", TimeToString(ob.time, TIME_DATE|TIME_MINUTES), " (", ageStr, ")");
    
    // Keep only last OB_MaxStored order blocks (higher = retain more HTF OBs)
    int maxOB = (OB_MaxStored > 0) ? OB_MaxStored : 200;
    if(ArraySize(orderBlocks) > maxOB) {
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
//| Detect Fair Value Gaps on a specific timeframe (Goldmine Nexus) |
//+------------------------------------------------------------------+
void DetectFVGOnTF(ENUM_TIMEFRAMES tf) {
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
            fvg.tf = tf;
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
            fvg.tf = tf;
            AddFVG(fvg);
        }
    }
    
    CleanFVG(tf);
}

// Legacy: single-TF FVG (calls M15 for compatibility)
void DetectFVG() {
    DetectFVGOnTF(PERIOD_M15);
}

//+------------------------------------------------------------------+
//| Add FVG to Array                                                 |
//+------------------------------------------------------------------+
void AddFVG(FVG &fvg) {
    int size = ArraySize(fvgs);
    ArrayResize(fvgs, size + 1);
    fvgs[size] = fvg;
    
    // Keep last 80 FVGs (multi-TF Goldmine Nexus style)
    if(size > 80) {
        ArrayRemove(fvgs, 0, 1);
    }
}

//+------------------------------------------------------------------+
//| Clean Invalidated FVG (per timeframe)                             |
//+------------------------------------------------------------------+
void CleanFVG(ENUM_TIMEFRAMES tf) {
    int bars = iBars(_Symbol, tf);
    if(bars < 1) return;
    double close[];
    ArraySetAsSeries(close, true);
    CopyClose(_Symbol, tf, 0, 10, close);
    
    int size = ArraySize(fvgs);
    for(int i = size - 1; i >= 0; i--) {
        if(!fvgs[i].isActive || fvgs[i].tf != tf) continue;
        
        if(fvgs[i].isBullish && close[0] < fvgs[i].bottom) {
            fvgs[i].isActive = false;
        } else if(!fvgs[i].isBullish && close[0] > fvgs[i].top) {
            fvgs[i].isActive = false;
        }
    }
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
    if(!SuspendTradesDuringNews) return false;
    
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
//| Bullish Engulfing Candle (Goldmine Nexus - RequireEngulfingAtSupport) |
//+------------------------------------------------------------------+
bool IsBullishEngulfing(ENUM_TIMEFRAMES tf) {
    if(tf == PERIOD_CURRENT) tf = PrimaryTF;
    double open[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    if(CopyOpen(_Symbol, tf, 0, 2, open) < 2 || CopyClose(_Symbol, tf, 0, 2, close) < 2) return false;
    return (close[0] > open[0] && close[1] < open[1] && close[0] > open[1] && open[0] < close[1]);
}

//+------------------------------------------------------------------+
//| Bearish Engulfing Candle                                         |
//+------------------------------------------------------------------+
bool IsBearishEngulfing(ENUM_TIMEFRAMES tf) {
    if(tf == PERIOD_CURRENT) tf = PrimaryTF;
    double open[], close[];
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(close, true);
    if(CopyOpen(_Symbol, tf, 0, 2, open) < 2 || CopyClose(_Symbol, tf, 0, 2, close) < 2) return false;
    return (close[0] < open[0] && close[1] > open[1] && close[0] < open[1] && open[0] > close[1]);
}

//+------------------------------------------------------------------+
//| M1 or M3 engulfing for OB entry (your style: entries after engulfing) |
//+------------------------------------------------------------------+
bool HasBullishEngulfingM1orM3() {
    if(!RequireEngulfingForOB) return true;
    if(OB_Engulfing_M1 && IsBullishEngulfing(PERIOD_M1)) return true;
    if(OB_Engulfing_M3 && IsBullishEngulfing(PERIOD_M3)) return true;
    return false;
}
bool HasBearishEngulfingM1orM3() {
    if(!RequireEngulfingForOB) return true;
    if(OB_Engulfing_M1 && IsBearishEngulfing(PERIOD_M1)) return true;
    if(OB_Engulfing_M3 && IsBearishEngulfing(PERIOD_M3)) return true;
    return false;
}

//+------------------------------------------------------------------+
//| OB zone lines up with HTF support (for buy) or resistance (for sell) |
//+------------------------------------------------------------------+
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
    // STARTUP COOLDOWN: Block trades for 20 seconds after EA initialization
    if(initTime > 0 && TimeCurrent() - initTime < 20) {
        static datetime lastCooldownLog = 0;
        if(TimeCurrent() - lastCooldownLog >= 5) { // Log every 5 seconds during cooldown
            int remainingSeconds = 20 - (int)(TimeCurrent() - initTime);
            Print("*** STARTUP COOLDOWN: ", remainingSeconds, " seconds remaining - trades blocked ***");
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
    
    // DRAWDOWN PAUSE: Block new trades if account drawdown exceeds limit (protects capital)
    if(PauseNewTradesIfDrawdownPercent > 0) {
        double balance = account.Balance();
        double equity = account.Equity();
        if(balance > 0 && equity < balance) {
            double drawdownPercent = (balance - equity) / balance * 100.0;
            if(drawdownPercent >= PauseNewTradesIfDrawdownPercent) {
                static datetime lastDrawdownLog = 0;
                if(TimeCurrent() - lastDrawdownLog > 120) {
                    Print("*** TRADING PAUSED: Drawdown ", DoubleToString(drawdownPercent, 1), "% >= ", PauseNewTradesIfDrawdownPercent, "% - no new entries until recovery ***");
                    lastDrawdownLog = TimeCurrent();
                }
                return;
            }
        }
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
    
    // Check for high-probability reversal setups FIRST (Goldmine Nexus: S/D + optional engulfing)
    double supportLevel = 0, resistanceLevel = 0;
    bool closedOnSupport = PriceClosedOnSupport_M15(supportLevel);
    bool closedOnResistance = PriceClosedOnResistance_M15(resistanceLevel);
    bool hasEngulfingAtSupport = RequireEngulfingAtSupport ? IsBullishEngulfing(PrimaryTF) : true;
    bool hasEngulfingAtResistance = RequireEngulfingAtSupport ? IsBearishEngulfing(PrimaryTF) : true;
    bool supportWithEngulfing = closedOnSupport && hasEngulfingAtSupport;
    bool resistanceWithEngulfing = closedOnResistance && hasEngulfingAtResistance;
    double fvgTop = 0, fvgBottom = 0;
    bool isBullishFVG = false;
    bool fvgRetest = CheckFVG_Retest_M15(fvgTop, fvgBottom, isBullishFVG);
    bool isHighProbability = supportWithEngulfing || resistanceWithEngulfing || fvgRetest;
    
    if(isHighProbability) {
        Print("*** HIGH-PROBABILITY REVERSAL SETUP DETECTED - Bypassing strict requirements ***");
        if(supportWithEngulfing) Print("  -> Price closed on SUPPORT (M15)", RequireEngulfingAtSupport ? " + Bullish Engulfing" : "");
        if(resistanceWithEngulfing) Print("  -> Price closed on RESISTANCE (M15)", RequireEngulfingAtSupport ? " + Bearish Engulfing" : "");
        if(fvgRetest) Print("  -> FVG RETEST detected (", FVG_RetestPercent, "% hit)");
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
    
    for(int i = size - 1; i >= 0; i--) {
        if(!orderBlocks[i].isActive) continue;
        
        // Bullish order block entry - check if price is in zone OR near zone (with tolerance)
        if(orderBlocks[i].isBullish) {
            // Check if this is a high-probability setup (closed on support + engulfing, or FVG retest)
            bool isHighProbBullish = supportWithEngulfing || (fvgRetest && isBullishFVG);
            bool priceInZone = (currentPrice >= orderBlocks[i].bottom && currentPrice <= orderBlocks[i].top);
            bool priceNearZone = (currentPrice >= orderBlocks[i].bottom - touchTolerance && 
                                  currentPrice <= orderBlocks[i].top + touchTolerance);
            
            // For high-probability setups, expand the zone check
            if(isHighProbBullish && !priceInZone && !priceNearZone) {
                // Check if support level or FVG is near this order block
                if(supportWithEngulfing && MathAbs(supportLevel - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
                if(fvgRetest && isBullishFVG && MathAbs((fvgBottom + fvgTop) / 2.0 - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
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
                
                // OB entry: require 1M or 3M bullish engulfing (your style)
                if(shouldEnter && RequireEngulfingForOB && !HasBullishEngulfingM1orM3()) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "No M1/M3 bullish engulfing";
                }
                // Optional: only enter when OB lines up with HTF support
                if(shouldEnter && OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFSupport(orderBlocks[i].bottom, orderBlocks[i].top)) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "OB not aligned with HTF support";
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
                    
                    // CRITICAL: Check total risk (use equity when enabled - blocks new trades when equity drops)
                    double currentTotalRisk = CalculateTotalRisk(UseEquityForRiskLimit);
                    double newTradeRisk = canScale ? ScalingEntryRisk : (AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : (isFirstTrade ? FirstTradeRisk : RiskPercent));
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
                    
                    // Open order: SR type when support tap & bounce, else OB
                    string buyEntryType = supportWithEngulfing ? "SR" : "OB";
                    if(canScale) {
                        OpenBuyOrder(orderBlocks[i], scalingSL, ScalingEntryRisk, "OB");
                    } else {
                        OpenBuyOrder(orderBlocks[i], 0, newTradeRisk, buyEntryType);
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
            bool isHighProbBearish = resistanceWithEngulfing || (fvgRetest && !isBullishFVG);
            bool priceInZone = (currentPrice <= orderBlocks[i].top && currentPrice >= orderBlocks[i].bottom);
            bool priceNearZone = (currentPrice <= orderBlocks[i].top + touchTolerance && 
                                  currentPrice >= orderBlocks[i].bottom - touchTolerance);
            
            // For high-probability setups, expand the zone check
            if(isHighProbBearish && !priceInZone && !priceNearZone) {
                // Check if resistance level or FVG is near this order block
                if(resistanceWithEngulfing && MathAbs(resistanceLevel - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
                    priceNearZone = true;
                }
                if(fvgRetest && !isBullishFVG && MathAbs((fvgBottom + fvgTop) / 2.0 - (orderBlocks[i].bottom + orderBlocks[i].top) / 2.0) <= touchTolerance * 2) {
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
                
                // OB entry: require 1M or 3M bearish engulfing (your style)
                if(shouldEnter && RequireEngulfingForOB && !HasBearishEngulfingM1orM3()) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "No M1/M3 bearish engulfing";
                }
                // Optional: only enter when OB lines up with HTF resistance
                if(shouldEnter && OB_RequireHTFAlignment && !OrderBlockAlignsWithHTFResistance(orderBlocks[i].bottom, orderBlocks[i].top)) {
                    shouldEnter = false;
                    if(blockReason != "") blockReason += " | ";
                    blockReason += "OB not aligned with HTF resistance";
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
                    
                    // CRITICAL: Check total risk (use equity when enabled)
                    double currentTotalRisk = CalculateTotalRisk(UseEquityForRiskLimit);
                    double newTradeRisk = canScale ? ScalingEntryRisk : (AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : (isFirstTrade ? FirstTradeRisk : RiskPercent));
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
                    string sellEntryType = resistanceWithEngulfing ? "SR" : "OB";
                    if(canScale) {
                        OpenSellOrder(orderBlocks[i], scalingSL, ScalingEntryRisk, "OB");
                    } else {
                        OpenSellOrder(orderBlocks[i], 0, newTradeRisk, sellEntryType);
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
    
    // Session sweep entries (Asia/London/NY retest with confluence) - Goldmine Nexus style
    if(UseSessionSweeps && CheckSessionSweepEntries(currentPrice, ask, buyPositions, sellPositions, globalBlockBUY, globalBlockSELL)) {
        return;
    }
    
    // HTF sweep entries (H1/H4/D/W/M retest with confluence)
    if(UseHTFSweeps && CheckHTFSweepEntries(currentPrice, ask, buyPositions, sellPositions, globalBlockBUY, globalBlockSELL)) {
        return;
    }
    
    // Check FVG entries - TOUCH (price in FVG zone) and/or 50% retest (Goldmine Nexus style)
    if(UseFVG && FVG_EntryOnTouch) {
        int fvgSize = ArraySize(fvgs);
        for(int i = fvgSize - 1; i >= 0; i--) {
            if(!fvgs[i].isActive) continue;
            
            if(fvgs[i].isBullish && currentPrice >= fvgs[i].bottom && currentPrice <= fvgs[i].top) {
                // Require pullback: only BUY when price is in LOWER half of bullish FVG (not at the high)
                double fvgMidBuy = (fvgs[i].bottom + fvgs[i].top) / 2.0;
                if(FVG_RequirePullback && currentPrice > fvgMidBuy) continue; // Skip: price at top of FVG, wait for pullback
                // CRITICAL: Re-check position count BEFORE opening trade
                buyPositions = CountPositions(POSITION_TYPE_BUY);
                if(buyPositions >= MaxEntries) {
                    continue; // Skip this FVG, check next one
                }
                
                // CRITICAL: Check total risk (use equity when enabled)
                bool isFirstTradeFVG = (buyPositions == 0);
                double currentTotalRisk = CalculateTotalRisk(UseEquityForRiskLimit);
                double newTradeRisk = AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : (isFirstTradeFVG ? FirstTradeRisk : RiskPercent);
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
                // Require pullback: only SELL when price is in UPPER half of bearish FVG (not at the low)
                double fvgMidSell = (fvgs[i].bottom + fvgs[i].top) / 2.0;
                if(FVG_RequirePullback && currentPrice < fvgMidSell) continue; // Skip: price at bottom of FVG, wait for pullback
                // CRITICAL: Re-check position count BEFORE opening trade
                sellPositions = CountPositions(POSITION_TYPE_SELL);
                if(sellPositions >= MaxEntries) {
                    continue; // Skip this FVG, check next one
                }
                
                // CRITICAL: Check total risk (use equity when enabled)
                bool isFirstTradeFVG = (sellPositions == 0);
                double currentTotalRisk = CalculateTotalRisk(UseEquityForRiskLimit);
                double newTradeRisk = AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : (isFirstTradeFVG ? FirstTradeRisk : RiskPercent);
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
//| Session sweep entries: Asia/London/NY high-low retest + confluence |
//+------------------------------------------------------------------+
bool CheckSessionSweepEntries(double currentPrice, double ask, int buyPositions, int sellPositions, bool globalBlockBUY, bool globalBlockSELL) {
    if(globalBlockBUY && globalBlockSELL) return false;
    double tol = SR_TouchTolerance * pipValue;
    double zonePips = 10.0 * pipValue;
    
    if(asiaHigh > 0 && asiaLow > 0) {
        if(!globalBlockSELL && sellPositions < MaxEntries && MathAbs(currentPrice - asiaHigh) <= tol) {
            bool confluence = (nyHigh > asiaHigh) || IsBearishEngulfing(PrimaryTF);
            if(confluence) {
                OrderBlock ob;
                ob.top = asiaHigh + zonePips; ob.bottom = asiaHigh - zonePips;
                ob.time = TimeCurrent(); ob.isBullish = false; ob.isActive = true; ob.barIndex = 0; ob.tf = PrimaryTF;
                double risk = AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : ((sellPositions == 0) ? FirstTradeRisk : RiskPercent);
                if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(false, ask, ob.bottom, ob.top)) {
                    OpenSellOrder(ob, 0, risk, "SS");
                    Print("*** SESSION SWEEP SELL: Asia High retest ***");
                    return true;
                }
            }
        }
        if(!globalBlockBUY && buyPositions < MaxEntries && MathAbs(currentPrice - asiaLow) <= tol) {
            bool confluence = (nyLow < asiaLow) || IsBullishEngulfing(PrimaryTF);
            if(confluence) {
                OrderBlock ob;
                ob.top = asiaLow + zonePips; ob.bottom = asiaLow - zonePips;
                ob.time = TimeCurrent(); ob.isBullish = true; ob.isActive = true; ob.barIndex = 0; ob.tf = PrimaryTF;
                double risk = AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : ((buyPositions == 0) ? FirstTradeRisk : RiskPercent);
                if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(true, ask, ob.bottom, ob.top)) {
                    OpenBuyOrder(ob, 0, risk, "SS");
                    Print("*** SESSION SWEEP BUY: Asia Low retest ***");
                    return true;
                }
            }
        }
    }
    if(londonHigh > 0 && londonLow > 0) {
        if(!globalBlockSELL && sellPositions < MaxEntries && MathAbs(currentPrice - londonHigh) <= tol && IsBearishEngulfing(PrimaryTF)) {
            OrderBlock ob;
            ob.top = londonHigh + zonePips; ob.bottom = londonHigh - zonePips;
            ob.time = TimeCurrent(); ob.isBullish = false; ob.isActive = true; ob.barIndex = 0; ob.tf = PrimaryTF;
            double risk = AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : ((sellPositions == 0) ? FirstTradeRisk : RiskPercent);
            if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(false, ask, ob.bottom, ob.top)) {
                OpenSellOrder(ob, 0, risk, "SS");
                Print("*** SESSION SWEEP SELL: London High retest ***");
                return true;
            }
        }
        if(!globalBlockBUY && buyPositions < MaxEntries && MathAbs(currentPrice - londonLow) <= tol && IsBullishEngulfing(PrimaryTF)) {
            OrderBlock ob;
            ob.top = londonLow + zonePips; ob.bottom = londonLow - zonePips;
            ob.time = TimeCurrent(); ob.isBullish = true; ob.isActive = true; ob.barIndex = 0; ob.tf = PrimaryTF;
            double risk = AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : ((buyPositions == 0) ? FirstTradeRisk : RiskPercent);
            if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(true, ask, ob.bottom, ob.top)) {
                OpenBuyOrder(ob, 0, risk, "SS");
                Print("*** SESSION SWEEP BUY: London Low retest ***");
                return true;
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| HTF sweep entries: H1/H4/D/W/M swing high-low retest + confluence |
//+------------------------------------------------------------------+
bool CheckHTFSweepEntries(double currentPrice, double ask, int buyPositions, int sellPositions, bool globalBlockBUY, bool globalBlockSELL) {
    if(globalBlockBUY && globalBlockSELL) return false;
    double tol = SR_TouchTolerance * pipValue;
    double zonePips = 15.0 * pipValue;
    
    if(htfSweepHigh_H1 > 0 && !globalBlockSELL && sellPositions < MaxEntries && MathAbs(currentPrice - htfSweepHigh_H1) <= tol && IsBearishEngulfing(PrimaryTF)) {
        OrderBlock ob;
        ob.top = htfSweepHigh_H1 + zonePips; ob.bottom = htfSweepHigh_H1 - zonePips;
        ob.time = TimeCurrent(); ob.isBullish = false; ob.isActive = true; ob.barIndex = 0; ob.tf = PERIOD_H1;
        double risk = AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : ((sellPositions == 0) ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(false, ask, ob.bottom, ob.top)) {
            OpenSellOrder(ob, 0, risk);
            Print("*** HTF SWEEP SELL: H1 high retest ***");
            return true;
        }
    }
    if(htfSweepLow_H1 > 0 && !globalBlockBUY && buyPositions < MaxEntries && MathAbs(currentPrice - htfSweepLow_H1) <= tol && IsBullishEngulfing(PrimaryTF)) {
        OrderBlock ob;
        ob.top = htfSweepLow_H1 + zonePips; ob.bottom = htfSweepLow_H1 - zonePips;
        ob.time = TimeCurrent(); ob.isBullish = true; ob.isActive = true; ob.barIndex = 0; ob.tf = PERIOD_H1;
        double risk = AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : ((buyPositions == 0) ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(true, ask, ob.bottom, ob.top)) {
            OpenBuyOrder(ob, 0, risk);
            Print("*** HTF SWEEP BUY: H1 low retest ***");
            return true;
        }
    }
    if(htfSweepHigh_H4 > 0 && !globalBlockSELL && sellPositions < MaxEntries && MathAbs(currentPrice - htfSweepHigh_H4) <= tol && IsBearishEngulfing(PrimaryTF)) {
        OrderBlock ob;
        ob.top = htfSweepHigh_H4 + zonePips; ob.bottom = htfSweepHigh_H4 - zonePips;
        ob.time = TimeCurrent(); ob.isBullish = false; ob.isActive = true; ob.barIndex = 0; ob.tf = PERIOD_H4;
        double risk = AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : ((sellPositions == 0) ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(false, ask, ob.bottom, ob.top)) {
            OpenSellOrder(ob, 0, risk);
            Print("*** HTF SWEEP SELL: H4 high retest ***");
            return true;
        }
    }
    if(htfSweepLow_H4 > 0 && !globalBlockBUY && buyPositions < MaxEntries && MathAbs(currentPrice - htfSweepLow_H4) <= tol && IsBullishEngulfing(PrimaryTF)) {
        OrderBlock ob;
        ob.top = htfSweepLow_H4 + zonePips; ob.bottom = htfSweepLow_H4 - zonePips;
        ob.time = TimeCurrent(); ob.isBullish = true; ob.isActive = true; ob.barIndex = 0; ob.tf = PERIOD_H4;
        double risk = AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : ((buyPositions == 0) ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(true, ask, ob.bottom, ob.top)) {
            OpenBuyOrder(ob, 0, risk);
            Print("*** HTF SWEEP BUY: H4 low retest ***");
            return true;
        }
    }
    if(htfSweepHigh_D1 > 0 && !globalBlockSELL && sellPositions < MaxEntries && MathAbs(currentPrice - htfSweepHigh_D1) <= tol && IsBearishEngulfing(PrimaryTF)) {
        OrderBlock ob;
        ob.top = htfSweepHigh_D1 + zonePips; ob.bottom = htfSweepHigh_D1 - zonePips;
        ob.time = TimeCurrent(); ob.isBullish = false; ob.isActive = true; ob.barIndex = 0; ob.tf = PERIOD_D1;
        double risk = AllowLayeredEntries ? GetRiskPercentForLayer(sellPositions) : ((sellPositions == 0) ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(false, ask, ob.bottom, ob.top)) {
            OpenSellOrder(ob, 0, risk);
            Print("*** HTF SWEEP SELL: D1 high retest ***");
            return true;
        }
    }
    if(htfSweepLow_D1 > 0 && !globalBlockBUY && buyPositions < MaxEntries && MathAbs(currentPrice - htfSweepLow_D1) <= tol && IsBullishEngulfing(PrimaryTF)) {
        OrderBlock ob;
        ob.top = htfSweepLow_D1 + zonePips; ob.bottom = htfSweepLow_D1 - zonePips;
        ob.time = TimeCurrent(); ob.isBullish = true; ob.isActive = true; ob.barIndex = 0; ob.tf = PERIOD_D1;
        double risk = AllowLayeredEntries ? GetRiskPercentForLayer(buyPositions) : ((buyPositions == 0) ? FirstTradeRisk : RiskPercent);
        if(CalculateTotalRisk(UseEquityForRiskLimit) + risk <= MaxTotalRisk && !HasOppositeTradeNearby(true, ask, ob.bottom, ob.top)) {
            OpenBuyOrder(ob, 0, risk);
            Print("*** HTF SWEEP BUY: D1 low retest ***");
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Open Buy Order                                                   |
//+------------------------------------------------------------------+
void OpenBuyOrder(OrderBlock &ob, double useSL = 0, double riskPercent = 0, string entryType = "OB") {
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Calculate entry zone
    double entryZoneTop = ob.top;
    double entryZoneBottom = ob.bottom;
    double entryPrice = ask; // Enter at current ask
    
    // Count confluences for dynamic SL (not used for Session Sweep)
    int confluenceCount = 1; // Base: Order Block
    if((entryZoneTop - entryZoneBottom) / pipValue < 10) {
        confluenceCount = 2;
    }
    
    // Calculate stop loss - by type: Session = small fixed; OB/SR = dynamic or zone-based
    double sl = 0;
    if(useSL > 0) {
        sl = useSL;
        Print("*** USING PROVIDED SL FOR SCALING ENTRY: ", sl, " ***");
    } else if(entryType == "SS") {
        // Session sweep: tight SL (no big SL)
        sl = entryPrice - (SessionSweep_SL_Pips * pipValue);
        Print("*** SESSION SWEEP BUY: SL ", SessionSweep_SL_Pips, " pips below entry ***");
    } else {
        // OB or SR: dynamic or below zone (support tap = SL below support)
        sl = CalculateDynamicSL(true, entryPrice, entryZoneBottom, entryZoneTop, confluenceCount);
    }
    
    // Enforce broker minimum stop level (avoids Retcode 10011 / "common error")
    long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stopsLevel > 0) {
        double minDistPrice = (double)stopsLevel * point;
        double slDistPrice = entryPrice - sl;
        if(slDistPrice < minDistPrice && slDistPrice > 0) {
            sl = NormalizeDouble(entryPrice - minDistPrice, symbolDigits);
            Print("*** BUY: SL widened to broker minimum (", (minDistPrice / pipValue), " pips) to avoid Retcode 10011 ***");
        }
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
    
    // Layered risk: total 8% across MaxEntries → per layer = TotalLayeredRiskPercent/MaxEntries
    double actualRisk = (riskPercent > 0) ? riskPercent : (AllowLayeredEntries ? (TotalLayeredRiskPercent / (double)MathMax(1, MaxEntries)) : RiskPercent);
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
    Print("SL Distance: ", (entryPrice - sl), " points = ", slDistancePips, " pips | Type: ", entryType);
    Print("Lot Size: ", lotSize, " | Risk: ", actualRisk, "% (layered=", (AllowLayeredEntries ? "yes" : "no"), ")");
    
    // Build trade comment with type suffix for BE pips (FVG/OB/SR/SS)
    string finalComment = TradeComment + "_" + entryType;
    if(StringLen(UserName) > 0) {
        finalComment = finalComment + "|U:" + UserName;
    }
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    
    // Open order WITHOUT TP (set to 0) - we'll manage TPs manually
    if(trade.Buy(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
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
void OpenSellOrder(OrderBlock &ob, double useSL = 0, double riskPercent = 0, string entryType = "OB") {
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    double entryZoneTop = ob.top;
    double entryZoneBottom = ob.bottom;
    double entryPrice = bid;
    
    int confluenceCount = 1;
    if((entryZoneTop - entryZoneBottom) / pipValue < 10) {
        confluenceCount = 2;
    }
    
    double sl = 0;
    if(useSL > 0) {
        sl = useSL;
        Print("*** USING PROVIDED SL FOR SCALING ENTRY: ", sl, " ***");
    } else if(entryType == "SS") {
        sl = entryPrice + (SessionSweep_SL_Pips * pipValue);
        Print("*** SESSION SWEEP SELL: SL ", SessionSweep_SL_Pips, " pips above entry ***");
    } else {
        sl = CalculateDynamicSL(false, entryPrice, entryZoneBottom, entryZoneTop, confluenceCount);
    }
    
    // Enforce broker minimum stop level (avoids Retcode 10011 / "common error")
    long stopsLevelSell = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    if(stopsLevelSell > 0) {
        double minDistPriceSell = (double)stopsLevelSell * point;
        double slDistPriceSell = sl - entryPrice;
        if(slDistPriceSell < minDistPriceSell && slDistPriceSell > 0) {
            sl = NormalizeDouble(entryPrice + minDistPriceSell, symbolDigits);
            Print("*** SELL: SL widened to broker minimum (", (minDistPriceSell / pipValue), " pips) ***");
        }
    }
    
    double tp = 0;
    if(UseOB_TP) {
        tp = FindOrderBlockTP(false, entryPrice);
    }
    
    if(tp == 0) {
        tp = entryPrice - (500 * pipValue); // Very far TP, we'll manage manually
    }
    
    // Layered risk: total 8% across MaxEntries
    double actualRisk = (riskPercent > 0) ? riskPercent : (AllowLayeredEntries ? (TotalLayeredRiskPercent / (double)MathMax(1, MaxEntries)) : RiskPercent);
    double riskAmount = accountBalance * (actualRisk / 100.0);
    double slDistance = MathAbs(entryPrice - sl);
    double pvSell = (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0) ? 0.1 : pipValue;
    if(slDistance < 20.0 * pvSell) slDistance = 20.0 * pvSell;
    double lotSize = CalculateLotSize(riskAmount, slDistance);
    
    entryPrice = NormalizeDouble(entryPrice, symbolDigits);
    sl = NormalizeDouble(sl, symbolDigits);
    tp = NormalizeDouble(tp, symbolDigits);
    
    double slDistancePips = (sl - entryPrice) / pipValue;
    Print("=== SELL ORDER DEBUG ===");
    Print("Symbol: ", _Symbol, " | Entry: ", entryPrice, " | SL: ", sl, " (", slDistancePips, " pips) | Type: ", entryType);
    Print("Lot Size: ", lotSize, " | Risk: ", actualRisk, "%");
    
    string finalComment = TradeComment + "_" + entryType;
    if(StringLen(UserName) > 0) {
        finalComment = finalComment + "|U:" + UserName;
    }
    finalComment = finalComment + "|A:" + IntegerToString(account.Login());
    
    if(trade.Sell(lotSize, _Symbol, entryPrice, sl, 0, finalComment)) {
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
    // Use symbol-specific pip value so Silver SL is never 10x wrong (e.g. broker point=0.1)
    double symPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
#ifdef PLUG_SYMBOL_GOLD
    double pv = 0.1;
    if(!UseDynamicSL) {
        double baseSL = SL_Pips;
        if(isBuy) return entryPrice - (baseSL * pv);
        else     return entryPrice + (baseSL * pv);
    }
    double baseSL = SL_Pips;
    double minPips = DynamicSL_MinPips;
    double maxPips = MathMin(DynamicSL_MaxPips, MaxSL_Pips_Gold);  // Never exceed hard cap
#else
#ifdef PLUG_SYMBOL_SILVER
    double pv = (symPoint >= 0.1) ? 0.1 : 0.01;
    if(!UseDynamicSL) {
        double baseSL = SL_Pips_Silver;
        if(isBuy) return entryPrice - (baseSL * pv);
        else     return entryPrice + (baseSL * pv);
    }
    double baseSL = SL_Pips_Silver;
    double minPips = DynamicSL_MinPips_Silver;
    double maxPips = DynamicSL_MaxPips_Silver;
#else
    double pv = isSilver ? ((symPoint >= 0.1) ? 0.1 : 0.01) : (symPoint * (double)PointsPerPip_Gold);
    if(!UseDynamicSL || (DynamicSL_GoldOnly && isSilver)) {
        double baseSL = isSilver ? SL_Pips_Silver : SL_Pips;
        if(isBuy) return entryPrice - (baseSL * pv);
        else     return entryPrice + (baseSL * pv);
    }
    double baseSL = isSilver ? SL_Pips_Silver : SL_Pips;
    double minPips = isSilver ? DynamicSL_MinPips_Silver : DynamicSL_MinPips;
    double maxPips = isSilver ? DynamicSL_MaxPips_Silver : DynamicSL_MaxPips;
#endif
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
    // HARD FLOOR: Gold never below 25 pips (ignores saved inputs / old .ex5)
    const double GOLD_ABSOLUTE_MIN_SL_PIPS = 25.0;
    if(isGold && slPips < GOLD_ABSOLUTE_MIN_SL_PIPS) {
        Print("  [SAFETY] Gold SL raised to ", GOLD_ABSOLUTE_MIN_SL_PIPS, " pips (was ", DoubleToString(slPips, 1), " pips)");
        slPips = GOLD_ABSOLUTE_MIN_SL_PIPS;
    }
    // Safety: Gold absolute cap at MaxSL_Pips_Gold (stops 100+ pip SL from structure/broker min)
    if(isGold && slPips > MaxSL_Pips_Gold) {
        Print("  [SAFETY] Gold SL capped at ", MaxSL_Pips_Gold, " pips (was ", DoubleToString(slPips, 1), " pips)");
        slPips = MaxSL_Pips_Gold;
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
#ifdef PLUG_SYMBOL_GOLD
    Print("  Base SL: ", SL_Pips, " pips");
#else
#ifdef PLUG_SYMBOL_SILVER
    Print("  Base SL: ", SL_Pips_Silver, " pips");
#else
    Print("  Base SL: ", (isSilver ? SL_Pips_Silver : SL_Pips), " pips");
#endif
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
//| Calculate Total Risk of All Open Positions (% of balance or equity)|
//+------------------------------------------------------------------+
double CalculateTotalRisk(bool useEquity = false) {
    double totalRisk = 0.0;
    double balance = account.Balance();
    double equity = account.Equity();
    double denominator = useEquity ? (equity > 0 ? equity : balance) : balance;
    if(denominator <= 0) return 0.0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol) continue;
        if(position.Magic() != MagicNumber) continue;
        
        double openPrice = position.PriceOpen();
        double sl = position.StopLoss();
        double volume = position.Volume();
        
        if(sl > 0) {
            double slDistance = MathAbs(openPrice - sl);
            if(slDistance > 0) {
                double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
                double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
                double riskAmount = (slDistance / tickSize) * tickValue * volume;
                double riskPercent = (riskAmount / denominator) * 100.0;
                totalRisk += riskPercent;
            }
        }
    }
    
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Risk % for next layer (decreasing: first 2%, then 1.5%,1.5%,1%,1%) |
//+------------------------------------------------------------------+
double GetRiskPercentForLayer(int currentPositionCount) {
    if(!UseDecreasingRiskPerLayer) return TotalLayeredRiskPercent / (double)MathMax(1, MaxEntries);
    // First layer 2%, then 1.5%, 1.5%, 1%, 1% (total 7%) - keeps early entries meaningful, later layers smaller
    if(currentPositionCount >= 5) return 0;
    double riskByLayer[] = {2.0, 1.5, 1.5, 1.0, 1.0};
    return riskByLayer[currentPositionCount];
}

//+------------------------------------------------------------------+
//| Open Buy from FVG                                                |
//+------------------------------------------------------------------+
void OpenBuyOrderFromFVG(FVG &fvg, double riskPercent = 0) {
    // FVG SL: below the FVG (buy) = fvg.bottom - buffer
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double entryPrice = ask;
    double sl = fvg.bottom - (FVG_SLBuffer_Pips * pipValue); // SL below FVG
    // Cap FVG SL so we never get 100+ pip SL on large FVGs (Gold: 1 pip = 0.1)
    double pvGold = 0.1;
    double slPipsFVG = (entryPrice - sl) / pvGold;
    if(slPipsFVG > MaxSL_Pips_Gold) {
        sl = NormalizeDouble(entryPrice - MaxSL_Pips_Gold * pvGold, symbolDigits);
        Print("*** FVG BUY: SL capped at ", MaxSL_Pips_Gold, " pips (was ", DoubleToString(slPipsFVG, 1), " pips) ***");
    }
    // Layered risk when enabled
    double actualRisk = (riskPercent > 0) ? riskPercent : (AllowLayeredEntries ? (TotalLayeredRiskPercent / (double)MathMax(1, MaxEntries)) : RiskPercent);
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
    // FVG SL: above the FVG (sell) = fvg.top + buffer
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double entryPrice = bid;
    double sl = fvg.top + (FVG_SLBuffer_Pips * pipValue); // SL above FVG
    // Cap FVG SL so we never get 100+ pip SL on large FVGs (Gold: 1 pip = 0.1)
    double pvGold = 0.1;
    double slPipsFVGSell = (sl - entryPrice) / pvGold;
    if(slPipsFVGSell > MaxSL_Pips_Gold) {
        sl = NormalizeDouble(entryPrice + MaxSL_Pips_Gold * pvGold, symbolDigits);
        Print("*** FVG SELL: SL capped at ", MaxSL_Pips_Gold, " pips (was ", DoubleToString(slPipsFVGSell, 1), " pips) ***");
    }
    double actualRisk = (riskPercent > 0) ? riskPercent : (AllowLayeredEntries ? (TotalLayeredRiskPercent / (double)MathMax(1, MaxEntries)) : RiskPercent);
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
//| Calculate Lot Size Based on Risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double riskAmount, double slDistance) {
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(slDistance == 0) return minLot;
    
    double lotSize = riskAmount / (slDistance / tickSize * tickValue);
    
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
//| Get smallest position ticket by volume (same symbol/magic/type)   |
//+------------------------------------------------------------------+
ulong GetSmallestPositionTicket(ENUM_POSITION_TYPE type) {
    ulong smallestTicket = 0;
    double smallestVol = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Symbol() != _Symbol || position.Magic() != MagicNumber || position.Type() != type) continue;
        double vol = position.Volume();
        if(smallestTicket == 0 || vol < smallestVol) {
            smallestTicket = position.Ticket();
            smallestVol = vol;
        }
    }
    return smallestTicket;
}

//+------------------------------------------------------------------+
//| Get BE pips for this position from comment (FVG/OB/SR/Session)    |
//+------------------------------------------------------------------+
double GetBreakEvenPipsForComment(string comment) {
    if(StringFind(comment, "_SS") >= 0 || StringFind(comment, "_SESSION") >= 0) return BE_Session_Pips;
    if(StringFind(comment, "_FVG") >= 0) return BE_FVG_Pips;
    if(StringFind(comment, "_SR") >= 0) return BE_SR_Pips;
    if(StringFind(comment, "_OB") >= 0 || StringFind(comment, "Goldmine Nexus") >= 0) return BE_OB_Pips; // default OB/base
#ifdef PLUG_SYMBOL_GOLD
    return BreakEvenPips;
#else
#ifdef PLUG_SYMBOL_SILVER
    return BreakEvenPips_Silver;
#else
    return BreakEvenPips;
#endif
#endif
}

//+------------------------------------------------------------------+
//| Get pip value for a symbol (for multi-symbol position management) |
//+------------------------------------------------------------------+
double GetPipValueForSymbol(string sym) {
    string s = sym;
    StringToUpper(s);
    if(StringFind(s, "XAU") >= 0 || StringFind(s, "GOLD") >= 0) return 0.1;
    if(StringFind(s, "XAG") >= 0 || StringFind(s, "SILVER") >= 0) return 0.01;
    return 0.1;
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
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManagePositions() {
    static int lastLogTime = 0;
    static int s_tp1Closes = 0, s_tp2Closes = 0, s_tp3Closes = 0; // layered: close smallest first
    int currentTime = (int)TimeCurrent();
    
    int buyCount = CountPositions(POSITION_TYPE_BUY);
    int sellCount = CountPositions(POSITION_TYPE_SELL);
    if(buyCount + sellCount == 0) {
        s_tp1Closes = 0; s_tp2Closes = 0; s_tp3Closes = 0;
    }
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(!position.SelectByIndex(i)) continue;
        if(position.Magic() != MagicNumber) continue;
        string posSymbol = position.Symbol();
        string posSymbolUpper = posSymbol;
        StringToUpper(posSymbolUpper);
#ifndef PLUG_SYMBOL_GOLD
        if(SymbolFilter != SYMBOL_BOTH_P && posSymbol != _Symbol) continue;
#endif
        if(StringFind(posSymbolUpper, "XAU") < 0 && StringFind(posSymbolUpper, "GOLD") < 0 &&
           StringFind(posSymbolUpper, "XAG") < 0 && StringFind(posSymbolUpper, "SILVER") < 0) continue;
#ifdef PLUG_SYMBOL_GOLD
        if(StringFind(posSymbolUpper, "XAU") < 0 && StringFind(posSymbolUpper, "GOLD") < 0) continue; // This EA = Gold only
#endif
#ifdef PLUG_SYMBOL_SILVER
        if(StringFind(posSymbolUpper, "XAG") < 0 && StringFind(posSymbolUpper, "SILVER") < 0) continue; // This EA = Silver only
#endif
        ulong ticket = position.Ticket();
        double openPrice = position.PriceOpen();
        double currentSL = position.StopLoss();
        double currentTP = position.TakeProfit();
        double currentVolume = position.Volume();
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)position.Type();
        
        bool isSilver = (StringFind(posSymbolUpper, "XAG") >= 0 || StringFind(posSymbolUpper, "SILVER") >= 0);
        double posPipValue = GetPipValueForSymbol(posSymbol);
        double posPoint = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
        int posDigits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
        
        double currentBID = SymbolInfoDouble(posSymbol, SYMBOL_BID);
        double currentASK = SymbolInfoDouble(posSymbol, SYMBOL_ASK);
        
        // CRITICAL FIX: Use MT5's built-in profit (most accurate) and convert to pips
        // This avoids issues with position.PriceOpen() not matching actual execution price
        double mt5ProfitUSD = position.Profit() + position.Swap() + position.Commission();
        double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        
        double currentProfitPips = 0;
        if(posType == POSITION_TYPE_BUY)
            currentProfitPips = (currentBID - openPrice) / posPipValue;
        else
            currentProfitPips = (openPrice - currentASK) / posPipValue;
        // Gold BUY: 1 pip = 0.1 so BE/TP always see correct pips (e.g. 4950→4962 = 120 pips)
        bool isGoldSym = (StringFind(posSymbolUpper, "XAU") >= 0 || StringFind(posSymbolUpper, "GOLD") >= 0);
        if(isGoldSym && posType == POSITION_TYPE_BUY)
            currentProfitPips = (currentBID - openPrice) / 0.1;
        // Silver: 1 pip = 0.01
        if(isSilver) {
            if(posType == POSITION_TYPE_BUY)
                currentProfitPips = (currentBID - openPrice) / 0.01;
            else
                currentProfitPips = (openPrice - currentASK) / 0.01;
        }
#ifdef PLUG_SYMBOL_GOLD
        // GOLD-ONLY EA: force pip = 0.1 and profit from price (no broker/symbol ambiguity)
        posPipValue = 0.1;
        isSilver = false;
        isGoldSym = true;
        currentProfitPips = (posType == POSITION_TYPE_BUY) ? (currentBID - openPrice) / 0.1 : (openPrice - currentASK) / 0.1;
#endif
#ifdef PLUG_SYMBOL_SILVER
        // SILVER-ONLY EA: force pip = 0.01 and profit from price (no broker/symbol ambiguity)
        posPipValue = 0.01;
        isSilver = true;
        isGoldSym = false;
        currentProfitPips = (posType == POSITION_TYPE_BUY) ? (currentBID - openPrice) / 0.01 : (openPrice - currentASK) / 0.01;
        if(posType == POSITION_TYPE_SELL)
            currentProfitPips = (openPrice - currentASK) / 0.01;
#endif
        // SELL profit: always use fixed pip size so BE/TP never fail (Silver=0.01, Gold=0.1)
        if(posType == POSITION_TYPE_SELL)
            currentProfitPips = (openPrice - currentASK) / (isSilver ? 0.01 : 0.1);
        const double PLUG_MIN_PIPS_FULL_CLOSE = 80.0; // Never full-close below this (stops Silver "full at 50")
        
        // CRITICAL: For SELL trades, use ASK for BE/TP calculations (what we buy back at)
        // For BUY trades, use BID (what we sell at)
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
        
        // Stable per-ticket tracking index
        int ticketIndex = GetTicketIndex(ticket);
        
        // Log position status every 10 seconds for debugging
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
                Print("MT5 Profit USD: ", mt5ProfitUSD, " | Spread: ", (currentASK - currentBID), " | pipValue: ", pipValue);
                lastSellProfitDebug = TimeCurrent();
            }
        }
        
        // Verify pip conversion is correct (10 pips = 1000 points for Gold, 100 points for Silver)
        static bool pipConversionLogged = false;
        if(!pipConversionLogged) {
            Print("=== PIP CONVERSION VERIFICATION ===");
            Print("Symbol: ", posSymbol);
            Print("Point: ", posPoint);
            Print("PipValue: ", posPipValue);
            Print("Test: 10 pips = ", (10 * pipValue), " points");
            if(StringFind(posSymbolUpper, "XAU") >= 0 || StringFind(posSymbolUpper, "GOLD") >= 0) {
                Print("Expected for Gold: 10 pips = 1.0 price (1 pip = 0.1)");
                if(MathAbs((10 * posPipValue) - 1.0) < 0.01) {
                    Print("✓ CORRECT: Gold pip conversion working!");
                } else {
                    Print("✗ ERROR: Gold pip conversion incorrect!");
                }
            } else {
                Print("Expected for Silver: 10 pips = 0.10 price (1 pip = 0.01)");
                if(MathAbs((10 * posPipValue) - 0.10) < 0.01) {
                    Print("✓ CORRECT: Silver pip conversion working!");
                } else {
                    Print("✗ ERROR: Silver pip conversion incorrect!");
                }
            }
            pipConversionLogged = true;
        }
        
        double minLot = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN);
        double lotStep = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_STEP);
        if(lotStep <= 0) lotStep = 0.01;
        
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
        
        // NEW TP SYSTEM: BE at 20 pips → TP1 (10p, 25%) → TP2 (20p, 20%) → TP3 (50p, 30%) → TP4 (1H S/R, 25%) → TP5 (150p, secure profit) → Runner (5%)
        
        bool hasTP4 = (partialCloseLevel[ticketIndex] == 3); // TP4 is active (after TP3)
        
        // Step 1: Move to BE - use dynamic (position's SL distance) or type-based fixed pips
        // IMPORTANT: do NOT mark BE as hit unless the SL move succeeds.
        string posComment = position.Comment();
        double bePips = GetBreakEvenPipsForComment(posComment);
#ifndef PLUG_SYMBOL_GOLD
        if(isSilver)
            bePips = BreakEvenPips_Silver;
#endif
        if(UseDynamicBE && currentSL > 0 && posPipValue > 0) {
            // Use fixed pip size for Silver (0.01) / Gold (0.1) so SL distance is correct regardless of broker digits
            double pipForSL = isSilver ? 0.01 : (isGoldSym ? 0.1 : posPipValue);
            double slDistancePips = (posType == POSITION_TYPE_BUY)
                ? (openPrice - currentSL) / pipForSL
                : (currentSL - openPrice) / pipForSL;
            if(slDistancePips > 0) {
                double dynamicBE = MathMax(slDistancePips, bePips);
#ifdef PLUG_SYMBOL_GOLD
                double maxBEPips = MathMax(50.0, BreakEvenPips * 2.0);
                bePips = MathMin(dynamicBE, maxBEPips);
#else
#ifdef PLUG_SYMBOL_SILVER
                double maxBEPips = MathMax(50.0, BreakEvenPips_Silver * 2.0);
                bePips = MathMin(dynamicBE, maxBEPips);
                bePips = MathMin(bePips, BreakEvenPips_Silver);
#else
                double maxBEPips = MathMax(50.0, BreakEvenPips * 2.0);
                if(isSilver) maxBEPips = MathMax(50.0, BreakEvenPips_Silver * 2.0);
                bePips = MathMin(dynamicBE, maxBEPips);
                if(isSilver) bePips = MathMin(bePips, BreakEvenPips_Silver);
#endif
#endif
            }
        }
        // Gold: BE must be at least 30 pips (never trigger BE earlier than BreakEvenPips)
#ifdef PLUG_SYMBOL_GOLD
        bePips = MathMax(bePips, BreakEvenPips);
#endif
        // Cap BE at user setting so we never wait longer than BreakEvenPips / BreakEvenPips_Silver
#ifdef PLUG_SYMBOL_GOLD
        bePips = MathMin(bePips, BreakEvenPips);
#else
        bePips = MathMin(bePips, isSilver ? BreakEvenPips_Silver : BreakEvenPips);
#endif
        
        // CRITICAL: Silver SELL - always use price-based profit (1 pip = 0.01) so BE/TP never fail
#ifdef PLUG_SYMBOL_SILVER
        if(posType == POSITION_TYPE_SELL) {
            double silverSellPipsNow = (openPrice - currentASK) / 0.01;
            if(silverSellPipsNow > currentProfitPips) currentProfitPips = silverSellPipsNow;
        }
#endif
        // GOLD SELL FIX: Force BE trigger from price distance (1 pip Gold = 0.1) so BE always fires (like Goldmine Edge / SMC)
        bool isGold = (StringFind(posSymbolUpper, "XAU") >= 0 || StringFind(posSymbolUpper, "GOLD") >= 0);
        if(isGold && posType == POSITION_TYPE_SELL) {
            double priceProfit = openPrice - currentASK;
            const double goldPipPrice = 0.1;
            double pipsFromPrice = priceProfit / goldPipPrice;
            if(pipsFromPrice >= bePips && pipsFromPrice > 0 && pipsFromPrice > currentProfitPips)
                currentProfitPips = pipsFromPrice;
        }
        
        // SELL BE: Same as Goldmine Edge - one Modify(ticket, openPrice, 0). Try every tick until SL at BE. Gold & Silver both at 30 pips.
        if(posType == POSITION_TYPE_SELL) {
            double pipSizeSELL = isGold ? 0.1 : (isSilver ? 0.01 : posPipValue);
            double sellPips = (openPrice - currentASK) / pipSizeSELL;
            if(sellPips > currentProfitPips) currentProfitPips = sellPips;
            if(sellPips >= bePips && sellPips > 0) {
                if(!tp1Hit[ticketIndex]) { tp1Hit[ticketIndex] = true; tp1HitPrice[ticketIndex] = currentPrice; }
                Print("*** SELL BE FLAG (", (isGold ? "Gold" : "Silver"), "): ", DoubleToString(sellPips, 1), " pips >= ", bePips, " | Ticket #", ticket, " → TP enabled ***");
                if(UseBreakEven) {
                    double newSL = openPrice;
                    bool needToModify = (currentSL == 0 || newSL < currentSL);
                    if(needToModify) {
                        if(trade.PositionModify(ticket, newSL, 0)) {
                            Print("*** SELL BE SET | Ticket #", ticket, " (", (isGold ? "Gold" : "Silver"), ") | ", DoubleToString(sellPips, 1), " pips ***");
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
                        } else if(isGold) {
                            // Gold SELL: If broker rejects exact BE, try 1 pip in profit (SL 0.1 below entry)
                            double cushionSL = NormalizeDouble(openPrice - 0.1, posDigits);
                            if(trade.PositionModify(ticket, cushionSL, 0)) {
                                Print("*** Gold SELL BE SET (cushion -1 pip) | Ticket #", ticket, " | ", DoubleToString(sellPips, 1), " pips ***");
                            }
                        }
                    }
                }
            }
        }
        
        // Mark BE as hit early for SELL so TP runs even if SL move fails (same as SMC fix)
        if(currentProfitPips >= bePips && currentProfitPips > 0 && !tp1Hit[ticketIndex]) {
            tp1Hit[ticketIndex] = true;
            tp1HitPrice[ticketIndex] = currentPrice;
            if(posType == POSITION_TYPE_SELL)
                Print("*** SELL BE FLAG SET: ", currentProfitPips, " pips >= ", bePips, " → TP can run (will still try to move SL) ***");
        }
        
        bool shouldTriggerBE = (currentProfitPips >= bePips && currentProfitPips > 0);
        // Silver BUY: force BE from price (0.01/pip) so 30 pips triggers BE
        if(isSilver && posType == POSITION_TYPE_BUY) {
            double silverBuyPips = (currentBID - openPrice) / 0.01;
            if(silverBuyPips >= bePips && silverBuyPips > 0) {
                currentProfitPips = silverBuyPips;
                shouldTriggerBE = true;
            }
        }
        // Force BE trigger for Gold SELL from price (so BE always fires regardless of pip conversion)
        if(isGold && posType == POSITION_TYPE_SELL) {
            double priceProfitSELL = openPrice - currentASK;
            double pipsFromPriceSELL = priceProfitSELL / 0.1;
            if(pipsFromPriceSELL >= bePips && pipsFromPriceSELL > 0) {
                currentProfitPips = pipsFromPriceSELL;
                shouldTriggerBE = true;
            }
        }
        // Silver SELL: force BE from price (1 pip = 0.01) so e.g. 25 pips triggers BE (no dependency on posPipValue/dynamic cap)
        if(isSilver && posType == POSITION_TYPE_SELL) {
            double silverSellPips = (openPrice - currentASK) / 0.01;
            if(silverSellPips >= bePips && silverSellPips > 0) {
                currentProfitPips = silverSellPips;
                shouldTriggerBE = true;
            }
        }
        
        // Silver: only block BE if profit in pips is clearly below trigger (avoid wrong pip value blocking)
        if(isSilver && shouldTriggerBE && posPipValue > 0 && currentProfitPips < bePips - 2.0) {
            shouldTriggerBE = false;
        }
        
        // CRITICAL FIX FOR SELL TRADES: Use fixed pip size so BE/TP never fail (Gold=0.1, Silver=0.01)
        if(posType == POSITION_TYPE_SELL) {
            double sellPipSize = isGold ? 0.1 : 0.01;
            double sellProfitCheck = (openPrice - currentASK) / sellPipSize;
            if(sellProfitCheck != currentProfitPips) currentProfitPips = sellProfitCheck;
            if(!shouldTriggerBE && currentProfitPips >= bePips && !tp1Hit[ticketIndex]) shouldTriggerBE = true;
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
            Print("  Price Difference: ", (currentPrice - openPrice), 
                  " | pipValue: ", posPipValue, " | Calculated Pips: ", currentProfitPips);
            
            // Move SL to break even
            if(UseBreakEven) {
                double newSL = NormalizeDouble(openPrice, posDigits); // Exact break-even (BUY and SELL)
                bool needToModify = false;

                // Broker constraints: SL must respect stops/freeze levels
                int stopsLevelPts = (int)SymbolInfoInteger(posSymbol, SYMBOL_TRADE_STOPS_LEVEL);
                int freezeLevelPts = (int)SymbolInfoInteger(posSymbol, SYMBOL_TRADE_FREEZE_LEVEL);
                int minLevelPts = (stopsLevelPts > freezeLevelPts ? stopsLevelPts : freezeLevelPts);
                double minLevelPrice = (double)minLevelPts * posPoint;

                // Stop/freeze: delay BE only for non-Silver BUY when BE would be above allowed. Silver BUY: always try (retry with cushion if broker rejects).
                if(minLevelPts > 0 && posType == POSITION_TYPE_BUY && !isSilver) {
                    double maxAllowedSL = NormalizeDouble(currentPrice - minLevelPrice, posDigits);
                    if(newSL > maxAllowedSL) {
                        Print("BE DELAYED: stop/freeze level too high. Need more profit. | BE=", newSL, " | maxAllowedSL=", maxAllowedSL);
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
                        needToModify = true;
                        Print("*** SELL: Moving SL to BE at entry (current SL ", DoubleToString(slDistanceFromEntry, 1), " pips above) ***");
                    }
                }
                
                if(needToModify) {
                    Print("  Attempting to move SL to BE | Type: ", (posType == POSITION_TYPE_BUY ? "BUY" : "SELL"), 
                          " | Current SL: ", currentSL, " | New SL: ", newSL, " | Entry: ", openPrice);
                    Print("  Profit: ", currentProfitPips, " pips | BE Trigger: ", bePips, " pips | Symbol: ", posSymbol);
                    Print("  pipValue: ", posPipValue, " | point: ", posPoint, " | isSilver: ", isSilver);
                    
                    bool slMoved = false;
                    int maxRetries = 8;
                    for(int retry = 0; retry < maxRetries; retry++) {
                        if(!position.SelectByTicket(ticket)) break;
                        double slToTry = newSL;
                        // SELL: try exact entry first (retry 0), then entry+1pip, +2pip... (like Goldmine Edge)
                        if(posType == POSITION_TYPE_SELL) {
                            double pv = isGold ? 0.1 : posPipValue;
                            if(retry == 0)
                                slToTry = NormalizeDouble(openPrice, posDigits);
                            else
                                slToTry = NormalizeDouble(openPrice + (double)retry * pv, posDigits);
                        }
                        if(trade.PositionModify(ticket, slToTry, 0)) {
                            slMoved = true;
                            tp1Hit[ticketIndex] = true;
                            tp1HitPrice[ticketIndex] = currentPrice;
                            Print("*** SUCCESS: SL moved to break-even: ", slToTry, " ***");
                            Print("  Profit at BE: ", currentProfitPips, " pips | Symbol: ", posSymbol, " | BE Trigger: ", bePips, " pips");
                            break;
                        } else {
                            Print("  Retry ", (retry + 1), "/", maxRetries, ": Failed to move SL. Error: ", trade.ResultRetcode(), " | ", trade.ResultRetcodeDescription());
                            Print("  Ticket: ", ticket, " | Current SL: ", currentSL, " | Target SL: ", slToTry, " | Entry: ", openPrice);
                            if(retry < maxRetries - 1) Sleep(200); // Wait 200ms before retry (longer for Silver)
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
        
        // Step 2: New TP System - TP1, TP2, TP3, TP4 (trade must be in profit)
        // FIXED: TP system now works independently of BE - if profit is high enough, take TP even if BE hasn't been set
        if(currentProfitPips > 0) {
            // CRITICAL: If BE hasn't been set yet but we're past BE threshold, mark it as hit IMMEDIATELY
            // This allows TP system to work even if BE physically failed to move
            // FIXED: Especially important for SELL trades where BE might fail more often
            if(!tp1Hit[ticketIndex] && currentProfitPips >= bePips) {
                tp1Hit[ticketIndex] = true;
                tp1HitPrice[ticketIndex] = currentPrice;
                if(posType == POSITION_TYPE_SELL) {
                    Print("*** SELL TRADE: AUTO-MARKING BE AS HIT (profit=", currentProfitPips, " pips >= ", bePips, " pips) - TP system can now proceed ***");
                    Print("  Entry: ", openPrice, " | Current ASK: ", currentASK, " | Profit: ", currentProfitPips, " pips");
                    Print("  This ensures TP1/TP2/TP3 will trigger for SELL trades even if BE SL move failed!");
                } else {
                    Print("*** AUTO-MARKING BE AS HIT (profit=", currentProfitPips, " pips >= ", bePips, " pips) - TP system can now proceed ***");
                    Print("  This allows TP to trigger even if BE SL move failed!");
                }
            }
            
            // CRITICAL: For Silver, log EVERY profitable trade to diagnose TP issues
            if(isSilver && currentProfitPips > 0) {
                static datetime lastSilverTPLog = 0;
                if(TimeCurrent() - lastSilverTPLog >= 2) {
                    Print("=== SILVER TP SYSTEM CHECK ===");
                    Print("Ticket: ", ticket, " | Profit: ", currentProfitPips, " pips | tp1Hit: ", tp1Hit[ticketIndex]);
                    Print("TP Levels: TP1=", TP1_Pips, " TP2=", TP2_Pips, " TP3=", TP3_Pips, " TP5=", TP5_Pips, " TP6=", TP6_Pips);
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
            
            // TP1: 10 pips - Close 25% OR close smallest position first (layered)
            // CRITICAL: TP1 requires tp1Hit to be true (either BE was moved, or auto-marked)
            // FIXED: For SELL trades, ensure BE is marked even if SL move failed
            if(currentLevel == 0 && currentProfitPips >= TP1_Pips && tp1Hit[ticketIndex] && canCloseMore) {
                // Always partial at TP1 so we leave runners (no full-close of smallest position)
                // TP1: close ONLY TP1_Percent at TP1_Pips (never more than designated %)
                double closeVolume = NormalizeDouble(origVol * (TP1_Percent / 100.0), 2);
                double maxByInput = origVol * (TP1_Percent / 100.0) * 1.01;
                if(closeVolume > maxByInput) closeVolume = maxByInput;
                
                double maxCloseVolume = currentVolume - runnerSize;
                if(closeVolume > maxCloseVolume) closeVolume = maxCloseVolume;
                
                if(closeVolume < minLot) closeVolume = minLot;
                
                if(origVol < 0.1) {
                    double safeClosePercent = MathMin(TP1_Percent, 20.0);
                    closeVolume = NormalizeDouble(origVol * (safeClosePercent / 100.0), 2);
                    if(closeVolume < minLot) closeVolume = minLot;
                }
                
                // Never close more than designated TP1_Percent or 50% of current (strict)
                double maxAllowedClose = MathMin(currentVolume * 0.50, maxByInput);
                if(closeVolume > maxAllowedClose) closeVolume = maxAllowedClose;
                
                double remainingVolume = currentVolume - closeVolume;
                
                // FINAL CHECK: Never close if it would leave less than runner
                if(remainingVolume < runnerSize) {
                    closeVolume = currentVolume - runnerSize; // Adjust to leave exactly runner
                    remainingVolume = runnerSize;
                }
                
                // CRITICAL: Normalize to broker's volume step (fixes "invalid volume")
                closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
                closeVolume = NormalizeDouble(MathMax(minLot, MathMin(closeVolume, currentVolume - minLot)), 2);
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < minLot) { closeVolume = currentVolume - minLot; closeVolume = MathFloor(closeVolume / lotStep) * lotStep; closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2); remainingVolume = currentVolume - closeVolume; }
                
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
                    if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) > 0) {
                        double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
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
            // TP2: close TP2_Percent only (always partial - leave runners)
            else if(currentLevel == 1 && currentProfitPips >= TP2_Pips && canCloseMore) {
                double closeVolume = NormalizeDouble(origVol * (TP2_Percent / 100.0), 2);
                double remainingVolume = currentVolume - closeVolume;
                
                // CRITICAL: Always ensure we leave at least the runner size
                double maxCloseVolume = currentVolume - runnerSize;
                if(closeVolume > maxCloseVolume) {
                    closeVolume = maxCloseVolume; // Don't close more than we can (must leave runner)
                }
                
                // Ensure closeVolume is at least minLot and doesn't exceed current volume
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume * 0.9) closeVolume = NormalizeDouble(currentVolume * 0.9, 2);
                
                // FINAL CHECK: Never close if it would leave less than runner
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < runnerSize) {
                    closeVolume = currentVolume - runnerSize; // Adjust to leave exactly runner
                    remainingVolume = runnerSize;
                }
                closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
                closeVolume = NormalizeDouble(MathMax(minLot, MathMin(closeVolume, currentVolume - minLot)), 2);
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < minLot) { closeVolume = currentVolume - minLot; closeVolume = MathFloor(closeVolume / lotStep) * lotStep; closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2); remainingVolume = currentVolume - closeVolume; }
                
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    // CRITICAL: Verify position still exists before attempting to close
                    if(!position.SelectByTicket(ticket)) {
                        Print("*** TP2 SKIPPED: Position #", ticket, " no longer exists (already closed) ***");
                        continue; // Move to next position
                    }
                    
                    // Check if position is frozen
                    if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) > 0) {
                        double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
                        double priceDistance = MathAbs(currentPrice - openPrice);
                        if(priceDistance <= freezeLevel) {
                            Print("*** TP2 SKIPPED: Position #", ticket, " is frozen (within freeze level) - will retry next tick ***");
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
            // TP3: close TP3_Percent only (always partial - leave runners)
            else if(currentLevel == 2 && currentProfitPips >= TP3_Pips && canCloseMore) {
                double closeVolume = NormalizeDouble(origVol * (TP3_Percent / 100.0), 2);
                double remainingVolume = currentVolume - closeVolume;
                
                // CRITICAL: Always ensure we leave at least the runner size
                double maxCloseVolume = currentVolume - runnerSize;
                if(closeVolume > maxCloseVolume) {
                    closeVolume = maxCloseVolume; // Don't close more than we can (must leave runner)
                }
                
                // Ensure closeVolume is at least minLot and doesn't exceed current volume
                if(closeVolume < minLot) closeVolume = minLot;
                if(closeVolume > currentVolume * 0.9) closeVolume = NormalizeDouble(currentVolume * 0.9, 2);
                
                // FINAL CHECK: Never close if it would leave less than runner
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < runnerSize) {
                    closeVolume = currentVolume - runnerSize; // Adjust to leave exactly runner
                    remainingVolume = runnerSize;
                }
                closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
                closeVolume = NormalizeDouble(MathMax(minLot, MathMin(closeVolume, currentVolume - minLot)), 2);
                remainingVolume = currentVolume - closeVolume;
                if(remainingVolume < minLot) { closeVolume = currentVolume - minLot; closeVolume = MathFloor(closeVolume / lotStep) * lotStep; closeVolume = NormalizeDouble(MathMax(minLot, closeVolume), 2); remainingVolume = currentVolume - closeVolume; }
                
                if(closeVolume >= minLot && remainingVolume >= minLot) {
                    // CRITICAL: Verify position still exists before attempting to close
                    if(!position.SelectByTicket(ticket)) {
                        Print("*** TP3 SKIPPED: Position #", ticket, " no longer exists (already closed) ***");
                        continue; // Move to next position
                    }
                    
                    // Check if position is frozen
                    if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) > 0) {
                        double freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
                        double priceDistance = MathAbs(currentPrice - openPrice);
                        if(priceDistance <= freezeLevel) {
                            Print("*** TP3 SKIPPED: Position #", ticket, " is frozen (within freeze level) - will retry next tick ***");
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
        
        // Step 2b: TP4 - At 150 pips close 10%, leave 15% runner
        if(partialCloseLevel[ticketIndex] == 2 && currentProfitPips >= TP4_Pips && currentProfitPips > 0 && (currentVolume > runnerSize + minLot * 0.5)) {
            double closeVolume = NormalizeDouble(origVol * (TP4_Percent / 100.0), 2);
            if(closeVolume >= minLot) {
                double remainingVolume = NormalizeDouble(currentVolume - closeVolume, 2);
                if(remainingVolume >= minLot) {
                    if(trade.PositionClosePartial(ticket, closeVolume)) {
                        partialCloseLevel[ticketIndex] = 3;
                        Print("*** TP4 HIT: Closed ", closeVolume, " lots (", TP4_Percent, "% of ", origVol, ") at ", TP4_Pips, " pips | Remaining runner (", RunnerSizePercent, "%): ", remainingVolume, " lots ***");
                    }
                }
            }
        }
        
        // Step 3: TP4 alternate - Remaining targets 1H S/R (after TP3)
        if(hasTP4 && TP4_To1H_SR && !hasRunner && !tp5Hit[ticketIndex]) {
            double targetSR = Find1H_SupportResistance(posType == POSITION_TYPE_BUY);
            
            if(targetSR > 0) {
                // Check if price reached 1H S/R (within 5 pips)
                bool reachedSR = false;
                if(posType == POSITION_TYPE_BUY) {
                    reachedSR = currentPrice >= targetSR - (5 * posPipValue);
                } else {
                    reachedSR = currentPrice <= targetSR + (5 * posPipValue);
                }
                
                if(reachedSR) {
                    // Close TP4 (remaining 25%), but keep runner
                    double tp4Volume = NormalizeDouble(origVol * 0.25, 2); // 25% of original
                    double closeVolume = NormalizeDouble(tp4Volume - runnerSize, 2); // Close excess, keep runner
                    
                    if(closeVolume >= minLot && (currentVolume - closeVolume) >= runnerSize) {
                        if(trade.PositionClosePartial(ticket, closeVolume)) {
                            Print("*** TP4 HIT at 1H S/R: Closed ", closeVolume, " lots | Remaining runner (", RunnerSizePercent, "%): ", (currentVolume - closeVolume), " lots ***");
                            partialCloseLevel[ticketIndex] = 4; // Mark TP4 as complete
                        }
                    }
                }
            }
        }
        
        // Step 4: TP5 - Secure profit at TP5_Pips, leave only runner
        // Only run after at least one partial (TP1) so we don't jump from "no partials" to "runner" in one step
        // Cap close at 85% of current volume so we never accidentally full-close (broker rounding)
        if(!tp5Hit[ticketIndex] && partialCloseLevel[ticketIndex] >= 1 && currentProfitPips >= TP5_Pips && currentProfitPips > 0) {
            // Calculate how much to close: everything except the runner, but never more than 85% of current
            double closeVolume = NormalizeDouble(currentVolume - runnerSize, 2);
            double maxCloseByRunner = currentVolume * 0.85; // never close more than 85%
            if(closeVolume > maxCloseByRunner) closeVolume = NormalizeDouble(maxCloseByRunner, 2);
            double remainingAfterClose = currentVolume - closeVolume;
            if(remainingAfterClose < runnerSize) closeVolume = currentVolume - runnerSize; // ensure we leave at least runner
            remainingAfterClose = currentVolume - closeVolume;
            
            // Ensure we can close at least minimum lot and leave at least runner
            if(closeVolume >= minLot && remainingAfterClose >= runnerSize) {
                if(trade.PositionClosePartial(ticket, closeVolume)) {
                    tp5Hit[ticketIndex] = true;
                    partialCloseLevel[ticketIndex] = 5; // Mark TP5 as complete, runner active
                    Print("*** TP5 HIT at ", TP5_Pips, " pips: Secured profit! Closed ", closeVolume, " lots | Remaining runner (", RunnerSizePercent, "%): ", remainingAfterClose, " lots ***");
                    Print("  Original volume: ", origVol, " lots | Runner size: ", runnerSize, " lots");
                } else {
                    Print("ERROR: Failed to close TP5. Error: ", trade.ResultRetcodeDescription());
                }
            } else {
                // If position is too small to close partially, check if we're already at runner size
                if(currentVolume <= runnerSize + minLot * 0.1) {
                    tp5Hit[ticketIndex] = true;
                    partialCloseLevel[ticketIndex] = 5;
                    Print("*** TP5 HIT at ", TP5_Pips, " pips: Position already at runner size (", currentVolume, " lots) ***");
                } else {
                    // Try to close at least 1 lot if we have multiple lots (e.g., 0.03 lots -> close 0.02, leave 0.01)
                    double lotStep = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_STEP);
                    double closeOneLot = MathMax(minLot, lotStep); // Close at least 1 minimum lot or 1 step
                    if(closeOneLot < currentVolume && (currentVolume - closeOneLot) >= minLot) {
                        if(trade.PositionClosePartial(ticket, closeOneLot)) {
                            tp5Hit[ticketIndex] = true;
                            partialCloseLevel[ticketIndex] = 5;
                            Print("*** TP5 HIT at ", TP5_Pips, " pips: Closed ", closeOneLot, " lots | Remaining: ", (currentVolume - closeOneLot), " lots (runner) ***");
                        }
                    }
                }
            }
        }
        
        // Step 4b: TP6 - Extended target at 300 pips: close runner. Never full-close below PLUG_MIN_PIPS_FULL_CLOSE (stops Silver "full at 50").
        if(tp5Hit[ticketIndex] && !tp6Hit[ticketIndex] && currentProfitPips >= TP6_Pips && currentProfitPips >= PLUG_MIN_PIPS_FULL_CLOSE && currentProfitPips > 0) {
            if(trade.PositionClose(ticket)) {
                tp6Hit[ticketIndex] = true;
                Print("*** TP6 HIT at ", TP6_Pips, " pips: Closed runner | Full profit secured! ***");
            } else {
                Print("ERROR: Failed to close TP6 runner. Error: ", trade.ResultRetcodeDescription());
            }
        }
        
        // Step 5: Runner targets 1H S/R. Never full-close below 80 pips (stops Silver "full at 50").
        if(hasRunner && RunnerTo1H_SR && !tp6Hit[ticketIndex] && currentProfitPips >= PLUG_MIN_PIPS_FULL_CLOSE) {
            double targetSR = Find1H_SupportResistance(posType == POSITION_TYPE_BUY);
            
            if(targetSR > 0) {
                bool reachedSR = false;
                if(posType == POSITION_TYPE_BUY) {
                    reachedSR = currentPrice >= targetSR - (5 * posPipValue);
                } else {
                    reachedSR = currentPrice <= targetSR + (5 * posPipValue);
                }
                
                if(reachedSR) {
                    Print("*** Runner reached 1H S/R at ", targetSR, " | Closing runner ***");
                    trade.PositionClose(ticket);
                }
            }
        }
        
        // Step 5a: Dynamic Trail - close on structure reversal (BOS/CHoCH) to exit with a win (same logic Gold & Silver)
        if(UseDynamicTrail && UseMarketStructure && currentProfitPips > 0 && posSymbol == _Symbol) {
            bool reversalAgainstBuy  = (posType == POSITION_TYPE_BUY  && marketStruct.trend == -1);
            bool reversalAgainstSell  = (posType == POSITION_TYPE_SELL && marketStruct.trend == 1);
            if(reversalAgainstBuy || reversalAgainstSell) {
                if(trade.PositionClose(ticket)) {
                    Print("*** Dynamic Trail: Structure reversal (trend=", marketStruct.trend, ") | Closed #", ticket, " with ", DoubleToString(currentProfitPips, 1), " pips profit ***");
                    continue;
                }
            }
        }
        
        // Step 5b: Trail SL when profit >= TrailStartPips (Gold & Silver)
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
#ifdef PLUG_SYMBOL_GOLD
            double slPipsUse = SL_Pips;
#else
#ifdef PLUG_SYMBOL_SILVER
            double slPipsUse = SL_Pips_Silver;
#else
            double slPipsUse = isSilver ? SL_Pips_Silver : SL_Pips;
#endif
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
