echo "-============- Credit Features By -=============-"
echo "   - CMD TWEAK By @HoyoSlave "
echo "   - GMS Optimizer By @Kazuyoo"
echo "-===========================================-"
echo "  Build Date : Selasa, 13 Januari 2026"
echo "-==========-> INFORMATION PLUGIN <-==========-"
cek=$(pgrep -f lex.sh)
if [ -n $cek ]; then
  echo "[ SYSTEM ] : Running Smart Cache Cleaner"
  echo "[ INFO ]┬[PID] $(pgrep -f lex.sh | head -n 1) Running System"
  echo "        └[VERSION] 1.7.6-Dex"
else 
  echo "[ SYSTEM ] : System Smart Cache Cleaner Denied Killing"
  echo "[ INFO ]┬[PID] $(pgrep -f lex.sh) Not Running System"
  echo "        └[VERSION] 1.7.6-Dex"
fi