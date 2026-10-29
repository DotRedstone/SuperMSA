/*
 * Convert the per-residue 8-bit digital file to canonical Huffman.
 * The input BIN8 itself MUST be created from raw FASTA inside the timed
 * prologue. The intermediate and final format never inspect sequence
 * IDs or labels, nor discard or reorder records.
 *
 * Usage: bin8_to_huffman temporary.bin8 output.huf
 * Huffman format:
 *   magic "MSAHUF01", 256 code-length bytes;
 *   records of six LE u32:
 *     name_bytes, accession_bytes, desc_bytes, residues, taxid, payload_bytes;
 *   followed by name, accession, desc, Huffman payload (MSB-first,
 *   byte-aligned for each record).
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <limits.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include "../src/msa_huffman.h"

typedef struct { const unsigned char *base; size_t size; } INPUT;

static uint32_t
get32(const unsigned char *p) {
  return (uint32_t)p[0] | ((uint32_t)p[1]<<8) |
         ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static int
put32(FILE *f, uint32_t v) {
  unsigned char b[4] = {(unsigned char)v, (unsigned char)(v>>8),
                        (unsigned char)(v>>16), (unsigned char)(v>>24)};
  return fwrite(b,1,4,f)==4;
}
static int
write_bytes(FILE *f, const void *p, size_t n) {
  return fwrite(p,1,n,f)==n;
}
static int
next_record(const INPUT *in, size_t *pos, const unsigned char **metadata,
            const unsigned char **residues, uint32_t sizes[5])
{
  size_t p=*pos, metadata_len;
  int i;
  if (p==in->size) return 0;
  if (p>in->size || in->size-p<20) return -1;
  for (i=0;i<5;i++) sizes[i]=get32(in->base+p+4*i);
  if (!sizes[0] || sizes[0] > INT_MAX-1 || sizes[1]>INT_MAX-1 ||
      sizes[2] > INT_MAX-1) return -1;
  metadata_len=(size_t)sizes[0]+sizes[1]+sizes[2];
  if (metadata_len>in->size-p-20 ||
      (size_t)sizes[3]>in->size-p-20-metadata_len) return -1;
  *metadata=in->base+p+20;
  *residues=*metadata+metadata_len;
  *pos=p+20+metadata_len+sizes[3];
  return 1;
}

int main(int argc,char **argv)
{
  INPUT in={NULL,0};
  uint64_t histogram[256]={0}, records=0, symbols=0;
  unsigned char lengths[256];
  MSA_HUFF_TABLE t;
  struct stat st;
  const unsigned char *metadata, *dsq;
  uint32_t sizes[5];
  FILE *out=NULL;
  size_t pos;
  int fd=-1, st_rec, ok=0;
  if (argc!=3 || strcmp(argv[1],argv[2])==0) {
    fprintf(stderr,"usage: %s input.bin8 output.huf\n",argv[0]);
    return EXIT_FAILURE;
  }
  fd=open(argv[1],O_RDONLY);
  if(fd<0) {perror("open input"); goto done;}
  if(fstat(fd,&st)!=0 || st.st_size<8 ||
     (uintmax_t)st.st_size>SIZE_MAX) {
    fprintf(stderr,"invalid input file size\n"); goto done;
  }
  in.size=(size_t)st.st_size;
  in.base=mmap(NULL,in.size,PROT_READ,MAP_PRIVATE,fd,0);
  if(in.base==MAP_FAILED) { in.base=NULL; perror("mmap"); goto done; }
  if(memcmp(in.base,"MSA8DB01",8)!=0) {
    fprintf(stderr,"unexpected input signature\n"); goto done;
  }
  for(pos=8;(st_rec=next_record(&in,&pos,&metadata,&dsq,sizes))>0;) {
    uint32_t i;
    records++;
    symbols+=sizes[3];
    for(i=0;i<sizes[3];i++) histogram[dsq[i]]++;
  }
  if(st_rec<0 || !records || !symbols) {
    fprintf(stderr,"corrupt or empty bin8 database\n"); goto done;
  }
  if(msa_huff_lengths(histogram,lengths)!=0 ||
     msa_huff_init(&t,lengths)!=0) {
    fprintf(stderr,"Huffman code length limit exceeded\n"); goto done;
  }

  out=fopen(argv[2],"wb");
  if(!out) {perror("open output");goto done;}
  if(!write_bytes(out,"MSAHUF01",8) || !write_bytes(out,lengths,256))
    goto write_error;
  for(pos=8;(st_rec=next_record(&in,&pos,&metadata,&dsq,sizes))>0;) {
    size_t i, nbits=0, nbytes, bitpos=0;
    unsigned char *packed;
    for(i=0;i<sizes[3];i++) {
      int bits=t.bits[dsq[i]];
      if(!bits || SIZE_MAX - nbits < (size_t)bits) goto invalid;
      nbits+=(size_t)bits;
    }
    nbytes=(nbits+7)/8;
    if(nbits>SIZE_MAX-7 || nbytes>UINT32_MAX) goto invalid;
    packed=calloc(nbytes?nbytes:1,1);
    if(!packed) {perror("calloc");goto done;}

    for(i=0;i<sizes[3];i++) {
      int shift;
      unsigned sym=dsq[i], bits=t.bits[sym];
      uint32_t code=t.code[sym];
      for(shift=(int)bits-1;shift>=0;shift--) {
        if((code>>shift)&1)
          packed[bitpos>>3]|=(unsigned char)(1u<<(7-(bitpos&7)));
        bitpos++;
      }
    }

    if(!put32(out,sizes[0]) || !put32(out,sizes[1]) ||
       !put32(out,sizes[2]) || !put32(out,sizes[3]) ||
       !put32(out,sizes[4]) || !put32(out,(uint32_t)nbytes) ||
       !write_bytes(out,metadata,(size_t)sizes[0]+sizes[1]+sizes[2]) ||
       !write_bytes(out,packed,nbytes)) {
      free(packed);
      goto write_error;
    }
    free(packed);
  }
  if(st_rec<0) goto invalid;
  if(fflush(out)!=0 || ferror(out)) goto write_error;
  if(fclose(out)!=0) {out=NULL;perror("close output");goto done;}
  out=NULL;
  printf("HUFF_PREPARED records=%" PRIu64 " residues=%" PRIu64 "\n",records,symbols);
  ok=1;
  goto done;

invalid:
  fprintf(stderr,"invalid or oversized Huffman record\n");
  goto done;
write_error:
  perror("Huffman write");
done:
  if(out) fclose(out);
  if(in.base) munmap((void *)in.base,in.size);
  if(fd>=0) close(fd);
  return ok?EXIT_SUCCESS:EXIT_FAILURE;
}
