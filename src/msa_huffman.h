/*
 * Shared canonical Huffman codec for digital amino-acid bytes.
 * Experimental on-disk format; exactly reversible, no lossy mapping.
 * Each code is 1..32 bits, MSB first, with per-record byte alignment.
 * Alphabet codes come from Easel's digital input (including degeneracy).
 */
#ifndef MSA_HUFFMAN_H
#define MSA_HUFFMAN_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <limits.h>

#define MSA_HUFF_SYMS 256
#define MSA_HUFF_MAX_NODES 512
#define MSA_HUFF_MAX_BITS 32

typedef struct {
  uint32_t code[MSA_HUFF_SYMS];
  unsigned char bits[MSA_HUFF_SYMS];
  struct {
    int16_t next[2];
    int16_t sym;
  } node[MSA_HUFF_MAX_NODES];
  int nodes;
} MSA_HUFF_TABLE;

/* Deterministic construction: equal weights favor lower node indices.
 * Returns 0 on success. The single-symbol case gets one bit. */
static int
msa_huff_lengths(const uint64_t freq[MSA_HUFF_SYMS],
                 unsigned char lengths[MSA_HUFF_SYMS])
{
  struct tree_node {uint64_t count; int16_t parent; int16_t left; int16_t right;} tree[511];
  int n = 0, active = 0, i;
  memset(lengths, 0, MSA_HUFF_SYMS);
  for (i = 0; i < MSA_HUFF_SYMS; ++i) {
    if (freq[i]) {
      tree[n].count = freq[i];
      tree[n].parent = -1;
      tree[n].left = -1;
      tree[n].right = (int16_t)i; /* Leaf holds input symbol. */
      ++n; ++active;
    }
  }
  if (!active) return -1;
  if (active == 1) {
    for (i = 0; i < MSA_HUFF_SYMS; i++) if (freq[i]) lengths[i] = 1;
    return 0;
  }
  /* At most 511 nodes, for up to 256 symbols. */
  while (n < 2*active-1) {
    int a = -1, b = -1, j;
    for (j = 0; j < n; j++) if (tree[j].parent == -1) {
      if (a < 0 || tree[j].count < tree[a].count ||
          (tree[j].count == tree[a].count && j < a)) {
        b = a;
        a = j;
      } else if (b < 0 || tree[j].count < tree[b].count ||
                 (tree[j].count == tree[b].count && j < b)) {
        b = j;
      }
    }
    if (a < 0 || b < 0 || n >= 511 ||
        UINT64_MAX - tree[a].count < tree[b].count) return -1;
    tree[a].parent = (int16_t)n;
    tree[b].parent = (int16_t)n;
    tree[n].count = tree[a].count + tree[b].count;
    tree[n].parent = -1;
    tree[n].left = (int16_t)a;
    tree[n].right = (int16_t)b;
    ++n;
  }
  for (i = 0, n = 0; i < MSA_HUFF_SYMS; ++i) if (freq[i]) {
    int j = n, depth = 0;
    while (tree[j].parent != -1) {
      depth++;
      j = tree[j].parent;
    }
    if (depth < 1 || depth > MSA_HUFF_MAX_BITS) return -1;
    lengths[i] = (unsigned char)depth;
    ++n;
  }
  return 0;
}

/* Build both canonical codes and a validated prefix decoding trie. */
static int
msa_huff_init(MSA_HUFF_TABLE *t, const unsigned char lengths[MSA_HUFF_SYMS])
{
  uint64_t next_code = 0;
  int last_len = 0, total = 0, len, sym;
  memset(t, 0, sizeof(*t));
  for (sym = 0; sym < MSA_HUFF_SYMS; ++sym) {
    if (lengths[sym] > MSA_HUFF_MAX_BITS) return -1;
    t->bits[sym] = lengths[sym];
    total += (lengths[sym] != 0);
  }
  if (!total) return -1;
  t->nodes = 1;
  t->node[0].next[0] = -1;
  t->node[0].next[1] = -1;
  t->node[0].sym = -1;

  for (len = 1; len <= MSA_HUFF_MAX_BITS; len++) {
    for (sym = 0; sym < MSA_HUFF_SYMS; sym++) if (t->bits[sym] == len) {
      int j, node = 0;
      if (last_len != len) {
        next_code <<= (len-last_len);
        last_len = len;
      }
      if (next_code >= (UINT64_C(1) << len)) return -1; /* oversubscribed */
      t->code[sym] = (uint32_t)next_code;
      for (j = len - 1; j >= 0; --j) {
        int bit = (int)((next_code >> j) & 1);
        int child = t->node[node].next[bit];
        if (t->node[node].sym != -1) return -1; /* prefix conflict */
        if (child == -1) {
          if (t->nodes == MSA_HUFF_MAX_NODES) return -1;
          child = t->nodes++;
          t->node[node].next[bit] = (int16_t)child;
          t->node[child].next[0] = -1;
          t->node[child].next[1] = -1;
          t->node[child].sym = -1;
        }
        node = child;
      }
      if (t->node[node].sym != -1 ||
          t->node[node].next[0] != -1 ||
          t->node[node].next[1] != -1) return -1;
      t->node[node].sym = (int16_t)sym;
      next_code++;
    }
  }
  return 0;
}

/* Exact len-symbol decode. Never read past the record payload. */
static int
msa_huff_decode(const MSA_HUFF_TABLE *t,
                const unsigned char *in, size_t in_bytes,
                unsigned char *out, size_t out_symbols)
{
  size_t produced = 0, bitpos = 0;
  if (in_bytes > SIZE_MAX / 8) return -1;
  while (produced < out_symbols) {
    int node = 0;
    while (t->node[node].sym == -1) {
      int bit;
      if (bitpos >= in_bytes * 8) return -1;
      bit = (in[bitpos >> 3] >> (7 - (bitpos & 7))) & 1;
      bitpos++;
      node = t->node[node].next[bit];
      if (node < 0 || node >= t->nodes) return -1;
    }
    out[produced++] = (unsigned char)t->node[node].sym;
  }
  /* Byte padding is at most 7 bits and all padding bits must be zero. */
  if (in_bytes != (bitpos + 7)/8) return -1;
  while (bitpos < in_bytes*8) {
    if ((in[bitpos >> 3] >> (7 - (bitpos & 7))) & 1) return -1;
    bitpos++;
  }
  return 0;
}
#endif
