//last error message number: E003

input    string   opening = "--- Opening ---"; 
input    int      days_before = 4;
input    int      open_not_before_hour = 10;
input    int      open_not_after_hour = 18;

input    string   closing = "--- Closing ---";
input    int      days_after = 0;
input    int      close_not_before_hour = 13;
input    int      close_not_after_hour = 15;

input    string   indicators = "--- indicator fine tuning ---"; 
input    int      rsi_period = 3;
input    double   rsi_absolute_threshold = 15.0;

input    string   money_managment = "--- money management ---";
input    double   fix_lots = 1.0;   

input    string   magic_settings = "--- Magic ---";   
input    int      myMagic = 20200105;  
input    int      trace = 0;                          

int      ticket         = -1;
datetime lastbar        = NULL;
datetime hexensabat     = NULL;
datetime opendate       = NULL;
datetime closedate      = NULL;
int      quartal        = -1;

int OnInit() {
   
   // initialize ticket with any existing ticket number that qualifies:
   // by magic number
   // by symbol
   
   // this is required in case the EA is restarted while a position is open
   // note that positions are only closed in the "closing time window", that is, 
   // if the EA is stopped during that window, positions have to be closed manually.
   
   for (int i=OrdersTotal(); i>=0;i--) {
      if (OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) {
         if ( OrderMagicNumber() == myMagic &&
              OrderSymbol() == _Symbol) {
              ticket = OrderTicket();
              break;
         }
      }
   }
   
   return(INIT_SUCCEEDED);
   
}

void OnDeinit(const int reason) {

}

void OnTick() {
   // nur in durch 3 teilbaren Monaten rechnen
   if (Month()%3 > 0)return; 
      
   // nur einmal pro Kerze rechnen
   if (Time[1] == lastbar) return; 
   lastbar = Time[1]; 
   
   // das Datum des Verfalls muss ausgerechnet werden, wenn es noch unbekannt ist oder ein neues Quartal begonnen hat.
   if (quartal != Month()/3 || hexensabat == NULL) setHexensabat();
   
   if ( -1 == ticket && isDate(opendate)) {
      ticket = buy();
   }
   
   if ( -1 != ticket && isDateOrAfter(closedate)) {
      ticket = close();
   } 
}   

void setHexensabat() {
      if (trace>=1) Print("setHexensabat ENTRY");
      int fridays=0;
   
      for (int day = 1 ; day < 30 ; day++) {
         string datestring = StringFormat("%4i.%02i.%02i", Year(), Month(),day);
         datetime testDate = StringToTime(datestring);
         MqlDateTime testDateStruct;
         TimeToStruct(testDate,testDateStruct);
         
         if (testDateStruct.day_of_week == FRIDAY) {
            fridays++;
            if(fridays==3) {
               hexensabat = testDate;
               
               datestring = StringFormat("%4i.%02i.%02i", Year(), Month(), (day - days_before));
               opendate   = StringToTime(datestring);
               
               datestring = StringFormat("%4i.%02i.%02i", Year(), Month(), (day + days_after));
               closedate   = StringToTime(datestring);
               
               quartal    = Month()/3;
               break;
            }
         }
         
      }
      if (trace>=1) PrintFormat("setHexensabat EXIT, opendate: %s, closedate: %s, hexensabat: %s", 
         TimeToStr(opendate, TIME_DATE),
         TimeToStr(closedate, TIME_DATE),
         TimeToStr(hexensabat, TIME_DATE));
}

bool isDate(datetime datetocompare) {
   if (trace>=1) PrintFormat("isDate ENTRY %s", TimeToStr(datetocompare, TIME_DATE));
   
   bool isToday = false;
   
   MqlDateTime date1, date2;
   TimeCurrent(date2);
   TimeToStruct(datetocompare,date1);
   
   if ( date1.day   == date2.day &&
        date1.mon   == date2.mon &&  
        date1.year  == date2.year) {
      isToday = true;
   }
   
   if (trace>=1) Print("isDate EXIT: ", isToday);
   return isToday;
}

bool isDateOrAfter(datetime datetocompare) {
   if (trace>=1) PrintFormat("isDateOrAfter ENTRY %s", TimeToStr(datetocompare, TIME_DATE));
   
   bool isToday = false;
   
   MqlDateTime date1, date2;
   TimeCurrent(date2);
   TimeToStruct(datetocompare,date1);
   
   if ( date1.day   <= date2.day &&
        date1.mon   == date2.mon &&  
        date1.year  == date2.year) {
      isToday = true;
   }
   
   if (trace>=1) Print("isDateOrAfter EXIT: ", isToday);
   return isToday;
}

int buy() {
   int buyticket = -1;
   if (trace>=1) PrintFormat("buy ENTRY");
   
   bool buy_now = false;
   
   if (TimeHour(TimeCurrent()) < open_not_before_hour) {
      if (trace>=1) Print("buy EXIT: ", buyticket);
      return buyticket;
   }
   
   if (TimeHour(TimeCurrent()) >= open_not_after_hour) buy_now = true;
   
   if (!buy_now) {
      double rsi = iRSI(_Symbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE, 1);
      if ( rsi < rsi_absolute_threshold) buy_now = true;
   }
   
   if (buy_now) {
      buyticket = OrderSend(_Symbol, OP_BUY, fix_lots, Ask, 1000, 0, 0, "Hexen", myMagic,0,clrGreen);
      if (-1 == buyticket) {
         PrintFormat("E003: Cannot open order! %i", GetLastError());
      }
   }
 
   if (trace>=1) Print("buy EXIT: ", buyticket);
   return buyticket;
}


int close() {
   int closeticket = ticket;
   if (trace>=1) PrintFormat("close ENTRY");
   
   bool close_now = false;
   
   if (TimeHour(TimeCurrent()) < close_not_before_hour) {
      if (trace>=1) Print("close EXIT (too early): ", closeticket);
      return closeticket;
   }
   
   if (TimeHour(TimeCurrent()) >= close_not_after_hour) close_now = true;
   
   if (!close_now) {
      double rsi = iRSI(_Symbol, PERIOD_CURRENT, rsi_period, PRICE_CLOSE, 1);
      if ( rsi > (100 - rsi_absolute_threshold)) close_now = true;
   }
   
   if (close_now) {
      if (OrderSelect(ticket, SELECT_BY_TICKET,MODE_TRADES)) {
         if (OrderClose(OrderTicket(), OrderLots(),Bid,1000,clrGreen)) {
            closeticket = -1;
         } else {
            PrintFormat("E002: Cannot close order by ticket! %i", GetLastError());
         }
      } else {
         PrintFormat("E001: Cannot select order by ticket! %i", GetLastError());
      }
   } else {
      if (trace>=1) PrintFormat("waiting to close");
   }
   
   if (trace>=1) Print("close EXIT: ", closeticket);
   return closeticket;
}