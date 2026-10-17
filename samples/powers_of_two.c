/* Sample 1: multiplication by powers of two.
 * Every `mul` below should become a single `shl`.                          */
int printf(const char *, ...);

int mul2(int x)    { return x * 2; }
int mul8(int x)    { return x * 8; }
int mul64(int x)   { return x * 64; }
int mul1024(int x) { return 1024 * x; }          /* constant on the left   */

long long mul4096_i64(long long x) { return x * 4096; }
unsigned mul16_u32(unsigned x)     { return x * 16u; }

/* Loop-carried use: the shifted value feeds an accumulator. */
int sum_scaled(const int *a, int n) {
  int s = 0;
  for (int i = 0; i < n; ++i)
    s += a[i] * 32;
  return s;
}

int main(void) {
  int data[8] = {1, -2, 3, -4, 5, -6, 7, 100000};
  int acc = 0;
  for (int i = 0; i < 8; ++i) {
    int v = data[i];
    acc += mul2(v) + mul8(v) + mul64(v) + mul1024(v);
    acc ^= (int)mul4096_i64(v) + (int)mul16_u32((unsigned)v);
  }
  printf("powers_of_two: acc=%d sum=%d\n", acc, sum_scaled(data, 8));
  return 0;
}
