/*
 * Experimental adapter: feed native Easel DSQDATA chunks into the existing
 * jackhmmer serial/threaded ESL_SQ work queue without altering scoring.
 *
 * Writer and reader are Easel upstream primitives. This adapter simply
 * copies complete digital sequences and original metadata in input order.
 * Only one reader thread (jackhmmer master) calls esl_dsqdata_Read();
 * Easel manages its own loader/unpacker threads internally.
 */
#ifndef MSA_DSQ_BRIDGE_H
#define MSA_DSQ_BRIDGE_H
#include <stdint.h>
#include <limits.h>
#include <string.h>
#include <errno.h>
#include "esl_dsqdata.h"

typedef struct {
  ESL_DSQDATA *dd;
  ESL_DSQDATA_CHUNK *chunk;
  char *basename;
  int offset;
  int64_t next_index;
  int n_unpackers;
} MSA_DSQ_READER;

static MSA_DSQ_READER msa_dsq_reader = {0};

static int
msa_dsq_open(const char *basename, ESL_ALPHABET *abc)
{
  ESL_ALPHABET *expected = abc;
  size_t len;
  int status;
  char *endptr = NULL;
  const char *budget = getenv("MSA_DSQ_UNPACKERS");
  long workers = 1; /* one loader plus one unpacker, by default */
  if (budget && *budget) {
    errno = 0;
    workers = strtol(budget, &endptr, 10);
    if (errno || !endptr || *endptr != '\0' ||
        workers < 1 || workers > eslDSQDATA_UMAX) return eslEINVAL;
  }
  if (!basename || !*basename || !abc || msa_dsq_reader.dd) return eslEINVAL;
  msa_dsq_reader.n_unpackers = (int)workers;
  len = strlen(basename);
  msa_dsq_reader.basename = malloc(len+1);
  if (!msa_dsq_reader.basename) return eslEMEM;
  memcpy(msa_dsq_reader.basename, basename, len+1);
  status = esl_dsqdata_OpenWithUnpackers(
      &expected, msa_dsq_reader.basename, 1, msa_dsq_reader.n_unpackers,
      &msa_dsq_reader.dd);
  if (status != eslOK) {
    free(msa_dsq_reader.basename);
    msa_dsq_reader.basename = NULL;
    return status;
  }
  msa_dsq_reader.chunk = NULL;
  msa_dsq_reader.offset = 0;
  msa_dsq_reader.next_index = 0;
  return eslOK;
}

static int
msa_dsq_close(void)
{
  int status = eslOK, st;
  if (msa_dsq_reader.chunk) {
    st=esl_dsqdata_Recycle(msa_dsq_reader.dd, msa_dsq_reader.chunk);
    if (st!=eslOK) status=st;
    msa_dsq_reader.chunk=NULL;
  }
  if (msa_dsq_reader.dd) {
    st=esl_dsqdata_Close(msa_dsq_reader.dd);
    if (st!=eslOK) status=st;
    msa_dsq_reader.dd=NULL;
  }
  free(msa_dsq_reader.basename);
  msa_dsq_reader.basename=NULL;
  msa_dsq_reader.offset=0;
  msa_dsq_reader.next_index=0;
  msa_dsq_reader.n_unpackers=0;
  return status;
}

/* After each *completed* scan, retire the asynchronous reader without
 * starting new I/O. Reopen lazily on the first read of the next scan.
 *
 * jackhmmer calls rewind twice after the final iteration (once for the
 * iteration and once for the query). An eager reopen followed by Close()
 * on an unconsumed prefetch queue can deadlock Easel's loader waiting
 * for recycled chunks. A second rewind must therefore be a no-op. */
static int
msa_dsq_rewind(ESL_ALPHABET *abc)
{
  int status;
  (void)abc;
  if (!msa_dsq_reader.basename) return eslEINVAL;
  if (!msa_dsq_reader.dd) return eslOK;

  if (msa_dsq_reader.chunk) {
    status = esl_dsqdata_Recycle(msa_dsq_reader.dd, msa_dsq_reader.chunk);
    if (status != eslOK) return status;
    msa_dsq_reader.chunk = NULL;
  }
  status = esl_dsqdata_Close(msa_dsq_reader.dd);
  msa_dsq_reader.dd = NULL;
  if (status != eslOK) return status;
  msa_dsq_reader.offset = 0;
  msa_dsq_reader.next_index = 0;
  return eslOK;
}

static int
msa_dsq_read(ESL_SQ *sq)
{
  ESL_DSQDATA_CHUNK *chunk;
  int index, status;
  int64_t length;
  if (!sq || !sq->dsq || !msa_dsq_reader.basename) return eslEINVAL;
  if (!msa_dsq_reader.dd) {
    ESL_ALPHABET *expected = (ESL_ALPHABET *)sq->abc;
    status = esl_dsqdata_OpenWithUnpackers(
        &expected, msa_dsq_reader.basename, 1, msa_dsq_reader.n_unpackers,
        &msa_dsq_reader.dd);
    if (status != eslOK) return status;
  }
  while (!msa_dsq_reader.chunk ||
         msa_dsq_reader.offset>=msa_dsq_reader.chunk->N) {
    if (msa_dsq_reader.chunk) {
      status=esl_dsqdata_Recycle(msa_dsq_reader.dd,msa_dsq_reader.chunk);
      if (status!=eslOK)return status;
      msa_dsq_reader.chunk=NULL;
    }
    status=esl_dsqdata_Read(msa_dsq_reader.dd,&msa_dsq_reader.chunk);
    if (status!=eslOK) return status;
    msa_dsq_reader.offset=0;
    if (!msa_dsq_reader.chunk || msa_dsq_reader.chunk->N<=0)
      return eslEFORMAT;
  }
  chunk=msa_dsq_reader.chunk;
  index=msa_dsq_reader.offset;
  length=chunk->L[index];
  if (length<0 || length>INT_MAX || !chunk->dsq[index]) return eslEFORMAT;
  if ((status=msa_bin8_copystr(&sq->name,&sq->nalloc,
                    (const unsigned char*)chunk->name[index],
                    (uint32_t)strlen(chunk->name[index])))!=eslOK) return status;
  if ((status=msa_bin8_copystr(&sq->acc,&sq->aalloc,
                    (const unsigned char*)chunk->acc[index],
                    (uint32_t)strlen(chunk->acc[index])))!=eslOK) return status;
  if ((status=msa_bin8_copystr(&sq->desc,&sq->dalloc,
                    (const unsigned char*)chunk->desc[index],
                    (uint32_t)strlen(chunk->desc[index])))!=eslOK) return status;
  if ((status=esl_sq_GrowTo(sq,length))!=eslOK) return status;

  memcpy(sq->dsq,chunk->dsq[index],(size_t)length+2);
  if (sq->dsq[0]!=eslDSQ_SENTINEL ||
      sq->dsq[(size_t)length+1]!=eslDSQ_SENTINEL) return eslEFORMAT;
  sq->n=sq->L=length;
  sq->start=1;
  sq->end=length;
  sq->C=0;
  sq->W=length;
  sq->tax_id=chunk->taxid[index];
  sq->idx=-1;
  msa_dsq_reader.offset++;
  msa_dsq_reader.next_index++;
  return eslOK;
}

#ifdef HMMER_THREADS
static int
msa_dsq_readblock(ESL_SQ_BLOCK *block)
{
  int status=eslOK;
  int64_t residues=0;
  int i;
  block->count=0;
  block->complete=TRUE;
  block->first_seqidx=msa_dsq_reader.next_index;
  for (i=0;i<block->listSize && residues<MAX_RESIDUE_COUNT;i++) {
    status=msa_dsq_read(&block->list[i]);
    if (status==eslEOF) break;
    if (status!=eslOK) return status;
    residues+=block->list[i].n;
    block->count++;
  }
  return block->count?eslOK:eslEOF;
}
#endif
#endif
