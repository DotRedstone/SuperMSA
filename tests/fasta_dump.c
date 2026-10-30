/* 测试辅助：用 Easel 数字化读取 FASTA，把每条记录的 name/acc/desc/数字残基原样写出，
 * 用于逐字节比较不同读取路径的结果。用法：fasta_dump in.fasta out.bin */
#include <stdio.h>
#include <string.h>

#include "easel.h"
#include "esl_alphabet.h"
#include "esl_sq.h"
#include "esl_sqio.h"

static void put(FILE *f, const char *s) { if (s) fputs(s, f); fputc('\0', f); }

int
main(int argc, char **argv)
{
  ESL_ALPHABET *abc = esl_alphabet_Create(eslAMINO);
  ESL_SQFILE   *sqfp = NULL;
  ESL_SQ       *sq;
  FILE         *out;
  int           status;

  if (argc != 3) { fprintf(stderr, "usage: fasta_dump in.fasta out.bin\n"); return 2; }
  if (esl_sqfile_OpenDigital(abc, argv[1], eslSQFILE_FASTA, NULL, &sqfp) != eslOK) return 1;
  if ((out = fopen(argv[2], "wb")) == NULL) return 1;
  sq = esl_sq_CreateDigital(abc);
  while ((status = esl_sqio_Read(sqfp, sq)) == eslOK) {
    put(out, sq->name); put(out, sq->acc); put(out, sq->desc);
    fwrite(&sq->n, sizeof(sq->n), 1, out);
    fwrite(sq->dsq + 1, 1, (size_t) sq->n, out);
    esl_sq_Reuse(sq);
  }
  if (status != eslEOF) { fprintf(stderr, "%s\n", esl_sqfile_GetErrorBuf(sqfp)); return 1; }
  fclose(out);
  esl_sq_Destroy(sq);
  esl_sqfile_Close(sqfp);
  esl_alphabet_Destroy(abc);
  return 0;
}
