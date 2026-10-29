/* FASTA line-unwrapper for preprocessing experiments.
 *
 * Preserves every header, its order, and all non-EOL sequence bytes.
 * It only replaces wrapped sequence lines with one sequence line per record
 * and normalizes CRLF to LF at line endings.
 *
 * This is an experimental representation transformation, NOT a filter.
 * Do not use header annotations or identifiers to select targets.
 *
 * Build on test01: gcc -O3 -std=c99 -Wall -Wextra -o fasta_rewrap fasta_rewrap.c
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

static void fail(const char *what)
{
    fprintf(stderr, "fasta_rewrap: %s: %s\n", what, strerror(errno));
    exit(EXIT_FAILURE);
}

int main(int argc, char **argv)
{
    FILE *in, *out;
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length;
    bool have_header = false;
    uint64_t records = 0, sequence_bytes = 0;

    if (argc != 3) {
        fprintf(stderr, "Usage: %s original.fasta output.fasta\n", argv[0]);
        return EXIT_FAILURE;
    }
    if (strcmp(argv[1], argv[2]) == 0) {
        fprintf(stderr, "fasta_rewrap: input and output paths must differ\n");
        return EXIT_FAILURE;
    }
    in = fopen(argv[1], "rb");
    if (in == NULL) fail("open input");
    out = fopen(argv[2], "wb");
    if (out == NULL) fail("open output");

    while ((length = getline(&line, &capacity, in)) != -1) {
        size_t n = (size_t)length;
        /* Remove only trailing line delimiters; retain all other bytes.
         * Neither description text nor residues are interpreted here. */
        if (n && line[n - 1] == '\n') n--;
        if (n && line[n - 1] == '\r') n--;

        if (n && line[0] == '>') {
            if (have_header && fputc('\n', out) == EOF) fail("write sequence EOL");
            if (fwrite(line, 1, n, out) != n || fputc('\n', out) == EOF)
                fail("write header");
            have_header = true;
            records++;
        } else {
            if (!have_header) {
                fprintf(stderr, "fasta_rewrap: unexpected data before first FASTA header\n");
                return EXIT_FAILURE;
            }
            if (n && fwrite(line, 1, n, out) != n) fail("write sequence");
            sequence_bytes += n;
        }
    }

    if (ferror(in)) fail("read input");
    if (!have_header) {
        fprintf(stderr, "fasta_rewrap: input contains no FASTA records\n");
        return EXIT_FAILURE;
    }
    if (fputc('\n', out) == EOF || fflush(out) != 0) fail("flush output");
    if (fclose(out) != 0) fail("close output");
    if (fclose(in) != 0) fail("close input");
    free(line);
    printf("FASTA_REWRAP records=%" PRIu64 " sequence_bytes=%" PRIu64 "\n", records, sequence_bytes);
    return EXIT_SUCCESS;
}
