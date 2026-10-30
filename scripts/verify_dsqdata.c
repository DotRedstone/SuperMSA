/*
 * Exact, full-record DSQDATA verification against original FASTA.
 * Compare every name, accession, description, taxid, length and
 * digitized residue. No target labels used to decide what to compare.
 *
 * usage: verify_dsqdata raw.fasta packed_basename
 */
#include <stdio.h>
#include <stdlib.h>
#include <inttypes.h>
#include <string.h>
#include "easel.h"
#include "esl_alphabet.h"
#include "esl_sq.h"
#include "esl_sqio.h"
#include "esl_dsqdata.h"

int main(int argc,char **argv)
{
  ESL_ALPHABET *abc=NULL,*pass=NULL;
  ESL_SQFILE *sf=NULL;
  ESL_SQ *sq=NULL;
  ESL_DSQDATA *dd=NULL;
  ESL_DSQDATA_CHUNK *chunk=NULL;
  uint64_t records=0,residues=0;
  int status=eslFAIL,ok=0,i;
  if(argc!=3) {
    fprintf(stderr,"usage: %s raw.fasta packed_basename\n",argv[0]);
    return 1;
  }
  abc=esl_alphabet_Create(eslAMINO);
  if(!abc) goto done;
  pass=abc;
  if(esl_sqfile_OpenDigital(abc,argv[1],eslSQFILE_UNKNOWN,NULL,&sf)!=eslOK)
    goto done;
  sq=esl_sq_CreateDigital(abc);
  if(!sq) goto done;
  status=esl_dsqdata_Open(&pass,argv[2],1,&dd);
  if(status!=eslOK) {fprintf(stderr,"DSQ open failed: %d\n",status);goto done;}

  while((status=esl_dsqdata_Read(dd,&chunk))==eslOK) {
    for(i=0;i<chunk->N;i++) {
      if(esl_sqio_Read(sf,sq)!=eslOK ||
         sq->n!=chunk->L[i] ||
         strcmp(sq->name,chunk->name[i]) ||
         strcmp(sq->acc,chunk->acc[i]) ||
         strcmp(sq->desc,chunk->desc[i]) ||
         sq->tax_id!=chunk->taxid[i] ||
         memcmp(sq->dsq,chunk->dsq[i],(size_t)sq->n+2)!=0)
      {
        fprintf(stderr,"DSQDATA roundtrip mismatch record=%" PRIu64 "\n",records+1);
        goto done;
      }
      records++;
      residues+=sq->n;
      esl_sq_Reuse(sq);
    }
    if(esl_dsqdata_Recycle(dd,chunk)!=eslOK) goto done;
    chunk=NULL;
  }
  if(status!=eslEOF || esl_sqio_Read(sf,sq)!=eslEOF || !records)
    goto done;
  ok=1;
done:
  if(chunk && dd) esl_dsqdata_Recycle(dd,chunk);
  if(dd) esl_dsqdata_Close(dd);
  if(sq) esl_sq_Destroy(sq);
  if(sf) esl_sqfile_Close(sf);
  if(abc) esl_alphabet_Destroy(abc);
  if(ok)
    printf("DSQDATA_EXACT_ROUNDTRIP=PASS records=%" PRIu64 " residues=%" PRIu64 "\n",records,residues);
  else fprintf(stderr,"DSQDATA_EXACT_ROUNDTRIP=FAIL after record %" PRIu64 "\n",records);
  return ok?0:1;
}
