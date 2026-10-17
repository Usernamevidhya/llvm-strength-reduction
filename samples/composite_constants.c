/* Sample 2: composite constants 2^a + 2^b and 2^a - 2^b.
 * Expected: shl+add (3, 5, 9, 10, 12, 24, 33) and shl+sub (7, 15, 31, 14).
 * 11 and 100 are not of that shape and must remain `mul`.                  */
int printf(const char *, ...);

int mul3(int x)  { return x * 3; }    /* 2^1 + 2^0 */
int mul5(int x)  { return x * 5; }    /* 2^2 + 2^0 */
int mul9(int x)  { return x * 9; }    /* 2^3 + 2^0 */
int mul10(int x) { return x * 10; }   /* 2^3 + 2^1 */
int mul12(int x) { return x * 12; }   /* 2^3 + 2^2 */
int mul24(int x) { return 24 * x; }   /* 2^4 + 2^3 */
int mul33(int x) { return x * 33; }   /* 2^5 + 2^0 */

int mul7(int x)  { return x * 7; }    /* 2^3 - 2^0 */
int mul14(int x) { return x * 14; }   /* 2^4 - 2^1 */
int mul15(int x) { return x * 15; }   /* 2^4 - 2^0 */
int mul31(int x) { return x * 31; }   /* 2^5 - 2^0 */

int mul11(int x)  { return x * 11; }  /* NOT reducible */
int mul100(int x) { return x * 100; } /* NOT reducible */

unsigned long long mul_big(unsigned long long x) {
  return x * 0x100000001ULL;          /* 2^32 + 2^0 */
}

int main(void) {
  int acc = 0;
  for (int v = -50; v <= 50; ++v) {
    acc += mul3(v) + mul5(v) + mul9(v) + mul10(v) + mul12(v) + mul24(v) +
           mul33(v);
    acc ^= mul7(v) + mul14(v) + mul15(v) + mul31(v);
    acc += mul11(v) - mul100(v);
  }
  printf("composite_constants: acc=%d big=%llu\n", acc, mul_big(12345ULL));
  return 0;
}
