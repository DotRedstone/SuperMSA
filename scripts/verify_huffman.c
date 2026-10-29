/*
 * Verify Huffman database exactly matches its source BIN8, for every
 * record's metadata and every digitized residue (not just hit lists).
 * Usage: verify_huffman input.bin8 compressed.huf
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <inttypes.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include "../src/msa_huffman.h"

typedef struct {const unsigned char *p; size_t size, pos;} MAPPED;
static uint32_t u32(const unsigned char *p) {
  return (uint32_t)p[0]|((uint32_t)p[1]<<8)|
         ((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
}
static int open_map(const char *path, MAPPED *m) {
  int fd=open(path,O_RDONLY);
  struct stat st;
  void *p;
  if(fd<0) return -1;
  if(fstat(fd,&st)!=0 || st.st_size<8 ||
     (uintmax_t)st.st_size>SIZE_MAX) {close(fd);return -1;}
  p=mmap(NULL,(size_t)st.st_size,PROT_READ,MAP_PRIVATE,fd,0);
  close(fd);
  if(p==MAP_FAILED) return -1;
  m->p=(const unsigned char *)p;m->size=(size_t)st.st_size;m->pos=8;
  return 0;
}
static void close_map(MAPPED *m){if(m->p)munmap((void *)m->p,m->size);}
static int read_rec(MAPPED *m,int compressed,uint32_t sizes[5],
                    const unsigned char **meta,const unsigned char **sequence,
                    uint32_t *stored_bytes) {
  size_t header=compressed?24:20, mlen;
  int i;
  if(m->pos==m->size)return 0;
  if(m->pos>m->size || m->size-m->pos<header)return -1;
  for(i=0;i<5;i++) sizes[i]=u32(m->p+m->pos+4*i);
  *stored_bytes=compressed?u32(m->p+m->pos+20):sizes[3];
  mlen=(size_t)sizes[0]+sizes[1]+sizes[2];
  if(!sizes[0] || mlen>m->size-m->pos-header ||
     *stored_bytes>m->size-m->pos-header-mlen) return -1;
  *meta=m->p+m->pos+header;
  *sequence=*meta+mlen;
  m->pos+=header+mlen+*stored_bytes;
  return 1;
}
int main(int argc,char **argv) {
  MAPPED a={0},b={0};
  MSA_HUFF_TABLE table;
  uint32_t as[5],bs[5],a_bytes,b_bytes;
  const unsigned char *am,*bm,*ad,*bd;
  uint64_t count=0,residues=0;
  int x,y,ok=0;
  if(argc!=3){fprintf(stderr,"usage: %s raw.bin8 data.huf\n",argv[0]);return 1;}
  if(open_map(argv[1],&a)!=0 || open_map(argv[2],&b)!=0)goto done;
  if(memcmp(a.p,"MSA8DB01",8)!=0 || b.size<264 ||
     memcmp(b.p,"MSAHUF01",8)!=0 ||
     msa_huff_init(&table,b.p+8)!=0) goto done;
  b.pos=264;
  for(;;) {
    unsigned char *decoded;
    size_t mlen;
    x=read_rec(&a,0,as,&am,&ad,&a_bytes);
    y=read_rec(&b,1,bs,&bm,&bd,&b_bytes);
    if(x==0 && y==0) {ok=(count>0);break;}
    if(x!=1 || y!=1 || memcmp(as,bs,sizeof(as))!=0) break;
    mlen=(size_t)as[0]+as[1]+as[2];
    if(memcmp(am,bm,mlen)!=0) break;
    decoded=(unsigned char*)malloc(as[3]?as[3]:1);
    if(!decoded)break;
    if(msa_huff_decode(&table,bd,b_bytes,decoded,as[3])!=0 ||
       memcmp(ad,decoded,as[3])!=0) {
      free(decoded);break;
    }
    free(decoded);
    count++;residues+=as[3];
  }
done:
  if(ok)printf("HUFFMAN_EXACT_ROUNDTRIP=PASS records=%" PRIu64 " residues=%" PRIu64 "\n",count,residues);
  else fprintf(stderr,"HUFFMAN_EXACT_ROUNDTRIP=FAIL near record %" PRIu64 "\n",count+1);
  close_map(&a);close_map(&b);
  return ok?0:1;
}
