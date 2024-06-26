// PARAM: --enable ana.int.interval_set --set ana.context.gas_value 10
// Without context-insensitive analysis: Stack Overflow
#include <stdio.h>

int ack(int n, int m)
{
    if (n == 0)
    {
        return m + 1;
    }
    else
    {
        if (m == 0)
        {
            return ack(n - 1, 1);
        }
        else
        {
            return ack(n - 1, ack(n, m - 1));
        }
    }
}

int main(void)
{
    ack(4, 1);
    __goblint_check(1); // reachable
}