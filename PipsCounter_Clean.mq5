//+------------------------------------------------------------------+
//|                                           PipsCounter_Clean.mq5 |
//|                          Clean Pips Counter - NO OVERLAPPING     |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0

// ---------------- INPUTS ----------------
input string SymbolXAU     = "XAUUSD";     // Gold Symbol
input string SymbolXAG     = "XAGUSD";     // Silver Symbol
input int    CornerPosition= 2;            // 0=Top-Left, 1=Top-Right, 2=Bottom-Left, 3=Bottom-Right
input int    OffsetX       = 20;           // Distance from corner (horizontal)
input int    OffsetY       = 20;           // Distance from corner (vertical)
input int    PanelWidth    = 250;
input int    PanelHeight   = 180;
input color  BgColor       = C'250,250,250';
input color  BorderColor   = C'100,100,100';
input color  TextColor     = C'50,50,50';
input color  ProfitColor   = C'0,150,0';
input color  LossColor     = C'200,0,0';

// ---------------- GLOBALS ----------------
string OBJ_PREFIX = "PIPSCLEAN_";
int g_x = 0;
int g_y = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   CalculatePosition();
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

void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      CalculatePosition();
      RepositionDisplay();
   }
}

//+------------------------------------------------------------------+
//| CALCULATE POSITION                                               |
//+------------------------------------------------------------------+
void CalculatePosition()
{
   int chartWidth  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);

   switch(CornerPosition)
   {
      case 0: // Top-Left
         g_x = OffsetX;
         g_y = OffsetY;
         break;
      case 1: // Top-Right
         g_x = chartWidth - PanelWidth - OffsetX;
         g_y = OffsetY;
         break;
      case 2: // Bottom-Left
         g_x = OffsetX;
         g_y = chartHeight - PanelHeight - OffsetY;
         break;
      case 3: // Bottom-Right
         g_x = chartWidth - PanelWidth - OffsetX;
         g_y = chartHeight - PanelHeight - OffsetY;
         break;
      default:
         g_x = chartWidth - PanelWidth - OffsetX;
         g_y = chartHeight - PanelHeight - OffsetY;
         break;
   }

   if(g_x < 0) g_x = 0;
   if(g_y < 0) g_y = 0;
}

//+------------------------------------------------------------------+
//| CREATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void CreateDisplay()
{
   // Background panel
   string bg = OBJ_PREFIX + "BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, g_x);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, g_y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, PanelWidth);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE, PanelHeight);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, BgColor);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, BorderColor);
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_BACK, false);
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);

   // Create all labels with MASSIVE spacing
   CreateLabel("TITLE",      "PIPS",       15, 12,  11, TextColor);
   
   CreateLabel("XAU_LBL",    "Gold",       15, 45,  9,  TextColor);
   CreateLabel("XAU_VAL",    "",           15, 60,  10, ProfitColor);
   
   CreateLabel("XAG_LBL",    "Silver",     15, 95,  9,  TextColor);
   CreateLabel("XAG_VAL",    "",           15, 110, 10, ProfitColor);
   
   CreateLabel("PL_LBL",     "P/L",        15, 145, 9,  TextColor);
   CreateLabel("PL_VAL",     "",           15, 160, 10, ProfitColor);
}

void CreateLabel(string name, string text, int x, int y, int fsize, color clr)
{
   string obj = OBJ_PREFIX + name;
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, g_x + x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, g_y + y);
   ObjectSetInteger(0, obj, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, obj, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetString(0, obj, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, fsize);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, obj, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, obj, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| REPOSITION DISPLAY                                               |
//+------------------------------------------------------------------+
void RepositionDisplay()
{
   ObjectSetInteger(0, OBJ_PREFIX + "BG", OBJPROP_XDISTANCE, g_x);
   ObjectSetInteger(0, OBJ_PREFIX + "BG", OBJPROP_YDISTANCE, g_y);
   
   SetLabelPos("TITLE",   15, 12);
   SetLabelPos("XAU_LBL", 15, 45);
   SetLabelPos("XAU_VAL", 15, 60);
   SetLabelPos("XAG_LBL", 15, 95);
   SetLabelPos("XAG_VAL", 15, 110);
   SetLabelPos("PL_LBL",  15, 145);
   SetLabelPos("PL_VAL",  15, 160);
}

void SetLabelPos(string name, int x, int y)
{
   string obj = OBJ_PREFIX + name;
   if(ObjectFind(0, obj) >= 0)
   {
      ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, g_x + x);
      ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, g_y + y);
   }
}

//+------------------------------------------------------------------+
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   double pipsXAU = 0.0;
   double pipsXAG = 0.0;
   double plTotal = 0.0;
   double volXAU = 0.0;
   double volXAG = 0.0;
   double profitXAU = 0.0;
   double profitXAG = 0.0;

   // Collect P/L and volume for each symbol
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         
         if(sym == SymbolXAU)
         {
            profitXAU += profit;
            volXAU += volume;
         }
         else if(sym == SymbolXAG)
         {
            profitXAG += profit;
            volXAG += volume;
         }
      }
   }
   
   plTotal = profitXAU + profitXAG;
   
   // Derive pips from P/L: Gold $10/pip/lot, Silver $50/pip/lot
   // $1 Gold = 10 pips, $1 Silver = 100 pips
   if(volXAU > 0)
      pipsXAU = profitXAU / (10.0 * volXAU);  // $10 per pip per standard lot
   if(volXAG > 0)
      pipsXAG = profitXAG / (50.0 * volXAG);  // $50 per pip per standard lot (5000 oz)

   // Update values
   UpdateValue("XAU_VAL", pipsXAU);
   UpdateValue("XAG_VAL", pipsXAG);
   
   string plText = (plTotal >= 0 ? "+" : "") + DoubleToString(plTotal, 2);
   ObjectSetString(0, OBJ_PREFIX + "PL_VAL", OBJPROP_TEXT, plText);
   ObjectSetInteger(0, OBJ_PREFIX + "PL_VAL", OBJPROP_COLOR, plTotal >= 0 ? ProfitColor : LossColor);
}

void UpdateValue(string name, double pips)
{
   string obj = OBJ_PREFIX + name;
   string text = (pips >= 0 ? "+" : "") + DoubleToString(pips, 1);
   ObjectSetString(0, obj, OBJPROP_TEXT, text);
   ObjectSetInteger(0, obj, OBJPROP_COLOR, pips >= 0 ? ProfitColor : LossColor);
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
