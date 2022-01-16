
%{

/* ----------------------------------------------------------------
   DIRAC - Delightfully Intricate Reasonably Amazing Calculator
   Copyright (C) by Kamila Szewczyk, 2022. Licensed under the terms
   of AGPLv3 license.
*/

// lex will allocate ~30K by default which is unacceptable on low memory systems.
#undef YY_BUF_SIZE
#define YY_BUF_SIZE 512

#include <stdio.h>
#include <assert.h>
#include <stdlib.h>
#include <ctype.h>
#include "config.h"
#include "map.h"
#include "vector.h"

#define TOKEN_OK vector_push_back(tokens, sdup(yytext));

static unsigned int err_underflow() {
    fprintf(stderr, "Error: Stack underflow.");
    abort(); return 0; /* unreachable */
}

/* strdup for platforms that don't have it. */
static char * sdup(char * s) {
    int len = strlen(s);
    char * np = malloc(len + 1);
    memcpy(np, s, len);
    np[len] = 0;
    return np;
}

static vector(char *) tokens;
static vector(unsigned int) callstack;
static vector(num) stack;
static struct env * e;

static unsigned int tp;

struct env {
    struct env *parent;
    hashmap *data;
};

%}

%option noyywrap never-interactive nounistd

%%

[0-9]+                       { /* Push a number literal. */ TOKEN_OK }
'(.|\n)                      { /* Push a character literal. */ TOKEN_OK }
[\$\@\%\+\-\*\/\^\`\#]       { /* Stack operations. */ TOKEN_OK }
B[\|\&\^\~\>\<]              { /* Bitwise operations. */ TOKEN_OK }
C(\>\=|\<\=|[\>\<\=]|!)      { /* Comparisons. */ TOKEN_OK }
H[0-9A-F]+                   { /* Hexadecimal constants. */ TOKEN_OK }
D(,)                         { /* Debugging. */ TOKEN_OK }
"["                          { /* Lambda start. */ TOKEN_OK }
"]"                          { /* Lambda end. */ TOKEN_OK }
[\!\?]                       { /* First class functions. execution, conditional execution */ TOKEN_OK }
[a-z]+                       { /* Variables. */ TOKEN_OK }
[\:\;]                       { /* Read/write a variable */ TOKEN_OK }
\~[\:\;]                     { /* Outer scope access. */ TOKEN_OK }
F[\#\%\~\$\`]                { /* while, for, do..while, if..else */ TOKEN_OK }
\{                           {
    /* Purposefully allows unterminated comments. */
    int c;
    while ((c = input()) != '}' && c != EOF)
        ;
}
I[\<\>\,\.\:\;]              { /* Input and output, numeric and bytewise. */ TOKEN_OK }
M[\<\>\:\;\.\,]              { /* Memory management: allocate, free, read, write. */ TOKEN_OK }
\"(\\.|[^"\\])*\"            { /* Push a null-terminated string. */ TOKEN_OK }
[\ \t\r\n\f]                 { /* Ignore whitespace. */ }
.                            { fprintf(stderr, "Unknown instruction: %c", yytext[0]); exit(1); }

%%

#define TETRADIC_FETCH \
    num a = vector_back(stack, 3); \
    num b = vector_back(stack, 2); \
    num c = vector_back(stack, 1); \
    num d = vector_back(stack, 0); \
    vector_pop_back(stack); vector_pop_back(stack); \
    vector_pop_back(stack); vector_pop_back(stack);

#define TRIADIC_FETCH \
    num a = vector_back(stack, 2); \
    num b = vector_back(stack, 1); \
    num c = vector_back(stack, 0); \
    vector_pop_back(stack); vector_pop_back(stack); vector_pop_back(stack);

#define DYADIC_FETCH \
    num a = vector_back(stack, 1); \
    num b = vector_back(stack, 0); \
    vector_pop_back(stack); vector_pop_back(stack);

#define MONADIC_FETCH \
    num a = vector_back(stack, 0); \
    vector_pop_back(stack);

static void step();

static void call(unsigned int a) {
    struct env * new_env = malloc(sizeof(struct env));
    new_env->parent = e;
    new_env->data = hashmap_create();
    e = new_env;
    vector_push_back(callstack, tp);
    tp = a;
    while(tp < vector_size(tokens) && tokens[tp][0] != ']')
        step();
    if(tokens[tp][0] == ']')
        step();
}

num to_num(char * s, int base) {
    num n = 0;
    while(*s) {
        n *= base;
        if(isalpha(*s))
            n += *s - (isupper(*s) ? 'A' : 'a') + 10;
        else if(isdigit(*s))
            n += *s - '0';
        else {
            fprintf(stderr, "Unsupported character in a numeric constant: %c\n", *s);
            exit(1);
        }
        s++;
    }
    return n;
}

static void step() {
    char * token = tokens[tp++];
    if(isdigit(*token)) {
        num l = to_num(token, 10);
        vector_push_back(stack, l);
    } else if(*token == 'H' && isdigit(token[1])) {
        num l = to_num(token + 1, 16);
        vector_push_back(stack, l);
    } else if(*token == '\'') {
        vector_push_back(stack, token[1]);
    } else if(*token == '+') {
        DYADIC_FETCH; vector_push_back(stack, a + b);
    } else if(*token == '-') {
        DYADIC_FETCH; vector_push_back(stack, a - b);
    } else if(*token == '*') {
        DYADIC_FETCH; vector_push_back(stack, a * b);
    } else if(*token == '/') {
        DYADIC_FETCH; vector_push_back(stack, a / b);
    } else if(*token == 'I') {
        token++;
        if(*token == '.') {
            num l = getchar();
            vector_push_back(stack, l);
        } else if(*token == ',') {
            MONADIC_FETCH;
            putchar(a);
        } else if(*token == ':') {
            num l = 0;
            scanf(WORD_FORMAT, &l);
            vector_push_back(stack, l);
        } else if(*token == ';') {
            MONADIC_FETCH;
            printf(WORD_FORMAT, a);
        } else if(*token == '<') {
            num l = 0;
            scanf(HEX_WORD_FORMAT, &l);
            vector_push_back(stack, l);
        } else if(*token == '>') {
            MONADIC_FETCH;
            printf(HEX_WORD_FORMAT, a);
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
            void * ptr;
            MONADIC_FETCH;
            ptr = malloc(a);
            vector_push_back(stack, (num) ptr);
        } else if(*token == '>') {
            MONADIC_FETCH;
            free((void *) a);
        } else if(*token == '.') {
            uint8_t * data;
            DYADIC_FETCH;
            data = (uint8_t *) a;
            vector_push_back(stack, data[b]);
        } else if(*token == ',') {
            uint8_t * data;
            TRIADIC_FETCH;
            data = (uint8_t *) a;
            data[b] = c;
        } else if(*token == ':') {
            num * data;
            DYADIC_FETCH;
            data = (num *) a;
            vector_push_back(stack, data[b]);
        } else if(*token == ';') {
            num * data;
            TRIADIC_FETCH;
            data = (num *) a;
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
            MONADIC_FETCH; vector_push_back(stack, ~(unum)a);
        } else if(*token == '>') {
            DYADIC_FETCH; vector_push_back(stack, (unum)a >> (unum)b);
        } else if(*token == '<') {
            DYADIC_FETCH; vector_push_back(stack, (unum)a << (unum)b);
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
        DYADIC_FETCH; vector_push_back(stack, a % b);
    } else if(*token == '#') {
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
        num q = 1; size_t i;
        vector_push_back(stack, tp);
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
        vector_push_back(stack, (num) token);
    } else if(*token == ';') {
        char * name; num value;
        DYADIC_FETCH;
        name = (char *) b;
        value = a;
        hashmap_set(e->data, name, strlen(name), value);
    } else if(*token == ':') {
        struct env * ce; char * name; uintptr_t value;
        MONADIC_FETCH;
        ce = e;
        name = (char *) a;
        while(!hashmap_get(ce->data, name, strlen(name), &value)) {
            ce = ce->parent;
            if(ce == NULL) {
                fprintf(stderr, "Variable not bound: %s\n", name);
                exit(1);
            }
        }
        vector_push_back(stack, value);
    } else if(*token == '~') {
        token++;
        if(*token == ';') {
            char * name; uintptr_t value, ign; struct env * last_env = NULL, * ce;
            DYADIC_FETCH;
            name = (char *) b;
            value = a;
            ce = e;
            while(ce != NULL) {
                if(hashmap_get(ce->data, name, strlen(name), &ign))
                    last_env = ce;
                ce = ce->parent;
            }
            if(last_env == NULL) {
                fprintf(stderr, "Variable not bound: %s\n", name);
                exit(1);
            }
            hashmap_set(last_env->data, name, strlen(name), value);
        } else if(*token == ':') {
            struct env * ce, * last_env = NULL; char * name; uintptr_t value, ign;
            MONADIC_FETCH;
            ce = e;
            name = (char *) a;
            while(ce != NULL) {
                if(hashmap_get(ce->data, name, strlen(name), &ign))
                    last_env = ce;
                ce = ce->parent;
            }
            if(last_env == NULL) {
                fprintf(stderr, "Variable not bound: %s\n", name);
                exit(1);
            }
            hashmap_get(last_env->data, name, strlen(name), &value);
            vector_push_back(stack, value);
        }
    } else if(*token == 'D') {
        token++;
        if(*token == ',') {
            size_t i = 0;
            printf("~~ Debugging ~~\n");
            printf("Stack (from the bottom):\n");
            for(; i < vector_size(stack); i++)
                printf(WORD_FORMAT ": " WORD_FORMAT "\n", i, stack[i]);
            printf("~~~~\n");
        }
    } else if(*token == 'F') {
        token++;
        if(*token == '#') {
            DYADIC_FETCH;
            while(1) {
                num det;
                call(a);
                det = vector_back(stack, 0);
                vector_pop_back(stack);
                if(!det)
                    break;
                call(b);
            }
        } else if(*token == '%') {
            num start, end, step, fn, i;
            TETRADIC_FETCH;
            start = a;
            end = b;
            step = c;
            fn = d;
            if(start < end) {
                for(i = start; i < end; i += step) {
                    vector_push_back(stack, i);
                    call(fn);
                }
            } else if(start > end) {
                for(i = start; i >= end; i -= step) {
                    vector_push_back(stack, i);
                    call(fn);
                }
            }
        } else if(*token == '~') {
            DYADIC_FETCH;
            while(1) {
                num det;
                call(b);
                call(a);
                det = vector_back(stack, 0);
                vector_pop_back(stack);
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
        } else if(*token == '`') {
            exit(0);
        }
    } else {
        fprintf(stderr, "Internal error: Unknown instruction: %s\n", token);
        exit(1);
    }
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
        step();
    }
    return 0;
}

