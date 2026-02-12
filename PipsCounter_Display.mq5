//+------------------------------------------------------------------+
//|                                         PipsCounter_Display.mq5 |
//|                              Live Pips Counter with Positioning  |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0

// ---------------- INPUTS ----------------
input string SymbolXAU     = "XAUUSD";     // Gold Symbol
input string SymbolXAG     = "XAGUSD";     // Silver Symbol
input int    CornerPosition= 3;            // 0=Top-Left, 1=Top-Right, 2=Bottom-Left, 3=Bottom-Right
input int    OffsetX       = 20;           // Distance from corner (horizontal)
input int    OffsetY       = 130;          // Distance from corner (vertical) - INCREASED FOR SPACING
input int    PanelWidth    = 320;
input int    PanelHeight   = 150;
input int    FontSize      = 9;
input int    PipsFontSize  = 10;           // Larger font for pips values
input color  BgColor       = C'250,250,250';
input color  BorderColor   = C'100,100,100';
input color  TextColor     = C'50,50,50';
input color  ProfitColor   = C'0,150,0';
input color  LossColor     = C'200,0,0';

// ---------------- GLOBALS ----------------
string OBJ_PREFIX = "PIPSCOUNTER_";
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
   // Reposition on chart resize
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      CalculatePosition();
      RepositionDisplay();
   }
}

//+------------------------------------------------------------------+
//| CALCULATE POSITION BASED ON CORNER                              |
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
      default: // Bottom-Right
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

   // Title
   CreateLabel("TITLE", "PIPS COUNTER", 10, 10, FontSize + 1, TextColor);

   // Gold section
   CreateLabel("XAU_LABEL", "Gold:", 10, 42, FontSize, TextColor);
   CreateLabel("XAU_PIPS", "", 140, 42, PipsFontSize, ProfitColor);

   // Silver section
   CreateLabel("XAG_LABEL", "Silver:", 10, 72, FontSize, TextColor);
   CreateLabel("XAG_PIPS", "", 140, 72, PipsFontSize, ProfitColor);

   // Total section
   CreateLabel("TOTAL_LABEL", "Total:", 10, 102, FontSize, TextColor);
   CreateLabel("TOTAL_PIPS", "", 140, 102, PipsFontSize, ProfitColor);

   // Profit/Loss in currency
   CreateLabel("PL_LABEL", "P/L:", 10, 132, FontSize, TextColor);
   CreateLabel("PL_VALUE", "", 140, 132, FontSize + 1, ProfitColor);
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
//| REPOSITION ALL OBJECTS                                           |
//+------------------------------------------------------------------+
void RepositionDisplay()
{
   ObjectSetInteger(0, OBJ_PREFIX + "BG", OBJPROP_XDISTANCE, g_x);
   ObjectSetInteger(0, OBJ_PREFIX + "BG", OBJPROP_YDISTANCE, g_y);

   // Reposition all labels
   SetLabelPosition("TITLE", 10, 10);
   SetLabelPosition("XAU_LABEL", 10, 42);
   SetLabelPosition("XAU_PIPS", 140, 42);
   SetLabelPosition("XAG_LABEL", 10, 72);
   SetLabelPosition("XAG_PIPS", 140, 72);
   SetLabelPosition("TOTAL_LABEL", 10, 102);
   SetLabelPosition("TOTAL_PIPS", 140, 102);
   SetLabelPosition("PL_LABEL", 10, 132);
   SetLabelPosition("PL_VALUE", 140, 132);
}

void SetLabelPosition(string name, int x, int y)
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
   double plXAU = 0.0;
   double plXAG = 0.0;

   // Calculate pips and P/L for each symbol
   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0)
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         double profit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         long posType = PositionGetInteger(POSITION_TYPE);
         
         if(sym == SymbolXAU)
         {
            double pipDiff = 0.0;
            if(posType == POSITION_TYPE_BUY)
               pipDiff = currentPrice - openPrice;
            else
               pipDiff = openPrice - currentPrice;
            
            // For gold, 1 pip = 0.10 (10 cents movement)
            pipsXAU += (pipDiff / 0.10) * volume;
            plXAU += profit;
         }
         else if(sym == SymbolXAG)
         {
            double pipDiff = 0.0;
            if(posType == POSITION_TYPE_BUY)
               pipDiff = currentPrice - openPrice;
            else
               pipDiff = openPrice - currentPrice;
            
            // For silver, 1 pip = 0.01 (1 cent movement) - STANDARD FOREX PIP
            // This matches: 40 cents move = 40 pips
            pipsXAG += (pipDiff / 0.01) * volume;
            plXAG += profit;
         }
      }
   }

   double totalPips = pipsXAU + pipsXAG;
   double totalPL = plXAU + plXAG;

   // Update Gold pips
   UpdatePipsValue("XAU_PIPS", pipsXAU);
   
   // Update Silver pips
   UpdatePipsValue("XAG_PIPS", pipsXAG);
   
   // Update Total pips
   UpdatePipsValue("TOTAL_PIPS", totalPips);
   
   // Update P/L value
   string plText = (totalPL >= 0 ? "+" : "") + DoubleToString(totalPL, 2);
   ObjectSetString(0, OBJ_PREFIX + "PL_VALUE", OBJPROP_TEXT, plText);
   ObjectSetInteger(0, OBJ_PREFIX + "PL_VALUE", OBJPROP_COLOR, totalPL >= 0 ? ProfitColor : LossColor);
}

void UpdatePipsValue(string name, double pips)
{
   string obj = OBJ_PREFIX + name;
   string pipsText = (pips >= 0 ? "+" : "") + DoubleToString(pips, 1) + " pips";
   ObjectSetString(0, obj, OBJPROP_TEXT, pipsText);
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
