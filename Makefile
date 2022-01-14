
.PHONY: clean

dirac: lex.yy.o map.o
	gcc $^ -o $@

lex.yy.c: dirac.l
	lex dirac.l

map.o: map.c
	cc $(CFLAGS) -c $^ -o $@

lex.yy.o: lex.yy.c
	cc $(CFLAGS) -c $^ -o $@

clean:
	rm *.o lex.yy.c dirac
