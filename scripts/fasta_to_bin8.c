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

static int
write_u32(FILE *f, uint32_t v)
{
  unsigned char b[4] = {
    (unsigned char)(v), (unsigned char)(v >> 8),
    (unsigned char)(v >> 16), (unsigned char)(v >> 24)
  };
  return fwrite(b, 1, 4, f) == 4;
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

    if (!write_u32(out, (uint32_t)nlen) ||
        !write_u32(out, (uint32_t)alen) ||
        !write_u32(out, (uint32_t)dlen) ||
        !write_u32(out, (uint32_t)sq->n) ||
        !write_u32(out, (uint32_t)sq->tax_id) ||
        !write_bytes(out, sq->name, nlen) ||
        !write_bytes(out, sq->acc, alen) ||
        !write_bytes(out, sq->desc, dlen) ||
        !write_bytes(out, sq->dsq + 1, (size_t)sq->n))
      goto WRITE_ERROR;

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
  if (out != NULL) fclose(out);
  if (sq != NULL) esl_sq_Destroy(sq);
  if (sf != NULL) esl_sqfile_Close(sf);
  if (abc != NULL) esl_alphabet_Destroy(abc);
  return success ? EXIT_SUCCESS : EXIT_FAILURE;
}
