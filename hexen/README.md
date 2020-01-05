# Hexen
Based on [Heiße Hexen](https://www.andre-stagge.de/heisse-hexen/) by André Stagge.

# Backtests
## DAX30 M15 2012-2019
[Test settings](dax30_m15.set):
* buy 10:00 - 18:00 at RSI(3) 15, but no later than 18:00 local time
* close 13:00 - 15:00 at RSI(3) 85, but no later than 15:00 local time 

Note that "no later than" settings are early because of missing data in tick data suite.

![graph](hexen-backtest1-graph.png)
![report](hexen-backtest1-report.png)
