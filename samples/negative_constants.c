/* Sample 3: negative multipliers.
 *   -1, -8          ->  neg / shl+neg
 *   -3, -12         ->  -(2^a + 2^b)  : shl, add, neg
 *   -7, -14, -15    ->  -(2^a - 2^b)  : operands of the sub are swapped
 *   -100            ->  not reducible, stays `mul`                          */
int printf(const char *, ...);

int mulm1(int x)   { return x * -1; }
int mulm2(int x)   { return x * -2; }
int mulm8(int x)   { return x * -8; }
int mulm3(int x)   { return x * -3; }
int mulm12(int x)  { return -12 * x; }
int mulm7(int x)   { return x * -7; }
int mulm14(int x)  { return x * -14; }
int mulm15(int x)  { return x * -15; }
int mulm100(int x) { return x * -100; }               /* NOT reducible */

/* INT_MIN is 2^31 as a bit pattern -> shl x, 31 (nsw must be dropped). */
int mul_int_min(int x) { return x * (-2147483647 - 1); }

long long mulm5_i64(long long x) { return x * -5LL; }

int main(void) {
  int acc = 0;
  for (int v = -40; v <= 40; ++v) {
    acc += mulm1(v) + mulm2(v) + mulm8(v) + mulm3(v) + mulm12(v);
    acc ^= mulm7(v) + mulm14(v) + mulm15(v) + mulm100(v);
    acc += mul_int_min(v);
    acc += (int)mulm5_i64(v);
  }
  printf("negative_constants: acc=%d\n", acc);
  return 0;
}
