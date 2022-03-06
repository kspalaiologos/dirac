
#ifndef NO_STDINT
    #include <stdint.h>

    #if UINTPTR_MAX == 0xFFFF
        #define num int32_t
        #define unum uint32_t
        #define DIRAC_16
        #define WORD_FORMAT "%ld"
        #define HEX_WORD_FORMAT "%lX"
    #elif UINTPTR_MAX == 0xFFFFFFFF
        #define num int32_t
        #define unum uint32_t
        #define DIRAC_32
        #define WORD_FORMAT "%d"
        #define HEX_WORD_FORMAT "%X"
    #elif UINTPTR_MAX == 0xFFFFFFFFFFFFFFFFu
        #define num int64_t
        #define unum uint64_t
        #define DIRAC_64
        #define WORD_FORMAT "%lld"
        #define HEX_WORD_FORMAT "%llX"
    #else
        #error Unsupported pointer size or pointer size not defined. Is <stdint.h> present?
    #endif
#else
    #define uint32_t unsigned long
    #define int32_t long
    #define uint16_t unsigned int
    #define int16_t int
    #define uint8_t unsigned char
    #define int8_t char

    #ifdef DIRAC16
        #define uintptr_t unsigned int
        #define num long
        #define unum unsigned long
        #define WORD_FORMAT "%ld"
        #define HEX_WORD_FORMAT "%lX"
    #else
        #ifdef DIRAC32
            #define uintptr_t unsigned long
            #define num long
            #define unum unsigned long
            #define WORD_FORMAT "%ld"
            #define HEX_WORD_FORMAT "%lX"
        #else
            #error "Neither DIRAC16 nor DIRAC32 defined. 64-bit builds on machines without <stdint.h> are not supported."
        #endif
    #endif
#endif
