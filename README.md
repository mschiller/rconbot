# rconbot

A bot that sits on your server, administrates a match, collects statistics, and records via HLTV

## What's inside

* Bundled sinatra app for viewing match statistics
* The 'rconbot' binary file that
 * connects to specified HLDS server via RCon and executes clan.cfg
 * loads the warm-up config and waits for players to say 'ready' and executes the lo3.cfg
 * waits for the end of a half, and does the above step again for the 2nd half
 * waits for the end of the match
 * saves the statistics
 * kicks everyone out
 * executes pub.cfg
