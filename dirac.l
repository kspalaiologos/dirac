
%{

// ----------------------------------------------------------------
// DIRAC - Delightfully Intricate Reasonably Amazing Calculator
// Copyright (C) by Kamila Szewczyk, 2022. Licensed under the terms
// of AGPLv3 license.

#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
#include <ctype.h>
#include "map.h"
#include "vector.h"

#define TOKEN_OK vector_push_back(tokens, strdup(yytext));

static int err_underflow() {
    fprintf(stderr, "Error: Stack underflow.");
    abort(); return 0; // unreachable
}

static vector(char *) tokens;
static vector(unsigned int) callstack;
static vector(int64_t) stack;
static struct env * e;

static unsigned int tp;

struct env {
    struct env *parent;
    hashmap *data;
};

// Rule of thumb: : . - read -- ; , - write

%}

%option noyywrap

%%

[0-9]+                       { /* Push a number literal. */ TOKEN_OK }
'(.|\n)                      { /* Push a character literal. */ TOKEN_OK }
[\$\@\%\+\-\*\/\^\`]         { /* Stack operations. */ TOKEN_OK }
B[\|\&\^\~\>\<]              { /* Bitwise operations. */ TOKEN_OK }
C(\>\=|\<\=|[\>\<\=]|!)      { /* Comparisons. */ TOKEN_OK }
H[0-9A-F]+                   { /* Hexadecimal constants. */ TOKEN_OK }
"["                          { /* Lambda start. */ TOKEN_OK }
"]"                          { /* Lambda end. */ TOKEN_OK }
[\!\?]                       { /* First class functions. execution, conditional execution */ TOKEN_OK }
[a-z]+                       { /* Variables. */ TOKEN_OK }
[\:\;]                       { /* Read/write a variable. */ TOKEN_OK }
F[\#\%\~\$]                  { /* while, for, do..while, if..else */ TOKEN_OK }
\{                           {
    /* Purposefully allows unterminated comments. */
    int c;
    while ((c = input()) != '}' && c != EOF)
        ;
}
I[\,\.\:\;]                  { /* Input and output, numeric and bytewise. */ TOKEN_OK }
M[\<\>\:\;\.\,]              { /* Memory management: allocate, free, read, write. */ TOKEN_OK }
\"(\\.|[^"\\])*\"            { /* Push a null-terminated string. */ TOKEN_OK }
[\ \t\r\n\f]                 { /* Ignore whitespace. */ }
.                            { fprintf(stderr, "Unknown instruction: %c", yytext[0]); exit(1); }

%%

#define TETRADIC_FETCH \
    int64_t a = vector_back(stack, 3); \
    int64_t b = vector_back(stack, 2); \
    int64_t c = vector_back(stack, 1); \
    int64_t d = vector_back(stack, 0); \
    vector_pop_back(stack); vector_pop_back(stack); \
    vector_pop_back(stack); vector_pop_back(stack);

#define TRIADIC_FETCH \
    int64_t a = vector_back(stack, 2); \
    int64_t b = vector_back(stack, 1); \
    int64_t c = vector_back(stack, 0); \
    vector_pop_back(stack); vector_pop_back(stack); vector_pop_back(stack);

#define DYADIC_FETCH \
    int64_t a = vector_back(stack, 1); \
    int64_t b = vector_back(stack, 0); \
    vector_pop_back(stack); vector_pop_back(stack);

#define MONADIC_FETCH \
    int64_t a = vector_back(stack, 0); \
    vector_pop_back(stack);

static void call(unsigned int a) {
    struct env * new_env = malloc(sizeof(struct env));
    new_env->parent = NULL;
    new_env->data = hashmap_create();
    e = new_env;
    vector_push_back(callstack, tp);
    tp = a;
}

int main(int argc, char * argv[]) {
    if(argc == 2) {
        yyin = fopen(argv[1], "r");
        assert(yyin);
    }
    yylex();
    e = malloc(sizeof(struct env));
    e->parent = NULL;
    e->data = hashmap_create();
    while(tp < vector_size(tokens)) {
        char * token = tokens[tp++];
        if(isdigit(*token)) {
            int64_t l = strtoll(token, NULL, 10);
            vector_push_back(stack, l);
        } else if(*token == 'H' && isdigit(token[1])) {
            int64_t l = strtoll(token + 1, NULL, 16);
            vector_push_back(stack, l);
        } else if(*token == '\'') {
            vector_push_back(stack, token[1]);
        } else if(*token == '+') {
            DYADIC_FETCH; vector_push_back(stack, a + b);
        } else if(*token == '-') {
            DYADIC_FETCH; vector_push_back(stack, a - b);
        } else if(*token == 'I') {
            token++;
            if(*token == '.') {
                int64_t l = getchar();
                vector_push_back(stack, l);
            } else if(*token == ',') {
                MONADIC_FETCH;
                putchar(a);
            } else if(*token == ':') {
                int64_t l = 0;
                scanf("%" SCNd64, &l);
                vector_push_back(stack, l);
            } else if(*token == ';') {
                MONADIC_FETCH;
                printf("%" PRId64, a);
            }
        } else if(*token == '"') {
            token += strlen(token) - 2;
            vector_push_back(stack, 0);
            while(*token != '\"') {
                if(token[-1] == '\\') {
                    if(token[0] == 'n')
                        vector_push_back(stack, '\n');
                    else
                        vector_push_back(stack, token[0]);
                    token -= 2;
                } else if(*token == '\"')
                    break;
                else {
                    vector_push_back(stack, *token);
                    token--;
                }
            }
        } else if(*token == 'M') {
            token++;
            if(*token == '<') {
                MONADIC_FETCH;
                void * ptr = malloc(a);
                vector_push_back(stack, (int64_t) ptr);
            } else if(*token == '>') {
                MONADIC_FETCH;
                free((void *) a);
            } else if(*token == '.') {
                DYADIC_FETCH;
                uint8_t * data = (uint8_t *) a;
                vector_push_back(stack, data[b]);
            } else if(*token == ',') {
                TRIADIC_FETCH;
                uint8_t * data = (uint8_t *) a;
                data[b] = c;
            } else if(*token == ':') {
                DYADIC_FETCH;
                int64_t * data = (int64_t *) a;
                vector_push_back(stack, data[b]);
            } else if(*token == ';') {
                TRIADIC_FETCH;
                int64_t * data = (int64_t *) a;
                data[b] = c;
            }
        } else if(*token == 'B') {
            token++;
            if(*token == '|') {
                DYADIC_FETCH; vector_push_back(stack, a | b);
            } else if(*token == '&') {
                DYADIC_FETCH; vector_push_back(stack, a & b);
            } else if(*token == '^') {
                DYADIC_FETCH; vector_push_back(stack, a ^ b);
            } else if(*token == '~') {
                MONADIC_FETCH; vector_push_back(stack, ~a);
            } else if(*token == '>') {
                DYADIC_FETCH; vector_push_back(stack, a >> b);
            } else if(*token == '<') {
                DYADIC_FETCH; vector_push_back(stack, a << b);
            }
        } else if(*token == 'C') {
            token++;
            if(*token == '=') {
                DYADIC_FETCH; vector_push_back(stack, a == b);
            } else if(*token == '!') {
                DYADIC_FETCH; vector_push_back(stack, a != b);
            } else if(*token == '<' && token[1] == '=') {
                DYADIC_FETCH; vector_push_back(stack, a <= b);
            } else if(*token == '>' && token[1] == '=') {
                DYADIC_FETCH; vector_push_back(stack, a >= b);
            } else if(*token == '<') {
                DYADIC_FETCH; vector_push_back(stack, a < b);
            } else if(*token == '>') {
                DYADIC_FETCH; vector_push_back(stack, a > b);
            }
        } else if(*token == '$') {
            vector_pop_back(stack);
        } else if(*token == '@') {
            MONADIC_FETCH;
            vector_push_back(stack, vector_back(stack, a));
        } else if(*token == '%') {
            MONADIC_FETCH;
            vector_push_back(stack, a);
            vector_push_back(stack, a);
        } else if(*token == '^') {
            DYADIC_FETCH;
            vector_push_back(stack, b);
            vector_push_back(stack, a);
        } else if(*token == '`') {
            TRIADIC_FETCH;
            vector_push_back(stack, c);
            vector_push_back(stack, b);
            vector_push_back(stack, a);
        } else if(*token == '[') {
            // Find matching ].
            vector_push_back(stack, tp);
            int64_t q = 1, i;
            for(i = tp; i < vector_size(tokens); i++) {
                if(tokens[i][0] == ']')
                    q--;
                else if(tokens[i][0] == '[')
                    q++;
                if(!q)
                    break;
            }
            tp = i + 1;
        } else if(*token == ']') {
            struct env * parent_env = e->parent;
            hashmap_free(e->data);
            free(e);
            e = parent_env;
            tp = vector_back(callstack, 0);
            vector_pop_back(callstack);
        } else if(*token == '!') {
            MONADIC_FETCH;
            call(a);
        } else if(*token == '?') {
            DYADIC_FETCH;
            if(a) {
                call(b);
            }
        } else if(*token >= 'a' && *token <= 'z') {
            vector_push_back(stack, (int64_t) token);
        } else if(*token == ';') {
            DYADIC_FETCH;
            char * name = (char *) b;
            int64_t value = a;
            hashmap_set(e->data, name, strlen(name), value);
        } else if(*token == ':') {
            MONADIC_FETCH;
            struct env * ce = e;
            char * name = (char *) a;
            int64_t value;
            while(!hashmap_get(ce->data, name, strlen(name), &value)) {
                ce = ce->parent;
                if(ce == NULL) {
                    fprintf(stderr, "Variable not bound: %s\n", name);
                    exit(1);
                }
            }
            vector_push_back(stack, value);
        } else if(*token == 'F') {
            token++;
            if(*token == '#') {
                DYADIC_FETCH;
                while(true) {
                    call(a);
                    int64_t det = vector_back(stack, 0);
                    if(!det)
                        break;
                    call(b);
                }
            } else if(*token == '%') {
                TETRADIC_FETCH;
                int64_t start = a;
                int64_t end = b;
                int64_t step = c;
                int64_t fn = d;
                if(start < end) {
                    for(int64_t i = start; i < end; i += step) {
                        vector_push_back(stack, i);
                        call(fn);
                    }
                } else if(start > end) {
                    for(int64_t i = start; i >= end; i -= step) {
                        vector_push_back(stack, i);
                        call(fn);
                    }
                }
            } else if(*token == '~') {
                DYADIC_FETCH;
                while(true) {
                    call(b);
                    call(a);
                    int64_t det = vector_back(stack, 0);
                    if(!det)
                        break;
                }
            } else if(*token == '$') {
                TRIADIC_FETCH;
                if(a) {
                    call(b);
                } else {
                    call(c);
                }
            }
        } else {
            fprintf(stderr, "Internal error: Unknown instruction: %s\n", token);
            exit(1);
        }
    }
}

