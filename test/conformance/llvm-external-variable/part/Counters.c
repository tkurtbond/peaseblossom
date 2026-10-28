/* llvm-external-variable: the storage Counters.Mod's external variables
   name, defined and initialised here, not by poc */
int counter = 41;
int counters_table[4] = {1, 2, 3, 4};
struct { int first, second; } counters_pair = {7, 8};

int counters_sum(void)
{
  return counter + counters_table[0] + counters_table[1] + counters_table[2] + counters_table[3]
    + counters_pair.first + counters_pair.second;
}
