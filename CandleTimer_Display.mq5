//+------------------------------------------------------------------+
//|                                         CandleTimer_Display.mq5 |
//|                              Candle Closure Countdown Indicator  |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0

// ---------------- INPUTS ----------------
input int    PanelX        = 20;           // X Position
input int    PanelY        = 320;          // Y Position (below account info)
input int    PanelWidth    = 120;
input int    PanelHeight   = 110;
input int    FontSize      = 8;
input int    TimerFontSize = 12;           // Larger font for countdown
input color  BgColor       = C'250,250,250';
input color  BorderColor   = C'100,100,100';
input color  TextColor     = C'50,50,50';
input color  TimerColor    = C'0,100,200'; // Blue for timer
input color  UrgentColor   = C'200,0,0';   // Red when < 1 minute
input bool   ShowSeconds   = true;         // Show seconds in countdown

// ---------------- GLOBALS ----------------
string OBJ_PREFIX = "CANDLETIMER_";

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
   CreateLabel("TITLE", "TIMER", 8, 10, FontSize, TextColor);

   // Timeframe
   CreateLabel("TF_VALUE", "", 8, 38, FontSize, TextColor);

   // Timer on its own line with plenty of space
   CreateLabel("TIME_VALUE", "", 8, 68, TimerFontSize, TimerColor);
}

void CreateLabel(string name, string text, int x, int y, int fsize, color clr)
{
   string obj = OBJ_PREFIX + name;
   ObjectCreate(0, obj, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, obj, OBJPROP_XDISTANCE, PanelX + x);
   ObjectSetInteger(0, obj, OBJPROP_YDISTANCE, PanelY + y);
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
//| UPDATE DISPLAY                                                   |
//+------------------------------------------------------------------+
void UpdateDisplay()
{
   // Get current timeframe
   ENUM_TIMEFRAMES tf = Period();
   string tfName = GetTimeframeName(tf);
   ObjectSetString(0, OBJ_PREFIX + "TF_VALUE", OBJPROP_TEXT, tfName);

   // Calculate time until candle close
   datetime currentTime = TimeCurrent();
   int periodSeconds = PeriodSeconds(tf);
   int secondsSinceOpen = (int)(currentTime % periodSeconds);
   int secondsRemaining = periodSeconds - secondsSinceOpen;

   // Format time string
   string timeStr = FormatTime(secondsRemaining);
   
   // Update timer
   ObjectSetString(0, OBJ_PREFIX + "TIME_VALUE", OBJPROP_TEXT, timeStr);
   
   // Change color if less than 1 minute remaining
   color timerClr = (secondsRemaining < 60) ? UrgentColor : TimerColor;
   ObjectSetInteger(0, OBJ_PREFIX + "TIME_VALUE", OBJPROP_COLOR, timerClr);
}

//+------------------------------------------------------------------+
//| FORMAT TIME                                                      |
//+------------------------------------------------------------------+
string FormatTime(int totalSeconds)
{
   int hours = totalSeconds / 3600;
   int minutes = (totalSeconds % 3600) / 60;
   int seconds = totalSeconds % 60;

   string result = "";
   
   if(hours > 0)
   {
      result = StringFormat("%d:%02d:%02d", hours, minutes, seconds);
   }
   else if(minutes > 0)
   {
      if(ShowSeconds)
         result = StringFormat("%d:%02d", minutes, seconds);
      else
         result = StringFormat("%dm", minutes);
   }
   else
   {
      result = StringFormat("%ds", seconds);
   }

   return result;
}

//+------------------------------------------------------------------+
//| GET TIMEFRAME NAME                                               |
//+------------------------------------------------------------------+
string GetTimeframeName(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "Unknown";
   }
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
