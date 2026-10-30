/*
 * Timed prologue converter: raw FASTA -> native Easel DSQDATA 5-bit
 * protein database. Write is handled by esl_dsqdata_Write(); no custom
 * packed format. Creates basename, basename.dsqi/.dsqm/.dsqs.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "easel.h"
#include "esl_alphabet.h"
#include "esl_sqio.h"
#include "esl_dsqdata.h"

int main(int argc,char **argv)
{
  ESL_ALPHABET *abc=NULL;
  ESL_SQFILE *sqfp=NULL;
  char errbuf[eslERRBUFSIZE]={0};
  int status;
  if(argc!=3 || strcmp(argv[1],argv[2])==0) {
    fprintf(stderr,"usage: %s raw.fasta output_basename\n",argv[0]);
    return 1;
  }
  abc=esl_alphabet_Create(eslAMINO);
  if(!abc) return 1;
  status=esl_sqfile_OpenDigital(abc,argv[1],eslSQFILE_UNKNOWN,NULL,&sqfp);
  if(status!=eslOK) {
    fprintf(stderr,"dsqdata input open failed: %d\n",status);
    esl_alphabet_Destroy(abc);
    return 1;
  }
  status=esl_dsqdata_Write(sqfp,argv[2],errbuf);
  esl_sqfile_Close(sqfp);
  esl_alphabet_Destroy(abc);
  if(status!=eslOK) {
    fprintf(stderr,"dsqdata write failed: %d %s\n",status,errbuf);
    return 1;
  }
  puts("DSQDATA_PREPARED=YES");
  return 0;
}
