/* DP-01/V04: compare FASTA records across two read-buffer sizes.
 * Build against the project's Easel library on an allowed test node.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "easel.h"
#include "esl_alphabet.h"
#include "esl_sq.h"
#include "esl_sqio.h"

static int
compare_file(const char *path, int format)
{
  ESL_ALPHABET *abc = esl_alphabet_Create(eslAMINO);
  ESL_SQFILE *base = NULL, *tuned = NULL;
  ESL_SQ *a = NULL, *b = NULL;
  int sa, sb, ok = 0;
  uint64_t records = 0, residues = 0;

  if (!abc) goto DONE;
  a = esl_sq_CreateDigital(abc);
  b = esl_sq_CreateDigital(abc);
  if (!a || !b) goto DONE;

  if (setenv("MSA_FASTA_CHUNK_64K", "0", 1)) goto DONE;
  if (esl_sqfile_OpenDigital(abc, path, format, NULL, &base) != eslOK) goto DONE;
  if (setenv("MSA_FASTA_CHUNK_64K", "1", 1)) goto DONE;
  if (esl_sqfile_OpenDigital(abc, path, format, NULL, &tuned) != eslOK) goto DONE;

  while (1) {
    sa = esl_sqio_Read(base, a);
    sb = esl_sqio_Read(tuned, b);
    if (sa != sb) { fprintf(stderr, "different status: %d vs %d\n", sa, sb); goto DONE; }
    if (sa == eslEOF) break;
    if (sa != eslOK) { fprintf(stderr, "parse error: %d\n", sa); goto DONE; }
    if (a->n != b->n ||
        strcmp(a->name, b->name) || strcmp(a->acc, b->acc) ||
        strcmp(a->desc, b->desc) ||
        a->roff != b->roff || a->doff != b->doff ||
        a->eoff != b->eoff ||
        memcmp(a->dsq, b->dsq, (size_t)(a->n + 2))) {
      fprintf(stderr, "record mismatch at %llu\n", (unsigned long long)records + 1);
      goto DONE;
    }
    records++;
    residues += (uint64_t)a->n;
    esl_sq_Reuse(a);
    esl_sq_Reuse(b);
  }
  if (records < 2 || residues < 10) goto DONE;

  /* Rewinding must also yield the same first record. */
  if (esl_sqfile_Position(base, 0) != eslOK ||
      esl_sqfile_Position(tuned, 0) != eslOK) goto DONE;
  sa = esl_sqio_Read(base, a);
  sb = esl_sqio_Read(tuned, b);
  if (sa != eslOK || sb != eslOK || a->n != b->n ||
      strcmp(a->name, b->name) ||
      memcmp(a->dsq, b->dsq, (size_t)(a->n + 2))) goto DONE;
  printf("PASS records=%llu residues=%llu format=%d input=%s\n",
         (unsigned long long)records, (unsigned long long)residues, format, path);
  ok = 1;
DONE:
  if (base) esl_sqfile_Close(base);
  if (tuned) esl_sqfile_Close(tuned);
  if (a) esl_sq_Destroy(a);
  if (b) esl_sq_Destroy(b);
  if (abc) esl_alphabet_Destroy(abc);
  return ok ? 0 : 1;
}

static int
reject_file(const char *path, int format, int enabled)
{
  ESL_ALPHABET *abc = esl_alphabet_Create(eslAMINO);
  ESL_SQFILE *sqfp = NULL;
  ESL_SQ *sq = NULL;
  int status, ok = 0;
  if (!abc) return 1;
  sq = esl_sq_CreateDigital(abc);
  if (!sq) goto DONE;
  if (setenv("MSA_FASTA_CHUNK_64K", enabled ? "1" : "0", 1)) goto DONE;
  status = esl_sqfile_OpenDigital(abc, path, format, NULL, &sqfp);
  if (status != eslOK) goto DONE;
  status = esl_sqio_Read(sqfp, sq);
  if (status != eslEFORMAT) {
    fprintf(stderr, "invalid FASTA accepted: %s (mode=%d, status=%d)\n",
            path, enabled, status);
    goto DONE;
  }
  ok = 1;
DONE:
  if (sqfp) esl_sqfile_Close(sqfp);
  if (sq) esl_sq_Destroy(sq);
  esl_alphabet_Destroy(abc);
  return ok ? 0 : 1;
}

int
main(int argc, char **argv)
{
  if (argc != 5) {
    fprintf(stderr, "usage: %s toy-db synthetic-db bad-gap bad-highbit\n", argv[0]);
    return 2;
  }
  if (compare_file(argv[1], eslSQFILE_FASTA) ||
      compare_file(argv[2], eslSQFILE_FASTA) ||
      compare_file(argv[2], eslSQFILE_UNKNOWN)) return 1;
  for (int mode = 0; mode <= 1; mode++) {
    if (reject_file(argv[3], eslSQFILE_FASTA, mode) ||
        reject_file(argv[4], eslSQFILE_FASTA, mode)) return 1;
  }
  puts("FASTA_CHUNK_64K_UNIT=PASS");
  return 0;
}
