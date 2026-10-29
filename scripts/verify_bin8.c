/*
 * verify_bin8.c — strict stream-by-stream FASTA ↔ MSA8DB01 roundtrip.
 *
 * This is an optional OFFLINE verifier, never called during timed search.
 * Every record must have identical name, accession, description, tax ID,
 * digitized residues, length AND order. Missing, extra, partial,
 * truncated or corrupt BIN8 records fail immediately.
 *
 * Usage:
 *   ./scripts/verify_bin8 original.fasta candidate.bin8
 *
 * Build after ./configure and make:
 *   gcc -O2 -std=c99 -Wall -Wextra -I easel -o scripts/verify_bin8 \
 *     scripts/verify_bin8.c -L easel -leasel -pthread -lm
 */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include "easel.h"
#include "esl_alphabet.h"
#include "esl_sq.h"
#include "esl_sqio.h"

static uint32_t
get_u32(const unsigned char *p)
{
  return ((uint32_t)p[0]) |
         ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
}

static int
equal_text(const char *want, const unsigned char *found, size_t n)
{
  if (want == NULL) return n == 0;
  return strlen(want) == n && memcmp(want, found, n) == 0;
}

int
main(int argc, char **argv)
{
  ESL_ALPHABET *abc = NULL;
  ESL_SQFILE *sf = NULL;
  ESL_SQ *sq = NULL;
  int fd = -1, status, ok = 0;
  struct stat st;
  const unsigned char *base = NULL;
  size_t size = 0, pos = 0;
  uint64_t records = 0, residues = 0;

  if (argc != 3) {
    fprintf(stderr, "usage: %s original.fasta candidate.bin8\n", argv[0]);
    return EXIT_FAILURE;
  }
  fd = open(argv[2], O_RDONLY);
  if (fd < 0) {
    perror("verify_bin8: open");
    goto DONE;
  }
  if (fstat(fd, &st) != 0 || st.st_size < 8 ||
      (uintmax_t)st.st_size > (uintmax_t)SIZE_MAX) {
    fprintf(stderr, "verify_bin8: missing, undersized, or oversized file\n");
    goto DONE;
  }
  size = (size_t)st.st_size;
  base = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, 0);
  if (base == MAP_FAILED) {
    base = NULL;
    perror("verify_bin8: mmap");
    goto DONE;
  }
  close(fd); fd = -1;
  if (memcmp(base, "MSA8DB01", 8) != 0) {
    fprintf(stderr, "verify_bin8: bad magic (not MSA8DB01)\n");
    goto DONE;
  }
  pos = 8;

  abc = esl_alphabet_Create(eslAMINO);
  if (abc == NULL) goto DONE;
  status = esl_sqfile_OpenDigital(abc, argv[1], eslSQFILE_UNKNOWN, NULL, &sf);
  if (status != eslOK) {
    fprintf(stderr, "verify_bin8: cannot open FASTA (status %d)\n", status);
    goto DONE;
  }
  sq = esl_sq_CreateDigital(abc);
  if (sq == NULL) goto DONE;

  while ((status = esl_sqio_Read(sf, sq)) == eslOK) {
    uint32_t nlen, alen, dlen, n, tax_id;
    size_t remain, meta_len;
    const unsigned char *p;

    if (pos > size || size - pos < 20) {
      fprintf(stderr, "verify_bin8: missing or truncated record %" PRIu64 "\n",
              records + 1);
      goto DONE;
    }
    p = base + pos;
    nlen = get_u32(p);
    alen = get_u32(p + 4);
    dlen = get_u32(p + 8);
    n = get_u32(p + 12);
    tax_id = get_u32(p + 16);

    remain = size - pos - 20;
    meta_len = (size_t)nlen + (size_t)alen + (size_t)dlen;
    if (nlen == 0 || nlen > INT_MAX - 1 || alen > INT_MAX - 1 ||
        dlen > INT_MAX - 1 || meta_len > remain ||
        (size_t)n > remain - meta_len) {
      fprintf(stderr, "verify_bin8: invalid length at record %" PRIu64 "\n",
              records + 1);
      goto DONE;
    }
    p += 20;
    if (!equal_text(sq->name, p, nlen) ||
        !equal_text(sq->acc, p + nlen, alen) ||
        !equal_text(sq->desc, p + nlen + alen, dlen) ||
        sq->n < 0 || (uint64_t)sq->n != (uint64_t)n ||
        (uint32_t)sq->tax_id != tax_id ||
        memcmp(sq->dsq + 1, p + meta_len, n) != 0) {
      fprintf(stderr,
              "verify_bin8: FULL RECORD MISMATCH at %" PRIu64 " (name=%s)\n",
              records + 1, sq->name ? sq->name : "<null>");
      goto DONE;
    }
    pos += 20 + meta_len + (size_t)n;
    records++;
    residues += n;
    esl_sq_Reuse(sq);
  }
  if (status != eslEOF) {
    fprintf(stderr, "verify_bin8: FASTA parse failed (status %d)\n", status);
    goto DONE;
  }
  if (records == 0 || pos != size) {
    fprintf(stderr,
            "verify_bin8: extra bytes or records at EOF; offset=%zu size=%zu\n",
            pos, size);
    goto DONE;
  }
  ok = 1;
DONE:
  if (ok) {
    printf("BIN8_EXACT_ROUNDTRIP=PASS records=%" PRIu64
           " residues=%" PRIu64 "\n", records, residues);
  } else {
    fprintf(stderr,
            "BIN8_EXACT_ROUNDTRIP=FAIL after records=%" PRIu64 "\n", records);
  }
  if (sq != NULL) esl_sq_Destroy(sq);
  if (sf != NULL) esl_sqfile_Close(sf);
  if (abc != NULL) esl_alphabet_Destroy(abc);
  if (base != NULL) munmap((void *)base, size);
  if (fd >= 0) close(fd);
  return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
