/*
 * Convert a raw protein FASTA to an 8-bit digital sequence database.
 * Reads every record via Easel's native digital sequence reader:
 * no filtering, deduplication, reordering, or ID-based decisions.
 *
 * Usage: ./fasta_to_bin8 original.fasta temporary-output.bin8
 * Build in an already configured/built SuperMSA checkout:
 *   gcc -O3 -std=c99 -Wall -Wextra -I easel \
 *       -o scripts/fasta_to_bin8 scripts/fasta_to_bin8.c \
 *       -L easel -leasel -pthread -lm
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <limits.h>
#include <string.h>

#include "easel.h"
#include "esl_alphabet.h"
#include "esl_sq.h"
#include "esl_sqio.h"

/* Serialize the 20-byte fixed header followed by all three metadata
 * fields in one contiguous fwrite. A reusable allocation amortizes
 * per-record metadata formatting. Sequence payload remains zero-copy
 * from the reusable Easel digital buffer. */
static void
put_u32(unsigned char *b, uint32_t v)
{
  b[0] = (unsigned char)v;
  b[1] = (unsigned char)(v >> 8);
  b[2] = (unsigned char)(v >> 16);
  b[3] = (unsigned char)(v >> 24);
}

static int
grow_meta(unsigned char **buf, size_t *alloc, size_t need)
{
  size_t next = *alloc ? *alloc : 4096;
  unsigned char *p;
  if (need <= *alloc) return 0;
  while (next < need) {
    if (next > SIZE_MAX / 2) {next = need; break;}
    next *= 2;
  }
  p = realloc(*buf, next);
  if (p == NULL) return -1;
  *buf = p;
  *alloc = next;
  return 0;
}

static int
write_bytes(FILE *f, const void *buf, size_t n)
{
  return fwrite(buf, 1, n, f) == n;
}

int
main(int argc, char **argv)
{
  ESL_ALPHABET *abc = NULL;
  ESL_SQFILE *sf = NULL;
  ESL_SQ *sq = NULL;
  FILE *out = NULL;
  int status, success = 0;
  uint64_t count = 0, residues = 0;
  unsigned char *metabuf = NULL;
  size_t meta_alloc = 0;

  if (argc != 3 || strcmp(argv[1], argv[2]) == 0) {
    fprintf(stderr, "usage: %s original.fasta output.bin8\n", argv[0]);
    return EXIT_FAILURE;
  }
  abc = esl_alphabet_Create(eslAMINO);
  if (abc == NULL) goto DONE;
  status = esl_sqfile_OpenDigital(abc, argv[1], eslSQFILE_UNKNOWN, NULL, &sf);
  if (status != eslOK) {
    fprintf(stderr, "fasta_to_bin8: cannot open input FASTA (error %d)\n", status);
    goto DONE;
  }
  sq = esl_sq_CreateDigital(abc);
  if (sq == NULL) goto DONE;
  out = fopen(argv[2], "wb");
  if (out == NULL) { perror("fasta_to_bin8 fopen"); goto DONE; }
  /* Buffered IO: avoid libc's small default buffer for many records.
   * Failure falls back safely to standard buffering. */
  (void)setvbuf(out, NULL, _IOFBF, 1 << 20);
  if (!write_bytes(out, "MSA8DB01", 8)) goto WRITE_ERROR;

  while ((status = esl_sqio_Read(sf, sq)) == eslOK) {
    size_t nlen = strlen(sq->name);
    size_t alen = strlen(sq->acc);
    size_t dlen = strlen(sq->desc);
    if (nlen == 0 || nlen > INT_MAX - 1 || alen > INT_MAX - 1 ||
        dlen > INT_MAX - 1 || sq->n < 0 || (uint64_t)sq->n > UINT32_MAX)
    {
      fprintf(stderr, "fasta_to_bin8: record has unsupported length\n");
      goto DONE;
    }

    /* Preserve the exact MSA8DB01 layout; only write batching changes. */
    if (nlen > SIZE_MAX - alen ||
        nlen + alen > SIZE_MAX - dlen ||
        nlen + alen + dlen > SIZE_MAX - 20) {
      fprintf(stderr, "fasta_to_bin8: oversized metadata\n");
      goto DONE;
    }
    {
      size_t mlen = nlen + alen + dlen;
      if (grow_meta(&metabuf, &meta_alloc, 20 + mlen) != 0) {
        fprintf(stderr, "fasta_to_bin8: metadata allocation failed\n");
        goto DONE;
      }
      put_u32(metabuf,      (uint32_t)nlen);
      put_u32(metabuf + 4,  (uint32_t)alen);
      put_u32(metabuf + 8,  (uint32_t)dlen);
      put_u32(metabuf + 12, (uint32_t)sq->n);
      put_u32(metabuf + 16, (uint32_t)sq->tax_id);
      memcpy(metabuf + 20, sq->name, nlen);
      memcpy(metabuf + 20 + nlen, sq->acc, alen);
      memcpy(metabuf + 20 + nlen + alen, sq->desc, dlen);
      if (!write_bytes(out, metabuf, 20 + mlen) ||
          !write_bytes(out, sq->dsq + 1, (size_t)sq->n))
        goto WRITE_ERROR;
    }

    count++;
    residues += (uint64_t)sq->n;
    esl_sq_Reuse(sq);
  }
  if (status != eslEOF) {
    fprintf(stderr, "fasta_to_bin8: input parse failed (status %d): %s\n",
            status, esl_sqfile_GetErrorBuf(sf));
    goto DONE;
  }
  if (count == 0) {
    fprintf(stderr, "fasta_to_bin8: no FASTA records\n");
    goto DONE;
  }
  if (fflush(out) != 0 || ferror(out)) goto WRITE_ERROR;
  if (fclose(out) != 0) {
    out = NULL;
    perror("fasta_to_bin8 fclose");
    goto DONE;
  }
  out = NULL;
  printf("BIN8_PREPARED records=%" PRIu64 " residues=%" PRIu64 "\n", count, residues);
  success = 1;
  goto DONE;

WRITE_ERROR:
  perror("fasta_to_bin8 write");
DONE:
  free(metabuf);
  if (out != NULL) fclose(out);
  if (sq != NULL) esl_sq_Destroy(sq);
  if (sf != NULL) esl_sqfile_Close(sf);
  if (abc != NULL) esl_alphabet_Destroy(abc);
  return success ? EXIT_SUCCESS : EXIT_FAILURE;
}
