//+------------------------------------------------------------------+
//|                                          AccountInfo_Display.mq5 |
//|                          Clean Account & P/L Display for XAU/XAG |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0

// ---------------- INPUTS ----------------
input string SymbolXAU     = "XAUUSD";     // Gold Symbol
input string SymbolXAG     = "XAGUSD";     // Silver Symbol
input int    PanelX        = 20;           // X Position
input int    PanelY        = 20;           // Y Position
input int    PanelWidth    = 350;
input int    PanelHeight   = 280;
input int    FontSize      = 12;
input color  BgColor       = C'250,250,250';
input color  BorderColor   = C'100,100,100';
input color  TextColor     = C'50,50,50';
input color  ValueColor    = C'20,20,20';
input color  ProfitColor   = C'0,150,0';
input color  LossColor     = C'200,0,0';

// ---------------- GLOBALS ----------------
string OBJ_PREFIX = "ACCINFO_";

//+------------------------------------------------------------------+
int OnInit()
{
   CreateDisplay();
   UpdateDisplay();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllObjects();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
{
   return(rates_total);
}

void OnTimer()
{
   UpdateDisplay();
}

//+------------------------------------------------------------------+
//| CREATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void CreateDisplay()
{
   // Background panel
   string bg = OBJ_PREFIX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, PanelX);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, PanelY);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, PanelWidth);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, PanelHeight);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, BgColor);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, BorderColor);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);

   // Title
   CreateLabel("TITLE", "ACCOUNT INFO", 15, 20, true, TextColor);

   // Labels
   CreateLabel("LBL_BAL",  "Balance",      15, 55,  false, TextColor);
   CreateLabel("LBL_EQ",   "Equity",       15, 85,  false, TextColor);
   CreateLabel("LBL_MRG",  "Margin",       15, 115, false, TextColor);
   CreateLabel("LBL_FREE", "Free Margin",  15, 145, false, TextColor);
   CreateLabel("LBL_XAU",  "Gold P/L",     15, 185, false, TextColor);
   CreateLabel("LBL_XAG",  "Silver P/L",   15, 215, false, TextColor);
   CreateLabel("LBL_TOTAL","Total P/L",    15, 245, false, TextColor);

   // Values (will be updated)
   CreateLabel("VAL_BAL",  "",  200, 55,  false, ValueColor);
   CreateLabel("VAL_EQ",   "",  200, 85,  false, ValueColor);
   CreateLabel("VAL_MRG",  "",  200, 115, false, ValueColor);
   CreateLabel("VAL_FREE", "",  200, 145, false, ValueColor);
   CreateLabel("VAL_XAU",  "",  200, 185, false, ProfitColor);
   CreateLabel("VAL_XAG",  "",  200, 215, false, ProfitColor);
   CreateLabel("VAL_TOTAL","",  200, 245, false, ProfitColor);
}

void CreateLabel(string name, string text, int x, int y, bool bold, color clr)
{
   string obj = OBJ_PREFIX + name;
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, PanelX + x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, PanelY + y);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, FontSize + (bold ? 3 : 0));
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   // Get account info
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin  = AccountInfoDouble(ACCOUNT_MARGIN);
   double free    = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // Calculate P/L for each symbol
   double plXAU = 0.0;
   double plXAG = 0.0;

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         if(sym == SymbolXAU) plXAU += profit;
         if(sym == SymbolXAG) plXAG += profit;
      }
   }

   double plTotal = plXAU + plXAG;

   // Update values
   ObjectSetString(0, OBJ_PREFIX + "VAL_BAL",  OBJPROP_TEXT, FormatMoney(balance));
   ObjectSetString(0, OBJ_PREFIX + "VAL_EQ",   OBJPROP_TEXT, FormatMoney(equity));
   ObjectSetString(0, OBJ_PREFIX + "VAL_MRG",  OBJPROP_TEXT, FormatMoney(margin));
   ObjectSetString(0, OBJ_PREFIX + "VAL_FREE", OBJPROP_TEXT, FormatMoney(free));

   // Update P/L with colors
   UpdatePLValue("VAL_XAU", plXAU);
   UpdatePLValue("VAL_XAG", plXAG);
   UpdatePLValue("VAL_TOTAL", plTotal);
}

void UpdatePLValue(string name, double value)
{
   string obj = OBJ_PREFIX + name;
   ObjectSetString(0, obj, OBJPROP_TEXT, FormatMoney(value));
   ObjectSetInteger(0, obj, OBJPROP_COLOR, value >= 0 ? ProfitColor : LossColor);
}

string FormatMoney(double value)
{
   return DoubleToString(value, 2);
}

//+------------------------------------------------------------------+
//| CLEANUP                                                          |
//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, OBJ_PREFIX) == 0)
      {
         ObjectDelete(0, name);
      }
   }
}
//+------------------------------------------------------------------+
