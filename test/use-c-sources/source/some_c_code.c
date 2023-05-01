
#include <stdio.h>

#include "some_c_code.h"

// Some test functions follow to proof that C code can be called from D main()

void relatedCode(size_t aNumber)
{
	printf("Hallo! This is some output from C code! (%d)\n", aNumber);
}

uint64_t multiplyU64byU32(uint64_t*a, uint32_t*b)
{
    return *a * *b;
}

uint64_t multiplyAndAdd(uint32_t*arr, size_t arrlen, uint32_t mult)
{
    uint64_t acc = 0;
    for (int i = 0; i < arrlen; i++)
    {
        acc += arr[i]*mult;
    }
    return acc;
}

uint64_t fac(uint64_t n)
{
	if (n > 1)
		return n * fac(n-1);
	else
		return 1;
}
