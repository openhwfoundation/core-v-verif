/*
 ** Demonstrate that software can write and read back all 32 bits of the 
 ** mscratch CSR (CSR address 0x340) on an RV32 core, meaning:
 **    no bits are stuck-at 0 or 1,
 **    no masking/truncation (e.g., only low 16 bits implemented),
 **    reads return exactly what was written.
 **/

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>

static inline void mscratch_write(uint32_t v)
{
  __asm__ volatile("csrw 0x340, %0" :: "r"(v));
}

static inline uint32_t mscratch_read(void)
{
  uint32_t v;
  __asm__ volatile("csrr %0, 0x340" : "=r"(v));
  return v;
}

static int check(uint32_t pat, const char *name)
{
  mscratch_write(pat);
  uint32_t rd = mscratch_read();

  if (rd != pat) {
    printf("FAIL: mscratch %s: wrote 0x%08" PRIx32 ", read 0x%08" PRIx32 "\n",
		    name, pat, rd);
    return 1;
  }
  return 0;
}

int main(int argc, char *argv[])
{
  (void)argc; (void)argv;

  int err = 0;

  printf("\ncsr_mscratch32: verify full 32-bit RW of mscratch (CSR 0x340)\n");

  /**
   The program then runs a sequence of patterns. Each pattern is chosen to
   detect a different class of implementation bug. 

   A) All zeros: 0x00000000
      Catches: bits stuck-at-1,
               incorrect reset/clear behavior,
	       write logic that can set bits but not clear them.

   B) All ones: 0xFFFFFFFF
      Catches: bits stuck-at-0,
               write masks (e.g., only some bits writable),
	       width truncation (e.g., upper bits always read 0).

   C) Alternating patterns: 0xAAAAAAAA and 0x55555555
      Binary: 0xAAAAAAAA = 1010... 0x55555555 = 0101...
      Catches: data bus bit-swaps / bit-lane issues,
               coupling between adjacent bits,
	       logic that accidentally shifts/rotates,
	       partial-bit connectivity problems.

      
   D) Mixed entropy constants: 0x01234567 and 0x89ABCDEF
      Catches: endianness/byte-lane mistakes in some fabrics,
               weird masking that passes simple patterns but fails
	       with varied bit distributions,
	       accidental sign/zero-extension behaviors
	       (especially if someone mishandled types).

   E) Single MSB and LSB: 0x80000000 and 0x00000001
      Catches: top bits dont exist implementations (upper bits read as 0),
               sign-bit mishandling,
	       off-by-one in bit indexing.
   */

  err |= check(0x00000000u, "all0");
  err |= check(0xffffffffu, "all1");
  err |= check(0xaaaaaaaau, "aaaa");
  err |= check(0x55555555u, "5555");
  err |= check(0x01234567u, "01234567");
  err |= check(0x89abcdefu, "89abcdef");
  err |= check(0x80000000u, "msb");
  err |= check(0x00000001u, "lsb");

  /*
   * Walking 1s (bit-by-bit set)
   * Catches: any single bit that cannot be set,
   *          bit aliasing (writing one bit sets another),
   *          decode errors that only affect certain bit positions.
   *
   * Walking 0s (bit-by-bit clear)
   * Catches: any single bit that cannot be cleared,
   *          asymmetry: some designs can set a bit but not clear it
   *          (or vice versa),
   *          masked write paths that only allow 1s or only allow 0s in 
   *          certain positions.
   */


  // Walking 1s: each bit can be set and read back
  for (uint32_t i = 0; i < 32; i++) {
    uint32_t pat = (1u << i);
    mscratch_write(pat);
    uint32_t rd = mscratch_read();
    if (rd != pat) {
      printf("FAIL: walking1 bit %" PRIu32 " : wrote 0x%08" PRIx32
		      ", read 0x%08" PRIx32 "\n", i, pat, rd);
      err = 1;
      break;
    }
  }

  // Walking 0s: each bit can be cleared and read back
  for (uint32_t i = 0; i < 32 && !err; i++) {
    uint32_t pat = ~(1u << i);
    mscratch_write(pat);
    uint32_t rd = mscratch_read();
    if (rd != pat) {
      printf("FAIL: walking0 bit %"PRIx32 " : wrote 0x%08" PRIx32 ", read 0x%08"
		      PRIx32 "\n", i, pat, rd);
      err = 1;
      break;
    }
  }

  if (err) {
    printf("csr_mscratch32: FAIL\n");
    return EXIT_FAILURE;
  }

  printf("csr_mscratch32: PASS\n");
  return EXIT_SUCCESS;
}

