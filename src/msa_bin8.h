/*
 * Experimental read-only 8-bit digital database for jackhmmer.
 * Format: "MSA8DB01" followed by records; each record has five
 * little-endian u32 values: name length, accession length,
 * description length, sequence length, tax_id (bit representation).
 * Payload: name, accession, description, then L digital ESL_DSQ bytes
 * (without sentinels). This file is always created from the original
 * FASTA by the timed prologue, using Easel's own digital reader.
 *
 * This header is intentionally private to jackhmmer; its functions are
 * static, so no Makefile edits or linker changes are needed.
 */
#ifndef MSA_BIN8_H
#define MSA_BIN8_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/mman.h>

#include "easel.h"
#include "esl_sq.h"

typedef struct {
  const unsigned char *data;
  size_t size;
  size_t pos;
  uint64_t next_index;
} MSA_BIN8_READER;

static MSA_BIN8_READER msa_bin8_reader = { NULL, 0, 0, 0 };

static uint32_t
msa_bin8_u32(const unsigned char *p)
{
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
         ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static int
msa_bin8_open(const char *path)
{
  int fd;
  struct stat st;
  void *ptr;

  if (msa_bin8_reader.data != NULL || path == NULL) return eslEINVAL;
  fd = open(path, O_RDONLY);
  if (fd < 0) return eslENOTFOUND;
  if (fstat(fd, &st) != 0 || st.st_size < 8 ||
      (uintmax_t)st.st_size > (uintmax_t)SIZE_MAX) {
    close(fd);
    return eslEFORMAT;
  }
  ptr = mmap(NULL, (size_t)st.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
  close(fd);
  if (ptr == MAP_FAILED) return eslESYS;
  if (memcmp(ptr, "MSA8DB01", 8) != 0) {
    munmap(ptr, (size_t)st.st_size);
    return eslEFORMAT;
  }
  msa_bin8_reader.data = (const unsigned char *)ptr;
  msa_bin8_reader.size = (size_t)st.st_size;
  msa_bin8_reader.pos = 8;
  msa_bin8_reader.next_index = 0;
  return eslOK;
}

static void
msa_bin8_rewind(void)
{
  if (msa_bin8_reader.data != NULL) {
    msa_bin8_reader.pos = 8;
    msa_bin8_reader.next_index = 0;
  }
}

static void
msa_bin8_close(void)
{
  if (msa_bin8_reader.data != NULL)
    munmap((void *)msa_bin8_reader.data, msa_bin8_reader.size);
  msa_bin8_reader.data = NULL;
  msa_bin8_reader.size = msa_bin8_reader.pos = 0;
  msa_bin8_reader.next_index = 0;
}

/* Copy a metadata field from the mapped read-only source into a
 * reusable ESL_SQ-owned string; the source never gets modified. */
static int
msa_bin8_copystr(char **dst, int *alloc, const unsigned char *src, uint32_t len)
{
  char *tmp;
  if (len > INT_MAX - 1) return eslEFORMAT;
  if ((size_t)*alloc < (size_t)len + 1) {
    tmp = (char *)realloc(*dst, (size_t)len + 1);
    if (tmp == NULL) return eslEMEM;
    *dst = tmp;
    *alloc = (int)len + 1;
  }
  memcpy(*dst, src, len);
  (*dst)[len] = '\0';
  return eslOK;
}

static int
msa_bin8_read(ESL_SQ *sq)
{
  const unsigned char *p;
  uint32_t nlen, alen, dlen, len, taxid;
  size_t remain;
  int status;

  if (msa_bin8_reader.data == NULL) return eslEINVAL;
  if (msa_bin8_reader.pos == msa_bin8_reader.size) return eslEOF;
  if (msa_bin8_reader.pos > msa_bin8_reader.size) return eslEFORMAT;

  remain = msa_bin8_reader.size - msa_bin8_reader.pos;
  if (remain < 20) return eslEFORMAT;
  p = msa_bin8_reader.data + msa_bin8_reader.pos;
  nlen  = msa_bin8_u32(p);
  alen  = msa_bin8_u32(p + 4);
  dlen  = msa_bin8_u32(p + 8);
  len   = msa_bin8_u32(p + 12);
  taxid = msa_bin8_u32(p + 16);
  p += 20;
  remain -= 20;
  if (nlen == 0 || nlen > INT_MAX - 1 || alen > INT_MAX - 1 ||
      dlen > INT_MAX - 1 || (uint64_t)nlen + alen + dlen + len > remain)
    return eslEFORMAT;
  if (sq->dsq == NULL) return eslEINVAL;
  if ((status = msa_bin8_copystr(&sq->name, &sq->nalloc, p, nlen)) != eslOK) return status;
  p += nlen;
  if ((status = msa_bin8_copystr(&sq->acc, &sq->aalloc, p, alen)) != eslOK) return status;
  p += alen;
  if ((status = msa_bin8_copystr(&sq->desc, &sq->dalloc, p, dlen)) != eslOK) return status;
  p += dlen;
  if ((status = esl_sq_GrowTo(sq, len)) != eslOK) return status;
  sq->dsq[0] = eslDSQ_SENTINEL;
  memcpy(sq->dsq + 1, p, len);
  sq->dsq[(size_t)len + 1] = eslDSQ_SENTINEL;

  sq->n = sq->L = (int64_t)len;
  sq->start = 1;
  sq->end = (int64_t)len;
  sq->C = 0;
  sq->W = (int64_t)len;
  sq->tax_id = (int32_t)taxid;
  sq->idx = -1; /* Match Easel's ordinary sequential FASTA reader. */
  msa_bin8_reader.next_index++;
  msa_bin8_reader.pos += 20 + (size_t)nlen + alen + dlen + len;
  return eslOK;
}

#ifdef HMMER_THREADS
static int
msa_bin8_readblock(ESL_SQ_BLOCK *block)
{
  int status = eslOK;
  int64_t residues = 0;
  int i;

  block->count = 0;
  block->complete = TRUE;
  block->first_seqidx = (int64_t)msa_bin8_reader.next_index;
  for (i = 0; i < block->listSize && residues < MAX_RESIDUE_COUNT; i++) {
    status = msa_bin8_read(&block->list[i]);
    if (status == eslEOF) break;
    if (status != eslOK) return status;
    residues += block->list[i].n;
    block->count++;
  }
  return block->count ? eslOK : eslEOF;
}
#endif
#endif
